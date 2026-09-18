## BugHuntTest —— 运行时缺陷狩猎（动态测试）
##
## 【负责什么】
##   静态审查只能发现"看起来像 bug"的代码。本脚本把它们放到**真实运行的游戏**里跑一遍，
##   用可观测的结果判定：到底是不是 bug、能不能复现、影响面多大。
##
## 【怎么运行】
##   Godot --headless --path . res://tools/bug_hunt_test.tscn
##
## 【判定口径】
##   每项检查都模拟一次真实玩家行为（而不是直接读变量），
##   输出 [BUG] 表示"复现成功"，[OK] 表示"该假设不成立"。
extends Node

# ============================================================================
# 私有变量
# ============================================================================

var _bugs: Array[String] = []
var _oks: Array[String] = []
var _checks: int = 0

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	print("")
	print("############ 运行时缺陷狩猎 ############")
	GameState.reset_save()
	_install_persistent_ui()
	# 复刻真实流程：先看主菜单停留若干秒，再点"新的冒险"进关卡。
	# 这一步很关键——真实玩家不会在 0.1 秒内点开始，菜单停留期间 HUD 早已完成初始化。
	for i: int in 30:
		await get_tree().process_frame
	GameState.start_run()
	SceneDirector.change_to_level(&"town", &"start")
	for i: int in 45:
		await get_tree().process_frame

	await _hunt_ui_binding()
	await _hunt_scene_director_liveness()
	await _hunt_aim_direction()
	await _hunt_stat_modifiers()
	await _hunt_weapon_element_modifiers()
	await _hunt_modifier_stacking()
	await _hunt_charge_state_leak()
	await _hunt_roll_attack_override()
	await _hunt_modifier_choice_softlock()
	await _hunt_projectile_repeat_hit()
	await _hunt_clear_gate_without_enemies()
	await _hunt_respawn_position()
	await _hunt_friendly_fire()
	await _hunt_flash_leak()
	await _hunt_missing_reference_edges()

	_report()
	get_tree().quit(0)


# ============================================================================
# 狩猎 1：HUD 是否真的绑到了玩家身上
# ============================================================================

func _hunt_ui_binding() -> void:
	print("")
	print("--- 狩猎 1：HUD 绑定时机 ---")
	var hud: Node = get_tree().root.get_node_or_null("HUD")
	if hud == null:
		_bug("HUD 常驻层不存在")
		return
	var bound: Variant = hud.get("_player")
	_check(bound != null, "HUD 绑定了玩家引用",
		"HUD._player 仍为 null（HUD 在开场就完成初始化，那时玩家还没生成，之后再无重试）")
	var icons: Array = hud.get("_skill_icons")
	_check(icons.size() > 0, "HUD 技能栏已生成图标（%d 个）" % icons.size(),
		"HUD 技能栏为空（技能/法术永远没有图标，冷却遮罩也不更新）")
	if bound != null:
		return

	# _player 为 null 时，HUD 的过滤条件 `if _player != null and unit != _player` 会被绕过，
	# 于是任何单位的血量都会写进玩家的血条。
	var hp_bar: ProgressBar = hud.get("_health_bar") as ProgressBar
	var player: Actor = get_tree().get_first_node_in_group(&"player") as Actor
	if hp_bar == null or player == null:
		return
	var enemy: Actor = null
	for n: Node in get_tree().get_nodes_in_group(&"enemy"):
		enemy = n as Actor
		if enemy != null:
			break
	if enemy == null:
		# 城镇没刷怪，临时放一个假想受击体来验证同一条 EventBus 通路。
		var extra: Actor = Actor.new()
		extra.name = "ProbeDummy"
		extra.data = load("res://data/characters/player.tres")
		get_tree().current_scene.add_child(extra)
		await get_tree().process_frame
		enemy = extra
	var bar_before: float = hp_bar.value
	var info: DamageInfo = DamageInfo.new()
	info.amount = 12.0
	info.source = null
	enemy.grant_invulnerability(0.0)
	enemy.apply_damage(info)
	await get_tree().process_frame
	print("    打敌人一刀后：玩家血量=%.1f，HUD 血条=%.1f（打之前 %.1f）" % [
		player.get_health(), hp_bar.value, bar_before])
	_check(absf(hp_bar.value - player.get_health()) < 0.5, "HUD 血条显示玩家血量",
		"玩家满血 %s，HUD 血条却变成 %s —— 它显示的是刚被打的那个敌人的血量"
		% [player.get_health(), hp_bar.value])


