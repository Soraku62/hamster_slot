// Procedural backgrounds. Every background is drawn from math each frame,
// so the app ships no third-party images.
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

const bgStyleCount = 7;

class BgPainter extends CustomPainter {
  final int style;
  final double t;
  final List<Color> pal; // 3 colors: main, accent, dark
  BgPainter(this.style, this.t, this.pal);

  @override
  void paint(Canvas canvas, Size s) {
    final c = Offset(s.width / 2, s.height * 0.42);
    final r = s.longestSide * 1.3;
    canvas.drawRect(Offset.zero & s, Paint()..color = pal[2]);
    switch (style % bgStyleCount) {
      case 0:
        _spiral(canvas, c, r);
      case 1:
        _tunnel(canvas, c, r);
      case 2:
        _warp(canvas, s, c);
      case 3:
        _kaleido(canvas, c, r);
      case 4:
        _synth(canvas, s);
      case 5:
        _halftone(canvas, s, c);
      default:
        _plasma(canvas, s);
    }
  }

  /// Twisted wedges: each arm's angle grows with radius → a spiral.
  void _spiral(Canvas canvas, Offset c, double r) {
    const arms = 12;
    for (var i = 0; i < arms; i++) {
      final path = Path()..moveTo(c.dx, c.dy);
      final a0 = i * 2 * pi / arms + t * 1.5;
      for (var k = 0; k <= 24; k++) {
        final rad = r * k / 24;
        final a = a0 + rad / r * 2.2;
        path.lineTo(c.dx + cos(a) * rad, c.dy + sin(a) * rad);
      }
      for (var k = 24; k >= 0; k--) {
        final rad = r * k / 24;
        final a = a0 + pi / arms + rad / r * 2.2;
        path.lineTo(c.dx + cos(a) * rad, c.dy + sin(a) * rad);
      }
      canvas.drawPath(path, Paint()..color = i.isEven ? pal[0] : pal[1]);
    }
    _glow(canvas, c, r * 0.35, Colors.white);
  }

  /// Rotating polygons rushing toward the viewer (hyperspace tunnel).
  void _tunnel(Canvas canvas, Offset c, double r) {
    for (var i = 14; i >= 0; i--) {
      final z = ((i + (t * 2.2) % 1) / 14); // 0 near center → 1 edge
      final rad = r * pow(z, 2.2);
      final sides = 6;
      final rot = t * 0.6 + i * 0.18;
      final path = Path();
      for (var k = 0; k < sides; k++) {
        final a = rot + k * 2 * pi / sides;
        final p = c + Offset(cos(a), sin(a)) * rad.toDouble();
        k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()..color = Color.lerp(i.isEven ? pal[0] : pal[1], pal[2], 1 - z)!,
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 + 6 * z
          ..color = Colors.white.withValues(alpha: 0.7 * z),
      );
    }
  }

