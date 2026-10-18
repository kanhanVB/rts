"""把生图模型出的原始素材（1254px 大图）整理成游戏用的尺寸。
用法：python3 tools/prepare_art.py <原始 art 目录> <项目根目录>
- 裁掉透明边，按类别缩放到合适大小，写到 <项目>/art/
- 生成 art_data.gd：每张图的尺寸和锚点（单位=脚底中心，建筑/资源=底边中心，其余=中心）
"""
import sys, os, glob, json
from PIL import Image

SRC, DST = sys.argv[1], os.path.join(sys.argv[2], "art")

def trim(im):
    a = im.getchannel("A").point(lambda v: 255 if v > 10 else 0)
    bb = a.getbbox()
    return im.crop(bb)

def feet_x(im):
    """脚底中心：最下面 12% 行里不透明像素的平均 x（动作图的武器伸出去也不会把人挪位）"""
    w, h = im.size
    a = im.getchannel("A")
    y0 = int(h * 0.88)
    xs, n = 0, 0
    px = a.load()
    for y in range(y0, h):
        for x in range(0, w, 2):
            if px[x, y] > 128:
                xs += x; n += 1
    return xs / n if n else w / 2

data = {}
def save(rel, im, ax, ay):
    out = os.path.join(DST, rel)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    im.save(out, optimize=True)
    data[rel[:-4]] = {"w": im.size[0], "h": im.size[1], "ax": round(ax, 1), "ay": round(ay, 1)}

