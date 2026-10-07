extends SceneTree
## 批次2a 冒烟：npcs.json 完整性 + map.json npc 条目 + Interactable npc 分发端到端。
## 用法：Godot_console.exe --headless -s tools/art_convert/smoke_npc.gd

func _init() -> void:
	var errs := 0
	# 1) npcs.json 可读、条目 >= 10、每个 glb 存在
	var f := FileAccess.open("res://data/npcs.json", FileAccess.READ)
	if f == null:
		printerr("✗ npcs.json 无法读取")
		quit(1)
		return
	var v: Variant = JSON.parse_string(f.get_as_text())
	if typeof(v) != TYPE_DICTIONARY or not (v["npcs"] is Dictionary) \
			or (v["npcs"] as Dictionary).size() < 10:
		printerr("✗ npcs.json 格式/条目数异常")
		quit(1)
		return
	var catalog: Dictionary = v["npcs"]
	for id: String in catalog:
		var d: Dictionary = catalog[id]
		var p := "res://assets/art/npcs/%s.glb" % String(d.get("glb", id))
		if not ResourceLoader.exists(p):
			printerr("✗ 缺模型 " + p)
			errs += 1
	# 2) map.json 的每个 npc 条目都在目录里
	var mf := FileAccess.open("res://data/map.json", FileAccess.READ)
	var mv: Variant = JSON.parse_string(mf.get_as_text())
	var n_map := 0
	for o: Dictionary in (mv["objects"] as Array):
		if String(o.get("kind", "")) == "npc":
			n_map += 1
			if not catalog.has(String(o.get("npc", ""))):
				printerr("✗ map 里 npc 无目录: " + String(o.get("npc", "")))
				errs += 1
	if n_map < 10:
		printerr("✗ map.json npc 条目过少: %d" % n_map)
		errs += 1
	# 3) 端到端：Interactable npc 分发 → ArtNpc → glb + idle 动画
	var it := Interactable.make({"kind": "npc", "npc": "chef", "x": 100, "y": 100})
	root.add_child(it)
	await process_frame
	var npc_node: ArtNpc = null
	for c in it.get_children():
		if c is ArtNpc:
			npc_node = c
	if npc_node == null:
		printerr("✗ ArtNpc 未生成")
		errs += 1
	elif npc_node.display_name.is_empty() or not is_instance_valid(npc_node._ap):
		printerr("✗ ArtNpc 初始化异常 name=%s" % npc_node.display_name)
		errs += 1
	else:
		print("✓ chef NPC: name=%s idle=%s talk=%s" % [
			npc_node.display_name, npc_node._idle, npc_node._talk])
	# 4) delivery 分发（deliveries glb）
	var it2 := Interactable.make({"kind": "delivery", "model": "postcard", "x": 120, "y": 120})
	root.add_child(it2)
	await process_frame
	if _has_mesh(it2):
		print("✓ delivery postcard 生成网格")
	else:
		printerr("✗ delivery 未生成网格")
		errs += 1
	# 5) tree 分发（art 树冠 + tint + 树干）
	var it3 := Interactable.make({"kind": "tree", "word": "tree", "x": 140, "y": 140})
	root.add_child(it3)
	await process_frame
	if _has_mesh(it3):
		print("✓ tree 生成网格")
	else:
		printerr("✗ tree 未生成网格")
		errs += 1
	print("----")
	print("冒烟%s" % ("失败 %d 处" % errs if errs > 0 else "全部通过"))
	quit(1 if errs > 0 else 0)


## 递归查有无 MeshInstance3D（glb 树冠/程序化树干都算）
func _has_mesh(n: Node) -> bool:
	if n is MeshInstance3D:
		return true
	for c in n.get_children():
		if _has_mesh(c):
			return true
	return false
