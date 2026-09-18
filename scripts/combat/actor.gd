## Actor —— 所有"有血条、能被打"的单位基类
##
## 【负责什么】
##   玩家、敌人、Boss 的公共部分：血量/法力、受伤结算、无敌帧、硬直、击退、
##   死亡。子类只负责"怎么行动"（输入 / AI），不重复实现受伤逻辑。
##
## 【挂哪个节点】
##   挂在 CharacterBody2D 根节点上（player.tscn / enemy 场景）。
##   场景里必须挂好这些子节点（用 @export 引用，不写死路径）：
##     - health_bar: ProgressBar（可空，敌人小血条）
##     - hurtbox: Area2D（受击判定，独立碰撞层）
##     - sprite: AnimatedSprite2D 或 Sprite2D（用于闪白/抖动）
##
## 【依赖谁】
##   DamageInfo、EventBus、CharacterData（属性模板）。
##
## 【怎么扩展】
##   新单位继承本类，在 _physics_process 里实现自己的行为；受伤/死亡不要覆写，
##   需要额外反应就连接 on_damaged / died 信号。
##
## 【碰撞层约定】（见 project.godot 的 [layer_names]）
##   1=World 2=PlayerBody 3=EnemyBody 4=PlayerHurtbox 5=EnemyHurtbox
##   6=PlayerAttack 7=EnemyAttack 8=Pickup 9=Projectile 10=Interactable
class_name Actor
extends CharacterBody2D

# ============================================================================
# 信号
# ============================================================================

## 受到伤害后发出（扣血已完成）。UI/特效可监听。
signal damaged(info: DamageInfo)
## 血量归零时发出。
signal died(killer: Node)
## 血量变化（用于血条）。
signal health_updated(current: float, maximum: float)
## 法力变化。
signal mana_updated(current: float, maximum: float)

# ============================================================================
# @export —— 全部可在 Inspector 配置
# ============================================================================

## 角色属性模板。必须在 Inspector 里指定 .tres。
@export var data: CharacterData
## 精灵节点引用。留空则自动找名为 Sprite 的子节点（仅作为兜底）。
@export var sprite_path: NodePath
## 血条节点引用（可空）。
@export var health_bar_path: NodePath
## 受击盒节点引用（Area2D）。留空则不参与受击。
@export var hurtbox_path: NodePath
## 闪白着色器材质（受击时叠加）。留空则用 modulate 闪白。
@export var flash_material: ShaderMaterial
## 是否在 _ready 时按 data 自动创建碰撞体（原型期方便，正式场景可在 .tscn 里手挂）。
@export var auto_create_collision: bool = true

# ============================================================================
# 私有变量
# ============================================================================

## 当前血量。
var _health: float = 0.0
## 当前法力。
var _mana: float = 0.0
## 无敌帧剩余时间。
var _invuln_timer: float = 0.0
## 硬直剩余时间。>0 时 is_stunned 为 true。
var _stun_timer: float = 0.0
## 击退速度，逐帧衰减。
var _knockback_velocity: Vector2 = Vector2.ZERO
## 是否已死亡。
var _is_dead: bool = false
## 受击闪白用的原始 modulate，闪白结束后还原。
var _base_modulate: Color = Color.WHITE
## 缓存的血条引用。
var _health_bar: ProgressBar
## 缓存的受击盒引用。
var _hurtbox: Area2D
## 缓存的精灵引用。用 CanvasItem 是为了同时兼容 Sprite2D 与 ActorSprite；
## 需要动画/朝向接口的子类请自行再取一个强类型引用（见 EnemyBase._enemy_sprite）。
var _sprite: CanvasItem
## 受击闪色补间（复用，避免每次受击都新建）。
var _flash_tween: Tween
## 受击抖动补间。
var _shake_tween: Tween
## 死亡溶解补间。
var _death_tween: Tween
## 精灵抖动用的**基准位置**。必须在首次抖动时从静止状态记录，
## 之后每次抖动都从这里出发——否则反复受击会把偏移量累加进基准位置（见 _shake_sprite）。
var _sprite_origin: Vector2 = Vector2.ZERO
## 是否已记录过 _sprite_origin。
var _has_sprite_origin: bool = false
## 本实例**独占**的着色器材质（从 flash_material 模板复制而来，见 _ensure_owned_material）。
## 关键：绝不能让多个 Actor 共用一份可变的 ShaderMaterial，否则一个受击全体闪红。
var _owned_material: ShaderMaterial

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	_health = get_max_health()
	_mana = get_max_mana()
	_resolve_nodes()
	# 就绪即把共享材质"私有化"，保证本单位的闪白/溶解/描边只影响自己。
	_ensure_owned_material()
	_setup_collision()
	_setup_hurtbox()
	health_updated.emit(_health, get_max_health())
	mana_updated.emit(_mana, get_max_mana())
	EventBus.health_changed.emit(self, _health, get_max_health())


