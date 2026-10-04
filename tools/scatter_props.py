#!/usr/bin/env python3
"""把批次 7 的街景杂物散布到 map.json。

区域规则（px 坐标，1px = 0.025m）：
  sidewalk  人行道带：马路矩形外扩 sidewalk(90px) 再内缩 8px
  road      马路沥青区（水洼/路锥用）
  road_edge 马路内靠路缘 45px 内（路锥）
  park      公园矩形内缩（补花草树）
  yard      建筑周边环带（晾衣杆贴民宅 / 燃气罐贴饮食店 / 轮胎贴店后）

避让：每个已有物件按 kind 给半避让半径（米，含建筑膨胀），新道具之间也保持间距。
固定随机种子，可重复运行（幂等：先剔除旧批次再加新的）。
"""
import json
import math
import random
import sys

MAP = "data/map.json"
S = 0.025            # px -> m
SEED = 20261004

# 每个已有 kind 的避让半径（米）。建筑取半宽+膨胀（house 的围墙比 click 盒大）。
AVOID = {
    "station": 7.2, "train": 10.2, "konbini": 3.8, "house": 4.2, "mansion": 3.7,
    "super": 4.3, "cafe": 3.3, "ramen": 3.6, "post_office": 3.4, "furniture": 4.3,
    "vending": 1.0, "pole": 0.75, "tree": 1.75, "sakura": 1.95, "bench": 1.7,
    "car": 2.7, "traffic": 0.85, "streetlight": 1.35, "signboard": 1.0,
    "busstop": 1.2, "parksign": 1.3, "mailbox": 0.85, "trash": 0.9,
    "bicycle": 1.4, "pipe": 0.8, "crate": 0.85, "planter": 1.25, "lowwall": 1.7,
    "wash": 0.9, "dog": 1.05, "cat": 0.95, "bird": 0.65, "flower": 1.05,
    "grass": 1.25, "roadsign": 0.85, "crosswalk": 3.6, "door": 1.2, "window": 1.2,
    "table": 1.1, "chair": 0.8, "bed": 1.6, "sofa": 1.4, "tv": 1.2, "shelf": 1.1,
    "lamp": 0.8, "cans": 1.0, "bowl": 1.0, "onigiri": 1.0, "bread": 1.2,
}
BUILDINGS = ["konbini", "house", "mansion", "super", "cafe", "ramen",
             "post_office", "furniture", "station"]
FOOD_SHOPS = ["ramen", "konbini", "cafe", "super", "furniture"]
HOUSES = ["house", "mansion"]

# 新道具配额：kind -> (数量, 最小间距 m, 自身半宽 m)
QUOTA = {
    "puddle":    (26, 3.0, 0.7),
    "fireplug":  (10, 6.0, 0.4),
    "potplant":  (26, 2.0, 0.4),
    "laundry":   (9, 8.0, 0.8),
    "trashbags": (11, 4.0, 0.5),
    "tires":     (7, 7.0, 0.5),
    "cones":     (9, 7.0, 0.4),
    "gasbottle": (6, 9.0, 0.5),
    # 公园补植
    "flower":    (10, 2.4, 0.5),
    "grass":     (10, 2.4, 0.4),
    "tree":      (5, 6.0, 1.0),
    "sakura":    (3, 8.0, 1.1),
}


def load():
    with open(MAP, encoding="utf-8") as f:
        return json.load(f)


def save(m):
    with open(MAP, "w", encoding="utf-8") as f:
        json.dump(m, f, ensure_ascii=False, indent="\t")


def in_rect(x, y, rx, ry, rw, rh, inset=0):
    return rx + inset <= x <= rx + rw - inset and ry + inset <= y <= ry + rh - inset


