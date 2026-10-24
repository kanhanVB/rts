"""地图探索用的道具/新建筑贴图（王国保卫战画风：厚深色描边 + 亮边 + 木纹）。
先按 2 倍画、再缩小一半（边缘自然抗锯齿）。
用法：python3 tools/make_props.py art
输出：
  props/chest.png              宝箱（关着）
  props/relic_gem.png          遗物宝石（灰白，游戏里按遗物颜色染色）
  props/plinth.png             遗物石座
  buildings/waterwheel_house.png  水车磨坊（不含轮子）
  buildings/waterwheel_wheel.png  水车轮子（单独一张，游戏里绕轴转）
  buildings/waterwheel.png     合成图（命令卡图标 / 放置预览 / 工地长出来）
  buildings/outpost_body.png / outpost_top.png / outpost_front.png / outpost.png   前哨（塔身 → 弓手 → 挑檐 → 木屋栅栏）
  buildings/ruins.png          Goo 据点废墟（塌掉的窝）
打印每张图的尺寸 + 锚点，手工追加进 art_data.gd 的 SPRITES"""
import sys, math, random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

ROOT = sys.argv[1] if len(sys.argv) > 1 else '/data/work/props'
SRC = '/data/rts/art'
S = 2                                  # 超采样倍数
OUT = (42, 30, 26, 255)               # 描边
W_DARK = (104, 70, 40, 255)
W_MID = (146, 100, 56, 255)
W_MID2 = (134, 92, 52, 255)
W_LIGHT = (186, 136, 86, 255)
W_HI = (214, 170, 112, 255)
ST_DARK = (120, 106, 90, 255)
ST_MID = (170, 156, 138, 255)
ST_LIGHT = (214, 200, 170, 255)
ST_HI = (234, 222, 192, 255)
IRON = (74, 74, 84, 255)
IRON_HI = (150, 152, 162, 255)
GOLD = (236, 184, 62, 255)
GOLD_HI = (255, 232, 140, 255)
GOLD_DK = (170, 110, 30, 255)
rnd = random.Random(7)

def canvas(w, h):
    im = Image.new('RGBA', (w * S, h * S), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)

def sc(pts):
    return [(x * S, y * S) for x, y in pts]

def poly(d, pts, fill, ow=3.0):
    p = sc(pts)
    d.polygon(p, fill=fill)
    if ow > 0:
        d.line(p + [p[0]], fill=OUT, width=int(ow * S), joint='curve')

def line(d, pts, col, w):
    d.line(sc(pts), fill=col, width=max(1, int(w * S)), joint='curve')

def ellipse(d, box, fill, ow=3.0):
    x0, y0, x1, y1 = box
    d.ellipse([x0 * S, y0 * S, x1 * S, y1 * S], fill=fill, outline=OUT if ow > 0 else None, width=int(ow * S))

def rrect(d, box, r, fill, ow=3.0):
    x0, y0, x1, y1 = box
    d.rounded_rectangle([x0 * S, y0 * S, x1 * S, y1 * S], radius=r * S, fill=fill, outline=OUT if ow > 0 else None, width=int(ow * S))

