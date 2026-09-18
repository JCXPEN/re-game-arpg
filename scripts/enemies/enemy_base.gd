## EnemyBase —— 敌人基类 + 通用状态机
##
## 【负责什么】
##   所有敌人的公共行为：感知玩家、追击、攻击、硬直、死亡。三种 AI（近战/法师/
##   冲锋）通过 EnemyData.kind 切换"如何决策"，共用同一套状态机骨架。
##
## 【挂哪个节点】
##   scenes/enemies/enemy.tscn 的根节点（继承 Actor → CharacterBody2D）。
##   场景里需挂好：Sprite(ActorSprite)、Hurtbox(Area2D)、AttackBox(Area2D)、
##   AttackController(Node)、血条(ProgressBar)。
##
## 【依赖谁】
##   EnemyData、AttackController、EventBus。
##
## 【怎么扩展】
##   新 AI 行为 = 在 EnemyKind 里加枚举 + 在 _tick_ai 里加一个分支。
##   新敌人 = 新建 .tres 指定 kind，**不用写代码**。
class_name EnemyBase
extends Actor

# ============================================================================
# enum
# ============================================================================

## 敌人状态。比玩家多了 CHARGE（冲锋蓄力）。
enum State {
	IDLE,
	WANDER,   ## 游荡
	CHASE,    ## 追击
	ATTACK,   ## 攻击中
	CHARGE,   ## 冲锋蓄力
	HURT,     ## 硬直
	DEAD
}

# ============================================================================
# @export
# ============================================================================

## 敌人数据。LevelRuntime 会在生成时注入。
@export var enemy_data: EnemyData
## 攻击控制器。
## 注意：sprite_path / health_bar_path / _sprite / _health_bar 都继承自 Actor，
## 这里不能再声明，否则会与父类成员冲突。
@export var attack_controller_path: NodePath
## 武器场景的挂载父节点。留空则挂到敌人自己身上。
@export var weapon_parent_path: NodePath

# ============================================================================
# 私有变量
# ============================================================================

## 当前状态。
var _state: State = State.IDLE
## 状态计时。
var _state_time: float = 0.0
## 攻击冷却剩余。
var _attack_cooldown: float = 0.0
## 失去目标后还要追多久。
var _lose_target_timer: float = 0.0
## 游荡目标点。
var _wander_target: Vector2 = Vector2.ZERO
## 游荡等待计时。
var _wander_wait: float = 0.0
## 冲锋方向（蓄力结束时锁定）。
var _charge_direction: Vector2 = Vector2.ZERO
## 缓存的攻击控制器。
## _sprite / _health_bar 直接复用 Actor 里的缓存，不重复声明。
var _attack_controller: AttackController
## 当前武器场景实例。
var _weapon_instance: WeaponController
## 武器挂载父节点。
var _weapon_parent: Node2D
## 强类型精灵引用（ActorSprite 专属接口：vframes / play_anim）。
var _enemy_sprite: ActorSprite
## 当前目标。
var _target: Actor
## 感知计时（不需要每帧检测，每 0.15 秒一次即可）。
var _sense_timer: float = 0.0

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	super._ready()
	_resolve_enemy_nodes()
	damaged.connect(_on_damaged)
	died.connect(_on_died)
	# 允许 LevelRuntime 在 add_child 之后立刻注入数据。
	if enemy_data != null:
		_apply_enemy_data()
	# 找玩家。
	_target = get_tree().get_first_node_in_group(&"player") as Actor
	_wander_target = global_position
	add_to_group(&"enemy")


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if is_dead():
		return
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_state_time += delta
	_sense_timer -= delta
	if _sense_timer <= 0.0:
		_sense_timer = 0.15
		_sense_target()
	# 把朝向喂给武器，判定盒才会跟着敌人转（而不是固定在角色中心）。
	_update_weapon_aim()
	_tick_ai(delta)
	move_and_slide()


## 驱动武器朝向：有目标时朝目标，没目标时朝精灵当前朝向。
##
## 【为什么不用 _direction_to_target()】那个函数是从**角色原点（脚底）**算的，
##   适合移动/转身决策，但武器是绕 WeaponMount(y = -6) 旋转的，
##   用脚底算角度会让判定盒整体歪掉 —— 离目标越近偏得越多。
##   这里单独从武器自己的旋转锚点指向目标。
func _update_weapon_aim() -> void:
	if _weapon_instance == null or not is_instance_valid(_weapon_instance):
		return
	if _has_target():
		var to_target: Vector2 = _target.global_position - _aim_origin()
		# 目标恰好落在锚点上时方向退化，退回朝向，避免把 (0,0) 喂给武器。
		if to_target.length_squared() > 0.0001:
			_weapon_instance.set_aim(to_target)
			return
	_weapon_instance.set_aim(_facing_vector())


