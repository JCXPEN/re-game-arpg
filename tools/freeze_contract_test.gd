## FreezeContractTest —— "冻结"契约回归测试（教程冻结 + 冻结期间的对话）
##
## 【负责什么】
##   钉死本次修复的四组性质，防止哪次改动又把它们改回去：
##
##   A. **冻结由状态推导，不靠成对调用**
##      1. 阻塞步骤显示时世界真的冻结；推进后真的恢复（令牌不残留）。
##      2. **连续两个阻塞步骤之间冻结不中断** —— 中途不能发出 freeze_ended
##         （"世界短暂放跑一下"对 AI / BGM / 存档都是可观测的副作用）。
##      3. 每一条出口都交还令牌：`skip_tutorial()` / `reset()` / 教程结束
##         —— 旧实现在 `skip_tutorial()` 上漏写，玩家会在"世界冻着、界面没了"
##         的状态下被永久锁死。
##      4. **语义护栏**：要玩家在世界里做事才能完成的步骤（`trigger_action` 非空）
##         即使被误配成 `pause_game = true` 也不冻结 —— 否则完成条件永远不可能达成
##         （"靠近村民按 F 交谈"那一步的 NPC 对话会永远不显示）。
##
##   B. **PauseManager 的冻结声明**
##      5. `Cover.WORLD`（只停世界）/ `Cover.SCREEN`（独占屏幕）被如实记录，
##         `covers_screen()` 据此作答；默认按 SCREEN（保守）。
##      6. 持有者被释放却没交还令牌 → 自动回收（冻结泄漏的最后一道防线）。
##
##   C. **NPC 对话在冻结期间与之后都能正常显示**
##      7. 系统级冻结（`Cover.WORLD`）期间：对话条照常显示、照常逐字打完、
##         照常能推进与结算 —— 不再"一冻结就把 NPC 的话连同奖励一起丢掉"。
##      8. 阻塞教程步骤冻结期间发起的对话：排队不抢屏，教程一关就自动补位显示
##         （即"冻结之后正常显示"），且内容完整、奖励照发。
##      9. 被**独占屏幕**的窗口（暂停菜单 / 背包 / 结算…）盖住时，对话必须收掉
##         —— 否则会被压在遮罩下面"看不见也关不掉"（这是旧规则真正要防的场景）。
##     10. 提示条同理：系统级冻结期间能显示，被别的窗口占屏时让位，
##         且让位**不**波及对话条（"提示与对话可以同屏"是硬契约）。
##
## 【怎么运行】
##   Godot --headless --path . res://tools/freeze_contract_test.tscn
##   退出码 0 = 全绿。
##
## 【依赖谁】
##   boot.tscn（真实启动流程）、PauseManager、TutorialSystem / TutorialUI、DialogUI。
extends Node

# ============================================================================
# 私有变量
# ============================================================================

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []

## 冻结信号计数（A2 用：连续阻塞步之间不允许出现 freeze_ended）。
var _freeze_started: int = 0
var _freeze_ended: int = 0

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	var boot: Node = load("res://scenes/core/boot.tscn").instantiate()
	boot.name = "Boot"
	boot.set("skip_menu", true)
	get_tree().root.add_child.call_deferred(boot)
	# 等关卡真的加载完：换场景会广播 scene_changed，而几个窗口会据此收尾，
	# 用例里不能有"背景里还在换场景"这种噪声。
	for i: int in 400:
		if not SceneDirector.is_changing() and SceneDirector.get_current_level() != null:
			break
		await get_tree().physics_frame
	for i: int in 10:
		await get_tree().process_frame
	_quiet_tutorial()
	PauseManager.freeze_started.connect(func() -> void: _freeze_started += 1)
	PauseManager.freeze_ended.connect(func() -> void: _freeze_ended += 1)

	await _test_blocking_step_freezes()
	await _test_chained_blocking_never_thaws()
	await _test_all_exits_release_token()
	await _test_guard_against_self_defeating_freeze()
	await _test_cover_declaration()
	await _test_dead_holder_is_reclaimed()
	await _test_dialog_survives_world_freeze()
	await _test_windows_freeze_world()
	await _test_dialog_queued_then_shown_after_freeze()
	await _test_dialog_yields_to_screen_owner()
	await _test_notice_rules()

	print("")
	print("################################################")
	print("# 冻结契约：%d 通过，%d 失败" % [_pass, _fail])
	for f: String in _fails:
		print("  - " + f)
	print("################################################")
	get_tree().quit(0 if _fail == 0 else 1)


