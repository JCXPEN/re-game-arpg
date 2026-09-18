## CaptureEsc —— 窗口模式真实渲染下走 Esc 相关路径并截图
##
## 用户报的两个症状都涉及"看得见的状态"（角色是否移动、UI 是否错乱、BGM 是否匹配），
## headless 只能验逻辑位，验不了画面。本脚本在真实窗口里跑真实流程并截图。
##
## 运行：Godot --path . res://tools/capture_esc.tscn
extends Node

var _dir: String = "user://screenshots_esc"
var _log: Array[String] = []

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(_dir)
	var boot: Node = load("res://scenes/core/boot.tscn").instantiate()
	boot.name = "Boot"
	boot.set("show_menu", true)
	get_tree().root.add_child.call_deferred(boot)
	await _frames(8)

	await _shot("01_main_menu")
	await _log_state("主菜单")

	# 新的冒险
	var menu: Node = _root("MainMenu")
	var btn: Node = menu.find_child("btn_new_game", true, false)
	(btn as Button).pressed.emit()
	await _settle()
	await _shot("02_town")
	await _log_state("进城镇")

	var player: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D

	# 教程系统提示（切 town 后 TutorialSystem 会自动播第一步）
	await _frames(30)
	await _shot("03_tutorial_prompt")
	await _log_state("教程提示中")

	# 按住方向键 + 真实 Esc
	Input.parse_input_event(_key(KEY_D, true))
	await _phys(6)
	var before: Vector2 = player.global_position
	Input.parse_input_event(_esc())
	await _frames(4)
	await _shot("04_after_esc_on_prompt")
	await _log_state("提示按Esc后")
	await _phys(20)
	Input.parse_input_event(_key(KEY_D, false))
	var moved: float = player.global_position.distance_to(before)
	_log.append("提示界面按 Esc 后角色位移=%.3f" % moved)

	# 确保没有阻塞窗口，再开暂停菜单
	await _force_clear()
	await _frames(4)
	var pause: Node = _root("PauseMenu")
	Input.parse_input_event(_esc())
	await _frames(4)
	await _shot("05_pause_menu")
	await _log_state("暂停菜单")

	# 暂停中按住方向键：不应移动
	var b2: Vector2 = player.global_position
	Input.parse_input_event(_key(KEY_D, true))
	await _phys(20)
	Input.parse_input_event(_key(KEY_D, false))
	var moved2: float = player.global_position.distance_to(b2)
	_log.append("暂停中按住方向键位移=%.3f" % moved2)

	# 返回主菜单
	pause.call("_go_main_menu")
	await _frames(20)
	await _shot("06_back_to_menu")
	await _log_state("返回主菜单")

	print("======== ESC VISUAL LOG ========")
	for l: String in _log:
		print("  " + l)
	print("=================================")
	print("shots → ", ProjectSettings.globalize_path(_dir))
	get_tree().quit()


func _log_state(tag: String) -> void:
	_log.append("[%s] paused=%s holders=%s top=%s bgm_playing=%s bgm_owner=%s level=%s" % [
		tag, str(get_tree().paused), str(PauseManager.get_holders()),
		str(UIInputRouter.top_blocking_id()), str(AudioManager.is_playing_music()),
		str(AudioManager.get_music_owner()),
		str(SceneDirector.get_current_level().id if SceneDirector.get_current_level() != null else "&lt;null&gt;")])


func _force_clear() -> void:
	PauseManager.clear_all()
	for n: Node in get_tree().get_nodes_in_group(UIInputRouter.GROUP):
		if n.has_method(&"force_close"):
			n.call("force_close")
		n.set("visible", false)
	PopupManager.release_all()
	var dlg: Node = _root("DialogUI")
	if dlg != null and dlg.has_method(&"close"):
		dlg.call("close")
	await _frames(2)
	PauseManager.clear_all()


func _key(code: int, pressed: bool) -> InputEventKey:
	var ev: InputEventKey = InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	return ev

func _esc() -> InputEventKey:
	return _key(KEY_ESCAPE, true)

func _root(n: String) -> Node:
	# UI 现在可能挂在 Menus/GUI 容器下，不再直属 root；用注册表的递归查找兜底，
	# 这样测试不受容器层级影响（沿用'按名字访问'的旧写法，迁移期无需逐个改路径）。
	return UIRegistry.find_by_name(n)

func _settle() -> void:
	for i: int in 300:
		if not SceneDirector.is_changing():
			break
		await get_tree().process_frame
	await _frames(8)
	await RenderingServer.frame_post_draw

func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_dir.path_join("%s.png" % label))
	print("[CaptureEsc] ", label)

func _frames(n: int) -> void:
	for _i: int in n:
		await get_tree().process_frame

func _phys(n: int) -> void:
	for _i: int in n:
		await get_tree().physics_frame
