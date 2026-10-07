extends Node
## 自动加载：ShotTool —— 自动化截图工具（仅开发用）。
## 用法：
##   godot --path . -- --shot=out/menu.png --shot-frames=40 [--shot-scene=res://scenes/street.tscn] [--shot-action=demo_popup] [--demo]
## 到达指定帧后把当前画面存为 PNG 并退出。普通游玩时不产生任何影响。

var shot_path := ""
var shot_frames := 40
var shot_action := ""

var _count := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--shot="):
			shot_path = a.substr(7)
		elif a.begins_with("--shot-frames="):
			shot_frames = int(a.substr(14))
		elif a.begins_with("--shot-scene="):
			var scene_path := a.substr(13)
			get_tree().change_scene_to_file.call_deferred(scene_path)
		elif a.begins_with("--shot-action="):
			shot_action = a.substr(14)
		elif a.begins_with("--shot-place="):
			# 开发用：直接以某个 place（城市或室内）启动，便于对室内家具截图
			Game.current_place_id = a.substr(13)
			Game.pending_spawn = {}
	if shot_path.is_empty():
		set_process(false)


func _process(_delta: float) -> void:
	_count += 1
	if _count >= shot_frames:
		set_process(false)
		# headless（dummy 渲染器）下取不到纹理，img 为 null；必须判空，
		# 否则 save_png 抛脚本错误会中断本函数，get_tree().quit() 永远执行不到 → 进程挂死。
		var tex := get_viewport().get_texture()
		var img: Image = tex.get_image() if tex != null else null
		if img != null:
			img.save_png(shot_path)
			print("[ShotTool] 已保存 ", shot_path)
		else:
			print("[ShotTool] 无渲染纹理（headless），跳过保存")
		get_tree().quit()
