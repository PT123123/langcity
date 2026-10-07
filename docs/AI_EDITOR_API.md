# AI 编辑接口（无头批处理）

把**地图编辑器 + 人物 / 任务 / 对话编辑器**的全部能力开放给 AI（或脚本）程序化调用：
不开 GUI，喂一份 JSON 操作清单，一条命令跑完。JSON 进、JSON 出。

实现：`_tools/ai_editor.gd`（`ai_editor.tscn`）。判定内核复用 `scripts/street/map_validator.gd`。

## 运行

```powershell
# 推荐：包装脚本（免引号烦恼）
just ai-edit out/ops.json
python _tools/ai_edit.py out/ops.json

# 直接调 Godot
_tools\Godot_v4.4.1-stable_win64_console.exe --headless --path . `
    res://_tools/ai_editor.tscn -- --ops=res://out/ops.json --out=res://out/result.json

# 闭环自检（只碰 out/ 副本，不写 data/）
_tools\Godot_v4.4.1-stable_win64_console.exe --headless --path . `
    res://_tools/ai_editor.tscn -- --selftest
```

## ops 文件结构

```json
{
  "map": "res://data/planet.json",   // 可选，默认 planet.json；测试可指向副本
  "save": true,                      // 跑完自动保存所有被改动的文件（带备份）
  "ops": [ {"op": "map.move_by", "find": {"kind": "station"}, "dx": 40, "dy": 40} ]
}
```
- 顶层 `"save": true`，或在 ops 里放一条 `{"op":"save"}`。
- **启动过程只读**；只有 save 才写文件（`.bak` 备份 + 临时文件原子替换，绝不半截写盘）。
- 任何一条失败，整体 exit code = 1；结果逐条回报，写入 `--out`（默认 `out/ai_ops_result.json`）。

## 通用 find 语法

`{"index": n}` 或 `{"kind": x, "word": y?, "npc": z?, "host": w?, "label": l?, "nth": k?}`
（`nth` 缺省 0 取第一条，-1 取最后一条）。

## 查询

| op | 参数 | 返回 |
|----|------|------|
| `query.objects` | `find?` `limit?` | 物件清单（index/kind/x/y/word/npc/patrol…） |
| `query.kinds` | – | 各 kind 数量 |
| `query.npcs` | – | 地图上的 npc 条目（含 patrol / patrol_mode / appear_phase） |
| `query.quests` | – | 全部任务 |
| `query.dialogues` | – | 全部对话概览（start / nodes） |
| `query.ground_at` | `x` `y` | 落点 hit / grounded / r |
| `query.reachable_at` | `x` `y` `tol?` | `on_nav` / `main`（是否可达主城区）/ dist |
| `query.density` | `find` `radius?` | near / nearest / 稀疏·适中·偏密·过密 |
| `query.ops` | – | 本接口全部 op 的自描述表 |

## 地图

| op | 参数 | 说明 |
|----|------|------|
| `map.find` | `find` | 返回 index |
| `map.move` | `find` `x` `y` `rot?` `snap_ground?` `force?` | 绝对落位 |
| `map.move_by` | `find` `dx` `dy` `snap_ground?` `force?` | 增量平移（带动门/窗） |
| `map.rotate` | `find` `deg?` \| `ddeg?` | 绝对 / 相对旋转 |
| `map.set` | `find` `fields{}` | 改任意字段（kind/x/y 请用专用 op） |
| `map.add` | `entry{}` `snap_ground?` `force?` | 新增，返回新 index |
| `map.duplicate` | `find` `dx?` `dy?` `force?` | 复制 |
| `map.remove` | `find` `all?` `with_deps?` | 删除（默认连带门/窗） |
| `map.autoplace` | `find` | 螺旋找合法落点（见下） |
| `map.autoplace_all` | – | 自动重放所有「非适合」建筑 |
| `map.snap` | `find` | 吸附到最近可落脚地面 |
| `map.inspect` | `find` | 单栋判定：落点 + 可达性 + 密度 + 结论 |
| `map.validate` | `find?` 或 `navmesh?` | `find` 出单栋；否则出全图 counts/problems；`navmesh:true` 附带通路切断 |

