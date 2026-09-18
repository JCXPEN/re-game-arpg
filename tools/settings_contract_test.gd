## SettingsContractTest —— 设置面板的退出契约 + 滑块可见性回归
##
## 【负责什么】
##   钉死用户报的两条：
##     A. **设置面板能退出**：从暂停菜单/主菜单打开后，Esc / 确定 / 返回 任一途径都能关掉。
##        根因曾是 SettingsPanel 漏设 PROCESS_MODE_ALWAYS → 暂停中按钮点不动。
##     B. **滑块线条可见**：HSlider 轨道样式盒必须有非零高度（content_margin），
##        否则只画出把手、没有线（用户报"看不见滑块的线条"）。
##     C. **面板只有一个实例**：主菜单与暂停菜单共用同一个，避免 Esc 作用错对象。
##
## 【怎么运行】Godot --headless --path . res://tools/settings_contract_test.tscn
extends Node

var _pass: int = 0
var _fail: int = 0

func _ready() -> void:
	print("")
	print("################################################")
	print("#  设置面板：退出契约 + 滑块可见性")
	print("################################################")
	await get_tree().process_frame
	var boot: Node = load("res://scenes/core/boot.tscn").instantiate()
	boot.name = "Boot"
	boot.set("show_menu", true)
	get_tree().root.add_child.call_deferred(boot)
	await _frames(12)

	await _case_panel_always()
	await _case_slider_track_visible()
	await _case_esc_from_pause()
	await _case_esc_from_main_menu()
	await _case_confirm_button()
	await _case_single_instance()

	print("")
	print("################################################")
	print("# 设置契约：%d 通过，%d 失败" % [_pass, _fail])
	print("################################################")
	get_tree().quit(1 if _fail > 0 else 0)


## A. 面板必须在暂停中也能处理输入（PROCESS_MODE_ALWAYS）。
func _case_panel_always() -> void:
	print("")
	print("--- A. 暂停中面板仍可交互 ---")
	var st: Node = await _open_from_pause()
	_field("设置面板打开", _vis(st), "没打开")
	_field("打开时游戏处于暂停", get_tree().paused, "paused=false")
	_field("面板 process_mode=ALWAYS", st.process_mode == Node.PROCESS_MODE_ALWAYS,
		"process_mode=%d（暂停中按钮点不动 → 设置无法退出）" % st.process_mode)
	_field("暂停中 can_process() 为 true", st.can_process(), "can_process()=false")
	_close_all()


## B. 滑块轨道样式盒必须有实际高度，否则"看不见线条"。
func _case_slider_track_visible() -> void:
	print("")
	print("--- B. 滑块轨道可见（非零高度） ---")
	var st: Node = await _open_from_pause()
	var master: HSlider = st.get_node_or_null("Root/Panel/Margin/VBox/MasterRow/Master") as HSlider
	_field("找到主音量滑块", master != null, "节点路径不对：Root/Panel/Margin/VBox/MasterRow/Master")
	if master == null:
		_close_all()
		return
	var track: StyleBox = master.get_theme_stylebox("slider")
	_field("轨道样式盒已定义", track != null, "slider stylebox 为空")
	var min_h: float = track.get_minimum_size().y if track != null else 0.0
	_field("轨道有可见厚度（min_height >= 4）", min_h >= 4.0,
		"轨道最小高度=%.1f —— 为 0 时 HSlider 不画轨道，玩家只看到把手（看不见线条）" % min_h)
	# 已填充段的厚度必须与轨道一致，否则两者错位。
	var fill: StyleBox = master.get_theme_stylebox("grabber_area")
	var fill_h: float = fill.get_minimum_size().y if fill != null else 0.0
	_field("已填充段与轨道等高", is_equal_approx(fill_h, min_h),
		"填充段高=%.1f vs 轨道高=%.1f（会错位）" % [fill_h, min_h])
	# 滑块本体的最小高度也应随之被撑开。
	_field("滑块本体高度足够容纳轨道", master.get_combined_minimum_size().y >= 8.0,
		"combined_min_size.y=%.1f" % master.get_combined_minimum_size().y)
	_close_all()


## C1. 暂停菜单打开 → Esc 关闭，且暂停菜单仍在、游戏仍暂停。
func _case_esc_from_pause() -> void:
	print("")
	print("--- C1. 暂停菜单 → 设置 → Esc ---")
	var st: Node = await _open_from_pause()
	var pause: Node = _root("PauseMenu")
	_field("设置打开", _vis(st), "没打开")
	UIInputRouter.handle_cancel(_esc())
	await _frames(4)
	_field("Esc 关闭设置", not _vis(st), "设置没关掉（玩家被困）")
	_field("关闭后暂停菜单仍在", _vis(pause), "暂停菜单被一起关掉")
	_field("关闭后游戏仍暂停（回到暂停菜单）", get_tree().paused and PauseManager.holds(&"pause_menu"),
		"暂停被放跑：holders=%s" % str(PauseManager.get_holders()))
	_close_all()


