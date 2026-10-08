// Real 3D extruded text.
//
// Flutter has no 3D text, so we fake a solid: the same glyphs are drawn
// N times, each layer pushed further back along the Z axis, all under one
// shared perspective + rotation matrix. Seen at an angle, the stacked
// layers form the side walls of the letters — like a stack of coins
// looks like a cylinder.
//
// Performance ("はんこ方式"): laying out and stroking glyphs ~30 times per
// frame is expensive, so each (text, size, font, skin) is rasterized ONCE
// into three images — a white silhouette (tinted per side layer), the
// finished front face, and a pre-blurred glow. Every frame then only
// stamps those images with a perspective matrix: cheap GPU quads.
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

enum Skin { gold, chrome, fire, blood, ice, rainbow, grey, green, purple }

class SkinStyle {
  final List<Color> face; // vertical gradient on the front face
  final List<double>? stops;
  final Color rim; // inner outline
  final Color side; // extrusion color (darkened towards the back)
  final Color glow;
  const SkinStyle(this.face, this.rim, this.side, this.glow, [this.stops]);
}

// Metallic look = a bright highlight band in the middle of a dark gradient,
// imitating a reflection of the sky on a curved surface.
const _skins = {
  Skin.gold: SkinStyle(
    [
      Color(0xFFFFFFF0),
      Color(0xFFFFE27A),
      Color(0xFFC88400),
      Color(0xFFFFF6C8),
      Color(0xFFE09A00),
      Color(0xFF7A4200),
    ],
    Color(0xFFFF8A00),
    Color(0xFF6A3A00),
    Color(0xFFFFD040),
    [0, .3, .48, .52, .75, 1],
  ),
  Skin.chrome: SkinStyle(
    [
      Color(0xFFFFFFFF),
      Color(0xFFD8E4F0),
      Color(0xFF6F8296),
      Color(0xFFFFFFFF),
      Color(0xFFA9B8C8),
      Color(0xFF3C4654),
    ],
    Color(0xFFFF7A00),
    Color(0xFF283040),
    Color(0xFF80C8FF),
    [0, .3, .48, .52, .75, 1],
  ),
  Skin.fire: SkinStyle(
    [
      Color(0xFFFFFFD0),
      Color(0xFFFFE040),
      Color(0xFFFF7A00),
      Color(0xFFE01000),
      Color(0xFF700000),
    ],
    Color(0xFFFFE000),
    Color(0xFF500000),
    Color(0xFFFF5000),
  ),
  Skin.blood: SkinStyle(
    [
      Color(0xFFFF8A8A),
      Color(0xFFFF1020),
      Color(0xFFB00010),
      Color(0xFF500000),
    ],
    Color(0xFFFFFFFF),
    Color(0xFF300000),
    Color(0xFFFF0030),
  ),
  Skin.ice: SkinStyle(
    [
      Color(0xFFFFFFFF),
      Color(0xFFB8F4FF),
      Color(0xFF30A0FF),
      Color(0xFFFFFFFF),
      Color(0xFF1050D0),
      Color(0xFF002080),
    ],
    Color(0xFFFFFFFF),
    Color(0xFF001850),
    Color(0xFF40C0FF),
    [0, .3, .48, .52, .75, 1],
  ),
  Skin.green: SkinStyle(
    [
      Color(0xFFF0FFF0),
      Color(0xFF80FF90),
      Color(0xFF10B040),
      Color(0xFF005020),
    ],
    Color(0xFFFFFFFF),
    Color(0xFF002810),
    Color(0xFF30FF70),
  ),
  Skin.purple: SkinStyle(
    [
      Color(0xFFFFF0FF),
      Color(0xFFE080FF),
      Color(0xFF8020E0),
      Color(0xFF300070),
    ],
    Color(0xFFFFFFFF),
    Color(0xFF200040),
    Color(0xFFC050FF),
  ),
  Skin.grey: SkinStyle(
    [Color(0xFFDDDDDD), Color(0xFF888888), Color(0xFF333333)],
    Color(0xFF555555),
    Color(0xFF111111),
    Color(0x00000000),
  ),
};