`map.move/move_by/add/duplicate` 默认做落点安全检查：**贴地吸附 + 拒绝 REJECT + 拒绝互叠**；
不合法则报错回滚（`force:true` 可强加）。

## 人物 / 任务 / 对话

| op | 参数 |
|----|------|
| `npc.add` | `npc` `x` `y` `patrol?` `patrol_mode?` `patrol_speed?` `patrol_wait?` `appear_phase?` `snap_ground?` |
| `npc.remove` | `find` |
| `npc.set` | `find` `fields{}`（patrol 航点会校验可走性，剔除不可走点并回报 warnings） |
| `npc.catalog.add/set/remove` | `id` `glb?` `name?` `zh?` `height?` / `fields{}` |
| `quest.add/set/remove` | `quest{}` / `id` `fields{}`（五种类型 collect/errand/talk/photo/visit 全支持并校验） |
| `dialogue.set` | `npc` `dialogue{}` |
| `dialogue.node.set` | `npc` `node` `lines[]` `choices[]` |
| `dialogue.node.remove` | `npc` `node` |
| `dialogue.remove` | `npc` |

## 撤销 / 相机 / 保存

| op | 说明 |
|----|------|
| `undo` / `redo` | 撤销 / 重做上一步 `map.*` 或 `npc.add/remove/set`（objects 快照） |
| `camera.get` | 取相机/移动模式状态（可视化前端用；对数据无影响） |
| `camera.set` | 设 `mode?` `yaw?` `pitch?` `dist?` `move_mode?` `focus?` `locked?` |
| `save` | 写回所有脏文件（map/npcs/quests/dialogues） |

## 判定口径（与可视化编辑器一致）

- **落点质量**（`MapValidator`）：射线是否命中真地形、是否摆进海里、坡太陡、孤峰/崖边探头、
  占地悬空/半埋、与其它建筑 AABB 互叠 → `verdict`（ACCEPT/MOVE/ROTATE/REJECT/SKIP）+ `score`。
- **可达性**：烘焙地形 NavMesh，落点附近最近可行走面是否属于**主连通域**（孤岛 = 进不去）。
- **密度**：12m 内建筑级邻居数 → 稀疏 / 适中 / 偏密 / 过密。

`map.inspect` 的 `conclusion` 会把三者合成最终结论：不可达 → REJECT；落点 ACCEPT 但过密 → MOVE。

## 自动放置算法（`map.autoplace` / `map.autoplace_all`）

由近及远螺旋（`SNAP_RADII` 环 + 每环 16 方位）。候选必须：贴地、不 REJECT、不悬空
（`max_drop ≤ FOOT_FLOAT_TOL`）、不与任何建筑互叠、附近可达主城区。
评分 = `落点分 − 密度罚（>5 栋逐个扣、0 栋也扣）− 位移罚（每米）`，
**由近及远，第一个达 ACCEPT 的候选立即采用**（就近安置）。批量时已放的即时进互叠缓存。

## 示例

```json
{"op":"map.validate","navmesh":true}
```
```json
{"op":"query.density","find":{"kind":"house","nth":0}}
```
```json
{"op":"map.inspect","find":{"kind":"station"}}
```
```json
{"ops":[
  {"op":"map.autoplace_all"},
  {"op":"map.validate"},
  {"op":"save"}
]}
```
```json
{"ops":[
  {"op":"map.add","entry":{"kind":"vending","x":2600,"y":1500,"word":"vending","rot":90}},
  {"op":"map.autoplace","find":{"kind":"vending","nth":-1}},
  {"op":"undo"}
]}
```

结果：单条 op 的结构见各表；summary 形如
`{"ok":true,"ops_total":N,"ops_ok":N,"saved":[...],"results":[...]}`，每项带 `i/op/ok/result|error`。

## 全图搬迁工作流（判定 → 演练 → 过滤 → 执行 → 复验）

