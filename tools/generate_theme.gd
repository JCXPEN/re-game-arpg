## GenerateTheme —— 生成项目 UI 主题（编辑器工具脚本）
##
## 【负责什么】
##   生成 res://resources/ui_theme.tres —— 全项目**唯一**的皮肤来源。
##   做法遵循 Godot 官方 GUI 换肤文档（tutorials/ui/gui_skinning）：
##     1) 所有外观写在 Theme 里，节点上不再散落 add_theme_*_override；
##     2) 九宫格贴图用 StyleBoxTexture + 正确的 texture_margin（不拉伸边框）；
##     3) 同一控件族的"语义变体"用 Theme 类型变体（type variation）表达，
##        例如 PrimaryButton / HealthBar / DangerButton，而不是每个节点各调一遍。
##
## 【怎么运行】
##   Godot --headless --path . res://tools/generate_theme.tscn
##   依赖 res://assets/sprites/ui/theme/gen/ 下的九宫格贴图；
##   若贴图不存在请先跑 res://tools/generate_ui_skin.tscn 再 --import。
##
## 【设计语言（本次重做的依据）】
##   1) **状态阶梯由基色派生**，不为每个状态手挑颜色
##      —— 参考 passivestar/godot-minimal-theme 的 _get_base_color(offset) 模式。
##   2) **disabled 靠"低对比 + 无立体感"区分，pressed 靠"凹陷 + 强调描边"区分**
##      —— 参考 godotengine/godot 的 default_theme.cpp：
##         pressed 用最深填充，disabled 用低不透明度/低对比，两者语义不重叠。
##   3) **像素 UI 的立体语义靠斜面方向**：凸起=可点，凹陷=已按下，扁平=不可点。
##
## 【上一版为什么"按下去反直觉"（已修）】
##   - 素材包的 button_pressed 整体压暗（avgLum 75.6）比 button_disabled（83.7）还暗，
##     按下去像"变灰失效"，且它顶行整行透明，按钮还会缩水；
##   - 三态 content_margin 完全一致 → **按下去文字不动**，没有任何"压下去"的反馈；
##   - focus 用的是 8×8 的 nine_path_focus（实心块 + 中心黑洞，还 TILE 平铺），
##     Tab 上去整个按钮被一块橙色盖住。
##
## 【改配色/字号改哪里】
##   只改下面的"设计 token"两组常量，全项目 UI 一起变。
extends Node

# ============================================================================
# 常量 —— 资源
# ============================================================================

const FONT := "res://assets/fonts/FusionPixel12px.ttf"
const OUT := "res://resources/ui_theme.tres"
## 程序化生成的九宫格贴图目录（见 tools/generate_ui_skin.gd）。
const GEN := "res://assets/sprites/ui/theme/gen/%s.png"
## 素材包自带贴图目录（仅图标类还在用）。
const T := "res://assets/sprites/ui/theme/%s.png"

# ============================================================================
# 设计 token —— 表面 / 描边 / 文字 / 强调
# ============================================================================
#
# 【为什么改成"冷深色表面 + 单一暖强调色"】
#   上一版按钮是满饱和橙（240,103,51）配近黑文字，整屏没有层级：
#   主操作和次要操作长得一样，金色强调也就失去了强调的作用。
#   现在表面统一走冷深紫灰，暖金色只留给"可交互 / 进行中 / 重要"，
#   红色留给危险操作，层级一眼可辨。

## 最底层背景（面板背后的世界）。
const C_VOID := Color8(0x0B, 0x0A, 0x10)
## 面板底色。
const C_PANEL := Color8(0x14, 0x12, 0x1C)
## 对话框底色。比 C_PANEL 再深一档、且**完全不透明** —— 对话是要逐字读的长文本，
## 背后任何木纹/瓦片都会变成干扰阅读的噪声（旧版 90% 不透明就吃了这个亏）。
const C_DIALOG_BG := Color8(0x0E, 0x0D, 0x16)
## 凹槽（进度条底、输入框）。
const C_WELL := Color8(0x0E, 0x0C, 0x14)
## 分隔线 / 极弱描边。
const C_LINE := Color8(0x2A, 0x24, 0x38)
## 常规描边。
const C_BORDER := Color8(0x3A, 0x33, 0x50)
## 强调色（可交互、进行中）。
const C_ACCENT := Color8(0xE8, 0xA3, 0x3D)
## 强调色高亮（hover / 焦点环）。
const C_ACCENT_HI := Color8(0xFF, 0xD9, 0x80)
## 主文字。
const C_TEXT := Color8(0xED, 0xE8, 0xDC)
## 次要文字（说明、脚注）。
const C_MUTED := Color8(0xA7, 0x9F, 0xB8)
## 禁用态文字——刻意压到接近底色，一眼就知道点不动。
const C_OFF := Color8(0x5E, 0x58, 0x70)
## 危险。
const C_DANGER := Color8(0xE0, 0x5B, 0x4C)
## 成功 / 增益。
const C_OK := Color8(0x7B, 0xC4, 0x62)
## 生命 / 法力。
const C_HP := Color8(0xD9, 0x45, 0x3A)
const C_MP := Color8(0x41, 0x7E, 0xD8)
## 遮罩（弹窗背后的变暗层）。
const C_DIM := Color(0, 0, 0, 0.66)

