## AttackController —— 攻击时间轴控制器（组件）
##
## 【负责什么】
##   驱动"前摇 → 判定 → 后摇"这条时间轴，并实现三件手感关键的事：
##     1. 输入缓冲：后摇中按下攻击会被记住，窗口一到立刻接上。
##     2. 连击衔接：一段打完后在 combo_window 内再按，接下一段。
##     3. 后摇取消：后摇期间允许翻滚/移动取消（由外部调用 can_cancel）。
##
## 【挂哪个节点】
##   作为 Node 子节点挂在玩家/敌人场景里，通过 @export 引用它需要的节点：
##     - attack_box: AttackBox（攻击判定盒）
##     - sprite: AnimatedSprite2D（用于播放攻击动画，可空）
##
## 【依赖谁】
##   AttackData（帧数据）、AttackBox（判定）、EventBus（顿帧/震动）。
##
## 【怎么扩展】
##   要加"攻击时位移/前冲"，读 AttackData.self_motion 即可；要加"取消窗口"，
##   扩展 can_cancel()。不要在这里写具体武器逻辑——那属于 WeaponData。
##
## 【为什么用时间累加而不是 Timer 节点】
##   一个攻击有三段时间，用 Timer 要三个节点且难同步。用一个累加器 + 状态枚举
##   最直观，也方便把时间乘以攻速倍率做"整体加速"。
class_name AttackController
extends Node

# ============================================================================
# 信号
# ============================================================================

## 判定窗口开启。外部据此生成刀光特效。
signal swing_started(data: AttackData)
## 判定窗口关闭。
signal swing_finished(data: AttackData)
## 整段攻击结束（含后摇）。
signal attack_ended()

# ============================================================================
# enum
# ============================================================================

## 攻击阶段。
enum Phase {
	IDLE,     ## 没在攻击
	STARTUP,  ## 前摇
	ACTIVE,   ## 判定中
	RECOVERY  ## 后摇
}

# ============================================================================
# @export
# ============================================================================

## 武器控制器。设置后，判定盒/挥砍动画全部委托给武器场景；
## 留空则退回"角色自带判定盒"的旧模式（敌人暂时用这条路径）。
@export var weapon_path: NodePath
## 攻击判定盒（未配置 weapon_path 时使用）。
@export var attack_box_path: NodePath
## 攻击判定形状节点（用于按 AttackData 动态改大小/偏移）。
@export var attack_shape_path: NodePath
## 攻击动画播放器（可空）。
@export var sprite_path: NodePath
## 动画名：第 N 段连击对应的动画名。索引 0 = 第一段。
@export var combo_animation_names: PackedStringArray = PackedStringArray(["attack"])
## 攻速倍率来源：为 true 时从角色 get_stat(ATTACK_SPEED) 读取。
@export var use_actor_attack_speed: bool = true
## 固定攻速倍率（use_actor_attack_speed 为 false 时使用）。
@export_range(0.25, 4.0, 0.05) var attack_speed: float = 1.0
## 输入缓冲时长：在后摇开始前这么久内按下的攻击会被记住。
@export_range(0.0, 0.5, 1.0 / 60.0, "suffix:s") var input_buffer: float = 0.15

# ============================================================================
# 私有变量
# ============================================================================

## 当前阶段。
var _phase: Phase = Phase.IDLE
## 当前阶段的剩余时间。
var _phase_timer: float = 0.0
## 当前攻击数据。
var _current: AttackData
## 当前是第几段连击（0 起）。
var _combo_index: int = 0
## 缓冲的攻击输入剩余有效时间。
var _buffered_attack: float = 0.0
## 是否处于蓄力中。
var _charging: bool = false
## 缓存的武器控制器。
var _weapon: WeaponController
## 缓存的判定盒（无武器时的兜底）。
var _attack_box: AttackBox
## 缓存的判定形状。
var _attack_shape: CollisionShape2D
## 缓存的精灵。
var _sprite: AnimatedSprite2D
## 缓存的角色（用于取攻速）。
var _actor: Actor
## 本次攻击是否已经"生效过"（用于 combo_window 起点的计算）。
var _recovery_elapsed: float = 0.0

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	if not weapon_path.is_empty():
		_weapon = get_node_or_null(weapon_path) as WeaponController
	if not attack_box_path.is_empty():
		_attack_box = get_node_or_null(attack_box_path) as AttackBox
	if not attack_shape_path.is_empty():
		_attack_shape = get_node_or_null(attack_shape_path) as CollisionShape2D
	if _attack_shape == null and _attack_box != null:
		# 兜底：判定盒下第一个 CollisionShape2D。
		_attack_shape = _attack_box.get_node_or_null("Shape") as CollisionShape2D
	if not sprite_path.is_empty():
		_sprite = get_node_or_null(sprite_path) as AnimatedSprite2D
	_actor = get_parent() as Actor


