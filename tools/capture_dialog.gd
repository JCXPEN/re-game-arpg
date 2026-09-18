## CaptureDialog —— 截图取证：对话框（提示条 / 对话条两条通道）+ 结构化对话
##
## 【跑法】（**窗口模式**，不是 headless —— 截图需要真实渲染）
##   Godot --path . --audio-driver Dummy res://tools/capture_dialog.tscn
##   窗口尺寸由 project.godot 固定为 1280x720，画布 320x180，整数 4 倍拉伸。
##
## 【验什么】（对着"对话框改造"逐条取证，产物给 PIL 数化复核）
##   1. 走到 NPC 旁边按 F → 底部**对话条**（不再是占满屏幕的黑板）。
##   2. 点「继续 / 关闭」**按钮**（真实鼠标）= 推进；按钮与"点条内关闭"不打架。
##   3. 点对话条**空白处**（真实鼠标）= **关闭**（全项目统一契约）。
##   4. 对话条**宽度随文本自适应**：短句收窄、长句换行加宽，都不出画布。
##   5. 单句提示走**顶部提示条**，小、窄；与对话条同屏共存、互不顶掉。
##   6. **结构化对话**：逐句文本样式（低语 / 呼喊 / 系统）与立绘 / 小头像真的渲染出来。
##
## 【为什么点击用 Input.parse_input_event 而不是直接 emit gui_input】
##   本工具是**窗口模式**，画布拉伸（320→1280）真实生效，parse_input_event
##   走的是引擎完整的"窗口 → 视口 → GUI 命中"链路，能证伪 mouse_filter 配错。
##   headless 下拉伸不生效、坐标会落空，所以本工具**必须**在窗口模式跑
##   （headless 的点击语义由 tools/dialogue_system_test.gd 负责，那里用 gui_input）。
##
## 【产物】
##   res://Godot/app_userdata/ActRPG/screenshots_dialog/
extends Node

const OUT_DIR: String = "res://Godot/app_userdata/ActRPG/screenshots_dialog"
## 项目基准分辨率；鼠标点击的窗口坐标要按这个比例换算。
const CANVAS: Vector2 = Vector2(320, 180)

## 自适应排版取证用的两句：一短一长。
const DEMO_SHORT: String = "你终于醒了。"
const DEMO_LONG: String = "你终于醒了，勇者。这片土地已经被诅咒了整整三年，村里的井水都干了，愿意听我把话说完吗？"

var _ui: DialogUI
var _bar: Control
var _action: Button
var _mismatch: int = 0


func _ready() -> void:
	var boot: Node = load("res://scenes/core/boot.tscn").instantiate()
	boot.name = "Boot"
	boot.set("skip_menu", true)
	get_tree().root.add_child.call_deferred(boot)
	for i: int in 60:
		await get_tree().process_frame
	await _run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_quiet_tutorial()
	await get_tree().process_frame

	var npc: NPC = _find_npc()
	if npc == null:
		print("[CaptureDialog] 找不到 NPC")
		get_tree().quit(1)
		return
	print("[CaptureDialog] 找到 NPC：%s @ %s，legacy lines=%d，结构化 dialogue=%s"
		% [npc.npc_name, npc.global_position, npc.lines.size(),
			"有" if npc.get("dialogue") != null else "无"])

	var player: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
	if player == null:
		print("[CaptureDialog] 找不到玩家")
		get_tree().quit(1)
		return

	_ui = get_tree().root.get_node_or_null("DialogUI") as DialogUI
	if _ui == null:
		print("[CaptureDialog] 找不到 DialogUI")
		get_tree().quit(1)
		return
	_bar = _ui.get_node_or_null("Root/Bar") as Control
	_action = _ui.get_node_or_null("Root/Bar/VBox/Header/Action") as Button
	print("[CaptureDialog] 鼠标命中链路：Bar.mouse_filter=%d，Speaker.mouse_filter=%d，"
		% [_mf(_bar), _mf(_ui.get_node_or_null("Root/Bar/VBox/Header/Speaker"))]
		+ "Text.mouse_filter=%d" % _mf(_ui.get_node_or_null("Root/Bar/VBox/Text")))

	# 走到 NPC 跟前。NPC 的交互框只有 24x24（覆盖 ±12px），偏移必须小于 12。
	player.global_position = npc.global_position + Vector2(0, 8)
	for i: int in 20:
		await get_tree().physics_frame
	await get_tree().process_frame
	await _shot("00_approach")

	await _demo_npc_talk()
	await _demo_adapt()
	await _demo_notice()
	await _demo_structured()

	print("[CaptureDialog] 截图完成：%s（状态不符 %d 处）" % [OUT_DIR, _mismatch])
	get_tree().quit(0 if _mismatch == 0 else 1)


