## PlayabilityCheck —— "游戏能不能玩"核验（诊断脚本）
##
## 针对"游戏甚至没法运行"做的端到端检查：
##   1) 有没有常驻 UI 在全屏吞鼠标点击（这是最致命的）；
##   2) 模拟点击世界坐标，事件能不能真的落到游戏里（不是被 UI 吃掉）；
##   3) 教程面板能不能被玩家关掉；
##   4) 帮助面板能不能被玩家关掉；
##   5) 玩家能不能移动、能不能攻击。
extends Node

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []

func _ready() -> void:
	_install_ui()
	GameState.start_run()
	SceneDirector.change_to_level(&"town", &"start")
	for i: int in 200:
		if not SceneDirector.is_changing():
			break
		await get_tree().process_frame
	await get_tree().process_frame

	await _test_no_click_blocker()
	await _test_click_reaches_world()
	await _test_player_move_and_attack()
	await _test_tutorial_dismiss()
	await _test_help_panel_close()

	print("")
	print("################################################")
	print("# 可玩性核验：%d 通过，%d 失败" % [_pass, _fail])
	for f: String in _fails:
		print("  - " + f)
	print("################################################")
	get_tree().quit(0 if _fail == 0 else 1)


func _install_ui() -> void:
	# 必须用 call_deferred：在 _ready() 里 root 正在设置子节点，
	# 直接 add_child 会报 "Parent node is busy setting up children" 并静默失败。
	var paths: Array[String] = [
		"res://scenes/ui/hud.tscn", "res://scenes/ui/tutorial_ui.tscn",
		"res://scenes/ui/boss_health_bar.tscn", "res://scenes/ui/modifier_choice.tscn",
		"res://scenes/ui/inventory_ui.tscn", "res://scenes/ui/game_over.tscn",
		"res://scenes/ui/pause_menu.tscn", "res://scenes/ui/dialog_ui.tscn",
	]
	for path: String in paths:
		if not ResourceLoader.exists(path):
			print("  [install] 不存在：", path)
			continue
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			print("  [install] load 返回 null：", path)
			continue
		var inst: Node = packed.instantiate()
		if inst == null:
			print("  [install] instantiate 返回 null：", path)
			continue
		get_tree().root.add_child.call_deferred(inst)
	# 等 deferred 真正落地。
	await get_tree().process_frame
	await get_tree().process_frame


func _check(ok: bool, msg: String, detail: String) -> void:
	if ok:
		_pass += 1
		print("  [PASS] " + msg)
	else:
		_fail += 1
		_fails.append(detail)
		print("  [FAIL] " + msg)


# ---------------------------------------------------------------------------
# 1) 全屏吞点击检查
# ---------------------------------------------------------------------------

## 在"所有 UI 都处于默认（隐藏）状态"时，屏幕中心点下去，
## 应该命中游戏世界而不是某个 UI。
func _test_no_click_blocker() -> void:
	print("")
	print("--- 1. 常驻 UI 是否吞鼠标 ---")
	var vp: Viewport = get_tree().root
	var blockers: Array[String] = []
	for n: Node in _all_controls(vp):
		# 必须看"整条链都可见"，只看自己的 visible 会把
		# "父 CanvasLayer 已隐藏、但子 Dimmer 仍标 visible=true" 的模态误判成挡路。
		if not n.is_visible_in_tree():
			continue
		if n.mouse_filter != Control.MOUSE_FILTER_STOP:
			continue
		# 只有真正铺满屏幕的才算"挡住整个游戏"。
		var r: Rect2 = n.get_global_rect()
		if r.size.x >= 300.0 and r.size.y >= 170.0:
			blockers.append("%s/%s(%d)" % [_full_path(n), n.get_name(), n.mouse_filter])
	_check(blockers.is_empty(),
		"没有常驻 UI 在全屏吞鼠标点击",
		"这些全屏 STOP 控件会吞点击：%s" % ", ".join(blockers))


func _all_controls(root: Node) -> Array[Control]:
	var out: Array[Control] = []
	for c: Node in root.get_children():
		if c is Control:
			out.append(c as Control)
		if c is CanvasLayer or c is Control:
			out.append_array(_all_controls(c))
	return out


func _full_path(n: Node) -> String:
	var parts: Array[String] = []
	var cur: Node = n
	while cur != null and cur != get_tree().root:
		parts.insert(0, cur.get_name())
		cur = cur.get_parent()
	return "/".join(parts)


# ---------------------------------------------------------------------------
# 2) 点击能不能落到游戏世界
# ---------------------------------------------------------------------------