# ============================================================================
# 狩猎 1b：SceneDirector 会不会卡在 _changing（场景切换软锁）
# ============================================================================

func _hunt_scene_director_liveness() -> void:
	print("")
	print("--- 狩猎 1b：连续切换场景是否可靠 ---")
	# 【为什么先等启动转场结束】change_to_level 在 _changing 为 true 时会静默丢弃
	#   本次请求。开场的 town 转场含淡出+换场景+淡入，帧数不固定（受帧率影响），
	#   固定等 45 帧可能刚好落在它尚未归位时，于是第一条 field 请求被丢掉 ——
	#   那是**测试的时序假设**，不是产品缺陷。这里显式等到转场归位再开始。
	await _wait_scene_idle()
	var order: Array[StringName] = [&"field", &"dungeon_1", &"dungeon_2", &"boss_room", &"town"]
	for dest: StringName in order:
		var before_name: String = SceneDirector.get_current_scene().name if SceneDirector.get_current_scene() != null else "<无>"
		SceneDirector.change_to_level(dest, &"")
		# 同样按"转场是否结束"来等，而不是拍一个固定帧数：转场时长由 fade_time
		# 决定，固定帧数会在慢帧/无淡屏配置下误判。上限用于兜底软锁（真卡死时
		# is_changing 永不归零，最终仍会失败）。
		var waited: bool = await _wait_scene_idle(400)
		var now_scene: Node = SceneDirector.get_current_scene()
		var arrived: bool = now_scene != null and now_scene.name.to_lower().begins_with(String(dest).substr(0, 4))
		print("    切→%s：当前场景=%s，is_changing()=%s，按时归位=%s" % [
			dest, now_scene.name if now_scene != null else "<无>", SceneDirector.is_changing(), waited])
		_check(arrived, "切换到 %s 成功" % dest,
			"切换到 %s 失败：仍停在 %s（change_to_level 被 _changing 静默丢弃或淡流程未归还）" % [dest, before_name])
		_check(not SceneDirector.is_changing(), "%s 切换完成后 _changing 已复位" % dest,
			"%s 切换后 _changing 仍为 true：之后所有场景切换都会被静默吞掉（不可逆软锁）" % dest)
		if SceneDirector.is_changing():
			break


## 等场景转场结束。返回 true=在帧数上限内归位，false=疑似软锁。
func _wait_scene_idle(max_frames: int = 90) -> bool:
	for i: int in max_frames:
		if not SceneDirector.is_changing():
			# 多等几帧让新场景的 _ready / 玩家生成落定。
			for j: int in 6:
				await get_tree().process_frame
			return true
		await get_tree().process_frame
	return not SceneDirector.is_changing()


# ============================================================================
# 狩猎 2：鼠标瞄准的坐标系
# ============================================================================

