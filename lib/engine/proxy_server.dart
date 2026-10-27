import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'config.dart';
import 'doh.dart';
import 'strategies.dart';
import 'tls.dart';

typedef LogFn = void Function(String level, String msg);

class EngineStats {
  int up = 0;
  int down = 0;
  int active = 0;
  int total = 0;
  int failed = 0;
  final Map<String, int> perHost = {};
}

/// 127.0.0.1 üzerinde dinleyen HTTP(S) vekil sunucusu.
///
/// - Yalnızca [EngineConfig.domains] ile eşleşen CONNECT istekleri DoH ile
///   çözülür ve TLS başlangıç mesajı bölünerek gönderilir.
/// - Diğer her şey olduğu gibi (dokunulmadan) tünellenir.
/// - `/proxy.pac` adresinden, yalnızca seçili alan adlarını bu vekile yönlendiren
///   otomatik yapılandırma dosyasını sunar.
class ProxyServer {
  /// Deney için: alma tamponu boyutu (bayt); 0 = dokunma.
  static int rcvBuf = 0;

  ProxyServer(this.cfg, this.log) {
    if (cfg.useDoh || cfg.systemMode) doh = DohResolver(cfg.dohProvider);
  }

  final EngineConfig cfg;
  final LogFn log;
  final EngineStats stats = EngineStats();
  DohResolver? doh;
  ServerSocket? _server;
  ServerSocket? _transparent;
  final Set<_Conn> _conns = {};

  /// 127.0.0.1:443 üzerinde şeffaf dinleyici: istemci TLS başlangıcını gönderir,
  /// SNI'den hedef okunur, gerçek sunucuya bölünmüş olarak iletilir.
  Future<void> startTransparent() async {
    _transparent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 443);
    _transparent!.listen((c) => _onClient(c, transparent: true), onError: (_) {});
  }

  int get port => _server!.port;

  Future<int> start() async {
    try {
      _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, cfg.port);
    } on SocketException {
      if (cfg.port == 0) rethrow;
      log('warn', '${cfg.port} portu dolu, boş bir port seçiliyor');
      _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    }
    _server!.listen(_onClient, onError: (_) {});
    return _server!.port;
  }

  Future<void> stop() async {
    await _server?.close();
    await _transparent?.close();
    for (final c in _conns.toList()) {
      c.close();
    }
    doh?.close();
  }

  void _onClient(Socket client, {bool transparent = false}) {
    client.setOption(SocketOption.tcpNoDelay, true);
    final conn = _Conn(this, client, transparent: transparent);
    _conns.add(conn);
    stats.active++;
    stats.total++;
    conn.run();
  }

  String pac() {
    final list = cfg.domains.map((d) => '"$d"').join(',');
    final p = port;
    return '''function FindProxyForURL(url, host) {
  host = host.toLowerCase();
  var d = [$list];
  for (var i = 0; i < d.length; i++) {
    if (host === d[i] || (host.length > d[i].length && host.substr(host.length - d[i].length - 1) === "." + d[i])) {
      return "PROXY 127.0.0.1:$p; DIRECT";
    }
  }
  return "DIRECT";
}
''';
  }
}

class _Conn {
  _Conn(this.s, this.c, {this.transparent = false});

  final ProxyServer s;
  final Socket c;
  final bool transparent;
  Socket? up;
  late final StreamSubscription<Uint8List> csub;
  StreamSubscription<Uint8List>? usub;

  final BytesBuilder buf = BytesBuilder();
  int phase = 0; // 0 istek başlığı · 1 ClientHello bekleniyor · 2 tünel
  String host = '';
  bool matched = false;
  bool gotReply = false;
  bool helloSent = false;
  bool cEnded = false;
  bool uEnded = false;
  bool closed = false;
  Timer? helloTimer;
  Timer? replyTimer;

  void run() {
    if (transparent) {
      phase = 1; // doğrudan ClientHello bekle; hedef SNI'den öğrenilir
      matched = true;
      s.log('debug', 'şeffaf bağlantı kabul edildi');
      helloTimer = Timer(const Duration(seconds: 5), () {
        s.log('debug', 'şeffaf bağlantı: 5 sn içinde ClientHello gelmedi (${buf.length} bayt), kapatılıyor');
        close();
      });
    }
    csub = c.listen(
      _onClientData,
      onError: (_) => close(),
      onDone: () {
        cEnded = true;
        _halfClose();
      },
      cancelOnError: true,
    );
  }

  // ---------------------------------------------------------------- istemci

  void _onClientData(Uint8List d) {
    switch (phase) {
      case 0:
        buf.add(d);
        _parseRequest();
      case 1:
        buf.add(d);
        if (isHelloComplete(buf.toBytes())) _sendHello();
      case 2:
        s.stats.up += d.length;
        _pipe(csub, up, d);
      default:
        buf.add(d); // geçiş sırasında gelen veri; tünel kurulunca iletilir
    }
  }