func _physics_process(delta: float) -> void:
	# 计时器统一在这里推进，子类不用重复写。
	_invuln_timer = maxf(0.0, _invuln_timer - delta)
	_stun_timer = maxf(0.0, _stun_timer - delta)
	# 击退衰减：用指数衰减而不是线性，手感更"软"。
	# 衰减速度可由 CharacterData 覆盖（精英/重甲单位停得更快）。
	var damping: float = data.knockback_damping if data != null and data.knockback_damping > 0.0 else 12.0
	_knockback_velocity = _knockback_velocity.lerp(Vector2.ZERO, clampf(delta * damping, 0.0, 1.0))
	if _knockback_velocity.length_squared() < 1.0:
		_knockback_velocity = Vector2.ZERO
	_regen_mana(delta)


# ============================================================================
# 公开方法 —— 查询
# ============================================================================

func get_health() -> float:
	return _health

## 最大生命。必须走 get_stat —— 否则「体魄：最大生命 +15」这类词条完全无效。
func get_max_health() -> float:
	if data == null:
		return 100.0
	return maxf(1.0, get_stat(GameEnums.StatKind.MAX_HEALTH))

func get_mana() -> float:
	return _mana

## 最大法力。同样必须走 get_stat，让「灵泉」等词条生效。
func get_max_mana() -> float:
	if data == null:
		return 0.0
	return maxf(0.0, get_stat(GameEnums.StatKind.MAX_MANA))

func get_health_ratio() -> float:
	var max_hp: float = get_max_health()
	return _health / max_hp if max_hp > 0.0 else 0.0

func is_dead() -> bool:
	return _is_dead

## 无敌（翻滚中 / 受击无敌帧）。
func is_invulnerable() -> bool:
	return _invuln_timer > 0.0

## 处于硬直中（不能主动行动）。
func is_stunned() -> bool:
	return _stun_timer > 0.0

## 取当前属性值。这是**唯一**的属读取口——所有伤害/移动/冷却计算都必须走它，
## 不允许直接读 data.attack_power，否则 Roguelite 词条会失效。
## 结算顺序：基础值 → 词条乘区（FLAT → PERCENT → MULTIPLY）。
func get_stat(kind: GameEnums.StatKind, context: Dictionary = {}) -> float:
	if data == null:
		return 0.0
	var base: float = _get_base_stat(kind)
	# 只有玩家吃词条；敌人属性不参与局内构筑。
	if is_in_group(&"player"):
		base = ModifierSystem.apply_stat(base, kind, context)
	return base


## 攻击上下文：决定哪些"限定类"词条参与本次计算。
## 默认空（敌人不吃词条）。玩家覆写它，返回当前武器的类别。
## 攻击盒/弹道在算伤害时调用 get_stat(ATTACK_POWER, get_attack_context())。
func get_attack_context() -> Dictionary:
	return {}


