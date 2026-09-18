## AuditRegression —— 代码审计（bug_report）修复项的行为回归
##
## 【负责什么】
##   把 bug_report 里**不可由 audit_found_test 直接复现**的那些修复变成断言，
##   防止以后改代码把它们改回去。audit_found_test 负责 7 个可实证用例，
##   本文件覆盖其余"高危 + 中危"条目（B09~B32）。
##
## 【怎么运行】
##   Godot --headless --path . res://tools/audit_regression_test.tscn
##
## 【与 audit_found_test 的分工】
##   - audit_found_test：跑真实场景切换 / 真实点击，验证"用户看得到的症状"。
##   - 本文件：直接构造对象打桩，验证"修好的判定逻辑"，快且稳。
##
## 【写法注意】
##   1. GDScript 的 lambda 对局部变量是**值捕获**，跨回调传递的结果一律用 Array 装箱。
##   2. 断言"某信号成对上下线"要真正连信号计数，而不是读内部字段——
##      读字段只能证明实现没变，证明不了契约仍然成立。
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
	print("")
	print("############ 审计修复项回归 ############")
	await _check_b09_b10_super_armor_and_cooldown()
	await _check_b11_damage_return_value()
	await _check_b12_typing_last_page_reward()
	await _check_b13_inventory_pause_ownership()
	await _check_b14_boss_id()
	await _check_b15_chest_persistence()
	await _check_b17_save_point_null_level()
	await _check_b18_heal_spring_cooldown()
	await _check_b19_swing_signal_pairing()
	await _check_b20_shake_origin()
	await _check_b23_boss_bar_rebind()
	await _check_b24_boss_room_reward()
	await _check_b28_interactable_nearest()
	await _check_b30_heavy_attack_state()
	await _check_b31_coyote_time()
	await _check_b32_anim_restart()
	_report()
	get_tree().quit(1 if _fail.size() > 0 else 0)


# ============================================================================
# 工具
# ============================================================================

func _frames(n: int) -> void:
	for _i: int in n:
		await get_tree().process_frame


func _ok(label: String) -> void:
	_pass += 1
	print("  [PASS] ", label)


func _bad(label: String) -> void:
	_fail.append(label)
	print("  [FAIL] ", label)


func _check(cond: bool, ok_label: String, bad_label: String) -> void:
	if cond:
		_ok(ok_label)
	else:
		_bad(bad_label)


## 造一个脱离场景树的 Actor 用于打桩。挂一个最小 Hurtbox 之外的东西都不需要——
## 我们只调 apply_damage 这类纯逻辑方法。
## 造一个脱离场景树的 Actor 用于打桩。挂一个最小 Hurtbox 之外的东西都不需要——
## 我们只调 apply_damage 这类纯逻辑方法。
##
## 【为什么必须手动塞 _health】Actor.new() 出来的节点不在场景树里，_ready() 不会跑，
##   而"满血"恰恰是 _ready() 里 _health = get_max_health() 赋的。不手动灌就会
##   得到一个 0 血对象，apply_damage 会直接走"已经死了"分支返回 false——
##   断言失败的原因会伪装成"生产代码没修好"，其实是打桩没打全。
func _make_actor(hp: float, super_armor: bool, poise: float) -> Actor:
	var a: Actor = Actor.new()
	var d: CharacterData = CharacterData.new()
	d.max_health = hp
	d.max_mana = 0.0
	d.super_armor = super_armor
	d.poise = poise
	d.invuln_time = 0.0
	d.hurt_time = 0.2
	d.death_dissolve_time = 0.0
	d.destroy_on_death = false
	a.set("data", d)
	a.call("_resolve_nodes")
	a.set("_health", hp)
	a.set("_mana", 0.0)
	return a


func _dmg(amount: float, poise_damage: float = 10.0) -> DamageInfo:
	var info: DamageInfo = DamageInfo.new()
	info.amount = amount
	info.poise_damage = poise_damage
	return info


