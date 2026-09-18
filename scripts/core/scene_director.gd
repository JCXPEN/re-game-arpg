## SceneDirector —— 场景/关卡切换服务（Autoload 单例）
##
## 【负责什么】
##   管理"城镇 → 野外 → 地牢 → Boss 房 → 回城"的关卡流转：切换场景、把玩家
##   放到正确的入口点、传递关卡上下文（当前层数、是否清怪）。
##
## 【挂哪个节点】
##   project.godot 的 [autoload] 注册为 `SceneDirector`。
##
## 【依赖谁】
##   DataRegistry（查 LevelData）、EventBus（收发切换事件）。
##
## 【怎么扩展】
##   新增转场特效：在 _perform_change 里加一个过渡动画节点即可。
##   关卡表不写死在这里——通过 DataRegistry 扫描 res://data/levels 得到。
extends Node

# ============================================================================
# @export
# ============================================================================

## 切换场景时的遮罩动画时长（秒），收拢与绽放各算一次。0 表示不遮。
## 【为什么保持 0.18】大量工具脚本按固定帧数等待转场结束（40~60 帧），
##   时长与它们强耦合；转场的手感改由 scripts/core/transition.gd 的动画曲线
##   与视觉层次承担，不动这里的数值，避免波及既有回归套件。
@export_range(0.0, 2.0, 0.05, "suffix:s") var fade_time: float = 0.18
## 玩家场景。切换后由本服务实例化并放进新关卡的入口点。
## 默认指向项目里的玩家场景；换主角模型时只改这里或换 .tscn。
@export var player_scene: PackedScene = preload("res://scenes/player/player.tscn")
## 转场用的 CanvasLayer 场景（内部懒建 ColorRect + 遮罩 shader）。为空则不遮屏。
@export var transition_scene: PackedScene = preload("res://scenes/core/transition.tscn")

# ============================================================================
# 私有变量
# ============================================================================

## 当前关卡的 LevelData。
var _current_level: LevelData
## 当前关卡场景实例。
var _current_scene: Node
## 正在切换中，防止连点门导致重复加载。
var _changing: bool = false
## 切换代次。每次"开始一次切换"或"强制取消（回主菜单）"都 +1。
## 协程在**每个 await 之后**比对代次：对不上就说明自己已被取消，直接返回，
## 绝不再去碰 `_current_scene` / BGM / 玩家。见 `detach_level()`。
var _generation: int = 0
## 转场遮罩层实例。
var _transition: CanvasLayer
## 下一次生成玩家时使用的坐标覆盖（用于"从存档点复活"）。
var _spawn_override: Vector2 = Vector2.ZERO
## 是否有待用的坐标覆盖。
var _has_spawn_override: bool = false

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	EventBus.scene_change_requested.connect(change_to_level)


# ============================================================================
# 公开方法
# ============================================================================

## 按关卡 id 切换场景。entry_point 为进入点名称（对应关卡里的 Marker2D 名字）。
##
## 【为什么整个过程带"代次"校验】本函数是协程：`_fade_out` / `_swap_scene` /
##   `_fade_in` 里都有 await，一个切换可能横跨十几帧。玩家完全可能在转场中途
##   （尤其加载卡帧时）按 Esc 返回主菜单。若不管，那条被"抛弃"的协程醒来后仍会
##   继续往下走：把关卡场景挂回 root、生成玩家、把关卡 BGM 重新播起来
##   —— 于是主菜单背后活着一局游戏，BGM 也变成关卡曲（用户报的"BGM 与场景不匹配"
##   与"UI 状态错乱"的直接来源）。
##   代次校验就是给这类在途协程一个"撤回"语义：只要 `detach_level()` 被调用过，
##   旧协程在每个 await 后都会发现代次变了并立刻退出。
func change_to_level(level_id: StringName, entry_point: StringName = &"") -> void:
	if _changing:
		return
	var level: LevelData = DataRegistry.get_level(level_id)
	if level == null:
		push_error("[SceneDirector] 找不到关卡：%s" % level_id)
		return
	_changing = true
	_generation += 1
	var gen: int = _generation
	# 用 try/finally 的思路：无论中途发生什么（节点被释放、转场被中断），
	# 都必须把 _changing 复位，否则之后所有场景切换都会被静默丢弃。
	await _fade_out(gen)
	if gen != _generation:
		return
	# 【为什么必须 await】_swap_scene() 内含两处 `await get_tree().process_frame`，
	# 是协程。裸调用不会等它，于是下面的 _fade_in() 与 _changing = false 会抢在
	# 换场景之前执行：`await change_to_level(...)` 拿到的仍是旧关卡，
	# scene_changed 也还没发出——从"城镇 → 野外"之后立刻读当前关卡会读到 town。
	# 默认 fade_time=0.18s 时靠时间差侥幸掩盖，一旦 fade_time 配成 0 就必然暴露。
	await _swap_scene(level, entry_point, gen)
	if gen != _generation:
		return
	await _fade_in(gen)
	if gen != _generation:
		return
	_changing = false


