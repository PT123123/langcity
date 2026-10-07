extends Node
## 自动加载：Quests —— 任务目录、进度判定、跑腿步进与航点计算。
## 数据全部来自 res://data/quests.json：
##   type=collect 收集类：在街区里发现 N 个某分类的单词（进度 = 该分类已发现数）
##   type=errand  跑腿类：按顺序走到目标地点（目标按 kind/word 从当前场景查位置）
##   type=talk    对话类：和指定 NPC（target=npc id）搭上话即完成（street 在点开对话时上报）
##   type=photo   拍照类：拍到指定 kind/word 的物件即完成（street 在快门成功时上报）
##   type=visit   到达类：走到指定 kind 的目标半径内即完成（逻辑 = 单步跑腿）
## 每个任务可带 "giver"（发布者 NPC 的 id，角色表在 data/npcs.json）：
##   点击街上的 NPC 时，任务面板据此把 TA 的委托排前并高亮。
## 任务的持久化状态存在 Game.quest_state，本单例只负责「逻辑」。

signal tracking_changed        ## 追踪目标或跑腿步进变化 → HUD / 小地图刷新
signal quest_completed(id: String)

const QUESTS_PATH := "res://data/quests.json"

var _quests := {}    # id -> 任务 Dictionary
var _order: Array = []   # 保持文件顺序的 id
var _target_cache := {}  # "quest_id/step" -> Vector3，静态目标缓存，避免每帧遍历场景


func _ready() -> void:
	_load()
	Game.word_discovered.connect(_on_word_discovered)


func _load() -> void:
	var f := FileAccess.open(QUESTS_PATH, FileAccess.READ)
	if f == null:
		push_error("无法读取任务文件 " + QUESTS_PATH)
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("任务文件格式错误")
		return
	for q: Dictionary in data.get("quests", []):
		_quests[q["id"]] = q
		_order.append(q["id"])


# ---------------- 目录与状态查询 ----------------

func catalog() -> Array:
	var out: Array = []
	for id in _order:
		out.append(_quests[id])
	return out


func quest(id: String) -> Dictionary:
	return _quests.get(id, {})


## 任务发布者的 NPC id。旧数据没配 giver 也照常返回空串 —— NPC 接入是渐进的，不能因此崩
func giver_of(quest: Dictionary) -> String:
	return String(quest.get("giver", ""))