# ---------------------------------------------------------------------------
# 字号阶 —— 全项目字号的唯一出处
# ---------------------------------------------------------------------------
#
# 【为什么正文固定 12】
#   1) 用的是 Fusion Pixel 12px 点阵字，12 是它的**设计尺寸**，
#      1:1 渲染时每个点正好落在画布像素上，最锐利；
#      设成 8/10 会让点阵做非整数缩放，汉字笔画糊成一团。
#   2) 视口是 320×180，12px 占屏高 6.7%，一行能放 20+ 个汉字，够用。
const FS_HINT := 10
const FS_BODY := 12
const FS_HEADING := 14
const FS_TITLE := 20

## 按钮最小高度：12px 字行高 16 + 内容边距上下各 4 = 24。
const BTN_MIN_H := 24
## 九宫格四角尺寸，必须与 generate_ui_skin.gd 的 MARGIN 一致。
const SLICE_MARGIN := 3.0

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("res://resources")
	var theme: Theme = Theme.new()
	_setup_defaults(theme)
	_setup_label(theme)
	_setup_rich_text(theme)
	_setup_button(theme)
	_setup_panel(theme)
	_setup_progress_bar(theme)
	_setup_slider(theme)
	_setup_check_box(theme)
	_setup_scroll(theme)
	_setup_line_edit(theme)
	_setup_containers(theme)
	_setup_variations(theme)
	var err: int = ResourceSaver.save(theme, OUT)
	print("[GenerateTheme] 主题生成%s（err=%d，控件类型 %d 个）"
		% ["完毕" if err == OK else "失败", err, theme.get_type_list().size()])
	get_tree().quit()


# ============================================================================
# 基础
# ============================================================================

func _setup_defaults(theme: Theme) -> void:
	if ResourceLoader.exists(FONT):
		theme.default_font = load(FONT)
	else:
		push_warning("[GenerateTheme] 缺少字体：%s（中文会退化成系统字体）" % FONT)
	theme.default_font_size = FS_BODY


func _setup_label(theme: Theme) -> void:
	theme.set_color("font_color", "Label", C_TEXT)
	# 1px 硬阴影：像素字在游戏画面上（尤其压在贴图/敌人身上）必须靠它保可读性。
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.75))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)
	theme.set_constant("line_spacing", "Label", 2)
	theme.set_font_size("font_size", "Label", FS_BODY)


func _setup_rich_text(theme: Theme) -> void:
	theme.set_color("default_color", "RichTextLabel", C_TEXT)
	theme.set_color("font_shadow_color", "RichTextLabel", Color(0, 0, 0, 0.75))
	theme.set_constant("shadow_offset_x", "RichTextLabel", 1)
	theme.set_constant("shadow_offset_y", "RichTextLabel", 1)
	theme.set_constant("line_separation", "RichTextLabel", 3)
	for key: String in ["normal_font_size", "bold_font_size", "italics_font_size", "mono_font_size"]:
		theme.set_font_size(key, "RichTextLabel", FS_BODY)
	theme.set_stylebox("normal", "RichTextLabel", _empty())


# ============================================================================
# 按钮
# ============================================================================

