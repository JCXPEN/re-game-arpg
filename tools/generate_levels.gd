## GenerateLevels —— 关卡与 TileSet 生成器（编辑器工具脚本）
##
## 【负责什么】
##   按 docs/LEVEL_DESIGN.md 的设计哲学，程序化生成全部 5 个关卡：
##     城镇 → 野外 → 地牢一层 → 地牢二层 → Boss 房
##   每个关卡都包含入口安全区、战斗房、岔路宝箱、存档点、关底门，
##   并生成对应的 TileSet 与 LevelData 资源。
##
## 【怎么运行】
##   Godot --headless --path . res://tools/generate_levels.tscn
##
## 【为什么程序化生成】
##   1) TileMapLayer 的 tile_map_data 是二进制，手写不现实；
##   2) 房间-走廊布局用数据描述，改布局只改数字；
##   3) 能程序化保证"入口 5 格内无敌人""走廊 ≥2 格"等设计约束。
extends Node

# ============================================================================
# 常量 —— 瓦片（选择依据见 docs/ASSETS.md）
# ============================================================================

const TILE := 16

## 地牢/城镇地板：InteriorFloor 的浅色砖纹，可无缝平铺。
const FLOOR_DUNGEON := Vector2i(1, 1)
## 地牢墙：InteriorFloor 的灰绿石墙，可无缝平铺。
const WALL_DUNGEON := Vector2i(16, 7)
## 野外草地：TilesetFloor 的草皮（(4,12) 整片绿色，可无缝平铺）。
##
## 为什么不用 TilesetNature：(4,19) 是树干/树底，不是草地，
##   整张 Nature 集没找到能无缝平铺的"纯草"瓦片。
##   TilesetFloor (4,12) 的色块是均匀绿色、边沿一致，平铺干净。
const FLOOR_GRASS := Vector2i(4, 12)
## 城镇石地：与地牢共用 InteriorFloor (1,1)，避免同一关卡两种地板色相割裂。
const FLOOR_TOWN := Vector2i(1, 1)
## 城镇/野外墙：TilesetRelief 的红砖墙（(5,6) 实测可平铺）。
const WALL_STONE := Vector2i(5, 6)

const TEX_INT_FLOOR := "res://assets/tilesets/TilesetInteriorFloor.png"
const TEX_FLOOR := "res://assets/tilesets/TilesetFloor.png"
const TEX_NATURE := "res://assets/tilesets/TilesetNature.png"
const TEX_RELIEF := "res://assets/tilesets/TilesetRelief.png"

# ============================================================================
# 常量 —— 交互物场景
# ============================================================================

const SCENE_CHEST := "res://scenes/world/chest.tscn"
const SCENE_SAVE := "res://scenes/world/save_point.tscn"
const SCENE_SIGN := "res://scenes/world/sign_post.tscn"
const SCENE_NPC := "res://scenes/world/npc.tscn"
const SCENE_SPRING := "res://scenes/world/heal_spring.tscn"
const SCENE_DOOR := "res://scenes/world/locked_door.tscn"
const SCENE_ENEMY := "res://scenes/enemies/enemy.tscn"

# ============================================================================
# 私有变量
# ============================================================================

## 缓存的 TileSet。
var _tilesets: Dictionary = {}

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	_ensure_dirs()
	_build_tilesets()
	_generate_town()
	_generate_field()
	_generate_dungeon_1()
	_generate_dungeon_2()
	_generate_boss_room()
	print("[GenerateLevels] 全部关卡生成完毕")
	get_tree().quit()


func _ensure_dirs() -> void:
	for d: String in ["res://data/levels", "res://scenes/levels", "res://resources/tilesets"]:
		DirAccess.make_dir_recursive_absolute(d)


# ============================================================================
# TileSet 构建
# ============================================================================

func _build_tilesets() -> void:
	_tilesets[&"dungeon"] = _build_tileset(
		TEX_INT_FLOOR, FLOOR_DUNGEON, TEX_INT_FLOOR, WALL_DUNGEON,
		"res://resources/tilesets/dungeon_tileset.tres")
	_tilesets[&"field"] = _build_tileset(
		TEX_FLOOR, FLOOR_GRASS, TEX_RELIEF, WALL_STONE,
		"res://resources/tilesets/field_tileset.tres")
	_tilesets[&"town"] = _build_tileset(
		TEX_INT_FLOOR, FLOOR_TOWN, TEX_RELIEF, WALL_STONE,
		"res://resources/tilesets/town_tileset.tres")


