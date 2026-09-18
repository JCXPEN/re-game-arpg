## Player —— 玩家角色（输入 + 移动 + 翻滚 + 攻击编排）
##
## 【负责什么】
##   把玩家输入翻译成角色动作，并实现动作游戏的三条手感规则：
##     1. 输入缓冲：攻击/翻滚按早了会被记住，窗口一到立刻执行。
##     2. 土狼时间(Coyote)：刚离开"可行动状态"的极短时间内仍允许出招/翻滚。
##     3. 后摇取消：攻击后摇可以被翻滚或移动取消。
##   具体伤害与武器数值全部委托给 AttackController / PlayerCombat。
##
## 【挂哪个节点】
##   scenes/player/player.tscn 的根节点（继承 Actor → CharacterBody2D）。
##   场景里需挂好并通过 @export 引用的子节点：
##     - Sprite (ActorSprite)、AttackBox (AttackController 内引用)、
##       Hurtbox (Actor.hurtbox_path)、Camera2D (camera_path)
##
## 【依赖谁】
##   Actor（属性/受伤）、AttackController（攻击时间轴）、PlayerCombat（武器/法术/技能）、
##   PlayerCamera（跟随）、EventBus。
##
## 【怎么扩展】
##   新动作（冲刺、格挡）加一个 @export 的时长参数 + 一个状态枚举值 + 一个 _tick_xxx()。
##   不要把数值写进代码——所有手感参数都在下面 @export 里。
class_name Player
extends Actor

# ============================================================================
# enum
# ============================================================================

## 玩家行为状态。用一个枚举统一管理"同一时刻只能做一件事"。
enum State {
	IDLE,
	MOVE,
	ATTACK,
	ROLL,
	HURT,
	DEAD
}

# ============================================================================
# @export —— 手感参数（全部可在 Inspector 调）
# ============================================================================

## 攻击控制器节点。sprite_path / hurtbox_path / flash_material 等继承自 Actor。
@export var attack_controller_path: NodePath
## 战斗组件（武器/法术/技能）。
@export var combat_path: NodePath
## 摄像机节点。
@export var camera_path: NodePath
## 翻滚速度（像素/秒）。
@export_range(50.0, 800.0, 10.0) var roll_speed: float = 260.0
## 翻滚持续时间。
@export_range(0.05, 1.5, 1.0 / 60.0, "suffix:s") var roll_duration: float = 0.32
## 翻滚无敌帧时长（通常等于或略短于翻滚时长）。
@export_range(0.0, 1.5, 1.0 / 60.0, "suffix:s") var roll_invuln_time: float = 0.26
## 翻滚冷却，防止无脑连滚。
@export_range(0.0, 3.0, 0.05, "suffix:s") var roll_cooldown: float = 0.12
## 移动加速度（像素/秒²）。越大越"跟手"，越小越"滑"。
@export_range(100.0, 10000.0, 50.0) var acceleration: float = 2200.0
## 停止减速度。通常比加速度大，让松手立刻停下（俯视 ARPG 要的是精确）。
@export_range(100.0, 10000.0, 50.0) var friction: float = 3000.0
## 攻击时的移动速度倍率（近战攻击可以边走边打，但要减速）。
@export_range(0.0, 1.0, 0.05) var attack_move_mult: float = 0.25
## 土狼时间：离开可行动状态后仍可出招的宽限时长。
@export_range(0.0, 0.5, 1.0 / 60.0, "suffix:s") var coyote_time: float = 0.10
## 输入缓冲：动作键按下后保留多久。
@export_range(0.0, 0.5, 1.0 / 60.0, "suffix:s") var input_buffer: float = 0.14

# ============================================================================
# 私有变量
# ============================================================================

