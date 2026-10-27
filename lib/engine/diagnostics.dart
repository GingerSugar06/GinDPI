import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'config.dart';
import 'doh.dart';
import 'proxy_server.dart';

typedef Emit = void Function(Map<String, dynamic> event);

const _probeUrl = 'https://discord.com/api/v9/gateway';

/// [strategy] ile geçici bir vekil açıp gerçek bir HTTPS isteği yapar.
/// Başarılıysa gecikmeyi (ms), değilse null döner.
Future<int?> probeStrategy(EngineConfig base, String strategy) async {
  final cfg = base.copyWith(port: 0, strategy: strategy, domains: const ['discord.com']);
  final srv = ProxyServer(cfg, (_, _) {});
  HttpClient? client;
  try {
    await srv.start();
    client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 7)
      ..findProxy = (_) => 'PROXY 127.0.0.1:${srv.port}';
    final sw = Stopwatch()..start();
    final req = await client.getUrl(Uri.parse(_probeUrl));
    final res = await req.close().timeout(const Duration(seconds: 8));
    final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 5));
    if (res.statusCode == 200 && body.contains('wss://')) return sw.elapsedMilliseconds;
    return null;
  } catch (_) {
    return null;
  } finally {
    client?.close(force: true);
    await srv.stop();
  }
}

/// Eski (yalnızca TLS 1.2 bilen) istemciler için: curl.exe'yi TLS 1.2'ye zorlayıp
/// geçici vekil üzerinden dener. Discord güncelleyicisi böyle bir istemcidir.
/// curl.exe yoksa (eski Windows) sınama atlanır ve geçer sayılır.
Future<bool> probeTls12(EngineConfig base, String strategy) async {
  final curl = '${Platform.environment['SystemRoot'] ?? 'C:/Windows'}/System32/curl.exe';
  if (!File(curl).existsSync()) return true;
  final cfg = base.copyWith(port: 0, strategy: strategy, domains: const ['discord.com']);
  final srv = ProxyServer(cfg, (_, _) {});
  try {
    await srv.start();
    final r = await Process.run(curl, [
      '-s', '-m', '8', '-x', 'http://127.0.0.1:${srv.port}',
      '--tlsv1.2', '--tls-max', '1.2', '-o', 'NUL', '-w', '%{http_code}',
      'https://updates.discord.com/distributions/app/manifests/latest?channel=stable&platform=win&arch=x64',
    ]);
    return (r.stdout as String).trim() == '200';
  } catch (_) {
    return false;
  } finally {
    await srv.stop();
  }
}

/// Tüm yöntemleri (ve "yöntemsiz" taban çizgisini) paralel dener.
Future<void> autoTune(EngineConfig cfg, Emit emit) async {
  final ids = ['none', ...strategies.map((s) => s.id)];
  final results = <String, int?>{};
  await Future.wait(ids.map((id) async {
    var ms = await probeStrategy(cfg, id);
    // Yalnızca TLS 1.3'te çalışan yöntem Discord güncelleyicisini açamaz: onu elenmiş say.
    if (ms != null && id != 'none' && !await probeTls12(cfg, id)) ms = null;
    results[id] = ms;
    emit({'ev': 'tune', 'id': id, 'ok': ms != null, 'ms': ms});
  }));
  String? best;
  int? bestMs;
  for (final s in strategies) {
    final ms = results[s.id];
    if (ms != null && (bestMs == null || ms < bestMs - 40)) {
      best = s.id;
      bestMs = ms;
    }
  }
  emit({
    'ev': 'tune_done',
    'best': best,
    'baselineOk': results['none'] != null,
  });
}

