// Particle / VFX engine.
//
// Everything that glows (fire, sparks, stars, lightning, slashes) is drawn
// with additive blending (BlendMode.plus): overlapping light adds up and
// turns white-hot, which is what makes pachinko effects look "rich".
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

final _rnd = Random();
double rr(double a, double b) => a + _rnd.nextDouble() * (b - a);

// ---------------------------------------------------------------------------
// Color ramps: a particle's color over its life (0 = born, 1 = dead).
// ---------------------------------------------------------------------------
typedef Ramp = List<Color>;
const Ramp rampFire = [
  Color(0xFFFFF8D0),
  Color(0xFFFFC020),
  Color(0xFFFF4000),
  Color(0xAA900000),
  Color(0x00200000),
];
const Ramp rampGold = [
  Color(0xFFFFFFFF),
  Color(0xFFFFE070),
  Color(0xFFFF9800),
  Color(0x00602000),
];
const Ramp rampElec = [
  Color(0xFFFFFFFF),
  Color(0xFFA0E8FF),
  Color(0xFF6040FF),
  Color(0x00200060),
];
const Ramp rampBlood = [
  Color(0xFFFFFFFF),
  Color(0xFFFF3040),
  Color(0xFF900010),
  Color(0x00200000),
];
const Ramp rampWhite = [
  Color(0xFFFFFFFF),
  Color(0xFFFFFFFF),
  Color(0x00FFFFFF),
];
Ramp rampOf(Color c) => [
  Colors.white,
  c,
  Color.lerp(c, Colors.black, 0.5)!,
  c.withValues(alpha: 0),
];
const Ramp rampRainbow = [
  Color(0xFFFFFFFF),
  Color(0xFFFF2060),
  Color(0xFFFFC000),
  Color(0xFF40FF80),
  Color(0xFF30C0FF),
  Color(0xFFA040FF),
  Color(0x00FF00FF),
];

Color evalRamp(Ramp r, double t) {
  final f = t.clamp(0.0, 0.999) * (r.length - 1);
  final i = f.floor();
  return Color.lerp(r[i], r[i + 1], f - i)!;
}

enum PKind { glow, star, spark, shard, ink }

class Particle {
  double x, y, vx, vy, age = 0, life, size, rot, vr, drag, grav, grow;
  final PKind kind;
  final Ramp ramp;
  Particle(
    this.kind,
    this.x,
    this.y,
    this.vx,
    this.vy, {
    required this.life,
    required this.size,
    required this.ramp,
    this.rot = 0,
    this.vr = 0,
    this.drag = 0,
    this.grav = 0,
    this.grow = 0,
  });
  double get t => age / life;
}

class Bolt {
  final Offset a, b;
  final Color color;
  final double life, width;
  double age = 0;
  List<List<Offset>> paths = [];
  Bolt(this.a, this.b, this.color, this.life, this.width) {
    regen();
  }

  // Midpoint displacement: split the segment, push the midpoint sideways
  // by a random amount, repeat. Halving the push each level gives the
  // jagged-but-directed look of real lightning.
  static List<Offset> _jag(Offset a, Offset b, double rough, int depth) {
    var pts = [a, b];
    var amp = (b - a).distance * rough;
    for (var d = 0; d < depth; d++) {
      final next = <Offset>[pts.first];
      for (var i = 0; i < pts.length - 1; i++) {
        final p = pts[i], q = pts[i + 1];
        final dir = q - p;
        final n = Offset(-dir.dy, dir.dx) / (dir.distance + 1e-6);
        next
          ..add((p + q) / 2 + n * rr(-amp, amp))
          ..add(q);
      }
      pts = next;
      amp *= 0.55;
    }
    return pts;
  }

  void regen() {
    final main = _jag(a, b, 0.25, 6);
    paths = [main];
    for (var i = 0; i < 4; i++) {
      final s = main[_rnd.nextInt(main.length - 1)];
      final ang = (b - a).direction + rr(-1.2, 1.2);
      final len = (b - a).distance * rr(0.15, 0.4);
      paths.add(_jag(s, s + Offset.fromDirection(ang, len), 0.3, 4));
    }
  }
}

class Slash {
  final Offset a, b;
  final Color color;
  final double width;
  double age = 0;
  static const life = 0.45;
  Slash(this.a, this.b, this.color, this.width);
}

