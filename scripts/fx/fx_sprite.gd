## ProjectileSprite —— 弹道/特效帧动画播放器
##
## 【负责什么】
##   素材包的 FX 都是一条横向帧带（如 160×32 = 5 帧 32×32）。本组件按 hframes
##   自动切帧循环播放，播完可选自毁。
##
## 【挂哪个节点】
##   挂在 Sprite2D 上（projectile.tscn / area_spell.tscn / hit_effect.tscn 的子节点）。
##
## 【依赖谁】
##   无。纯表现。
##
## 【怎么扩展】
##   需要"播完停在最后一帧"，把 loop 设为 false 且 destroy_on_finish 设为 false。
class_name FxSprite
extends Sprite2D

# ============================================================================
# @export
# ============================================================================

## 播放速度（帧/秒）。
@export_range(1.0, 60.0, 1.0) var fps: float = 14.0
## 是否循环。
@export var loop: bool = true
## 播完是否自毁（连同父节点一起释放）。
@export var destroy_on_finish: bool = true
## 是否随机起始帧（多个同类特效同时出现时不整齐划一）。
@export var random_start: bool = true

# ============================================================================
# 私有变量
# ============================================================================

var _frame_index: float = 0.0

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	if random_start and hframes > 1:
		_frame_index = randi() % hframes
	frame = int(_frame_index)


func _process(delta: float) -> void:
	if hframes <= 1:
		return
	_frame_index += fps * delta
	if _frame_index >= float(hframes):
		if loop:
			_frame_index = fmod(_frame_index, float(hframes))
		else:
			frame = hframes - 1
			set_process(false)
			if destroy_on_finish:
				# 销毁父节点：特效场景通常整个一起消失。
				var target: Node = get_parent()
				if target == self or target == null:
					target = self
				target.queue_free()
			return
	frame = int(_frame_index)
