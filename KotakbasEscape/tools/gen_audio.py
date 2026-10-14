#!/usr/bin/env python3
"""Процедурная генерация звуков и музыки для «Котакбас побег от ТЦК».

Запуск: python3 tools/gen_audio.py  (из корня проекта Godot)
Результат: assets/audio/sfx/*.wav и assets/audio/music/*.wav (16 бит, моно, 22050 Гц).
"""
import os
import wave
import numpy as np

SR = 22050
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SFX = os.path.join(ROOT, "assets", "audio", "sfx")
MUS = os.path.join(ROOT, "assets", "audio", "music")
os.makedirs(SFX, exist_ok=True)
os.makedirs(MUS, exist_ok=True)
rng = np.random.default_rng(1337)


def t_arr(dur):
    return np.arange(int(SR * dur)) / SR


def save(path, x, gain=0.9):
    x = np.asarray(x, dtype=np.float64)
    peak = np.max(np.abs(x)) if len(x) else 1.0
    if peak > 0:
        x = x / peak * gain
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def env(n, a=0.005, d=0.1, s=0.6, r=0.1, dur=None):
    """ADSR по количеству сэмплов n."""
    total = n
    a_n = max(1, int(a * SR))
    d_n = max(1, int(d * SR))
    r_n = max(1, int(r * SR))
    s_n = max(0, total - a_n - d_n - r_n)
    e = np.concatenate([
        np.linspace(0, 1, a_n),
        np.linspace(1, s, d_n),
        np.full(s_n, s),
        np.linspace(s, 0, r_n),
    ])
    if len(e) < total:
        e = np.pad(e, (0, total - len(e)))
    return e[:total]


def osc(kind, freq, dur, duty=0.5):
    t = t_arr(dur)
    if np.isscalar(freq):
        phase = freq * t
    else:
        phase = np.cumsum(freq) / SR
    ph = phase % 1.0
    if kind == "sine":
        return np.sin(2 * np.pi * phase)
    if kind == "square":
        return np.where(ph < duty, 1.0, -1.0)
    if kind == "saw":
        return 2 * ph - 1
    if kind == "tri":
        return 2 * np.abs(2 * ph - 1) - 1
    raise ValueError(kind)


def noise(dur):
    return rng.uniform(-1, 1, int(SR * dur))


def lowpass(x, alpha):
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += alpha * (x[i] - acc)
        y[i] = acc
    return y


def fast_lowpass(x, k=8):
    kernel = np.ones(k) / k
    return np.convolve(x, kernel, mode="same")


def sweep(f0, f1, dur, kind="sine", curve=1.0):
    n = int(SR * dur)
    f = f0 + (f1 - f0) * (np.linspace(0, 1, n) ** curve)
    return osc(kind, f, dur)


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def concat(*parts):
    return np.concatenate(parts)


def silence(dur):
    return np.zeros(int(SR * dur))


def note_freq(n):
    """MIDI-нота -> частота."""
    return 440.0 * 2 ** ((n - 69) / 12)


# ---------------------------------------------------------------- SFX

