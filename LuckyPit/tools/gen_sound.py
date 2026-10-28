# -*- coding: utf-8 -*-
"""Synthesised sound effects (8 kHz, 8-bit mono PCM WAV) and a MIDI loop."""
import math
import random
import struct

RATE = 8000


def wav(path, samples):
    data = bytes(max(0, min(255, int(128 + s * 127))) for s in samples)
    with open(path, 'wb') as f:
        f.write(b'RIFF' + struct.pack('<I', 36 + len(data)) + b'WAVE')
        f.write(b'fmt ' + struct.pack('<IHHIIHH', 16, 1, 1, RATE, RATE, 1, 8))
        f.write(b'data' + struct.pack('<I', len(data)) + data)


def env(i, n, a=0.01, r=0.3):
    t = i / RATE
    dur = n / RATE
    if t < a:
        return t / a
    rel = dur * r
    if t > dur - rel:
        return max(0.0, (dur - t) / rel)
    return 1.0


def tone(freq, dur, vol=0.6, shape='sq', a=0.005, r=0.4, slide=0.0, vib=0.0):
    n = int(dur * RATE)
    out = []
    ph = 0.0
    for i in range(n):
        f = freq * (1 + slide * i / n) * (1 + vib * math.sin(i / RATE * 30))
        ph += f / RATE
        x = ph % 1.0
        if shape == 'sq':
            v = 1.0 if x < 0.5 else -1.0
        elif shape == 'tri':
            v = 4 * abs(x - 0.5) - 1
        elif shape == 'saw':
            v = 2 * x - 1
        else:
            v = math.sin(2 * math.pi * x)
        out.append(v * vol * env(i, n, a, r))
    return out


def mix(*tracks):
    n = max(len(t) for t in tracks)
    return [max(-1, min(1, sum(t[i] for t in tracks if i < len(t)))) for i in range(n)]


def cat(*parts):
    out = []
    for p in parts:
        out += p
    return out


def noise(dur, vol=0.5, r=0.9, seed=1, lp=0.5):
    rnd = random.Random(seed)
    n = int(dur * RATE)
    out = []
    prev = 0
    for i in range(n):
        v = rnd.uniform(-1, 1)
        prev = prev + (v - prev) * lp
        out.append(prev * vol * env(i, n, 0.002, r))
    return out


def silence(dur):
    return [0.0] * int(dur * RATE)


def build(outdir):
    # reels start: rising ratchet whirr
    clicks = []
    for k in range(14):
        clicks += noise(0.012, 0.6, 0.9, seed=k, lp=0.8) + silence(max(0.004, 0.03 - k * 0.0018))
    spin = mix(clicks, tone(90, len(clicks) / RATE, 0.25, 'saw', 0.05, 0.3, slide=1.2))
    wav(outdir + '/s_spin.wav', spin)
    # reel stop: mechanical clunk
    stop = mix(noise(0.05, 0.9, 0.95, seed=3, lp=0.35), tone(140, 0.06, 0.5, 'sq', 0.001, 0.9, slide=-0.5))
    wav(outdir + '/s_stop.wav', stop)
    # small win: two-note chime
    win = cat(tone(880, 0.09, 0.45, 'tri', r=0.5), tone(1320, 0.22, 0.45, 'tri', r=0.8))
    wav(outdir + '/s_win.wav', win)
    # big win: arpeggio
    notes = [523, 659, 784, 1047, 784, 1047, 1319]
    big = cat(*[tone(f, 0.08, 0.45, 'sq', r=0.5) for f in notes[:-1]] + [tone(notes[-1], 0.3, 0.45, 'sq', r=0.8, vib=0.01)])
    wav(outdir + '/s_big.wav', big)
    # jackpot fanfare with bell
    fan = []
    for f, d in ((523, .12), (523, .12), (523, .12), (659, .3), (587, .12), (659, .12), (784, .5)):
        fan += mix(tone(f, d, 0.35, 'sq', r=0.3), tone(f / 2, d, 0.25, 'tri', r=0.3))
    fan = mix(fan, cat(silence(0.9), tone(1568, 0.5, 0.25, 'sine', r=0.9)))
    wav(outdir + '/s_jackpot.wav', fan)
    # buy: cash register "ka-ching"
    buy = cat(noise(0.04, 0.6, 0.8, seed=8, lp=0.9), mix(tone(1760, 0.25, 0.35, 'sine', r=0.9), tone(2637, 0.25, 0.25, 'sine', r=0.9)))
    wav(outdir + '/s_buy.wav', buy)
    # debt: ominous low gong
    debt = mix(tone(55, 0.9, 0.55, 'tri', 0.01, 0.95, slide=-0.1), tone(82, 0.9, 0.3, 'sine', 0.01, 0.95),
               noise(0.15, 0.3, 0.9, seed=4, lp=0.2))
    wav(outdir + '/s_debt.wav', debt)
    # curse: descending tritone wobble
    curse = cat(tone(440, 0.18, 0.45, 'saw', r=0.3, vib=0.04), tone(311, 0.18, 0.45, 'saw', r=0.3, vib=0.04),
                tone(220, 0.4, 0.45, 'saw', r=0.8, vib=0.06, slide=-0.3))
    wav(outdir + '/s_curse.wav', curse)
    # coin tick
    wav(outdir + '/s_coin.wav', tone(1975, 0.05, 0.35, 'sq', r=0.7))
    # menu move / select / back / error
    wav(outdir + '/s_move.wav', tone(660, 0.03, 0.3, 'sq', r=0.6))
    wav(outdir + '/s_ok.wav', cat(tone(784, 0.04, 0.35, 'sq', r=0.4), tone(1047, 0.06, 0.35, 'sq', r=0.7)))
    wav(outdir + '/s_err.wav', tone(110, 0.16, 0.45, 'sq', r=0.4, vib=0.05))
    # card effect sparkle
    wav(outdir + '/s_magic.wav', cat(*[tone(f, 0.035, 0.3, 'tri', r=0.5) for f in (1047, 1319, 1568, 2093)]))
    midi(outdir + '/m_lounge.mid')


