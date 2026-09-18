## WeaponDialogTest —— 武器统一化 + 对话框 定点验证
##
## 【跑法】
##   Godot --headless --path . res://tools/weapon_dialog_test.tscn
##
## 【验什么】
##   A. 武器：6 把武器共用同一个场景；rotate_to_aim 由数据决定；换武器判定盒跟着变。
##   B. 对话框（重构后）：
##      B1 挂载与初始状态；
##      B2 NPC 对话弹出 + 打字机；
##      B3 鼠标点击推进 / 关闭（鼠标优先，不再只认 F）；
##      B4 键盘 F 仍可作为快捷键推进；
##      B5 **提示条不阻塞**（is_open 保持 false），也不打断正在进行的对话；
##      B6 对话期间玩家**没有**被锁住操作（"卡游戏进程"的直接回归）；
##      B7 玩家走开 → 对话自动结束，且**不**结算奖励；
##      B8 换场景 → 强制收尾，is_open 不会残留到下个关卡；
##      B9 提示条不会赖着不走（点击可关 / 到时自动消失）；
##      B10 对话中按 F 不重复触发脚下的可交互物。
extends Node

var _passed: int = 0
var _failed: Array[String] = []

func _pass(msg: String) -> void:
	_passed += 1
	print("  [PASS] ", msg)

func _fail(msg: String) -> void:
	_failed.append(msg)
	print("  [FAIL] ", msg)

func _check(cond: bool, ok_msg: String, fail_msg: String) -> void:
	if cond:
		_pass(ok_msg)
	else:
		_fail(fail_msg)

func _ready() -> void:
	print("")
	print("############ 武器统一化 + 对话框 验证 ############")
	# 开发档里通常已经"教程完成"，那样教程一步都不会播、也就验不到它的显示通道。
	# 这里显式让它跑起来（本测试不改存档，最后只是把 TutorialSystem 停掉）。
	GameState.tutorial_completed = false
	# 用**真实的 Boot** 启动：这样常驻 UI（含 DialogUI）走的就是游戏真实挂载路径，
	# 顺便验证 Boot.PERSISTENT_UI 里确实配了对话框。
	var boot: Node = load("res://scenes/core/boot.tscn").instantiate()
	boot.name = "Boot"
	boot.set("skip_menu", true)
	# root 此刻正忙于挂载本测试场景，必须延迟添加（否则 add_child 会失败）。
	get_tree().root.add_child.call_deferred(boot)
	# 常驻 UI 也是 call_deferred 挂载的，多等几帧确保全部进树。
	for i: int in 60:
		await get_tree().process_frame

	await _test_tutorial_single_channel()
	await _test_weapon_unified()
	await _test_dialog_popup()
	await _test_dialog_mouse()
	await _test_dialog_f_key()
	await _test_notice_nonblocking()
	await _test_player_not_locked()
	await _test_walk_away_cancels()
	await _test_scene_change_clears()
	await _test_notice_never_sticks()
	await _test_dialog_mutex()
	# 放在最后：它会触发 GameOverUI（会把游戏暂停），副作用最大。
	await _test_player_death_clears()

	_report()
	get_tree().quit(0)


# ============================================================================
# B0. 教程文字只显示一份（顺带验证"别再抢键盘"）
# ============================================================================

## 教程曾经同时往 TutorialUI 和对话框各发一份，同一句话在屏幕上出现两次
## （上下一对，既占画面又像弹了两个东西）。这里把它钉住。
func _test_tutorial_single_channel() -> void:
	print("")
	print("--- B0. 教程只走一条显示通道 ---")

	var ui: DialogUI = _get_dialog()
	var tut: Node = UIRegistry.find_by_name("TutorialUI")
	if ui == null or tut == null:
		_fail("TutorialUI / DialogUI 没挂上，无法验证")
		return

	var panel: Control = tut.get_node_or_null("Root/Panel") as Control
	var hint: Label = tut.get_node_or_null("Root/Panel/Margin/HBox/Hint") as Label
	if panel == null:
		_fail("教程面板节点缺失")
		return

	# 等关卡真的加载完（主菜单 → 城镇有淡入淡出）。
	# 必须用**物理帧**计时：headless 下 idle 帧率远高于 60，按 process_frame 数帧
	# 会把 0.2 秒的转场当成上百帧。
	for i: int in 300:
		if not SceneDirector.is_changing() and SceneDirector.get_current_level() != null:
			break
		await get_tree().physics_frame
	# 新档开场会立刻播第一步（等它出现，别拿时序赌）。
	for i: int in 300:
		if panel.visible:
			break
		await get_tree().physics_frame
	_check(panel.visible, "新档开场教程面板正常显示（教程没被改坏）",
		"教程面板一直没出现")

	if hint != null:
		_check(not hint.visible,
			"自动消失的教程步骤不显示按键提示（不会骗玩家按键盘）",
			"教程显示了「按 F 继续」，但这步是自动消失的")

	_check(not DialogUI.notice_open and not DialogUI.is_open,
		"同一句教程文字没有在对话框里再显示一份（占画面回归）",
		"教程文字被重复显示了两份：notice=%s bar=%s" % [DialogUI.notice_open, DialogUI.is_open])

	# 收掉教程，避免它影响后面的用例。
	_quiet_tutorial()
	await get_tree().process_frame