「把不该在那里的建筑重新安置」不是一条 op 能做完的事，按下面五步跑（2026-10-07 首次实践，
记录见下一节）。核心纪律：**先在副本上演练，真数据只在最后一步写回**。

**第 1 步 · 全图判定（只读）**

```json
{"ops": [{"op": "map.validate", "navmesh": true}]}
```

拿到 `counts`（ACCEPT/MOVE/ROTATE/REJECT）、`problems`（非适合清单，含 index/kind/score/px）、
`nav`（主可行走域面积 + 被建筑围死的割裂区）。候选 = **REJECT 全体 ∪ map.inspect 里
`reachable.main=false` 的物件**（后者要逐个 `map.inspect` 取，判定才含可达性）。

**第 2 步 · 排除「不该自动搬」的**

- **任务地标**（跑腿/传送/拍照任务按 kind 找它们，动了改任务地理）：
  `station` / `konbini` / `ramen` / `cafe` / `post_office` / `parksign` / `sakura` / `counter` / `gate`。
- **「半埋/过密」型 REJECT 的镇中心大件**：山城建筑嵌在坡地基座上是设计使然
  （如 hospital/bank/police/temple/school/library），360px 内没有更优落点，强搬毁布局。
- 这两类单独列出来给人看，不进自动重放清单。

**第 3 步 · 副本演练**

把 `data/planet.json` 复制一份（如 `out/probe_planet.json`），ops 文件顶层写
`"map": "res://out/probe_planet.json"`、**不写 save**，对每个候选跑
`{"op":"map.autoplace","find":{"index":i}}`，末尾补一条 `map.validate` 看改善幅度。

**第 4 步 · 过滤假改善**（用演练的 before/after 分数对照）

- 位移 < 5px 的「搬家」是假修复——问题在**密度**（过密）不在落点，autoplace 原地不动也算成功；
- 新分数 < 旧分数 + 5 的剔除（改善不足，白折腾）；
- 新分数为负的坚决剔除（越搬越差）。

**第 5 步 · 执行 + 复验**

先手动备份（`cp data/planet.json out/planet_backup_<日期>.json`，planet.json 未进 git，
接口的 `.ai-editor.bak` 只在首次保存时生成、不覆盖），然后对真数据跑同一批 autoplace +
`map.validate` + 顶层 `"save": true`，逐条核对 `ok` 与搬迁明细，最后跑一次
street 场景冒烟确认游戏能加载。

## 搬迁记录 2026-10-07（首批 15 栋）

判定基线：245 物件 = ACCEPT 195 / MOVE 14 / **REJECT 34** / ROTATE 2；主可行走域 1165㎡，割裂区 7 处。
副本演练 38 个候选 → 过滤后执行 15 栋（16/16 ops 成功），已写回 `data/planet.json`。

| # | kind | 搬前 (px) | 搬后 (px) | 位移 | 分数 搬前→搬后 | 备注 |
|---|------|-----------|-----------|------|----------------|------|
| 2 | house | (645, 542) | (509, 209) | 360px | 0 → 41 | 0 分=射线落空（悬空） |
| 5 | super | (3754, 2848) | (4007, 3104) | 360px | 31 → 51 | |
| 12 | house | (5200, 434) | (5064, 101) | 360px | 0 → 41 | 悬空 |
| 14 | house | (1281, 881) | (1174, 1000) | 160px | 30 → 52 | 门窗 #22 随动 |
| 16 | house | (5091, 4000) | (5121, 4002) | 30px | 29 → 59 | 图缘 |
| 17 | house | (3206, 3846) | (3268, 3924) | 100px | 0 → 58 | 悬空 |
| 48 | bench | (3212, 1742) | (3266, 1591) | 160px | 42 → 65 | |
| 49 | bench | (3494, 1713) | (3445, 1800) | 100px | 35 → 62 | |
| 89 | lowwall | (3198, 1723) | (3327, 1520) | 241px | 44 → 72 | |
| 108 | bed | (3135, 3673) | (3137, 3688) | 15px | 0 → 60 | 悬空 |
| 118 | mansion | (986, 538) | (1137, 592) | 160px | 19 → 86 | |
| 156 | laundry | (5038, 592) | (5065, 605) | 30px | 4 → 59 | |
| 160 | laundry | (186, 3185) | (50, 2852) | 360px | 68 → 91 | |
| 207 | truck | (425, 1276) | (296, 1479) | 241px | 0 → 74 | 悬空 |
| 208 | boat | (3390, 1214) | (3550, 1206) | 160px | 17 → 36 | 陡坡上移到缓坡 |

