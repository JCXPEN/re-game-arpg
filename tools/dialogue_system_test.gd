## DialogueSystemTest —— 结构化对话 + 自适应排版回归测试
##
## 【负责什么】
##   钉死这次"对话框改造"的两组契约，防止哪次改动把它们改回去：
##
##   A. **结构化对话**（可编辑 / 可扩展）
##      1. `DialogueScript` / `DialogueLine` 两个数据资源的行为（默认值回落、
##         逐句覆盖说话人、整段强制自动推进、旧 `PackedStringArray` 兼容转换）。
##      2. 逐句 **文本样式** 真的切换到了对应的 Theme 类型变体（字号随之变化）。
##      3. 三种 **显示方式** 各自生效：打字机 / 瞬显 / 自动推进。
##      4. **立绘 / 头像 / 表情** 这些预留字段真的能被渲染出来（不是死字段）。
##
##   B. **自适应排版**（这一组对应玩家报的三个问题）
##      5. 短句收窄、长句加宽 —— 对话框宽度**真的随文本变化**。
##      6. 任何长度（含 130+ 字）的文本，对话框都**不越出画布**、
##         内容**不被裁剪**、**行数不超过上限**（超长自动分页）。
##      7. 结算语义不变：读完最后一页回调 **恰好一次**；中途取消 **不回调**。
##
## 【为什么这些断言必须存在】
##   改造前的实测数据（`tools/ui_layout_probe.tscn` 可复现）：
##   一段 130 字的文本会让对话条长到 176×210，顶边跑到 **y = -52** ——
##   半个对话框在屏幕外，"说话人 + 关闭按钮"那一行直接被顶出可视区。
##   这种回归只有靠"量矩形"才能抓住，靠肉眼看截图是看不出来的。
##
## 【怎么运行】
##   Godot --headless --path . --quit-after 4000 res://tools/dialogue_system_test.tscn
##   退出码 0 = 全绿。
##
## 【依赖谁】
##   boot.tscn（真实启动流程）、EventBus、DialogUI、ui_theme.tres。
extends Node

# ============================================================================
# 常量
# ============================================================================

## 基准画布。所有几何断言都以它为界。
const CANVAS: Vector2 = Vector2(320, 180)
## 浮点容差。
const EPS: float = 0.05

const SHORT_LINE: String = "你终于醒了，勇者。"
const LONG_LINE: String = "你终于醒了，勇者。这片土地已经被诅咒了整整三年，村里的井水都干了，愿意听我把话说完吗？"
const HUGE_LINE: String = "北境的寒风从来不会怜悯任何人。三年前那场大雪埋掉了整整一个村子，活下来的人不到十分之一。如今同样的乌云又压了过来，而领主却把仅剩的粮食全部锁进了地窖。孩子，我不管你是为了赏金还是为了名声，我只求你一件事——在你还能选择的时候，选那条能让更多人活下来的路。"

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
	var boot: Node = load("res://scenes/core/boot.tscn").instantiate()
	boot.name = "Boot"
	boot.set("skip_menu", true)
	get_tree().root.add_child.call_deferred(boot)
	for i: int in 60:
		await get_tree().process_frame
	_quiet_tutorial()
	await get_tree().process_frame

	await _test_data_model()
	await _test_legacy_sequence_still_works()
	await _test_structured_script()
	await _test_text_styles()
	await _test_display_modes()
	await _test_voice_sfx()
	await _test_adaptive_width()
	await _test_no_overflow_any_length()
	await _test_pagination()
	await _test_portrait_slots()
	await _test_reward_semantics()
	await _test_notice_layout()

	print("")
	print("################################################")
	print("# 对话系统：%d 通过，%d 失败" % [_pass, _fail])
	for f: String in _fails:
		print("  - " + f)
	print("################################################")
	get_tree().quit(0 if _fail == 0 else 1)


# ============================================================================
# A. 结构化对话
# ============================================================================