## 取当前关卡数据。
func get_current_level() -> LevelData:
	return _current_level


## 取当前关卡场景根节点。
func get_current_scene() -> Node:
	return _current_scene


## 卸掉当前关卡并**清空引用**（回主菜单 / 换局时用）。
##
## 【为什么必须清引用而不是只 queue_free】
##   `_current_scene` / `_current_level` 是本服务的跨场景状态。
##   只释放节点不清引用，`get_current_level()` 会继续返回**已经死掉的**
##   关卡数据，新局读它是脏的；`get_current_scene()` 也会返回野指针
##   （is_instance_valid 为 false，但非 null），调用方一碰就炸。
##   任何"退出这一局"的路径都必须走这里。
func detach_level() -> void:
	# 【先作废所有在途切换】回主菜单 / 换局时，可能正有一次 change_to_level 协程
	#   卡在某个 await 上。不 +1 的话它醒来会把关卡挂回 root、生成玩家、重播关卡
	#   BGM —— 主菜单背后就此活着一局游戏。代次 +1 是给它们的"撤回"信号。
	_generation += 1
	if _current_scene != null and is_instance_valid(_current_scene):
		_current_scene.queue_free()
	_current_scene = null
	_current_level = null
	_spawn_override = Vector2.ZERO
	_has_spawn_override = false
	# 转场遮罩可能正停在黑屏帧上；不清理的话新局会从全黑开始。
	if _transition != null and is_instance_valid(_transition):
		_transition.queue_free()
	_transition = null
	# 换局期间若留下 _changing = true，之后所有场景切换都会被静默丢弃。
	_changing = false


## 是否正在切换场景（转场动画进行中）。
## 外部（测试、加载界面）需要它来判断"现在调用 change_to_level 会不会被丢弃"。
func is_changing() -> bool:
	return _changing


## 指定下一次生成玩家的坐标（存档点复活用）。
## 必须在 change_to_level 之前调用；玩家会在**生成时**直接落在该坐标，
## 而不是先出生再被外部改坐标——后者会和异步场景切换抢时序，导致写错对象。
func set_next_spawn_position(pos: Vector2) -> void:
	_spawn_override = pos
	_has_spawn_override = true


## 取当前关卡里名为 entry_point 的出生点坐标。找不到时退回场景原点。
func get_entry_position(entry_point: StringName) -> Vector2:
	if _current_scene == null or entry_point == &"":
		return Vector2.ZERO
	var marker: Node = _current_scene.find_child(String(entry_point), true, false)
	if marker is Node2D:
		return (marker as Node2D).global_position
	push_warning("[SceneDirector] 关卡 %s 里找不到入口点 %s" % [_current_level.id, entry_point])
	return Vector2.ZERO


# ============================================================================
# 私有方法
# ============================================================================