## 用两张贴图构建一套 TileSet：地板无碰撞，墙带整格碰撞。
func _build_tileset(floor_tex: String, floor_coord: Vector2i, wall_tex: String,
		wall_coord: Vector2i, save_path: String) -> TileSet:
	var ts: TileSet = TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	# 物理层必须在 add_source 之前加好：TileData 的碰撞多边形按物理层索引存。
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)
	ts.set_physics_layer_collision_mask(0, 0)

	var floor_source: TileSetAtlasSource = TileSetAtlasSource.new()
	floor_source.texture = load(floor_tex)
	floor_source.texture_region_size = Vector2i(TILE, TILE)
	floor_source.create_tile(floor_coord)
	var floor_id: int = ts.add_source(floor_source, 0)

	var wall_source: TileSetAtlasSource = TileSetAtlasSource.new()
	wall_source.texture = load(wall_tex)
	wall_source.texture_region_size = Vector2i(TILE, TILE)
	wall_source.create_tile(wall_coord)
	var wall_id: int = ts.add_source(wall_source, 1)
	# TileData 只有在源属于本 TileSet 之后才认识物理层。
	var tile_data: TileData = wall_source.get_tile_data(wall_coord, 0)
	tile_data.add_collision_polygon(0)
	tile_data.set_collision_polygon_points(0, 0, PackedVector2Array([
		Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)
	]))

	ts.set_meta(&"floor_source", floor_id)
	ts.set_meta(&"wall_source", wall_id)
	ts.set_meta(&"floor_coord", floor_coord)
	ts.set_meta(&"wall_coord", wall_coord)
	ResourceSaver.save(ts, save_path)
	return ts


# ============================================================================
# 关卡 1：城镇（安全区 + NPC + 引导）
# ============================================================================

func _generate_town() -> void:
	var ts: TileSet = _tilesets[&"town"]
	var w: int = 40
	var h: int = 30
	var root: Node2D = _new_level_root("Town", ts, Rect2(0, 0, w * TILE, h * TILE), "1 - Adventure Begin")
	_fill_rect(root, 0, 0, w, h, ts, true)
	_wall_border(root, w, h, ts)
	# 两栋房子（用墙围轮廓 + 门洞），纯装饰兼视觉引导。
	_wall_rect(root, 6, 6, 10, 7, ts, [[9, 12]])
	_wall_rect(root, 24, 14, 11, 8, ts, [[29, 21]])

	# 出生点（左上），出口在右侧。
	_add_spawn_marker(root, "start", Vector2(3 * TILE, 3 * TILE))
	_add_spawn_marker(root, "from_field", Vector2((w - 3) * TILE, h * 0.5 * TILE))

	# --- 引导设施 ---
	# 路牌：告诉玩家往右走。
	_add_sign(root, Vector2(6 * TILE, 4 * TILE),
		"边境小镇\n\n右边出去就是风鸣平原。\n路上小心魔物。")
	# 村民 NPC：给一瓶药水 + 提示。
	_add_npc(root, Vector2(14 * TILE, 10 * TILE), "村民",
		PackedStringArray([
			"你终于醒了，勇者。",
			"地牢深处有只独眼巨人，最近一直在闹事。",
			"这瓶药水你拿着，路上用得上。",
		]), &"potion_life", 0, &"")
	# 长老 NPC：教战斗要点。
	_add_npc(root, Vector2(28 * TILE, 8 * TILE), "长老",
		PackedStringArray([
			"战斗有三件事要记住。",
			"第一，打不过就翻滚——翻滚时你是无敌的。",
			"第二，攻击后摇可以用翻滚取消，别站着挨打。",
			"第三，蓄力重击虽然慢，但能打断敌人。",
		]), &"", 10, &"")
	# 存档点：城镇入口处。
	_add_save_point(root, Vector2(8 * TILE, 16 * TILE))

	_add_exit_marker(root, "to_field", Vector2((w - 2) * TILE, h * 0.5 * TILE), &"field", &"from_town")
	root.set("enemy_count", 0)
	root.set("auto_spawn_enemies", false)
	root.set_meta(&"default_entry", &"start")
	_save_level_scene(root, "res://scenes/levels/town.tscn")
	_save_level_data("town", "边境小镇", "res://scenes/levels/town.tscn", "Town",
		Rect2(0, 0, w * TILE, h * TILE), &"start",
		[{ "entry": &"to_field", "target_level": &"field", "target_entry": &"from_town" }])


