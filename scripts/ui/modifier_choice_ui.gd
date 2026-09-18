## ModifierChoiceUI —— Roguelite 三选一界面
##
## 【负责什么】
##   弹出三个词条卡片让玩家选一个。选完关闭并通知 ModifierSystem。
##   支持键盘（1/2/3）和鼠标点击。
##
## 【挂哪个节点】
##   scenes/ui/modifier_choice.tscn 的根节点（CanvasLayer）。
##   默认隐藏，收到 EventBus.modifier_choice_requested 时弹出。
##
## 【依赖谁】
##   ModifierData、ModifierSystem、EventBus。
##
## 【怎么扩展】
##   想改成"四选一"只改 @export 的 option_count；想加词条图标在卡片里加一个
##   TextureRect 即可。卡片布局由 _build_cards 统一生成，不手摆。
class_name ModifierChoiceUI
extends CanvasLayer

# ============================================================================
# @export
# ============================================================================

## 卡片容器（HBoxContainer）。
@export var card_container_path: NodePath
## 卡片场景（一个 PanelContainer + 标题 + 描述）。
@export var card_scene: PackedScene
## 背景遮罩节点（用于点击穿透控制）。
@export var dimmer_path: NodePath
## 弹出时是否暂停游戏。
@export var pause_game: bool = true
## 默认候选数量。
@export_range(1, 5, 1) var option_count: int = 3

# ============================================================================
# 常量
# ============================================================================

## 本窗口在 PauseManager 里的暂停令牌 id。
const PAUSE_OWNER: StringName = &"modifier_choice"

# ============================================================================
# 私有变量
# ============================================================================

var _card_container: HBoxContainer
var _dimmer: Control
## 当前候选词条。
var _candidates: Array[ModifierData] = []
## 是否正在展示（防止重复弹出）。
var _active: bool = false

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	# 关键：本界面弹出时会把 get_tree().paused 设为 true，
	# 而 Godot 只向 PROCESS_MODE_ALWAYS 的节点派发输入。不设这一行，
	# 暂停后本层收不到 gui_input/_unhandled_input → 卡片点不动、数字键也没反应
	# → 永久软锁，只能强退游戏。（GameOverUI 同样设了 ALWAYS。）
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not card_container_path.is_empty():
		_card_container = get_node_or_null(card_container_path) as HBoxContainer
	if not dimmer_path.is_empty():
		_dimmer = get_node_or_null(dimmer_path) as Control
	# 默认隐藏。
	visible = false
	# Esc 交给 UIInputRouter 仲裁（本窗口是阻塞型，且 Esc **不**用于关闭
	# ——三选一必须选一个，否则奖励就丢了。但必须吃掉 Esc，不让它开暂停菜单）。
	add_to_group(UIInputRouter.GROUP)
	# 登记进 UI 注册表：调用方按 id 访问，不再按树路径查名。
	UIRegistry.register(&"modifier_choice", self)
	EventBus.modifier_choice_requested.connect(_on_choice_requested)


# ============================================================================
# UIInputRouter 契约
# ============================================================================

func ui_layer_priority() -> int:
	return UIInputRouter.LAYER_MODIFIER_CHOICE


func is_blocking_ui() -> bool:
	return _active


func ui_window_id() -> StringName:
	return &"modifier_choice"


## 轮到本窗口处理 Esc。
##
## 【为什么不关】三选一是"清空房间"的一次性奖励，关掉就等于把奖励弄丢。
##   返回 true 只是**吃掉**这次的 Esc，不让它穿透去弹暂停菜单。
func route_esc() -> bool:
	return _active


