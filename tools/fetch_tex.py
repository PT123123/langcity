#!/usr/bin/env python3
"""从 Poly Haven (CC0) 批量抓取 PBR 贴图到 assets/tex/。

用法:
    python fetch_tex.py                # 下载清单里所有条目
    python fetch_tex.py road grass     # 只下指定条目
    python fetch_tex.py --list         # 列出本地已有

命名约定（配合 Godot 侧 mat_photo 使用）:
    <id>_col.jpg   albedo
    <id>_nrm.jpg   normal (OpenGL, +Y 上)
    <id>_rgh.jpg   roughness (灰度)
默认下 1k jpg，与项目现有 9 套贴图规格一致。
"""
import json
import os
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEST = os.path.join(ROOT, "assets", "tex")
API_FILES = "https://api.polyhaven.com/files/%s"
UA = {"User-Agent": "LangCity-tex-fetcher/1.0"}

# 项目实际用到的贴图清单。id 为 Poly Haven 资产名。
# 分组对应游戏里的用途，方便后续调 tint。
# 名称已对 api.polyhaven.com/assets 校验过（2026-10）。
WANTED = {
    # ---- 地面 ----
    "aerial_asphalt_01": "road",
    "worn_asphalt": "road_alt",
    "concrete_pavers": "pavers",
    "worn_patterned_pavers": "pavers_alt",
    "concrete_pavement_02": "pavement",
    "cobblestone_pavement": "cobble",
    "worn_concrete_floor": "concrete",
    "grass_ground": "grass",
    "sparse_grass": "grass_sparse",
    "dirt": "dirt",
    "dirt_floor": "dirt_path",
    # ---- 墙面 ----
    "grey_plaster": "plaster",
    "worn_plaster_wall": "plaster_alt",
    "painted_plaster_wall": "plaster_paint",
    "worn_mossy_plasterwall": "plaster_old",
    "plaster_brick_01": "plaster_brick",
    "brick_wall_001": "brick",
    "yellow_brick": "brick_warm",
    "red_brick_03": "brick_red",
    "worn_brick_wall": "brick_old",
    "concrete_wall_001": "wall_concrete",
    "patterned_slate_tiles": "stone",
    "rustic_stone_wall": "stone_rustic",
    "concrete_tile_facade": "concrete_tile_facade",  # 商店/公寓外墙小口瓷砖
    "japanese_stone_wall": "stone_jp",
    "plaster_stone_wall_01": "plaster_stone",
    # ---- 屋顶 ----
    "clay_roof_tiles": "roof",
    "roof_slates_02": "roof_slate",
    "grey_roof_tiles": "roof_tile",
    # ---- 楼梯 / 踏步 / 门槛（台阶是玩家每天踩的面，不能只有纯色盒）----
    "concrete_tiles": "step_concrete",   # 水泥踏步/缘石
    "large_grey_tiles": "step_grey",     # 大块灰阶石（车站/公共建筑）
    "stair_planks": "step_wood",         # 木踏步
    "anti_skid_tiles": "step_antiskid",  # 防滑砖（浴室/玄关）
    "granite_tile": "step_granite",      # 花岗岩踏步
    # ---- 木材 / 家具 ----
    "wooden_planks": "wood",
    "dark_planks": "wood_dark",
    "brown_planks_08": "wood_warm",
    "wooden_panels": "wood_panel",
    "wooden_gate": "wood_gate",
    "japanese_cedar_bark": "bark_cedar",
    "bark_brown_02": "bark",
    # ---- 室内地面（原来 wood_floor / tiles 只在代码里引用、磁盘上根本没有，
    #      室内全程走ProceduralTex 程序纹理 —— 这批补齐后interior_builder 改用真贴图）----
    "wood_floor": "wood_floor",
    "tatami_mat": "tatami",              # 榻榻米（和室）
    "interior_tiles": "tiles",           # 室内地砖（玄关/厨房/浴室）
    "terrazzo_tiles": "tiles_terrazzo",  # 水磨石（车站/商店地面）
    "old_wood_floor": "floor_old_wood",
    "hinoki_planks": "wood_hinoki",      # 檜木板（室内墙裙/天花板）
    # ---- 立面差异化：民居 12 栋不能全用同一张 grey_plaster ----
    "white_planks_clean": "wall_white_plank",
    "weathered_plank_siding": "wall_plank_siding",
    "bamboo_wall": "wall_bamboo",
    "yellow_plaster": "wall_yellow",
    "white_plaster_rough_01": "wall_white_rough",
    "worn_mossy_plasterwall": "wall_mossy",
    "concrete_block_wall_02": "wall_block",
    # ---- 金属 / 涂装 ----
    "metal_plate": "metal",
    "blue_metal_plate": "metal_blue",
    "rusty_metal_02": "metal_rust",
    "rusty_corrugated_iron": "metal_corrugated",
    "worn_corrugated_iron": "metal_iron",
    "painted_metal_shutter": "metal_shutter",
    # ---- 其他 ----
    "dirt_aerial_02": "dirt_dark",
    "pebbles": "pebbles",
    # ---- 家具/家电「表面族」贴图（Kenney 家具·家电·植物原本是纯色材质）----
    # 需求来源：用户要求「几乎所有模型都要有贴图，不要纯的裸的」。
    # Kenney 的 Furniture/Nature 系模型材质只有 baseColorFactor、没有贴图，
    # 靠 ModelUtil 的材质名→贴图映射补上（见 model_util.gd 的 SURFACE_TEX）。
    "fabric_pattern_07": "fabric",        # 地毯/沙发/椅面软布
    "fabric_pattern_05": "fabric_alt",    # 备用软布（花纹不同，避免整屋同纹）
    "leather_white": "leather",           # 沙发/椅面皮革
}


