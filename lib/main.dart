import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'bg.dart';
import 'cards.dart';
import 'deco.dart';
import 'fx.dart';
import 'text3d.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Sprites.load();
  // EXPORT_CARDS=1: render the prize-card PNGs instead of running the game.
  final export = !kIsWeb && Platform.environment['EXPORT_CARDS'] == '1';
  runApp(
    MaterialApp(
      title: 'FEVER GACHA 🎰',
      debugShowCheckedModeBanner: false,
      home: export ? const CardExporter() : const PachiGacha(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Expectation levels (期待度). Color convention: blue < green < red < gold < rainbow.
// ---------------------------------------------------------------------------
class Level {
  final String name, yokoku;
  final Color color;
  final Skin skin;
  final int weight, percent;
  final double winRate;
  final List<int> styles; // background styles (see bg.dart)
  final List<Color> pal; // background palette: main, accent, dark
  const Level(
    this.name,
    this.yokoku,
    this.color,
    this.skin,
    this.weight,
    this.percent,
    this.winRate,
    this.styles,
    this.pal,
  );
}

const levels = [
  Level(
    '通常',
    '',
    Color(0xFF2E7BFF),
    Skin.ice,
    45,
    3,
    0.0,
    [2, 1, 5],
    [Color(0xFF1040C0), Color(0xFF40C0FF), Color(0xFF020820)],
  ),
  Level(
    'チャンス',
    'チャンス',
    Color(0xFF19E36B),
    Skin.green,
    30,
    18,
    0.15,
    [0, 3, 5, 6],
    [Color(0xFF0A8040), Color(0xFF80FF60), Color(0xFF021808)],
  ),
  Level(
    '激熱',
    '激熱',
    Color(0xFFFF1A1A),
    Skin.fire,
    17,
    52,
    0.5,
    [0, 1, 4, 6],
    [Color(0xFFC00010), Color(0xFFFF8000), Color(0xFF200000)],
  ),
  Level(
    '超激熱',
    '超激熱',
    Color(0xFFFFC400),
    Skin.gold,
    6,
    85,
    0.85,
    [0, 3, 4],
    [Color(0xFFE09000), Color(0xFFFFF060), Color(0xFF301800)],
  ),
  Level(
    '極',
    '極',
    Color(0xFFFF40FF),
    Skin.rainbow,
    2,
    100,
    1.0,
    [3, 0, 2],
    [Color(0xFFB000FF), Color(0xFF00E0FF), Color(0xFF100020)],
  ),
];
const jackpotStyles = [0, 3, 4];
const jackpotPal = [Color(0xFFFFB000), Color(0xFFFF2060), Color(0xFF301000)];
const losePal = [Color(0xFF404040), Color(0xFF707070), Color(0xFF080808)];

enum Phase { idle, spin, yokoku, reach, freeze, climax, push, result }

/// One queued spin (保留). Its level is decided early so the hold icon can
/// "change color" before the spin plays — a classic pachinko tease.
class Hold {
  final int lv;
  final bool reveal;
  Hold(this.lv, this.reveal);
}

// Auto-screenshot mode for the improvement loop:
//   SHOT_LV=3 SHOT_WIN=1 hamster.app/Contents/MacOS/hamster
// dart:io's Platform is unavailable in browsers, so web never enters shot mode.
final shotLv = kIsWeb
    ? null
    : int.tryParse(Platform.environment['SHOT_LV'] ?? '');
final shotWin = !kIsWeb && Platform.environment['SHOT_WIN'] == '1';
// Optional SHOT_T0 / SHOT_DT / SHOT_N sample a window densely.
double _env(String k, double d) =>
    kIsWeb ? d : double.tryParse(Platform.environment[k] ?? '') ?? d;
final shotTimes = [
  for (var i = 0; i < _env('SHOT_N', 20); i++)
    _env('SHOT_T0', 0.2) + i * _env('SHOT_DT', shotLv == 4 ? 0.62 : 0.5),
];

class PachiGacha extends StatefulWidget {
  const PachiGacha({super.key});
  @override
  State<PachiGacha> createState() => _PachiGachaState();
}

class _PachiGachaState extends State<PachiGacha>
    with SingleTickerProviderStateMixin {
  final rnd = Random();
  final world = FxWorld();
  final frameTick = ValueNotifier(0);
  final shotKey = GlobalKey();
  final player = AudioPlayer();
  final hitPlayer = AudioPlayer(); // short hits that overlap the music
  late final Ticker ticker;

  double clock = 0, phaseStart = 0, prevPt = -1, lastClock = 0;
  Phase phase = Phase.idle;
  int lv = 0, bg = 0, spins = 0, hits = 0;
  List<Color> pal = levels[3].pal;
  int card = 0; // prize card shown after each result (random every spin)
  bool win = false;
  List<int> reels = [7, 7, 7], finalReels = [7, 7, 7];
  final holds = <Hold>[];

  double smashAt = -9, splitAt = -9, kachiAt = -9;
  Offset splitA = Offset.zero, splitB = Offset.zero;

  double get pt => clock - phaseStart;
  Level get level => levels[lv];
  bool get hasReach => finalReels[0] == finalReels[2];
  bool get winning => phase == Phase.result && win;

  // Jackpot zoom: the winning digits rush toward the viewer one at a time
  // (left → right → center), spin, then snap back into their reels.
  static const zoomOrder = [0, 2, 1]; // reel index for each turn
  static const zoomStart = [0.0, 0.55, 1.1];
  static const zoomEnd = [0.55, 1.1, 1.95]; // = moment of the snap
  static const snapDur = 0.14; // how long the "fly back" takes

  /// Seconds since the last digit snapped in (negative while zooming).
  double get celebT => winning ? pt - zoomEnd.last : -1;

  /// Time base for result-screen animations (win waits for the zoom).
  double get rt => win ? celebT : pt;

  // auto-shot state
  double shotStart = -1;
  int shotIdx = 0;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < 4; i++) {
      holds.add(_newHold());
    }
    ticker = createTicker(_tick)..start();
    if (shotLv != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => Future.delayed(const Duration(seconds: 2), () {
          start();
          shotStart = clock;
        }),
      );
    }
  }

  @override
  void dispose() {
    ticker.dispose();
    player.dispose();
    hitPlayer.dispose();
    super.dispose();
  }

  Hold _newHold() {
    var r = rnd.nextInt(levels.fold(0, (s, l) => s + l.weight));
    var l = 0;
    while (r >= levels[l].weight) {
      r -= levels[l].weight;
      l++;
    }
    return Hold(l, l >= 1 && rnd.nextDouble() < 0.5);
  }

  // ---- sound --------------------------------------------------------------
  static const phaseSfx = {
    Phase.spin: 'spin',
    Phase.yokoku: 'yokoku',
    Phase.reach: 'reach',
    Phase.climax: 'climax',
  };
  void _hit(String name) {
    hitPlayer.stop();
    hitPlayer.play(AssetSource('sfx/$name.mp3'));
  }

  void _sfx(String name) {
    player.stop();
    player.play(AssetSource('sfx/$name.mp3'));
  }

  // ---- flow ---------------------------------------------------------------
  void _go(Phase p) {
    phase = p;
    phaseStart = clock;
    prevPt = -1;
    if (p == Phase.freeze) {
      player.stop(); // silence builds tension
      world.clear();
    }
    if (p == Phase.reach && !hasReach) return;
    if (phaseSfx[p] case final s?) _sfx(s);
  }

  /// One-shot trigger: true only on the frame where phase time crosses [s].
  bool at(double s) => prevPt < s && pt >= s;

  /// Periodic trigger every [period] seconds within the phase.
  bool every(double period) =>
      (pt / period).floor() != (prevPt / period).floor();

  void onTap() {
    if (phase == Phase.idle || (phase == Phase.result && pt > 0.6)) start();
    if (phase == Phase.push) _resolve();
  }

  void start() {
    final h = holds.removeAt(0);
    holds.add(_newHold());
    lv = shotLv ?? h.lv;
    win = shotLv != null ? shotWin : rnd.nextDouble() < level.winRate;
    final n = rnd.nextInt(9) + 1;
    finalReels = win ? [n, n, n] : [n, (n + rnd.nextInt(8)) % 9 + 1, n];
    if (!win && lv == 0 && rnd.nextBool()) {
      finalReels = [n, (n + 3) % 9 + 1, (n + 5) % 9 + 1];
    }
    spins++;
    world.clear();
    _go(Phase.spin);
  }

  void _smash() => smashAt = clock;

  void _setBg(List<int> styles, List<Color> p) {
    bg = styles[rnd.nextInt(styles.length)];
    pal = p;
  }

  /// Rapid-cut flicker: any style with any level's palette.
  void _randomBg() {
    bg = rnd.nextInt(bgStyleCount);
    pal = levels[rnd.nextInt(levels.length)].pal;
  }

  void _split(Offset a, Offset b, Color c) {
    splitAt = clock;
    splitA = a;
    splitB = b;
    world.slash(
      world.at(a.dx, a.dy),
      world.at(b.dx, b.dy),
      color: c,
      width: 1.6,
    );
  }

  void _resolve() {
    _smash();
    _finish();
  }

  void _finish() {
    reels = finalReels;
    final pool = win ? winCards : loseCards;
    card = pool[rnd.nextInt(pool.length)];
    if (win) {
      hits++;
      _setBg(jackpotStyles, jackpotPal);
      player.stop(); // the fanfare waits for the final snap
    } else {
      _setBg(levels[0].styles, losePal);
      player.stop();
    }
    _go(Phase.result);
  }

  Ramp get ramp => switch (lv) {
    0 => rampElec,
    2 => rampFire,
    3 => rampGold,
    4 => rampRainbow,
    _ => rampOf(level.color),
  };

  double get yokokuDur => 1.2 + lv * 0.35;
  double get climaxDur => 1.2 + lv * 0.4;

  // ---- per-frame update ---------------------------------------------------
  void _tick(Duration t) {
    clock = t.inMicroseconds / 1e6;
    final dt = (clock - lastClock).clamp(0.0, 0.05);
    lastClock = clock;
    final w = world;
    final center = w.at(0.5, 0.42);
    final reelY = 0.58;

    switch (phase) {
      case Phase.idle:
        if (every(0.5)) {
          w.twinkle(
            Rect.fromLTWH(0, 0, w.size.width, w.size.height),
            3,
            rampGold,
          );
        }
      case Phase.spin:
        reels = List.generate(3, (_) => rnd.nextInt(9) + 1);
        if (at(0)) {
          w.shock(w.at(0.5, reelY), level.color, r: 300);
          if (lv >= 3) _smash();
        }
        if (every(0.1)) {
          w.twinkle(
            Rect.fromLTWH(
              0,
              w.size.height * 0.45,
              w.size.width,
              w.size.height * 0.3,
            ),
            2,
            ramp,
          );
        }
        if (pt > 1.0) _go(lv >= 1 ? Phase.yokoku : Phase.reach);
      case Phase.yokoku:
        reels = List.generate(3, (_) => rnd.nextInt(9) + 1);
        if (at(0)) {
          _smash();
          w.slash(
            w.at(-0.1, 0.1),
            w.at(1.1, 0.5),
            color: level.color,
            width: 1.4,
          );
          _setBg(level.styles, level.pal);
        }
        if (at(0.08)) w.burst(center, 90, ramp);
        if (lv >= 3 && at(0.15)) w.shards(center, 90, rampGold);
        if (lv >= 2 && every(0.18) && pt > 0.4) {
          w.bolt(
            w.at(rr(0, 1), -0.02),
            w.at(rr(0.2, 0.8), rr(0.3, 0.6)),
            color: level.color,
          );
        }
        if (lv >= 2) {
          for (var i = 0; i < 2; i++) {
            w.fire(w.at(rr(0, 1), 1.02), 20, 2, power: 0.8 + lv * 0.15);
          }
        }
        if (at(yokokuDur - 0.15)) {
          _split(const Offset(0, 0.62), const Offset(1, 0.38), level.color);
        }
        if (pt > yokokuDur) _go(Phase.reach);
      case Phase.reach:
        reels = [finalReels[0], rnd.nextInt(9) + 1, finalReels[2]];
        if (!hasReach) {
          if (pt > 0.5) _finish();
          break;
        }
        if (at(0)) {
          w.shock(w.at(0.5, 0.3), Colors.white);
          w.burst(w.at(0.5, 0.3), 80, ramp);
          if (lv >= 1) _smash();
        }
        if (lv >= 1) {
          w.fire(
            w.at(rr(0, 1), 1.02),
            30,
            2,
            power: 0.7 + lv * 0.2,
            ramp: lv == 4 ? rampRainbow : rampFire,
          );
        }
        if (lv >= 2 && every(0.22)) {
          w.bolt(
            w.at(0.18, reelY),
            w.at(0.82, reelY),
            color: level.color,
            width: 1.3,
          );
        }
        if (every(0.15)) {
          w.twinkle(
            Rect.fromLTWH(0, 0, w.size.width, w.size.height * 0.5),
            3,
            ramp,
          );
        }
        if (pt > 2.0) {
          if (lv == 4) {
            _go(Phase.freeze);
          } else if (lv >= 1) {
            _go(Phase.climax);
          } else {
            _finish();
          }
        }
      case Phase.freeze:
        // Everything stops. Then the "glass" cracks and light breaks through.
        if (at(1.5)) {
          w.slash(
            w.at(0.5, 0.42),
            w.at(0.1, 0.1),
            color: Colors.white,
            width: 0.4,
          );
        }
        if (at(1.65)) {
          w.slash(
            w.at(0.5, 0.42),
            w.at(0.95, 0.2),
            color: Colors.white,
            width: 0.4,
          );
        }
        if (at(1.8)) {
          w.slash(
            w.at(0.5, 0.42),
            w.at(0.6, 0.95),
            color: Colors.white,
            width: 0.4,
          );
        }
        if (pt > 2.1) {
          _smash();
          w.burst(center, 300, rampRainbow, speed: 1300);
          w.shards(center, 120, rampRainbow, speed: 1300);
          w.shock(center, Colors.white, r: 900);
          _go(Phase.climax);
        }
      case Phase.climax:
        reels = [finalReels[0], rnd.nextInt(9) + 1, finalReels[2]];
        if (at(0)) {
          _smash();
          w.ringSlash(center, w.size.width * 0.55, level.color);
          w.burst(center, 120, ramp, speed: 1000);
        }
        // fire columns on both edges
        for (final x in [0.03, 0.97]) {
          w.fire(
            w.at(x, 1.0),
            25,
            3,
            power: 1.2 + lv * 0.2,
            ramp: lv == 4 ? rampRainbow : rampFire,
          );
        }
        if (lv >= 2 && every(0.14)) {
          w.bolt(
            w.at(rr(0, 1), -0.02),
            w.at(rr(0, 1), rr(0.4, 0.9)),
            color: lv == 4 ? Colors.white : level.color,
            width: 1.4,
          );
        }
        if (every(0.5) && pt > 0.3) {
          final y = rr(0.2, 0.7);
          _split(
            Offset(0, y + rr(-0.15, 0.15)),
            Offset(1, y + rr(-0.15, 0.15)),
            level.color,
          );
        }
        if (lv >= 3 && every(0.3)) {
          w.shards(w.at(rr(0.2, 0.8), rr(0.2, 0.6)), 30, rampGold);
        }
        if (every(0.07)) _randomBg();
        if (pt > climaxDur) _go(Phase.push);
      case Phase.push:
        if (every(0.08)) {
          w.twinkle(
            Rect.fromCenter(center: w.at(0.5, 0.95), width: 260, height: 120),
            3,
            rampGold,
          );
        }
        if (lv >= 2) w.fire(w.at(rr(0.3, 0.7), 1.02), 40, 1, power: 0.9);
        if (pt > 3.0 || (shotLv != null && pt > 0.7)) _resolve();
      case Phase.result:
        if (win) {
          for (var k = 0; k < 3; k++) {
            // a giant digit appears
            if (at(zoomStart[k])) {
              _hit('zoom');
              w.shock(center, Colors.amber, r: 420);
              w.burst(center, 50, rampGold, speed: 500);
            }
            // カチッ: it lands in its reel
            if (at(zoomEnd[k])) {
              final slot = _slotPos(zoomOrder[k], w.size);
              kachiAt = clock;
              _hit('kachi');
              w.shock(slot, Colors.white, r: 230);
              w.burst(slot, 80, rampGold, speed: 750);
              w.shards(slot, 30, rampGold, speed: 700);
            }
          }
          if (at(zoomEnd.last)) {
            _smash();
            _sfx(lv == 4 ? 'premium' : 'win');
            w.shards(center, 160, rampGold, speed: 1200);
            w.burst(center, 260, lv == 4 ? rampRainbow : rampGold, speed: 1200);
            w.shock(center, Colors.white, r: 900);
            w.ringSlash(center, w.size.width * 0.5, Colors.amber);
          }
          if (celebT < 0) {
            // while zooming: sparkles swirl around the giant digit
            if (every(0.05)) {
              w.twinkle(
                Rect.fromCircle(center: center, radius: 170),
                2,
                rampGold,
              );
            }
            break;
          }
          if (every(0.3)) {
            w.firework(
              w.at(rr(0.1, 0.9), rr(0.08, 0.5)),
              [
                rampGold,
                rampRainbow,
                rampOf(const Color(0xFFFF3060)),
                rampElec,
              ][rnd.nextInt(4)],
            );
          }
          w.fire(
            w.at(rr(0, 1), 1.02),
            30,
            2,
            power: 1.1,
            ramp: lv == 4 ? rampRainbow : rampGold,
          );
          if (every(0.06)) {
            w.twinkle(
              Rect.fromLTWH(0, 0, w.size.width, w.size.height),
              3,
              rampGold,
            );
          }
        } else if (at(0) && lv >= 1) {
          w.ink(w.at(0.5, 0.3), 80);
        }
    }

    // background drifts between styles of the current level while waiting
    if ((phase == Phase.reach || phase == Phase.yokoku) && every(0.6)) {
      _setBg(level.styles, level.pal);
    }
    if (phase == Phase.spin && every(0.09)) {
      _randomBg();
    }

    w.update(dt);
    prevPt = pt;
    _autoShot();
    frameTick.value++;
    setState(() {});
  }

  // ---- screen-level effects (flash / nega / shake / split) ----------------

  /// The PV's "smash cut": 1 frame white → 2 frames negative → color flash.
  double get smashAge => clock - smashAt;

  bool get negative {
    if (smashAge > 0.017 && smashAge < 0.06) return true;
    final p = switch (phase) {
      Phase.climax => 0.05 + lv * 0.025,
      Phase.reach when lv >= 2 => 0.03,
      Phase.result when win && celebT >= 0 && celebT < 0.8 => 0.3,
      _ => 0.0,
    };
    return rnd.nextDouble() < p;
  }

  Color? get flash {
    if (smashAge < 0.017) return Colors.white;
    if (clock - kachiAt < 0.034) return Colors.white.withValues(alpha: 0.55);
    if (smashAge > 0.06 && smashAge < 0.11) {
      return (win && phase == Phase.result ? Colors.amber : level.color)
          .withValues(alpha: 0.7);
    }
    final p = switch (phase) {
      Phase.spin => 0.02 * lv,
      Phase.climax => 0.18 + lv * 0.04,
      Phase.result when win && celebT >= 0 => celebT < 0.8 ? 0.3 : 0.02,
      _ => 0.0,
    };
    if (rnd.nextDouble() >= p) return null;
    final opts = [
      Colors.white,
      Colors.black,
      level.color,
      if (lv >= 3) ...[Colors.amber, Colors.cyan, Colors.pinkAccent],
    ];
    return opts[rnd.nextInt(opts.length)].withValues(alpha: rr(0.5, 0.9));
  }

  Offset get shake {
    var a = max(0.0, 26 * (1 - smashAge / 0.45));
    a += max(0.0, 14 * (1 - (clock - kachiAt) / 0.25));
    a += switch (phase) {
      Phase.climax => 5.0 + lv * 3,
      Phase.reach when lv >= 2 => 2.0,
      Phase.result when win && celebT >= 0 && celebT < 1 => 10.0,
      _ => 0.0,
    };
    return Offset(rr(-a, a), rr(-a, a));
  }

  // ---- auto-screenshot loop ----------------------------------------------
  Future<void> _autoShot() async {
    if (shotStart < 0 || shotIdx >= shotTimes.length) return;
    if (clock - shotStart < shotTimes[shotIdx]) return;
    final i = shotIdx++;
    final boundary =
        shotKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await boundary.toImage(pixelRatio: 1);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('${Directory.systemTemp.path}/hamster_shots')
      ..createSync(recursive: true);
    final name =
        '${dir.path}/lv${lv}_w${win ? 1 : 0}_${i.toString().padLeft(2, '0')}_${phase.name}.png';
    File(name).writeAsBytesSync(data!.buffer.asUint8List());
    debugPrint('SHOT $name');
    if (shotIdx >= shotTimes.length) exit(0);
  }

  // ---- build ---------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: RepaintBoundary(
        key: shotKey,
        child: ColoredBox(
          color: Colors.black,
          child: SafeArea(
            child: Column(
              children: [
                _hud(),
                Expanded(
                  child: GestureDetector(onTap: onTap, child: _screen()),
                ),
                _bottom(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const _invert = ColorFilter.matrix([
    -1, 0, 0, 0, 255, //
    0, -1, 0, 0, 255,
    0, 0, -1, 0, 255,
    0, 0, 0, 1, 0,
  ]);
  static const _grey = ColorFilter.matrix([
    0.3, 0.5, 0.1, 0, 0, //
    0.3, 0.5, 0.1, 0, 0,
    0.3, 0.5, 0.1, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  Widget _screen() {
    final scene = _scene();
    Widget s = scene;
    // 斬: the screen itself is cut in two along the slash and the halves slide apart.
    final splitAge = clock - splitAt;
    if (splitAge < 0.3) {
      final d = 40 * (1 - splitAge / 0.3);
      s = LayoutBuilder(
        builder: (context, c) {
          final a = Offset(splitA.dx * c.maxWidth, splitA.dy * c.maxHeight);
          final b = Offset(splitB.dx * c.maxWidth, splitB.dy * c.maxHeight);
          final dir = (b - a) / (b - a).distance;
          return Stack(
            fit: StackFit.expand,
            children: [
              for (final side in [1.0, -1.0])
                ClipPath(
                  clipper: _HalfClipper(a, b, side),
                  child: Transform.translate(
                    offset:
                        dir * d * side +
                        Offset(-dir.dy, dir.dx) * d * 0.3 * side,
                    child: scene,
                  ),
                ),
            ],
          );
        },
      );
    }
    return ClipRect(
      child: Transform.translate(
        offset: shake,
        child: negative ? ColorFiltered(colorFilter: _invert, child: s) : s,
      ),
    );
  }

  Widget _scene() {
    final frozen = phase == Phase.freeze;
    final lose = phase == Phase.result && !win;
    final hue = (clock * 300) % 360;
    final c = winning ? Colors.amber : level.color;
    Widget bgImg = Transform.scale(
      scale:
          1.15 +
          0.08 * sin(clock * 0.7) +
          (phase == Phase.climax ? 0.12 * sin(pt * 40) : 0),
      child: CustomPaint(painter: BgPainter(bg, clock, pal)),
    );
    if (lose) bgImg = ColorFiltered(colorFilter: _grey, child: bgImg);

    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.hardEdge,
      children: [
        if (!frozen) bgImg else const ColoredBox(color: Colors.black),
        // tint + vignette
        if (!frozen)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 1.0,
                colors: [
                  Colors.black.withValues(alpha: 0.15),
                  Colors.black.withValues(alpha: lose ? 0.85 : 0.7),
                ],
              ),
            ),
          ),
        if (!frozen && !lose && phase != Phase.idle)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  c.withValues(alpha: 0.35),
                  Colors.transparent,
                  Colors.transparent,
                  c.withValues(alpha: 0.45),
                ],
              ),
            ),
          ),
        if (!frozen &&
            (lv >= 1 && phase.index >= Phase.yokoku.index && !lose ||
                winning ||
                phase == Phase.idle))
          CustomPaint(
            painter: RaysPainter(
              clock,
              winning && lv == 4
                  ? HSVColor.fromAHSV(1, hue, 1, 1).toColor()
                  : c,
              alpha: winning ? 0.6 : 0.25,
              count: winning ? 24 : 16,
            ),
          ),
        if (phase == Phase.reach ||
            phase == Phase.climax ||
            phase == Phase.push ||
            winning)
          CustomPaint(
            painter: SpeedLines(
              clock,
              Colors.white.withValues(
                alpha: phase == Phase.climax ? 0.55 : 0.3,
              ),
            ),
          ),
        if (!frozen) ..._bands(c),
        if (!frozen)
          Align(alignment: const Alignment(0, 0.25), child: _reels()),
        // 縦のぼり: vertical brush banners swinging on both edges
        if (!frozen &&
            lv >= 2 &&
            (phase == Phase.reach ||
                phase == Phase.climax ||
                phase == Phase.push))
          for (final (x, txt) in [
            (-0.97, lv >= 3 ? '超激熱' : '激熱'),
            (0.97, '勝負所'),
          ])
            Align(
              alignment: Alignment(x, -0.05),
              child: Transform.rotate(
                angle: sin(clock * 3 + x) * 0.06,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xCC000000),
                    border: Border.all(color: level.color, width: 3),
                    boxShadow: [BoxShadow(color: level.color, blurRadius: 16)],
                  ),
                  child: Text3D(
                    txt.split('').join('\n'),
                    size: 40,
                    font: 'Boku',
                    skin: level.skin,
                    hue: (clock * 300) % 360,
                    depth: 6,
                  ),
                ),
              ),
            ),
        if (phase == Phase.yokoku && lv >= 2 && pt > 0.4)
          Swarm(
            pt - 0.4,
            lv == 4 ? '極熱激' : (lv == 3 ? '激熱金' : '熱'),
            level.skin,
            n: 10 + lv * 6,
          ),
        if (phase == Phase.yokoku)
          Align(
            alignment: const Alignment(0, -0.45),
            child: CutIn(
              pt,
              Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: BgPainter(spins.isEven ? 3 : 0, pt * 2, level.pal),
                  ),
                  Align(
                    alignment: const Alignment(0.72, 0),
                    child: Text3D(
                      '7',
                      size: 130,
                      skin: Skin.blood,
                      ry: pt * 5,
                      rx: 0.2,
                    ),
                  ),
                ],
              ),
              level.yokoku,
              level.color,
              level.skin,
            ),
          ),
        if (!frozen || pt > 1.4)
          CustomPaint(painter: FxPainter(world, frameTick)),
        Align(alignment: const Alignment(0, -0.5), child: _headline()),
        if (winning && celebT < 0) _zoomDigits(),
        if (phase == Phase.result && rt > 0.3) _resultCard(),
        if (winning && rt > 0.9)
          Align(alignment: const Alignment(0.78, 0.62), child: _hanko()),
        if (flash case final f?) ColoredBox(color: f),
      ],
    );
  }

  /// Center of reel [i] in scene coordinates. Mirrors the layout in
  /// [_reels]: a 156px-tall row placed at Alignment(0, 0.25), reels 126px
  /// wide + 5px margin on each side (136px apart).
  Offset _slotPos(int i, Size s) =>
      Offset(s.width / 2 + (i - 1) * 136, (s.height - 156) / 2 * 1.25 + 78);

  /// The giant spinning digit of the current zoom turn.
  Widget _zoomDigits() {
    return LayoutBuilder(
      builder: (context, c) {
        final size = c.biggest;
        final center = Offset(size.width / 2, size.height * 0.42);
        final k = zoomEnd.indexWhere((e) => pt < e);
        if (k < 0 || pt < zoomStart[k]) return const SizedBox();
        final i = zoomOrder[k];
        final local = pt - zoomStart[k];
        final hold = zoomEnd[k] - zoomStart[k] - snapDur;
        final big = k == 2 ? 4.6 : 3.8; // the last one is the biggest

        double scale, ry;
        Offset pos;
        if (local < hold) {
          // rush in from far away (tiny → huge, with overshoot) ...
          scale =
              big * Curves.easeOutBack.transform((local / 0.16).clamp(0, 1));
          // ... while spinning fast and slowing down to face front
          ry = pow(1 - local / hold, 2) * pi * (k == 2 ? 8 : 5);
          pos = center;
        } else {
          // snap: accelerate back down to reel size and into the slot
          final q = Curves.easeInCubic.transform((local - hold) / snapDur);
          scale = big + (1 - big) * q;
          ry = 0;
          pos = Offset.lerp(center, _slotPos(i, size), q)!;
        }
        final skin = lv == 4 ? Skin.rainbow : Skin.gold;
        Widget digit(double dry, double opacity) => Opacity(
          opacity: opacity,
          child: Text3D(
            '${finalReels[i]}',
            size: 104,
            skin: skin,
            hue: (clock * 300) % 360,
            ry: ry + dry,
            rx: 0.15,
          ),
        );
        return Stack(
          children: [
            // dim the world so the digit pops
            ColoredBox(
              color: Colors.black.withValues(
                alpha: 0.45 * (1 - (local - hold).clamp(0, 1)),
              ),
              child: const SizedBox.expand(),
            ),
            Positioned(
              left: pos.dx - 150,
              top: pos.dy - 150,
              width: 300,
              height: 300,
              child: Transform.scale(
                scale: scale,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // halo behind the digit
                    Container(
                      width: 150,
                      height: 150,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [Color(0xCCFFE080), Color(0x00FFA000)],
                        ),
                      ),
                    ),
                    // afterimages trailing the spin
                    if (local < hold) ...[digit(0.5, 0.15), digit(0.25, 0.3)],
                    digit(0, 1),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// The prize card flips in (3D Y-rotation) and lands bottom-left.
  Widget _resultCard() {
    final p = Curves.easeOutBack.transform(((rt - 0.3) / 0.5).clamp(0, 1));
    return Align(
      alignment: const Alignment(-0.75, 0.82),
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.002)
          ..rotateY((1 - p) * pi * 3)
          ..rotateZ(-0.12)
          ..scaleByDouble(0.4 + 0.6 * p, 0.4 + 0.6 * p, 1, 1),
        child: Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: winning ? Colors.amber : Colors.black,
                blurRadius: 30,
              ),
            ],
          ),
          child: Image.asset(cardAsset(card), gaplessPlayback: true),
        ),
      ),
    );
  }

  /// Sub-display emoji: shuffles fast while waiting for the result.
  static const _waitEmoji = [
    '🎰',
    '7️⃣',
    '🔥',
    '⚡',
    '💰',
    '🍒',
    '🔔',
    '💎',
    '⭐',
    '🎯',
  ];
  String get subEmoji => switch (phase) {
    Phase.idle => '🎰',
    Phase.freeze => '❓',
    Phase.result when win => ['🎉', '💰', '👑'][(clock * 6).floor() % 3],
    Phase.result => '😢',
    _ => _waitEmoji[(clock * 14).floor() % _waitEmoji.length],
  };

  /// 確定 seal stamp: slams down from huge, red ink, slightly crooked.
  Widget _hanko() {
    final p = Curves.easeOutBack.transform(((rt - 0.9) / 0.15).clamp(0, 1));
    return Transform.rotate(
      angle: -0.25,
      child: Transform.scale(
        scale: 4 - 3 * p,
        child: Opacity(
          opacity: p.clamp(0, 1),
          child: Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xEEFFF8E8),
              border: Border.all(color: const Color(0xFFE00010), width: 7),
              boxShadow: const [
                BoxShadow(color: Color(0xFFFF2040), blurRadius: 20),
              ],
            ),
            alignment: Alignment.center,
            child: const Text(
              '確定',
              style: TextStyle(
                fontFamily: 'Boku',
                fontSize: 40,
                color: Color(0xFFE00010),
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _bands(Color c) {
    final (top, bottom) = switch (phase) {
      Phase.idle => ('★FEVER GACHA★PUSH START★', '大当り確率 1/2.4 ★ 継続率 ∞% ★'),
      Phase.result when win => (
        '★★大当り★★BONUS★★',
        'おめでとう！ ★ JACKPOT ★ おめでとう！ ★',
      ),
      Phase.result => ('', ''),
      _ when lv >= 3 => ('激熱★超激熱★激熱★', 'CHANCE ★ CHANCE ★ CHANCE ★'),
      _ when lv >= 1 => ('CHANCE★CHANCE★', '期待度UP ★ 期待度UP ★'),
      _ => ('', ''),
    };
    final bgc = Color.lerp(c, Colors.black, 0.25)!;
    return [
      if (top.isNotEmpty)
        Positioned(
          left: 0,
          right: 0,
          top: 4,
          child: Marquee(top, clock, bg: bgc, angle: -0.04),
        ),
      if (bottom.isNotEmpty)
        Positioned(
          left: 0,
          right: 0,
          bottom: 10,
          child: Marquee(bottom, clock, bg: bgc, angle: 0.04, speed: -160),
        ),
    ];
  }

  Widget _headline() {
    final hue = (clock * 300) % 360;
    // "slam": text drops from huge to normal with overshoot in ~0.15s, then holds.
    double slam(double t) =>
        1 + 3 * (1 - Curves.easeOutBack.transform((t / 0.18).clamp(0, 1)));
    switch (phase) {
      case Phase.idle:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎰', style: TextStyle(fontSize: 72)),
            Text3D(
              'FEVER',
              size: 72,
              font: 'Rampart',
              skin: Skin.chrome,
              ry: sin(clock * 1.5) * 0.5,
              rx: 0.2,
            ),
            Text3D(
              'GACHA',
              size: 84,
              skin: Skin.gold,
              ry: sin(clock * 1.5 + 1) * 0.5,
              rx: 0.2,
              rz: -0.06,
            ),
          ],
        );
      case Phase.spin:
      case Phase.yokoku:
        return const SizedBox();
      case Phase.reach:
        if (!hasReach) return const SizedBox();
        // くるくる: spins 3 full turns around Y while flying in, then wobbles.
        final p = Curves.easeOutCubic.transform((pt / 0.7).clamp(0, 1));
        return Transform.scale(
          scale: 0.3 + 0.7 * p,
          child: Text3D(
            'リーチ',
            size: 96,
            skin: level.skin,
            hue: hue,
            ry: (1 - p) * pi * 6 + sin(pt * 3) * 0.35,
            rx: 0.25 * sin(pt * 2),
            rz: -0.08,
          ),
        );
      case Phase.freeze:
        return Text(
          '………',
          style: TextStyle(
            fontFamily: 'Boku',
            fontSize: 50,
            color: Colors.white.withValues(alpha: pt > 0.8 ? 1 : 0),
          ),
        );
      case Phase.climax:
        return Transform.scale(
          scale: slam(pt) + 0.06 * sin(pt * 30),
          child: Text3D(
            '勝負',
            size: 140,
            font: 'Boku',
            skin: lv == 4 ? Skin.rainbow : Skin.fire,
            hue: hue,
            ry: sin(pt * 5) * 0.3,
            rz: -0.1 + sin(pt * 23) * 0.03,
            depth: 30,
          ),
        );
      case Phase.push:
        return Transform.scale(
          scale: slam(pt) * (1 + 0.1 * sin(pt * 25)),
          child: Text3D(
            '押せ!!',
            size: 110,
            font: 'Boku',
            skin: Skin.chrome,
            rz: -0.1,
            ry: sin(pt * 4) * 0.2,
          ),
        );
      case Phase.result:
        if (!win) {
          final drop = Curves.bounceOut.transform((pt / 0.8).clamp(0, 1));
          return Transform.translate(
            offset: Offset(0, -200 * (1 - drop)),
            child: const Text3D(
              '残念…',
              size: 90,
              font: 'Boku',
              skin: Skin.grey,
              rz: 0.08,
            ),
          );
        }
        if (celebT < 0) return const SizedBox();
        final t = celebT;
        final p = Curves.easeOutBack.transform((t / 0.9).clamp(0, 1));
        return Transform.scale(
          scale: 0.2 + 0.8 * p + 0.05 * sin(t * 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (lv == 4)
                Text3D(
                  '超',
                  size: 80,
                  font: 'Boku',
                  skin: Skin.rainbow,
                  hue: hue,
                  ry: sin(t * 2) * 0.4,
                ),
              Text3D(
                '大当り',
                size: 110,
                skin: lv == 4 ? Skin.rainbow : Skin.gold,
                hue: hue,
                ry: (1 - p) * pi * 4 + sin(t * 2.2) * 0.45,
                rx: sin(t * 1.7) * 0.2,
                depth: 34,
              ),
              Text3D(
                'BONUS',
                size: 60,
                font: 'Reggae',
                skin: Skin.chrome,
                ry: -sin(t * 2.2) * 0.5,
                rx: 0.2,
              ),
            ],
          ),
        );
    }
  }

  double _flip(double t) {
    if (t < 0) return 0;
    final c = t % 1.4;
    return c < 0.5
        ? Curves.easeInOutCubic.transform(c / 0.5) * 2 * pi
        : sin(t * 3) * 0.2;
  }

  Widget _reels() {
    final spinning = phase == Phase.spin || phase == Phase.yokoku;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          () {
            final moving =
                spinning ||
                ((phase == Phase.reach ||
                        phase == Phase.climax ||
                        phase == Phase.freeze ||
                        phase == Phase.push) &&
                    i == 1);
            final digit = reels[i];
            final snapAt = zoomEnd[zoomOrder.indexOf(i)];
            if (winning && pt < snapAt) {
              return _reelBox(const SizedBox());
            }
            final skin = winning
                ? (lv == 4 ? Skin.rainbow : Skin.gold)
                : (digit == 7 ? Skin.blood : Skin.chrome);
            Widget num = Text3D(
              '$digit',
              size: 104,
              skin: skin,
              hue: (clock * 300) % 360,
              // win: coin-flip one full turn every 1.4s, staggered per reel,
              // then rest facing front (continuous spinning shows mirrored
              // digits half the time).
              ry: winning
                  ? _flip(celebT - i * 0.15)
                  : (moving ? 0 : sin(clock * 2 + i) * 0.25),
              rx: 0.15,
            );
            if (moving) {
              num = ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 0, sigmaY: 10),
                child: num,
              );
            }
            if (winning) {
              // カチッ: a quick damped wobble right after landing
              final dt = pt - snapAt;
              num = Transform.scale(
                scale: 1 + 0.3 * exp(-dt * 18) * cos(dt * 55),
                child: num,
              );
            }
            return _reelBox(num);
          }(),
      ],
    );
  }

  Widget _reelBox(Widget num) => Container(
    width: 126,
    height: 156,
    margin: const EdgeInsets.symmetric(horizontal: 5),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xEE101020), Color(0xCC303050), Color(0xEE101020)],
      ),
      border: Border.all(color: winning ? Colors.amber : level.color, width: 4),
      boxShadow: [
        BoxShadow(
          color: (winning ? Colors.amber : level.color).withValues(alpha: 0.8),
          blurRadius: 18,
        ),
      ],
    ),
    alignment: Alignment.center,
    child: num,
  );

  Widget _hud() {
    final showMeter =
        phase.index >= Phase.yokoku.index && !(phase == Phase.result && !win);
    final pct = showMeter ? (winning ? 100 : level.percent) : 0;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF300010), Color(0xFF000000), Color(0xFF300010)],
        ),
        border: Border(bottom: BorderSide(color: Color(0xFFFFC000), width: 2)),
      ),
      child: Row(
        children: [
          _stat('回転', '$spins', Skin.chrome),
          const SizedBox(width: 14),
          _stat('大当り', '$hits', Skin.gold),
          const Spacer(),
          const Text(
            '期待度',
            style: TextStyle(
              fontFamily: 'Dela',
              color: Colors.white,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 90,
            height: 14,
            child: Stack(
              children: [
                Container(color: Colors.white12),
                FractionallySizedBox(
                  widthFactor: pct / 100,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Colors.blue,
                          Colors.green,
                          Colors.red,
                          Colors.amber,
                          Colors.purpleAccent,
                        ],
                      ),
                      boxShadow: [BoxShadow(color: level.color, blurRadius: 8)],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 74,
            child: Text3D(
              '$pct%',
              size: 24,
              skin: pct >= 50 ? Skin.fire : Skin.chrome,
              depth: 4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String v, Skin skin) => Row(
    children: [
      Text(
        label,
        style: const TextStyle(
          fontFamily: 'Dela',
          color: Colors.white70,
          fontSize: 12,
        ),
      ),
      const SizedBox(width: 4),
      Text3D(v, size: 24, skin: skin, depth: 4),
    ],
  );

  Widget _bottom() {
    final pushing = phase == Phase.push;
    final pulse = 0.5 + 0.5 * sin(clock * (pushing ? 30 : 8));
    final hue = (clock * 400) % 360;
    return Container(
      height: 130,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF200008), Color(0xFF000000)],
        ),
        border: Border(top: BorderSide(color: Color(0xFFFFC000), width: 2)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          // サブ液晶 (emoji) over the 保留 icons
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 150,
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF001018),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF40E0FF), width: 2),
                  boxShadow: const [
                    BoxShadow(color: Color(0xFF0080FF), blurRadius: 10),
                  ],
                ),
                child: Text(
                  subEmoji,
                  style: const TextStyle(fontSize: 38, height: 1.1),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final (i, h) in holds.indexed)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Transform.scale(
                        scale: h.reveal ? 1.0 + 0.12 * sin(clock * 10 + i) : 1,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                Colors.white,
                                h.reveal
                                    ? (h.lv == 4
                                          ? HSVColor.fromAHSV(
                                              1,
                                              hue,
                                              1,
                                              1,
                                            ).toColor()
                                          : levels[h.lv].color)
                                    : Colors.grey,
                                Colors.black,
                              ],
                              stops: const [0, 0.55, 1],
                            ),
                            boxShadow: h.reveal
                                ? [
                                    BoxShadow(
                                      color: levels[h.lv].color,
                                      blurRadius: 14,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(width: 10),
          // last prize card (changes randomly every spin)
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(color: Color(0xFFFFC000), blurRadius: 8),
              ],
            ),
            child: Image.asset(cardAsset(card), gaplessPlayback: true),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onTap,
            child: Transform.scale(
              scale: pushing ? 1.15 + 0.08 * pulse : 1,
              child: Container(
                width: 112,
                height: 112,
                margin: const EdgeInsets.only(right: 14),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white,
                      pushing
                          ? HSVColor.fromAHSV(1, hue, 1, 1).toColor()
                          : Colors.red,
                      const Color(0xFF400000),
                    ],
                    stops: const [0, 0.45, 1],
                  ),
                  border: Border.all(color: const Color(0xFFFFD040), width: 5),
                  boxShadow: [
                    BoxShadow(
                      color:
                          (pushing
                                  ? HSVColor.fromAHSV(1, hue, 1, 1).toColor()
                                  : Colors.red)
                              .withValues(alpha: 0.4 + 0.6 * pulse),
                      blurRadius: pushing ? 50 : 24,
                      spreadRadius: pushing ? 14 : 4,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text3D(
                  'PUSH',
                  size: 30,
                  skin: Skin.chrome,
                  depth: 5,
                  ry: sin(clock * 3) * 0.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Clips to one side of the infinite line through a–b.
class _HalfClipper extends CustomClipper<Path> {
  final Offset a, b;
  final double side;
  _HalfClipper(this.a, this.b, this.side);
  @override
  Path getClip(Size size) {
    final dir = (b - a) / (b - a).distance;
    final n = Offset(-dir.dy, dir.dx) * side * 5000;
    final p0 = a - dir * 5000, p1 = b + dir * 5000;
    return Path()..addPolygon([p0, p1, p1 + n, p0 + n], true);
  }

  @override
  bool shouldReclip(_) => true;
}
