## PopupContractTest —— 弹窗 / 对话窗口"统一契约"回归测试
##
## 【负责什么】
##   钉死这次改造的四条硬性要求，防止哪次改动又把窗口改回"关不掉"：
##     1. **统一关闭**：教程 / 帮助 / 对话条都必须能被 **J**、**回车**、
##        **窗口内左键**关掉。
##     2. **关闭按钮 × 渲染正确**：必须用程序生成的贴图，而不是字体里
##        根本没有的 "✕" 字形（会变成豆腐块）。
##     3. **互斥**：同一时刻只允许一个窗口；多来源触发时按优先级排队，
##        关掉一个才显示下一个。
##     4. **系统级窗口冻结游戏**：教程 / 帮助显示期间 get_tree().paused，
##        关闭后恢复；且"本来就是暂停"的场景不能被错误恢复成运行。
##
## 【怎么运行】
##   Godot --headless --path . res://tools/popup_contract_test.tscn
##
## 【依赖谁】
##   PopupManager（autoload）、TutorialUI / DialogUI / HelpPanel 三个场景。
extends Node

# ============================================================================
# 私有变量
# ============================================================================

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	_install_ui()
	await get_tree().process_frame
	await get_tree().process_frame

	await _test_close_button_uses_icon()
	await _test_tutorial_freezes_game()
	await _test_tutorial_close_by_key(KEY_J, "J")
	await _test_tutorial_close_by_key(KEY_ENTER, "回车")
	await _test_tutorial_close_by_left_click()
	await _test_mutual_exclusion_queue()
	await _test_help_freeze_and_restore()

	print("")
	print("################################################")
	print("# 弹窗统一契约：%d 通过，%d 失败" % [_pass, _fail])
	for f: String in _fails:
		print("  - " + f)
	print("################################################")
	get_tree().quit(0 if _fail == 0 else 1)


# ============================================================================
# 用例
# ============================================================================

## 2) 关闭按钮必须用贴图，不能再用字体里没有的 "✕" 字形。
func _test_close_button_uses_icon() -> void:
	print("")
	print("--- 1. 关闭按钮 × 的渲染方式 ---")
	var tut: CanvasLayer = _find_tutorial()
	if tut == null:
		_failed("TutorialUI 未挂载")
		return
	var btn: Button = tut.get_node_or_null("Root/Panel/Margin/VBox/Header/Close")
	if btn == null:
		_failed("教程缺少关闭按钮（Root/Panel/Margin/VBox/Header/Close）")
		return
	_check(btn.icon != null,
		"关闭按钮用贴图渲染 ×（不依赖任何字体字形）",
		"关闭按钮没有 icon，会退化成字体渲染（像素字体缺 U+2715 → 豆腐块）")
	_check(btn.text == "",
		"关闭按钮不再使用 ✕ 文字",
		"关闭按钮仍有文字「%s」，字体缺字形时会显示成豆腐块" % btn.text)


## 4) **系统级**教程提示显示期间必须冻结游戏，关闭后恢复。
## 注意"冻结"不是教程提示的默认行为：只有 pause_game = true 的步骤才冻结
## （见 _show_tutorial 与 tutorial_ui.gd 文件头）。
func _test_tutorial_freezes_game() -> void:
	print("")
	print("--- 2. 教程/系统窗口冻结游戏 ---")
	var panel: Control = await _show_tutorial("冻结测试")
	if panel == null:
		return
	_check(get_tree().paused,
		"教程显示期间游戏被冻结（角色不能移动 / 不能交互）",
		"教程显示时 get_tree().paused 仍是 false，玩家照样能跑能打")
	# 关闭走窗口自己的入口（与玩家按 J / 点面板同一条路径）：它会推进 TutorialSystem，
	# 由系统交还暂停令牌。裸 emit 一个"收起"信号只画不管状态，令牌会留在半路。
	_find_tutorial().call("dismiss_current")
	await get_tree().create_timer(0.5).timeout
	_check(not get_tree().paused,
		"关闭教程后游戏恢复运行",
		"关闭教程后游戏还是暂停的（玩家被卡住）")


## 1) 按 J / 回车都能关掉教程。
func _test_tutorial_close_by_key(keycode: int, label: String) -> void:
	print("")
	print("--- 3. 按 %s 关闭教程 ---" % label)
	var panel: Control = await _show_tutorial("按键关闭测试")
	if panel == null:
		return
	await _press_key(keycode)
	await get_tree().create_timer(0.5).timeout
	_check(not panel.visible,
		"按 %s 能关闭教程" % label,
		"按 %s 关不掉教程（面板还开着）" % label)
	_ensure_unpaused()


