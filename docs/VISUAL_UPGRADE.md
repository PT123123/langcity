# 视觉升级文档（批次 1–3）

> 对应规格：《把「日语街道」从「技术 demo 感」改造成「治愈系日式街景」》
> 本轮完成**批次 1（后处理与调色）**、**批次 2（时间系统与灯光布局）**、**批次 3（材质程序化）**。
> 批次 4–7（拍照玩法升级 / 微动空气感 / 工具链 / 新增资产）未做。

---

## 一、改造前后对比

| 时刻 | 截图 | 关键变化 |
|---|---|---|
| 朝 6:30 | `vu_morning.png` | 暖橙低角度光（-16°），长影，薄雾 |
| 昼 12:30 | `vu_day.png` | 冷白高角度光（-58°），短影，饱和度高 |
| 夕 18:00 | `vu_dusk.png` | ★默认。天空橙→紫渐变，长影，橱窗暖光，Bloom 溢光 |
| 夜 21:30 | `vu_night.png` | 月光蓝，窗户/招牌自发光被 Bloom 捕获 |
| 街道 · 夕 | `vu_shop_dusk.png` | 自动贩卖机亮灯箱、材质分区、Verge 收边 |
| 车站 · 夕 | `vu_station_dusk.png` | 抹灰墙 + 沥青 + 树皮的材质区分 |

改造前的问题（对照记忆里上一轮的截图）：
1. 全场景 `TONE_MAPPER_FILMIC` + 冷蓝雾 + 低饱和 → 惨白、无颜色
2. 所有物体共用同一种 `StandardMaterial3D` → 满屏塑料反光
3. 没有点光源 → 夜里纯黑、没有街道感
4. 无 Vignette / Bloom 阈值控制 → 画面平、无胶片感

---

## 二、Godot 4.4 与规格的差异（重要）

规格里的部分 API **在 Godot 4.4 上不存在**，实现时做了替代。这是本轮最值得记录的部分。

| 规格写法 | Godot 4.4 实测 | 本项目采用 |
|---|---|---|
| `env.vignette_*` | **不存在**（4.3+ 把后处理从 Environment 拆走） | 自建 `assets/shaders/grade.gdshader`，全屏 CanvasLayer + `hint_screen_texture` |
| `env.chromatic_*` | 不存在 | 同上（shader 内实现，仅边缘生效） |
| `env.auto_exposure_*` | 不存在 | 手动插值 `tonemap_exposure` |
| ColorLUT | 无「生成 LUT」便利接口 | 用 `env.adjustment_color_correction`（挂 Texture 的入口） |
| `SHADOW_PARALLEL_1_SPLIT` | **不存在**（只有 2/4 级联） | 低端用 2 级联 + 缩短 `shadow_max_distance` |
| `OS.get_video_adapter_memory()` | **不存在** | `OS.get_static_memory_peak_usage()` + GPU 名称 SoC 判断 |
| `BaseMaterial3D.DETAIL_BLEND_MIX` | 枚举搬到 `StandardMaterial3D` | `StandardMaterial3D.BLEND_MODE_MIX` / `DETAIL_UV_1` |
| `tonemap_exposure_white` | 实际叫 `tonemap_white` | `tonemap_white` |
| `env.adjustment_exposure` | 不存在 | `tonemap_exposure` |

**结论**：规格里的后处理栈需要按 4.4 重写。官方文档网页（docs.godotengine.org）仍写 BaseMaterial3D，
不可信——用 `ClassDB.class_get_integer_constant_list()` / `get_property_list()` 反射验证。

---

## 三、文件清单

### 新增
| 文件 | 批次 | 说明 |
|---|---|---|
| `scripts/street/graphics_tier.gd` | 1 | 画质三档（LOW/MEDIUM/HIGH）+ 机型嗅探 + Environment 应用 |
| `scripts/street/time_of_day.gd` | 2 | 四时刻系统，15 秒 Tween 插值，驱动全部光影 |
| `assets/shaders/grade.gdshader` | 1 | Vignette + 色差 + 胶片颗粒（Environment 没有的那部分） |
| `docs/VISUAL_UPGRADE.md` | — | 本文档 |

