## GenerateData —— 一次性数据生成器（编辑器工具脚本，不参与游戏运行）
##
## 【负责什么】
##   用代码批量生成 .tres 数据资源，避免手写几十个文本文件出错。
##   生成后可以直接删掉本脚本，.tres 会留在项目里。
##
## 【怎么运行】
##   Godot --headless --path . res://tools/generate_data.tscn
##   注意：必须用"运行场景"的方式而不是 --script。因为被加载的场景会引用
##   EventBus 等 autoload 单例，而 --script 模式不注册 autoload，会编译失败。
##
## 【为什么这么做】
##   .tres 是文本格式，但里面的 ext_resource/uid/SubResource 结构手写极易出错。
##   用 ResourceSaver 生成，格式一定正确，且能顺带校验字段名。
extends Node

# ============================================================================
# 常量 —— 素材路径集中在这里，方便统一改
# ============================================================================

const TEX_CHARS := "res://assets/sprites/characters/%s.png"
const TEX_MONSTERS := "res://assets/sprites/monsters/%s.png"
const TEX_WEAPONS := "res://assets/sprites/weapons/%s/%s.png"
const TEX_FX_SLASH := "res://assets/fx/slash/%s.png"
const TEX_FX_ELEM := "res://assets/fx/elemental/%s.png"
const TEX_FX_PROJ := "res://assets/fx/projectile/%s.png"
const SFX := "res://assets/audio/sfx/%s.wav"

# ============================================================================
# 入口
# ============================================================================

func _ready() -> void:
	_ensure_dirs()
	_generate_attacks()
	_generate_weapons()
	_generate_characters()
	_generate_spells()
	_generate_abilities()
	_generate_enemies()
	_generate_modifiers()
	_generate_items()
	print("[GenerateData] 全部数据生成完毕")
	get_tree().quit()


func _ensure_dirs() -> void:
	for d: String in [
		"res://data/attacks", "res://data/weapons", "res://data/characters",
		"res://data/spells", "res://data/abilities", "res://data/enemies",
		"res://data/modifiers", "res://data/items", "res://data/levels",
	]:
		DirAccess.make_dir_recursive_absolute(d)


# ============================================================================
# 攻击数据
# ============================================================================

