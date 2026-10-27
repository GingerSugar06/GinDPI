import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Yuvarlatılmış, ince çerçeveli kart.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color = P.panel,
    this.borderColor = P.line,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor),
        ),
        child: child,
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: const TextStyle(color: P.muted, fontSize: 13.5, height: 1.4)),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      );
}

/// Birincil / ikincil düğme.
class GButton extends StatefulWidget {
  const GButton(this.label, {super.key, this.onPressed, this.icon, this.primary = false, this.busy = false, this.danger = false});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool primary;
  final bool busy;
  final bool danger;

  @override
  State<GButton> createState() => _GButtonState();
}

class _GButtonState extends State<GButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    final fg = widget.primary ? const Color(0xFF1A0E04) : (widget.danger ? P.bad : P.text);
    final bg = widget.primary
        ? (_hover ? P.accentSoft : P.accent)
        : (_hover ? P.panelHi : Colors.transparent);
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: enabled ? 1 : 0.5,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: widget.primary ? Colors.transparent : P.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.busy)
                  SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  )
                else if (widget.icon != null)
                  Icon(widget.icon, size: 17, color: fg),
                if (widget.busy || widget.icon != null) const SizedBox(width: 8),
                Text(widget.label, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Aç/kapa anahtarı (Material Switch'ten daha tutarlı bir görünüm).
class GSwitch extends StatelessWidget {
  const GSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onChanged == null ? null : () => onChanged!(!value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: 46,
            height: 26,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: value ? P.accent : P.line,
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: value ? const Color(0xFF1A0E04) : P.muted,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      );
}

class Chip2 extends StatelessWidget {
  const Chip2(this.text, {super.key, this.color = P.muted, this.onDelete});
  final String text;
  final Color color;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.fromLTRB(10, 4, onDelete == null ? 10 : 4, 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
          if (onDelete != null)
            InkWell(
              onTap: onDelete,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(Icons.close_rounded, size: 14, color: color),
              ),
            ),
        ]),
      );
}

// ===================================================================== Orb

enum OrbMode { off, busy, on }

/// Ana ekrandaki büyük güç düğmesi. Yalnızca bağlıyken/çalışırken animasyon yapar.
class PowerOrb extends StatefulWidget {
  const PowerOrb({super.key, required this.mode, required this.onTap, required this.animate});
  final OrbMode mode;
  final VoidCallback onTap;
  final bool animate;

  @override
  State<PowerOrb> createState() => _PowerOrbState();
}

class _PowerOrbState extends State<PowerOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3600));
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(PowerOrb old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final run = widget.animate && widget.mode != OrbMode.off;
    if (run && !_c.isAnimating) {
      _c.repeat();
    } else if (!run && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = 260.0;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (_, _) => CustomPaint(
                    size: const Size(size, size),
                    painter: _OrbPainter(widget.mode, _c.value, _hover),
                  ),
                ),
              ),
              AnimatedScale(
                scale: _hover ? 1.06 : 1,
                duration: const Duration(milliseconds: 160),
                child: Icon(
                  Icons.power_settings_new_rounded,
                  size: 72,
                  color: switch (widget.mode) {
                    OrbMode.on => P.ok,
                    OrbMode.busy => P.accent,
                    OrbMode.off => _hover ? P.text : P.muted,
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter(this.mode, this.t, this.hover);
  final OrbMode mode;
  final double t;
  final bool hover;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const r = 92.0;
    final tone = switch (mode) {
      OrbMode.on => P.ok,
      OrbMode.busy => P.accent,
      OrbMode.off => P.faint,
    };

    // dış parıltı
    final glowAlpha = switch (mode) {
      OrbMode.on => 0.22,
      OrbMode.busy => 0.18,
      OrbMode.off => hover ? 0.12 : 0.05,
    };
    canvas.drawCircle(
      c,
      r + 34,
      Paint()
        ..shader = RadialGradient(colors: [
          (mode == OrbMode.off ? P.accent : tone).withValues(alpha: glowAlpha),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: c, radius: r + 34)),
    );

    // dalgalar (yalnızca bağlıyken)
    if (mode == OrbMode.on) {
      for (var i = 0; i < 2; i++) {
        final p = (t + i * 0.5) % 1.0;
        canvas.drawCircle(
          c,
          r + 6 + p * 34,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = tone.withValues(alpha: (1 - p) * 0.35),
        );
      }
    }

    // gövde
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.4),
          colors: [Color(0xFF232838), Color(0xFF12141C)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // halka
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromCircle(center: c, radius: r);
    if (mode == OrbMode.busy) {
      ring.color = P.accent;
      canvas.drawArc(rect, t * 2 * math.pi, math.pi * 0.9, false, ring);
      canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 5..color = P.line);
    } else if (mode == OrbMode.on) {
      ring.shader = SweepGradient(
        transform: GradientRotation(t * 2 * math.pi),
        colors: [P.ok, const Color(0xFF2DB5A0), P.ok],
      ).createShader(rect);
      canvas.drawCircle(c, r, ring);
    } else {
      ring.color = hover ? P.muted : P.line;
      canvas.drawCircle(c, r, ring);
    }
  }

  @override
  bool shouldRepaint(_OrbPainter o) => o.mode != mode || o.t != t || o.hover != hover;
}

// ================================================================ Grafik

/// Saniyelik veri akışı grafiği (yumuşak çizgi + degrade dolgu).
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, this.color = P.accent});
  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(painter: _SparkPainter(List.of(values), color), size: Size.infinite),
      );
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.v, this.color);
  final List<double> v;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // ızgara
    final grid = Paint()
      ..color = P.line.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (v.length < 2) return;
    final maxV = math.max(v.reduce(math.max), 4096.0);
    final dx = size.width / (v.length - 1);
    Offset pt(int i) => Offset(i * dx, size.height - (v[i] / maxV) * (size.height - 8) - 4);

    final path = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < v.length; i++) {
      final a = pt(i - 1), b = pt(i);
      final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      path.quadraticBezierTo(a.dx, a.dy, mid.dx, mid.dy);
    }
    path.lineTo(pt(v.length - 1).dx, pt(v.length - 1).dy);

    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.32), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter o) => true;
}

String fmtBytes(num b) {
  if (b < 1024) return '${b.toInt()} B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