func _hunt_aim_direction() -> void:
	print("")
	print("--- 狩猎 2：鼠标瞄准坐标系 ---")
	var player: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
	if player == null:
		_bug("找不到玩家")
		return
	# 必须调用**真实的**瞄准函数，而不是在测试里重抄一份表达式——
	# 否则测试只会验证自己抄的那份代码，与被测实现脱节。
	var combat: PlayerCombat = player.get_node_or_null("Combat") as PlayerCombat
	if combat == null:
		_bug("找不到 PlayerCombat")
		return
	var origin: Vector2 = player.global_position
	var viewport: Viewport = get_viewport()
	var cam: PlayerCamera = viewport.get_camera_2d() as PlayerCamera
	print("    视口 %s，摄像机 zoom=%s" % [viewport.get_visible_rect().size, _camera_zoom()])
	# 隔离变量：临时关掉边界钳制，让镜头严格居中玩家，这样"正确方向"有唯一解析解，
	# 剩下的差异就纯粹来自坐标系混用。
	if cam != null:
		cam.clamp_to_bounds = false
		cam.follow_speed = 0.0
		cam.look_ahead_max = 0.0

	# 参照物：**武器实际的旋转中心**。角色原点是脚底，武器挂在 WeaponMount(y = -6)
	# 上、绕挂载点转，两者差 6px —— 瞄准角必须从后者算起。
	# 这里直接从武器实例取，不经被测代码，这样"基准点用错了"才会真的被逮到。
	var atk: AttackController = player.get_node_or_null("AttackController") as AttackController
	var weapon: WeaponController = atk.get_weapon() if atk != null else null

	# 玩家站在地图上不同位置、鼠标一动不动：瞄准方向本应完全相同。
	var worst_angle: float = 0.0
	var worst_at: Vector2 = Vector2.ZERO
	var probes: Array[Vector2] = [
		Vector2(320.0, 40.0), Vector2(1000.0, 500.0),
		Vector2(-380.0, 620.0), Vector2(760.0, -240.0), Vector2(96.0, 96.0),
	]
	for p: Vector2 in probes:
		player.global_position = p
		for i: int in 6:
			await get_tree().physics_frame
		# —— 调用 PlayerCombat 的真实实现 ——
		var used: Vector2 = combat._aim_direction()
		# —— 正确做法：鼠标世界坐标（Camera2D 逆变换） − 武器旋转中心 ——
		var world_mouse: Vector2 = player.get_global_mouse_position()
		var pivot: Vector2 = weapon.global_position if weapon != null else combat._aim_origin()
		var correct: Vector2 = (world_mouse - pivot).normalized()
		if correct == Vector2.ZERO:
			continue
		var ang: float = rad_to_deg(used.angle_to(correct))
		if absf(ang) > absf(worst_angle):
			worst_angle = ang
			worst_at = p
		print("    玩家%s（镜头%s）：代码方向%s，真实方向%s，偏差 %.1f°" % [
			_fmt_vec(p), _fmt_vec(cam.global_position) if cam != null else "?",
			_fmt_vec(used), _fmt_vec(correct), ang])
	player.global_position = origin
	if cam != null:
		cam.clamp_to_bounds = true

	# 容差 1.0°：基准点若退回"角色原点（脚底）"，与武器旋转中心(WeaponMount)差 6px，
	# 在本测试的鼠标距离（~183px）下会稳定产生 ~1.7° 偏差 —— 正好被这条卡住。
	_check(absf(worst_angle) < 1.0, "鼠标瞄准方向以武器旋转锚点为基准（最大偏差 %.1f°）" % worst_angle,
		"瞄准方向最大偏差 %.1f°（玩家走到 %s 时）：基准点没取到武器的旋转中心。"
			% [worst_angle, _fmt_vec(worst_at)]
		+ "角色原点是脚底，武器挂在 WeaponMount(y = -6) 上、绕挂载点旋转；"
		+ "用脚底算角度，鼠标离得越近偏得越多（离 30px 时约 11°），刀尖与判定盒都指不到鼠标")


# ============================================================================
# 狩猎 3：最大生命 / 最大法力 / 回蓝 词条是否真的生效
# ============================================================================

func _hunt_stat_modifiers() -> void:
	print("")
	print("--- 狩猎 3：属性类词条是否真的生效 ---")
	ModifierSystem.clear()
	var player: Actor = get_tree().get_first_node_in_group(&"player") as Actor
	if player == null:
		_bug("找不到玩家")
		return

	var hp_before: float = player.get_max_health()
	var hp_mod: ModifierData = DataRegistry.get_modifier(&"m_hp_flat")
	_check(hp_mod != null, "能查到 m_hp_flat（体魄）", "查不到 m_hp_flat")
	if hp_mod != null:
		ModifierSystem.add_modifier(hp_mod)
		var hp_after: float = player.get_max_health()
		_check(hp_after > hp_before, "「体魄：最大生命 +15」生效",
			"选了体魄后最大生命仍是 %.0f（词条无效，2 个生命词条全是摆设）" % hp_after)
		print("    get_stat(MAX_HEALTH)=%.1f  vs  Actor.get_max_health()=%.1f" % [
			player.get_stat(GameEnums.StatKind.MAX_HEALTH), hp_after])

	ModifierSystem.clear()
	var mp_mod: ModifierData = DataRegistry.get_modifier(&"m_mana_flat")
	if mp_mod != null:
		var mp_before: float = player.get_max_mana()
		ModifierSystem.add_modifier(mp_mod)
		_check(player.get_max_mana() > mp_before, "「灵泉：最大法力 +12」生效",
			"选了灵泉后最大法力仍是 %.0f" % player.get_max_mana())

	ModifierSystem.clear()
	var regen_mod: ModifierData = DataRegistry.get_modifier(&"m_regen")
	if regen_mod != null:
		var stat_regen: float = player.get_stat(GameEnums.StatKind.MANA_REGEN)
		var data_regen: float = player.data.mana_regen
		ModifierSystem.add_modifier(regen_mod)
		var stat_regen2: float = player.get_stat(GameEnums.StatKind.MANA_REGEN)
		_check(stat_regen2 > stat_regen, "「冥想：回蓝 +2」经 get_stat 生效（%.1f → %.1f）" % [stat_regen, stat_regen2],
			"get_stat(MANA_REGEN) 没变")
		# 但 _regen_mana 用的是 data.mana_regen，不走 get_stat。
		_check(data_regen == player.data.mana_regen, "回蓝实际读取源仍是 data.mana_regen（说明冥想不影响回蓝）", "")
	ModifierSystem.clear()