func _generate_attacks() -> void:
	# --- 单手剑三段连击 ---
	var s3: AttackData = _new_attack("sword_3", 8.0, 0.14, 0.10, 0.24, 180.0, 0.05, Vector2(22, 0), Vector2(26, 22))
	var s2: AttackData = _new_attack("sword_2", 10.0, 0.12, 0.10, 0.24, 220.0, 0.06, Vector2(22, 0), Vector2(26, 22))
	var s1: AttackData = _new_attack("sword_1", 9.0, 0.10, 0.09, 0.20, 200.0, 0.05, Vector2(20, 0), Vector2(24, 20))
	s1.next_combo = s2
	s1.roll_cancel_at = 0.06
	s2.next_combo = s3
	s2.roll_cancel_at = 0.06
	s3.roll_cancel_at = 0.05
	# 三段连击的收招最重：伤害/击退/顿帧都更高。
	s3.damage = 14.0
	s3.knockback = 300.0
	s3.hitstop = 0.09
	s3.hitbox_size = Vector2(30, 26)
	s3.self_motion = Vector2(40, 0)
	_save(s1, "res://data/attacks/sword_combo_1.tres")
	_save(s2, "res://data/attacks/sword_combo_2.tres")
	_save(s3, "res://data/attacks/sword_combo_3.tres")

	# --- 蓄力重击（单手剑）---
	var heavy: AttackData = _new_attack("sword_heavy", 26.0, 0.30, 0.14, 0.42, 420.0, 0.14, Vector2(26, 0), Vector2(38, 34))
	heavy.poise_damage = 40.0
	heavy.self_motion = Vector2(70, 0)
	heavy.shake = 7.0
	_save(heavy, "res://data/attacks/sword_heavy.tres")

	# --- 双手大剑（慢、重、范围大）---
	var t3: AttackData = _new_attack("twohand_3", 20.0, 0.26, 0.16, 0.44, 380.0, 0.11, Vector2(26, 0), Vector2(40, 34))
	var t2: AttackData = _new_attack("twohand_2", 16.0, 0.24, 0.14, 0.42, 340.0, 0.10, Vector2(26, 0), Vector2(38, 32))
	var t1: AttackData = _new_attack("twohand_1", 15.0, 0.22, 0.13, 0.40, 320.0, 0.10, Vector2(24, 0), Vector2(36, 30))
	t1.next_combo = t2
	t1.roll_cancel_at = 0.12
	t2.next_combo = t3
	t2.roll_cancel_at = 0.12
	t3.poise_damage = 35.0
	t3.self_motion = Vector2(50, 0)
	_save(t1, "res://data/attacks/twohand_combo_1.tres")
	_save(t2, "res://data/attacks/twohand_combo_2.tres")
	_save(t3, "res://data/attacks/twohand_combo_3.tres")

	var theavy: AttackData = _new_attack("twohand_heavy", 40.0, 0.42, 0.18, 0.60, 560.0, 0.20, Vector2(30, 0), Vector2(48, 42))
	theavy.poise_damage = 60.0
	theavy.self_motion = Vector2(60, 0)
	theavy.shake = 10.0
	_save(theavy, "res://data/attacks/twohand_heavy.tres")

	# --- 远程弓 ---
	var arrow: AttackData = _new_attack("bow_shot", 9.0, 0.10, 0.05, 0.22, 90.0, 0.03, Vector2(14, 0), Vector2(16, 14))
	arrow.attack_scaling = 0.8
	_save(arrow, "res://data/attacks/bow_shot.tres")

	# --- 法术：火球 / 冰锥 / 雷击 ---
	var fireball: AttackData = _new_attack("fireball", 18.0, 0.18, 0.12, 0.30, 140.0, 0.07, Vector2(20, 0), Vector2(26, 26))
	fireball.element = GameEnums.Element.FIRE
	fireball.attack_scaling = 1.2
	_save(fireball, "res://data/attacks/fireball.tres")

	var icespike: AttackData = _new_attack("ice_spike", 14.0, 0.16, 0.10, 0.28, 110.0, 0.06, Vector2(20, 0), Vector2(24, 24))
	icespike.element = GameEnums.Element.ICE
	icespike.attack_scaling = 1.0
	_save(icespike, "res://data/attacks/ice_spike.tres")

	var thunder: AttackData = _new_attack("thunder_strike", 22.0, 0.30, 0.10, 0.40, 160.0, 0.10, Vector2(0, 0), Vector2(40, 40))
	thunder.element = GameEnums.Element.THUNDER
	thunder.attack_scaling = 1.4
	thunder.shake = 8.0
	_save(thunder, "res://data/attacks/thunder_strike.tres")

	# --- 附魔后的普攻（火焰附魔）---
	var ench: AttackData = _new_attack("fire_enchant", 12.0, 0.10, 0.09, 0.20, 200.0, 0.06, Vector2(20, 0), Vector2(26, 22))
	ench.element = GameEnums.Element.FIRE
	_save(ench, "res://data/attacks/fire_enchant.tres")

	# --- 敌人招式 ---
	var bite: AttackData = _new_attack("enemy_bite", 8.0, 0.35, 0.10, 0.45, 160.0, 0.04, Vector2(16, 0), Vector2(20, 18))
	bite.attack_scaling = 1.0
	_save(bite, "res://data/attacks/enemy_bite.tres")

	var enemy_cast: AttackData = _new_attack("enemy_cast", 10.0, 0.5, 0.05, 0.6, 80.0, 0.04, Vector2(12, 0), Vector2(14, 14))
	enemy_cast.element = GameEnums.Element.FIRE
	enemy_cast.attack_scaling = 1.0
	_save(enemy_cast, "res://data/attacks/enemy_cast.tres")

	var charge_hit: AttackData = _new_attack("enemy_charge", 16.0, 0.1, 0.35, 0.5, 380.0, 0.09, Vector2(18, 0), Vector2(24, 22))
	charge_hit.attack_scaling = 1.2
	_save(charge_hit, "res://data/attacks/enemy_charge.tres")

	var boss_slam: AttackData = _new_attack("boss_slam", 28.0, 0.5, 0.2, 0.8, 420.0, 0.16, Vector2(0, 0), Vector2(56, 56))
	boss_slam.attack_scaling = 1.5
	boss_slam.shake = 9.0
	_save(boss_slam, "res://data/attacks/boss_slam.tres")


## 构造一个 AttackData 并填常用字段，减少重复代码。
func _new_attack(_id: String, dmg: float, startup: float, active: float, recovery: float, knockback: float, hitstop: float, offset: Vector2, size: Vector2) -> AttackData:
	var a: AttackData = AttackData.new()
	a.damage = dmg
	a.startup = startup
	a.active = active
	a.recovery = recovery
	a.knockback = knockback
	a.hitstop = hitstop
	a.hitbox_offset = offset
	a.hitbox_size = size
	return a


# ============================================================================
# 武器数据
# ============================================================================