# ============================================================================
# A. 冻结由状态推导
# ============================================================================

func _test_blocking_step_freezes() -> void:
	print("")
	print("--- A1. 阻塞步骤：冻结 / 推进 / 恢复 ---")
	var steps: Array[TutorialStep] = [
		_step("阻塞提示", true),
		_step("后续空档", false, &"", &"__never__"),
	]
	_arm_steps(steps, 0)
	TutorialSystem.call("_show_step", steps[0])
	await get_tree().process_frame
	_check(get_tree().paused, "阻塞步骤显示时世界冻结", "paused=false，角色还能跑能打")
	_check(PauseManager.holds(&"tutorial"), "冻结令牌在教程系统名下",
		"令牌归属异常：%s" % str(PauseManager.get_holders()))
	_check(TutorialSystem.is_current_step_blocking(),
		"系统与 UI 对“这一步是不是阻塞窗口”的答案一致",
		"is_current_step_blocking()=false，UI 会把阻塞步当普通浮层（两个窗口抢屏）")

	# 幂等：同一状态再同步一次不该产生任何状态变化或信号。
	var started_before: int = _freeze_started
	TutorialSystem.call("_sync_pause")
	await get_tree().process_frame
	_check(_freeze_started == started_before and get_tree().paused,
		"重复同步冻结状态是幂等的（无信号抖动、状态不变）",
		"重复同步发了 freeze_started（%d → %d）" % [started_before, _freeze_started])

	# 推进到普通步骤 → 交还令牌。
	TutorialSystem.dismiss_current_step()
	await get_tree().process_frame
	_check(not get_tree().paused and not PauseManager.holds(&"tutorial"),
		"推进到普通提示后世界恢复、令牌不残留",
		"仍暂停或令牌残留：%s" % str(PauseManager.get_holders()))


func _test_chained_blocking_never_thaws() -> void:
	print("")
	print("--- A2. 连续两个阻塞步骤：冻结必须连续不断 ---")
	var steps: Array[TutorialStep] = [_step("阻塞一", true), _step("阻塞二", true)]
	_arm_steps(steps, 0)
	TutorialSystem.call("_show_step", steps[0])
	await get_tree().process_frame
	_check(get_tree().paused, "第一个阻塞步已冻结", "第一个阻塞步没有冻结")

	var started_before: int = _freeze_started
	var ended_before: int = _freeze_ended
	# 推进到下一个阻塞步：世界必须一直是停的，不能"先解冻再冻回来"。
	TutorialSystem.dismiss_current_step()
	await get_tree().process_frame
	_check(get_tree().paused, "第二个阻塞步显示时世界仍是冻结的",
		"推进到下一个阻塞步时把世界放跑了")
	_check(_freeze_ended == ended_before,
		"连续阻塞步之间没有发出 freeze_ended（冻结不中断）",
		"中途发了 %d 次 freeze_ended —— 任何监听冻结状态的系统都会以为“恢复了”"
			% (_freeze_ended - ended_before))
	_check(_freeze_started == started_before,
		"也没有重复发 freeze_started（冻结是连续的，不是“解冻再冻结”）",
		"重复发了 %d 次 freeze_started" % (_freeze_started - started_before))

	# 收尾：换一组"阻塞 + 普通"，让普通步来解冻。
	var tail: Array[TutorialStep] = [_step("阻塞", true), _step("普通", false, &"", &"__never__")]
	_arm_steps(tail, 0)
	TutorialSystem.call("_show_step", tail[0])
	await get_tree().process_frame
	TutorialSystem.dismiss_current_step()
	await get_tree().process_frame
	_check(not get_tree().paused and PauseManager.holder_count() == 0,
		"推进到普通步后解冻（收尾用例）",
		"仍暂停：%s" % str(PauseManager.get_holders()))


