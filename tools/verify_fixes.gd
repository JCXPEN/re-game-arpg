## VerifyFixes —— QA 报告 19 个 Bug 的回归验证
##
## 【负责什么】
##   针对 docs/QA_REPORT.md 里的每个 bug 做一条断言，防止回归。
##   每条都直接检查"修复后的行为"，而不是检查代码长相。
##
## 【怎么运行】
##   Godot --headless --path . res://tools/verify_fixes.tscn
extends Node

# ============================================================================
# 私有变量
# ============================================================================

var _pass: int = 0
var _fail: Array[String] = []

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	GameState.reset_save()
	GameState.start_run()
	_install_ui()
	await get_tree().process_frame
	await _goto(&"field", &"from_town", "Field")

	await _check_01_modifier_choice()
	await _check_02_respawn()
	_check_03_clear_gate()
	await _check_04_roll_charge()
	await _check_05_hud_filter()
	await _check_06_hud_bind()
	await _check_07_aim()
	_check_08_max_health()
	_check_09_scope_filter()
	_check_10_stacking()
	_check_11_duplicate_key()
	await _check_12_charge_reset()
	await _check_13_floating_text()
	await _check_14_15_tutorial()
	await _check_16_camera()
	_check_17_hud_bar_colors()
	_check_19_global_trigger()

	print("")
	print("=== 修复回归验证：%d 通过，%d 失败 ===" % [_pass, _fail.size()])
	for f: String in _fail:
		print("  ✗ ", f)
	get_tree().quit(1 if _fail.size() > 0 else 0)


# ============================================================================
# 检查项
# ============================================================================

## BUG-01：三选一在暂停态仍可交互。
func _check_01_modifier_choice() -> void:
	var ui: Node = get_tree().root.get_node_or_null("ModifierChoice")
	if ui == null:
		_bad("BUG-01 找不到三选一")
		return
	var candidates: Array[ModifierData] = ModifierSystem.roll_candidates(3)
	ui.call("show_choices", candidates)
	await get_tree().process_frame
	var ok: bool = ui.can_process() and bool(ui.get("_active"))
	if ok:
		_ok("BUG-01 三选一在暂停态可交互")
	else:
		_bad("BUG-01 三选一仍软锁 process_mode=%d" % ui.process_mode)
	# 【为什么用 force_close 而不是手动改 visible/_active/paused】
	#   暂停的唯一真相是 PauseManager 的令牌集合。本界面 show_choices 时 freeze 过，
	#   直接写 get_tree().paused = false 会绕过所有权：PauseManager 会在下一帧
	#   立刻把树重新冻住（它仍认为有人要暂停），后续用例全部卡在暂停态。
	#   force_close() 同时收起界面并交还令牌，才是与 freeze 对偶的收尾。
	ui.call("force_close")


## BUG-02：复活落在存档点。
func _check_02_respawn() -> void:
	var ui: Node = get_tree().root.get_node_or_null("GameOverUI")
	if ui == null:
		_bad("BUG-02 找不到 GameOverUI")
		return
	var target: Vector2 = Vector2(1234, 567)
	GameState.set_respawn_point(&"field", target)
	ui.call("_respawn")
	await _wait_idle()
	var p: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
	if p != null and p.global_position.distance_to(target) < 8.0:
		_ok("BUG-02 复活落在存档点 %s" % p.global_position)
	else:
		_bad("BUG-02 复活坐标错误 %s" % (p.global_position if p != null else "null"))


