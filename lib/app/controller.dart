import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../engine/config.dart';
import '../engine/engine_isolate.dart';
import '../system/settings_store.dart';
import '../system/win_system.dart';

enum ConnState { off, starting, on, error }

class LogLine {
  LogLine(this.level, this.msg, this.time);
  final String level;
  final String msg;
  final DateTime time;
}

class DiagItem {
  DiagItem(this.id, this.status, this.title, this.detail, this.fix);
  final String id;
  final String status; // run | ok | warn | fail
  final String title;
  final String detail;
  final List<String> fix;
}

class TuneResult {
  TuneResult(this.ok, this.ms);
  final bool ok;
  final int? ms;
}

/// Arayüzün tek gerçek kaynağı. Motor isolate'ı ile konuşur, Windows
/// entegrasyonunu yönetir ve değişiklikleri dinleyicilere bildirir.
class AppController extends ChangeNotifier {
  AppController(this.settings);

  AppSettings settings;

  ConnState state = ConnState.off;
  String statusNote = '';
  int port = 0;

  // Sayaçlar
  int upBytes = 0;
  int downBytes = 0;
  int active = 0;
  int totalConns = 0;
  int failed = 0;
  Map<String, int> hostHits = {};
  final List<double> history = List.filled(60, 0, growable: true);
  int _lastUp = 0;
  int _lastDown = 0;
  int _statsThisTick = 0;
  Timer? _tick;

  // Günlük / tanılama / otomatik arama
  final List<LogLine> logs = [];
  final Map<String, DiagItem> diag = {};
  bool diagRunning = false;
  final Map<String, TuneResult> tune = {};
  bool tuning = false;
  String? tuneBest;
  bool? tuneBaselineOk;

  // Ortam
  List<DiscordInstall> discords = const [];
  bool foreignProxy = false;
  bool systemActive = false;
  bool elevated = false;
  bool _nrptApplied = false;

  /// Motora giden ayar: sistem modu yalnızca yönetici isek anlamlıdır.
  EngineConfig get engineConfig => settings.toEngine().copyWith(systemMode: settings.systemMode && elevated);
  bool windowVisible = true;
  String? banner; // kullanıcıya gösterilecek tek satırlık uyarı

  SendPort? _engine;
  Isolate? _isolate;
  Completer<Map>? _stateWait;
  Completer<void>? _tuneWait;
  Timer? _restartDebounce;

  // ---------------------------------------------------------------- başlangıç

  Future<void> init() async {
    discords = WinSystem.findDiscord();
    elevated = await WinSystem.isElevated();
    // Önceki oturum çöktüyse PAC'ı ve DNS kuralını geri al (motor yokken kural kalmamalı).
    if (settings.pacApplied) await WinSystem.restorePac(settings);
    if (elevated && await WinSystem.nrptInstalled()) await WinSystem.removeNrpt();
    await _spawnEngine();
    // Varsayılan olarak Windows ile başlar: görev ilk açılışta kurulur, klasör
    // taşındıysa (taşınabilir sürüm) yeni yola güncellenir. Beklenmez.
    if (settings.launchAtStartup && elevated) unawaited(WinSystem.setLaunchAtStartup(true));
    notifyListeners();
  }

  Future<void> _spawnEngine() async {
    final rp = ReceivePort();
    final ready = Completer<SendPort>();
    rp.listen((dynamic m) {
      if (m is SendPort) {
        ready.complete(m);
      } else if (m is Map) {
        _onEngineEvent(m);
      }
    });
    _isolate = await Isolate.spawn(engineMain, rp.sendPort, debugName: 'gindpi-engine');
    _engine = await ready.future;
  }

  void _onEngineEvent(Map m) {
    switch (m['ev']) {
      case 'state':
        _stateWait?.complete(m);
        _stateWait = null;
        if (m['running'] == true) {
          port = m['port'] as int;
        } else if (state == ConnState.on) {
          state = ConnState.off;
          notifyListeners();
        }
      case 'log':
        _addLog(m['level'] as String, m['msg'] as String,
            DateTime.fromMillisecondsSinceEpoch(m['t'] as int));
      case 'stats':
        _statsThisTick++;
        final up = m['up'] as int;
        final down = m['down'] as int;
        _pushHistory((up - _lastUp + down - _lastDown).toDouble());
        _lastUp = up;
        _lastDown = down;
        upBytes = up;
        downBytes = down;
        active = m['active'] as int;
        totalConns = m['total'] as int;
        failed = m['failed'] as int;
        hostHits = Map<String, int>.from(m['hosts'] as Map);
        if (windowVisible) notifyListeners();
      case 'diag':
        diag[m['id'] as String] = DiagItem(
          m['id'] as String,
          m['status'] as String,
          m['title'] as String,
          m['detail'] as String,
          List<String>.from(m['fix'] as List),
        );
        notifyListeners();
      case 'diag_done':
        diagRunning = false;
        notifyListeners();
      case 'tune':
        tune[m['id'] as String] = TuneResult(m['ok'] as bool, m['ms'] as int?);
        notifyListeners();
      case 'tune_done':
        tuning = false;
        tuneBest = m['best'] as String?;
        tuneBaselineOk = m['baselineOk'] as bool?;
        _tuneWait?.complete();
        _tuneWait = null;
        notifyListeners();
    }
  }