def make_sfx():
    s = {}
    d = 0.06
    s["click"] = osc("square", 900, d) * env(int(SR * d), 0.001, 0.02, 0.3, 0.03)
    d = 0.035
    s["blip"] = osc("square", 1400, d, 0.25) * env(int(SR * d), 0.001, 0.01, 0.4, 0.015) * 0.5
    d = 0.5
    s["studio_beep"] = mix(
        sweep(300, 1800, d, "square", 0.5) * env(int(SR * d), 0.01, 0.1, 0.5, 0.2) * 0.4,
        osc("sine", 880, d) * env(int(SR * d), 0.2, 0.1, 0.4, 0.15) * 0.5,
    )
    d = 0.45
    g = np.concatenate([osc("square", rng.uniform(100, 2000), 0.03) * rng.uniform(0.3, 1) for _ in range(15)])
    s["studio_glitch"] = mix(g * env(len(g), 0.001, 0.1, 0.8, 0.1), noise(d) * 0.3 * env(int(SR * d), 0.001, 0.05, 0.4, 0.2))
    d = 0.9
    s["whoosh"] = fast_lowpass(noise(d), 12) * env(int(SR * d), 0.3, 0.2, 0.6, 0.35)
    knock = lambda: fast_lowpass(noise(0.08), 30) * env(int(SR * 0.08), 0.001, 0.03, 0.2, 0.04) + osc("sine", 110, 0.08) * env(int(SR * 0.08), 0.001, 0.05, 0.1, 0.02)
    s["knock"] = concat(knock(), silence(0.12), knock(), silence(0.12), knock(), silence(0.35), knock(), silence(0.1), knock())
    d = 0.18
    s["choice"] = concat(osc("tri", 660, 0.07) * env(int(SR * 0.07), 0.001, 0.03, 0.5, 0.03), osc("tri", 990, 0.11) * env(int(SR * 0.11), 0.001, 0.05, 0.5, 0.05))
    s["alert"] = concat(*[osc("square", f, 0.12, 0.3) * env(int(SR * 0.12), 0.001, 0.05, 0.6, 0.03) for f in (880, 660, 880, 660)])
    s["door"] = mix(sweep(180, 90, 0.5, "saw") * env(int(SR * 0.5), 0.01, 0.2, 0.3, 0.2) * 0.4, fast_lowpass(noise(0.5), 40) * env(int(SR * 0.5), 0.01, 0.3, 0.1, 0.1))
    vib = (osc("square", 140, 0.35, 0.5) * 0.3 + noise(0.35) * 0.1) * env(int(SR * 0.35), 0.01, 0.1, 0.9, 0.05)
    s["phone_vibe"] = concat(vib, silence(0.15), vib)
    d = 0.7
    s["tv_noise"] = noise(d) * env(int(SR * d), 0.02, 0.1, 0.7, 0.2) * 0.5
    coo = lambda f: sweep(f, f * 0.8, 0.25, "sine", 0.7) * (1 + 0.5 * osc("sine", 30, 0.25)) * env(int(SR * 0.25), 0.02, 0.1, 0.6, 0.1)
    s["pigeon"] = concat(coo(420), silence(0.05), coo(380), silence(0.08), coo(440))
    d = 0.25
    s["jump"] = sweep(250, 900, d, "square", 0.6) * env(int(SR * d), 0.001, 0.05, 0.5, 0.1) * 0.5
    d = 0.35
    s["slide"] = fast_lowpass(noise(d), 4) * env(int(SR * d), 0.01, 0.1, 0.6, 0.15) * 0.6
    d = 0.15
    s["swipe"] = fast_lowpass(noise(d), 6) * env(int(SR * d), 0.02, 0.05, 0.3, 0.06) * 0.5
    s["coin"] = concat(osc("square", 988, 0.06, 0.25) * env(int(SR * 0.06), 0.001, 0.02, 0.6, 0.02), osc("square", 1319, 0.16, 0.25) * env(int(SR * 0.16), 0.001, 0.05, 0.5, 0.1)) * 0.5
    s["powerup"] = concat(*[osc("square", note_freq(n), 0.06, 0.3) * env(int(SR * 0.06), 0.001, 0.02, 0.7, 0.02) for n in (60, 64, 67, 72, 76, 79, 84)]) * 0.5
    d = 0.3
    s["hit"] = mix(sweep(200, 50, d, "sine") * env(int(SR * d), 0.001, 0.1, 0.3, 0.15), fast_lowpass(noise(d), 6) * env(int(SR * d), 0.001, 0.05, 0.2, 0.1) * 0.7)
    d = 0.9
    s["crash"] = mix(fast_lowpass(noise(d), 3) * env(int(SR * d), 0.001, 0.3, 0.3, 0.4), sweep(120, 40, d, "saw") * env(int(SR * d), 0.001, 0.2, 0.2, 0.3) * 0.5)
    d = 0.45
    s["boing"] = osc("sine", 180 + 120 * np.sin(2 * np.pi * 9 * t_arr(d)) * np.exp(-t_arr(d) * 4), d) * env(int(SR * d), 0.001, 0.1, 0.7, 0.2)
    nokia = [76, 74, 66, 68, 73, 71, 62, 64, 71, 69, 61, 64, 69]
    lens = [1, 1, 2, 2, 1, 1, 2, 2, 1, 1, 2, 2, 4]
    s["nokia"] = concat(*[osc("square", note_freq(n + 12), l * 0.09, 0.5) * env(int(SR * l * 0.09), 0.001, 0.02, 0.6, 0.02) for n, l in zip(nokia, lens)]) * 0.4
    d = 0.4
    s["helmet_break"] = mix(osc("square", 1200, d, 0.1) * np.exp(-t_arr(d) * 12), noise(d) * np.exp(-t_arr(d) * 9) * 0.6)
    d = 0.22
    s["chop"] = mix(fast_lowpass(noise(d), 10) * np.exp(-t_arr(d) * 20), osc("sine", 160, d) * np.exp(-t_arr(d) * 25))
    s["mine"] = mix(osc("square", 1800, 0.2, 0.1) * np.exp(-t_arr(0.2) * 30) * 0.4, noise(0.2) * np.exp(-t_arr(0.2) * 25))
    s["pickup"] = concat(osc("tri", 520, 0.05) * env(int(SR * 0.05), 0.001, 0.02, 0.6, 0.02), osc("tri", 780, 0.08) * env(int(SR * 0.08), 0.001, 0.03, 0.6, 0.04))
    s["craft_done"] = concat(*[osc("tri", note_freq(n), 0.09) * env(int(SR * 0.09), 0.001, 0.03, 0.6, 0.04) for n in (67, 72, 76)])
    s["build"] = concat(s["chop"], silence(0.05), s["chop"] * 0.8, silence(0.05), s["chop"] * 0.6)
    munch = lambda: fast_lowpass(noise(0.07), 8) * env(int(SR * 0.07), 0.005, 0.03, 0.5, 0.03)
    s["eat"] = concat(munch(), silence(0.06), munch(), silence(0.06), munch())
    gulp = lambda: sweep(300, 600, 0.1, "sine") * env(int(SR * 0.1), 0.01, 0.04, 0.5, 0.04)
    s["drink"] = concat(gulp(), silence(0.08), gulp(), silence(0.08), gulp())
    d = 0.3
    s["hurt"] = sweep(500, 200, d, "saw", 0.8) * env(int(SR * d), 0.005, 0.1, 0.5, 0.1) * 0.6
    d = 0.09
    s["step"] = fast_lowpass(noise(d), 20) * env(int(SR * d), 0.002, 0.03, 0.3, 0.04) * 0.5
    d = 0.25
    s["throw"] = fast_lowpass(noise(d), 3) * env(int(SR * d), 0.08, 0.05, 0.6, 0.1)
    d = 0.5
    t = t_arr(d)
    s["metal_hit"] = sum(np.sin(2 * np.pi * f * t) * np.exp(-t * k) for f, k in ((520, 9), (1310, 12), (2150, 16), (3400, 22))) + noise(d) * np.exp(-t * 40)
    d = 0.7
    t = t_arr(d)
    s["cockpit_hit"] = mix(sum(np.sin(2 * np.pi * f * t) * np.exp(-t * k) for f, k in ((900, 6), (1700, 8), (2600, 10))), noise(d) * np.exp(-t * 30) * 0.8)
    d = 4.0
    t = t_arr(d)
    hum = osc("saw", 55 + 3 * np.sin(2 * np.pi * 0.5 * t), d) * 0.4 + osc("sine", 110 + 6 * np.sin(2 * np.pi * 3 * t), d) * 0.5 + osc("sine", 440 + 40 * np.sin(2 * np.pi * 1 * t), d) * 0.12
    s["ufo_hum"] = fast_lowpass(hum, 6)
    d = 2.0
    t = t_arr(d)
    siren = osc("square", 600 + 300 * np.sin(2 * np.pi * 1.0 * t), d, 0.5) * 0.4
    s["ufo_alarm"] = siren * env(int(SR * d), 0.02, 0.1, 0.9, 0.1)
    d = 3.0
    t = t_arr(d)
    s["beam"] = (osc("sine", 300 + 30 * np.sin(2 * np.pi * 6 * t), d) * 0.5 + osc("sine", 603, d) * 0.25 + noise(d) * 0.05)
    d = 1.4
    s["ufo_retreat"] = mix(sweep(1600, 120, d, "sine", 0.7) * env(int(SR * d), 0.01, 0.2, 0.8, 0.3), osc("square", 20, d) * 0.1)
    d = 2.5
    t = t_arr(d)
    s["thunder"] = fast_lowpass(noise(d), 40) * (np.exp(-t * 1.5) + 0.6 * np.exp(-np.maximum(t - 0.4, 0) * 2) * (t > 0.4))
    d = 2.0
    t = t_arr(d)
    s["howl"] = osc("sine", 400 + 250 * np.sin(np.pi * t / d) + 8 * np.sin(2 * np.pi * 5 * t), d) * env(int(SR * d), 0.3, 0.3, 0.7, 0.6)
    honk = lambda: (osc("saw", 330, 0.18) * 0.5 + osc("square", 335, 0.18) * 0.3) * env(int(SR * 0.18), 0.01, 0.05, 0.8, 0.05)
    s["honk"] = concat(honk(), silence(0.06), honk())
    xp = [(68, 0.25), (75, 0.25), (73, 0.25), (68, 0.25), (75, 0.25), (70, 0.75)]
    s["xp_startup"] = concat(*[(osc("sine", note_freq(n), dd) * 0.6 + osc("tri", note_freq(n - 12), dd) * 0.4) * env(int(SR * dd), 0.02, 0.1, 0.7, 0.15) for n, dd in xp])
    s["xp_error"] = concat(osc("sine", 440, 0.18) * env(int(SR * 0.18), 0.005, 0.05, 0.6, 0.05), osc("sine", 330, 0.3) * env(int(SR * 0.3), 0.005, 0.05, 0.6, 0.2))
    d = 0.6
    s["splash"] = fast_lowpass(noise(d), 5) * np.exp(-t_arr(d) * 6)
    s["achievement"] = concat(*[osc("square", note_freq(n), dd, 0.3) * env(int(SR * dd), 0.001, 0.03, 0.6, 0.04) for n, dd in ((72, 0.1), (76, 0.1), (79, 0.1), (84, 0.35))]) * 0.5
    s["quest_done"] = concat(*[osc("tri", note_freq(n), dd) * env(int(SR * dd), 0.001, 0.03, 0.6, 0.05) for n, dd in ((65, 0.12), (69, 0.12), (72, 0.3))])
    d = 1.5
    s["sleep"] = sweep(500, 200, d, "sine") * env(int(SR * d), 0.2, 0.3, 0.5, 0.5) * 0.5
    s["fanfare"] = concat(*[(osc("saw", note_freq(n), dd) * 0.4 + osc("square", note_freq(n + 7), dd, 0.3) * 0.2) * env(int(SR * dd), 0.005, 0.05, 0.7, 0.05) for n, dd in ((60, 0.15), (60, 0.15), (60, 0.15), (64, 0.45), (62, 0.15), (64, 0.15), (67, 0.7))])
    d = 1.2
    s["radio"] = fast_lowpass(noise(d), 2) * (0.6 + 0.4 * osc("sine", 7, d)) * env(int(SR * d), 0.05, 0.1, 0.7, 0.2)
    d = 0.8
    s["fall"] = sweep(900, 150, d, "sine", 0.5) * env(int(SR * d), 0.01, 0.2, 0.7, 0.1) * 0.5
    s["thud"] = mix(osc("sine", 70, 0.3) * np.exp(-t_arr(0.3) * 12), fast_lowpass(noise(0.3), 20) * np.exp(-t_arr(0.3) * 18))
    # Нелепые звуки для попаданий по кабине НЛО
    d = 0.5
    s["silly_1"] = osc("square", 300 + 200 * np.sin(2 * np.pi * 14 * t_arr(d)), d, 0.4) * env(int(SR * d), 0.005, 0.1, 0.6, 0.2) * 0.5  # «бвоинг»
    s["silly_2"] = concat(*[osc("sine", f, 0.07) * env(int(SR * 0.07), 0.002, 0.02, 0.5, 0.02) for f in (1200, 900, 1500, 700, 1800)])  # «пиу-пиу»
    d = 0.7
    s["silly_3"] = (osc("saw", 90 + 40 * np.sin(2 * np.pi * 25 * t_arr(d)), d) * 0.5 + noise(d) * 0.2) * env(int(SR * d), 0.01, 0.1, 0.7, 0.2)  # «пррр»
    s["silly_4"] = sweep(200, 1400, 0.4, "tri", 2.0) * env(int(SR * 0.4), 0.01, 0.1, 0.7, 0.1)  # «уииип»
    d = 1.0
    s["whistle_down"] = sweep(2000, 400, d, "sine", 1.0) * env(int(SR * d), 0.02, 0.1, 0.8, 0.1) * 0.6
    # Окружение (зацикленные)
    d = 4.0
    s["rain"] = fast_lowpass(noise(d), 3) * 0.6 + (rng.uniform(0, 1, int(SR * d)) > 0.9985) * rng.uniform(-1, 1, int(SR * d)) * 0.8
    t = t_arr(6.0)
    s["wind"] = fast_lowpass(noise(6.0), 60) * (0.6 + 0.4 * np.sin(2 * np.pi * t / 6.0)) * 3
    day = noise(6.0) * 0.03
    for k in range(9):
        start = rng.uniform(0, 5.4)
        ch = concat(*[sweep(f, f * 1.3, 0.06, "sine") * env(int(SR * 0.06), 0.005, 0.02, 0.5, 0.02) for f in rng.uniform(2500, 4200, 4)])
        i = int(start * SR)
        day[i:i + len(ch)] += ch[: len(day) - i] * 0.35
    s["forest_day"] = day
    night = noise(6.0) * 0.02
    for k in range(40):
        start = rng.uniform(0, 5.8)
        ch = osc("sine", 4300, 0.04) * env(int(SR * 0.04), 0.002, 0.01, 0.5, 0.01)
        i = int(start * SR)
        night[i:i + len(ch)] += ch[: len(night) - i] * 0.2
    s["forest_night"] = night
    s["city"] = fast_lowpass(noise(5.0), 25) * 2 + osc("sine", 70, 5.0) * 0.05
    s["fire"] = fast_lowpass(noise(3.0), 6) * 0.4 + (rng.uniform(0, 1, int(SR * 3)) > 0.997) * rng.uniform(-1, 1, int(SR * 3))
    d = 3.0
    t = t_arr(d)
    s["night_weird"] = osc("sine", 180 + 60 * np.sin(2 * np.pi * 0.7 * t), d) * env(int(SR * d), 0.5, 0.5, 0.6, 1.0) * 0.5 + fast_lowpass(noise(d), 50) * 0.5
    for name, x in s.items():
        loopy = name in ("ufo_hum", "beam", "rain", "wind", "forest_day", "forest_night", "city", "fire")
        save(os.path.join(SFX, name + ".wav"), x, 0.7 if loopy else 0.9)
    print("SFX:", len(s))


