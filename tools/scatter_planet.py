#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""往 data/planet.json 撒新物件（批次 9：给 0% 分类补词载体）。

为什么需要单独一个工具
----------------------
tools/scatter_props.py 吃的是 data/map.json 的 `ground` 段（roads_h/roads_v/park
矩形），靠「在不在马路上/公园里」决定物件放哪。但星球地图已经没有 `ground` 段了
——那套 schema 随 GroundBuilder 一起废弃，岛屿地形烘焙在
assets/art/env/planets_present_full_0..9.glb 里，Python 侧看不到任何地面信息。

所以本工具换一套落点策略：**就近播种**。
  · 锚点 = planet.json 里已经通过 curate_planet 整备、位置已知合法的既有物件
  · 在锚点周围按切平面偏移撒新物件（锚点合法 → 附近大概率也合法）
  · 最后**必须**跑 _tools/curate_planet.tscn 做真正的射线校验（它才有地面数据）

坐标系：planet.json 的 (x, y) 是「岛冠展开图的像素」，由 PlanetMath 解释为
（经度, 余纬）。1px = 0.025m，所以偏移量用米算好再 ×40 换成 px。

幂等：新物件统一带 "batch": "cc0"，重跑时先按 batch 剔除再撒，种子固定。

用法：
    python tools/scatter_planet.py            # 撒，并写回 planet.json
    python tools/scatter_planet.py --dry      # 只打印统计，不写文件

⚠️ 跑完必须接着跑（2~3 轮收敛）：
    _tools\\Godot_v4.4.1-stable_win64_console.exe --path . res://_tools/curate_planet.tscn
   绝不要重跑 _tools/make_planet_map.py —— 它会覆盖整备结果。
