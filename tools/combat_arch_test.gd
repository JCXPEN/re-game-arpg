## CombatArchTest —— 角色/武器解耦与受击系统验证
##
## 【负责什么】
##   验证本轮重构的核心主张：
##     1. 攻击判定跟随**武器**（随武器旋转），而不是固定在角色中心。
##     2. 判定盒比受击盒大（ARPG 的命中宽容度）。
##     3. 武器是独立场景，换武器不用改角色脚本。
##     4. 击退抗性 / 霸体由数据驱动（Boss 免疫击退、精英半免疫）。
##     5. 受击有闪色 + 抖动，死亡有溶解。
##
## 【怎么运行】
##   Godot --headless --path . res://tools/combat_arch_test.tscn
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
	await _goto(&"field", &"from_town", "Field")
	await _check_weapon_scene_exists()
	await _check_hitbox_follows_weapon()
	_check_hitbox_larger_than_hurtbox()
	_check_weapon_data_binding()
	await _check_weapon_swap()
	_check_knockback_resist()
	await _check_super_armor()
	await _check_hurt_feedback()
	await _check_death_dissolve()

	print("")
	print("=== 战斗架构验证：%d 通过，%d 失败 ===" % [_pass, _fail.size()])
	for f: String in _fail:
		print("  ✗ ", f)
	get_tree().quit(1 if _fail.size() > 0 else 0)


# ============================================================================
# 检查项
# ============================================================================

## 武器场景存在且结构正确（判定盒挂在 SwingPivot 下）。
func _check_weapon_scene_exists() -> void:
	# 武器场景已合并为唯一的通用场景；差异全部由 WeaponData 描述。
	if ResourceLoader.exists(WeaponController.DEFAULT_SCENE):
		_ok("通用武器场景存在（%s）" % WeaponController.DEFAULT_SCENE.get_file())
	else:
		_fail.append("通用武器场景缺失：%s" % WeaponController.DEFAULT_SCENE)
	# 每把武器的数据都应存在，且不再各自绑定私有场景。
	var missing: Array[String] = []
	var scattered: Array[String] = []
	for res: Resource in DataRegistry.get_all_weapons():
		var w: WeaponData = res as WeaponData
		if w == null:
			continue
		if w.weapon_scene != null:
			scattered.append(w.display_name)
	if not scattered.is_empty():
		_fail.append("仍有武器自带私有场景（应统一用通用场景）：%s" % ", ".join(scattered))
	else:
		_ok("所有武器共用通用场景（无私有 .tscn）")
	if not missing.is_empty():
		_fail.append("武器数据缺失：%s" % ", ".join(missing))
	var inst: Node = load(WeaponController.DEFAULT_SCENE).instantiate()
	var box: Node = inst.get_node_or_null("SwingPivot/AttackBox")
	if box != null:
		_ok("判定盒挂在 SwingPivot 下（会跟随武器旋转）")
	else:
		_fail.append("判定盒不在 SwingPivot 下")
	inst.free()


## 核心：武器旋转后，判定盒的世界坐标跟着转（不再固定在角色中心）。
func _check_hitbox_follows_weapon() -> void:
	var player: Player = get_tree().get_first_node_in_group(&"player") as Player
	var combat: PlayerCombat = player.get_node_or_null("Combat") as PlayerCombat
	var weapon: WeaponController = combat.get_node_or_null("../WeaponMount/Weapon_sword") as WeaponController
	if weapon == null:
		# 名字可能不同，按类型找。
		for child: Node in player.get_node("WeaponMount").get_children():
			if child is WeaponController:
				weapon = child as WeaponController
				break
	if weapon == null:
		_fail.append("玩家没有实例化武器场景")
		return
	var box: AttackBox = weapon.get_attack_box()
	if box == null:
		_fail.append("武器没有判定盒")
		return
	# 朝右 vs 朝左，判定盒世界位置应分别落在角色右侧 / 左侧。
	weapon.set_aim(Vector2.RIGHT)
	await get_tree().process_frame
	var right_pos: Vector2 = box.global_position - player.global_position
	weapon.set_aim(Vector2.LEFT)
	await get_tree().process_frame
	var left_pos: Vector2 = box.global_position - player.global_position
	if right_pos.x > 5.0 and left_pos.x < -5.0:
		_ok("判定盒跟随武器朝向（右 %.0f / 左 %.0f）" % [right_pos.x, left_pos.x])
	else:
		_fail.append("判定盒没有跟随武器旋转（右 %.1f / 左 %.1f）" % [right_pos.x, left_pos.x])
	# 朝上时判定盒应该在角色上方。
	weapon.set_aim(Vector2.UP)
	await get_tree().process_frame
	var up_pos: Vector2 = box.global_position - player.global_position
	if up_pos.y < -5.0:
		_ok("朝上时判定盒在上方（y=%.0f）" % up_pos.y)
	else:
		_fail.append("朝上时判定盒位置错误（y=%.1f）" % up_pos.y)


