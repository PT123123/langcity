# 地图浮空问题排查与修复（满岛东西挂在天上）

> 2026-10-05。用户反馈「地图做的太差了，很多在天上的」。
> 本文记录量化基线、根因、修复内容、验证数据与排查过程中的判断失误。
> 与 [PLANET_WORLD_FIX.md](PLANET_WORLD_FIX.md)（上一次碰撞/移动修复）是**不同的 bug**，别混淆。

---

## 一、结论速览

| | |
|---|---|
| **根因** | `street.gd._build_planet()` 在 `_ready()` 里就调 `surface()` 打射线，而 trimesh 碰撞要到**下一个物理帧**才进宽相 → 射线全部落空 |
| **兜底危害** | `surface()` 落空时静默返回标称球面 `r = 34 × 1.5 = 51`，而真实岛面只有 `r ≈ 35~49` → **245 个物件整整齐齐挂在 1.3~15.8m 空中** |
| **修复** | 摆件延后一帧；`surface()` 返回 `hit` 字段；坡度比真落点径向而非标称球面 |
| **结果** | 悬空物件 **240 → 1**（剩的那个是门吸附到建筑正面的预期偏移，不是浮空） |

---

## 二、排查过程（含走过的弯路）

### 1. 第一个弯路：被现有探针的「全命中」误导

先跑 `_tools/probe_planet.tscn`，输出：

```
[probe] objects hit=245 miss(fallback)=0
[probe] hit radius range: 35.0 .. 55.1
```

245 个全部命中地形，0 兜底 —— 看起来完全正常。**但这个结论是假的。**

看 `probe_planet.gd` 的代码才发现，它在 `_ready` 里 `await get_tree().physics_frame` 两次**之后**才打射线：

```gdscript
builder.setup(math, pcfg)
await get_tree().physics_frame
await get_tree().physics_frame   # ← 等了物理，命中率高是必然的
```

探针复刻的是「物理就绪之后」的理想时序，**没有复现 `street.gd` 的真实调用时序**。它量的是「落点位置有没有地形」，而不是「物件实际被摆到哪」。

> **教训**：验收工具本身可能就是错的。对「满岛浮空」这种全局现象，
> 用一个已知有前科（它就是上一轮排查留下的）的工具去验，等于没验。

### 2. 第二个弯路：先怀疑了错误的原因

在没有实测数据前，我依次怀疑过：

- **shader 顶点位移**让地形和碰撞错位 → 查 `island_*.gdshader` / `toon.gdshader`，除云层 ±0.5m 径向摆动外无位移，且碰撞用 `mesh.create_trimesh_shape()` 与渲染顶点完全一致。**排除**。
- **`surface()` 兜底被大量触发**（图缘物件射线打空）→ 这是 `PLANET_WORLD_FIX.md` 里记录过的老问题。但探针显示 0 落空。**排除**。
- **落点在海底/悬崖** → `curate_planet.tscn` 上次整备报告是「保留 238 / 搬迁 2 / 无法安置 0」。**排除**。

真正的原因是**调用时序**，而代码里其实早有线索 —— `street.gd` 里给玩家的出生点写了这么一段注释：

```gdscript
# 【延迟落位】_planet_spawn_pos() 里的 surface() 射线在 _ready() 阶段打不到
# 地形（物理服务器尚未把 trimesh 同步进宽相），会返回标称球面 r=34×scale=51，
# 而真实岛面在 r≈35.5 —— 出生点悬空 15m，猫一进世界就自由落体。
```

**玩家被识别出这个问题并做了补救**（`Player.request_ground_snap()` 延迟到第一个物理帧重新贴地），**但 245 个地图物件没有这份补救** —— 它们在同一个 `_ready` 里被摆上 51m 兜底球面，然后就没人管了。

这也解释了为什么 bug 能活这么久：玩家会掉下来摔一下自己纠正，物件不会。

### 3. 写对工具才量出真数据

新写 `_tools/audit_float.tscn`，**刻意不在 `_ready` 里 await**，复刻 `street.gd` 的真实时序，再用「当时的落点」对比「物理就绪后的真值」：

