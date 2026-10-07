# 日语星球（Nihongo Planet）

一个用 **Godot 4** 制作的安卓日语学习游戏，玩法类似 Shashingo：
漫步在一颗**低多边形 3D 小星球**上的日本小镇里（马里奥银河式球形重力，可以绕星球走一整圈），
看到什么就点什么——弹出日语单词卡（汉字 / 假名 / 罗马音 / 中文），一键发音，加入你的词汇库。

> 打开手机 → 登上小星球 → 随便逛 → 看到东西就点 → 学会它的日语

完全离线：场景、单词、进度、收藏、发音全部保存在本机，无登录、无服务器。

## 游戏截图

| 街景探索（走近物体出现金色光圈） | 拍照弹出单词卡 |
|---|---|
| ![街景探索](docs/img/demo_street.png) | ![单词卡](docs/img/demo_wordcard.png) |

| 词汇库（分类进度 + 收藏） | 复习（10 题选择题） |
|---|---|
| ![词汇库](docs/img/demo_vocab.png) | ![复习](docs/img/demo_review.png) |

---

## 玩法与功能（当前 MVP）

- **3D 星球探索（第三人称猫）**：整个世界是一颗**球形小星球**——重力指向球心，
  从岛顶的町走到海滩再绕到星球背面都行；宇宙星空背景 + 星球大气雾。
  左下虚拟摇杆走路（W/S 前后、A/D 转向，相机自动回正），屏幕任意处拖动转头（桌面端 WASD/方向键 + 鼠标拖动）。
- **可进入的室内**：民居 / 公寓 / 便利店 / 超市 / 咖啡馆 / 拉面店 / 车站大厅共 7 套房间模板。
  走到建筑门口点底部【进入】加载独立室内空间（普通重力），点门口【出门】精确回到星球上的门前位置。
  室内按模板成套布置家具（玄関/居間/台所/寝室/浴室、便利店铺面、餐饮堂食、车站候车厅），
  同一模板不同建筑用存档坐标做随机微调，避免千篇一律。
- **拍照学单词（Shashingo 式）**：走近物体后它脚下会出现金色光圈，
  屏幕中央对准它按右下角【拍照】——白闪 + 快门音，弹出单词卡。
  随便点空白处不会触发单词。
- **大量可交互物体**（持续扩充中）：自動販売機、電柱、ポスト、ゴミ箱、駅、
  コンビニ、ラーメン屋、家具屋、テーブル、椅子、ベッド、洗濯機、桜、犬、猫……
  以及室内新增的 17 种家居（冷蔵庫、浴槽、トイレ、コンロ、食器棚、靴箱、エアコン、
  カーペット、絵画、カーテン、レジ、陳列棚、カウンター、椅子、券売機、改札、駅名標）。
- **剧情章节《罗生门·岭南篇》**：独立线性剧情关（主菜单「◆ 章节・罗生门 岭南篇」进入）。
  雨夜的岭南古城：官道小贩 → 南城门下避雨 → 爬上黑暗的城门楼梯 → 楼上发现拔
  死人头发的林婆 —— 观察 4 个对象、对质、**日语听力问答（听懂关键词才读得懂剧情）**、
  抢衣服 QTE，冷峻黑屏结尾 + 章节结算（新词汇 / 探索率 / PERFECT / XP）。
  章节使用的 23 个词条与正篇词库互通，学过的词计入同一条词汇库。
- **任务系统**：16 个数据驱动任务（收集 / 跑腿 / 对话 / 拍照 / 到达五类）。
  收集类「发现 N 个某分类单词」，跑腿类「按顺序走到指定地点」——含需要**进屋**的任务
  （如进咖啡馆到柜台点单、进车站过改札）；对话类「和某个 NPC 聊天」、拍照类「拍下某个目标」、
  到达类「走到某地」。任务面板可接取/追踪，左上追踪条 + 星球小地图航点实时指路。
- **NPC 对话与巡走**：点 NPC 先聊天再办事（日文台词 + 中文翻译 + 自动朗读，
  选项可直达 TA 的任务面板）；部分 NPC 会沿路线走动（闭环绕圈或走到头折返来回，
  走近时驻足等你搭话），还可配置只在朝/昼/夕/夜某些时段出现（如潜水员只在傍晚和夜里现身）。
