import 'dart:convert';
import 'dart:io';

import '../engine/config.dart';

class AppSettings {
  AppSettings({
    Set<String>? services,
    List<String>? customDomains,
    this.strategy = 'combo',
    this.tuned = false,
    this.useDoh = true,
    this.dohProvider = 'auto',
    this.port = 8118,
    this.splitDelayMs = 2,
    this.systemPac = true,
    this.launchAtStartup = false,
    this.autoConnect = false,
    this.closeToTray = true,
    this.pacApplied = false,
    this.pacBackup,
    this.systemMode = true,
  })  : services = services ?? {'discord'},
        customDomains = customDomains ?? [];

  Set<String> services;
  List<String> customDomains;
  String strategy;
  bool tuned;
  bool useDoh;
  String dohProvider;
  int port;
  int splitDelayMs;
  bool systemPac;
  bool launchAtStartup;
  bool autoConnect;
  bool closeToTray;

  /// NRPT kuralı kurulu ve motor yerel DNS + SNI ileticisini çalıştırıyor.
  bool systemMode;

  /// PAC adresi bu uygulama tarafından yazıldıysa true; çökme sonrası geri alma için.
  bool pacApplied;

  /// PAC öncesindeki AutoConfigURL değeri (yoksa null).
  String? pacBackup;

  List<String> get activeDomains => [
        for (final p in servicePresets)
          if (services.contains(p.id)) ...p.domains,
        ...customDomains,
      ];

  EngineConfig toEngine() => EngineConfig(
        port: port,
        domains: activeDomains,
        strategy: strategy,
        useDoh: useDoh,
        dohProvider: dohProvider,
        splitDelayMs: splitDelayMs,
        systemMode: systemMode,
      );

  Map<String, dynamic> toJson() => {
        'services': services.toList(),
        'customDomains': customDomains,
        'strategy': strategy,
        'tuned': tuned,
        'useDoh': useDoh,
        'dohProvider': dohProvider,
        'port': port,
        'splitDelayMs': splitDelayMs,
        'systemPac': systemPac,
        'launchAtStartup': launchAtStartup,
        'autoConnect': autoConnect,
        'closeToTray': closeToTray,
        'pacApplied': pacApplied,
        'pacBackup': pacBackup,
        'systemMode': systemMode,
        'ver': 2,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) {
    final d = AppSettings();
    // Sürüm 2: yöntem seçimi TLS 1.2'yi de sınıyor; eski seçim yeniden aranmalı.
    final old = ((j['ver'] as int?) ?? 1) < 2;
    return AppSettings(
      services: (j['services'] as List?)?.cast<String>().toSet() ?? d.services,
      customDomains: (j['customDomains'] as List?)?.cast<String>().toList(),
      strategy: old ? d.strategy : (j['strategy'] as String? ?? d.strategy),
      tuned: old ? false : (j['tuned'] as bool? ?? false),
      useDoh: j['useDoh'] as bool? ?? true,
      dohProvider: j['dohProvider'] as String? ?? 'auto',
      port: j['port'] as int? ?? 8118,
      splitDelayMs: j['splitDelayMs'] as int? ?? 2,
      systemPac: j['systemPac'] as bool? ?? true,
      launchAtStartup: j['launchAtStartup'] as bool? ?? false,
      autoConnect: j['autoConnect'] as bool? ?? false,
      closeToTray: j['closeToTray'] as bool? ?? true,
      pacApplied: j['pacApplied'] as bool? ?? false,
      pacBackup: j['pacBackup'] as String?,
      systemMode: j['systemMode'] as bool? ?? true,
    );
  }
}

class SettingsStore {
  static Directory get dir {
    final base = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
    return Directory('$base\\GinDPI');
  }

  static File get _file => File('${dir.path}\\settings.json');

  static Future<AppSettings> load() async {
    try {
      if (await _file.exists()) {
        return AppSettings.fromJson(jsonDecode(await _file.readAsString()) as Map<String, dynamic>);
      }
    } catch (_) {}
    return AppSettings();
  }

  static Future<void> save(AppSettings s) async {
    try {
      await dir.create(recursive: true);
      await _file.writeAsString(const JsonEncoder.withIndent('  ').convert(s.toJson()));
    } catch (_) {}
  }
}
