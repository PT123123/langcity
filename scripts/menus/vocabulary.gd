extends Control
## 词汇库：分类 chips + 搜索 + 词典全开放。
## 已发现的词白卡 + 收藏星；未发现的呈半透明灰卡（内容可见，鼓励上街发现）。

var popup: WordPopup
var list_box: VBoxContainer
var empty_label: Label
var count_label: Label
var search: LineEdit
var chips_box: HBoxContainer
var chip_group: ButtonGroup
var current_cat := ""       # "" = 全部
var only_fav := false

var _fav_btn: Button


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

	# ---- 搜索 ----
	search = LineEdit.new()
	search.placeholder_text = "搜索：日语 / 假名 / 罗马音 / 中文"
	search.custom_minimum_size = Vector2(0, 52)
	search.clear_button_enabled = true
	search.focus_mode = Control.FOCUS_CLICK
	var se := StyleBoxFlat.new()
	se.bg_color = UiKit.WHITE
	se.set_corner_radius_all(14)
	se.set_border_width_all(2)
	se.border_color = Color("c9c2b0")
	se.content_margin_left = 16
	se.content_margin_right = 12
	search.add_theme_stylebox_override("normal", se)
	var sef := se.duplicate()
	sef.border_color = UiKit.VERMILION
	search.add_theme_stylebox_override("focus", sef)
	search.add_theme_font_override("font", UiKit.font())
	search.add_theme_font_size_override("font_size", 20)
	search.add_theme_color_override("font_color", UiKit.INK)
	search.add_theme_color_override("font_placeholder_color", Color("b3ad9c"))
	search.add_theme_color_override("caret_color", UiKit.VERMILION)
	search.text_changed.connect(func(_t): _rebuild())
	root.add_child(search)

	# ---- 分类 chips ----
	var chips_scroll := ScrollContainer.new()
	chips_scroll.custom_minimum_size = Vector2(0, 50)
	chips_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	chips_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	root.add_child(chips_scroll)
	chips_box = HBoxContainer.new()
	chips_box.add_theme_constant_override("separation", 8)
	chips_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chips_scroll.add_child(chips_box)
	chip_group = ButtonGroup.new()
	_fav_btn = _make_chip("★ 收藏", UiKit.GOLD)
	_fav_btn.pressed.connect(func():
		only_fav = true
		Game.play_sfx("click")
		_rebuild())
	for cat: Dictionary in Game.categories_in_order():
		var b := _make_chip(String(cat["name"]), Game.category_color(String(cat["id"])))
		var cid := String(cat["id"])
		b.pressed.connect(func():
			current_cat = cid
			only_fav = false
			Game.play_sfx("click")
			_rebuild())
	# 「全部」chip 放最前
	var all_btn := _make_chip("全部", UiKit.INK)
	all_btn.button_pressed = true
	all_btn.pressed.connect(func():
		current_cat = ""
		only_fav = false
		Game.play_sfx("click")
		_rebuild())
	all_btn.move_to_front()
	chips_box.move_child(all_btn, 0)

	# ---- 列表 ----
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 14)
	scroll.add_child(list_box)

	empty_label = UiKit.label("", 22, Color("b3ad9c"), HORIZONTAL_ALIGNMENT_CENTER)
	empty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	empty_label.visible = false
	root.add_child(empty_label)

	popup = WordPopup.new()
	var pl := CanvasLayer.new()
	pl.layer = 10
	add_child(pl)
	pl.add_child(popup)

	_rebuild()
	Game.favorites_changed.connect(func(): _rebuild())
	Game.word_discovered.connect(func(_id): _rebuild())