## BUG-03：**零敌人**关卡必须直接算"已清空"，否则 require_clear 的锁门永不开。
## 注意要专门切到城镇（0 敌人）来测——野外有 10 个活着的敌人，is_cleared 本就该是 false。
func _check_03_clear_gate() -> void:
	await _goto(&"town", &"start", "Town")
	var lvl: Node = SceneDirector.get_current_scene()
	var alive: int = int(lvl.call("get_alive_count"))
	var cleared: bool = lvl != null and lvl.has_method("is_cleared") and bool(lvl.call("is_cleared"))
	if alive == 0 and cleared:
		_ok("BUG-03 零敌人关卡 is_cleared=true（城镇）")
	else:
		_bad("BUG-03 零敌人关卡仍锁死（alive=%d cleared=%s）" % [alive, cleared])
	await _goto(&"field", &"from_town", "Field")


## BUG-04：翻滚中不能释放蓄力。
func _check_04_roll_charge() -> void:
	var p: Player = get_tree().get_first_node_in_group(&"player") as Player
	if p == null:
		_bad("BUG-04 找不到玩家")
		return
	var combat: PlayerCombat = p.get_node_or_null("Combat") as PlayerCombat
	var ctrl: AttackController = p.get_node_or_null("AttackController") as AttackController
	if ctrl.is_attacking():
		ctrl.interrupt()
	combat.begin_charge()
	await get_tree().process_frame
	# 直接进入翻滚态，模拟"蓄力中翻滚"。
	p.set("_state", Player.State.ROLL)
	combat.release_charge()
	await get_tree().process_frame
	if not ctrl.is_attacking():
		_ok("BUG-04 翻滚中释放蓄力不出招")
	else:
		_bad("BUG-04 翻滚中仍能白嫖重击")
		p.set("_state", Player.State.IDLE)


## BUG-05：敌人受伤不刷玩家血条。
func _check_05_hud_filter() -> void:
	var hud: Node = get_tree().root.get_node_or_null("HUD")
	if hud == null:
		_bad("BUG-05 找不到 HUD")
		return
	var bar: ProgressBar = hud.get("_health_bar") as ProgressBar
	var dummy: Actor = Actor.new()
	dummy.data = load("res://data/characters/player.tres")
	SceneDirector.get_current_scene().add_child(dummy)
	await get_tree().process_frame
	var before: float = bar.value
	var info: DamageInfo = DamageInfo.new()
	info.amount = 30.0
	dummy.grant_invulnerability(0.0)
	dummy.apply_damage(info)
	await get_tree().process_frame
	if is_equal_approx(bar.value, before):
		_ok("BUG-05 敌人受伤不刷玩家血条")
	else:
		_bad("BUG-05 血条被敌人血量污染 %.1f" % bar.value)
	dummy.queue_free()


## BUG-06：HUD 最终绑定到玩家并建好技能栏。
func _check_06_hud_bind() -> void:
	var hud: Node = get_tree().root.get_node_or_null("HUD")
	if hud == null:
		_bad("BUG-06 找不到 HUD")
		return
	for i: int in 30:
		await get_tree().process_frame
		if hud.get("_player") != null:
			break
	if hud.get("_player") != null:
		_ok("BUG-06 HUD 已绑定玩家")
	else:
		_bad("BUG-06 HUD._player 仍为 null")
	var icons: Array = hud.get("_skill_icons")
	if icons.size() > 0:
		_ok("BUG-06 技能栏有 %d 个图标" % icons.size())
	else:
		_bad("BUG-06 技能栏为空")


