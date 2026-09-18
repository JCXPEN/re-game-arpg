## Ability —— 技能基类（主动 + 被动统一）
##
## 【负责什么】
##   所有技能的公共骨架：读取 AbilityData、检查释放条件、扣除消耗、执行效果、
##   进入冷却。子类只实现 _execute()，不用重复写条件与消耗逻辑。
##
## 【挂哪个节点】
##   不是场景节点，运行时由 PlayerCombat 动态创建并挂到玩家下（见 Ability.create）。
##
## 【依赖谁】
##   AbilityData、Actor、EventBus。
##
## 【怎么扩展】
##   新技能 = 继承本类 + 覆写 _execute()。被动技能覆写 _apply_passive()。
##   数值全部来自 AbilityData，不要在子类里写死。
class_name Ability
extends Node

# ============================================================================
# 信号
# ============================================================================

## 技能成功释放。
signal executed()
## 技能释放失败（条件不足）。
signal failed(reason: String)

# ============================================================================
# @export
# ============================================================================

## 技能数据。运行时由 create() 注入。
@export var data: AbilityData

# ============================================================================
# 私有变量
# ============================================================================

## 技能释放者。
var _caster: Actor
## 释放者的精灵（用于朝向/位置）。
var _sprite: ActorSprite
## 冷却剩余。
var _cooldown_timer: float = 0.0

# ============================================================================
# 生命周期
# ============================================================================

func _process(delta: float) -> void:
	_cooldown_timer = maxf(0.0, _cooldown_timer - delta)


# ============================================================================
# 公开方法 —— 静态工厂
# ============================================================================

## 创建技能实例。根据数据里的标记选择对应子类：
## 目前用"是否有 effect_scene + 是否为主动"做简单分派，后续可加 kind 字段。
static func create(ability_data: AbilityData, caster: Actor, sprite: ActorSprite) -> Ability:
	if ability_data == null:
		return null
	var instance: Ability = Ability.new()
	instance.data = ability_data
	instance._caster = caster
	instance._sprite = sprite
	instance.name = "Ability_%s" % ability_data.display_name
	return instance


# ============================================================================
# 公开方法 —— 释放
# ============================================================================

## 检查是否满足释放条件。返回 true 表示可以放。
func can_execute() -> bool:
	if data == null or _caster == null:
		return false
	if _cooldown_timer > 0.0:
		return false
	# 等级条件。
	if _caster.get("level") != null and int(_caster.get("level")) < data.required_level:
		return false
	# 血量条件（残血技能）。
	if data.required_health_ratio > 0.0 and _caster.get_health_ratio() > data.required_health_ratio:
		return false
	# 蓝量条件。
	if _caster.get_mana() < data.mana_cost:
		return false
	# 硬直/死亡时不能放。
	if _caster.is_dead() or _caster.is_stunned():
		return false
	return true


## 尝试释放。成功返回 true。
##
## 【为什么是协程】技能效果（_execute）常带 await —— 播施法动画、等生成物落地、
##   分阶段结算。本函数必须 await 它，否则父节点在同帧走完 _start_cooldown 的
##   `await process_frame` + `queue_free()` 之后，技能节点就没了，
##   `_execute` 里跨帧的协程会被静默丢弃（不报错，但后半段效果永不发生）。
func try_execute() -> bool:
	if not can_execute():
		failed.emit("条件不满足")
		return false
	if not _caster.spend_mana(data.mana_cost):
		failed.emit("法力不足")
		return false
	# 先等效果跑完，再进冷却与自毁——顺序很重要：
	# 反过来的话，冷却已经开始但效果还在跑，玩家能在这段窗口里再放一次。
	await _execute()
	_start_cooldown()
	executed.emit()
	AudioManager.play_sfx(data.cast_sfx)
	return true


## 冷却剩余比例 0~1。
func get_cooldown_ratio() -> float:
	if data == null or data.cooldown <= 0.0:
		return 0.0
	return clampf(_cooldown_timer / data.cooldown, 0.0, 1.0)


## 被动技能生效入口。由 PlayerCombat/装备系统在获得技能时调用。
func apply_passive() -> void:
	if data == null or data.is_active or not data.apply_on_equip:
		return
	_apply_passive()


# ============================================================================
# 私有方法 —— 供子类覆写
# ============================================================================

## 技能的实际效果。**子类必须覆写**。
func _execute() -> void:
	# 基类默认只生成 effect_scene（如果配了），覆盖大多数简单技能。
	if data.effect_scene != null and _caster != null:
		var fx: Node2D = data.effect_scene.instantiate() as Node2D
		if fx != null:
			_caster.get_parent().add_child(fx)
			fx.global_position = _caster.global_position


## 被动效果。子类覆写。
func _apply_passive() -> void:
	pass


## 进入冷却。应用释放者的冷却缩减。
func _start_cooldown() -> void:
	var rate: float = _caster.get_stat(GameEnums.StatKind.COOLDOWN_RATE) if _caster != null else 0.0
	_cooldown_timer = data.cooldown * (1.0 - clampf(rate, 0.0, 0.75))
	# 技能实例用完即弃，但被动技能需要常驻，所以这里只对主动技能自毁。
	if data.is_active:
		# 延迟一帧销毁，保证 _execute 里的 await/动画有时间跑。
		await get_tree().process_frame
		queue_free()