# ============================================================================
# 狩猎 4：武器/元素限定词条是否被当成全局攻击加成
# ============================================================================

func _hunt_weapon_element_modifiers() -> void:
	print("")
	print("--- 狩猎 4：限定类词条是否越界生效 ---")
	ModifierSystem.clear()
	var player: Actor = get_tree().get_first_node_in_group(&"player") as Actor
	if player == null:
		return
	var combat: PlayerCombat = player.get_node_or_null("Combat") as PlayerCombat
	if combat == null:
		return

	# 「巨力」描述：双手武器伤害 +25%。先用单手剑，再验证是否被加成。
	var one_hand: WeaponData = DataRegistry.get_weapon(&"sword")
	if one_hand != null:
		combat.equip_weapon(one_hand)
	var base_atk: float = player.get_stat(GameEnums.StatKind.ATTACK_POWER)
	var heavy: ModifierData = DataRegistry.get_modifier(&"m_heavy_hitter")
	if heavy != null:
		ModifierSystem.add_modifier(heavy)
		var after_atk: float = player.get_stat(GameEnums.StatKind.ATTACK_POWER)
		print("    装备=%s（kind=%d），巨力前后攻击力 %.2f → %.2f" % [
			combat.current_weapon.display_name if combat.current_weapon != null else "无",
			combat.current_weapon.kind if combat.current_weapon != null else -1, base_atk, after_atk])
		_check(absf(after_atk - base_atk) < 0.001, "「巨力」仅在双手武器下加成（描述相符）",
			"拿着%s时「巨力」也把攻击力抬到 %.2f（描述写双手武器专属，实际对所有武器/法术生效）" % [
				combat.current_weapon.display_name if combat.current_weapon != null else "无武器", after_atk])
	ModifierSystem.clear()

	var pyro: ModifierData = DataRegistry.get_modifier(&"m_pyromancy")
	if pyro != null:
		var base2: float = player.get_stat(GameEnums.StatKind.ATTACK_POWER)
		ModifierSystem.add_modifier(pyro)
		var after2: float = player.get_stat(GameEnums.StatKind.ATTACK_POWER)
		_check(absf(after2 - base2) < 0.001, "「烈焰精通」仅在火系法术下加成（描述相符）",
			"「烈焰精通」把普攻/全属性攻击力也从 %.2f 抬到 %.2f（无视 elements 过滤）" % [base2, after2])
	ModifierSystem.clear()


# ============================================================================
# 狩猎 5：词条叠层数学是否正确
# ============================================================================