# ============================================================================
# A. 武器统一化
# ============================================================================

func _test_weapon_unified() -> void:
	print("")
	print("--- A. 武器统一化 ---")

	var weapons: Array = DataRegistry.get_all_weapons()
	_check(weapons.size() >= 6, "武器数据已加载（%d 把）" % weapons.size(),
		"武器数据不足：只有 %d 把" % weapons.size())

	# 1) 没有任何武器再绑私有场景。
	var scattered: Array[String] = []
	for res: Resource in weapons:
		var w: WeaponData = res as WeaponData
		if w != null and w.weapon_scene != null:
			scattered.append(w.display_name)
	_check(scattered.is_empty(), "所有武器共用通用场景（无私有 .tscn）",
		"这些武器仍绑私有场景：%s" % ", ".join(scattered))

	# 2) 旧场景文件已不存在。
	var leftovers: Array[String] = []
	for old: String in ["sword", "big_sword", "katana", "hammer", "bow", "wand"]:
		if ResourceLoader.exists("res://scenes/weapons/%s.tscn" % old):
			leftovers.append(old)
	_check(leftovers.is_empty(), "6 个旧武器场景已删除",
		"旧场景仍在：%s" % ", ".join(leftovers))

	# 3) 每把武器都能由统一入口实例化，且贴图来自数据。
	var built: int = 0
	var no_tex: Array[String] = []
	for res: Resource in weapons:
		var w: WeaponData = res as WeaponData
		if w == null:
			continue
		var inst: WeaponController = WeaponController.create(w, null)
		if inst == null:
			no_tex.append(w.display_name)
			continue
		built += 1
		var spr: Sprite2D = inst.get_sprite()
		if spr != null and spr.texture != w.held_texture:
			no_tex.append(w.display_name + "(贴图不符)")
		inst.free()
	_check(no_tex.is_empty() and built == weapons.size(),
		"%d 把武器全部由统一入口实例化成功且贴图正确" % built,
		"实例化异常：%s" % ", ".join(no_tex))

	# 4) rotate_to_aim 由数据决定：近战 true，远程 false。
	var melee_wrong: Array[String] = []
	var ranged_wrong: Array[String] = []
	for res: Resource in weapons:
		var w: WeaponData = res as WeaponData
		if w == null:
			continue
		var inst: WeaponController = WeaponController.create(w, null)
		if inst == null:
			continue
		var got: bool = inst.rotate_to_aim
		inst.free()
		if w.kind == GameEnums.WeaponKind.RANGED:
			if got:
				ranged_wrong.append(w.display_name)
		else:
			if not got:
				melee_wrong.append(w.display_name)
	_check(ranged_wrong.is_empty(), "远程武器不跟随瞄准旋转（弓/杖不会跟着鼠标转圈）",
		"这些远程武器仍在跟随瞄准：%s" % ", ".join(ranged_wrong))
	_check(melee_wrong.is_empty(), "近战武器跟随瞄准旋转",
		"这些近战武器没有跟随瞄准：%s" % ", ".join(melee_wrong))

	# 5) 换武器：判定盒尺寸随 WeaponData 变化（远程小盒 / 近战大盒）。
	var bow: WeaponData = DataRegistry.get_weapon(&"bow")
	var sword: WeaponData = DataRegistry.get_weapon(&"sword")
	if bow != null and sword != null:
		var bi: WeaponController = WeaponController.create(bow, null)
		var si: WeaponController = WeaponController.create(sword, null)
		if bi != null and si != null:
			var bs: Vector2 = _hitbox_size(bi)
			var ss: Vector2 = _hitbox_size(si)
			bi.free()
			si.free()
			print("    弓判定盒 %s（数据配 %s） / 剑判定盒 %s" % [bs, bow.hitbox_size, ss])
			_check(bs.x < ss.x, "远程判定盒比近战小（%.0f < %.0f）——差异由数据驱动" % [bs.x, ss.x],
				"远程判定盒 %.0f 没有比近战 %.0f 小，数据没生效" % [bs.x, ss.x])
		else:
			_fail("无法实例化弓/剑用于对比")

	# 6) 旋转半径由 WeaponData.orbit_radius 驱动：贴图沿 +X 推出这个半径
	#    （半径 0 = 武器贴在身上），判定盒不受影响 —— 观感与攻击距离解耦。
	var radius_wrong: Array[String] = []
	for res: Resource in weapons:
		var w: WeaponData = res as WeaponData
		if w == null:
			continue
		var inst: WeaponController = WeaponController.create(w, null)
		if inst == null:
			continue
		var pivot: Node2D = inst.get_node_or_null("SwingPivot") as Node2D
		var spr: Sprite2D = inst.get_sprite()
		var box: AttackBox = inst.get_attack_box()
		# 未旋转时（rotation = 0），贴图应落在半径 + 手持偏移处。
		var grip_x: float = spr.global_position.x if spr != null else -999.0
		var hit_x: float = box.global_position.x if box != null else -999.0
		var grip_ok: bool = is_equal_approx(grip_x, w.orbit_radius + w.held_offset.x)
		var pivot_ok: bool = pivot != null and is_equal_approx(pivot.position.x, 0.0)
		var reach_ok: bool = is_equal_approx(hit_x, w.hitbox_offset.x)
		print("    %s：半径 %.0f → 贴图距身体 %.0f，判定盒 %.0f（不含半径）" % [w.display_name, w.orbit_radius, grip_x, hit_x])
		inst.free()
		if not (grip_ok and pivot_ok and reach_ok):
			radius_wrong.append(w.display_name)
	_check(radius_wrong.is_empty(),
		"旋转半径由数据驱动（贴图推到 orbit_radius 外，攻击距离不受影响）",
		"这些武器的旋转半径没生效：%s" % ", ".join(radius_wrong))


