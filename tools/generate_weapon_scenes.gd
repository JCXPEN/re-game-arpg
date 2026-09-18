## GenerateWeaponScenes —— 生成通用武器场景（编辑器工具脚本）
##
## 【负责什么】
##   生成**唯一**的通用武器场景 res://scenes/weapons/weapon.tscn。
##   所有武器（剑/刀/大剑/锤/弓/法杖）共用它，武器之间的差异一律由
##   WeaponData 的字段在运行时套用（贴图、判定、弧线、是否跟随瞄准）。
##   这样新增一把武器 = 新建一个 .tres，不需要再建 .tscn。
##
##   场景结构决定了"判定跟随武器"：
##     WeaponController        ← 旋转到瞄准方向
##       └─ SwingPivot         ← 挥砍时在弧线内扫动
##            ├─ Sprite        ← 武器贴图（由 WeaponData 注入）
##            └─ AttackBox     ← 判定盒（跟着武器转+扫）
##
## 【怎么运行】
##   Godot --headless --path . res://tools/generate_weapon_scenes.tscn
extends Node

# ============================================================================
# 常量
# ============================================================================

## 通用武器场景路径。与 WeaponController.DEFAULT_SCENE 保持一致。
const SCENE_PATH: String = "res://scenes/weapons/weapon.tscn"
## 攻击层：PlayerAttack(32) / EnemyAttack(64)。武器场景会被玩家和敌人共用，
## 所以两套层都打开，由使用者在运行时按阵营改写。
const LAYER_PLAYER_ATTACK := 32
const LAYER_ENEMY_ATTACK := 64
## 受击层：PlayerHurtbox=8 / EnemyHurtbox=16。
const MASK_PLAYER_HURTBOX := 8
const MASK_ENEMY_HURTBOX := 16
## 判定盒兜底尺寸：AttackData / WeaponData 都没配时才用到。
const DEFAULT_HITBOX_OFFSET := Vector2(22, 0)
const DEFAULT_HITBOX_SIZE := Vector2(30, 26)

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("res://scenes/weapons")
	_make_universal()
	print("[GenerateWeaponScenes] 通用武器场景生成完毕：%s" % SCENE_PATH)
	get_tree().quit()


# ============================================================================
# 生成
# ============================================================================

## 通用武器场景。
## rotate_to_aim 默认 true（近战跟随瞄准）；远程武器由 WeaponData.rotate_to_aim
## 在 setup() 时改成 false，不需要单独的场景。
func _make_universal() -> void:
	var root: WeaponController = WeaponController.new()
	root.name = "Weapon"
	root.set("sprite_path", NodePath("SwingPivot/Sprite"))
	root.set("swing_pivot_path", NodePath("SwingPivot"))
	root.set("attack_box_path", NodePath("SwingPivot/AttackBox"))
	root.set("attack_shape_path", NodePath("SwingPivot/AttackBox/Shape"))
	root.set("rotate_to_aim", true)

	var pivot: Node2D = Node2D.new()
	pivot.name = "SwingPivot"
	root.add_child(pivot)

	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = "Sprite"
	pivot.add_child(sprite)

	pivot.add_child(_make_attack_box(DEFAULT_HITBOX_OFFSET, DEFAULT_HITBOX_SIZE))
	_save(root, SCENE_PATH)


## 构造一个标准攻击盒（含碰撞形状）。
func _make_attack_box(offset: Vector2, size: Vector2) -> Area2D:
	var box: AttackBox = AttackBox.new()
	box.name = "AttackBox"
	# 两套攻击层都打开，运行时由使用者按阵营收敛。
	box.collision_layer = LAYER_PLAYER_ATTACK | LAYER_ENEMY_ATTACK
	box.collision_mask = MASK_PLAYER_HURTBOX | MASK_ENEMY_HURTBOX
	box.monitoring = false
	box.position = offset

	var shape: CollisionShape2D = CollisionShape2D.new()
	shape.name = "Shape"
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	box.add_child(shape)
	return box


# ============================================================================
# 工具
# ============================================================================

func _save(root: Node, path: String) -> void:
	_set_owner_recursive(root, root)
	var packed: PackedScene = PackedScene.new()
	var err: int = packed.pack(root)
	if err != OK:
		push_error("[GenerateWeaponScenes] pack 失败 %s：%d" % [path, err])
		root.queue_free()
		return
	ResourceSaver.save(packed, path)
	root.queue_free()


func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner_node
		_set_owner_recursive(child, owner_node)