func _hunt_modifier_stacking() -> void:
	print("")
	print("--- 狩猎 5：叠层公式 & 同名 Key ---")
	# 造一个 value_per_stack > 0 的词条（当前数据里没有，但这是系统声称支持的能力）。
	var probe: ModifierData = ModifierData.new()
	probe.display_name = "__probe__"
	probe.description = "探针"
	probe.stat = GameEnums.StatKind.ATTACK_POWER
	probe.op = GameEnums.ModifierOp.FLAT
	probe.value = 10.0
	probe.value_per_stack = 5.0
	probe.max_stacks = 0
	probe.weight = 1.0

	ModifierSystem.clear()
	ModifierSystem.add_modifier(probe, &"probe")
	var one_stack: float = ModifierSystem.apply_stat(0.0, GameEnums.StatKind.ATTACK_POWER)
	ModifierSystem.add_modifier(probe, &"probe")
	var two_stack: float = ModifierSystem.apply_stat(0.0, GameEnums.StatKind.ATTACK_POWER)
	# 期望：第 1 层 +10；第 2 层 +(10+5) → 合计 25。
	print("    1 层=%s  2 层=%s  期望 1 层=10、2 层=25" % [one_stack, two_stack])
	_check(absf(two_stack - 25.0) < 0.001, "value_per_stack 叠层公式正确（2 层 = 25）",
		"2 层算成 %s，正确应为 25（(value + value_per_stack*(n-1)) * n 把增量乘了两遍）" % two_stack)
	ModifierSystem.clear()

	# 同名词条：两个「龙之心」资源。
	var dragon1: ModifierData = DataRegistry.get_modifier(&"m_all_mult")
	var dragon2: ModifierData = DataRegistry.get_modifier(&"m_dragon_heart")
	if dragon1 != null and dragon2 != null:
		ModifierSystem.clear()
		ModifierSystem.add_modifier(dragon1)
		var owned1: int = ModifierSystem.get_owned_count()
		ModifierSystem.add_modifier(dragon2)
		var owned2: int = ModifierSystem.get_owned_count()
		print("    拿到第 1 个龙之心后词条数=%d，再拿第 2 个后=%d" % [owned1, owned2])
		_check(owned2 == 2, "两个同名不同源的词条能分别入账",
			"display_name 相同时 key 冲突：第 2 个「龙之心」被吞掉（词条数 %d → %d）" % [owned1, owned2])
	ModifierSystem.clear()


# ============================================================================
# 狩猎 6：蓄力被打断后，移速惩罚是否会残留
# ============================================================================

func _hunt_charge_state_leak() -> void:
	print("")
	print("--- 狩猎 6：蓄力中断后的状态残留 ---")
	var player: Player = get_tree().get_first_node_in_group(&"player") as Player
	if player == null:
		return
	var combat: PlayerCombat = player.get_node_or_null("Combat") as PlayerCombat
	if combat == null:
		return
	combat.begin_charge()
	_check(combat.get_move_multiplier() == 1.0, "刚开始蓄力还没减速", "")
	for i: int in 40:
		await get_tree().process_frame
	var charging_mult: float = combat.get_move_multiplier()
	print("    蓄力中移速倍率 = %.3f" % charging_mult)
	# 模拟被敌人打断：直接给一刀。
	var info: DamageInfo = DamageInfo.new()
	info.amount = 1.0
	info.poise_damage = 999.0
	info.source = null
	player.grant_invulnerability(0.0)
	player.apply_damage(info)
	for i: int in 60:
		await get_tree().process_frame
	var after_mult: float = combat.get_move_multiplier()
	print("    被打断 60 帧后移速倍率 = %.3f" % after_mult)
	_check(charging_mult < 1.0, "蓄力确实会降低移速（前置条件）", "蓄力没减速，本项跳过")
	_check(absf(after_mult - 1.0) < 0.001, "被打断后移速恢复正常",
		"打断后移速倍率卡在 %.3f（打折 permanently，玩家会感觉角色变慢）" % after_mult)


# ============================================================================
# 狩猎 7：翻滚/硬直中松开右键，是否会白嫖一次重击
# ============================================================================

func _hunt_roll_attack_override() -> void:
	print("")
	print("--- 狩猎 7：翻滚中释放蓄力 ---")
	ModifierSystem.clear()
	var player: Player = get_tree().get_first_node_in_group(&"player") as Player
	if player == null:
		return
	var combat: PlayerCombat = player.get_node_or_null("Combat") as PlayerCombat
	var ctrl: AttackController = player.get_node_or_null("AttackController") as AttackController
	if combat == null or ctrl == null:
		return
	# 确保站着、攻击控制器空闲。
	if ctrl.is_attacking():
		ctrl.interrupt()
	combat.begin_charge()
	await get_tree().process_frame
	# 进入翻滚（此刻仍在蓄力）。
	player._buffered_roll = 1.0
	for i: int in 4:
		await get_tree().physics_frame
	var rolling: bool = player.get_state() == Player.State.ROLL
	_check(rolling, "玩家已进入翻滚状态（前置条件）", "没能进入翻滚，本项跳过")
	if not rolling:
		combat.release_charge()
		return
	combat.release_charge()
	await get_tree().process_frame
	_check(not ctrl.is_attacking(), "翻滚中释放蓄力不会出招",
		"翻滚（带无敌帧）过程中松开右键照样打出了重击 —— 无敌帧内可以白嫖输出")
	if ctrl.is_attacking():
		ctrl.interrupt()