## 当前状态。
var _state: State = State.IDLE
## 当前状态已持续时间。
var _state_time: float = 0.0
## 翻滚冷却剩余。
var _roll_cooldown_timer: float = 0.0
## 土狼时间剩余。
var _coyote_timer: float = 0.0
## 缓冲的翻滚输入剩余时间。
var _buffered_roll: float = 0.0
## 翻滚方向（起滚瞬间锁定，滚的过程中不可改变）。
var _roll_direction: Vector2 = Vector2.DOWN
## 缓存的节点引用。
## 注意：Actor 已有 _sprite(CanvasItem)，这里用强类型别名 _player_sprite 以访问
## ActorSprite 的 face_direction / play_anim。
var _player_sprite: ActorSprite
var _attack_controller: AttackController
var _combat: PlayerCombat
var _camera: PlayerCamera
## 本帧的输入方向。
var _input_dir: Vector2 = Vector2.ZERO
## 蓄力是否已达成（用于重击判定）。
var _heavy_released: bool = false

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	super._ready()
	# 加入 player 组，让敌人/关卡能用 get_first_node_in_group 找到玩家，
	# 避免任何系统硬编码节点路径去抓玩家。
	add_to_group(&"player")
	_resolve_player_nodes()
	_ready_connect_signals()
	if _combat != null:
		_combat.setup(self, _player_sprite)
	if _camera != null:
		_camera.set_target(self)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if is_dead():
		_tick_dead()
		return
	_state_time += delta
	_roll_cooldown_timer = maxf(0.0, _roll_cooldown_timer - delta)
	_coyote_timer = maxf(0.0, _coyote_timer - delta)
	_buffered_roll = maxf(0.0, _buffered_roll - delta)
	_read_input()
	_tick_state(delta)
	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	# 用 _unhandled_input 而不是 _input：UI 打开时（暂停/背包）按键不该驱动角色。
	if is_dead():
		return
	# 对话**不**再锁玩家动作。旧实现这里有一句 `if DialogUI.is_open: return`，
	# 一旦对话框因为换场景/玩家死亡/回调悬空而没能关闭，新关卡的玩家就会
	# 一出生就被永久锁住移动和攻击（这就是"卡游戏进程"的根因）。
	# 现在对话期间照样能移动/攻击/翻滚——走开即是"结束对话"（DialogUI 自己判断距离）。
	if event.is_action_pressed(&"roll"):
		_buffered_roll = input_buffer
	if event.is_action_pressed(&"attack"):
		_request_light_attack()
	if event.is_action_pressed(&"heavy_attack"):
		_begin_charge()
	if event.is_action_released(&"heavy_attack"):
		_release_charge()
	# 法术与技能槽。释放失败（蓝不够/冷却中）静默忽略，不打断玩家操作。
	if event.is_action_pressed(&"spell_1"):
		_cast_spell(0)
	if event.is_action_pressed(&"spell_2"):
		_cast_spell(1)
	if event.is_action_pressed(&"spell_3"):
		_cast_spell(2)
	if event.is_action_pressed(&"ability_1"):
		_use_ability(0)
	if event.is_action_pressed(&"ability_2"):
		_use_ability(1)


## 释放法术。成功后进入短暂的施法状态，防止立刻再打普攻。
func _cast_spell(index: int) -> void:
	if _combat == null or not can_act():
		return
	if _combat.cast_spell(index):
		_enter_state(State.ATTACK)


## 释放主动技能。
func _use_ability(index: int) -> void:
	if _combat == null:
		return
	_combat.use_ability(index)


# ============================================================================
# 公开方法
# ============================================================================

## 覆写：把"当前处境"作为攻击上下文，决定哪些限定词条参与本次伤害计算。
##   weapon_kind —— 让「巨力」只在双手武器下生效
##   trigger     —— 让「嗜血狂怒（残血增伤）」在低血量时生效
func get_attack_context() -> Dictionary:
	var ctx: Dictionary = {}
	if _combat != null and _combat.current_weapon != null:
		ctx[&"weapon_kind"] = _combat.current_weapon.kind
	# 残血触发：生命低于 40% 时给全局规则类词条放行。
	if get_health_ratio() < 0.4:
		ctx[&"trigger"] = &"low_health"
	return ctx


## 当前状态（供 UI / 调试显示）。
func get_state() -> State:
	return _state

## 是否处于可被"取消后摇"的状态。
##
## 【为什么要读 _coyote_timer】coyote_time（土狼时间）的语义是"刚结束翻滚/攻击的
##   一小段时间内，仍视为可行动"，专门用来消除"刚滚完按攻击没反应"的粘滞感。
##   旧实现只在 _tick_roll 末尾给 _coyote_timer 赋值，然后**只**在 _tick_grounded
##   里用它切了一次 MOVE 状态，从没接入 can_act() —— 而所有动作入口
##   （_cast_spell / _request_light_attack / _can_start_action）都先问 can_act()，
##   于是土狼时间实际上从未生效过。
func can_act() -> bool:
	if _state in [State.IDLE, State.MOVE]:
		return true
	return _coyote_timer > 0.0


## 当前是否在土狼时间窗口内（供 UI/调试与状态机使用）。
func in_coyote_window() -> bool:
	return _coyote_timer > 0.0


# ============================================================================
# 私有方法 —— 节点
# ============================================================================

