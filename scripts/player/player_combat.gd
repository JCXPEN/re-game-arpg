## PlayerCombat —— 玩家战斗中枢（武器 / 法术 / 技能）
##
## 【负责什么】
##   把玩家的攻击、法术、技能请求路由到对应子系统，并维护"当前武器、冷却表、
##   蓄力状态、移动速度倍率"。它是战斗系统的**唯一入口**，UI 与 Player 都只跟它说话。
##
## 【挂哪个节点】
##   scenes/player/player.tscn 里的 Combat 节点（Node）。
##   @export 引用 AttackController / AttackBox / 法术与技能槽资源。
##
## 【依赖谁】
##   AttackController（攻击时间轴）、WeaponData / SpellData / AbilityData、
##   CooldownTracker（冷却）、EventBus。
##
## 【怎么扩展】
##   加"武器切换"只需换 current_weapon 并刷新 held 贴图；加新技能类型在 Ability
##   子类里实现，这里只负责按槽位调用。数值一律来自 .tres。
class_name PlayerCombat
extends Node

# ============================================================================
# 信号
# ============================================================================

## 武器切换。
signal weapon_changed(weapon: WeaponData)
## 冷却变化（UI 用）。slot 为槽位名，ratio 为剩余比例 0~1。
signal cooldown_changed(slot: StringName, ratio: float)

# ============================================================================
# @export
# ============================================================================

## 攻击控制器。
@export var attack_controller_path: NodePath
## 手持武器贴图节点（叠在角色上）。可空——武器场景化后由武器自己显示贴图。
@export var held_weapon_sprite_path: NodePath
## 武器场景的挂载父节点。留空则挂到玩家自己身上。
@export var weapon_parent_path: NodePath
## 弹道生成用的父节点（通常留空，默认挂到当前场景）。
@export var projectile_parent_path: NodePath

## 当前武器数据。
@export var current_weapon: WeaponData
## 法术槽（3 个）。元素 × 形态的组合在 .tres 里配。
@export var spell_slots: Array[SpellData] = [null, null, null]
## 主动技能槽（2 个）。
@export var ability_slots: Array[AbilityData] = [null, null]

# ============================================================================
# 私有变量
# ============================================================================

## 所属玩家。
var _player: Actor
## 精灵（用于朝向）。
var _sprite: ActorSprite
## 攻击控制器引用。
var _attack_controller: AttackController
## 手持武器贴图（旧的兼容字段）。
var _held_sprite: Sprite2D
## 当前武器场景实例。
var _weapon_instance: WeaponController
## 武器挂载父节点。
var _weapon_parent: Node2D
## 冷却表：{ StringName: float(剩余秒) }。
var _cooldowns: Dictionary = {}
## 冷却总时长表：{ StringName: float(总秒) }，用于算 UI 比例。
var _cooldown_max: Dictionary = {}
## 当前蓄力时间。
var _charge_time: float = 0.0
## 是否正在蓄力。
var _charging: bool = false
## 当前移动速度倍率（蓄力/吟唱时降低）。
var _move_multiplier: float = 1.0
## 附魔覆盖的攻击数据及其剩余时间。
var _enchant_attack: AttackData
var _enchant_timer: float = 0.0

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	if not attack_controller_path.is_empty():
		_attack_controller = get_node_or_null(attack_controller_path) as AttackController
	if not held_weapon_sprite_path.is_empty():
		_held_sprite = get_node_or_null(held_weapon_sprite_path) as Sprite2D
	if not weapon_parent_path.is_empty():
		_weapon_parent = get_node_or_null(weapon_parent_path) as Node2D


func _process(delta: float) -> void:
	_tick_cooldowns(delta)
	_tick_charge(delta)
	_tick_enchant(delta)
	_update_held_weapon_facing()
	# 每帧把瞄准方向喂给武器——武器据此旋转，判定盒跟着转。
	if _weapon_instance != null and is_instance_valid(_weapon_instance):
		_weapon_instance.set_aim(_aim_direction())


# ============================================================================
# 公开方法
# ============================================================================

## 由 Player 在 _ready 时调用，注入依赖。
func setup(player: Actor, sprite: ActorSprite) -> void:
	_player = player
	_sprite = sprite
	_instantiate_weapon()


