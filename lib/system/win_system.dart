import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'settings_store.dart';

class DiscordInstall {
  const DiscordInstall(this.name, this.updateExe, this.exeName);
  final String name;
  final String updateExe;
  final String exeName;
}

/// Windows'a dokunan her şey burada; hepsi kullanıcı düzeyindedir (yönetici
/// gerektirenler açıkça ayrılmış ve UAC onayı ister).
class WinSystem {
  static const _inet = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
  static const _run = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';

  // ------------------------------------------------------------------ PAC

  static Future<String?> readAutoConfig() async {
    final r = await Process.run('reg', ['query', _inet, '/v', 'AutoConfigURL']);
    if (r.exitCode != 0) return null;
    return RegExp(r'AutoConfigURL\s+REG_SZ\s+(.+)').firstMatch(r.stdout as String)?.group(1)?.trim();
  }

  /// Kullanıcının kendi proxy/PAC ayarı var mı? GinDPI'nın kendi PAC'ı sayılmaz.
  static Future<bool> hasForeignProxy() async {
    final pac = await readAutoConfig();
    if (pac != null && !pac.contains('127.0.0.1')) return true;
    final r = await Process.run('reg', ['query', _inet, '/v', 'ProxyEnable']);
    return RegExp(r'ProxyEnable\s+REG_DWORD\s+0x1').hasMatch(r.stdout as String);
  }

  static Future<void> applyPac(String url, AppSettings s) async {
    if (!s.pacApplied) s.pacBackup = await readAutoConfig();
    await Process.run('reg', ['add', _inet, '/v', 'AutoConfigURL', '/t', 'REG_SZ', '/d', url, '/f']);
    s.pacApplied = true;
    await SettingsStore.save(s);
    _notifyProxyChanged();
  }

  /// PAC'ı kaldırır ve öncesindeki değeri geri yükler.
  static Future<void> restorePac(AppSettings s) async {
    if (!s.pacApplied) return;
    final current = await readAutoConfig();
    if (current != null && current.contains('127.0.0.1')) {
      if (s.pacBackup != null && !s.pacBackup!.contains('127.0.0.1')) {
        await Process.run(
            'reg', ['add', _inet, '/v', 'AutoConfigURL', '/t', 'REG_SZ', '/d', s.pacBackup!, '/f']);
      } else {
        await Process.run('reg', ['delete', _inet, '/v', 'AutoConfigURL', '/f']);
      }
    }
    s.pacApplied = false;
    s.pacBackup = null;
    await SettingsStore.save(s);
    _notifyProxyChanged();
  }

  /// Çalışan uygulamalara (Discord, tarayıcılar) proxy ayarının değiştiğini bildirir.
  static void _notifyProxyChanged() {
    try {
      final f = DynamicLibrary.open('wininet.dll').lookupFunction<
          Int32 Function(Pointer<Void>, Uint32, Pointer<Void>, Uint32),
          int Function(Pointer<Void>, int, Pointer<Void>, int)>('InternetSetOptionW');
      f(nullptr, 39, nullptr, 0); // INTERNET_OPTION_SETTINGS_CHANGED
      f(nullptr, 37, nullptr, 0); // INTERNET_OPTION_REFRESH
    } catch (_) {}
  }

  // -------------------------------------------------------------- Discord

  static List<DiscordInstall> findDiscord() {
    final local = Platform.environment['LOCALAPPDATA'];
    if (local == null) return const [];
    final out = <DiscordInstall>[];
    for (final (folder, exe) in const [
      ('Discord', 'Discord.exe'),
      ('DiscordPTB', 'DiscordPTB.exe'),
      ('DiscordCanary', 'DiscordCanary.exe'),
    ]) {
      final update = '$local\\$folder\\Update.exe';
      if (File(update).existsSync()) out.add(DiscordInstall(folder, update, exe));
    }
    return out;
  }

  static Future<bool> isRunning(String exeName) async {
    final r = await Process.run('tasklist', ['/FI', 'IMAGENAME eq $exeName', '/NH']);
    return (r.stdout as String).toLowerCase().contains(exeName.toLowerCase());
  }

