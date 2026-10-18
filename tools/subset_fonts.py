#!/usr/bin/env python3
"""把字体裁成游戏要用的字，减小体积。

用法: python3 tools/subset_fonts.py <榜书原始ttf> <思源柔黑Heavy原始ttf>

- 标题字（仓耳周珂正大榜书，免费商用）：只保留代码里实际出现的字 + ASCII
  （原字体 17MB，笔画轮廓点很多，全量太大）。新加文案后重跑一遍即可。
- 兜底字（思源柔黑 Heavy，OFL）：GB2312 全集 + ASCII + 代码里的字。
  榜书缺的字（新文案里还没裁进来的字、·×—…→（）「」等符号）自动落到这里。
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
    title_src, body_src = sys.argv[1], sys.argv[2]
    cc = code_chars()
    run(title_src, os.path.join(OUT, "TsangerZhoukeZhengdabangshu.ttf"), cc)
    run(body_src, os.path.join(OUT, "ResourceHanRoundedCN-Heavy.ttf"), cc | gb2312())