func _generate_weapons() -> void:
	# --- 近战 2 把：单手剑、武士刀 ---
	var sword: WeaponData = _new_weapon("铁剑", "均衡的单手剑，三段连击流畅。", "Sword", GameEnums.WeaponKind.MELEE, GameEnums.Rarity.COMMON)
	sword.combo_1 = load("res://data/attacks/sword_combo_1.tres")
	sword.heavy_attack = load("res://data/attacks/sword_heavy.tres")
	sword.attack_bonus = 4.0
	sword.attack_speed = 1.15
	sword.held_offset = Vector2(7, -2)
	_save(sword, "res://data/weapons/sword.tres")

	var katana: WeaponData = _new_weapon("疾风刀", "攻速更快的武士刀，牺牲单次伤害换取连击速度。", "Katana", GameEnums.WeaponKind.MELEE, GameEnums.Rarity.RARE)
	katana.combo_1 = load("res://data/attacks/sword_combo_1.tres")
	katana.heavy_attack = load("res://data/attacks/sword_heavy.tres")
	katana.attack_bonus = 6.0
	katana.attack_speed = 1.45
	katana.held_offset = Vector2(7, -3)
	_save(katana, "res://data/weapons/katana.tres")

	# --- 远程 2 把：短弓、法杖 ---
	var bow: WeaponData = _new_weapon("猎手短弓", "远程点射，适合风筝打法。", "Bow", GameEnums.WeaponKind.RANGED, GameEnums.Rarity.COMMON)
	bow.combo_1 = load("res://data/attacks/bow_shot.tres")
	bow.projectile_scene = load("res://scenes/fx/projectile.tscn")
	bow.projectile_cooldown = 0.34
	bow.projectile_count = 1
	bow.attack_bonus = 5.0
	_save(bow, "res://data/weapons/bow.tres")

	var wand: WeaponData = _new_weapon("元素法杖", "三连散射的魔法弹，弹道会轻微扩散。", "MagicWand", GameEnums.WeaponKind.RANGED, GameEnums.Rarity.RARE)
	wand.combo_1 = load("res://data/attacks/bow_shot.tres")
	wand.projectile_scene = load("res://scenes/fx/projectile.tscn")
	wand.projectile_cooldown = 0.42
	wand.projectile_count = 3
	wand.spread_degrees = 18.0
	wand.attack_bonus = 7.0
	_save(wand, "res://data/weapons/wand.tres")

	# --- 双手 2 把：大剑、巨锤 ---
	var bigsword: WeaponData = _new_weapon("双手大剑", "攻击缓慢但范围与伤害极高，重击能打断敌人。", "BigSword", GameEnums.WeaponKind.TWO_HANDED, GameEnums.Rarity.RARE)
	bigsword.combo_1 = load("res://data/attacks/twohand_combo_1.tres")
	bigsword.heavy_attack = load("res://data/attacks/twohand_heavy.tres")
	bigsword.attack_bonus = 12.0
	bigsword.attack_speed = 0.8
	bigsword.charge_time = 0.85
	bigsword.charge_move_mult = 0.2
	bigsword.held_offset = Vector2(8, -4)
	_save(bigsword, "res://data/weapons/big_sword.tres")

	var hammer: WeaponData = _new_weapon("碎地巨锤", "最重的武器，蓄满重击可造成大范围击退。", "Hammer", GameEnums.WeaponKind.TWO_HANDED, GameEnums.Rarity.EPIC)
	hammer.combo_1 = load("res://data/attacks/twohand_combo_1.tres")
	hammer.heavy_attack = load("res://data/attacks/twohand_heavy.tres")
	hammer.attack_bonus = 16.0
	hammer.attack_speed = 0.65
	hammer.charge_time = 1.0
	hammer.charge_move_mult = 0.1
	hammer.held_offset = Vector2(8, -5)
	_save(hammer, "res://data/weapons/hammer.tres")


func _new_weapon(disp: String, desc: String, tex_name: String, kind: GameEnums.WeaponKind, rarity: GameEnums.Rarity) -> WeaponData:
	var w: WeaponData = WeaponData.new()
	w.display_name = disp
	w.description = desc
	w.kind = kind
	w.rarity = rarity
	w.icon = load(TEX_WEAPONS % [tex_name, "Sprite"])
	w.held_texture = load(TEX_WEAPONS % [tex_name, "SpriteInHand"])
	w.swing_sfx = load(SFX % "Hit1")
	w.hit_sfx = load(SFX % "Hit")
	# 不再给武器数据绑私有场景：所有武器共用 res://scenes/weapons/weapon.tscn，
	# 判定/弧线/是否跟随瞄准等差异由下面的字段描述。
	# 远程武器不跟随瞄准旋转（弓/杖跟着鼠标转圈很怪），弹道方向由发射器单独算。
	w.weapon_scene = null
	if w.kind == GameEnums.WeaponKind.RANGED:
		w.rotate_to_aim = false
		# 远程只留一个很小的近身盒（防贴脸），主要伤害走弹道。
		w.hitbox_offset = Vector2(10, 0)
		w.hitbox_size = Vector2(14, 14)
	return w


## 贴图名 → 武器数据。武器不再各自绑定场景，统一由通用场景 + 本数据实例化。
## 找不到对应数据时返回 null（回退到角色自带判定盒）。
func _weapon_data_for(tex_name: String) -> WeaponData:
	var data_id: String = ""
	match tex_name:
		"Sword": data_id = "sword"
		"Katana": data_id = "katana"
		"BigSword": data_id = "big_sword"
		"Hammer": data_id = "hammer"
		"Bow": data_id = "bow"
		"MagicWand": data_id = "wand"
		_: return null
	var path: String = "res://data/weapons/%s.tres" % data_id
	return load(path) if ResourceLoader.exists(path) else null