  /// Discord'u doğrudan GinDPI vekiliyle başlatır (sistem ayarlarına dokunmaz).
  /// Zaten açıksa kapatıp yeniden başlatır; yoksa bayrak yok sayılırdı.
  static Future<void> launchDiscord(DiscordInstall d, int port, {bool restart = true}) async {
    if (restart && await isRunning(d.exeName)) {
      await Process.run('taskkill', ['/F', '/IM', d.exeName]);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    }
    // Chromium bayrağı arayüzü kapsar; Discord'un Rust güncelleyicisi (reqwest) ise
    // yalnızca ortam değişkenlerine bakar. İkisi de gerekli.
    final proxy = 'http://127.0.0.1:$port';
    // GinDPI yönetici olarak çalışır; çocuk süreç de yönetici olurdu ve Windows,
    // yönetici olmayan Gezgin'den sürükle-bırakı (dosya yükleme) engellerdi.
    if (await isElevated()) {
      await _startUnelevated(
          '"${d.updateExe}" --processStart ${d.exeName} --process-start-args --proxy-server=$proxy');
      return;
    }
    await Process.start(
      d.updateExe,
      ['--processStart', d.exeName, '--process-start-args', '--proxy-server=$proxy'],
      environment: {
        'HTTPS_PROXY': proxy,
        'HTTP_PROXY': proxy,
        'ALL_PROXY': proxy,
      },
      mode: ProcessStartMode.detached,
    );
  }

  /// Yönetici bir süreçten, yetkisi YÜKSELTİLMEMİŞ bir program başlatır: kullanıcı
  /// olarak çalışan, "sınırlı" yetkili tek seferlik zamanlanmış görev.
  static Future<void> _startUnelevated(String command) async {
    const task = 'GinDPI-Launch';
    await Process.run('schtasks', [
      '/Create', '/F', '/TN', task, '/SC', 'ONCE', '/ST', '00:00', '/RL', 'LIMITED', '/TR', command,
    ]);
    await Process.run('schtasks', ['/Run', '/TN', task]);
    await Future<void>.delayed(const Duration(seconds: 3));
    await Process.run('schtasks', ['/Delete', '/F', '/TN', task]);
  }

  // ------------------------------------------------------------ Başlangıç

  /// Yönetici gerektiren uygulamalar Run anahtarıyla sessizce açılamaz; en yüksek
  /// yetkili zamanlanmış görev kullanılır (oturum açılışında, onay sormadan).
  static Future<void> setLaunchAtStartup(bool on) async {
    await Process.run('reg', ['delete', _run, '/v', 'GinDPI', '/f']); // eski sürümden kalan
    if (on) {
      await Process.run('schtasks', [
        '/Create', '/F', '/TN', 'GinDPI', '/SC', 'ONLOGON', '/RL', 'HIGHEST',
        '/TR', '"${Platform.resolvedExecutable}" --minimized',
      ]);
    } else {
      await Process.run('schtasks', ['/Delete', '/F', '/TN', 'GinDPI']);
    }
  }

  // --------------------------------------------------- Yönetici gerektirenler