# ---------------------------------------------------------------- Музыка

def drum_kick(dur=0.25):
    return sweep(150, 40, dur, "sine", 0.4) * np.exp(-t_arr(dur) * 14)


def drum_snare(dur=0.18):
    return noise(dur) * np.exp(-t_arr(dur) * 18) * 0.7 + osc("tri", 190, dur) * np.exp(-t_arr(dur) * 25) * 0.4


def drum_hat(dur=0.05):
    x = noise(dur)
    return (x - fast_lowpass(x, 3)) * np.exp(-t_arr(dur) * 60) * 0.5


def place(buf, sig, t, gain=1.0):
    i = int(t * SR)
    if i >= len(buf):
        return
    end = min(len(buf), i + len(sig))
    buf[i:end] += sig[: end - i] * gain


def tone(kind, midi, dur, duty=0.5, a=0.005, d=0.08, s=0.6, r=0.08):
    n = int(SR * dur)
    return osc(kind, note_freq(midi), dur, duty) * env(n, a, d, s, min(r, dur * 0.5))


def song(bpm, bars, chords, scale, lead_kind, bass_kind, pattern, seed, lead_gain=0.35, bass_gain=0.4,
         pad=None, drums=True, swing=0.0, lead_density=0.7, lead_oct=72, lead_div=2):
    beat = 60.0 / bpm
    total = bars * 4 * beat
    buf = np.zeros(int(total * SR) + SR)
    r = np.random.default_rng(seed)
    last = lead_oct
    for bar in range(bars):
        root = chords[bar % len(chords)]
        t0 = bar * 4 * beat
        # бас
        for step, (off, l) in enumerate(pattern):
            note = root + 36 + (7 if step % 2 == 1 and len(pattern) > 2 else 0)
            place(buf, tone(bass_kind, note, l * beat * 0.95, 0.5, 0.005, 0.05, 0.7, 0.05), t0 + off * beat, bass_gain)
        # пэд
        if pad:
            chord = [root + 60, root + 60 + (3 if root in scale.get("minor_roots", []) else 4), root + 67]
            for c in chord:
                place(buf, tone(pad, c, 4 * beat, 0.5, 0.3, 0.5, 0.6, 0.6), t0, 0.08)
        # мелодия по тонам аккорда и гамме
        steps = 4 * lead_div
        for k in range(steps):
            if r.random() > lead_density:
                continue
            cand = [n for n in scale["notes"] if abs(n - last) <= 5] or scale["notes"]
            if r.random() < 0.5:
                chord_tones = [n for n in cand if (n - root) % 12 in (0, 3, 4, 7)]
                if chord_tones:
                    cand = chord_tones
            last = int(r.choice(cand))
            ln = beat / lead_div * (2 if r.random() < 0.25 else 1)
            off = k * beat / lead_div + (swing * beat / lead_div if k % 2 == 1 else 0)
            place(buf, tone(lead_kind, last, ln * 0.9, 0.25), t0 + off, lead_gain)
        if drums:
            for b in range(4):
                tb = t0 + b * beat
                if b % 2 == 0:
                    place(buf, drum_kick(), tb, 0.8)
                else:
                    place(buf, drum_snare(), tb, 0.5)
                place(buf, drum_hat(), tb + beat * 0.5, 0.4)
                place(buf, drum_hat(), tb, 0.25)
    return buf[: int(total * SR)]


