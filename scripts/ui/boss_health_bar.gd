## BossHealthBar —— Boss 血条
##
## 【负责什么】
##   屏幕底部显示当前 Boss 的名字与血量。Boss 出现时淡入，死亡时淡出。
##
## 【挂哪个节点】
##   scenes/ui/boss_health_bar.tscn 的根节点（CanvasLayer），由 Boot 常驻挂载。
##
## 【依赖谁】
##   EventBus.scene_changed（找 Boss）、Actor.health_updated。
class_name BossHealthBar
extends CanvasLayer

# ============================================================================
# @export
# ============================================================================

## 容器。
@export var container_path: NodePath
## 名字标签。
@export var name_path: NodePath
## 血条。
@export var bar_path: NodePath

# ============================================================================
# 私有变量
# ============================================================================

var _container: Control
var _name_label: Label
var _bar: ProgressBar
## 当前绑定的 Boss。
var _boss: Actor
## 血条淡入/淡出补间。需要在绑定新 Boss 时作废旧的那个，
## 否则它挂着的 _unbind 回调会把新血条一起隐藏掉（见 _bind）。
var _fade_tween: Tween

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	if not container_path.is_empty():
		_container = get_node_or_null(container_path) as Control
	if not name_path.is_empty():
		_name_label = get_node_or_null(name_path) as Label
	if not bar_path.is_empty():
		_bar = get_node_or_null(bar_path) as ProgressBar
	if _container != null:
		_container.visible = false
	EventBus.scene_changed.connect(_on_scene_changed)
	# 登记进 UI 注册表：调用方按 id 访问，不再按树路径查名。
	UIRegistry.register(&"boss_health_bar", self)


# ============================================================================
# 公开方法
# ============================================================================

## 设置"局内激活"状态。回主菜单时置 false：收起血条并断开与 Boss 的绑定
## （Boss 随关卡一起被释放，留着绑定就是悬空引用）。
func set_active(active: bool) -> void:
	visible = active
	if not active:
		force_close()


## 回主菜单时收起血条并断开与 Boss 的绑定。
func force_close() -> void:
	visible = false
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_unbind()


# ============================================================================
# 私有方法
# ============================================================================

## 换关卡后找新的 Boss。
func _on_scene_changed(_scene: Node) -> void:
	_unbind()
	# 等一帧让 Boss 生成完。
	await get_tree().process_frame
	await get_tree().process_frame
	for enemy: Node in get_tree().get_nodes_in_group(&"enemy"):
		var e: EnemyBase = enemy as EnemyBase
		if e != null and e.enemy_data != null and e.enemy_data.is_boss:
			_bind(e)
			return


## 绑定 Boss 并显示血条。
##
## 【为什么先 kill 上一个淡出 tween】_on_boss_died 会挂一个
## `tween_callback(_unbind)`：淡出 0.5 秒后把血条隐藏。
## 若玩家在 Boss 死后的 0.5 秒内就进了下一个 Boss 房（换关卡 / 快速重开），
## _bind 刚把新血条点亮，紧接着**旧 tween 的 callback 才到期**，
## 于是把刚绑好的新血条又 _unbind() 隐藏掉——新 Boss 一场血条都不显示。
func _bind(boss: EnemyBase) -> void:
	# 作废上一个 Boss 遗留的淡出回调。
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_boss = boss
	if _name_label != null:
		_name_label.text = boss.enemy_data.display_name
	if _bar != null:
		_bar.max_value = boss.get_max_health()
		_bar.value = boss.get_health()
	if _container != null:
		_container.visible = true
		_container.modulate.a = 0.0
		# 【为什么 tween 要挂 ALWAYS】Boss 出场往往伴随 hitstop / 过场（paused=true）。
		#   默认 PAUSABLE 的 tween 在暂停中不推进 → 血条永远停在 a=0 的透明状态，
		#   玩家以为"Boss 血条没出来"。入场动画必须能在暂停中跑完。
		_fade_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_fade_tween.tween_property(_container, "modulate:a", 1.0, 0.4)
	boss.health_updated.connect(_on_boss_health_updated.bind(boss))
	boss.died.connect(_on_boss_died.bind(boss))


## 解绑。
func _unbind() -> void:
	_boss = null
	if _container != null:
		_container.visible = false


# ============================================================================
# 信号回调
# ============================================================================

func _on_boss_health_updated(current: float, maximum: float, boss: Actor) -> void:
	if boss != _boss:
		return
	if _bar != null:
		_bar.max_value = maximum
		_bar.value = current


func _on_boss_died(_killer: Node, boss: Actor) -> void:
	if boss != _boss:
		return
	if _container != null:
		if _fade_tween != null and _fade_tween.is_valid():
			_fade_tween.kill()
		_fade_tween = create_tween()
		_fade_tween.tween_property(_container, "modulate:a", 0.0, 0.5)
		_fade_tween.tween_callback(_unbind)