## 请求普攻（走武器连段）。
func request_light_attack() -> void:
	if _attack_controller == null or current_weapon == null:
		return
	var data: AttackData = _enchant_attack if _enchant_attack != null else current_weapon.combo_1
	if data == null:
		return
	# 远程武器不走攻击时间轴，而是发射弹道。
	if current_weapon.kind == GameEnums.WeaponKind.RANGED:
		_fire_projectiles()
		return
	# 连击：如果控制器正在打且还没结束，request_attack 会自动缓冲/接段。
	_attack_controller.request_attack(data)
	AudioManager.play_sfx(current_weapon.swing_sfx)


## 开始蓄力。翻滚/硬直中不允许起手。
func begin_charge() -> void:
	if current_weapon == null or current_weapon.heavy_attack == null:
		return
	# 翻滚/硬直/死亡中不能蓄力，否则会出现"翻滚无敌期间蓄力"的越权操作。
	if not _can_start_action():
		return
	_charging = true
	_charge_time = 0.0
	if _attack_controller != null:
		_attack_controller.set_charging(true)


## 取消蓄力（被打断 / 进入翻滚时调用）。
## 必须走这里而不是直接改 _charging：移速惩罚是在 _tick_charge 里累积的，
## 只清标志位会让 _move_multiplier 永远停在蓄力值上（角色永久变慢）。
func cancel_charge() -> void:
	if not _charging:
		# 即使没在蓄力也把倍率复位，防止其它路径漏掉。
		_move_multiplier = 1.0
		return
	_charging = false
	_charge_time = 0.0
	_move_multiplier = 1.0
	if _attack_controller != null:
		_attack_controller.set_charging(false)


## 是否正在蓄力（供 Player 决定要不要进入 ATTACK 状态）。
func is_charging() -> bool:
	return _charging


## 释放蓄力。达到 charge_time 时打出满蓄力重击，否则打出普通重击。
func release_charge() -> void:
	if not _charging:
		return
	# 翻滚/硬直/死亡中松手不该出招（无敌帧内白嫖输出的漏洞）。
	# 注意：这里要先复位移速，否则取消后仍会残留减速。
	if not _can_start_action():
		cancel_charge()
		return
	_charging = false
	if _attack_controller != null:
		_attack_controller.set_charging(false)
	_move_multiplier = 1.0
	if current_weapon == null or current_weapon.heavy_attack == null:
		return
	# 未蓄满也能出招，但伤害/范围按比例打折——这样"短按重击"也有意义。
	var ratio: float = clampf(_charge_time / maxf(current_weapon.charge_time, 0.01), 0.0, 1.0)
	var heavy: AttackData = current_weapon.heavy_attack.duplicate() as AttackData
	heavy.damage *= lerpf(0.5, 1.0, ratio)
	heavy.knockback *= lerpf(0.6, 1.0, ratio)
	heavy.hitstop *= lerpf(0.7, 1.3, ratio)
	if _attack_controller != null:
		_attack_controller.request_attack(heavy)
	AudioManager.play_sfx(current_weapon.swing_sfx)


## 释放第 index 个法术槽。
func cast_spell(index: int) -> bool:
	if index < 0 or index >= spell_slots.size():
		return false
	var spell: SpellData = spell_slots[index]
	if spell == null or not _is_off_cooldown(&"spell_%d" % index):
		return false
	if _player == null or not _player.spend_mana(spell.mana_cost):
		return false
	_start_cooldown(&"spell_%d" % index, _apply_cooldown_rate(spell.cooldown))
	_resolve_spell(spell)
	return true


## 释放第 index 个主动技能。
##
## 【为什么是协程】Ability.try_execute() 现在是协程（要等 _execute 里的施法动画/
##   分阶段效果跑完再进冷却），这里必须 await 它，否则拿到的永远不是"真正的"
##   ok，且失败时会在技能还没跑完就把节点 queue_free 掉。
##   调用方（输入处理）按 fire-and-forget 处理即可，不影响手感。
func use_ability(index: int) -> bool:
	if index < 0 or index >= ability_slots.size():
		return false
	var ability: AbilityData = ability_slots[index]
	if ability == null or not ability.is_active:
		return false
	if not _is_off_cooldown(&"ability_%d" % index):
		return false
	# 消耗与冷却都由 Ability 自己校验/结算，这里只负责槽位路由与 UI 冷却记录。
	var effect: Ability = Ability.create(ability, _player, _sprite)
	if effect == null:
		return false
	add_child(effect)
	var ok: bool = await effect.try_execute()
	if not ok:
		effect.queue_free()
		return false
	_start_cooldown(&"ability_%d" % index, _apply_cooldown_rate(ability.cooldown))
	return true