const _rainbow = [
  Color(0xFFFF2060),
  Color(0xFFFFA000),
  Color(0xFFFFFF40),
  Color(0xFF40FF80),
  Color(0xFF30C0FF),
  Color(0xFFA040FF),
  Color(0xFFFF40C0),
];

class Text3D extends StatelessWidget {
  final String text;
  final double size;
  final String font;
  final Skin skin;
  final double rx, ry, rz; // rotation (radians) around X / Y / Z
  final double depth; // extrusion depth in px
  final double hue; // animates rainbow skin
  final double opacity;

  /// How much this text will be scaled up by parents (e.g. Transform.scale),
  /// so the cached images are rasterized sharp enough.
  final double res;
  const Text3D(
    this.text, {
    super.key,
    required this.size,
    this.font = 'Dela',
    this.skin = Skin.gold,
    this.rx = 0,
    this.ry = 0,
    this.rz = 0,
    this.depth = -1,
    this.hue = 0,
    this.opacity = 1,
    this.res = 1,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2;
    final r = ((dpr * res).clamp(1.0, 7.0) * 2).round() / 2; // 0.5 steps
    // Rainbow hue is quantized so it can be cached too: 15° steps normally,
    // 60° for big high-res images (each variant costs megabytes).
    final step = r > 3 ? 60 : 15;
    final hueQ = ((hue / step).round() * step) % 360;
    final st = skin == Skin.rainbow
        ? SkinStyle(
            [
              Colors.white,
              for (var i = 0; i < 5; i++)
                HSVColor.fromAHSV(1, (hueQ + i * 50) % 360, 0.9, 1).toColor(),
            ],
            Colors.white,
            const Color(0xFF301050),
            _rainbow[(hueQ ~/ 50) % 7],
          )
        : _skins[skin]!;
    final g = _Glyphs.get(text, size, font, '${skin.name}$hueQ', st, r);
    final d = depth < 0 ? size * 0.22 : depth;
    // Align with factor 1: takes the text's own size when the parent lets
    // it, but if forced bigger (tight constraints) it centers the text
    // instead of pinning it to the top-left corner.
    return Align(
      widthFactor: 1,
      heightFactor: 1,
      child: SizedBox(
        width: g.box.width,
        height: g.box.height,
        child: CustomPaint(
          painter: _Text3DPainter(g, st, d, rx, ry, rz, opacity),
        ),
      ),
    );
  }
}

/// Cached rasterized glyph images for one text configuration.
class _Glyphs {
  final ui.Image side, face, glow;
  final Size box; // logical size of the laid-out text
  final double pad, glowPad; // logical margins baked into the images
  _Glyphs(this.side, this.face, this.glow, this.box, this.pad, this.glowPad);

  // Insertion-ordered map used as a small LRU cache.
  static final _cache = <String, _Glyphs>{};

