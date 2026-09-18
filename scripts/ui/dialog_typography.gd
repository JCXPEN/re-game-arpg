## DialogTypography —— 对话排版的纯测量助手（RefCounted，不碰场景树）
##
## 【负责什么】
##   "先量字、再定框"（策略说明见 DialogUI 文件头）：给定主题，量字体、
##   算自然宽度 / 折行数、按标点把长文分页，并给出提示条 / 对话条应有的尺寸。
##   量的结果由 DialogUI 拿去改面板 offset 与可见性 —— 本类不做任何副作用，
##   也因此可以单独测、不会烂成第二个状态机。
##
## 【为什么量宽度要用 font.get_string_size 而不是等 Label 自己算】
##   Label 开着 autowrap 时，`get_combined_minimum_size().x` 恒为 1（它可以折行，
##   最小宽度就是"一个字的宽度"）。也就是说 **Label 永远不会告诉你"我想多宽"**。
##   所以必须自己量：拿字体 + 字号算整句宽度，再决定面板给多宽。
##
## 【排版数值从哪来】
##   字号 / 行距 / 颜色全部在 Theme（`tools/generate_theme.gd`），
##   尺寸上下限（bar_min_width 等）由 DialogUI 作为参数传进来 —— 本类不持有任何配置。
class_name DialogTypography
extends RefCounted

## 画布宽度，用于把自适应尺寸夹在屏幕内。
const CANVAS_W: float = 320.0

## 分页断句时优先作为断点的字符（尽量不在句子中间断开）。
const BREAK_CHARS: String = "。！？；，、：」』）】…— \t"

## 取"用来查主题的节点"。
##
## 【为什么不用对话正文 Label 自己查】
##   `Control.get_theme_font(name, theme_type="")` 里传空 type 会回落到
##   **该控件当前挂的类型变体**。而对话正文的变体是逐句变化的（BODY/WHISPER/SHOUT…），
##   拿它去量"提示条的字体"会量到对话的变体上。
##   所以统一用对话条面板（它自己不挂变体）作为查询入口，并显式传类型名。
var theme_source: Control


func _init(source: Control) -> void:
	theme_source = source


## 文本样式 → Theme 里的 Label 类型变体名。
##
## 【为什么用 match 而不是 const 字典】
##   字典的键会用到 `DialogueLine.Style` 的枚举值，而"另一个 class_name 的枚举值"
##   在 GDScript 里**不是常量表达式** → `const DICT = {...}` 直接编译失败
##   （报 "isn't a constant expression"）。所以这里用 match，顺带还能让
##   漏配的样式自动回落到常规正文。
##
## **改样式请改 `tools/generate_theme.gd` 里对应的变体定义，不要在这里写字号/颜色。**
static func variation_for(style: DialogueLine.Style) -> StringName:
	match style:
		DialogueLine.Style.EMPHASIS:
			return &"DialogEmphasisLabel"
		DialogueLine.Style.WHISPER:
			return &"DialogWhisperLabel"
		DialogueLine.Style.SHOUT:
			return &"DialogShoutLabel"
		DialogueLine.Style.SYSTEM:
			return &"DialogSystemLabel"
		_:
			return &"DialogBodyLabel"


# ============================================================================
# 字体 / 行高
# ============================================================================

func font_for(type_name: StringName) -> Font:
	if theme_source == null:
		return null
	return theme_source.get_theme_font(&"font", type_name)


func font_size(type_name: StringName) -> int:
	if theme_source == null:
		return 12
	var fs: int = theme_source.get_theme_font_size(&"font_size", type_name)
	if fs > 0:
		return fs
	var fallback: int = theme_source.get_theme_font_size(&"font_size", &"Label")
	if fallback > 0:
		return fallback
	return 12


