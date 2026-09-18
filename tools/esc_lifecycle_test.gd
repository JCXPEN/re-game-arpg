## EscLifecycleTest —— Esc 生命周期 / 暂停健壮性 / 场景-音频一致性 的永久回归
##
## 【负责什么】
##   把本次修复的、现有套件覆盖不到的**端到端**契约钉死。esc_contract_test 验的是
##   "令牌集合 / paused 位"这类间接指标；本套件跑真实 boot + 真实关卡，验用户
##   真正看得见的行为：
##
##     A. 暂停真的冻结游戏（真实输入按住方向键，角色位移为 0）。
##     B. PauseManager 以真实 paused 位为准：外部直写 paused 之后，再 freeze
##        仍能重新冻住（旧实现的缓存位脱节会让 Esc 失效、角色照跑）。
##     C. 暂停菜单的子面板走 open()/close() 契约：Esc 关设置会落盘、关帮助会
##        交还 PopupManager 槽位与暂停令牌；从暂停菜单进入时关子面板不丢暂停。
##     D. 回主菜单后：HUD / Boss 血条收起、技能栏清空、音乐归属=menu。
##     E. 转场中途返回主菜单：在途的 change_to_level 被取消，不得把关卡/BGM
##        挂回来（fade_time=0 时窗口最窄，是竞态高发区）。
##
## 【怎么运行】
##   Godot --headless --path . res://tools/esc_lifecycle_test.tscn
##
## 【为什么这些必须端到端跑】
##   本次修复的缺陷（缓存位脱节 / 在途转场复活 / 子面板绕过 close / HUD 残留）
##   全是**跨模块时序**问题，纯单元断言和直接调 handle_cancel() 都验不出来。
extends Node

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	print("")
	print("################################################")
	print("#  Esc 生命周期 / 暂停健壮性 / 场景-音频一致性")
	print("################################################")

	# 用真实 boot 装配常驻层（与生产完全一致）。
	var boot: Node = load("res://scenes/core/boot.tscn").instantiate()
	boot.name = "Boot"
	boot.set("show_menu", true)
	get_tree().root.add_child.call_deferred(boot)
	await _frames(12)

	await _case_real_input_freeze()
	await _case_pause_cache_desync()
	await _case_subpanel_contracts()
	await _case_menu_ui_cleanup()
	await _case_transition_cancel()

	print("")
	print("################################################")
	print("# Esc 生命周期：%d 通过，%d 失败" % [_pass, _fail])
	for f: String in _fails:
		print("  - " + f)
	print("################################################")
	get_tree().quit(1 if _fail > 0 else 0)


# ============================================================================
# A. 暂停真的冻结游戏（真实输入）
# ============================================================================

func _case_real_input_freeze() -> void:
	print("")
	print("--- A. 真实输入下 Esc 冻结游戏 ---")
	await _goto_level(&"town")

	var player: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
	_field("找到玩家", player != null, "没有玩家节点")
	if player == null:
		return
	# 提示/教程可能正占着屏幕，先清干净，确保 Esc 走的是"开暂停菜单"分支。
	await _clear_blocking()

	Input.parse_input_event(_key(KEY_D, true))
	await _frames(2)
	var p0: Vector2 = player.global_position
	await _phys(10)
	_field("未暂停时角色会移动", player.global_position.distance_to(p0) > 1.0, "位移≈0")

	Input.parse_input_event(_esc())
	await _frames(4)
	var pause: Node = _root("PauseMenu")
	_field("真实 Esc 打开暂停菜单", pause != null and bool(pause.get("visible")), "没打开")
	_field("Esc 后 get_tree().paused==true", get_tree().paused, "paused=false")

	var p1: Vector2 = player.global_position
	await _phys(20)
	_field("暂停中按住方向键角色不移动", player.global_position.distance_to(p1) < 0.01,
		"位移=%.4f（暂停没有冻结物理循环）" % player.global_position.distance_to(p1))
	Input.parse_input_event(_key(KEY_D, false))
	if pause != null and pause.has_method(&"close"):
		pause.call("close")
	PauseManager.clear_all()
	await _frames(2)


# ============================================================================
# B. 缓存位脱节（外部直写 paused）
# ============================================================================

