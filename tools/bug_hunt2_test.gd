## BugHunt2 —— 第二轮：针对截图复核中发现的疑点做定点验证
##
## 【怎么运行】
##   Godot --headless --path . res://tools/bug_hunt2_test.tscn
extends Node

var _bugs: Array[String] = []
var _oks: Array[String] = []

func _ready() -> void:
	print("")
	print("############ 第二轮定点验证 ############")
	GameState.reset_save()
	GameState.start_run()
	# 复刻真实顺序：主菜单阶段（还没有任何关卡）就启动教程。
	await _check_tutorial_race()
	SceneDirector.change_to_level(&"town", &"start")
	for i: int in 45:
		await get_tree().process_frame

	_install_hud()
	await get_tree().process_frame
	await get_tree().process_frame
	await _check_floating_text_lifetime()
	await _check_camera_bounds_black_edge()

	_report()
	get_tree().quit(0)


func _install_hud() -> void:
	var hud: Node = load("res://scenes/ui/hud.tscn").instantiate()
	hud.name = "HUD"
	get_tree().root.add_child.call_deferred(hud)


## 假设：教程在主菜单阶段就"跑完"了（因为当时还没有当前关卡，
## 所有带 level_id 的步骤都被判为"不属于本关"而被跳过）。
func _check_tutorial_race() -> void:
	print("")
	print("--- 定点 1：新手教程是否瞬间自毁 ---")
	# 复刻 MainMenu._start_new_game 的调用顺序：此时还没有任何关卡。
	GameState.tutorial_completed = false
	TutorialSystem.start_tutorial()
	var idx_at_menu: int = TutorialSystem.get_current_index()
	var running_at_menu: bool = TutorialSystem.is_running()
	print("    在主菜单调用 start_tutorial()：index=%d，is_running=%s" % [idx_at_menu, running_at_menu])
	_check(running_at_menu and idx_at_menu == 0, "教程在主菜单阶段处于待命状态（index=0）",
		"主菜单阶段教程就已自毁（index=%d，is_running=%s）：start_tutorial 时还没有当前关卡，" % [idx_at_menu, running_at_menu]
		+ "所有带 level_id 的步骤被 _step_matches_level 判为不匹配而被跳过，"
		+ "14 步新手教程一步都没播就弹了「教程完成」")
	# 再进关卡，看它能不能正常播放第一步。
	SceneDirector.change_to_level(&"town", &"start")
	for i: int in 45:
		await get_tree().process_frame
	var idx_in_town: int = TutorialSystem.get_current_index()
	print("    进入城镇后：index=%d，is_running=%s" % [idx_in_town, TutorialSystem.is_running()])
	_check(idx_in_town == 0 and TutorialSystem.is_running(), "进入城镇后教程开始播第 1 步",
		"进入城镇后教程没有从第 1 步开始（index=%d，is_running=%s）" % [idx_in_town, TutorialSystem.is_running()])
	TutorialSystem.skip_tutorial()


## 假设：伤害飘字不会消失（截图里同一个"9"挂了 5 张图）。
func _check_floating_text_lifetime() -> void:
	print("")
	print("--- 定点 2：飘字生命周期 ---")
	SceneDirector.change_to_level(&"field", &"from_town")
	for i: int in 45:
		await get_tree().process_frame
	var scene: Node = SceneDirector.get_current_scene()
	EventBus.floating_text_requested.emit("999", Vector2(200.0, 200.0), Color.WHITE)
	await get_tree().process_frame
	var found: Node = null
	for child: Node in scene.get_children():
		if child is FloatingText:
			found = child
	_check(found != null, "飘字已生成", "飘字没有生成")
	if found == null:
		return
	# 按**真实时间**等待，而不是帧数：headless 下 90 帧只有约 0.6 秒，
	# 短于 lifetime(0.75s)，用帧数等会误报"飘字没销毁"。
	await get_tree().create_timer(1.5, true, false, true).timeout
	for i: int in 5:
		await get_tree().process_frame
		if not is_instance_valid(found):
			break
	var still_alive: bool = is_instance_valid(found) and not found.is_queued_for_deletion()
	_check(not still_alive, "飘字 0.75 秒后自行销毁",
		"飘字超过 1.5 秒仍然存活（截图里同一个数字能挂满整场战斗）：%s" % [
			"tween 未执行" if still_alive else "正常"])
	if still_alive:
		print("    存活的飘字 position=%s alpha=%.2f" % [found.position, found.get_node("Label").modulate.a])


## 假设：镜头会拍到地图外的黑边（town 截图左侧大片纯黑）。
func _check_camera_bounds_black_edge() -> void:
	print("")
	print("--- 定点 3：镜头边界与地图尺寸 ---")
	SceneDirector.change_to_level(&"town", &"start")
	for i: int in 45:
		await get_tree().process_frame
	var level: Node = SceneDirector.get_current_scene()
	var floor_layer: TileMapLayer = level.get_node_or_null("Floor") as TileMapLayer
	var player: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
	if floor_layer == null or player == null:
		return
	var used: Rect2i = floor_layer.get_used_rect()
	var map_rect: Rect2 = Rect2(
		floor_layer.map_to_local(used.position) - Vector2(8, 8),
		Vector2(used.size) * 16.0)
	var cam: Camera2D = player.get_viewport().get_camera_2d()
	var half: Vector2 = Vector2(320, 180) * 0.5
	var view: Rect2 = Rect2(cam.get_screen_center_position() - half, Vector2(320, 180))
	print("    地图范围 %s（%sx%s），镜头视野 %s" % [
		map_rect, used.size.x * 16, used.size.y * 16, view])
	var outside: float = 0.0
	if view.position.x < map_rect.position.x:
		outside += map_rect.position.x - view.position.x
	if view.position.y < map_rect.position.y:
		outside += map_rect.position.y - view.position.y
	if view.end.x > map_rect.end.x:
		outside += view.end.x - map_rect.end.x
	if view.end.y > map_rect.end.y:
		outside += view.end.y - map_rect.end.y
	print("    视野超出地图的宽度合计 %.0f 像素（视口宽 320）" % outside)
	_check(outside < 1.0, "镜头视野始终被钳制在地图内",
		"城镇里视野超出地图 %.0f 像素：LevelData.camera_bounds 比地图本身大，" % outside
		+ "玩家贴边走时会看到大片地图外的黑边（02_town.png 左侧就是）")


func _check(condition: bool, ok_label: String, bug_label: String) -> void:
	if condition:
		_oks.append(ok_label)
		print("  [OK]  ", ok_label)
	else:
		_bugs.append(bug_label)
		print("  [BUG] ", bug_label)


func _report() -> void:
	var total: int = _bugs.size() + _oks.size()
	print("")
	print("############################################")
	print("第二轮定点验证：%d 项，复现 %d 个问题" % [total, _bugs.size()])
	var i: int = 1
	for b: String in _bugs:
		print("  %d. %s" % [i, b])
		i += 1
	print("############################################")