## 换武器（局外解锁/拾取时调用）。
func equip_weapon(weapon: WeaponData) -> void:
	current_weapon = weapon
	_instantiate_weapon()
	weapon_changed.emit(weapon)


## 实例化当前武器场景，并把判定委托给它。
## 武器是独立场景 → 换武器不用改角色脚本；判定盒挂在武器下 → 判定跟随武器。
func _instantiate_weapon() -> void:
	# 清掉旧武器。
	if _weapon_instance != null and is_instance_valid(_weapon_instance):
		_weapon_instance.queue_free()
		_weapon_instance = null
	if current_weapon == null:
		# 没配武器就退回角色自带贴图模式。
		_refresh_held_weapon()
		if _attack_controller != null:
			_attack_controller.set_weapon(null)
		return
	var parent: Node2D = _weapon_parent
	if parent == null:
		parent = _player as Node2D
	if parent == null:
		return
	# 统一入口：数据决定用通用场景还是自定义场景，这里不关心具体 .tscn。
	_weapon_instance = WeaponController.create(current_weapon, _player)
	if _weapon_instance == null:
		push_warning("[PlayerCombat] 武器实例化失败：%s" % current_weapon.display_name)
		_refresh_held_weapon()
		if _attack_controller != null:
			_attack_controller.set_weapon(null)
		return
	parent.add_child(_weapon_instance)
	# 按阵营收敛碰撞层：玩家武器只打敌人受击盒。
	var box: AttackBox = _weapon_instance.get_attack_box()
	if box != null:
		box.collision_layer = 32      ## PlayerAttack
		box.collision_mask = 16       ## EnemyHurtbox
		box.set_attacker(_player)
	# 把武器交给攻击控制器：判定窗口开启时由武器负责挥砍。
	if _attack_controller != null:
		_attack_controller.set_weapon(_weapon_instance)
	# 武器场景自带贴图，旧的手持贴图就不用了。
	if _held_sprite != null:
		_held_sprite.visible = false


## 玩家当前是否处于"可以发起新动作"的状态。
## 翻滚（含无敌帧）、硬直、死亡中都不允许蓄力/放招。
func _can_start_action() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	if _player is Player:
		var p: Player = _player as Player
		var st: int = p.get_state()
		if st in [Player.State.ROLL, Player.State.HURT, Player.State.DEAD]:
			return false
	if _player.is_dead() or _player.is_stunned():
		return false
	return true


## 当前移动速度倍率（蓄力/吟唱时 <1）。
func get_move_multiplier() -> float:
	return _move_multiplier


## 取某槽位冷却剩余比例 0~1（UI 画冷却圈用）。
func get_cooldown_ratio(slot: StringName) -> float:
	if not _cooldowns.has(slot):
		return 0.0
	var remaining: float = _cooldowns[slot]
	var total: float = _cooldown_max.get(slot, 1.0)
	return clampf(remaining / maxf(total, 0.001), 0.0, 1.0)


## 是否在冷却中。
func is_on_cooldown(slot: StringName) -> bool:
	return _cooldowns.has(slot) and _cooldowns[slot] > 0.0


# ============================================================================
# 私有方法 —— 冷却与蓄力
# ============================================================================

func _tick_cooldowns(delta: float) -> void:
	# 只对还在冷却的槽位做减法，避免每帧遍历整张表。
	for slot: StringName in _cooldowns.keys():
		if _cooldowns[slot] > 0.0:
			_cooldowns[slot] = maxf(0.0, _cooldowns[slot] - delta)
			cooldown_changed.emit(slot, get_cooldown_ratio(slot))


func _tick_charge(delta: float) -> void:
	if not _charging or current_weapon == null:
		return
	_charge_time += delta
	# 蓄力期间移动变慢，越接近蓄满越慢，形成"站桩蓄力"的压迫感。
	var ratio: float = clampf(_charge_time / maxf(current_weapon.charge_time, 0.01), 0.0, 1.0)
	_move_multiplier = lerpf(1.0, current_weapon.charge_move_mult, ratio)