func _resolve_player_nodes() -> void:
	# sprite_path 继承自 Actor，且它的类型是 NodePath；这里按 ActorSprite 取。
	_player_sprite = get_node_or_null(sprite_path) as ActorSprite
	if _player_sprite == null:
		_player_sprite = get_node_or_null("Sprite") as ActorSprite
	_attack_controller = get_node_or_null(attack_controller_path) as AttackController
	if _attack_controller == null:
		_attack_controller = get_node_or_null("AttackController") as AttackController
	_combat = get_node_or_null(combat_path) as PlayerCombat
	if _combat == null:
		_combat = get_node_or_null("Combat") as PlayerCombat
	_camera = get_node_or_null(camera_path) as PlayerCamera
	if _camera == null:
		_camera = get_node_or_null("Camera2D") as PlayerCamera


# ============================================================================
# 私有方法 —— 输入
# ============================================================================

func _read_input() -> void:
	# 对话期间**不**锁移动：走开就是"结束对话"的表达方式，
	# 玩家永远拿得回控制权。旧实现这里把输入清零，对话框一旦没关掉就是永久锁死。
	_input_dir = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	# 斜向移动不应该更快：归一化后速度恒定，这是 2D 动作游戏的基本要求。
	if _input_dir.length_squared() > 1.0:
		_input_dir = _input_dir.normalized()


func _request_light_attack() -> void:
	if _combat == null:
		return
	# 后摇取消：如果正在攻击但已进入可取消窗口，允许直接接下一段。
	if _state == State.ATTACK:
		if _attack_controller != null and _attack_controller.can_cancel():
			_combat.request_light_attack()
		return
	if _state in [State.IDLE, State.MOVE]:
		_enter_state(State.ATTACK)
		_combat.request_light_attack()


func _begin_charge() -> void:
	if _combat == null:
		return
	if _state in [State.IDLE, State.MOVE, State.ATTACK]:
		_combat.begin_charge()


## 释放重击。
##
## 【为什么要补进 ATTACK 状态】轻击走 `_enter_state(State.ATTACK)`，于是它在
##   整个挥砍期间都吃 `attack_move_mult` 减速（默认 0.25）。重击旧实现只调
##   `_combat.release_charge()`，不进状态，于是玩家可以**全速跑动着放重击**，
##   而且放完立刻又是 IDLE，能马上再次蓄力——重击没有任何走位代价，与设计意图相反。
##   这里与轻击对齐，手感与数值都一致。
func _release_charge() -> void:
	if _combat == null:
		return
	_heavy_released = true
	# 只有真的蓄着力才进攻击状态（松手时若已取消蓄力，就不该把玩家钉在原地）。
	if not _combat.is_charging():
		_combat.release_charge()
		return
	if _state in [State.IDLE, State.MOVE]:
		_enter_state(State.ATTACK)
	_combat.release_charge()


# ============================================================================
# 私有方法 —— 状态机
# ============================================================================

func _tick_state(delta: float) -> void:
	match _state:
		State.IDLE, State.MOVE:
			_tick_grounded(delta)
		State.ATTACK:
			_tick_attack(delta)
		State.ROLL:
			_tick_roll(delta)
		State.HURT:
			_tick_hurt(delta)
		_:
			pass


## 站立/移动：处理翻滚、攻击、移动。
func _tick_grounded(delta: float) -> void:
	# 硬直中不能行动，但仍然受击退影响（由基类叠加）。
	if is_stunned():
		_apply_knockback_motion(delta)
		return
	# 翻滚优先级最高（且处于冷却中则忽略缓冲）。
	if _buffered_roll > 0.0 and _roll_cooldown_timer <= 0.0:
		_buffered_roll = 0.0
		_start_roll()
		return
	# 土狼时间：刚结束攻击/翻滚时，若玩家仍按着方向，视为"仍在移动"，
	# 允许立刻接下一次动作，避免出现"刚滚完按攻击没反应"的粘滞感。
	if _coyote_timer > 0.0 and _input_dir.length_squared() > 0.01:
		_enter_state(State.MOVE)
	_move_with_input(delta)
	if _input_dir.length_squared() > 0.01:
		if _player_sprite != null:
			_player_sprite.face_direction(_input_dir)
			_player_sprite.play_anim(&"walk")
		if _state != State.MOVE:
			_enter_state(State.MOVE)
	else:
		if _player_sprite != null:
			_player_sprite.play_anim(&"idle")
		if _state != State.IDLE:
			_enter_state(State.IDLE)


