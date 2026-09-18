## GameFlowTest —— 局面状态机回归测试
##
## 【负责什么】
##   钉死 GameFlow 的状态机契约，防止"局面流转"重新退化成散落的命令式代码：
##     A. 合法转移表被遵守，非法转移被拒绝且**不改变状态**。
##     B. 主菜单 / 局内 / 暂停 / 结算 四态的真实流转（跑真实 UI 与关卡）。
##     C. 暂停菜单的开关与 GameFlow 局面同步（PAUSED ⇄ PLAYING）。
##     D. BOOT → MENU 由 Boot 驱动；回主菜单后局面回到 MENU。
##
## 【怎么运行】Godot --headless --path . res://tools/game_flow_test.tscn
extends Node

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []

func _ready() -> void:
	print("")
	print("################################################")
	print("#  GameFlow 局面状态机契约")
	print("################################################")
	await get_tree().process_frame

	await _test_legal_table()
	await _test_illegal_rejected()
	await _test_boot_to_menu()
	await _test_play_and_pause_flow()
	await _test_game_over_flow()
	await _test_back_to_menu()

	print("")
	print("################################################")
	print("# GameFlow 契约：%d 通过，%d 失败" % [_pass, _fail])
	for f: String in _fails:
		print("  - " + f)
	print("################################################")
	get_tree().quit(1 if _fail > 0 else 0)


## A. 合法转移表：逐条断言表的形状与 can_transition 的一致性。
func _test_legal_table() -> void:
	print("")
	print("--- A. 合法转移表 ---")
	var S: Dictionary = GameFlow.State
	# 表必须覆盖全部枚举值。
	for s: int in [GameFlow.State.BOOT, GameFlow.State.MENU, GameFlow.State.PLAYING,
			GameFlow.State.PAUSED, GameFlow.State.GAME_OVER]:
		_field("转移表覆盖状态 %s" % GameFlow.state_name(s),
			GameFlow.LEGAL_TRANSITIONS.has(s), "缺状态 %d" % s)
	# 抽查若干合法 / 非法对。
	_field("MENU 可达 PLAYING", _allowed(S.MENU, S.PLAYING), "表中 MENU→PLAYING 不存在")
	_field("PLAYING 可达 PAUSED", _allowed(S.PLAYING, S.PAUSED), "表中 PLAYING→PAUSED 不存在")
	_field("PAUSED 可达 PLAYING", _allowed(S.PAUSED, S.PLAYING), "表中 PAUSED→PLAYING 不存在")
	_field("PLAYING 可达 GAME_OVER", _allowed(S.PLAYING, S.GAME_OVER), "表中 PLAYING→GAME_OVER 不存在")
	_field("BOOT 不可直接到 PAUSED", not _allowed(S.BOOT, S.PAUSED), "BOOT→PAUSED 不该合法")
	_field("MENU 不可直接到 GAME_OVER", not _allowed(S.MENU, S.GAME_OVER), "MENU→GAME_OVER 不该合法")
	# 自反：任何状态到自己是允许的（幂等 request）。
	_field("转移到自身视为合法", GameFlow.can_transition.bind(GameFlow.state()).call(),
		"can_transition(当前) 应为 true")


func _allowed(from: int, to: int) -> bool:
	return (GameFlow.LEGAL_TRANSITIONS.get(from, []) as Array).has(to)


## B. 非法转移被拒绝且状态不变。
func _test_illegal_rejected() -> void:
	print("")
	print("--- B. 非法转移拒绝 ---")
	# 先把局面强制放到 BOOT（用 request 无法到达，直接读当前即可：测试启动时就是 BOOT）。
	# 若已被其它用例改动，就用一次合法转移把它拉回可预期状态。
	await _force_state(GameFlow.State.BOOT)
	var before: int = GameFlow.state()
	var ok: bool = GameFlow.request(GameFlow.State.PAUSED)   # BOOT→PAUSED 非法
	_field("非法转移返回 false", not ok, "竟然返回 true")
	_field("非法转移不改变状态", GameFlow.state() == before,
		"状态被改成了 %s" % GameFlow.state_name())
	_field("can_transition 对非法返回 false", not GameFlow.can_transition(GameFlow.State.PAUSED),
		"can_transition 与 request 判定不一致")


## C. BOOT → MENU（由 Boot 装配驱动）。
func _test_boot_to_menu() -> void:
	print("")
	print("--- C. Boot → Menu ---")
	var boot: Node = load("res://scenes/core/boot.tscn").instantiate()
	boot.name = "Boot"
	boot.set("show_menu", true)
	get_tree().root.add_child.call_deferred(boot)
	await _frames(12)
	_field("Boot 装配后进入 MENU 局面", GameFlow.state() == GameFlow.State.MENU,
		"当前局面=%s" % GameFlow.state_name())
	_field("主菜单已挂载", _root("MainMenu") != null, "没有 MainMenu")
	_field("主菜单有 BGM 归属", AudioManager.get_music_owner() == GameFlow.MENU_MUSIC_OWNER,
		"归属=%s" % AudioManager.get_music_owner())
	# 清理，避免影响后续用例。
	var menu: Node = _root("MainMenu")
	if menu != null:
		menu.queue_free()
	await _frames(2)