## 1) 数据资源本身的行为。
func _test_data_model() -> void:
	print("")
	print("[A1] 数据模型")

	# 旧格式 → 结构化：说话人落到整段默认上，句数不变。
	var legacy: DialogueScript = DialogueScript.from_strings("村民", PackedStringArray(["甲", "乙", "丙"]))
	_check(legacy.line_count() == 3, "from_strings 保留句数",
		"句数 = %d" % legacy.line_count())
	_check(legacy.speaker_default == "村民", "from_strings 保留说话人",
		"说话人 = %s" % legacy.speaker_default)
	_check(legacy.get_line(0).resolve_speaker(legacy.speaker_default) == "村民",
		"行级说话人为空时回落到整段默认", "回落失败")
	_check(legacy.has_content(), "有内容时 has_content 为真", "has_content 为假")

	# 越界读取安全返回 null，不抛异常。
	_check(legacy.get_line(99) == null, "get_line 越界返回 null", "越界没有返回 null")
	_check(legacy.get_line(-1) == null, "get_line 负数返回 null", "负数没有返回 null")

	# 空段不该被当成"有内容"。
	var empty: DialogueScript = DialogueScript.new()
	_check(not empty.has_content(), "空段 has_content 为假", "空段被当成有内容")

	# 逐句覆盖说话人。
	var multi: DialogueScript = DialogueScript.new()
	multi.speaker_default = "长老"
	var l0: DialogueLine = DialogueLine.make("第一句")
	var l1: DialogueLine = DialogueLine.make("第二句", "村民")
	multi.lines = [l0, l1]
	_check(multi.get_line(0).resolve_speaker("长老") == "长老",
		"未覆盖的行用整段默认说话人", "默认说话人没生效")
	_check(multi.get_line(1).resolve_speaker("长老") == "村民",
		"行级说话人覆盖整段默认", "行级说话人没生效")

	# 整段强制自动推进优先于行级设置。
	var auto_line: DialogueLine = DialogueLine.make("x")
	auto_line.display = DialogueLine.Display.TYPEWRITER
	_check(auto_line.resolve_display(true) == DialogueLine.Display.AUTO,
		"auto_advance_all 强制所有行自动推进", "整段自动推进没生效")
	_check(auto_line.resolve_display(false) == DialogueLine.Display.TYPEWRITER,
		"未开整段自动推进时沿用行级设置", "行级设置被错误覆盖")

	# 打字速度回落。
	_check(auto_line.resolve_chars_per_sec(45.0) == 45.0,
		"行级未设速度时回落到全局默认", "速度回落失败")
	auto_line.chars_per_sec = 120.0
	_check(auto_line.resolve_chars_per_sec(45.0) == 120.0,
		"行级速度覆盖全局默认", "行级速度没生效")

	# 最长句长度统计（排版自检用）。
	_check(multi.longest_line_length() == 3, "longest_line_length 统计正确",
		"统计结果 = %d" % multi.longest_line_length())


## 2) 旧的 PackedStringArray 入口必须仍然可用（大量既有 NPC / 测试依赖它）。
func _test_legacy_sequence_still_works() -> void:
	print("")
	print("[A2] 旧入口兼容")
	var done: Array[int] = []
	EventBus.dialog_sequence_requested.emit("村民", PackedStringArray(["甲", "乙"]),
		func() -> void: done.append(1))
	await _settle()
	_check(DialogUI.is_open, "旧入口能打开对话条", "旧入口没打开对话条")
	_check(_speaker().text == "村民", "旧入口的说话人正确显示",
		"说话人 = 「%s」" % _speaker().text)
	await _finish_bar()
	_check(done.size() == 1, "旧入口播完回调恰好执行一次",
		"回调执行 %d 次" % done.size())


