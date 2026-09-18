## AreaSpell —— 范围法术（AOE）
##
## 【负责什么】
##   在目标点生成一片范围伤害：先播放蓄力/爆发特效，再对范围内敌人结算一次伤害，
##   然后自毁。冰环、落雷、地裂都用它。
##
## 【挂哪个节点】
##   scenes/fx/area_spell.tscn 的根节点（Area2D）。
##
## 【依赖谁】
##   AttackData、DamageInfo、EventBus。
##
## 【怎么扩展】
##   想加"持续伤害区域"，把 _apply_damage_once 改成按 tick 间隔重复调用。
class_name AreaSpell
extends Area2D

# ============================================================================
# @export
# ============================================================================

## 生效延迟（秒）：给特效一点时间演完再结算伤害。
@export_range(0.0, 2.0, 1.0 / 60.0, "suffix:s") var delay: float = 0.08
## 整个法术的存活时间（秒），到点自毁。
@export_range(0.05, 10.0, 0.05, "suffix:s") var lifetime: float = 0.9
## 是否只对每个目标结算一次。
@export var hit_once: bool = true

# ============================================================================
# 私有变量
# ============================================================================

var _attack_data: AttackData
var _element: GameEnums.Element = GameEnums.Element.NONE
var _source: Node = null
var _elapsed: float = 0.0
var _damage_done: bool = false
var _hit_targets: Array[Actor] = []

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	# 范围法术自己主动扫描（它是主动方），受击盒是被动方。
	monitoring = true
	area_entered.connect(_on_area_entered)


func _process(delta: float) -> void:
	_elapsed += delta
	if not _damage_done and _elapsed >= delay:
		_damage_done = true
		_apply_damage_to_overlaps()
	if _elapsed >= lifetime:
		queue_free()


# ============================================================================
# 公开方法
# ============================================================================

## 由 SpellCaster 调用，注入伤害与来源。
func configure(attack_data: AttackData, element: GameEnums.Element, source: Node) -> void:
	_attack_data = attack_data
	_element = element
	_source = source


# ============================================================================
# 私有方法
# ============================================================================

## 延迟结束后对当前重叠的所有目标结算伤害。
func _apply_damage_to_overlaps() -> void:
	for area: Area2D in get_overlapping_areas():
		var target: Actor = area.get_parent() as Actor
		if target == null or target == _source:
			continue
		if hit_once and _hit_targets.has(target):
			continue
		_hit_targets.append(target)
		_damage(target)


## 延迟期间走进范围的目标也要被打到（在 area_entered 里处理）。
func _on_area_entered(area: Area2D) -> void:
	if not _damage_done:
		return
	var target: Actor = area.get_parent() as Actor
	if target == null or target == _source:
		return
	if hit_once and _hit_targets.has(target):
		return
	_hit_targets.append(target)
	_damage(target)


func _damage(target: Actor) -> void:
	if _attack_data == null:
		return
	var info: DamageInfo = DamageInfo.new()
	var power: float = 0.0
	var actor: Actor = _source as Actor
	if actor != null:
		var ctx: Dictionary = actor.get_attack_context()
		ctx[&"element"] = _element
		power = actor.get_stat(GameEnums.StatKind.ATTACK_POWER, ctx)
	info.amount = _attack_data.damage + power * _attack_data.attack_scaling
	info.element = _element
	info.poise_damage = _attack_data.poise_damage
	info.hitstop = _attack_data.hitstop
	info.shake = _attack_data.shake
	info.hit_sfx = _attack_data.hit_sfx
	info.source = _source
	info.knockback = (target.global_position - global_position).normalized() * _attack_data.knockback
	# 与 AttackBox 同理：只有在真的造成伤害时才做打击感反馈，
	# 否则无敌帧内的目标会让法术区域持续顿帧、震屏（尤其持续型区域）。
	if not target.apply_damage(info):
		return
	EventBus.hit_stop_requested.emit(_attack_data.hitstop)
	EventBus.camera_shake_requested.emit(_attack_data.shake, 0.14)
