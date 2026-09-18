## CombatTest —— 战斗链路集成测试
##
## 【负责什么】
##   验证"攻击盒真的能打到受击盒"这条最关键的链路：碰撞层配置、命中判定、
##   伤害结算、顿帧/震动广播。碰撞层写错是 2D 动作游戏最常见的静默失败，
##   逻辑测试（直接调 apply_damage）测不出来。
##
## 【怎么运行】
##   Godot --headless --path . res://tools/combat_test.tscn
extends Node

# ============================================================================
# 私有变量
# ============================================================================

var _failures: Array[String] = []
var _checks: int = 0
var _hitstop_received: float = 0.0
var _shake_received: float = 0.0

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	EventBus.hit_stop_requested.connect(func(d: float) -> void: _hitstop_received = maxf(_hitstop_received, d))
	EventBus.camera_shake_requested.connect(func(a: float, _d: float) -> void: _shake_received = maxf(_shake_received, a))
	SceneDirector.change_to_level(&"field", &"from_town")
	for i: int in 60:
		await get_tree().process_frame
	await _run()
	_report()
	get_tree().quit(1 if _failures.size() > 0 else 0)


func _run() -> void:
	var player: Actor = get_tree().get_first_node_in_group(&"player") as Actor
	_check(player != null, "玩家存在")
	if player == null:
		return
	var enemies: Array[Node] = get_tree().get_nodes_in_group(&"enemy")
	_check(enemies.size() > 0, "场上有敌人")
	if enemies.is_empty():
		return
	var enemy: Actor = enemies[0] as Actor
	# 彻底静默敌人：关 AI 且关掉它们的攻击盒。
	# 只关 set_physics_process 不够——Area2D 的 overlap 检测仍由物理服务器驱动，
	# 已经打开的判定盒会继续命中玩家并打断我们的攻击，导致测试随机失败。
	for e: Node in enemies:
		e.set_physics_process(false)
		# 敌人也用武器场景了，要把武器里的判定盒关掉。
		var ebox: Area2D = e.get_node_or_null("AttackBox") as Area2D
		if ebox != null:
			ebox.monitoring = false
		for child: Node in e.get_children():
			if child is WeaponController:
				var wbox: AttackBox = (child as WeaponController).get_attack_box()
				if wbox != null:
					wbox.monitoring = false
	# 清掉场上残留的弹道（法师在 AI 被关掉前可能已经发射了火球）。
	# 这些弹道会命中玩家 → 触发 _on_damaged → interrupt()，把我们的攻击打断。
	for proj: Node in get_tree().get_nodes_in_group(&"projectile"):
		proj.queue_free()
	# 让玩家在整段测试期间无敌：本测试验证的是"玩家的攻击盒 → 敌人受击盒"，
	# 玩家被打断只会让测试不稳定，与要验证的链路无关。
	player.grant_invulnerability(10.0)

	# 注意：PlayerCombat._process 每帧会把武器瞄准方向刷新为鼠标方向，
	# 所以测试不能假设"朝右"。这里先取武器的真实瞄准方向，再把敌人放到该方向上。
	var aim: Vector2 = Vector2.RIGHT
	var w: WeaponController = (player.get_node_or_null("AttackController") as AttackController).get_weapon()
	if w != null:
		aim = w.transform.x.normalized() if w.transform.x.length_squared() > 0.0001 else Vector2.RIGHT
	# 把敌人搬到玩家瞄准方向上，确保攻击盒能覆盖它。
	enemy.global_position = player.global_position + aim * 14.0
	enemy.velocity = Vector2.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame

	# 让玩家朝右并挥砍。直接驱动 AttackController，绕过输入层。
	var ac: AttackController = player.get_node_or_null("AttackController") as AttackController
	_check(ac != null, "玩家有 AttackController")
	if ac == null:
		return
	var sword: WeaponData = DataRegistry.get_weapon(&"sword")
	_check(sword != null and sword.combo_1 != null, "sword 有连击数据")
	if sword == null or sword.combo_1 == null:
		return

	var hp_before: float = enemy.get_health()
	# 判定盒现在属于武器，从武器拿；同时把武器瞄准右方（敌人所在方向）。
	var weapon: WeaponController = ac.get_weapon()
	if weapon == null:
		_failures.append("玩家武器未挂到 AttackController")
		_report()
		return
	var box: AttackBox = weapon.get_attack_box()
	ac.request_attack(sword.combo_1)
	# 等过前摇 + 判定窗口。
	for i: int in 30:
		await get_tree().physics_frame
		# 每帧把敌人钉在攻击范围内，避免击退后打不到第二下。
		if is_instance_valid(enemy):
			enemy.global_position = player.global_position + aim * 14.0
	var hp_after: float = enemy.get_health()
	_check(hp_after < hp_before, "攻击盒命中敌人并扣血（%.1f → %.1f）" % [hp_before, hp_after])
	_check(_hitstop_received > 0.0, "命中触发了顿帧（%.3f 秒）" % _hitstop_received)
	_check(_shake_received > 0.0, "命中触发了屏幕震动（%.1f）" % _shake_received)

	# 翻滚无敌：给玩家无敌后打它，血量不应变化。
	player.grant_invulnerability(0.5)
	var hp_before2: float = player.get_health()
	var probe: DamageInfo = DamageInfo.new()
	probe.amount = 50.0
	player.apply_damage(probe)
	_check(is_equal_approx(player.get_health(), hp_before2), "无敌帧内免疫伤害")

	# 击退：直接检查受击后是否拿到击退速度。
	# 不用位移来判断，因为本测试关掉了敌人的物理帧，位移不会发生。
	player.grant_invulnerability(0.0)
	var hit2: DamageInfo = DamageInfo.new()
	hit2.amount = 1.0
	hit2.knockback = Vector2(300, 0)
	hit2.source = player
	enemy.apply_damage(hit2)
	var knockback: Vector2 = enemy.get_knockback_velocity()
	_check(knockback.length() > 100.0, "受击后获得击退速度（%.0f 像素/秒）" % knockback.length())


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


func _report() -> void:
	print("")
	print("=== 战斗测试：%d 项检查，%d 项失败 ===" % [_checks, _failures.size()])
	for f: String in _failures:
		print("  ✗ ", f)