# ============================================================================
# 关卡 2：野外（开阔战斗区 + 岔路宝箱 + 治愈泉）
# ============================================================================

func _generate_field() -> void:
	var ts: TileSet = _tilesets[&"field"]
	var w: int = 50
	var h: int = 38
	var root: Node2D = _new_level_root("Field", ts, Rect2(0, 0, w * TILE, h * TILE), "23 - Road")
	_fill_rect(root, 0, 0, w, h, ts, true)
	_wall_border(root, w, h, ts)

	# 岩石障碍：留出通道，制造"绕行"而不是"直线冲"。
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20260909
	var clusters: Array = [
		Vector2i(10, 12), Vector2i(24, 8), Vector2i(36, 20), Vector2i(16, 26), Vector2i(40, 8),
	]
	for center: Vector2i in clusters:
		# 每个障碍是一小簇石头，不是单格。
		for dx: int in range(-1, 2):
			for dy: int in range(-1, 2):
				if rng.randf() < 0.6:
					_set_wall(root, center.x + dx, center.y + dy, ts)

	# 入口/出口。
	_add_spawn_marker(root, "from_town", Vector2(3 * TILE, 3 * TILE))
	_add_spawn_marker(root, "from_dungeon", Vector2((w - 4) * TILE, (h - 4) * TILE))

	# --- 引导与补给 ---
	_add_sign(root, Vector2(5 * TILE, 5 * TILE),
		"风鸣平原\n\n魔物在草地上游荡。\n清光它们，再往东南方去地牢。")
	# 治愈泉放在中段，作为战斗间的"释放"节拍。
	_add_heal_spring(root, Vector2(25 * TILE, 19 * TILE))
	# 岔路宝箱：放在远离主路径的角落，奖励探索。
	_add_chest(root, Vector2(45 * TILE, 5 * TILE), [&"potion_life"], 8, 16)
	_add_chest(root, Vector2(8 * TILE, 32 * TILE), [&"potion_mana"], 6, 12)
	# 存档点：出口之前。
	_add_save_point(root, Vector2((w - 8) * TILE, (h - 8) * TILE))

	_add_exit_marker(root, "to_dungeon", Vector2((w - 3) * TILE, (h - 3) * TILE), &"dungeon_1", &"from_field")
	_add_exit_marker(root, "to_town", Vector2(2 * TILE, 2 * TILE), &"town", &"from_field")
	root.set("enemy_count", 10)
	root.set("enemy_pool", [&"slime", &"skeleton"])
	root.set("min_spawn_distance", 80.0)
	root.set_meta(&"default_entry", &"from_town")
	_save_level_scene(root, "res://scenes/levels/field.tscn")
	_save_level_data("field", "风鸣平原", "res://scenes/levels/field.tscn", "Field",
		Rect2(0, 0, w * TILE, h * TILE), &"from_town",
		[{ "entry": &"to_dungeon", "target_level": &"dungeon_1", "target_entry": &"from_field" },
		 { "entry": &"to_town", "target_level": &"town", "target_entry": &"from_field" }])


# ============================================================================
# 关卡 3：地牢一层（房间-走廊，教机制）
# ============================================================================

