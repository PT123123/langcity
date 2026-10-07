#!/usr/bin/env python3
"""生成新的城区地图（data/city_harbor.json / data/city_hillside.json）。

设计：与 data/map.json 同一套尺度与 kind（1px = 0.025m）。
- 道路网格把世界切成街区，建筑按街区面积配额确定性摆放（种子固定，可重复运行）。
- 公园/广场、人行道杂物、路口斑马线、行道树各自按区域规则散布，带避让半径。
- 每张城一个近车站的 portal（回旧市街），坐标与 data/map.json 里 street_city
  portal 的 to_x/to_y 对齐，构成 hub-and-spoke 传送网。
用法：python tools/gen_city.py
"""
import json
import math
import random

PX = 40.0          # 1m = 40px
S = 0.025
MARGIN = 12        # 建筑间距余量（px）

# kind -> click 盒 (宽 x, 深 z)，单位米（取自 Interactable.META）
SIZE = {
    "station": (12.6, 8.2), "konbini": (6.6, 5.1), "house": (4.3, 3.7),
    "mansion": (4.3, 3.9), "super": (7.7, 5.5), "cafe": (5.3, 4.3),
    "ramen": (6.3, 4.7), "post_office": (5.9, 4.3), "furniture": (7.7, 5.5),
}
# 间距用足印：house 带院子围墙，视觉比 click 盒大得多
FOOT = dict(SIZE)
FOOT["house"] = (7.8, 5.0)
FOOT["mansion"] = (5.0, 4.6)

WORD = {
    "station": "station", "konbini": "konbini", "house": "house",
    "mansion": "mansion", "super": "supermarket", "cafe": "cafe",
    "ramen": "ramen_shop", "post_office": "post_office", "furniture": "kagu",
    "tree": "tree", "sakura": "sakura", "flower": "flower", "grass": "grass",
    "parksign": "park", "pole": "pole", "trash": "trash", "vending": "vending",
    "signboard": "signboard", "streetlight": "streetlight", "bench": "bench",
    "roadsign": "roadsign", "traffic": "traffic_light", "busstop": "busstop",
    "car": "car", "bicycle": "bicycle", "crosswalk": "crosswalk",
    "dog": "dog", "cat": "cat", "bird": "bird", "bread": "bread",
    "onigiri": "onigiri", "cans": "drink", "bowl": "ramen",
    "lowwall": "lowwall", "planter": "planter", "planter_x": "planter",
    "marker_cross": "crossing", "marker_road": "road", "marker_walk": "sidewalk",
}

# 散布道具：kind -> (数量, 自身半宽 m, 新道具间最小间距 m)
SCATTER = {
    "puddle": (20, 0.7, 3.0), "cones": (8, 0.4, 7.0),
    "fireplug": (8, 0.4, 6.0), "potplant": (18, 0.4, 2.4),
    "trashbags": (8, 0.5, 4.0), "laundry": (7, 0.8, 7.0),
    "tires": (5, 0.5, 7.0), "gasbottle": (5, 0.5, 8.0),
    "lowwall": (6, 1.2, 6.0), "planter": (6, 0.8, 5.0),
    "crate": (6, 0.4, 4.0), "pipe": (6, 0.4, 5.0),
}
AVOID = {
    "station": 7.2, "konbini": 3.8, "house": 4.2, "mansion": 3.7,
    "super": 4.3, "cafe": 3.3, "ramen": 3.6, "post_office": 3.4, "furniture": 4.3,
    "vending": 1.0, "pole": 0.75, "tree": 1.75, "sakura": 1.95, "bench": 1.7,
    "car": 2.7, "traffic": 0.85, "streetlight": 1.35, "signboard": 1.0,
    "busstop": 1.2, "parksign": 1.3, "mailbox": 0.85, "trash": 0.9,
    "bicycle": 1.4, "flower": 1.05, "grass": 1.25, "roadsign": 0.85,
    "crosswalk": 3.6, "portal": 3.5, "dog": 1.05, "cat": 0.95, "bird": 0.65,
}