# ============================================================================
# 角色数据
# ============================================================================

func _generate_characters() -> void:
	var player: CharacterData = CharacterData.new()
	player.display_name = "勇者"
	player.sprite_texture = load(TEX_CHARS % "BlueNinja")
	player.body_radius = 5.0
	player.sprite_offset = Vector2(0, -6)
	player.max_health = 100.0
	player.max_mana = 60.0
	player.attack_power = 10.0
	player.defense = 5.0
	player.move_speed = 115.0
	player.mana_regen = 4.0
	player.crit_chance = 0.08
	player.crit_damage = 1.6
	player.hurt_time = 0.16
	player.poise = 20.0
	player.invuln_time = 0.5
	player.hurt_flash_color = Color(1.0, 0.3, 0.3)
	player.hurt_flash_time = 0.1
	player.hurt_shake_intensity = 2.0
	player.death_dissolve_time = 0.7
	_save(player, "res://data/characters/player.tres")

	var npc: CharacterData = CharacterData.new()
	npc.display_name = "村民"
	npc.sprite_texture = load(TEX_CHARS % "Villager")
	npc.body_radius = 5.0
	npc.sprite_offset = Vector2(0, -6)
	npc.max_health = 30.0
	npc.move_speed = 40.0
	_save(npc, "res://data/characters/villager.tres")


# ============================================================================
# 法术数据
# ============================================================================

func _generate_spells() -> void:
	# 火 × 弹道
	var fireball: SpellData = _new_spell("火球术", "向瞄准方向发射一枚火球，命中后爆炸。", "ScrollFire", GameEnums.Element.FIRE, GameEnums.SpellForm.PROJECTILE)
	fireball.mana_cost = 14.0
	fireball.cooldown = 1.1
	fireball.cast_time = 0.18
	fireball.recovery = 0.22
	fireball.attack_data = load("res://data/attacks/fireball.tres")
	fireball.projectile_scene = load("res://scenes/fx/projectile.tscn")
	fireball.cast_sfx = load(SFX % "Fireball")
	fireball.impact_sfx = load(SFX % "Explosion2")
	_save(fireball, "res://data/spells/fireball.tres")

	# 冰 × 弹道
	var icespike: SpellData = _new_spell("冰锥术", "射出锋利的冰锥，命中造成减速。", "ScrollIce", GameEnums.Element.ICE, GameEnums.SpellForm.PROJECTILE)
	icespike.mana_cost = 10.0
	icespike.cooldown = 0.8
	icespike.cast_time = 0.12
	icespike.attack_data = load("res://data/attacks/ice_spike.tres")
	icespike.projectile_scene = load("res://scenes/fx/projectile.tscn")
	icespike.cast_sfx = load(SFX % "Magic1")
	_save(icespike, "res://data/spells/ice_spike.tres")

	# 雷 × 范围
	var thunder: SpellData = _new_spell("落雷", "在目标位置降下落雷，范围伤害。", "ScrollThunder", GameEnums.Element.THUNDER, GameEnums.SpellForm.AREA)
	thunder.mana_cost = 22.0
	thunder.cooldown = 2.4
	thunder.cast_time = 0.4
	thunder.cast_move_mult = 0.15
	thunder.attack_data = load("res://data/attacks/thunder_strike.tres")
	thunder.area_scene = load("res://scenes/fx/area_spell.tscn")
	thunder.cast_sfx = load(SFX % "Magic3")
	thunder.impact_sfx = load(SFX % "Explosion")
	_save(thunder, "res://data/spells/thunder.tres")

	# 火 × 附魔
	var enchant: SpellData = _new_spell("烈焰附魔", "为武器附上火元素，持续期间普攻附带火焰伤害。", "ScrollFire", GameEnums.Element.FIRE, GameEnums.SpellForm.ENCHANT)
	enchant.mana_cost = 18.0
	enchant.cooldown = 8.0
	enchant.cast_time = 0.3
	enchant.enchant_attack = load("res://data/attacks/fire_enchant.tres")
	enchant.enchant_duration = 10.0
	enchant.cast_sfx = load(SFX % "PowerUp1")
	_save(enchant, "res://data/spells/fire_enchant.tres")

	# 冰 × 范围
	var frost: SpellData = _new_spell("寒霜新星", "以自身为中心爆发冰环，击退并冻伤周围敌人。", "ScrollIce", GameEnums.Element.ICE, GameEnums.SpellForm.AREA)
	frost.mana_cost = 20.0
	frost.cooldown = 3.0
	frost.cast_time = 0.25
	frost.attack_data = load("res://data/attacks/ice_spike.tres")
	frost.area_scene = load("res://scenes/fx/area_spell.tscn")
	frost.cast_sfx = load(SFX % "Magic2")
	_save(frost, "res://data/spells/frost_nova.tres")


