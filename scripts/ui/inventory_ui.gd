## InventoryUI —— 背包 / 装备栏
##
## 【负责什么】
##   显示背包物品（图标 + 数量），可点击消耗品使用。装备栏显示当前武器。
##   Tab / I 开关，打开时暂停游戏。
##
## 【挂哪个节点】
##   scenes/ui/inventory_ui.tscn 的根节点（CanvasLayer），由 Boot 常驻挂载。
##
## 【依赖谁】
##   GameState（背包数据）、PlayerCombat（装备）。
class_name InventoryUI
extends CanvasLayer

# ============================================================================
# @export
# ============================================================================

## 面板容器。
@export var panel_path: NodePath
## 物品网格（GridContainer）。
@export var grid_path: NodePath
## 装备栏武器图标。
@export var weapon_icon_path: NodePath
## 金币标签。
@export var gold_label_path: NodePath
## 物品格子场景（可选）。留空则代码生成。
@export var slot_scene: PackedScene

# ============================================================================
# 私有变量
# ============================================================================

var _panel: Control
var _grid: GridContainer
var _weapon_icon: TextureRect
var _gold_label: Label
## 全屏遮罩。必须和面板一起显示/隐藏，否则关掉背包后画面仍被压暗。
var _dimmer: Control
var _is_open: bool = false

# ============================================================================
# 常量
# ============================================================================

## 本窗口在 PauseManager 里的暂停令牌 id。
const PAUSE_OWNER: StringName = &"inventory"

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not panel_path.is_empty():
		_panel = get_node_or_null(panel_path) as Control
	if not grid_path.is_empty():
		_grid = get_node_or_null(grid_path) as GridContainer
	if not weapon_icon_path.is_empty():
		_weapon_icon = get_node_or_null(weapon_icon_path) as TextureRect
	if not gold_label_path.is_empty():
		_gold_label = get_node_or_null(gold_label_path) as Label
	_dimmer = get_node_or_null("Root/Dimmer") as Control
	if _panel != null:
		_panel.visible = false
	if _dimmer != null:
		_dimmer.visible = false
	# Esc 交给 UIInputRouter 仲裁（背包层级最低，只在没有别的阻塞窗口时才轮到）。
	add_to_group(UIInputRouter.GROUP)
	# 登记进 UI 注册表：调用方按 id 访问，不再按树路径查名。
	UIRegistry.register(&"inventory", self)
	EventBus.item_acquired.connect(func(_id: StringName, _n: int) -> void: _refresh())


# ============================================================================
# UIInputRouter 契约
# ============================================================================

func ui_layer_priority() -> int:
	return UIInputRouter.LAYER_INVENTORY


func is_blocking_ui() -> bool:
	return _is_open


func ui_window_id() -> StringName:
	return &"inventory"


## 轮到本窗口处理 Esc：关背包。
func route_esc() -> bool:
	if not _is_open:
		return false
	close()
	return true


## 回主菜单时强制收起。
func force_close() -> void:
	close()


func _unhandled_input(event: InputEvent) -> void:
	# Tab / I 开合背包。Esc 由路由器处理（仍在 _is_open 时会被优先派给背包）。
	if not event.is_action_pressed(&"inventory"):
		return
	toggle()
	get_viewport().set_input_as_handled()


# ============================================================================
# 公开方法
# ============================================================================

func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


func open() -> void:
	_is_open = true
	if _panel != null:
		_panel.visible = true
	if _dimmer != null:
		_dimmer.visible = true
	_freeze_game()
	_refresh()


func close() -> void:
	_is_open = false
	if _panel != null:
		_panel.visible = false
	if _dimmer != null:
		_dimmer.visible = false
	_unfreeze_game()


# ============================================================================
# 私有方法 —— 暂停状态
# ============================================================================

## 冻结游戏。走 PauseManager 令牌（不再自己记 _paused_by_me）。
##
## 【为什么不能裸写 paused = true / false】
##   背包可以叠在暂停菜单之上打开（Esc 开菜单 → I 开背包）。旧写法无条件
##   `paused = false` 会**连带把暂停菜单底下的游戏一起放跑** ——
##   玩家可以顶着暂停菜单在 Boss 战里自由行动。
##   令牌模型下，暂停菜单还持有令牌，游戏就仍然是停的。
func _freeze_game() -> void:
	PauseManager.freeze(PAUSE_OWNER)


