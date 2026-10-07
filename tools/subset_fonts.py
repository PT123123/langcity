# -*- coding: utf-8 -*-
"""
字体子集化：把 assets/fonts 里的完整 Noto 字体裁剪成项目实际用到的字符集，
大幅减小 APK 体积（27MB -> 约 2MB）。

何时需要重新运行：
  往 data/words.json 或界面里新增了文字（尤其是新单词的汉字）之后。
  即使忘了运行，游戏也会回退到系统字体显示缺字（Android/Windows 都有 CJK 系统字体），
  只是体积没有优化而已。

用法：
  pip install fonttools
  python tools/subset_fonts.py
"""
import io
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT_DIR = os.path.join(ROOT, "assets", "fonts")
SRC_DIR = os.path.join(ROOT, "_tools", "fonts_src")


def collect_text() -> str:
    chars = set()

    def feed(path):
        with io.open(path, encoding="utf-8") as f:
            chars.update(f.read())

    # 词库与地图数据。planet.json 是当前主地图（已取代 map.json），
    # interiors.json / npcs.json 里的牌面文字与称呼也要收进来，
    # 否则新增的 text3d 招牌会被子集裁掉、显示豆腐块。
    for name in ("words.json", "map.json", "planet.json", "interiors.json",
                 "npcs.json", "quests.json"):
        p = os.path.join(ROOT, "data", name)
        if os.path.exists(p):
            feed(p)
    # 所有脚本里的界面文案
    for base, _dirs, files in os.walk(os.path.join(ROOT, "scripts")):
        for fn in files:
            if fn.endswith(".gd"):
                feed(os.path.join(base, fn))

    # 常备字符：全部假名、CJK 符号、全角符号、ASCII
    for lo, hi in [
        (0x0020, 0x007E),   # ASCII
        (0x00A0, 0x00FF),   # 拉丁补充
        (0x3000, 0x30FF),   # CJK 符号 + 假名
        (0xFF00, 0xFFEF),   # 全角形式
        (0x2026, 0x2026), (0x2018, 0x201D), (0x00B7, 0x00B7),
    ]:
        for cp in range(lo, hi + 1):
            chars.add(chr(cp))
    return "".join(sorted(chars))


def main():
    try:
        import fontTools  # noqa: F401
    except ImportError:
        print("请先安装 fonttools：pip install fonttools")
        sys.exit(1)

    os.makedirs(SRC_DIR, exist_ok=True)
    charset_path = os.path.join(SRC_DIR, "charset.txt")
    with io.open(charset_path, "w", encoding="utf-8") as f:
        f.write(collect_text())
    print("字符集大小:", len(set(io.open(charset_path, encoding="utf-8").read())))

    for src_name, out_name in [
        ("NotoSansJP-Medium.ttf", "NotoSansJP-Medium.ttf"),
        ("NotoSansSC-Medium.ttf", "NotoSansSC-Medium.ttf"),
    ]:
        src = os.path.join(SRC_DIR, src_name)
        if not os.path.exists(src):
            # 第一次运行：把 assets 里的完整字体挪到 _tools/fonts_src 留底
            cur = os.path.join(FONT_DIR, src_name)
            if os.path.exists(cur) and os.path.getsize(cur) > 3_000_000:
                os.replace(cur, src)
            else:
                print("跳过", src_name, "（找不到源字体）")
                continue
        out = os.path.join(FONT_DIR, out_name)
        subprocess.check_call([
            sys.executable, "-m", "fontTools.subset", src,
            f"--text-file={charset_path}",
            "--layout-features=*",
            "--flavor=",  # 保持 ttf
            f"--output-file={out}",
            "--desubroutinize",
        ])
        print(out_name, "->", os.path.getsize(out) // 1024, "KB")


if __name__ == "__main__":
    main()
