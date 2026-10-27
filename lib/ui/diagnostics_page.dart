import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../engine/config.dart';
import 'theme.dart';
import 'widgets.dart';

const _fixLabels = {
  'autotune': 'Yöntemi otomatik bul',
  'use_launcher': 'Sistem ayarına dokunma',
  'kill_legacy': 'Eski aracı kapat (yönetici)',
  'dns_fix': 'Windows DNS\'ini şifrele (yönetici)',
};

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key, required this.c});
  final AppController c;

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  AppController get c => widget.c;
  String? _busyFix;

  Future<void> _fix(String id) async {
    setState(() => _busyFix = id);
    final msg = await c.applyFix(id);
    if (!mounted) return;
    setState(() => _busyFix = null);
    if (msg != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final items = c.diag.values.toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 8, 32, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            'Tanılama ve çözümler',
            subtitle: 'Çalışmıyorsa nedenini bulur, çözümü tek tıkla uygular.',
            trailing: GButton('Tanılamayı çalıştır',
                icon: Icons.health_and_safety_rounded,
                primary: true,
                busy: c.diagRunning,
                onPressed: c.runDiagnostics),
          ),
          const SizedBox(height: 22),
          if (items.isEmpty && !c.diagRunning)
            const Panel(
              child: Row(children: [
                Icon(Icons.search_rounded, color: P.muted),
                SizedBox(width: 14),
                Expanded(
                    child: Text('Henüz tanılama yapılmadı. İnternet, DNS, engel durumu ve çakışan araçlar kontrol edilir.',
                        style: TextStyle(color: P.muted, height: 1.4))),
              ]),
            )
          else
            Panel(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _DiagRow(item: items[i], busyFix: _busyFix, onFix: _fix),
                ],
              ]),
            ),
          const SizedBox(height: 28),
          SectionTitle(
            'Yöntem denemesi',
            subtitle: 'Operatörünüzün engelini hangi yöntemin geçtiğini gerçek bağlantıyla ölçer.',
            trailing: GButton('Hepsini dene',
                icon: Icons.speed_rounded,
                busy: c.tuning,
                onPressed: () async {
                  await c.runAutoTune(apply: true);
                  c.changed();
                }),
          ),
          const SizedBox(height: 16),
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(children: [
              _TuneRow(
                  name: 'Yöntemsiz (taban çizgisi)',
                  desc: 'Engel var mı yok mu görmek için',
                  r: c.tune['none'],
                  waiting: c.tuning,
                  selected: false),
              for (final s in strategies) ...[
                const Divider(height: 1),
                _TuneRow(
                  name: s.name,
                  desc: s.description,
                  r: c.tune[s.id],
                  waiting: c.tuning,
                  selected: c.settings.strategy == s.id,
                  best: c.tuneBest == s.id,
                  onUse: () {
                    c.settings.strategy = s.id;
                    c.changed();
                  },
                ),
              ],
            ]),
          ),
          const SizedBox(height: 28),
          const SectionTitle('Sık karşılaşılan durumlar'),
          const SizedBox(height: 14),
          const _Faq('Discord hâlâ açılmıyor',
              '1) Ana ekrandan bağlanın.  2) "Discord\'u başlat" düğmesine basın; bu, Discord\'u doğrudan GinDPI\'ya bağlı açar.  '
                  '3) Olmazsa buradan "Hepsini dene" ile başka yöntem seçtirin.  4) Eski GoodbyeDPI/zapret açıksa kapatın.'),
          const _Faq('Sesli odaya bağlanamıyorum (RTC bağlanıyor…)',
              'Ses trafiği UDP\'dir ve vekilden geçemez; Discord ses sunucusu adreslerini Windows DNS\'inden çözer. '
                  'Tanılama "Sistem DNS\'i zehirlenmiş" diyorsa "Windows DNS\'ini şifrele" düğmesine basın; '
                  'bu işlem yönetici onayı ister ve Ayarlar\'dan geri alınabilir.'),
          const _Faq('Ödeme / banka sayfaları',
              'GinDPI bu siteleri hiç yönlendirmez. Bozulma yaşıyorsanız eski bir DPI aracının hâlâ çalışıp çalışmadığına '
                  'Tanılama\'dan bakın; ya da Servisler\'den gereksiz siteleri kapatın.'),
          const _Faq('Tarayıcıda discord.com açılıyor ama uygulama açılmıyor',
              'Uygulama kendi vekil ayarını kullanıyor olabilir. "Discord\'u başlat" düğmesi bunu kesin çözer.'),
          const _Faq('Antivirüs uyarısı verdi',
              'GinDPI sürücü yüklemez ve yönetici izni istemez. Yerel bir vekil (127.0.0.1) olarak çalıştığı için bazı '
                  'güvenlik yazılımları ilk çalıştırmada bilgi isteyebilir; izin verin.'),
          const _Faq('VPN veya başka bir proxy kullanıyorum',
              'Başka bir proxy ayarı bulunursa GinDPI onu ezmez. Servisler çalışır; yalnızca Discord\'u GinDPI\'dan başlatmanız gerekir.'),
        ],
      ),
    );
  }
}

