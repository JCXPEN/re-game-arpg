## HUD —— 主界面（血/蓝条、技能栏、飘字、提示）
##
## 【负责什么】
##   屏幕常驻 UI：左上角血条蓝条、底部技能栏、飘字生成、临时提示。
##   它是"只读消费者"——通过 EventBus 监听状态变化，从不主动去抓玩家节点。
##
## 【挂哪个节点】
##   scenes/ui/hud.tscn 的根节点（CanvasLayer）。由 Boot 或关卡加载。
##
## 【依赖谁】
##   EventBus（health_changed / mana_changed / floating_text_requested / toast_requested）、
##   DataRegistry（取技能图标）。
##
## 【怎么扩展】
##   新 UI 元素（小地图、任务追踪）加一个子节点 + 在 _ready 里连对应信号即可。
class_name HUD
extends CanvasLayer

# ============================================================================
# @export
# ============================================================================

## 血条。
@export var health_bar_path: NodePath
## 蓝条。
@export var mana_bar_path: NodePath
## 技能栏容器（HBoxContainer）。
@export var skill_bar_path: NodePath
## 飘字场景。
@export var floating_text_scene: PackedScene
## 飘字挂载的节点（通常是关卡根，这样飘字会跟随世界坐标）。
@export var world_root_path: NodePath
## 提示标签。
@export var toast_label_path: NodePath
## 玩家引用（用于读技能槽与冷却）。
@export var player_path: NodePath

# ============================================================================
# 私有变量
# ============================================================================

var _health_bar: ProgressBar
var _mana_bar: ProgressBar
var _skill_bar: HBoxContainer
var _toast_label: Label
var _world_root: Node
var _player: Player
## 技能栏按钮：Array[TextureRect]，与 spell_slots 一一对应。
var _skill_icons: Array[TextureRect] = []
## 提示淡出补间。
var _toast_tween: Tween

## 是否处于"局内激活"状态。回主菜单后置 false：HUD 停止每帧重绑玩家，
## 否则它会一边不可见、一边把新关卡/已释放的玩家重新绑回来，技能栏图标残留。
var _active: bool = true

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	_resolve_nodes()
	EventBus.health_changed.connect(_on_health_changed)
	EventBus.mana_changed.connect(_on_mana_changed)
	EventBus.floating_text_requested.connect(_on_floating_text_requested)
	EventBus.toast_requested.connect(_on_toast_requested)
	# 换关卡后玩家会被重建，需要重新绑定。
	EventBus.scene_changed.connect(_on_scene_changed)
	# 登记进 UI 注册表：调用方按 id 访问，不再按树路径查名。
	UIRegistry.register(&"hud", self)


func _process(_delta: float) -> void:
	if not _active:
		return
	# Toast 让位给提示条这件事必须每帧都做，所以要放在"玩家还没绑定就 return"
	# 这个早退之前 —— 开场几帧玩家必然没绑定，而提示条那几帧可能已经在显示。
	_update_toast_placement()
	# HUD 是常驻层，而玩家是每个关卡才生成的——开场那几帧必然拿不到玩家。
	# 所以这里持续重试绑定，直到拿到为止（拿到后 _player 有效就不再走）。
	if _player == null or not is_instance_valid(_player):
		_bind_player()
		return
	_update_cooldowns()


## 把 Toast 排在"顶部消息"的**下方**，避免叠在一起。
##
## 【为什么需要它】
##   HUD 的 Toast（"[F] 交谈"、拾取提示）固定在上方居中 y=40；而顶部还有两块
##   会往下长的面板：DialogUI 的提示条（路牌 / 系统提示）与 TutorialUI 的教程面板。
##   实测教程面板能把 y=40 的 Toast 整个埋在背后 —— 玩家站在村民旁边却
##   看不到"[F] 交谈"（"NPC 窗口出不来 / 不知道按 F"体感的直接来源）。
##   两个面板各自对外报自己的底边（notice_bottom / panel_bottom），
##   Toast 只需待在两者最大值的下面，不需要一套真正的布局系统。
func _update_toast_placement() -> void:
	if _toast_label == null:
		return
	# 没有面板时两个 bottom 都是 0，maxf 保证 Toast 待在原来的 40。
	var want: float = maxf(40.0, maxf(DialogUI.notice_bottom, TutorialUI.panel_bottom) + 4.0)
	if is_equal_approx(_toast_label.offset_top, want):
		return
	_toast_label.offset_top = want
	_toast_label.offset_bottom = want


# ============================================================================
# 公开方法
# ============================================================================

## 设置 HUD 的"局内激活"状态。
##
## 【为什么需要这个开关，而不是只切 visible】
##   HUD 的 _process 每帧重试绑定玩家（因为玩家是每个关卡才生成的）。回主菜单后
##   如果只是 visible=false，_process 仍会把已释放/新关卡的玩家重新绑回来，
##   技能栏图标残留、状态跨局错乱。set_active(false) 同时停止重绑并清掉绑定。
func set_active(active: bool) -> void:
	_active = active
	if active:
		visible = true
	else:
		force_close()


## 收起 HUD 并清掉对已释放玩家的绑定。
##
## 【为什么不能只 visible=false】HUD 是常驻层，玩家每个关卡重建，但 HUD 的
##   `_player` / `_skill_icons` / 技能栏子节点不会自己清。回主菜单后玩家被释放，
##   这些引用就成了悬空状态；下次进关前若没重新绑定干净，就会出现"技能栏还挂着
##   上一局的图标"这类跨局状态错乱。force_close 把它们一次性收敛。
func force_close() -> void:
	visible = false
	_player = null
	_skill_icons.clear()
	if _skill_bar != null:
		for child: Node in _skill_bar.get_children():
			child.queue_free()


