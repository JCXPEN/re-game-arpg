## LevelRuntime —— 关卡运行时控制器
##
## 【负责什么】
##   把关卡场景里的"静态配置"变成"活的玩法"：
##     1. 按 LevelData 生成敌人（从 @export 的敌人生成表读取）。
##     2. 监听出口 Trigger，玩家踩上去就切场景。
##     3. 统计房间清怪进度，全清后开门。
##     4. 把摄像机边界套给玩家摄像机。
##
## 【挂哪个节点】
##   每个关卡场景的根节点上（由生成器或手搭时挂上）。
##
## 【依赖谁】
##   LevelData、DataRegistry、SceneDirector、EventBus。
##
## 【怎么扩展】
##   刷怪规则目前是"进关卡刷一次"；要加"进房间才刷"，把 _spawn_enemies 拆成
##   按房间触发即可，不用改其它系统。
class_name LevelRuntime
extends Node2D

# ============================================================================
# @export
# ============================================================================

## 本关卡的 LevelData。生成器会在保存场景时写进 meta，也可以手动指定。
@export var level_data: LevelData
## 敌人场景。所有敌人都用同一个场景，靠 EnemyData 区分行为。
@export var enemy_scene: PackedScene
## 是否在进入时自动生成敌人。
@export var auto_spawn_enemies: bool = true
## 敌人生成点与玩家出生点的最小距离，避免一进场就被贴脸。
@export_range(0.0, 500.0, 8.0) var min_spawn_distance: float = 64.0
## 本关卡要生成的敌人数量。
@export_range(0, 64, 1) var enemy_count: int = 6
## 从 DataRegistry 里随机挑选的敌人权重表（空则用默认三种）。
@export var enemy_pool: Array[StringName] = [&"slime", &"skeleton", &"dark_mage"]

# ============================================================================
# 私有变量
# ============================================================================

## 存活敌人数。
var _alive_enemies: int = 0
## 房间是否已清空（用于开门）。
var _cleared: bool = false
## 玩家引用（用于算刷怪距离）。
var _player: Node2D
## 已生成的敌人列表。
var _spawned: Array[Node] = []

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	# 场景根节点的脚本如果是本类，LevelRuntime 就是关卡根，直接接管。
	add_to_group(&"level")
	EventBus.unit_died.connect(_on_unit_died)
	# 等一帧，让 SceneDirector 把玩家放进来之后再刷怪/配摄像机。
	await get_tree().process_frame
	# 关卡数据由 SceneDirector 持有。不在这里引用 .tres，是因为 LevelData 反过来
	# 引用了本场景，直接互相引用会形成循环依赖。
	if level_data == null:
		level_data = SceneDirector.get_current_level()
	_resolve_player()
	_apply_camera_bounds()
	_apply_ambient_color()
	_connect_doors()
	if auto_spawn_enemies:
		_spawn_enemies()
	# 【顺序很重要】必须先刷 Boss 再判定清场。
	# 旧顺序是 _spawn_enemies() 里 "0 只 → _mark_cleared()" 抢在 _spawn_bosses() 前面，
	# 于是 Boss 房一进门就被置为"已清空"；等 Boss 真的被打死时
	# _on_unit_died 里的 `_alive_enemies == 0` 分支已经被 _cleared 挡掉，
	# 通关的三选一词条奖励直接丢失。
	_spawn_bosses()
	# 零敌人关卡（城镇/Boss 房）直接置位 _cleared，但不广播"房间已清空"提示
	# ——进城镇弹这个提示很突兀。锁门只查 is_cleared()，不受影响。
	if _alive_enemies <= 0 and _spawned.is_empty():
		_cleared = true


# ============================================================================
# 公开方法
# ============================================================================

## 本关是否已清空。
## 零敌人的关卡（城镇、Boss 房）必须直接算"已清空"——否则 require_clear 的锁门
## 会因为"永远等不到敌人死光"而永久锁死。
func is_cleared() -> bool:
	if _cleared:
		return true
	# 没有任何敌人时视为已清空（含 auto_spawn_enemies=false 的关卡）。
	return _alive_enemies <= 0 and _spawned.is_empty()