func _generate_dungeon_1() -> void:
	var ts: TileSet = _tilesets[&"dungeon"]
	var w: int = 58
	var h: int = 42
	var root: Node2D = _new_level_root("Dungeon1", ts, Rect2(0, 0, w * TILE, h * TILE), "21 - Dungeon")
	# 整片填墙再挖房间——最稳的地牢做法，不会漏墙。
	_fill_rect(root, 0, 0, w, h, ts, false)

	# 房间：(x, y, w, h, 用途)。布局遵循"入口安全 → 战斗 → 岔路奖励 → 存档 → 关底"。
	var rooms: Array = [
		[3, 3, 12, 9, "entry"],      ## 入口房（安全）
		[22, 4, 14, 9, "combat"],    ## 主战斗房 1
		[42, 4, 13, 9, "treasure"],  ## 岔路宝箱房
		[6, 20, 13, 11, "combat"],   ## 主战斗房 2
		[26, 24, 14, 11, "save"],    ## 存档房
		[44, 24, 12, 12, "exit"],    ## 关底房（锁门）
	]
	for room: Array in rooms:
		_dig_room(root, room[0], room[1], room[2], room[3], ts)
	# 走廊：L 形连接，宽度 2 格（设计约束：不允许单格走廊）。
	var centers: Array = []
	for room: Array in rooms:
		centers.append(Vector2i(room[0] + room[2] / 2, room[1] + room[3] / 2))
	_dig_corridor(root, centers[0], centers[1], ts, 1)
	_dig_corridor(root, centers[1], centers[2], ts, 1)
	_dig_corridor(root, centers[0], centers[3], ts, 1)
	_dig_corridor(root, centers[3], centers[4], ts, 1)
	_dig_corridor(root, centers[4], centers[5], ts, 1)
	_dig_corridor(root, centers[1], centers[4], ts, 1)

	# --- 内容放置 ---
	_add_spawn_marker(root, "from_field", Vector2((rooms[0][0] + 1) * TILE, (rooms[0][1] + 1) * TILE))
	_add_sign(root, Vector2((rooms[0][0] + 3) * TILE, (rooms[0][1] + 2) * TILE),
		"古代地牢 · 一层\n\n清空这一层的敌人，\n深处的门才会打开。")
	# 岔路宝箱房。
	_add_chest(root, Vector2((rooms[2][0] + 2) * TILE, (rooms[2][1] + 2) * TILE), [&"potion_life"], 12, 22)
	# 存档房。
	_add_save_point(root, Vector2((rooms[4][0] + 2) * TILE, (rooms[4][1] + 2) * TILE))
	# 关底锁门：清怪才开。
	_add_locked_door(root, Vector2((rooms[5][0] + 1) * TILE, (rooms[5][1] + rooms[5][3] / 2) * TILE), true, false)
	_add_exit_marker(root, "to_field", Vector2((rooms[0][0] + 1) * TILE, (rooms[0][1] + 1) * TILE), &"field", &"from_dungeon")
	_add_exit_marker(root, "to_dungeon_2", Vector2((rooms[5][0] + rooms[5][2] - 2) * TILE, (rooms[5][1] + rooms[5][3] / 2) * TILE), &"dungeon_2", &"from_dungeon_1")

	root.set("enemy_count", 13)
	root.set("enemy_pool", [&"slime", &"skeleton", &"dark_mage"])
	root.set("min_spawn_distance", 96.0)
	root.set_meta(&"default_entry", &"from_field")
	_save_level_scene(root, "res://scenes/levels/dungeon_1.tscn")
	_save_level_data("dungeon_1", "古代地牢 · 一层", "res://scenes/levels/dungeon_1.tscn", "Dungeon",
		Rect2(0, 0, w * TILE, h * TILE), &"from_field",
		[{ "entry": &"to_field", "target_level": &"field", "target_entry": &"from_dungeon" },
		 { "entry": &"to_dungeon_2", "target_level": &"dungeon_2", "target_entry": &"from_dungeon_1", "locked_until_cleared": true }])


# ============================================================================
# 关卡 4：地牢二层（精英 + 钥匙锁门）
# ============================================================================