func _case_pause_cache_desync() -> void:
	print("")
	print("--- B. 外部直写 paused 后 freeze 仍有效 ---")
	PauseManager.clear_all()
	await _frames(2)
	# 模拟"某个外部系统/旧代码直接写 paused"造成的脱节。
	PauseManager.freeze(&"x")
	get_tree().paused = false
	PauseManager.freeze(&"pause_menu")
	_field("外部把 paused 设 false 后，pause 菜单 freeze 能重新冻住",
		get_tree().paused,
		"paused 仍为 false —— 缓存位脱节会让 Esc 完全失效、角色照跑")
	PauseManager.unfreeze(&"pause_menu")
	_field("仍持有 x 令牌时保持暂停", get_tree().paused,
		"交还 pause_menu 后把 x 按着的游戏放跑了")
	PauseManager.clear_all()
	await _frames(2)
	_field("clear_all 后恢复运行", not get_tree().paused, "clear_all 没能解除暂停")


# ============================================================================
# C. 暂停菜单的子面板契约
# ============================================================================

func _case_subpanel_contracts() -> void:
	print("")
	print("--- C. 子面板 open()/close() 契约 ---")
	await _clear_blocking()

	var pause: Node = _root("PauseMenu")
	pause.call("open")
	await _frames(2)

	# C1. 帮助：Esc 关闭后必须交还弹窗槽位与暂停令牌，且不丢暂停菜单的暂停。
	pause.call("_open_help")
	await _frames(3)
	var help: Node = _root("HelpPanel")
	_field("帮助面板打开", help != null and bool(help.get("visible")), "没打开")
	UIInputRouter.handle_cancel(_esc())
	await _frames(3)
	_field("Esc 关闭帮助", help != null and not bool(help.get("visible")), "仍可见")
	_field("关闭帮助后暂停菜单仍在", bool(pause.get("visible")), "暂停菜单被一起关掉")
	_field("关闭帮助后游戏仍暂停", get_tree().paused, "游戏被放跑")
	_field("关闭帮助后无弹窗槽位残留", PopupManager.active_id() == &"",
		"槽位仍被占：%s" % PopupManager.active_id())
	_field("关闭帮助后无令牌残留", not PauseManager.holds(&"help"),
		"令牌残留：%s" % str(PauseManager.get_holders()))

	# C2. 设置：Esc 关闭必须生效（走 route_esc → close 契约）；改动即时落盘不丢。
	var settings_path: String = SettingsService.SETTINGS_PATH
	if FileAccess.file_exists(settings_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	pause.call("_open_settings")
	await _frames(3)
	var st: Node = _root("SettingsPanel")
	_field("设置面板打开", st != null and bool(st.get("visible")), "没打开")
	# 打开后动一下音量滑块 → 应立即落盘（新语义：改动即时保存，不必等关闭）。
	# 【为什么要选一个"不同"的值】若目标值和当前值相同，value_changed 不触发、
	#   也就不会落盘；直接写死 0.4 在"上次运行恰好存了 0.4"时会假失败。
	var music: HSlider = st.get_node_or_null("Root/Panel/Margin/VBox/MusicRow/Music") as HSlider
	if music != null:
		music.value = 0.6 if not is_equal_approx(music.value, 0.6) else 0.4
		await _frames(2)
	UIInputRouter.handle_cancel(_esc())
	await _frames(3)
	_field("Esc 关闭设置", st != null and not bool(st.get("visible")), "仍可见")
	_field("设置改动已落盘（未因 Esc 关闭而丢失）", FileAccess.file_exists(settings_path),
		"settings.cfg 不存在（设置改动丢失）")

	# C3. 返回主菜单时子面板一起收，不留令牌/槽位。
	pause.call("_open_help")
	await _frames(2)
	pause.call("_go_main_menu")
	await _frames(6)
	_field("回主菜单后帮助已收起", help == null or not bool(help.get("visible")), "帮助仍可见")
	_field("回主菜单后无弹窗残留", PopupManager.active_id() == &"",
		"弹窗仍占着：%s" % PopupManager.active_id())


# ============================================================================
# D. 回主菜单的 UI / 音频清理
# ============================================================================

func _case_menu_ui_cleanup() -> void:
	print("")
	print("--- D. 回主菜单后 UI / 音频状态 ---")
	await _goto_level(&"town")
	# 确保 HUD 绑上玩家并建好技能栏。
	await _frames(12)
	var hud: Node = _root("HUD")
	var boss_bar: Node = _root("BossHealthBar")
	_field("进关后 HUD 可见", _vis(hud), "进关后 HUD 不可见")

	GameFlow.teardown_to_menu(true)
	await _frames(10)

	_field("回主菜单后 HUD 已隐藏", not _vis(hud), "HUD 仍叠在主菜单上")
	_field("回主菜单后 Boss 血条已隐藏", not _vis(boss_bar), "Boss 血条仍可见")
	var skill_bar: Node = hud.get_node_or_null("Root/SkillBar") if hud != null else null
	_field("回主菜单后技能栏已清空", skill_bar == null or skill_bar.get_child_count() == 0,
		"技能栏仍挂着 %d 个图标" % (skill_bar.get_child_count() if skill_bar != null else -1))
	_field("主菜单 BGM 在播", AudioManager.is_playing_music(), "主菜单没有音乐")
	_field("主菜单 BGM 归属=menu", AudioManager.get_music_owner() == &"menu",
		"归属=%s（与主菜单场景不匹配）" % AudioManager.get_music_owner())


# ============================================================================
# E. 转场中途回主菜单（竞态）
# ============================================================================

func _case_transition_cancel() -> void:
	print("")
	print("--- E. 转场途中返回主菜单 ---")
	await _goto_level(&"town")
	# fade_time=0 让转场只由 process_frame 驱动，竞态窗口最窄也最难躲。
	var saved: float = SceneDirector.fade_time
	SceneDirector.fade_time = 0.0
	SceneDirector.change_to_level(&"field", &"from_town")
	await _frames(1)  # 转场已开始、尚未提交新场景
	GameFlow.teardown_to_menu(true)
	for _i: int in 90:
		await get_tree().process_frame
	await _frames(4)

	_field("转场中回菜单：无关卡残挂", SceneDirector.get_current_level() == null,
		"关卡被在途协程挂回：%s" % str(SceneDirector.get_current_level()))
	var scene: Node = SceneDirector.get_current_scene()
	_field("转场中回菜单：场景引用为空", scene == null or not is_instance_valid(scene),
		"场景引用=%s" % str(scene))
	_field("转场中回菜单：BGM 仍是主菜单曲", AudioManager.get_music_owner() == &"menu",
		"BGM 归属=%s（关卡曲被在途协程重新播起）" % AudioManager.get_music_owner())
	_field("转场中回菜单：未处于切换中", not SceneDirector.is_changing(), "仍标记为切换中")
	SceneDirector.fade_time = saved


# ============================================================================
# 工具
# ============================================================================

func _goto_level(level_id: StringName) -> void:
	# 真实流程里主菜单点"新的冒险"后会 queue_free 自己；本套件直接调
	# GameFlow.start_run 绕过了按钮，必须手动把菜单收掉。否则 MainMenu 会
	# 一直盖在关卡上并优先吞掉 Esc（Menu._unhandled_input），导致用例 A 假失败。
	var menu: Node = _root("MainMenu")
	if menu != null:
		menu.queue_free()
		await _frames(2)
	GameFlow.start_run(level_id, &"")
	for _i: int in 200:
		if not SceneDirector.is_changing():
			break
		await get_tree().process_frame
	await _frames(8)


## 收掉所有阻塞窗口 / 对话框 / 暂停令牌，回到"干净可玩"状态。
func _clear_blocking() -> void:
	var pause: Node = _root("PauseMenu")
	if pause != null and pause.has_method(&"close"):
		pause.call("close")
	for n: Node in get_tree().get_nodes_in_group(UIInputRouter.GROUP):
		if n.has_method(&"force_close"):
			n.call(&"force_close")
	PopupManager.release_all()
	var dlg: Node = _root("DialogUI")
	if dlg != null and dlg.has_method(&"close"):
		dlg.call("close")
	PauseManager.clear_all()
	await _frames(3)
	PauseManager.clear_all()


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


func _key(code: int, pressed: bool) -> InputEventKey:
	var ev: InputEventKey = InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	return ev


func _esc() -> InputEventKey:
	return _key(KEY_ESCAPE, true)


func _root(n: String) -> Node:
	# UI 现在可能挂在 Menus/GUI 容器下，不再直属 root；用注册表的递归查找兜底，
	# 这样测试不受容器层级影响（沿用'按名字访问'的旧写法，迁移期无需逐个改路径）。
	return UIRegistry.find_by_name(n)


func _frames(n: int) -> void:
	for _i: int in n:
		await get_tree().process_frame


func _phys(n: int) -> void:
	for _i: int in n:
		await get_tree().physics_frame