## 3) 结构化入口：逐句内容、空句过滤、多句推进。
func _test_structured_script() -> void:
	print("")
	print("[A3] 结构化入口")
	var script: DialogueScript = DialogueScript.new()
	script.speaker_default = "长老"
	script.lines = [
		DialogueLine.make("第一句"),
		DialogueLine.make("   "),           # 空句：应当被丢掉，不能显示成空对话框
		DialogueLine.make("第二句", "村民", DialogueLine.Style.EMPHASIS),
	]
	var seen: Array[String] = []
	EventBus.dialog_script_requested.emit(script, func() -> void: seen.append("done"))
	await _settle()
	_check(DialogUI.is_open, "结构化入口能打开对话条", "结构化入口没打开对话条")
	await _wait_typing("第一句")
	_check(_text().text == "第一句", "第 1 句内容正确", "实际 = 「%s」" % _text().text)
	_check(_speaker().text == "长老", "第 1 句用整段默认说话人",
		"实际 = 「%s」" % _speaker().text)

	_action().pressed.emit()
	await _settle()
	await _wait_typing("第二句")
	_check(_text().text == "第二句", "空句被过滤，第 2 句直接是「第二句」",
		"实际 = 「%s」" % _text().text)
	_check(_speaker().text == "村民", "第 2 句换说话人成功",
		"实际 = 「%s」" % _speaker().text)

	# 已是最后一句 → 点条内任意处 = 关闭并结算。
	_click(_bar())
	await _settle()
	_check(not DialogUI.is_open, "最后一句点条内关闭成功", "没能关闭")
	_check(seen.size() == 1, "结构化对话播完回调执行一次",
		"回调执行 %d 次" % seen.size())


## 4) 逐句文本样式真的切换了 Theme 变体（字号随之变化）。
func _test_text_styles() -> void:
	print("")
	print("[A4] 文本样式")
	var cases: Array = [
		[DialogueLine.Style.BODY, &"DialogBodyLabel"],
		[DialogueLine.Style.EMPHASIS, &"DialogEmphasisLabel"],
		[DialogueLine.Style.WHISPER, &"DialogWhisperLabel"],
		[DialogueLine.Style.SHOUT, &"DialogShoutLabel"],
		[DialogueLine.Style.SYSTEM, &"DialogSystemLabel"],
	]
	for pair: Array in cases:
		var script: DialogueScript = DialogueScript.new()
		script.lines = [DialogueLine.make("样式测试", "", pair[0])]
		EventBus.dialog_script_requested.emit(script, Callable())
		await _settle()
		_check(_text().theme_type_variation == pair[1],
			"样式 %s → 变体 %s" % [DialogueLine.Style.keys()[pair[0]], pair[1]],
			"实际变体 = %s" % _text().theme_type_variation)
		await _finish_bar()

	# SHOUT 走 HEADING 档、WHISPER 走 HINT 档 —— 证明"样式真的改了字号"，
	# 而不是只换了个颜色（换颜色在 320×180 上是很难分辨的）。
	var shout_fs: int = _font_size_of(DialogueLine.Style.SHOUT)
	var whisper_fs: int = _font_size_of(DialogueLine.Style.WHISPER)
	var body_fs: int = _font_size_of(DialogueLine.Style.BODY)
	_check(shout_fs > body_fs, "SHOUT 字号大于 BODY（%d > %d）" % [shout_fs, body_fs],
		"SHOUT=%d BODY=%d" % [shout_fs, body_fs])
	_check(whisper_fs < body_fs, "WHISPER 字号小于 BODY（%d < %d）" % [whisper_fs, body_fs],
		"WHISPER=%d BODY=%d" % [whisper_fs, body_fs])


## 5) 三种显示方式。
func _test_display_modes() -> void:
	print("")
	print("[A5] 显示方式")

	# INSTANT：不经过打字机，一帧内就是整句。
	var instant: DialogueScript = DialogueScript.new()
	var li: DialogueLine = DialogueLine.make(LONG_LINE)
	li.display = DialogueLine.Display.INSTANT
	instant.lines = [li]
	EventBus.dialog_script_requested.emit(instant, Callable())
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_text().text == LONG_LINE, "INSTANT 立刻显示整句（无打字机）",
		"实际长度 %d / 期望 %d" % [_text().text.length(), LONG_LINE.length()])
	await _finish_bar()

	# TYPEWRITER：刚开播时不是整句。
	var typed: DialogueScript = DialogueScript.new()
	typed.lines = [DialogueLine.make(LONG_LINE)]
	EventBus.dialog_script_requested.emit(typed, Callable())
	await get_tree().process_frame
	_check(_text().text.length() < LONG_LINE.length(),
		"TYPEWRITER 刚开播时只有部分文字",
		"开播即有 %d 字（应为部分）" % _text().text.length())
	await _finish_bar()

	# AUTO：不需要任何输入，到点自己往前走并结束。
	var auto: DialogueScript = DialogueScript.new()
	var la: DialogueLine = DialogueLine.make("自动推进的一句")
	la.display = DialogueLine.Display.AUTO
	la.auto_delay = 0.2
	auto.lines = [la]
	var auto_done: Array[int] = []
	EventBus.dialog_script_requested.emit(auto, func() -> void: auto_done.append(1))
	# 给足"打完字 + 停顿"的时间；不主动点任何东西。
	var waited: float = 0.0
	while DialogUI.is_open and waited < 3.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	_check(not DialogUI.is_open, "AUTO 对话无需输入即自动结束",
		"等了 %.2fs 仍开着" % waited)
	_check(auto_done.size() == 1, "AUTO 结束后回调执行一次",
		"回调执行 %d 次" % auto_done.size())