func _test_all_exits_release_token() -> void:
	print("")
	print("--- A3. 每一条出口都交还令牌（旧实现漏在 skip_tutorial）---")
	var completed_before: bool = GameState.tutorial_completed

	# 出口 1：skip_tutorial()。
	var s1: Array[TutorialStep] = [_step("阻塞", true), _step("空档", false, &"", &"__never__")]
	_arm_steps(s1, 0)
	TutorialSystem.call("_show_step", s1[0])
	await get_tree().process_frame
	_check(get_tree().paused, "跳过前：阻塞步冻结中（前置条件）", "前置条件失败：没有冻结")
	TutorialSystem.skip_tutorial()
	await get_tree().process_frame
	_check(not get_tree().paused and PauseManager.holder_count() == 0,
		"阻塞步显示期间跳过教程 → 令牌被交还（玩家不会被永久冻住）",
		"跳过教程后世界仍暂停：holders=%s（旧实现就是在这一步漏写交还）"
			% str(PauseManager.get_holders()))
	GameState.tutorial_completed = completed_before

	# 出口 2：reset()（换局路径）。
	var s2: Array[TutorialStep] = [_step("阻塞", true), _step("空档", false, &"", &"__never__")]
	_arm_steps(s2, 0)
	TutorialSystem.call("_show_step", s2[0])
	await get_tree().process_frame
	TutorialSystem.reset()
	await get_tree().process_frame
	_check(not get_tree().paused and PauseManager.holder_count() == 0,
		"reset() 交还令牌（换局不会带着冻结进新局）",
		"reset 后仍暂停：holders=%s" % str(PauseManager.get_holders()))

	# 出口 3：教程结束（最后一步就是阻塞步）。
	var s3: Array[TutorialStep] = [_step("最后一步", true)]
	_arm_steps(s3, 0)
	TutorialSystem.call("_show_step", s3[0])
	await get_tree().process_frame
	TutorialSystem.dismiss_current_step()
	await get_tree().process_frame
	_check(not get_tree().paused and PauseManager.holder_count() == 0,
		"教程走完最后一步后不残留冻结令牌",
		"教程结束后仍暂停：holders=%s" % str(PauseManager.get_holders()))
	TutorialSystem.reset()
	GameState.tutorial_completed = completed_before
	GameState.save_game()


func _test_guard_against_self_defeating_freeze() -> void:
	print("")
	print("--- A4. 语义护栏：完成条件依赖世界的步骤绝不能冻结 ---")
	# 数据被误配：既要玩家在世界里做事（trigger_action），又要求冻结世界。
	var bad: TutorialStep = _step("与 NPC 交谈", true, &"attack")
	var steps: Array[TutorialStep] = [bad, _step("空档", false, &"", &"__never__")]
	_arm_steps(steps, 0)
	TutorialSystem.call("_show_step", bad)
	await get_tree().process_frame
	_check(not get_tree().paused,
		"要玩家做事才能完成的步骤被拒绝冻结（否则完成条件永远达不成）",
		"世界被冻住了：这一步的完成条件（在世界里做某件事）永远不可能达成 → 教程死锁、NPC 对话永远不显示")
	_check(not TutorialSystem.is_current_step_blocking(),
		"护栏同时反映到 is_current_step_blocking()（UI 与系统不各说各话）",
		"UI 仍认为这是阻塞窗口，会去抢弹窗位置（系统却没冻结）")
	_check(PauseManager.holder_count() == 0,
		"被拒绝的冻结不留令牌",
		"残留令牌：%s" % str(PauseManager.get_holders()))
	TutorialSystem.dismiss_current_step()
	await get_tree().process_frame


# ============================================================================
# B. PauseManager 的冻结声明
# ============================================================================

