## GenerateUIScenes —— 生成全部 UI 场景（编辑器工具脚本）
##
## 【负责什么】
##   生成主菜单、暂停菜单、设置、操作说明、教程提示、Boss 血条、背包、结算界面。
##   UI 布局用代码搭，保证锚点/边距一致，且改一次全局生效。
##
## 【怎么运行】
##   Godot --headless --path . res://tools/generate_ui_scenes.tscn
extends Node

# ============================================================================
# 常量
# ============================================================================

const THEME := "res://resources/ui_theme.tres"
const S := "res://scripts/ui/%s.gd"

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("res://scenes/ui")
	_make_help_panel()
	_make_settings_panel()
	_make_main_menu()
	_make_pause_menu()
	_make_tutorial_ui()
	_make_boss_health_bar()
	_make_inventory_ui()
	_make_game_over()
	_make_floating_text()
	_make_hud()
	_make_modifier_choice()
	print("[GenerateUIScenes] UI 场景生成完毕")
	get_tree().quit()


# ============================================================================
# 生成
# ============================================================================

## 操作说明面板。
func _make_help_panel() -> void:
	var root: CanvasLayer = _new_canvas("HelpPanel", S % "help_panel", 60)
	root.set("panel_path", NodePath("Root/Panel"))
	root.set("label_path", NodePath("Root/Panel/Margin/VBox/Text"))
	root.set("close_button_path", NodePath("Root/Panel/Margin/VBox/Close"))

	_canvas_root(root).add_child(_make_dimmer())

	var panel: PanelContainer = PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(272, 150)
	panel.position = Vector2(-136, -75)
	_canvas_root(root).add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)

	# PanelContainer 会把子节点拉伸填满，所以必须用 VBox 管理纵向排布，
	# 并让文本区占满剩余空间、按钮保持自然高度，否则按钮会被拉成整屏。
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	var text: RichTextLabel = RichTextLabel.new()
	text.name = "Text"
	text.bbcode_enabled = true
	text.scroll_active = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 8)
	text.add_theme_font_size_override("bold_font_size", 8)
	vbox.add_child(text)

	var close: Button = Button.new()
	close.name = "Close"
	close.text = "关闭"
	close.custom_minimum_size = Vector2(60, 13)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(close)

	_save(root, "res://scenes/ui/help_panel.tscn")


## 设置面板。
##
## 【为什么三行音量统一用 0..1 线性值，而不是 -40..6 分贝】
##   分贝对玩家没有意义，且 -40dB→+6dB 的听感变化不是线性的（-40 那半段几乎听不出
##   差别）。0..1 线性值再 `linear_to_db()` 才是常见做法；也方便旁边直接显示百分比。
func _make_settings_panel() -> void:
	var root: CanvasLayer = _new_canvas("SettingsPanel", S % "settings_panel", 60)
	var croot: Control = _canvas_root(root)
	# 节点路径是脚本 @export 的契约，改名要同步改 settings_panel.gd。
	croot.name = "Root"
	croot.add_child(_make_dimmer())

	# 面板：锚定屏幕中心、offset 全 0、grow 双向 —— 按自身最小尺寸**对称向两侧生长**，
	# 于是内容怎么变都居中（写死 offsets 会因高度变化而偏移或溢出）。
	# 面板仍是 Root 的直接子节点，脚本里的 "Root/Panel/..." 路径不变。
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = 0.0
	panel.offset_top = 0.0
	panel.offset_right = 0.0
	panel.offset_bottom = 0.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(208, 0)
	croot.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 3)
	margin.add_child(vbox)

	var title: Label = Label.new()
	title.name = "Title"
	title.text = "设置"
	title.custom_minimum_size = Vector2(0, 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color8(0xE8, 0xA3, 0x3D))
	vbox.add_child(title)

	# 音量区（三行）。
	vbox.add_child(_make_slider_row_full("Master", "主音量"))
	vbox.add_child(_make_slider_row_full("Sfx", "音效"))
	vbox.add_child(_make_slider_row_full("Music", "音乐"))

	# 分隔。
	var sep: HSeparator = HSeparator.new()
	sep.name = "Sep"
	vbox.add_child(sep)

	# 显示区（全屏开关）。
	vbox.add_child(_make_toggle_row("Fullscreen", "全屏"))

	# 按钮：返回（左）/ 确定（右）。
	var actions: HBoxContainer = HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", 8)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(actions)

	var back: Button = Button.new()
	back.name = "btn_back"
	back.text = "返回"
	back.custom_minimum_size = Vector2(72, 22)
	back.theme_type_variation = &"QuietButton"
	actions.add_child(back)

	var close: Button = Button.new()
	close.name = "btn_confirm"
	close.text = "确定"
	close.custom_minimum_size = Vector2(72, 22)
	close.theme_type_variation = &"PrimaryButton"
	actions.add_child(close)

	# 脚本 @export 契约：主音量/音效/音乐滑块 + 关闭按钮 + 全屏开关。
	root.set("panel_path", NodePath("Root/Panel"))
	root.set("master_slider_path", NodePath("Root/Panel/Margin/VBox/MasterRow/Master"))
	root.set("sfx_slider_path", NodePath("Root/Panel/Margin/VBox/SfxRow/Sfx"))
	root.set("music_slider_path", NodePath("Root/Panel/Margin/VBox/MusicRow/Music"))
	root.set("close_button_path", NodePath("Root/Panel/Margin/VBox/Actions/btn_confirm"))
	root.set("back_button_path", NodePath("Root/Panel/Margin/VBox/Actions/btn_back"))
	root.set("fullscreen_path", NodePath("Root/Panel/Margin/VBox/FullscreenRow/Fullscreen"))

	_save(root, "res://scenes/ui/settings_panel.tscn")