  /// PowerShell betiğini UAC onayıyla yönetici olarak çalıştırır.
  /// Kullanıcı reddederse false döner.
  static Future<bool> runElevated(String script) async {
    final b64 = base64.encode(_utf16le(script));
    final r = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      "try { Start-Process powershell -Verb RunAs -WindowStyle Hidden -Wait "
          "-ArgumentList '-NoProfile','-EncodedCommand','$b64'; exit 0 } catch { exit 1 }",
    ]);
    return r.exitCode == 0;
  }

  static Future<bool> killLegacyTools() => runAdmin(
      "foreach(\$n in 'goodbyedpi','winws','zapret','spoofdpi','byedpi','powertunnel'){ "
      "Stop-Process -Name \$n -Force -ErrorAction SilentlyContinue }; "
      "sc.exe stop WinDivert 2>\$null | Out-Null");

  /// Windows DNS'ini Cloudflare DoH ile şifreler (yalnızca fiziksel bağdaştırıcılar).
  /// Eski değerler yedeklenir; [revertSecureDns] ile geri alınır.
  static Future<bool> applySecureDns() async {
    await SettingsStore.dir.create(recursive: true);
    final backup = '${SettingsStore.dir.path}\\dns-backup.json';
    return runAdmin('''
\$ErrorActionPreference = 'Stop'
\$ads = Get-NetAdapter -Physical | Where-Object Status -eq 'Up'
\$bk = @(\$ads | ForEach-Object {
  [pscustomobject]@{ index = \$_.ifIndex; servers = @((Get-DnsClientServerAddress -InterfaceIndex \$_.ifIndex -AddressFamily IPv4).ServerAddresses) }
})
if (-not (Test-Path '$backup')) { \$bk | ConvertTo-Json -Compress | Set-Content '$backup' -Encoding utf8 }
foreach (\$a in '1.1.1.1','1.0.0.1') {
  if (-not (Get-DnsClientDohServerAddress | Where-Object ServerAddress -eq \$a)) {
    Add-DnsClientDohServerAddress -ServerAddress \$a -DohTemplate 'https://cloudflare-dns.com/dns-query' -AllowFallbackToUdp \$false -AutoUpgrade \$true
  }
}
foreach (\$ad in \$ads) { Set-DnsClientServerAddress -InterfaceIndex \$ad.ifIndex -ServerAddresses ('1.1.1.1','1.0.0.1') }
Clear-DnsClientCache
''');
  }

  static Future<bool> revertSecureDns() {
    final backup = '${SettingsStore.dir.path}\\dns-backup.json';
    return runAdmin('''
if (Test-Path '$backup') {
  \$bk = @(Get-Content '$backup' -Raw | ConvertFrom-Json)
  foreach (\$b in \$bk) {
    if (@(\$b.servers).Count -eq 0) { Set-DnsClientServerAddress -InterfaceIndex \$b.index -ResetServerAddresses }
    else { Set-DnsClientServerAddress -InterfaceIndex \$b.index -ServerAddresses @(\$b.servers) }
  }
  Remove-Item '$backup' -Force
}
Clear-DnsClientCache
''');
  }

  // ------------------------------------------------ Sistem modu (NRPT kuralı)

  /// Yalnızca bu alan adlarının DNS sorguları 127.0.0.1'deki GinDPI DNS'ine gider.
  /// Diğer siteler Windows'un normal DNS'ini kullanmaya devam eder. Yönetici onayı ister.
  static Future<bool> installNrpt(List<String> domains) {
    final ns = <String>{
      for (final d in domains) ...[d, '.$d'],
    }.map((e) => "'$e'").join(',');
    return runAdmin('''
Get-DnsClientNrptRule | Where-Object Comment -eq 'GinDPI' | Remove-DnsClientNrptRule -Force
Add-DnsClientNrptRule -Namespace @($ns) -NameServers '127.0.0.1' -Comment 'GinDPI'
Clear-DnsClientCache
''');
  }

  static Future<bool> removeNrpt() => runAdmin('''
Get-DnsClientNrptRule | Where-Object Comment -eq 'GinDPI' | Remove-DnsClientNrptRule -Force
Clear-DnsClientCache
''');

  /// Uygulama yönetici olarak mı çalışıyor? (Manifest bunu ister; yine de doğrularız.)
  static bool? _elevated;
  static Future<bool> isElevated() async {
    if (_elevated != null) return _elevated!;
    try {
      final r = await Process.run('whoami', ['/groups']);
      _elevated = (r.stdout as String).contains('S-1-16-12288');
    } catch (_) {
      _elevated = false;
    }
    return _elevated!;
  }

  /// Yönetici isek doğrudan, değilsek UAC onayıyla çalıştırır.
  static Future<bool> runAdmin(String script) async {
    if (await isElevated()) {
      final r = await Process.run('powershell',
          ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', base64.encode(_utf16le(script))]);
      return r.exitCode == 0;
    }
    return runElevated(script);
  }

  static Future<bool> nrptInstalled() async {
    try {
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        "if (Get-DnsClientNrptRule | Where-Object Comment -eq 'GinDPI') { 'yes' } else { 'no' }",
      ]);
      return (r.stdout as String).trim() == 'yes';
    } catch (_) {
      return false;
    }
  }

  static bool get hasDnsBackup => File('${SettingsStore.dir.path}\\dns-backup.json').existsSync();

  static List<int> _utf16le(String s) {
    final out = <int>[];
    for (final u in s.codeUnits) {
      out..add(u & 0xff)..add(u >> 8);
    }
    return out;
  }
}

/// Aynı anda tek örnek: loopback portunu kilit olarak kullanır.
class SingleInstance {
  static const _port = 47213;
  static ServerSocket? _lock;

  /// true: bu ilk örnek. false: başka örnek çalışıyor ve ona "göster" sinyali gönderildi.
  static Future<bool> acquire(void Function() onShowRequest) async {
    try {
      _lock = await ServerSocket.bind(InternetAddress.loopbackIPv4, _port);
      _lock!.listen((c) {
        c.listen((_) => onShowRequest(), onError: (_) {});
      });
      return true;
    } on SocketException {
      try {
        final s = await Socket.connect(InternetAddress.loopbackIPv4, _port,
            timeout: const Duration(seconds: 1));
        s.add([1]);
        await s.flush();
        await s.close();
      } catch (_) {}
      return false;
    }
  }
}
