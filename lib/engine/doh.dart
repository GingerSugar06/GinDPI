import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// DoH (HTTPS üzerinden DNS) çözücü. Sunucular IP adresiyle bağlanılır; böylece
/// DNS'e veya SNI'ye dayalı engelleme bu sorgulara uygulanamaz.
class DohResolver {
  DohResolver(this.provider) {
    _client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 4)
      ..idleTimeout = const Duration(seconds: 30);
  }

  final String provider; // auto | cloudflare | google | quad9
  late final HttpClient _client;
  final Map<String, _Entry> _cache = {};

  static const endpoints = <String, List<String>>{
    'cloudflare': [
      'https://1.1.1.1/dns-query',
      'https://1.0.0.1/dns-query',
    ],
    'google': [
      'https://8.8.8.8/resolve',
      'https://8.8.4.4/resolve',
    ],
    'quad9': [
      'https://9.9.9.9:5053/dns-query',
      'https://149.112.112.112:5053/dns-query',
    ],
  };

  List<String> get _order {
    if (provider != 'auto' && endpoints.containsKey(provider)) {
      return [
        ...endpoints[provider]!,
        for (final e in endpoints.entries)
          if (e.key != provider) ...e.value,
      ];
    }
    return [for (final e in endpoints.values) ...e];
  }

  /// IPv4 adreslerini döndürür; hiçbir sağlayıcı yanıt vermezse boş liste.
  Future<List<InternetAddress>> resolve(String host) async {
    final key = host.toLowerCase();
    final hit = _cache[key];
    if (hit != null && hit.expires.isAfter(DateTime.now())) return hit.addrs;

    for (final url in _order) {
      try {
        final addrs = await _query(url, key).timeout(const Duration(seconds: 5));
        if (addrs.isNotEmpty) {
          _cache[key] = _Entry(addrs, DateTime.now().add(const Duration(minutes: 3)));
          return addrs;
        }
      } catch (_) {
        // sıradaki sağlayıcıyı dene
      }
    }
    return const [];
  }

  /// Tek bir sağlayıcıyı ölçer; tanılama sayfası için.
  Future<Duration?> ping(String url) async {
    final sw = Stopwatch()..start();
    try {
      final r = await _query(url, 'discord.com').timeout(const Duration(seconds: 5));
      return r.isEmpty ? null : sw.elapsed;
    } catch (_) {
      return null;
    }
  }

  Future<List<InternetAddress>> _query(String base, String name) async {
    final uri = Uri.parse('$base?name=$name&type=A');
    final req = await _client.getUrl(uri);
    req.headers.set('accept', 'application/dns-json');
    final res = await req.close();
    if (res.statusCode != 200) {
      await res.drain<void>();
      throw HttpException('DoH ${res.statusCode}');
    }
    final body = await res.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final answers = (json['Answer'] as List?) ?? const [];
    final out = <InternetAddress>[];
    for (final a in answers) {
      if (a is Map && a['type'] == 1) {
        final ip = InternetAddress.tryParse(a['data'] as String);
        if (ip != null) out.add(ip);
      }
    }
    return out;
  }

  void close() => _client.close(force: true);
}

class _Entry {
  _Entry(this.addrs, this.expires);
  final List<InternetAddress> addrs;
  final DateTime expires;
}