## 主菜单。
func _make_main_menu() -> void:
	var root: Control = _new_control("MainMenu", S % "main_menu")
	root.set("help_panel_scene", load("res://scenes/ui/help_panel.tscn"))
	root.set("settings_panel_scene", load("res://scenes/ui/settings_panel.tscn"))

	var bg: ColorRect = ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.055, 0.055, 0.078)
	root.add_child(bg)

	var title: Label = Label.new()
	title.name = "Title"
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-60, 14)
	title.custom_minimum_size = Vector2(120, 0)
	title.text = "ActRPG"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	var sub: Label = Label.new()
	sub.name = "Subtitle"
	sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sub.position = Vector2(-100, 42)
	sub.custom_minimum_size = Vector2(200, 0)
	sub.text = "2D 俯视动作 ARPG 原型"
	sub.add_theme_font_size_override("font_size", 8)
	sub.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(sub)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.name = "Menu"
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.position = Vector2(-40, -18)
	vbox.custom_minimum_size = Vector2(80, 0)
	vbox.add_theme_constant_override("separation", 3)
	root.add_child(vbox)

	vbox.add_child(_make_button("btn_new_game", "新的冒险"))
	vbox.add_child(_make_button("btn_continue", "继续游戏"))
	vbox.add_child(_make_button("btn_help", "操作说明"))
	vbox.add_child(_make_button("btn_settings", "设置"))
	vbox.add_child(_make_button("btn_quit", "退出"))

	_save(root, "res://scenes/ui/main_menu.tscn")


## 暂停菜单。
func _make_pause_menu() -> void:
	var root: CanvasLayer = _new_canvas("PauseMenu", S % "pause_menu", 40)
	root.set("help_panel_scene", load("res://scenes/ui/help_panel.tscn"))
	root.set("settings_panel_scene", load("res://scenes/ui/settings_panel.tscn"))
	root.set("main_menu_scene", load("res://scenes/ui/main_menu.tscn"))

	_canvas_root(root).add_child(_make_dimmer())

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.name = "Menu"
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.position = Vector2(-40, -40)
	vbox.custom_minimum_size = Vector2(80, 0)
	vbox.add_theme_constant_override("separation", 3)
	_canvas_root(root).add_child(vbox)

	var title: Label = Label.new()
	title.name = "Title"
	title.text = "已暂停"
	title.add_theme_font_size_override("font_size", 14)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(_make_button("btn_resume", "继续"))
	vbox.add_child(_make_button("btn_help", "操作说明"))
	vbox.add_child(_make_button("btn_settings", "设置"))
	vbox.add_child(_make_button("btn_main_menu", "返回主菜单"))
	vbox.add_child(_make_button("btn_quit", "退出游戏"))

	_save(root, "res://scenes/ui/pause_menu.tscn")