门窗随宿主自动跟搬：#18 door、#21 window（宿主 #2 house）、#22 window（宿主 #14 house）。

**执行后**：ACCEPT 197 / MOVE 29 / **REJECT 17** / ROTATE 2；主可行走域 1267㎡（+102㎡）；割裂区 7 → 5 处。
（MOVE 变多是因为搬完的物件多数落在 55~84 分区间，从 REJECT 升到了 MOVE 档。）

**刻意不动的 17 个 REJECT**（三类，见工作流第 2 步）：

- 任务地标 4：`#0 station`（半埋 12m=山城基座设计，门口距主路 1.9m 实际可达）、`#6 cafe`、`#9 ramen`、`#10 post_office`
- 大型公共建筑 6（360px 内无合法落点）：`#200 temple`、`#201 school`、`#202 hospital`、`#203 bank`、`#204 police`、`#205 library`
- 图缘小件 7（附近无可走地面）：`#53/#54/#55 car`、`#97 furniture`、`#135/#154 laundry`、`#206 truck`

**回滚备份**：`out/planet_backup_20261007_before_relocate.json`（全量快照）、
`data/planet.json.ai-editor.bak`（接口首次保存时自动生成，之后不覆盖）。

## 水位调整（`water_drop`，2026-10-07 第二批）

水位是烘焙在美术件里的球壳（`planets_present_water`），`planet.json` 的 `planet` 段新增
`"water_drop"`（单位=世界米）让水壳绕球心均匀收缩 —— 浅沟/岸架露出来变成可走陆地，
蓄水山沟变少。`planet_builder.gd` 落实（视觉壳、水面碰撞、`water_radius` 门槛同步），
摆件/软墙/小地图自动跟随；**岸沫/瀑布 VFX 仍烘焙在旧水位上，会有 ≤drop 的悬差**。

**本次采用 drop=1.4m**（探针实测：可落脚网格 1981 → 2461，约 +1900㎡ 新岸架与干沟床；
镇中心水道干涸、左岸后退，见 `out/water_before_view.png` / `out/water_after_view.png`）。

随水位一并安置的「没地可放」建筑（试搬评分达标才落位）：

| # | kind | 搬前 → 搬后 (px) | 分数 | 说明 |
|---|------|------------------|------|------|
| 54 | car | (1950, 3313) → (1998, 3079) | 0 → 54 | 射线落空 → 新岸架 |
| 55 | car | (3350, 2890) → (3738, 2777) | 42 → 69 | |
| 97 | furniture | (3406, 3195) → (3406, 3395) | 5 → 60 | ACCEPT |

**试搬后放弃的**（副本演练里 score 达标但 `map.inspect` 结论 REJECT=落在与主城区割裂的
新岸架上，猫走不到；或改善不足 5 分）：`#53 car`、`#135/#154 laundry`、`#206 truck`、
以及全部大公共建筑（temple/school/hospital/bank/police/library —— 它们的问题山坡地形，
降水解决不了）。留在原位不劣化。

判据口径提醒：`map.validate`（全图）与 `map.inspect`（单栋 eval_one）对同一物件可能差分
（车站 60 vs 0、super 51 vs 28），verdict 大方向一致；重要决定用两种口径交叉确认。
回滚备份：`out/planet_backup_20261007_before_waterdrop.json`（本批之前）。

## 第三批搬迁：空地开发（2026-10-07，v1 回滚 → v2 连通性选址）