func _process(delta: float) -> void:
	# 缓冲输入随时间衰减。
	_buffered_attack = maxf(0.0, _buffered_attack - delta)
	if _phase == Phase.IDLE:
		return
	_phase_timer -= delta * _speed_multiplier()
	match _phase:
		Phase.STARTUP:
			if _phase_timer <= 0.0:
				_enter_active()
		Phase.ACTIVE:
			if _phase_timer <= 0.0:
				_enter_recovery()
		Phase.RECOVERY:
			_recovery_elapsed += delta * _speed_multiplier()
			# 缓冲的攻击输入一旦进入连击窗口，立刻接下一段。
			if _buffered_attack > 0.0 and _recovery_elapsed >= _current.combo_window:
				if _current.next_combo != null:
					_buffered_attack = 0.0
					_start_attack(_current.next_combo, _combo_index + 1)
					return
			if _phase_timer <= 0.0:
				_end_attack()
		_:
			pass


# ============================================================================
# 公开方法
# ============================================================================

## 请求攻击。返回 true 表示"这次输入被接受了"（无论立刻开始还是被缓冲）。
## 外部（玩家输入/AI）只管调用，不需要关心当前阶段。
func request_attack(data: AttackData) -> bool:
	if data == null:
		return false
	if _phase == Phase.IDLE:
		_start_attack(data, 0)
		return true
	# 后摇中：缓冲起来，等到连击窗口自动接上。
	if _phase == Phase.RECOVERY:
		_buffered_attack = input_buffer
		return true
	# 前摇/判定中：缓冲，但不打断当前段（避免出现"打一半变招"的鬼畜感）。
	_buffered_attack = input_buffer
	return true


## 是否处于可被取消的状态（后摇且过了 roll_cancel_at）。
func can_cancel() -> bool:
	if _phase != Phase.RECOVERY or _current == null:
		return false
	return _recovery_elapsed >= _current.roll_cancel_at


## 强制中断当前攻击（翻滚/受击打断时调用）。
##
## 【为什么必须补发 swing_finished】swing_started / swing_finished 是一对：
##   外部（刀光特效、挥砍音效）按"收到 started 就建、收到 finished 就回收"来管理资源。
##   旧实现在这里只发 attack_ended，不发 swing_finished，于是**被打断的挥砍永远不会回收**
##   ——刀光留在场上、音效循环不停。这与 _enter_recovery 的成对语义也不一致。
func interrupt() -> void:
	if _phase == Phase.IDLE:
		return
	if _weapon != null:
		_weapon.end_swing()
	elif _attack_box != null:
		_attack_box.end_swing()
	# 只有真的走到过判定窗口才需要补 finished，否则会发出"没 started 的 finished"。
	# STARTUP 阶段被中段时，swing_started 还没发（见 _start_attack），不该补。
	var had_swing: bool = _phase == Phase.ACTIVE or _phase == Phase.RECOVERY
	var interrupted: AttackData = _current
	_phase = Phase.IDLE
	_phase_timer = 0.0
	_buffered_attack = 0.0
	_charging = false
	_current = null
	_combo_index = 0
	_recovery_elapsed = 0.0
	if had_swing and interrupted != null:
		swing_finished.emit(interrupted)
	attack_ended.emit()


## 是否正在攻击。
func is_attacking() -> bool:
	return _phase != Phase.IDLE


## 当前阶段（供状态机查询）。
func get_phase() -> Phase:
	return _phase


## 当前攻击数据（供动画/特效查询）。
func get_current_attack() -> AttackData:
	return _current