func _generate_dungeon_2() -> void:
	var ts: TileSet = _tilesets[&"dungeon"]
	var w: int = 62
	var h: int = 46
	var root: Node2D = _new_level_root("Dungeon2", ts, Rect2(0, 0, w * TILE, h * TILE), "21 - Dungeon")
	_fill_rect(root, 0, 0, w, h, ts, false)

	var rooms: Array = [
		[3, 3, 12, 9, "entry"],
		[21, 3, 14, 10, "combat"],
		[41, 4, 13, 9, "key"],       ## 钥匙房
		[4, 22, 13, 11, "combat"],
		[23, 24, 14, 12, "save"],
		[44, 26, 14, 12, "exit"],
		[52, 3, 8, 8, "treasure"],   ## 隐蔽宝箱房
	]
	for room: Array in rooms:
		_dig_room(root, room[0], room[1], room[2], room[3], ts)
	var centers: Array = []
	for room: Array in rooms:
		centers.append(Vector2i(room[0] + room[2] / 2, room[1] + room[3] / 2))
	_dig_corridor(root, centers[0], centers[1], ts, 1)
	_dig_corridor(root, centers[1], centers[2], ts, 1)
	_dig_corridor(root, centers[2], centers[6], ts, 1)
	_dig_corridor(root, centers[0], centers[3], ts, 1)
	_dig_corridor(root, centers[3], centers[4], ts, 1)
	_dig_corridor(root, centers[4], centers[5], ts, 1)
	_dig_corridor(root, centers[1], centers[4], ts, 1)

	_add_spawn_marker(root, "from_dungeon_1", Vector2((rooms[0][0] + 1) * TILE, (rooms[0][1] + 1) * TILE))
	_add_sign(root, Vector2((rooms[0][0] + 3) * TILE, (rooms[0][1] + 2) * TILE),
		"古代地牢 · 二层\n\n这一层有精英魔物。\n找到钥匙，才能打开通往巢穴的门。")
	# 钥匙房：宝箱里是钥匙。
	_add_chest(root, Vector2((rooms[2][0] + 3) * TILE, (rooms[2][1] + 3) * TILE), [&"dungeon_key"], 20, 30)
	# 隐蔽宝箱房。
	_add_chest(root, Vector2((rooms[6][0] + 2) * TILE, (rooms[6][1] + 2) * TILE), [&"potion_life", &"potion_mana"], 15, 25)
	# 治愈泉：两层之间补给。
	_add_heal_spring(root, Vector2((rooms[4][0] + 2) * TILE, (rooms[4][1] + 2) * TILE))
	_add_save_point(root, Vector2((rooms[4][0] + 5) * TILE, (rooms[4][1] + 2) * TILE))
	# 关底门：需要钥匙。
	_add_locked_door(root, Vector2((rooms[5][0] + 1) * TILE, (rooms[5][1] + rooms[5][3] / 2) * TILE), false, true)
	_add_exit_marker(root, "to_dungeon_1", Vector2((rooms[0][0] + 1) * TILE, (rooms[0][1] + 1) * TILE), &"dungeon_1", &"from_field")
	_add_exit_marker(root, "to_boss", Vector2((rooms[5][0] + rooms[5][2] - 2) * TILE, (rooms[5][1] + rooms[5][3] / 2) * TILE), &"boss_room", &"from_dungeon_2")

	root.set("enemy_count", 15)
	root.set("enemy_pool", [&"skeleton", &"dark_mage", &"red_samurai"])
	root.set("min_spawn_distance", 104.0)
	root.set_meta(&"default_entry", &"from_dungeon_1")
	_save_level_scene(root, "res://scenes/levels/dungeon_2.tscn")
	_save_level_data("dungeon_2", "古代地牢 · 二层", "res://scenes/levels/dungeon_2.tscn", "Dungeon",
		Rect2(0, 0, w * TILE, h * TILE), &"from_dungeon_1",
		[{ "entry": &"to_dungeon_1", "target_level": &"dungeon_1", "target_entry": &"from_field" },
		 { "entry": &"to_boss", "target_level": &"boss_room", "target_entry": &"from_dungeon_2", "locked_until_cleared": true }])


# ============================================================================
# 关卡 5：Boss 房
# ============================================================================

