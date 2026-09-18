## HealSpring —— 治愈泉
##
## 【负责什么】
##   踩上去自动恢复一定比例生命，然后进入冷却。比存档点轻量，用于战斗中段补给。
##
## 【挂哪个节点】
##   scenes/world/heal_spring.tscn 的根节点（继承 Interactable）。
##
## 【依赖谁】
##   Actor（治疗）。
class_name HealSpring
extends Interactable

# ============================================================================
# @export
# ============================================================================

## 恢复的最大生命比例。
@export_range(0.05, 1.0, 0.05) var heal_ratio: float = 0.5
## 恢复的最大法力比例。
@export_range(0.0, 1.0, 0.05) var mana_ratio: float = 0.5

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	super._ready()
	# 踩上去自动触发，不需要按键。
	requires_input = false
	cooldown = 8.0
	if interact_sfx == null:
		interact_sfx = load("res://assets/audio/sfx/Spirit.wav")


# ============================================================================
# 私有方法
# ============================================================================

func _on_interact(actor: Node) -> void:
	var target: Actor = actor as Actor
	if target == null:
		return
	# 满血时不消耗冷却，避免站着白刷。
	#
	# 【为什么这里直接 return、绝不能碰 _cooldown_timer】
	#   `requires_input = false` 时 Interactable 是**每帧**尝试交互的。
	#   旧实现把 `_cooldown_timer = 0.0` 写在这个分支里，等于每帧都把自己刚设的
	#   8 秒冷却清掉 → 计时器永远是 0 → 下一帧又通过冷却检查 → 再清一次……
	#   形成"站在泉上满血时每帧触发一次"的死循环，音效每秒播约 60 次。
	#   正确做法：满血就什么都不做，把冷却计时器留给它自己正常倒数。
	if target.get_health() >= target.get_max_health() and target.get_mana() >= target.get_max_mana():
		return
	target.heal(target.get_max_health() * heal_ratio)
	target.restore_mana(target.get_max_mana() * mana_ratio)
	EventBus.floating_text_requested.emit("+%d" % int(target.get_max_health() * heal_ratio), global_position + Vector2(0, -14), Color(0.5, 1.0, 0.5))
	EventBus.toast_requested.emit("治愈泉恢复了你的状态")