  void _pipe(StreamSubscription<Uint8List> from, Socket? to, Uint8List d) {
    if (to == null) return;
    try {
      to.add(d);
      from.pause();
      to.flush().then((_) => from.resume(), onError: (_) => close());
    } catch (_) {
      close();
    }
  }

  Future<void> _parseRequest() async {
    final bytes = buf.toBytes();
    final end = _indexOfCrlf2(bytes);
    if (end < 0) {
      if (bytes.length > 16384) close();
      return;
    }
    phase = -1; // başka veri işlenmesin
    csub.pause();
    final headText = latin1.decode(Uint8List.sublistView(bytes, 0, end));
    buf
      ..clear()
      ..add(Uint8List.sublistView(bytes, end + 4));
    final lines = headText.split('\r\n');
    final parts = lines.first.split(' ');
    if (parts.length < 3) return close();
    final method = parts[0].toUpperCase();
    final target = parts[1];

    if (method == 'GET' && target.startsWith('/proxy.pac')) {
      return _reply(200, s.pac(), 'application/x-ns-proxy-autoconfig');
    }
    if (method == 'GET' && target.startsWith('/ping')) {
      return _reply(200, 'gindpi', 'text/plain');
    }

    if (method == 'CONNECT') {
      final hp = _splitHostPort(target, 443);
      host = hp.$1;
      matched = s.cfg.matches(host);
      final sock = await _dial(host, hp.$2);
      if (closed) {
        sock?.destroy();
        return;
      }
      if (sock == null) {
        s.stats.failed++;
        s.log('warn', '$host:${hp.$2} adresine bağlanılamadı');
        return _reply(502, 'Bad Gateway', 'text/plain');
      }
      up = sock;
      _listenUpstream();
      c.add(latin1.encode('HTTP/1.1 200 Connection Established\r\n\r\n'));
      if (matched) {
        s.stats.perHost.update(host, (v) => v + 1, ifAbsent: () => 1);
        s.log('debug', 'tünel: $host');
      }
      if (matched && hp.$2 == 443) {
        phase = 1;
        helloTimer = Timer(const Duration(seconds: 2), _sendHello);
        if (buf.length > 0 && isHelloComplete(buf.toBytes())) {
          _sendHello();
          return;
        }
      } else {
        phase = 2;
        if (buf.length > 0) {
          final pending = buf.takeBytes();
          s.stats.up += pending.length;
          _pipe(csub, up, pending);
        }
      }
      csub.resume();
      return;
    }

    // Düz HTTP isteği (http://...). Yalnızca ilk isteğin yönlendirilmesi.
    final uri = Uri.tryParse(target);
    if (uri == null || !uri.hasAuthority) {
      return _reply(400, 'Bad Request', 'text/plain');
    }
    host = uri.host;
    matched = s.cfg.matches(host);
    final sock = await _dial(host, uri.hasPort ? uri.port : 80);
    if (closed) {
      sock?.destroy();
      return;
    }
    if (sock == null) return _reply(502, 'Bad Gateway', 'text/plain');
    up = sock;
    _listenUpstream();
    final path = uri.hasQuery ? '${uri.path.isEmpty ? '/' : uri.path}?${uri.query}' : (uri.path.isEmpty ? '/' : uri.path);
    final out = StringBuffer('$method $path ${parts[2]}\r\n');
    for (final l in lines.skip(1)) {
      if (l.toLowerCase().startsWith('proxy-connection')) continue;
      out.write('$l\r\n');
    }
    out.write('\r\n');
    sock.add(latin1.encode(out.toString()));
    if (buf.length > 0) sock.add(buf.takeBytes());
    phase = 2;
    csub.resume();
  }

  Future<void> _sendHello() async {
    if (phase != 1) return;
    phase = -1;
    helloTimer?.cancel();
    csub.pause();
    final all = buf.takeBytes();
    try {
      if (all.isNotEmpty) {
        // İlk TLS kaydı ile (varsa) ardından gelen baytları ayır.
        var recEnd = all.length;
        if (all.length >= 5 && all[0] == 0x16) {
          recEnd = (5 + ((all[3] << 8) | all[4])).clamp(5, all.length);
        }
        final rec = Uint8List.sublistView(all, 0, recEnd);
        final tail = Uint8List.sublistView(all, recEnd);
        final info = parseClientHello(rec);
        if (transparent) {
          final head = all.take(12).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
          s.log('debug',
              'şeffaf istek: ${all.length} bayt, kayıt ${rec.length}, SNI=${info?.sni}, ilk baytlar: $head');
        }
        if (up == null) {
          // Şeffaf mod: hedef ancak şimdi, SNI'den belli oluyor.
          if (info == null) return close();
          host = info.sni;
          final sock = await _dial(host, 443);
          if (closed) {
            sock?.destroy();
            return;
          }
          if (sock == null) {
            s.stats.failed++;
            s.log('warn', '$host adresine bağlanılamadı');
            return close();
          }
          up = sock;
          _listenUpstream();
          s.stats.perHost.update(host, (v) => v + 1, ifAbsent: () => 1);
          s.log('debug', 'şeffaf tünel: $host');
        }
        final pieces = planPieces(s.cfg.strategy, rec, info, s.cfg.splitDelayMs);
        for (var i = 0; i < pieces.length; i++) {
          final p = pieces[i];
          up!.add(p.data);
          if (i == pieces.length - 1 && tail.isNotEmpty) up!.add(tail);
          await up!.flush();
          if (p.delayMs > 0 && i < pieces.length - 1) {
            await Future<void>.delayed(Duration(milliseconds: p.delayMs));
          }
        }
        s.stats.up += all.length;
      }
      helloSent = true;
      replyTimer = Timer(const Duration(seconds: 7), () {
        if (!gotReply && !closed) {
          s.stats.failed++;
          s.log('warn',
              '$host yanıt vermedi (7 sn). Operatör engeli olabilir; Ayarlar\'dan başka yöntem deneyin.');
        }
      });
      phase = 2;
      if (buf.length > 0) _pipe(csub, up, buf.takeBytes());
      csub.resume();
    } catch (_) {
      close();
    }
  }

