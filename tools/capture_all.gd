## CaptureAll —— 全量截图（关卡 + 界面）
##
## 【负责什么】
##   无窗口跑游戏，把 5 个关卡和所有主要界面各截一张，用于人工/视觉验收。
##
## 【怎么运行】
##   Godot --path . --resolution 1280x720 res://tools/capture_all.tscn
extends Node

var _dir: String = "user://screenshots"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(_dir)
	# 常驻 UI
	_install_ui()
	GameState.start_run()
	# 给点金币和物品，让背包界面有内容。
	GameState.add_gold(128)
	GameState.add_item(&"potion_life", 3)
	GameState.add_item(&"potion_mana", 2)
	GameState.add_item(&"dungeon_key", 1)
	await get_tree().process_frame

	# --- 关卡 ---
	var levels: Array = [
		[&"town", &"start", "Town"],
		[&"field", &"from_town", "Field"],
		[&"dungeon_1", &"from_field", "Dungeon1"],
		[&"dungeon_2", &"from_dungeon_1", "Dungeon2"],
		[&"boss_room", &"from_dungeon_2", "BossRoom"],
	]
	for entry: Array in levels:
		await _change(entry[0], entry[1], entry[2])
		var cur: Node = SceneDirector.get_current_scene()
		print("[CaptureAll] 期望=", entry[2], " 实际=", cur.name if cur != null else "<null>")
		await _shot("level_%s" % entry[0])

	# --- 界面 ---
	await _shot_with("ui_hud", func() -> void: pass)
	# 暂停菜单
	var pause: CanvasLayer = get_tree().root.get_node_or_null("PauseMenu")
	if pause != null:
		pause.visible = true
		await _shot("ui_pause")
		pause.visible = false
	# 背包
	var inv: CanvasLayer = get_tree().root.get_node_or_null("InventoryUI")
	if inv != null:
		inv.call("open")
		await _shot("ui_inventory")
		inv.call("close")
	# 操作说明
	var help: CanvasLayer = load("res://scenes/ui/help_panel.tscn").instantiate()
	get_tree().root.add_child.call_deferred(help)
	await get_tree().process_frame
	help.visible = true
	await _shot("ui_help")
	# 截完立刻关掉，否则会盖住后面要截的界面。
	help.visible = false
	help.queue_free()
	await get_tree().process_frame
	# 三选一
	var mc: CanvasLayer = get_tree().root.get_node_or_null("ModifierChoice")
	if mc != null:
		var cands: Array[ModifierData] = ModifierSystem.roll_candidates(3)
		EventBus.modifier_choice_requested.emit(cands)
		await _shot("ui_modifier")
	print("[CaptureAll] 全部截图完成")
	get_tree().quit()


func _install_ui() -> void:
	for path: String in [
		"res://scenes/ui/hud.tscn", "res://scenes/ui/tutorial_ui.tscn",
		"res://scenes/ui/boss_health_bar.tscn", "res://scenes/ui/modifier_choice.tscn",
		"res://scenes/ui/inventory_ui.tscn", "res://scenes/ui/game_over.tscn",
		"res://scenes/ui/pause_menu.tscn",
	]:
		var n: Node = load(path).instantiate()
		get_tree().root.add_child.call_deferred(n)


func _change(level_id: StringName, entry: StringName, expected: String) -> void:
	for i: int in 120:
		if not SceneDirector.is_changing(): break
		await get_tree().process_frame
	SceneDirector.change_to_level(level_id, entry)
	# 等切换开始、再等它结束。
	await get_tree().process_frame
	for i: int in 180:
		if not SceneDirector.is_changing():
			break
		await get_tree().process_frame
	for i: int in 10:
		await get_tree().process_frame


func _shot(label: String) -> void:
	# 等 SceneDirector 转场彻底结束（它会自己把遮罩淡出）。
	# 不要手动调 fade_in——那会打断 SceneDirector 正在 await 的转场。
	for i: int in 120:
		if not SceneDirector.is_changing():
			break
		await get_tree().process_frame
	for i: int in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_dir.path_join("%s.png" % label))
	print("[CaptureAll] ", label)


func _shot_with(label: String, _cb: Callable) -> void:
	await _shot(label)