func _hitbox_size(w: WeaponController) -> Vector2:
	var box: AttackBox = w.get_attack_box()
	if box == null:
		return Vector2.ZERO
	var shape: CollisionShape2D = box.get_node_or_null("Shape") as CollisionShape2D
	if shape == null:
		return Vector2.ZERO
	var rect: RectangleShape2D = shape.shape as RectangleShape2D
	return rect.size if rect != null else Vector2.ZERO


# ============================================================================
# B. 对话框（重构后：提示条 + 对话条两条通道）
# ============================================================================

func _get_dialog() -> DialogUI:
	return UIRegistry.find_by_name("DialogUI") as DialogUI


func _bar(ui: DialogUI) -> Control:
	return ui.get_node_or_null("Root/Bar") as Control


func _notice(ui: DialogUI) -> Control:
	return ui.get_node_or_null("Root/Notice") as Control


func _bar_text(ui: DialogUI) -> Label:
	return ui.get_node_or_null("Root/Bar/VBox/Text") as Label


## 对话条上的「继续 / 关闭」按钮。
## 统一契约下"推进"由这个按钮负责（点条上别处是关闭），所以测试要用它。
func _bar_action(ui: DialogUI) -> Button:
	return ui.get_node_or_null("Root/Bar/VBox/Header/Action") as Button


## 模拟鼠标左键点击某个 Control 的正中央。
## 走 Control.gui_input 信号派发：与引擎把点击送到面板上的路径一致
## （面板自身 mouse_filter 必须是 STOP 才会收到），且不受画面拉伸影响。
func _click(control: Control) -> void:
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = control.get_global_rect().get_center()
	control.gui_input.emit(ev)


## 模拟一次真实的**按钮**被按下（会走按钮自己的 pressed 逻辑）。
##
## 【为什么不能对按钮用 _click】
##   _click 是直接 emit Control 的 gui_input 信号，那只是"通知观察者"；
##   Button 的 pressed 是引擎在内部处理按下流程时才发出的，
##   手动 emit gui_input 并不会让 BaseButton 走它的按下逻辑，也就不会触发 pressed。
##   真实点击路径是：引擎 → BaseButton 内部处理 → emit pressed → 且 accept_event()
##   （所以事件不会继续冒泡到父面板，按钮和"点面板关闭"天然不冲突）。
func _press_button(btn: Button) -> void:
	btn.pressed.emit()