def blocks_of(roads_v, roads_h, world):
    """把世界按道路切成街区（可用矩形，已内缩人行道 + 余量）。"""
    xs = [0]
    for a, b in roads_v:
        xs += [a, b]
    xs.append(world[0])
    ys = [0]
    for a, b in roads_h:
        ys += [a, b]
    ys.append(world[1])
    sw = 90
    out = []
    for i in range(0, len(xs) - 1, 2):
        for j in range(0, len(ys) - 1, 2):
            x0, x1 = xs[i] + sw + MARGIN, xs[i + 1] - sw - MARGIN
            y0, y1 = ys[j] + sw + MARGIN, ys[j + 1] - sw - MARGIN
            if x1 - x0 > 260 and y1 - y0 > 260:
                out.append([x0, y0, x1, y1])
    return out


def distribute(pool, bl, rng):
    """把建筑池按街区面积分摊，保证每个街区都有建筑。"""
    rng.shuffle(pool)
    w = [max(1, r[2] - r[0]) * max(1, r[3] - r[1]) for r in bl]
    tot = sum(w)
    counts = [int(len(pool) * x / tot) for x in w]
    i = 0
    while sum(counts) < len(pool):
        counts[i % len(counts)] += 1
        i += 1
    out = []
    k = 0
    for c in counts:
        out.append(pool[k:k + c])
        k += c
    return out