func _new_spell(disp: String, desc: String, icon_name: String, element: GameEnums.Element, form: GameEnums.SpellForm) -> SpellData:
	var s: SpellData = SpellData.new()
	s.display_name = disp
	s.description = desc
	s.icon = load("res://assets/sprites/items/%s.png" % icon_name)
	s.element = element
	s.form = form
	return s


# ============================================================================
# 技能数据
# ============================================================================

func _generate_abilities() -> void:
	# --- 主动：冲刺斩 ---
	var dash: AbilityData = _new_ability("冲刺斩", "向前突进并挥砍，突进期间无敌。", true, GameEnums.Rarity.RARE)
	dash.mana_cost = 12.0
	dash.cooldown = 4.0
	dash.attack_data = load("res://data/attacks/sword_combo_3.tres")
	dash.effect_value = 90.0
	dash.cast_sfx = load(SFX % "Jump")
	_save(dash, "res://data/abilities/dash_slash.tres")

	# --- 主动：治疗术 ---
	var heal: AbilityData = _new_ability("治愈之光", "立即恢复 30% 最大生命。", true, GameEnums.Rarity.RARE)
	heal.mana_cost = 25.0
	heal.cooldown = 12.0
	heal.cast_time = 0.5
	heal.effect_value = 0.3
	heal.cast_sfx = load(SFX % "Success1")
	_save(heal, "res://data/abilities/heal.tres")

	# --- 主动：旋风斩 ---
	var whirl: AbilityData = _new_ability("旋风斩", "原地旋转，对周围所有敌人造成伤害。", true, GameEnums.Rarity.EPIC)
	whirl.mana_cost = 20.0
	whirl.cooldown = 6.0
	whirl.attack_data = load("res://data/attacks/twohand_combo_2.tres")
	whirl.cast_sfx = load(SFX % "Magic2")
	_save(whirl, "res://data/abilities/whirlwind.tres")

	# --- 被动：坚韧 ---
	var tough: AbilityData = _new_ability("坚韧", "最大生命 +20%。", false, GameEnums.Rarity.COMMON)
	tough.apply_on_equip = true
	tough.passive_stat_mods = {GameEnums.StatKind.MAX_HEALTH: 0.2}
	tough.passive_op = GameEnums.ModifierOp.PERCENT
	_save(tough, "res://data/abilities/toughness.tres")

	# --- 被动：疾风 ---
	var swift: AbilityData = _new_ability("疾风步", "移动速度 +15%。", false, GameEnums.Rarity.COMMON)
	swift.passive_stat_mods = {GameEnums.StatKind.MOVE_SPEED: 0.15}
	swift.passive_op = GameEnums.ModifierOp.PERCENT
	_save(swift, "res://data/abilities/swift_step.tres")

	# --- 被动：致命 ---
	var lethal: AbilityData = _new_ability("致命打击", "暴击率 +10%。", false, GameEnums.Rarity.RARE)
	lethal.passive_stat_mods = {GameEnums.StatKind.CRIT_CHANCE: 0.10}
	lethal.passive_op = GameEnums.ModifierOp.FLAT
	_save(lethal, "res://data/abilities/lethal_strike.tres")


func _new_ability(disp: String, desc: String, is_active: bool, rarity: GameEnums.Rarity) -> AbilityData:
	var a: AbilityData = AbilityData.new()
	a.display_name = disp
	a.description = desc
	a.is_active = is_active
	a.rarity = rarity
	return a


# ============================================================================
# 敌人数据
# ============================================================================