func _test_dialog_popup() -> void:
	print("")
	print("--- B1/B2. 挂载、初始状态、NPC 对话弹出 ---")

	var ui: DialogUI = _get_dialog()
	if ui == null:
		_fail("DialogUI 未挂载（Boot.PERSISTENT_UI 里缺它）")
		return
	_pass("DialogUI 已由 Boot 常驻挂载")

	var bar: Control = _bar(ui)
	var notice: Control = _notice(ui)
	if bar == null or notice == null:
		_fail("对话条 / 提示条面板节点缺失（Root/Bar 或 Root/Notice）")
		return

	# 教程现在只走 TutorialUI，不再往对话框塞东西；但仍先清一次场。
	ui.close()
	await get_tree().process_frame
	_check(not bar.visible and not notice.visible and not DialogUI.is_open,
		"初始状态两条通道都是隐藏的，is_open = false",
		"初始状态异常：bar=%s notice=%s is_open=%s" % [bar.visible, notice.visible, DialogUI.is_open])

	# 模拟 NPC 发起一段多句对话。
	var lines: PackedStringArray = PackedStringArray(["第一句。", "第二句。", "第三句。"])
	var finished: Array[int] = []
	EventBus.dialog_sequence_requested.emit("铁匠", lines, func() -> void: finished.append(1))
	await get_tree().process_frame

	_check(bar.visible, "NPC 对话触发后对话条**真的弹出来了**",
		"NPC 对话触发后对话条仍然不可见（这就是玩家报的 bug）")
	_check(DialogUI.is_open, "DialogUI.is_open 已置为 true",
		"is_open 仍为 false，互斥逻辑会失效")
	_check(not notice.visible, "对话不会误开顶部的提示条", "对话把提示条也打开了")

	var speaker: Label = ui.get_node_or_null("Root/Bar/VBox/Header/Speaker") as Label
	if speaker != null:
		_check(speaker.text == "铁匠", "说话人名字显示为「铁匠」",
			"说话人显示错误：%s" % speaker.text)

	# 打字机跑完后应显示第一句全文。
	for i: int in 120:
		await get_tree().process_frame
	var text: Label = _bar_text(ui)
	if text != null:
		_check(text.text == "第一句。", "第一句已完整显示（%s）" % text.text,
			"第一句内容不对：%s" % text.text)


## 鼠标优先：点条内任意处 = 推进 / 关闭。
func _test_dialog_mouse() -> void:
	print("")
	print("--- B3. 鼠标点击推进 / 关闭 ---")

	var ui: DialogUI = _get_dialog()
	if ui == null:
		return
	var bar: Control = _bar(ui)
	var text: Label = _bar_text(ui)
	if bar == null or text == null:
		_fail("对话条节点缺失，无法验证鼠标点击")
		return

	# 结构前提：面板必须自己吃掉鼠标事件，否则点击会穿到游戏里、永远点不到。
	_check(bar.mouse_filter == Control.MOUSE_FILTER_STOP,
		"对话条 mouse_filter = STOP（鼠标能落到面板上，不会穿透）",
		"对话条 mouse_filter = %d，鼠标点击会穿过去" % bar.mouse_filter)
	_check(bar.gui_input.get_connections().size() > 0,
		"对话条已接上 gui_input（点击有处理者）", "对话条没有接 gui_input，点了没反应")

	var lines: PackedStringArray = PackedStringArray(["甲甲", "乙乙", "丙丙"])
	var done: Array[int] = []
	EventBus.dialog_sequence_requested.emit("村民", lines, func() -> void: done.append(1))
	await get_tree().process_frame

	var action: Button = _bar_action(ui)
	if action == null:
		_fail("对话条缺少「继续/关闭」按钮（推进交互按钮）")
		return

	# 统一契约下"推进"由**按钮**负责（点条上别处 = 关闭），所以这里点按钮。
	var seen: Array[String] = []
	for i: int in lines.size():
		await _wait_typing_done(text, lines[i])
		seen.append(text.text)
		if i < lines.size() - 1:
			_press_button(action)
			await get_tree().process_frame

	_check(seen.size() == 3 and seen[0] == "甲甲" and seen[1] == "乙乙" and seen[2] == "丙丙",
		"点「继续」按钮逐句推进：%s → %s → %s" % [seen[0], seen[1], seen[2]],
		"点按钮没推进对话：%s" % str(seen))

	# 已是最后一句，点条上**任意处** → 关闭（统一契约：左键点窗口内即关）。
	# 读完最后一句才关 = 听完了，按"完成"处理，回调必须结算奖励。
	_click(bar)
	await get_tree().process_frame
	_check(not DialogUI.is_open and not bar.visible,
		"最后一句点条上任意处即关闭（统一契约）", "点条上任意处没能关闭对话条")
	_check(done.size() == 1, "关闭时回调已执行（奖励会结算）",
		"关闭时没有回调，NPC 奖励永远不会发放")

	# 中途点条上任意处 → 也应当能关掉（这是"关不掉"问题的核心回归点），
	# 且属于"没听完"，按取消处理：不结算、NPC 的 once 不被消耗。
	var done2: Array[int] = []
	EventBus.dialog_sequence_requested.emit("村民",
		PackedStringArray(["一", "二", "三"]), func() -> void: done2.append(1))
	await get_tree().process_frame
	await _wait_typing_done(text, "一")
	_click(bar)
	await get_tree().process_frame
	_check(not DialogUI.is_open and not bar.visible,
		"中途点条上任意处也能关闭", "中途点条上任意处关不掉")
	_check(done2.is_empty(), "中途关闭按取消处理（不发奖励，可重听）",
		"中途关闭却结算了奖励，一次性奖励会被半句话吃掉")