## 教程提示。
##
## 【必须和 scenes/ui/tutorial_ui.tscn 的实际结构保持一致】
##   本函数是那个场景的来源。曾经这里生成的是**没有关闭按钮**的旧结构，
##   而磁盘上的场景被手改加了 ✕，两边漂移 —— 一跑生成器，✕ 就被抹掉，
##   教程又变回"关不掉"。现在以本函数为准，改结构请改这里再重新生成。
func _make_tutorial_ui() -> void:
	var root: CanvasLayer = _new_canvas("TutorialUI", S % "tutorial_ui", 30)
	root.set("panel_path", NodePath("Root/Panel"))
	root.set("title_label_path", NodePath("Root/Panel/Margin/VBox/Header/Title"))
	root.set("label_path", NodePath("Root/Panel/Margin/VBox/Body/Text"))
	root.set("icon_path", NodePath("Root/Panel/Margin/VBox/Header/Icon"))
	root.set("hint_path", NodePath("Root/Panel/Margin/VBox/Header/Hint"))
	root.set("close_button_path", NodePath("Root/Panel/Margin/VBox/Header/Close"))
	root.set("dismiss_area_path", NodePath("Root/Panel"))

	var panel: PanelContainer = PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.position = Vector2(-130, 12)
	panel.custom_minimum_size = Vector2(260, 0)
	_canvas_root(root).add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)

	# 头部一行：图标 / 标题 / 按键提示 / 关闭按钮。
	var header: HBoxContainer = HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 6)
	vbox.add_child(header)

	var icon: TextureRect = TextureRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(14, 14)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(icon)

	var title: Label = Label.new()
	title.name = "Title"
	title.visible = false
	title.custom_minimum_size = Vector2(0, 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.theme_type_variation = &"HeadingLabel"
	header.add_child(title)

	var hint: Label = Label.new()
	hint.name = "Hint"
	hint.visible = false
	hint.text = "[F] 继续"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.theme_type_variation = &"HintLabel"
	header.add_child(hint)

	# 关闭按钮：× 用程序生成的贴图，不用文字 "✕"
	# ——像素字体里没有 U+2715 这个字形，会渲染成豆腐块。
	var close_btn: Button = Button.new()
	close_btn.name = "Close"
	close_btn.custom_minimum_size = Vector2(20, 24)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_btn.tooltip_text = "关闭教程"
	close_btn.icon = _load_close_icon()
	close_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(close_btn)

	# 正文一行。
	var body: HBoxContainer = HBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 4)
	vbox.add_child(body)

	var text: Label = Label.new()
	text.name = "Text"
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(220, 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(text)

	_save(root, "res://scenes/ui/tutorial_ui.tscn")


## 载入程序生成的 × 图标（generate_ui_skin 产出）。
## 文件不存在时返回 null 而不是让整轮生成失败——按钮退化成无图标，
## 至少结构还在，跑一次 generate_ui_skin 就能补上。
func _load_close_icon() -> Texture2D:
	var path := "res://assets/sprites/ui/theme/gen/icon_close.png"
	if not ResourceLoader.exists(path):
		push_warning("[GenerateUIScenes] 缺少 %s，请先跑 generate_ui_skin" % path)
		return null
	return load(path) as Texture2D


## Boss 血条。
func _make_boss_health_bar() -> void:
	var root: CanvasLayer = _new_canvas("BossHealthBar", S % "boss_health_bar", 20)
	root.set("container_path", NodePath("Root"))
	root.set("name_path", NodePath("Root/Name"))
	root.set("bar_path", NodePath("Root/Bar"))

	var container: Control = Control.new()
	container.name = "Root"
	container.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	container.position = Vector2(-100, -26)
	container.custom_minimum_size = Vector2(200, 0)
	_canvas_root(root).add_child(container)

	var name_label: Label = Label.new()
	name_label.name = "Name"
	name_label.custom_minimum_size = Vector2(200, 0)
	name_label.text = "Boss"
	name_label.add_theme_font_size_override("font_size", 9)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(name_label)

	var bar: ProgressBar = ProgressBar.new()
	bar.name = "Bar"
	bar.custom_minimum_size = Vector2(200, 8)
	bar.position = Vector2(0, 12)
	bar.max_value = 100.0
	bar.value = 100.0
	bar.show_percentage = false
	container.add_child(bar)

	_save(root, "res://scenes/ui/boss_health_bar.tscn")


## 背包 / 装备栏。
func _make_inventory_ui() -> void:
	var root: CanvasLayer = _new_canvas("InventoryUI", S % "inventory_ui", 40)
	root.set("panel_path", NodePath("Root/Panel"))
	root.set("grid_path", NodePath("Root/Panel/Margin/VBox/Grid"))
	root.set("weapon_icon_path", NodePath("Root/Panel/Margin/VBox/EquipRow/WeaponIcon"))
	root.set("gold_label_path", NodePath("Root/Panel/Margin/VBox/Gold"))

	_canvas_root(root).add_child(_make_dimmer())

	var panel: PanelContainer = PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-110, -70)
	panel.custom_minimum_size = Vector2(220, 140)
	_canvas_root(root).add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	var title: Label = Label.new()
	title.name = "Title"
	title.text = "背包与装备"
	title.add_theme_font_size_override("font_size", 11)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var equip: HBoxContainer = HBoxContainer.new()
	equip.name = "EquipRow"
	equip.add_theme_constant_override("separation", 4)
	vbox.add_child(equip)
	var equip_label: Label = Label.new()
	equip_label.text = "武器："
	equip_label.add_theme_font_size_override("font_size", 8)
	equip.add_child(equip_label)
	var weapon_icon: TextureRect = TextureRect.new()
	weapon_icon.name = "WeaponIcon"
	weapon_icon.custom_minimum_size = Vector2(16, 16)
	weapon_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	equip.add_child(weapon_icon)

	var gold: Label = Label.new()
	gold.name = "Gold"
	gold.text = "金币：0"
	gold.add_theme_font_size_override("font_size", 8)
	vbox.add_child(gold)

	var grid: GridContainer = GridContainer.new()
	grid.name = "Grid"
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	vbox.add_child(grid)

	var hint: Label = Label.new()
	hint.name = "Hint"
	hint.text = "点击消耗品使用　·　Tab/I 关闭"
	hint.add_theme_font_size_override("font_size", 6)
	hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
	vbox.add_child(hint)

	_save(root, "res://scenes/ui/inventory_ui.tscn")


