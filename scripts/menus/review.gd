extends Control
## 复习测验：看日语选中文（或反过来），记录对错，供以后扩展 SRS。

const ROUND_SIZE := 10

var popup_layer: CanvasLayer
var popup: WordPopup

var top_bar: HBoxContainer
var progress_label: Label
var score_label: Label
var quiz_box: VBoxContainer
var result_box: VBoxContainer
var question_label: Label
var sub_label: Label
var answer_buttons: Array[Button] = []
var mode_hint: Label

var queue: Array = []
var index := -1
var correct_count := 0
var wrong_ids: Array = []
var current := {}
var answering := false


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

	# 顶栏
	top_bar = HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 16)
	root.add_child(top_bar)
	var back := UiKit.button("← 返回", false, 20)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	top_bar.add_child(back)
	var title := UiKit.label("复习", 34, UiKit.INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_bar.add_child(title)
	score_label = UiKit.label("", 22, UiKit.INK_SOFT)
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_bar.add_child(score_label)
	progress_label = UiKit.label("", 22, UiKit.INK)
	progress_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_bar.add_child(progress_label)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.panel_style(UiKit.WHITE, 20))
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(card)

	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(center)

	quiz_box = VBoxContainer.new()
	quiz_box.add_theme_constant_override("separation", 18)
	quiz_box.custom_minimum_size = Vector2(640, 0)
	center.add_child(quiz_box)

	mode_hint = UiKit.label("", 18, UiKit.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	mode_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quiz_box.add_child(mode_hint)

	question_label = UiKit.label("", 56, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	question_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quiz_box.add_child(question_label)

	sub_label = UiKit.label("", 24, UiKit.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	sub_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quiz_box.add_child(sub_label)

	quiz_box.add_child(UiKit.vspace(6))
	for i in 4:
		var b := UiKit.button("", false, 24)
		b.custom_minimum_size = Vector2(0, 62)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_answer.bind(i))
		quiz_box.add_child(b)
		answer_buttons.append(b)

	# 结果面板
	result_box = VBoxContainer.new()
	result_box.add_theme_constant_override("separation", 16)
	result_box.custom_minimum_size = Vector2(640, 0)
	result_box.visible = false
	center.add_child(result_box)

	popup = WordPopup.new()
	popup_layer = CanvasLayer.new()
	popup_layer.layer = 10
	add_child(popup_layer)
	popup_layer.add_child(popup)

	var pool := Game.review_candidates()
	if pool.size() < 2:
		_show_empty_state()
	else:
		_start_round()


func _show_empty_state() -> void:
	quiz_box.visible = false
	result_box.visible = true
	for c in result_box.get_children():
		c.queue_free()
	var t := UiKit.label("还没有可复习的单词", 30, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_box.add_child(t)
	var tip := UiKit.label("先去街道上发现至少 2 个单词吧！", 20, UiKit.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_box.add_child(tip)
	var go := UiKit.button("▶  去街道探索", true, 24)
	go.custom_minimum_size = Vector2(0, 58)
	go.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/street.tscn"))
	result_box.add_child(go)


func _start_round() -> void:
	queue = Game.review_candidates()
	if queue.size() > ROUND_SIZE:
		queue = queue.slice(0, ROUND_SIZE)
	index = -1
	correct_count = 0
	wrong_ids = []
	result_box.visible = false
	quiz_box.visible = true
	_next_question()


func _next_question() -> void:
	index += 1
	if index >= queue.size():
		_show_result()
		return
	progress_label.text = "第 %d / %d 题" % [index + 1, queue.size()]
	score_label.text = "答对 %d" % correct_count
	current = Game.word(String(queue[index]))
	var distractors := _pick_distractors(String(current["id"]))
	var options: Array = distractors.duplicate()
	options.push_back(current)
	options.shuffle()

	# 题干：偶数题看日语选中文，奇数题看中文选日语
	var ja_to_zh := index % 2 == 0
	question_label.text = String(current["ja"]) if ja_to_zh else String(current["zh"])
	sub_label.text = String(current.get("kana", "")) if ja_to_zh else "它的日语是？"
	mode_hint.text = "选出正确的中文意思" if ja_to_zh else "选出正确的日语说法"
	if ja_to_zh and bool(Game.settings.get("auto_speak", true)):
		Tts.speak_word(current)

	answering = true
	for i in 4:
		var opt: Dictionary = options[i]
		var b := answer_buttons[i]
		b.visible = i < options.size()
		b.text = String(opt["zh"]) if ja_to_zh else String(opt["ja"])
		b.disabled = false
		b.modulate = Color.WHITE
		b.add_theme_color_override("font_color", UiKit.INK)
		b.set_meta("word_id", String(opt["id"]))
		b.set_meta("correct", String(opt["id"]) == String(current["id"]))


func _pick_distractors(id: String) -> Array:
	var same_cat: Array = []
	var others: Array = []
	for other_id in Game.discovered.keys():
		if other_id == id:
			continue
		if Game.word(other_id).get("category", "") == current.get("category", ""):
			same_cat.append(Game.word(other_id))
		else:
			others.append(Game.word(other_id))
	others.shuffle()
	same_cat.shuffle()
	var out: Array = []
	for w: Dictionary in same_cat + others:
		if out.size() >= 3:
			break
		out.append(w)
	# 已发现的词不够时，从未学习的词里补（保证 4 个选项）
	if out.size() < 3:
		for other_id in Game.words.keys():
			if out.size() >= 3:
				break
			if other_id != id and Game.word(other_id).get("category", "") != current.get("category", ""):
				var w := Game.word(other_id)
				var dup := false
				for o in out:
					if o["id"] == other_id:
						dup = true
				if not dup:
					out.append(w)
	return out


func _on_answer(i: int) -> void:
	if not answering:
		return
	answering = false
	var b := answer_buttons[i]
	var correct := bool(b.get_meta("correct"))
	var picked_id := String(b.get_meta("word_id"))
	Game.record_review(String(current["id"]), correct)
	if picked_id != String(current["id"]):
		Game.record_review(picked_id, false)
	if correct:
		correct_count += 1
		Game.play_sfx("correct")
		b.modulate = Color(0.75, 1.0, 0.75)
		var ok := b
		ok.add_theme_color_override("font_color", Color("2e7d32"))
	else:
		wrong_ids.append(String(current["id"]))
		Game.play_sfx("wrong")
		b.modulate = Color(1.0, 0.72, 0.72)
		b.add_theme_color_override("font_color", Color("b03030"))
		for ob in answer_buttons:
			if ob.get_meta("correct"):
				ob.add_theme_color_override("font_color", Color("2e7d32"))
				ob.modulate = Color(0.85, 1.0, 0.85)
	for ob in answer_buttons:
		ob.disabled = true
	var timer := get_tree().create_timer(0.85)
	timer.timeout.connect(_next_question)


func _show_result() -> void:
	quiz_box.visible = false
	result_box.visible = true
	for c in result_box.get_children():
		c.queue_free()
	progress_label.text = "第 %d / %d 题" % [queue.size(), queue.size()]
	var t := UiKit.label("本轮复习完成  %d / %d" % [correct_count, queue.size()], 32, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_box.add_child(t)
	if wrong_ids.is_empty():
		var perfect := UiKit.label("全对！すごい！", 22, UiKit.GREEN_OK, HORIZONTAL_ALIGNMENT_CENTER)
		perfect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		result_box.add_child(perfect)
	else:
		var sub := UiKit.label("错题（点击查看）", 20, UiKit.INK_SOFT)
		result_box.add_child(sub)
		for id in wrong_ids:
			var w := Game.word(id)
			var row := UiKit.button("%s  ·  %s" % [String(w.get("ja", "")), String(w.get("zh", ""))], false, 20)
			row.custom_minimum_size = Vector2(0, 52)
			row.pressed.connect(func():
				Game.play_sfx("open")
				popup.show_word(w, false)
			)
			result_box.add_child(row)
	var again := UiKit.button("↻  再来一轮", true, 24)
	again.custom_minimum_size = Vector2(0, 58)
	again.pressed.connect(_start_round)
	result_box.add_child(again)