func _test_cover_declaration() -> void:
	print("")
	print("--- B1. 冻结必须说清“是否独占屏幕” ---")
	PauseManager.clear_all()
	PauseManager.freeze(&"sys_intro", PauseManager.Cover.WORLD)
	_check(get_tree().paused, "Cover.WORLD 也会冻结世界", "没有冻结")
	_check(not PauseManager.covers_screen(),
		"Cover.WORLD 不算“盖住别人”（下层窗口照常显示）",
		"covers_screen()=true —— 会把不该收的对话收掉")

	PauseManager.freeze(&"pause_menu", PauseManager.Cover.SCREEN)
	_check(PauseManager.covers_screen(), "Cover.SCREEN 会被记为“独占屏幕”",
		"暂停菜单声明了独占屏幕却没被记录")

	PauseManager.clear_all()
	PauseManager.freeze(&"legacy")   # 老调用点不传 cover
	_check(PauseManager.covers_screen(),
		"不传 cover 时默认按 SCREEN 处理（保守：宁可多收一次下层窗口）",
		"默认没有按独占屏幕处理，被盖住的对话可能“看不见也关不掉”")
	PauseManager.clear_all()
	await get_tree().process_frame
	_check(not get_tree().paused and PauseManager.holder_count() == 0,
		"clear_all 清干净并恢复运行",
		"clear_all 后仍暂停：holders=%s" % str(PauseManager.get_holders()))


func _test_dead_holder_is_reclaimed() -> void:
	print("")
	print("--- B2. 持有者被释放 → 令牌自动回收 ---")
	PauseManager.clear_all()
	var probe: Node = Node.new()
	probe.name = "FreezeProbe"
	get_tree().root.add_child(probe)
	PauseManager.freeze(&"probe", PauseManager.Cover.SCREEN, probe)
	_check(get_tree().paused, "探针持有令牌时世界是暂停的（前置条件）", "探针没能冻结")
	probe.free()                     # 模拟"窗口被销毁却没交还令牌"
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not PauseManager.holds(&"probe") and PauseManager.holder_count() == 0,
		"持有者被释放后令牌自动回收（不会永久冻结）",
		"持有者已释放但令牌仍在：%s" % str(PauseManager.get_holders()))
	_check(not get_tree().paused, "回收后世界恢复运行", "回收后世界仍是暂停的")
	PauseManager.clear_all()


# ============================================================================
# C. NPC 对话在冻结期间 / 之后都能正常显示
# ============================================================================

func _test_dialog_survives_world_freeze() -> void:
	print("")
	print("--- C1. 系统级冻结期间：对话照常显示、照常推进 ---")
	_reset_overlays()
	PauseManager.set_frozen(&"sys_intro", true, PauseManager.Cover.WORLD)
	await get_tree().process_frame

	var done: Array[int] = []
	EventBus.dialog_sequence_requested.emit("村民",
		PackedStringArray(["冻结期间也要能读。", "第二句。"]),
		func() -> void: done.append(1))
	await get_tree().process_frame
	_check(DialogUI.is_open and _bar().visible,
		"世界被冻结时 NPC 对话照常弹出（旧实现会被静默收掉）",
		"对话没显示：is_open=%s bar=%s" % [DialogUI.is_open, _bar().visible])

	# 冻结期间照样逐字打完（本层是 PROCESS_MODE_ALWAYS）。
	await _wait_typing("冻结期间也要能读。")
	_check(_text().text == "冻结期间也要能读。",
		"冻结期间打字机照常跑完",
		"冻结期间文本停在「%s」——对话被冻结卡住了" % _text().text)

	# 冻结期间照样能推进到下一句。
	_ui().call("advance")
	await get_tree().process_frame
	_check(DialogUI.is_open, "冻结期间还能推进到下一句", "冻结期间推进不了，玩家被困在对话里")
	await _wait_typing("第二句。")
	_ui().call("advance")
	await get_tree().process_frame
	_check(not DialogUI.is_open and done.size() == 1,
		"冻结期间照样能读完并结算（回调恰好一次）",
		"读完却没收尾：is_open=%s 回调=%d 次" % [DialogUI.is_open, done.size()])

	# 冻结结束后一切照旧。
	PauseManager.set_frozen(&"sys_intro", false)
	await get_tree().process_frame
	var done2: Array[int] = []
	EventBus.dialog_sequence_requested.emit("村民", PackedStringArray(["冻结结束后照常显示。"]),
		func() -> void: done2.append(1))
	await get_tree().process_frame
	await _wait_typing("冻结结束后照常显示。")
	_check(DialogUI.is_open and _text().text == "冻结结束后照常显示。",
		"冻结结束后对话照常显示",
		"冻结结束后对话不显示：is_open=%s" % DialogUI.is_open)
	_finish_bar()
	await get_tree().process_frame
	_check(done2.size() == 1, "冻结结束后的对话也照常结算", "回调执行了 %d 次" % done2.size())
	_reset_overlays()


