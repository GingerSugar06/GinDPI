// Arayüzsüz hızlı deneme: dart run bin/probe.dart
// Motoru ve otomatik yöntem aramasını gerçek ağda dener.
import 'dart:io';

import 'package:gindpi/engine/config.dart';
import 'package:gindpi/engine/diagnostics.dart';

Future<void> main() async {
  final cfg = EngineConfig(domains: servicePresets.first.domains);
  stdout.writeln('Yöntemler paralel deneniyor…');
  await autoTune(cfg, (e) {
    if (e['ev'] == 'tune') {
      stdout.writeln('  ${e['id'].toString().padRight(16)} ${e['ok'] ? "OK  ${e['ms']} ms" : "BAŞARISIZ"}');
    } else if (e['ev'] == 'tune_done') {
      stdout.writeln('En iyi: ${e['best']}  (yöntemsiz erişim: ${e['baselineOk']})');
    }
  });
  exit(0);
}