## 死亡 / 胜利结算。
func _make_game_over() -> void:
	var root: CanvasLayer = _new_canvas("GameOverUI", S % "game_over_ui", 55)
	root.set("title_path", NodePath("Root/Title"))
	root.set("body_path", NodePath("Root/Body"))
	root.set("main_menu_scene", load("res://scenes/ui/main_menu.tscn"))

	_canvas_root(root).add_child(_make_dimmer())

	var title: Label = Label.new()
	title.name = "Title"
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.position = Vector2(-80, -50)
	title.custom_minimum_size = Vector2(160, 0)
	title.add_theme_font_size_override("font_size", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_canvas_root(root).add_child(title)

	var body: Label = Label.new()
	body.name = "Body"
	body.set_anchors_preset(Control.PRESET_CENTER)
	body.position = Vector2(-90, -22)
	body.custom_minimum_size = Vector2(180, 0)
	body.add_theme_font_size_override("font_size", 8)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_canvas_root(root).add_child(body)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.name = "Buttons"
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.position = Vector2(-40, 20)
	vbox.custom_minimum_size = Vector2(80, 0)
	vbox.add_theme_constant_override("separation", 3)
	_canvas_root(root).add_child(vbox)
	vbox.add_child(_make_button("btn_respawn", "从存档点复活"))
	vbox.add_child(_make_button("btn_main_menu", "返回主菜单"))

	_save(root, "res://scenes/ui/game_over.tscn")


## 伤害飘字（Node2D，不是 CanvasLayer）。
func _make_floating_text() -> void:
	var root: Node2D = Node2D.new()
	root.name = "FloatingText"
	root.set_script(load(S % "floating_text"))
	var label: Label = Label.new()
	label.name = "Label"
	label.offset_left = -40.0
	label.offset_top = -8.0
	label.offset_right = 40.0
	label.offset_bottom = 8.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	root.add_child(label)
	_save(root, "res://scenes/ui/floating_text.tscn")


## 主 HUD：血/蓝条 + 技能栏 + 提示。
func _make_hud() -> void:
	var canvas: CanvasLayer = _new_canvas("HUD", S % "hud", 10)
	canvas.set("health_bar_path", NodePath("Root/Stats/HealthBar"))
	canvas.set("mana_bar_path", NodePath("Root/Stats/ManaBar"))
	canvas.set("skill_bar_path", NodePath("Root/SkillBar"))
	canvas.set("floating_text_scene", load("res://scenes/ui/floating_text.tscn"))
	canvas.set("toast_label_path", NodePath("Root/Toast"))
	var root: Control = _canvas_root(canvas)

	var stats: VBoxContainer = VBoxContainer.new()
	stats.name = "Stats"
	stats.position = Vector2(4, 4)
	stats.add_theme_constant_override("separation", 1)
	root.add_child(stats)

	var hp: ProgressBar = ProgressBar.new()
	hp.name = "HealthBar"
	hp.custom_minimum_size = Vector2(78, 8)
	hp.max_value = 100.0
	hp.value = 100.0
	hp.show_percentage = false
	# 底槽与填充必须用不同颜色，否则血条永远看起来是满的（背景=填充色）。
	# 底槽用近黑的暗红，填充用亮红，掉血时能明显看出缺口。
	var hp_bg: StyleBoxFlat = StyleBoxFlat.new()
	hp_bg.bg_color = Color(0.13, 0.06, 0.08)
	hp_bg.border_color = Color(0.05, 0.04, 0.05)
	hp_bg.set_border_width_all(1)
	var hp_fill: StyleBoxFlat = StyleBoxFlat.new()
	hp_fill.bg_color = Color(0.85, 0.22, 0.22)
	hp.add_theme_stylebox_override("background", hp_bg)
	hp.add_theme_stylebox_override("fill", hp_fill)
	stats.add_child(hp)

	var mp: ProgressBar = ProgressBar.new()
	mp.name = "ManaBar"
	mp.custom_minimum_size = Vector2(78, 6)
	mp.max_value = 60.0
	mp.value = 60.0
	mp.show_percentage = false
	# 蓝条同理：暗底 + 亮蓝填充。
	var mp_bg: StyleBoxFlat = StyleBoxFlat.new()
	mp_bg.bg_color = Color(0.06, 0.1, 0.2)
	mp_bg.border_color = Color(0.05, 0.04, 0.05)
	mp_bg.set_border_width_all(1)
	var mp_fill: StyleBoxFlat = StyleBoxFlat.new()
	mp_fill.bg_color = Color(0.32, 0.55, 0.95)
	mp.add_theme_stylebox_override("background", mp_bg)
	mp.add_theme_stylebox_override("fill", mp_fill)
	stats.add_child(mp)

	var skill_bar: HBoxContainer = HBoxContainer.new()
	skill_bar.name = "SkillBar"
	skill_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	skill_bar.position = Vector2(-50, -22)
	skill_bar.custom_minimum_size = Vector2(100, 0)
	skill_bar.add_theme_constant_override("separation", 2)
	root.add_child(skill_bar)

	var toast: Label = Label.new()
	toast.name = "Toast"
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.position = Vector2(-100, 40)
	toast.custom_minimum_size = Vector2(200, 0)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_font_size_override("font_size", 10)
	toast.add_theme_color_override("font_color", Color(1, 0.95, 0.6))
	root.add_child(toast)

	_save(canvas, "res://scenes/ui/hud.tscn")


## 三选一词条界面。
func _make_modifier_choice() -> void:
	var canvas: CanvasLayer = _new_canvas("ModifierChoice", S % "modifier_choice_ui", 50)
	canvas.set("card_container_path", NodePath("Root/Cards"))
	canvas.set("dimmer_path", NodePath("Root/Dimmer"))
	var root: Control = _canvas_root(canvas)

	root.add_child(_make_dimmer())

	var title: Label = Label.new()
	title.name = "Title"
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-80, 16)
	title.custom_minimum_size = Vector2(160, 0)
	title.text = "选择你的强化"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(1, 0.95, 0.75))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	var cards: HBoxContainer = HBoxContainer.new()
	cards.name = "Cards"
	cards.set_anchors_preset(Control.PRESET_CENTER)
	cards.position = Vector2(-135, -35)
	cards.custom_minimum_size = Vector2(270, 70)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 8)
	root.add_child(cards)

	_save(canvas, "res://scenes/ui/modifier_choice.tscn")


