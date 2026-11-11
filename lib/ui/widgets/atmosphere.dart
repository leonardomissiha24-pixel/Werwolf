import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../../theme.dart';

/// Animierter Hintergrund: Mond, ziehender Nebel, kahle Äste und Vignette.
class Atmosphere extends StatefulWidget {
  const Atmosphere({
    super.key,
    required this.child,
    this.bloodMoon = false,
    this.darkness = 0.0,
    this.showMoon = true,
  });

  final Widget child;
  final bool bloodMoon;

  /// 0 = normal, 1 = fast völlig schwarz (Nacht, Augen geschlossen).
  final double darkness;
  final bool showMoon;

  @override
  State<Atmosphere> createState() => _AtmosphereState();
}

class _AtmosphereState extends State<Atmosphere> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) => CustomPaint(
              painter: _SkyPainter(_c.value, widget.bloodMoon, widget.showMoon),
            ),
          ),
        ),
        widget.child,
        IgnorePointer(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 1600),
            curve: Curves.easeInOut,
            color: Colors.black.withValues(alpha: widget.darkness * 0.82),
          ),
        ),
      ],
    );
  }
}

class _SkyPainter extends CustomPainter {
  _SkyPainter(this.t, this.blood, this.moon);
  final double t;
  final bool blood;
  final bool moon;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // Himmel
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: blood
              ? const [Color(0xFF1A0607), Color(0xFF0C0506), AppColors.ink]
              : const [Color(0xFF0E0F16), Color(0xFF09080C), AppColors.ink],
        ).createShader(Offset.zero & size),
    );

    // Mond
    if (moon) {
      final c = Offset(w * 0.74, h * 0.16);
      final r = min(w, h) * 0.13;
      final moonColor = blood ? const Color(0xFF9E2A1E) : AppColors.moon;
      canvas.drawCircle(
          c,
          r * 3.2,
          Paint()
            ..shader = RadialGradient(colors: [
              moonColor.withValues(alpha: 0.22),
              moonColor.withValues(alpha: 0.0),
            ]).createShader(Rect.fromCircle(center: c, radius: r * 3.2)));
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.3, -0.3),
              colors: [moonColor, Color.lerp(moonColor, Colors.black, 0.35)!],
            ).createShader(Rect.fromCircle(center: c, radius: r)));
      // Krater
      final crater = Paint()..color = Colors.black.withValues(alpha: 0.10);
      canvas.drawCircle(c + Offset(-r * 0.3, -r * 0.1), r * 0.22, crater);
      canvas.drawCircle(c + Offset(r * 0.35, r * 0.3), r * 0.15, crater);
      canvas.drawCircle(c + Offset(r * 0.05, r * 0.5), r * 0.09, crater);
    }

    // Kahle Äste von links oben
    final branch = Paint()
      ..color = const Color(0xFF020203)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    void limb(Offset from, double angle, double len, double width, int depth) {
      if (depth == 0 || len < 4) return;
      final sway = sin(t * 2 * pi + depth) * 0.015;
      final to = from + Offset(cos(angle + sway), sin(angle + sway)) * len;
      branch.strokeWidth = width;
      canvas.drawLine(from, to, branch);
      limb(to, angle - 0.45, len * 0.68, width * 0.62, depth - 1);
      limb(to, angle + 0.35, len * 0.62, width * 0.6, depth - 1);
    }

    limb(Offset(-10, h * 0.05), 0.35, w * 0.32, 9, 6);
    limb(Offset(w + 10, h * 0.42), pi - 0.25, w * 0.22, 7, 5);

    // Nebelschwaden
    for (var i = 0; i < 6; i++) {
      final phase = t * 2 * pi + i * 1.7;
      final x = (w * (0.5 + 0.6 * sin(phase * (i.isEven ? 1 : -1) + i))) % (w * 1.4) - w * 0.2;
      final y = h * (0.45 + 0.09 * i) + sin(phase * 2) * 12;
      final rx = w * (0.55 + 0.1 * (i % 3));
      final rect = Rect.fromCenter(center: Offset(x, y), width: rx * 2, height: h * 0.22);
      canvas.drawOval(
          rect,
          Paint()
            ..shader = RadialGradient(colors: [
              (blood ? const Color(0xFF4A1A1A) : const Color(0xFF5B5A63)).withValues(alpha: 0.10),
              Colors.transparent,
            ]).createShader(rect));
    }

    // Vignette
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = RadialGradient(
            radius: 1.0,
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.75)],
            stops: const [0.55, 1.0],
          ).createShader(Offset.zero & size));
  }

  @override
  bool shouldRepaint(_SkyPainter old) => old.t != t || old.blood != blood || old.moon != moon;
}

/// Kantiger, zurückhaltender Knopf mit blutroter Linie.
class GothicButton extends StatelessWidget {
  const GothicButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = true,
    this.dense = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool primary;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final border = primary ? AppColors.bloodBright : AppColors.line;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: primary ? const Color(0xFF2A0B0B) : const Color(0xAA0B090E),
        shape: RoundedRectangleBorder(side: BorderSide(color: border, width: 1)),
        child: InkWell(
          onTap: onPressed,
          splashColor: AppColors.blood.withValues(alpha: 0.4),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: dense ? 14 : 22, vertical: dense ? 10 : 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: dense ? 16 : 18, color: AppColors.bone),
                  const SizedBox(width: 10),
                ],
                Flexible(
                  child: Text(
                    label.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppText.display,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.5,
                      fontSize: dense ? 12 : 14,
                      color: AppColors.bone,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Zierlinie mit Blutstropfen in der Mitte.
class BloodDivider extends StatelessWidget {
  const BloodDivider({super.key, this.width = 180});
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 16,
      child: CustomPaint(painter: _DividerPainter()),
    );
  }
}

class _DividerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final line = Paint()
      ..shader = const LinearGradient(colors: [
        Colors.transparent,
        AppColors.blood,
        Colors.transparent,
      ]).createShader(Offset.zero & size)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), line);
    final cx = size.width / 2;
    final drop = Path()
      ..moveTo(cx, cy - 7)
      ..quadraticBezierTo(cx + 6, cy + 1, cx, cy + 6)
      ..quadraticBezierTo(cx - 6, cy + 1, cx, cy - 7);
    canvas.drawPath(drop, Paint()..color = AppColors.bloodBright);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Rollen-Siegel: Symbol in einem doppelten Ring.
class RoleSigil extends StatelessWidget {
  const RoleSigil({super.key, required this.icon, this.size = 64, this.color = AppColors.bone, this.glow});
  final IconData icon;
  final double size;
  final Color color;
  final Color? glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF0A080B),
        border: Border.all(color: AppColors.line, width: 1),
        boxShadow: [
          if (glow != null) BoxShadow(color: glow!.withValues(alpha: 0.45), blurRadius: size * 0.4),
        ],
      ),
      padding: EdgeInsets.all(size * 0.07),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.blood.withValues(alpha: 0.8), width: 1),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: size * 0.42, color: color),
      ),
    );
  }
}
