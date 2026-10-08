// Screen decorations that add "information density": rotating light rays,
// speed lines, scrolling text bands, slanted cut-in panels, kanji swarms.
import 'dart:math';
import 'package:flutter/material.dart';
import 'text3d.dart';

/// Sunburst: alternating wedges rotating around a point, fading outward.
class RaysPainter extends CustomPainter {
  final double t, alpha;
  final Color color;
  final Offset center; // normalized
  final int count;
  RaysPainter(
    this.t,
    this.color, {
    this.alpha = 0.6,
    this.center = const Offset(0.5, 0.42),
    this.count = 18,
  });
  @override
  void paint(Canvas canvas, Size s) {
    final c = Offset(center.dx * s.width, center.dy * s.height);
    final r = s.longestSide * 1.2;
    final paint = Paint()
      ..blendMode = BlendMode.plus
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: alpha),
          color.withValues(alpha: alpha * 0.4),
          color.withValues(alpha: 0),
        ],
        stops: const [0, 0.35, 1],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    final path = Path();
    for (var i = 0; i < count; i++) {
      final a = t * 0.8 + i * 2 * pi / count;
      final w = pi / count * 0.55;
      path
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + cos(a - w) * r, c.dy + sin(a - w) * r)
        ..lineTo(c.dx + cos(a + w) * r, c.dy + sin(a + w) * r)
        ..close();
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_) => true;
}