func _test_dialog_queued_then_shown_after_freeze() -> void:
	print("")
	print("--- C2. 阻塞教程冻结期间：对话排队，冻结结束后补位显示 ---")
	_reset_overlays()
	var steps: Array[TutorialStep] = [
		_step("系统级提示", true),
		_step("空档", false, &"", &"__never__"),
	]
	_arm_steps(steps, 0)
	TutorialSystem.call("_show_step", steps[0])
	await get_tree().process_frame
	_check(get_tree().paused, "教程阻塞步已冻结世界（前置条件）", "教程没有冻结")

	var done: Array[int] = []
	EventBus.dialog_sequence_requested.emit("村民", PackedStringArray(["教程关掉后该看到我。"]),
		func() -> void: done.append(1))
	await get_tree().process_frame
	_check(not _bar().visible and not DialogUI.is_open,
		"教程占着屏幕时，对话排队而不抢屏",
		"两个窗口同时弹出：popup=%s bar=%s" % [PopupManager.active_id(), _bar().visible])

	# 玩家关掉教程（真实入口）→ 排队的对话必须补位显示，而不是被丢掉。
	var tut: Node = UIRegistry.find_by_name("TutorialUI")
	if tut == null:
		_failed("TutorialUI 未挂载")
		return
	tut.call("dismiss_current")
	await get_tree().create_timer(0.2).timeout
	_check(DialogUI.is_open and _bar().visible,
		"冻结结束后排队的对话自动补位显示（“冻结之后能正常显示”）",
		"教程关了但对话没补位：is_open=%s bar=%s" % [DialogUI.is_open, _bar().visible])
	# 教程交还了令牌，但对话此刻接管屏幕：世界仍由对话冻结（窗口开着 = 世界停着）。
	_check(PauseManager.holds(&"dialog"),
		"补位的对话接管屏幕并持有自己的冻结令牌",
		"对话在屏却没人冻结世界：holders=%s" % str(PauseManager.get_holders()))
	await _wait_typing("教程关掉后该看到我。")
	_check(_text().text == "教程关掉后该看到我。", "补位显示的对话内容完整",
		"补位后文本不正确：「%s」" % _text().text)
	_finish_bar()
	await get_tree().process_frame
	_check(not get_tree().paused and PauseManager.holder_count() == 0,
		"对话读完关闭后世界恢复、令牌不残留",
		"对话关了世界还停着：holders=%s" % str(PauseManager.get_holders()))
	_check(done.size() == 1, "补位显示的对话结算回调照常执行（奖励不会丢）",
		"回调执行了 %d 次" % done.size())
	_reset_overlays()