# ============================================================================
# 工具
# ============================================================================

## 创建 CanvasLayer 场景根，并返回一个"容器"用于挂 UI 子节点。
## 注意：所有 UI 子节点必须挂在内部 Root(Control) 下——脚本里的 NodePath 都写成
## "Root/..." 形式，直接挂 CanvasLayer 会导致路径找不到节点。
func _new_canvas(node_name: String, script_path: String, layer_index: int) -> CanvasLayer:
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.name = node_name
	canvas.layer = layer_index
	canvas.set_script(load(script_path))
	var control: Control = Control.new()
	control.name = "Root"
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(control)
	_apply_theme_to(canvas)
	return canvas


## 取 CanvasLayer 的内部 Root 容器，用于挂子节点。
func _canvas_root(canvas: CanvasLayer) -> Control:
	return canvas.get_node("Root") as Control


func _new_control(node_name: String, script_path: String) -> Control:
	var root: Control = Control.new()
	root.name = node_name
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.set_script(load(script_path))
	_apply_theme_to(root)
	return root


## 只对 Control 设主题。CanvasLayer 没有 theme 属性，设了会报 Nil 错误。
## 对 CanvasLayer 场景，主题设在它的内部 Root(Control) 上。
func _apply_theme_to(node: Node) -> void:
	if not ResourceLoader.exists(THEME):
		return
	if node is Control:
		(node as Control).theme = load(THEME)
	elif node is CanvasLayer:
		var root: Node = node.get_node_or_null("Root")
		if root is Control:
			(root as Control).theme = load(THEME)


