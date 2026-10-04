extends Node
## 自动加载：Game —— 词库数据、学习进度、收藏、复习记录、设置与本地存档。

signal word_discovered(id: String)
signal favorites_changed

const SAVE_PATH := "user://savegame.json"
const WORDS_PATH := "res://data/words.json"

var words := {}             # id -> 词条 Dictionary
var word_order: Array = []  # 保持文件顺序的 id 列表
var categories: Array = []  # [{id, name, color}]
var _cat_index := {}        # id -> 分类 Dictionary

var discovered := {}        # id -> 发现时间(unix 秒)
var favorites := {}         # id -> true
var review_stats := {}      # id -> {"c": 对, "w": 错, "last": 时间}
var last_position := Vector2.ZERO
var has_last_position := false

var settings := {
	"auto_speak": true,     # 发现新词自动发音
	"show_romaji": true,    # 弹窗显示罗马音
	"volume": 0.8,          # TTS 音量 0..1
	"pitch": 1.0,           # TTS 音调
	"tutorial_done": false, # 是否看过街道引导
}

var _save_timer: SceneTreeTimer = null
var _sfx_cache := {}
var _sfx_player: AudioStreamPlayer


func _ready() -> void:
	_load_words()
	# 自动化截图/演示模式：--demo 预置一部分学习进度
	if OS.get_cmdline_user_args().has("--demo"):
		_seed_demo()
	_load_save()
	UiKit.click_cb = play_sfx.bind("click")
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.volume_db = -8.0
	add_child(_sfx_player)


func _load_words() -> void:
	var f := FileAccess.open(WORDS_PATH, FileAccess.READ)
	if f == null:
		push_error("无法读取词库文件 " + WORDS_PATH)
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("词库文件格式错误")
		return
	for c: Dictionary in data.get("categories", []):
		categories.append(c)
		_cat_index[c["id"]] = c
	for w: Dictionary in data.get("words", []):
		words[w["id"]] = w
		word_order.append(w["id"])


# ---------------- 查询 ----------------

func word(id: String) -> Dictionary:
	return words.get(id, {})


func total_words() -> int:
	return word_order.size()


func discovered_count() -> int:
	return discovered.size()


func is_discovered(id: String) -> bool:
	return discovered.has(id)


func is_favorite(id: String) -> bool:
	return favorites.has(id)


func category_name(cat_id: String) -> String:
	return _cat_index[cat_id]["name"] if _cat_index.has(cat_id) else cat_id


func category_color(cat_id: String) -> Color:
	return Color(_cat_index[cat_id]["color"]) if _cat_index.has(cat_id) else Color.GRAY


func category_word_ids(cat_id: String) -> Array:
	var out: Array = []
	for id in word_order:
		if words[id]["category"] == cat_id:
			out.append(id)
	return out


func categories_in_order() -> Array:
	# 按词库文件中分类的定义顺序返回
	return categories


# ---------------- 进度变更 ----------------

## 返回是否为首次发现
func discover(id: String) -> bool:
	if is_discovered(id) or not words.has(id):
		return false
	discovered[id] = int(Time.get_unix_time_from_system())
	save_soon()
	word_discovered.emit(id)
	return true


func toggle_favorite(id: String) -> bool:
	if favorites.has(id):
		favorites.erase(id)
	else:
		favorites[id] = true
	save_soon()
	favorites_changed.emit()
	return favorites.has(id)


func record_review(id: String, correct: bool) -> void:
	var s: Dictionary = review_stats.get(id, {"c": 0, "w": 0, "last": 0})
	if correct:
		s["c"] = int(s.get("c", 0)) + 1
	else:
		s["w"] = int(s.get("w", 0)) + 1
	s["last"] = int(Time.get_unix_time_from_system())
	review_stats[id] = s
	save_soon()


## 按学习优先级排出一批复习用词：错得多、久未复习的优先
func review_candidates() -> Array:
	var pool: Array = []
	for id in discovered.keys():
		var s: Dictionary = review_stats.get(id, {})
		var weight := int(s.get("w", 0)) * 2 - int(s.get("c", 0)) - int(s.get("last", 0)) / 10000000
		pool.append({"id": id, "w": weight})
	pool.shuffle()
	pool.sort_custom(func(a, b): return a["w"] > b["w"])
	var out: Array = []
	for p in pool:
		out.append(p["id"])
	return out


func set_position(p: Vector2) -> void:
	last_position = p
	has_last_position = true
	save_soon()


# ---------------- 存档 ----------------

func save_soon() -> void:
	# 3 秒去抖：频繁变更（如移动位置）不会反复写盘
	if _save_timer != null and _save_timer.time_left > 0.0:
		return
	_save_timer = get_tree().create_timer(3.0)
	_save_timer.timeout.connect(save_now)


func save_now() -> void:
	var data := {
		"version": 1,
		"discovered": discovered,
		"favorites": favorites,
		"review_stats": review_stats,
		"last_position": [last_position.x, last_position.y],
		"has_last_position": has_last_position,
		"settings": settings,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("存档写入失败: " + SAVE_PATH)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()


func _load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	var d: Dictionary = data
	discovered = d.get("discovered", {})
	favorites = d.get("favorites", {})
	review_stats = d.get("review_stats", {})
	var lp: Array = d.get("last_position", [0, 0])
	last_position = Vector2(float(lp[0]), float(lp[1]))
	has_last_position = bool(d.get("has_last_position", false))
	for k in settings.keys():
		if d.get("settings", {}).has(k):
			settings[k] = d["settings"][k]


func reset_progress() -> void:
	discovered = {}
	favorites = {}
	review_stats = {}
	has_last_position = false
	last_position = Vector2.ZERO
	save_now()


func _seed_demo() -> void:
	for id in ["vending", "pole", "mailbox", "trash", "konbini", "station",
			"traffic_light", "sakura", "car", "bicycle", "cat", "ramen_shop"]:
		discovered[id] = int(Time.get_unix_time_from_system())
	favorites["vending"] = true


# ---------------- 音效（程序生成，无需音频文件） ----------------

func play_sfx(sfx_name: String) -> void:
	if _sfx_player == null:
		return
	if not _sfx_cache.has(sfx_name):
		var notes: Array = []
		match sfx_name:
			"click":
				notes = [[880.0, 0.05]]
			"discover":
				notes = [[523.25, 0.09], [659.25, 0.09], [783.99, 0.16]]
			"correct":
				notes = [[659.25, 0.08], [880.0, 0.12]]
			"wrong":
				notes = [[233.08, 0.18]]
			"open":
				notes = [[659.25, 0.05]]
			"shutter":
				notes = [[1567.98, 0.025], [392.0, 0.06]]
			_:
				return
		_sfx_cache[sfx_name] = _make_wav(notes)
	_sfx_player.stream = _sfx_cache[sfx_name]
	_sfx_player.play()


func _make_wav(notes: Array) -> AudioStreamWAV:
	var all := PackedByteArray()
	for n: Array in notes:
		all.append_array(_tone(float(n[0]), float(n[1])))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	wav.data = all
	return wav


func _tone(freq: float, dur: float) -> PackedByteArray:
	var rate := 22050
	var n := int(dur * rate)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var env := 1.0 - float(i) / float(n)
		env *= minf(1.0, float(i) / (rate * 0.008))  # 消除爆音的短起音
		var s := sin(TAU * freq * float(i) / float(rate)) * env * 0.55
		bytes.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	return bytes