# ============================================================================
# 狩猎 8：三选一界面弹出后还能不能操作（软锁检测）
# ============================================================================

func _hunt_modifier_choice_softlock() -> void:
	print("")
	print("--- 狩猎 8：三选一界面软锁 ---")
	var ui: Node = get_tree().root.get_node_or_null("ModifierChoice")
	if ui == null:
		_bug("找不到 ModifierChoice")
		return
	var candidates: Array[ModifierData] = ModifierSystem.roll_candidates(3)
	if candidates.is_empty():
		_bug("抽不到词条候选")
		return
	ui.show_choices(candidates)
	await get_tree().process_frame
	# 关键判定：弹窗后 Godot 还会不会把输入派发给这一层。
	# 对照组 GameOverUI 显式设了 PROCESS_MODE_ALWAYS，是可以正常工作的那类写法。
	var control: Node = get_tree().root.get_node_or_null("GameOverUI")
	print("    三选一 process_mode=%d can_process()=%s，对照 GameOverUI=%d can_process()=%s" % [
		ui.process_mode, ui.can_process(),
		control.process_mode if control != null else -1,
		control.can_process() if control != null else "?"])
	_check(ui.can_process(), "三选一层在暂停态仍能接收输入",
		"三选一层 process_mode=%d（INHERIT → 暂停态即 PAUSABLE），而它弹窗时会" % ui.process_mode
		+ " get_tree().paused=true：暂停后 can_process()=false，收不到 gui_input /"
		+ " _unhandled_input → 卡片点不动、1/2/3 也没反应 → 永久软锁，只能强退游戏")
	if control != null:
		_check(control.can_process(), "对照组 GameOverUI（已设 ALWAYS）在暂停态仍可用",
			"连对照组都不可用，说明暂停体系本身有问题")
	if ui.get("_active"):
		ui.visible = false
		ui.set("_active", false)
		ui.set("_candidates", [])
	get_tree().paused = false
	ModifierSystem.clear()


# ============================================================================
# 狩猎 9：穿透弹道会不会对同一目标反复结算
# ============================================================================

func _hunt_projectile_repeat_hit() -> void:
	print("")
	print("--- 狩猎 9：弹道重复命中 ---")
	SceneDirector.change_to_level(&"field", &"from_town")
	for i: int in 45:
		await get_tree().process_frame
	var enemies: Array[Node] = get_tree().get_nodes_in_group(&"enemy")
	if enemies.is_empty():
		_bug("野外没有敌人")
		return
	var target: Actor = enemies[0] as Actor
	var attacker: Actor = get_tree().get_first_node_in_group(&"player") as Actor
	if target == null or attacker == null:
		return

	var data: AttackData = AttackData.new()
	data.damage = 5.0
	data.attack_scaling = 0.0
	data.knockback = 0.0

	var proj: Projectile = load("res://scenes/fx/projectile.tscn").instantiate() as Projectile
	if proj == null:
		_bug("实例化不了弹道")
		return
	proj.pierce_count = 5
	proj.destroy_on_hit = true
	SceneDirector.get_current_scene().add_child(proj)
	# 把弹道塞进目标体内并保持接触。
	proj.global_position = target.global_position
	proj.launch(Vector2.RIGHT, data, GameEnums.Element.NONE, attacker)

	var hp_before: float = target.get_health()
	for i: int in 12:
		proj.global_position = target.global_position
		await get_tree().physics_frame
	var hp_after: float = target.get_health()
	var hits: int = int(round((hp_before - hp_after) / 5.0))
	print("    12 个物理帧内目标掉了 %.1f 血 ≈ %d 次结算" % [hp_before - hp_after, hits])
	_check(hits <= 1, "穿透弹道对同一目标每帧至多结算一次",
		"同一目标在 12 帧内被结算了 %d 次：Projectile 没有 per-target 命中表" % hits)
	proj.queue_free()


# ============================================================================
# 狩猎 10：没有敌人的关卡，清怪门会不会永远打不开
# ============================================================================

