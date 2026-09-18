## MaterialIsolationTest —— 受击材质的**每实例隔离**回归
##
## 【负责什么】
##   钉死"一个敌人被打红，其余实例同时全部变红"这个缺陷不会复发。
##
##   根因：场景把同一个 ShaderMaterial 子资源同时挂在根节点与 Sprite 上，而 Godot
##   的子资源**默认在所有场景实例间共享**。旧代码对"已经是 ShaderMaterial"的
##   Sprite 不做复制，直接改共享对象的 flash_amount → 全体敌人一起红。
##
##   本测试的行为：生成多个敌人实例，只对其中一个施加受击反馈，断言
##     · 被打的那个 flash_amount 上升（确实生效了）；
##     · **其余实例的 flash_amount 保持为 0**（隔离成立）；
##     · 各实例的 Sprite.material 是**不同对象**；
##     · 素材模板本身不被改动（模板 flash_amount 仍为 0）。
##
## 【怎么运行】Godot --headless --path . res://tools/material_isolation_test.tscn
extends Node

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []

func _ready() -> void:
	print("")
	print("################################################")
	print("#  受击材质每实例隔离")
	print("################################################")
	await get_tree().process_frame
	await _test_enemy_material_isolation()
	await _test_player_material_isolation()
	await _test_elite_outline_isolation()

	print("")
	print("################################################")
	print("# 材质隔离：%d 通过，%d 失败" % [_pass, _fail])
	for f: String in _fails:
		print("  - " + f)
	print("################################################")
	get_tree().quit(1 if _fail > 0 else 0)


## A. 多个敌人：只打一个，其余不受影响。
func _test_enemy_material_isolation() -> void:
	print("")
	print("--- A. 敌人之间 ---")
	var enemies: Array[Node] = await _spawn_enemies(3)
	if enemies.size() < 3:
		_field("生成 3 个敌人", false, "只生成了 %d 个" % enemies.size())
		return
	var mats: Array[ShaderMaterial] = []
	for e: Node in enemies:
		mats.append(_sprite_material(e))
	_field("每个敌人都有材质", mats.all(func(m: ShaderMaterial) -> bool: return m != null),
		"有敌人没有材质")
	# 三者必须是不同对象（共享即失败）。
	var distinct: bool = mats[0] != mats[1] and mats[1] != mats[2] and mats[0] != mats[2]
	_field("敌人各自持有不同材质对象", distinct,
		"材质被共享！obj0=%s obj1=%s obj2=%s" % [str(mats[0]), str(mats[1]), str(mats[2])])

	# 只让第 0 个敌人受击。
	var target: Node = enemies[0]
	(target as Actor).apply_damage(_damage(5.0))
	await _frames(2)
	var v0: float = float(mats[0].get_shader_parameter("flash_amount"))
	var v1: float = float(mats[1].get_shader_parameter("flash_amount"))
	var v2: float = float(mats[2].get_shader_parameter("flash_amount"))
	_field("被打的敌人闪白生效", v0 > 0.5, "flash_amount=%.2f" % v0)
	_field("其余敌人**没有**跟着变红", v1 < 0.01 and v2 < 0.01,
		"隔离失败：obj1=%.2f obj2=%.2f（一个受击全体闪红）" % [v1, v2])

	# 素材模板本身不能被污染。
	var template: ShaderMaterial = (enemies[0] as Actor).flash_material
	if template != null:
		_field("共享模板未被污染", float(template.get_shader_parameter("flash_amount")) < 0.01,
			"模板 flash_amount=%.2f（后续新生成的敌人会自带红色）"
				% float(template.get_shader_parameter("flash_amount")))
	_cleanup(enemies)