## 1) 左键点窗口内任意处（不只是 ✕ 按钮）就能关掉教程。
func _test_tutorial_close_by_left_click() -> void:
	print("")
	print("--- 4. 左键点窗口内关闭教程 ---")
	var panel: Control = await _show_tutorial("左键关闭测试")
	if panel == null:
		return
	_click_inside(panel)
	await get_tree().create_timer(0.5).timeout
	_check(not panel.visible,
		"左键点窗口内任意处即可关闭教程",
		"左键点窗口内关不掉教程（玩家只能去戳那个小 ✕）")
	_ensure_unpaused()


## 3) 互斥 + 排队：教程在显示时，NPC 对话不能抢屏；教程关掉后对话自动补位。
func _test_mutual_exclusion_queue() -> void:
	print("")
	print("--- 5. 互斥：同时只存在一个弹窗，其余排队 ---")
	var tut: CanvasLayer = _find_tutorial()
	var dlg: CanvasLayer = _find_dialog()
	if tut == null or dlg == null:
		_failed("TutorialUI / DialogUI 未挂载")
		return
	var tut_panel: Control = tut.get_node_or_null("Root/Panel")
	var bar: Control = dlg.get_node_or_null("Root/Bar")
	if tut_panel == null or bar == null:
		_failed("教程面板 / 对话条节点缺失")
		return

	# 先让教程占用屏幕（只有**阻塞型**提示才独占屏幕位置，见 _show_tutorial）。
	if await _show_tutorial("先显示教程。") == null:
		return
	# 再请求一段 NPC 对话 —— 此刻必须排队，不能两个一起弹。
	EventBus.dialog_sequence_requested.emit("村民",
		PackedStringArray(["甲", "乙"]), Callable())
	await get_tree().process_frame
	_check(tut_panel.visible and not bar.visible,
		"教程显示时，对话不抢屏（进队列等待）",
		"两个窗口同时弹出：tutorial=%s bar=%s" % [tut_panel.visible, bar.visible])
	_check(PopupManager.active_id() == &"tutorial",
		"当前活跃窗口是教程",
		"活跃窗口 id=%s（应为 tutorial）" % PopupManager.active_id())

	# 关掉教程 → 排队的对话应当被自动叫醒。
	# 走窗口自己的关闭入口（与玩家按 J / 点面板同一条路径）：它会 release 弹窗位置
	# 并交还暂停令牌，不能只 emit 一个"收起"信号把系统状态留在半路。
	tut.call("dismiss_current")
	await get_tree().create_timer(0.5).timeout
	_check(bar.visible,
		"教程关闭后，排队的对话自动显示",
		"教程关了，但排队的对话没有补位显示")
	_ensure_unpaused()
	# 收尾：把对话也关掉，别把状态留给后面的用例。
	await _press_key(KEY_J)
	await get_tree().process_frame


## 4) 帮助面板：冻结游戏 + 精确还原（从暂停菜单进来不能把游戏放跑）。
func _test_help_freeze_and_restore() -> void:
	print("")
	print("--- 6. 帮助面板冻结与精确还原 ---")
	var help: CanvasLayer = load("res://scenes/ui/help_panel.tscn").instantiate() as CanvasLayer
	get_tree().root.add_child(help)
	await get_tree().process_frame

	# 场景 A：游戏本来在跑 → 打开帮助要冻结，关闭要恢复。
	PauseManager.clear_all()
	help.call("open")
	await get_tree().process_frame
	_check(get_tree().paused,
		"帮助打开时冻结游戏",
		"帮助打开没有冻结游戏（角色还能动）")
	help.call("close")
	await get_tree().process_frame
	_check(not get_tree().paused,
		"帮助关闭后恢复游戏",
		"帮助关闭后游戏仍是暂停的")
	_check(PauseManager.holder_count() == 0,
		"帮助关闭后 PauseManager 不残留令牌",
		"帮助关闭后仍有令牌：%s" % str(PauseManager.get_holders()))

	# 场景 B：本来就是暂停（从暂停菜单进入）→ 关闭后必须**保持**暂停，
	# 否则玩家一关帮助就直接掉回游戏、跳过暂停菜单。
	#
	# 【重构后怎么表达"暂停菜单开着"】不再裸写 `paused = true`（绕过所有权
	#   写状态正是被修掉的病灶），改用 PauseMenu 同款契约
	#   `PauseManager.freeze(&"pause_menu")`。这样断言的是真正要保的性质：
	#   帮助交还自己的令牌后，暂停菜单的令牌还在 ⇒ 游戏保持暂停。
	PauseManager.freeze(&"pause_menu")
	help.call("open")
	await get_tree().process_frame
	help.call("close")
	await get_tree().process_frame
	_check(get_tree().paused,
		"从暂停菜单进入时，关闭帮助后仍保持暂停（回到暂停菜单）",
		"关闭帮助把游戏放跑了（paused 被错误恢复成 false）")
	_check(PauseManager.holds(&"pause_menu") and not PauseManager.holds(&"help"),
		"帮助只交还自己的令牌，暂停菜单的令牌不受影响",
		"令牌归属错乱：%s" % str(PauseManager.get_holders()))

	PauseManager.clear_all()
	help.queue_free()


