## UIRegistryTest —— 场景树容器 + UI 注册表契约
##
## 【负责什么】
##   钉死阶段 2 引入的"按关系组织场景树"的契约：
##     A. 容器存在且归属正确：Boot 下建立 World / GUI / Menus。
##     B. 关卡挂进 World，窗口挂进 GUI / Menus，**不再平铺在 root 下**。
##     C. 注册表按 id 取窗口；同名窗口全局唯一；节点被释放后查询返回 null 并自清理。
##     D. 注册表未装配时（测试直接调用）能安全回退到 root。
##
## 【怎么运行】Godot --headless --path . res://tools/ui_registry_test.tscn
extends Node

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []

func _ready() -> void:
	print("")
	print("################################################")
	print("#  UIRegistry / 场景树容器契约")
	print("################################################")
	await get_tree().process_frame
	var boot: Node = load("res://scenes/core/boot.tscn").instantiate()
	boot.name = "Boot"
	boot.set("show_menu", true)
	get_tree().root.add_child.call_deferred(boot)
	await _frames(12)

	await _test_containers_exist()
	await _test_windows_in_containers()
	await _test_level_in_world()
	await _test_registry_unique()
	await _test_registry_autoclean()
	await _test_fallback_parent()

	print("")
	print("################################################")
	print("# UIRegistry 契约：%d 通过，%d 失败" % [_pass, _fail])
	for f: String in _fails:
		print("  - " + f)
	print("################################################")
	get_tree().quit(1 if _fail > 0 else 0)


## A. Boot 下建立了三个容器，且 UIRegistry 持有它们。
func _test_containers_exist() -> void:
	print("")
	print("--- A. 容器存在 ---")
	var boot: Node = get_tree().root.get_node_or_null(NodePath("Boot"))
	_field("Boot 存在", boot != null, "没有 Boot")
	_field("Boot 下有 World", boot != null and boot.get_node_or_null("World") != null, "缺 World")
	_field("Boot 下有 GUI", boot != null and boot.get_node_or_null("GUI") != null, "缺 GUI")
	_field("Boot 下有 Menus", boot != null and boot.get_node_or_null("Menus") != null, "缺 Menus")
	_field("UIRegistry 已注册容器", UIRegistry.world != null and UIRegistry.gui != null and UIRegistry.menus != null,
		"容器未 attach 到注册表")
	# root 直属子节点里**不该**再出现平铺的 HUD/菜单（它们应归容器）。
	var flat: Array[String] = []
	for c: Node in get_tree().root.get_children():
		var n: String = str(c.name)
		if n in ["HUD", "BossHealthBar", "TutorialUI", "DialogUI", "PauseMenu", "GameOverUI", "MainMenu"]:
			flat.append(n)
	_field("常驻 UI 不再平铺在 root 下", flat.is_empty(), "仍平铺在 root：%s" % str(flat))


## B. 常驻窗口挂在 GUI / Menus 容器下。
func _test_windows_in_containers() -> void:
	print("")
	print("--- B. 窗口归属容器 ---")
	var hud: Node = UIRegistry.find_by_name("HUD")
	var boss: Node = UIRegistry.find_by_name("BossHealthBar")
	var pause: Node = UIRegistry.find_by_name("PauseMenu")
	_field("HUD 找到", hud != null, "HUD 缺失")
	_field("Boss 血条找到", boss != null, "BossHealthBar 缺失")
	_field("暂停菜单找到", pause != null, "PauseMenu 缺失")
	_field("HUD 挂在 GUI 容器下", hud != null and hud.get_parent() == UIRegistry.gui_container(),
		"HUD 父节点=%s" % (str(hud.get_parent().name) if hud != null else "-"))
	_field("Boss 血条挂在 GUI 容器下", boss != null and boss.get_parent() == UIRegistry.gui_container(),
		"Boss 父节点=%s" % (str(boss.get_parent().name) if boss != null else "-"))
	_field("暂停菜单挂在 Menus 容器下", pause != null and pause.get_parent() == UIRegistry.menus_container(),
		"暂停父节点=%s" % (str(pause.get_parent().name) if pause != null else "-"))