class City:
    def __init__(self, cfg):
        self.cfg = cfg
        self.rng = random.Random(cfg["seed"])
        self.world = cfg["world"]
        self.park = cfg["ground"].get("park", {}).get("rect")
        self.spawn = cfg["spawn"]
        self.portal = cfg["portal"]
        self.objs = []
        self.placed = []          # (x, y, half_w_px, half_d_px)
        self.built = []           # (x, y, kind)

    def add(self, kind, x, y, **extra):
        o = {"kind": kind, "x": int(round(x)), "y": int(round(y))}
        w = WORD.get(kind)
        if w and "word" not in extra:
            o["word"] = w
        for k, v in extra.items():
            o[k] = v
        self.objs.append(o)
        return o

    def on_road(self, x, y):
        for a, b in self.cfg["ground"].get("roads_h", []):
            if a <= y <= b:
                return True
        for a, b in self.cfg["ground"].get("roads_v", []):
            if a <= x <= b:
                return True
        return False

    def near_road(self, x, y, band=24):
        for a, b in self.cfg["ground"].get("roads_h", []):
            if a - band <= y <= b + band:
                return True
        for a, b in self.cfg["ground"].get("roads_v", []):
            if a - band <= x <= b + band:
                return True
        return False

    def in_park(self, x, y):
        return self.park and (self.park[0] <= x <= self.park[0] + self.park[2]
                              and self.park[1] <= y <= self.park[1] + self.park[3])

    def free(self, x, y, hw, hd, pad=MARGIN):
        for bx, by, bw, bd in self.placed:
            if abs(x - bx) < hw + bw + pad and abs(y - by) < hd + bd + pad:
                return False
        return True

    def reserved(self, x, y, hw, hd):
        # 出生点/传送点必须落在建筑体之外（按建筑半尺寸 + 玩家净空做 AABB 判定）
        for px, py in (self.spawn, self.portal):
            if abs(x - px) < hw + 40 and abs(y - py) < hd + 40:
                return True
        return False

    # ---- 建筑 ----
    def build(self, kind, x, y):
        fw, fd = FOOT[kind]
        hw, hd = fw * PX / 2, fd * PX / 2
        if self.on_road(x, y) or self.near_road(x, y, 30):
            return False
        if self.in_park(x, y):
            return False
        if x - hw < 40 or x + hw > self.world[0] - 40:
            return False
        if y - hd < 320 or y + hd > self.world[1] - 40:
            return False
        if self.reserved(x, y, hw, hd):
            return False
        if not self.free(x, y, hw, hd):
            return False
        self.add(kind, x, y)
        self.placed.append((x, y, hw, hd))
        self.built.append((x, y, kind))
        w = SIZE[kind][0]
        door_xs = [-w * 0.25, w * 0.25] if w > 6.0 else [0.0]
        for dxm in door_xs:
            # 门/窗的 px 坐标 = 建筑中心；make() 会按 host 的深度自动吸附到正面
            self.add("door", x, y, host=kind, dx=dxm)
        n_win = max(1, int(w / 2.4))
        for i in range(n_win):
            wx = -w / 2 + 1.1 + i * (w - 2.2) / max(1, n_win - 1)
            self.add("window", x, y, host=kind, dx=wx)
        return True

    def fill_block(self, rect, kinds):
        x0, y0, x1, y1 = rect
        step = 150
        cw = max(1, int((x1 - x0) / step))
        ch = max(1, int((y1 - y0) / step))
        cells = [(i, j) for i in range(cw) for j in range(ch)]
        self.rng.shuffle(cells)
        for kind in kinds:
            nw = FOOT[kind][0] * PX
            nd = FOOT[kind][1] * PX
            for i, j in cells:
                cx = x0 + nw / 2 + 24 + i * step
                cy = y0 + nd / 2 + 24 + j * step
                if cx + nw / 2 > x1 or cy + nd / 2 > y1:
                    continue
                if self.build(kind, cx + self.rng.randint(-16, 16),
                              cy + self.rng.randint(-16, 16)):
                    break

    # ---- 公园 / 广场 ----
    def park_fill(self):
        if not self.park:
            return
        prx, pry, prw, prh = self.park
        x0, y0 = prx + 60, pry + 60
        x1, y1 = prx + prw - 60, pry + prh - 60
        self.add("parksign", x0 + 40, y1 - 40)
        self.add("marker_cross", (x0 + x1) / 2, (y0 + y1) / 2)
        # 樱花沿公园中轴摆一圈，树/花草铺满
        span_x, span_y = x1 - x0, y1 - y0
        self.add("sakura", x0 + span_x * 0.5, y0 + span_y * 0.45)
        slots = [(0.25, 0.3), (0.7, 0.28), (0.4, 0.7), (0.78, 0.66),
                 (0.15, 0.55), (0.6, 0.5), (0.3, 0.85), (0.85, 0.85)]
        for fxs, fys in slots:
            fx = x0 + span_x * fxs
            fy = y0 + span_y * fys
            if self.free(fx, fy, 1.0 * PX, 1.0 * PX, pad=8):
                self.add("sakura" if self.rng.random() < 0.4 else "tree", fx, fy)
                self.placed.append((fx, fy, 1.0 * PX, 1.0 * PX))
        for kind, n, r in [("tree", 12, 1.4), ("flower", 12, 0.8), ("grass", 12, 0.9)]:
            tries = 0
            placed = 0
            while placed < n and tries < n * 12:
                tries += 1
                fx = x0 + self.rng.random() * span_x
                fy = y0 + self.rng.random() * span_y
                hw = r * PX
                if self.free(fx, fy, hw, hw, pad=6):
                    self.add(kind, fx, fy)
                    self.placed.append((fx, fy, hw, hw))
                    placed += 1

    # ---- 道路 ----
    def roads_fill(self):
        g = self.cfg["ground"]
        h, v = g.get("roads_h", []), g.get("roads_v", [])
        xs = [(a + b) / 2 for a, b in v]
        ys = [(a + b) / 2 for a, b in h]
        # 斑马线：每个路口两向各一条
        for rx in xs:
            for ry in ys:
                self.add("crosswalk", rx, ry - 240)
                self.add("crosswalk", rx - 240, ry)
        for i, rx in enumerate(xs):
            for j, ry in enumerate(ys):
                if (i + j) % 2 == 0:
                    self.add("traffic", rx + 120, ry + 70)
        for _ in range(6):
            self.add("car", self.rng.choice(xs) + self.rng.randint(-50, 50),
                     self.rng.choice(ys) + self.rng.choice([-170, 170]),
                     rot=self.rng.choice([0, 90]))
        # 电线杆：主路（h[0]/v[0]）按 ≤16m 间距拉线，其余路各补一两根
        if h:
            x = 260
            while x < self.world[0] - 100:
                self.add("pole", x, h[0][0] - 130)
                x += 600
        if v:
            y = 420
            while y < self.world[1] - 100:
                self.add("pole", v[0][0] - 130, y)
                y += 600
        for a, b in h[1:]:
            self.add("pole", self.world[0] * 0.5, a - 130)
        for a, b in v[1:]:
            self.add("pole", a - 130, self.world[1] * 0.55)
        for a, b in h:
            for k in range(4):
                self.add("streetlight", 420 + k * 1150, b + 130)
        # 任务/小地图用的隐形路线标记
        self.add("marker_road", self.world[0] * 0.5, ys[0] if ys else 1200)
        self.add("marker_walk", xs[0] if xs else 1200, 700)

    # ---- 店铺门前杂物 ----
    def shopfront_fill(self):
        quotas = {"bench": 5, "vending": 5, "bicycle": 4, "mailbox": 3,
                  "trash": 4, "signboard": 3, "busstop": 1}
        anchors = [b for b in self.built]
        self.rng.shuffle(anchors)
        for _pass in range(3):
            for bx, by, bk in anchors:
                if all(q <= 0 for q in quotas.values()):
                    return
                w, d = SIZE[bk]
                for kind in quotas:
                    if quotas[kind] <= 0:
                        continue
                    side = self.rng.choice([-1, 1])
                    fx = bx + side * (w * PX / 2 + self.rng.uniform(2.6, 3.8) * PX)
                    fy = by + d * PX / 2 + self.rng.uniform(2.4, 3.6) * PX
                    if self.on_road(fx, fy) or self.in_park(fx, fy):
                        continue
                    if fx < 60 or fx > self.world[0] - 60 or fy > self.world[1] - 60:
                        continue
                    self.add(kind, fx, fy)
                    quotas[kind] -= 1
                    break

    # ---- 动物 / 食物（收集类任务要跨图也能推进）----
    def life_fill(self):
        picks = [("dog", 2), ("cat", 2), ("bird", 2),
                 ("bread", 1), ("onigiri", 1), ("cans", 1), ("bowl", 1)]
        for kind, n in picks:
            for _ in range(n):
                for _try in range(40):
                    x = self.rng.randint(120, int(self.world[0]) - 120)
                    y = self.rng.randint(400, int(self.world[1]) - 120)
                    r = AVOID.get(kind, 1.0) * PX
                    if not self.on_road(x, y) and not self.in_park(x, y) \
                            and self.free(x, y, r, r, pad=3):
                        self.add(kind, x, y)
                        self.placed.append((x, y, r, r))
                        break

    # ---- 通用杂物散布 ----
    def scatter_fill(self):
        taken = [(o["x"], o["y"], AVOID.get(o["kind"], 1.0)) for o in self.objs]
        used = []
        quotas = {k: v[0] for k, v in SCATTER.items()}
        half = {k: v[1] for k, v in SCATTER.items()}
        seps = {k: v[2] for k, v in SCATTER.items()}
        pt = [(x, y) for x in range(80, self.world[0] - 80, 40)
              for y in range(340, self.world[1] - 80, 40)]
        self.rng.shuffle(pt)
        sp = self.spawn

        def clear(x, y, r_self):
            for tx, ty, tr in taken:
                if math.hypot(x - tx, y - ty) * S < (r_self + tr):
                    return False
            for ux, uy, ur in used:
                if math.hypot(x - ux, y - uy) * S < ur:
                    return False
            return True

        def put(kind, x, y):
            if quotas[kind] <= 0 or not clear(x, y, half[kind]):
                return False
            self.add(kind, x, y)
            used.append((x, y, seps[kind]))
            quotas[kind] -= 1
            return True

        for x, y in pt:
            if all(q <= 0 for q in quotas.values()):
                break
            if math.hypot(x - sp[0], y - sp[1]) < 220:
                continue
            on_road = self.on_road(x, y)
            sidewalk = self.near_road(x, y, 130) and not on_road
            if quotas["puddle"] > 0 and on_road and put("puddle", x, y):
                continue
            if quotas["cones"] > 0 and on_road and put("cones", x, y):
                continue
            if quotas["fireplug"] > 0 and sidewalk and put("fireplug", x, y):
                continue
            if quotas["potplant"] > 0 and sidewalk and put("potplant", x, y):
                continue
            if quotas["trashbags"] > 0 and sidewalk and put("trashbags", x, y):
                continue
            if self.in_park(x, y) or sidewalk or on_road:
                continue
            for k in ("laundry", "tires", "gasbottle", "lowwall", "planter", "crate", "pipe"):
                if quotas[k] > 0 and put(k, x, y):
                    break

    def run(self):
        c = self.cfg
        self.build("station", c["station"][0], c["station"][1])
        blocks = blocks_of(c["ground"]["roads_v"], c["ground"]["roads_h"], c["world"])
        # 公园所在的街区整块留空（免得建筑和树互相压）
        if self.park:
            def blocked(r):
                cx, cy = (r[0] + r[2]) / 2, (r[1] + r[3]) / 2
                return self.in_park(cx, cy)
            blocks = [r for r in blocks if not blocked(r)]
        assign = distribute(list(c["pool"]), blocks, self.rng)
        for rect, kinds in zip(blocks, assign):
            self.fill_block(rect, kinds)
        self.park_fill()
        self.roads_fill()
        self.shopfront_fill()
        self.life_fill()
        self.scatter_fill()
        px, py = c["portal"]
        self.add("portal", px, py, to_map="street_city", to_x=2000, to_y=900,
                 to_yaw=0, label="旧市街", accent="#8a7f6a")
        return {"world": c["world"], "spawn": c["spawn"],
                "ground": c["ground"], "objects": self.objs}