# ============================================================================
# 私有方法 —— 工具
# ============================================================================

func _install_ui() -> void:
	# 必须 call_deferred：_ready 期间 root 正在设置子节点，直接 add_child 会
	# 报 "Parent node is busy setting up children" 并静默失败。
	for path: String in ["res://scenes/ui/tutorial_ui.tscn",
			"res://scenes/ui/dialog_ui.tscn"]:
		if not ResourceLoader.exists(path):
			print("  [install] 不存在：", path)
			continue
		var inst: Node = (load(path) as PackedScene).instantiate()
		get_tree().root.add_child.call_deferred(inst)


## 显示一条**阻塞型**教程，返回它的面板；失败返回 null。
##
## 【为什么要造数据、不能直接 emit 信号】提示是否冻结游戏 / 独占屏幕由
##   `TutorialStep.pause_game` 决定（操作类提示是非阻塞的，见 tutorial_ui.gd 文件头），
##   而本套用例验的正是"阻塞窗口"的互斥与关闭契约 —— 必须真造一条
##   pause_game = true 的步骤并走 TutorialSystem 的真实入口，不能假设提示一律阻塞。
##
## 【为什么给两步】dismiss_current_step() 会往下一步推进；只有一步时
##   _try_start_next() 会走 _finish() 把"教程已完成"写进存档，污染后续用例。
func _show_tutorial(body: String) -> Control:
	var tut: CanvasLayer = _find_tutorial()
	if tut == null:
		_failed("TutorialUI 未挂载")
		return null
	var first: TutorialStep = TutorialStep.new()
	first.pause_game = true
	first.title = "测试标题"
	first.text = body
	var second: TutorialStep = TutorialStep.new()
	# 空档步骤绑一个不存在的关卡：`level_id` 为空表示"任意关卡都匹配"，
	# 若当前正好在某个关卡里，关掉本步后会立刻又播一步，断言就失真了。
	second.level_id = &"__never__"
	var steps: Array[TutorialStep] = [first, second]
	TutorialSystem.set("_steps", steps)
	TutorialSystem.set("_enabled", false)
	TutorialSystem.set("_active", false)
	TutorialSystem.set("_index", 0)
	TutorialSystem.call("_show_step", first)
	await get_tree().process_frame
	var panel: Control = tut.get_node_or_null("Root/Panel")
	if panel == null or not panel.visible:
		_failed("教程面板没显示出来（前置条件失败）")
		return null
	return panel


## 不靠节点名找（实例化后可能被重命名），按脚本路径找。
func _find_tutorial() -> CanvasLayer:
	return _find_by_script("tutorial_ui")


func _find_dialog() -> CanvasLayer:
	return _find_by_script("dialog_ui")


func _find_by_script(keyword: String) -> CanvasLayer:
	for n: Node in get_tree().root.get_children():
		if n is CanvasLayer:
			var cl: CanvasLayer = n as CanvasLayer
			if cl.get_script() != null \
					and keyword in cl.script.resource_path.to_lower():
				return cl
	return null


## 模拟一次真实的键盘按下 + 抬起（走 Input，能触发 _unhandled_input）。
func _press_key(keycode: int) -> void:
	var down: InputEventKey = InputEventKey.new()
	down.keycode = keycode
	down.physical_keycode = keycode
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up: InputEventKey = InputEventKey.new()
	up.keycode = keycode
	up.physical_keycode = keycode
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


## 模拟鼠标左键点在某个 Control 正中央（走 gui_input，与真实点击同路径）。
func _click_inside(control: Control) -> void:
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = control.get_global_rect().get_center()
	control.gui_input.emit(ev)


## 兜底：用例之间确保游戏是运行的，别把暂停状态带进下一个用例。
func _ensure_unpaused() -> void:
	if get_tree().paused:
		get_tree().paused = false
	await get_tree().process_frame


func _check(ok: bool, msg: String, detail: String) -> void:
	if ok:
		_pass += 1
		print("  [PASS] " + msg)
	else:
		_failed(detail)
		print("  [FAIL] " + msg)


## 不依赖"面板是否取到"的直接失败记录（用于前置条件就崩了的场景）。
func _failed(detail: String) -> void:
	_fail += 1
	_fails.append(detail)