## 一行正文的高度 = 字体自身行高 + 主题的 line_spacing。
##
## 【为什么不用"字号 × 系数"估算】
##   点阵字的 `get_height()` 与字号并不相等（FusionPixel12 在 12px 下是 14），
##   估出来的行高会偏大或偏小，直接导致"预测高度"与实际渲染对不上 ——
##   要么留白难看，要么内容被裁。这里取字体真实行高，误差为 0。
func line_height(type_name: StringName) -> float:
	var font: Font = font_for(type_name)
	var base: float = float(font_size(type_name))
	if font != null:
		base = float(font.get_height(font_size(type_name)))
	var spacing: float = 0.0
	if theme_source != null:
		spacing = float(theme_source.get_theme_constant(&"line_spacing", type_name))
	return base + spacing


# ============================================================================
# 量字
# ============================================================================

## 把一个字符串换算成"在给定宽度下要占几行"。
##
## 用 `Font.get_multiline_string_size` 而不是自己数换行符：它会应用引擎
## 自己的折行规则（中日韩逐字断、西文按空格断），和 Label 实际渲染一致。
func count_lines(text: String, type_name: StringName, width: float) -> int:
	var font: Font = font_for(type_name)
	if font == null or text.is_empty() or width <= 0.0:
		return 1
	var size: Vector2 = font.get_multiline_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size(type_name))
	return maxi(1, int(round(size.y / maxf(1.0, line_height(type_name)))))


## 单行文本的自然宽度（不折行）。width_cap > 0 时结果被夹在上限内。
func string_width(text: String, type_name: StringName, width_cap: float) -> float:
	var font: Font = font_for(type_name)
	if font == null or text.is_empty():
		return 0.0
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size(type_name)).x
	if width_cap > 0.0:
		w = minf(w, width_cap)
	return w


# ============================================================================
# 样式盒子 / 容器
# ============================================================================

## 样式盒子左右内边距（含边框）。
func box_h_padding(box: Control) -> float:
	var sb: StyleBox = _panel_stylebox(box)
	if sb == null:
		return 0.0
	return sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT)


func box_v_padding(box: Control) -> float:
	var sb: StyleBox = _panel_stylebox(box)
	if sb == null:
		return 0.0
	return sb.get_margin(SIDE_TOP) + sb.get_margin(SIDE_BOTTOM)


static func _panel_stylebox(box: Control) -> StyleBox:
	if box == null:
		return null
	if box is PanelContainer:
		return (box as PanelContainer).get_theme_stylebox(&"panel")
	return box.get_theme_stylebox(&"panel")


## 表头（说话人 + 按钮）的最小宽度。对话条不能比它窄，否则按钮会被挤没。
static func header_min_width(header: HBoxContainer) -> float:
	if header == null:
		return 0.0
	return header.get_combined_minimum_size().x


static func header_height(header: HBoxContainer) -> float:
	if header == null:
		return 0.0
	return header.get_combined_minimum_size().y


static func vbox_separation(vbox: VBoxContainer) -> float:
	if vbox == null:
		return 0.0
	return float(vbox.get_theme_constant(&"separation"))


## 对话条正文可用的文字宽度上限（决定折行与分页）。
func bar_text_width(bar_panel: Control, max_width: float) -> float:
	if bar_panel == null:
		return max_width
	return maxf(32.0, max_width - box_h_padding(bar_panel))


# ============================================================================
# 面板定尺寸（只算不摆：应用 offset / visible 是 DialogUI 的事）
# ============================================================================

## 提示条应有的尺寸：短提示收窄，长提示换行、往下长。
func measure_notice_size(message: String, panel: Control, min_width: float,
		max_width: float) -> Vector2:
	if panel == null:
		return Vector2.ZERO
	var type_name: StringName = &"Label"
	var pad: float = box_h_padding(panel)
	var cap: float = clampf(max_width, min_width, CANVAS_W)
	var text_w: float = minf(string_width(message, type_name, 0.0), cap - pad)
	var w: float = clampf(text_w + pad, min_width, cap)
	var lines: int = count_lines(message, type_name, w - pad)
	var h: float = box_v_padding(panel) + float(lines) * line_height(type_name)
	return Vector2(w, h)


