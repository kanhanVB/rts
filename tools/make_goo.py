"""新敌人贴图：从 Goo 的三张图（idle/act/dead）换色 + 变形出来，保持同一画风。
用法：python3 tools/make_goo.py art/units
窜窜（runner）：紫蓝色、扁长（跑得快的感觉），尺寸在游戏里画小
岩壳（brute）：灰褐岩石色、背上加深色岩块纹，眼睛改橙红，在游戏里画大"""
import sys, colorsys
import numpy as np
from PIL import Image
SRC = '/data/rts/art/units'
DST = sys.argv[1] if len(sys.argv) > 1 else '/data/work/tower'

def rgb_to_hsv(a):
    r, g, b = a[..., 0] / 255.0, a[..., 1] / 255.0, a[..., 2] / 255.0
    mx = np.maximum(np.maximum(r, g), b); mn = np.minimum(np.minimum(r, g), b)
    d = mx - mn
    h = np.zeros_like(mx)
    m = d > 1e-6
    rm = m & (mx == r); gm = m & (mx == g) & ~rm; bm = m & ~rm & ~gm
    h[rm] = ((g - b)[rm] / d[rm]) % 6
    h[gm] = (b - r)[gm] / d[gm] + 2
    h[bm] = (r - g)[bm] / d[bm] + 4
    h = h / 6.0
    s = np.where(mx > 0, d / np.maximum(mx, 1e-6), 0)
    return h, s, mx

def hsv_to_rgb(h, s, v):
    i = np.floor(h * 6).astype(int) % 6
    f = h * 6 - np.floor(h * 6)
    p = v * (1 - s); q = v * (1 - f * s); t = v * (1 - (1 - f) * s)
    out = np.zeros(h.shape + (3,))
    for k, (R, G, B) in enumerate([(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)]):
        mk = i == k
        out[..., 0][mk] = R[mk]; out[..., 1][mk] = G[mk]; out[..., 2][mk] = B[mk]
    return out * 255

def recolor(im, body_h, body_s_mul, body_v_mul, shadow_h=None, shadow_s=None, shadow_v=None, eye=None):
    a = np.asarray(im.convert('RGBA')).astype(float)
    h, s, v = rgb_to_hsv(a)
    green = (h > 0.13) & (h < 0.33) & (s > 0.18)       # 黏液体色（黄绿～绿）
    purple = (h > 0.70) & (h < 0.92) & (s > 0.15)      # 嘴里 / 洞里的紫暗面
    yellow = (h > 0.08) & (h < 0.17) & (s > 0.5) & (v > 0.6)   # 眼睛
    nh, ns, nv = h.copy(), s.copy(), v.copy()
    nh[green] = body_h
    ns[green] = np.clip(s[green] * body_s_mul, 0, 1)
    nv[green] = np.clip(v[green] * body_v_mul, 0, 1)
    if shadow_h is not None:
        nh[purple] = shadow_h
        ns[purple] = np.clip(s[purple] * shadow_s, 0, 1)
        nv[purple] = np.clip(v[purple] * shadow_v, 0, 1)
    if eye is not None:
        nh[yellow] = eye[0]
        ns[yellow] = np.clip(s[yellow] * eye[1], 0, 1)
    rgb = hsv_to_rgb(nh, ns, nv)
    out = a.copy()
    out[..., :3] = rgb
    return Image.fromarray(out.clip(0, 255).astype('uint8'))

def rock_spots(im, seed):
    """岩壳：背上扣几块大岩板（浅色顶面 + 深描边 + 高光线），只画在不透明的体色上"""
    from PIL import ImageDraw
    rng = np.random.default_rng(seed)
    w, h = im.size
    a = np.asarray(im)
    layer = Image.new('RGBA', im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    xs = np.linspace(w * 0.2, w * 0.72, 5)
    for i, x0 in enumerate(xs):
        # 找这一列身体的顶边，岩板贴在背上
        col = a[:, int(x0), 3]
        ys = np.nonzero(col > 250)[0]
        if ys.size == 0:
            continue
        top = ys[0]
        r = w * rng.uniform(0.075, 0.095)
        cx = x0 + rng.uniform(-3, 3)
        cy = top + r * 0.95 + h * 0.04
        pts = []
        for t in np.linspace(0, 2 * np.pi, 7)[:-1] + rng.uniform(0, 0.5):
            k = rng.uniform(0.8, 1.05)
            pts.append((cx + r * np.cos(t) * k, cy + r * 0.62 * np.sin(t) * k))
        d.polygon(pts, fill=(150, 132, 112, 255))
        d.line(pts + [pts[0]], fill=(52, 42, 36, 255), width=3)
        d.line([(cx - r * 0.5, cy - r * 0.3), (cx + r * 0.25, cy - r * 0.42)], fill=(196, 180, 156, 255), width=3)
    la = np.asarray(layer).copy()
    la[..., 3] = np.where(a[..., 3] > 250, la[..., 3], 0)
    bright = a[..., :3].astype(int).sum(axis=2) > 560      # 刺 / 眼睛上不压岩板
    la[..., 3][bright] = 0
    base = im.copy()
    base.alpha_composite(Image.fromarray(la))
    return base

for pose in ['idle', 'act', 'dead']:
    im = Image.open(f'{SRC}/goo_{pose}.png').convert('RGBA')
    # 窜窜：紫蓝、扁长
    r = recolor(im, 0.72, 1.05, 0.95, shadow_h=0.62, shadow_s=1.0, shadow_v=0.8, eye=(0.02, 1.0))
    r = r.resize((round(im.size[0] * 1.12), round(im.size[1] * 0.88)), Image.LANCZOS)
    r.save(f'{DST}/runner_{pose}.png')
    # 岩壳：灰褐岩石、岩斑、橙红眼
    b = recolor(im, 0.075, 0.5, 0.72, shadow_h=0.03, shadow_s=0.7, shadow_v=0.5, eye=(0.03, 1.3))
    if pose != 'dead':
        b = rock_spots(b, 7 if pose == 'idle' else 11)
    b.save(f'{DST}/brute_{pose}.png')

if DST == '/data/work/tower':
    ims = [Image.open(f'{SRC}/goo_idle.png')] + [Image.open(f'{DST}/{k}_{p}.png') for k in ['runner', 'brute'] for p in ['idle', 'act', 'dead']]
    Hh = max(i.size[1] for i in ims); Ww = sum(i.size[0] for i in ims) + 10 * len(ims)
    c = Image.new('RGBA', (Ww, Hh), (120, 160, 90, 255)); x = 0
    for i in ims:
        c.alpha_composite(i.convert('RGBA'), (x, Hh - i.size[1])); x += i.size[0] + 10
    c.save(f'{DST}/goo_preview.png')