func _tick_enchant(delta: float) -> void:
	if _enchant_attack == null:
		return
	_enchant_timer -= delta
	if _enchant_timer <= 0.0:
		_enchant_attack = null
		_enchant_timer = 0.0


func _is_off_cooldown(slot: StringName) -> bool:
	return not _cooldowns.has(slot) or _cooldowns[slot] <= 0.0


func _start_cooldown(slot: StringName, duration: float) -> void:
	if duration <= 0.0:
		_cooldowns.erase(slot)
		return
	_cooldowns[slot] = duration
	_cooldown_max[slot] = duration
	cooldown_changed.emit(slot, 1.0)


## 应用冷却缩减词条。上限 75% 已在 CharacterData 里限制。
func _apply_cooldown_rate(base: float) -> float:
	if _player == null:
		return base
	var rate: float = _player.get_stat(GameEnums.StatKind.COOLDOWN_RATE)
	return base * (1.0 - clampf(rate, 0.0, 0.75))


# ============================================================================
# 私有方法 —— 法术 / 弹道
# ============================================================================

## 按法术形态分派。
func _resolve_spell(spell: SpellData) -> void:
	AudioManager.play_sfx(spell.cast_sfx)
	match spell.form:
		GameEnums.SpellForm.PROJECTILE:
			_spawn_projectile(spell.projectile_scene, spell.attack_data, spell.element)
		GameEnums.SpellForm.AREA:
			_spawn_area_spell(spell)
		GameEnums.SpellForm.ENCHANT:
			_apply_enchant(spell)
		_:
			pass


## 发射远程武器的弹道（支持散射）。
func _fire_projectiles() -> void:
	if current_weapon == null or current_weapon.projectile_scene == null:
		return
	if not _is_off_cooldown(&"weapon_ranged"):
		return
	_start_cooldown(&"weapon_ranged", _apply_cooldown_rate(current_weapon.projectile_cooldown))
	var base_dir: Vector2 = _aim_direction()
	var count: int = maxi(1, current_weapon.projectile_count)
	# 散射：以瞄准方向为中心均匀分布。
	for i: int in count:
		var angle_offset: float = 0.0
		if count > 1:
			var step: float = deg_to_rad(current_weapon.spread_degrees) / float(count - 1)
			angle_offset = -deg_to_rad(current_weapon.spread_degrees) * 0.5 + step * i
		_spawn_projectile(current_weapon.projectile_scene, current_weapon.combo_1, GameEnums.Element.NONE, base_dir.rotated(angle_offset))


## 生成一个弹道。
##
## 【出生点为什么用 _aim_origin() 而不是角色原点】施法点就是瞄准基准点（武器锚点/手），
##   两者同源才能保证"飞行轨迹 = 瞄准射线"：从别处（脚底）发射，弹道会整体平移 6px，
##   表现为"准星指着敌人，火球却从脚下斜着飞过去"。
func _spawn_projectile(scene: PackedScene, data: AttackData, element: GameEnums.Element, dir_override: Vector2 = Vector2.ZERO) -> void:
	if scene == null:
		return
	var proj: Node2D = scene.instantiate() as Node2D
	if proj == null:
		return
	var dir: Vector2 = dir_override if dir_override != Vector2.ZERO else _aim_direction()
	var parent: Node = _get_projectile_parent()
	parent.add_child(proj)
	proj.global_position = _aim_origin() + dir * 8.0
	if proj is Projectile:
		(proj as Projectile).launch(dir, data, element, _player)


## 范围法术：在施法点前方一点的位置生成 AOE 场景。
## 基准点同 _spawn_projectile：与瞄准同源，AOE 中心才落在玩家真正指的方向上。
func _spawn_area_spell(spell: SpellData) -> void:
	if spell.area_scene == null:
		return
	var area: Node2D = spell.area_scene.instantiate() as Node2D
	if area == null:
		return
	var dir: Vector2 = _aim_direction()
	_get_projectile_parent().add_child(area)
	area.global_position = _aim_origin() + dir * 28.0
	if area.has_method("configure"):
		area.call("configure", spell.attack_data, spell.element, _player)