### 修改
| 文件 | 改动 |
|---|---|
| `scripts/street/street.gd` | `_setup_environment` 重写；新增 `_setup_grade`（调色层）、`_register_street_lights`（点光布局）、`_budget_omni`、`apply_tier`、`apply_time_phase`；`_run_debug_hooks` 加 `demo_tod_*` 四时刻调试动作 |
| `scripts/street/interactable.gd` | 新增 20 个材质工厂（见下）；`cyl/sph/torus` 加 material 参数；`_window_unit` 改为夜间自发光；贩卖机/邮筒/垃圾桶/自行车/信号灯/路灯/树/樱花/公交站/电线杆上材质 |
| `scripts/globals/game_state.gd` | 新增 `apply_graphics_tier()` / `set_time_phase()` / `current_tier()`；settings 加 `gfx_tier` / `time_phase` / `reduce_flicker` |
| `scripts/menus/settings_menu.gd` | 新增「画质」「时刻」两个下拉 + 「降低闪烁」开关；**顺带修复了一个原有 bug：ScrollContainer 未撑开导致整页空白** |

---

## 四、画质三档

设置页可手动覆盖，默认按机型嗅探（`GraphicsTier.detect()`）。

| 档 | Bloom | SSAO | 体积雾 | 阴影 | 点光上限 | 色差/颗粒 |
|---|---|---|---|---|---|---|
| 高（旗舰/桌面） | Softlight 0.55 | 开 r0.5 i1.6 | 开 density 0.008 | 4 级联 70m | 6 | 开 |
| **中（默认）** | Softlight 0.5 | 开 r0.4 i1.2 | 开 density 0.005 | 2 级联 60m | 3 | 开 |
| 低（省电/旧机） | Additive 0.42 | 关 | 关 | 2 级联 45m | 1 | 关 |

**共同项**：Tonemap = ACES、saturation 1.2、contrast 1.12、Vignette 0.3（深棕非纯黑）、
颗粒 0.02、**SSR 全档关闭**（规格红线：移动端掉 15–25fps）。

**降级顺序**（`GraphicsTier.DEGRADE_ORDER`，供后续 performance_budget 用）：
体积雾 → SSAO → Bloom → 粒子 → 阴影。

**注意**：中档也保留了 SSAO。规格表把中档标为「Low」，但屋檐下/电柱根/贩卖机底的
接触阴影是廉价感重灾区，砍掉不划算——这点实测后决定偏离规格表。

---

## 五、四时刻参数

| | 朝 | 昼 | 夕★ | 夜 |
|---|---|---|---|---|
| 太阳角度 | -16° | -58° | **-13°** | -40° |
| 太阳能量 | 0.95 | 1.35 | **1.5** | 0.45（月光） |
| 太阳色 | 暖橙 | 冷白 | **暖橙** | 月光蓝 |
| 环境光 | 0.28 | 0.34 | **0.42** | 0.5 |
| 曝光偏置 | -0.1 | 0.0 | **0.0** | +0.15 |
| Bloom 阈值 | 0.82 | 0.9 | **0.72** | 0.5 |
| 暖点光 | 0.5 | 0.0 | **0.85** | 1.0 |
| 自发光 | 0.25 | 0.0 | **0.85** | 1.0 |
| 雾色 | 暖米 | 冷白 | **橙褐** | 深蓝紫 |

**踩坑：夜景不能用「低能量 + 负曝光」**。第一版夜景给了 `sun_energy 0.14` +
`exposure_bias -0.45`，结果整个画面糊成黑块，什么都看不见。
夜景的正确做法是：月光弱但**有方向**、ambient 提上来保证轮廓可读、
靠人工点光和自发光做明暗层次。黄昏同理——`exposure_bias -0.25` 太压，改成 0.0。

---

## 六、材质工厂（批次 3）

`Interactable` 新增 20 个材质语义工厂。**核心不是加细节，是把 roughness 与 metallic 拉开档**：