func _generate_boss_room() -> void:
	var ts: TileSet = _tilesets[&"dungeon"]
	var w: int = 32
	var h: int = 26
	var root: Node2D = _new_level_root("BossRoom", ts, Rect2(0, 0, w * TILE, h * TILE), "17 - Fight")
	_fill_rect(root, 0, 0, w, h, ts, true)
	_wall_border(root, w, h, ts)
	# 两根柱子：给玩家一个"绕柱子躲技能"的战术点。
	# 用 2×2 而不是单格——单格墙在开阔地面上看起来像一个"洞"，
	# 2×2 才有"柱体"的体积感。
	for cx: int in [12, 20]:
		for cy: int in [9, 17]:
			for dx: int in 2:
				for dy: int in 2:
					_set_wall(root, cx + dx, cy + dy, ts)

	_add_spawn_marker(root, "from_dungeon_2", Vector2(3 * TILE, h * 0.5 * TILE))
	# 存档点在 Boss 房入口，是"最后补给"。
	_add_save_point(root, Vector2(5 * TILE, (h - 4) * TILE))
	# Boss 在房间右侧中央。
	_add_boss_marker(root, Vector2((w - 8) * TILE, h * 0.5 * TILE), &"boss_cyclops")
	# 击败后回城的传送点。
	_add_exit_marker(root, "to_town", Vector2(2 * TILE, (h - 3) * TILE), &"town", &"from_field")

	root.set("enemy_count", 0)
	root.set("auto_spawn_enemies", false)
	root.set_meta(&"default_entry", &"from_dungeon_2")
	root.set_meta(&"is_boss_room", true)
	_save_level_scene(root, "res://scenes/levels/boss_room.tscn")
	_save_level_data("boss_room", "独眼巨人巢穴", "res://scenes/levels/boss_room.tscn", "Boss",
		Rect2(0, 0, w * TILE, h * TILE), &"from_dungeon_2",
		[{ "entry": &"to_town", "target_level": &"town", "target_entry": &"from_field" }],
		true, &"boss_cyclops")


# ============================================================================
# 关卡构件 —— 地图
# ============================================================================

## 创建关卡根节点（挂 LevelRuntime，含地板层与墙体层）。
func _new_level_root(level_name: String, ts: TileSet, bounds: Rect2, _bgm_path: String) -> Node2D:
	var root: Node2D = Node2D.new()
	root.name = level_name
	root.set_script(load("res://scripts/world/level_runtime.gd"))
	root.y_sort_enabled = true

	var floor_layer: TileMapLayer = TileMapLayer.new()
	floor_layer.name = "Floor"
	floor_layer.tile_set = ts
	floor_layer.z_index = -10
	floor_layer.y_sort_enabled = false
	root.add_child(floor_layer)

	var wall_layer: TileMapLayer = TileMapLayer.new()
	wall_layer.name = "Walls"
	wall_layer.tile_set = ts
	wall_layer.y_sort_enabled = true
	wall_layer.z_index = 0
	root.add_child(wall_layer)

	root.set_meta(&"camera_bounds", bounds)
	root.set(&"enemy_scene", load(SCENE_ENEMY))
	return root


## 铺一块矩形（地板或墙）。
func _fill_rect(root: Node2D, x: int, y: int, w: int, h: int, ts: TileSet, is_floor: bool) -> void:
	var layer: TileMapLayer = (root.get_node("Floor") if is_floor else root.get_node("Walls")) as TileMapLayer
	var source: int = int(ts.get_meta(&"floor_source")) if is_floor else int(ts.get_meta(&"wall_source"))
	var coord: Vector2i = ts.get_meta(&"floor_coord") if is_floor else ts.get_meta(&"wall_coord")
	for ty: int in range(y, y + h):
		for tx: int in range(x, x + w):
			layer.set_cell(Vector2i(tx, ty), source, coord)


## 设一格墙。
func _set_wall(root: Node2D, x: int, y: int, ts: TileSet) -> void:
	var wall_layer: TileMapLayer = root.get_node("Walls") as TileMapLayer
	wall_layer.set_cell(Vector2i(x, y), int(ts.get_meta(&"wall_source")), ts.get_meta(&"wall_coord"))


## 挖房间：铺地板 + 清墙。
func _dig_room(root: Node2D, x: int, y: int, w: int, h: int, ts: TileSet) -> void:
	_fill_rect(root, x, y, w, h, ts, true)
	var wall_layer: TileMapLayer = root.get_node("Walls") as TileMapLayer
	for ty: int in range(y, y + h):
		for tx: int in range(x, x + w):
			wall_layer.erase_cell(Vector2i(tx, ty))


