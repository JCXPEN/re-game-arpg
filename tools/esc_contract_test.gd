## EscContractTest —— Esc 仲裁 / 暂停所有权 / 音频生命周期 的回归测试
##
## 【负责什么】
##   钉死本次重构的二条用户可见契约，防止"Esc 一按又乱套"重新长回来：
##
##     A. **Esc 有唯一仲裁者**（UIInputRouter）
##        · 有阻塞窗口在屏幕上时，Esc 必须交给**它**，不能穿透去开暂停菜单。
##        · 没有阻塞窗口时，Esc 才是"打开暂停菜单"。
##        · 层级高的压层级低的（教程 > 三选一 > 暂停 > 帮助 > 背包）。
##
##     B. **暂停只有一个所有者**（PauseManager）
##        · 令牌集合非空 ⇔ get_tree().paused == true（不变量）。
##        · 多个持有者叠加时，交还其中一个**不能**把游戏放跑。
##        · clear_all() 是换局语义，清干净且恢复运行。
##
##     C. **音频有归属，换局必收干净**
##        · stop_music() 之后 is_playing_music() 为 false、owner 清空。
##        · 换了 owner 就是换了曲子（不会"沿用上一首"造成 BGM 错配）。
##
##     D. **回主菜单是一条完整路径**（GameFlow.teardown_to_menu）
##        · 暂停令牌全清、弹窗队列作废、BGM 停掉、关卡引用断开。
##        · 且**不能**把"显示在主菜单"当成副作用偷偷发生（load_menu_music=false 时）。
##
## 【为什么这些必须写成测试】
##   这三处缺陷（Esc 抢跑 / 暂停多所有者 / BGM 不收敛）都不是"某一行写错"，
##   而是**架构性缺失**：任何一次"我就顺手加个 _unhandled_input"、
##   "我就顺手写个 paused = false"都能把它们重新引入。
##   只有把它们固化成可执行断言，重构才不会悄悄退化。
##
## 【怎么运行】
##   Godot --headless --path . res://tools/esc_contract_test.tscn
##
## 【依赖谁】
##   UIInputRouter / PauseManager / GameFlow / AudioManager / SceneDirector
##   （全部 autoload）+ TutorialUI / PauseMenu / HelpPanel / InventoryUI 场景。
##
## 【测试铁律提醒（本项目踩过的坑）】
##   · 断言"函数里的先后顺序"必须先切函数体，不能对整份源码 find。
##   · 脱离场景树的节点没有生命周期（不 add_child 就不跑 _ready）。
##   · lambda 是值捕获，跨回调结果一律 Array 装箱。
##   · 模拟点按钮要用 btn.pressed.emit()，不能 emit gui_input。
extends Node

# ============================================================================
# 常量
# ============================================================================

## 与 boot.PERSISTENT_UI 保持同序（挂载顺序影响 Godot 的 Esc 派发顺序，
## 本测试要复现真实顺序，顺序错了结论就不成立）。
## 末尾的 HelpPanel / SettingsPanel 不在 boot 常驻表里（它们由暂停菜单按需挂载），
## 但同样是 UIInputRouter 的 target，测试要一起验注册与令牌语义，所以额外补上。
const PERSISTENT_UI: Array[String] = [
	"res://scenes/ui/hud.tscn",
	"res://scenes/ui/tutorial_ui.tscn",
	"res://scenes/ui/boss_health_bar.tscn",
	"res://scenes/ui/dialog_ui.tscn",
	"res://scenes/ui/modifier_choice.tscn",
	"res://scenes/ui/inventory_ui.tscn",
	"res://scenes/ui/game_over.tscn",
	"res://scenes/ui/pause_menu.tscn",
	"res://scenes/ui/help_panel.tscn",
	"res://scenes/ui/settings_panel.tscn",
]

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
	print("")
	print("################################################")
	print("#  Esc 仲裁 / 暂停所有权 / 音频 契约测试")
	print("################################################")

	await _install_ui()

	await _test_router_group_registered()
	await _test_esc_goes_to_top_blocker()
	await _test_esc_opens_pause_when_clear()
	await _test_pause_token_invariant()
	await _test_pause_stacked_holders()
	await _test_pause_clear_all()
	await _test_audio_lifecycle()
	await _test_teardown_to_menu()

	print("")
	print("################################################")
	print("# Esc 契约：%d 通过，%d 失败" % [_pass, _fail])
	for f: String in _fails:
		print("  - " + f)
	print("################################################")
	get_tree().quit(0 if _fail == 0 else 1)


