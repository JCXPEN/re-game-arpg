## AuditFound —— 本轮代码审计发现的缺陷定点复现
##
## 【怎么运行】
##   Godot --headless --path . res://tools/audit_found_test.tscn
##
## 【目的】
##   把审计中通过"读代码"推断出的缺陷变成可复现的红/绿用例，避免只凭推理下结论。
##   每项都会打印 [OK] / [BUG]，末尾汇总。
##
## 【写法注意】
##   GDScript 的 lambda 对局部变量是**值捕获**，在 lambda 里改 `var flag := false`
##   改不出去。所有跨回调传递的结果一律用 `Array` 装箱。
extends Node

var _bugs: Array[String] = []
var _oks: Array[String] = []


func _ready() -> void:
	print("")
	print("############ 审计定点复现 ############")
	await _check_main_menu_help_button()
	await _check_main_menu_settings_button()
	await _check_main_menu_new_game()
	await _check_scene_director_missing_await()
	await _check_pause_menu_self_free()
	await _check_game_over_self_free()
	await _check_tutorial_wrong_level()
	_report()
	get_tree().quit(0)


# ----------------------------------------------------------------------------
# 工具
# ----------------------------------------------------------------------------

func _frames(n: int) -> void:
	for _i: int in n:
		await get_tree().process_frame


## 安全挂载：root 可能正处于 busy 状态，统一走 call_deferred。
func _mount(node: Node) -> void:
	get_tree().root.add_child.call_deferred(node)
	await _frames(3)


func _find(root: Node, node_name: String) -> Node:
	return root.find_child(node_name, true, false)