func _hunt_clear_gate_without_enemies() -> void:
	print("")
	print("--- 狩猎 10：零敌人关卡的开门条件 ---")
	SceneDirector.change_to_level(&"town", &"start")
	for i: int in 45:
		await get_tree().process_frame
	var level: Node = SceneDirector.get_current_scene()
	if level == null or not level.has_method("is_cleared"):
		_bug("城镇没有 LevelRuntime")
		return
	var alive: int = level.get_alive_count()
	var cleared: bool = level.is_cleared()
	print("    城镇敌人数=%d，is_cleared()=%s" % [alive, cleared])
	_check(alive > 0 or cleared, "没有敌人的关卡也能处于\"已清空\"状态",
		"敌人数为 0 但 is_cleared()=false：任何 require_clear 的锁门在此关卡永不开启（软锁）")


# ============================================================================
# 狩猎 11：死亡复活后是否真的回到存档点坐标
# ============================================================================

func _hunt_respawn_position() -> void:
	print("")
	print("--- 狩猎 11：复活坐标 ---")
	SceneDirector.change_to_level(&"field", &"from_town")
	for i: int in 45:
		await get_tree().process_frame
	var ui: Node = get_tree().root.get_node_or_null("GameOverUI")
	if ui == null:
		_bug("找不到 GameOverUI")
		return
	var marker: Vector2 = Vector2(1234.0, 567.0)
	GameState.set_respawn_point(&"field", marker)
	ui._respawn()
	# 给足时间：淡出 0.18s + 淡入 0.18s + player 重生。
	for i: int in 90:
		await get_tree().process_frame
	var player: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
	if player == null:
		_bug("复活后找不到玩家")
		return
	var dist: float = player.global_position.distance_to(marker)
	print("    期望落在 %s，实际 %s，偏差 %.1f" % [_fmt_vec(marker), _fmt_vec(player.global_position), dist])
	_check(dist < 8.0, "复活后回到存档点坐标",
		"复活点在 %s，玩家却出生在 %s（偏差 %.1f）—— GameOverUI 只 await 了 2 帧，" % [
			_fmt_vec(marker), _fmt_vec(player.global_position), dist]
		+ "那时 SceneDirector 还没换完场景（淡入淡出要 ~22 帧），坐标写给了旧玩家")


# ============================================================================
# 狩猎 13：敌人之间会不会互相打到（友伤）
# ============================================================================

func _hunt_friendly_fire() -> void:
	print("")
	print("--- 狩猎 13：敌方弹道的友伤判定 ---")
	SceneDirector.change_to_level(&"dungeon_1", &"")
	for i: int in 60:
		await get_tree().process_frame
	var enemies: Array[Node] = get_tree().get_nodes_in_group(&"enemy")
	if enemies.size() < 2:
		print("    敌人不足 2 个（%d），跳过" % enemies.size())
		return
	var shooter: EnemyBase = enemies[0] as EnemyBase
	var victim: Actor = enemies[1] as Actor
	if shooter == null or victim == null:
		return
	# 把受害者挪到射手正右方，保证弹道必经其身。
	shooter.global_position = Vector2(200.0, 200.0)
	victim.global_position = Vector2(280.0, 200.0)
	await get_tree().physics_frame
	var scene_path: String = "res://scenes/fx/projectile.tscn"
	if not ResourceLoader.exists(scene_path):
		return
	var proj: Projectile = load(scene_path).instantiate() as Projectile
	if proj == null:
		return
	SceneDirector.get_current_scene().add_child(proj)
	proj.global_position = shooter.global_position
	var data: AttackData = AttackData.new()
	data.damage = 8.0
	data.attack_scaling = 0.0
	proj.launch(Vector2.RIGHT, data, GameEnums.Element.FIRE, shooter)
	var hp_before: float = victim.get_health()
	for i: int in 30:
		await get_tree().physics_frame
	var hp_after: float = victim.get_health()
	print("    敌方弹道穿过队友：队友血量 %.1f → %.1f" % [hp_before, hp_after])
	_check(hp_after >= hp_before, "敌方弹道不会误伤队友",
		"敌方弹道把队友打掉了 %.1f 血：Projectile 只排除了发射者本人，" % (hp_before - hp_after)
		+ "没有阵营判定，混战时会出现自相残杀")


# ============================================================================
# 狩猎 14：受击闪白是否会持续泄漏材质
# ============================================================================