func _generate_enemies() -> void:
	# --- 近战小怪：史莱姆 ---
	var slime_stats: CharacterData = _new_enemy_stats("史莱姆", "Slime", 30.0, 6.0, 0.0, 60.0)
	_save(slime_stats, "res://data/enemies/slime_stats.tres")
	var slime: EnemyData = _new_enemy("史莱姆", "Slime", slime_stats, GameEnums.EnemyKind.MELEE)
	slime.melee_attack = load("res://data/attacks/enemy_bite.tres")
	slime.detect_range = 110.0
	slime.attack_range = 18.0
	slime.attack_cooldown = 1.3
	slime.experience_reward = 8
	slime.drop_table = [{"item_id": &"coin", "chance": 0.6}]
	_save(slime, "res://data/enemies/slime.tres")

	# --- 近战小怪：骷髅 ---
	var skel_stats: CharacterData = _new_enemy_stats("骷髅兵", "Skeleton", 45.0, 9.0, 3.0, 72.0)
	_save(skel_stats, "res://data/enemies/skeleton_stats.tres")
	var skel: EnemyData = _new_enemy("骷髅兵", "Skeleton", skel_stats, GameEnums.EnemyKind.MELEE)
	skel.melee_attack = load("res://data/attacks/enemy_bite.tres")
	skel.detect_range = 130.0
	skel.attack_range = 20.0
	skel.attack_cooldown = 1.1
	skel.experience_reward = 12
	_save(skel, "res://data/enemies/skeleton.tres")

	# --- 远程法师：黑法师 ---
	var mage_stats: CharacterData = _new_enemy_stats("黑法师", "SorcererBlack", 35.0, 11.0, 2.0, 55.0)
	_save(mage_stats, "res://data/enemies/mage_stats.tres")
	var mage: EnemyData = _new_enemy("黑法师", "SorcererBlack", mage_stats, GameEnums.EnemyKind.CASTER)
	mage.melee_attack = load("res://data/attacks/enemy_bite.tres")
	mage.ranged_attack = load("res://data/attacks/enemy_cast.tres")
	mage.projectile_scene = load("res://scenes/fx/enemy_projectile.tscn")
	mage.detect_range = 160.0
	mage.preferred_range = 90.0
	mage.attack_cooldown = 2.0
	mage.experience_reward = 18
	_save(mage, "res://data/enemies/dark_mage.tres")

	# --- 冲锋精英：赤武士 ---
	var charger_stats: CharacterData = _new_enemy_stats("赤武士", "RedSamurai", 90.0, 14.0, 6.0, 78.0)
	charger_stats.poise = 30.0
	# 精英：只吃一半击退，被推得动但推不远。
	charger_stats.knockback_resist = 0.5
	charger_stats.knockback_damping = 18.0
	charger_stats.hurt_shake_intensity = 3.0
	_save(charger_stats, "res://data/enemies/charger_stats.tres")
	var charger: EnemyData = _new_enemy("赤武士", "RedSamurai", charger_stats, GameEnums.EnemyKind.CHARGER)
	charger.is_elite = true
	charger.melee_attack = load("res://data/attacks/enemy_charge.tres")
	charger.detect_range = 170.0
	charger.attack_range = 30.0
	charger.attack_cooldown = 2.4
	charger.charge_time = 0.7
	charger.charge_speed_mult = 4.5
	charger.experience_reward = 40
	charger.drop_table = [{"item_id": &"coin", "chance": 1.0}]
	_save(charger, "res://data/enemies/red_samurai.tres")

	# --- Boss：独眼巨人 ---
	var boss_stats: CharacterData = _new_enemy_stats("独眼巨人", "Knight", 420.0, 20.0, 12.0, 62.0)
	boss_stats.poise = 90.0
	boss_stats.invuln_time = 0.15
	# Boss：完全不被击退、不吃硬直（霸体），但依然会闪红——这样脚本不用为
	# "Boss 免疫击退"写任何特判，只要数据设成这两个值即可。
	boss_stats.knockback_resist = 1.0
	boss_stats.super_armor = true
	boss_stats.hurt_shake_intensity = 0.0
	boss_stats.hurt_flash_color = Color(1.0, 0.6, 0.2)
	boss_stats.death_dissolve_time = 1.2
	boss_stats.destroy_on_death = true
	_save(boss_stats, "res://data/enemies/boss_cyclops_stats.tres")
	var boss: EnemyData = _new_enemy("独眼巨人", "Knight", boss_stats, GameEnums.EnemyKind.MELEE)
	boss.is_boss = true
	boss.is_elite = true
	boss.melee_attack = load("res://data/attacks/boss_slam.tres")
	boss.detect_range = 220.0
	boss.attack_range = 34.0
	boss.attack_cooldown = 1.8
	boss.experience_reward = 250
	boss.drop_table = [{"item_id": &"coin", "chance": 1.0}]
	_save(boss, "res://data/enemies/boss_cyclops.tres")


func _new_enemy_stats(disp: String, tex: String, hp: float, atk: float, def: float, spd: float) -> CharacterData:
	var c: CharacterData = CharacterData.new()
	c.display_name = disp
	# 敌人素材可能来自"角色表"（64×112，4 列 × 7 行）或"怪物表"（64×64，4×4）。
	# 优先角色表，找不到再退回怪物表，避免每加一个敌人就要改代码。
	var char_path: String = TEX_CHARS % tex
	var monster_path: String = TEX_MONSTERS % tex
	if ResourceLoader.exists(char_path):
		c.sprite_texture = load(char_path)
	elif ResourceLoader.exists(monster_path):
		c.sprite_texture = load(monster_path)
	else:
		push_warning("[GenerateData] 找不到敌人贴图：%s" % tex)
	c.body_radius = 5.0
	c.sprite_offset = Vector2(0, -6)
	c.max_health = hp
	c.attack_power = atk
	c.defense = def
	c.move_speed = spd
	c.max_mana = 0.0
	c.mana_regen = 0.0
	c.hurt_time = 0.2
	c.poise = 0.0
	c.invuln_time = 0.12
	return c


func _new_enemy(disp: String, tex: String, stats: CharacterData, kind: GameEnums.EnemyKind) -> EnemyData:
	var e: EnemyData = EnemyData.new()
	e.display_name = disp
	e.stats = stats
	e.kind = kind
	e.hurt_sfx = load(SFX % "Hit2")
	e.attack_sfx = load(SFX % "Hit3")
	# 敌人也走"武器数据 + 通用场景"：判定盒跟着敌人朝向转，不再固定在角色中心。
	# 法师拿法杖（远程、不跟随瞄准），近战/冲锋拿剑。
	e.weapon = _weapon_data_for("MagicWand" if kind == GameEnums.EnemyKind.CASTER else "Sword")
	return e


