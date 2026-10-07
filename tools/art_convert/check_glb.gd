extends SceneTree
## 临时验证脚本：headless 加载 assets/art 下全部 glb，检查结构合理性。
## 用法：Godot_console.exe --headless -s tools/art_convert/check_glb.gd

func _init() -> void:
	var bad := 0
	var n_npc := 0
	var n_env := 0
	for sub in ["npcs", "env"]:
		var d := DirAccess.open("res://assets/art/" + sub)
		if d == null:
			printerr("✗ 目录不存在 assets/art/" + sub)
			bad += 1
			continue
		for f in d.get_files():
			if not f.ends_with(".glb"):
				continue
			var path := "res://assets/art/%s/%s" % [sub, f]
			var ps: PackedScene = load(path)
			if ps == null:
				printerr("✗ 无法加载 " + path)
				bad += 1
				continue
			var root := ps.instantiate()
			# 遍历收集：网格/表面/顶点色标记/骨架/动画
			var mesh_count := 0
			var surf_total := 0
			var vcol := false
			var bones := 0
			var anims: PackedStringArray = []
			var aabb := AABB()
			var stack: Array = [root]
			while not stack.is_empty():
				var n: Node = stack.pop_back()
				for c in n.get_children():
					stack.append(c)
				if n is MeshInstance3D and n.mesh != null:
					mesh_count += 1
					surf_total += n.mesh.get_surface_count()
					if aabb.size == Vector3.ZERO:
						aabb = n.get_aabb()
					else:
						aabb = aabb.merge(n.get_aabb())
					for s in n.mesh.get_surface_count():
						if n.mesh.surface_get_format(s) & Mesh.ARRAY_FORMAT_COLOR:
							vcol = true
				elif n is Skeleton3D:
					bones = n.get_bone_count()
				elif n is AnimationPlayer:
					anims = n.get_animation_list()
			var ok := true
			var why := ""
			if sub == "npcs":
				n_npc += 1
				if bones < 9:
					ok = false; why = "骨架关节数异常 %d" % bones
				elif mesh_count == 0:
					ok = false; why = "无网格"
				elif anims.is_empty():
					ok = false; why = "无动画"
			else:
				n_env += 1
				if mesh_count == 0:
					ok = false; why = "无网格"
				elif aabb.size.length() < 0.01:
					ok = false; why = "AABB 近似为零（坐标丢失）"
			if ok:
				print("✓ %-44s 面%d 骨%d 顶点色%s 动画%s aabb=%.1f" % [
					f, surf_total, bones, "有" if vcol else "无",
					",".join(anims), aabb.size.length()])
			else:
				printerr("✗ %-44s %s" % [f, why])
				bad += 1
			root.free()
	print("----")
	print("NPC %d 个 / 静态 %d 个 / 失败 %d" % [n_npc, n_env, bad])
	quit(1 if bad > 0 else 0)