Future<void> runDiagnostics(EngineConfig cfg, bool engineRunning, int enginePort, Emit emit) async {
  void d(String id, String status, String title, String detail, [List<String> fix = const []]) =>
      emit({'ev': 'diag', 'id': id, 'status': status, 'title': title, 'detail': detail, 'fix': fix});

  // 1) İnternet
  d('internet', 'run', 'İnternet bağlantısı', 'Kontrol ediliyor…');
  final net = await _httpOk('https://1.1.1.1/cdn-cgi/trace');
  d(
    'internet',
    net ? 'ok' : 'fail',
    'İnternet bağlantısı',
    net ? 'Bağlısınız.' : 'İnternete ulaşılamıyor. Bağlantınızı, modemi veya VPN\'i kontrol edin.',
  );
  if (!net) return;

  // 2) DoH sağlayıcıları
  d('doh', 'run', 'Şifreli DNS (DoH)', 'Sağlayıcılar deneniyor…');
  final doh = DohResolver('auto');
  final pings = await Future.wait(
      DohResolver.endpoints.entries.map((e) async => MapEntry(e.key, await doh.ping(e.value.first))));
  final okNames = pings.where((p) => p.value != null).map((p) => p.key).toList();
  doh.close();
  if (okNames.length == pings.length) {
    d('doh', 'ok', 'Şifreli DNS (DoH)', 'Üç sağlayıcı da yanıt veriyor (${okNames.join(', ')}).');
  } else if (okNames.isNotEmpty) {
    d('doh', 'ok', 'Şifreli DNS (DoH)',
        'Yanıt veren: ${okNames.join(', ')}. Diğerleri engelli olabilir; motor otomatik olarak çalışanı kullanır.');
  } else {
    d('doh', 'fail', 'Şifreli DNS (DoH)',
        'Hiçbir DoH sağlayıcısına ulaşılamıyor. Güvenlik duvarı veya ağ bunları engelliyor olabilir.',
        ['dns_fix']);
  }

  // 3) Sistem DNS'i zehirlenmiş mi?
  d('dns', 'run', 'Sistem DNS\'i', 'discord.com çözülüyor…');
  final sys = await _lookup('discord.com');
  final dohRes = DohResolver('auto');
  final dohAddrs = await dohRes.resolve('discord.com');
  dohRes.close();
  if (sys.isEmpty) {
    d('dns', 'warn', 'Sistem DNS\'i',
        'Sistem DNS\'i discord.com\'u çözemedi. Motor DoH ile çözer, ancak ses sunucuları için DNS\'i şifreli yapmanız gerekebilir.',
        ['dns_fix']);
  } else if (_looksPoisoned(sys, dohAddrs)) {
    d('dns', 'warn', 'Sistem DNS\'i zehirlenmiş',
        'Sistem DNS\'i discord.com için sahte adres veriyor (${sys.first.address}). Motor bunu DoH ile aşar; '
        'ancak Discord\'un ses (UDP) sunucuları sistem DNS\'ini kullanır. Windows DNS\'ini şifreli yapmanız önerilir.',
        ['dns_fix']);
  } else {
    d('dns', 'ok', 'Sistem DNS\'i', 'DNS yanıtları doğru görünüyor.');
  }

  // 4) Taban çizgisi + seçili yöntem
  d('block', 'run', 'Engel testi', 'Yöntemsiz bağlantı deneniyor…');
  final baseline = await probeStrategy(cfg, 'none');
  if (baseline != null) {
    d('block', 'ok', 'Engel testi',
        'Şu an engel görünmüyor ($baseline ms). Operatör engeli kalkmış ya da eski bir DPI aracı hâlâ çalışıyor olabilir.');
  } else {
    d('block', 'warn', 'Engel testi', 'Discord doğrudan açılmıyor; motorun yöntemi gerekli.');
  }
  d('strategy', 'run', 'Seçili yöntem', '${_name(cfg.strategy)} deneniyor…');
  final ms = await probeStrategy(cfg, cfg.strategy);
  if (ms != null) {
    d('strategy', 'ok', 'Seçili yöntem', '${_name(cfg.strategy)} çalışıyor ($ms ms).');
  } else {
    d('strategy', 'fail', 'Seçili yöntem',
        '${_name(cfg.strategy)} bu ağda sonuç vermedi. Otomatik arama diğer yöntemleri deneyecek.',
        ['autotune']);
  }

  // 5) Çakışan araçlar
  final legacy = await _legacyTools();
  if (legacy.isNotEmpty) {
    d('legacy', 'warn', 'Çakışan DPI aracı',
        '${legacy.join(', ')} çalışıyor. Tüm trafiği değiştirdiği için ödeme sayfalarını bozabilir ve GinDPI testlerini yanıltır.',
        ['kill_legacy']);
  } else {
    d('legacy', 'ok', 'Çakışan DPI aracı', 'GoodbyeDPI / zapret gibi bir araç çalışmıyor.');
  }

  // 6) Sistem proxy ayarları
  final proxy = await _systemProxy();
  if (proxy != null) {
    d('sysproxy', 'warn', 'Mevcut proxy ayarı',
        'Windows\'ta zaten bir proxy/PAC tanımlı ($proxy). GinDPI\'nın otomatik yapılandırması onu ezmemek için kapatılır; '
        'Discord\'u GinDPI üzerinden başlatmanız yeterli.',
        ['use_launcher']);
  } else {
    d('sysproxy', 'ok', 'Mevcut proxy ayarı', 'Başka bir proxy ayarı yok.');
  }

  // 6b) Sistem modu
  if (cfg.systemMode) {
    d('sysmode', 'ok', 'Sistem modu', 'Açık: Discord güncelleyicisi dahil tüm uygulamaların Discord sorguları GinDPI üzerinden geçiyor.');
  } else {
    d('sysmode', 'warn', 'Sistem modu',
        'Kapalı. Discord masaüstü uygulamasının güncelleyicisi vekil ayarını dinlemez; "Update failed" ekranında '
            "kalıyorsa GinDPI'yı yönetici olarak açın ve Ayarlar'dan \"Tüm uygulamalar için çalış\"ı açık tutun.");
  }

  // 7) Motor
  d(
    'engine',
    engineRunning ? 'ok' : 'warn',
    'GinDPI motoru',
    engineRunning ? '127.0.0.1:$enginePort üzerinde çalışıyor.' : 'Motor kapalı. Ana ekrandan bağlanın.',
  );
}