  void _addLog(String level, String msg, [DateTime? t]) {
    if (level == 'debug' && logs.length > 400) return;
    logs.add(LogLine(level, msg, t ?? DateTime.now()));
    if (logs.length > 500) logs.removeRange(0, logs.length - 500);
    if (level == 'warn' || level == 'error') banner = msg;
    if (windowVisible) notifyListeners();
  }

  void clearLogs() {
    logs.clear();
    banner = null;
    notifyListeners();
  }

  void _pushHistory(double bytes) {
    history.add(bytes);
    if (history.length > 60) history.removeAt(0);
  }

  // -------------------------------------------------------------- bağlantı

  bool get isOn => state == ConnState.on;
  bool get isBusy => state == ConnState.starting;

  Future<void> toggle() => isOn || state == ConnState.error ? disconnect() : connect();

  Future<void> connect() async {
    if (isBusy || isOn) return;
    state = ConnState.starting;
    statusNote = 'Hazırlanıyor…';
    banner = null;
    notifyListeners();

    // İlk bağlantıda bu ağa uygun yöntemi otomatik bul.
    if (!settings.tuned) {
      statusNote = 'Bu ağ için en iyi yöntem aranıyor…';
      notifyListeners();
      await runAutoTune(apply: true);
    }

    statusNote = 'Motor başlatılıyor…';
    notifyListeners();
    _stateWait = Completer<Map>();
    _engine!.send({'cmd': 'start', 'config': engineConfig.toMap()});
    final r = await _stateWait!.future;
    if (r['running'] != true) {
      state = ConnState.error;
      statusNote = 'Motor başlatılamadı';
      banner = 'Motor başlatılamadı: ${r['error']}';
      notifyListeners();
      return;
    }

    systemActive = r['system'] == true;
    if (systemActive) {
      // Yerel DNS ayakta; şimdi yalnızca bu alan adlarının sorgularını ona yönlendir.
      final domains = {
        for (final p in servicePresets) ...p.domains,
        ...settings.customDomains,
      }.toList();
      _nrptApplied = await WinSystem.installNrpt(domains);
      if (_nrptApplied) {
        _addLog('info', 'Sistem modu etkin: Discord güncelleyicisi dahil tüm uygulamalar yönlendiriliyor');
      } else {
        systemActive = false;
        _addLog('warn', 'DNS kuralı kurulamadı; yalnızca vekil ayarını dinleyen uygulamalar çalışır.');
      }
    } else if (settings.systemMode && !elevated) {
      _addLog('warn', 'Yönetici izni yok: sistem modu kapalı. GinDPI\'yı yönetici olarak açın.');
    } else if (settings.systemMode) {
      _addLog('warn',
          'Sistem modu başlatılamadı: ${r['systemError']}. 53/443 portlarını kullanan başka bir program olabilir.');
    }

    // Yalnızca seçili alan adlarını yönlendiren PAC'ı Windows'a tanıt.
    foreignProxy = await WinSystem.hasForeignProxy();
    if (settings.systemPac && !foreignProxy) {
      await WinSystem.applyPac('http://127.0.0.1:$port/proxy.pac', settings);
      _addLog('info', 'Windows otomatik yapılandırması etkin: yalnızca seçili siteler yönlendiriliyor');
    } else if (foreignProxy) {
      _addLog('warn',
          'Windows\'ta başka bir proxy ayarı var; ezmemek için PAC uygulanmadı. Discord\'u GinDPI\'dan başlatın.');
    }

    _resetCounters();
    state = ConnState.on;
    statusNote = 'Korumalı';
    _startTick();
    notifyListeners();
  }

  /// Windows'a yazdığımız her şeyi geri alır (PAC + DNS kuralı).
  Future<void> _cleanupSystem() async {
    await WinSystem.restorePac(settings);
    if (_nrptApplied) {
      await WinSystem.removeNrpt();
      _nrptApplied = false;
    }
    systemActive = false;
  }

  Future<void> disconnect() async {
    _tick?.cancel();
    await _cleanupSystem();
    _engine?.send({'cmd': 'stop'});
    state = ConnState.off;
    statusNote = '';
    active = 0;
    notifyListeners();
  }

  void _resetCounters() {
    upBytes = downBytes = _lastUp = _lastDown = 0;
    active = totalConns = failed = 0;
    hostHits = {};
    history.fillRange(0, history.length, 0);
  }