"""
import json
import math
import random
import sys

MAP = "data/planet.json"
SEED = 20261007
BATCH = "cc0"

PX = 40.0            # 1m = 40px
S = 0.025            # px -> m（与 Interactable.S 一致）

WORLD = (5200, 4000)  # planet.json 的 world（展开图尺寸，px）
SPAWN_PX = (0.0, 2756.0)

# 任务绑定 kind：quests.json 的跑腿任务按 kind 找它们，位置绝不能被新物件挤掉。
# 这些 kind 在锚点选择时**排除**，新物件也不允许压到它们身上。
QUEST_BOUND = {
    "post_office", "station", "konbini", "ramen", "cafe",
    "parksign", "sakura", "counter", "gate",
}

# kind -> 避让半径（米）。建筑取半宽 + 膨胀；小道具取自身半径。
# 与 tools/scatter_props.py 的 AVOID 同一套思路（单位都是米）。
AVOID = {
    # 建筑（click 盒半宽 ~ m）
    "station": 7.2, "house": 4.2, "mansion": 3.7, "super": 4.3, "konbini": 3.8,
    "cafe": 3.3, "ramen": 3.6, "post_office": 3.4, "furniture": 4.3,
    "temple": 3.6, "school": 5.2, "hospital": 4.3, "bank": 3.8, "police": 3.8,
    "library": 3.9,
    # 交通
    "truck": 3.2, "car": 2.7, "bicycle": 1.4, "boat": 1.5,
    # 街景
    "pole": 0.75, "streetlight": 1.35, "signboard": 1.0, "busstop": 1.2,
    "roadsign": 0.85, "vending": 1.0, "bench": 1.7, "trash": 0.9, "mailbox": 0.85,
    "tree": 1.75, "flower": 1.05, "grass": 1.25, "potplant": 0.4, "planter": 1.25,
    "lowwall": 1.7, "pipe": 0.8, "crate": 0.85, "laundry": 0.8,
    "trashbags": 0.5, "tires": 0.5, "cones": 0.4, "gasbottle": 0.5,
    # 动物 / 人形
    "dog": 1.05, "cat": 0.95, "bird": 0.65, "npc": 0.5,
    "deer": 1.0, "fox": 0.7, "wolf": 1.0, "turtle": 0.5,
    # 新增道具
    "ticket_sign": 0.5, "goods": 1.1, "plate": 0.7,
    # 家具/室内件（家具屋门前展示品）
    "table": 1.1, "chair": 0.8, "bed": 1.6, "sofa": 1.4, "tv": 1.2,
    "shelf": 1.1, "lamp": 0.8, "wash": 0.9,
    "bowl": 1.0, "cans": 1.0, "onigiri": 1.0, "bread": 1.2,
    "door": 1.2, "window": 1.2, "delivery": 0.4,
}

# 批次 9 新撒的物件：kind -> (词, 数量, 最小间距 m, 锚点 kind 白名单)
# 锚点白名单 = 只在这些 kind 附近撒（避免把动物撒到屋顶上）。
NEW = {
    # 公共设施：独栋，沿用既有建筑区的锚点
    "temple":   ("tera",          1, 14.0, {"sakura", "tree", "parksign", "bench"}),
    "school":   ("gakkou",        1, 16.0, {"tree", "flower"}),
    "hospital": ("byouin",        1, 14.0, {"tree", "pole"}),
    "bank":     ("ginkou",        1, 12.0, {"pole", "streetlight"}),
    "police":   ("keisatsusho",   1, 12.0, {"pole", "streetlight"}),
    "library":  ("toshokan",      1, 13.0, {"tree", "sakura"}),
    # 交通：码头/街边
    "truck":        ("torakku",   2,  9.0, {"car", "pole"}),
    "boat":         ("fune",      2, 11.0, {"pole", "bench"}),
    "ticket_sign":  ("kippu",     3,  6.0, {"busstop", "station", "pole"}),
    # 购物：店前货架
    "goods":        ("mise",      6,  5.0, {"konbini", "super", "cafe", "ramen"}),
    # 动物
    "deer":         ("yagi",      2,  8.0, {"tree", "sakura", "flower"}),
    "fox":          ("kitsune",   3,  7.0, {"tree", "planter", "bench"}),
    "wolf":         ("ookami",    1, 10.0, {"tree", "sakura"}),
    "turtle":       ("kame",      2,  5.0, {"flower", "grass", "planter"}),
    # 单词牌：成组摆（看板墙），只给抽象分类
    "plate":        (None,       18,  2.2, {"bench", "planter", "pole", "streetlight"}),
}

# plate 牌面轮转的词（color 分类 14 个 + 少量其它抽象词）。
# 这些词在 words.json 里都是 0% 覆盖，牌面是它们唯一的载体。
PLATE_WORDS = [
    "iro", "aka", "ao", "kiiro", "midori", "shiro", "kuro",
    "haiiro", "chairo", "pinku", "orenji", "murasaki", "kiniro", "giniro",
    # 顺带补几个 0% 分类里语义上适合「看板」的
    "asa", "hiru", "yoru", "kyou", "ashita",       # time
    "ichi", "ni", "san", "go",                    # number
]


def load():
    with open(MAP, encoding="utf-8") as f:
        return json.load(f)


def save(m):
    with open(MAP, "w", encoding="utf-8") as f:
        json.dump(m, f, ensure_ascii=False, indent="\t")


def main():
    dry = "--dry" in sys.argv
    m = load()
    objs = m["objects"]
    world = m.get("world", list(WORLD))

    # 幂等：剔除上一轮本批次撒的
    before = len(objs)
    kept = [o for o in objs if o.get("batch") != BATCH]
    removed = before - len(kept)
    objs = kept

    # 已有物件避让表（含任务绑定建筑，它们只作为障碍，不当锚点）
    taken = []
    anchors = collections_of(objs)
    for o in objs:
        r = AVOID.get(o["kind"], 1.0)
        taken.append((float(o["x"]), float(o["y"]), r))

    rng = random.Random(SEED)
    placed = []
    used = []          # 新物件落点 (x, y, sep_m)
    quotas = {k: v[1] for k, v in NEW.items()}
    plate_i = 0

    def clear(x, y, r_self):
        for tx, ty, tr in taken:
            if math.hypot(x - tx, y - ty) * S < (r_self + tr):
                return False
        for ux, uy, ur in used:
            if math.hypot(x - ux, y - uy) * S < ur:
                return False
        # 出生点与传送点周围留空
        for px, py in (SPAWN_PX,):
            if math.hypot(x - px, y - py) * S < 6.0:
                return False
        return True

    def put(kind, word, x, y, rot=None):
        if quotas[kind] <= 0:
            return False
        o = {"kind": kind, "x": int(round(x)), "y": int(round(y)), "batch": BATCH}
        if word:
            o["word"] = word
        if rot:
            o["rot"] = rot
        placed.append(o)
        used.append((o["x"], o["y"], NEW[kind][2]))
        quotas[kind] -= 1
        return True

    # 逐 kind 撒：先在锚点附近螺旋试点
    for kind, (word, qty, sep_m, anchor_kinds) in NEW.items():
        pool = [a for a in anchors if a[2] in anchor_kinds]
        rng.shuffle(pool)
        r_self = AVOID.get(kind, 1.0)
        tries = 0
        while quotas[kind] > 0 and pool and tries < qty * 60:
            tries += 1
            ax, ay, _ = pool[tries % len(pool)]
            # 在锚点周围 3~14m 内随机方向撒（角度偏移模拟切平面偏移）
            ang = rng.uniform(0, math.tau)
            dist = rng.uniform(3.0, 14.0)
            x = ax + math.cos(ang) * dist / S
            y = ay + math.sin(ang) * dist / S
            if x < 60 or x > world[0] - 60 or y < 60 or y > world[1] - 60:
                continue
            # word：plate 走 PLATE_WORDS 轮转，其余 kind 用 NEW 里登记的词
            w = PLATE_WORDS[plate_i % len(PLATE_WORDS)] if kind == "plate" else word
            if kind == "plate":
                plate_i += 1
            if clear(x, y, r_self) and put(kind, w, x, y, rng.choice([0, 90, 180, 270])):
                continue

    objs.extend(placed)
    # 关键：kept 是新 list（重新赋值不会改到 m["objects"]），
    # 必须显式写回，否则 save() 存的是那份没被 extend 过的旧 list。
    m["objects"] = objs
    if not dry:
        save(m)

    from collections import Counter
    c = Counter(p["kind"] for p in placed)
    total = len(objs)
    print(("DRY " if dry else "") + f"移除旧批次 {removed} 个，新撒 {len(placed)} 个，总物件 {total}")
    for k, n in c.most_common():
        left = quotas.get(k, 0)
        print(f"  {k}: {n}" + (f"  (未放满 {left})" if left else ""))
    left_over = {k: v for k, v in quotas.items() if v > 0}
    if left_over:
        print("  未放满:", left_over)
    print("\n下一步：跑 curate_planet.tscn 做射线校验（2~3 轮）")
    return 0


def collections_of(objs):
    """按 kind 收集锚点 (x, y, kind)。任务绑定 kind 排除在外。"""
    from collections import defaultdict
    out = defaultdict(list)
    for o in objs:
        k = o["kind"]
        if k in QUEST_BOUND:
            continue
        out[k].append((float(o["x"]), float(o["y"]), k))
    flat = []
    for k, v in out.items():
        flat.extend(v)
    return flat


if __name__ == "__main__":
    sys.exit(main())