def finish(im):
    w, h = im.size
    return im.resize((w // S, h // S), Image.LANCZOS)

def outlined(im, r=2):
    """外轮廓再补一圈描边（拼贴的图裁断处也有描边）"""
    a = im.getchannel('A').point(lambda v: 255 if v > 90 else 0)
    big = a.filter(ImageFilter.MaxFilter(r * 2 + 1))
    o = Image.new('RGBA', im.size, OUT)
    o.putalpha(big)
    o.alpha_composite(im)
    return o

def board(d, a, b, wdt, fill=W_MID, hi=W_HI, seam=True):
    """一块木板：a→b 的中线、宽 wdt；上沿亮边、两道木纹、描边"""
    ax, ay = a
    bx, by = b
    L = math.hypot(bx - ax, by - ay)
    ux, uy = (bx - ax) / L, (by - ay) / L
    nx, ny = -uy, ux
    if ny > 0:
        nx, ny = -nx, -ny               # n 指向上方
    h = wdt * 0.5
    pts = [(ax + nx * h, ay + ny * h), (bx + nx * h, by + ny * h), (bx - nx * h, by - ny * h), (ax - nx * h, ay - ny * h)]
    poly(d, pts, fill, 2.6)
    line(d, [(ax + nx * (h - 2.6) + ux * 4, ay + ny * (h - 2.6) + uy * 4), (bx + nx * (h - 2.6) - ux * 4, by + ny * (h - 2.6) - uy * 4)], hi, 2.0)
    if seam:
        for k in range(2):
            t0 = rnd.uniform(0.12, 0.5)
            t1 = t0 + rnd.uniform(0.15, 0.35)
            off = rnd.uniform(-h * 0.35, h * 0.25)
            line(d, [(ax + ux * L * t0 + nx * off, ay + uy * L * t0 + ny * off), (ax + ux * L * t1 + nx * off, ay + uy * L * t1 + ny * off)], W_DARK, 1.4)

def nail(d, x, y, r=1.6):
    ellipse(d, (x - r, y - r, x + r, y + r), (60, 48, 40, 255), 0)

def save(im, name, ax=None, ay=None):
    path = f'{ROOT}/{name}.png'
    im.save(path)
    w, h = im.size
    print(f'"{name}": {{"w": {w}, "h": {h}, "ax": {ax if ax is not None else w / 2}, "ay": {ay if ay is not None else h}}},')
    return im

# ------------------------------------------------------------------ 宝箱
def make_chest():
    im, d = canvas(124, 104)
    # 箱身
    rrect(d, (14, 46, 110, 98), 5, W_MID, 3)
    for x in (38, 62, 86):
        line(d, [(x, 50), (x, 95)], W_DARK, 1.6)
    line(d, [(18, 50), (106, 50)], W_HI, 1.8)
    # 箱盖：半圆拱顶
    d.chord([14 * S, 10 * S, 110 * S, 82 * S], 180, 360, fill=W_LIGHT, outline=OUT, width=int(3 * S))
    for x in (38, 62, 86):
        line(d, [(x, 14 if x == 62 else 18), (x, 45)], W_MID2, 1.4)
    d.arc([20 * S, 16 * S, 104 * S, 76 * S], 200, 300, fill=W_HI, width=int(2.2 * S))
    # 盖沿铁条
    rrect(d, (11, 42, 113, 52), 3, IRON, 2.6)
    line(d, [(16, 44.5), (108, 44.5)], IRON_HI, 1.4)
    # 竖铁箍
    # 竖箍按拱形裁：重画一遍拱顶外缘的描边盖住箍头
    for x0 in (26, 86):
        # 箍在拱顶上的那截：沿椭圆贴着
        top = 46 - 36 * math.sqrt(max(0.0, 1 - ((x0 + 6 - 62) / 48.0) ** 2))
        rrect(d, (x0, top, x0 + 12, 98), 2, IRON, 2.4)
        line(d, [(x0 + 3, top + 4), (x0 + 3, 94)], IRON_HI, 1.4)
        for y in (top + 8, 60, 88):
            nail(d, x0 + 6, y, 1.8)
    d.arc([14 * S, 10 * S, 110 * S, 82 * S], 180, 360, fill=OUT, width=int(3 * S))
    # 金锁
    rrect(d, (52, 40, 72, 64), 4, GOLD, 2.6)
    line(d, [(56, 44), (68, 44)], GOLD_HI, 1.8)
    ellipse(d, (59, 48, 65, 54), OUT, 0)
    poly(d, [(60.5, 52), (63.5, 52), (64, 59), (60, 59)], OUT, 0)
    return finish(im)

# ------------------------------------------------------------------ 遗物宝石（灰白，染色用）
def make_gem():
    im, d = canvas(60, 78)
    top, ur, lr, bot, ll, ul = (30, 4), (54, 24), (48, 58), (30, 74), (12, 58), (6, 24)
    mid_t, mid_b = (30, 26), (30, 56)
    poly(d, [top, ur, lr, bot, ll, ul], (200, 200, 200, 255), 3.2)
    facets = [
        ([ul, top, mid_t], (246, 246, 246, 255)),
        ([top, ur, mid_t], (214, 214, 214, 255)),
        ([ul, mid_t, mid_b, ll], (232, 232, 232, 255)),
        ([mid_t, ur, lr, mid_b], (176, 176, 176, 255)),
        ([ll, mid_b, bot], (196, 196, 196, 255)),
        ([mid_b, lr, bot], (140, 140, 140, 255)),
    ]
    for pts, col in facets:
        poly(d, pts, col, 0)
    for a, b in [(ul, mid_t), (mid_t, ur), (mid_t, mid_b), (ll, mid_b), (mid_b, lr), (top, mid_t), (mid_b, bot)]:
        line(d, [a, b], (110, 110, 110, 255), 1.3)
    line(d, [top, ur, lr, bot, ll, ul, top], OUT, 3.2)
    # 高光
    line(d, [(14, 26), (24, 12)], (255, 255, 255, 255), 2.6)
    ellipse(d, (15, 32, 19, 36), (255, 255, 255, 255), 0)
    return finish(im)

def make_plinth():
    im, d = canvas(92, 66)
    # 底座 → 柱身 → 顶板（从下往上画）
    rrect(d, (6, 46, 86, 62), 5, ST_DARK, 3)
    line(d, [(12, 49), (80, 49)], ST_MID, 1.8)
    rrect(d, (20, 22, 72, 50), 3, ST_MID, 3)
    for x in (36, 56):
        line(d, [(x, 25), (x, 47)], ST_DARK, 1.4)
    line(d, [(24, 25), (24, 46)], ST_LIGHT, 1.8)
    rrect(d, (12, 12, 80, 28), 6, ST_LIGHT, 3)
    line(d, [(18, 16), (74, 16)], ST_HI, 2.0)
    line(d, [(16, 24), (76, 24)], ST_MID, 1.6)
    # 裂缝 + 苔
    line(d, [(62, 30), (66, 37), (63, 44)], ST_DARK, 1.4)
    ellipse(d, (10, 52, 22, 58), (96, 130, 60, 255), 0)
    ellipse(d, (66, 47, 78, 52), (96, 130, 60, 255), 0)
    return finish(im)

# ------------------------------------------------------------------ 水车磨坊
WW_W, WW_H = 360, 262
WHEEL_C = (284, 178)       # 轮心（合成图坐标）
WHEEL_R = 76

def make_wheel():
    R = WHEEL_R
    n = R * 2 + 8
    im, d = canvas(n, n)
    c = n / 2
    # 叶片：12 块，从轮圈往外伸
    for i in range(12):
        a = i * math.tau / 12
        ux, uy = math.cos(a), math.sin(a)
        vx, vy = -uy, ux
        r0, r1, hw = R - 26, R - 1, 9.0
        pts = [(c + ux * r0 + vx * hw, c + uy * r0 + vy * hw), (c + ux * r1 + vx * hw, c + uy * r1 + vy * hw),
               (c + ux * r1 - vx * hw, c + uy * r1 - vy * hw), (c + ux * r0 - vx * hw, c + uy * r0 - vy * hw)]
        poly(d, pts, W_LIGHT if i % 2 == 0 else W_MID, 2.6)
        line(d, [(c + ux * (r0 + 3) + vx * (hw - 2.5), c + uy * (r0 + 3) + vy * (hw - 2.5)),
                 (c + ux * (r1 - 3) + vx * (hw - 2.5), c + uy * (r1 - 3) + vy * (hw - 2.5))], W_HI, 1.6)
    # 外圈：两道木圈
    for r_out, r_in, col in [(R - 20, R - 31, W_DARK)]:
        ellipse(d, (c - r_out, c - r_out, c + r_out, c + r_out), col, 3)
        ellipse(d, (c - r_in, c - r_in, c + r_in, c + r_in), (0, 0, 0, 0), 3)
    d2 = ImageDraw.Draw(im)
    # 内圈挖空（上面那个 ellipse 填了透明 = 没挖空，这里用掩膜挖）
    mask = Image.new('L', im.size, 0)
    ImageDraw.Draw(mask).ellipse([(c - (R - 31) + 1.5) * S, (c - (R - 31) + 1.5) * S, (c + (R - 31) - 1.5) * S, (c + (R - 31) - 1.5) * S], fill=255)
    hole = Image.new('RGBA', im.size, (0, 0, 0, 0))
    im.paste(hole, (0, 0), mask)
    d = ImageDraw.Draw(im)
    d.arc([(c - R + 24) * S, (c - R + 24) * S, (c + R - 24) * S, (c + R - 24) * S], 200, 300, fill=W_LIGHT, width=int(2 * S))
    # 轮辐：6 根
    for i in range(6):
        a = i * math.tau / 6 + math.tau / 24
        board(d, (c + math.cos(a) * 12, c + math.sin(a) * 12), (c + math.cos(a) * (R - 28), c + math.sin(a) * (R - 28)), 9.0, W_MID, W_LIGHT, seam=False)
    # 轮毂：铁盘 + 螺栓
    ellipse(d, (c - 17, c - 17, c + 17, c + 17), IRON, 3)
    ellipse(d, (c - 12, c - 12, c + 12, c + 12), (96, 96, 106, 255), 0)
    for i in range(6):
        a = i * math.tau / 6
        nail(d, c + math.cos(a) * 9, c + math.sin(a) * 9, 2.0)
    ellipse(d, (c - 5, c - 5, c + 5, c + 5), (40, 40, 46, 255), 0)
    d.arc([(c - 14) * S, (c - 14) * S, (c + 14) * S, (c + 14) * S], 200, 290, fill=IRON_HI, width=int(2 * S))
    return finish(im)

def make_mill_house():
    im, d = canvas(WW_W, WW_H)
    # 石基
    rrect(d, (100, 212, 262, 250), 6, ST_DARK, 3)
    x = 104
    row = 0
    for y0, y1 in [(214, 231), (231, 248)]:
        x = 104 + (12 if row else 0)
        while x < 256:
            wdt = rnd.uniform(22, 32)
            x1 = min(x + wdt, 258)
            rrect(d, (x, y0 + 1, x1 - 2, y1 - 1), 4, ST_MID if (int(x) // 7) % 2 else ST_LIGHT, 2.2)
            line(d, [(x + 3, y0 + 4), (x1 - 6, y0 + 4)], ST_HI, 1.4)
            x = x1
        row += 1
    # 墙：竖木板
    wall = (110, 140, 252, 216)
    poly(d, [(wall[0], wall[1]), (wall[2], wall[1]), (wall[2], wall[3]), (wall[0], wall[3])], W_MID, 3)
    xs = list(range(wall[0] + 14, wall[2], 15))
    for i, xx in enumerate(xs):
        line(d, [(xx, wall[1] + 3), (xx, wall[3] - 3)], W_DARK, 1.6)
    # 角柱 + 横梁
    for x0 in (wall[0] - 2, wall[2] - 12):
        rrect(d, (x0, wall[1] - 2, x0 + 14, wall[3] + 2), 2, W_LIGHT, 2.6)
        line(d, [(x0 + 4, wall[1] + 2), (x0 + 4, wall[3] - 2)], W_HI, 1.4)
    rrect(d, (wall[0] - 4, 186, wall[2] + 4, 196), 2, W_LIGHT, 2.4)
    line(d, [(wall[0], 188.5), (wall[2], 188.5)], W_HI, 1.4)
    # 门
    rrect(d, (160, 158, 202, 220), 3, W_DARK, 3)
    rrect(d, (165, 163, 197, 220), 2, (70, 46, 30, 255), 0)
    for xx in (173, 181, 189):
        line(d, [(xx, 165), (xx, 218)], (56, 38, 26, 255), 1.4)
    line(d, [(166, 176), (196, 176)], IRON, 3)
    line(d, [(166, 205), (196, 205)], IRON, 3)
    ellipse(d, (189, 189, 195, 195), GOLD, 1.4)
    # 小窗
    rrect(d, (124, 150, 148, 174), 3, W_LIGHT, 2.6)
    rrect(d, (128, 154, 144, 170), 1, (46, 40, 52, 255), 0)
    line(d, [(136, 154), (136, 170)], W_LIGHT, 2)
    line(d, [(128, 162), (144, 162)], W_LIGHT, 2)
    # 屋顶：正面山墙 + 往后斜上去的两坡木板
    G = (180, 76)                 # 山墙尖
    FL, FR = (94, 146), (268, 146)
    B = (12, -46)                 # 屋顶往后（往上）的进深
    gable = [(FL[0] + 18, FL[1] - 2), G, (FR[0] - 18, FR[1] - 2)]
    poly(d, gable, W_MID2, 3)
    for xx in range(126, 240, 14):
        top = G[1] + abs(xx - G[0]) * (FL[1] - G[1]) / (G[0] - FL[0]) + 4
        line(d, [(xx, top), (xx, FL[1] - 4)], W_DARK, 1.4)
    # 两坡：每坡 3 块板，从后往前画（前面的压住后面的下沿）
    for side in (0, 1):
        A0, A1 = (FL, G) if side == 0 else (G, FR)
        for j in (2, 1, 0):
            t0, t1 = j / 3.0, (j + 1) / 3.0 + 0.04
            p0 = (A0[0] + B[0] * t0, A0[1] + B[1] * t0)
            p1 = (A1[0] + B[0] * t0, A1[1] + B[1] * t0)
            p2 = (A1[0] + B[0] * t1, A1[1] + B[1] * t1)
            p3 = (A0[0] + B[0] * t1, A0[1] + B[1] * t1)
            jit = rnd.uniform(-2, 2)
            pts = [(p0[0], p0[1] + jit), (p1[0], p1[1]), (p2[0], p2[1]), (p3[0], p3[1] + jit)]
            poly(d, pts, W_MID if (j + side) % 2 else W_MID2, 2.8)
            line(d, [((p3[0] * 0.9 + p2[0] * 0.1), (p3[1] * 0.9 + p2[1] * 0.1) + 3), ((p3[0] * 0.1 + p2[0] * 0.9), (p3[1] * 0.1 + p2[1] * 0.9) + 3)], W_HI, 1.8)
            for k in range(2):
                tt = rnd.uniform(0.2, 0.7)
                q0 = (p0[0] + (p1[0] - p0[0]) * tt, p0[1] + (p1[1] - p0[1]) * tt)
                q1 = (p3[0] + (p2[0] - p3[0]) * tt, p3[1] + (p2[1] - p3[1]) * tt)
                line(d, [((q0[0] * 0.65 + q1[0] * 0.35), (q0[1] * 0.65 + q1[1] * 0.35)), ((q0[0] * 0.4 + q1[0] * 0.6) + 8, (q0[1] * 0.4 + q1[1] * 0.6))], W_DARK, 1.3)
    # 屋脊压条 + 山墙封檐板（最靠前）
    board(d, (G[0] - 2, G[1] + 2), (G[0] + B[0], G[1] + B[1]), 10, W_LIGHT, W_HI, seam=False)
    board(d, (FL[0] - 4, FL[1] + 4), (G[0] + 1, G[1] - 3), 13, W_LIGHT, W_HI)
    board(d, (G[0] - 1, G[1] - 3), (FR[0] + 4, FR[1] + 4), 13, W_LIGHT, W_HI)
    nail(d, G[0], G[1] + 3, 2.2)
    # 轮轴座：右墙伸出一截木梁接轮毂
    rrect(d, (246, WHEEL_C[1] - 7, WHEEL_C[0], WHEEL_C[1] + 7), 2, W_DARK, 2.6)
    return finish(im)

# ------------------------------------------------------------------ 前哨：箭塔塔身 + 木屋 + 木栅栏
OP_W, OP_H = 320, 262
def make_outpost():
    body = Image.open(f'{SRC}/buildings/tower_body.png').convert('RGBA')
    top = Image.open(f'{SRC}/buildings/tower_top.png').convert('RGBA')
    wh = Image.open(f'{SRC}/buildings/warehouse.png').convert('RGBA')
    fence = Image.open(f'{SRC}/decor/fence.png').convert('RGBA')
    k_t = 0.92
    tw, th = int(body.size[0] * k_t), int(body.size[1] * k_t)
    body = body.resize((tw, th), Image.LANCZOS)
    top = top.resize((tw, th), Image.LANCZOS)
    tx, ty = 18, OP_H - th - 22        # 塔在左后
    k_h = 0.62
    hw_, hh_ = int(wh.size[0] * k_h), int(wh.size[1] * k_h)
    hut = wh.resize((hw_, hh_), Image.LANCZOS)
    hx, hy = OP_W - hw_ - 8, OP_H - hh_ - 4
    c_body = Image.new('RGBA', (OP_W, OP_H), (0, 0, 0, 0))
    c_body.alpha_composite(body, (tx, ty))
    c_top = Image.new('RGBA', (OP_W, OP_H), (0, 0, 0, 0))
    c_top.alpha_composite(top, (tx, ty))
    c_front = Image.new('RGBA', (OP_W, OP_H), (0, 0, 0, 0))
    c_front.alpha_composite(hut, (hx, hy))
    # 栅栏：塔脚前一段、屋前左侧一段
    fk = 0.85
    f = fence.resize((int(fence.size[0] * fk), int(fence.size[1] * fk)), Image.LANCZOS)
    c_front.alpha_composite(f, (6, OP_H - f.size[1] - 2))
    # 蓝旗：塔顶右侧插一面（和主城同色）
    d = ImageDraw.Draw(c_front)
    feet_y = ty + 92.0 * k_t            # 弓手脚底（tower_top 挑檐那一层），和 building.gd 的 TOWER_FEET_Y 对应
    feet_x = tx + tw / 2.0
    full = c_body.copy()
    full.alpha_composite(c_top)
    full.alpha_composite(c_front)
    print('outpost archer feet', feet_x, feet_y, 'tower scale', k_t)
    return c_body, c_top, c_front, full

# ------------------------------------------------------------------ 废墟：塌掉的窝（巢穴受损图只留下半截碎石，去饱和、黏液发干）
def make_ruins():
    src = Image.open(f'{SRC}/buildings/hive_damaged.png').convert('RGBA')
    A = np.asarray(src).astype(float)
    w, h = src.size
    out = np.zeros_like(A)
    cut = int(h * 0.42)
    band = A[cut:].copy()
    bh = band.shape[0]
    # 上沿：中间高两边低的一道锯齿弧（塌成一堆的样子），弧线以上全部去掉
    xs = np.arange(w)
    t = (xs - w / 2) / (w / 2)
    edge = (bh * 0.10 + bh * 0.34 * t ** 2 + 7 * np.sin(xs * 0.21) + 5 * np.sin(xs * 0.07 + 1.3)).astype(int)
    for x in range(w):
        band[:max(0, edge[x]), x, 3] = 0
    # 洞口那块（中间偏下的暗红）挖掉，换成左右两边的碎石
    r, g, b = band[..., 0], band[..., 1], band[..., 2]
    mouth = (r > g + 25) & (r > b) & (band[..., 3] > 0)
    cx0, cx1 = int(w * 0.33), int(w * 0.70)
    m2 = np.zeros_like(mouth)
    m2[:, cx0:cx1] = mouth[:, cx0:cx1]
    left = band[:, int(w * 0.05):int(w * 0.05) + (cx1 - cx0)].copy()
    sub = band[:, cx0:cx1]
    sel = m2[:, cx0:cx1]
    sub[sel] = left[sel]
    band[:, cx0:cx1] = sub
    # 去饱和 + 压暗，绿黏液变成发干的橄榄褐
    rgb = band[..., :3]
    lum = (rgb * [0.3, 0.59, 0.11]).sum(axis=2, keepdims=True)
    gooish = (rgb[..., 1] > rgb[..., 0] + 20) & (rgb[..., 1] > rgb[..., 2] + 20)
    rgb = rgb * 0.45 + lum * 0.55
    rgb = rgb * 0.82
    rgb[gooish] = rgb[gooish] * [1.0, 0.9, 0.6] + np.array([18, 12, 0])
    band[..., :3] = np.clip(rgb, 0, 255)
    out = band
    im = Image.fromarray(out.astype(np.uint8))
    im = im.crop(im.getbbox())
    im = outlined(im, 1)
    return im

if __name__ == '__main__':
    import os
    os.makedirs(f'{ROOT}/props', exist_ok=True)
    os.makedirs(f'{ROOT}/buildings', exist_ok=True)
    save(make_chest(), 'props/chest')
    save(make_gem(), 'props/relic_gem')
    save(make_plinth(), 'props/plinth')
    house = make_mill_house()
    wheel = make_wheel()
    save(house, 'buildings/waterwheel_house', 180.0, 252)
    save(wheel, 'buildings/waterwheel_wheel', wheel.size[0] / 2, wheel.size[1] / 2)
    full = house.copy()
    full.alpha_composite(wheel, (WHEEL_C[0] - wheel.size[0] // 2, WHEEL_C[1] - wheel.size[1] // 2))
    save(full, 'buildings/waterwheel', 180.0, 252)
    print('wheel center (canvas)', WHEEL_C, 'r', WHEEL_R)
    b, t, f, full = make_outpost()
    save(b, 'buildings/outpost_body', OP_W / 2, OP_H)
    save(t, 'buildings/outpost_top', OP_W / 2, OP_H)
    save(f, 'buildings/outpost_front', OP_W / 2, OP_H)
    save(full, 'buildings/outpost', OP_W / 2, OP_H)
    save(make_ruins(), 'buildings/ruins')