## 附魔：临时用 spell.enchant_attack 覆盖普攻数据。
func _apply_enchant(spell: SpellData) -> void:
	if spell.enchant_attack == null:
		return
	_enchant_attack = spell.enchant_attack
	_enchant_timer = spell.enchant_duration


## 瞄准方向：优先朝鼠标（俯视 ARPG 用鼠标瞄准最自然），无鼠标则用朝向。
##
## 【坐标系必须踩对两点，否则刀尖指不到鼠标】
##   1) 鼠标要用 `get_global_mouse_position()`（世界坐标）：
##      `Viewport.get_mouse_position()` 是视口坐标，相机一跟随移动差值就乱飘
##      （历史实测最大偏差 92°）。
##   2) 基准点必须是**武器的旋转锚点**，而不是 `_player.global_position`：
##      角色原点是脚底，而武器挂在 WeaponMount(y = -6) 上、绕挂载点旋转，
##      两者差 6px。用脚底当基准，鼠标离角色越近角度偏得越多
##      （离 30px 时约 11°），判定盒是武器的子节点，于是"刀尖指鼠标"整体歪掉。
##      锚点由武器自己报（`WeaponController.get_aim_origin()`），这里不假设挂载点在哪。
func _aim_direction() -> Vector2:
	if _player == null or not is_instance_valid(_player):
		return _facing_vector()
	var dir: Vector2 = _player.get_global_mouse_position() - _aim_origin()
	if dir.length_squared() > 4.0:
		return dir.normalized()
	return _facing_vector()


## 瞄准基准点（世界坐标）= 武器绕其旋转的中心。
##
## 三级兜底：武器实例（正常路径）→ 挂载点（武器实例化/换武器间隙）→ 角色原点（无挂载点）。
## 前两级都比"脚底"更接近真实旋转中心；第三级只是保证任何配置下都不会算出 NaN。
func _aim_origin() -> Vector2:
	if _weapon_instance != null and is_instance_valid(_weapon_instance):
		return _weapon_instance.get_aim_origin()
	if _weapon_parent != null and is_instance_valid(_weapon_parent):
		return _weapon_parent.global_position
	if _player != null and is_instance_valid(_player):
		return _player.global_position
	return Vector2.ZERO


## 朝向向量。
func _facing_vector() -> Vector2:
	if _sprite == null:
		return Vector2.RIGHT
	match _sprite.direction:
		&"up": return Vector2.UP
		&"down": return Vector2.DOWN
		&"left": return Vector2.LEFT
		_: return Vector2.RIGHT


## 弹道挂到哪个节点下。
## 优先挂在当前关卡根节点上，这样切场景时弹道会随关卡一起释放，
## 不会残留到下一个关卡。get_tree().current_scene 是 boot 节点（不是关卡），
## 所以这里不能用它兜底。
func _get_projectile_parent() -> Node:
	if not projectile_parent_path.is_empty():
		var node: Node = get_node_or_null(projectile_parent_path)
		if node != null:
			return node
	var level: Node = SceneDirector.get_current_scene()
	if level != null:
		return level
	# 最后兜底：挂到自己的父节点（关卡根）。
	return get_parent()


## 刷新手持武器贴图。
func _refresh_held_weapon() -> void:
	if _held_sprite == null:
		return
	if current_weapon == null or current_weapon.held_texture == null:
		_held_sprite.visible = false
		return
	_held_sprite.visible = true
	_held_sprite.texture = current_weapon.held_texture
	_held_sprite.position = current_weapon.held_offset
	_held_sprite.rotation_degrees = current_weapon.held_rotation


## 每帧根据朝向翻转手持武器。朝左时水平镜像并把偏移也翻到左侧，
## 否则剑会一直挂在身体右边，看着很怪。
func _update_held_weapon_facing() -> void:
	if _held_sprite == null or _sprite == null:
		return
	var facing_left: bool = _sprite.direction == &"left"
	_held_sprite.flip_h = facing_left
	var offset: Vector2 = current_weapon.held_offset if current_weapon != null else Vector2.ZERO
	_held_sprite.position = Vector2(-offset.x if facing_left else offset.x, offset.y)
	# 背面朝向时把武器藏到身后（负 z_index），正面/侧面时放在身前。
	_held_sprite.z_index = -1 if _sprite.direction == &"up" else 1