# ============================================================================
# 取证 1~3：真实 NPC 对话 —— 按钮推进 / 点条关闭
# ============================================================================

func _demo_npc_talk() -> void:
	# 按 F 说话 → 打字机跑完第一句。
	_press_f()
	await _wait_typing()
	await _shot("10_bar_line1")
	print("[CaptureDialog] 第 1 句 = 「%s」 对话条 %s" % [_bar_text(), _rect_str(_bar)])

	# 点「继续」按钮（真实鼠标）→ 下一句。按钮自己 accept_event，不会被"点条关闭"抢走。
	_expect(DialogUI.is_open, "按 F 后对话条已打开")
	var before: String = _bar_text()
	_click_control(_action)
	await _wait_typing()
	await _shot("11_bar_line2_button")
	_expect(_bar_text() != before or not DialogUI.is_open,
		"点「继续」按钮真的推进了（或刚好结束）")
	print("[CaptureDialog] 点按钮后 = 「%s」 按钮文案=「%s」 对话条 %s"
		% [_bar_text(), _action.text, _rect_str(_bar)])

	# 再点一次按钮（若还没结束）→ 第 3 句。
	if DialogUI.is_open:
		before = _bar_text()
		_click_control(_action)
		await _wait_typing()
		await _shot("12_bar_line3_button")
		print("[CaptureDialog] 再点按钮后 = 「%s」 按钮文案=「%s」"
			% [_bar_text(), _action.text])

	# 点对话条**空白处**（左侧、避开右侧按钮）= 关闭（统一契约）。
	if DialogUI.is_open:
		var r: Rect2 = _bar.get_global_rect()
		var blank: Vector2 = Vector2(r.position.x + 8.0, r.position.y + r.size.y * 0.5)
		_click_canvas(blank)
		for i: int in 4:
			await get_tree().process_frame
	await _shot("13_bar_closed_by_click")
	_expect(not DialogUI.is_open, "点对话条空白处 → 关闭")
	print("[CaptureDialog] 点条内关闭后 is_open = %s" % DialogUI.is_open)


# ============================================================================
# 取证 4：宽度自适应（短句收窄 / 长句换行）
# ============================================================================

func _demo_adapt() -> void:
	var sh: float = await _show_instant_and_shot("20_adapt_short", DEMO_SHORT)
	var lg: float = await _show_instant_and_shot("21_adapt_long", DEMO_LONG)
	print("[CaptureDialog] 自适应宽度：短句 %.0fpx → 长句 %.0fpx" % [sh, lg])
	_expect(sh < lg, "对话条宽度随文本变化（短 < 长）")
	_expect(lg <= CANVAS.x, "长句对话条不出画布")


## 用瞬显方式播一句、截图、量宽，然后关掉。
func _show_instant_and_shot(tag: String, text: String) -> float:
	var script: DialogueScript = DialogueScript.new()
	script.speaker_default = "长老"
	var line: DialogueLine = DialogueLine.make(text, "", DialogueLine.Style.BODY,
		DialogueLine.Display.INSTANT)
	script.lines = [line]
	EventBus.dialog_script_requested.emit(script, Callable())
	for i: int in 4:
		await get_tree().process_frame
	await _shot(tag)
	var w: float = _bar.get_global_rect().size.x
	_ui.call("cancel_conversation")
	for i: int in 2:
		await get_tree().process_frame
	return w


# ============================================================================
# 取证 5：提示条（非阻塞）与对话条同屏
# ============================================================================

func _demo_notice() -> void:
	# 单句提示 → 顶部提示条。故意用长文本，验证它换行后仍在画布内、不压 HUD。
	EventBus.dialog_requested.emit(
		"路牌：前方是野外的入口，走过去就能离开小镇，路上小心野兽，记得先补满血再出发。", 0.0)
	for i: int in 3:
		await get_tree().process_frame
	await _shot("14_notice_top")
	var notice: Control = _ui.get_node_or_null("Root/Notice") as Control
	print("[CaptureDialog] 提示条 %s，notice_bottom=%.0f" % [_rect_str(notice), DialogUI.notice_bottom])
	_expect(notice != null and notice.get_global_rect().end.y <= CANVAS.y,
		"提示条在画布内")

	# 提示条还在时再开一段对话 → 两条通道同屏，谁也不顶掉谁。
	EventBus.dialog_sequence_requested.emit("铁匠",
		PackedStringArray(["提示条在上面，对话条在下面。", "两条通道各管各的，谁也不顶掉谁。"]),
		Callable())
	for i: int in 3:
		await get_tree().process_frame
	await _wait_typing()
	await _shot("15_notice_and_bar")
	_expect(DialogUI.is_open and DialogUI.notice_open, "提示条与对话条可以同屏共存")
	_ui.call("cancel_conversation")
	_ui.call("dismiss_notice")
	for i: int in 2:
		await get_tree().process_frame