def key_out(im):
    """没有透明通道的图（纯色底：白底或 #FF00FF 品红都行）：取四角颜色当背景抠掉，边缘柔化 + 去色溢"""
    import numpy as np
    a = np.asarray(im).astype(float)
    if a[..., 3].min() < 250:
        return im    # 本来就是透明图
    h, w = a.shape[:2]
    c = max(4, min(h, w) // 40)
    corners = np.concatenate([a[:c, :c, :3].reshape(-1, 3), a[:c, -c:, :3].reshape(-1, 3),
                              a[-c:, :c, :3].reshape(-1, 3), a[-c:, -c:, :3].reshape(-1, 3)])
    bg = np.median(corners, axis=0)
    dist = np.sqrt(((a[..., :3] - bg) ** 2).sum(axis=2))
    alpha = np.clip((dist - 40.0) / 50.0, 0.0, 1.0)
    # 白底：只抠和画布边缘连通的背景（角色身上的白色高光不会被抠掉；被线条围住的小块白底会留下，所以首选品红底）
    try:
        if bg.min() < 200:
            raise ImportError   # 品红等彩色底：全图抠
        import cv2
        n, lab = cv2.connectedComponents((alpha < 1).astype("uint8"), connectivity=4)
        edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
        inner = (alpha < 1) & ~np.isin(lab, list(edge))
        alpha[inner] = 1.0
    except ImportError:
        pass
    # 去色溢：半透明边缘里混进来的背景色按比例减掉
    soft = (alpha > 0) & (alpha < 1)
    for ch in range(3):
        v = a[..., ch]
        v[soft] = np.clip((v[soft] - bg[ch] * (1 - alpha[soft])) / np.maximum(alpha[soft], 0.05), 0, 255)
    if bg[0] > 200 and bg[2] > 200 and bg[1] < 80:
        # 品红底：描边上残留的紫边（红蓝都比绿高一截）压回去
        r, g, b = a[..., 0], a[..., 1], a[..., 2]
        m = (alpha > 0) & (np.minimum(r, b) - g > 18)
        a[..., 0][m] = np.minimum(r[m], g[m] + 18)
        a[..., 2][m] = np.minimum(b[m], g[m] + 12)
    a[..., 3] = alpha * 255
    return Image.fromarray(a.astype("uint8"), "RGBA")

# 地图 / 建筑 / 树石摆设统一"压灰"，和低饱和的角色画风对上（1.0 = 不处理）
MUTE_SAT, MUTE_VAL, MUTE_WARM = 0.62, 1.06, 0.08
MUTED = ("map/", "resources/", "decor/")   # 建筑 / UI 是按角色画风新画的，本来就低饱和，不再压

def mute(im):
    import numpy as np
    from PIL import ImageEnhance
    alpha = im.getchannel("A") if im.mode == "RGBA" else None
    rgb = ImageEnhance.Color(im.convert("RGB")).enhance(MUTE_SAT)
    a = np.asarray(rgb).astype(float) * MUTE_VAL
    a = a * (1 - MUTE_WARM) + np.array([150.0, 138.0, 112.0]) * MUTE_WARM   # 往暖灰褐靠一点
    out = Image.fromarray(np.clip(a, 0, 255).astype("uint8"), "RGB")
    if alpha is not None:
        out = out.convert("RGBA"); out.putalpha(alpha)
    return out

def load(rel):
    p = os.path.join(SRC, rel)
    if not os.path.exists(p):
        return None
    im = trim(key_out(Image.open(p).convert("RGBA")))
    return mute(im) if rel.startswith(MUTED) else im

def scaled(im, k):
    return im.resize((max(1, round(im.size[0] * k)), max(1, round(im.size[1] * k))), Image.LANCZOS)

def pose_ratio(idle, im, has_skin):
    import numpy as np
    def areas(x):
        a = np.asarray(x).astype(int)
        r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
        sk = (al > 200) & (r > 170) & (g > 110) & (g < 185) & (b < 110) & (r - g > 25) & (r - g < 90)
        return sk.sum(), (al > 200).sum()
    si, ai = areas(idle)
    sp, ap = areas(im)
    ka = (ai / max(ap, 1)) ** 0.5
    if has_skin and si > 200 and sp > 200:
        return (ka * (si / sp) ** 0.5) ** 0.5
    return ka

# ---- 单位：同一个兵种所有姿势用同一个缩放系数（以站姿身高为准），锚点 = 脚底中心
UNIT_H = 160
for key in ["worker", "engineer", "swordsman", "archer", "goo"]:
    idle = load(f"units/{key}_idle.png")
    if idle is None:
        continue
    k = (UNIT_H * (0.75 if key == "goo" else 1.0)) / idle.size[1]
    for pose in ["idle", "act", "carry", "dead"]:
        im = load(f"units/{key}_{pose}.png")
        if im is None:
            continue
        # 动作图常常和站姿图画得不一样大：按"角色画了多少像素"（不透明面积 + 皮肤面积）对齐到站姿的大小
        im = scaled(im, k * pose_ratio(idle, im, key != "goo"))
        save(f"units/{key}_{pose}.png", im, feet_x(im) if pose != "dead" else im.size[0] / 2, im.size[1])

# ---- 建筑：统一宽度，锚点 = 底边中心
def load_raw(rel):
    im = key_out(Image.open(os.path.join(SRC, rel)).convert("RGBA"))
    return mute(im) if rel.startswith(MUTED) else im

done = set()
for p in sorted(glob.glob(os.path.join(SRC, "buildings/*.png"))):
    rel = os.path.relpath(p, SRC)
    if rel in done:
        continue
    dmg = rel[:-4] + "_damaged.png"
    if os.path.exists(os.path.join(SRC, dmg)) and not rel.endswith("_damaged.png"):
        # 正常 / 受损两张同画布同位置：按正常版的范围裁、同一个缩放，受损时房子不会跳
        a, b = load_raw(rel), load_raw(dmg)
        bb = a.getchannel("A").point(lambda v: 255 if v > 10 else 0).getbbox()
        k = 320 / (bb[2] - bb[0])
        for r2, im in [(rel, a), (dmg, b)]:
            ib = im.getchannel("A").point(lambda v: 255 if v > 10 else 0).getbbox()
            u = (min(bb[0], ib[0]), min(bb[1], ib[1]), max(bb[2], ib[2]), max(bb[3], ib[3]))
            c = scaled(im.crop(u), k)
            # 锚点 = 正常版底边中心（换算到这张裁剪后的坐标）
            save(r2, c, ((bb[0] + bb[2]) / 2 - u[0]) * k, (bb[3] - u[1]) * k)
            done.add(r2)
        continue
    im = load(rel)
    im = scaled(im, 320 / im.size[0])
    save(rel, im, im.size[0] / 2, im.size[1])

# ---- 资源：矿三档共用满矿的系数（越采越小）；树按高度
ore = load("resources/ore_full.png")
if ore is not None:
    k = 160 / ore.size[0]
    for s in ["full", "half", "low"]:
        im = load(f"resources/ore_{s}.png")
        if im is not None:
            im = scaled(im, k)
            save(f"resources/ore_{s}.png", im, im.size[0] / 2, im.size[1])
for p in glob.glob(os.path.join(SRC, "resources/tree_*.png")):
    rel = os.path.relpath(p, SRC)
    im = load(rel)
    im = scaled(im, 230 / im.size[1])
    save(rel, im, feet_x(im), im.size[1])

# ---- 装饰 / 道具 / 特效
def fit(rel, mx, anchor="center"):
    im = load(rel)
    if im is None:
        return
    im = scaled(im, mx / max(im.size))
    if anchor == "bottom":
        save(rel, im, im.size[0] / 2, im.size[1])
    else:
        save(rel, im, im.size[0] / 2, im.size[1] / 2)
for p in glob.glob(os.path.join(SRC, "decor/*.png")):
    fit(os.path.relpath(p, SRC), 128, "bottom")
for p in glob.glob(os.path.join(SRC, "items/*.png")):
    fit(os.path.relpath(p, SRC), 128)
for p in glob.glob(os.path.join(SRC, "fx/*.png")):
    fit(os.path.relpath(p, SRC), 160)

# ---- 地图分析：森林遮罩 + 土路中心线（都换算到 1280×720 世界坐标）
def analyze_map(im):
    import numpy as np
    a = np.asarray(im.resize((1280, 720), Image.LANCZOS)).astype(int)
    lum = a.mean(axis=2)
    cs = 16
    gh, gw = 720 // cs, 1280 // cs
    cand = np.zeros((gh, gw), bool)
    for y in range(gh):
        for x in range(gw):
            cand[y, x] = (lum[y*cs:(y+1)*cs, x*cs:(x+1)*cs] < 55).mean() > 0.12    # 树冠的粗描边很密
    # 闭运算：树冠中间的亮色高光格子也算森林
    pad = np.pad(cand, 1)
    nb = sum(pad[1+dy:gh+1+dy, 1+dx:gw+1+dx] for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx)
    m = cand | (nb >= 5)
    # 只保留和地图边缘连通的大片树林（场地中间的零星灌木不算）
    keep = np.zeros_like(m)
    stack = [(y, x) for y in range(gh) for x in range(gw) if (y in (0, gh-1) or x in (0, gw-1)) and m[y, x]]
    while stack:
        y, x = stack.pop()
        if keep[y, x]:
            continue
        keep[y, x] = True
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < gh and 0 <= nx < gw and m[ny, nx] and not keep[ny, nx]:
                stack.append((ny, nx))
    forest = ["".join("1" if keep[y, x] else "0" for x in range(gw)) for y in range(gh)]
    # 土路：暖黄沙土色像素，按列取中心
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    sand = (r > 190) & (g > 150) & (b < 140) & (r - b > 70) & (r > g)
    cols = [x for x in range(0, 1280, 4) if sand[:, x].sum() > 12]
    road = []
    if cols:
        x0, x1 = cols[0] + 12, cols[-1] - 12
        n = max(2, int((x1 - x0) / 140) + 1)
        for i in range(n):
            x = int(x0 + (x1 - x0) * i / (n - 1))
            ys = np.where(sand[:, max(0, x-6):x+6].any(axis=1))[0]
            if len(ys):
                # 只取最大一段连续沙土（排除远处零星黄花）
                segs = np.split(ys, np.where(np.diff(ys) > 3)[0] + 1)
                seg = max(segs, key=len)
                road.append((x, int(seg.mean())))
    return forest, road

# ---- UI
for rel, mx in [("ui/panel.png", 384), ("ui/parchment.png", 384), ("ui/portrait_frame.png", 192),
                ("ui/banner.png", 640), ("ui/icon_victory.png", 480), ("ui/icon_defeat.png", 480),
                ("ui/icon_worker.png", 128), ("ui/icon_hero.png", 128), ("ui/icon_wave.png", 128),
                ("ui/cursor.png", 44)]:
    fit(rel, mx)
# 头像框：中间那块实心底挖空（头像画在框下面，框中间不透明会把头像盖住）
pf = os.path.join(DST, "ui/portrait_frame.png")
if os.path.exists(os.path.join(SRC, "ui/portrait_frame.png")):
    import numpy as np, cv2
    a = np.asarray(Image.open(pf).convert("RGBA")).copy()
    h, w = a.shape[:2]
    c = a[h // 2, w // 2, :3].astype(int)
    near = (np.abs(a[..., :3].astype(int) - c).sum(axis=2) < 60) & (a[..., 3] > 200)
    n, lab = cv2.connectedComponents(near.astype("uint8"), connectivity=4)
    hole = lab == lab[h // 2, w // 2]
    hole = cv2.dilate(hole.astype("uint8"), np.ones((3, 3), np.uint8)).astype(bool)   # 带上一圈抗锯齿边
    a[..., 3][hole] = 0
    Image.fromarray(a, "RGBA").save(pf, optimize=True)
btn = load("ui/button.png")
if btn is not None:
    k = 360 / btn.size[0]
    for s in ["", "_hover", "_pressed", "_disabled"]:
        im = load(f"ui/button{s}.png")
        if im is not None:
            im = scaled(im, k)
            save(f"ui/button{s}.png", im, im.size[0] / 2, im.size[1] / 2)

# ---- 地图：压灰后拷贝
m = os.path.join(SRC, "map/map.png")
if os.path.exists(m):
    im = Image.open(m).convert("RGB")
    os.makedirs(os.path.join(DST, "map"), exist_ok=True)
    mute(im).save(os.path.join(DST, "map/map.png"), optimize=True)
    data["map/map"] = {"w": im.size[0], "h": im.size[1], "ax": 0, "ay": 0}
    forest, road = analyze_map(im)   # 用原图分析（颜色阈值按原图调的）

else:
    forest, road = [], []

with open(os.path.join(sys.argv[2], "art_data.gd"), "w", encoding="utf-8") as f:
    f.write("## 由 tools/prepare_art.py 自动生成，别手改：每张图的尺寸和锚点（像素）\n")
    f.write("class_name ArtData\nextends RefCounted\n\nconst SPRITES := ")
    f.write(json.dumps(data, ensure_ascii=False, indent=1).replace("    ", "\t"))
    f.write("\n\n## 地图上画着森林的格子（16px 一格，1 = 树林，单位不该走进去、不能盖房）\n")
    f.write("const FOREST_CELL := 16\nconst FOREST := [\n" + "".join('\t"%s",\n' % r for r in forest) + "]\n")
    f.write("\n## 地图上土路的中心线（1280×720 世界坐标，从基地端到巢穴端）\n")
    f.write("const ROAD := [" + ", ".join("Vector2(%d, %d)" % p for p in road) + "]\n")
print(len(data), "sprites")
