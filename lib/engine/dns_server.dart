import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'config.dart';
import 'doh.dart';
import 'proxy_server.dart' show LogFn;

/// 127.0.0.1:53 üzerinde çalışan küçük DNS sunucusu.
///
/// Windows'un alan adına özel DNS kuralı (NRPT) yalnızca seçili alan adlarının
/// sorgularını buraya yollar; diğer siteler etkilenmez.
///  - Yönlendirilen servisler (Discord vb.): [loopback] adresi döner. O adrese gelen
///    bağlantıyı SNI'ye bakıp gerçek sunucuya ileten dinleyici karşılar.
///  - Diğer eşleşenler (ör. ses sunucuları): DoH ile çözülen GERÇEK adres döner.
class DnsServer {
  DnsServer(this.cfg, this.doh, this.log, {this.loopback = '127.0.0.1'});

  final EngineConfig cfg;
  final DohResolver doh;
  final LogFn log;
  final String loopback;
  RawDatagramSocket? _sock;
  int queries = 0;

  Future<void> start() async {
    final s = await RawDatagramSocket.bind(InternetAddress(loopback), 53);
    _sock = s;
    s.listen((e) {
      if (e != RawSocketEvent.read) return;
      final d = s.receive();
      if (d != null) _handle(d, s);
    });
  }

  void stop() => _sock?.close();

  Future<void> _handle(Datagram d, RawDatagramSocket s) async {
    final q = _parse(d.data);
    if (q == null) return;
    queries++;
    List<InternetAddress> answers = const [];
    if (q.type == 1) {
      if (cfg.matches(q.name) && !cfg.dnsPassthrough(q.name)) {
        answers = [InternetAddress(loopback)];
      } else {
        answers = await doh.resolve(q.name);
      }
    }
    // AAAA ve diğer türlerde boş (NODATA) yanıt: IPv6 ile doğrudan kaçışı engeller.
    s.send(_reply(d.data, q, answers), d.address, d.port);
  }

  _Question? _parse(Uint8List b) {
    try {
      if (b.length < 17) return null;
      final qd = (b[4] << 8) | b[5];
      if (qd != 1 || (b[2] & 0x80) != 0) return null; // yalnızca tek soru, sorgu
      var p = 12;
      final labels = <String>[];
      while (b[p] != 0) {
        final n = b[p];
        if (n & 0xC0 != 0) return null;
        labels.add(String.fromCharCodes(b.sublist(p + 1, p + 1 + n)));
        p += n + 1;
      }
      p++;
      final type = (b[p] << 8) | b[p + 1];
      return _Question(labels.join('.').toLowerCase(), type, p + 4);
    } catch (_) {
      return null;
    }
  }

  Uint8List _reply(Uint8List req, _Question q, List<InternetAddress> ips) {
    final out = BytesBuilder();
    out.add([req[0], req[1], 0x81, 0x80, 0, 1, 0, ips.length, 0, 0, 0, 0]);
    out.add(req.sublist(12, q.end));
    for (final ip in ips) {
      out.add([0xC0, 0x0C, 0, 1, 0, 1, 0, 0, 0, 30, 0, 4]);
      out.add(ip.rawAddress);
    }
    return out.toBytes();
  }
}

class _Question {
  _Question(this.name, this.type, this.end);
  final String name;
  final int type;
  final int end;
}