## D. MENU → PLAYING → PAUSED → PLAYING 真实流转。
func _test_play_and_pause_flow() -> void:
	print("")
	print("--- D. 局内 / 暂停流转 ---")
	GameFlow.start_run(&"town", &"start")
	await _wait_idle()
	_field("start_run 后局面=PLAYING", GameFlow.state() == GameFlow.State.PLAYING,
		"当前局面=%s" % GameFlow.state_name())
	_field("is_playing 为 true", GameFlow.is_playing(), "is_playing=false")
	var player: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
	_field("关卡与玩家已就绪", player != null, "没有玩家")

	# 打开暂停菜单 → 局内应变为 PAUSED。
	var pause: Node = _root("PauseMenu")
	pause.call("open")
	await _frames(3)
	_field("暂停菜单打开后局面=PAUSED", GameFlow.state() == GameFlow.State.PAUSED,
		"当前局面=%s" % GameFlow.state_name())
	_field("暂停令牌已获取", PauseManager.holds(&"pause_menu"), "没拿到令牌")

	# 关闭 → 回到 PLAYING。
	pause.call("close")
	await _frames(3)
	_field("暂停菜单关闭后局面=PLAYING", GameFlow.state() == GameFlow.State.PLAYING,
		"当前局面=%s" % GameFlow.state_name())
	_field("暂停令牌已交还", not PauseManager.holds(&"pause_menu"),
		"令牌残留：%s" % str(PauseManager.get_holders()))


## E. PLAYING → GAME_OVER → PLAYING（复活）。
func _test_game_over_flow() -> void:
	print("")
	print("--- E. 结算流转 ---")
	if GameFlow.state() != GameFlow.State.PLAYING:
		GameFlow.start_run(&"town", &"start")
		await _wait_idle()
	var over: Node = _root("GameOverUI")
	over.call("_show_panel", "你倒下了", "测试", true)
	await _frames(3)
	_field("显示结算后局面=GAME_OVER", GameFlow.state() == GameFlow.State.GAME_OVER,
		"当前局面=%s" % GameFlow.state_name())
	# 复活 → 回 PLAYING。
	over.call("_respawn")
	await _wait_idle()
	_field("复活后局面=PLAYING", GameFlow.state() == GameFlow.State.PLAYING,
		"当前局面=%s" % GameFlow.state_name())


## F. 回主菜单：局面回到 MENU，且清理干净。
func _test_back_to_menu() -> void:
	print("")
	print("--- F. 回主菜单 ---")
	GameFlow.teardown_to_menu(true)
	await _frames(10)
	_field("回主菜单后局面=MENU", GameFlow.state() == GameFlow.State.MENU,
		"当前局面=%s" % GameFlow.state_name())
	_field("关卡引用已断开", SceneDirector.get_current_level() == null,
		"关卡残留：%s" % str(SceneDirector.get_current_level()))
	_field("无暂停令牌", not PauseManager.is_frozen(),
		"令牌残留：%s" % str(PauseManager.get_holders()))
	_field("HUD 已隐藏", not _vis(_root("HUD")), "HUD 仍可见")


# ============================================================================
# 工具
# ============================================================================

## 用合法路径把局面强制拉到目标（测试专用）。BOOT 只能靠"当前本就 BOOT"。
func _force_state(target: int) -> void:
	if GameFlow.state() == target:
		return
	# 常见情况：已经在 MENU/PLAYING。按合法路径走回去。
	if target == GameFlow.State.BOOT:
		# BOOT 不可达（它只是起点）；测试若已不在 BOOT，就跳过依赖。
		return
	GameFlow.request(target)


func _check(ok: bool, msg: String, detail: String) -> void:
	if ok:
		_pass += 1
		print("  [PASS] " + msg)
	else:
		_fail += 1
		_fails.append(detail)
		print("  [FAIL] " + msg)


func _field(msg: String, ok: bool, detail: String) -> void:
	_check(ok, msg, "%s :: %s" % [msg, detail])


func _vis(n: Node) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	return bool(n.get("visible"))


func _root(n: String) -> Node:
	# UI 现在可能挂在 Menus/GUI 容器下，不再直属 root；用注册表的递归查找兜底，
	# 这样测试不受容器层级影响（沿用'按名字访问'的旧写法，迁移期无需逐个改路径）。
	return UIRegistry.find_by_name(n)


func _wait_idle() -> void:
	for _i: int in 200:
		if not SceneDirector.is_changing():
			break
		await get_tree().process_frame
	await _frames(8)


func _frames(n: int) -> void:
	for _i: int in n:
		await get_tree().process_frame