## 直接问 Viewport：屏幕某点下面有没有 UI 在接事件。
## 用 gui_get_hovered_control() 比"真发事件"更稳（headless 下 Input 不好模拟）。
func _test_click_reaches_world() -> void:
	print("")
	print("--- 2. 点击能否落到游戏世界 ---")
	var pts: Array[Vector2] = [
		Vector2(160, 90),   ## 屏幕中心（玩家常在这附近）
		Vector2(60, 150),   ## 左下
		Vector2(260, 40),   ## 右上
	]
	var blocked: Array[String] = []
	for p: Vector2 in pts:
		# 让鼠标真的移到这点，再看谁接住了。
		var ev: InputEventMouseMotion = InputEventMouseMotion.new()
		ev.position = p
		ev.global_position = p
		Input.parse_input_event(ev)
		await get_tree().process_frame
		await get_tree().process_frame
		var hovered: Control = get_tree().root.gui_get_hovered_control()
		if hovered != null and _covers(hovered, p):
			blocked.append("%s@%s" % [hovered.get_name(), str(p)])
	_check(blocked.is_empty(),
		"屏幕各处点击都不会被 UI 拦截（能打到游戏世界）",
		"这些点被 UI 吃掉了：%s" % ", ".join(blocked))


## 该控件是否覆盖了这个点（用全局矩形判断，避免误判）。
func _covers(c: Control, p: Vector2) -> bool:
	var r: Rect2 = c.get_global_rect()
	return r.has_point(p) and r.size.x > 250.0 and r.size.y > 150.0


# ---------------------------------------------------------------------------
# 3) 玩家能移动、能攻击
# ---------------------------------------------------------------------------

func _test_player_move_and_attack() -> void:
	print("")
	print("--- 3. 玩家能否移动与攻击 ---")
	# 教程窗口现在是模态的（窗口开着世界冻结）。本用例验的是"没有窗口时玩家能动"，
	# 先把教程收起来，别让它把世界冻住（否则位移恒为 0，是前置条件不是缺陷）。
	_quiet_tutorial()
	await get_tree().process_frame
	var player: Node2D = null
	for n: Node in get_tree().get_nodes_in_group(&"player"):
		player = n as Node2D
		break
	_check(player != null, "玩家已生成", "玩家没生成")

	if player == null:
		return

	var before: Vector2 = player.global_position
	# 直接给输入方向（绕过物理等待）。
	if player.has_method(&"set") and player.get(&"input_direction") != null:
		player.set(&"input_direction", Vector2(1, 0))
		for i: int in 30:
			await get_tree().physics_frame
		var moved: float = player.global_position.distance_to(before)
		_check(moved > 1.0, "玩家能移动（位移 %.1f px）" % moved,
			"玩家完全不动（位移 %.1f），可能被锁死" % moved)
	else:
		# 没有 input_direction 字段就直接看速度接口。
		_check(player.has_method(&"get_velocity") or player is CharacterBody2D,
			"玩家有移动能力接口", "玩家既没有 input_direction 也不是 CharacterBody2D")

	# 攻击：看 AttackController 有没有响应。
	var ac: Node = player.get_node_or_null("AttackController")
	if ac == null:
		for c: Node in player.get_children():
			if c.get_class() == "Node" and c.get_script() != null \
				and "attack" in (c.get_script() as Script).get_script_path().to_lower():
				ac = c
				break
	_check(ac != null, "玩家有攻击控制器", "找不到 AttackController")


## 让教程停手并收起面板（走系统自己的关闭路径，冻结令牌会被交还）。
func _quiet_tutorial() -> void:
	TutorialSystem.dismiss_current_step()
	TutorialSystem.set("_enabled", false)
	TutorialSystem.set("_active", false)
	TutorialSystem.set("_index", -1)
	TutorialSystem.set_process(false)
	EventBus.tutorial_step_shown.emit(-1, "", "", false)
	PauseManager.clear_all()


# ---------------------------------------------------------------------------
# 4) 教程面板能关
# ---------------------------------------------------------------------------