## 解冻：只交还自己那一个令牌。
func _unfreeze_game() -> void:
	PauseManager.unfreeze(PAUSE_OWNER)


# ============================================================================
# 私有方法
# ============================================================================

## 刷新背包与装备显示。
func _refresh() -> void:
	_refresh_equipment()
	_refresh_gold()
	_refresh_grid()


## 装备栏：显示当前武器图标。
func _refresh_equipment() -> void:
	if _weapon_icon == null:
		return
	var player: Node = get_tree().get_first_node_in_group(&"player")
	if player == null:
		return
	var combat: PlayerCombat = player.get_node_or_null("Combat") as PlayerCombat
	if combat == null or combat.current_weapon == null:
		_weapon_icon.texture = null
		return
	_weapon_icon.texture = combat.current_weapon.icon


func _refresh_gold() -> void:
	if _gold_label != null:
		_gold_label.text = "金币：%d" % GameState.gold


## 重建物品格子。
func _refresh_grid() -> void:
	if _grid == null:
		return
	for child: Node in _grid.get_children():
		child.queue_free()
	var entries: Array = GameState.get_inventory_entries()
	if entries.is_empty():
		var empty: Label = Label.new()
		empty.text = "背包是空的"
		empty.add_theme_font_size_override("font_size", 7)
		_grid.add_child(empty)
		return
	for entry: Dictionary in entries:
		_grid.add_child(_make_slot(entry))


## 生成一个物品格子。
func _make_slot(entry: Dictionary) -> Control:
	var slot: Control
	if slot_scene != null:
		slot = slot_scene.instantiate() as Control
	else:
		slot = _make_default_slot()
	var data: ItemData = entry.get("data") as ItemData
	var count: int = int(entry.get("count", 1))
	var icon: TextureRect = slot.find_child("Icon", true, false) as TextureRect
	var label: Label = slot.find_child("Count", true, false) as Label
	if icon != null and data != null:
		icon.texture = data.icon
	if label != null:
		label.text = "x%d" % count if count > 1 else ""
	if data != null:
		slot.tooltip_text = "%s\n%s" % [data.display_name, data.description]
	# 消耗品可点击使用。
	if data != null and data.kind == ItemData.Kind.CONSUMABLE:
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.gui_input.connect(_on_slot_input.bind(entry))
	return slot


## 代码生成默认格子（图标 + 右下角数量）。
func _make_default_slot() -> Control:
	# 用 Control 而不是 PanelContainer：PanelContainer 会把两个子节点纵向堆叠，
	# 数量标签会被挤到图标下方。这里手动定位，让数量叠在图标右下角。
	var slot: Control = Control.new()
	slot.custom_minimum_size = Vector2(20, 20)

	var bg: ColorRect = ColorRect.new()
	bg.name = "Bg"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.16, 0.15, 0.2, 0.9)
	slot.add_child(bg)

	var icon: TextureRect = TextureRect.new()
	icon.name = "Icon"
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	slot.add_child(icon)

	var label: Label = Label.new()
	label.name = "Count"
	label.add_theme_font_size_override("font_size", 6)
	label.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	# 右下角锚定。
	label.anchor_left = 1.0
	label.anchor_top = 1.0
	label.anchor_right = 1.0
	label.anchor_bottom = 1.0
	label.offset_left = -14.0
	label.offset_top = -9.0
	label.offset_right = -1.0
	label.offset_bottom = -1.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slot.add_child(label)
	return slot


# ============================================================================
# 信号回调
# ============================================================================

## 点击消耗品使用它。
func _on_slot_input(event: InputEvent, entry: Dictionary) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var data: ItemData = entry.get("data") as ItemData
	if data == null:
		return
	var player: Actor = get_tree().get_first_node_in_group(&"player") as Actor
	if player == null:
		return
	# 消耗：回血/回蓝。
	var used: bool = false
	if data.heal_amount > 0.0 and player.get_health() < player.get_max_health():
		player.heal(data.heal_amount)
		used = true
	if data.mana_amount > 0.0 and player.get_mana() < player.get_max_mana():
		player.restore_mana(data.mana_amount)
		used = true
	if not used:
		EventBus.toast_requested.emit("现在用不上这个")
		return
	if GameState.remove_item(data.id, 1):
		AudioManager.play_sfx(data.use_sfx)
		EventBus.toast_requested.emit("使用了 %s" % data.display_name)
		_refresh()