## 取攻击带来的自身位移，外部移动逻辑每帧读取它。
func get_self_motion() -> Vector2:
	if _current == null:
		return Vector2.ZERO
	# 只在判定窗口给位移，前摇/后摇不动，这样冲刺斩才有"顿一下再窜出去"的节奏。
	if _phase == Phase.ACTIVE:
		return _current.self_motion
	return Vector2.ZERO


## 绑定武器控制器（换武器时由 PlayerCombat 调用）。
func set_weapon(weapon: WeaponController) -> void:
	_weapon = weapon


## 取当前武器控制器。
func get_weapon() -> WeaponController:
	return _weapon


## 设置蓄力状态（由玩家蓄力逻辑驱动，影响是否允许立刻出招）。
func set_charging(value: bool) -> void:
	_charging = value


func is_charging() -> bool:
	return _charging


# ============================================================================
# 私有方法
# ============================================================================

## 开始一段攻击。
func _start_attack(data: AttackData, combo_index: int) -> void:
	_current = data
	_combo_index = combo_index
	_recovery_elapsed = 0.0
	_phase = Phase.STARTUP
	# 攻速倍率整体缩放三段时长：>1 时全部变短。
	_phase_timer = data.startup
	_play_animation(combo_index)
	# 【为什么不在这里发 swing_started】
	#   本函数是**前摇**的起点。旧的把 swing_started 发在这里，与它在
	#   _enter_active 里才真正 begin_swing()（开判定盒）差了整整一个前摇，
	#   于是刀光/音效会在角色还没挥出去时就先播出来，看起来是"特效先动、武器后动"。
	#   成对的语义是"判定窗口开启 ↔ 关闭"，所以两个信号都挪到 ACTIVE 边界上。


func _enter_active() -> void:
	_phase = Phase.ACTIVE
	_phase_timer = _current.active
	if _weapon != null:
		# 委托给武器：判定盒的位置/旋转/扫动都由武器负责。
		_weapon.begin_swing(_current)
	else:
		if _attack_box != null:
			_attack_box.begin_swing(_current)
		_apply_hitbox_shape()
	# 判定窗口真正开启，此刻才通知外部生成刀光/音效。
	swing_started.emit(_current)


## 按 AttackData 的偏移/尺寸更新判定形状。
## 判定形状用 RectangleShape2D，这样"范围倍率"只需乘尺寸。
func _apply_hitbox_shape() -> void:
	if _attack_shape == null or _current == null:
		return
	var rect: RectangleShape2D = _attack_shape.shape as RectangleShape2D
	if rect == null:
		rect = RectangleShape2D.new()
		_attack_shape.shape = rect
	var range_mult: float = 1.0
	if _actor != null and _actor.has_method("get_weapon_range_mult"):
		range_mult = _actor.call("get_weapon_range_mult") as float
	rect.size = _current.hitbox_size * range_mult
	_attack_shape.position = _current.hitbox_offset * range_mult


func _enter_recovery() -> void:
	_phase = Phase.RECOVERY
	_phase_timer = _current.recovery
	_recovery_elapsed = 0.0
	if _weapon != null:
		_weapon.end_swing()
	elif _attack_box != null:
		_attack_box.end_swing()
	swing_finished.emit(_current)


func _end_attack() -> void:
	_phase = Phase.IDLE
	_phase_timer = 0.0
	_current = null
	_combo_index = 0
	_recovery_elapsed = 0.0
	attack_ended.emit()


## 攻速倍率。所有阶段计时都除以它，实现"整体加速"而不是只缩短后摇。
func _speed_multiplier() -> float:
	if use_actor_attack_speed and _actor != null:
		var value: float = _actor.get_stat(GameEnums.StatKind.ATTACK_SPEED)
		# get_stat 默认返回 0（因为 CharacterData 没有 attack_speed 字段），
		# 这里把 0 视为"未配置"，回退到 1.0，避免攻速变成 0 导致攻击永不结束。
		return value if value > 0.0 else 1.0
	return attack_speed


## 播放攻击动画。动画名越界时退回第 0 个，避免缺动画直接报错。
func _play_animation(combo_index: int) -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		return
	var anim: String = combo_animation_names[0]
	if combo_index < combo_animation_names.size():
		anim = combo_animation_names[combo_index]
	if _sprite.sprite_frames.has_animation(anim):
		_sprite.play(anim)