func _make_chip(text: String, col: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = chip_group
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", UiKit.font())
	b.add_theme_font_size_override("font_size", 18)
	b.custom_minimum_size = Vector2(0, 42)
	b.set_meta("chip_color", col)
	var st := StyleBoxFlat.new()
	st.bg_color = UiKit.WHITE
	st.set_corner_radius_all(21)
	st.set_border_width_all(2)
	st.border_color = Color("c9c2b0")
	st.content_margin_left = 16
	st.content_margin_right = 16
	b.add_theme_stylebox_override("normal", st)
	var sth := st.duplicate()
	sth.bg_color = UiKit.PAPER_DARK
	b.add_theme_stylebox_override("hover", sth)
	b.add_theme_stylebox_override("pressed", sth)
	b.add_theme_color_override("font_color", UiKit.INK)
	b.add_theme_color_override("font_hover_color", UiKit.INK)
	chips_box.add_child(b)
	return b


## chip 选中态：底色换成分类色。toggle 按钮按下时走 pressed 样式，三个状态都要刷。
func _refresh_chips() -> void:
	for b: Button in chips_box.get_children():
		var col: Color = b.get_meta("chip_color", UiKit.INK)
		var active: bool = b.button_pressed
		for state in ["normal", "hover", "pressed"]:
			var sb: StyleBoxFlat = b.get_theme_stylebox(state)
			if sb is StyleBoxFlat:
				sb.bg_color = col if active else (UiKit.PAPER_DARK if state == "hover" else UiKit.WHITE)
				sb.border_color = col if active else Color("c9c2b0")
				sb.set_border_width_all(0 if active else 2)
		b.add_theme_color_override("font_color", UiKit.WHITE if active else UiKit.INK)
		b.add_theme_color_override("font_hover_color", UiKit.WHITE if active else UiKit.INK)
		b.add_theme_color_override("font_pressed_color", UiKit.WHITE)


func _rebuild() -> void:
	for c in list_box.get_children():
		c.queue_free()
	count_label.text = "%d / %d" % [Game.discovered_count(), Game.total_words()]
	var q := search.text.strip_edges().to_lower()
	var shown_any := false
	for cat: Dictionary in Game.categories_in_order():
		var cid := String(cat["id"])
		if not only_fav and not current_cat.is_empty() and current_cat != cid:
			continue
		var ids := Game.category_word_ids(cid)
		if only_fav:
			ids = ids.filter(func(id): return Game.is_favorite(id))
		if not q.is_empty():
			ids = ids.filter(func(id): return _match(Game.word(id), q))
		if ids.is_empty():
			continue
		list_box.add_child(_category_section(cat, ids))
		shown_any = true
	empty_label.text = "没有匹配的单词" if not shown_any else ""
	empty_label.visible = not shown_any
	_refresh_chips()


func _match(w: Dictionary, q: String) -> bool:
	for k in ["ja", "kana", "romaji", "zh"]:
		if String(w.get(k, "")).to_lower().contains(q):
			return true
	return false


func _category_section(cat: Dictionary, ids: Array) -> Control:
	var sec := VBoxContainer.new()
	sec.add_theme_constant_override("separation", 8)

	var total := Game.category_word_ids(String(cat["id"])).size()
	var have := 0
	for id in Game.category_word_ids(String(cat["id"])):
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

	var ja := UiKit.label(String(w.get("ja", "")), 24, UiKit.INK)
	ja.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(ja)
	# 未发现的词整行降不透明度，但内容可读、可点开（词典全开放）
	if not found:
		ja.add_theme_color_override("font_color", Color("8f8a78"))
	var zh_text := String(w.get("zh", ""))
	var right := UiKit.label(zh_text, 18, UiKit.INK_SOFT if found else Color("a29c8a"),
			HORIZONTAL_ALIGNMENT_RIGHT)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(right)
	if found:
		var fav := Game.is_favorite(id)
		var star := UiKit.label("★" if fav else "", 22, UiKit.GOLD)
		star.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hbox.add_child(star)
	else:
		var lock := UiKit.label("未发现", 15, Color("b3ad9c"))
		lock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hbox.add_child(lock)
	row.pressed.connect(func():
		Game.play_sfx("open")
		popup.show_word(w, false)
	)
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
		"furniture": return "家具"
		"clothing": return "服"
		"body": return "からだ"
		"time": return "じかん"
		"color": return "いろ"
		"people": return "ひと"
		"verb": return "うごき"
		"adj": return "ようす"
		"number": return "かず"
		"shopping": return "かいもの"
	return ""