## 6) 逐字语音：带 `voice_sfx` 的句子必须能把打字机走完。
##
## 【为什么这条断言值得存在】
##   语音是在"逐字打字"的回调里触发的。一旦这条路径访问了 DialogueLine 上
##   **不存在**的属性，整个打字循环会在中途抛错停住 —— 表现是"话说到一半不动了"，
##   而且因为不报断言失败、只报脚本错误，很容易被漏掉。
##   这里用"文本最终能打全"作为判据，间接钉死"语音路径没有把打字机搞崩"。
func _test_voice_sfx() -> void:
	print("")
	print("[A6] 逐字语音")
	var sfx: AudioStream = load("res://assets/audio/sfx/Coin.wav") as AudioStream
	if sfx == null:
		_check(false, "能加载到测试音效资源", "res://assets/audio/sfx/Coin.wav 加载失败")
		return
	var script: DialogueScript = DialogueScript.new()
	var line: DialogueLine = DialogueLine.make("带语音的一句台词，应该能一字不差地打完。")
	line.voice_sfx = sfx
	line.voice_pitch = 1.4
	script.lines = [line]
	EventBus.dialog_script_requested.emit(script, Callable())
	await _settle()
	await _wait_typing(line.text)
	_check(_text().text == line.text, "带逐字语音的句子能完整打完",
		"实际 = 「%s」（打字机可能被语音路径中断）" % _text().text)
	await _finish_bar()


# ============================================================================
# B. 自适应排版
# ============================================================================
## 6) 宽度随文本变化：短句收窄、长句加宽，且都在画布内。
func _test_adaptive_width() -> void:
	print("")
	print("[B1] 宽度自适应")
	var short_w: float = await _bar_width_for(SHORT_LINE)
	var long_w: float = await _bar_width_for(LONG_LINE)
	print("  短句宽 %.0f / 长句宽 %.0f" % [short_w, long_w])
	_check(short_w < long_w, "短句的对话框比长句窄（%.0f < %.0f）" % [short_w, long_w],
		"短句 %.0f，长句 %.0f —— 宽度没有随文本变化" % [short_w, long_w])
	_check(short_w >= 96.0, "短句宽度不低于下限（%.0f）" % short_w,
		"短句过窄：%.0f" % short_w)
	_check(long_w <= CANVAS.x, "长句宽度不超过画布（%.0f）" % long_w,
		"长句过宽：%.0f" % long_w)
	await _finish_bar()
	await _dismiss_all_notices()