## 按钮四态 + 焦点环。
##
## 【本次修正的三件事】
##   1) pressed 用"凹陷"贴图 + 更深的填充，配合**金色强调描边**，
##      所以它是最深的但**不会**被误读成 disabled（disabled 是扁平 + 灰边 + 灰字）。
##   2) pressed 的 content_margin 上 +1 / 下 -1 → **按下时文字下沉 1px**，
##      这是"真的被压下去了"最关键的一条反馈，之前完全没有。
##   3) focus 改成"不画中心 + 1px 金色边 + 外扩 1px"的细环，
##      叠在当前状态之上而不遮挡它（旧版是块带洞的 8×8 图，会盖住整个按钮）。
func _setup_button(theme: Theme) -> void:
	theme.set_stylebox("normal", "Button", _btn("btn_normal", 0))
	theme.set_stylebox("hover", "Button", _btn("btn_hover", 0))
	theme.set_stylebox("pressed", "Button", _btn("btn_pressed", 1))
	theme.set_stylebox("disabled", "Button", _btn("btn_disabled", 0))
	theme.set_stylebox("focus", "Button", _focus_ring())
	# 文字：底色深 → 用亮字；按下时给强调色，保证"最深底 + 最亮字"对比最强。
	theme.set_color("font_color", "Button", C_TEXT)
	theme.set_color("font_hover_color", "Button", Color8(0xFF, 0xF4, 0xDC))
	theme.set_color("font_pressed_color", "Button", C_ACCENT_HI)
	theme.set_color("font_disabled_color", "Button", C_OFF)
	theme.set_color("font_focus_color", "Button", Color8(0xFF, 0xF4, 0xDC))
	theme.set_font_size("font_size", "Button", FS_BODY)
	theme.set_constant("h_separation", "Button", 8)
	theme.set_constant("outline_size", "Button", 0)


## 建一个按钮状态样式。
## shift_down：按下时内容下沉的像素数（0 = 不动）。
func _btn(tex_name: String, shift_down: int) -> StyleBoxTexture:
	var box: StyleBoxTexture = StyleBoxTexture.new()
	var path: String = GEN % tex_name
	if not ResourceLoader.exists(path):
		push_warning("[GenerateTheme] 缺少按钮贴图：%s（回退纯色）" % path)
		return _flat_fallback(C_BORDER)
	box.texture = load(path)
	box.set_texture_margin_all(SLICE_MARGIN)
	# 左右 8px 内边距；上下合计 8px（12px 字行高 16 + 8 = BTN_MIN_H 24）。
	box.content_margin_left = 8.0
	box.content_margin_right = 8.0
	box.content_margin_top = 4.0 + float(shift_down)
	box.content_margin_bottom = 4.0 - float(shift_down)
	return box


## 焦点环：只画 1px 边、不画中心、整体外扩 1px。
## draw_center=false 是关键——否则叠在按钮上会把按钮整个盖掉。
func _focus_ring() -> StyleBoxFlat:
	var ring: StyleBoxFlat = _flat(Color(0, 0, 0, 0))
	ring.draw_center = false
	ring.border_color = C_ACCENT_HI
	ring.set_border_width_all(1)
	ring.set_expand_margin_all(1.0)
	return ring


# ============================================================================
# 面板
# ============================================================================

func _setup_panel(theme: Theme) -> void:
	var panel: StyleBox = _slice("panel_bg", 10.0)
	for type_name: String in ["Panel", "PanelContainer", "PopupPanel", "PopupMenu", "TooltipPanel"]:
		theme.set_stylebox("panel", type_name, panel)
	theme.set_font_size("font_size", "PopupMenu", FS_BODY)
	theme.set_color("font_color", "PopupMenu", C_TEXT)
	theme.set_color("font_hover_color", "PopupMenu", C_ACCENT_HI)
	theme.set_color("font_color", "TooltipLabel", C_TEXT)
	theme.set_font_size("font_size", "TooltipLabel", FS_HINT)


func _setup_progress_bar(theme: Theme) -> void:
	theme.set_stylebox("background", "ProgressBar", _slice("well_bg", 0.0))
	theme.set_stylebox("fill", "ProgressBar", _flat(C_ACCENT))
	theme.set_color("font_color", "ProgressBar", C_TEXT)
	theme.set_font_size("font_size", "ProgressBar", FS_HINT)


# ============================================================================
# 滑块 / 复选框 / 滚动条 / 输入框
# ============================================================================