func _test_windows_freeze_world() -> void:
	print("")
	print("--- C0. 窗口开着 = 世界冻结（不能移动 / 不会挨打）---")
	_reset_overlays()

	# 1) 对话条打开 → 世界冻结；关掉 → 恢复。
	EventBus.dialog_sequence_requested.emit("村民", PackedStringArray(["读对话的时候不该挨打。"]), Callable())
	await get_tree().process_frame
	_check(DialogUI.is_open and get_tree().paused,
		"NPC 对话窗口打开时世界冻结",
		"对话开着世界还在跑（玩家会被围殴）：paused=%s" % get_tree().paused)
	_finish_bar()
	await get_tree().process_frame
	_check(not get_tree().paused and PauseManager.holder_count() == 0,
		"对话关闭后世界立刻恢复",
		"对话关了世界还停着：holders=%s" % str(PauseManager.get_holders()))

	# 2) 教程系统级提示 → 世界冻结；关掉 → 恢复。
	var steps: Array[TutorialStep] = [
		_step("系统级提示", true),
		_step("空档", false, &"", &"__never__"),
	]
	_arm_steps(steps, 0)
	TutorialSystem.call("_show_step", steps[0])
	await get_tree().process_frame
	_check(get_tree().paused and PauseManager.holds(&"tutorial"),
		"教程窗口显示时世界冻结（窗口存在时不能移动 / 受伤）",
		"教程窗口开着世界却在跑：paused=%s" % get_tree().paused)
	TutorialSystem.dismiss_current_step()
	await get_tree().process_frame
	_check(not get_tree().paused and PauseManager.holder_count() == 0,
		"教程窗口关闭后世界恢复",
		"教程关了世界还停着：holders=%s" % str(PauseManager.get_holders()))
	_reset_overlays()


func _test_dialog_yields_to_screen_owner() -> void:
	print("")
	print("--- C3. 被“独占屏幕”的窗口盖住时，对话必须让位 ---")
	_reset_overlays()
	EventBus.dialog_sequence_requested.emit("村民",
		PackedStringArray(["会被暂停菜单盖住。", "下一句。"]), Callable())
	await get_tree().process_frame
	_check(DialogUI.is_open, "对话已打开（前置条件）", "对话没打开")

	# 暂停菜单/背包这类窗口：自带全屏遮罩，会把对话压在下面。
	PauseManager.set_frozen(&"pause_menu", true, PauseManager.Cover.SCREEN)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not DialogUI.is_open and not _bar().visible,
		"独占屏幕的窗口盖住时对话被收掉（否则“看不见也关不掉”）",
		"对话仍开着：is_open=%s（被遮罩压住后玩家既看不见也关不掉）" % DialogUI.is_open)
	PauseManager.clear_all()
	await get_tree().process_frame


func _test_notice_rules() -> void:
	print("")
	print("--- C4. 提示条：系统冻结期间能显示，被盖住时让位 ---")
	_reset_overlays()

	# 1) 系统级冻结期间：提示条照常显示。
	PauseManager.set_frozen(&"sys_intro", true, PauseManager.Cover.WORLD)
	EventBus.dialog_requested.emit("路牌：前方有危险。", 5.0)
	await get_tree().process_frame
	_check(_notice().visible and DialogUI.notice_open,
		"系统级冻结期间提示条照常显示",
		"冻结期间提示条不显示（NPC 的短回应会静默丢失）")
	PauseManager.set_frozen(&"sys_intro", false)
	await get_tree().process_frame

	# 2) 别的窗口占屏 → 提示条让位（顶部只有一条消息的位置）。
	var got_slot: bool = PopupManager.try_acquire(&"help")
	_check(got_slot, "让别的窗口占屏（前置条件）", "弹窗槽位被占，无法验证")
	await get_tree().process_frame
	_check(not _notice().visible,
		"别的窗口占屏时提示条让位（不和顶部面板叠在一起）",
		"提示条仍挂在顶部，会和教程/帮助面板重叠")
	PopupManager.release(&"help")
	await get_tree().process_frame

	# 3) 提示条让位**不能**波及对话条（"提示与对话可以同屏"是硬契约）。
	_reset_overlays()
	EventBus.dialog_sequence_requested.emit("村民", PackedStringArray(["对话不受影响。"]), Callable())
	await get_tree().process_frame
	EventBus.dialog_requested.emit("系统：你被通缉了。", 5.0)
	await get_tree().process_frame
	_check(DialogUI.notice_open and DialogUI.is_open, "提示与对话同时在屏（前置条件）",
		"notice=%s is_open=%s" % [DialogUI.notice_open, DialogUI.is_open])
	PopupManager.popup_opened.emit(&"help")
	await get_tree().process_frame
	_check(not DialogUI.notice_open, "提示条给别的窗口让位",
		"提示条没让位，会和顶部面板重叠")
	_check(DialogUI.is_open and _bar().visible,
		"让位只动提示条，对话条照常开着",
		"对话被顺带收掉了：is_open=%s" % DialogUI.is_open)
	_reset_overlays()