class Ring {
  final Offset c;
  final double rx, ry, rot, life;
  final Color color;
  final bool shock; // true = expanding shockwave, false = sweeping slash arc
  double age = 0;
  Ring(this.c, this.rx, this.ry, this.rot, this.color, this.life, this.shock);
}

class FxWorld {
  Size size = const Size(400, 700);
  final ps = <Particle>[];
  final bolts = <Bolt>[];
  final slashes = <Slash>[];
  final rings = <Ring>[];
  double _boltClock = 0;

  Offset at(double nx, double ny) => Offset(nx * size.width, ny * size.height);

  void _add(Particle p) {
    if (ps.length < 5000) ps.add(p);
  }

  void update(double dt) {
    for (final p in ps) {
      p.age += dt;
      p.vx *= 1 - p.drag * dt;
      p.vy = p.vy * (1 - p.drag * dt) + p.grav * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.rot += p.vr * dt;
      p.size += p.grow * dt;
    }
    ps.removeWhere((p) => p.age >= p.life || p.size <= 0);
    _boltClock += dt;
    final re = _boltClock > 0.045; // lightning flickers ~22 times/s
    if (re) _boltClock = 0;
    for (final b in bolts) {
      b.age += dt;
      if (re) b.regen();
    }
    bolts.removeWhere((b) => b.age >= b.life);
    for (final s in slashes) {
      s.age += dt;
    }
    slashes.removeWhere((s) => s.age >= Slash.life);
    for (final r in rings) {
      r.age += dt;
    }
    rings.removeWhere((r) => r.age >= r.life);
  }

  void clear() {
    ps.clear();
    bolts.clear();
    slashes.clear();
    rings.clear();
  }

  // ---- emitters ----------------------------------------------------------

  /// Flames: big soft glows rising and shrinking, plus a few embers.
  void fire(
    Offset p,
    double spread,
    int n, {
    double power = 1,
    Ramp ramp = rampFire,
  }) {
    for (var i = 0; i < n; i++) {
      _add(
        Particle(
          PKind.glow,
          p.dx + rr(-spread, spread),
          p.dy + rr(-6, 6),
          rr(-30, 30),
          rr(-260, -120) * power,
          life: rr(0.35, 0.8),
          size: rr(18, 46) * power,
          grow: -40,
          ramp: ramp,
          drag: 1,
        ),
      );
    }
    if (_rnd.nextDouble() < 0.5) {
      _add(
        Particle(
          PKind.spark,
          p.dx + rr(-spread, spread),
          p.dy,
          rr(-60, 60),
          rr(-500, -250),
          life: rr(0.4, 0.9),
          size: rr(1.5, 3),
          ramp: ramp,
          grav: 200,
        ),
      );
    }
  }

  /// Radial explosion of sparks + glows + stars.
  void burst(
    Offset p,
    int n,
    Ramp ramp, {
    double speed = 700,
    bool stars = true,
  }) {
    for (var i = 0; i < n; i++) {
      final a = rr(0, pi * 2), s = rr(0.2, 1) * speed;
      final k = i % 3 == 0
          ? PKind.glow
          : (stars && i % 3 == 1 ? PKind.star : PKind.spark);
      _add(
        Particle(
          k,
          p.dx,
          p.dy,
          cos(a) * s,
          sin(a) * s,
          life: rr(0.5, 1.4),
          size: k == PKind.spark ? rr(1.5, 3.5) : rr(8, 30),
          ramp: ramp,
          drag: 1.8,
          grav: 160,
          rot: rr(0, 6),
          vr: rr(-8, 8),
        ),
      );
    }
  }

  /// Firework: a clean ring of sparks with trailing stars.
  void firework(Offset p, Ramp ramp) {
    const n = 48;
    final sp = rr(250, 420);
    for (var i = 0; i < n; i++) {
      final a = i / n * pi * 2;
      _add(
        Particle(
          PKind.spark,
          p.dx,
          p.dy,
          cos(a) * sp,
          sin(a) * sp,
          life: rr(0.9, 1.3),
          size: 2.5,
          ramp: ramp,
          drag: 1.4,
          grav: 120,
        ),
      );
      if (i.isEven) {
        _add(
          Particle(
            PKind.star,
            p.dx,
            p.dy,
            cos(a) * sp * 0.7,
            sin(a) * sp * 0.7,
            life: rr(0.8, 1.2),
            size: rr(10, 18),
            ramp: ramp,
            drag: 1.4,
            grav: 90,
            vr: 6,
          ),
        );
      }
    }
    _add(
      Particle(
        PKind.glow,
        p.dx,
        p.dy,
        0,
        0,
        life: 0.35,
        size: 140,
        grow: -300,
        ramp: rampWhite,
      ),
    );
  }