## 从 CharacterData 读原始属性值（不含词条）。
func _get_base_stat(kind: GameEnums.StatKind) -> float:
	match kind:
		GameEnums.StatKind.MAX_HEALTH: return data.max_health
		GameEnums.StatKind.MAX_MANA: return data.max_mana
		GameEnums.StatKind.ATTACK_POWER: return data.attack_power
		GameEnums.StatKind.DEFENSE: return data.defense
		GameEnums.StatKind.MOVE_SPEED: return data.move_speed
		GameEnums.StatKind.MANA_REGEN: return data.mana_regen
		GameEnums.StatKind.CRIT_CHANCE: return data.crit_chance
		GameEnums.StatKind.CRIT_DAMAGE: return data.crit_damage
		GameEnums.StatKind.COOLDOWN_RATE: return data.cooldown_rate
		GameEnums.StatKind.ATTACK_SPEED: return data.attack_speed
		GameEnums.StatKind.LIFE_STEAL: return data.life_steal
		GameEnums.StatKind.PICKUP_RANGE: return data.pickup_range
		_: return 0.0


# ============================================================================
# 公开方法 —— 状态操作
# ============================================================================

## 施加伤害。这是全游戏唯一的"扣血入口"。
##
## 【为什么返回 bool】调用方（attack_box / area_spell / projectile）靠它区分
##   "真的打中了" 与 "被无敌帧 / 已死 / 溶解中吃掉了"。
##   旧实现返回 void，调用方无法得知，于是打尸体也会飘伤害数字、顿帧、震屏，
##   带吸血词条时甚至能"砍尸体回血"。
func apply_damage(info: DamageInfo) -> bool:
	if _is_dead or info == null:
		return false
	# 无敌帧内完全免伤，但击退仍然生效？不——翻滚无敌就应该连击退都免疫，
	# 否则玩家会觉得"滚了还是被推"，所以这里直接整体返回。
	if is_invulnerable():
		return false
	# 先算防御减伤：用"乘法减伤"而不是"减法"，避免高防御直接免疫。
	var final_amount: float = _compute_damage_after_defense(info.amount)
	_health = maxf(0.0, _health - final_amount)
	# 硬直：霸体（super_armor）时完全不进硬直，只掉血；
	# 否则只有削韧超过自身韧性才被打断（韧性 0 表示一击必断）。
	if data != null and not data.super_armor and info.poise_damage >= _poise_threshold():
		_stun_timer = maxf(_stun_timer, data.hurt_time)
	# 击退：按目标的击退抗性打折。Boss 把 knockback_resist 设成 1.0 就完全站桩，
	# 精英设 0.5 会被推动一点点——**不需要为此写任何特殊代码**。
	var resist: float = data.knockback_resist if data != null else 0.0
	_knockback_velocity += info.knockback * (1.0 - clampf(resist, 0.0, 1.0))
	# 受击后的短暂无敌，防止被同一波攻击连续多帧打中。
	if data != null:
		_invuln_timer = maxf(_invuln_timer, data.invuln_time)
	health_updated.emit(_health, get_max_health())
	EventBus.health_changed.emit(self, _health, get_max_health())
	damaged.emit(info)
	# 受击表现：红色闪 + 精灵抖动。两者都由数据驱动，精英/Boss 可调。
	_play_hurt_feedback()
	if info.hit_sfx != null:
		AudioManager.play_sfx(info.hit_sfx)
	if _health <= 0.0:
		_die(info.source)
	return true


## 本次伤害是否会打断当前动作（进硬直）。
##
## 【为什么单独抽出来】`apply_damage` 只负责"是否掉血"，而"是否被打断"是另一个
##   正交问题：Boss 会掉血但**不该**被轻击打断（否则霸体设计完全失效，
##   玩家轻击连打就能让 Boss 永远起不了手，难度曲线崩塌）。
##   敌人侧在 _on_damaged 里读它，与 Actor.apply_damage 用同一套判定，避免两处漂移。
##
## 【判定规则】霸体直接免疫打断；否则削韧必须达到自身韧性（韧性 0 = 一击必断）。
func would_stagger(info: DamageInfo) -> bool:
	if info == null:
		return false
	if data != null and data.super_armor:
		return false
	return info.poise_damage >= _poise_threshold()


