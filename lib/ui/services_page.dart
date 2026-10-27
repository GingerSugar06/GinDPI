import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../engine/config.dart';
import 'theme.dart';
import 'widgets.dart';

class ServicesPage extends StatefulWidget {
  const ServicesPage({super.key, required this.c});
  final AppController c;

  @override
  State<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends State<ServicesPage> {
  final _input = TextEditingController();
  String? _error;

  AppController get c => widget.c;

  void _add() {
    var t = _input.text.trim().toLowerCase();
    t = t.replaceFirst(RegExp(r'^https?://'), '').split('/').first.replaceFirst(RegExp(r'^www\.'), '');
    final ok = RegExp(r'^([a-z0-9-]+\.)+[a-z]{2,}$').hasMatch(t);
    if (!ok) {
      setState(() => _error = 'Geçerli bir alan adı yazın (örnek: ornek.com)');
      return;
    }
    if (!c.settings.customDomains.contains(t)) c.settings.customDomains.add(t);
    _input.clear();
    setState(() => _error = null);
    c.changed();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = c.settings;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 8, 32, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('Servisler',
              subtitle: 'Yalnızca açık olanlar GinDPI üzerinden geçer. Geri kalan her şey olduğu gibi gider.'),
          const SizedBox(height: 22),
          for (final p in servicePresets) ...[
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: P.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  alignment: Alignment.center,
                  child: Text(p.name[0],
                      style: const TextStyle(color: P.accent, fontWeight: FontWeight.w800, fontSize: 18)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text('${p.description} · ${p.domains.length} alan adı',
                        style: const TextStyle(color: P.muted, fontSize: 12.5)),
                  ]),
                ),
                GSwitch(
                  value: s.services.contains(p.id),
                  onChanged: (v) {
                    v ? s.services.add(p.id) : s.services.remove(p.id);
                    c.changed();
                  },
                ),
              ]),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 10),
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Kendi sitelerim', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text('Engelli başka bir site varsa alan adını ekleyin; alt alan adları otomatik dahil olur.',
                  style: TextStyle(color: P.muted, fontSize: 12.5)),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    onSubmitted: (_) => _add(),
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'ornek.com',
                      errorText: _error,
                      filled: true,
                      fillColor: P.bg,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: P.line)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: P.line)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: P.accent)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GButton('Ekle', icon: Icons.add_rounded, primary: true, onPressed: _add),
              ]),
              if (s.customDomains.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final d in s.customDomains)
                    Chip2(d, color: P.accentSoft, onDelete: () {
                      s.customDomains.remove(d);
                      c.changed();
                    }),
                ]),
              ],
            ]),
          ),
          const SizedBox(height: 22),
          const Panel(
            color: P.bg,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.shield_outlined, color: P.ok, size: 22),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Neden ödemeler bozulmaz? Eski araçlar bilgisayarın tüm ağ trafiğini değiştirir. '
                  'GinDPI ise Windows\'a yalnızca "şu alan adları bana gelsin" listesini verir; '
                  'diğer tüm siteler (bankalar, ödeme sayfaları, oyunlar) hiç uğramadan doğrudan bağlanır.',
                  style: TextStyle(color: P.muted, fontSize: 13, height: 1.5),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