```
=== 浮空审计 ===
_ready 时序命中地形: 0 / 245（其余走标称球面 r=51.0 兜底）
物理就绪后复查：贴地 0 / 悬空(>0.35m) 240 / 总 245
surface() 打得到真实地面所需物理帧数：1
```

三行数据把根因、范围、修复参数一次说清：

- **0/245 命中** → 不是个别物件，是**全部**
- **240 悬空**，空隙 1.3~15.8m → 与「很多在天上」的主观描述完全吻合
- **只需 1 个物理帧** → 修复用 `await get_tree().physics_frame` 即可，不必轮询或魔改数字

最大空隙样本（真实地面 r 明显小于兜底的 51）：

| kind | px | 空隙 | 兜底 r | 真实 r |
|---|---|---|---|---|
| mansion | (4934,1288) | 15.8m | 51.0 | 35.2 |
| super | (3754,2848) | 15.8m | 51.0 | 35.1 |
| mansion | (5200,1189) | 15.7m | 51.0 | 35.3 |
| streetlight | (2769,1363) | 15.5m | 51.0 | 35.2 |
| post_office | (4915,4000) | 13.4m | 51.0 | 37.6 |

---

## 三、修复内容

### 1. `planet_builder.gd` —— `surface()` 必须报告命中状态

```gdscript
# 修复前：落空与真值长得一模一样，调用方无法分辨
if not hit.is_empty():
    return {"pos": hit["position"], "normal": hit["normal"].normalized()}
return {"pos": d * math.radius, "normal": d}

# 修复后
if not hit.is_empty():
    return {"pos": hit["position"], "normal": hit["normal"].normalized(), "hit": true}
return {"pos": d * math.radius, "normal": d, "hit": false}
```

静默兜底是最阴的一类 bug 源：它不报错、不告警，只是安静地给出一个看似合理的数。

### 2. `street.gd` —— 摆件延后一帧（核心修复）

`_build_planet()` 只建地形，摆件挪到 `_place_all_objects_deferred()`：

```gdscript
func _place_all_objects_deferred() -> void:
	await get_tree().physics_frame          # 等 trimesh 进宽相（实测 1 帧够）
	for obj: Dictionary in map.get("objects", []):
		var it := Interactable.make(obj)
		_place_on_planet(it, obj)
		...
	_setup_scatter()                          # 装饰撒点同样走 surface()，一起延后
	_register_street_lights()                # 灯光点位要从 objects 里挑，必须在摆件后
	_refresh_quest_tracking()                 # 见下方「顺带修掉的两个回归」
	if _spawn_at_konbini_deferred:            # 见下方「新档出生点」
		_teleport_to_kind("konbini", true)
```

用 `call_deferred()` 起协程，`_ready()` 继续往下跑，玩家/HUD 不用等摆件（配合原有的淡入黑场，无可见闪烁）。

**为什么不做「先兜底摆一遍、就绪后再重摆」的两段式**：那会让 245 个节点在 51m 处先存在一帧，既浪费又容易漏掉重摆。

### 3. `street.gd` —— 坡度基准改用真落点径向

```gdscript
# 修复前：拿标称球面方向 dir（理想 r=51 球）比坡度
if up.dot(dir) > 0.8:

# 修复后：拿命中点的径向（此处真正朝外的方向）比
if up.dot((spot["pos"] as Vector3).normalized()) > 0.8:
```

`dir` 与真实落点径向差好几个度（真实岛面 r 只有 35~49），dot 被系统性压低 →
**高海拔的平地被误判成斜坡**，物件白白歪向一边。这个 bug 被时序 bug 完全掩盖了（反正都浮在空中），修好浮空后才暴露出来。

### 4. 顺带修掉的两个回归（延后摆件自己引入的）

延后意味着 `objects` 在 `_ready` 期间是空的，两处依赖它的逻辑被打破：

| 位置 | 问题 | 修法 |
|---|---|---|
| `_refresh_quest_tracking()` | `_ready` 里那次跑时 `objects` 空 → 收集任务的「最近未发现目标」光圈丢（`_process` 0.25s 节流能自愈，但有空窗） | 延后链末尾补一次 |
| `_teleport_to_kind("konbini")` | 新档出生传送靠 `_first_kind()` 找目标物件，`it == null` 时**静默 return** → 新档留在悬空的地图默认出生点 | 加 `_spawn_at_konbini_deferred` 标志，延后链末尾消费 |