# ============================================================================
# 词条数据（Roguelite）
# ============================================================================

func _generate_modifiers() -> void:
	# --- 普通 ---
	_mod(&"m_atk_flat", "锋锐", "攻击力 +3", GameEnums.Rarity.COMMON, GameEnums.StatKind.ATTACK_POWER, GameEnums.ModifierOp.FLAT, 3.0, 20.0, 5)
	_mod(&"m_hp_flat", "体魄", "最大生命 +15", GameEnums.Rarity.COMMON, GameEnums.StatKind.MAX_HEALTH, GameEnums.ModifierOp.FLAT, 15.0, 20.0, 5)
	_mod(&"m_spd_flat", "轻足", "移动速度 +8", GameEnums.Rarity.COMMON, GameEnums.StatKind.MOVE_SPEED, GameEnums.ModifierOp.FLAT, 8.0, 20.0, 4)
	_mod(&"m_mana_flat", "灵泉", "最大法力 +12", GameEnums.Rarity.COMMON, GameEnums.StatKind.MAX_MANA, GameEnums.ModifierOp.FLAT, 12.0, 18.0, 4)
	_mod(&"m_def_flat", "护甲", "防御 +4", GameEnums.Rarity.COMMON, GameEnums.StatKind.DEFENSE, GameEnums.ModifierOp.FLAT, 4.0, 18.0, 5)
	_mod(&"m_regen", "冥想", "每秒回蓝 +2", GameEnums.Rarity.COMMON, GameEnums.StatKind.MANA_REGEN, GameEnums.ModifierOp.FLAT, 2.0, 14.0, 4)

	# --- 稀有 ---
	_mod(&"m_atk_pct", "狂暴", "攻击力 +15%", GameEnums.Rarity.RARE, GameEnums.StatKind.ATTACK_POWER, GameEnums.ModifierOp.PERCENT, 0.15, 10.0, 4)
	_mod(&"m_hp_pct", "巨人血脉", "最大生命 +18%", GameEnums.Rarity.RARE, GameEnums.StatKind.MAX_HEALTH, GameEnums.ModifierOp.PERCENT, 0.18, 9.0, 4)
	_mod(&"m_crit", "锐眼", "暴击率 +8%", GameEnums.Rarity.RARE, GameEnums.StatKind.CRIT_CHANCE, GameEnums.ModifierOp.FLAT, 0.08, 9.0, 5)
	_mod(&"m_critdmg", "致命一击", "暴击伤害 +25%", GameEnums.Rarity.RARE, GameEnums.StatKind.CRIT_DAMAGE, GameEnums.ModifierOp.FLAT, 0.25, 8.0, 4)
	_mod(&"m_cdr", "冷却精通", "冷却缩减 +8%", GameEnums.Rarity.RARE, GameEnums.StatKind.COOLDOWN_RATE, GameEnums.ModifierOp.FLAT, 0.08, 8.0, 4)
	_mod(&"m_lifesteal", "吸血", "吸血 +4%", GameEnums.Rarity.RARE, GameEnums.StatKind.LIFE_STEAL, GameEnums.ModifierOp.FLAT, 0.04, 7.0, 5)

	# --- 史诗 ---
	_mod(&"m_atk_mult", "战神之力", "攻击力 ×1.2", GameEnums.Rarity.EPIC, GameEnums.StatKind.ATTACK_POWER, GameEnums.ModifierOp.MULTIPLY, 1.2, 3.5, 2)
	_mod(&"m_atkspd", "疾风连击", "攻击速度 +20%", GameEnums.Rarity.EPIC, GameEnums.StatKind.ATTACK_SPEED, GameEnums.ModifierOp.PERCENT, 0.20, 3.5, 3)
	_mod(&"m_crit_mult", "处刑者", "暴击伤害 ×1.3", GameEnums.Rarity.EPIC, GameEnums.StatKind.CRIT_DAMAGE, GameEnums.ModifierOp.MULTIPLY, 1.3, 3.0, 2)
	_mod(&"m_pickup", "贪婪之手", "拾取范围 +30", GameEnums.Rarity.EPIC, GameEnums.StatKind.PICKUP_RANGE, GameEnums.ModifierOp.FLAT, 30.0, 3.0, 2)

	# --- 传说 ---
	# 传说词条。文件名必须与 id 一致——否则同一份数据会出现两个名字，
	# 后续维护时极易被误当成两个词条（QA 报告里的"同名词条被吞"就是这个坑引出的）。
	var legend: ModifierData = _mod(&"m_dragon_heart", "龙之心", "攻击力 ×1.35", GameEnums.Rarity.LEGENDARY, GameEnums.StatKind.ATTACK_POWER, GameEnums.ModifierOp.MULTIPLY, 1.35, 1.0, 1)
	legend.max_stacks = 1
	_save(legend, "res://data/modifiers/m_dragon_heart.tres")

	# --- 武器专用词条 ---
	var w_mod: ModifierData = ModifierData.new()
	w_mod.display_name = "巨力"
	w_mod.description = "双手武器伤害 +25%"
	w_mod.rarity = GameEnums.Rarity.RARE
	w_mod.target = GameEnums.ModifierTarget.WEAPON
	w_mod.stat = GameEnums.StatKind.ATTACK_POWER
	w_mod.op = GameEnums.ModifierOp.PERCENT
	w_mod.value = 0.25
	w_mod.weight = 8.0
	w_mod.weapon_kinds = [GameEnums.WeaponKind.TWO_HANDED]
	_save(w_mod, "res://data/modifiers/m_heavy_hitter.tres")

	# --- 技能专用词条 ---
	var s_mod: ModifierData = ModifierData.new()
	s_mod.display_name = "烈焰精通"
	s_mod.description = "火系法术伤害 +30%"
	s_mod.rarity = GameEnums.Rarity.RARE
	s_mod.target = GameEnums.ModifierTarget.ABILITY
	s_mod.stat = GameEnums.StatKind.ATTACK_POWER
	s_mod.op = GameEnums.ModifierOp.PERCENT
	s_mod.value = 0.30
	s_mod.weight = 8.0
	s_mod.elements = [GameEnums.Element.FIRE]
	_save(s_mod, "res://data/modifiers/m_pyromancy.tres")

	# --- 全局规则词条 ---
	var g_mod: ModifierData = ModifierData.new()
	g_mod.display_name = "嗜血狂怒"
	g_mod.description = "生命低于 40% 时攻击力 +40%"
	g_mod.rarity = GameEnums.Rarity.EPIC
	g_mod.target = GameEnums.ModifierTarget.GLOBAL
	g_mod.stat = GameEnums.StatKind.ATTACK_POWER
	g_mod.op = GameEnums.ModifierOp.PERCENT
	g_mod.value = 0.40
	g_mod.weight = 4.0
	g_mod.trigger_tag = &"low_health"
	_save(g_mod, "res://data/modifiers/m_blood_rage.tres")


