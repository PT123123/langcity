class_name ArtNpc
extends Node3D
## 美术包 NPC（assets/art/npcs/<glb>.glb，由 tools/art_convert 转换）：
## 加载 → 归一化身高 → 播 idle。talk() 切说话动画（任务面板/未来对话用）。
## 目录数据来自 data/npcs.json：
##   {"npcs": {"chef": {"glb":"chef","name":"シェフ","zh":"厨师","height":1.75}}}
## 任务发布（giver）由 quests.json 的 giver 字段单向关联本目录的 npc id。

const DATA_PATH := "res://data/npcs.json"
const ART_ROOT := "res://assets/art/npcs/"

static var _catalog := {}

var npc_id := ""
var display_name := ""

var _ap: AnimationPlayer
var _idle := ""
var _talk := ""
var _walk := ""


## npcs.json 目录（懒加载缓存一次）
static func data(id: String) -> Dictionary:
	if _catalog.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		if f != null:
			var v: Variant = JSON.parse_string(f.get_as_text())
			if v is Dictionary:
				_catalog = v.get("npcs", {})
	return _catalog.get(id, {})


func _ready() -> void:
	var d := data(npc_id)
	var glb := String(d.get("glb", npc_id))
	var path := ART_ROOT + glb + ".glb"
	if not ResourceLoader.exists(path):
		push_warning("NPC 模型缺失 " + path)
		queue_free()
		return
	display_name = String(d.get("name", npc_id))
	# ModelUtil.spawn：加载缓存 + 脚贴地 + 归一化到 npcs.json 的身高
	var inst := ModelUtil.spawn(self, path, Vector3.ZERO, float(d.get("height", 1.7)))
	if inst == null:
		queue_free()
		return
	_ap = ModelUtil.find_anim(inst, ["idle", "talk"])
	if _ap != null:
		_idle = ModelUtil.pick_anim(_ap, ["idle"])
		_talk = ModelUtil.pick_anim(_ap, ["talk"])
		_walk = ModelUtil.pick_anim(_ap, ["walk", "run"])
		if _idle != "":
			_ap.play(_idle)
			# 随机相位：同屏几个 NPC 不会齐刷刷做同一个动作
			_ap.seek(randf() * _ap.get_animation(_idle).length)


## 说话状态切换：on 时播 talk（没有 talk 动画则保持 idle）
func talk(on: bool) -> void:
	if _ap == null:
		return
	var target := (_talk if _talk != "" else _idle) if on else _idle
	if target != "" and _ap.current_animation != target:
		_ap.play(target)


## 巡航状态切换：on 时播 walk（没有 walk/run 动画则保持 idle，纯滑动也不难看）
func set_walking(on: bool) -> void:
	if _ap == null:
		return
	var target := (_walk if _walk != "" else _idle) if on else _idle
	if target != "" and _ap.current_animation != target:
		_ap.play(target)