| 语义 | 工厂 | rough | metal | 用途 |
|---|---|---|---|---|
| 朱红塑料 | `m_plastic_red` | 0.35 | 0.10 | 自动贩卖机机身 |
| 白塑料 | `m_plastic_white` | 0.40 | 0.0 | 贩卖机面板 / 窗框 |
| 深色金属 | `m_metal_dark` | 0.42 | **0.85** | 电柱 / 护栏 / 管道 |
| 镀锌铁皮 | `m_metal_galva` | 0.55 | **0.75** | 空调外机 / 垃圾桶 / 挡泥板 |
| 混凝土 | `m_concrete` | 0.88 | 0.0 | 外墙 / 台阶 / 窗台 |
| 瓦 | `m_tile_roof` | 0.68 | 0.05 | 屋顶 |
| 木材 | `m_wood` | 0.76 | 0.0 | 招牌框 / 长椅 |
| 玻璃 | `m_glass` | 0.06 | 0.30 | 窗户（夜晚自发光） |
| 橡胶 | `m_rubber` | 0.92 | 0.0 | 轮胎 / 取物口 / 盲道 |
| 叶片 | `m_leaf` | 0.82 | 0.0 | 树冠（微 emission 模拟透光） |
| 樱花瓣 | `m_petal` | 0.90 | 0.0 | 落樱（双面） |
| 和纸 | `m_paper` | 0.95 | 0.0 | 灯笼 / 暖帘 |
| 铺装 | `m_paving` | 0.80 | 0.0 | 人行道砖 |
| 霓虹 | `m_neon` | UNSHADED | — | 招牌发光字，energy 4.0 |
| 亮面 | `m_glow` | UNSHADED | — | 灯箱 / 车窗 / 信号灯 |
| 朱红点缀 | `m_vermilion` | 0.45 | 0.05 | 邮筒 / 自行车 / 消火栓 |
| 沥青 | `m_asphalt` | 0.95 | 0.0 | 路面 |
| 白漆 | `m_paint_white` | 0.75 | 0.0 | 斑马线 |
| 冷金属 | `m_metal_cool` | 0.50 | 0.60 | 信号灯杆 / 护栏 |
| 深叶 | `m_foliage` | 0.88 | 0.0 | 灌木 / 深色树冠 |

### 关键技巧：材质微差（`_mat_j` / `_jitter_color`）

规格要求「同一材质、每块颜色微差」。实现方式：按**世界坐标哈希**生成缓存 key，
让每块砖/每扇窗/每棵树冠都拿到独立的材质实例，明度抖动 ±5.5% + 轻微色相偏移。

**为什么重要**：消除「同一个紫出现 200 次」的塑料感。面数代价换无塑料感，比加面数划算。

### Bloom 铁律
`emission_energy_multiplier` 必须 **> 1** 才会被 Bloom 捕获。信号灯 3.0、路灯 3.2、
贩卖机灯箱 2.6、霓虹 4.0。低于 1 就只是块白板。

---

## 七、已知限制（明确写做不到什么）

- **无实时反射（SSR/ReflectionProbe）**：规格明确禁止（移动端掉 15–25fps）。
  湿路面的「倒影感」本轮未实现，规格里提的「假高光 + 法线扰动」三层方案需要另开批次。
- **无体积光轴（god rays）**：Godot 4.4 的 `volumetric_fog` 只有均匀雾，没有径向光轴。
- **无 LightmapGI 烘焙**：静态间接光仍是运行时环境光近似，没有真正的烘焙 GI。
- **无 ColorLUT 文件**：四时刻的调色目前是直接改 Environment 参数，
  没有生成 64³ LUT 贴图（那属于批次 6 的 `gen_lut.py`）。
- **点光数量受档位限制**：中档只允许 3 盏 omni 参与光照，所以「整条街都是暖光」
  做不到，只能在物体自发光上做文章。**这是移动端的硬约束，不是偷懒。**
- **无实时阴影在小物件上**：规格要求电柱/邮筒/贩卖机/垃圾桶用 Blob Shadow
  （贴地圆片），本轮未做——它们目前不投实时阴影，也**没有补 Blob Shadow**，
  所以夜里这些物体会显得「浮在地面」。这是当前最明显的遗留问题。
- **窗外的 emission 调制依赖全表扫描**：`TimeOfDay.scan_emissives()` 遍历场景所有
  `MeshInstance3D` 收集自发光材质。场景规模再大（比如批次 7 加 60+ 物体）时
  启动会变慢，需要改成按需注册。
- **无公开同场景跨引擎基准测试数据**：本轮未在真机（骁龙 7 系）验证帧率。
  所有帧率相关判断均为设计推演，**不是实测**。

---

## 八、验证清单

- [x] 7 个 demo 场景 0 error（park / station / shop / cross / sign / cat_walk / popup）
- [x] 4 时刻瞬时切换无报错
- [x] 设置页画质/时刻切换生效
- [ ] **真机（骁龙 7 系）连续走 5 分钟 fps ≥ 55 —— 未做（无真机）**
- [ ] 4 时刻 15 秒过渡动画无跳变 —— 只验证了瞬时切换，过渡动画未实机观看
- [ ] 拍照快门 10 连拍 —— 本轮未改拍照逻辑
- [ ] 词汇库条目 ≥ 60 —— 当前 39（批次 7 范围）
- [x] 包体增量：本轮新增代码 + 1 个 shader，无新贴图
- [x] 杀进程重开进度恢复（本轮未改存档结构，仅新增 settings 键，兼容旧存档）