func _test_dialog_f_key() -> void:
	print("")
	print("--- B4. 键盘 F 仍可推进（快捷键，不再是唯一途径）---")

	var ui: DialogUI = _get_dialog()
	if ui == null:
		return
	var text: Label = _bar_text(ui)
	if text == null:
		_fail("文本节点缺失")
		return

	var lines: PackedStringArray = PackedStringArray(["甲", "乙"])
	var done: Array[int] = []
	EventBus.dialog_sequence_requested.emit("村民", lines, func() -> void: done.append(1))
	await get_tree().process_frame

	await _wait_typing_done(text, "甲")
	_check(text.text == "甲", "第 1 句显示「甲」（实际 %s）" % text.text, "第 1 句不对：%s" % text.text)
	_press_f()
	await get_tree().process_frame
	await _wait_typing_done(text, "乙")
	_check(text.text == "乙", "按 F 推进到「乙」（实际 %s）" % text.text, "按 F 没推进：%s" % text.text)
	_press_f()
	await get_tree().process_frame
	_check(not DialogUI.is_open, "最后一句按 F 关闭了对话", "按 F 没能关闭对话")
	_check(done.size() == 1, "关闭时回调已执行", "关闭时没有回调")


## 提示条是**非阻塞**通道：不发 dialog_opened、不打断正在进行的对话。
func _test_notice_nonblocking() -> void:
	print("")
	print("--- B5. 提示条非阻塞、且不打断对话 ---")

	var ui: DialogUI = _get_dialog()
	if ui == null:
		return
	var notice: Control = _notice(ui)
	var bar: Control = _bar(ui)
	if notice == null or bar == null:
		return

	# 1) 单独一条提示：显示出来，但 is_open 必须仍是 false（不阻塞任何输入）。
	EventBus.dialog_requested.emit("路牌：前面有危险。", 5.0)
	await get_tree().process_frame
	_check(notice.visible, "提示条已显示", "提示条没显示")
	_check(not DialogUI.is_open,
		"提示条不设 is_open —— 玩家操控与交互完全不受影响",
		"提示条把 is_open 置成了 true，又会开始锁玩家")
	ui.dismiss_notice()
	await get_tree().process_frame

	# 2) 对话进行中再收到提示：两句都该在，且对话的回调不能被顶掉。
	#    （旧实现是单队列，提示会把对话整个顶掉并丢掉它的奖励回调。）
	var done: Array[int] = []
	EventBus.dialog_sequence_requested.emit("铁匠", PackedStringArray(["甲", "乙"]), func() -> void: done.append(1))
	await get_tree().process_frame
	EventBus.dialog_requested.emit("系统：你被通缉了。", 5.0)
	await get_tree().process_frame
	_check(notice.visible and bar.visible and DialogUI.is_open,
		"提示与对话可以同时在屏（两条通道互不干扰）",
		"提示把对话顶掉了：notice=%s bar=%s is_open=%s" % [notice.visible, bar.visible, DialogUI.is_open])

	# 把对话推到底，回调必须仍然有效。
	var guard: int = 0
	while DialogUI.is_open and guard < 20:
		ui.advance()
		await get_tree().process_frame
		guard += 1
	_check(done.size() == 1,
		"被打断过一次的对话关闭时回调仍然执行（奖励不丢）",
		"对话的 on_finished 被提示顶掉了（触发 %d 次）" % done.size())
	ui.dismiss_notice()