  /// Spinning golden shards (triangles) flung outward.
  void shards(Offset p, int n, Ramp ramp, {double speed = 900}) {
    for (var i = 0; i < n; i++) {
      final a = rr(0, pi * 2), s = rr(0.3, 1) * speed;
      _add(
        Particle(
          PKind.shard,
          p.dx,
          p.dy,
          cos(a) * s,
          sin(a) * s,
          life: rr(0.8, 1.6),
          size: rr(6, 22),
          ramp: ramp,
          rot: rr(0, 6),
          vr: rr(-14, 14),
          drag: 1.2,
          grav: 500,
        ),
      );
    }
  }

  /// Twinkling stars scattered over a rect.
  void twinkle(Rect r, int n, Ramp ramp) {
    for (var i = 0; i < n; i++) {
      _add(
        Particle(
          PKind.star,
          rr(r.left, r.right),
          rr(r.top, r.bottom),
          0,
          rr(-30, 10),
          life: rr(0.3, 0.8),
          size: rr(8, 26),
          ramp: ramp,
          vr: rr(-3, 3),
        ),
      );
    }
  }

  /// Black ink droplets (normal blending) for the "lose" mood.
  void ink(Offset p, int n) {
    for (var i = 0; i < n; i++) {
      _add(
        Particle(
          PKind.ink,
          p.dx + rr(-150, 150),
          p.dy + rr(-40, 40),
          rr(-80, 80),
          rr(-200, 50),
          life: rr(0.8, 1.6),
          size: rr(4, 16),
          ramp: const [Color(0xFF000000), Color(0x00000000)],
          grav: 700,
        ),
      );
    }
  }

  /// Implosion: sparks spawn on a ring and rush INTO [c] — the reverse of
  /// [burst]. Reads as "gathering power" (気を溜める).
  void charge(Offset c, double r, int n, Ramp ramp) {
    for (var i = 0; i < n; i++) {
      final a = rr(0, pi * 2), dist = rr(r * 0.5, r), sp = rr(500, 950);
      final dir = Offset(cos(a), sin(a));
      final p = c + dir * dist;
      _add(
        Particle(
          PKind.spark,
          p.dx,
          p.dy,
          -dir.dx * sp,
          -dir.dy * sp,
          life: dist / sp,
          size: rr(1.5, 3.5),
          ramp: ramp,
        ),
      );
    }
  }

  void bolt(
    Offset a,
    Offset b, {
    Color color = const Color(0xFF8A6CFF),
    double life = 0.25,
    double width = 1,
  }) {
    bolts.add(Bolt(a, b, color, life, width));
    burst(b, 12, rampElec, speed: 400, stars: false);
  }

  void slash(
    Offset a,
    Offset b, {
    Color color = const Color(0xFFFF2040),
    double width = 1,
  }) {
    slashes.add(Slash(a, b, color, width));
    // sparks sprayed perpendicular along the cut
    final d = b - a;
    final n = Offset(-d.dy, d.dx) / d.distance;
    for (var i = 0; i < 70; i++) {
      final p = a + d * rr(0, 1);
      final s = rr(100, 600) * (_rnd.nextBool() ? 1 : -1);
      _add(
        Particle(
          PKind.spark,
          p.dx,
          p.dy,
          n.dx * s + d.dx * 0.4,
          n.dy * s + d.dy * 0.4,
          life: rr(0.2, 0.6),
          size: rr(1.5, 3),
          ramp: rampOf(color),
          drag: 3,
        ),
      );
    }
  }

  void ringSlash(Offset c, double r, Color color) =>
      rings.add(Ring(c, r, r * 0.32, rr(-0.4, 0.4), color, 0.5, false));
  void shock(Offset c, Color color, {double r = 600}) =>
      rings.add(Ring(c, r, r, 0, color, 0.5, true));
}

