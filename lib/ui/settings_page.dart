import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../engine/config.dart';
import '../system/win_system.dart';
import 'theme.dart';
import 'widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.c});
  final AppController c;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  AppController get c => widget.c;
  late final _port = TextEditingController(text: '${c.settings.port}');

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  void dispose() {
    _port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = c.settings;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 8, 32, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('Ayarlar'),
        const SizedBox(height: 22),
        _Group('Bağlantı', [
          _Row(
            'Yöntem',
            'Engeli aşma biçimi. Emin değilseniz Tanılama\'dan "Hepsini dene" kullanın.',
            trailing: _Drop<String>(
              value: s.strategy,
              items: {for (final x in strategies) x.id: x.name},
              onChanged: (v) {
                s.strategy = v;
                c.changed();
              },
            ),
          ),
          _Row(
            'Şifreli DNS (DoH)',
            'Alan adlarını operatörün DNS\'i yerine şifreli kanaldan çözer. DNS zehirlenmesini aşar.',
            trailing: GSwitch(
              value: s.useDoh,
              onChanged: (v) {
                s.useDoh = v;
                c.changed();
              },
            ),
          ),
          if (s.useDoh)
            _Row(
              'DoH sağlayıcısı',
              'Otomatik: çalışan ilk sağlayıcı kullanılır.',
              trailing: _Drop<String>(
                value: s.dohProvider,
                items: const {'auto': 'Otomatik', 'cloudflare': 'Cloudflare', 'google': 'Google', 'quad9': 'Quad9'},
                onChanged: (v) {
                  s.dohProvider = v;
                  c.changed();
                },
              ),
            ),
          _Row(
            'Yerel port',
            'Başka bir program 8118\'i kullanıyorsa değiştirin. Doluysa otomatik boş port seçilir.',
            trailing: SizedBox(
              width: 96,
              child: TextField(
                controller: _port,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                onSubmitted: (v) {
                  final p = int.tryParse(v);
                  if (p != null && p >= 1024 && p <= 65535) {
                    s.port = p;
                    c.changed();
                  } else {
                    _port.text = '${s.port}';
                    _toast('Port 1024–65535 arasında olmalı.');
                  }
                },
                decoration: _fieldDeco(),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 18),
        _Group('Windows entegrasyonu', [
          _Row(
            'Tüm uygulamalar için çalış',
            'Discord uygulaması ve güncelleyicisi gibi vekil ayarını dinlemeyen programlar için gerekir. '
                "Yalnızca Discord alan adlarının DNS sorguları GinDPI'a yönlenir; diğer siteler etkilenmez. "
                '${c.elevated ? "Bağlanınca kendiliğinden kurulur, kesince temizlenir." : "Yönetici izni yok: GinDPI'yı yönetici olarak açın."}',
            trailing: GSwitch(
              value: s.systemMode,
              onChanged: (v) {
                s.systemMode = v;
                c.changed();
              },
            ),
          ),
          _Row(
            'Otomatik yönlendirme (PAC)',
            'Seçili siteleri Windows üzerinden motora yönlendirir; Discord\'u yeniden başlatmak gerekmez. '
                'Kapalıysa Discord\'u "Discord\'u başlat" ile açın.',
            trailing: GSwitch(
              value: s.systemPac,
              onChanged: (v) {
                s.systemPac = v;
                c.changed();
              },
            ),
          ),
          _Row(
            'Windows ile birlikte başlat',
            'Bilgisayar açılınca GinDPI sistem tepsisinde sessizce başlar ve kendiliğinden bağlanır; '
                'Discord için elle bir şey yapmanız gerekmez.',
            trailing: GSwitch(value: s.launchAtStartup, onChanged: c.setLaunchAtStartup),
          ),
          _Row(
            'Açılışta otomatik bağlan',
            'Uygulama her açıldığında motor kendiliğinden çalışır.',
            trailing: GSwitch(
              value: s.autoConnect,
              onChanged: (v) {
                s.autoConnect = v;
                c.changed(restartEngine: false);
              },
            ),
          ),
          _Row(
            'Kapatınca tepsiye küçül',
            'Pencereyi kapatmak motoru durdurmaz. Tamamen çıkmak için tepsi simgesine sağ tıklayın.',
            trailing: GSwitch(
              value: s.closeToTray,
              onChanged: (v) {
                s.closeToTray = v;
                c.changed(restartEngine: false);
              },
            ),
          ),
        ]),
        const SizedBox(height: 18),
        _Group('Gelişmiş', [
          _Row(
            'Windows DNS\'i şifreli yap',
            'Discord ses sunucuları için gerekebilir. Yönetici onayı ister; yalnızca fiziksel bağdaştırıcıları değiştirir.',
            trailing: Wrap(spacing: 8, children: [
              GButton('Uygula', onPressed: () async {
                final ok = await WinSystem.applySecureDns();
                if (mounted) _toast(ok ? 'Windows DNS\'i şifrelendi.' : 'Yönetici onayı verilmedi.');
                setState(() {});
              }),
              if (WinSystem.hasDnsBackup)
                GButton('Geri al', onPressed: () async {
                  _toast(await c.revertDns());
                  setState(() {});
                }),
            ]),
          ),
          _Row(
            'Ayarları sıfırla',
            'Tüm tercihler varsayılana döner. Motor çalışıyorsa durdurulur.',
            trailing: GButton('Sıfırla', danger: true, onPressed: () async {
              await c.resetSettings();
              _port.text = '${c.settings.port}';
              if (mounted) _toast('Ayarlar sıfırlandı.');
            }),
          ),
        ]),
        const SizedBox(height: 22),
        const Text('GinDPI · sürücü yüklemez · yalnızca seçili siteleri etkiler',
            style: TextStyle(color: P.faint, fontSize: 12)),
      ]),
    );
  }
}

InputDecoration _fieldDeco() => InputDecoration(
      isDense: true,
      filled: true,
      fillColor: P.bg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: P.line)),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: P.line)),
      focusedBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: P.accent)),
    );

class _Group extends StatelessWidget {
  const _Group(this.title, this.rows);
  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(title.toUpperCase(),
              style: const TextStyle(color: P.faint, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        ),
        Panel(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              rows[i],
            ],
          ]),
        ),
      ]);
}

class _Row extends StatelessWidget {
  const _Row(this.title, this.desc, {required this.trailing});
  final String title;
  final String desc;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              const SizedBox(height: 3),
              Text(desc, style: const TextStyle(color: P.muted, fontSize: 12.5, height: 1.4)),
            ]),
          ),
          const SizedBox(width: 24),
          trailing,
        ]),
      );
}

class _Drop<T> extends StatelessWidget {
  const _Drop({required this.value, required this.items, required this.onChanged});
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: P.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: P.line),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: items.containsKey(value) ? value : items.keys.first,
            dropdownColor: P.panelHi,
            borderRadius: BorderRadius.circular(12),
            style: const TextStyle(color: P.text, fontSize: 13.5, fontFamily: kFont, fontFamilyFallback: kFontFallback),
            items: [for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      );
}