# ============================================================================
# 公开方法 —— 治疗与资源
# ============================================================================

## 治疗。不会超过最大生命。
func heal(amount: float) -> void:
	if _is_dead or amount <= 0.0:
		return
	_health = minf(get_max_health(), _health + amount)
	health_updated.emit(_health, get_max_health())
	EventBus.health_changed.emit(self, _health, get_max_health())


## 消耗法力。返回是否成功（不够则不扣）。
func spend_mana(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if _mana < amount:
		return false
	_mana -= amount
	mana_updated.emit(_mana, get_max_mana())
	EventBus.mana_changed.emit(self, _mana, get_max_mana())
	return true


## 恢复法力。
func restore_mana(amount: float) -> void:
	_mana = minf(get_max_mana(), _mana + amount)
	mana_updated.emit(_mana, get_max_mana())
	EventBus.mana_changed.emit(self, _mana, get_max_mana())


## 给一段无敌时间（翻滚调用）。
func grant_invulnerability(duration: float) -> void:
	_invuln_timer = maxf(_invuln_timer, duration)


## 重新按 data 初始化血量与法力。
## 用于"数据在 _ready 之后才注入"的场景（敌人生成器就是这么做的）。
func reset_resources() -> void:
	_health = get_max_health()
	_mana = get_max_mana()
	_is_dead = false
	_invuln_timer = 0.0
	_stun_timer = 0.0
	_knockback_velocity = Vector2.ZERO
	health_updated.emit(_health, get_max_health())
	mana_updated.emit(_mana, get_max_mana())
	EventBus.health_changed.emit(self, _health, get_max_health())


## 施加硬直（打断敌人动作）。
func apply_stun(duration: float) -> void:
	_stun_timer = maxf(_stun_timer, duration)


## 取当前击退速度，子类的移动逻辑要把它叠加进去。
func get_knockback_velocity() -> Vector2:
	return _knockback_velocity


## 直接设置位置（传送用），同时清掉击退，避免落地滑行。
func teleport_to(target: Vector2) -> void:
	global_position = target
	_knockback_velocity = Vector2.ZERO
	velocity = Vector2.ZERO


# ============================================================================
# 私有方法
# ============================================================================

## 配置受击盒：它是被动方——只被攻击盒/弹道检测，自己不主动扫描。
func _setup_hurtbox() -> void:
	if _hurtbox == null:
		return
	_hurtbox.monitoring = false
	_hurtbox.monitorable = true


## 解析 Inspector 里配置的节点引用。用 @export 的 NodePath 而不是硬编码 get_node。
func _resolve_nodes() -> void:
	if not sprite_path.is_empty():
		_sprite = get_node_or_null(sprite_path) as CanvasItem
	if _sprite == null:
		# 兜底：只在没配置时才按名字找，方便快速搭场景。
		_sprite = get_node_or_null("Sprite") as CanvasItem
	_base_modulate = _sprite.modulate if _sprite != null else Color.WHITE
	if not health_bar_path.is_empty():
		_health_bar = get_node_or_null(health_bar_path) as ProgressBar
	if not hurtbox_path.is_empty():
		_hurtbox = get_node_or_null(hurtbox_path) as Area2D


## 按 data.body_radius 自动创建圆形碰撞体。正式关卡可在 .tscn 里手挂后关掉它。
func _setup_collision() -> void:
	if not auto_create_collision or data == null:
		return
	if get_node_or_null("BodyShape") == null:
		var shape: CollisionShape2D = CollisionShape2D.new()
		shape.name = "BodyShape"
		var circle: CircleShape2D = CircleShape2D.new()
		circle.radius = data.body_radius
		shape.shape = circle
		add_child(shape)
	if _sprite == null and data.sprite_texture != null:
		var spr: Sprite2D = Sprite2D.new()
		spr.name = "Sprite"
		spr.texture = data.sprite_texture
		spr.offset = data.sprite_offset
		add_child(spr)
		_sprite = spr
		_base_modulate = spr.modulate


## 防御减伤公式：伤害 * (100 / (100 + 防御))。
## 为什么用这个：防御收益递减，永远不会出现"防御堆满=无敌"，也方便策划调。
func _compute_damage_after_defense(raw: float) -> float:
	var defense: float = get_stat(GameEnums.StatKind.DEFENSE)
	return raw * (100.0 / (100.0 + maxf(0.0, defense)))


## 韧性阈值。data.poise 为 0 时表示"一击必断"。
func _poise_threshold() -> float:
	return 0.0 if data == null else maxf(0.0, data.poise)


## 受击反馈：闪色 + 抖动。参数全部来自 CharacterData。
func _play_hurt_feedback() -> void:
	var flash_color: Color = data.hurt_flash_color if data != null else Color(1.0, 0.25, 0.25)
	var flash_time: float = data.hurt_flash_time if data != null else 0.12
	_flash(flash_color, flash_time)
	var intensity: float = data.hurt_shake_intensity if data != null else 2.0
	var shake_time: float = data.hurt_shake_time if data != null else 0.12
	if intensity > 0.0 and shake_time > 0.0:
		_shake_sprite(intensity, shake_time)


## 受击闪色。优先用着色器材质（只染不透明像素，像素边缘干净），否则退化为 modulate。
##
## 【为什么必须每实例一份材质 —— 这是"一个敌人红了，全体一起红"的根因】
##   ShaderMaterial 是**可变资源**：改 `flash_amount` 就是改这个材质对象本身。
##   场景（enemy.tscn）把同一个 ShaderMaterial 子资源同时挂在根节点 `flash_material`
##   和 Sprite.material 上，而 Godot 的**子资源默认在所有场景实例间共享**
##   （除非声明 `resource_local_to_scene = true`）。于是 10 个敌人共用一份材质，
##   给其中一个设 flash_amount=1，其余 9 个的精灵也一起变红 —— 看起来就像"对象池没隔离"。
##
##   旧代码的判断 `if _sprite.material == null or not (_sprite.material is ShaderMaterial)`
##   想省掉重复 duplicate，但场景已经给 Sprite 预挂了那份**共享**材质，条件不成立，
##   于是直接改了共享对象。正确做法：每个 Actor 在就绪时从模板复制出**本实例独占**的
##   一份并缓存（`_ensure_owned_material`），此后所有闪白/溶解/描边都只改自己这份。
##   （复制只发生一次，不是每次受击都复制，所以不会像旧 QA 报的那样泄漏材质。）
func _flash(flash_color: Color = Color(1.0, 0.25, 0.25), duration: float = 0.12) -> void:
	if _sprite == null:
		return
	var mat: ShaderMaterial = _ensure_owned_material()
	if mat != null:
		mat.set_shader_parameter("flash_color", flash_color)
		mat.set_shader_parameter("flash_amount", 1.0)
		if _flash_tween != null and _flash_tween.is_valid():
			_flash_tween.kill()
		_flash_tween = create_tween()
		_flash_tween.tween_method(func(v: float) -> void: mat.set_shader_parameter("flash_amount", v), 1.0, 0.0, duration)
		return
	_sprite.modulate = flash_color * 4.0
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_sprite, "modulate", _base_modulate, duration)