func _hunt_flash_leak() -> void:
	print("")
	print("--- 狩猎 14：受击闪白的资源泄漏 ---")
	var victim: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
	if victim == null:
		return
	var actor: Actor = victim as Actor
	if actor == null:
		return
	var before_count: int = Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
	# 连续受击 60 次，其间不断清无敌帧让每次都能结算。
	for i: int in 60:
		var info: DamageInfo = DamageInfo.new()
		info.amount = 0.0
		info.source = null
		actor.grant_invulnerability(0.0)
		actor.apply_damage(info)
	var after_count: int = Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
	var delta: int = after_count - before_count
	print("    60 次受击后 Resource 总数 %d → %d（+ %d）" % [before_count, after_count, delta])
	_check(delta < 10, "连续受击不产生资源泄漏（+ %d）" % delta,
		"60 次受击新增了 %d 个 Resource：_flash() 每次都 duplicate 一份 ShaderMaterial" % delta
		+ "且从不释放，长时间战斗会持续吃内存")
	actor.heal(actor.get_max_health())


# ============================================================================
# 狩猎 12：边界条件下的空引用
# ============================================================================

func _hunt_missing_reference_edges() -> void:
	print("")
	print("--- 狩猎 12：边界/异常输入 ---")
	# SceneDirector.get_entry_position 在没关卡数据时会访问 _current_level.id。
	_check(SceneDirector.get_entry_position(&"不存在的入口点") == Vector2.ZERO,
		"查询不存在的入口点不会崩", "查询不存在的入口点直接抛异常")
	# Actor 在 data 为空时的读值。
	var ghost: Actor = Actor.new()
	ghost.data = null
	_check(ghost.get_max_health() == 100.0, "data 为空时 Actor 仍有兜底上限", "")
	ghost.free()
	# GameState 的异常入参。
	var gold_before: int = GameState.gold
	GameState.add_item(&"", 1)
	GameState.remove_item(&"不存在的物品", 99)
	_check(GameState.gold == gold_before, "非法入参不影响金币", "")
	# ModifierSystem 对空数据的健壮性。
	var before: int = ModifierSystem.get_owned_count()
	ModifierSystem.add_modifier(null)
	_check(ModifierSystem.get_owned_count() == before, "add_modifier(null) 不会误加", "")


# ============================================================================
# 私有方法
# ============================================================================

func _check(condition: bool, ok_label: String, bug_label: String) -> void:
	_checks += 1
	if condition:
		_oks.append(ok_label)
		print("  [OK]  ", ok_label)
	else:
		_bugs.append(bug_label)
		print("  [BUG] ", bug_label)


func _bug(label: String) -> void:
	_checks += 1
	_bugs.append(label)
	print("  [BUG] ", label)


func _fmt_vec(v: Vector2) -> String:
	return "(%.1f, %.1f)" % [v.x, v.y]


func _camera_zoom() -> String:
	var p: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
	if p == null:
		return "?"
	var cam: Camera2D = p.get_viewport().get_camera_2d()
	return "%.2f" % cam.zoom.x if cam != null else "无摄像机"


## 复刻 Boot 的常驻 UI 安装。
func _install_persistent_ui() -> void:
	var paths: Dictionary = {
		"res://scenes/ui/hud.tscn": "HUD",
		"res://scenes/ui/tutorial_ui.tscn": "TutorialUI",
		"res://scenes/ui/boss_health_bar.tscn": "BossHealthBar",
		"res://scenes/ui/modifier_choice.tscn": "ModifierChoice",
		"res://scenes/ui/inventory_ui.tscn": "InventoryUI",
		"res://scenes/ui/game_over.tscn": "GameOverUI",
		"res://scenes/ui/pause_menu.tscn": "PauseMenu",
	}
	for path: String in paths.keys():
		if not ResourceLoader.exists(path):
			continue
		var node: Node = load(path).instantiate()
		node.name = paths[path]
		get_tree().root.add_child.call_deferred(node)


func _report() -> void:
	print("")
	print("############################################")
	print("运行时缺陷狩猎：%d 项检查，复现 %d 个问题" % [_checks, _bugs.size()])
	if _bugs.is_empty():
		print("全部通过。")
		return
	print("")
	print("## 复现清单")
	var idx: int = 1
	for b: String in _bugs:
		print("  %d. %s" % [idx, b])
		idx += 1
	print("############################################")