  void _startTick() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_statsThisTick == 0) _pushHistory(0); // boşta: motor rapor göndermedi
      _statsThisTick = 0;
      if (windowVisible) notifyListeners();
    });
  }

  void setWindowVisible(bool v) {
    windowVisible = v;
    if (v) notifyListeners();
  }

  // ---------------------------------------------------------------- ayarlar

  /// Ayar değişti: kaydet, gerekiyorsa motoru yeni ayarlarla yeniden başlat.
  void changed({bool restartEngine = true}) {
    SettingsStore.save(settings);
    notifyListeners();
    if (restartEngine && isOn) {
      _restartDebounce?.cancel();
      _restartDebounce = Timer(const Duration(milliseconds: 600), _restartRunning);
    }
  }

  Future<void> _restartRunning() async {
    if (!isOn) return;
    await _cleanupSystem();
    state = ConnState.off;
    await connect();
  }

  Future<void> setLaunchAtStartup(bool on) async {
    final ok = await WinSystem.setLaunchAtStartup(on);
    if (ok) {
      settings.launchAtStartup = on;
    } else {
      _addLog('warn', 'Başlangıç görevi ayarlanamadı (yönetici onayı verilmedi).');
    }
    changed(restartEngine: false);
  }

  Future<void> resetSettings() async {
    final wasOn = isOn;
    if (wasOn) await disconnect();
    settings = AppSettings();
    await SettingsStore.save(settings);
    notifyListeners();
  }

  // ------------------------------------------------------ tanılama / çözümler

  void runDiagnostics() {
    if (diagRunning) return;
    diag.clear();
    diagRunning = true;
    notifyListeners();
    _engine!.send({'cmd': 'diagnose', 'config': engineConfig.toMap()});
  }

  /// Tüm yöntemleri dener. [apply] true ise en iyisini ayara yazar.
  Future<void> runAutoTune({bool apply = false}) async {
    if (tuning) return;
    tuning = true;
    tune.clear();
    tuneBest = null;
    notifyListeners();
    _tuneWait = Completer<void>();
    _engine!.send({'cmd': 'autotune', 'config': engineConfig.toMap()});
    await _tuneWait!.future;
    // Ağ henüz hazır değilken (açılışta) hiçbir şey geçmez; bunu "ayarlandı" sayma.
    settings.tuned = tune.values.any((t) => t.ok) || tuneBaselineOk == true;
    if (apply && tuneBest != null) {
      settings.strategy = tuneBest!;
      _addLog('info', 'En iyi yöntem seçildi: ${_strategyName(tuneBest!)}');
    } else if (apply && tune.values.every((t) => !t.ok)) {
      _addLog('warn',
          'Hiçbir yöntem sonuç vermedi. Tanılama sayfasındaki önerilere bakın (DNS, çakışan araçlar).');
    }
    await SettingsStore.save(settings);
    notifyListeners();
  }

  String _strategyName(String id) =>
      strategies.firstWhere((s) => s.id == id, orElse: () => strategies.first).name;

  /// Tanılama kartlarındaki çözüm düğmeleri.
  Future<String?> applyFix(String id) async {
    switch (id) {
      case 'autotune':
        await runAutoTune(apply: true);
        changed();
        return tuneBest == null ? 'Çalışan bir yöntem bulunamadı.' : 'Yöntem değiştirildi.';
      case 'use_launcher':
        settings.systemPac = false;
        changed();
        return 'Sistem ayarlarına dokunulmayacak. Discord\'u GinDPI\'dan başlatın.';
      case 'kill_legacy':
        final ok = await WinSystem.killLegacyTools();
        return ok ? 'Eski araç kapatıldı. Tanılamayı yeniden çalıştırın.' : 'Yönetici onayı verilmedi.';
      case 'dns_fix':
        final ok = await WinSystem.applySecureDns();
        return ok
            ? 'Windows DNS\'i şifrelendi. Discord\'u yeniden başlatın.'
            : 'Yönetici onayı verilmedi.';
    }
    return null;
  }

  Future<String> revertDns() async {
    final ok = await WinSystem.revertSecureDns();
    notifyListeners();
    return ok ? 'DNS ayarları eski haline getirildi.' : 'Yönetici onayı verilmedi.';
  }

  // ---------------------------------------------------------------- Discord

  Future<String?> launchDiscord() async {
    if (discords.isEmpty) return 'Discord bulunamadı. Tarayıcıdan discord.com kullanabilirsiniz.';
    if (!isOn) await connect();
    if (!isOn) return 'Önce bağlantı kurulamadı.';
    await WinSystem.launchDiscord(discords.first, port);
    _addLog('info', '${discords.first.name} GinDPI vekiliyle başlatıldı');
    return null;
  }

  // ------------------------------------------------------------------ çıkış

  Future<void> shutdown() async {
    _tick?.cancel();
    await _cleanupSystem();
    _engine?.send({'cmd': 'exit'});
    await Future<void>.delayed(const Duration(milliseconds: 150));
    _isolate?.kill(priority: Isolate.immediate);
  }
}
