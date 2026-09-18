## SavePoint —— 存档点（篝火/水晶）
##
## 【负责什么】
##   交互后：回满血蓝、写入存档、把复活点设到此处。可重复使用但有冷却。
##   这是"降低挫败感"的关键设施，每关必须在关底门前放一个。
##
## 【挂哪个节点】
##   scenes/world/save_point.tscn 的根节点（继承 Interactable）。
##
## 【依赖谁】
##   GameState（写档 + 复活点）、Actor（治疗）。
class_name SavePoint
extends Interactable

# ============================================================================
# @export
# ============================================================================

## 激活时的光效场景（可选）。
@export var activate_effect: PackedScene
## 激活后的自发光颜色。
@export var glow_color: Color = Color(1.0, 0.9, 0.5)

# ============================================================================
# 私有变量
# ============================================================================

## 是否已激活过（首次激活做特效）。
var _activated: bool = false

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	super._ready()
	prompt_text = "休息（回复 + 存档）"
	cooldown = 1.0
	if interact_sfx == null:
		interact_sfx = load("res://assets/audio/sfx/Success1.wav")


# ============================================================================
# 私有方法
# ============================================================================

func _on_interact(actor: Node) -> void:
	var target: Actor = actor as Actor
	if target == null:
		return
	# 回满血蓝。
	target.heal(target.get_max_health())
	target.restore_mana(target.get_max_mana())
	EventBus.floating_text_requested.emit("已休息", global_position + Vector2(0, -16), Color(1, 0.95, 0.6))
	# 记录复活点并写档。
	# 【必须先判空】SceneDirector.get_current_level() 在"没走 SceneDirector 加载关卡"时
	# 返回 null（编辑器里单独 F5 跑某个关卡场景、工具脚本直接实例化本场景都会这样），
	# 未判空就直接 `.id` 会抛空引用，后面的 save_game() 也不会执行——
	# 表现为"存档点一交互就崩，且进度全没写进去"。
	var level: LevelData = SceneDirector.get_current_level()
	if level == null:
		push_error("[SavePoint] 当前关卡未知（未经 SceneDirector 加载），无法记录复活点")
		EventBus.toast_requested.emit("存档失败：关卡信息缺失")
		return
	GameState.set_respawn_point(level.id, global_position)
	GameState.save_game()
	EventBus.toast_requested.emit("已保存进度")
	_play_activate_effect()


## 首次激活时播放特效并点亮自身。
func _play_activate_effect() -> void:
	if _activated:
		return
	_activated = true
	var sprite: Sprite2D = get_node_or_null("Sprite") as Sprite2D
	if sprite != null:
		# 点亮：加一个脉动的 self_modulate，表示"已激活"。
		sprite.self_modulate = glow_color
		var tween: Tween = create_tween().set_loops()
		tween.tween_property(sprite, "self_modulate", glow_color * 1.4, 0.9)
		tween.tween_property(sprite, "self_modulate", glow_color, 0.9)
	if activate_effect != null:
		var fx: Node2D = activate_effect.instantiate() as Node2D
		if fx != null:
			add_child(fx)