## 7) 任何长度都不越界、不被裁剪。这是"对话框跑出屏幕"的直接守卫。
func _test_no_overflow_any_length() -> void:
	print("")
	print("[B2] 不越界 / 不裁剪")
	for line: String in [SHORT_LINE, LONG_LINE, HUGE_LINE]:
		var script: DialogueScript = DialogueScript.new()
		script.lines = [DialogueLine.make(line)]
		EventBus.dialog_script_requested.emit(script, Callable())
		await _settle()
		# 跳过分页：只量第一页就要满足约束（分页本身由 B3 覆盖）。
		var bar: Control = _bar()
		var r: Rect2 = bar.get_global_rect()
		var m: Vector2 = bar.get_combined_minimum_size()
		var tag: String = "%d 字" % line.length()
		_check(r.position.y >= -EPS and r.end.y <= CANVAS.y + EPS,
			"【%s】对话框竖向不出画布（y %.0f..%.0f）" % [tag, r.position.y, r.end.y],
			"【%s】对话框越界：y %.0f..%.0f（画布高 %.0f）" % [tag, r.position.y, r.end.y, CANVAS.y])
		_check(r.position.x >= -EPS and r.end.x <= CANVAS.x + EPS,
			"【%s】对话框横向不出画布（x %.0f..%.0f）" % [tag, r.position.x, r.end.x],
			"【%s】对话框横向越界：x %.0f..%.0f" % [tag, r.position.x, r.end.x])
		_check(m.x <= r.size.x + EPS and m.y <= r.size.y + EPS,
			"【%s】对话框内容不被裁剪（需要 %.0f×%.0f，实有 %.0f×%.0f）"
				% [tag, m.x, m.y, r.size.x, r.size.y],
			"【%s】内容被裁剪" % tag)
		# 表头（说话人 + 关闭按钮）必须在可视区内 —— 它是唯一的手动关闭入口。
		var action: Button = _action()
		var ar: Rect2 = action.get_global_rect()
		_check(ar.position.y >= -EPS and ar.end.y <= CANVAS.y + EPS,
			"【%s】推进按钮在可视区内（y %.0f..%.0f）" % [tag, ar.position.y, ar.end.y],
			"【%s】推进按钮跑到屏幕外：y %.0f..%.0f" % [tag, ar.position.y, ar.end.y])
		var lines_shown: int = _visible_line_count()
		print("    %s → 对话框 %.0f×%.0f，正文 %d 行" % [tag, r.size.x, r.size.y, lines_shown])
		_check(lines_shown <= int(_ui().get("bar_max_lines")),
			"【%s】单页行数不超过上限（%d ≤ %d）"
				% [tag, lines_shown, int(_ui().get("bar_max_lines"))],
			"【%s】单页行数超限：%d" % [tag, lines_shown])
		await _finish_bar()


## 9) 超长文本自动分页：翻页次数大于句数，且最后一页才结算。
func _test_pagination() -> void:
	print("")
	print("[B3] 超长文本分页")
	var done: Array[int] = []
	EventBus.dialog_script_requested.emit(
		DialogueScript.from_text_array([HUGE_LINE], "村民"),
		func() -> void: done.append(1))
	await _settle()

	# 全程用**按钮**推进（点条内是"关闭 = 取消"，会中断分页验证）。
	# 文案为"全文"时是跳过打字机，不算推进；其余每一次按下才算推进了一页。
	var advances: int = 0
	var guard: int = 0
	while DialogUI.is_open and guard < 60:
		guard += 1
		var skipping: bool = _action().text == "全文"
		_action().pressed.emit()
		if not skipping:
			advances += 1
		await _settle()

	print("  130+ 字文本共推进 %d 次，回调 %d 次" % [advances, done.size()])
	_check(advances >= 2, "超长文本被分成多页（推进 %d 次 ≥ 2）" % advances,
		"只推进了 %d 次 —— 130+ 字没有分页，会撑破屏幕" % advances)
	_check(done.size() == 1, "分页后回调仍然恰好执行一次",
		"回调执行 %d 次" % done.size())
	_check(not DialogUI.is_open, "分页推进到底后对话关闭", "对话没关闭")