## 把源码里的整行注释剔掉（保留行号占位），用于"这个标识符出现在代码里吗"这类断言。
##
## 【为什么需要它】本项目的注释密度极高，而且规范要求用【为什么…】解释反直觉设计，
##   注释里经常原样引用代码片段（比如 `interrupt()`、`_mark_cleared()`）。
##   对整份源码直接 contains/find，注释会冒充代码，断言就会假绿或假红。
func _strip_comment_lines(src: String) -> String:
	var out: PackedStringArray = PackedStringArray()
	for line: String in src.split("\n"):
		if line.strip_edges().begins_with("#"):
			out.append("")
		else:
			out.append(line)
	return "\n".join(out)


## 只保留某个函数体（从 `func_signature` 命中处到下一个 `func ` 之前）。
## 同样先剥注释，避免文档注释里的示例代码污染断言。
func _function_body(path: String, func_signature: String) -> String:
	var src: String = _strip_comment_lines(FileAccess.get_file_as_string(path))
	var start: int = src.find(func_signature)
	if start == -1:
		return ""
	var rest: String = src.substr(start + func_signature.length())
	var next: int = rest.find("\nfunc ")
	return rest if next == -1 else rest.substr(0, next)


# ============================================================================
# B09 / B10 —— 霸体不该被打断；打断要吃冷却
# ============================================================================

func _check_b09_b10_super_armor_and_cooldown() -> void:
	print("")
	print("--- B09 / B10：霸体与打断冷却 ---")
	var boss: Actor = _make_actor(500.0, true, 90.0)
	# 霸体：削韧 999 也判成"不打断"。
	_check(not boss.would_stagger(_dmg(1.0, 999.0)),
		"B09 霸体（super_armor）免疫打断，只掉血",
		"B09 霸体仍会被打断：would_stagger 未读 super_armor")

	# 无霸体但韧性高：削韧不足不打断，够了才打断。
	var tough: Actor = _make_actor(200.0, false, 50.0)
	var soft_stagger: bool = tough.would_stagger(_dmg(1.0, 10.0))
	var hard_stagger: bool = tough.would_stagger(_dmg(1.0, 60.0))
	_check(not soft_stagger and hard_stagger,
		"B09 无霸体时按韧性阈值判定打断（10 不断 / 60 断）",
		"B09 韧性阈值失效（10→%s，60→%s）" % [soft_stagger, hard_stagger])

	# 韧性 0 = 一击必断。
	var squishy: Actor = _make_actor(100.0, false, 0.0)
	_check(squishy.would_stagger(_dmg(1.0, 1.0)),
		"B09 韧性为 0 时一击必断",
		"B09 韧性 0 却打不断")

	boss.free()
	tough.free()
	squishy.free()

	# B10：源码层断言——打断路径必须同时写冷却。
	# 这条用行为很难在 headless 里稳定复现（要跑满前摇），
	# 于是退一步做"结构断言"：确认 _on_damaged 的打断分支包含冷却赋值。
	#
	# 【为什么必须限定在 _on_damaged 函数体内】`_attack_cooldown = enemy_data.attack_cooldown`
	#   在文件里出现三次（_tick_attack 的自然结束分支、冲撞结束分支、_on_damaged 的打断分支）。
	#   对整份文件 find() 只会拿到最靠前的那次（_tick_attack），与 interrupt() 的位置
	#   怎么比都不对。只有切出 _on_damaged 本体、并在其中确认"赋值跟在 interrupt() 之后"，
	#   才真正对应"打断也吃冷却"这条修复。
	var hurt_body: String = _function_body(
		"res://scripts/enemies/enemy_base.gd", "func _on_damaged")
	var interrupted_at: int = hurt_body.find("_attack_controller.interrupt()")
	var cooldown_at: int = hurt_body.find("_attack_cooldown = enemy_data.attack_cooldown")
	_check(interrupted_at != -1 and cooldown_at > interrupted_at,
		"B10 打断路径会重置 _attack_cooldown（不再越打出手越快）",
		"B10 打断路径仍未写 _attack_cooldown（interrupt@%d cooldown@%d，body=%d 字符）"
			% [interrupted_at, cooldown_at, hurt_body.length()])