func _make_dimmer() -> ColorRect:
	var dim: ColorRect = ColorRect.new()
	dim.name = "Dimmer"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.65)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	return dim


func _make_button(btn_name: String, text: String) -> Button:
	var btn: Button = Button.new()
	btn.name = btn_name
	btn.text = text
	btn.custom_minimum_size = Vector2(80, 13)
	btn.add_theme_font_size_override("font_size", 8)
	return btn


func _make_slider_row(slider_name: String, label_text: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var label: Label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(48, 0)
	label.add_theme_font_size_override("font_size", 8)
	row.add_child(label)
	var slider: HSlider = HSlider.new()
	slider.name = slider_name
	slider.min_value = -40.0
	slider.max_value = 6.0
	slider.step = 1.0
	slider.custom_minimum_size = Vector2(80, 10)
	row.add_child(slider)
	return row


## 单行"标签 + 滑块(占满) + 数值"。
##
## 【为什么用固定宽度的标签/数值列】三行必须左对齐成一列，否则中文标签宽度不一，
##   滑块起点参差不齐，看起来像没排版。标签列与数值列都给定宽，中间滑块 expand。
func _make_slider_row_full(node_name: String, label_text: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = node_name + "Row"
	row.add_theme_constant_override("separation", 6)

	var label: Label = Label.new()
	label.name = "Label"
	label.text = label_text
	label.custom_minimum_size = Vector2(46, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	row.add_child(label)

	var slider: HSlider = HSlider.new()
	slider.name = node_name
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = 1.0
	slider.custom_minimum_size = Vector2(72, 12)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)

	var value_label: Label = Label.new()
	value_label.name = "Value"
	value_label.text = "100%"
	value_label.custom_minimum_size = Vector2(28, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", 10)
	value_label.add_theme_color_override("font_color", Color8(0xE8, 0xA3, 0x3D))
	row.add_child(value_label)
	return row


## 单行"标签 + 复选框/开关"。
func _make_toggle_row(node_name: String, label_text: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = node_name + "Row"
	row.add_theme_constant_override("separation", 6)

	var label: Label = Label.new()
	label.name = "Label"
	label.text = label_text
	label.custom_minimum_size = Vector2(46, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	row.add_child(label)

	var check: CheckButton = CheckButton.new()
	check.name = node_name
	check.text = ""
	check.custom_minimum_size = Vector2(0, 14)
	check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(check)
	return row


func _save(root: Node, path: String) -> void:
	_set_owner_recursive(root, root)
	var packed: PackedScene = PackedScene.new()
	var err: int = packed.pack(root)
	if err != OK:
		push_error("[GenerateUIScenes] pack 失败 %s：%d" % [path, err])
		root.queue_free()
		return
	ResourceSaver.save(packed, path)
	root.queue_free()


func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner_node
		_set_owner_recursive(child, owner_node)
