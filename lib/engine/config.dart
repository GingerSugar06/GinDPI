/// Motorun çalışması için gereken, isolate sınırından geçebilen (Map'e
/// dönüştürülebilir) ayarlar.
class EngineConfig {
  const EngineConfig({
    this.port = 8118,
    this.domains = const [],
    this.strategy = 'combo',
    this.useDoh = true,
    this.dohProvider = 'auto',
    this.splitDelayMs = 2,
    this.systemMode = false,
  });

  /// Sistem modu: yerel DNS (127.0.0.1:53) + SNI ileticisi (127.0.0.1:443).
  /// Vekil ayarını dinlemeyen programlar (Discord güncelleyicisi) için.
  final bool systemMode;

  /// Gerçek adresiyle çözülmesi gereken (yönlendirilmeyen) alan adları:
  /// ses sunucuları UDP kullanır, vekile/ileticiye uğramamalı.
  bool dnsPassthrough(String name) => name == 'discord.media' || name.endsWith('.discord.media');

  final int port;

  /// Eşleşen (son ek) alan adları motor üzerinden geçer; gerisi dokunulmadan gider.
  final List<String> domains;
  final String strategy;
  final bool useDoh;
  final String dohProvider;
  final int splitDelayMs;

  Map<String, dynamic> toMap() => {
        'port': port,
        'domains': domains,
        'strategy': strategy,
        'useDoh': useDoh,
        'dohProvider': dohProvider,
        'splitDelayMs': splitDelayMs,
        'systemMode': systemMode,
      };

  factory EngineConfig.fromMap(Map m) => EngineConfig(
        port: m['port'] as int,
        domains: List<String>.from(m['domains'] as List),
        strategy: m['strategy'] as String,
        useDoh: m['useDoh'] as bool,
        dohProvider: m['dohProvider'] as String,
        splitDelayMs: m['splitDelayMs'] as int,
        systemMode: m['systemMode'] as bool? ?? false,
      );

  EngineConfig copyWith({
    int? port,
    List<String>? domains,
    String? strategy,
    bool? useDoh,
    String? dohProvider,
    int? splitDelayMs,
    bool? systemMode,
  }) =>
      EngineConfig(
        systemMode: systemMode ?? this.systemMode,
        port: port ?? this.port,
        domains: domains ?? this.domains,
        strategy: strategy ?? this.strategy,
        useDoh: useDoh ?? this.useDoh,
        dohProvider: dohProvider ?? this.dohProvider,
        splitDelayMs: splitDelayMs ?? this.splitDelayMs,
      );

  /// [host] kural listesindeki bir alan adına (veya alt alan adına) uyuyor mu?
  bool matches(String host) {
    final h = host.toLowerCase();
    for (final d in domains) {
      if (h == d || h.endsWith('.$d')) return true;
    }
    return false;
  }
}

/// Kullanıcıya gösterilen hazır servis paketleri.
class ServicePreset {
  const ServicePreset(this.id, this.name, this.description, this.domains);
  final String id;
  final String name;
  final String description;
  final List<String> domains;
}

const servicePresets = <ServicePreset>[
  ServicePreset(
    'discord',
    'Discord',
    'Uygulama, tarayıcı, ses ve görüntü sunucuları',
    [
      'discord.com',
      'discordapp.com',
      'discordapp.net',
      'discord.gg',
      'discord.media',
      'discordcdn.com',
      'discord.new',
      'discord.gift',
      'discordstatus.com',
      'dis.gd',
      'discord.co',
      'discordsays.com',
      // Dosya/görsel yüklemeleri Discord alan adında değil, adında "discord" geçen
      // Google Cloud Storage adreslerine gider; vekilden geçmezse yükleme takılır.
      'discord-attachments-uploads-prd.storage.googleapis.com',
      'discordapp.storage.googleapis.com',
    ],
  ),
  ServicePreset(
    'roblox',
    'Roblox',
    'Oyun, web sitesi ve içerik sunucuları',
    ['roblox.com', 'rbxcdn.com', 'robloxlabs.com'],
  ),
  ServicePreset(
    'wattpad',
    'Wattpad',
    'Okuma sitesi ve uygulaması',
    ['wattpad.com'],
  ),
];

/// Bölme yöntemleri (otomatik arama bu sırayla dener).
class StrategyInfo {
  const StrategyInfo(this.id, this.name, this.description);
  final String id;
  final String name;
  final String description;
}

const strategies = <StrategyInfo>[
  StrategyInfo('combo', 'Birleşik (3 parça)',
      'İlk 2 baytı ayırır, sonra iki TLS kaydı gönderir. Hem TLS 1.3 hem eski TLS 1.2 istemcilerinde (Discord güncelleyicisi) çalışır.'),
  StrategyInfo('tls_record_tcp', 'TLS kaydını böl',
      'Başlangıç mesajını iki ayrı TLS kaydı yapar, her biri ayrı TCP paketinde gider. Tarayıcılar için yeterli.'),
  StrategyInfo('sni_split', 'SNI ortasından böl',
      'TLS başlangıç paketini alan adının ortasından iki TCP parçasına böler. Bazı operatörlerde işe yaramaz.'),
  StrategyInfo('first_byte', 'İlk bayttan böl',
      'İlk baytı tek başına gönderir, kalanı sonradan.'),
  StrategyInfo('tls_record', 'TLS kaydı (tek paket)',
      'İki TLS kaydı tek paket içinde gider. Düşük gecikmeli.'),
];