# ============================================================================
# 用例 A —— Esc 仲裁
# ============================================================================

## A0：所有会挡玩家的窗口都必须**注册进路由器 group**。
##
## 【为什么这条要单测】漏注册的窗口不会被路由，其 Esc 行为就退回"各自为政"。
##   这是一个静默失败：窗口看起来正常，只在特定叠加顺序下才暴露。
func _test_router_group_registered() -> void:
	print("")
	print("--- A0. 路由目标注册 ---")
	# 兜底等多几帧：call_deferred 挂载是逐帧排空的，最后一个可能要等到
	# 本用例真正开始时才入树。这里主动补等，避免"安装竞态"变成假失败。
	for _i: int in 6:
		await get_tree().process_frame
	var expected: Array[String] = [
		"TutorialUI", "PauseMenu", "HelpPanel", "InventoryUI",
	]
	var missing: Array[String] = []
	var members: Array[Node] = get_tree().get_nodes_in_group(UIInputRouter.GROUP)
	var names: Array[String] = []
	for n: Node in members:
		names.append(str(n.name))
	for want: String in expected:
		if not names.has(want):
			missing.append(want)
	_check(missing.is_empty(),
		"挡玩家的窗口都已注册进 UIInputRouter 路由组（注册成员：%s）" % ", ".join(names),
		"这些窗口没注册，Esc 行为会退回各自为政：%s（实际注册：%s）"
			% [", ".join(missing), ", ".join(names)])


## A1：屏幕上有阻塞窗口时，Esc 归它，**绝不开暂停菜单**。
##
## 这是用户报的原始症状：教程窗口按 Esc → 角色还在动 + 暂停菜单叠上来。
func _test_esc_goes_to_top_blocker() -> void:
	print("")
	print("--- A1. Esc 归最上层阻塞窗口 ---")
	PauseManager.clear_all()

	var tut: Node = _root_node("TutorialUI")
	var pause: Node = _root_node("PauseMenu")
	if tut == null or pause == null:
		_check(false, "教程 / 暂停菜单已挂载", "缺少 TutorialUI 或 PauseMenu")
		return

	# 让教程窗口显示一个**阻塞型**步骤（冻结 + 独占屏幕）。
	_show_blocking_step()
	await _frames(3)

	_check(bool(tut.call("is_blocking_ui")),
		"A1 教程显示时自报为阻塞窗口",
		"教程显示中但 is_blocking_ui() 为 false")
	_check(UIInputRouter.top_blocking_id() == &"tutorial",
		"A1 路由器认定最上层是教程",
		"路由器认定的最上层是 %s（应为 tutorial）" % UIInputRouter.top_blocking_id())
	_check(PauseManager.holds(&"tutorial"),
		"A1 教程持有暂停令牌",
		"教程显示但没拿暂停令牌，角色会继续移动")

	# 投递 Esc。走路由器的公开入口（等价于真实 _unhandled_input 路径）。
	var handled: bool = UIInputRouter.handle_cancel(_esc_event())
	await _frames(3)

	_check(handled, "A1 Esc 被路由器消费", "Esc 无人处理，会继续向下传播")
	_check(not bool(pause.get("visible")),
		"A1 按 Esc 后暂停菜单**没有**被打开",
		"暂停菜单被错误打开了（Esc 穿透到了暂停菜单）")
	_check(UIInputRouter.top_blocking_id() != &"tutorial",
		"A1 Esc 之后教程不再是阻塞窗口（已被关掉）",
		"教程仍是阻塞窗口，说明 Esc 没有关掉它")
	_check(not PauseManager.is_frozen(),
		"A1 教程关闭后游戏恢复运行",
		"教程关闭后游戏仍暂停（令牌没交还）")
	_check(_panel_gone(tut),
		"A1 教程面板真正隐藏且不透明度已复位",
		"教程面板 visible 仍为 true（卡住的透明面板 —— 回主菜单后 UI 错乱的同源病灶）")

	PauseManager.clear_all()