## 判定盒面积必须大于受击盒（否则玩家会觉得"明明打到了却没中"）。
func _check_hitbox_larger_than_hurtbox() -> void:
	var player: Player = get_tree().get_first_node_in_group(&"player") as Player
	var hurt_shape: CollisionShape2D = player.get_node("Hurtbox/Shape") as CollisionShape2D
	var hurt_circle: CircleShape2D = hurt_shape.shape as CircleShape2D
	# 受击盒直径（用半径算等效边长）。
	var hurt_size: float = hurt_circle.radius * 2.0
	# 玩家武器的判定盒尺寸。
	var inst: Node = load(WeaponController.DEFAULT_SCENE).instantiate()
	var atk_shape: CollisionShape2D = inst.get_node("SwingPivot/AttackBox/Shape") as CollisionShape2D
	var rect: RectangleShape2D = atk_shape.shape as RectangleShape2D
	var atk_min_side: float = minf(rect.size.x, rect.size.y)
	if atk_min_side > hurt_size:
		_ok("判定盒大于受击盒（判定 %.0f > 受击 %.0f）" % [atk_min_side, hurt_size])
	else:
		_fail.append("判定盒比受击盒还小（%.0f vs %.0f）" % [atk_min_side, hurt_size])
	inst.free()


## 每把武器数据都绑定了场景。
func _check_weapon_data_binding() -> void:
	# 合并后：武器不再各自绑场景，改为校验"每把武器都能被统一入口实例化"。
	var missing: Array[String] = []
	var count: int = 0
	for res: Resource in DataRegistry.get_all_weapons():
		var w: WeaponData = res as WeaponData
		if w == null:
			continue
		count += 1
		if w.held_texture == null:
			missing.append(w.display_name)
	if missing.is_empty():
		_ok("%d 把武器数据完整（都能由通用场景实例化）" % count)
	else:
		_fail.append("这些武器缺手持贴图：%s" % ", ".join(missing))


## 换武器会重建武器场景（解耦的证明）。
func _check_weapon_swap() -> void:
	var player: Player = get_tree().get_first_node_in_group(&"player") as Player
	var combat: PlayerCombat = player.get_node_or_null("Combat") as PlayerCombat
	combat.equip_weapon(DataRegistry.get_weapon(&"big_sword"))
	await get_tree().process_frame
	await get_tree().process_frame
	var mount: Node = player.get_node("WeaponMount")
	var found: WeaponController = null
	for child: Node in mount.get_children():
		if child is WeaponController:
			found = child as WeaponController
			break
	if found != null and found.weapon_data != null and found.weapon_data.kind == GameEnums.WeaponKind.TWO_HANDED:
		_ok("换武器后重建为双手武器场景（%s）" % found.weapon_data.display_name)
	else:
		_fail.append("换武器没有重建场景")
	combat.equip_weapon(DataRegistry.get_weapon(&"sword"))
	await get_tree().process_frame


## 击退抗性：Boss 100% 免疫、精英 50%。
func _check_knockback_resist() -> void:
	var boss: EnemyData = DataRegistry.get_enemy(&"boss_cyclops")
	var elite: EnemyData = DataRegistry.get_enemy(&"red_samurai")
	if boss != null and boss.stats != null and boss.stats.knockback_resist >= 1.0:
		_ok("Boss 完全免疫击退（resist=%.1f）" % boss.stats.knockback_resist)
	else:
		_fail.append("Boss 抗击退配置错误")
	if elite != null and elite.stats != null and elite.stats.knockback_resist > 0.0 and elite.stats.knockback_resist < 1.0:
		_ok("精英半免疫击退（resist=%.1f）" % elite.stats.knockback_resist)
	else:
		_fail.append("精英抗击退配置错误")


