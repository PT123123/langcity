class_name UiKit
extends RefCounted
## 全局 UI 工具：配色、字体、控件工厂。
## 纯静态工具，不依赖任何自动加载单例。

# ---- 和风配色 ----
const INK := Color("2b2b33")            # 墨色（主文字）
const INK_SOFT := Color("6b6858")       # 淡墨（次要文字）
const PAPER := Color("f7f3ea")          # 和纸（面板底色）
const PAPER_DARK := Color("ece5d3")     # 和纸·深
const VERMILION := Color("bf5754")      # 朱红（强调/主按钮）—— §17：降到中饱和
const VERMILION_DARK := Color("a83e3e")
const NAVY := Color("2b3040")           # 绀青（深色底）
const NAVY_LIGHT := Color("3a4056")
const GOLD := Color("d0a660")           # 金（收藏星）—— §17：降饱和
const GREEN_OK := Color("5f9e5f")
const WHITE := Color("fdfcf8")

## 由 Game 在启动时注入：按钮点击音回调（避免静态上下文引用单例）
static var click_cb: Callable = Callable()

static var _font: Font = null
static var _theme: Theme = null

const FONT_CANDIDATES := [
	"res://assets/fonts/NotoSansJP-Medium.ttf",
	"res://assets/fonts/NotoSansSC-Medium.ttf",
]

static func font() -> Font:
	if _font != null:
		return _font
	var loaded: Array[Font] = []
	for p in FONT_CANDIDATES:
		if ResourceLoader.exists(p):
			loaded.append(load(p))
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray([
		"Noto Sans CJK JP", "Noto Sans CJK SC", "Noto Sans JP", "Noto Sans SC",
		"Yu Gothic UI", "Yu Gothic", "Meiryo", "Microsoft YaHei",
		"PingFang SC", "Hiragino Sans", "sans-serif",
	])
	if loaded.is_empty():
		_font = sys
	else:
		var fv := FontVariation.new()
		fv.base_font = loaded[0]
		var rest: Array[Font] = []
		for i in range(1, loaded.size()):
			rest.append(loaded[i])
		rest.append(sys)
		fv.fallbacks = rest
		_font = fv
	return _font


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 22
	_theme = t
	return t


static func label(text: String, size: int, color: Color = INK, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func panel_style(bg: Color = PAPER, radius: int = 14, border: Color = Color(0, 0, 0, 0), bw: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	# 视觉方向 §17：UI 权重低于世界 —— 阴影更收、更淡，面板不「浮」在画面之上
	sb.shadow_color = Color(0.1, 0.08, 0.12, 0.18)
	sb.shadow_size = 5
	sb.shadow_offset = Vector2(0, 3)
	return sb


static func style_button(b: Button, primary: bool = true, font_size: int = 24) -> void:
	b.add_theme_font_override("font", font())
	b.add_theme_font_size_override("font_size", font_size)
	b.focus_mode = Control.FOCUS_NONE
	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(16)
	normal.content_margin_left = 22
	normal.content_margin_right = 22
	normal.content_margin_top = 12
	normal.content_margin_bottom = 12
	var hover := normal.duplicate()
	var down := normal.duplicate()
	var disabled := normal.duplicate()
	if primary:
		normal.bg_color = VERMILION
		hover.bg_color = Color("d66363")
		down.bg_color = VERMILION_DARK
		disabled.bg_color = Color("9a9284")
		b.add_theme_color_override("font_color", WHITE)
		b.add_theme_color_override("font_hover_color", WHITE)
		b.add_theme_color_override("font_pressed_color", WHITE)
		b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.65))
	else:
		normal.bg_color = WHITE
		normal.border_color = Color("c9c2b0")
		normal.set_border_width_all(2)
		hover.bg_color = PAPER_DARK
		hover.border_color = Color("b0a894")
		hover.set_border_width_all(2)
		down.bg_color = Color("e0d8c4")
		down.border_color = Color("b0a894")
		down.set_border_width_all(2)
		disabled.bg_color = Color(1, 1, 1, 0.4)
		disabled.border_color = Color("d5cfbf")
		disabled.set_border_width_all(2)
		b.add_theme_color_override("font_color", INK)
		b.add_theme_color_override("font_hover_color", INK)
		b.add_theme_color_override("font_pressed_color", INK)
		b.add_theme_color_override("font_disabled_color", Color(0.42, 0.4, 0.35, 0.6))
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", down)
	b.add_theme_stylebox_override("disabled", disabled)
	if click_cb.is_valid():
		b.pressed.connect(click_cb)


static func button(text: String, primary: bool = true, font_size: int = 24) -> Button:
	var b := Button.new()
	b.text = text
	style_button(b, primary, font_size)
	return b


static func icon_button(text: String, size: int = 30) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font())
	b.add_theme_font_size_override("font_size", size)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.13, 0.14, 0.19, 0.72)
	normal.set_corner_radius_all(14)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal.duplicate())
	b.add_theme_stylebox_override("pressed", normal.duplicate())
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	if click_cb.is_valid():
		b.pressed.connect(click_cb)
	return b


static func vspace(px: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, px)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func hspace(px: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(px, 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
