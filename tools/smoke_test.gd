## SmokeTest —— 冒烟测试（编辑器工具脚本，不参与游戏运行）
##
## 【负责什么】
##   无窗口跑一遍游戏，检查关键节点是否都存在、玩家能否移动、能否造成伤害。
##   每次大改动后跑一次，比人肉点开编辑器快得多。
##
## 【怎么运行】
##   Godot --headless --path . res://tools/smoke_test.tscn
##
## 【为什么需要它】
##   无头模式看不到画面，但能验证"逻辑是否跑通"：场景树结构、信号连接、
##   数据加载、伤害结算。视觉问题再单独截图确认。
extends Node

# ============================================================================
# 私有变量
# ============================================================================

var _failures: Array[String] = []
var _checks: int = 0

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	# 本场景被当作主场景直接运行，所以 boot.tscn 不会执行——需要自己触发关卡加载。
	# 同时要复刻 boot 的常驻 UI 安装，否则 UI 相关检查必然失败。
	GameState.start_run()
	_install_persistent_ui()
	SceneDirector.change_to_level(&"town", &"start")
	# 等足够帧数让转场（淡出 0.18s + 淡入 0.18s ≈ 22 帧）彻底结束，
	# 否则下一次 change_to_level 会因为 _changing 仍为 true 而被丢弃。
	for i: int in 45:
		await get_tree().process_frame
	await _run_checks()
	_report()
	get_tree().quit(1 if _failures.size() > 0 else 0)


