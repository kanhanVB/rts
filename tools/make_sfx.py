#!/usr/bin/env python3
"""音效合成：警钟 / 警报解除 / 挨打报警号角 → art/sfx/*.wav（16 位单声道 22050Hz）

用法：python3 tools/make_sfx.py ，然后重新导入一次：Godot --headless --path . --import
想换成真录音：同名 wav 直接覆盖（再导入一次）就行，代码只认文件名（见 sfx.gd）。
"""
import os
import wave

import numpy as np

RATE = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "sfx")


def strike(nominal, dur, partials, click=0.22, seed=0):
    """敲一下钟：一组按指数衰减的分音 + 敲击瞬间一小声"嗒"（噪声）"""
    t = np.arange(int(dur * RATE)) / RATE
    y = np.zeros_like(t)
    for ratio, amp, decay in partials:
        y += amp * np.exp(-t / decay) * np.sin(2 * np.pi * nominal * ratio * t)
    rng = np.random.default_rng(seed)
    n = int(0.012 * RATE)
    burst = rng.standard_normal(n) * np.exp(-np.arange(n) / (0.0025 * RATE))
    y[:n] += click * np.diff(burst, prepend=0.0)
    a = int(0.002 * RATE)
    y[:a] *= np.linspace(0.0, 1.0, a)    # 起音 2ms，防爆音
    r = int(0.25 * RATE)
    y[-r:] *= np.linspace(1.0, 0.0, r) ** 2    # 收尾淡出：余音被截断会"咔"一声
    return y


def mix(parts, total):
    """parts = [(起始秒, 波形, 音量)] 叠到一条 total 秒长的轨上"""
    y = np.zeros(int(total * RATE))
    for t0, w, g in parts:
        i = int(t0 * RATE)
        n = min(len(w), len(y) - i)
        y[i:i + n] += g * w[:n]
    return y


def finish(y, peak=0.85, fade=0.06):
    n = int(fade * RATE)
    y[-n:] *= np.linspace(1.0, 0.0, n)
    return y * (peak / max(1e-9, np.max(np.abs(y))))


def save(name, y):
    os.makedirs(OUT, exist_ok=True)
    pcm = (np.clip(y, -1.0, 1.0) * 32767.0).astype("<i2")
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(pcm.tobytes())
    print("%s.wav  %.2f 秒" % (name, len(y) / RATE))


# 镇上的警钟：小三度（tierce）是"钟味"的来源；名义音旁边再挂一个差 0.3% 的分音，余音带点颤
BELL = [(0.25, 0.30, 2.2), (0.5, 0.55, 1.6), (0.6, 0.42, 1.1), (0.75, 0.20, 0.9), (1.0, 1.0, 1.0),
        (1.003, 0.35, 1.0), (1.5, 0.28, 0.45), (2.0, 0.26, 0.35), (2.66, 0.13, 0.22), (3.2, 0.07, 0.15)]


def bell():
    """当—当—当：三下，一下比一下急"""
    w = [strike(660.0, 1.9, BELL, seed=s) for s in range(3)]
    return finish(mix([(0.0, w[0], 1.0), (0.46, w[1], 0.9), (0.88, w[2], 0.95)], 2.75))


# 手摇小铃：分音接近整数倍，短、亮
CHIME = [(1.0, 1.0, 0.55), (2.0, 0.42, 0.3), (3.0, 0.18, 0.18), (4.2, 0.1, 0.1), (0.5, 0.18, 0.7)]


def clear():
    """叮—咚（往上走一个大三度）：警报解除，回去干活"""
    a = strike(1046.5, 1.2, CHIME, click=0.12, seed=7)
    b = strike(1318.5, 1.2, CHIME, click=0.12, seed=8)
    return finish(mix([(0.0, a, 0.9), (0.26, b, 1.0)], 1.5), peak=0.7)