## BUG-07：瞄准方向与鼠标世界坐标一致，且基准是**武器的旋转中心**。
##
## 【为什么每轮都重新解析节点】BUG-02 的复活流程是异步的（change_to_level 跨十几帧），
##   可能在本函数执行中途才真正换掉关卡与玩家，旧玩家随之释放。
##   开局取一次引用用到底，第二轮就会对着已释放的实例调方法而报错，
##   整条断言静默失效（历史现象：BUG-07 一行输出都没有，却仍算"通过 17 项"）。
func _check_07_aim() -> void:
	var cam: PlayerCamera = null
	var worst: float = 0.0
	var measured: int = 0
	for pos: Vector2 in [Vector2(320, 40), Vector2(-380, 620), Vector2(1000, 500)]:
		var p: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
		if p == null:
			continue
		if cam == null:
			cam = p.get_node_or_null("Camera2D") as PlayerCamera
			if cam != null:
				cam.clamp_to_bounds = false
				cam.follow_speed = 0.0
		p.global_position = pos
		for i: int in 6:
			await get_tree().physics_frame
		# 重新解析：这 6 帧里玩家可能已被复活流程换掉。
		p = get_tree().get_first_node_in_group(&"player") as Node2D
		if p == null or not is_instance_valid(p):
			continue
		var combat: PlayerCombat = p.get_node_or_null("Combat") as PlayerCombat
		if combat == null or not is_instance_valid(combat):
			continue
		# 参照物：武器实际的旋转中心（不经被测代码取），见 bug_hunt_test 狩猎 2。
		var atk: AttackController = p.get_node_or_null("AttackController") as AttackController
		var weapon: WeaponController = atk.get_weapon() if atk != null else null
		if weapon != null and not is_instance_valid(weapon):
			weapon = null
		var pivot: Vector2 = weapon.global_position if weapon != null else combat._aim_origin()
		var used: Vector2 = combat._aim_direction()
		var correct: Vector2 = (p.get_global_mouse_position() - pivot).normalized()
		if correct == Vector2.ZERO:
			continue
		worst = maxf(worst, absf(rad_to_deg(used.angle_to(correct))))
		measured += 1
	if cam != null and is_instance_valid(cam):
		cam.clamp_to_bounds = true
	# 容差 1.0°：退回"脚底"当基准会稳定偏 ~1.7°，正好被卡住。
	if measured == 0:
		_bad("BUG-07 没能完成瞄准测量（玩家或武器取不到）")
	elif worst < 1.0:
		_ok("BUG-07 瞄准偏差 %.1f°（基准 = 武器旋转中心，%d 次测量）" % [worst, measured])
	else:
		_bad("BUG-07 瞄准偏差 %.1f°（基准应取武器旋转中心，而不是角色脚底）" % worst)


## BUG-08：最大生命词条生效。
func _check_08_max_health() -> void:
	var p: Actor = get_tree().get_first_node_in_group(&"player") as Actor
	ModifierSystem.clear()
	var before: float = p.get_max_health()
	ModifierSystem.add_modifier(DataRegistry.get_modifier(&"m_hp_flat"))
	var after: float = p.get_max_health()
	ModifierSystem.clear()
	if after > before:
		_ok("BUG-08 体魄生效 %.0f → %.0f" % [before, after])
	else:
		_bad("BUG-08 最大生命词条无效")


## BUG-09：限定类词条只对号入座。
func _check_09_scope_filter() -> void:
	var p: Actor = get_tree().get_first_node_in_group(&"player") as Actor
	var combat: PlayerCombat = p.get_node_or_null("Combat") as PlayerCombat
	combat.equip_weapon(DataRegistry.get_weapon(&"sword"))
	ModifierSystem.clear()
	var base: float = p.get_stat(GameEnums.StatKind.ATTACK_POWER, p.get_attack_context())
	ModifierSystem.add_modifier(DataRegistry.get_modifier(&"m_heavy_hitter"))
	var after: float = p.get_stat(GameEnums.StatKind.ATTACK_POWER, p.get_attack_context())
	ModifierSystem.clear()
	if absf(after - base) < 0.001:
		_ok("BUG-09 巨力不对单手剑生效")
	else:
		_bad("BUG-09 巨力越界生效 %.2f → %.2f" % [base, after])