func _run_checks() -> void:
	# --- 1. 数据层 ---
	_check(DataRegistry.is_ready(), "DataRegistry 已就绪")
	_check(DataRegistry.get_all_weapons().size() >= 6, "武器数据 >= 6（实际 %d）" % DataRegistry.get_all_weapons().size())
	_check(DataRegistry.get_all_spells().size() >= 3, "法术数据 >= 3")
	_check(DataRegistry.get_all_modifiers().size() >= 15, "词条数据 >= 15")
	_check(DataRegistry.get_all_levels().size() >= 4, "关卡数据 >= 4")
	_check(DataRegistry.get_weapon(&"sword") != null, "能查到 sword 武器")
	_check(DataRegistry.get_level(&"town") != null, "能查到 town 关卡")
	_check(DataRegistry.get_enemy(&"slime") != null, "能查到 slime 敌人")

	# --- 2. 场景层 ---
	var level: Node = SceneDirector.get_current_scene()
	_check(level != null, "当前关卡场景已加载")
	if level == null:
		return
	_check(level.has_node("Floor"), "关卡有 Floor 图层")
	_check(level.has_node("Walls"), "关卡有 Walls 图层")

	# --- 3. 玩家 ---
	var player: Node = get_tree().get_first_node_in_group(&"player")
	_check(player != null, "玩家已生成并加入 player 组")
	if player == null:
		return
	_check(player is Actor, "玩家是 Actor 子类")
	_check(player.get("data") != null, "玩家已绑定 CharacterData")
	var actor: Actor = player as Actor
	_check(actor.get_max_health() > 0.0, "玩家最大生命 > 0（%.0f）" % actor.get_max_health())
	_check(actor.get_stat(GameEnums.StatKind.MOVE_SPEED) > 0.0, "玩家移动速度 > 0")
	_check(player.has_node("Sprite"), "玩家有 Sprite")
	_check(player.has_node("AttackBox"), "玩家有 AttackBox")
	_check(player.has_node("Hurtbox"), "玩家有 Hurtbox")
	_check(player.has_node("Camera2D"), "玩家有 Camera2D")

	# --- 4. 战斗：手动对玩家造成伤害，验证扣血链路 ---
	var before: float = actor.get_health()
	var info: DamageInfo = DamageInfo.new()
	info.amount = 10.0
	info.source = null
	# 先清掉无敌帧（_ready 后可能还没到期），确保伤害能进去。
	actor.grant_invulnerability(0.0)
	actor.apply_damage(info)
	_check(actor.get_health() < before, "造成伤害后血量下降（%.1f → %.1f）" % [before, actor.get_health()])

	# --- 5. 玩家控制器状态机可切换 ---
	_check(player.has_method("get_state"), "玩家有状态查询接口")

	# --- 6. 摄像机跟随 ---
	var cam: PlayerCamera = player.get_node_or_null("Camera2D") as PlayerCamera
	_check(cam != null, "摄像机脚本挂载正确")
	if cam != null:
		cam.shake(5.0, 0.2)
		_check(true, "摄像机震动调用成功")

	# --- 7. 敌人系统（切到野外验证刷怪）---
	SceneDirector.change_to_level(&"field", &"from_town")
	# 切场景含转场淡入淡出（约 0.2 秒 = 12 帧），必须等够，否则拿到的是旧场景。
	for i: int in 40:
		await get_tree().process_frame
	var enemies: Array[Node] = get_tree().get_nodes_in_group(&"enemy")
	_check(enemies.size() > 0, "野外生成了敌人（%d 个）" % enemies.size())
	if enemies.size() > 0:
		var e: Actor = enemies[0] as Actor
		_check(e != null and e.get_max_health() > 0.0, "敌人生成后已绑定属性")

	# --- 8. Roguelite 词条系统 ---
	# 注意：切场景后旧玩家节点已被释放，必须重新取当前玩家。
	var live_player: Actor = get_tree().get_first_node_in_group(&"player") as Actor
	_check(live_player != null, "切场景后仍能找到玩家")
	if live_player == null:
		return
	var base_attack: float = live_player.get_stat(GameEnums.StatKind.ATTACK_POWER)
	var candidates: Array[ModifierData] = ModifierSystem.roll_candidates(3)
	_check(candidates.size() == 3, "能抽出 3 个词条候选")
	# 手动加一个固定加攻击的词条，验证乘区生效。
	var atk_mod: ModifierData = DataRegistry.get_modifier(&"m_atk_flat")
	_check(atk_mod != null, "能查到 m_atk_flat 词条")
	if atk_mod != null:
		ModifierSystem.add_modifier(atk_mod)
		var after: float = live_player.get_stat(GameEnums.StatKind.ATTACK_POWER)
		_check(after > base_attack, "词条生效：攻击力 %.0f → %.0f" % [base_attack, after])
		_check(ModifierSystem.get_owned_count() > 0, "词条已记录到系统")

	# --- 9. 法术与技能槽 ---
	var combat: PlayerCombat = live_player.get_node_or_null("Combat") as PlayerCombat
	_check(combat != null, "玩家有 PlayerCombat 组件")
	if combat != null:
		_check(combat.current_weapon != null, "玩家已装备武器")
		_check(combat.spell_slots.size() == 3, "法术槽有 3 个")
		_check(combat.spell_slots[0] != null, "第 1 个法术槽已配置")
		# 蓝够的情况下应该能放出火球。
		var mana_before: float = live_player.get_mana()
		var cast_ok: bool = combat.cast_spell(0)
		_check(cast_ok, "能释放火球术")
		if cast_ok:
			_check(live_player.get_mana() < mana_before, "释放法术后蓝量下降（%.0f → %.0f）" % [mana_before, live_player.get_mana()])
			_check(combat.is_on_cooldown(&"spell_0"), "法术后进入冷却")
		# 武器切换。
		var two_hand: WeaponData = DataRegistry.get_weapon(&"big_sword")
		if two_hand != null:
			combat.equip_weapon(two_hand)
			_check(combat.current_weapon == two_hand, "能切换到双手大剑")
			_check(two_hand.kind == GameEnums.WeaponKind.TWO_HANDED, "双手大剑类别正确")

	# --- 10. UI 常驻层 ---
	var hud: Node = get_tree().root.get_node_or_null("HUD")
	_check(hud != null, "HUD 已挂载到 root")
	var choice_ui: Node = get_tree().root.get_node_or_null("ModifierChoice")
	_check(choice_ui != null, "三选一界面已挂载到 root")


# ============================================================================
# 私有方法
# ============================================================================

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  [PASS] ", label)
	else:
		_failures.append(label)
		print("  [FAIL] ", label)


## 复刻 Boot 的常驻 UI 安装逻辑（本脚本独立运行时需要）。
func _install_persistent_ui() -> void:
	var hud_scene: PackedScene = load("res://scenes/ui/hud.tscn")
	var choice_scene: PackedScene = load("res://scenes/ui/modifier_choice.tscn")
	if hud_scene != null:
		var hud: Node = hud_scene.instantiate()
		hud.name = "HUD"
		get_tree().root.add_child.call_deferred(hud)
	if choice_scene != null:
		var choice: Node = choice_scene.instantiate()
		choice.name = "ModifierChoice"
		get_tree().root.add_child.call_deferred(choice)


func _report() -> void:
	print("")
	print("=== 冒烟测试：%d 项检查，%d 项失败 ===" % [_checks, _failures.size()])
	for f: String in _failures:
		print("  ✗ ", f)