String _name(String id) => strategies.firstWhere((s) => s.id == id, orElse: () => strategies.first).name;

bool _looksPoisoned(List<InternetAddress> sys, List<InternetAddress> good) {
  for (final a in sys) {
    final x = a.address;
    if (x.startsWith('0.') || x.startsWith('127.') || x.startsWith('10.') || x.startsWith('192.168.')) {
      return true;
    }
  }
  if (good.isEmpty) return false;
  String net(InternetAddress a) => a.address.split('.').take(2).join('.');
  final goodNets = good.map(net).toSet();
  return !sys.any((a) => goodNets.contains(net(a)));
}

Future<List<InternetAddress>> _lookup(String h) async {
  try {
    return await InternetAddress.lookup(h, type: InternetAddressType.IPv4)
        .timeout(const Duration(seconds: 4));
  } catch (_) {
    return const [];
  }
}

Future<bool> _httpOk(String url) async {
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final r = await (await c.getUrl(Uri.parse(url))).close().timeout(const Duration(seconds: 6));
    await r.drain<void>();
    return r.statusCode < 500;
  } catch (_) {
    return false;
  } finally {
    c.close(force: true);
  }
}

Future<List<String>> _legacyTools() async {
  try {
    final r = await Process.run('tasklist', ['/FO', 'CSV', '/NH']);
    final text = (r.stdout as String).toLowerCase();
    const names = ['goodbyedpi', 'winws', 'zapret', 'spoofdpi', 'byedpi', 'powertunnel'];
    return names.where(text.contains).toList();
  } catch (_) {
    return const [];
  }
}

/// HKCU proxy/PAC ayarı varsa kısa açıklamasını döndürür. GinDPI'nın kendi PAC'ı sayılmaz.
Future<String?> _systemProxy() async {
  try {
    final r = await Process.run('reg', [
      'query',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
    ]);
    final out = r.stdout as String;
    final pac = RegExp(r'AutoConfigURL\s+REG_SZ\s+(\S+)').firstMatch(out)?.group(1);
    if (pac != null && !pac.contains('127.0.0.1')) return 'PAC: $pac';
    final enabled = RegExp(r'ProxyEnable\s+REG_DWORD\s+0x1').hasMatch(out);
    final server = RegExp(r'ProxyServer\s+REG_SZ\s+(\S+)').firstMatch(out)?.group(1);
    if (enabled && server != null) return 'Proxy: $server';
  } catch (_) {}
  return null;
}

