import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../app/controller.dart';
import 'diagnostics_page.dart';
import 'home_page.dart';
import 'log_page.dart';
import 'services_page.dart';
import 'settings_page.dart';
import 'theme.dart';

class Shell extends StatefulWidget {
  const Shell({super.key, required this.c});
  final AppController c;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  static const _items = [
    (Icons.shield_moon_rounded, 'Ana ekran'),
    (Icons.apps_rounded, 'Servisler'),
    (Icons.health_and_safety_rounded, 'Tanılama'),
    (Icons.tune_rounded, 'Ayarlar'),
    (Icons.receipt_long_rounded, 'Günlük'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final pages = [
      HomePage(c: c, goTo: (i) => setState(() => _index = i)),
      ServicesPage(c: c),
      DiagnosticsPage(c: c),
      SettingsPage(c: c),
      LogPage(c: c),
    ];
    return Scaffold(
      body: Row(children: [
        _Sidebar(
          index: _index,
          items: _items,
          c: c,
          onTap: (i) => setState(() => _index = i),
        ),
        Expanded(
          child: Column(children: [
            const _TitleBar(),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: KeyedSubtree(key: ValueKey(_index), child: pages[_index]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.index, required this.items, required this.onTap, required this.c});
  final int index;
  final List<(IconData, String)> items;
  final ValueChanged<int> onTap;
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final on = c.isOn;
    return Container(
      width: 220,
      decoration: const BoxDecoration(
        color: P.side,
        border: Border(right: BorderSide(color: P.line)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DragToMoveArea(
          child: SizedBox(
            height: 74,
            child: Row(children: [
              const SizedBox(width: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset('assets/logo.png', width: 34, height: 34, filterQuality: FilterQuality.medium),
              ),
              const SizedBox(width: 12),
              const Text('GinDPI',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
            ]),
          ),
        ),
        for (var i = 0; i < items.length; i++)
          _NavItem(icon: items[i].$1, label: items[i].$2, selected: i == index, onTap: () => onTap(i)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: P.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: P.line),
          ),
          child: Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: on ? P.ok : (c.isBusy ? P.accent : P.faint),
                shape: BoxShape.circle,
                boxShadow: on ? [BoxShadow(color: P.ok.withValues(alpha: 0.6), blurRadius: 8)] : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                on ? 'Korumalı · :${c.port}' : (c.isBusy ? 'Başlıyor…' : 'Kapalı'),
                style: const TextStyle(fontSize: 12.5, color: P.muted),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: sel ? P.accent.withValues(alpha: 0.13) : (_hover ? P.panel : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Icon(widget.icon, size: 20, color: sel ? P.accent : P.muted),
            const SizedBox(width: 12),
            Text(widget.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                  color: sel ? P.text : P.muted,
                )),
          ]),
        ),
      ),
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar();

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: Row(children: [
          const Expanded(child: DragToMoveArea(child: SizedBox.expand())),
          _WinBtn(Icons.remove_rounded, () => windowManager.minimize()),
          _WinBtn(Icons.crop_square_rounded, () async {
            if (await windowManager.isMaximized()) {
              windowManager.unmaximize();
            } else {
              windowManager.maximize();
            }
          }, size: 16),
          _WinBtn(Icons.close_rounded, () => windowManager.close(), danger: true),
          const SizedBox(width: 8),
        ]),
      );
}

class _WinBtn extends StatefulWidget {
  const _WinBtn(this.icon, this.onTap, {this.danger = false, this.size = 19});
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;
  final double size;

  @override
  State<_WinBtn> createState() => _WinBtnState();
}

class _WinBtnState extends State<_WinBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 42,
            height: 34,
            margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 9),
            decoration: BoxDecoration(
              color: _hover ? (widget.danger ? P.bad : P.panelHi) : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(widget.icon, size: widget.size, color: _hover && widget.danger ? Colors.white : P.muted),
          ),
        ),
      );
}
