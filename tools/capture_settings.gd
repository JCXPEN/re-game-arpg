## CaptureSettings —— 真实窗口下渲染设置面板：验证"能否退出 / 滑块是否可见"
extends Node

var _dir: String = "user://screenshots_settings"
var _log: Array[String] = []

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(_dir)
	var boot: Node = load("res://scenes/core/boot.tscn").instantiate()
	boot.name = "Boot"
	boot.set("show_menu", true)
	get_tree().root.add_child.call_deferred(boot)
	await _frames(10)

	# 主菜单 → 新的冒险
	var menu: Node = _root("MainMenu")
	menu.find_child("btn_new_game", true, false).pressed.emit()
	await _settle()
	await _force_clear()

	var pause: Node = _root("PauseMenu")
	pause.call("open")
	await _frames(4)
	pause.call("_open_settings")
	await _frames(6)
	await _shot("01_settings_from_pause")
	var st: Node = _settings_node()
	_report("暂停菜单进入设置", st)
	_dump_slider_rects(st)

	# 真实 Esc
	Input.parse_input_event(_esc())
	await _frames(6)
	_log.append("真实 Esc 后：settings.visible=%s  pause.visible=%s" % [_vis(st), _vis(pause)])
	await _shot("02_after_esc")

	# 若没关掉，试试点"确定"按钮
	if _vis(st):
		var btn: Node = st.find_child("Close", true, false)
		if btn != null:
			(btn as Button).pressed.emit()
			await _frames(6)
			_log.append("点确定后：settings.visible=%s" % _vis(st))
			await _shot("03_after_confirm_click")

	# 再从主菜单进设置，验证主菜单路径的 Esc
	await _force_clear()
	GameFlow.teardown_to_menu(true)
	await _frames(10)
	var menu2: Node = _root("MainMenu")
	menu2.call("_open_settings")
	await _frames(6)
	var st2: Node = _settings_node()
	_report("主菜单进入设置", st2)
	await _shot("04_settings_from_mainmenu")
	Input.parse_input_event(_esc())
	await _frames(6)
	_log.append("主菜单路径真实 Esc 后：settings.visible=%s" % _vis(st2))
	await _shot("05_mainmenu_after_esc")

	print("======== SETTINGS LOG ========")
	for l: String in _log:
		print("  " + l)
	print("==============================")
	print("shots → ", ProjectSettings.globalize_path(_dir))
	get_tree().quit()


## 可能有多个同名面板（历史遗留），取当前可见的那个做断言。
func _settings_node() -> Node:
	var nodes: Array[Node] = get_tree().root.get_children() if get_tree() != null else []
	for n: Node in nodes:
		if str(n.name).begins_with("SettingsPanel") and bool(n.get("visible")):
			return n
	return get_tree().root.get_node_or_null(NodePath("SettingsPanel"))


func _report(tag: String, st: Node) -> void:
	_log.append("[%s] settings=%s visible=%s" % [tag, str(st != null), _vis(st)])


func _dump_slider_rects(st: Node) -> void:
	if st == null:
		return
	var paths: Array = [
		"Root/Panel/Margin/VBox/@HBoxContainer@24/Master",
		"Root/Panel/Margin/VBox/@HBoxContainer@26/Sfx",
		"Root/Panel/Margin/VBox/@HBoxContainer@28/Music",
	]
	for p: String in paths:
		var s: Node = st.get_node_or_null(p)
		if s is Control:
			var c: Control = s as Control
			_log.append("  slider %s rect=%s min=%s visible=%s mod=%s" % [
				p.get_file(), str(c.get_global_rect()), str(c.get_combined_minimum_size()),
				str(c.is_visible_in_tree()), str(c.modulate)])
	var panel: Node = st.get_node_or_null("Root/Panel")
	if panel is Control:
		_log.append("  panel rect=%s" % str((panel as Control).get_global_rect()))


func _vis(n: Node) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	return bool(n.get("visible"))


func _force_clear() -> void:
	PauseManager.clear_all()
	for n: Node in get_tree().get_nodes_in_group(UIInputRouter.GROUP):
		if n.has_method(&"force_close"):
			n.call("force_close")
	PopupManager.release_all()
	PauseManager.clear_all()
	await _frames(2)


func _esc() -> InputEventKey:
	var ev: InputEventKey = InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	return ev


func _root(n: String) -> Node:
	# UI 现在可能挂在 Menus/GUI 容器下，不再直属 root；用注册表的递归查找兜底，
	# 这样测试不受容器层级影响（沿用'按名字访问'的旧写法，迁移期无需逐个改路径）。
	return UIRegistry.find_by_name(n)


func _settle() -> void:
	for _i: int in 300:
		if not SceneDirector.is_changing():
			break
		await get_tree().process_frame
	await _frames(8)


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_dir.path_join("%s.png" % label))
	print("[CaptureSettings] ", label)


func _frames(n: int) -> void:
	for _i: int in n:
		await get_tree().process_frame