## "窗口开着 = 世界停着"：对话期间世界冻结（不能移动 / 不会挨打），关掉即恢复。
##
## 【契约为什么变了】旧契约是"对话不锁玩家"——那是修"对话直接改输入、
##   一旦没关掉就永久卡死"时的权宜之计。现在冻结走 PauseManager 令牌
##   （唯一所有者 + 多条强制收尾 + 死持有者回收），玩家读对话时不会被围殴，
##   对话也不会因为走动被"走远即取消"瞬间收掉；关掉窗口立刻恢复运行，
##   玩家永远拿得回控制权（这条才是当年那个 bug 要保的性质）。
func _test_player_not_locked() -> void:
	print("")
	print("--- B6. 对话期间世界冻结，关闭即恢复 ---")

	var ui: DialogUI = _get_dialog()
	var player: Player = get_tree().get_first_node_in_group(&"player") as Player
	if ui == null or player == null:
		_fail("找不到玩家，无法验证")
		return

	EventBus.dialog_sequence_requested.emit("村民", PackedStringArray(["说点长的东西好让对话开着"]), Callable())
	await get_tree().process_frame
	_check(DialogUI.is_open, "对话已打开（前置条件）", "对话没打开，无法验证")

	# 世界必须真的停了：玩家节点不再处理（不能移动 / 不会挨打）。
	_check(get_tree().paused and PauseManager.holds(&"dialog"),
		"对话窗口开着时世界冻结（令牌在对话框名下）",
		"对话开着世界却还在跑：paused=%s holders=%s" % [
			get_tree().paused, str(PauseManager.get_holders())])
	_check(not player.can_process(),
		"对话期间玩家节点被冻结（不能移动 / 不会挨打）",
		"对话开着玩家还能处理（can_process=true），窗口没有冻结世界")

	# 关掉对话 → 控制权立刻回来（这才是当年"卡游戏进程"要保的性质）。
	ui.cancel_conversation()
	await get_tree().process_frame
	_check(not get_tree().paused and not PauseManager.holds(&"dialog"),
		"关闭对话后世界立刻恢复（玩家永远拿得回控制权）",
		"对话关了世界还停着：holders=%s" % str(PauseManager.get_holders()))

	# 顺手确认"能攻击"这条也不受对话影响：Player 不再引用 DialogUI 做门闸。
	# 只看真正的代码行（跳过注释——注释里正解释着"旧实现为什么这么写"）。
	var gated: Array[String] = []
	for line: String in FileAccess.get_file_as_string("res://scripts/player/player.gd").split("\n"):
		var code: String = line.strip_edges()
		if code.begins_with("#"):
			continue
		if code.contains("DialogUI.is_open"):
			gated.append(code)
	_check(gated.is_empty(),
		"Player 脚本里已彻底没有 DialogUI.is_open 门闸",
		"player.gd 里仍有 DialogUI.is_open 门闸：%s" % "; ".join(gated))

	await get_tree().process_frame


## 兜底收尾：玩家离开对话发起位置 → 对话自动结束（不结算）。
##
## 【现在为什么只是"兜底"】对话窗口打开时世界已冻结，玩家走不动，
## 正常流程轮不到这条路；它留在原地是为了"冻结万一没生效 / 玩家被击退"时
## 依然能脱身——控制权必须永远拿得回来。
func _test_walk_away_cancels() -> void:
	print("")
	print("--- B7. 玩家离开对话位置 → 对话自动结束（不结算，兜底路径）---")

	var ui: DialogUI = _get_dialog()
	var player: Player = get_tree().get_first_node_in_group(&"player") as Player
	if ui == null or player == null:
		return
	var home: Vector2 = player.global_position

	var done: Array[int] = []
	EventBus.dialog_sequence_requested.emit("村民", PackedStringArray(["甲", "乙"]), func() -> void: done.append(1))
	await get_tree().process_frame
	_check(DialogUI.is_open, "对话已打开（前置条件）", "对话没打开，无法验证走开")

	# 走出 cancel_distance（默认 26px）之外。
	player.global_position = home + Vector2(0, 80)
	for i: int in 4:
		await get_tree().process_frame
	_check(not DialogUI.is_open,
		"走出 %d px 后对话自动结束（玩家可以直接走开脱身）" % int(ui.cancel_distance),
		"玩家走远了对话还开着，等于把玩家按在原地")

	# 走开属于"取消"：奖励不结算，once 也不会被半句话吃掉。
	_check(done.is_empty(),
		"走开结束不结算奖励（该对话可以再谈一次）",
		"走开也结算了奖励，一次性奖励会被半句话骗走")

	player.global_position = home
	for i: int in 4:
		await get_tree().process_frame


