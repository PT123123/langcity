extends Node
## 自动加载：Places —— 多地图注册表。
## 数据来自 res://data/places.json：
##   kind=planet   星球世界：{"kind":"planet","title_zh":"小星球","map":"res://data/planet.json"}
##   kind=interior 室内空间：{"kind":"interior","title_zh":"便利店","template":"konbini_shop","parent":"planet_home"}
## 星球的 objects 由 street.gd 读取对应 map 文件摆上球面；本单例只负责注册表查询，
## 以及「某 kind 出现在哪些室外地图」的反查（跑腿任务指路用）。

const PLACES_PATH := "res://data/places.json"

var _places := {}
var _default := "planet_home"
var _kind_index := {}    # kind -> PackedStringArray(place_id)
var _scanned := false


func _ready() -> void:
	_load()


func _load() -> void:
	var f := FileAccess.open(PLACES_PATH, FileAccess.READ)
	if f == null:
		push_error("无法读取地图注册表 " + PLACES_PATH)
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("地图注册表格式错误 " + PLACES_PATH)
		return
	_default = String(data.get("default", "planet_home"))
	_places = data.get("places", {})


func default_id() -> String:
	return _default


func has_place(id: String) -> bool:
	return _places.has(id)


## 取 place 描述；未知 id 回退到默认 place（保证不会拿到空字典导致场景空转）
func get_place(id: String) -> Dictionary:
	if _places.has(id):
		return _places[id]
	return _places.get(_default, {})


func is_interior(id: String) -> bool:
	return String(get_place(id).get("kind", "")) == "interior"


func title(id: String) -> String:
	return String(get_place(id).get("title_zh", id))


## 该 place 的父地图（室内的「出门返回城」）。非室内返回空串。
func parent_of(id: String) -> String:
	return String(get_place(id).get("parent", ""))


## 某 kind 出现在哪些城市地图。惰性扫描各地图 objects；跑腿任务在当前图
## 找不到目标时用它反查应去哪个城（配合该城的 portal 指路）。
func kind_index(kind: String) -> PackedStringArray:
	if not _scanned:
		_scan_kinds()
	return _kind_index.get(kind, PackedStringArray())


func _scan_kinds() -> void:
	_scanned = true
	_kind_index = {}
	for id in _places:
		var p: Dictionary = _places[id]
		# 室外地图（星球/城市 alike）才参与 kind 反查；室内没有独立地图文件
		if String(p.get("kind", "")) == "interior":
			continue
		var path := String(p.get("map", ""))
		if path.is_empty():
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var data: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(data) != TYPE_DICTIONARY:
			continue
		for o: Dictionary in data.get("objects", []):
			var k := String(o.get("kind", ""))
			if k.is_empty():
				continue
			var arr: PackedStringArray = _kind_index.get(k, PackedStringArray())
			if not arr.has(id):
				arr.append(id)
				_kind_index[k] = arr


## 修改注册表数据后强制重扫（供扩展/调试用）
func invalidate() -> void:
	_scanned = false
