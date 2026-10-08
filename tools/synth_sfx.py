# Pure-python synth: builds every SFX from sine/saw/square/noise.
import math, random, struct, sys, wave

SR = 22050
OUT = sys.argv[1]
random.seed(1)


def buf(sec):
    return [0.0] * int(SR * sec)


def note(f):  # MIDI -> Hz
    return 440 * 2 ** ((f - 69) / 12)


def osc(kind, ph):
    x = ph % 1.0
    if kind == "sin":
        return math.sin(2 * math.pi * x)
    if kind == "saw":
        return 2 * x - 1
    if kind == "sq":
        return 1.0 if x < 0.5 else -1.0
    if kind == "tri":
        return 4 * abs(x - 0.5) - 1


def tone(b, start, dur, f0, f1=None, kind="sq", vol=0.3, a=0.005, rel=0.05, vib=0.0, detune=0.0):
    """Add a tone with linear pitch glide f0->f1, attack/release envelope."""
    f1 = f1 or f0
    n0, n = int(start * SR), int(dur * SR)
    ph = ph2 = 0.0
    for i in range(n):
        if n0 + i >= len(b):
            break
        t = i / SR
        f = f0 + (f1 - f0) * i / n
        f *= 1 + vib * math.sin(2 * math.pi * 6 * t)
        ph += f / SR
        ph2 += f * (1 + detune) / SR
        env = min(1, t / a) * min(1, (dur - t) / rel)
        s = osc(kind, ph) + (osc(kind, ph2) if detune else 0)
        b[n0 + i] += s * vol * env


def noise(b, start, dur, vol=0.3, decay=8.0, lp=0.5):
    n0, n = int(start * SR), int(dur * SR)
    y = 0.0
    for i in range(n):
        if n0 + i >= len(b):
            break
        y += lp * (random.uniform(-1, 1) - y)  # one-pole lowpass
        b[n0 + i] += y * vol * math.exp(-decay * i / SR)


def kick(b, start, vol=0.9):
    tone(b, start, 0.25, 160, 40, "sin", vol, rel=0.2)
    noise(b, start, 0.03, vol * 0.5, 60, 0.9)


def bell(b, start, f, vol=0.25, dur=0.8):
    for k, (m, v) in enumerate([(1, 1), (2.76, 0.5), (5.4, 0.25)]):
        n0 = int(start * SR)
        for i in range(int(dur * SR)):
            if n0 + i >= len(b):
                break
            t = i / SR
            b[n0 + i] += math.sin(2 * math.pi * f * m * t) * vol * v * math.exp(-5 * t * (1 + k))


def crash(b, start, vol=0.5, dur=1.5):
    noise(b, start, dur, vol, 2.5, 0.95)


def save(name, b):
    peak = max(1e-6, max(abs(x) for x in b))
    g = 0.9 / peak
    with wave.open(f"{OUT}/{name}.wav", "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, x * g)) * 32767)) for x in b))


# spin: quick rising pentatonic blips + whoosh
b = buf(1.0)
penta = [0, 2, 4, 7, 9]
for i in range(16):
    m = 72 + penta[i % 5] + 12 * (i // 5)
    tone(b, i * 0.055, 0.05, note(m), kind="sq", vol=0.18)
noise(b, 0, 1.0, 0.15, 2, 0.2)
save("spin", b)

# yokoku: impact + whoosh + ascending bell chime
b = buf(1.5)
kick(b, 0)
crash(b, 0, 0.3, 0.6)
tone(b, 0, 0.4, 1200, 200, "saw", 0.12, rel=0.3)
for i, m in enumerate([84, 88, 91, 96]):
    bell(b, 0.15 + i * 0.09, note(m), 0.25)
save("yokoku", b)

# reach: siren rising + heartbeat kicks
b = buf(2.0)
tone(b, 0, 2.0, 300, 900, "saw", 0.16, vib=0.03, detune=0.01, rel=0.3)
for t in [0, 0.5, 0.9, 1.25, 1.55, 1.8]:
    kick(b, t, 0.7)
save("reach", b)

# climax: accelerating snare roll + rising bass + final crash
b = buf(3.0)
t = 0.0
gap = 0.16
while t < 2.6:
    noise(b, t, 0.08, 0.5, 30, 0.8)
    t += gap
    gap = max(0.035, gap * 0.92)
tone(b, 0, 2.7, note(36), note(48), "saw", 0.25, detune=0.008, rel=0.1)
crash(b, 2.65, 0.6, 0.35)
kick(b, 2.65)
save("climax", b)


def fanfare(b, root, extra):
    # brass-ish detuned saw: da-da-da-DAAA then chord
    seq = [(0, 0.12, 0), (0.14, 0.12, 4), (0.28, 0.12, 7), (0.42, 0.7, 12)]
    for st, d, iv in seq:
        tone(b, st, d, note(root + iv), kind="saw", vol=0.16, detune=0.006, rel=0.08)
        tone(b, st, d, note(root + iv - 12), kind="sq", vol=0.06)
    for iv in [0, 4, 7, 12, 16]:
        tone(b, 1.2, 2.2, note(root + iv), kind="saw", vol=0.08, detune=0.007, rel=1.0, vib=0.004)
    kick(b, 0.42)
    kick(b, 1.2)
    crash(b, 1.2, 0.5, 2.5)
    for i in range(24):  # sparkling arpeggio on top
        bell(b, 1.2 + i * 0.08, note(root + 24 + [0, 4, 7, 12][i % 4] + (12 if extra and i % 8 > 3 else 0)), 0.12, 0.5)


b = buf(4.0)
fanfare(b, 60, False)
save("win", b)

b = buf(5.0)
for i in range(30):  # premium: shimmering glissando before the fanfare
    bell(b, i * 0.012, note(72 + i), 0.08, 0.4)
sub = buf(4.0)
fanfare(sub, 62, True)
for i, x in enumerate(sub):
    if i + int(0.4 * SR) < len(b):
        b[i + int(0.4 * SR)] += x
save("premium", b)
print("ok")
