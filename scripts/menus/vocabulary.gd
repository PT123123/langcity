extends Control
## 词汇库：按分类展示进度，点击查看词条详情，支持收藏筛选。

var popup: WordPopup
var list_box: VBoxContainer
var count_label: Label
var filter_all: Button
var filter_fav: Button
var only_fav := false


func _ready() -> void:
	theme = UiKit.theme()

	var bg := ColorRect.new()
	bg.color = UiKit.PAPER
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24
	root.offset_right = -24
	root.offset_top = 18
	root.offset_bottom = -18
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	# ---- 顶栏 ----
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	root.add_child(top)
	var back := UiKit.button("← 返回", false, 20)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	top.add_child(back)
	var title := UiKit.label("词汇库", 34, UiKit.INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(title)
	count_label = UiKit.label("", 22, UiKit.INK_SOFT, HORIZONTAL_ALIGNMENT_RIGHT)
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(count_label)

	# ---- 筛选 ----
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 10)
	root.add_child(filters)
	var group := ButtonGroup.new()
	filter_all = UiKit.button("全部", true, 19)
	filter_all.toggle_mode = true
	filter_all.button_group = group
	filter_all.button_pressed = true
	filter_all.pressed.connect(func(): _set_filter(false))
	filters.add_child(filter_all)
	filter_fav = UiKit.button("★ 已收藏", true, 19)
	filter_fav.toggle_mode = true
	filter_fav.button_group = group
	filter_fav.pressed.connect(func(): _set_filter(true))
	filters.add_child(filter_fav)
	_filter_style()

	# ---- 列表 ----
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 14)
	scroll.add_child(list_box)

	popup = WordPopup.new()
	var pl := CanvasLayer.new()
	pl.layer = 10
	add_child(pl)
	pl.add_child(popup)

	_rebuild()
	Game.favorites_changed.connect(func(): _rebuild())
	Game.word_discovered.connect(func(_id): _rebuild())


func _set_filter(fav: bool) -> void:
	only_fav = fav
	Game.play_sfx("click")
	_filter_style()
	_rebuild()


func _filter_style() -> void:
	# 选中项用主色，未选中用描边样式，状态一目了然
	for b in [filter_all, filter_fav]:
		for state in ["normal", "hover", "pressed"]:
			var sb: StyleBoxFlat = b.get_theme_stylebox(state)
			if sb is StyleBoxFlat:
				var active: bool = (b == filter_fav) == only_fav
				sb.bg_color = UiKit.VERMILION if active and state == "normal" else (Color("d66363") if active and state == "hover" else (UiKit.VERMILION_DARK if active else UiKit.WHITE))
				sb.border_color = Color("c9c2b0") if not active else UiKit.VERMILION
				sb.set_border_width_all(0 if active else 2)
		b.add_theme_color_override("font_color", UiKit.WHITE if (b == filter_fav) == only_fav else UiKit.INK)


func _rebuild() -> void:
	for c in list_box.get_children():
		c.queue_free()
	count_label.text = "%d / %d" % [Game.discovered_count(), Game.total_words()]
	for cat: Dictionary in Game.categories_in_order():
		var ids := Game.category_word_ids(String(cat["id"]))
		if only_fav:
			ids = ids.filter(func(id): return Game.is_favorite(id) and Game.is_discovered(id))
		if ids.is_empty():
			continue
		list_box.add_child(_category_section(cat, ids))


func _category_section(cat: Dictionary, ids: Array) -> Control:
	var sec := VBoxContainer.new()
	sec.add_theme_constant_override("separation", 8)

	var have := 0
	var total := 0
	for id in Game.category_word_ids(String(cat["id"])):
		total += 1
		if Game.is_discovered(id):
			have += 1

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var dot := PanelContainer.new()
	var dot_style := StyleBoxFlat.new()
	dot_style.bg_color = Game.category_color(String(cat["id"]))
	dot_style.set_corner_radius_all(7)
	dot.custom_minimum_size = Vector2(16, 16)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.add_theme_stylebox_override("panel", dot_style)
	head.add_child(dot)
	var name_label := UiKit.label("%s  ·  %s" % [String(cat["name"]), _jp_name(String(cat["id"]))], 24, UiKit.INK)
	head.add_child(name_label)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(UiKit.label("%d / %d" % [have, total], 20, UiKit.INK_SOFT))
	sec.add_child(head)

	# 进度条
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = maxi(total, 1)
	bar.value = have
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = UiKit.PAPER_DARK
	bg_sb.set_corner_radius_all(4)
	var fill_sb := StyleBoxFlat.new()
	fill_sb.bg_color = Game.category_color(String(cat["id"]))
	fill_sb.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg_sb)
	bar.add_theme_stylebox_override("fill", fill_sb)
	sec.add_child(bar)

	for id in ids:
		sec.add_child(_word_row(id))
	return sec


func _word_row(id: String) -> Control:
	var w := Game.word(id)
	var found := Game.is_discovered(id)
	var row := Button.new()
	row.custom_minimum_size = Vector2(0, 62)
	row.focus_mode = Control.FOCUS_NONE
	var st := StyleBoxFlat.new()
	st.bg_color = UiKit.WHITE if found else UiKit.PAPER_DARK
	st.set_corner_radius_all(14)
	st.content_margin_left = 18
	st.content_margin_right = 18
	st.content_margin_top = 10
	st.content_margin_bottom = 10
	row.add_theme_stylebox_override("normal", st)
	var sth := st.duplicate()
	sth.bg_color = UiKit.PAPER_DARK if found else UiKit.PAPER
	row.add_theme_stylebox_override("hover", sth)
	row.add_theme_stylebox_override("pressed", sth)
	row.add_theme_stylebox_override("disabled", st)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 18
	hbox.offset_right = -18
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 12)
	row.add_child(hbox)

	if found:
		var ja := UiKit.label(String(w.get("ja", "")), 24, UiKit.INK)
		ja.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hbox.add_child(ja)
		var zh := UiKit.label(String(w.get("zh", "")), 18, UiKit.INK_SOFT)
		zh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		zh.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		zh.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hbox.add_child(zh)
		var fav := Game.is_favorite(id)
		var star := UiKit.label("★" if fav else "", 22, UiKit.GOLD)
		star.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hbox.add_child(star)
		row.pressed.connect(func():
			Game.play_sfx("open")
			popup.show_word(w, false)
		)
	else:
		var q := UiKit.label("？？？", 24, Color("b3ad9c"))
		q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hbox.add_child(q)
		var tip := UiKit.label("去街道上发现它吧", 17, Color("b3ad9c"))
		tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hbox.add_child(tip)
	return row


## 分类的日语名（装饰用）
func _jp_name(cat_id: String) -> String:
	match cat_id:
		"street": return "道"
		"transport": return "乗り物"
		"building": return "町の建物"
		"nature": return "自然"
		"animal": return "生き物"
		"food": return "食べ物"
	return ""