空地盘点（`_tools/spot_probe.tscn`，全岛 2m 网格 + 虚拟 house 试评 + NavMesh 可达性）：
岛南/东南一整片连续空地 ~6952㎡（中心 px 2207,2369），可达格子里优质(≥85) 88㎡、
尚可(55-85) 5292㎡；分布图 `out/spot_map.png`。

**v1 教训**：直接按 spot 分数贪心把 17 栋 REJECT 全搬进空地（`_tools/relocate_plan.tscn`），
落点自身 eval 全 ACCEPT，但全图判定主步行域 1169→889㎡ —— 大建筑落在窄步行带边缘，
自己把路切断了（自己的门口也被自己的 footprint 堵成不可达）。已整体回滚。

**v2 正确姿势**（`_tools/relocate_plan2.tscn`）：每个候选落点试算「放进去之后的主域面积 +
新增割裂区」（地形 NavMesh 只烘一次，建筑用 OBB 多边形剔除模拟，试算纯图操作、很便宜），
主域下降 >2% 或出现新的 ≥20㎡ 割裂区直接淘汰。结果 6 栋成功落位：

| # | kind | 搬前 → 搬后 (px) | spot 分 |
|---|------|------------------|---------|
| 201 | school | (3182,3248) → (1120,4000) | 60 |
| 206 | truck | (2724,656) → (3680,3360) | 60 |
| 55 | car | (3738,2777) → (720,3840) | 77 |
| 54 | car | (1998,3079) → (3520,2720) | 66 |
| 135 | laundry | (2300,920) → (4560,1440) | 82 |
| 154 | laundry | (1928,3252) → (4320,1600) | 68 |

执行后：ACCEPT 197 / MOVE 35 / **REJECT 11** / ROTATE 2；主域 1118㎡（仅 -51㎡，v1 方案是 -280㎡）。

追加（用户指名）：`#8 house` 原在 (4273,4000) 地图南缘、与主城步行区割裂（main=false，猫走不到）。
单栋选址用「搬→全图判定→撤销」链路试了 5 个宽位点，选定 (1280,3960)（学校新区旁，
主域仅 -3㎡，割裂不变，inspect conclusion ACCEPT / main=true）。注意全图 validate 仍会把它
连同 school 列为 REJECT——半埋硬规则口径，物理位置已实际改善。

再追加：`#13 house` 应用户要求从 (4654,3685)（半埋 12.3m）搬到 (4560,1040)
东北部空地——半埋降到 7.68m，main=true（dist 1.27m），主域仅 -32㎡。
选址经验：单栋搬迁用「survey 格子（reach+score≥60）+ 距现有物件 ≥350px 过滤 →
试搬 5 点（move→validate→undo）选主域损失最小 → inspect 验证自身 reach」，
比 relocate_plan2 全池试算快得多且可控。

**剩余 11 个 REJECT 刻意不动**：任务地标 4（station/cafe/ramen/post_office）+ 大公共建筑
（temple/hospital/bank/police/library）+ super/house/car ×3 —— 两类原因：①校验器 finalize()
把「半埋 ≥1m」硬判 REJECT，而这些山城建筑的基座本来就该嵌进坡地（半埋 9~16m），**放哪都是
REJECT，这是口径问题不是位置问题**（同一位置 inspect=ACCEPT 60、validate=REJECT 0 即此故）；
②周边窄步行带上找不到不切路的落点。要动它们得逐栋人工在 Godot 编辑器里摆。
回滚备份：`out/planet_backup_20261007_before_bigmove2.json`（v2 之前）、
`out/planet_backup_20261007_before_bigmove.json`（v1 之前）。

## 遗留问题建筑清单与优先级（2026-10-07 深度盘点）

对 48 个问题物件（REJECT 15 / MOVE 31 / ROTATE 2）逐栋 `map.inspect` 后的完整台账。
**判读口径**：以 inspect 的 conclusion + reach.main（猫能不能走到）+ density（拥挤度）为准；
全图 validate 的 REJECT 对「半埋大件」是永久标签（finalize 硬规则），不代表位置好坏。
数据快照：`out/deep_rows.json`（48 行完整判据）。