# ============================================================================
# B11 —— apply_damage 返回值与命中反馈脱钩
# ============================================================================

func _check_b11_damage_return_value() -> void:
	print("")
	print("--- B11：命中反馈与是否真扣血对齐 ---")
	var a: Actor = _make_actor(100.0, false, 0.0)

	var landed: bool = a.apply_damage(_dmg(10.0))
	_check(landed and is_equal_approx(a.get_health(), 90.0),
		"B11 正常命中返回 true 并扣血（100 → 90）",
		"B11 正常命中返回 %s，血量 %s" % [landed, a.get_health()])

	# 无敌帧内不吃伤害，必须返回 false，否则调用方会照常飘字/顿帧/吸血。
	a.grant_invulnerability(1.0)
	var blocked: bool = a.apply_damage(_dmg(10.0))
	_check(not blocked,
		"B11 无敌帧内 apply_damage 返回 false（调用方据此跳过飘字/吸血）",
		"B11 无敌帧内仍返回 true，打尸体照样飘字")
	a.free()

	# 调用方确实检查了返回值。
	var box_src: String = _strip_comment_lines(
		FileAccess.get_file_as_string("res://scripts/combat/attack_box.gd"))
	var proj_src: String = _strip_comment_lines(
		FileAccess.get_file_as_string("res://scripts/combat/projectile.gd"))
	var spell_src: String = _strip_comment_lines(
		FileAccess.get_file_as_string("res://scripts/combat/area_spell.gd"))
	_check(box_src.contains("if not target.apply_damage(info)") \
			and proj_src.contains("if not target.apply_damage(info)") \
			and spell_src.contains("if not target.apply_damage(info)"),
		"B11 三处伤害入口（攻击盒/弹道/法术区域）都检查了返回值",
		"B11 仍有伤害入口不检查返回值")


# ============================================================================
# B12 —— 最后一页打字未完成时关闭不该丢奖励
# ============================================================================

func _check_b12_typing_last_page_reward() -> void:
	print("")
	print("--- B12：打字未完时关闭不吞奖励 ---")
	var ui: Node = load("res://scenes/ui/dialog_ui.tscn").instantiate()
	ui.name = "DialogUI"
	get_tree().root.add_child.call_deferred(ui)
	await _frames(3)

	# 装一段单句对话，注册结算回调。
	var got: Array = [false]
	var cb: Callable = func() -> void:
		got[0] = true
	var script: DialogueScript = DialogueScript.from_strings("测试者", ["这是一句需要打很久才能显示完的台词，测试用。"])
	EventBus.dialog_script_requested.emit(script, cb)
	await _frames(3)

	var typing: bool = bool(ui.get("_typing"))
	# 打字中按"玩家主动关闭"：应当只补全文字，**不**结束对话、**不**丢回调。
	ui.call("dismiss_by_player")
	await _frames(2)
	var still_open: bool = bool(ui.get("is_open"))
	var finished_typing: bool = not bool(ui.get("_typing"))
	_check(typing and still_open and finished_typing and not got[0],
		"B12 打字中关闭 = 只补全文字（对话仍开着、回调未结算）",
		"B12 打字中关闭行为错误（typing=%s open=%s typing_done=%s rewarded=%s）"
			% [typing, still_open, finished_typing, got[0]])

	# 再关一次：这次才是真正的"读完了"，必须结算。
	ui.call("dismiss_by_player")
	await _frames(2)
	_check(got[0] and not bool(ui.get("is_open")),
		"B12 补全后再关闭 = 按已完成结算回调",
		"B12 补全后关闭仍未结算（rewarded=%s）" % got[0])

	ui.queue_free()
	await _frames(2)


