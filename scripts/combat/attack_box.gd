## AttackBox —— 攻击判定盒
##
## 【负责什么】
##   挂在攻击者身上（或作为攻击时的临时节点），在"判定持续"窗口内检测受击盒。
##   它本身不含任何数值——数值来自构造它的 AttackData + 攻击者属性。
##
## 【挂哪个节点】
##   作为 Area2D 挂在攻击者场景里，由 AttackController 在判定帧启用/禁用。
##   必须在 .tscn 里配好 CollisionShape2D 和碰撞层。
##
## 【依赖谁】
##   AttackData、DamageInfo、Actor（取攻击力）。
##
## 【怎么扩展】
##   想做"多段判定"就多次开关 enabled；想做"穿透"就改 collision_mask。
##
## 【碰撞方向约定 —— 重要】
##   攻击盒是**主动方**：它 monitoring=true，用 collision_mask 去匹配目标的受击盒层。
##   受击盒是被动方：monitorable=true、monitoring=false。这样一次判定只走一条路径，
##   不会出现"攻受双方各触发一次"导致的双倍伤害。
class_name AttackBox
extends Area2D

# ============================================================================
# 信号
# ============================================================================

## 确认命中（伤害已结算）。武器/角色据此做吸血、特效、加怒等反应。
signal hit_confirmed(target: Actor, info: DamageInfo)

# ============================================================================
# @export
# ============================================================================

## 攻击数据。由 AttackController 在每次攻击时赋值。
@export var attack_data: AttackData
## 攻击者。用于取攻击力、暴击率，以及区分敌我。
@export var attacker: NodePath
## 是否已对同一目标生效过（防止一次挥砍对同一敌人重复结算）。
@export var hit_once_per_swing: bool = true

# ============================================================================
# 私有变量
# ============================================================================

## 本次挥砍已命中的目标集合。
var _hit_targets: Array[Node] = []
## 缓存的攻击者引用。
var _attacker: Node

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	# 判定盒默认关闭，由 AttackController 在判定帧打开。
	monitoring = false
	if not attacker.is_empty():
		_attacker = get_node_or_null(attacker)
	if _attacker == null:
		_attacker = get_parent()
	# 攻击盒是主动检测方：命中受击盒后自己结算伤害。
	area_entered.connect(_on_area_entered)


# ============================================================================
# 公开方法
# ============================================================================

## 注入攻击者。武器场景化之后，判定盒属于武器，需要外部告诉它"谁在挥"。
func set_attacker(new_attacker: Node) -> void:
	_attacker = new_attacker


## 开始一次挥砍：清空命中记录并开启检测。
func begin_swing(data: AttackData) -> void:
	attack_data = data
	_hit_targets.clear()
	monitoring = true


## 结束挥砍：关闭检测。
func end_swing() -> void:
	monitoring = false
	_hit_targets.clear()


## 构造一份 DamageInfo 给受击方。受击方 Actor 调用它。
func build_damage_info() -> DamageInfo:
	if attack_data == null:
		return null
	var info: DamageInfo = DamageInfo.new()
	# 伤害 = 基础伤害 + 攻击力 * 缩放。攻击力走 Actor.get_stat，保证词条生效。
	var attack_power: float = 0.0
	var crit_chance: float = 0.0
	var crit_damage: float = 1.5
	var source_actor: Actor = _attacker as Actor
	if source_actor != null:
		# 带上攻击上下文，让限定类词条（如"巨力：双手武器"）正确过滤。
		attack_power = source_actor.get_stat(GameEnums.StatKind.ATTACK_POWER, source_actor.get_attack_context())
		crit_chance = source_actor.get_stat(GameEnums.StatKind.CRIT_CHANCE)
		crit_damage = source_actor.get_stat(GameEnums.StatKind.CRIT_DAMAGE)
	info.amount = attack_data.damage + attack_power * attack_data.attack_scaling
	info.element = attack_data.element
	info.poise_damage = attack_data.poise_damage
	info.hitstop = attack_data.hitstop
	info.shake = attack_data.shake
	info.hit_effect = attack_data.hit_effect
	info.hit_sfx = attack_data.hit_sfx
	info.source = _attacker
	# 击退方向：从攻击者指向目标，保证"打飞"方向正确。
	var dir: Vector2 = global_position - (_attacker as Node2D).global_position if _attacker is Node2D else Vector2.RIGHT
	if dir.length_squared() < 0.001:
		dir = Vector2.RIGHT
	info.knockback = dir.normalized() * attack_data.knockback
	# 暴击判定放在攻击方，因为暴击率属于攻击者属性。
	if randf() < crit_chance:
		info.is_crit = true
		info.amount *= crit_damage
	return info


## 标记某目标已被本次挥砍命中（用于穿透攻击时不重复打）。
func mark_hit(target: Node) -> void:
	if hit_once_per_swing:
		_hit_targets.append(target)


## 该目标本次挥砍是否已命中过。
func has_hit(target: Node) -> bool:
	return hit_once_per_swing and _hit_targets.has(target)


# ============================================================================
# 信号回调
# ============================================================================

## 攻击盒命中目标受击盒。这是伤害结算的唯一入口。
func _on_area_entered(area: Area2D) -> void:
	var target: Actor = area.get_parent() as Actor
	if target == null or target == _attacker:
		return
	if has_hit(target):
		return
	mark_hit(target)
	var info: DamageInfo = build_damage_info()
	if info == null:
		return
	# 【必须检查返回值】apply_damage() 在目标处于无敌帧 / 已死 / 溶解中时什么都不做，
	# 返回 false。旧实现不检查，照常往下走飘字、顿帧、震屏、hit_landed 与吸血，
	# 于是"砍尸体"每次都飘伤害数字、触发顿帧，带吸血词条时还能靠砍尸体回血，
	# 连击计数与教程的"命中"判定也跟着虚高。
	if not target.apply_damage(info):
		return
	# 飘字：暴击用金色大字，普通用白色。
	var text_color: Color = Color(1.0, 0.85, 0.3) if info.is_crit else Color(1, 1, 1)
	var text: String = "%d" % int(round(info.amount))
	if info.is_crit:
		text += "!"
	EventBus.floating_text_requested.emit(text, target.global_position + Vector2(0, -12), text_color)
	# 命中反馈：顿帧 + 屏幕震动。这是"打击感"三件套的另两件。
	EventBus.hit_stop_requested.emit(info.hitstop)
	EventBus.camera_shake_requested.emit(info.shake, 0.12)
	EventBus.hit_landed.emit(_attacker, target, info.amount, info.knockback)
	# 吸血：从攻击者属性取比例，按实际伤害转化。
	var attacker_actor: Actor = _attacker as Actor
	if attacker_actor != null:
		var steal: float = attacker_actor.get_stat(GameEnums.StatKind.LIFE_STEAL)
		if steal > 0.0:
			attacker_actor.heal(info.amount * steal)
	# 通知武器/角色：这一下打实了。
	hit_confirmed.emit(target, info)