## 挖 L 形走廊。width 为半宽（1 = 3 格宽）。
func _dig_corridor(root: Node2D, a: Vector2i, b: Vector2i, ts: TileSet, width: int) -> void:
	for x: int in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
		for dy: int in range(-width, width + 1):
			_dig_single(root, x, a.y + dy, ts)
	for y: int in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
		for dx: int in range(-width, width + 1):
			_dig_single(root, b.x + dx, y, ts)


## 把一格变成可通行。
func _dig_single(root: Node2D, x: int, y: int, ts: TileSet) -> void:
	var floor_layer: TileMapLayer = root.get_node("Floor") as TileMapLayer
	var wall_layer: TileMapLayer = root.get_node("Walls") as TileMapLayer
	floor_layer.set_cell(Vector2i(x, y), int(ts.get_meta(&"floor_source")), ts.get_meta(&"floor_coord"))
	wall_layer.erase_cell(Vector2i(x, y))


## 沿矩形四边摆墙。
func _wall_border(root: Node2D, w: int, h: int, ts: TileSet) -> void:
	var wall_layer: TileMapLayer = root.get_node("Walls") as TileMapLayer
	var source: int = int(ts.get_meta(&"wall_source"))
	var coord: Vector2i = ts.get_meta(&"wall_coord")
	for x: int in range(w):
		wall_layer.set_cell(Vector2i(x, 0), source, coord)
		wall_layer.set_cell(Vector2i(x, h - 1), source, coord)
	for y: int in range(h):
		wall_layer.set_cell(Vector2i(0, y), source, coord)
		wall_layer.set_cell(Vector2i(w - 1, y), source, coord)


## 用墙围一个矩形轮廓，doors 为门洞坐标列表。
func _wall_rect(root: Node2D, x: int, y: int, w: int, h: int, ts: TileSet, doors: Array) -> void:
	var wall_layer: TileMapLayer = root.get_node("Walls") as TileMapLayer
	var source: int = int(ts.get_meta(&"wall_source"))
	var coord: Vector2i = ts.get_meta(&"wall_coord")
	for tx: int in range(x, x + w):
		for ty: int in [y, y + h - 1]:
			if not _is_door(doors, tx, ty):
				wall_layer.set_cell(Vector2i(tx, ty), source, coord)
	for ty: int in range(y, y + h):
		for tx: int in [x, x + w - 1]:
			if not _is_door(doors, tx, ty):
				wall_layer.set_cell(Vector2i(tx, ty), source, coord)


func _is_door(doors: Array, x: int, y: int) -> bool:
	for d: Array in doors:
		if d[0] == x and d[1] == y:
			return true
	return false


# ============================================================================
# 关卡构件 —— 标记与交互物
# ============================================================================

## 出生点。
func _add_spawn_marker(root: Node2D, marker_name: String, pos: Vector2) -> void:
	var marker: Marker2D = Marker2D.new()
	marker.name = marker_name
	marker.position = pos
	root.add_child(marker)


## Boss 生成点。
func _add_boss_marker(root: Node2D, pos: Vector2, boss_id: StringName) -> void:
	var marker: Marker2D = Marker2D.new()
	marker.name = "BossSpawn"
	marker.position = pos
	marker.set_meta(&"boss_id", boss_id)
	root.add_child(marker)


## 出口（门/楼梯），带触发区域。
func _add_exit_marker(root: Node2D, marker_name: String, pos: Vector2,
		target_level: StringName, target_entry: StringName) -> void:
	var door: Node2D = Node2D.new()
	door.name = marker_name
	door.position = pos
	var area: Area2D = Area2D.new()
	area.name = "Trigger"
	area.collision_layer = 512
	area.collision_mask = 2
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(TILE, TILE)
	shape.shape = rect
	area.add_child(shape)
	door.add_child(area)
	door.set_meta(&"target_level", target_level)
	door.set_meta(&"target_entry", target_entry)
	root.add_child(door)


## 宝箱。
func _add_chest(root: Node2D, pos: Vector2, items: Array, gold_min: int, gold_max: int) -> void:
	var chest: Node2D = load(SCENE_CHEST).instantiate() as Node2D
	chest.position = pos
	chest.set("guaranteed_items", items)
	chest.set("gold_min", gold_min)
	chest.set("gold_max", gold_max)
	root.add_child(chest)