## 9) 立绘 / 头像 / 表情这些预留字段真的能渲染。
func _test_portrait_slots() -> void:
	print("")
	print("[B4] 立绘 / 头像 / 表情（预留字段）")
	var tex: Texture2D = _make_texture(8, 8)
	# 故意用一张**大图**当头像，专治"小头像把表头顶高"这个坑：
	# TextureRect 默认 EXPAND_KEEP_SIZE，未设 expand_mode 时它的最小尺寸 = 贴图原尺寸，
	# 于是一张 64×112 的立绘会把表头顶到 112px、把对话条从 51px 撑到 138px。
	var big: Texture2D = _make_texture(64, 112)

	var script: DialogueScript = DialogueScript.new()
	script.expression_default = &"neutral"
	var l0: DialogueLine = DialogueLine.make("带头像的一句", "村民")
	l0.portrait = big
	l0.portrait_slot = DialogueLine.PortraitSlot.INLINE
	l0.expression = &"smile"
	var l1: DialogueLine = DialogueLine.make("带立绘的一句")
	l1.portrait = tex
	l1.portrait_slot = DialogueLine.PortraitSlot.LEFT
	script.lines = [l0, l1]

	var states: Array = []
	var cb: Callable = func(line: DialogueLine) -> void: states.append(line)
	EventBus.portrait_state_changed.connect(cb)

	EventBus.dialog_script_requested.emit(script, Callable())
	await _settle()
	var avatar: TextureRect = _node("Root/Bar/VBox/Header/Avatar") as TextureRect
	_check(avatar != null and avatar.visible, "INLINE 槽位显示小头像",
		"头像不可见：%s" % str(avatar))
	# 小头像必须是"小"的：喂大图也不能把表头和对话框顶高。
	_check(avatar != null and avatar.size.y <= 20.0,
		"INLINE 头像是小尺寸而非贴图原尺寸（高 %.0f ≤ 20）"
			% (avatar.size.y if avatar != null else -1.0),
		"INLINE 头像没被限制尺寸（高 %.0f），会把对话条撑大"
			% (avatar.size.y if avatar != null else -1.0))
	_check(_bar().size.y <= 80.0,
		"带 INLINE 头像时对话条不被撑高（高 %.0f ≤ 80）" % _bar().size.y,
		"INLINE 头像把对话条撑到 %.0f 高" % _bar().size.y)
	_check(states.size() >= 1 and states[states.size() - 1] != null
			and (states[states.size() - 1] as DialogueLine).expression == &"smile",
		"表情状态通过 portrait_state_changed 透传",
		"没收到带 smile 的行")

	# 【为什么这里必须先等打字机打完】
	#   advance() 在"正在打字"时只做一件事——把整句立刻显示出来，**不翻页**。
	#   不等它打完就按按钮，只会把第 1 句补全，人还停在第 1 句上，
	#   于是立绘（属于第 2 句）永远不会显示。这是测试写法问题，不是渲染问题。
	await _wait_typing("带头像的一句")
	_action().pressed.emit()
	await _settle()
	await _wait_typing("带立绘的一句")
	var portrait: TextureRect = _node("Root/Portrait") as TextureRect
	_check(portrait != null and portrait.visible, "LEFT 槽位显示立绘",
		"立绘不可见：%s" % str(portrait))
	if portrait != null and portrait.visible:
		var pr: Rect2 = portrait.get_global_rect()
		_check(pr.position.x >= -EPS and pr.end.x <= CANVAS.x + EPS
				and pr.position.y >= -EPS and pr.end.y <= CANVAS.y + EPS,
			"立绘被夹在画布内（x %.0f..%.0f, y %.0f..%.0f）"
				% [pr.position.x, pr.end.x, pr.position.y, pr.end.y],
			"立绘跑出画布：%s" % str(pr))
	await _finish_bar()
	_check(not (portrait != null and portrait.visible), "对话结束后立绘被收起",
		"立绘还挂在屏幕上")
	EventBus.portrait_state_changed.disconnect(cb)


## 10) 结算语义：读完 = 回调一次；中途取消 = 不回调。
func _test_reward_semantics() -> void:
	print("")
	print("[B5] 结算语义")
	var done: Array[int] = []
	EventBus.dialog_sequence_requested.emit("村民",
		PackedStringArray(["一", "二", "三"]), func() -> void: done.append(1))
	await _settle()
	await _wait_typing("一")
	_click(_bar())          # 中途点条内 = 取消
	await _settle()
	_check(not DialogUI.is_open, "中途点条内可以关闭", "中途关不掉")
	_check(done.is_empty(), "中途取消不结算奖励（可重听）",
		"中途取消却结算了 %d 次" % done.size())

	# 读完最后一句再关 → 结算一次。
	EventBus.dialog_sequence_requested.emit("村民",
		PackedStringArray(["一", "二"]), func() -> void: done.append(1))
	await _settle()
	await _wait_typing("一")
	_action().pressed.emit()
	await _settle()
	await _wait_typing("二")
	_click(_bar())
	await _settle()
	_check(done.size() == 1, "读完后关闭恰好结算一次",
		"结算 %d 次" % done.size())