## 换场景必须清干净，否则对话框会跨关卡残留、把新关卡的玩家锁死。
func _test_scene_change_clears() -> void:
	print("")
	print("--- B8. 换场景 → 强制收尾 ---")

	var ui: DialogUI = _get_dialog()
	if ui == null:
		return

	# 本用例会发真实的 scene_changed，先让 TutorialSystem 停手，
	# 免得测试顺手把「教程已完成」写进存档（测试不该动玩家的档）。
	TutorialSystem.set("_enabled", false)
	TutorialSystem.set_process(false)

	EventBus.dialog_sequence_requested.emit("村民", PackedStringArray(["甲", "乙"]), Callable())
	EventBus.dialog_requested.emit("常驻提示", 0.0)
	await get_tree().process_frame
	_check(DialogUI.is_open, "对话已打开（前置条件）", "对话没打开，无法验证收尾")

	EventBus.scene_changed.emit(null)
	await get_tree().process_frame
	_check(not DialogUI.is_open and not DialogUI.notice_open,
		"换场景后对话与提示都被收掉，is_open 不残留",
		"换场景后仍然 is_open=%s（新关卡的玩家会被锁住）" % DialogUI.is_open)


## 玩家死亡同样要收掉（GameOverUI 会在此时把游戏暂停）。
func _test_player_death_clears() -> void:
	print("")
	print("--- B8b. 玩家死亡 → 强制收尾 ---")

	var ui: DialogUI = _get_dialog()
	if ui == null:
		return

	EventBus.dialog_sequence_requested.emit("村民", PackedStringArray(["甲"]), Callable())
	await get_tree().process_frame
	EventBus.player_died.emit()
	await get_tree().process_frame
	_check(not DialogUI.is_open, "玩家死亡后对话被收掉", "玩家死亡后对话还开着")

	# 收拾 GameOverUI 的副作用（它会 get_tree().paused = true），
	# 否则本测试的收尾跑在暂停里。
	get_tree().paused = false
	var over: Node = UIRegistry.find_by_name("GameOverUI")
	if over != null:
		(over as CanvasLayer).visible = false


## 提示条不能"赖着死不掉"：点击能关，到点能自动消失。
func _test_notice_never_sticks() -> void:
	print("")
	print("--- B9. 提示条不会赖着不走 ---")

	var ui: DialogUI = _get_dialog()
	if ui == null:
		return
	var notice: Control = _notice(ui)
	if notice == null:
		return

	# 1) duration = 0（路牌"常驻"）也能靠点击收掉。
	EventBus.dialog_requested.emit("常驻提示，点我关掉", 0.0)
	await get_tree().process_frame
	_check(notice.visible, "常驻提示已显示", "常驻提示没显示")
	_click(notice)
	await get_tree().process_frame
	_check(not notice.visible, "点击提示条即可收起（常驻提示也关得掉）",
		"点击提示条关不掉，这就是玩家说的'赖着死不掉'")

	# 2) 有限时长会自己消失。
	EventBus.dialog_requested.emit("马上就走", 0.15)
	await get_tree().process_frame
	_check(notice.visible, "定时提示已显示", "定时提示没显示")
	for i: int in 40:
		await get_tree().process_frame
	_check(not notice.visible, "到时间后提示条自动消失", "定时提示到点还挂在屏幕上")

	# 3) 硬上限兜底：即使 duration 配成 0，也不会超过 notice_max_lifetime。
	_check(ui.notice_max_lifetime > 0.0,
		"提示条有硬上限（%.0fs）——结构上不可能永久常驻" % ui.notice_max_lifetime,
		"提示条没有硬上限，duration=0 时永远关不掉")


