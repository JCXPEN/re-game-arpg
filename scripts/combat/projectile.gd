## Projectile —— 通用弹道（法术 / 远程武器共用）
##
## 【负责什么】
##   直线飞行、命中判定、命中后生成特效并销毁。伤害数值由发射者传入的
##   AttackData + 发射者属性决定，弹道本身不含数值。
##
## 【挂哪个节点】
##   scenes/fx/projectile.tscn 的根节点（Area2D）。必须挂好 CollisionShape2D，
##   并设置碰撞层（Projectile 层）与掩码（敌方受击盒 + 世界）。
##
## 【依赖谁】
##   AttackData、DamageInfo、EventBus。
##
## 【怎么扩展】
##   追踪弹继承本类并覆写 _update_direction()；穿透弹把 _pierce_count 设 >0。
class_name Projectile
extends Area2D

# ============================================================================
# @export
# ============================================================================

## 飞行速度（像素/秒）。
@export_range(20.0, 1200.0, 5.0) var speed: float = 180.0
## 存活时间上限（秒），防止飞出地图不回收。
@export_range(0.1, 20.0, 0.1, "suffix:s") var lifetime: float = 4.0
## 是否旋转贴图朝向飞行方向。
@export var rotate_to_direction: bool = true
## 命中后是否销毁。
@export var destroy_on_hit: bool = true
## 可穿透的目标数量（0 表示命中即消失）。
@export_range(0, 20, 1) var pierce_count: int = 0
## 命中特效场景。
@export var hit_effect_scene: PackedScene
## 是否受重力影响（俯视视角通常为 false）。
@export var apply_gravity: bool = false
## 重力加速度。注意不能叫 gravity——Area2D 已经有同名原生属性，会冲突。
@export var gravity_strength: float = 0.0

# ============================================================================
# 私有变量
# ============================================================================

## 飞行方向（单位向量）。
var _direction: Vector2 = Vector2.RIGHT
## 携带的攻击数据。
var _attack_data: AttackData
## 元素类型。
var _element: GameEnums.Element = GameEnums.Element.NONE
## 发射者。
var _source: Node = null
## 剩余存活时间。
var _life: float = 0.0
## 已命中次数。
var _hit_count: int = 0
## 当前速度向量。
var _velocity: Vector2 = Vector2.ZERO

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	_life = lifetime
	# 加入 projectile 组，方便测试/清场时统一回收。
	add_to_group(&"projectile")
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		_despawn()
		return
	if apply_gravity:
		_velocity.y += gravity_strength * delta
	else:
		_velocity = _update_direction() * speed
	global_position += _velocity * delta
	if rotate_to_direction and _velocity.length_squared() > 0.001:
		rotation = _velocity.angle()


# ============================================================================
# 公开方法
# ============================================================================

## 发射。direction 会被归一化；data 为 null 时弹道只做表现不造成伤害。
func launch(direction: Vector2, data: AttackData, element: GameEnums.Element, source: Node) -> void:
	_direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	_attack_data = data
	_element = element
	_source = source
	_velocity = _direction * speed
	rotation = _direction.angle()


# ============================================================================
# 私有方法
# ============================================================================

## 每帧的飞行方向。子类（追踪弹）覆写它。
func _update_direction() -> Vector2:
	return _direction


## 构造伤害信息。
func _build_damage() -> DamageInfo:
	if _attack_data == null:
		return null
	var info: DamageInfo = DamageInfo.new()
	var power: float = 0.0
	var crit_chance: float = 0.0
	var crit_damage: float = 1.5
	var actor: Actor = _source as Actor
	if actor != null:
		# 上下文同时带武器类别与元素，让「巨力」「烈焰精通」各自只对号入座。
		var ctx: Dictionary = actor.get_attack_context()
		ctx[&"element"] = _element
		power = actor.get_stat(GameEnums.StatKind.ATTACK_POWER, ctx)
		crit_chance = actor.get_stat(GameEnums.StatKind.CRIT_CHANCE)
		crit_damage = actor.get_stat(GameEnums.StatKind.CRIT_DAMAGE)
	info.amount = _attack_data.damage + power * _attack_data.attack_scaling
	info.element = _element
	info.poise_damage = _attack_data.poise_damage
	info.hitstop = _attack_data.hitstop
	info.shake = _attack_data.shake
	info.hit_sfx = _attack_data.hit_sfx
	info.source = _source
	info.knockback = _direction * _attack_data.knockback
	if randf() < crit_chance:
		info.is_crit = true
		info.amount *= crit_damage
	return info


## 命中处理。
func _on_area_entered(area: Area2D) -> void:
	if area.get_parent() == _source:
		return
	# 受击盒的父节点就是 Actor。
	var target: Actor = area.get_parent() as Actor
	if target == null:
		return
	_apply_hit(target)


func _on_body_entered(body: Node2D) -> void:
	# 撞到世界（墙）也消失。
	if body == _source:
		return
	_despawn()


func _apply_hit(target: Actor) -> void:
	var info: DamageInfo = _build_damage()
	if info == null:
		return
	# 无敌帧 / 已死目标不吃伤害，也不该消耗穿透次数、不该放命中特效——
	# 否则一发穿透弹会被尸体"白吃"掉一格穿透。
	if not target.apply_damage(info):
		return
	_spawn_hit_effect()
	_hit_count += 1
	if destroy_on_hit and _hit_count > pierce_count:
		_despawn()


## 生成命中特效。
func _spawn_hit_effect() -> void:
	var scene: PackedScene = hit_effect_scene
	if scene == null and _attack_data != null:
		scene = _attack_data.hit_effect
	if scene == null:
		return
	var fx: Node2D = scene.instantiate() as Node2D
	if fx == null:
		return
	# 挂到当前关卡根节点，切场景时随关卡一起释放，不会残留到下一关。
	var parent: Node = SceneDirector.get_current_scene()
	if parent == null:
		parent = get_parent()
	parent.add_child(fx)
	fx.global_position = global_position


func _despawn() -> void:
	queue_free()
