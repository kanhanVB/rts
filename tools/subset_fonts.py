#!/usr/bin/env python3
"""把字体裁成 GB2312 + 游戏代码里用到的字，减小体积。

用法: python3 tools/subset_fonts.py <SourceHanSansCN-Bold.otf> <SourceHanSansCN-Medium.otf>
原始字体: https://github.com/adobe-fonts/source-han-sans (SubsetOTF/CN，OFL)

字体参照王国保卫战：起源 中文版（它用的是系统黑体 苹方，思源黑体是同类开源字体）：
- Bold：按钮 / 标题 / 顶栏 / 提示条 / 地图上的标签
- Medium：说明文字、数值面板
"""
import glob, os, sys
from fontTools import subset

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "fonts")


def code_chars() -> set:
    s = set()
    for p in glob.glob(os.path.join(ROOT, "**", "*.gd"), recursive=True) + \
             glob.glob(os.path.join(ROOT, "**", "*.tscn"), recursive=True):
        s |= set(open(p, encoding="utf-8").read())
    return s


def gb2312() -> set:
    s = set()
    for i in range(0xA1, 0xF8):
        for j in range(0xA1, 0xFF):
            try:
                s.add(bytes([i, j]).decode("gb2312"))
            except UnicodeDecodeError:
                pass
    return s


def run(src: str, dst: str, chars: set) -> None:
    chars = {c for c in chars if c.isprintable()} | {chr(i) for i in range(32, 127)}
    opt = subset.Options()
    opt.layout_features = ["*"]
    opt.name_IDs = ["*"]
    opt.name_languages = ["*"]
    opt.notdef_outline = True
    f = subset.load_font(src, opt)
    sub = subset.Subsetter(opt)
    sub.populate(text="".join(sorted(chars)))
    sub.subset(f)
    subset.save_font(f, dst, opt)
    print(dst, os.path.getsize(dst) // 1024, "KB")


if __name__ == "__main__":
    cc = code_chars() | gb2312()
    run(sys.argv[1], os.path.join(OUT, "SourceHanSansCN-Bold.otf"), cc)
    run(sys.argv[2], os.path.join(OUT, "SourceHanSansCN-Medium.otf"), cc)