def horn_note(f, dur):
    """号角一声：起音时音高往上一挑（铜管的"噗"），稳住后加点颤音；两层略微错开的声部撑厚度"""
    t = np.arange(int(dur * RATE)) / RATE
    y = np.zeros_like(t)
    for det, g in [(1.0, 1.0), (1.006, 0.55)]:
        bend = 1.0 - 0.035 * np.exp(-t / 0.035)
        vib = 1.0 + 0.007 * np.sin(2 * np.pi * 5.5 * t) * np.clip((t - 0.08) / 0.12, 0.0, 1.0)
        ph = 2 * np.pi * np.cumsum(f * det * bend * vib) / RATE
        for n, a in enumerate([1.0, 0.78, 0.6, 0.44, 0.3, 0.2, 0.13, 0.08, 0.05], start=1):
            # 高次谐波晚一点出来（起音发闷、吹开了才亮）
            y += g * a * (1.0 - np.exp(-t / (0.012 * n))) * np.sin(n * ph)
    att = np.clip(t / 0.05, 0.0, 1.0)
    rel = np.clip((dur - t) / 0.12, 0.0, 1.0)
    return y * att * att * (3 - 2 * att) * rel


def alert():
    """呜—呜—：两声号角（降 B → 降 E 往上走四度），有人挨打了"""
    return finish(mix([(0.0, horn_note(233.1, 0.34), 0.85), (0.4, horn_note(311.1, 0.56), 1.0)], 1.0), peak=0.8)


# ---------- 下面四个是"手感音"：都比报警音轻，混战里一直响也不该抢戏 ----------

def knock(f, dur=0.18, seed=1):
    """木头/骨头被敲一下：低频下滑 + 一小撮噪声当"咔"。盖房子、砸建筑都用它"""
    t = np.arange(int(dur * RATE)) / RATE
    freq = f * (1.0 + 1.1 * np.exp(-t / 0.03))    # 起音高、几十毫秒内落回基频
    body = np.sin(2 * np.pi * np.cumsum(freq) / RATE) * np.exp(-t / 0.055)
    rng = np.random.default_rng(seed)
    n = rng.standard_normal(len(t))
    click = np.diff(n, prepend=0.0) * np.exp(-t / 0.010) * 0.30
    att = np.clip(t / 0.003, 0.0, 1.0)
    return (body + click) * att


def build_done():
    """笃、笃—叮：两下锤子收工，再落一声亮铃。每座房子完工放一次"""
    a = knock(150.0, 0.16, seed=3)
    b = knock(178.0, 0.16, seed=4)
    ch = strike(1318.5, 0.9, CHIME, click=0.10, seed=11)
    return finish(mix([(0.0, a, 0.85), (0.15, b, 0.75), (0.32, ch, 0.9)], 1.35), peak=0.78)


def thud():
    """闷响：自家房子被砸。低频、不带金属味——要"砸在木头上"，不是"打铁" """
    y = knock(92.0, 0.30, seed=5)
    return finish(y, peak=0.85, fade=0.09)


def horn_wave():
    """进攻号角：两声（低音 → 五度上），比报警的 alert 更长更沉，一听就知道"波次来了"""
    return finish(mix([(0.0, horn_note(155.6, 0.52), 0.9), (0.54, horn_note(233.1, 0.72), 1.0)], 1.4), peak=0.85)


def kill():
    """一只怪没了：短促下滑的"啵"。很轻（-12dB），混战里响成一串也不该盖过号角"""
    dur = 0.14
    t = np.arange(int(dur * RATE)) / RATE
    f = 430.0 * (1.0 - 0.5 * t / dur)
    y = np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.exp(-t / 0.038)
    rng = np.random.default_rng(13)
    y += np.diff(rng.standard_normal(len(t)), prepend=0.0) * np.exp(-t / 0.008) * 0.20
    return finish(y * np.clip(t / 0.002, 0.0, 1.0), peak=0.62, fade=0.04)


if __name__ == "__main__":
    save("bell", bell())
    save("clear", clear())
    save("alert", alert())
    save("build_done", build_done())
    save("thud", thud())
    save("horn_wave", horn_wave())
    save("kill", kill())