## 取得本实例独占的着色器材质（懒创建 + 缓存）。
##
## 【契约】返回非 null 时，`_sprite.material` 已经指向这份独占副本；调用方可以放心改参数。
## 返回 null 时表示"没有材质可用"，调用方应退回 modulate 方案。
## 子类（如 EnemyBase 的精英描边）也必须走这里，避免各自再复制一份导致互相覆盖。
func _ensure_owned_material() -> ShaderMaterial:
	if _owned_material != null and is_instance_valid(_owned_material):
		# 可能有外部代码（老路径）把 Sprite 的材质换掉了，重新夺回所有权。
		if _sprite != null and _sprite.material != _owned_material:
			_sprite.material = _owned_material
		return _owned_material
	if flash_material == null or _sprite == null:
		return null
	_owned_material = flash_material.duplicate() as ShaderMaterial
	_sprite.material = _owned_material
	return _owned_material


## 精灵抖动：快速左右偏移再归位。用 tween 而不是物理位移，不影响判定。
##
## 【为什么必须先 kill 再读 origin】tween 是**异步**的：反复受击时上一次抖动
##   可能正停在偏移位置上。旧实现先读 `node.position` 拿到的是**当前偏移后**的坐标，
##   再 kill 掉旧 tween（把锚点丢在偏移处），于是每次受击都把偏移量累加进基准位置，
##   打几下之后精灵就永久跑偏了。
##   顺序反过来：先 kill 让 tween 停下，再读位置——但 tween 被 kill 时
##   不会自动把属性归位，所以基准位置必须来自**独立的记录**，见 _sprite_origin。
func _shake_sprite(intensity: float, duration: float) -> void:
	if _sprite == null or not (_sprite is Node2D):
		return
	var node: Node2D = _sprite as Node2D
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	# 基准位置在首次抖动时记录一次，之后所有抖动都从这里出发，
	# 不依赖"当前 position 是不是正好归位"。
	if not _has_sprite_origin:
		_sprite_origin = node.position
		_has_sprite_origin = true
	var origin: Vector2 = _sprite_origin
	_shake_tween = create_tween()
	var step: float = duration / 4.0
	_shake_tween.tween_property(node, "position", origin + Vector2(-intensity, 0), step)
	_shake_tween.tween_property(node, "position", origin + Vector2(intensity, 0), step)
	_shake_tween.tween_property(node, "position", origin + Vector2(-intensity * 0.5, 0), step)
	_shake_tween.tween_property(node, "position", origin, step)


