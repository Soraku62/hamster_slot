// Prize cards (景品カード). The PNGs in assets/cards/ were rendered by this
// file itself: run the macOS app with EXPORT_CARDS=1 and it draws each card,
// saves it as an image, and quits. So every image is our own artwork.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'bg.dart';
import 'text3d.dart';

class CardSpec {
  final String emblem, label, font;
  final Skin skin;
  final int style;
  final List<Color> pal;
  final bool win;
  const CardSpec(
    this.emblem,
    this.label,
    this.skin,
    this.style,
    this.pal, {
    this.font = 'Dela',
    this.win = true,
  });
}

const cards = [
  CardSpec('7', 'SEVEN', Skin.blood, 0, [
    Color(0xFFC00010),
    Color(0xFFFF8000),
    Color(0xFF200000),
  ]),
  CardSpec('★', 'STAR', Skin.gold, 3, [
    Color(0xFFE09000),
    Color(0xFFFFF060),
    Color(0xFF301800),
  ]),
  CardSpec('炎', 'FIRE', Skin.fire, 1, [
    Color(0xFFFF4000),
    Color(0xFFFFC000),
    Color(0xFF200000),
  ], font: 'Boku'),
  CardSpec('雷', 'THUNDER', Skin.purple, 2, [
    Color(0xFF6020FF),
    Color(0xFF80E0FF),
    Color(0xFF080018),
  ], font: 'Boku'),
  CardSpec('斬', 'SLASH', Skin.ice, 5, [
    Color(0xFF1060E0),
    Color(0xFF60F0FF),
    Color(0xFF000820),
  ], font: 'Boku'),
  CardSpec('極', 'PREMIUM', Skin.rainbow, 3, [
    Color(0xFFB000FF),
    Color(0xFF00E0FF),
    Color(0xFF100020),
  ], font: 'Boku'),
  CardSpec('BAR', 'BAR', Skin.chrome, 4, [
    Color(0xFFFF2080),
    Color(0xFF00E0FF),
    Color(0xFF100030),
  ]),
  CardSpec(
    '残',
    'MISS',
    Skin.grey,
    6,
    [Color(0xFF404040), Color(0xFF707070), Color(0xFF080808)],
    font: 'Boku',
    win: false,
  ),
  CardSpec(
    '凶',
    'MISS',
    Skin.grey,
    1,
    [Color(0xFF303040), Color(0xFF606070), Color(0xFF050508)],
    font: 'Boku',
    win: false,
  ),
];
String cardAsset(int i) => 'assets/cards/card_$i.png';
final winCards = [
  for (var i = 0; i < cards.length; i++)
    if (cards[i].win) i,
];
final loseCards = [
  for (var i = 0; i < cards.length; i++)
    if (!cards[i].win) i,
];

/// The artwork of one card, drawn live (used only for exporting).
class CardArt extends StatelessWidget {
  final CardSpec c;
  const CardArt(this.c, {super.key});
  @override
  Widget build(BuildContext context) {
    final edge = c.win ? const Color(0xFFFFD040) : const Color(0xFF888888);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: edge, width: 10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: BgPainter(c.style, 1.3, c.pal)),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [Colors.transparent, Color(0xAA000000)],
                ),
              ),
            ),
            Align(
              alignment: const Alignment(0, -0.15),
              child: Text3D(
                c.emblem,
                size: c.emblem.length > 1 ? 120 : 200,
                font: c.font,
                skin: c.skin,
                hue: 40,
                ry: -0.35,
                rx: 0.2,
                rz: -0.06,
              ),
            ),
            Align(
              alignment: const Alignment(0, 0.85),
              child: Text3D(
                c.label,
                size: 46,
                font: 'Reggae',
                skin: c.win ? Skin.chrome : Skin.grey,
                depth: 6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// EXPORT_CARDS=1 mode: shows each card, snapshots it to PNG, then exits.
class CardExporter extends StatefulWidget {
  const CardExporter({super.key});
  @override
  State<CardExporter> createState() => _CardExporterState();
}

class _CardExporterState extends State<CardExporter> {
  final key = GlobalKey();
  int i = 0;

  @override
  void initState() {
    super.initState();
    _next();
  }

  Future<void> _next() async {
    await Future.delayed(const Duration(milliseconds: 800)); // let fonts settle
    final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 1);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('${Directory.systemTemp.path}/cards')
      ..createSync(recursive: true);
    File(
      '${dir.path}/card_$i.png',
    ).writeAsBytesSync(data!.buffer.asUint8List());
    debugPrint('CARD ${dir.path}/card_$i.png');
    if (++i >= cards.length) exit(0);
    setState(() {});
    _next();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black,
    child: Center(
      child: RepaintBoundary(
        key: key,
        child: SizedBox(width: 400, height: 400, child: CardArt(cards[i])),
      ),
    ),
  );
}