## 对话条应有的尺寸。
##
## 【宽度】短句贴合成一条窄条，长句收到 max_width 换行；
##         再夹一个下限，避免"嗯。"这种只有一个字的碎片条。
## 【高度】按"表头 + 正文行数"预测，供底部锚定往上长。
func measure_bar_size(text: String, style_name: StringName, panel: Control,
		header: HBoxContainer, vbox: VBoxContainer, min_width: float,
		max_width: float) -> Vector2:
	if panel == null:
		return Vector2.ZERO
	var pad: float = box_h_padding(panel)
	var cap: float = clampf(max_width, min_width, CANVAS_W)
	var text_cap: float = maxf(32.0, cap - pad)
	var natural: float = string_width(text, style_name, text_cap)
	# 文字区至少要放得下表头（说话人 + 按钮），否则按钮会被挤掉。
	var w: float = clampf(maxf(natural, header_min_width(header)) + pad, min_width, cap)
	var lines: int = count_lines(text, style_name, w - pad)
	var h: float = box_v_padding(panel) + header_height(header) + vbox_separation(vbox) \
		+ float(lines) * line_height(style_name)
	return Vector2(w, h)


# ============================================================================
# 自动分页
# ============================================================================

## 把整段文本按 `max_lines` 切成若干页（不需要分页时原样返回一页）。
##
## 【为什么均分而不是"每页塞满"】
##   130 个字按每页 3 行切是 3+3+3 行；按"塞满"切会得到 3+3+3 也一样，
##   但按上限切（例如 5 行上限、6 行文本）会得到 5+1 —— 第二页只有一个孤字，
##   翻过去看到一行字很突兀。所以先算"需要几页"，再均分成每页的行数。
func paginate(text: String, style_name: StringName, width: float, max_lines: int) -> PackedStringArray:
	var single: PackedStringArray = PackedStringArray([text])
	if max_lines <= 0 or text.strip_edges() == "":
		return single
	var total: int = count_lines(text, style_name, width)
	if total <= max_lines:
		return single
	var pages_needed: int = int(ceil(float(total) / float(max_lines)))
	var per_page: int = int(ceil(float(total) / float(pages_needed)))
	var pages: PackedStringArray = PackedStringArray()
	var rest: String = text
	var guard: int = 0
	while rest.strip_edges() != "" and guard < 64:
		guard += 1
		if count_lines(rest, style_name, width) <= per_page:
			pages.append(rest.strip_edges())
			break
		var cut: int = cut_for_lines(rest, style_name, width, per_page)
		if cut <= 0 or cut >= rest.length():
			pages.append(rest.strip_edges())
			break
		pages.append(rest.substr(0, cut).strip_edges())
		rest = rest.substr(cut)
	return pages if not pages.is_empty() else single


## 找一个切点：前缀刚好占 `max_lines` 行。
## 先二分找"不超过 max_lines 的最长前缀"，再往前回退到最近的标点/空格，
## 尽量避免把句子从中间劈开。
func cut_for_lines(text: String, style_name: StringName, width: float, max_lines: int) -> int:
	var lo: int = 1
	var hi: int = text.length()
	var best: int = 0
	while lo <= hi:
		var mid: int = (lo + hi) / 2
		if count_lines(text.substr(0, mid), style_name, width) <= max_lines:
			best = mid
			lo = mid + 1
		else:
			hi = mid - 1
	if best <= 0:
		return 0
	# 回退到最近的标点：最多退 10 个字，退不到就用二分结果（宁可断在句中也不要空转）。
	var floor_i: int = maxi(1, best - 10)
	for i: int in range(best, floor_i - 1, -1):
		if BREAK_CHARS.contains(text.substr(i - 1, 1)):
			return i
	return best