/// 集中線: thin random wedges converging on the center, re-rolled every frame.
class SpeedLines extends CustomPainter {
  final double t;
  final Color color;
  final int n;
  SpeedLines(this.t, this.color, {this.n = 70});
  @override
  void paint(Canvas canvas, Size s) {
    final c = Offset(s.width / 2, s.height * 0.42);
    final rnd = Random((t * 30).floor());
    final paint = Paint()..color = color;
    for (var i = 0; i < n; i++) {
      final a = rnd.nextDouble() * pi * 2;
      final w = 0.004 + rnd.nextDouble() * 0.016;
      final r0 = s.shortestSide * (0.25 + rnd.nextDouble() * 0.2);
      canvas.drawPath(
        Path()
          ..moveTo(c.dx + cos(a) * r0, c.dy + sin(a) * r0)
          ..lineTo(c.dx + cos(a - w) * 3000, c.dy + sin(a - w) * 3000)
          ..lineTo(c.dx + cos(a + w) * 3000, c.dy + sin(a + w) * 3000)
          ..close(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_) => true;
}

/// Slanted band with a phrase scrolling endlessly (like an LED ticker).
class Marquee extends StatelessWidget {
  final String text;
  final double t, speed, height, angle;
  final Color bg, fg;
  const Marquee(
    this.text,
    this.t, {
    super.key,
    this.speed = 200,
    this.height = 34,
    this.angle = -0.05,
    this.bg = const Color(0xFFD00000),
    this.fg = Colors.white,
  });
  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: 'Dela',
      fontSize: height * 0.62,
      color: fg,
      height: 1,
      shadows: const [Shadow(color: Colors.black, offset: Offset(2, 2))],
    );
    final unit = text.length * height * 0.62 + 30;
    final off = -(t * speed) % unit;
    return SizedBox(
      height: height,
      child: Transform.rotate(
        angle: angle,
        child: OverflowBox(
          maxWidth: 3000,
          maxHeight: height,
          child: Container(
            width: 3000,
            height: height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [bg, Color.lerp(bg, Colors.black, 0.4)!, bg],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              border: const Border.symmetric(
                horizontal: BorderSide(color: Colors.white, width: 2),
              ),
            ),
            child: ClipRect(
              child: Stack(
                children: [
                  for (var i = -1; i < 12; i++)
                    Positioned(
                      left: off + i * unit,
                      top: height * 0.17,
                      child: Text(text, style: style),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Parallelogram clip used by cut-in panels.
class SlantClipper extends CustomClipper<Path> {
  final double slant;
  const SlantClipper(this.slant);
  @override
  Path getClip(Size s) => Path()
    ..moveTo(s.width * slant, 0)
    ..lineTo(s.width, 0)
    ..lineTo(s.width * (1 - slant), s.height)
    ..lineTo(0, s.height)
    ..close();
  @override
  bool shouldReclip(_) => false;
}

/// カットイン: a slanted panel showing a [picture] that slams in from the side,
/// holds while jittering, then shoots out.
class CutIn extends StatelessWidget {
  final double t; // seconds since start
  final Widget picture;
  final String label;
  final Color color;
  final Skin skin;
  const CutIn(
    this.t,
    this.picture,
    this.label,
    this.color,
    this.skin, {
    super.key,
  });
  @override
  Widget build(BuildContext context) {
    final inP = Curves.easeOutBack.transform((t / 0.18).clamp(0, 1));
    final outP = Curves.easeInExpo.transform(((t - 1.1) / 0.25).clamp(0, 1));
    final w = MediaQuery.sizeOf(context).width;
    final x = (1 - inP) * -w + outP * w * 1.2;
    final zoom = 1.3 - 0.3 * (t / 1.3).clamp(0, 1); // slow push-in while held
    return Transform.translate(
      offset: Offset(x, 0),
      child: SizedBox(
        height: 170,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipPath(
              clipper: const SlantClipper(0.12),
              child: Container(
                color: color,
                padding: const EdgeInsets.symmetric(vertical: 6),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ClipPath(
                clipper: const SlantClipper(0.12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Transform.scale(scale: zoom, child: picture),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black87,
                            Colors.transparent,
                            color.withValues(alpha: 0.5),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Align(
              alignment: const Alignment(-0.55, 0),
              child: Text3D(
                label,
                size: 92,
                font: 'Boku',
                skin: skin,
                ry: 0.35 - 0.2 * (t / 1.3).clamp(0, 1),
                rz: -0.08,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 群予告: a swarm of characters flying across the screen at different
/// depths (bigger = closer = faster), like a flock of birds.
class Swarm extends StatelessWidget {
  final double t;
  final String chars;
  final Skin skin;
  final int n;
  const Swarm(this.t, this.chars, this.skin, {super.key, this.n = 26});
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final rnd = Random(7);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < n; i++)
              () {
                final depth = 0.3 + rnd.nextDouble() * 0.9;
                final delay = rnd.nextDouble() * 0.5;
                final y = rnd.nextDouble() * c.maxHeight * 0.9;
                final x =
                    c.maxWidth * 1.1 - (t - delay) * c.maxWidth * 1.4 * depth;
                final size = 26 + 70 * depth;
                return Positioned(
                  left: x,
                  top: y + sin(t * 8 + i) * 12,
                  child: Text3D(
                    chars[i % chars.length],
                    size: size,
                    font: 'Boku',
                    skin: skin,
                    ry: sin(t * 6 + i) * 0.8,
                    rz: sin(t * 3 + i) * 0.3,
                  ),
                );
              }(),
          ],
        );
      },
    );
  }
}

/// Light behind the charging digits: a breathing glow, a horizontal lens
/// flare streak and thin rotating rays. [color] null = rainbow.
class ChargeLightPainter extends CustomPainter {
  final Offset c;
  final double pulse, charge, fade;
  final Color? color;
  ChargeLightPainter(this.c, this.pulse, this.charge, this.fade, this.color);

  @override
  void paint(Canvas canvas, Size s) {
    if (fade <= 0) return;
    final col =
        color ??
        HSVColor.fromAHSV(
          1,
          (pulse * 360 + charge * 720) % 360,
          0.8,
          1,
        ).toColor();
    final add = Paint()..blendMode = BlendMode.plus;
    // breathing glow
    final r = s.width * (0.3 + 0.15 * pulse) * (1 + charge * 0.5);
    canvas.drawCircle(
      c,
      r,
      add
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: (0.1 + 0.3 * pulse) * fade),
            col.withValues(alpha: (0.1 + 0.2 * pulse) * fade),
            col.withValues(alpha: 0),
          ],
          stops: const [0, 0.35, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    // rotating thin rays
    final rays = Paint()
      ..blendMode = BlendMode.plus
      ..color = col.withValues(alpha: (0.15 + 0.3 * charge) * fade);
    for (var i = 0; i < 24; i++) {
      final a = i * pi / 12 + charge * 3;
      final w = 0.015 + 0.02 * pulse;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy)
          ..lineTo(c.dx + cos(a - w) * 1500, c.dy + sin(a - w) * 1500)
          ..lineTo(c.dx + cos(a + w) * 1500, c.dy + sin(a + w) * 1500)
          ..close(),
        rays,
      );
    }
    // lens-flare streak across the row
    final h = (8 + 30 * pulse) * (0.4 + charge);
    final streak = Rect.fromCenter(center: c, width: s.width * 2, height: h);
    canvas.drawRect(
      streak,
      Paint()
        ..blendMode = BlendMode.plus
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.4)
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            Colors.white.withValues(alpha: 0.9 * fade),
            Colors.transparent,
          ],
        ).createShader(streak),
    );
  }

  @override
  bool shouldRepaint(_) => true;
}
