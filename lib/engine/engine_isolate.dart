import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'config.dart';
import 'diagnostics.dart';
import 'dns_server.dart';
import 'proxy_server.dart';

/// Motoru arayüzden ayrı bir isolate'ta çalıştırır; arayüz takılmaz ve
/// boştayken neredeyse hiç işlemci harcanmaz.
///
/// Komutlar: start · stop · diagnose · autotune
/// Olaylar : state · log · stats · diag · tune · tune_done
void engineMain(SendPort ui) {
  final inbox = ReceivePort();
  ui.send(inbox.sendPort);

  ProxyServer? server;
  DnsServer? dns;
  Timer? statsTimer;
  var lastSnapshot = '';

  void send(Map<String, dynamic> m) => ui.send(m);
  // Destek için: tüm satırlar (debug dahil) %APPDATA%\GinDPI\gindpi.log dosyasına da yazılır.
  final logFile = File('${Platform.environment['APPDATA'] ?? Directory.systemTemp.path}\\GinDPI\\gindpi.log');
  try {
    logFile.parent.createSync(recursive: true);
    if (logFile.existsSync() && logFile.lengthSync() > 512 * 1024) logFile.deleteSync();
  } catch (_) {}
  void log(String level, String msg) {
    final now = DateTime.now();
    try {
      logFile.writeAsStringSync('${now.toIso8601String()} [$level] $msg\n', mode: FileMode.append);
    } catch (_) {}
    send({'ev': 'log', 'level': level, 'msg': msg, 't': now.millisecondsSinceEpoch});
  }

  Future<void> stop({bool notify = true}) async {
    statsTimer?.cancel();
    statsTimer = null;
    final s = server;
    server = null;
    dns?.stop();
    dns = null;
    await s?.stop();
    if (notify) send({'ev': 'state', 'running': false});
  }

  inbox.listen((dynamic raw) async {
    final msg = raw as Map;
    switch (msg['cmd']) {
      case 'start':
        await stop(notify: false);
        final cfg = EngineConfig.fromMap(msg['config'] as Map);
        try {
          final s = ProxyServer(cfg, log);
          final port = await s.start();
          server = s;
          log('info', 'Motor başladı: 127.0.0.1:$port · yöntem: ${cfg.strategy} · '
              '${cfg.domains.length} alan adı · DoH ${cfg.useDoh ? "açık" : "kapalı"}');
          var systemOk = false;
          String? systemError;
          if (cfg.systemMode) {
            try {
              await s.startTransparent();
              final d = DnsServer(cfg, s.doh!, log);
              await d.start();
              dns = d;
              systemOk = true;
              log('info', 'Sistem modu etkin: yerel DNS (53) ve SNI ileticisi (443) çalışıyor');
            } catch (e) {
              systemError = '$e';
              log('error', 'Sistem modu başlatılamadı (53 veya 443 portu başka programda olabilir): $e');
            }
          }
          send({
            'ev': 'state',
            'running': true,
            'port': port,
            'pac': s.pac(),
            'system': systemOk,
            'systemError': systemError,
          });
          statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
            final st = s.stats;
            final snap = '${st.up}|${st.down}|${st.active}|${st.total}|${st.failed}';
            if (snap == lastSnapshot && st.active == 0) return; // boştayken rapor yok
            lastSnapshot = snap;
            send({
              'ev': 'stats',
              'up': st.up,
              'down': st.down,
              'active': st.active,
              'total': st.total,
              'failed': st.failed,
              'hosts': Map<String, int>.from(st.perHost),
            });
          });
        } catch (e) {
          log('error', 'Motor başlatılamadı: $e');
          send({'ev': 'state', 'running': false, 'error': '$e'});
        }
      case 'stop':
        await stop();
        log('info', 'Motor durduruldu');
      case 'diagnose':
        final cfg = EngineConfig.fromMap(msg['config'] as Map);
        await runDiagnostics(cfg, server != null, server?.port ?? 0, send);
        send({'ev': 'diag_done'});
      case 'autotune':
        final cfg = EngineConfig.fromMap(msg['config'] as Map);
        await autoTune(cfg, send);
      case 'exit':
        await stop();
        inbox.close();
        Isolate.exit();
    }
  });
}