# ============================================================================
# 取证 6：结构化对话 —— 样式 + 立绘 + 小头像
# ============================================================================

func _demo_structured() -> void:
	# 【坑】角色图是 64×112 的**精灵表**（4 列 × 7 行，每帧 16×16）。
	# 直接把整张表塞进 portrait，屏幕上会出现一整片小人格子（实测）。
	# 正确做法：抠出单帧，要放大就用 NEAREST 保持像素风。
	var portrait: Texture2D = _sprite_frame("res://assets/sprites/characters/OldMan.png", 0, 0, 4)
	var avatar: Texture2D = _sprite_frame("res://assets/sprites/characters/Villager.png", 0, 0, 1)

	var script: DialogueScript = DialogueScript.new()
	script.speaker_default = "长老"
	script.portrait_default = portrait
	script.portrait_slot_default = DialogueLine.PortraitSlot.LEFT
	script.expression_default = &"neutral"

	var a: DialogueLine = DialogueLine.make("（低语）三年前那场雪，埋掉了整个村子……",
		"长老", DialogueLine.Style.WHISPER, DialogueLine.Display.INSTANT)
	var b: DialogueLine = DialogueLine.make("大声点！我耳朵不聋！",
		"铁匠", DialogueLine.Style.SHOUT, DialogueLine.Display.INSTANT)
	var c: DialogueLine = DialogueLine.make("系统：获得「古旧的钥匙」×1",
		"", DialogueLine.Style.SYSTEM, DialogueLine.Display.INSTANT)
	var d: DialogueLine = DialogueLine.make("（旁白）一枚钥匙，沉甸甸的。",
		"", DialogueLine.Style.EMPHASIS, DialogueLine.Display.INSTANT)
	# 小头像（INLINE）：只有这一句带头像，验证"表头左侧头像"挂点。
	d.portrait = avatar
	d.portrait_slot = DialogueLine.PortraitSlot.INLINE
	script.lines = [a, b, c, d]

	EventBus.dialog_script_requested.emit(script, Callable())
	for i: int in 4:
		await get_tree().process_frame
	await _shot("16_style_whisper_portrait")
	print("[CaptureDialog] 样式/立绘：WHISPER+LEFT %s 立绘可见=%s"
		% [_rect_str(_bar), _visible("Root/Portrait")])

	_click_control(_action)
	for i: int in 4:
		await get_tree().process_frame
	await _shot("17_style_shout")
	print("[CaptureDialog] SHOUT：%s 立绘可见=%s" % [_rect_str(_bar), _visible("Root/Portrait")])

	_click_control(_action)
	for i: int in 4:
		await get_tree().process_frame
	await _shot("18_style_system")

	_click_control(_action)
	for i: int in 4:
		await get_tree().process_frame
	await _shot("19_style_emphasis_avatar")
	print("[CaptureDialog] EMPHASIS+INLINE：小头像可见=%s 对话条 %s"
		% [_visible("Root/Bar/VBox/Header/Avatar"), _rect_str(_bar)])
	_expect(_bar.get_global_rect().size.y <= 80.0,
		"INLINE 小头像没把对话条撑高（高 %.0f）" % _bar.get_global_rect().size.y)
	var avatar_node: Control = _ui.get_node_or_null("Root/Bar/VBox/Header/Avatar") as Control
	_expect(avatar_node != null and avatar_node.size.y <= 20.0, "INLINE 头像被限制在小尺寸")

	_ui.call("cancel_conversation")
	for i: int in 2:
		await get_tree().process_frame


# ============================================================================
# 工具
# ============================================================================

## 让教程停手并收起它的顶部面板。**不**调用 skip_tutorial()——
## 那会把「教程已完成」写进存档，截图脚本不该改玩家的档。
func _quiet_tutorial() -> void:
	# 【先 dismiss 再 poke】教程窗口是模态的（开着就持冻结令牌），直接 poke 会漏令牌。
	TutorialSystem.dismiss_current_step()
	TutorialSystem.set("_enabled", false)
	TutorialSystem.set("_active", false)
	TutorialSystem.set("_index", -1)
	TutorialSystem.set_process(false)
	EventBus.tutorial_step_shown.emit(-1, "", "", false)
	PauseManager.clear_all()