def human(n: int) -> str:
    for u in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.0f}{u}"
        n /= 1024.0
    return f"{n:.1f}TB"


def get_json(url: str, retries: int = 3):
    for i in range(retries):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.loads(r.read().decode())
        except Exception as e:  # noqa: BLE001
            if i == retries - 1:
                print(f"    ! API 失败 {url}: {e}")
                return None
            time.sleep(1.5 * (i + 1))
    return None


def download(url: str, path: str, retries: int = 3) -> bool:
    for i in range(retries):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=120) as r, open(path, "wb") as f:
                total = 0
                while True:
                    chunk = r.read(1 << 16)
                    if not chunk:
                        break
                    f.write(chunk)
                    total += len(chunk)
            print(f"    + {os.path.basename(path):32s} {human(total)}")
            return True
        except Exception as e:  # noqa: BLE001
            if i == retries - 1:
                print(f"    ! 下载失败 {os.path.basename(path)}: {e}")
                return False
            time.sleep(2.0 * (i + 1))
    return False


def fetch(asset_id: str, res: str = "1k", alias: str = "") -> int:
    """抓一套 col/nrm/rgh。返回成功下载的文件数。
    alias 非空时按别名命名文件（代码里用语义名，更易读）。"""
    meta = get_json(API_FILES % asset_id)
    if not meta:
        return 0
    name = alias or asset_id
    # Poly Haven 通道名 -> 本地后缀
    #
    # 【漫反射为什么要一串候选】不是所有资产的漫反射都叫 "Diffuse"：
    # fabric_pattern_07 / 05 这类多色织物把通道拆成 col_1 / col_2 / col_03，
    # 只认 "Diffuse" 会静默跳过 —— 结果是 nrm/rgh 下了、col 没下，
    # 而 Interactable._scan_tex() 只认 *_col.jpg，于是这个 kind 等于不存在。
    # （症状：地毯/沙发材质"看起来没贴图"，但日志里这套贴图明明下载过。）
    channels = [
        (("Diffuse", "col_1", "col_2", "col_03", "base_color"), "col"),
        (("nor_gl",), "nrm"),
        (("Rough",), "rgh"),
    ]
    got = 0
    for keys, suffix in channels:
        node = None
        for key in keys:
            if meta.get(key):
                node = meta[key]
                break
        if not node:
            continue
        # 优先 jpg（体积小），没有就 png
        for fmt in ("jpg", "png"):
            if fmt in node.get(res, {}):
                info = node[res][fmt]
                out = os.path.join(DEST, f"{name}_{suffix}.{fmt}")
                if os.path.exists(out) and os.path.getsize(out) > 2000:
                    got += 1
                    continue
                if download(info["url"], out):
                    got += 1
                break
    return got


def main() -> int:
    os.makedirs(DEST, exist_ok=True)
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if "--list" in sys.argv:
        ids = sorted({f.rsplit("_", 1)[0] for f in os.listdir(DEST) if f.endswith(".jpg")})
        print(f"本地已有 {len(ids)} 套:")
        for i in ids:
            print("   ", i)
        return 0

    # 支持 `python fetch_tex.py alias:asset_id` 只抓指定套
    targets = []
    for a in args:
        if ":" in a:
            al, aid = a.split(":", 1)
            targets.append((aid, al))
        else:
            targets.append((a, WANTED.get(a, a)))
    if not targets:
        targets = [(aid, alias) for aid, alias in WANTED.items()]

    print(f"目标：{len(targets)} 套贴图 -> {DEST}\n")
    total_files = 0
    failed = []
    for n, (aid, alias) in enumerate(targets, 1):
        print(f"[{n}/{len(targets)}] {aid} -> {alias}")
        got = fetch(aid, alias=alias)
        if got == 0:
            failed.append(aid)
        else:
            total_files += got
        time.sleep(0.25)  # 别把官方 CDN 打成靶子

    print(f"\n完成：{total_files} 个文件")
    if failed:
        print("失败条目：")
        for f in failed:
            print("   ", f)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