## 瞄准 / 施法基准点（世界坐标）= 武器实际绕其旋转的中心（手）。
##
## 与玩家侧（PlayerCombat._aim_origin）同源：方向从哪算、弹道就从哪出，
## 否则轨迹与瞄准射线会整体错开 6px（WeaponMount 在 y = -6）。
## 三级兜底：武器实例 → 挂载点 → 角色原点，任何配置下都不会算出 NaN。
func _aim_origin() -> Vector2:
	if _weapon_instance != null and is_instance_valid(_weapon_instance):
		return _weapon_instance.get_aim_origin()
	if _weapon_parent != null and is_instance_valid(_weapon_parent):
		return _weapon_parent.global_position
	return global_position


## 精灵朝向 → 单位向量。
func _facing_vector() -> Vector2:
	if _enemy_sprite == null:
		return Vector2.DOWN
	match _enemy_sprite.direction:
		&"up": return Vector2.UP
		&"down": return Vector2.DOWN
		&"left": return Vector2.LEFT
		_: return Vector2.RIGHT


# ============================================================================
# 公开方法
# ============================================================================

## 注入敌人数据（LevelRuntime 生成敌人时调用）。
func setup(data: EnemyData) -> void:
	enemy_data = data
	_apply_enemy_data()


## 当前状态（调试/UI）。
func get_state() -> State:
	return _state


# ============================================================================
# 私有方法 —— 初始化
# ============================================================================

func _resolve_enemy_nodes() -> void:
	# sprite_path / health_bar_path 继承自 Actor，直接用父类的导出引用。
	# Actor._sprite 的类型是 CanvasItem（够通用），这里再取一个 ActorSprite 的
	# 强类型引用，才能访问 vframes / play_anim 这些子类专属接口。
	_enemy_sprite = get_node_or_null(sprite_path) as ActorSprite
	if _enemy_sprite == null:
		_enemy_sprite = get_node_or_null("Sprite") as ActorSprite
	_attack_controller = get_node_or_null(attack_controller_path) as AttackController
	if _attack_controller == null:
		_attack_controller = get_node_or_null("AttackController") as AttackController
	if not weapon_parent_path.is_empty():
		_weapon_parent = get_node_or_null(weapon_parent_path) as Node2D
	if _health_bar != null:
		health_updated.connect(_on_health_updated)
		_on_health_updated(get_health(), get_max_health())


## 把 EnemyData 应用到自身（属性 + 贴图 + 碰撞半径）。
func _apply_enemy_data() -> void:
	if enemy_data == null:
		return
	data = enemy_data.stats
	# 数据是运行时注入的，所以要在这里重算血量（_ready 时可能还没数据）。
	reset_resources()
	if _enemy_sprite != null and enemy_data.stats != null and enemy_data.stats.sprite_texture != null:
		_enemy_sprite.texture = enemy_data.stats.sprite_texture
		# 怪物表是 64×64（4×4），角色表是 64×112（4×7），按贴图高度自适应。
		var tex_height: int = enemy_data.stats.sprite_texture.get_height()
		_enemy_sprite.vframes = 7 if tex_height >= 112 else 4
		_enemy_sprite.offset = enemy_data.stats.sprite_offset
	# 精英/Boss 加描边，让玩家一眼分辨威胁等级。
	_apply_elite_outline()
	_instantiate_weapon()
	health_updated.emit(get_health(), get_max_health())


## 实例化敌人武器，让判定盒跟随敌人朝向。
## 走 WeaponController.create() 统一入口：优先用 EnemyData.weapon 的数据，
## 场景由通用武器场景提供，敌人不需要自己的武器 .tscn。
func _instantiate_weapon() -> void:
	if enemy_data == null:
		return
	if enemy_data.weapon == null and enemy_data.weapon_scene == null:
		return
	if _weapon_instance != null and is_instance_valid(_weapon_instance):
		_weapon_instance.queue_free()
	var parent: Node2D = _weapon_parent
	if parent == null:
		parent = self
	# 有自定义场景时优先用它，否则 create() 会用通用武器场景。
	if enemy_data.weapon_scene != null:
		_weapon_instance = enemy_data.weapon_scene.instantiate() as WeaponController
		if _weapon_instance != null:
			_weapon_instance.setup(enemy_data.weapon, self)
	else:
		# create() 内部已经调了 setup()，不要再调一次。
		_weapon_instance = WeaponController.create(enemy_data.weapon, self)
	if _weapon_instance == null:
		return
	parent.add_child(_weapon_instance)
	# 敌人武器只打玩家受击盒：层 = EnemyAttack(64)，掩码 = PlayerHurtbox(8)。
	var box: AttackBox = _weapon_instance.get_attack_box()
	if box != null:
		box.collision_layer = 64
		box.collision_mask = 8
		box.set_attacker(self)
	if _attack_controller != null:
		_attack_controller.set_weapon(_weapon_instance)