# ============================================================================
# B13 —— 背包不该无条件解除暂停
# ============================================================================

func _check_b13_inventory_pause_ownership() -> void:
	print("")
	print("--- B13：背包的暂停所有权 ---")
	# 【为什么要先把 PauseManager 清空】本用例测的是"背包自己那一个令牌"的
	#   加减语义。重构后暂停的唯一真相是 PauseManager 的持有者集合，若上一批
	#   用例留下过令牌，背包 open/close 的净效果就被别的持有者掩盖了。
	#   清空 = 回到"没有任何窗口要求暂停"的干净起点。
	PauseManager.clear_all()
	var inv: Node = load("res://scenes/ui/inventory_ui.tscn").instantiate()
	inv.name = "InventoryUI"
	get_tree().root.add_child.call_deferred(inv)
	await _frames(3)

	# 场景一：游戏本来在跑 → 开背包暂停，关背包恢复。
	inv.call("open")
	await _frames(1)
	var paused_after_open: bool = get_tree().paused
	inv.call("close")
	await _frames(1)
	var resumed_after_close: bool = not get_tree().paused
	_check(paused_after_open and resumed_after_close,
		"B13 游戏运行中开背包→暂停，关背包→恢复",
		"B13 运行中开/关背包的暂停语义错误（open=%s close=%s）"
			% [paused_after_open, resumed_after_close])
	_check(PauseManager.holder_count() == 0,
		"B13 关背包后 PauseManager 不残留令牌",
		"B13 关背包后仍有令牌：%s" % str(PauseManager.get_holders()))

	# 场景二：**游戏本来就停着**（暂停菜单开着）→ 关背包必须保持暂停。
	# 这是"顶着暂停菜单在 Boss 战里自由行动"的根因场景。
	#
	# 【重构后怎么表达"暂停菜单开着"】不能再裸写 `paused = true` —— 那正是
	#   被修掉的病灶（绕过所有权写状态，PauseManager 无从知道）。现在用
	#   与 PauseMenu 相同的契约 `PauseManager.freeze(&"pause_menu")` 来扮演它。
	#   这样本用例同时验证了：背包交还自己的令牌后，另一个持有者的令牌仍在，
	#   游戏保持暂停 —— 这才是"不允许背包把暂停菜单底下的游戏放跑"的正解。
	PauseManager.freeze(&"pause_menu")
	inv.call("open")
	await _frames(1)
	inv.call("close")
	await _frames(1)
	var still_paused: bool = get_tree().paused
	_check(still_paused,
		"B13 从暂停菜单进入时，关掉背包后游戏仍保持暂停",
		"B13 关背包把暂停菜单底下的游戏放跑了（paused=%s）" % still_paused)
	_check(PauseManager.holds(&"pause_menu") and not PauseManager.holds(&"inventory"),
		"B13 背包只交还自己的令牌，暂停菜单的令牌不受影响",
		"B13 令牌归属错乱：%s" % str(PauseManager.get_holders()))
	PauseManager.clear_all()

	get_tree().paused = false
	inv.queue_free()
	await _frames(2)


# ============================================================================
# B14 —— Boss 击败登记用的是 id 而不是中文名
# ============================================================================

