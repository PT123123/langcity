# -*- coding: utf-8 -*-
"""从 Poly Haven (CC0) 下载照片级贴图到 assets/tex/。
每个材质下载 1k 的 Diffuse / nor_gl(法线) / Rough(粗糙度) jpg。"""
import json
import os
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "tex")

PICKS = {
    "road":     "asphalt_02",           # 柏油路
    "pavers":   "concrete_pavers",      # 人行道铺装
    "tilewall": "concrete_tile_facade", # 商店/公寓外墙小口瓷砖
    "plaster":  "painted_plaster_wall", # 住宅墙面
    "roof":     "grey_roof_tiles",      # 灰瓦屋顶
    "wood":     "wood_planks",          # 木墙
    "grass":    "leafy_grass",          # 草地
    "concrete": "brushed_concrete",     # 站台/小径混凝土
    "block":    "concrete_block_wall",  # 住宅围墙（ブロック塀）
}


def get_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode())


def dl(url, path):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=120) as r, open(path, "wb") as f:
        f.write(r.read())


def main():
    os.makedirs(OUT, exist_ok=True)
    for kind, aid in PICKS.items():
        try:
            files = get_json(f"https://api.polyhaven.com/files/{aid}")
        except Exception as e:
            print("skip", kind, repr(e)[:80])
            continue
        res = "2k" if "2k" in files.get("Diffuse", {}) else "1k"
        for map_name, suffix in [("Diffuse", "col"), ("nor_gl", "nrm"), ("Rough", "rgh")]:
            try:
                url = files[map_name][res]["jpg"]["url"]
                path = os.path.join(OUT, f"{kind}_{suffix}.jpg")
                if not (os.path.exists(path) and os.path.getsize(path) > 10000):
                    dl(url, path)
                print("ok", kind, suffix, os.path.getsize(path) // 1024, "KB")
            except Exception as e:
                print("MISS", kind, suffix, repr(e)[:80])


if __name__ == "__main__":
    main()