## B. 玩家与敌人之间也不能互相影响。
func _test_player_material_isolation() -> void:
	print("")
	print("--- B. 玩家 vs 敌人 ---")
	var enemies: Array[Node] = await _spawn_enemies(1)
	if enemies.is_empty():
		_field("生成敌人", false, "失败")
		return
	# 造一个"玩家等价物"：裸 Actor + 显式 Sprite 子节点 + 同一套闪白材质模板。
	# （直接 Actor.new() 没有 Sprite 子节点，材质路径走不到，故手动挂一个。）
	var player: Actor = Actor.new()
	player.name = "IsoPlayer"
	player.data = load("res://data/characters/player.tres")
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = "Sprite"
	player.add_child(sprite)
	var tmpl: ShaderMaterial = ShaderMaterial.new()
	tmpl.shader = load("res://shaders/hit_flash.gdshader")
	player.flash_material = tmpl
	get_tree().root.add_child(player)
	await _frames(2)

	var pm: ShaderMaterial = _sprite_material(player)
	var em: ShaderMaterial = _sprite_material(enemies[0])
	if pm == null or em == null:
		_field("玩家/敌人都有材质", false, "pm=%s em=%s" % [str(pm), str(em)])
	else:
		_field("玩家与敌人材质是不同对象", pm != em, "材质被共享")
		(player as Actor).apply_damage(_damage(3.0))
		await _frames(2)
		_field("玩家受击不影响敌人", float(em.get_shader_parameter("flash_amount")) < 0.01,
			"敌人 flash_amount=%.2f（玩家受击把敌人也染红了）"
				% float(em.get_shader_parameter("flash_amount")))
	player.queue_free()
	_cleanup(enemies)


## C. 精英描边也不能波及普通敌人。
func _test_elite_outline_isolation() -> void:
	print("")
	print("--- C. 精英描边隔离 ---")
	var elite_scene: PackedScene = load("res://scenes/enemies/enemy.tscn")
	if elite_scene == null:
		_field("敌人场景可加载", false, "缺 enemy.tscn")
		return
	var elite: Node = elite_scene.instantiate()
	var plain: Node = elite_scene.instantiate()
	get_tree().root.add_child(elite)
	get_tree().root.add_child(plain)
	await _frames(2)
	# 手工注入数据：一个精英、一个普通（两者都必须有数据，否则描边逻辑读空指针）。
	var edata: EnemyData = load("res://data/enemies/skeleton.tres")
	if edata == null:
		_field("找到敌人数据", false, "缺 skeleton.tres")
		elite.free(); plain.free()
		return
	# duplicate 一份精英数据，避免污染共享的 .tres。
	var elite_data: EnemyData = edata.duplicate(true) as EnemyData
	elite_data.is_elite = true
	elite.set("enemy_data", elite_data)
	plain.set("enemy_data", edata)
	elite.call("_apply_enemy_data")
	elite.call("_apply_elite_outline")
	plain.call("_apply_enemy_data")
	plain.call("_apply_elite_outline")
	await _frames(2)

	var em: ShaderMaterial = _sprite_material(elite)
	var pm: ShaderMaterial = _sprite_material(plain)
	if em == null or pm == null:
		_field("精英/普通都有材质", false, "elite=%s plain=%s" % [str(em), str(pm)])
	else:
		_field("精英有描边", float(em.get_shader_parameter("outline_amount")) > 0.5,
			"elite outline=%.2f" % float(em.get_shader_parameter("outline_amount")))
		_field("普通敌人没有描边", float(pm.get_shader_parameter("outline_amount")) < 0.01,
			"plain outline=%.2f（精英描边串到了普通敌人）"
				% float(pm.get_shader_parameter("outline_amount")))
		_field("精英/普通材质是不同对象", em != pm, "材质被共享")
	elite.free(); plain.free()


# ============================================================================
# 工具
# ============================================================================

func _spawn_enemies(n: int) -> Array[Node]:
	var out: Array[Node] = []
	var scene: PackedScene = load("res://scenes/enemies/enemy.tscn")
	if scene == null:
		return out
	var data: EnemyData = load("res://data/enemies/skeleton.tres")
	for i: int in n:
		var e: Node = scene.instantiate()
		e.name = "IsoEnemy%d" % i
		if data != null:
			e.set("enemy_data", data)
		get_tree().root.add_child(e)
		out.append(e)
	await _frames(2)
	# 手动应用数据（不依赖 LevelRuntime），确保材质路径被走到。
	for e: Node in out:
		e.call("_apply_enemy_data")
	await _frames(2)
	return out


func _sprite_material(actor: Node) -> ShaderMaterial:
	if actor == null or not is_instance_valid(actor):
		return null
	var sprite: Node = actor.get_node_or_null("Sprite")
	if sprite == null:
		return null
	return (sprite as CanvasItem).material as ShaderMaterial


func _damage(amount: float) -> DamageInfo:
	var info: DamageInfo = DamageInfo.new()
	info.amount = amount
	info.source = null
	return info


func _cleanup(nodes: Array[Node]) -> void:
	for n: Node in nodes:
		if is_instance_valid(n):
			n.queue_free()


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


func _frames(n: int) -> void:
	for _i: int in n:
		await get_tree().process_frame