# ============================================================================
# 私有方法 —— 工具
# ============================================================================

## 造一个教程步骤（测试数据，不落盘）。
func _step(title: String, pause_game: bool,
		action: StringName = &"", level: StringName = &"") -> TutorialStep:
	var s: TutorialStep = TutorialStep.new()
	s.title = title
	s.text = "测试正文"
	s.pause_game = pause_game
	s.trigger_action = action
	s.level_id = level
	return s


## 把教程系统接到给定的步骤列表上（不走存档、不自动推进，测试完全自己驱动）。
func _arm_steps(steps: Array[TutorialStep], index: int) -> void:
	TutorialSystem.reset()
	TutorialSystem.set("_steps", steps)
	TutorialSystem.set("_enabled", false)
	TutorialSystem.set("_active", false)
	TutorialSystem.set("_index", index)
	TutorialSystem.set_process(false)
	PauseManager.clear_all()
	_reset_overlays()


## 让教程停手并收起面板（**不**写存档）。
## 【先 dismiss 再 poke】教程窗口是模态的，直接 poke 会把冻结令牌留在 PauseManager 里。
func _quiet_tutorial() -> void:
	TutorialSystem.dismiss_current_step()
	TutorialSystem.set("_enabled", false)
	TutorialSystem.set("_active", false)
	TutorialSystem.set("_index", -1)
	TutorialSystem.set_process(false)
	EventBus.tutorial_step_shown.emit(-1, "", "", false)
	PauseManager.clear_all()


## 把两条通道与弹窗槽位恢复到"什么都没有"的干净状态。
func _reset_overlays() -> void:
	var ui: DialogUI = _ui()
	if ui != null:
		ui.call("close")
	if PopupManager.active_id() != &"":
		PopupManager.release(PopupManager.active_id())
	PopupManager.clear_queue()


## 把当前对话推到底并收掉。
func _finish_bar() -> void:
	var ui: DialogUI = _ui()
	if ui == null:
		return
	var guard: int = 0
	while DialogUI.is_open and guard < 60:
		guard += 1
		ui.call("advance")
		await get_tree().process_frame
	ui.call("cancel_conversation")


## 等打字机把整句显示完（按**真实时间**兜底，不受 headless 高帧率影响）。
func _wait_typing(expected: String) -> void:
	var label: Label = _text()
	if label == null:
		return
	var deadline: int = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		if label.text == expected:
			return
		await get_tree().process_frame
	push_warning("[FreezeTest] 等打字机超时：期望「%s」，实际「%s」" % [expected, label.text])


func _ui() -> DialogUI:
	return UIRegistry.window_for(&"dialog") as DialogUI


func _bar() -> Control:
	var ui: DialogUI = _ui()
	return ui.get_node_or_null("Root/Bar") as Control if ui != null else null


func _notice() -> Control:
	var ui: DialogUI = _ui()
	return ui.get_node_or_null("Root/Notice") as Control if ui != null else null


func _text() -> Label:
	var ui: DialogUI = _ui()
	return ui.get_node_or_null("Root/Bar/VBox/Text") as Label if ui != null else null


func _check(ok: bool, msg: String, detail: String) -> void:
	if ok:
		_pass += 1
		print("  [PASS] " + msg)
	else:
		_failed(detail)
		print("  [FAIL] " + msg)


func _failed(detail: String) -> void:
	_fail += 1
	_fails.append(detail)