## A2：没有阻塞窗口时，Esc = 打开暂停菜单。
func _test_esc_opens_pause_when_clear() -> void:
	print("")
	print("--- A2. 无阻塞窗口时 Esc 开暂停菜单 ---")
	PauseManager.clear_all()
	# 先把可能残留的界面收干净（上一条用例关过教程，但别假设）。
	_force_close_all()

	var pause: Node = _root_node("PauseMenu")
	if pause == null:
		_check(false, "暂停菜单已挂载", "缺少 PauseMenu")
		return

	_check(not UIInputRouter.has_blocking_ui(),
		"A2 当前无阻塞窗口",
		"仍有阻塞窗口：%s" % UIInputRouter.top_blocking_id())

	var handled: bool = UIInputRouter.handle_cancel(_esc_event())
	await _frames(2)

	_check(handled, "A2 Esc 被消费（用于打开暂停菜单）", "Esc 无人处理")
	_check(bool(pause.get("visible")),
		"A2 Esc 打开了暂停菜单",
		"Esc 没有打开暂停菜单")
	_check(PauseManager.holds(&"pause_menu"),
		"A2 暂停菜单持有暂停令牌",
		"暂停菜单开了但没拿令牌，游戏没停")
	_check(get_tree().paused,
		"A2 暂停菜单打开时游戏真的停住了",
		"暂停菜单开着但 paused 为 false（角色还能动）")

	# 再按一次 Esc 应该关掉它（自食其果，不留残局）。
	UIInputRouter.handle_cancel(_esc_event())
	await _frames(2)
	_check(not bool(pause.get("visible")) and not get_tree().paused,
		"A2 再按 Esc 关掉暂停菜单并恢复游戏",
		"暂停菜单关不掉或游戏没恢复")
	PauseManager.clear_all()


# ============================================================================
# 用例 B —— 暂停令牌
# ============================================================================

## B0：核心不变量 —— 持有者集合非空 ⇔ paused == true。
func _test_pause_token_invariant() -> void:
	print("")
	print("--- B0. 暂停令牌不变量 ---")
	PauseManager.clear_all()
	_check(not PauseManager.is_frozen() and not get_tree().paused,
		"B0 起点：无令牌、未暂停",
		"起点状态不对：holders=%s paused=%s"
			% [str(PauseManager.get_holders()), get_tree().paused])

	PauseManager.freeze(&"a")
	_check(PauseManager.is_frozen() and get_tree().paused,
		"B0 freeze 后：有令牌、已暂停",
		"freeze 没生效：paused=%s" % get_tree().paused)

	PauseManager.freeze(&"b")
	_check(PauseManager.holder_count() == 2 and get_tree().paused,
		"B0 再 freeze 一个：两个令牌，仍暂停",
		"多持有者状态错误：%s" % str(PauseManager.get_holders()))

	PauseManager.unfreeze(&"a")
	_check(PauseManager.holder_count() == 1 and get_tree().paused,
		"B0 交还一个：仍有令牌 ⇒ 仍暂停",
		"交还一个就把游戏放跑了：paused=%s" % get_tree().paused)

	PauseManager.unfreeze(&"b")
	_check(PauseManager.holder_count() == 0 and not get_tree().paused,
		"B0 全部交还：无令牌 ⇒ 恢复运行",
		"令牌空了但游戏仍暂停：paused=%s" % get_tree().paused)

	# 幂等性：重复 freeze / 重复 unfreeze 都不能破坏状态。
	PauseManager.freeze(&"a")
	PauseManager.freeze(&"a")
	_check(PauseManager.holder_count() == 1,
		"B0 freeze 幂等（同 id 重复申请只记一次）",
		"重复 freeze 记了多次：%s" % str(PauseManager.get_holders()))
	PauseManager.unfreeze(&"a")
	PauseManager.unfreeze(&"a")
	_check(PauseManager.holder_count() == 0 and not get_tree().paused,
		"B0 unfreeze 幂等（不持有则忽略）",
		"重复 unfreeze 把状态弄坏了：paused=%s" % get_tree().paused)


