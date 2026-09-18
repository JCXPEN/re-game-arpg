## Interactable —— 可交互物基类（宝箱/存档点/提示牌/NPC/治愈泉共用）
##
## 【负责什么】
##   玩家走进范围时显示"按 F 交互"提示，按下后执行效果。子类只实现
##   _on_interact()，不用重复写检测、提示、冷却逻辑。
##
## 【挂哪个节点】
##   作为 Area2D 挂在交互物场景根节点。场景里需有：
##     - CollisionShape2D（交互范围）
##     - 一个 Sprite2D / ActorSprite 用于显示
##   玩家必须在 "player" 组里（Player._ready 已加入）。
##
## 【依赖谁】
##   EventBus（提示/飘字/音效）、GameState（存档点写档）。
##
## 【怎么扩展】
##   新交互物 = 继承本类 + 覆写 _on_interact()，并在 .tscn 里配好碰撞层。
##   一次性交互把 one_shot 设 true。
class_name Interactable
extends Area2D

# ============================================================================
# 信号
# ============================================================================

## 交互发生时发出。
signal interacted(actor: Node)
## 玩家进入/离开交互范围（子类可用来显示/隐藏提示）。
signal focus_entered()
signal focus_exited()

# ============================================================================
# @export
# ============================================================================

## 交互提示文字。
@export var prompt_text: String = "交互"
## 是否只能用一次。
@export var one_shot: bool = false
## 交互后的冷却（秒）。one_shot 为 true 时忽略。
@export_range(0.0, 60.0, 0.1, "suffix:s") var cooldown: float = 0.0
## 需要按键才能交互（false 表示踩上去自动触发，用于传送点/陷阱）。
@export var requires_input: bool = true
## 交互音效。
@export var interact_sfx: AudioStream
## 是否在玩家进入时自动面向玩家（NPC 用）。
@export var face_player: bool = false

# ============================================================================
# 私有变量
# ============================================================================

## 当前在范围内的玩家。
var _player_in_range: Node2D
## 冷却剩余。
var _cooldown_timer: float = 0.0
## 是否已用过（one_shot）。
var _used: bool = false

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	# 交互物是被动检测方：只监听玩家进入，不主动扫描别的东西。
	monitoring = true
	monitorable = false
	# 入组：F 键的"就近择优"需要一个能枚举全部候选的容器（见 _pick_nearest_in_range）。
	# 放在基类里，子类不必各自登记。
	add_to_group(&"interactable")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	_cooldown_timer = maxf(0.0, _cooldown_timer - delta)
	# 自动触发的交互物（传送点等）踩上去就生效。
	if not requires_input and _player_in_range != null and _can_interact():
		_do_interact(_player_in_range)


func _unhandled_input(event: InputEvent) -> void:
	if not requires_input:
		return
	# 对话进行中吞掉 F：否则按一次 F 会"推进对话"同时又"重新触发一次交互"，
	# 表现为 NPC 对话被瞬间重开、或者一句话都看不清就跳完了。
	# 注意这里只让出 F 这一个动作——对话**不**再锁移动/攻击。旧实现把"对话中"
	# 当成全局静默期，一旦对话框没被关掉就会把玩家永久按在地上，见 dialog_ui.gd。
	if DialogUI.is_open:
		return
	if not event.is_action_pressed(&"interact"):
		return
	# 【为什么要做"全屏择优"而不是自己直接响应】
	#   两个交互物的范围重叠时（NPC 站在宝箱旁、存档点紧挨着门），
	#   所有重叠的交互物都会收到同一个 F。旧实现是"谁先处理谁就
	#   set_input_as_handled()"——也就是**树序最后的那个**吃掉按键，
	#   玩家站在离宝箱更近的位置却可能开到了 NPC。
	#   现在把按键交给一个仲裁者：收集范围内所有候选，选距离玩家最近的那个。
	var winner: Interactable = _pick_nearest_in_range()
	if winner == null:
		return
	winner._do_interact(winner._player_in_range)
	get_viewport().set_input_as_handled()


## 在所有"玩家在范围内且可交互"的交互物里，选出离玩家最近的一个。
##
## 【为什么用组而不是遍历全树找 Area2D】
##   用 "interactable" 组 + get_tree() 比 find_children 便宜，且语义明确。
##   本类在 _ready 里自动入组，子类不需要各自登记。
func _pick_nearest_in_range() -> Interactable:
	if _player_in_range == null:
		return null
	var best: Interactable = null
	var best_dist: float = INF
	for node: Node in get_tree().get_nodes_in_group(&"interactable"):
		var other: Interactable = node as Interactable
		if other == null or not is_instance_valid(other):
			continue
		if other._player_in_range == null or not other._can_interact():
			continue
		# 同一帧里只有最靠前的那个类别的候选来自本人，其余都靠自己的范围状态。
		var d: float = other.global_position.distance_squared_to(_player_in_range.global_position)
		if d < best_dist:
			best_dist = d
			best = other
	return best


# ============================================================================
# 公开方法
# ============================================================================

## 是否处于可交互状态。
func can_interact() -> bool:
	return _can_interact()


## 是否已被使用过（one_shot）。
func is_used() -> bool:
	return _used


## 强制触发一次交互（用于测试/脚本驱动）。
func force_interact(actor: Node) -> void:
	_do_interact(actor)


# ============================================================================
# 私有方法
# ============================================================================

func _can_interact() -> bool:
	if one_shot and _used:
		return false
	return _cooldown_timer <= 0.0


## 执行交互：播提示/音效、跑子类效果、处理冷却与一次性标记。
func _do_interact(actor: Node) -> void:
	_cooldown_timer = cooldown
	if one_shot:
		_used = true
	if interact_sfx != null:
		AudioManager.play_sfx(interact_sfx)
	_on_interact(actor)
	interacted.emit(actor)


## 子类覆写：实际的交互效果。
func _on_interact(_actor: Node) -> void:
	pass


# ============================================================================
# 信号回调
# ============================================================================

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group(&"player"):
		return
	_player_in_range = body
	if face_player:
		# NPC 转身面向玩家，纯表现。
		var sprite: Node = get_node_or_null("Sprite")
		if sprite is ActorSprite:
			(sprite as ActorSprite).face_direction(body.global_position - global_position)
	if requires_input and _can_interact():
		EventBus.toast_requested.emit("[F] %s" % prompt_text)
	focus_entered.emit()


func _on_body_exited(body: Node2D) -> void:
	if body != _player_in_range:
		return
	_player_in_range = null
	focus_exited.emit()