## 存档点。
func _add_save_point(root: Node2D, pos: Vector2) -> void:
	var sp: Node2D = load(SCENE_SAVE).instantiate() as Node2D
	sp.position = pos
	root.add_child(sp)


## 提示牌。
func _add_sign(root: Node2D, pos: Vector2, message: String) -> void:
	var sign: Node2D = load(SCENE_SIGN).instantiate() as Node2D
	sign.position = pos
	sign.set("message", message)
	root.add_child(sign)


## NPC。
func _add_npc(root: Node2D, pos: Vector2, npc_name: String, lines: PackedStringArray,
		give_item: StringName, give_gold: int, unlock_spell: StringName) -> void:
	var npc: Node2D = load(SCENE_NPC).instantiate() as Node2D
	npc.position = pos
	npc.set("npc_name", npc_name)
	npc.set("lines", lines)
	npc.set("give_item_id", give_item)
	npc.set("give_gold", give_gold)
	npc.set("unlock_spell_id", unlock_spell)
	npc.set("once", true)
	root.add_child(npc)


## 治愈泉。
func _add_heal_spring(root: Node2D, pos: Vector2) -> void:
	var spring: Node2D = load(SCENE_SPRING).instantiate() as Node2D
	spring.position = pos
	root.add_child(spring)


## 锁门。
func _add_locked_door(root: Node2D, pos: Vector2, require_clear: bool, requires_key: bool) -> void:
	var door: Node2D = load(SCENE_DOOR).instantiate() as Node2D
	door.position = pos
	door.set("require_clear", require_clear)
	door.set("requires_key", requires_key)
	if requires_key:
		door.set("locked_message", "门被锁住了，需要地牢钥匙。")
	root.add_child(door)


# ============================================================================
# 保存
# ============================================================================

func _save_level_scene(root: Node2D, path: String) -> void:
	_set_owner_recursive(root, root)
	var packed: PackedScene = PackedScene.new()
	var err: int = packed.pack(root)
	if err != OK:
		push_error("[GenerateLevels] pack 失败 %s：%d" % [path, err])
		root.queue_free()
		return
	ResourceSaver.save(packed, path)
	root.queue_free()


func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner_node
		_set_owner_recursive(child, owner_node)


## 保存关卡数据。
func _save_level_data(id: String, disp: String, scene_path: String, area_type: String,
		bounds: Rect2, default_entry: StringName, exits: Array,
		is_boss_room: bool = false, boss_id: StringName = &"") -> void:
	var ld: LevelData = LevelData.new()
	ld.id = StringName(id)
	ld.display_name = disp
	ld.scene = load(scene_path)
	ld.area_type = area_type
	ld.default_entry = default_entry
	ld.camera_bounds = bounds
	ld.is_boss_room = is_boss_room
	ld.boss_id = boss_id
	var exit_dicts: Array[Dictionary] = []
	for e: Dictionary in exits:
		exit_dicts.append({
			"entry_point_id": e.get("entry", &""),
			"target_level": e.get("target_level", &""),
			"target_entry": e.get("target_entry", &""),
			"locked_until_cleared": e.get("locked_until_cleared", false),
		})
	ld.exits = exit_dicts
	ld.bgm = load("res://assets/audio/music/%s.ogg" % _bgm_name_for(id))
	ld.ambient_color = _ambient_for(area_type)
	ResourceSaver.save(ld, "res://data/levels/%s.tres" % id)


## 区域环境色调。地牢压暗，野外略暖，城镇保持中性。
func _ambient_for(area_type: String) -> Color:
	match area_type:
		"Dungeon": return Color(0.62, 0.66, 0.78)  ## 冷暗，突出地牢的阴森
		"Boss": return Color(0.72, 0.6, 0.66)      ## 偏紫，强调危险
		"Field": return Color(1.0, 0.97, 0.9)      ## 略暖，户外阳光
		_: return Color.WHITE


func _bgm_name_for(id: String) -> String:
	match id:
		"town": return "1 - Adventure Begin"
		"field": return "23 - Road"
		"dungeon_1", "dungeon_2": return "21 - Dungeon"
		"boss_room": return "17 - Fight"
		_: return "23 - Road"