## 攻击中：允许小幅移动（手感上"边走边砍"），后摇可被翻滚取消。
func _tick_attack(delta: float) -> void:
	# 攻击中按翻滚 → 取消后摇（这是本作最核心的手感点之一）。
	if _buffered_roll > 0.0 and _roll_cooldown_timer <= 0.0:
		if _attack_controller != null and _attack_controller.can_cancel():
			_buffered_roll = 0.0
			_attack_controller.interrupt()
			_start_roll()
			return
	# 攻击期间仍可微调朝向，让"转身砍"成立。
	if _input_dir.length_squared() > 0.01 and _player_sprite != null:
		_player_sprite.face_direction(_input_dir)
	_move_with_input(delta, attack_move_mult)
	# 攻击控制器结束整段攻击后自动回到待机。
	if _attack_controller == null or not _attack_controller.is_attacking():
		# 与翻滚结束时一致地给出土狼时间：让"砍完立刻接翻滚/下一段"不粘滞。
		_coyote_timer = coyote_time
		_enter_state(State.IDLE)


## 翻滚中：速度固定，方向锁定，不可转向。
func _tick_roll(delta: float) -> void:
	velocity = _roll_direction * roll_speed
	velocity += get_knockback_velocity()
	if _state_time >= roll_duration:
		# 给一点土狼时间，让"滚完立刻攻击"成立。
		_coyote_timer = coyote_time
		_enter_state(State.IDLE)


func _tick_hurt(delta: float) -> void:
	_apply_knockback_motion(delta)
	if _state_time >= (data.hurt_time if data != null else 0.15):
		# 硬直结束也清掉土狼时间：刚被打完就"立刻可行动"会显得硬直形同虚设。
		_coyote_timer = 0.0
		_enter_state(State.IDLE)


func _tick_dead() -> void:
	velocity = Vector2.ZERO
	if _player_sprite != null:
		_player_sprite.play_anim(&"dead")


## 开始翻滚。
func _start_roll() -> void:
	# 没有输入方向时朝当前朝向滚，保证"原地按翻滚"也能触发。
	var dir: Vector2 = _input_dir
	if dir.length_squared() < 0.01:
		dir = _direction_from_facing()
	_roll_direction = dir.normalized()
	_enter_state(State.ROLL)
	_roll_cooldown_timer = roll_cooldown
	grant_invulnerability(roll_invuln_time)
	# 翻滚必须取消蓄力：既防止"无敌帧里白嫖重击"，也保证移速惩罚被复位。
	if _combat != null:
		_combat.cancel_charge()
	if _player_sprite != null:
		_player_sprite.play_anim(&"roll", true)
		_player_sprite.set_facing(_facing_name(_roll_direction))
	# 翻滚音效/特效交给 EventBus 或后续接入。
	AudioManager.play_sfx(null)


## 切换到新状态并重置计时。
func _enter_state(next: State) -> void:
	if _state == next:
		return
	_state = next
	_state_time = 0.0


## 按输入方向移动（带加减速）。
func _move_with_input(delta: float, speed_mult: float = 1.0) -> void:
	var target_speed: float = get_stat(GameEnums.StatKind.MOVE_SPEED) * speed_mult
	# 攻击时额外乘以数据里的蓄力/攻击移动倍率（由 combat 设置）。
	if _combat != null:
		target_speed *= _combat.get_move_multiplier()
	var target_velocity: Vector2 = _input_dir * target_speed
	var rate: float = acceleration if _input_dir.length_squared() > 0.01 else friction
	velocity = velocity.move_toward(target_velocity, rate * delta)
	velocity += get_knockback_velocity()


## 只施加击退（硬直时不能主动移动）。
func _apply_knockback_motion(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, friction * delta) + get_knockback_velocity()


## 把朝向名转成方向向量（原地翻滚时用）。
func _direction_from_facing() -> Vector2:
	if _player_sprite == null:
		return Vector2.DOWN
	match _player_sprite.direction:
		&"up": return Vector2.UP
		&"down": return Vector2.DOWN
		&"left": return Vector2.LEFT
		_: return Vector2.RIGHT


## 方向向量 → 朝向名。
func _facing_name(dir: Vector2) -> StringName:
	if absf(dir.x) >= absf(dir.y):
		return &"right" if dir.x > 0.0 else &"left"
	return &"down" if dir.y > 0.0 else &"up"


# ============================================================================
# 信号回调
# ============================================================================

## 受击：打断当前动作并进入硬直状态。
func _on_damaged(_info: DamageInfo) -> void:
	if is_dead():
		return
	if _attack_controller != null:
		_attack_controller.interrupt()
	# 被打断时同样要取消蓄力，否则移速惩罚会残留。
	if _combat != null:
		_combat.cancel_charge()
	_enter_state(State.HURT)


func _on_died(_killer: Node) -> void:
	_enter_state(State.DEAD)
	EventBus.player_died.emit()


func _ready_connect_signals() -> void:
	# 放在单独函数里，方便 _ready 调用顺序清晰。
	damaged.connect(_on_damaged)
	died.connect(_on_died)