class _DiagRow extends StatelessWidget {
  const _DiagRow({required this.item, required this.busyFix, required this.onFix});
  final DiagItem item;
  final String? busyFix;
  final Future<void> Function(String) onFix;

  @override
  Widget build(BuildContext context) {
    final col = P.status(item.status);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 22,
          height: 22,
          child: item.status == 'run'
              ? const Padding(
                  padding: EdgeInsets.all(2),
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: P.accent))
              : Icon(
                  switch (item.status) {
                    'ok' => Icons.check_circle_rounded,
                    'warn' => Icons.warning_amber_rounded,
                    _ => Icons.cancel_rounded,
                  },
                  color: col,
                  size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
            const SizedBox(height: 3),
            Text(item.detail, style: const TextStyle(color: P.muted, fontSize: 13, height: 1.45)),
            if (item.fix.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 10, runSpacing: 8, children: [
                for (final f in item.fix)
                  GButton(_fixLabels[f] ?? f, busy: busyFix == f, onPressed: () => onFix(f)),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _TuneRow extends StatelessWidget {
  const _TuneRow({
    required this.name,
    required this.desc,
    required this.r,
    required this.waiting,
    required this.selected,
    this.best = false,
    this.onUse,
  });
  final String name;
  final String desc;
  final TuneResult? r;
  final bool waiting;
  final bool selected;
  final bool best;
  final VoidCallback? onUse;

  @override
  Widget build(BuildContext context) {
    Widget status;
    if (r == null) {
      status = waiting
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: P.accent))
          : const Text('—', style: TextStyle(color: P.faint));
    } else if (r!.ok) {
      status = Text('${r!.ms} ms', style: const TextStyle(color: P.ok, fontWeight: FontWeight.w600));
    } else {
      status = const Text('Çalışmadı', style: TextStyle(color: P.bad, fontSize: 12.5));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
              if (best) ...[const SizedBox(width: 8), const Chip2('En iyi', color: P.ok)],
              if (selected) ...[const SizedBox(width: 8), const Chip2('Kullanımda', color: P.accent)],
            ]),
            const SizedBox(height: 2),
            Text(desc, style: const TextStyle(color: P.muted, fontSize: 12.5)),
          ]),
        ),
        const SizedBox(width: 12),
        SizedBox(width: 80, child: Align(alignment: Alignment.centerRight, child: status)),
        if (onUse != null) ...[
          const SizedBox(width: 12),
          SizedBox(
            width: 84,
            child: selected
                ? const SizedBox.shrink()
                : GButton('Kullan', onPressed: (r?.ok ?? false) || r == null ? onUse : null),
          ),
        ],
      ]),
    );
  }
}

class _Faq extends StatelessWidget {
  const _Faq(this.q, this.a);
  final String q;
  final String a;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          decoration: BoxDecoration(
            color: P.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: P.line),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
              childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              iconColor: P.muted,
              collapsedIconColor: P.muted,
              title: Text(q, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              children: [Text(a, style: const TextStyle(color: P.muted, fontSize: 13, height: 1.55))],
            ),
          ),
        ),
      );
}