## BUG-10：叠层公式正确。
func _check_10_stacking() -> void:
	var probe: ModifierData = ModifierData.new()
	probe.stat = GameEnums.StatKind.ATTACK_POWER
	probe.op = GameEnums.ModifierOp.FLAT
	probe.value = 10.0
	probe.value_per_stack = 5.0
	ModifierSystem.clear()
	ModifierSystem.add_modifier(probe, &"p")
	ModifierSystem.add_modifier(probe, &"p")
	var two: float = ModifierSystem.apply_stat(0.0, GameEnums.StatKind.ATTACK_POWER)
	ModifierSystem.clear()
	if absf(two - 25.0) < 0.001:
		_ok("BUG-10 叠层公式正确（2 层=25）")
	else:
		_bad("BUG-10 叠层错误 %.1f" % two)


## BUG-11：同名不同源词条各占一条（用两个运行时实例模拟，不依赖特定数据文件）。
func _check_11_duplicate_key() -> void:
	var d1: ModifierData = ModifierData.new()
	d1.display_name = "同名测试"
	d1.stat = GameEnums.StatKind.ATTACK_POWER
	d1.op = GameEnums.ModifierOp.FLAT
	d1.value = 1.0
	var d2: ModifierData = ModifierData.new()
	d2.display_name = "同名测试"
	d2.stat = GameEnums.StatKind.DEFENSE
	d2.op = GameEnums.ModifierOp.FLAT
	d2.value = 2.0
	ModifierSystem.clear()
	ModifierSystem.add_modifier(d1)
	ModifierSystem.add_modifier(d2)
	var n: int = ModifierSystem.get_owned_count()
	ModifierSystem.clear()
	if n == 2:
		_ok("BUG-11 同名不同源词条各占一条")
	else:
		_bad("BUG-11 同名词条被吞（count=%d）" % n)


## BUG-12：取消蓄力后移速复位。
func _check_12_charge_reset() -> void:
	var p: Player = get_tree().get_first_node_in_group(&"player") as Player
	var combat: PlayerCombat = p.get_node_or_null("Combat") as PlayerCombat
	combat.begin_charge()
	for i: int in 30:
		await get_tree().process_frame
	combat.cancel_charge()
	await get_tree().process_frame
	if is_equal_approx(combat.get_move_multiplier(), 1.0):
		_ok("BUG-12 取消蓄力后移速复位")
	else:
		_bad("BUG-12 移速残留 %.3f" % combat.get_move_multiplier())


## BUG-13：飘字按时自毁。
func _check_13_floating_text() -> void:
	var ft: FloatingText = load("res://scenes/ui/floating_text.tscn").instantiate() as FloatingText
	SceneDirector.get_current_scene().add_child(ft)
	ft.setup("1", Color.WHITE)
	await get_tree().create_timer(1.5, true, false, true).timeout
	await get_tree().process_frame
	if not is_instance_valid(ft):
		_ok("BUG-13 飘字按时自毁")
	else:
		_bad("BUG-13 飘字未销毁")


## BUG-14/15：教程在主菜单待命，进关卡才开播。
func _check_14_15_tutorial() -> void:
	GameState.tutorial_completed = false
	TutorialSystem.start_tutorial()
	var running: bool = TutorialSystem.is_running()
	SceneDirector.change_to_level(&"town", &"start")
	await _wait_idle()
	for i: int in 20:
		await get_tree().process_frame
	var idx: int = TutorialSystem.get_current_index()
	if running and idx >= 0:
		_ok("BUG-14/15 教程在主菜单待命、进城镇开播（index=%d）" % idx)
	else:
		_bad("BUG-14/15 教程异常（running=%s idx=%d）" % [running, idx])
	TutorialSystem.skip_tutorial()