## 精英/Boss 描边。用着色器的 outline 参数，不额外加节点。
##
## 【为什么改走 _ensure_owned_material 而不是自己 duplicate 一份】
##   材质必须**每实例独占**（否则一个受击全体闪红，见 Actor._flash 注释）。
##   Actor 基类已经在 _ready 里为本实例复制好一份独占材质；这里若再 duplicate 一次，
##   就会把 Sprite 的材质换成另一份，基类缓存的那份失去引用，两边各改各的参数，
##   行为又要靠运气对齐。统一改基类那一份，全项目一个实例只有一份材质。
func _apply_elite_outline() -> void:
	if _enemy_sprite == null or flash_material == null:
		return
	if not enemy_data.is_elite:
		return
	var mat: ShaderMaterial = _ensure_owned_material()
	if mat == null:
		return
	mat.set_shader_parameter("outline_amount", 1.0)
	mat.set_shader_parameter("outline_color",
		Color(1.0, 0.75, 0.2) if enemy_data.is_boss else Color(1.0, 0.35, 0.35))


# ============================================================================
# 私有方法 —— 感知
# ============================================================================

## 周期性检测玩家是否在感知范围内。
func _sense_target() -> void:
	if _target == null or not is_instance_valid(_target) or _target.is_dead():
		_target = get_tree().get_first_node_in_group(&"player") as Actor
		return
	if enemy_data == null:
		return
	var dist: float = global_position.distance_to(_target.global_position)
	if dist <= enemy_data.detect_range:
		_lose_target_timer = enemy_data.lose_target_time
	else:
		_lose_target_timer = maxf(0.0, _lose_target_timer - 0.15)


## 是否还在追踪玩家。
func _has_target() -> bool:
	return _target != null and is_instance_valid(_target) and not _target.is_dead() and _lose_target_timer > 0.0


func _distance_to_target() -> float:
	if _target == null:
		return INF
	return global_position.distance_to(_target.global_position)


func _direction_to_target() -> Vector2:
	if _target == null:
		return Vector2.DOWN
	return (_target.global_position - global_position).normalized()


# ============================================================================
# 私有方法 —— AI 主循环
# ============================================================================

func _tick_ai(delta: float) -> void:
	# 硬直优先于一切：被打断时停止所有行动。
	if is_stunned():
		if _state != State.HURT:
			_enter_state(State.HURT)
		_tick_hurt(delta)
		return
	match _state:
		State.IDLE, State.WANDER:
			_tick_idle(delta)
		State.CHASE:
			_tick_chase(delta)
		State.ATTACK:
			_tick_attack(delta)
		State.CHARGE:
			_tick_charge(delta)
		State.HURT:
			_tick_hurt(delta)
		_:
			pass


## 待机/游荡：没目标时在出生点附近晃悠。
func _tick_idle(delta: float) -> void:
	if _has_target():
		_enter_state(State.CHASE)
		return
	_wander_wait = maxf(0.0, _wander_wait - delta)
	if _wander_wait > 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, 600.0 * delta)
		return
	if global_position.distance_to(_wander_target) < 6.0:
		# 到点了，随机歇一会儿再选下一个点。
		_wander_wait = randf_range(0.6, 1.8)
		_pick_wander_target()
		return
	_move_toward(_wander_target, delta, 0.4)


## 追击：靠近到攻击距离就出手。
func _tick_chase(delta: float) -> void:
	if not _has_target():
		_enter_state(State.IDLE)
		return
	var dist: float = _distance_to_target()
	if enemy_data == null:
		return
	# 法师保持距离：太近就后退，太远就靠近。
	if enemy_data.kind == GameEnums.EnemyKind.CASTER:
		_tick_caster_movement(delta, dist)
	else:
		_move_toward(_target.global_position, delta, 1.0)
	# 进入攻击距离且冷却好了 → 攻击。
	if _attack_cooldown <= 0.0:
		if enemy_data.kind == GameEnums.EnemyKind.CASTER and dist <= enemy_data.detect_range:
			_start_attack()
		elif enemy_data.kind == GameEnums.EnemyKind.CHARGER and dist <= enemy_data.attack_range * 4.0:
			_enter_state(State.CHARGE)
		elif dist <= enemy_data.attack_range:
			_start_attack()