// ---------------------------------------------------------------------------
// Sprite atlas: soft glow + 4-point star, rendered once at startup and then
// stamped thousands of times per frame with drawAtlas (one GPU call).
// ---------------------------------------------------------------------------
class Sprites {
  static ui.Image? atlas;
  static const glowRect = Rect.fromLTWH(0, 0, 64, 64);
  static const starRect = Rect.fromLTWH(64, 0, 64, 64);

  static Future<void> load() async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawCircle(
      const Offset(32, 32),
      32,
      Paint()
        ..shader = ui.Gradient.radial(
          const Offset(32, 32),
          32,
          [Colors.white, const Color(0x66FFFFFF), const Color(0x00FFFFFF)],
          [0, 0.3, 1],
        ),
    );
    const sc = Offset(96, 32);
    c.drawCircle(
      sc,
      12,
      Paint()
        ..shader = ui.Gradient.radial(sc, 12, [
          Colors.white,
          const Color(0x00FFFFFF),
        ]),
    );
    final star = Path()
      ..moveTo(96, 0)
      ..quadraticBezierTo(98, 30, 128, 32)
      ..quadraticBezierTo(98, 34, 96, 64)
      ..quadraticBezierTo(94, 34, 64, 32)
      ..quadraticBezierTo(94, 30, 96, 0);
    c.drawPath(star, Paint()..color = Colors.white);
    atlas = await rec.endRecording().toImage(128, 64);
  }
}

class FxPainter extends CustomPainter {
  final FxWorld w;
  FxPainter(this.w, Listenable repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    w.size = size;
    final add = Paint()..blendMode = BlendMode.plus;

    // --- rings (shockwaves / arc slashes)
    for (final r in w.rings) {
      final t = r.age / r.life;
      canvas.save();
      canvas.translate(r.c.dx, r.c.dy);
      canvas.rotate(r.rot);
      if (r.shock) {
        final rad = r.rx * Curves.easeOut.transform(t);
        canvas.drawCircle(
          Offset.zero,
          rad,
          Paint()
            ..blendMode = BlendMode.plus
            ..style = PaintingStyle.stroke
            ..strokeWidth = 40 * (1 - t)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
            ..color = r.color.withValues(alpha: 1 - t),
        );
      } else {
        final rect = Rect.fromCenter(
          center: Offset.zero,
          width: r.rx * 2,
          height: r.ry * 2,
        );
        final sweep =
            pi * 2 * Curves.easeOutCubic.transform((t * 2.5).clamp(0, 1));
        final fade = 1 - ((t - 0.5) * 2).clamp(0.0, 1.0);
        for (final (wd, col, blur) in [
          (26.0, r.color, 14.0),
          (8.0, Colors.white, 2.0),
        ]) {
          canvas.drawArc(
            rect,
            -pi / 2,
            sweep,
            false,
            Paint()
              ..blendMode = BlendMode.plus
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeWidth = wd * fade
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur)
              ..color = col.withValues(alpha: fade),
          );
        }
      }
      canvas.restore();
    }

    // --- glows & stars via drawAtlas (batched)
    final atlas = Sprites.atlas;
    if (atlas != null) {
      final tr = <RSTransform>[], rects = <Rect>[], cols = <Color>[];
      for (final p in w.ps) {
        if (p.kind != PKind.glow && p.kind != PKind.star) continue;
        final isStar = p.kind == PKind.star;
        final tw = isStar
            ? 0.6 + 0.4 * sin(p.age * 40 + p.size)
            : 1.0; // twinkle
        final s = max(0.0, p.size) * tw / 32;
        tr.add(
          RSTransform.fromComponents(
            rotation: p.rot,
            scale: s,
            anchorX: 32,
            anchorY: 32,
            translateX: p.x,
            translateY: p.y,
          ),
        );
        rects.add(isStar ? Sprites.starRect : Sprites.glowRect);
        cols.add(evalRamp(p.ramp, p.t));
      }
      canvas.drawAtlas(atlas, tr, rects, cols, BlendMode.modulate, null, add);
    }

