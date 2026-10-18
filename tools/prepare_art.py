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

def load(rel):
    p = os.path.join(SRC, rel)
    return trim(Image.open(p).convert("RGBA")) if os.path.exists(p) else None

def scaled(im, k):
    return im.resize((max(1, round(im.size[0] * k)), max(1, round(im.size[1] * k))), Image.LANCZOS)

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
        im = scaled(im, k)
        save(f"units/{key}_{pose}.png", im, feet_x(im) if pose != "dead" else im.size[0] / 2, im.size[1])

# ---- 建筑：统一宽度，锚点 = 底边中心
for p in glob.glob(os.path.join(SRC, "buildings/*.png")):
    rel = os.path.relpath(p, SRC)
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

# ---- UI
for rel, mx in [("ui/panel.png", 384), ("ui/parchment.png", 384), ("ui/portrait_frame.png", 192),
                ("ui/banner.png", 640), ("ui/icon_victory.png", 480), ("ui/icon_defeat.png", 480),
                ("ui/icon_worker.png", 128), ("ui/icon_hero.png", 128), ("ui/icon_wave.png", 128),
                ("ui/cursor.png", 44)]:
    fit(rel, mx)
btn = load("ui/button.png")
if btn is not None:
    k = 360 / btn.size[0]
    for s in ["", "_hover", "_pressed", "_disabled"]:
        im = load(f"ui/button{s}.png")
        if im is not None:
            im = scaled(im, k)
            save(f"ui/button{s}.png", im, im.size[0] / 2, im.size[1] / 2)

# ---- 地图：原样拷贝
m = os.path.join(SRC, "map/map.png")
if os.path.exists(m):
    im = Image.open(m).convert("RGB")
    os.makedirs(os.path.join(DST, "map"), exist_ok=True)
    im.save(os.path.join(DST, "map/map.png"), optimize=True)
    data["map/map"] = {"w": im.size[0], "h": im.size[1], "ax": 0, "ay": 0}

with open(os.path.join(sys.argv[2], "art_data.gd"), "w", encoding="utf-8") as f:
    f.write("## 由 tools/prepare_art.py 自动生成，别手改：每张图的尺寸和锚点（像素）\n")
    f.write("class_name ArtData\nextends RefCounted\n\nconst SPRITES := ")
    f.write(json.dumps(data, ensure_ascii=False, indent=1).replace("    ", "\t"))
    f.write("\n")
print(len(data), "sprites")