def scale_notes(root, kind, lo=64, hi=86):
    steps = {"major": [0, 2, 4, 5, 7, 9, 11], "minor": [0, 2, 3, 5, 7, 8, 10], "dorian": [0, 2, 3, 5, 7, 9, 10]}[kind]
    return [n for n in range(lo, hi) if (n - root) % 12 in steps]


def make_music():
    m = {}
    C = scale_notes(0, "major")
    Am = scale_notes(9, "minor")
    Dm = scale_notes(2, "dorian")
    Em = scale_notes(4, "minor")
    m["menu"] = song(138, 8, [0, 5, 7, 0, 9, 5, 7, 7], {"notes": C}, "square", "tri", [(0, 1), (1, 1), (2, 1), (3, 1)], 3, swing=0.0)
    m["novel"] = song(84, 8, [5, 4, 2, 9, 5, 4, 0, 0], {"notes": scale_notes(0, "major", 60, 80)}, "tri", "sine", [(0, 2), (2, 2)], 11, lead_gain=0.3, pad="tri", drums=False, lead_density=0.45)
    m["tension"] = song(100, 4, [9, 9, 8, 8], {"notes": scale_notes(9, "minor", 57, 72), "minor_roots": [9]}, "sine", "saw", [(0, 0.5), (0.5, 0.5), (1, 0.5), (1.5, 0.5), (2, 0.5), (2.5, 0.5), (3, 0.5), (3.5, 0.5)], 5, lead_gain=0.18, bass_gain=0.3, drums=False, lead_density=0.25)
    m["runner"] = song(168, 16, [9, 9, 5, 7, 9, 9, 2, 4, 5, 5, 7, 7, 9, 2, 4, 4], {"notes": Am}, "square", "saw", [(0, 0.5), (0.5, 0.5), (1, 0.5), (1.5, 0.5), (2, 0.5), (2.5, 0.5), (3, 0.5), (3.5, 0.5)], 7, lead_gain=0.3, bass_gain=0.32, lead_density=0.8, lead_div=4)
    m["survival_day"] = song(100, 8, [2, 0, 7, 2, 2, 5, 0, 9], {"notes": Dm}, "tri", "tri", [(0, 1.5), (1.5, 0.5), (2, 2)], 13, lead_gain=0.3, pad="sine", drums=False, lead_density=0.55)
    m["survival_night"] = song(70, 8, [4, 0, 4, 11], {"notes": scale_notes(4, "minor", 59, 79), "minor_roots": [4]}, "sine", "sine", [(0, 4)], 17, lead_gain=0.2, bass_gain=0.3, pad="tri", drums=False, lead_density=0.3)
    m["ufo"] = song(150, 8, [2, 2, 10, 0, 2, 2, 10, 9], {"notes": Dm}, "saw", "square", [(0, 0.5), (0.5, 0.5), (1, 0.5), (1.5, 0.5), (2, 0.5), (2.5, 0.5), (3, 0.5), (3.5, 0.5)], 19, lead_gain=0.22, bass_gain=0.3, lead_density=0.9, lead_div=4)
    m["ending"] = song(76, 8, [0, 7, 9, 5, 0, 7, 5, 7], {"notes": scale_notes(0, "major", 60, 84)}, "tri", "sine", [(0, 2), (2, 2)], 23, lead_gain=0.32, pad="sine", drums=False, lead_density=0.5)
    m["credits"] = song(120, 8, [0, 9, 5, 7], {"notes": C}, "square", "tri", [(0, 1), (1, 1), (2, 1), (3, 1)], 29, lead_gain=0.25)
    for name, x in m.items():
        save(os.path.join(MUS, name + ".wav"), x, 0.6)
    print("Music:", len(m))


if __name__ == "__main__":
    make_sfx()
    make_music()