    // --- sparks: short streaks along velocity. Each streak is a thin quad
    // (2 triangles) and ALL of them go to the GPU in one drawVertices call,
    // instead of one drawLine call per spark.
    final sPos = <Offset>[], sCol = <Color>[];
    for (final p in w.ps) {
      if (p.kind != PKind.spark) continue;
      final a = Offset(p.x, p.y);
      final b = Offset(p.x - p.vx * 0.03, p.y - p.vy * 0.03);
      final d = b - a;
      final len = d.distance;
      if (len < 0.01) continue;
      final n = Offset(-d.dy, d.dx) / len * (p.size / 2);
      final c = evalRamp(p.ramp, p.t);
      final tail = c.withValues(alpha: 0); // fade out toward the tail
      sPos.addAll([a + n, a - n, b + n, b + n, a - n, b - n]);
      sCol.addAll([c, c, tail, tail, c, tail]);
    }
    if (sPos.isNotEmpty) {
      canvas.drawVertices(
        ui.Vertices(ui.VertexMode.triangles, sPos, colors: sCol),
        BlendMode.dst,
        add,
      );
    }

    // --- shards: spinning triangles in one drawVertices call
    final pos = <Offset>[], vc = <Color>[];
    for (final p in w.ps) {
      if (p.kind != PKind.shard) continue;
      final c = evalRamp(p.ramp, p.t);
      final flip = cos(p.rot * 1.7).abs(); // fake 3D tumble: squash one axis
      for (final (a, rad) in [(0.0, 1.0), (2.3, 0.6), (4.0, 0.8)]) {
        final ang = p.rot + a;
        pos.add(
          Offset(
            p.x + cos(ang) * p.size * rad,
            p.y + sin(ang) * p.size * rad * flip,
          ),
        );
        vc.add(Color.lerp(c, Colors.white, a == 0 ? 0.6 : 0)!);
      }
    }
    if (pos.isNotEmpty) {
      canvas.drawVertices(
        ui.Vertices(ui.VertexMode.triangles, pos, colors: vc),
        BlendMode.dst,
        add,
      );
    }

    // --- ink: normal blending
    for (final p in w.ps) {
      if (p.kind != PKind.ink) continue;
      canvas.drawCircle(
        Offset(p.x, p.y),
        p.size,
        Paint()..color = evalRamp(p.ramp, p.t),
      );
    }

    // --- lightning: wide blurred glow + thin white core
    for (final b in w.bolts) {
      final fade = 1 - b.age / b.life;
      for (final (i, path) in b.paths.indexed) {
        final pth = Path()..addPolygon(path, false);
        final main = i == 0 ? 1.0 : 0.5;
        canvas.drawPath(
          pth,
          Paint()
            ..blendMode = BlendMode.plus
            ..style = PaintingStyle.stroke
            ..strokeWidth = 14 * main * b.width
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9)
            ..color = b.color.withValues(alpha: fade),
        );
        canvas.drawPath(
          pth,
          Paint()
            ..blendMode = BlendMode.plus
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5 * main * b.width
            ..color = Colors.white.withValues(alpha: fade),
        );
      }
    }

    // --- slashes: a lens-shaped blade of light that shoots across, then thins
    for (final s in w.slashes) {
      final grow = Curves.easeOutExpo.transform((s.age / 0.09).clamp(0, 1));
      final fade = 1 - ((s.age - 0.09) / (Slash.life - 0.09)).clamp(0.0, 1.0);
      final d = s.b - s.a;
      final end = s.a + d * grow;
      final n = Offset(-d.dy, d.dx) / d.distance;
      final mid = (s.a + end) / 2;
      for (final (wd, col, blur) in [
        (40.0, s.color, 18.0),
        (12.0, Color.lerp(s.color, Colors.white, 0.5)!, 4.0),
        (4.0, Colors.white, 0.0),
      ]) {
        final h = wd * s.width * (0.3 + 0.7 * fade);
        final path = Path()
          ..moveTo(s.a.dx, s.a.dy)
          ..quadraticBezierTo(
            mid.dx + n.dx * h,
            mid.dy + n.dy * h,
            end.dx,
            end.dy,
          )
          ..quadraticBezierTo(
            mid.dx - n.dx * h,
            mid.dy - n.dy * h,
            s.a.dx,
            s.a.dy,
          );
        canvas.drawPath(
          path,
          Paint()
            ..blendMode = BlendMode.plus
            ..maskFilter = blur > 0
                ? MaskFilter.blur(BlurStyle.normal, blur)
                : null
            ..color = col.withValues(alpha: fade),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_) => true;
}