## B1：叠加场景 —— 关掉上层窗口不能把下层还按着的游戏放跑。
##
## 这是 B13 的分身：背包可以叠在暂停菜单之上打开。
func _test_pause_stacked_holders() -> void:
	print("")
	print("--- B1. 叠加持有者 ---")
	PauseManager.clear_all()
	_force_close_all()

	var inv: Node = _root_node("InventoryUI")
	var help: Node = _root_node("HelpPanel")
	if inv == null:
		_check(false, "背包已挂载", "缺少 InventoryUI")
		return

	# 暂停菜单（用契约扮演）→ 再开背包 → 关背包。
	PauseManager.freeze(&"pause_menu")
	inv.call("open")
	await _frames(1)
	_check(get_tree().paused and PauseManager.holds(&"inventory"),
		"B1 暂停菜单 + 背包叠加时游戏暂停",
		"叠加时没暂停，holders=%s" % str(PauseManager.get_holders()))
	inv.call("close")
	await _frames(1)
	_check(get_tree().paused,
		"B1 关背包后游戏**仍暂停**（暂停菜单还按着）",
		"关背包把暂停菜单底下的游戏放跑了")
	_check(PauseManager.holds(&"pause_menu") and not PauseManager.holds(&"inventory"),
		"B1 背包只交还自己的令牌",
		"令牌归属错乱：%s" % str(PauseManager.get_holders()))
	PauseManager.clear_all()

	# 帮助面板同款场景（它也是从暂停菜单里打开的常客）。
	if help == null:
		return
	PauseManager.freeze(&"pause_menu")
	help.call("open")
	await _frames(1)
	help.call("close")
	await _frames(1)
	_check(get_tree().paused and PauseManager.holds(&"pause_menu")
			and not PauseManager.holds(&"help"),
		"B1 帮助面板同样只交还自己的令牌",
		"帮助面板令牌归属错乱：%s" % str(PauseManager.get_holders()))
	PauseManager.clear_all()


## B2：clear_all() 是"换局"语义，必须清干净并恢复运行。
func _test_pause_clear_all() -> void:
	print("")
	print("--- B2. clear_all 换局语义 ---")
	PauseManager.freeze(&"x")
	PauseManager.freeze(&"y")
	PauseManager.freeze(&"z")
	PauseManager.clear_all()
	_check(PauseManager.holder_count() == 0 and not get_tree().paused,
		"B2 clear_all 清空全部令牌并恢复运行",
		"clear_all 后状态不对：holders=%s paused=%s"
			% [str(PauseManager.get_holders()), get_tree().paused])


# ============================================================================
# 用例 C —— 音频生命周期
# ============================================================================