## 剩余敌人数。
func get_alive_count() -> int:
	return _alive_enemies


# ============================================================================
# 私有方法
# ============================================================================

func _resolve_player() -> void:
	_player = get_tree().get_first_node_in_group(&"player") as Node2D
	if _player == null:
		_player = get_node_or_null("Player") as Node2D


## 应用关卡环境色调（地牢更暗、野外偏暖），让不同区域的氛围有区分。
## 用 CanvasModulate 做全局乘色，比给每个图层调 modulate 更省事且不会漏节点。
func _apply_ambient_color() -> void:
	var tint: Color = level_data.ambient_color if level_data != null else Color.WHITE
	# 已经是白色就说明没配置，不加节点（省一次遍历）。
	if tint.is_equal_approx(Color.WHITE):
		return
	var mod: CanvasModulate = CanvasModulate.new()
	mod.name = "AmbientTint"
	mod.color = tint
	# 放在最前面，保证它乘到所有绘制内容上。
	add_child(mod)
	move_child(mod, 0)


## 把 LevelData 的边界写给玩家摄像机。
func _apply_camera_bounds() -> void:
	if _player == null:
		return
	var cam: PlayerCamera = _player.get_node_or_null("Camera2D") as PlayerCamera
	if cam == null:
		return
	var bounds: Rect2 = level_data.camera_bounds if level_data != null else get_meta(&"camera_bounds", Rect2())
	cam.set_bounds(bounds)


## 连接所有出口 Trigger。
func _connect_doors() -> void:
	for child: Node in get_children():
		if not child.has_meta(&"target_level"):
			continue
		var trigger: Area2D = child.get_node_or_null("Trigger") as Area2D
		if trigger == null:
			continue
		trigger.body_entered.connect(_on_door_entered.bind(child))


## 生成敌人。在关卡内的地板格上随机取点，避开玩家附近。
func _spawn_enemies() -> void:
	if enemy_scene == null or enemy_count <= 0:
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	# 用关卡名做种子，保证同一个关卡每次布局一致（方便调试）。
	rng.seed = hash(name)
	var attempts: int = 0
	var spawned: int = 0
	while spawned < enemy_count and attempts < enemy_count * 30:
		attempts += 1
		var pos: Vector2 = _random_walkable_position(rng)
		if pos == Vector2.INF:
			# 找不到可通行格子：不要 break，继续试几次（随机点可能落在墙上）。
			continue
		if _player != null and pos.distance_to(_player.global_position) < min_spawn_distance:
			continue
		_spawn_one(pos, rng)
		spawned += 1
	_alive_enemies = spawned
	print("[LevelRuntime] %s 生成敌人 %d 个（尝试 %d 次）" % [name, spawned, attempts])
	# 【为什么这里不能 _mark_cleared()】
	#   本函数在 _spawn_bosses() 之前执行。Boss 房是"0 只小怪 + 1 只 Boss"，
	#   若在这里就置位清空，Boss 死后的奖励与后续判定都会被 _cleared 吞掉。
	#   清场判定统一交给 _ready() 末尾（Boss 刷完之后）和 _on_unit_died()。


## 在关卡地图里随机找一个可通行的格子中心。
func _random_walkable_position(rng: RandomNumberGenerator) -> Vector2:
	var floor_layer: TileMapLayer = get_node_or_null("Floor") as TileMapLayer
	if floor_layer == null:
		return Vector2.INF
	var used: Rect2i = floor_layer.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return Vector2.INF
	var tx: int = rng.randi_range(used.position.x, used.position.x + used.size.x - 1)
	var ty: int = rng.randi_range(used.position.y, used.position.y + used.size.y - 1)
	# 必须是地板且不是墙。
	if floor_layer.get_cell_source_id(Vector2i(tx, ty)) < 0:
		return Vector2.INF
	return floor_layer.map_to_local(Vector2i(tx, ty))