## 生成一个标准属性词条并保存。
func _mod(id: StringName, disp: String, desc: String, rarity: GameEnums.Rarity, stat: GameEnums.StatKind, op: GameEnums.ModifierOp, value: float, weight: float, max_stacks: int) -> ModifierData:
	var m: ModifierData = ModifierData.new()
	m.display_name = disp
	m.description = desc
	m.rarity = rarity
	m.target = GameEnums.ModifierTarget.STAT
	m.stat = stat
	m.op = op
	m.value = value
	m.weight = weight
	m.max_stacks = max_stacks
	m.pick_sfx = load(SFX % "PowerUp1")
	_save(m, "res://data/modifiers/%s.tres" % String(id))
	return m


# ============================================================================
# 物品数据
# ============================================================================

func _generate_items() -> void:
	var life: ItemData = ItemData.new()
	life.id = &"potion_life"
	life.display_name = "生命药水"
	life.description = "恢复 40 点生命。"
	life.icon = load("res://assets/sprites/items/PotionLife.png")
	life.kind = ItemData.Kind.CONSUMABLE
	life.heal_amount = 40.0
	life.use_sfx = load(SFX % "Success1")
	_save(life, "res://data/items/potion_life.tres")

	var mana: ItemData = ItemData.new()
	mana.id = &"potion_mana"
	mana.display_name = "法力药水"
	mana.description = "恢复 30 点法力。"
	mana.icon = load("res://assets/sprites/items/PotionMana.png")
	mana.kind = ItemData.Kind.CONSUMABLE
	mana.mana_amount = 30.0
	mana.use_sfx = load(SFX % "Magic1")
	_save(mana, "res://data/items/potion_mana.tres")

	var coin: ItemData = ItemData.new()
	coin.id = &"coin"
	coin.display_name = "金币"
	coin.description = "通用货币。"
	coin.icon = load("res://assets/sprites/items/Coin.png")
	coin.kind = ItemData.Kind.MATERIAL
	coin.max_stack = 999
	_save(coin, "res://data/items/coin.tres")

	var key: ItemData = ItemData.new()
	key.id = &"dungeon_key"
	key.display_name = "地牢钥匙"
	key.description = "打开地牢深处的关底门。"
	key.icon = load("res://assets/sprites/items/Key.png")
	key.kind = ItemData.Kind.KEY
	key.max_stack = 1
	key.can_drop = false
	_save(key, "res://data/items/dungeon_key.tres")


# ============================================================================
# 工具
# ============================================================================

func _save(res: Resource, path: String) -> void:
	var err: int = ResourceSaver.save(res, path)
	if err != OK:
		push_error("[GenerateData] 保存失败 %s：%d" % [path, err])