func _check_b14_boss_id() -> void:
	print("")
	print("--- B14：Boss 击败登记的 id ---")
	GameState.defeated_bosses.clear()
	# 关卡表里的 boss_id 是 boss_cyclops；登记的必须是同一个字符串。
	var level: LevelData = DataRegistry.get_level(&"boss_room")
	var expected: StringName = level.boss_id if level != null else &"boss_cyclops"
	GameState.register_boss_defeat(expected)
	_check(GameState.is_boss_defeated(expected),
		"B14 is_boss_defeated(&\"%s\") 能查到登记记录" % expected,
		"B14 击败登记与关卡 boss_id 对不上")
	_check(not GameState.is_boss_defeated(&"独眼巨人"),
		"B14 不再用中文 display_name 当 boss id",
		"B14 仍在用中文名登记 boss id")

	# 源码层：死亡回调必须走 _resolve_boss_id() 而不是 display_name。
	var src: String = _strip_comment_lines(
		FileAccess.get_file_as_string("res://scripts/enemies/enemy_base.gd"))
	_check(src.contains("register_boss_defeat(_resolve_boss_id())"),
		"B14 死亡回调改用 _resolve_boss_id()",
		"B14 死亡回调仍直接传 display_name")
	GameState.defeated_bosses.clear()


# ============================================================================
# B15 —— 宝箱开箱状态落盘，不能重复领取
# ============================================================================

func _check_b15_chest_persistence() -> void:
	print("")
	print("--- B15：宝箱一次性状态落盘 ---")
	GameState.opened_chests.clear()
	var key: StringName = &"field/chest_test"
	_check(not GameState.is_chest_opened(key), "B15 新宝箱初始为未开", "B15 宝箱初始状态错误")
	GameState.mark_chest_opened(key)
	_check(GameState.is_chest_opened(key), "B15 开箱后标记为已开", "B15 开箱标记未写入")

	# 走一遍真实的存/读盘：这才是"死亡重进也能记住"的关键。
	GameState.save_game()
	GameState.opened_chests.clear()
	GameState.load_game()
	var survived: bool = GameState.is_chest_opened(key)
	_check(survived,
		"B15 开箱状态经存/读盘后仍在（重进不会重复领取）",
		"B15 开箱状态没落盘，重进可无限领取")
	GameState.opened_chests.clear()
	GameState.save_game()


# ============================================================================
# B17 —— 存档点在没有当前关卡时不崩
# ============================================================================

func _check_b17_save_point_null_level() -> void:
	print("")
	print("--- B17：save_point 的关卡判空 ---")
	var src: String = _strip_comment_lines(
		FileAccess.get_file_as_string("res://scripts/world/save_point.gd"))
	var guarded: bool = src.contains("var level: LevelData = SceneDirector.get_current_level()") \
		and src.contains("if level == null:")
	_check(guarded,
		"B17 save_point 取关卡前先判空（未经 SceneDirector 加载时不再空引用崩溃）",
		"B17 save_point 仍直接 .id，未判空")


# ============================================================================
# B18 —— 治愈泉满血时不能清掉自己的冷却
# ============================================================================

func _check_b18_heal_spring_cooldown() -> void:
	print("")
	print("--- B18：治愈泉冷却计时器 ---")
	var src: String = _strip_comment_lines(
		FileAccess.get_file_as_string("res://scripts/world/heal_spring.gd"))
	# 满血分支必须只 return，绝不能碰 _cooldown_timer。
	var full_hp_branch: String = src.substr(src.find("get_health() >= target.get_max_health()"))
	var touches_timer: bool = full_hp_branch.contains("_cooldown_timer")
	_check(src.contains("if target.get_health() >= target.get_max_health()") and not touches_timer,
		"B18 满血分支直接 return，不动冷却计时器（不再每帧触发/狂播音效）",
		"B18 满血分支仍写 _cooldown_timer，站在泉上会每帧触发")


# ============================================================================
# B19 —— swing_started / swing_finished 成对
# ============================================================================