def harbor_cfg():
    world = [5200, 4000]
    ground = {
        "base_color": "#c9c4b4", "sidewalk": 90,
        "roads_h": [[1070, 1330], [2670, 2930]],
        "roads_v": [[1070, 1330], [2670, 2930], [4070, 4330]],
        "rail": {"y": 60, "h": 140, "platform": [200, 262]},
        "park": {"rect": [3220, 1520, 760, 1020]},
    }
    pool = (["house"] * 9 + ["mansion"] * 2 + ["konbini"] * 2 + ["ramen"] * 2
            + ["super"] * 2 + ["cafe"] * 1 + ["furniture"] * 1 + ["post_office"] * 2)
    return {"name": "harbor", "seed": 20261005, "world": world,
            "spawn": [2650, 3400], "station": [2200, 3120], "portal": [2200, 3400],
            "ground": ground, "pool": pool}


def hillside_cfg():
    world = [5200, 4000]
    ground = {
        "base_color": "#cdc7b6", "sidewalk": 90,
        "roads_h": [[1070, 1330], [2670, 2930]],
        "roads_v": [[1070, 1330], [2670, 2930]],
        "park": {"rect": [1400, 1400, 1160, 1160]},
    }
    pool = (["house"] * 10 + ["mansion"] * 3 + ["konbini"] * 2 + ["ramen"] * 2
            + ["super"] * 2 + ["cafe"] * 2 + ["furniture"] * 1 + ["post_office"] * 2)
    return {"name": "hillside", "seed": 20261006, "world": world,
            "spawn": [2300, 3400], "station": [2000, 3120], "portal": [2000, 3400],
            "ground": ground, "pool": pool}


def main():
    from collections import Counter
    for cfg, path in [(harbor_cfg(), "data/city_harbor.json"),
                      (hillside_cfg(), "data/city_hillside.json")]:
        out = City(cfg).run()
        with open(path, "w", encoding="utf-8") as f:
            json.dump(out, f, ensure_ascii=False, indent="\t")
        c = Counter(o["kind"] for o in out["objects"])
        print(f"{path}: {len(out['objects'])} objects  spawn={out['spawn']}")
        print("   ", dict(c))


if __name__ == "__main__":
    main()