# ============================================================================
# 私有方法
# ============================================================================

func _resolve_nodes() -> void:
	if not health_bar_path.is_empty():
		_health_bar = get_node_or_null(health_bar_path) as ProgressBar
	if not mana_bar_path.is_empty():
		_mana_bar = get_node_or_null(mana_bar_path) as ProgressBar
	if not skill_bar_path.is_empty():
		_skill_bar = get_node_or_null(skill_bar_path) as HBoxContainer
	if not toast_label_path.is_empty():
		_toast_label = get_node_or_null(toast_label_path) as Label
	if not world_root_path.is_empty():
		_world_root = get_node_or_null(world_root_path)
	if _world_root == null:
		# 飘字要挂在关卡根上（世界坐标），不能挂在 boot 节点上。
		_world_root = SceneDirector.get_current_scene()


## 绑定玩家，建立技能栏图标。
func _bind_player() -> void:
	_player = get_tree().get_first_node_in_group(&"player") as Player
	if _player == null:
		return
	if not player_path.is_empty():
		var explicit: Node = get_node_or_null(player_path)
		if explicit is Player:
			_player = explicit as Player
	# 血条蓝条立即刷新一次，避免开场显示满格但数值未同步。
	_on_health_changed(_player, _player.get_health(), _player.get_max_health())
	_on_mana_changed(_player, _player.get_mana(), _player.get_max_mana())
	_build_skill_bar()


## 按玩家的法术/技能槽生成技能栏图标。
func _build_skill_bar() -> void:
	if _skill_bar == null or _player == null:
		return
	for child: Node in _skill_bar.get_children():
		child.queue_free()
	_skill_icons.clear()
	var combat: PlayerCombat = _player.get_node_or_null("Combat") as PlayerCombat
	if combat == null:
		return
	# 法术槽。
	for i: int in combat.spell_slots.size():
		var spell: SpellData = combat.spell_slots[i]
		_skill_icons.append(_add_skill_icon(spell.icon if spell != null else null, "spell_%d" % i))
	# 技能槽。
	for i: int in combat.ability_slots.size():
		var ability: AbilityData = combat.ability_slots[i]
		_skill_icons.append(_add_skill_icon(ability.icon if ability != null else null, "ability_%d" % i))


## 加一个技能图标格子，返回图标节点用于后续画冷却。
func _add_skill_icon(icon: Texture2D, _slot: String) -> TextureRect:
	var rect: TextureRect = TextureRect.new()
	rect.custom_minimum_size = Vector2(18, 18)
	rect.texture = icon
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.tooltip_text = _slot
	_skill_bar.add_child(rect)
	return rect


## 每帧更新冷却遮罩（用 modulate 变暗表示冷却中，简单有效）。
func _update_cooldowns() -> void:
	if _player == null or _skill_icons.is_empty():
		return
	var combat: PlayerCombat = _player.get_node_or_null("Combat") as PlayerCombat
	if combat == null:
		return
	var index: int = 0
	for i: int in combat.spell_slots.size():
		if index < _skill_icons.size():
			var ratio: float = combat.get_cooldown_ratio(&"spell_%d" % i)
			_skill_icons[index].modulate = Color(1, 1, 1).lerp(Color(0.35, 0.35, 0.4), ratio)
		index += 1
	for i: int in combat.ability_slots.size():
		if index < _skill_icons.size():
			var ratio2: float = combat.get_cooldown_ratio(&"ability_%d" % i)
			_skill_icons[index].modulate = Color(1, 1, 1).lerp(Color(0.35, 0.35, 0.4), ratio2)
		index += 1


# ============================================================================
# 信号回调
# ============================================================================

func _on_health_changed(unit: Node, current: float, maximum: float) -> void:
	# 只显示玩家的血量；敌人的血条由敌人自己挂在头顶。
	# 注意必须用"unit 必须是玩家"这个正向判定——写成 `if _player != null and unit != _player`
	# 时，一旦 _player 还没绑定（开场几帧），过滤条件就被绕过，任何单位受伤都会刷玩家血条。
	if _player == null or unit != _player:
		return
	if _health_bar == null:
		return
	_health_bar.max_value = maximum
	_health_bar.value = current


func _on_mana_changed(unit: Node, current: float, maximum: float) -> void:
	if _player == null or unit != _player:
		return
	if _mana_bar == null:
		return
	_mana_bar.max_value = maximum
	_mana_bar.value = current


## 生成飘字。世界坐标转屏幕坐标的活由 Node2D 层级自动完成。
func _on_floating_text_requested(text: String, world_position: Vector2, color: Color) -> void:
	if floating_text_scene == null:
		return
	var root: Node = _world_root
	if root == null or not is_instance_valid(root):
		# 关卡可能刚被切走，重新取一次。
		root = SceneDirector.get_current_scene()
		_world_root = root
	if root == null:
		return
	var ft: FloatingText = floating_text_scene.instantiate() as FloatingText
	if ft == null:
		return
	root.add_child(ft)
	ft.global_position = world_position
	ft.setup(text, color, false)


## 换关卡后重新绑定玩家（旧玩家已被释放）。
func _on_scene_changed(_scene: Node) -> void:
	_player = null
	_skill_icons.clear()


func _on_toast_requested(message: String) -> void:
	if _toast_label == null:
		return
	_toast_label.text = message
	_toast_label.modulate.a = 1.0
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	# 【为什么挂 ALWAYS】提示条可能在暂停 / hitstop 期间弹出（例如"获得物品"）。
	#   默认 PAUSABLE 的 tween 在暂停时不推进，提示条就会一直挂在那儿不淡出。
	_toast_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_toast_tween.tween_interval(1.6)
	_toast_tween.tween_property(_toast_label, "modulate:a", 0.0, 0.5)