func _test_dialog_mutex() -> void:
	print("")
	print("--- B10. 对话中按 F 不重复触发交互 ---")

	var ui: DialogUI = _get_dialog()
	if ui == null:
		return

	# 造一个可交互物，统计它被触发的次数。
	var probe: Interactable = Interactable.new()
	probe.name = "MutexProbe"
	probe.requires_input = true
	get_tree().root.add_child(probe)
	await get_tree().process_frame

	var hits: Array[int] = []
	probe.interacted.connect(func(_a: Node) -> void: hits.append(1))
	# 假装玩家站在范围内。_player_in_range 是 Node2D 类型，必须传 Node2D，
	# 传 Viewport 之类的会因为类型不匹配而赋值失败（表现为"怎么按都没反应"）。
	var fake_player: Node2D = Node2D.new()
	fake_player.name = "FakePlayer"
	add_child(fake_player)
	probe.set("_player_in_range", fake_player)

	# 先弹一段对话。
	EventBus.dialog_sequence_requested.emit("测试", PackedStringArray(["一", "二"]), Callable())
	await get_tree().process_frame
	_check(DialogUI.is_open, "对话已打开（前置条件）", "对话没打开，无法验证互斥")

	# 对话开着时按 F：应该只推进对话，不触发交互物。
	var before: int = hits.size()
	_press_f()
	await get_tree().process_frame
	_press_f()
	await get_tree().process_frame
	_check(hits.size() == before,
		"对话中按 F 没有误触发脚下的可交互物（触发次数 %d）" % hits.size(),
		"对话中按 F 把交互物也触发了 %d 次（一次按 F 干了两件事）" % (hits.size() - before))

	# 关掉对话后再按 F：交互物应该恢复响应。（限次，避免异常时死循环拖死测试）
	for guard: int in 20:
		if not DialogUI.is_open:
			break
		_press_f()
		await get_tree().process_frame
	_press_f()
	await get_tree().process_frame
	_check(hits.size() > before, "对话关闭后 F 恢复触发交互（%d 次）" % hits.size(),
		"对话关闭后 F 仍然触发不了交互")

	probe.queue_free()


# ============================================================================
# 工具
# ============================================================================

## 让教程停手并收起面板（**不**写存档）。
##
## 【为什么必须先 dismiss 再 poke】教程窗口现在是模态的——开着就持有冻结令牌。
## 只 set("_active", false) 会把令牌留在 PauseManager 里，后面所有用例
## 都跑在冻结里（B10 的"关掉对话后 F 触发不了交互"就是这样假失败的）。
func _quiet_tutorial() -> void:
	TutorialSystem.dismiss_current_step()
	TutorialSystem.set("_enabled", false)
	TutorialSystem.set("_active", false)
	TutorialSystem.set("_index", -1)
	TutorialSystem.set_process(false)
	EventBus.tutorial_step_shown.emit(-1, "", "", false)
	# 测试兜底：不管前面发生过什么，用例之间世界必须是运行的。
	PauseManager.clear_all()


## 模拟按下 F（interact 动作）。
func _press_f() -> void:
	var ev: InputEventAction = InputEventAction.new()
	ev.action = &"interact"
	ev.pressed = true
	Input.parse_input_event(ev)


## 等打字机把当前句跑完（文本不再变化即视为完成）。
## 等打字机把这一句打完。
##
## 【为什么必须传 expected】
##   旧实现是"文本连续 3 帧不变就算打完"。但打字机推进在 `_process` 里，
##   只要那几帧 `_process` 没跑到（例如被暂停分支提前 return），文本就会
##   停在中途不动 → 判定"打完了"，于是采到 "乙" 而不是 "乙乙"，
##   后面整段推进/关闭/回调断言全部错位（表现为随机 3 项失败）。
##   直接等"文本 == 预期整句"是确定性收敛，帧率再高也不会误判。
func _wait_typing_done(text: Label, expected: String = "") -> void:
	if expected != "":
		for _i: int in 240:
			if text.text == expected:
				return
			await get_tree().process_frame
		push_warning("[测试] 等打字机超时：期望「%s」，实际「%s」" % [expected, text.text])
		return
	var last: String = text.text
	var stable: int = 0
	for _i: int in 90:
		await get_tree().process_frame
		if text.text == last and text.text != "":
			stable += 1
			if stable >= 3:
				return
		else:
			stable = 0
			last = text.text


func _report() -> void:
	print("")
	print("############################################")
	print("武器统一化 + 对话框验证：%d 通过，%d 失败" % [_passed, _failed.size()])
	if not _failed.is_empty():
		print("")
		print("## 失败清单")
		var i: int = 1
		for f: String in _failed:
			print("  %d. %s" % [i, f])
			i += 1
	print("############################################")
