## DeliveryTest —— 交付级功能集成测试
##
## 【负责什么】
##   验证"可交付"相关的功能：5 个关卡完整性、交互物、教程、菜单、背包、
##   锁门、复活点、Boss 血条。这些是内容/流程层面的检查，逻辑测试测不到。
##
## 【怎么运行】
##   Godot --headless --path . res://tools/delivery_test.tscn
extends Node

# ============================================================================
# 私有变量
# ============================================================================

var _failures: Array[String] = []
var _checks: int = 0

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	await _run()
	_report()
	get_tree().quit(1 if _failures.size() > 0 else 0)


func _run() -> void:
	await _test_data()
	await _test_levels()
	await _test_interactables()
	await _test_inventory()
	await _test_ui_scenes()
	await _test_tutorial()


# ============================================================================
# 1. 数据完整性
# ============================================================================

func _test_data() -> void:
	print("--- 数据层 ---")
	_check(DataRegistry.get_all_levels().size() >= 5, "关卡数据 >= 5（实际 %d）" % DataRegistry.get_all_levels().size())
	_check(DataRegistry.get_all(&"TutorialStep").size() >= 10, "教程步骤 >= 10（实际 %d）" % DataRegistry.get_all(&"TutorialStep").size())
	# 每个关卡都要有 id / 场景 / BGM / 边界。
	for res: Resource in DataRegistry.get_all_levels():
		var ld: LevelData = res as LevelData
		_check(ld != null and ld.id != &"", "关卡 %s 有 id" % res.resource_path.get_file())
		if ld == null:
			continue
		_check(ld.scene != null, "关卡 %s 配置了场景" % ld.id)
		_check(ld.bgm != null, "关卡 %s 配置了 BGM" % ld.id)
		_check(ld.camera_bounds.size.x > 0.0, "关卡 %s 有摄像机边界" % ld.id)
	# 地牢二层必须存在（新加的）。
	_check(DataRegistry.get_level(&"dungeon_2") != null, "存在地牢二层")


# ============================================================================
# 2. 关卡结构
# ============================================================================

func _test_levels() -> void:
	print("--- 关卡结构 ---")
	var level_names: Dictionary = {
		&"town": "Town", &"field": "Field", &"dungeon_1": "Dungeon1",
		&"dungeon_2": "Dungeon2", &"boss_room": "BossRoom",
	}
	for level_id: StringName in level_names.keys():
		var scene: Node = await _change_and_wait(level_id, &"", level_names[level_id])
		_check(scene != null, "关卡 %s 能加载" % level_id)
		if scene == null:
			continue
		_check(scene.has_node("Floor"), "%s 有地板层" % level_id)
		_check(scene.has_node("Walls"), "%s 有墙体层" % level_id)
		# 每个关卡必须有出生点。
		var has_spawn: bool = false
		for child: Node in scene.get_children():
			if child is Marker2D:
				has_spawn = true
				break
		_check(has_spawn, "%s 有出生点标记" % level_id)
		# 只统计"挂在当前关卡下"的敌人，避免上一关没释放干净的节点干扰。
		var enemies: int = _count_type(scene, "EnemyBase")
		if level_id in [&"field", &"dungeon_1", &"dungeon_2"]:
			_check(enemies > 0, "%s 生成了敌人（%d）" % [level_id, enemies])
		if level_id == &"boss_room":
			_check(enemies == 1, "Boss 房有 1 个 Boss（实际 %d）" % enemies)


# ============================================================================
# 3. 交互物
# ============================================================================

func _test_interactables() -> void:
	print("--- 交互物 ---")
	# 城镇：应有 NPC、提示牌、存档点。
	var scene: Node = await _change_and_wait(&"town", &"start", "Town")
	_check(scene != null, "城镇加载完成")
	if scene == null:
		return
	_check(_count_type(scene, "SignPost") >= 1, "城镇有提示牌")
	_check(_count_type(scene, "NPC") >= 2, "城镇有 NPC（%d 个）" % _count_type(scene, "NPC"))
	_check(_count_type(scene, "SavePoint") >= 1, "城镇有存档点")

	# 野外：应有宝箱与治愈泉。
	scene = await _change_and_wait(&"field", &"from_town", "Field")
	_check(_count_type(scene, "Chest") >= 2, "野外有宝箱（%d 个）" % _count_type(scene, "Chest"))
	_check(_count_type(scene, "HealSpring") >= 1, "野外有治愈泉")

	# 地牢：应有锁门。
	scene = await _change_and_wait(&"dungeon_1", &"from_field", "Dungeon1")
	_check(_count_type(scene, "LockedDoor") >= 1, "地牢一层有锁门")

	# 交互行为：宝箱给金币。
	var chest: Node = _find_type(scene, "Chest")
	if chest != null:
		var gold_before: int = GameState.gold
		chest.call("force_interact", get_tree().get_first_node_in_group(&"player"))
		await get_tree().process_frame
		_check(GameState.gold > gold_before, "开宝箱获得金币（%d → %d）" % [gold_before, GameState.gold])

	# 交互行为：存档点回满血并记录复活点。
	var save_pt: Node = _find_type(scene, "SavePoint")
	var player: Actor = get_tree().get_first_node_in_group(&"player") as Actor
	if save_pt != null and player != null:
		player.apply_damage(_make_damage(30.0))
		var hurt_hp: float = player.get_health()
		save_pt.call("force_interact", player)
		await get_tree().process_frame
		_check(player.get_health() > hurt_hp, "存档点回血（%.0f → %.0f）" % [hurt_hp, player.get_health()])
		_check(GameState.get_respawn_point()["level"] == &"dungeon_1", "存档点记录了复活关卡")


# ============================================================================
# 4. 背包
# ============================================================================