### P0 已处置 ✅（本轮完成，全部 main=true）

| # | kind | 原位置问题 | 新位置 | 结果 |
|---|------|-----------|--------|------|
| 53 | car | 不可达+悬空+半埋11m | (4080,2000) | MOVE, main=0.5m |
| 3 | mansion | 不可达+悬空0.77m | (3600,2160) | MOVE, main=0.8m |
| 7 | house | 不可达+半埋13.9m | (3760,3840) | ACCEPT, main=0.7m |
| 120 | house | 不可达 | (5200,2000) | ACCEPT, main=2.1m |
| 8 | house | 南缘孤角 main=false | (1280,3960) | ACCEPT（上一批） |
| 13 | house | 半埋12.3m | (4560,1040) | MOVE, main=1.3m（上一批） |
| 54/55 | car×2 | 悬空/半埋 | 东部岸架 | MOVE（水位批次） |
| 97 | furniture | 半埋 | (3406,3395) | ACCEPT（水位批次） |

主步行域代价：1083 → 1012㎡（-71㎡，逐点试搬后选的最优组合）。

### P1 待处置（需要人实地看一眼再决定）

| # | kind | 问题 | 为什么不自动搬 |
|---|------|------|----------------|
| 0 | station | 不可达标签+过密(8) | **任务地标**（传送点+跑腿目标+单词 station）。自动搬会改任务地理；且镇中心「不可达」可能是 NavMesh 60° 坡度近似偏严——先实地确认猫能否走到站台 |
| 6 | cafe | 不可达+过密(10) | 同上（咖啡馆=可进室内+跑腿目标） |
| 10 | post_office | 不可达+半埋1.3m | 同上（送信跑腿目标） |
| 121 | house | 不可达+偏密 | 东北角孤区；点池已试尽（对 house 的最优代价 -436㎡ 不值） |
| 11 | house | 不可达 | 同上 |
| 9 | ramen | 悬空0.62m+偏密(5) | 地标（拉面店可进室内）；悬空量小，观感优先级低 |

P1 的正确解法大概率是「挪周边堵路的房子/围墙给地标让路」，而不是搬地标本身。

### P2 观感与密度（有空再做，不影响可玩性）

- **过密群**（互相拉开间距即可）：#13 house(11)、#135 laundry(12)、#111 bench(10)、#4/#15 mansion（ROTATE，9/7）、#200 temple(8)、#12 house(7)、#119 house(7)、#156 laundry(7)、#208/#209 boat(7)、#52 car(7)
- **深陷观感**：#206 truck 半埋 19.4m（全岛最深，但可达）、#108 bed 8.7m、#201 school 7.3m——都在可达带，纯观感
- **不可达大件**：#202 hospital、#203 bank、#204 police（半埋 7~16m，窄带难安置，v1/v2 都没找到不切路的位置）——需人工在 Godot 编辑器摆
- **装饰件**：#85 lowwall 悬空 0.77m——可挪可删

### 不用管（口径噪音）

22 个 inspect conclusion=ACCEPT 的物件（konbini/super/ramen/bench/sofa/lowwall/car...）——
validate 的 MOVE/REJECT 标签全部来自半埋/坡度硬规则（山城设计使然），无需处理。

判据快照与工具：`out/deep_rows.json`（48 行）、`_tools/spot_probe.tscn`（空地盘点）、
`_tools/relocate_plan2.tscn`（连通性选址，支持 --only/--tol/--trials）。
回滚备份链：`out/planet_backup_20261007_before_p0.json`（本批前）→ `_before_house13.json` →
`_before_house8.json` → `_before_bigmove2.json` → `_before_bigmove.json` →
`_before_waterdrop.json` → `_before_relocate.json`。

**已知口径差**：`map.validate`（全图管线）与 `map.inspect`（单栋 eval_one）对同一物件可能差分
（station 一个 0 一个 60），但 verdict 方向一致；以全图 validate 做基线、inspect 做单栋深挖即可。