## 取节点的 visible，对 null / 已释放一律安全返回 false。
## 注意 CanvasLayer **不是** CanvasItem 的子类，不能 as CanvasItem，
## 只能用属性名读（HelpPanel / SettingsPanel 的根节点都是 CanvasLayer）。
func _visible_of(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	return bool(node.get("visible"))


func _child_names(root: Node) -> String:
	var names: Array[String] = []
	for child: Node in root.get_children():
		names.append("%s(%s)" % [child.name, child.get_class()])
	return ", ".join(names)


func _check(condition: bool, ok_label: String, bug_label: String) -> void:
	if condition:
		_oks.append(ok_label)
		print("  [OK]  ", ok_label)
	else:
		_bugs.append(bug_label)
		print("  [BUG] ", bug_label)


# ----------------------------------------------------------------------------
# 定点 1：主菜单「操作说明」按钮
# ----------------------------------------------------------------------------

func _check_main_menu_help_button() -> void:
	print("")
	print("--- 定点 1：主菜单「操作说明」按钮 ---")
	var menu: Node = load("res://scenes/ui/main_menu.tscn").instantiate()
	menu.name = "MainMenu"
	await _mount(menu)
	var btn: Button = menu.find_child("btn_help", true, false) as Button
	if btn == null:
		print("    找不到 btn_help，跳过")
		menu.queue_free()
		await _frames(2)
		return

	btn.pressed.emit()
	await _frames(3)
	var panel: Node = _find(get_tree().root, "HelpPanel")
	var first: bool = _visible_of(panel)
	print("    第 1 次点击：面板存在=%s 可见=%s" % [panel != null, first])
	print("    root 子节点：%s" % _child_names(get_tree().root))

	btn.pressed.emit()
	await _frames(3)
	var second: bool = _visible_of(panel)
	print("    第 2 次点击：面板可见=%s" % second)

	_check(first,
		"「操作说明」第 1 次点击就弹出面板",
		"「操作说明」第 1 次点击无反应（实测 first=%s second=%s）："
			% [first, second]
			+ "MainMenu._open_help() 只 instantiate + add_child，"
			+ "而 HelpPanel._ready() 末尾有 `visible = false` 且从不调用 open()；"
			+ "第 2 次点击走的是 `if _help_panel != null: visible = true` 分支才显示。")
	if panel != null:
		panel.queue_free()
	menu.queue_free()
	await _frames(2)


# ----------------------------------------------------------------------------
# 定点 2：主菜单「设置」按钮
# ----------------------------------------------------------------------------

func _check_main_menu_settings_button() -> void:
	print("")
	print("--- 定点 2：主菜单「设置」按钮 ---")
	var menu: Node = load("res://scenes/ui/main_menu.tscn").instantiate()
	menu.name = "MainMenu"
	await _mount(menu)
	var btn: Button = menu.find_child("btn_settings", true, false) as Button
	if btn == null:
		print("    找不到 btn_settings，跳过")
		menu.queue_free()
		await _frames(2)
		return

	btn.pressed.emit()
	await _frames(3)
	var panel: Node = _find(get_tree().root, "SettingsPanel")
	var first: bool = _visible_of(panel)
	print("    第 1 次点击：面板存在=%s 可见=%s" % [panel != null, first])

	btn.pressed.emit()
	await _frames(3)
	var second: bool = _visible_of(panel)
	print("    第 2 次点击：面板可见=%s" % second)

	_check(first,
		"「设置」第 1 次点击就弹出面板",
		"「设置」第 1 次点击无反应（实测 first=%s second=%s）："
			% [first, second]
			+ "MainMenu._open_settings() 同样没有调用 SettingsPanel.open()。")
	if panel != null:
		panel.queue_free()
	menu.queue_free()
	await _frames(2)


# ----------------------------------------------------------------------------
# 定点 3：主菜单「新的冒险」（对照组）
# ----------------------------------------------------------------------------

func _check_main_menu_new_game() -> void:
	print("")
	print("--- 定点 3：主菜单「新的冒险」（对照组）---")
	GameState.reset_save()
	var menu: Node = load("res://scenes/ui/main_menu.tscn").instantiate()
	menu.name = "MainMenu"
	await _mount(menu)
	var btn: Button = menu.find_child("btn_new_game", true, false) as Button
	if btn == null:
		print("    找不到 btn_new_game，跳过")
		menu.queue_free()
		await _frames(2)
		return
	btn.pressed.emit()
	await _frames(60)
	var scene: Node = SceneDirector.get_current_scene()
	_check(scene != null and scene.is_inside_tree(),
		"「新的冒险」能正常进入关卡并挂上场景树",
		"「新的冒险」没能进入关卡（current_scene=%s）" % scene)


# ----------------------------------------------------------------------------
# 定点 4：SceneDirector.change_to_level 未 await _swap_scene
# ----------------------------------------------------------------------------

func _check_scene_director_missing_await() -> void:
	print("")
	print("--- 定点 4：change_to_level 是否等场景替换完成 ---")
	var old_fade: float = SceneDirector.fade_time
	SceneDirector.fade_time = 0.0

	# Array 装箱：GDScript 的 lambda 对局部变量是值捕获，用 bool 改不出去。
	var got: Array = [false, ""]  # [是否收到 scene_changed, 当前关卡 id]
	var cb: Callable = func(_n: Node) -> void:
		got[0] = true
	EventBus.scene_changed.connect(cb)

	await SceneDirector.change_to_level(&"field", &"from_town")

	var lvl: LevelData = SceneDirector.get_current_level()
	got[1] = lvl.id if lvl != null else "<null>"
	var settled: bool = got[0] and got[1] == "field"
	print("    change_to_level 已返回：scene_changed 已发出=%s，当前关卡=%s" % [got[0], got[1]])
	_check(settled,
		"change_to_level 返回时场景已替换完成且 scene_changed 已发出",
		"change_to_level 在场景替换完成前就返回了（scene_changed 已发出=%s，当前关卡=%s）："
			% [got[0], got[1]]
			+ "`_swap_scene()` 内含两处 `await get_tree().process_frame` 却是**未加 await 的裸调用**，"
			+ "于是 `_fade_in()` 与 `_changing = false` 都抢在换场景之前执行。"
			+ "默认 fade_time=0.18s 时靠时间差侥幸掩盖；一旦把转场时长配成 0，"
			+ "`await change_to_level()` 拿到的就是一个还没入树的空场景，"
			+ "且 `_changing` 提前复位会放行并发切换——这与函数上方注释声明的"
			+ "『无论发生什么都要把 _changing 复位』的意图恰好相反。")
	EventBus.scene_changed.disconnect(cb)
	SceneDirector.fade_time = old_fade
	await _frames(30)


# ----------------------------------------------------------------------------
# 定点 5：暂停菜单「返回主菜单」
# ----------------------------------------------------------------------------

func _check_pause_menu_self_free() -> void:
	print("")
	print("--- 定点 5：暂停菜单「返回主菜单」是否销毁常驻 PauseMenu ---")
	var pm: Node = load("res://scenes/ui/pause_menu.tscn").instantiate()
	pm.name = "PauseMenu"
	await _mount(pm)
	var btn: Button = pm.find_child("btn_main_menu", true, false) as Button
	if btn == null:
		print("    找不到 btn_main_menu，跳过")
		pm.queue_free()
		await _frames(2)
		return
	btn.pressed.emit()
	await _frames(5)
	var freed: bool = not is_instance_valid(pm) or pm.is_queued_for_deletion()
	print("    PauseMenu 已自我销毁=%s" % freed)
	_check(not freed,
		"PauseMenu 是 Boot 常驻层，返回主菜单后仍然存在",
		"PauseMenu._go_main_menu() 末尾调用 `queue_free()` 把**自己**（Boot 挂载的常驻层）"
			+ "也销毁了：返回主菜单后再开新游戏，Esc 暂停菜单永久失效，且 Boot 不会重建。")
	if not freed:
		pm.queue_free()
	var spawned: Node = get_tree().root.get_node_or_null("MainMenu")
	if spawned != null:
		spawned.queue_free()
	await _frames(2)


# ----------------------------------------------------------------------------
# 定点 6：死亡结算「返回主菜单」
# ----------------------------------------------------------------------------

func _check_game_over_self_free() -> void:
	print("")
	print("--- 定点 6：死亡/通关界面「返回主菜单」是否销毁常驻 GameOverUI ---")
	var go: Node = load("res://scenes/ui/game_over.tscn").instantiate()
	go.name = "GameOverUI"
	await _mount(go)
	var btn: Button = go.find_child("btn_main_menu", true, false) as Button
	if btn == null:
		print("    找不到 btn_main_menu，跳过")
		go.queue_free()
		await _frames(2)
		return
	btn.pressed.emit()
	await _frames(5)
	var freed: bool = not is_instance_valid(go) or go.is_queued_for_deletion()
	print("    GameOverUI 已自我销毁=%s" % freed)
	_check(not freed,
		"GameOverUI 是 Boot 常驻层，返回主菜单后仍然存在",
		"GameOverUI._go_main_menu() 末尾同样 `queue_free()` 销毁自身（Boot 常驻层）："
			+ "返回主菜单后再开新游戏，玩家死亡 / 击败 Boss 时结算界面再也不会出现，"
			+ "游戏进入『死亡但没有任何 UI』的死局。")
	if not freed:
		go.queue_free()
	var spawned: Node = get_tree().root.get_node_or_null("MainMenu")
	if spawned != null:
		spawned.queue_free()
	await _frames(2)


# ----------------------------------------------------------------------------
# 定点 7：教程步骤是否在错误的关卡弹出
# ----------------------------------------------------------------------------

func _check_tutorial_wrong_level() -> void:
	print("")
	print("--- 定点 7：教程步骤是否会播在非目标关卡 ---")
	# 清掉历史状态，回到"刚开新档"的干净起点。
	TutorialSystem.skip_tutorial()
	GameState.tutorial_completed = false
	GameState.save_game()
	TutorialSystem.start_tutorial()
	await SceneDirector.change_to_level(&"town", &"start")
	await _frames(60)

	# 把 town 的 3 步全部手动跳过，让待播步骤指向 field 的 step_010。
	for _i: int in 4:
		if not TutorialSystem.is_running():
			break
		TutorialSystem.dismiss_current_step()
		await _frames(3)
	var pending_index: int = TutorialSystem.get_current_index()
	print("    跳过城镇步骤后，待播步骤 index=%d" % pending_index)

	var shown: Array = [false, ""]  # [是否弹出, 标题]
	var cb: Callable = func(_i: int, title: String, _t: String, _c: bool) -> void:
		if title.strip_edges() != "":
			shown[0] = true
			shown[1] = title
	EventBus.tutorial_step_shown.connect(cb)

	# 切到一个**不是**该步骤目标关卡的场景（Boss 房）。
	await SceneDirector.change_to_level(&"boss_room", &"start")
	await _frames(60)
	EventBus.tutorial_step_shown.disconnect(cb)

	print("    切到 boss_room 后弹出的教程标题：%s" % shown[1])
	_check(not shown[0],
		"非目标关卡切换不会误弹其它关卡的教程",
		"切到 boss_room 却弹出了属于其它关卡的教程「%s」："
			% shown[1]
			+ "TutorialSystem._on_scene_changed() 直接 `_show_step(_steps[_index])`，"
			+ "**没有**像 _try_start_next() 那样先过 `_step_matches_level()`，"
			+ "导致 level_id 过滤在这个入口完全失效。")
	TutorialSystem.skip_tutorial()


func _report() -> void:
	var total: int = _bugs.size() + _oks.size()
	print("")
	print("############################################")
	print("审计定点复现：%d 项，复现 %d 个问题" % [total, _bugs.size()])
	var i: int = 1
	for b: String in _bugs:
		print("  %d. %s" % [i, b])
		i += 1
	print("############################################")