## BUG-16：镜头视野不超出地图。
func _check_16_camera() -> void:
	await _goto(&"town", &"start", "Town")
	var p: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
	var cam: PlayerCamera = p.get_node_or_null("Camera2D") as PlayerCamera
	var floor_layer: TileMapLayer = SceneDirector.get_current_scene().get_node("Floor") as TileMapLayer
	var used: Rect2i = floor_layer.get_used_rect()
	var map_rect: Rect2 = Rect2(floor_layer.map_to_local(used.position) - Vector2(8, 8), Vector2(used.size) * 16.0)
	var half: Vector2 = Vector2(320, 180) * 0.5
	var view: Rect2 = Rect2(cam.get_screen_center_position() - half, Vector2(320, 180))
	var outside: float = 0.0
	outside += maxf(0.0, map_rect.position.x - view.position.x)
	outside += maxf(0.0, map_rect.position.y - view.position.y)
	outside += maxf(0.0, view.end.x - map_rect.end.x)
	outside += maxf(0.0, view.end.y - map_rect.end.y)
	if outside < 1.0:
		_ok("BUG-16 镜头视野始终在地图内")
	else:
		_bad("BUG-16 视野超出地图 %.0f px" % outside)


## BUG-17：血条底槽与填充颜色不同。
func _check_17_hud_bar_colors() -> void:
	var hud: Node = get_tree().root.get_node_or_null("HUD")
	if hud == null:
		_bad("BUG-17 找不到 HUD")
		return
	var bar: ProgressBar = hud.get("_health_bar") as ProgressBar
	var bg: StyleBoxFlat = bar.get_theme_stylebox("background") as StyleBoxFlat
	var fill: StyleBoxFlat = bar.get_theme_stylebox("fill") as StyleBoxFlat
	if bg != null and fill != null and not bg.bg_color.is_equal_approx(fill.bg_color):
		_ok("BUG-17 血条底槽与填充颜色不同")
	else:
		_bad("BUG-17 血条背景与填充同色")


## BUG-19：全局规则词条只在残血时触发。
func _check_19_global_trigger() -> void:
	var p: Actor = get_tree().get_first_node_in_group(&"player") as Actor
	ModifierSystem.clear()
	ModifierSystem.add_modifier(DataRegistry.get_modifier(&"m_blood_rage"))
	p.heal(p.get_max_health())
	var ctx_full: Dictionary = (p as Player).get_attack_context()
	var has_full: bool = ctx_full.get(&"trigger", &"") == &"low_health"
	p.grant_invulnerability(0.0)
	p.apply_damage(_dmg(p.get_max_health() * 0.7))
	var ctx_low: Dictionary = (p as Player).get_attack_context()
	var has_low: bool = ctx_low.get(&"trigger", &"") == &"low_health"
	ModifierSystem.clear()
	if not has_full and has_low:
		_ok("BUG-19 嗜血狂怒仅在残血时触发")
	else:
		_bad("BUG-19 触发条件异常 full=%s low=%s" % [has_full, has_low])


# ============================================================================
# 工具
# ============================================================================

func _ok(label: String) -> void:
	_pass += 1
	print("  [PASS] ", label)


func _bad(label: String) -> void:
	_fail.append(label)
	print("  [FAIL] ", label)


func _dmg(amount: float) -> DamageInfo:
	var info: DamageInfo = DamageInfo.new()
	info.amount = amount
	return info


## 切到指定关卡并等切换完成。
func _goto(level_id: StringName, entry: StringName, expected: String) -> void:
	SceneDirector.change_to_level(level_id, entry)
	await _wait_idle()
	var scene: Node = SceneDirector.get_current_scene()
	if scene == null or scene.name != expected:
		push_warning("[VerifyFixes] 期望 %s，实际 %s" % [expected, scene.name if scene != null else "<null>"])


## 等场景切换结束。
func _wait_idle() -> void:
	for i: int in 150:
		await get_tree().process_frame
		if not SceneDirector.is_changing():
			break
	for i: int in 8:
		await get_tree().process_frame


func _install_ui() -> void:
	for path: String in [
		"res://scenes/ui/hud.tscn", "res://scenes/ui/tutorial_ui.tscn",
		"res://scenes/ui/modifier_choice.tscn", "res://scenes/ui/game_over.tscn",
	]:
		var n: Node = load(path).instantiate()
		get_tree().root.add_child.call_deferred(n)