  /// Stars streaking outward from the center (light-speed jump).
  void _warp(Canvas canvas, Size s, Offset c) {
    _glow(canvas, c, s.shortestSide * 0.6, pal[0]);
    final rnd = Random(3);
    final p = Paint()
      ..blendMode = BlendMode.plus
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 260; i++) {
      final a = rnd.nextDouble() * 2 * pi;
      final z = (rnd.nextDouble() + t * (0.5 + rnd.nextDouble())) % 1;
      final d0 = pow(z, 2.5) * s.longestSide;
      final d1 = d0 * 0.75;
      final dir = Offset(cos(a), sin(a));
      p
        ..strokeWidth = 1 + 4 * z
        ..color = Color.lerp(
          pal[1],
          Colors.white,
          rnd.nextDouble(),
        )!.withValues(alpha: z);
      canvas.drawLine(c + dir * d1.toDouble(), c + dir * d0.toDouble(), p);
    }
  }

  /// Layered rotating stars (kaleidoscope).
  void _kaleido(Canvas canvas, Offset c, double r) {
    for (var layer = 6; layer >= 1; layer--) {
      final rad = r * layer / 6;
      final pts = 8 + layer;
      final rot = t * (layer.isEven ? 0.7 : -0.5);
      final path = Path();
      for (var k = 0; k < pts * 2; k++) {
        final a = rot + k * pi / pts;
        final rr = k.isEven ? rad : rad * 0.62;
        final p = c + Offset(cos(a), sin(a)) * rr;
        k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()..color = [pal[0], pal[1], pal[2]][layer % 3],
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.white54,
      );
    }
    _glow(canvas, c, r * 0.3, Colors.white);
  }

  /// Synthwave: striped sun + perspective grid floor scrolling toward us.
  void _synth(Canvas canvas, Size s) {
    final horizon = s.height * 0.55;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, s.width, horizon),
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(0, horizon), [
          pal[2],
          pal[0],
        ]),
    );
    final sun = Offset(s.width / 2, horizon - s.width * 0.05);
    final sr = s.width * 0.38;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, s.width, horizon));
    canvas.drawCircle(
      sun,
      sr,
      Paint()
        ..shader = ui.Gradient.linear(
          sun - Offset(0, sr),
          sun + Offset(0, sr),
          [Colors.yellow, pal[1]],
        ),
    );
    for (var i = 0; i < 7; i++) {
      final y = sun.dy + sr * (0.1 + i * 0.13) - (t * 20) % (sr * 0.13);
      canvas.drawRect(
        Rect.fromLTWH(0, y, s.width, 3.0 + i * 1.5),
        Paint()..color = pal[0],
      );
    }
    canvas.restore();
    canvas.drawRect(
      Rect.fromLTWH(0, horizon, s.width, s.height - horizon),
      Paint()..color = pal[2],
    );
    final grid = Paint()
      ..color = pal[1]
      ..strokeWidth = 2;
    for (var i = -12; i <= 12; i++) {
      canvas.drawLine(
        Offset(s.width / 2 + i * 8, horizon),
        Offset(s.width / 2 + i * s.width * 0.25, s.height),
        grid,
      );
    }
    for (var i = 0; i < 12; i++) {
      final z = (i + (t * 2) % 1) / 12;
      final y = horizon + (s.height - horizon) * pow(z, 2.4);
      canvas.drawLine(
        Offset(0, y.toDouble()),
        Offset(s.width, y.toDouble()),
        grid,
      );
    }
  }

  /// Comic halftone dots pulsing outward in a ring wave.
  void _halftone(Canvas canvas, Size s, Offset c) {
    canvas.drawRect(
      Offset.zero & s,
      Paint()
        ..shader = ui.Gradient.radial(
          c,
          s.longestSide * 0.7,
          [pal[1], pal[0], pal[2]],
          [0, 0.5, 1],
        ),
    );
    const step = 22.0;
    final p = Paint()..color = pal[2].withValues(alpha: 0.75);
    for (var y = 0.0; y < s.height + step; y += step) {
      for (var x = 0.0; x < s.width + step; x += step) {
        final d = (Offset(x, y) - c).distance;
        final rad = step * 0.5 * (0.5 + 0.5 * sin(d / 40 - t * 6));
        canvas.drawCircle(Offset(x, y), rad, p);
      }
    }
  }

  /// Big drifting color blobs (cheap "plasma").
  void _plasma(Canvas canvas, Size s) {
    for (var i = 0; i < 7; i++) {
      final p = Offset(
        s.width * (0.5 + 0.45 * sin(t * (0.7 + i * 0.13) + i * 2)),
        s.height * (0.45 + 0.4 * cos(t * (0.5 + i * 0.11) + i)),
      );
      _glow(
        canvas,
        p,
        s.shortestSide * 0.7,
        [pal[0], pal[1], Colors.white][i % 3],
      );
    }
  }

  void _glow(Canvas canvas, Offset c, double r, Color col) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(c, r, [
          col.withValues(alpha: 0.8),
          col.withValues(alpha: 0),
        ]),
    );
  }

  @override
  bool shouldRepaint(_) => true;
}