## C. 关卡实例挂进 World 容器。
func _test_level_in_world() -> void:
	print("")
	print("--- C. 关卡归属 World ---")
	GameFlow.start_run(&"town", &"start")
	await _wait_idle()
	var scene: Node = SceneDirector.get_current_scene()
	_field("关卡已加载", scene != null, "没有当前关卡")
	_field("关卡挂在 World 容器下", scene != null and scene.get_parent() == UIRegistry.level_parent(),
		"关卡父节点=%s（应为 World）" % (str(scene.get_parent().name) if scene != null and scene.get_parent() != null else "-"))
	_field("AI/HUD 不受换关影响：HUD 仍在 GUI 下",
		UIRegistry.find_by_name("HUD") != null and UIRegistry.find_by_name("HUD").get_parent() == UIRegistry.gui_container(),
		"换关后 HUD 归属变了")


## D. 注册表按 id 唯一，且 find_by_name 递归兜底。
func _test_registry_unique() -> void:
	print("")
	print("--- D. 注册表查询 ---")
	# 从暂停菜单打开设置两次，必须拿到同一实例。
	var pause: Node = UIRegistry.find_by_name("PauseMenu")
	pause.call("_open_settings")
	await _frames(3)
	var a: Node = UIRegistry.window_for(&"settings")
	_field("设置登记进注册表", a != null, "settings 未登记")
	if pause != null:
		UIRegistry.window_for(&"settings").call("close")
	await _frames(2)
	pause.call("_open_settings")
	await _frames(3)
	var b: Node = UIRegistry.window_for(&"settings")
	_field("两次打开是同一实例", a == b, "出现多个设置实例")
	# find_by_name 应能通过注册表命中（甚至递归兜底）。
	_field("find_by_name 命中设置", UIRegistry.find_by_name("SettingsPanel") == b,
		"find_by_name 返回 %s" % str(UIRegistry.find_by_name("SettingsPanel")))
	var ids: Array = UIRegistry.registered_ids()
	_field("注册表含关键 id", ids.has(&"hud") and ids.has(&"pause_menu") and ids.has(&"settings"),
		"已登记：%s" % str(ids))
	if b != null and b.has_method(&"close"):
		b.call("close")
	await _frames(2)


## E. 节点释放后查询自动返回 null 并清理登记。
func _test_registry_autoclean() -> void:
	print("")
	print("--- E. 释放自清理 ---")
	var probe: Node = Node.new()
	probe.name = "ProbeWindow"
	get_tree().root.add_child(probe)
	UIRegistry.register(&"probe", probe)
	_field("登记后可查到", UIRegistry.window_for(&"probe") == probe, "查不到")
	probe.free()
	await _frames(1)
	_field("节点释放后查询返回 null", UIRegistry.window_for(&"probe") == null,
		"仍返回已释放节点")
	_field("释放后登记被清理", not UIRegistry.registered_ids().has(&"probe"),
		"登记未被清理")


## F. 未装配容器时安全回退 root（测试常直接调 SceneDirector）。
func _test_fallback_parent() -> void:
	print("")
	print("--- F. 无容器回退 ---")
	# 保存并临时清空容器，模拟"Boot 未装配"。
	var saved_world: Node2D = UIRegistry.world
	var saved_gui: Node = UIRegistry.gui
	UIRegistry.world = null
	UIRegistry.gui = null
	_field("level_parent 在无 World 时回退 root",
		UIRegistry.level_parent() == get_tree().root,
		"回退失败：%s" % str(UIRegistry.level_parent()))
	_field("gui_container 在无 GUI 时回退 root",
		UIRegistry.gui_container() == get_tree().root, "回退失败")
	UIRegistry.world = saved_world
	UIRegistry.gui = saved_gui
	_field("恢复容器后 level_parent 正确", UIRegistry.level_parent() != get_tree().root,
		"未恢复")


# ============================================================================
# 工具
# ============================================================================

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


func _wait_idle() -> void:
	for _i: int in 200:
		if not SceneDirector.is_changing():
			break
		await get_tree().process_frame
	await _frames(8)


func _frames(n: int) -> void:
	for _i: int in n:
		await get_tree().process_frame
