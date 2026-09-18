## FloatingText —— 伤害飘字
##
## 【负责什么】
##   在世界坐标处弹出一个数字/文字，向上飘并淡出。暴击用更大更亮的字。
##
## 【挂哪个节点】
##   scenes/ui/floating_text.tscn 的根节点（Node2D + Label）。
##
## 【依赖谁】
##   无。纯表现，由 EventBus.floating_text_requested 驱动生成。
##
## 【怎么扩展】
##   想加"治疗绿色 +/ 伤害红色 -"只需在生成时传不同 color。
class_name FloatingText
extends Node2D

# ============================================================================
# @export
# ============================================================================

## 上飘距离（像素）。
@export_range(4.0, 120.0, 1.0) var rise_distance: float = 26.0
## 存活时间（秒）。
@export_range(0.1, 3.0, 0.05, "suffix:s") var lifetime: float = 0.75
## 水平漂移（像素），让多个飘字不重叠。
@export_range(0.0, 60.0, 1.0) var drift: float = 10.0
## 基础字号。
@export_range(6, 48, 1) var base_font_size: int = 10
## 暴击时的字号倍率。
@export_range(1.0, 3.0, 0.1) var crit_size_mult: float = 1.6

# ============================================================================
# 私有变量
# ============================================================================

## 显示文本的 Label。
var _label: Label
## 补间。
var _tween: Tween

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	# 飘字可能在暂停态（三选一/背包/暂停菜单）里生成——比如暂停瞬间的一次命中。
	# 设成 ALWAYS 才能让它的 Tween 继续推进并按时自毁，否则会永久挂在屏幕上。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label = get_node_or_null("Label") as Label
	if _label == null:
		_label = Label.new()
		_label.name = "Label"
		add_child(_label)
	# 像素字体放大时不要做插值平滑，否则字会糊。
	_label.add_theme_font_size_override("font_size", base_font_size)


# ============================================================================
# 公开方法
# ============================================================================

## 初始化飘字。text 为显示内容，color 为颜色，is_crit 决定是否放大。
func setup(text: String, color: Color, is_crit: bool = false) -> void:
	if _label == null:
		_label = get_node_or_null("Label") as Label
	if _label == null:
		return
	_label.text = text
	_label.modulate = color
	if is_crit:
		_label.add_theme_font_size_override("font_size", int(base_font_size * crit_size_mult))
	# 居中显示：让数字以世界坐标为锚点居中。
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(-40, -8)
	_label.size = Vector2(80, 16)
	_animate()


# ============================================================================
# 私有方法
# ============================================================================

## 上飘 + 淡出 + 随机横向漂移。
func _animate() -> void:
	# 随机水平偏移，避免同时命中多个目标时数字完全重叠。
	var offset_x: float = randf_range(-drift, drift)
	# 两条并行动画：位置上升 + 透明度淡出。
	# 注意不要把 queue_free 挂在 set_parallel(true) 的 tween 上——并行模式下
	# 回调会与动画同时开始（立刻释放）。所以释放交给下面的契约计时器。
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "position", position + Vector2(offset_x, -rise_distance), lifetime)
	_tween.tween_property(_label, "modulate:a", 0.0, lifetime).set_delay(lifetime * 0.4)
	# 契约：lifetime 后一定自毁，不依赖上面的补间是否被打断。
	await get_tree().create_timer(lifetime, true, false, true).timeout
	if is_instance_valid(self):
		queue_free()
	else:
		push_warning("[FloatingText] 计时器醒来时节点已失效")