## 12) 提示条：宽度自适应、底边坐标对 HUD 可见。
func _test_notice_layout() -> void:
	print("")
	print("[B6] 提示条")
	var short_msg: String = "前方是野外。"
	EventBus.dialog_requested.emit(short_msg, 0.0)
	await _settle()
	var notice: Control = _node("Root/Notice") as Control
	var short_w: float = notice.get_global_rect().size.x
	await _dismiss_all_notices()

	var long_msg: String = "路牌：前方是野外的入口，走过去就能离开小镇，路上小心野兽，记得先补满血再出发。"
	EventBus.dialog_requested.emit(long_msg, 0.0)
	await _settle()
	var long_w: float = notice.get_global_rect().size.x
	var r: Rect2 = notice.get_global_rect()
	_check(short_w < long_w, "提示条宽度随文本变化（%.0f < %.0f）" % [short_w, long_w],
		"短 %.0f / 长 %.0f —— 提示条没有自适应" % [short_w, long_w])
	_check(r.position.x >= -EPS and r.end.x <= CANVAS.x + EPS
			and r.end.y <= CANVAS.y + EPS,
		"提示条在画布内（x %.0f..%.0f, y %.0f..%.0f）"
			% [r.position.x, r.end.x, r.position.y, r.end.y],
		"提示条越界：%s" % str(r))
	_check(DialogUI.notice_bottom > 0.0, "提示条向 HUD 暴露底边坐标（%.0f）"
			% DialogUI.notice_bottom,
		"notice_bottom 仍为 0，HUD 的 Toast 会和提示条叠在一起")
	_check(not DialogUI.is_open, "提示条不打开对话条（非阻塞）",
		"提示条错误地把对话条打开了")
	await _dismiss_all_notices()


# ============================================================================
# 工具 —— 断言
# ============================================================================

func _check(ok: bool, msg: String, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  [PASS] " + msg)
	else:
		_fail += 1
		_fails.append(detail if detail != "" else msg)
		print("  [FAIL] " + msg)


# ============================================================================
# 工具 —— 节点与状态
# ============================================================================

func _ui() -> Node:
	return UIRegistry.find_by_name("DialogUI")


func _node(path: String) -> Node:
	var ui: Node = _ui()
	return ui.get_node_or_null(path) if ui != null else null


func _bar() -> Control:
	return _node("Root/Bar") as Control


func _text() -> Label:
	return _node("Root/Bar/VBox/Text") as Label


func _speaker() -> Label:
	return _node("Root/Bar/VBox/Header/Speaker") as Label


func _action() -> Button:
	return _node("Root/Bar/VBox/Header/Action") as Button


## 当前正文实际占了几行。
##
## 【为什么不用 Label 的 get_combined_minimum_size().y 反推】
##   容器布局是**异步收敛**的：宽度刚改完的那一帧，Label 还没按新宽度重新折行，
##   它的最小高度仍是"上一帧的 1 行"。拿它反推会恒定得到 1 行，
##   于是"行数不超过上限"这条断言形同虚设（实测过）。
##   这里直接用"字体 + 当前宽度 + 正文字符串"自己折一遍，结果与布局时机无关。
func _visible_line_count() -> int:
	var label: Label = _text()
	if label == null or label.text == "":
		return 0
	var font: Font = label.get_theme_font(&"font")
	if font == null:
		return 0
	var fs: int = label.get_theme_font_size(&"font_size")
	var line_h: float = float(font.get_height(fs)) \
		+ float(label.get_theme_constant(&"line_spacing"))
	if line_h <= 0.0:
		return 1
	var width: float = label.size.x
	if width <= 0.0:
		width = label.get_global_rect().size.x
	var size: Vector2 = font.get_multiline_string_size(
		label.text, HORIZONTAL_ALIGNMENT_LEFT, width, fs)
	return maxi(1, int(round(size.y / line_h)))


## 某个文本样式实际会用到的字号（直接问主题，不需要真的播放那句话）。
func _font_size_of(style: DialogueLine.Style) -> int:
	var bar: Control = _bar()
	if bar == null:
		return 0
	var variation: StringName = DialogUI.variation_for(style)
	var fs: int = bar.get_theme_font_size(&"font_size", variation)
	if fs <= 0:
		fs = bar.get_theme_font_size(&"font_size", &"Label")
	return fs


func _make_texture(w: int, h: int) -> Texture2D:
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.9, 0.3, 0.3, 1.0))
	return ImageTexture.create_from_image(img)