## C2. 主菜单打开 → Esc 关闭（MainMenu 不能把 Esc 抢走吞掉）。
func _case_esc_from_main_menu() -> void:
	print("")
	print("--- C2. 主菜单 → 设置 → Esc ---")
	GameFlow.teardown_to_menu(true)
	await _frames(10)
	var menu: Node = _root("MainMenu")
	menu.call("_open_settings")
	await _frames(4)
	var st: Node = SettingsPanel.acquire(null)
	_field("主菜单打开设置", _vis(st), "没打开")
	# 真实输入：验证 MainMenu._unhandled_input 不再抢走 Esc。
	Input.parse_input_event(_esc())
	await _frames(5)
	_field("主菜单下 Esc 关闭设置", not _vis(st),
		"设置没关掉（MainMenu 抢先把 Esc 吞了，router 收不到）")
	_close_all()


## C3. 改动即时生效并落盘；点"确定"能关闭。
##
## 【为什么"落盘"与"关闭"分开断言】拆分 SettingsService 后，语义变为：
##   玩家一改滑块就即时应用 + 落盘（不必等确定），"确定/返回"只负责关闭面板。
##   这比"关闭才保存"更不容易丢设置（中途崩溃 / 强退也不会丢）。
func _case_confirm_button() -> void:
	print("")
	print("--- C3. 确定按钮 + 即时落盘 ---")
	var st: Node = await _open_from_pause()
	var path: String = SettingsService.SETTINGS_PATH
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# 模拟玩家拖动音效滑块 → 应立即落盘。
	# 【为什么要挑一个"与当前不同"的值】若赋的值恰好等于当前值，value_changed 不触发、
	#   也就不会落盘（上一次运行若存了同一值，断言会假失败）。
	var sfx: HSlider = st.get_node_or_null(
		"Root/Panel/Margin/VBox/SfxRow/Sfx") as HSlider
	_field("找到音效滑块", sfx != null, "节点路径不对")
	var target: float = 0.5 if not is_equal_approx(sfx.value, 0.5) else 0.7
	if sfx != null:
		sfx.value = target
		await _frames(2)
	_field("改动滑块后设置已落盘", FileAccess.file_exists(path),
		"settings.cfg 不存在（设置丢失）")
	_field("服务已应用该值", is_equal_approx(SettingsService.sfx_volume(), target),
		"服务值=%s（期望 %s）" % [str(SettingsService.sfx_volume()), str(target)])

	var btn: Button = st.get_node_or_null("Root/Panel/Margin/VBox/Actions/btn_confirm") as Button
	_field("找到确定按钮", btn != null, "节点路径不对")
	if btn != null:
		btn.pressed.emit()
		await _frames(3)
	_field("点确定后设置关闭", not _vis(st), "仍可见")
	_close_all()


## C4. 主菜单与暂停菜单共用同一个设置实例。
func _case_single_instance() -> void:
	print("")
	print("--- C4. 面板唯一实例 ---")
	_close_all()
	var menu: Node = _root("MainMenu")
	menu.call("_open_settings")
	await _frames(3)
	var a: Node = SettingsPanel.acquire(null)
	UIInputRouter.handle_cancel(_esc())
	await _frames(3)
	# 现在从暂停菜单打开：必须是同一个节点。
	var b: Node = await _open_from_pause()
	_field("两个入口拿到同一实例", a == b,
		"出现多个 SettingsPanel 实例，Esc/可见性会作用错对象")
	_close_all()


# ============================================================================
# 工具
# ============================================================================

func _open_from_pause() -> Node:
	var pause: Node = _root("PauseMenu")
	if pause != null:
		pause.call("open")
	await _frames(2)
	# 走真实按钮路径（btn_settings → _open_settings）。
	if pause != null:
		var btn: Node = pause.find_child("btn_settings", true, false)
		if btn is Button:
			(btn as Button).pressed.emit()
		else:
			pause.call("_open_settings")
	await _frames(4)
	return SettingsPanel.acquire(null)


func _close_all() -> void:
	PauseManager.clear_all()
	for n: Node in get_tree().get_nodes_in_group(UIInputRouter.GROUP):
		if n.has_method(&"force_close"):
			n.call(&"force_close")
	PopupManager.release_all()
	var pause: Node = _root("PauseMenu")
	if pause != null and pause.has_method(&"close"):
		pause.call("close")
	PauseManager.clear_all()
	await _frames(2)


func _check(ok: bool, msg: String, detail: String) -> void:
	if ok:
		_pass += 1
		print("  [PASS] " + msg)
	else:
		_fail += 1
		print("  [FAIL] " + msg + " :: " + detail)


func _field(msg: String, ok: bool, detail: String) -> void:
	_check(ok, msg, "%s :: %s" % [msg, detail])


func _vis(n: Node) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	return bool(n.get("visible"))


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


func _frames(n: int) -> void:
	for _i: int in n:
		await get_tree().process_frame