## 真正执行场景替换。先清掉旧场景，再实例化新场景并放入玩家。
##
## 【提交顺序：所有 await 走完、确认没被取消，才动跨场景状态】
##   旧实现在第一个 await 之前就把 `_current_level = level` 写死了。若此时被
##   取消（回主菜单），`detach_level()` 已经把引用清空，随后旧协程又把新场景
##   挂回 root —— 引用与场景树各说各话（野指针 + 幽灵关卡）。
##   现在改成"本地变量暂存 → 全部 await 完 → 一次性提交"，取消路径只需释放
##   本地临时场景，不污染任何跨场景状态。
func _swap_scene(level: LevelData, entry_point: StringName, gen: int) -> void:
	if level.scene == null:
		push_error("[SceneDirector] 关卡 %s 没有配置场景" % level.id)
		return
	# 旧场景先移除并释放，避免内存里堆着多张地图。
	if _current_scene != null and is_instance_valid(_current_scene):
		_current_scene.queue_free()
		_current_scene = null
		# 等一帧让 queue_free 真正生效，否则同名节点可能冲突。
		await get_tree().process_frame
		if gen != _generation:
			return
	_current_level = null
	# 实例化但先不提交：本地持有引用，取消时由本函数负责释放。
	var scene: Node = level.scene.instantiate()
	# 【挂到 World 容器，而不是 root】官方《Scene organization》推荐换关卡只替换
	#   World 容器的子节点；这样 GUI/Menus 天然不受影响。UIRegistry 在 Boot 未装配时
	#   回退到 root（测试常直接调用本函数），保证两种场景都正确。
	var level_parent: Node = UIRegistry.level_parent()
	# 用 call_deferred 而不是直接 add_child：boot 的 _ready 里调用本函数时，
	# 父节点正在"设置子节点"的过程中，直接 add_child 会报 "Parent node is busy"。
	level_parent.add_child.call_deferred(scene)
	# 等新场景真正入树后再放玩家，否则 add_child(Player) 会找不到父节点。
	await get_tree().process_frame
	if gen != _generation:
		# 这段时间里被取消（回主菜单）：把刚挂上的新场景也卸掉，
		# 否则主菜单背后会活着一张地图。
		if is_instance_valid(scene):
			scene.queue_free()
		return
	# ---- 确认存活，一次性提交跨场景状态（此后不再有 await）----
	_current_level = level
	_current_scene = scene
	# 用"默认入口 → 调用方指定入口"的优先级决定出生点。
	var spawn_name: StringName = entry_point if entry_point != &"" else level.default_entry
	_spawn_player(spawn_name)
	# 背景音乐：按关卡归属切歌。
	#
	# 【为什么没配 bgm 要 stop 而不是"沿用上一首"】沿用是"BGM 与场景不匹配"
	#   的直接成因：从有配乐的关卡走到没配乐的关卡，上一首会一直响，
	#   玩家听到的音乐与实际所在场景对不上。没配就是"这段场景没有音乐"。
	var music_owner: StringName = StringName("level:%s" % level.id)
	if level.bgm != null:
		AudioManager.play_music_for(music_owner, level.bgm)
	else:
		AudioManager.stop_music()
	EventBus.scene_changed.emit(_current_scene)


## 实例化玩家并放到入口点。若场景里已经有玩家（例如直接 F5 跑某关卡），就复用它。
func _spawn_player(entry_point: StringName) -> void:
	if _current_scene == null or not is_instance_valid(_current_scene):
		push_warning("[SceneDirector] 当前没有有效关卡场景，跳过玩家生成")
		return
	var pos: Vector2 = get_entry_position(entry_point)
	# 有坐标覆盖时优先用它（存档点复活），用完即清，避免影响后续正常进关。
	if _has_spawn_override:
		pos = _spawn_override
		_has_spawn_override = false
	var existing: Node = _current_scene.get_node_or_null("Player")
	if existing != null:
		if existing is Node2D:
			(existing as Node2D).global_position = pos
		return
	if player_scene == null:
		push_warning("[SceneDirector] 未配置 player_scene，无法生成玩家")
		return
	var player: Node = player_scene.instantiate()
	player.name = "Player"
	player.position = pos
	_current_scene.add_child(player)


func _fade_out(gen: int) -> void:
	if fade_time <= 0.0:
		return
	await _ensure_transition(gen)
	if gen != _generation:
		return
	if _transition != null and _transition.has_method("fade_out"):
		await _transition.fade_out(fade_time)


func _fade_in(gen: int) -> void:
	if fade_time <= 0.0:
		return
	if gen != _generation:
		return
	if _transition != null and _transition.has_method("fade_in"):
		await _transition.fade_in(fade_time)


## 懒创建转场层，只在第一次需要时实例化。
func _ensure_transition(gen: int) -> void:
	if _transition != null:
		return
	if transition_scene == null:
		return
	_transition = transition_scene.instantiate() as CanvasLayer
	if _transition != null:
		# 与 _swap_scene 同理：boot._ready 阶段 root 正在设置子节点，必须延迟挂载。
		get_tree().root.add_child.call_deferred(_transition)
		# 等它真正入树，否则紧接着的 fade_out 会拿到空节点。
		await get_tree().process_frame