## C0：stop_music() 必须真的停干净（播放器 / 流 / 归属三者一致）。
##
## 用户报的"BGM 与当前场景不匹配"的底层原因就是这里没收敛：
## 场景已经释放了，_music_player.playing 还是 true。
func _test_audio_lifecycle() -> void:
	print("")
	print("--- C0. 音频生命周期 ---")
	AudioManager.stop_music()
	_check(not AudioManager.is_playing_music(),
		"C0 stop_music 后 is_playing_music 为 false",
		"stop_music 后仍在播放")
	_check(AudioManager.get_music_owner() == &"",
		"C0 stop_music 后归属清空",
		"归属未清空：%s" % AudioManager.get_music_owner())

	# 换 owner 就是换曲子：不同 owner 播同一首也要重启（避免"沿用上一首"）。
	var stream: AudioStream = _any_music_stream()
	if stream == null:
		_check(false, "能取到一首测试音乐", "找不到任何 .ogg 音乐资源")
		return

	AudioManager.play_music_for(&"level:field", stream)
	_check(AudioManager.get_music_owner() == &"level:field",
		"C0 播放后归属为 level:field",
		"归属错误：%s" % AudioManager.get_music_owner())

	# 同 owner + 同曲 + restart=false → 不打断（会返回，不重播）。
	AudioManager.play_music_for(&"level:field", stream, false)
	_check(AudioManager.get_music_owner() == &"level:field",
		"C0 同归属同曲重复调用保持归属",
		"重复调用后归属漂移：%s" % AudioManager.get_music_owner())

	# 换 owner → 归属必须跟着换（这就是"BGM 与场景匹配"的判定依据）。
	AudioManager.play_music_for(&"menu", stream, true)
	_check(AudioManager.get_music_owner() == &"menu",
		"C0 换归属后 owner 跟着换",
		"换归属失败，仍是：%s" % AudioManager.get_music_owner())

	AudioManager.stop_music()
	_check(not AudioManager.is_playing_music() and AudioManager.get_music_owner() == &"",
		"C0 收尾 stop_music 干净",
		"收尾不干净：playing=%s owner=%s"
			% [AudioManager.is_playing_music(), AudioManager.get_music_owner()])


# ============================================================================
# 用例 D —— 回主菜单
# ============================================================================

## D0：teardown_to_menu 必须把五件事一次做完。
##
## 【为什么用 load_menu_music=false 测】只验状态清理，不副作用地挂主菜单，
##   免得测试之间互相干扰（也顺便钉住"不挂菜单"这条参数语义）。
func _test_teardown_to_menu() -> void:
	print("")
	print("--- D0. 回主菜单的状态清理 ---")
	# 造一个"脏"的局面：暂停令牌 + 弹窗 + 关卡 BGM。
	PauseManager.freeze(&"pause_menu")
	PauseManager.freeze(&"inventory")
	var stream: AudioStream = _any_music_stream()
	if stream != null:
		AudioManager.play_music_for(&"level:field", stream)
	# 占用弹窗槽位 + 排一个等待项，做出一副"局内界面还开着"的样子。
	PopupManager.try_acquire(&"tutorial")
	PopupManager.enqueue(&"help", PopupManager.PRIORITY_HELP, func() -> void: pass)

	GameFlow.teardown_to_menu(false)
	await _frames(2)

	_check(PauseManager.holder_count() == 0 and not get_tree().paused,
		"D0 回主菜单后暂停令牌全清、游戏恢复运行",
		"令牌/暂停没清干净：holders=%s paused=%s"
			% [str(PauseManager.get_holders()), get_tree().paused])
	_check(not AudioManager.is_playing_music(),
		"D0 回主菜单后关卡 BGM 已停止",
		"回主菜单后 BGM 仍在放（用户报的 BGM 错配）")
	_check(AudioManager.get_music_owner() == &"",
		"D0 回主菜单后音乐归属已清空",
		"音乐归属残留：%s" % AudioManager.get_music_owner())
	_check(PopupManager.active_id() == &"",
		"D0 回主菜单后弹窗占用已释放",
		"弹窗仍占着：%s" % PopupManager.active_id())
	# 队列也必须空：这里**真的连信号数一下**，不读内部字段 ——
	# 读字段只能证明实现没变，证明不了"队里那个 help 的回调再也不会被叫醒"。
	# 做法：teardown 之后再申请一次，若槽位与队列都干净就必然立刻拿到。
	var probed: Array[bool] = []
	PopupManager.popup_opened.connect(func(_id: StringName) -> void: probed.append(true),
		CONNECT_ONE_SHOT)
	var got_slot: bool = PopupManager.try_acquire(&"probe_after_teardown")
	PopupManager.release(&"probe_after_teardown")
	_check(got_slot and probed.size() == 1,
		"D0 回主菜单后弹窗队列已作废（新申请立刻拿到并触发 opened）",
		"弹窗队列仍有残留占用（probed=%d）" % probed.size())
	_check(SceneDirector.get_current_level() == null,
		"D0 回主菜单后关卡引用已断开（无野指针）",
		"关卡引用仍在：%s" % str(SceneDirector.get_current_level()))

	# 收尾：把测试期间开的界面都收掉，别把状态带出测试。
	_force_close_all()
	PauseManager.clear_all()