## 某 NPC 发布的全部任务，保持目录顺序（任务面板把该 NPC 的委托排前时用）
func quests_by_giver(npc_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in _order:
		var q: Dictionary = _quests[id]
		if giver_of(q) == npc_id:
			out.append(q)
	return out


func is_active(id: String) -> bool:
	return String(Game.quest_state.get(id, {}).get("status", "")) == "active"


func is_done(id: String) -> bool:
	return String(Game.quest_state.get(id, {}).get("status", "")) == "done"


func is_locked(id: String) -> bool:
	return not Game.quest_state.has(id)


func active_count() -> int:
	var n := 0
	for id in _order:
		if is_active(id):
			n += 1
	return n


## 收集类进度：该分类已发现单词数（上限 = 任务要求数）
func collect_progress(q: Dictionary) -> int:
	var cat := String(q.get("category", ""))
	var n := 0
	for wid in Game.category_word_ids(cat):
		if Game.is_discovered(wid):
			n += 1
	return mini(n, int(q.get("count", 0)))


## 跑腿类当前步号（从 0 开始）
func errand_step(q: Dictionary) -> int:
	return int(Game.quest_state.get(String(q.get("id", "")), {}).get("step", 0))


## 卡片上显示的进度短句
func status_text(q: Dictionary) -> String:
	var id := String(q.get("id", ""))
	if is_done(id):
		return "已完成"
	var active := is_active(id)
	match String(q.get("type", "")):
		"collect":
			var need := int(q.get("count", 0))
			if active:
				return "进行中 %d / %d" % [collect_progress(q), need]
			return "需找到 %d 个" % need
		"errand":
			var steps: Array = q.get("steps", [])
			if active:
				return "进行中 第 %d / %d 步" % [errand_step(q) + 1, steps.size()]
			return "共 %d 步" % steps.size()
		"talk":
			if active:
				return "去和 %s 聊聊" % npc_name(String(q.get("target", "")))
			return "未接取"
		"photo":
			return "快门拍下目标" if active else "未接取"
		"visit":
			return "走到目标地点" if active else "未接取"
	return ""


## npc id → 显示名（读 data/npcs.json；缺条目回退 id。缓存一次）。
func npc_name(npc_id: String) -> String:
	if _npc_names.is_empty() and not _npc_names_tried:
		_npc_names_tried = true
		var f := FileAccess.open("res://data/npcs.json", FileAccess.READ)
		if f != null:
			var v: Variant = JSON.parse_string(f.get_as_text())
			if v is Dictionary and (v as Dictionary).get("npcs") is Dictionary:
				for k: String in (v as Dictionary)["npcs"]:
					_npc_names[k] = String((v as Dictionary)["npcs"][k].get("name", k))
	return String(_npc_names.get(npc_id, npc_id))
var _npc_names := {}
var _npc_names_tried := false


# ---------------- 接取 / 追踪 ----------------

func accept(id: String) -> bool:
	if not _quests.has(id) or Game.quest_state.has(id):
		return false
	Game.quest_state[id] = {"status": "active", "step": 0}
	Game.quest_tracked = id        # 接取即追踪，HUD 立刻给出指引
	Game.save_soon()
	# 收集类可能接取时就已达成（之前已经找够了）
	if String(_quests[id].get("type", "")) == "collect":
		_check_collect(id)
	tracking_changed.emit()
	return true


func track(id: String) -> void:
	if not is_active(id):
		return
	Game.quest_tracked = id
	Game.save_soon()
	tracking_changed.emit()


func tracked_id() -> String:
	return Game.quest_tracked if is_active(Game.quest_tracked) else ""


func tracked_quest() -> Dictionary:
	var id := tracked_id()
	return _quests.get(id, {}) if not id.is_empty() else {}


## HUD 追踪条上的一行目标文字（含进度）
func objective_text() -> String:
	var q := tracked_quest()
	if q.is_empty():
		return ""
	match String(q.get("type", "")):
		"collect":
			return "%s   %d / %d" % [String(q.get("desc", "")), collect_progress(q), int(q.get("count", 0))]
		"errand":
			var steps: Array = q.get("steps", [])
			var step := errand_step(q)
			if step < steps.size():
				return "%s   (%d/%d)" % [String(steps[step].get("text", "")), step + 1, steps.size()]
		"talk":
			return "和 %s 说说话" % npc_name(String(q.get("target", "")))
		"photo":
			return String(q.get("desc", "拍下目标物件"))
		"visit":
			return String(q.get("desc", "走到目标地点"))
	return String(q.get("desc", ""))


## 追踪目标的场景世界坐标。
## 跑腿类 = 当前步的目标点；收集类 = 最近的「未发现」目标物体位置（给 HUD 指路）；
## talk = 目标 NPC 所在位置；photo/visit = 目标 kind 物件位置。
func tracked_waypoint(player_pos: Vector3) -> Variant:
	var q := tracked_quest()
	if q.is_empty():
		return null
	match String(q.get("type", "")):
		"collect":
			var t: Variant = collect_target(player_pos)
			return t.position if t != null else null
		"errand":
			var steps: Array = q.get("steps", [])
			var step := errand_step(q)
			if step >= steps.size():
				return null
			return _step_target(String(q.get("id", "")), step, steps[step])
		"talk":
			return _scene_pos_of_npc(String(q.get("target", "")))
		"photo", "visit":
			return _scene_pos_of_kind(String(q.get("kind", "")))
	return null


## 在当前场景里按 kind 找物件位置（不缓存：photo/visit 目标少，调用频率低）
func _scene_pos_of_kind(kind: String) -> Variant:
	if kind.is_empty():
		return null
	var street := get_tree().current_scene
	if street == null:
		return null
	var objs: Variant = street.get("objects")
	if objs == null:
		return null
	for it in objs:
		if it == null or not is_instance_valid(it):
			continue
		if it.kind == kind:
			return it.position
	return null


## 在当前场景里按 npc id 找 NPC 位置
func _scene_pos_of_npc(npc_id: String) -> Variant:
	if npc_id.is_empty():
		return null
	var street := get_tree().current_scene
	if street == null:
		return null
	var objs: Variant = street.get("objects")
	if objs == null:
		return null
	for it in objs:
		if it == null or not is_instance_valid(it) or it.kind != "npc":
			continue
		if String(it.extra.get("npc", "")) == npc_id:
			return it.position
	return null


## 收集类当前应指路的目标：距玩家最近、属于该分类且尚未发现的物体。
## 包含隐形标记（如「交差点」的 marker_cross），否则最后几个永远找不到。
## 非收集类任务、或该分类已全部发现时返回 null。
func collect_target(player_pos: Vector3) -> Variant:
	var q := tracked_quest()
	if q.is_empty() or String(q.get("type", "")) != "collect":
		return null
	var cat := String(q.get("category", ""))
	var street := get_tree().current_scene
	if street == null:
		return null
	var objs: Variant = street.get("objects")
	if objs == null:
		return null
	var best: Variant = null
	var best_d := INF
	for it in objs:
		if it == null or not is_instance_valid(it):
			continue
		var wid := String(it.word_id)
		if wid.is_empty() or Game.is_discovered(wid):
			continue
		if String(Game.word(wid).get("category", "")) != cat:
			continue
		var d: float = player_pos.distance_to(it.position)
		if d < best_d:
			best_d = d
			best = it
	return best


## 供场景取「当前收集目标物体」画光圈用：仅收集类任务返回 Interactable，其余 null
func tracked_target_object(player_pos: Vector3) -> Variant:
	return collect_target(player_pos)


# ---------------- 每帧：跑腿到达判定 ----------------

## 由 street 每物理帧调用，传入玩家世界坐标。
## 检查所有进行中的跑腿/到达任务（不只追踪中的），走到目标半径内就推进/完成。
func tick(player_pos: Vector3) -> void:
	var changed := false
	for id in _order:
		if not is_active(id):
			continue
		var q: Dictionary = _quests[id]
		match String(q.get("type", "")):
			"errand":
				var steps: Array = q.get("steps", [])
				var step := int(Game.quest_state[id].get("step", 0))
				if step >= steps.size():
					continue
				var target: Variant = _step_target(id, step, steps[step])
				if target == null:
					continue
				if player_pos.distance_to(target) <= float(steps[step].get("radius", 8.0)):
					Game.quest_state[id]["step"] = step + 1
					Game.save_soon()
					changed = true
					if step + 1 >= steps.size():
						_finish(id)
			"visit":
				var target2: Variant = _scene_pos_of_kind(String(q.get("kind", "")))
				if target2 != null \
						and player_pos.distance_to(target2) <= float(q.get("radius", 8.0)):
					_finish(id)
					changed = true
	if changed:
		tracking_changed.emit()


## street 在点开 NPC（对话/任务面板）时上报：对话类任务就此完成。
func notify_talk(npc_id: String) -> void:
	if npc_id.is_empty():
		return
	for id in _order:
		if is_active(id) and String(_quests[id].get("type", "")) == "talk" \
				and String(_quests[id].get("target", "")) == npc_id:
			_finish(id)


## street 在快门成功时上报：拍照类任务按 kind/word 匹配完成。
func notify_photo(kind: String, word_id: String) -> void:
	for id in _order:
		if not is_active(id) or String(_quests[id].get("type", "")) != "photo":
			continue
		var want_kind := String(_quests[id].get("kind", ""))
		var want_word := String(_quests[id].get("word", ""))
		if (not want_kind.is_empty() and kind == want_kind) \
				or (not want_word.is_empty() and word_id == want_word):
			_finish(id)


## 用 kind（或 word）在当前场景里找第一步目标的位置；静态目标结果缓存。
## 当前图没有该 kind 时（跨图跑腿），改用 Places 反查该 kind 在哪张城，
## 再指到本图里通往那张城的 portal —— 航点永远指「当前该走的传送点」，不指旧城坐标。
func _step_target(qid: String, step: int, s: Dictionary) -> Variant:
	var key := "%s/%d" % [qid, step]
	if _target_cache.has(key):
		return _target_cache[key]
	var want_kind := String(s.get("kind", ""))
	var want_word := String(s.get("word", ""))
	var street := get_tree().current_scene
	if street == null:
		return null
	var objs: Variant = street.get("objects")
	if objs == null:
		return null
	for it in objs:
		if it == null or not is_instance_valid(it):
			continue
		if (not want_kind.is_empty() and it.kind == want_kind) \
				or (not want_word.is_empty() and it.word_id == want_word):
			_target_cache[key] = it.position
			return it.position
	var portal: Variant = _portal_toward(want_kind, objs)
	if portal != null:
		_target_cache[key] = portal
		return portal
	return null


## 目标 kind 在别城时，返回本图里应走的 portal 世界坐标：
## 优先直达（portal.to_map == 目标所在城）；否则中转到枢纽（默认城）。
## 目标就在本城、或本城根本没有该 kind 的登记，返回 null。
func _portal_toward(want_kind: String, objs: Variant) -> Variant:
	if want_kind.is_empty():
		return null
	var hosts := Places.kind_index(want_kind)
	var current: String = Game.current_place_id
	if hosts.is_empty() or hosts.has(current):
		return null
	for it in objs:
		if it == null or not is_instance_valid(it) or it.kind != "portal":
			continue
		if hosts.has(String(it.extra.get("to_map", ""))):
			return it.position
	var hub := Places.default_id()
	if not hosts.has(hub):
		for it in objs:
			if it == null or not is_instance_valid(it) or it.kind != "portal":
				continue
			if String(it.extra.get("to_map", "")) == hub:
				return it.position
	return null


## 场景切换后清空目标缓存：里面存的是上一张图的世界坐标，跨图必须失效
func clear_target_cache() -> void:
	_target_cache = {}


# ---------------- 内部：完成判定 ----------------

func _on_word_discovered(_word_id: String) -> void:
	for id in _order:
		if is_active(id) and String(_quests[id].get("type", "")) == "collect":
			_check_collect(id)
	if not tracked_quest().is_empty():
		tracking_changed.emit()


func _check_collect(id: String) -> void:
	var q: Dictionary = _quests.get(id, {})
	if q.is_empty() or not is_active(id):
		return
	if collect_progress(q) >= int(q.get("count", 0)):
		_finish(id)


func _finish(id: String) -> void:
	if not Game.quest_state.has(id):
		return
	Game.quest_state[id]["status"] = "done"
	if Game.quest_tracked == id:
		Game.quest_tracked = ""
	var q: Dictionary = _quests.get(id, {})
	Game.add_xp(int(q.get("xp", 0)))
	Game.save_now()
	Game.play_sfx("correct")
	quest_completed.emit(id)
	tracking_changed.emit()