func _check_b19_swing_signal_pairing() -> void:
	print("")
	print("--- B19：挥砍信号成对 ---")
	var ctrl: AttackController = AttackController.new()
	# 【为什么必须 add_child】时间轴完全由 _process(delta) 推进（_phase_timer -= delta）。
	#   上层 add_child 进来才谈得上调 _process，挂空气里跑一万帧也停在 STARTUP：
	#   started/finished 恒为 0，会把"实现没修好"这个结论安到无辜的生产代码头上。
	#   同时把攻击贴图/判定盒路径留空，控制器就只跑时间轴，不碰任何场景节点。
	add_child(ctrl)
	var attack: AttackData = AttackData.new()
	attack.startup = 0.05
	attack.active = 0.05
	attack.recovery = 0.05

	var started: Array = [0]
	var finished: Array = [0]
	ctrl.swing_started.connect(func(_d: AttackData) -> void: started[0] += 1)
	ctrl.swing_finished.connect(func(_d: AttackData) -> void: finished[0] += 1)

	# 正常跑完一整段：进出必须各一次。
	ctrl.request_attack(attack)
	for _i: int in 60:
		await get_tree().process_frame
		if not ctrl.is_attacking():
			break
	_check(started[0] == 1 and finished[0] == 1,
		"B19 完整挥砍：started/finished 各 1 次",
		"B19 完整挥砍信号不成对（started=%d finished=%d）" % [started[0], finished[0]])

	# 判定窗口内被中断：必须补发 finished，否则刀光/音效永不回收。
	started[0] = 0
	finished[0] = 0
	ctrl.request_attack(attack)
	# 等进 ACTIVE（started 已发）再打断。
	for _i: int in 60:
		await get_tree().process_frame
		if started[0] > 0:
			break
	ctrl.interrupt()
	_check(started[0] == 1 and finished[0] == 1,
		"B19 判定窗口被打断时补发 finished（started/finished 仍成对）",
		"B19 打断后 finished 未补发（started=%d finished=%d）→ 刀光/音效泄漏"
			% [started[0], finished[0]])

	# 前摇内被打断：started 还没发，就不该凭空发一个 finished。
	started[0] = 0
	finished[0] = 0
	var slow: AttackData = AttackData.new()
	slow.startup = 5.0
	slow.active = 0.05
	slow.recovery = 0.05
	ctrl.request_attack(slow)
	await _frames(2)
	ctrl.interrupt()
	_check(started[0] == 0 and finished[0] == 0,
		"B19 前摇内被打断不会发出无配对的 finished",
		"B19 前摇打断发出了孤立 finished（started=%d finished=%d）" % [started[0], finished[0]])
	ctrl.queue_free()
	await _frames(1)


# ============================================================================
# B20 —— 受击抖动不累积偏移
# ============================================================================

func _check_b20_shake_origin() -> void:
	print("")
	print("--- B20：受击抖动基准位置 ---")
	var a: Actor = _make_actor(100.0, false, 0.0)
	var sprite: Node2D = Node2D.new()
	sprite.name = "Sprite"
	a.add_child(sprite)
	# _resolve_nodes 会把 "Sprite" 认成 _sprite；这里直接注入保证确定性。
	a.set("_sprite", sprite)
	a.set("_sprite_origin", sprite.position)
	a.set("_has_sprite_origin", true)

	# 连打 6 次抖动，每次都在上一次还没归位时就重开。
	for _i: int in 6:
		a.call("_shake_sprite", 3.0, 0.12)
		await _frames(2)
	# 等最后一段动画跑完。
	await get_tree().create_timer(0.4).timeout
	_check(sprite.position.is_equal_approx(Vector2.ZERO),
		"B20 反复受击后精灵回到基准位置（不再累积永久偏移）",
		"B20 精灵偏移漂移到了 %s" % sprite.position)
	a.free()


# ============================================================================
# B23 —— 新 Boss 绑定时旧淡出回调不会隐藏它
# ============================================================================