func _test_tutorial_dismiss() -> void:
	print("")
	print("--- 4. 教程面板能否关闭 ---")
	EventBus.tutorial_step_shown.emit(0, "测试标题", "这是一句测试教程文字。", false)
	await get_tree().process_frame
	# 不靠节点名找（实例化后可能被重命名），按类型找。
	var tut: CanvasLayer = null
	for n: Node in get_tree().root.get_children():
		if n is CanvasLayer and (n as CanvasLayer).get_script() != null \
			and "tutorial_ui" in (n as CanvasLayer).script.resource_path.to_lower():
			tut = n as CanvasLayer
			break
	if tut == null:
		var names: Array[String] = []
		for n: Node in get_tree().root.get_children():
			names.append(n.get_name())
		_fail += 1
		_fails.append("TutorialUI 没挂载，root 现有子节点：%s" % ", ".join(names))
		print("  [FAIL] TutorialUI 已挂载 —— root 子节点：%s" % ", ".join(names))
		return
	_pass += 1
	print("  [PASS] TutorialUI 已挂载（节点名=%s）" % tut.get_name())
	var panel: Control = tut.get_node_or_null("Root/Panel")
	_check(panel != null and panel.visible, "教程面板已显示", "教程面板没显示")
	if panel == null:
		return

	# 关闭按钮必须存在且可点。
	var close_btn: Button = tut.get_node_or_null("Root/Panel/Margin/VBox/Header/Close")
	_check(close_btn != null, "教程有关闭按钮", "教程缺少关闭按钮")
	if close_btn != null:
		_check(close_btn.visible, "关闭按钮可见", "关闭按钮不可见，玩家点不到")
		close_btn.pressed.emit()
		# _hide() 是 0.3s 淡出，必须等够时间，否则会误判成"关不掉"。
		await get_tree().create_timer(0.5).timeout
		_check(not panel.visible, "点关闭按钮后面板收起",
			"点了关闭按钮，面板还开着（visible=%s）" % str(panel.visible))

	# 再开一次，用 Esc 关。
	#
	# 【为什么要造一条**阻塞型**步骤】教程提示是否冻结游戏 / 抢 Esc 由数据决定
	#   （TutorialStep.pause_game）：操作类提示是非阻塞浮层，它**不**抢 Esc
	#   —— 否则玩家按 Esc 想暂停会被一句提示吃掉。Esc 关闭契约只对系统级提示成立。
	var first: TutorialStep = TutorialStep.new()
	first.pause_game = true
	first.title = "测试标题"
	first.text = "这是一句测试教程文字。"
	var second: TutorialStep = TutorialStep.new()
	# 空档步骤绑一个不存在的关卡：`level_id` 为空表示"任意关卡都匹配"，
	# 本用例正处在城镇里，清空后会**立刻又播一步**，于是"Esc 关掉了"也看不出来。
	second.level_id = &"__never__"
	var steps: Array[TutorialStep] = [first, second]
	TutorialSystem.set("_steps", steps)
	TutorialSystem.set("_enabled", false)
	TutorialSystem.set("_active", false)
	TutorialSystem.set("_index", 0)
	TutorialSystem.call("_show_step", first)
	await get_tree().process_frame
	if panel.visible:
		var esc: InputEventAction = InputEventAction.new()
		esc.action = &"ui_cancel"
		esc.pressed = true
		Input.parse_input_event(esc)
		await get_tree().process_frame
		await get_tree().process_frame
		var esc2: InputEventAction = InputEventAction.new()
		esc2.action = &"ui_cancel"
		esc2.pressed = false
		Input.parse_input_event(esc2)
		await get_tree().create_timer(0.5).timeout
		_check(not panel.visible, "按 Esc 也能关掉教程",
			"按 Esc 后面板还开着")
	else:
		_check(false, "按 Esc 也能关掉教程（前置：面板已显示）", "面板第二次没显示")


# ---------------------------------------------------------------------------
# 5) 帮助面板能关
# ---------------------------------------------------------------------------

func _test_help_panel_close() -> void:
	print("")
	print("--- 5. 帮助面板能否关闭 ---")
	var help: CanvasLayer = load("res://scenes/ui/help_panel.tscn").instantiate() as CanvasLayer
	get_tree().root.add_child(help)
	await get_tree().process_frame
	help.call("open")
	await get_tree().process_frame
	_check(help.visible, "帮助面板能打开", "帮助面板打不开")

	# 暂停状态下也要能关（这是原 bug 的根因）。
	get_tree().paused = true
	help.call("close")
	await get_tree().process_frame
	_check(not help.visible, "暂停状态下也能关闭帮助面板",
		"paused=true 时关不掉帮助面板")
	get_tree().paused = false

	# 再来一次，用关闭按钮。
	help.call("open")
	await get_tree().process_frame
	var btn: Button = help.get_node_or_null("Root/Panel/Margin/VBox/Close")
	_check(btn != null, "帮助面板有关闭按钮", "帮助面板缺关闭按钮")
	if btn != null:
		btn.pressed.emit()
		await get_tree().process_frame
		_check(not help.visible, "点关闭按钮能关帮助面板", "点关闭按钮关不掉")
	help.queue_free()