func _regen_mana(delta: float) -> void:
	if _is_dead or data == null:
		return
	# 回蓝速度也走 get_stat，让「冥想」词条真正生效。
	var regen: float = get_stat(GameEnums.StatKind.MANA_REGEN)
	if regen <= 0.0:
		return
	if _mana < get_max_mana():
		restore_mana(regen * delta)


func _die(killer: Node) -> void:
	if _is_dead:
		return
	_is_dead = true
	_stun_timer = 0.0
	velocity = Vector2.ZERO
	_knockback_velocity = Vector2.ZERO
	died.emit(killer)
	EventBus.unit_died.emit(self, killer)
	_play_death_effect()


## 死亡表现：着色器溶解 + 淡出，然后按配置销毁节点。
## 放在基类里，玩家/敌人/Boss 都能直接复用，不需要各自写一遍。
func _play_death_effect() -> void:
	var dissolve_time: float = data.death_dissolve_time if data != null else 0.5
	# 【为什么先 kill 闪白 tween】致死一击同样会触发 _flash()，它正在
	# 争抢同一个属性（ShaderMaterial 的 flash_amount 或 sprite.modulate）。
	# 不 kill 的话两个 tween 会互相覆盖：尸体淡出被闪白拉回去，
	# 表现为"尸体闪烁几下才消失"甚至永远淡不掉。
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	if _sprite == null or dissolve_time <= 0.0:
		if data == null or data.destroy_on_death:
			queue_free()
		return
	# 用着色器溶解（有材质时），否则退化为整体淡出。
	# 走 _ensure_owned_material 拿到本实例独占材质，避免溶解波及其它单位。
	var owned: ShaderMaterial = _ensure_owned_material()
	if owned != null:
		if _death_tween != null and _death_tween.is_valid():
			_death_tween.kill()
		_death_tween = create_tween()
		_death_tween.tween_method(func(v: float) -> void: owned.set_shader_parameter("dissolve_amount", v), 0.0, 1.0, dissolve_time)
		if data == null or data.destroy_on_death:
			_death_tween.tween_callback(queue_free)
		return
	if _sprite is CanvasItem:
		var item: CanvasItem = _sprite as CanvasItem
		_death_tween = create_tween()
		_death_tween.tween_property(item, "modulate:a", 0.0, dissolve_time)
		if data == null or data.destroy_on_death:
			_death_tween.tween_callback(queue_free)