# ------------------------------------------------------------------- MIDI
def vlq(n):
    out = [n & 0x7f]
    n >>= 7
    while n:
        out.insert(0, (n & 0x7f) | 0x80)
        n >>= 7
    return bytes(out)


def midi(path):
    """Slow minor-key lounge loop: walking bass, piano chords, brushes."""
    tpq = 96
    ev = []  # (tick, bytes)

    def note(t, ch, n, d, v):
        ev.append((t, bytes([0x90 | ch, n, v])))
        ev.append((t + d, bytes([0x80 | ch, n, 0])))
    ev.append((0, bytes([0xC0, 0])))      # piano
    ev.append((0, bytes([0xC1, 32])))     # acoustic bass
    ev.append((0, bytes([0xC2, 11])))     # vibraphone
    ev.append((0, bytes([0xB0, 7, 70])))
    ev.append((0, bytes([0xB1, 7, 100])))
    ev.append((0, bytes([0xB2, 7, 60])))
    # progression in D minor: Dm7 - Gm7 - A7 - Dm7 / Bb7 - A7 - Dm - A7
    prog = [(50, [53, 57, 60, 64]), (55, [53, 58, 62, 65]), (57, [55, 61, 64, 67]), (50, [53, 57, 60, 64]),
            (46, [50, 56, 58, 62]), (45, [55, 61, 64, 67]), (50, [53, 57, 62, 65]), (45, [55, 61, 64, 67])]
    bar = tpq * 4
    walk = [0, 3, 5, 7]
    for b, (root, chord) in enumerate(prog):
        t0 = b * bar
        for i in range(4):
            n = root - 12 + walk[i] if i < 3 else root - 12 + (2 if b % 2 else -1)
            note(t0 + i * tpq, 1, n, tpq - 8, 90 if i == 0 else 70)
        # piano comp on 2 and the "and" of 3
        for (off, dur, vel) in ((tpq, tpq // 2, 50), (tpq * 2 + tpq // 2, tpq, 45)):
            for n in chord:
                note(t0 + off, 0, n, dur, vel)
        # brushes on beats 2 and 4 (ch 9)
        for i in (1, 3):
            note(t0 + i * tpq, 9, 38, 20, 28)
        for i in range(8):
            note(t0 + i * tpq // 2, 9, 42, 10, 18 + (8 if i % 2 == 0 else 0))
        # sparse vibraphone melody
        mel = [None, chord[3] + 12, None, chord[2] + 12] if b % 2 == 0 else [chord[1] + 12, None, chord[3] + 12, None]
        for i, n in enumerate(mel):
            if n:
                note(t0 + i * tpq, 2, n, tpq + tpq // 2, 45)
    ev.sort(key=lambda e: (e[0], e[1][0] & 0xF0 == 0x90))
    trk = bytearray()
    trk += vlq(0) + bytes([0xFF, 0x51, 0x03]) + struct.pack('>I', 750000)[1:]  # 80 bpm
    last = 0
    for t, b in ev:
        trk += vlq(t - last) + b
        last = t
    trk += vlq(bar * len(prog) - last) + bytes([0xFF, 0x2F, 0x00])
    with open(path, 'wb') as f:
        f.write(b'MThd' + struct.pack('>IHHH', 6, 0, 1, tpq))
        f.write(b'MTrk' + struct.pack('>I', len(trk)) + bytes(trk))


if __name__ == '__main__':
    import sys
    build(sys.argv[1] if len(sys.argv) > 1 else '.')