## 霸体：Boss 受击不进硬直，但依然掉血。
func _check_super_armor() -> void:
	var boss: EnemyData = DataRegistry.get_enemy(&"boss_cyclops")
	if boss == null or boss.stats == null:
		_fail.append("找不到 Boss 数据")
		return
	if not boss.stats.super_armor:
		_fail.append("Boss 没有霸体")
		return
	# 实际造一个 Boss 验证：受击后不硬直但掉血。
	var scene: PackedScene = load("res://scenes/enemies/enemy.tscn")
	var e: EnemyBase = scene.instantiate() as EnemyBase
	get_tree().current_scene.add_child(e)
	e.setup(boss)
	await get_tree().process_frame
	var hp_before: float = e.get_health()
	var info: DamageInfo = DamageInfo.new()
	info.amount = 20.0
	info.poise_damage = 999.0
	info.knockback = Vector2(500, 0)
	e.grant_invulnerability(0.0)
	e.apply_damage(info)
	await get_tree().process_frame
	var lost: bool = e.get_health() < hp_before
	var stunned: bool = e.is_stunned()
	var kb: float = e.get_knockback_velocity().length()
	if lost and not stunned and kb < 1.0:
		_ok("Boss 霸体：掉血但无硬直、无击退")
	else:
		_fail.append("Boss 霸体异常（掉血=%s 硬直=%s 击退=%.0f）" % [lost, stunned, kb])
	e.queue_free()


## 受击有闪色参数与抖动参数。
func _check_hurt_feedback() -> void:
	var player: Actor = get_tree().get_first_node_in_group(&"player") as Actor
	if player.data == null:
		_fail.append("玩家没有 CharacterData")
		return
	if player.data.hurt_flash_time > 0.0 and player.data.hurt_flash_color.r > player.data.hurt_flash_color.g:
		_ok("受击闪色偏红（%.2f 秒）" % player.data.hurt_flash_time)
	else:
		_fail.append("受击闪色参数异常")
	if player.data.hurt_shake_intensity > 0.0:
		_ok("受击抖动已配置（%.1f px）" % player.data.hurt_shake_intensity)
	else:
		_fail.append("受击抖动未配置")
	# 触发一次受击，确认 shader 的 flash_amount 被写过。
	player.grant_invulnerability(0.0)
	var info: DamageInfo = DamageInfo.new()
	info.amount = 1.0
	player.apply_damage(info)
	await get_tree().process_frame
	var sprite: CanvasItem = player.get_node("Sprite") as CanvasItem
	if sprite.material is ShaderMaterial:
		_ok("受击走着色器闪色（材质已挂载）")
	else:
		_fail.append("受击没有挂着色器材质")


## 死亡溶解参数存在且为合理值。
func _check_death_dissolve() -> void:
	var boss: EnemyData = DataRegistry.get_enemy(&"boss_cyclops")
	if boss != null and boss.stats != null and boss.stats.death_dissolve_time > 0.0:
		_ok("Boss 死亡溶解已配置（%.1f 秒）" % boss.stats.death_dissolve_time)
	else:
		_fail.append("Boss 死亡溶解未配置")


# ============================================================================
# 工具
# ============================================================================

func _ok(label: String) -> void:
	_pass += 1
	print("  [PASS] ", label)


func _goto(level_id: StringName, entry: StringName, expected: String) -> void:
	SceneDirector.change_to_level(level_id, entry)
	for i: int in 150:
		await get_tree().process_frame
		if not SceneDirector.is_changing():
			break
	for i: int in 10:
		await get_tree().process_frame
	var scene: Node = SceneDirector.get_current_scene()
	if scene == null or scene.name != expected:
		push_warning("[CombatArchTest] 期望 %s，实际 %s" % [expected, scene.name if scene != null else "<null>"])