def main():
    m = load()
    g = m["ground"]
    world = m["world"]
    sw = float(g.get("sidewalk", 90))
    roads_h = g.get("roads_h", [])
    roads_v = g.get("roads_v", [])
    park = g.get("park", {}).get("rect")

    # 幂等：剔除上一批散布的（word 为空且 kind 在新清单里）
    NEW_KINDS = set(QUOTA) | {"fireplug", "potplant", "laundry", "trashbags",
                              "tires", "cones", "gasbottle", "puddle"}
    objs = [o for o in m["objects"]
            if not (o.get("kind") in NEW_KINDS and not o.get("word"))]

    # 已有物件避让表
    taken = []  # (x, y, r_m)
    for o in objs:
        r = AVOID.get(o["kind"], 1.0)
        if o.get("kind") in BUILDINGS:
            r += 0.4
        taken.append((float(o["x"]), float(o["y"]), r))

    buildings = [(float(o["x"]), float(o["y"]), o["kind"]) for o in objs
                 if o.get("kind") in BUILDINGS]

    def sidewalk_ok(x, y):
        for a, b in roads_h:
            if a - sw + 8 <= y <= a - 8 or b + 8 <= y <= b + sw - 8:
                return True
        for a, b in roads_v:
            if a - sw + 8 <= x <= a - 8 or b + 8 <= x <= b + sw - 8:
                return True
        return False

    def road_ok(x, y):
        return (any(a <= y <= b for a, b in roads_h)
                or any(a <= x <= b for a, b in roads_v))

    def road_edge_ok(x, y):
        if not road_ok(x, y):
            return False
        for a, b in roads_h:
            if a + 8 <= y <= a + 45 or b - 45 <= y <= b - 8:
                return True
        for a, b in roads_v:
            if a + 8 <= x <= a + 45 or b - 45 <= x <= b - 8:
                return True
        return False

    def near_some(building_kinds, dmin, dmax, x, y):
        for bx, by, bk in buildings:
            if bk not in building_kinds:
                continue
            d = math.hypot(x - bx, y - by) * S
            if dmin <= d <= dmax:
                return True
        return False

    def clear(x, y, r_self, used):
        # 与已有物件：自身半宽 + 对方避让半径（对方半径已含自身膨胀，不叠加间距）
        for tx, ty, tr in taken:
            if math.hypot(x - tx, y - ty) * S < (r_self + tr):
                return False
        # 新道具之间：直接用配好的最小间距（间距本身就是双侧和）
        for ux, uy, ur in used:
            if math.hypot(x - ux, y - uy) * S < ur:
                return False
        return True

    rng = random.Random(SEED)
    # 全图 1m 网格候选点，洗牌
    pts = [(x, y) for x in range(60, world[0] - 60, 40)
           for y in range(320, world[1] - 60, 40)]
    rng.shuffle(pts)

    used = []      # 新道具落点 (x, y, sep_m)
    placed = []    # 输出 dict
    quotas = {k: v[0] for k, v in QUOTA.items()}
    seps = {k: v[1] for k, v in QUOTA.items()}
    half = {k: v[2] for k, v in QUOTA.items()}

    def try_place(kind, x, y, rot=0):
        if quotas.get(kind, 0) <= 0:
            return False
        if not clear(x, y, half[kind], used):
            return False
        obj = {"kind": kind, "x": x, "y": y}
        if rot:
            obj["rot"] = rot
        placed.append(obj)
        used.append((x, y, seps[kind]))
        quotas[kind] -= 1
        return True

    for x, y in pts:
        if not quotas or all(v <= 0 for v in quotas.values()):
            break
        # 出生点周围留空
        if math.hypot(x - 2000, y - 900) < 240:
            continue
        on_road = road_ok(x, y)
        in_park = park and in_rect(x, y, *park, inset=60)

        if quotas["puddle"] > 0 and on_road and not road_edge_ok(x, y):
            if try_place("puddle", x, y):
                continue
        if quotas["cones"] > 0 and road_edge_ok(x, y):
            if try_place("cones", x, y, rot=rng.choice([0, 90])):
                continue
        if quotas["fireplug"] > 0 and sidewalk_ok(x, y):
            if try_place("fireplug", x, y):
                continue
        if quotas["potplant"] > 0 and (sidewalk_ok(x, y) or
                near_some(BUILDINGS, 2.6, 4.2, x, y)) and not on_road:
            if try_place("potplant", x, y):
                continue
        if quotas["trashbags"] > 0 and (sidewalk_ok(x, y) or
                near_some(HOUSES, 2.6, 5.0, x, y)) and not on_road:
            if try_place("trashbags", x, y):
                continue
        if quotas["tires"] > 0 and not on_road and not in_park and \
                near_some(FOOD_SHOPS + ["house"], 5.2, 6.5, x, y):
            if try_place("tires", x, y):
                continue
        if quotas["laundry"] > 0 and not on_road and not in_park and \
                near_some(HOUSES, 5.4, 6.8, x, y):
            if try_place("laundry", x, y, rot=rng.choice([0, 90])):
                continue
        if quotas["gasbottle"] > 0 and not on_road and \
                near_some(FOOD_SHOPS, 4.7, 6.0, x, y):
            if try_place("gasbottle", x, y):
                continue
        # 公园补植（最宽松，最后塞）
        if in_park and not on_road:
            for k in ("flower", "grass", "tree", "sakura"):
                if quotas[k] > 0 and try_place(k, x, y):
                    break

    # 燃气罐 quota 在 near_some 命中率低时兜底：贴着拉面店摆（店半宽 ~3.2m，罐在 4.7m 处）
    if quotas["gasbottle"] > 0:
        for bx, by, bk in buildings:
            if bk == "ramen" and quotas["gasbottle"] > 0:
                for dx, dy in [(4.8, 1.2), (-4.8, -1.0), (4.6, -1.6)]:
                    x = int(bx + dx / S)
                    y = int(by + dy / S)
                    if try_place("gasbottle", x, y):
                        break

    m["objects"] = objs + placed
    save(m)

    total = len(m["objects"])
    print(f"新增 {len(placed)} 个道具，总物件 {total}")
    from collections import Counter
    c = Counter(p["kind"] for p in placed)
    for k, n in c.most_common():
        left = quotas.get(k, 0)
        print(f"  {k}: {n}" + (f"  (未放满 {left})" if left else ""))
    if any(v > 0 for v in quotas.values()):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
