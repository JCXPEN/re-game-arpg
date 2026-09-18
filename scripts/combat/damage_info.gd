## DamageInfo —— 一次伤害结算的载体
##
## 【负责什么】
##   把"这一下打出去的所有信息"打包成一个对象，在攻击盒 → 受击盒 → 角色 之间传递。
##   用对象而不是 Dictionary，是为了拿到静态类型检查，字段写错编译期就报错。
##
## 【挂哪个节点】
##   不是节点，是 RefCounted。每次命中 new 一个，用完即弃（有引用计数自动回收）。
##
## 【依赖谁】
##   GameEnums.Element。
##
## 【怎么扩展】
##   需要"破甲/吸血/元素附着"等新机制时，在这里加字段，并在 Actor.apply_damage 里
##   读取。不要用 Dictionary 传，那会丢掉类型安全。
class_name DamageInfo
extends RefCounted

# ============================================================================
# 公开变量
# ============================================================================

## 基础伤害（已含攻击力缩放，但还没减防御、没算暴击）。
var amount: float = 0.0
## 元素类型。
var element: GameEnums.Element = GameEnums.Element.NONE
## 击退向量（方向已归一化，长度即力度）。
var knockback: Vector2 = Vector2.ZERO
## 削韧值：用于判断能否打断目标。
var poise_damage: float = 0.0
## 命中顿帧时长（秒）。
var hitstop: float = 0.05
## 屏幕震动强度。
var shake: float = 2.0
## 攻击者。用于吸血、仇恨、击杀归属。可能为 null（陷阱等环境伤害）。
var source: Node = null
## 是否暴击（由攻击方在结算时决定）。
var is_crit: bool = false
## 命中特效场景（由攻击数据带入）。
var hit_effect: PackedScene = null
## 命中音效。
var hit_sfx: AudioStream = null


# ============================================================================
# 公开方法
# ============================================================================

## 复制一份。命中多个目标时每个目标都要独立结算（避免暴击结果互相污染）。
func duplicate_info() -> DamageInfo:
	var copy: DamageInfo = DamageInfo.new()
	copy.amount = amount
	copy.element = element
	copy.knockback = knockback
	copy.poise_damage = poise_damage
	copy.hitstop = hitstop
	copy.shake = shake
	copy.source = source
	copy.is_crit = is_crit
	copy.hit_effect = hit_effect
	copy.hit_sfx = hit_sfx
	return copy
