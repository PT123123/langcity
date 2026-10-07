# 罗生门·岭南篇 —— MVP 竖切实现状态

> 规格来源：`docs/rashomon_game_chapter_spec_guangdong.md`（§27 MVP / §30 P0）。
> 本文档记录 2026-10-07 竖切已交付的内容与已知限制。

## 入口

- 主菜单 → **◆ 章节・罗生门 岭南篇**（`scenes/rashomon.tscn`，独立场景，不进星球地图管线）。

## 已实现（对照 P0 清单）

| P0 | 状态 | 实现 |
|---|---|---|
| 小型 3D 岭南古城场景 | ✅ | 官道 140m 线性地图：石城墙 + 门洞 + 城门楼（全程序化几何，复用 Poly Haven 贴图与 ToonKit 风格收口） |
| 玩家移动 | ✅ | 复用 `Player`（平地模式猫）+ 虚拟摇杆 + 拖屏转视角 |
| 拍照/识别物体 | ✅ | 章节内 golden-ring 高亮 + 快门 + `Game.discover`，词卡复用 `WordPopup` |
| 日语词汇卡 | ✅ | 23 个章节词条（8 个全新，15 个复用既有词条；全部有打包音频，`tools/gen_audio.py` 已补） |
| 林婆 NPC | ✅ | `ArtNpc`（oldwoman 模型 + npcs.json 目录），观察 4 目标后才触发相遇 |
| 对话 | ✅ | 复用 `DialogueBox` + `data/dialogues.json`（阿强/何伯/安生/林婆 ×2） |
| 楼梯探索 | ✅ | 20 级台阶 + 随机恐吓闪回（走到楼梯中段触发黑闪 + 文案） |
| 尸体环境 | ✅ | 楼上 3 具（程序化低模）+ 头发堆 + 衣物堆 + 火盆（缩放光源） |
| 抢衣服 QTE | ✅ | 摆动指针 + 金色判定带（复用拍照按钮/空格），首中 PERFECT |
| 黑暗结尾 | ✅ | 逐句黑屏文案（内容由问答成绩变化）→ 章节结算面板 → 返回主菜单 |

P1 交付：

- 饥饿压力条（顶部红色，随时间与地而结增；≥85 一次性提示「再这样下去会饿死」）。
- PERFECT/GREAT 统一反馈（大字居中 + 程序音效；首拍新词 = PERFECT）。
- 章节结算：新词汇 N/23 · 探索率 % · PERFECT 计数 · XP（`Game.add_xp`）。

## 明确不做（按规格 §15/§16）

- 无善恶值 UI；道德滑坡只体现在结尾文案与 XP。
- 不改原作核心结局；无任务链/装备/战斗系统。

## 已知限制 / 后续

- 「何伯巡走」「陈捕头潜行」未实现（原规格里均为可选）。
- 对话小游戏只实现了模式 A（听关键词）；模式 B 句子重组 / 模式 C 补全待后续。
- 章节内进度不做断点续玩（重进从头开始；学到的词已入正篇存档）。
- 独立场景不受 Pre curate/validate 工具管辖（无 planet.json 参与），布局直接代码内给定。

## 自测命令

```bat
:: 全链路 bot（自动通关、干跑不写存档）：
_tools\Godot_v4.4.1-stable_win64_console.exe --headless --path . res://scenes/rashomon.tscn -- --chapter-bot

:: 开发截图机位（street|gate|stairs|top|upstairs|fire，配 ShotTool）：
_tools\Godot_v4.4.1-stable_win64.exe --path . -- --shot=out/rm_fire.png --shot-frames=60 --shot-scene=res://scenes/rashomon.tscn --chapter-pose=fire

:: 章节数据落地（幂等）：
python _tools\rashomon_chapter_data.py
```

## 顺手修复的正篇 bug

- `scripts/street/dialogue_box.gd`：`open_for()` 未复位 `_line_idx` ——
  上一个对话播到中途再开新对话时，新对话会直接跳过台词（数据驱动对话的通用 bug），已复位。