## 滑块轨道上下内边距（决定轨道厚度）。
##
## 【为什么必须显式设 content_margin —— 这是"看不见滑块线条"的根因】
##   HSlider 画轨道时，轨道的**高度**取自 `slider` 样式盒的最小尺寸，而样式盒的
##   最小尺寸由 content_margin 决定。旧实现用的是 `_slice("well_bg", 0.0)` /
##   `_flat()`，content_margin 全 0 → 最小高度 0 → 轨道宽高为 0，**什么都没画**。
##   玩家只看到把手（图标，不受样式盒厚度影响），于是"只有一个小方块、没有线"。
##   这里给上下各 PAD 的内边距，轨道就有确定厚度（= 2×PAD + 2px 边框）。
##   `grabber_area`（已填充段）用同样的内边距，才能和轨道严丝合缝对齐。
const SLIDER_TRACK_PAD := 3.0

func _slider_track(well: Color, border: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = well
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(0)
	box.content_margin_top = SLIDER_TRACK_PAD
	box.content_margin_bottom = SLIDER_TRACK_PAD
	box.content_margin_left = 0.0
	box.content_margin_right = 0.0
	return box


func _setup_slider(theme: Theme) -> void:
	for type_name: String in ["HSlider", "VSlider", "Slider"]:
		# 静态轨道：暗色凹槽 + 1px 描边，保证任何缩放下都看得见一条线。
		theme.set_stylebox("slider", type_name, _slider_track(C_WELL, C_BORDER))
		# 已填充段：暖色，让"当前音量"一眼可读。
		theme.set_stylebox("grabber_area", type_name, _slider_track(C_ACCENT.darkened(0.25), C_ACCENT))
		theme.set_stylebox("grabber_area_highlight", type_name, _slider_track(C_ACCENT, C_ACCENT_HI))
		theme.set_stylebox("grabber_area_disabled", type_name, _slider_track(C_OFF.darkened(0.4), C_OFF.darkened(0.2)))
	# 滑块把手用素材包图标（有描边的小方块），比纯色矩形更贴像素风。
	_set_icon_if_exists(theme, "HSlider", "grabber", "h_slidder_grabber")
	_set_icon_if_exists(theme, "HSlider", "grabber_highlight", "h_slidder_grabber_hover")
	_set_icon_if_exists(theme, "HSlider", "grabber_disabled", "h_slidder_grabber_disabled")
	_set_icon_if_exists(theme, "VSlider", "grabber", "v_slidder_grabber")
	_set_icon_if_exists(theme, "VSlider", "grabber_highlight", "v_slidder_grabber_hover")
	_set_icon_if_exists(theme, "VSlider", "grabber_disabled", "v_slidder_grabber_disabled")


func _setup_check_box(theme: Theme) -> void:
	for type_name: String in ["CheckBox", "CheckButton"]:
		theme.set_stylebox("normal", type_name, _empty())
		theme.set_stylebox("hover", type_name, _focus_ring())
		theme.set_stylebox("pressed", type_name, _empty())
		theme.set_stylebox("disabled", type_name, _empty())
		theme.set_stylebox("focus", type_name, _focus_ring())
		theme.set_color("font_color", type_name, C_TEXT)
		theme.set_color("font_hover_color", type_name, C_ACCENT_HI)
		theme.set_color("font_disabled_color", type_name, C_OFF)
		theme.set_font_size("font_size", type_name, FS_BODY)
		theme.set_constant("h_separation", type_name, 6)
		theme.set_constant("check_v_offset", type_name, 0)
	for state: String in ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]:
		_set_icon_if_exists(theme, "CheckBox", state, state)
		_set_icon_if_exists(theme, "CheckButton", state, state)


## 滚动条：细、暗、hover 时提亮。帮助面板的按键说明要靠它滚动，
## 必须显式给样式，否则会退回 Godot 内置灰皮。
func _setup_scroll(theme: Theme) -> void:
	var bg: StyleBoxFlat = _flat(Color8(0x0B, 0x0A, 0x10, 0xEE))
	bg.set_content_margin_all(0.0)
	var grab: StyleBoxFlat = _flat(Color8(0x3A, 0x33, 0x50))
	grab.set_content_margin_all(0.0)
	var grab_hl: StyleBoxFlat = _flat(C_ACCENT.darkened(0.15))
	grab_hl.set_content_margin_all(0.0)
	var grab_pr: StyleBoxFlat = _flat(C_ACCENT)
	grab_pr.set_content_margin_all(0.0)
	for type_name: String in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", type_name, bg)
		theme.set_stylebox("scroll_focus", type_name, _focus_ring())
		theme.set_stylebox("grabber", type_name, grab)
		theme.set_stylebox("grabber_highlight", type_name, grab_hl)
		theme.set_stylebox("grabber_pressed", type_name, grab_pr)
	# ScrollContainer 本体不画背景，避免和 PanelContainer 叠出双层边框。
	theme.set_stylebox("panel", "ScrollContainer", _empty())


