import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../engine/config.dart';
import 'theme.dart';
import 'widgets.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.c, required this.goTo});
  final AppController c;
  final void Function(int) goTo;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth > 860;
      final hero = _Hero(c: c, goTo: goTo);
      final side = _SidePanels(c: c);
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 8, 32, 32),
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: hero),
                  const SizedBox(width: 24),
                  Expanded(flex: 4, child: side),
                ],
              )
            : Column(children: [hero, const SizedBox(height: 24), side]),
      );
    });
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.c, required this.goTo});
  final AppController c;
  final void Function(int) goTo;

  @override
  Widget build(BuildContext context) {
    final mode = switch (c.state) {
      ConnState.on => OrbMode.on,
      ConnState.starting => OrbMode.busy,
      _ => OrbMode.off,
    };
    final title = switch (c.state) {
      ConnState.on => 'Bağlantı yolu açık',
      ConnState.starting => c.statusNote,
      ConnState.error => 'Bir sorun var',
      ConnState.off => 'Kapalı',
    };
    final names = [
      for (final p in servicePresets)
        if (c.settings.services.contains(p.id)) p.name,
      ...c.settings.customDomains,
    ];
    final sub = switch (c.state) {
      ConnState.on =>
        '${names.isEmpty ? "Seçili site yok" : names.join(", ")} bu motor üzerinden gidiyor.\nBankalar, ödeme sayfaları ve diğer her şey doğrudan, dokunulmadan gider.',
      ConnState.starting => 'Lütfen bekleyin…',
      ConnState.error => 'Tanılama sayfası nedeni bulup çözümü önerecek.',
      ConnState.off => 'Başlatmak için düğmeye basın. Yalnızca seçtiğiniz siteler etkilenir.',
    };

    return Panel(
      padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
      child: Column(
        children: [
          PowerOrb(
            mode: mode,
            animate: c.windowVisible,
            onTap: c.isBusy ? () {} : c.toggle,
          ),
          const SizedBox(height: 22),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              title,
              key: ValueKey(title),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
                color: c.state == ConnState.on ? P.ok : (c.state == ConnState.error ? P.bad : P.text),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(sub,
              textAlign: TextAlign.center,
              style: const TextStyle(color: P.muted, fontSize: 14, height: 1.5)),
          const SizedBox(height: 26),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              GButton(
                c.isOn ? 'Bağlantıyı kes' : 'Bağlan',
                primary: !c.isOn,
                busy: c.isBusy,
                icon: c.isOn ? Icons.stop_rounded : Icons.bolt_rounded,
                onPressed: c.toggle,
              ),
              if (c.discords.isNotEmpty)
                GButton(
                  'Discord\'u başlat',
                  icon: Icons.rocket_launch_rounded,
                  onPressed: () async {
                    final msg = await c.launchDiscord();
                    if (msg != null && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                    }
                  },
                ),
            ],
          ),
          if (c.banner != null) ...[
            const SizedBox(height: 22),
            _Banner(text: c.banner!, onFix: () => goTo(2)),
          ],
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.onFix});
  final String text;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: P.warn.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: P.warn.withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded, color: P.warn, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.4))),
          const SizedBox(width: 12),
          GButton('Çözüm bul', onPressed: onFix),
        ]),
      );
}

class _SidePanels extends StatelessWidget {
  const _SidePanels({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final last = c.history.isEmpty ? 0.0 : c.history.last;
    return Column(
      children: [
        Row(children: [
          Expanded(child: _Stat('Giden', fmtBytes(c.upBytes), Icons.north_east_rounded, P.accent)),
          const SizedBox(width: 14),
          Expanded(child: _Stat('Gelen', fmtBytes(c.downBytes), Icons.south_west_rounded, P.ok)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _Stat('Aktif bağlantı', '${c.active}', Icons.hub_rounded, P.accentSoft)),
          const SizedBox(width: 14),
          Expanded(
              child: _Stat('Engellenen', '${c.failed}', Icons.block_rounded,
                  c.failed > 0 ? P.bad : P.muted)),
        ]),
        const SizedBox(height: 14),
        Panel(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Text('Veri akışı', style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${fmtBytes(last)}/sn', style: const TextStyle(color: P.muted, fontSize: 12.5)),
              ]),
              const SizedBox(height: 12),
              SizedBox(height: 110, child: Sparkline(values: c.history)),
              const SizedBox(height: 6),
              const Text('Son 60 saniye', style: TextStyle(color: P.faint, fontSize: 11.5)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Yönlendirilen siteler', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              if (c.hostHits.isEmpty)
                Text(
                  c.isOn ? 'Henüz trafik yok. Discord\'u açın.' : 'Bağlandığınızda burada görünür.',
                  style: const TextStyle(color: P.muted, fontSize: 13),
                )
              else
                for (final e in (c.hostHits.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(5))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Expanded(child: Text(e.key, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                      Text('${e.value}', style: const TextStyle(color: P.muted, fontSize: 12.5)),
                    ]),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Panel(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(color: P.muted, fontSize: 12)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
      );
}