func _check_b23_boss_bar_rebind() -> void:
	print("")
	print("--- B23：Boss 血条重绑 ---")
	var bar: CanvasLayer = load("res://scenes/ui/boss_health_bar.tscn").instantiate() as CanvasLayer
	bar.name = "BossHealthBar"
	get_tree().root.add_child.call_deferred(bar)
	await _frames(3)

	var old_boss: EnemyBase = EnemyBase.new()
	var new_boss: EnemyBase = EnemyBase.new()
	var d1: EnemyData = EnemyData.new()
	d1.display_name = "旧 Boss"
	var d2: EnemyData = EnemyData.new()
	d2.display_name = "新 Boss"
	old_boss.set("enemy_data", d1)
	new_boss.set("enemy_data", d2)
	var cd: CharacterData = CharacterData.new()
	cd.max_health = 100.0
	old_boss.set("data", cd)
	new_boss.set("data", cd)
	old_boss.call("_resolve_nodes")
	new_boss.call("_resolve_nodes")
	var container: Control = bar.get("_container") as Control

	bar.call("_bind", old_boss)
	await _frames(2)
	# 旧 Boss 死亡 → 挂起一个 0.5s 后 _unbind 的淡出补间。
	bar.call("_on_boss_died", null, old_boss)
	await _frames(2)
	# 紧接着绑新 Boss（模拟 0.5 秒内进下一个 Boss 房）。
	bar.call("_bind", new_boss)
	# 熬过旧补间的到期时间。
	await get_tree().create_timer(0.9).timeout
	var visible_now: bool = container.visible and bar.get("_boss") == new_boss
	_check(visible_now,
		"B23 旧 Boss 的淡出回调不会隐藏新绑定的血条",
		"B23 新血条被旧回调隐藏了（visible=%s boss=%s）"
			% [container.visible, bar.get("_boss")])

	old_boss.free()
	new_boss.free()
	bar.queue_free()
	await _frames(2)


# ============================================================================
# B24 —— Boss 房清场顺序（奖励不丢）
# ============================================================================

func _check_b24_boss_room_reward() -> void:
	print("")
	print("--- B24：Boss 房清场顺序 ---")
	var raw: String = FileAccess.get_file_as_string("res://scripts/world/level_runtime.gd")
	# _spawn_bosses() 必须出现在"0 敌人即置位清空"之前，且 _spawn_enemies 里
	# 不能再自己 _mark_cleared()。
	#
	# 【为什么要剥注释】_spawn_enemies() 结尾那段【为什么这里不能 _mark_cleared()】
	#   的说明里原样写了 `_mark_cleared()`。断言"函数体里不含 _mark_cleared()"
	#   会被这行注释直接证伪——真正该被检查的是代码，不是解释代码的文字。
	var src: String = _strip_comment_lines(raw)
	var boss_call: int = src.find("_spawn_bosses()")
	var cleared_assign: int = src.find("_cleared = true")
	var spawn_boss: int = src.find("func _spawn_bosses")
	var enemies_body: String = ""
	_check(boss_call != -1 and cleared_assign != -1 and boss_call < cleared_assign,
		"B24 先刷 Boss 再判定清场（Boss 死后仍能拿到三选一奖励）",
		"B24 清场判定仍抢在刷 Boss 之前")
	# 直接从函数体切，不靠"两个 func 的下标相减"——后者一旦漏剥注释就会把注释也算进去。
	enemies_body = _function_body("res://scripts/world/level_runtime.gd", "func _spawn_enemies")
	_check(not enemies_body.contains("_mark_cleared()"),
		"B24 _spawn_enemies 不再自行置位清空",
		"B24 _spawn_enemies 仍会自行 _mark_cleared()")
	# 反向兜底：确保上面剥掉的只是注释，不是整个函数体被剥空导致假绿。
	_check(enemies_body.contains("_alive_enemies = spawned"),
		"B24 断言作用在真实函数体上（非空壳）",
		"B24 函数体提取失败，断言失去意义")


# ============================================================================
# B28 —— 多个交互物重叠时按距离择优
# ============================================================================