func _setup_line_edit(theme: Theme) -> void:
	theme.set_stylebox("normal", "LineEdit", _slice("well_bg", 5.0))
	var focus: StyleBoxFlat = _flat(Color8(0x0E, 0x0C, 0x14))
	focus.border_color = C_ACCENT
	focus.set_border_width_all(1)
	focus.set_content_margin_all(5.0)
	theme.set_stylebox("focus", "LineEdit", focus)
	theme.set_stylebox("read_only", "LineEdit", _slice("well_bg", 5.0))
	theme.set_color("font_color", "LineEdit", C_TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", C_OFF)
	theme.set_color("caret_color", "LineEdit", C_ACCENT_HI)
	theme.set_color("selection_color", "LineEdit", Color8(0xE8, 0xA3, 0x3D, 0x66))
	theme.set_font_size("font_size", "LineEdit", FS_BODY)


## 容器的默认间距。之前各场景自己写 2/4/6 三种 separation，
## 节奏不统一是"看起来散"的一大来源；这里给主题级默认值收敛。
func _setup_containers(theme: Theme) -> void:
	theme.set_constant("separation", "VBoxContainer", 6)
	theme.set_constant("separation", "HBoxContainer", 6)
	# 分隔线：默认主题的 Separator 几乎不可见，给一条明确的弱描边色。
	var line: StyleBoxFlat = _flat(C_LINE)
	line.content_margin_top = 0.0
	line.content_margin_bottom = 0.0
	theme.set_stylebox("separator", "HSeparator", line)
	theme.set_constant("separation", "HSeparator", 1)
	theme.set_stylebox("separator", "VSeparator", line)
	theme.set_constant("separation", "VSeparator", 1)


# ============================================================================
# 类型变体（Godot 4 换肤文档推荐做法）
# ============================================================================

func _setup_variations(theme: Theme) -> void:
	_setup_text_variations(theme)
	_setup_button_variations(theme)
	_setup_bar_variations(theme)
	_setup_panel_variations(theme)
	_setup_dialogue_variations(theme)


## 对话系统专用变体（文本样式 / 紧凑按钮 / 不透明对话面板）。
##
## 【为什么对话的字号不另开档位、只另开颜色与行距】
##   用的是 12px 点阵字，**12 是它的设计尺寸**，非整数缩放会把汉字糊成一团；
##   而档位（HINT10 / BODY12 / HEADING14 / TITLE20）是整数倍关系，可以安全互用。
##   所以对话的"文本样式"只做三件事：换颜色、在既有档位里挑一档、单独调行距。
##
## 【为什么要给对话正文单独调 line_spacing】
##   主题默认行距 2 是给"一到两行的说明文字"配的；对话经常有 3 行以上，
##   2px 的行距会让整块看起来挤成一片、换行处读不出"这是新的一行"。
##   对话正文用 4，等于给每个汉字四周留白，扫读时眼睛有落点。
##
## 【为什么 Action 按钮要"紧凑"】
##   实测：按钮最小高度由"字体行高 + 上 4px + 下 4px"决定，参考 12px 字 = 24px。
##   而对话表头只有一行名字（16px）。24px 的按钮把整个表头行撑到 24px，
##   于是一句话的对话框里有 **一半高度** 是"名字 + 按钮"这一行 —— 这就是
##   "对话框过大"最直接的成因（实测 176×48 的条里有 24px 是表头）。
##   压到上下各 2px（高度 20）既保住九宫格的斜面与"按下下沉 1px"语义，
##   又把表头收窄 4px；配合自适应宽度，整体观感才回到"细条"。
func _setup_dialogue_variations(theme: Theme) -> void:
	# --- 对话文本样式：语义 -> Label 变体 ---
	theme.set_type_variation(&"DialogBodyLabel", &"Label")
	theme.set_font_size("font_size", "DialogBodyLabel", FS_BODY)
	theme.set_color("font_color", "DialogBodyLabel", C_TEXT)
	theme.set_constant("line_spacing", "DialogBodyLabel", 4)

	theme.set_type_variation(&"DialogEmphasisLabel", &"Label")
	theme.set_font_size("font_size", "DialogEmphasisLabel", FS_BODY)
	theme.set_color("font_color", "DialogEmphasisLabel", C_ACCENT_HI)
	theme.set_constant("line_spacing", "DialogEmphasisLabel", 4)

	theme.set_type_variation(&"DialogWhisperLabel", &"Label")
	theme.set_font_size("font_size", "DialogWhisperLabel", FS_HINT)
	theme.set_color("font_color", "DialogWhisperLabel", C_MUTED)
	theme.set_constant("line_spacing", "DialogWhisperLabel", 4)

	theme.set_type_variation(&"DialogShoutLabel", &"Label")
	theme.set_font_size("font_size", "DialogShoutLabel", FS_HEADING)
	theme.set_color("font_color", "DialogShoutLabel", C_ACCENT_HI)
	theme.set_constant("line_spacing", "DialogShoutLabel", 4)

	theme.set_type_variation(&"DialogSystemLabel", &"Label")
	theme.set_font_size("font_size", "DialogSystemLabel", FS_BODY)
	theme.set_color("font_color", "DialogSystemLabel", Color8(0x8F, 0xB6, 0xE8))
	theme.set_constant("line_spacing", "DialogSystemLabel", 4)

	# 说话人名字：同字号、只换色 —— 名字变大反而会把表头行撑高（见上面的【为什么】）。
	theme.set_type_variation(&"DialogSpeakerLabel", &"Label")
	theme.set_font_size("font_size", "DialogSpeakerLabel", FS_BODY)
	theme.set_color("font_color", "DialogSpeakerLabel", C_ACCENT)

	# --- 对话条专用的紧凑按钮 ---
	theme.set_type_variation(&"DialogActionButton", &"Button")
	theme.set_stylebox("normal", "DialogActionButton", _btn_padded("btn_normal", 0, 6.0))
	theme.set_stylebox("hover", "DialogActionButton", _btn_padded("btn_hover", 0, 6.0))
	theme.set_stylebox("pressed", "DialogActionButton", _btn_padded("btn_pressed", 1, 6.0))
	theme.set_stylebox("disabled", "DialogActionButton", _btn_padded("btn_disabled", 0, 6.0))
	theme.set_font_size("font_size", "DialogActionButton", FS_BODY)
	theme.set_constant("h_separation", "DialogActionButton", 4)

	# --- 对话面板：**不透明** ---
	# 【为什么要不透明】旧版面板是 0.9 透明度，背后的木墙竖纹会透出来，
	# 截图上一眼看去像是"对话框里有一块脏条纹"。90% 不透明在像素游戏里
	# 既不产生"透明玻璃"的美感，又把背景噪声留在了文字后面，得不偿失。
	theme.set_type_variation(&"DialogPanel", &"PanelContainer")
	theme.set_stylebox("panel", "DialogPanel", _dialog_box(C_ACCENT.darkened(0.25)))
	theme.set_type_variation(&"DialogNoticePanel", &"PanelContainer")
	theme.set_stylebox("panel", "DialogNoticePanel", _dialog_box(C_ACCENT_HI.darkened(0.1)))


## 对话面板样式：不透明底 + 1px 强调色描边 + 统一内边距。
func _dialog_box(border: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = _flat(C_DIALOG_BG)
	box.border_color = border
	box.set_border_width_all(1)
	box.content_margin_left = 6.0
	box.content_margin_right = 6.0
	box.content_margin_top = 4.0
	box.content_margin_bottom = 4.0
	return box


func _setup_text_variations(theme: Theme) -> void:
	theme.set_type_variation(&"TitleLabel", &"Label")
	theme.set_font_size("font_size", "TitleLabel", FS_TITLE)
	theme.set_color("font_color", "TitleLabel", C_ACCENT_HI)

	theme.set_type_variation(&"HeadingLabel", &"Label")
	theme.set_font_size("font_size", "HeadingLabel", FS_HEADING)
	theme.set_color("font_color", "HeadingLabel", C_ACCENT)

	## 强调色正文（说话人名字、需要高亮的关键词）。
	## 字号保持正文大小，只改颜色——想加大请用 HeadingLabel。
	theme.set_type_variation(&"AccentLabel", &"Label")
	theme.set_color("font_color", "AccentLabel", C_ACCENT)
	theme.set_font_size("font_size", "AccentLabel", FS_BODY)

	theme.set_type_variation(&"MutedLabel", &"Label")
	theme.set_color("font_color", "MutedLabel", C_MUTED)
	theme.set_font_size("font_size", "MutedLabel", FS_BODY)

	theme.set_type_variation(&"HintLabel", &"Label")
	theme.set_color("font_color", "HintLabel", C_MUTED)
	theme.set_font_size("font_size", "HintLabel", FS_HINT)

	theme.set_type_variation(&"ToastLabel", &"Label")
	theme.set_color("font_color", "ToastLabel", C_ACCENT_HI)
	theme.set_font_size("font_size", "ToastLabel", FS_BODY)

	theme.set_type_variation(&"DangerLabel", &"Label")
	theme.set_color("font_color", "DangerLabel", C_DANGER)

	theme.set_type_variation(&"OkLabel", &"Label")
	theme.set_color("font_color", "OkLabel", C_OK)


func _setup_button_variations(theme: Theme) -> void:
	# --- 主按钮：强调色填充，用于"开始冒险"这类主行动 ---
	# 层级的意义就在这里：一屏里只该有一个 PrimaryButton。
	theme.set_type_variation(&"PrimaryButton", &"Button")
	theme.set_stylebox("normal", "PrimaryButton", _btn("btn_primary_normal", 0))
	theme.set_stylebox("hover", "PrimaryButton", _btn("btn_primary_hover", 0))
	theme.set_stylebox("pressed", "PrimaryButton", _btn("btn_primary_pressed", 1))
	theme.set_stylebox("disabled", "PrimaryButton", _btn("btn_primary_disabled", 0))
	# 金底配深字（而不是白字），对比度才够。
	theme.set_color("font_color", "PrimaryButton", Color8(0x2A, 0x1E, 0x08))
	theme.set_color("font_hover_color", "PrimaryButton", Color8(0x1A, 0x12, 0x06))
	theme.set_color("font_pressed_color", "PrimaryButton", Color8(0x3A, 0x2A, 0x0C))
	theme.set_color("font_disabled_color", "PrimaryButton", Color8(0x6B, 0x5F, 0x4A))

	# --- 危险按钮：复用中性贴图 + modulate 染红，斜面语义自动继承 ---
	theme.set_type_variation(&"DangerButton", &"Button")
	var red: Color = Color(1.0, 0.42, 0.38)
	theme.set_stylebox("normal", "DangerButton", _btn_mod("btn_normal", 0, red))
	theme.set_stylebox("hover", "DangerButton", _btn_mod("btn_hover", 0, red))
	theme.set_stylebox("pressed", "DangerButton", _btn_mod("btn_pressed", 1, red))
	theme.set_stylebox("disabled", "DangerButton", _btn_mod("btn_disabled", 0, red))
	theme.set_color("font_color", "DangerButton", C_DANGER)
	theme.set_color("font_hover_color", "DangerButton", Color8(0xFF, 0x8A, 0x7C))
	theme.set_color("font_pressed_color", "DangerButton", Color8(0xFF, 0xD4, 0xCC))

	# --- 安静按钮：无填充，只在 hover/按下时显形。用于"取消/返回" ---
	theme.set_type_variation(&"QuietButton", &"Button")
	theme.set_stylebox("normal", "QuietButton", _empty())
	var q_hover: StyleBoxFlat = _flat(Color8(0x2A, 0x24, 0x38))
	q_hover.set_content_margin_all(4.0)
	q_hover.content_margin_left = 8.0
	q_hover.content_margin_right = 8.0
	var q_pressed: StyleBoxFlat = _flat(Color8(0x1A, 0x15, 0x24))
	q_pressed.border_color = C_ACCENT
	q_pressed.set_border_width_all(1)
	q_pressed.content_margin_left = 8.0
	q_pressed.content_margin_right = 8.0
	q_pressed.content_margin_top = 5.0    ## 同样下沉 1px
	q_pressed.content_margin_bottom = 3.0
	theme.set_stylebox("hover", "QuietButton", q_hover)
	theme.set_stylebox("pressed", "QuietButton", q_pressed)
	theme.set_stylebox("disabled", "QuietButton", _empty())
	theme.set_color("font_color", "QuietButton", C_MUTED)
	theme.set_color("font_hover_color", "QuietButton", C_TEXT)
	theme.set_color("font_pressed_color", "QuietButton", C_ACCENT_HI)
	theme.set_color("font_disabled_color", "QuietButton", C_OFF)

	# --- 卡片按钮：更大的内边距，用于三选一词条 ---
	theme.set_type_variation(&"CardButton", &"Button")
	theme.set_stylebox("normal", "CardButton", _btn_padded("btn_normal", 0, 8.0))
	theme.set_stylebox("hover", "CardButton", _btn_padded("btn_hover", 0, 8.0))
	theme.set_stylebox("pressed", "CardButton", _btn_padded("btn_pressed", 1, 8.0))
	theme.set_stylebox("disabled", "CardButton", _btn_padded("btn_disabled", 0, 8.0))
	theme.set_constant("h_separation", "CardButton", 8)


func _setup_bar_variations(theme: Theme) -> void:
	theme.set_type_variation(&"HealthBar", &"ProgressBar")
	theme.set_stylebox("background", "HealthBar", _slice("well_bg", 0.0))
	theme.set_stylebox("fill", "HealthBar", _flat(C_HP))

	theme.set_type_variation(&"ManaBar", &"ProgressBar")
	theme.set_stylebox("background", "ManaBar", _slice("well_bg", 0.0))
	theme.set_stylebox("fill", "ManaBar", _flat(C_MP))

	theme.set_type_variation(&"BossBar", &"ProgressBar")
	theme.set_stylebox("background", "BossBar", _slice("well_bg", 0.0))
	theme.set_stylebox("fill", "BossBar", _flat(Color8(0xB8, 0x2E, 0x22)))


func _setup_panel_variations(theme: Theme) -> void:
	# --- 卡片面板（背包格子、词条卡）---
	theme.set_type_variation(&"CardPanel", &"PanelContainer")
	var card: StyleBoxFlat = _flat(Color8(0x18, 0x15, 0x22, 0xF2))
	card.border_color = Color8(0x4A, 0x41, 0x66)
	card.set_border_width_all(1)
	card.set_content_margin_all(8.0)
	theme.set_stylebox("panel", "CardPanel", card)

	# --- 半透明遮罩（弹窗背后那层变暗）---
	theme.set_type_variation(&"Dimmer", &"ColorRect")
	theme.set_color("color", "Dimmer", C_DIM)


# ============================================================================
# 工具
# ============================================================================

func _flat(color: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(0)
	box.set_border_width_all(0)
	return box


func _empty() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


## 建九宫格样式：四角固定、中间（纯色）拉伸，因此任意尺寸都是硬边像素。
func _slice(tex_name: String, content_margin: float) -> StyleBox:
	var path: String = GEN % tex_name
	if not ResourceLoader.exists(path):
		return _flat(C_PANEL)
	var box: StyleBoxTexture = StyleBoxTexture.new()
	box.texture = load(path)
	box.set_texture_margin_all(SLICE_MARGIN)
	box.set_content_margin_all(content_margin)
	return box


## 带下沉位移的按钮样式（shift_down=1 时内容下移 1px）。
func _btn_padded(tex_name: String, shift_down: int, pad: float) -> StyleBoxTexture:
	var box: StyleBoxTexture = _btn(tex_name, shift_down)
	box.content_margin_left = pad
	box.content_margin_right = pad
	box.content_margin_top = pad - 4.0 + float(shift_down)
	box.content_margin_bottom = pad - 4.0 - float(shift_down)
	return box


## 染色版按钮：复用同一套九宫格贴图与斜面语义，只改颜色。
func _btn_mod(tex_name: String, shift_down: int, modulate: Color) -> StyleBoxTexture:
	var box: StyleBoxTexture = _btn(tex_name, shift_down)
	box.modulate_color = modulate
	return box


## 缺贴图时的兜底：包成 StyleBoxTexture 让调用方签名一致。
func _flat_fallback(color: Color) -> StyleBoxTexture:
	var box: StyleBoxTexture = StyleBoxTexture.new()
	box.content_margin_left = 8.0
	box.content_margin_right = 8.0
	box.content_margin_top = 4.0
	box.content_margin_bottom = 4.0
	box.modulate_color = color
	return box


func _set_icon_if_exists(theme: Theme, type_name: String, item: String, tex_name: String) -> void:
	var path: String = T % tex_name
	if ResourceLoader.exists(path):
		theme.set_icon(item, type_name, load(path))