  static _Glyphs get(
    String text,
    double size,
    String font,
    String skinKey,
    SkinStyle st,
    double res,
  ) {
    final key = '$text|$size|$font|$skinKey|$res';
    final hit = _cache.remove(key);
    if (hit != null) return _cache[key] = hit; // move to most-recent
    if (_cache.length > 400) _cache.remove(_cache.keys.first);

    final style = TextStyle(
      fontFamily: font,
      fontSize: size,
      height: 1.05,
      letterSpacing: -size * 0.04,
    );
    TextPainter tp(Paint fg) => TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(foreground: fg),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    Paint stroke(Color c, double w) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeJoin = StrokeJoin.round
      ..color = c;

    final fill = tp(Paint()..color = Colors.white);
    final box = fill.size;
    final pad = size * 0.14; // room for the thick outline
    final glowPad = size * 0.9; // room for the blur

    ui.Image render(double margin, double scale, void Function(Canvas) draw) {
      final rec = ui.PictureRecorder();
      final c = Canvas(rec)
        ..scale(scale)
        ..translate(margin, margin);
      draw(c);
      return rec.endRecording().toImageSync(
        ((box.width + margin * 2) * scale).ceil(),
        ((box.height + margin * 2) * scale).ceil(),
      );
    }

    // white silhouette; each side layer tints it with its own color
    final side = render(pad, res, (c) {
      tp(stroke(Colors.white, size * 0.2)).paint(c, Offset.zero);
      fill.paint(c, Offset.zero);
    });
    // finished face: black outline, colored rim, metallic gradient
    final face = render(pad, res, (c) {
      tp(stroke(Colors.black, size * 0.2)).paint(c, Offset.zero);
      tp(stroke(st.rim, size * 0.1)).paint(c, Offset.zero);
      tp(
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: st.face,
            stops: st.stops,
          ).createShader(Offset.zero & box),
      ).paint(c, Offset.zero);
    });
    // blur needs no detail, so the glow is rendered at low resolution
    final glow = render(glowPad, max(0.5, res / 3), (c) {
      if (st.glow.a == 0) return;
      for (final sigma in [size * 0.29, size * 0.12]) {
        tp(
          Paint()
            ..color = st.glow
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma),
        ).paint(c, Offset.zero);
      }
    });
    return _cache[key] = _Glyphs(side, face, glow, box, pad, glowPad);
  }
}

class _Text3DPainter extends CustomPainter {
  final _Glyphs g;
  final SkinStyle st;
  final double d, rx, ry, rz, opacity;
  _Text3DPainter(
    this.g,
    this.st,
    this.d,
    this.rx,
    this.ry,
    this.rz,
    this.opacity,
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final c = size.center(Offset.zero);
    final base = Matrix4.identity()
      ..setEntry(3, 2, 0.0012) // perspective strength
      ..rotateX(rx)
      ..rotateY(ry)
      ..rotateZ(rz);
    final n = max(4, (d / 1.6).round());

    void stamp(double z, ui.Image img, double margin, Paint paint) {
      final m = Matrix4.translationValues(c.dx, c.dy, 0)
        ..multiply(base.clone()..translateByDouble(0, 0, z, 1))
        ..translateByDouble(-c.dx, -c.dy, 0, 1);
      canvas.save();
      canvas.transform(m.storage);
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromLTWH(
          -margin,
          -margin,
          g.box.width + margin * 2,
          g.box.height + margin * 2,
        ),
        paint,
      );
      canvas.restore();
    }

    Paint tint(Color col) => Paint()
      ..filterQuality = FilterQuality.low
      ..colorFilter = ColorFilter.mode(
        col.withValues(alpha: col.a * opacity),
        BlendMode.srcIn,
      );
    final facePaint = Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Colors.white.withValues(alpha: opacity);

    // Side walls: start near the rim color at the front and darken towards
    // the back so the extrusion reads as a lit solid block; the backmost
    // layer is black to close the silhouette.
    void side(int i) => stamp(
      d * i / n,
      g.side,
      g.pad,
      tint(
        i == n
            ? Colors.black
            : Color.lerp(Color.lerp(st.rim, st.side, 0.45)!, st.side, i / n)!,
      ),
    );

    if (st.glow.a > 0) {
      stamp(
        d,
        g.glow,
        g.glowPad,
        Paint()..color = Colors.white.withValues(alpha: opacity),
      );
    }
    // Back → front. Turned around (facing < 0) the order flips so the
    // nearest layers still paint last, and a second face at z=d shows a
    // proper (mirrored) face like the back of a coin.
    if (cos(rx) * cos(ry) >= 0) {
      for (var i = n; i >= 1; i--) {
        side(i);
      }
      stamp(0, g.face, g.pad, facePaint);
    } else {
      stamp(0, g.face, g.pad, facePaint);
      for (var i = 1; i <= n; i++) {
        side(i);
      }
      stamp(d, g.face, g.pad, facePaint);
    }
  }

  @override
  bool shouldRepaint(_Text3DPainter o) =>
      o.g != g ||
      o.rx != rx ||
      o.ry != ry ||
      o.rz != rz ||
      o.opacity != opacity ||
      o.d != d;
}