## 生成一个敌人并绑定数据。
func _spawn_one(pos: Vector2, rng: RandomNumberGenerator) -> void:
	var enemy: Node2D = enemy_scene.instantiate() as Node2D
	if enemy == null:
		return
	enemy.position = pos
	add_child(enemy)
	# 从池里随机选一种敌人数据。
	if not enemy_pool.is_empty() and enemy is EnemyBase:
		var pick: StringName = enemy_pool[rng.randi() % enemy_pool.size()]
		var enemy_data: EnemyData = DataRegistry.get_enemy(pick)
		if enemy_data != null:
			(enemy as EnemyBase).setup(enemy_data)
	_spawned.append(enemy)


## 生成 Boss。Boss 房在场景里放了一个 BossSpawn 标记，这里按它的 meta 生成。
func _spawn_bosses() -> void:
	if enemy_scene == null:
		return
	for child: Node in get_children():
		if not child.has_meta(&"boss_id"):
			continue
		var boss_id: StringName = child.get_meta(&"boss_id", &"")
		var boss_data: EnemyData = DataRegistry.get_enemy(boss_id)
		if boss_data == null:
			push_warning("[LevelRuntime] 找不到 Boss 数据：%s" % boss_id)
			continue
		var boss: Node2D = enemy_scene.instantiate() as Node2D
		if boss == null:
			continue
		boss.position = (child as Node2D).position
		# 把真实 id 写进 meta：EnemyData 里没有 id 字段（id 是 DataRegistry 的索引键），
		# 死亡时若拿 display_name 去登记，会写成"独眼巨人"，
		# 而 data/levels/boss_room.tres 的 boss_id 是 &"boss_cyclops"，
		# is_boss_defeated() 永远匹配不上。
		boss.set_meta(&"boss_id", boss_id)
		add_child(boss)
		if boss is EnemyBase:
			(boss as EnemyBase).setup(boss_data)
		_spawned.append(boss)
		_alive_enemies += 1


# ============================================================================
# 信号回调
# ============================================================================

## 玩家踩到门 → 请求切场景。门未解锁时给提示。
##
## 【为什么先判 _player == null】
##   `if body != _player: return` 在 _player 还是 null 时恒为 false（null != null 是假），
##   等于**完全不过滤**：任何跑进 Trigger 的物理体（敌人被击退到门上、投射物、
##   掉落的碰撞体）都会替玩家触发切场景。必须先显式挡掉"玩家还没解析出来"的窗口。
func _on_door_entered(body: Node2D, door: Node) -> void:
	if _player == null:
		_resolve_player()
	if _player == null or body != _player:
		return
	var target_level: StringName = door.get_meta(&"target_level", &"")
	var target_entry: StringName = door.get_meta(&"target_entry", &"")
	if target_level == &"":
		return
	EventBus.scene_change_requested.emit(target_level, target_entry)


## 标记本关已清空并广播（只生效一次）。
func _mark_cleared() -> void:
	if _cleared:
		return
	_cleared = true
	EventBus.room_cleared.emit(StringName(name))
	EventBus.toast_requested.emit("房间已清空！")


## 敌人死亡 → 减少计数，全清后标记并广播。
func _on_unit_died(unit: Node, _killer: Node) -> void:
	if not _spawned.has(unit):
		return
	_alive_enemies = maxi(0, _alive_enemies - 1)
	GameState.register_kill()
	if _alive_enemies == 0:
		_mark_cleared()
		_offer_modifier_choice()


## 清怪后弹三选一。这是 Roguelite 构筑的入口——只有真正清完怪才给奖励，
## 让"打怪"和"变强"形成闭环。
func _offer_modifier_choice() -> void:
	var candidates: Array[ModifierData] = ModifierSystem.roll_candidates(3)
	if candidates.is_empty():
		return
	EventBus.modifier_choice_requested.emit(candidates)
