"""箭塔贴图：从主城贴图里拼（同一套画风）——左塔楼的塔身（左半镜像成对称）+ 城墙垛口（中间垛口为轴镜像）+ 一圈石砌挑檐。
用法：python3 tools/make_tower.py art/buildings
输出同尺寸画布（150×196）的分层图，游戏里按 塔身 → 弓手 → 挑檐 的顺序叠画：
  tower_body / tower_body2：塔身 + 垛口（二级：垛口插蓝旗、塔身挂蓝底白十字长旗），画在弓手后面
  tower_top：挑檐石条，画在弓手前面挡住脚
  tower / tower2：合成图（命令卡图标 / 工地长出来用）
弓手脚底 y = ledge_y + 9（building.gd 的 TOWER_FEET_Y），二级两名弓手 x 偏移 ±26"""
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
SRC = '/data/rts/art/buildings/base.png'
DST = sys.argv[1] if len(sys.argv) > 1 else '/data/work/tower'
base = Image.open(SRC).convert('RGBA')
A = np.asarray(base).copy()
OUT = (39, 36, 33, 255)
MID = (176, 165, 146, 255)
HI = (240, 226, 204, 255)
SEAM = (112, 104, 90, 255)

def is_blue(a):
    r, g, b = a[..., 0].astype(int), a[..., 1].astype(int), a[..., 2].astype(int)
    return (b > r + 30) & (b > g + 5)

def mirror_left(arr, cx):
    L = arr[:, :cx]
    return np.concatenate([L, L[:, ::-1]], axis=1)

def outlined(im, r=2):
    """外轮廓补一圈深描边（裁断处也有描边，和原图的厚外轮廓一致）"""
    a = im.getchannel('A').point(lambda v: 255 if v > 90 else 0)
    big = a.filter(ImageFilter.MaxFilter(r * 2 + 1))
    o = Image.new('RGBA', im.size, OUT)
    o.putalpha(big)
    o.alpha_composite(im)
    return o

# 塔身：左塔楼 y 104..229，左半 0..58 镜像
body = A[104:, 0:58].copy()
body[is_blue(body)] = [0, 0, 0, 0]
body = mirror_left(body, 58)
# 垛口：城墙 y 79..136，以中间垛口中心 x=160 为轴，左半 114..160 镜像（避开塔楼屋檐的描边）
par = A[79:136, 114:160].copy()
par[is_blue(par)] = [0, 0, 0, 0]
# 塔楼屋檐的深色描边残留：左边 4 列里接近黑色的像素清掉
dark = (par[..., :3].astype(int).sum(axis=2) < 200)
par[:, :4][dark[:, :4]] = [0, 0, 0, 0]
par = mirror_left(par, par.shape[1])

W, H = 150, 196
pad = 2
bim = Image.fromarray(body)
by = H - bim.size[1] - pad
pim = Image.fromarray(par)
pw = 108
ph = round(pim.size[1] * pw / pim.size[0] * 0.82)
pim = pim.resize((pw, ph), Image.LANCZOS)
ledge_y = by + 14
px0 = (W - pw) // 2
py0 = ledge_y - ph + 10

def make_body(banner=False):
    c = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    c.alpha_composite(bim, ((W - bim.size[0]) // 2, by))
    if banner:
        d = ImageDraw.Draw(c)
        cx = W // 2
        y0 = ledge_y + 12
        # 蓝底白十字的长条旗（挂在挑檐下，二级塔的标志）
        pts = [(cx - 13, y0), (cx + 13, y0), (cx + 13, y0 + 40), (cx, y0 + 50), (cx - 13, y0 + 40)]
        d.polygon(pts, fill=(70, 105, 160, 255), outline=OUT)
        d.line(pts + [pts[0]], fill=OUT, width=3)
        d.line([(cx, y0 + 8), (cx, y0 + 38)], fill=(236, 230, 212, 255), width=4)
        d.line([(cx - 8, y0 + 20), (cx + 8, y0 + 20)], fill=(236, 230, 212, 255), width=4)
        d.line([(cx - 11, y0 + 3), (cx + 11, y0 + 3)], fill=(110, 145, 200, 255), width=2)
    return outlined(c, 1)

def make_par(flags=False):
    c = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    c.alpha_composite(pim, (px0, py0))
    c = outlined(c, 2)
    d = ImageDraw.Draw(c)
    if flags:
        fl = base.crop((10, 0, 66, 34))   # 主城左塔的旗 + 旗杆顶
        fl = fl.resize((round(fl.size[0] * 0.8), round(fl.size[1] * 0.8)), Image.LANCZOS)
        tips = [(px0 + 12, py0 + 4), (px0 + pw - 12, py0 + 4)]
        for k, (tx, ty) in enumerate(tips):
            f = fl if k == 0 else fl.transpose(Image.FLIP_LEFT_RIGHT)
            pole_x = 38 if k == 0 else fl.size[0] - 38
            d.line([(tx, ty + 30), (tx, ty + 8)], fill=OUT, width=4)
            c.alpha_composite(f, (int(tx - pole_x), int(ty - 18)))
    return c

def make_top(flags=False):
    c = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(c)
    # 挑檐：一排石块（浅色顶面 + 暗缝 + 厚描边）
    lx0, lx1 = px0 - 6, px0 + pw + 6
    n = 6
    bw = (lx1 - lx0) / n
    for i in range(n):
        x0 = lx0 + i * bw
        d.rounded_rectangle([x0, ledge_y, x0 + bw, ledge_y + 12], radius=3, fill=MID, outline=OUT, width=3)
        d.line([(x0 + 4, ledge_y + 3), (x0 + bw - 4, ledge_y + 3)], fill=HI, width=2)
        d.line([(x0 + 4, ledge_y + 9), (x0 + bw - 4, ledge_y + 9)], fill=SEAM, width=2)
    return c

body1 = make_body(False)
body1.alpha_composite(make_par(False))
body2 = make_body(True)
body2.alpha_composite(make_par(True))
top1 = make_top(False)
top2 = make_top(True)
body1.save(f'{DST}/tower_body.png'); body2.save(f'{DST}/tower_body2.png')
top1.save(f'{DST}/tower_top.png')    # 二级的挑檐和一级一样，不单独存
f1 = body1.copy(); f1.alpha_composite(top1); f1.save(f'{DST}/tower.png')
f2 = body2.copy(); f2.alpha_composite(top2); f2.save(f'{DST}/tower2.png')
print('ledge_y', ledge_y, 'py0', py0, 'px0', px0, 'pw', pw, 'W', W, 'H', H)

if DST == '/data/work/tower':
    arc = Image.open('/data/rts/art/units/archer_idle.png').convert('RGBA')
    ah = 46
    arc = arc.resize((round(arc.size[0] * ah / arc.size[1]), ah), Image.LANCZOS)
    def with_archers(bd, tp, xs):
        c = bd.copy()
        for x in xs:
            c.alpha_composite(arc, (int(W / 2 + x - arc.size[0] / 2), int(ledge_y + 9 - ah)))
        c.alpha_composite(tp)
        return c
    bg = Image.new('RGBA', (W * 2 + 20, H), (120, 160, 90, 255))
    bg.alpha_composite(with_archers(body1, top1, [0]), (0, 0))
    bg.alpha_composite(with_archers(body2, top2, [-26, 26]), (W + 20, 0))
    bg = bg.resize((bg.size[0] * 3, bg.size[1] * 3), Image.LANCZOS)
    bg.save('/data/work/tower/preview.png')