## 法师移动：维持理想距离，像螃蟹一样侧移。
func _tick_caster_movement(delta: float, dist: float) -> void:
	if enemy_data == null:
		return
	var dir: Vector2 = _direction_to_target()
	if dist < enemy_data.preferred_range * 0.75:
		# 太近 → 后退。
		velocity = velocity.move_toward(-dir * get_stat(GameEnums.StatKind.MOVE_SPEED), 800.0 * delta)
	elif dist > enemy_data.preferred_range * 1.25:
		# 太远 → 靠近。
		_move_toward(_target.global_position, delta, 1.0)
	else:
		# 距离合适 → 轻微横移，避免站桩。
		var side: Vector2 = dir.rotated(PI * 0.5)
		velocity = velocity.move_toward(side * get_stat(GameEnums.StatKind.MOVE_SPEED) * 0.5, 500.0 * delta)


## 攻击中：等 AttackController 跑完。
func _tick_attack(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
	if _attack_controller == null or not _attack_controller.is_attacking():
		_attack_cooldown = enemy_data.attack_cooldown if enemy_data != null else 1.0
		_enter_state(State.CHASE)


## 冲锋蓄力：先站定蓄力，然后锁定方向冲出去。
func _tick_charge(delta: float) -> void:
	if enemy_data == null:
		_enter_state(State.CHASE)
		return
	# 蓄力阶段：站定并持续面向玩家（给玩家反应时间）。
	if _state_time < enemy_data.charge_time:
		velocity = Vector2.ZERO
		if _enemy_sprite != null:
			_enemy_sprite.face_direction(_direction_to_target())
			_enemy_sprite.play_anim(&"attack")
		return
	# 蓄力结束：锁定方向，进入冲撞。
	if _charge_direction == Vector2.ZERO:
		_charge_direction = _direction_to_target()
		if _attack_controller != null and enemy_data.melee_attack != null:
			_attack_controller.request_attack(enemy_data.melee_attack)
	# 冲撞阶段：高速直线移动，撞墙或超时后结束。
	var charge_speed: float = get_stat(GameEnums.StatKind.MOVE_SPEED) * enemy_data.charge_speed_mult
	velocity = _charge_direction * charge_speed
	# 冲撞时长用攻击数据的判定时长兜底。
	if _state_time > enemy_data.charge_time + 0.5:
		_charge_direction = Vector2.ZERO
		_attack_cooldown = enemy_data.attack_cooldown
		_enter_state(State.CHASE)


## 硬直：被击退，不能行动。
func _tick_hurt(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, 700.0 * delta) + get_knockback_velocity()
	if not is_stunned():
		_enter_state(State.CHASE if _has_target() else State.IDLE)


# ============================================================================
# 私有方法 —— 动作
# ============================================================================

## 朝目标移动。
func _move_toward(target_pos: Vector2, delta: float, speed_mult: float) -> void:
	var dir: Vector2 = (target_pos - global_position).normalized()
	var speed: float = get_stat(GameEnums.StatKind.MOVE_SPEED) * speed_mult
	velocity = velocity.move_toward(dir * speed, 900.0 * delta)
	if _enemy_sprite != null and dir.length_squared() > 0.01:
		_enemy_sprite.face_direction(dir)
		_enemy_sprite.play_anim(&"walk")


## 发起一次攻击。
func _start_attack() -> void:
	if enemy_data == null:
		return
	# 法师发射弹道。
	if enemy_data.kind == GameEnums.EnemyKind.CASTER:
		_fire_projectile()
		_attack_cooldown = enemy_data.attack_cooldown
		_enter_state(State.ATTACK)
		return
	if enemy_data.melee_attack == null or _attack_controller == null:
		return
	if _enemy_sprite != null:
		_enemy_sprite.face_direction(_direction_to_target())
		_enemy_sprite.play_anim(&"attack", true)
	_attack_controller.request_attack(enemy_data.melee_attack)
	AudioManager.play_sfx(enemy_data.attack_sfx)
	_enter_state(State.ATTACK)


## 法师发射弹道。
func _fire_projectile() -> void:
	if enemy_data == null or enemy_data.projectile_scene == null:
		return
	var proj: Node2D = enemy_data.projectile_scene.instantiate() as Node2D
	if proj == null:
		return
	# 施法点 = 武器旋转锚点（手），方向也从**锚点**指向目标：
	# 这样"弹道轨迹 = 瞄准射线"，不会出现"从脚底斜着飞出去"的 6px 整体偏移。
	var origin: Vector2 = _aim_origin()
	var dir: Vector2 = ( _target.global_position - origin).normalized() if _target != null else _facing_vector()
	# 挂到当前关卡根节点，切场景时随关卡释放。
	var parent: Node = SceneDirector.get_current_scene()
	if parent == null:
		parent = get_parent()
	parent.add_child(proj)
	proj.global_position = origin + dir * 8.0
	if proj is Projectile:
		(proj as Projectile).launch(dir, enemy_data.ranged_attack, GameEnums.Element.FIRE, self)
	AudioManager.play_sfx(enemy_data.attack_sfx)


## 选一个新的游荡点（在出生点附近随机）。
func _pick_wander_target() -> void:
	if enemy_data == null:
		return
	var angle: float = randf() * TAU
	var radius: float = randf() * enemy_data.wander_radius
	_wander_target = global_position + Vector2(cos(angle), sin(angle)) * radius


func _enter_state(next: State) -> void:
	if _state == next:
		return
	_state = next
	_state_time = 0.0
	if next == State.CHARGE:
		_charge_direction = Vector2.ZERO


# ============================================================================
# 信号回调
# ============================================================================

func _on_health_updated(current: float, maximum: float) -> void:
	if _health_bar == null:
		return
	_health_bar.max_value = maximum
	_health_bar.value = current
	# 满血时隐藏血条，受伤后显示——俯视 ARPG 的通用做法，避免画面太乱。
	_health_bar.visible = current < maximum


## 受击：按霸体/削韧判定是否打断攻击并进入硬直。
##
## 【为什么不能无条件打断】旧实现直接 `interrupt()` + `_enter_state(HURT)`，
##   完全不看 `super_armor` / `poise`。于是 Boss（`super_armor = true`、`poise = 90`）
##   被玩家轻击连打时，**每一次起手都被打断**，霸体形同虚设，难度曲线崩塌。
##   判定统一走 `Actor.would_stagger()`，与 Actor.apply_damage 内部那套保持一致。
func _on_damaged(info: DamageInfo) -> void:
	if is_dead():
		return
	# 霸体 / 韧性足够 → 只掉血，动作继续，不进硬直。
	if not would_stagger(info):
		return
	if _attack_controller != null:
		_attack_controller.interrupt()
		# 打断也要吃冷却。旧实现把冷却赋值写在 _tick_attack 的
		# "攻击自然结束"分支里，走打断路径就永远到不了那儿 →
		# 被打断的敌人可以立刻重新起手，越打它出手越快。
		_attack_cooldown = enemy_data.attack_cooldown if enemy_data != null else 1.0
	_enter_state(State.HURT)


## 死亡：播放溶解并广播。
func _on_died(killer: Node) -> void:
	_enter_state(State.DEAD)
	velocity = Vector2.ZERO
	if _enemy_sprite != null:
		_enemy_sprite.play_anim(&"dead")
	# 死亡溶解与节点销毁由 Actor._play_death_effect() 统一处理
	# （基类已在 _die 里调用），这里不再重复。
	if enemy_data != null:
		GameState.add_gold(enemy_data.gold_reward)
		AudioManager.play_sfx(enemy_data.hurt_sfx)
	if enemy_data != null and enemy_data.is_boss:
		GameState.register_boss_defeat(_resolve_boss_id())


## 登记 Boss 击杀时用的 id。
##
## 【为什么不能直接用 display_name】Boss 的 id 是 `boss_cyclops`（DataRegistry 的索引键
##   与 `LevelData.boss_id`），而 display_name 是"独眼巨人"。旧实现把中文名登记进
##   `defeated_bosses`，于是 `GameState.is_boss_defeated(&"boss_cyclops")` 永远返回 false
##   ——通关判定与"已击败"分支全部失效。
##
## 【优先级】刷怪时由 LevelRuntime 写入的 meta > 数据里的显式 id > 空串（不登记）。
##   空串时 register_boss_defeat 会自行忽略，不会污染存档。
func _resolve_boss_id() -> StringName:
	if has_meta(&"boss_id"):
		var meta_id: StringName = get_meta(&"boss_id", &"")
		if meta_id != &"":
			return meta_id
	if enemy_data != null and enemy_data.id != &"":
		return enemy_data.id
	push_warning("[EnemyBase] Boss %s 缺少 id，无法登记击败记录" % name)
	return &""