  void _reply(int code, String body, String type) {
    final b = utf8.encode(body);
    c.add(latin1.encode('HTTP/1.1 $code OK\r\nContent-Type: $type\r\n'
        'Content-Length: ${b.length}\r\nConnection: close\r\n\r\n'));
    c.add(b);
    c.flush().whenComplete(close);
  }

  // ---------------------------------------------------------------- sunucu

  void _listenUpstream() {
    usub = up!.listen(
      (d) {
        if (!gotReply && transparent) s.log('debug', '$host ilk yanıt: ${d.length} bayt');
        gotReply = true;
        s.stats.down += d.length;
        try {
          c.add(d);
          usub!.pause();
          c.flush().then((_) => usub?.resume(), onError: (_) => close());
        } catch (_) {
          close();
        }
      },
      onError: (_) {
        if (helloSent && !gotReply) {
          s.stats.failed++;
          s.log('warn', '$host bağlantısı el sıkışma sırasında sıfırlandı (engel olabilir)');
        }
        close();
      },
      onDone: () {
        uEnded = true;
        if (helloSent && !gotReply) {
          s.stats.failed++;
          s.log('warn', '$host bağlantısı yanıtsız kapatıldı (engel olabilir)');
        }
        _halfClose();
      },
      cancelOnError: true,
    );
  }

  /// Bir taraf bittiğinde diğerinin yazma ucunu kapatır; ikisi de bitince yıkar.
  void _halfClose() {
    if (cEnded && uEnded) return close();
    try {
      if (cEnded) up?.close();
      if (uEnded) c.close();
    } catch (_) {
      close();
    }
  }

  Future<Socket?> _dial(String host, int port) async {
    List<InternetAddress> addrs = const [];
    final literal = InternetAddress.tryParse(host);
    if (literal != null) {
      addrs = [literal];
    } else {
      if (matched && s.doh != null) {
        addrs = await s.doh!.resolve(host);
        if (addrs.isEmpty) s.log('warn', 'DoH yanıt vermedi, sistem DNS\'i deneniyor: $host');
      }
      if (addrs.isEmpty) {
        try {
          addrs = await InternetAddress.lookup(host, type: InternetAddressType.IPv4);
        } catch (_) {
          try {
            addrs = await InternetAddress.lookup(host);
          } catch (_) {}
        }
      }
    }
    for (final a in addrs.take(4)) {
      try {
        final sock = await Socket.connect(a, port, timeout: const Duration(seconds: 5));
        sock.setOption(SocketOption.tcpNoDelay, true);
        if (matched && ProxyServer.rcvBuf > 0) {
          // Küçük alma penceresi: sunucu el sıkışma yanıtını (TLS 1.2'de açık sertifika)
          // küçük TCP parçalarına bölmek zorunda kalır; operatör eşleştiremez.
          try {
            sock.setRawOption(RawSocketOption.fromInt(0xffff, 0x1002, ProxyServer.rcvBuf)); // SOL_SOCKET, SO_RCVBUF
          } catch (_) {}
        }
        return sock;
      } catch (_) {}
    }
    return null;
  }

  void close() {
    if (closed) return;
    closed = true;
    helloTimer?.cancel();
    replyTimer?.cancel();
    try {
      csub.cancel();
    } catch (_) {}
    usub?.cancel();
    c.destroy();
    up?.destroy();
    s.stats.active--;
    s._conns.remove(this);
  }
}

(String, int) _splitHostPort(String t, int defPort) {
  if (t.startsWith('[')) {
    final i = t.indexOf(']');
    final h = t.substring(1, i);
    final p = (i + 2 < t.length) ? int.tryParse(t.substring(i + 2)) : null;
    return (h, p ?? defPort);
  }
  final i = t.lastIndexOf(':');
  if (i < 0) return (t, defPort);
  return (t.substring(0, i), int.tryParse(t.substring(i + 1)) ?? defPort);
}

int _indexOfCrlf2(Uint8List b) {
  for (var i = 0; i + 3 < b.length; i++) {
    if (b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10) return i;
  }
  return -1;
}
