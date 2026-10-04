extends Node
## 自动加载：Quests —— 任务目录、进度判定、跑腿步进与航点计算。
## 数据全部来自 res://data/quests.json：
##   type=collect 收集类：在街区里发现 N 个某分类的单词（进度 = 该分类已发现数）
##   type=errand  跑腿类：按顺序走到目标地点（目标按 kind/word 从当前场景查位置）
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
	return ""


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
	return String(q.get("desc", ""))


## 追踪目标的场景世界坐标（收集类没有航点，返回 null）
func tracked_waypoint() -> Variant:
	var q := tracked_quest()
	if q.is_empty() or String(q.get("type", "")) != "errand":
		return null
	var steps: Array = q.get("steps", [])
	var step := errand_step(q)
	if step >= steps.size():
		return null
	return _step_target(String(q.get("id", "")), step, steps[step])


# ---------------- 每帧：跑腿到达判定 ----------------

## 由 street 每物理帧调用，传入玩家世界坐标。
## 检查所有进行中的跑腿任务（不只追踪中的），走到目标半径内就推进到下一步。
func tick(player_pos: Vector3) -> void:
	var changed := false
	for id in _order:
		if not is_active(id):
			continue
		var q: Dictionary = _quests[id]
		if String(q.get("type", "")) != "errand":
			continue
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
	if changed:
		tracking_changed.emit()


## 用 kind（或 word）在当前场景里找第一步目标的位置；静态目标结果缓存
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
	return null


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