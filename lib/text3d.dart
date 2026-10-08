// Real 3D extruded text.
//
// Flutter has no 3D text, so we fake a solid: the same glyphs are drawn
// N times, each layer pushed further back along the Z axis, all under one
// shared perspective + rotation matrix. Seen at an angle, the stacked
// layers form the side walls of the letters — like a stack of coins
// looks like a cylinder.
import 'dart:math';
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
  });

  Matrix4 _m(double z) => Matrix4.identity()
    ..setEntry(3, 2, 0.0012) // perspective strength
    ..rotateX(rx)
    ..rotateY(ry)
    ..rotateZ(rz)
    ..translateByDouble(0, 0, z, 1);

  @override
  Widget build(BuildContext context) {
    final st = skin == Skin.rainbow
        ? SkinStyle(
            [
              Colors.white,
              for (var i = 0; i < 5; i++)
                HSVColor.fromAHSV(1, (hue + i * 50) % 360, 0.9, 1).toColor(),
            ],
            Colors.white,
            const Color(0xFF301050),
            _rainbow[(hue ~/ 50) % 7],
          )
        : _skins[skin]!;
    final style = TextStyle(
      fontFamily: font,
      fontSize: size,
      height: 1.05,
      letterSpacing: -size * 0.04,
    );
    final d = depth < 0 ? size * 0.22 : depth;
    final n = max(4, (d / 1.6).round());

    Widget layer(double z, Widget child) =>
        Transform(transform: _m(z), alignment: Alignment.center, child: child);

    Text plain(Color c, {List<Shadow>? shadows}) => Text(
      text,
      textAlign: TextAlign.center,
      softWrap: false,
      style: style.copyWith(color: c, shadows: shadows),
    );
    Text stroke(Color c, double w) => Text(
      text,
      textAlign: TextAlign.center,
      softWrap: false,
      style: style.copyWith(
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..strokeJoin = StrokeJoin.round
          ..color = c,
      ),
    );

    // back → front. When the text has turned around (facing < 0) the
    // order flips so the nearest layers are still painted last.
    final facing = cos(rx) * cos(ry);
    final sides = <Widget>[
      for (var i = n; i >= 1; i--)
        // Side walls: start near the rim color at the front and darken
        // towards the back, so the extrusion reads as a lit solid block
        // instead of a black blob. The stroke matches the front outline
        // width so the silhouette stays continuous.
        () {
          final c = Color.lerp(
            Color.lerp(st.rim, st.side, 0.45)!,
            st.side,
            i / n,
          )!;
          return layer(
            d * i / n,
            Stack(
              alignment: Alignment.center,
              children: [
                stroke(i == n ? Colors.black : c, size * 0.2),
                plain(c),
              ],
            ),
          );
        }(),
    ];
    final front = layer(
      0,
      Stack(
        alignment: Alignment.center,
        children: [
          stroke(Colors.black, size * 0.2), // outer black outline
          stroke(st.rim, size * 0.1), // colored inner rim
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (r) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: st.face,
              stops: st.stops,
            ).createShader(r),
            child: plain(Colors.white),
          ),
        ],
      ),
    );
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // glow halo behind everything
        if (st.glow.a > 0)
          layer(
            d,
            plain(
              Colors.transparent,
              shadows: [
                Shadow(color: st.glow, blurRadius: size * 0.5),
                Shadow(color: st.glow, blurRadius: size * 0.2),
              ],
            ),
          ),
        if (facing >= 0) ...[
          ...sides,
          front,
        ] else ...[
          front,
          ...sides.reversed,
        ],
      ],
    );
  }
}