# ============================================================================
# 私有方法 —— 工具
# ============================================================================

func _check(ok: bool, msg: String, detail: String) -> void:
	if ok:
		_pass += 1
		print("  [PASS] " + msg)
	else:
		_fail += 1
		_fails.append(detail)
		print("  [FAIL] " + msg)


## 让 TutorialUI 显示一个**阻塞型**教程步骤，走 TutorialSystem 的真实入口。
##
## 【为什么要造数据、不直接调 UI】提示是否冻结游戏 / 独占屏幕由
##   `TutorialStep.pause_game` 决定：操作类提示（"靠近村民按 [F] 交谈"）是非阻塞的，
##   系统级提示才是阻塞的（见 tutorial_ui.gd 文件头）。本用例验的是**阻塞窗口**的
##   Esc 契约，所以必须真造一条 pause_game = true 的步骤，而不是假设提示一律阻塞。
##
## 【为什么给两步】dismiss_current_step() 会往下一步推进；只有一步时
##   _try_start_next() 会走 _finish() 把"教程已完成"写进存档，污染后续用例。
func _show_blocking_step() -> void:
	var first: TutorialStep = TutorialStep.new()
	first.pause_game = true
	first.title = "标题"
	first.text = "内容"
	var second: TutorialStep = TutorialStep.new()
	# 空档步骤绑一个不存在的关卡：`level_id` 为空表示"任意关卡都匹配"，
	# 若当前正好在某个关卡里，关掉本步后会立刻又播一步，断言就失真了。
	second.level_id = &"__never__"
	var steps: Array[TutorialStep] = [first, second]
	TutorialSystem.set("_steps", steps)
	TutorialSystem.set("_enabled", false)
	TutorialSystem.set("_active", false)
	TutorialSystem.set("_index", 0)
	# 冻结与发信号都在 _show_step 里成对完成（唯一所有者）。
	TutorialSystem.call("_show_step", first)


## 构造一个物理 Esc 按键事件（按下、非回显）。
func _esc_event() -> InputEventKey:
	var ev: InputEventKey = InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	return ev


## 面板是否"真的不在了"（visible=false）。教程面板用 _panel 判定。
func _panel_gone(host: Node) -> bool:
	var panel: Variant = host.get("_panel")
	if panel is CanvasItem:
		return not (panel as CanvasItem).visible
	return true


## 把 root 下所有瞬态界面收掉（测试之间清场）。
func _force_close_all() -> void:
	for n: Node in get_tree().get_nodes_in_group(UIInputRouter.GROUP):
		if n.has_method(&"force_close"):
			n.call(&"force_close")
	PopupManager.release_all()
	PauseManager.clear_all()