- **单词卡**：日语 / 假名 / 罗马音 / 中文，首次发现显示 NEW WORD 并自动发音。
- **发音**：全部词条都内置神经语音合成音频（随游戏打包，离线可用，无需系统 TTS）；桌面端无音频的词条自动回退系统 TTS 朗读假名。
- **词汇库**：按分类查看进度（街道 4/13 这样的进度条），支持收藏筛选、未发现词条提示。
- **复习**：自动出 10 题选择题（看日语选中文 / 看中文选日语交替），
  错词优先复现，为以后接入 SRS 预留了 `review_stats` 数据。
- **本地存档**：已发现单词、收藏、复习记录、玩家位置、设置，自动保存，重开继续。

## 快速开始（电脑上试玩）

1. 安装 [Godot 4.4+](https://godotengine.org/download)（标准版即可，无需 .NET 版）。
2. 打开 Godot → Import → 选择本目录的 `project.godot`。
3. 按 F5 运行。桌面上：WASD/方向键移动，鼠标点击物体。

> 本目录 `_tools/` 里有一份便携版 Godot 4.4.1（`Godot_v4.4.1-stable_win64.exe`），
> 双击即可打开项目，无需安装。

## 导出安卓 APK

1. Godot 编辑器 → Editor → Manage Export Templates → 下载对应版本的导出模板。
2. 安装 Android 开发环境（Android Studio 或仅命令行工具），并在
   Editor → Editor Settings → Export → Android 里配置好 Java SDK / Android SDK。
3. 首次导出前：Project → Install Android Build Template（可选，默认不用 Gradle 也能导出）。
4. Project → Export… → 选择预设 **Android**（本项目已内置 `export_presets.cfg`：
   包名 `com.langcity.nihongostreet`，arm64 + armv7，横屏传感器方向，无需任何权限）
   → Export Project，得到可直接安装的 APK。

- 调试安装：`just installandroid`（或手动 `adb install build/nihongo-street.apk`）
- 手机上首次运行请在系统设置里允许安装未知来源应用。

## 常用命令（justfile）

已内置 [just](https://github.com/casey/just) 任务文件，装好 just 后在项目根目录直接跑：

| 命令 | 作用 |
|---|---|
| `just` / `just --list` | 列出所有可用任务 |
| `just installandroid` | 把 `build/nihongo-street.apk` 安装到已连接的安卓设备（仅安装，不启动） |
| `just edit-map` | 打开星球地图编辑器（拖放/旋转/增删建筑，人物 / 任务 / 对话数据编辑） |
| `just ai-edit out/ops.json` | AI 编辑接口：无头执行 JSON 操作清单（查询/增删改/判定/保存），结果写 `out/ai_ops_result.json` |
| `just download-resource` | 下载外部素材：Poly Haven CC0 贴图（`tools/fetch_textures.py`）+ edge-tts 生成单词发音音频（`tools/gen_audio.py`），增量执行，已有文件自动跳过 |
| `just clean` | 清理 `.godot` 导入缓存和 `out/` 开发截图；**不会**清理 `assets/` 素材与 `build/` APK |

依赖说明：
- `installandroid` 需要手机开启 USB 调试并连接电脑，PATH 里有 `adb`。
- `download-resource` 需要 python3；发音生成依赖 `edge-tts`（`pip install edge-tts`）。
  全部素材已随仓库提交，**克隆后无需执行**，只有新增贴图材质 / 新增单词补音频时才需要重跑。

## 地图编辑器与数据编辑器

`just edit-map`（或 `_tools\Godot_v4.4.1-stable_win64.exe --path . res://_tools/map_editor.tscn`）：

- **地图**：点选 / 拖动 / 旋转 / 复制 / 删除建筑，门窗随动，撤销重做，落点可达性判定，
  自动贴地与「自动放置」（就近找合法落点），保存自动备份 `planet.json.map-editor.bak`。
- **人物页**：从角色表添加 NPC 到地图并拖动摆放；**巡走路线画笔**——选中 NPC 后
  左键沿街点航点（Backspace 删末点、Esc 结束），模式可选**闭环**（回出生点循环）或
  **来回**（到终点原路折返），可调速度/停留时间，「试走」用游戏内同一控制器预览效果。
  还能配**出现时段**（朝/昼/夕/夜任意组合，全勾=一直出现），游戏内时段切换时自动显隐。
  路线与时段存进 `planet.json` 的 NPC 条目（`patrol` / `patrol_mode` / `patrol_speed` /
  `patrol_wait` / `appear_phase`），游戏里直接生效。
  还能维护角色表 `npcs.json`（新增 / 改名 / 换模型 / 调身高，删除前检查是否被地图引用）。
- **任务页**：可视化增删改 `quests.json`，支持收集 / 跑腿 / 对话 / 拍照 / 到达五类，
  自带校验（id 重复、giver / 分类 / kind 是否存在）。
- **对话页**：节点式编辑 `dialogues.json`——每 NPC 一个对话，台词（日文 + 中文）逐条播放，
  选项可跳节点或直达任务面板。
- 任务 / 对话 / 角色表保存各自带 `.editor.bak` 备份；改完重启游戏生效。

## AI 编辑接口（给 AI / 脚本的无头批处理）

> ⚠️ **给 AI 的硬约束**：地图 / 模型 / 材质等 3D 内容**禁止手撸**（手写坐标摆件、
> CSG/ArrayMesh 搓几何、绕过材质工厂手调参数），必须走下面的 ops 接口与
> ModelUtil / ToonKit / IslandMaterials 框架。规则与标准动作见
> **docs/3D_CONTENT_RULES.md**，动手前先读。

以上**全部编辑能力**（地图建筑增删挪转、自动放置、落点/可达性/密度判定、
NPC 添加摆放与巡走路线/出现时段、npcs.json 角色表、五种任务、NPC 对话）
都开放成了程序化接口：AI 写一份 JSON 操作清单，一条命令执行并回报逐条结果。

```
just ai-edit out/ops.json          # 或 python _tools/ai_edit.py out/ops.json
```

- 全部 op 一览：跑 `{"op":"query.ops"}`，或看 **docs/AI_EDITOR_API.md**（含参数表与示例）。
- 安全：启动只读；只有显式 `save` 才写文件（自动 `.bak` 备份 + 临时文件原子替换）；
  地图改动默认过 MapValidator 判据（贴地吸附、拒绝海里/悬空/互叠，`force:true` 才放行）。
- 自检：`_tools\Godot_v4.4.1-stable_win64_console.exe --headless --path . res://_tools/ai_editor.tscn -- --selftest`
  （用 out/ 副本闭环回归，不碰 data/）。

## 项目结构

```
project.godot            引擎配置（mobile 渲染器、横屏、触控）
justfile                 常用任务（安装 APK / 下载素材 / 清理）
data/
  words.json             ★ 词库：分类 + 单词（ja/kana/romaji/zh/category）
  places.json            ★ 地点注册表：每张地图 / 每个室内的 kind、标题、来源文件
  planet.json            ★ 星球地图（当前主地图）：物体种类与坐标（像素，1m = 40px）
  map.json               旧市街平面地图（历史遗留，street.gd 已不再加载）
  city_harbor.json       港区・市場地图（同上，历史遗留）
  city_hillside.json     丘の上・住宅街地图（同上，历史遗留）
  interiors.json         ★ 室内模板：尺寸/地板/隔墙/门洞/家具/灯光（坐标同为 px）
  quests.json            ★ 任务：收集 / 跑腿 / 对话 / 拍照 / 到达 五类
  dialogues.json         ★ NPC 对话：节点式台词 + 中文翻译 + 选项（可跳任务面板）
  npcs.json              ★ NPC：id → 模型文件 / 日文称呼 / 中文名 / 身高
scenes/                  6 个场景壳（UI 全部由脚本构建；星球与室内共用 street.tscn；
                         rashomon.tscn 为独立剧情章节）
scripts/
  chapter/
    rashomon.gd          ★ 剧情章节《罗生门·岭南篇》（含 --chapter-bot 全链路自测）
  globals/
    game_state.gd        自动加载 Game：词库、进度、收藏、复习记录、存档、程序生成音效
    places.gd            自动加载 Places：读取 places.json，按 id/kind 查地点
    quest_system.gd      自动加载 Quests：任务目录、进度判定、跑腿步进与航点
    dialogues.gd         自动加载 Dialogues：NPC 对话目录（data/dialogues.json）
    tts_manager.gd       自动加载 Tts：系统 TTS 封装（优先日语语音，朗读假名）
    ui_kit.gd            和风 UI 主题（和纸色 + 朱红）、字体加载（内嵌 Noto + 系统字体回退）
    toast.gd             顶部提示条
    shot_tool.gd         开发用自动截图工具（不影响正常游玩）
  planet/
    planet_math.gd       ★ 球面坐标：地图像素 ↔ (经度, 余纬) ↔ 世界方向向量
    planet_builder.gd    ★ 拼装星球本体（地形/水/树叶/云）+ 收集碰撞 + surface() 射线
  street/
    street.gd            主场景：按 place.kind 分「星球 / 室内」两支；小地图、HUD、拾取
    interactable.gd      ★ 全部物体的 3D 模型（程序化几何 + 外部 CC0 模型 + Label3D 招牌）
    interior_builder.gd  ★ 按 interiors.json 搭室内：地板/隔墙/门洞/天花/家具/点光
    interior_lighting.gd 室内环境预设（暖灰背景 + 无雾 + 顶光，适配 Mobile 渲染器）
    island_materials.gd  星球材质预设（地形/水/树叶/云/平面）
    player.gd            玩家（可跳的猫 + 弹簧臂相机 + 自动回正）
    procedural_textures.gd 程序纹理（柏油/砖/瓦/木/草）
    minimap.gd           小地图 + 地标 + 任务航点/路线（室内自动隐藏）
    quest_panel.gd / quest_tracker.gd  任务面板 / 左上追踪条
    dialogue_box.gd      NPC 对话框（底部弹窗：日文台词/中文/选项/朗读）
    npc_patrol.gd        NPC 巡航控制器（沿 planet.json patrol 路线绕街行走）
    gen_audio 脚本见 tools/
    virtual_joystick.gd  虚拟摇杆
    word_popup.gd        单词卡弹窗
  menus/                 主菜单 / 词汇库 / 复习 / 设置
assets/fonts/            Noto Sans JP/SC 子集（约 1.4MB）
tools/
  subset_fonts.py        字体子集化脚本
  scatter_planet.py      ★ 往 planet.json 撒新物件（就近播种 + batch 幂等）
  scatter_props.py       往 map.json 撒街景杂物（旧平面地图用）
  gen_city.py            生成平面城区地图（历史遗留）
  fetch_tex.py           下载 Poly Haven CC0 贴图（44 条目录）
  gen_audio.py           edge-tts 生成单词发音
_tools/                  开发工具（不进游戏包）
  curate_planet.tscn     ★ 星球落点整备：射线校验 + 自动搬迁，**撒完物件必跑**
  map_validate.tscn      ★ 地图合法性校验：落点分 + 处置建议 + NavMesh 连通性（只查不改）
  map_fix.tscn           地图修复：把互叠/摆进海里的物件就近挪到合法位（默认干跑，--apply 才写）
  make_planet_map.py     由 map.json 生成 planet.json（会覆盖整备结果，慎用）
  smoke_objects.tscn     无头冒烟测试：245 个物件逐个构建，验 META/视觉注册
```

## 如何新增单词 / 物体（给未来的批量扩展）

1. **加词条**：在 `data/words.json` 的 `words` 里加一条
   （`id, ja, kana, romaji, zh, category, audio`），category 取现有分类 id 或新增分类。
   同一载体想教多个词，就加 `variants`（见 `pole`/`car`/`onigiri`）：
   场景里第 N 个同 kind 实例会自动拿到第 N 个变体词（`_assign_variant_word` 取模轮转）。
2. **摆进场景**：在 `data/planet.json` 的 `objects` 里加一条
   `{ "word": "你的id", "kind": "已有模型种类", "x": 1200, "y": 900 }`
   —— 坐标是像素（岛冠展开图 5200×4000，1m = 40px），由 `PlanetMath` 解释为经纬度。
   **落点合法性由工具保证，不要手填**：见下面「撒物件的正确流程」。
3. **加新模型（可选）**：在 `scripts/street/interactable.gd` 里照抄一个 `_b_xxx()`
   构建函数并在 `META` 与 `_build_visual()` 注册，就能用新的外观。
   `META` 铁律：**可跳物件台面 ≤ 0.66m**（猫肩高 0.23m、跳高 0.66m）。
   独栋建筑还要在 `scripts/street/minimap.gd` 的 `LANDMARKS` 登记，否则小地图上没有菱形地标。
4. **重跑字体子集**（仅当新增了汉字）：`python tools/subset_fonts.py`。
   忘了也没关系，缺字会自动回退到系统字体，只是包体没优化。

### 撒物件的正确流程（星球地图必读）

岛屿地形烘焙在 GLB 里，**Python 侧看不到任何地面信息**，所以落点不能靠算，只能靠工具校验：

```bat
python tools\scatter_planet.py                          :: 1. 就近播种（幂等，按 batch 标记先清旧的）
_tools\Godot_v4.4.1-stable_win64_console.exe --headless --path . res://_tools/curate_planet.tscn
                                                           :: 2. 射线校验 + 自动搬迁（跑 2~3 轮收敛）
_tools\Godot_v4.4.1-stable_win64_console.exe --headless --path . res://_tools/map_validate.tscn
                                                           :: 3. 合法性校验（只查不改，出 out/map_validate.txt）
_tools\Godot_v4.4.1-stable_win64_console.exe --headless --path . res://_tools/smoke_objects.tscn
                                                           :: 4. 冒烟测试：每个物件都能构建出视觉
```

`curate_planet` 的判定：射线命中 / 海拔 ≥ water_radius+0.35m / 坡度 / 八方向足迹高差 /
邻域塌陷（防树干顶和崖边）/ 大件互斥。报告在 `out/curate_report.txt`。

`map_validate` 是**只读**的验收工具（不改数据），在 curate 之后跑，给每个物件打分并给处置建议
（`ACCEPT` / `MOVE` / `ROTATE` / `REJECT`），再加一项 curate 没有的检查：**NavMesh 连通性** ——
烘焙地形导航网格后，把每个大件的 footprint 从可行走面里扣掉，比较扣前/扣后发现
「哪些可走区域被建筑切断」并直接点名堵路的大件。产物 `out/map_validate.txt`；去掉 `--headless`
运行还会把需处理物件撒成彩球（黄=MOVE / 橙=ROTATE / 红=REJECT）并截图 `out/map_validate.png` ——
截图叠加了**坐标网格线 + 每格坐标 + 地标名坐标**（如 `super(3754,2848)`），读数与 `planet.json`
同一坐标系，报障时直接报 (x,y) 即可。

另外，**游戏里左上角常驻当前坐标读数**（`px (x, y)`，室内显示室内 px）——走到问题点，把那个
数字发出来就能精确定位，不用描述方位。

`map_fix` 是配套的**修复**工具：拿 map_validate 的同一套判据，只治「硬伤」（互叠 > 1m /
射线落空 / 摆进海里），优先原地换朝向、不行再逐圈外扩（≤ 6m），且每步改完重烘 NavMesh，
**主可行走区缩水 > 2% 就撤销该步**（避免「修好穿模却堵死路」）。坡度/占地不平属于作者的布局，
交给 curate_planet，本工具不越权。默认**干跑**只打印计划，加 `-- --apply` 才写回
`data/planet.json`（先备份 `data/planet.json.mapfix.bak`）：

```bat
_tools\Godot_v4.4.1-stable_win64_console.exe --headless --path . res://_tools/map_fix.tscn
                                                           :: 干跑：只打印「要动谁、动到哪、为什么」
_tools\Godot_v4.4.1-stable_win64_console.exe --headless --path . res://_tools/map_fix.tscn -- --apply
                                                           :: 落实：写回 planet.json（先备份）
```

> ⚠️ **绝不要重跑 `_tools/make_planet_map.py`** —— 它会用旧 `map.json` 重新生成 planet.json，
> 直接覆盖掉整备结果，45 个新物件全丢。正确顺序永远是：散布 → curate。

`tools/scatter_planet.py` 会自动避开任务绑定的 kind（`post_office`/`station`/`konbini`/
`ramen`/`cafe`/`parksign`/`sakura`/`counter`/`gate`）—— 跑腿任务按 kind 找它们，不能被挤掉。

### 加一张新地图 / 一个新室内

- **新星球地图**：复制一份 `data/planet.json`（保留 `planet` / `world` / `spawn` 三段），
  在 `data/places.json` 的 `places` 里加一条 `{"kind": "planet", "title_zh": "...", "map": "res://data/xxx.json"}`。
  注意地形 GLB 是硬编码在 `planet_builder.gd` 里的（`planets_present_full_0..9`），
  新星球要换模型得改 `PlanetBuilder._build_full_chunks()`。
- **新室内**：在 `data/interiors.json` 的 `templates` 里加一套模板
  （`size`/`ceil`/`floor`/`tiles`/`rooms`/`walls`(带 `door` 门洞)/`props`(按 zone 摆)/`lights`，坐标同为 px），
  在 `places.json` 里加 `{"kind": "interior", "template": "模板id", "parent": "所属 place id"}`；
  城里的门写 `"host": "建筑kind"`（走 street.gd 的 `INTERIOR_BY_HOST` 映射）或直接 `"interior": "室内place id"`。
  `props` 只写 `kind` 即可，`word` 缺省时自动用 kind 名去 `words.json` 找。
  注意：室内家具会自动做占位避让，**装饰件**（`META` 里 `solid: null`，如地毯/挂画/窗帘/空调/站名标）不占地面，可叠在其它家具上。

> **踩坑提醒**：新增带 `class_name` 的 `.gd` 文件后，跑游戏二进制前必须先
> `godot --headless --import --path .` 刷新全局类缓存，否则会报 "Identifier not declared"。

建筑附属词（门/窗）用 `"kind": "door"/"window"` 并写 `"host": "建筑kind"`，
会自动贴到该建筑的正面（可用 `dx` 左右偏移）。

## 常见问题

**发音相关的说明**
安卓/iOS 上发音全部使用随游戏打包的音频（`assets/audio/*.mp3`，由 `tools/gen_audio.py`
用微软神经语音 ja-JP-Nanami 生成），不依赖系统 TTS——部分国产 ROM 的 TTS 引擎
会让 Godot 崩溃，因此移动端已彻底绕开。新增单词后可重跑 `tools/gen_audio.py` 补音频；
桌面端缺失音频的词条会用系统 TTS 朗读。

**存档在哪？**
`Android/data` 应用目录下的 `savegame.json`（桌面端在 `%APPDATA%\Godot\app_userdata\日语街道\`）。
游戏内 设置 → 重置全部进度 可清空。

## 后续路线（MVP 之后）

- NPC 简单对话（便利店店员「いらっしゃいませ」+ 选项应答）
- 更细的室内任务（按房间/用途细分，如「在某户人家找到 5 件厨房用品」）
- 更多街区（东京/京都/北海道词汇包）、SRS 复习曲线、真人录音替换 TTS
- 车辆行人动效、更多室内房型与家具

## 素材来源

- 3D 表面贴图（柏油 / 铺装砖 / 瓷砖外墙 / 灰瓦 / 木板 / 草地 / 混凝土 / 砌块墙 /
  楼梯踏步 / 榻榻米 / 水磨石 / 室内瓷砖 / 竹编壁 / 杉木壁）来自
  [Poly Haven](https://polyhaven.com)，**CC0 公共领域**，可自由商用，无需署名
  （`tools/fetch_tex.py` 可重新下载，共 54 套 × col/nrm/rgh 三通道）。
  **表面一律用现成扫描贴图，不在运行时程序化生成图案** —— 楼梯、墙面、
  地面这类玩家每天看的面尤其如此。
- 部分道具模型来自 [Kenney](https://kenney.nl)（Furniture Kit / Food Kit / City Kit 等，**CC0**）
  与 [Poly Pizza](https://poly.pizza)：自行车、麻雀来自 Poly by Google（**CC-BY 4.0**，需署名）；
  燃气罐、消火栓为 CC0。
- 动物模型（Deer / Fox / Husky / Alpaca）来自 Quaternius Ultimate Animal Pack（**CC0**）。
- 发音音频由微软神经语音 ja-JP-Nanami 合成（tools/gen_audio.py）。

### ⚠️ 授权待确认：`assets/art/` 与 `art-assets/`

星球本体（`planets_present_full_0..9.glb` 等，38 个 glb）、19 个 NPC 模型、
以及 `art-assets/` 下的 193 个原始 GLSL shader，是从一款商业网页 3D 游戏
《BEGIN ANYWHERE》**提取**的。仓库内**没有 LICENSE 文件或署名说明**，
授权状态未经确认，且此前未在本节列出。

现状：`interactable.gd` 的 `_b_tree` / `_b_sakura` / `_b_bird` / `_b_npc` / `_b_delivery`
已在使用其中一部分（既有事实）。**批次 9 的扩充没有新增任何对该素材的引用** ——
新增载体全部用 Kenney / Quaternius / Poly Haven（CC0）。若要发布，
这部分需要先厘清授权或替换。

## 技术说明

- Godot 4.4，Mobile 渲染器，MSAA 4x；建筑与街道为运行时几何体拼装，
  道具优先使用外部 CC0/CC-BY 低模（`assets/models/`），包体可控且辨识度更高。
- 单词数据与场景数据完全数据驱动（JSON），UI 与玩法脚本解耦，便于批量扩充。
- 词卡 UI、菜单为和纸配色（#f7f3ea）+ 朱红（#c94f4f）的和风主题。