## 强制收起（回主菜单 / 换局时由 GameFlow 调用）。
##
## 【为什么必须交还暂停令牌】本界面弹出时 freeze 过。只把界面藏起来而留着令牌，
##   在"回主菜单"路径上靠 PauseManager.clear_all() 兜住了，但任何其它强制收起
##   路径都会导致令牌泄漏、游戏永久暂停。收尾必须与 freeze 对偶。
func force_close() -> void:
	visible = false
	_active = false
	if pause_game:
		PauseManager.unfreeze(PAUSE_OWNER)


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	# 数字键 1/2/3 快速选择（复用已有的输入映射，不再新增按键）。
	for i: int in _candidates.size():
		if i == 0 and event.is_action_pressed(&"ability_1"):
			_choose(i)
			get_viewport().set_input_as_handled()
			return
		if i == 1 and event.is_action_pressed(&"ability_2"):
			_choose(i)
			get_viewport().set_input_as_handled()
			return
		if i == 2 and event.is_action_pressed(&"spell_3"):
			_choose(i)
			get_viewport().set_input_as_handled()
			return


# ============================================================================
# 公开方法
# ============================================================================

## 手动弹出三选一（不依赖事件）。
func show_choices(candidates: Array[ModifierData]) -> void:
	if _active or candidates.is_empty():
		return
	_candidates = candidates
	_active = true
	_build_cards()
	visible = true
	if pause_game:
		PauseManager.freeze(PAUSE_OWNER)


# ============================================================================
# 私有方法
# ============================================================================

## 构建卡片。
func _build_cards() -> void:
	if _card_container == null:
		return
	for child: Node in _card_container.get_children():
		child.queue_free()
	for i: int in _candidates.size():
		var mod: ModifierData = _candidates[i]
		var card: Control = _create_card(mod, i)
		_card_container.add_child(card)


## 创建一张词条卡片。
func _create_card(mod: ModifierData, index: int) -> Control:
	# 如果配了卡片场景就用它，否则用代码搭一个最小卡片，保证一定能跑。
	var card: Control
	if card_scene != null:
		card = card_scene.instantiate() as Control
	else:
		card = _make_default_card()
	# 用 find_child(recursive=true) 而不是 get_node("Title")：卡片结构可能是
	# "Panel > VBox > Title" 这样的嵌套，固定路径会在换布局时直接失效。
	var title: Label = card.find_child("Title", true, false) as Label
	var desc: Label = card.find_child("Desc", true, false) as Label
	var icon: TextureRect = card.find_child("Icon", true, false) as TextureRect
	if title != null:
		title.text = "%d. %s" % [index + 1, mod.display_name]
		# 稀有度用颜色表达，玩家一眼分辨价值。
		title.add_theme_color_override("font_color", mod.get_rarity_color())
	if desc != null:
		desc.text = mod.description
	if icon != null and mod.icon != null:
		icon.texture = mod.icon
	# 点击选择。PanelContainer 默认会吃掉鼠标事件，这里显式监听它。
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(_on_card_gui_input.bind(index))
	return card


## 代码生成默认卡片（没有配 card_scene 时的兜底）。
func _make_default_card() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(84, 62)
	var vbox: VBoxContainer = VBoxContainer.new()
	panel.add_child(vbox)
	var title: Label = Label.new()
	title.name = "Title"
	title.add_theme_font_size_override("font_size", 9)
	vbox.add_child(title)
	var icon: TextureRect = TextureRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(16, 16)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vbox.add_child(icon)
	var desc: Label = Label.new()
	desc.name = "Desc"
	desc.add_theme_font_size_override("font_size", 7)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(78, 0)
	vbox.add_child(desc)
	return panel


## 选择第 index 个词条。
func _choose(index: int) -> void:
	if index < 0 or index >= _candidates.size():
		return
	var picked: ModifierData = _candidates[index]
	ModifierSystem.add_modifier(picked)
	_close()
	EventBus.toast_requested.emit("获得词条：%s" % picked.display_name)


## 关闭界面并恢复游戏。
func _close() -> void:
	_active = false
	visible = false
	_candidates.clear()
	if pause_game:
		PauseManager.unfreeze(PAUSE_OWNER)
	if _card_container != null:
		for child: Node in _card_container.get_children():
			child.queue_free()


# ============================================================================
# 信号回调
# ============================================================================

func _on_choice_requested(candidates: Array[ModifierData]) -> void:
	show_choices(candidates)


## 卡片被点击。
func _on_card_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_choose(index)