---

## 四、验证

### 1. 审计工具（根因侧）—— 修复前后闭合

```
_ready 时序命中地形: 0 / 245     ← 修复前的真实行为
延后一帧后：贴地 245 / 仍落空 0   ← 修复后的行为
```

### 2. 真实场景审计（`--shot-action=audit_float`）

新增钩子：不复刻时序，直接查摆完之后的 `Interactable.global_position`，量「物件原点到当地地面、沿当地法线」的有符号距离。

```bash
_tools\Godot_v4.4.1-stable_win64_console.exe --path . --headless -- \
  --shot-frames=99999 --shot-scene=res://scenes/street.tscn --shot-action=audit_float
```

```
=== 悬空审计（真实场景） ===
物件总数 245：贴地 244 / 悬空 1 / 埋进地下 0
（判定：悬空 = 离地 > 0.35m，埋地 = 离地 < -1.2m）
悬空最大的（kind / 离地 / 当前 r）：
  door           离地=  0.90m  r=43.6
```

| | 修复前 | 修复后 |
|---|---|---|
| 贴地 | 5 | **244** |
| 悬空 | **240** | 1 |
| 最大空隙 | 15.8m | 0.90m |

**剩下那个 door 不是浮空**：`Interactable.make()` 会把门窗吸附到建筑正面
（`it.position += Vector3(dx, 0, hs.z * 0.5 + 0.12)`），审计量的是物件原点，
0.90m 就是这个吸附偏移本身。门的视觉贴在建筑面上，没有悬空。

### 3. 新档出生路径回归

清空存档（`%APPDATA%/Godot/app_userdata/日语街道/savegame.json`，先备份）
后重跑，审计结果一致（244/245），并验证传送链路：

```
[tp] kind=konbini 锚点r=43.63 base_ground_r=42.78 front=(-0.607, -0.607, -0.513)
[tp] stand_r=43.57 ((-21.640268, 33.138702, -18.220766))
```

锚点 r=43.63（真落点，非 51 兜底），落点 r=43.57 紧贴便利店门口地面。
**测完已把原存档恢复。**

---

## 五、新增/改动文件

| 文件 | 改动 |
|---|---|
| `scripts/planet/planet_builder.gd` | `surface()` 增加 `hit` 字段 |
| `scripts/street/street.gd` | 摆件延后一帧；坡度基准改真落点径向；补两处依赖 `objects` 的延后；新增 `audit_float` 钩子与 `_audit_float()` |
| `_tools/audit_float.gd` / `.tscn` | **新增**。复刻旧时序量根因 + 量所需物理帧数 + 复核延后后落点 |
| `out/audit_float.txt` / `out/audit_float_live.txt` | 审计输出 |

---

## 六、遗留与注意事项

- **`_tools/probe_planet.tscn` 仍有误导性**：它在 `_ready` 里 await 物理再打射线，
  永远显示「全命中」，**不能用它判断浮空**。判浮空用 `--shot-action=audit_float`。
  （保留它是因为它画的落点鸟瞰图仍有参考价值。）
- **同类时序风险**：`surface()` 还会被 `Player._ground_snap()`（已有延迟补救）、
  `_scatter_spots()`、`_ground_below()`（传送落点）调用。前两者已随延后链修正；
  `_ground_below()` 只在玩家交互时（运行时，物理早已就绪）调用，安全。
- **`curate_planet.tscn` 不受本 bug 影响**：它在 `_ready` 里 `await physics_frame` 4 次
  之后才做落点校验，所以上一轮整备的数据是可信的。**无需重跑整备。**
- `interactable.gd:15 类 kind`（`temple`/`school`/`hospital`/`bank`/`police`/`library`/
  `truck`/`boat`/`ticket_sign`/`goods`/`plate`/`deer`/`fox`/`wolf`/`turtle`）
  仍**没有 `_b_*()` 视觉构建函数** —— 这 15 类在 `planet.json` 里有 45 个 cc0 物件，
  只有碰撞体和点击盒、没有外形。这是**另一个未修的内容缺口**，与浮空无关。
- 存档在 `%APPDATA%/Godot/app_userdata/日语街道/savegame.json`，动之前先备份。