func _test_inventory() -> void:
	print("--- 背包 ---")
	GameState.inventory.clear()
	GameState.add_item(&"potion_life", 3)
	_check(GameState.has_item(&"potion_life", 3), "背包记录物品数量")
	_check(GameState.get_inventory_entries().size() == 1, "背包条目正确")
	_check(GameState.remove_item(&"potion_life", 1), "能移除物品")
	_check(GameState.get_item_count(&"potion_life") == 2, "移除后数量正确")
	_check(not GameState.remove_item(&"potion_life", 99), "数量不足时移除失败")
	# 钥匙判定。
	GameState.inventory.clear()
	_check(not GameState.has_item(&"dungeon_key"), "初始没有钥匙")
	GameState.add_item(&"dungeon_key", 1)
	_check(GameState.has_item(&"dungeon_key"), "拿到钥匙后判定为真")


# ============================================================================
# 5. UI 场景
# ============================================================================

func _test_ui_scenes() -> void:
	print("--- UI 场景 ---")
	var ui_scenes: Dictionary = {
		"主菜单": "res://scenes/ui/main_menu.tscn",
		"暂停菜单": "res://scenes/ui/pause_menu.tscn",
		"操作说明": "res://scenes/ui/help_panel.tscn",
		"设置": "res://scenes/ui/settings_panel.tscn",
		"HUD": "res://scenes/ui/hud.tscn",
		"背包": "res://scenes/ui/inventory_ui.tscn",
		"结算": "res://scenes/ui/game_over.tscn",
		"教程": "res://scenes/ui/tutorial_ui.tscn",
		"Boss血条": "res://scenes/ui/boss_health_bar.tscn",
		"三选一": "res://scenes/ui/modifier_choice.tscn",
		"飘字": "res://scenes/ui/floating_text.tscn",
	}
	for label: String in ui_scenes.keys():
		var path: String = ui_scenes[label]
		_check(ResourceLoader.exists(path), "%s 场景存在" % label)
		if ResourceLoader.exists(path):
			var packed: PackedScene = load(path)
			var inst: Node = packed.instantiate()
			_check(inst != null, "%s 能实例化" % label)
			if inst != null:
				inst.free()
	# 主题存在且按钮有样式。
	_check(ResourceLoader.exists("res://resources/ui_theme.tres"), "UI 主题存在")
	if ResourceLoader.exists("res://resources/ui_theme.tres"):
		var theme: Theme = load("res://resources/ui_theme.tres")
		_check(theme.has_stylebox("normal", "Button"), "主题为按钮配置了 normal 样式")
		_check(theme.has_stylebox("panel", "PanelContainer"), "主题为面板配置了样式")


# ============================================================================
# 6. 教程
# ============================================================================

func _test_tutorial() -> void:
	print("--- 教程 ---")
	# 重置教程状态，模拟新档。
	GameState.tutorial_completed = false
	TutorialSystem.start_tutorial()
	_check(TutorialSystem.is_running(), "教程能启动")
	# 进城镇，应该播第一步。
	await _change_and_wait(&"town", &"start", "Town")
	for i: int in 20:
		await get_tree().process_frame
	_check(TutorialSystem.get_current_index() >= 0, "进城镇后教程推进到某一步（index=%d）" % TutorialSystem.get_current_index())
	# 跳过教程。
	TutorialSystem.skip_tutorial()
	_check(not TutorialSystem.is_running(), "教程能跳过")
	_check(GameState.tutorial_completed, "跳过会标记完成")


# ============================================================================
# 工具
# ============================================================================

## 切到指定关卡并等它真正加载完成。
## 关键点：SceneDirector 在转场期间会丢弃新的切换请求，所以必须先等它空闲，
## 否则连续切关卡时后面的请求会被静默忽略（表现为"关卡加载失败"）。
func _change_and_wait(level_id: StringName, entry: StringName, expected_name: String) -> Node:
	for i: int in 120:
		if not SceneDirector.is_changing():
			break
		await get_tree().process_frame
	SceneDirector.change_to_level(level_id, entry)
	return await _await_level(expected_name)


## 等关卡切换到目标名（最多等 120 帧）。
## 固定帧数不可靠：转场淡入淡出 + queue_free 的时序会随负载变化。
func _await_level(expected_name: String) -> Node:
	for i: int in 120:
		await get_tree().process_frame
		var scene: Node = SceneDirector.get_current_scene()
		if scene != null and is_instance_valid(scene) and scene.name == expected_name:
			# 再多等两帧，让 LevelRuntime 的刷怪/连接门完成。
			await get_tree().process_frame
			await get_tree().process_frame
			return scene
	return null


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  [PASS] ", label)
	else:
		_failures.append(label)
		print("  [FAIL] ", label)


## 统计场景里某脚本类名的节点数。
func _count_type(root: Node, type_name: String) -> int:
	var count: int = 0
	for node: Node in _all_descendants(root):
		if node.get_script() != null and node.get_script().get_global_name() == type_name:
			count += 1
	return count


## 找第一个某类名的节点。
func _find_type(root: Node, type_name: String) -> Node:
	for node: Node in _all_descendants(root):
		if node.get_script() != null and node.get_script().get_global_name() == type_name:
			return node
	return null


func _all_descendants(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child: Node in root.get_children():
		out.append(child)
		out.append_array(_all_descendants(child))
	return out


func _make_damage(amount: float) -> DamageInfo:
	var info: DamageInfo = DamageInfo.new()
	info.amount = amount
	info.source = null
	return info


func _report() -> void:
	print("")
	print("=== 交付测试：%d 项检查，%d 项失败 ===" % [_checks, _failures.size()])
	for f: String in _failures:
		print("  ✗ ", f)
