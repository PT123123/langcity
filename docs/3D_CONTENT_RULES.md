# 3D 内容修改规范：走框架，禁止手撸

> 给 AI（和未来的自己）的硬约束。写代码前先读这篇。
> 类比：在 Windows 上做界面，你不会用 Win32 直接调渲染 API 自己画控件——
> 你走框架的控件体系。本项目里，**地图 / 模型 / 材质就是那些控件**，
> 手撸它们 = 绕过整条校验、批处理、口径体系。

## 为什么必须死死限定

1. **不可验证**。手写坐标 / 顶点 / 材质参数没有判定口径；框架路径（MapValidator、
   autoplace、probe 工具）每一步都有 ACCEPT/REJECT 和分数。
2. **破坏既定口径**。星球摆件有贴地射线、可达性 NavMesh、密度、互叠 AABB 一整套
   规则（`map_validator.gd`）。手撸的物件不在口径里，后续所有自动化（跑腿指路、
   任务导航、传送、搬迁）都会被它坑。
3. **破坏批处理与性能契约**。材质走共享工厂是为了 draw call 批处理（470k 顶点地形
   只有 4 个 draw 分支）；手 new 材质 = 悄悄毁掉帧率。
4. **不可回滚**。框架路径有备份链与 undo；手撸散在代码 diff 里，撤不干净。

## 三类内容的唯一合法路径

### 地图 / 摆件（data/planet.json 等）

- **只通过 ops 修改**：写 ops.json → `just ai-edit out/ops.json`。
  全部可用 op 见 `docs/AI_EDITOR_API.md`（query.* / map.* / npc.* / quest.* / dialogue.*）。
- **禁止**：
  - 在 GDScript 里手写 `Vector3` 摆物件；
  - 用文本编辑直接改 planet.json 的 x/y/rot 字段；
  - 手算「这个 px 大概在哪」——用 `query.ground_at` / `query.reachable_at` / `query.density` 问。
- 选址交给 `map.autoplace`；批量搬迁走 AI_EDITOR_API.md 里的五步工作流
  （判定 → 排除 → **副本演练** → 过滤 → 执行+复验），真数据落盘前先备份。

### 模型（GLB / glTF）

- 新资产放 `assets/art/`，经 `tools/art_convert/` 转换入库；
- 运行时只经 `ModelUtil`（`scripts/street/model_util.gd`）：`scene()` 加载缓存、
  `normalize()` 脚贴地/XZ 居中/尺寸归一、`attach_textures()` 补贴图（colormap 族 vs
  表面族两条路，不要自创第三条）；
- **禁止**：CSG / ArrayMesh / SurfaceTool 手搓几何、手写顶点、运行时拼 Mesh。
  需要新物件 = 找/做 GLB 资产 + 走 ModelUtil 接入。

### 材质 / shader

- 平涂物件：`ToonKit`（`scripts/street/toon_kit.gd`）——在既有材质工厂里一行接入；
- 星球族（地形/水/树叶/云）：`IslandMaterials` 共享 ShaderMaterial 工厂，顶点色语义
  和贴图通道见其文件头注释，不要另起炉灶；
- **禁止**：在场景/物件代码里 `StandardMaterial3D.new()` 手调参数（绕过 ToonKit、
  破坏 TimeOfDay 扫 emissive、破坏批处理）；
- shader 改动集中在 `assets/shaders/*.gdshader`，改完跑
  `_tools/shader_verify.tscn` / `shader_compile_check.gd` 验证。

## 我（AI）以后修改 3D 内容的标准动作

1. **先查后动**：`query.objects` / `query.kinds` / `map.inspect` 摸清现状，不凭想象写坐标。
2. **选对入口**：地图 → ops；模型 → ModelUtil + art_convert；材质 → ToonKit / IslandMaterials。
3. **副本演练**：动真数据前，ops 顶层指到 `out/` 副本跑一遍，看 result.json 全绿。
4. **落盘三件套**：备份（`out/planet_backup_<日期>.json`）→ `"save": true` → 逐条核对 ok。
5. **复验**：
   - 全图：`{"op":"map.validate","navmesh":true}` 看 counts/主域面积/割裂区不劣化；
   - 游戏内：street 场景冒烟（`_tools/smoke_objects.tscn`）+
     `--shot-action=look:<kind>` 截图目检 + `--shot-action=audit_float` 查悬空。
6. **记录**：像 AI_EDITOR_API.md 的搬迁台账那样，把改了什么、分数变化、回滚点写回文档。

## 违规信号自查（代码 review 时 grep 这些）

- `Vector3(` 出现在摆件/出生点之外的硬编码定位逻辑；
- `StandardMaterial3D.new()` 不在材质工厂里；
- `ArrayMesh` / `SurfaceTool` / `CSG` 出现在非工具脚本；
- 直接编辑 `data/*.json` 的坐标字段（git diff 里 x/y/rot 变了但没有对应 ops 记录）；
- 新增「往星球上放东西」的代码路径，而不是往 ops/编辑器里加能力。

## 一句话版本

**内容是数据，数据走管线，管线带校验。代码里只允许出现「怎么用框架」，不允许出现「框架替你算好的东西」。**