# ============================================================================
# 工具 —— 驱动
# ============================================================================

func _settle() -> void:
	for i: int in 4:
		await get_tree().process_frame


## 等打字机把整句显示完（判据是"文本 == 预期"，确定性收敛，不受帧率影响）。
func _wait_typing(expected: String) -> void:
	var label: Label = _text()
	if label == null:
		return
	for i: int in 600:
		if label.text == expected:
			return
		await get_tree().process_frame
	push_warning("[DialogueTest] 等打字机超时：期望「%s」，实际「%s」" % [expected, label.text])


## 量一次"某个文本对应的对话框宽度"，量完收掉。
func _bar_width_for(line: String) -> float:
	EventBus.dialog_script_requested.emit(DialogueScript.from_text_array([line], "村民"), Callable())
	await _settle()
	var ui: Node = _ui()
	if ui != null:
		ui.call("advance")      # 跳到整句显示
	await _settle()
	var w: float = _bar().get_global_rect().size.x
	await _finish_bar()
	return w


## 把当前对话推到底（每轮先跳过打字机再推进），并确保关闭。
func _finish_bar() -> void:
	var ui: Node = _ui()
	if ui == null:
		return
	var guard: int = 0
	while DialogUI.is_open and guard < 80:
		guard += 1
		ui.call("advance")
		await get_tree().process_frame
	ui.call("cancel_conversation")


## 收掉提示条（本轮测试里它可能被设成常驻）。
func _dismiss_all_notices() -> void:
	var ui: Node = _ui()
	if ui != null:
		ui.call("dismiss_notice")
	await get_tree().process_frame


## 模拟左键点在某个 Control 的正中央（走 Control.gui_input 派发）。
##
## 【为什么不能对面板用 Input.parse_input_event】
##   `Input.parse_input_event` 送进去的是**窗口坐标**，引擎随后会按画布拉伸
##   （320×180 → 实际窗口）把它映射回画布坐标。headless 下没有真实窗口、
##   拉伸变换也不生效，于是坐标映射错位、点击"落空"（实测：点了但面板没反应）。
##   这里直接 emit 面板自己的 gui_input 信号，与引擎把点击送到面板上的路径一致
##   （面板 mouse_filter 必须是 STOP 才会收到），且完全不受拉伸影响 ——
##   与 weapon_dialog_test / popup_contract_test 的做法保持统一。
##
## 【注意】只能对"读 gui_input 的面板"用这个；按钮（BaseButton）要改用
##   `btn.pressed.emit()`，直接 emit gui_input 不会触发按钮的按下逻辑。
func _click(control: Control) -> void:
	if control == null:
		return
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = control.get_global_rect().get_center()
	control.gui_input.emit(ev)


## 让教程停手并收起它的面板（**不**写存档）。
##
## 【为什么必须先 dismiss 再 poke】教程窗口是模态的（开着就持冻结令牌），
## 只 set("_active", false) 会把令牌留在 PauseManager 里，让后续用例跑在冻结里。
func _quiet_tutorial() -> void:
	TutorialSystem.dismiss_current_step()
	TutorialSystem.set("_enabled", false)
	TutorialSystem.set("_active", false)
	TutorialSystem.set("_index", -1)
	TutorialSystem.set_process(false)
	EventBus.tutorial_step_shown.emit(-1, "", "", false)
	PauseManager.clear_all()