## 尽量再装一次常驻 UI（本测试直接从 root 起，没有 boot 帮忙）。
##
## 【为什么不改名】每个 UI 场景的**根节点名就是它该有的名字**
##   （help_panel.tscn 的根叫 HelpPanel、tutorial_ui.tscn 的根叫 TutorialUI…）。
##   曾经这里用 `path.get_file().get_basename().to_pascal_case()` 推名字，
##   结果 `tutorial_ui` → `TutorialUi`、`game_over` → `GameOver`（首字母大写
##   不是"大写字母缩写"），节点名和代码里按 NodePath 找的名字对不上。
##   直接用场景自带的根名最可靠，也和 boot.PERSISTENT_UI 的显式命名表一致。
##
## 【为什么先 await 一帧】_ready 期间 root 正在"设置子节点"，
##   此时 add_child 会报 "Parent node is busy setting up children" 并静默失败。
func _install_ui() -> void:
	await _frames(1)
	for path: String in PERSISTENT_UI:
		if not ResourceLoader.exists(path):
			push_warning("[EscContract] 缺少 UI 场景：%s" % path)
			continue
		# 场景根节点的名字本来就是对的（HelpPanel / TutorialUI / GameOverUI…），
		# 不要再改名：改名会破坏 .tscn 里带 unique_id 的根节点绑定，
		# 实测 HelpPanel / SettingsPanel 会因此挂载失败（静默，不报错）。
		var node: Node = (load(path) as PackedScene).instantiate()
		get_tree().root.add_child.call_deferred(node)
	# 每个节点都要等它自己的 _ready（add_to_group 在里面）跑完。
	# 帧数给足：挂载是 call_deferred 的，一次性挂 10 个节点需要多帧才全部就绪。
	await _frames(10)


## UI 场景路径 → 常驻节点名（与 boot.PERSISTENT_UI 的值逐一对应）。
##
## 【为什么不用 to_pascal_case()】它只做"首字母大写"，得到 TutorialUi / GameOver，
##   与本项目实际使用的 TutorialUI / GameOverUI 不符。显式映射虽然啰嗦，
##   但它是**唯一**能保证"测试里的名字 == 生产里的名字"的写法。
func _ui_node_name(path: String) -> String:
	match path:
		"res://scenes/ui/hud.tscn": return "HUD"
		"res://scenes/ui/tutorial_ui.tscn": return "TutorialUI"
		"res://scenes/ui/boss_health_bar.tscn": return "BossHealthBar"
		"res://scenes/ui/dialog_ui.tscn": return "DialogUI"
		"res://scenes/ui/modifier_choice.tscn": return "ModifierChoice"
		"res://scenes/ui/inventory_ui.tscn": return "InventoryUI"
		"res://scenes/ui/game_over.tscn": return "GameOverUI"
		"res://scenes/ui/pause_menu.tscn": return "PauseMenu"
		"res://scenes/ui/help_panel.tscn": return "HelpPanel"
		"res://scenes/ui/settings_panel.tscn": return "SettingsPanel"
		_: return path.get_file().get_basename()


## root 直属子节点里按名字取。
func _root_node(node_name: String) -> Node:
	if get_tree() == null:
		return null
	return get_tree().root.get_node_or_null(NodePath(node_name))


## 随便找一首音乐资源（用于音频用例）。
func _any_music_stream() -> AudioStream:
	for path: String in [
		GameFlow.MENU_MUSIC_PATH,
		"res://assets/audio/music/17 - Fight.ogg",
		"res://assets/audio/music/2 - The Cave.ogg",
	]:
		if ResourceLoader.exists(path):
			return load(path) as AudioStream
	# 兜底：扫目录里第一首。
	var dir: DirAccess = DirAccess.open("res://assets/audio/music")
	if dir == null:
		return null
	for f: String in dir.get_files():
		if f.ends_with(".ogg") or f.ends_with(".ogg.import"):
			var real: String = f.trim_suffix(".import")
			var p: String = "res://assets/audio/music/" + real
			if ResourceLoader.exists(p):
				return load(p) as AudioStream
	return null


func _frames(n: int) -> void:
	for _i: int in n:
		await get_tree().process_frame