func _check_b28_interactable_nearest() -> void:
	print("")
	print("--- B28：交互物就近择优 ---")
	var src: String = _strip_comment_lines(
		FileAccess.get_file_as_string("res://scripts/world/interactable.gd"))
	_check(src.contains("func _pick_nearest_in_range") and src.contains("get_nodes_in_group(&\"interactable\")"),
		"B28 F 键走就近择优仲裁（不再由树序最后的那个吃掉按键）",
		"B28 交互物仍按树序抢按键")
	_check(src.contains("add_to_group(&\"interactable\")"),
		"B28 交互物在基类自动入组（子类无需各自登记）",
		"B28 交互物未入组，择优逻辑会永远找不到候选")


# ============================================================================
# B30 —— 重击进入 ATTACK 状态（受 attack_move_mult 约束）
# ============================================================================

func _check_b30_heavy_attack_state() -> void:
	print("")
	print("--- B30：重击进入攻击状态 ---")
	var release_body: String = _function_body("res://scripts/player/player.gd", "func _release_charge")
	_check(release_body.contains("_enter_state(State.ATTACK)"),
		"B30 释放重击时进入 ATTACK 状态（与轻击一样吃减速，不能全速跑放）",
		"B30 重击仍不进 ATTACK 状态")


# ============================================================================
# B31 —— 土狼时间接入 can_act()
# ============================================================================

func _check_b31_coyote_time() -> void:
	print("")
	print("--- B31：土狼时间 ---")
	var src: String = _strip_comment_lines(
		FileAccess.get_file_as_string("res://scripts/player/player.gd"))
	var body: String = _function_body("res://scripts/player/player.gd", "func can_act")
	_check(body.contains("_coyote_timer"),
		"B31 can_act() 读 _coyote_timer（土狼时间真正生效）",
		"B31 can_act() 仍不读 _coyote_timer，土狼时间形同虚设")
	# 翻滚与攻击结束都要给窗口。
	_check(src.count("_coyote_timer = coyote_time") >= 2,
		"B31 翻滚与攻击结束时都给出土狼时间窗口",
		"B31 只有一处赋值，另一条路径没有土狼时间")


# ============================================================================
# B32 —— play_anim 的 restart 不再被 setter 吞掉
# ============================================================================

func _check_b32_anim_restart() -> void:
	print("")
	print("--- B32：动画 restart ---")
	var spr: ActorSprite = ActorSprite.new()
	# 【为什么要补 hframes/vframes】ActorSprite._ready() 里才把分帧兜底成 4×7，
	#   而脱离场景树的桩不会走 _ready()，vframes 还是默认的 1 →
	#   frame_coords = (col, row) 一设就报 "out of bounds (vframes = 1)"。
	#   这不是被测代码的问题（真精灵表在 _ready 后必定是 4×7），补上即可消音。
	spr.hframes = 4
	spr.vframes = 7
	spr.animation = &"attack"
	spr.set("_frame_index", 5.0)
	# 同名 + restart=true 必须把帧归零。
	spr.play_anim(&"attack", true)
	var after_restart: float = float(spr.get("_frame_index"))
	_check(is_equal_approx(after_restart, 0.0),
		"B32 play_anim(同名, restart=true) 归零帧（连击第二段会重播动画）",
		"B32 restart 被 setter 吞掉，帧仍停在 %s" % after_restart)

	# 同名 + restart=false 不应重置（走路不抖）。
	spr.set("_frame_index", 3.0)
	spr.play_anim(&"attack", false)
	var keep: float = float(spr.get("_frame_index"))
	_check(is_equal_approx(keep, 3.0),
		"B32 play_anim(同名, restart=false) 保持当前帧",
		"B32 不 restart 的重复调用把帧重置了（走路会抖）")
	spr.free()


# ============================================================================
# 汇总
# ============================================================================

func _report() -> void:
	print("")
	print("############################################")
	print("审计修复项回归：%d 通过，%d 失败" % [_pass, _fail.size()])
	for f: String in _fail:
		print("  ✗ ", f)
	print("############################################")