func _find_npc() -> NPC:
	for n: Node in get_tree().get_nodes_in_group(&"interactable"):
		if n is NPC:
			return n as NPC
	return _find_npc_recursive(get_tree().root)


## 从角色**精灵表**里抠出单帧，可选等比放大（NEAREST 保像素风）。
##
## 【为什么不直接 load() 整张图当立绘】
##   角色的 PNG 是 4 列 × 7 行、每帧 16×16 的精灵表，整张塞进 portrait
##   会显示一整片小人格子。要当立绘就得先 get_region() 抠一帧。
func _sprite_frame(path: String, col: int, row: int, scale: int, frame_px: int = 16) -> Texture2D:
	var sheet: Texture2D = load(path) as Texture2D
	if sheet == null:
		return null
	var region: Image = sheet.get_image().get_region(
		Rect2i(col * frame_px, row * frame_px, frame_px, frame_px)).duplicate()
	if scale > 1:
		region.resize(frame_px * scale, frame_px * scale, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(region)


func _find_npc_recursive(root: Node) -> NPC:
	if root is NPC:
		return root as NPC
	for c: Node in root.get_children():
		var found: NPC = _find_npc_recursive(c)
		if found != null:
			return found
	return null


func _bar_text() -> String:
	var label: Label = _ui.get_node_or_null("Root/Bar/VBox/Text") as Label
	return label.text if label != null else "<无>"


func _mf(node: Node) -> int:
	return (node as Control).mouse_filter if node is Control else -1


func _visible(path: String) -> bool:
	var n: Node = _ui.get_node_or_null(path)
	return n != null and (n as CanvasItem).visible


func _rect_str(node: Control) -> String:
	if node == null:
		return "<无>"
	if not node.visible:
		return "hidden"
	var r: Rect2 = node.get_global_rect()
	return "x%.0f..%.0f y%.0f..%.0f" % [r.position.x, r.end.x, r.position.y, r.end.y]


## 记录"应该为真"的状态；不符就计数（退出码非 0），但**不**中断截图。
func _expect(ok: bool, what: String) -> void:
	if ok:
		print("[CaptureDialog]   ✓ %s" % what)
	else:
		_mismatch += 1
		print("[CaptureDialog]   ✗ %s" % what)


## 模拟按下 F（interact 动作）。
func _press_f() -> void:
	var ev: InputEventAction = InputEventAction.new()
	ev.action = &"interact"
	ev.pressed = true
	Input.parse_input_event(ev)


## 用真实鼠标事件点击画布上的某个点（画布坐标 → 窗口坐标要乘拉伸倍数）。
## 走的是引擎完整的 GUI 派发路径：证明面板的 mouse_filter / gui_input 真的接得住鼠标。
func _click_canvas(canvas_pos: Vector2) -> void:
	var factor: Vector2 = Vector2(get_window().size) / CANVAS
	var down: InputEventMouseButton = InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = canvas_pos * factor
	down.global_position = down.position
	Input.parse_input_event(down)
	var up: InputEventMouseButton = down.duplicate() as InputEventMouseButton
	up.pressed = false
	Input.parse_input_event(up)


## 用真实鼠标事件点击某个控件正中央（画布坐标 → 窗口坐标）。
func _click_control(control: Control) -> void:
	if control == null:
		return
	_click_canvas(control.get_global_rect().get_center())


## 等打字机把当前句跑完。
## 判据用右上角按钮的文案：打字中显示「全文」，打完了才变成「继续」/「关闭」。
## 比"文本若干帧不变"可靠——打字机每帧可能因为取整而短暂不变，会误判成已打完。
func _wait_typing() -> void:
	if _action == null:
		return
	for i: int in 300:
		await get_tree().process_frame
		if _action.text != "全文":
			return


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/%s.png" % [OUT_DIR, name]
	var err: int = img.save_png(path)
	# 一行机器可读的几何记录：tools/verify_dialog_shots.py 会拿它和截图里
	# **实际画出来的像素**对账（面板必须恰好出现在这里、hide 时一处都不能有）。
	print("[CaptureDialog] SHOT %s bar=%s notice=%s portrait=%s text=%s"
		% [name, _rect_str(_bar),
			_rect_str(_ui.get_node_or_null("Root/Notice") as Control),
			_rect_str(_ui.get_node_or_null("Root/Portrait") as Control),
			_rect_str(_ui.get_node_or_null("Root/Bar/VBox/Text") as Control)])
	if err != OK:
		print("[CaptureDialog] !! %s 保存失败：%d" % [path, err])
