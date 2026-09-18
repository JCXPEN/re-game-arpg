## GenerateWorldScenes —— 交互物场景生成器（编辑器工具脚本）
##
## 【负责什么】
##   生成存档点、提示牌、NPC、治愈泉、锁门、金币堆等交互物的 .tscn。
##   这些场景结构简单但重复度高，用代码生成避免手写格式出错。
##
## 【怎么运行】
##   Godot --headless --path . res://tools/generate_world_scenes.tscn
##
## 【为什么用生成器】
##   .tscn 的 ext_resource/sub_resource 编号手写极易错位，且改一次碰撞层就要
##   动多个文件。集中生成保证所有交互物碰撞层一致。
extends Node

# ============================================================================
# 常量
# ============================================================================

## 交互物碰撞层：Interactable = 第 10 层 = 512。
const LAYER_INTERACTABLE := 512
## 玩家碰撞层：PlayerBody = 第 2 层 = 2。
const LAYER_PLAYER := 2
## 交互范围尺寸（像素）。
const REACH := 24.0

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("res://scenes/world")
	_make_save_point()
	_make_sign_post()
	_make_heal_spring()
	_make_npc()
	_make_locked_door()
	print("[GenerateWorldScenes] 交互物场景生成完毕")
	get_tree().quit()


# ============================================================================
# 生成
# ============================================================================

## 存档点：用魔法阵贴图当篝火/水晶。
func _make_save_point() -> void:
	var root: Area2D = _make_area("SavePoint", "res://scripts/world/save_point.gd")
	_add_sprite(root, "res://assets/fx/magic/CircleOrange.png", 4, 0, Vector2(0, -6))
	_save(root, "res://scenes/world/save_point.tscn")


## 提示牌。
func _make_sign_post() -> void:
	var root: Area2D = _make_area("SignPost", "res://scripts/world/sign_post.gd")
	_add_sprite(root, "res://assets/sprites/items/ScrollFire.png", 1, 0, Vector2(0, -6))
	_save(root, "res://scenes/world/sign_post.tscn")


## 治愈泉：用冰元素特效贴图。
func _make_heal_spring() -> void:
	var root: Area2D = _make_area("HealSpring", "res://scripts/world/heal_spring.gd")
	_add_sprite(root, "res://assets/fx/elemental/Ice.png", 4, 0, Vector2(0, -4))
	_save(root, "res://scenes/world/heal_spring.tscn")


## NPC：用村民角色表。
func _make_npc() -> void:
	var root: Area2D = _make_area("NPC", "res://scripts/world/npc.gd")
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = load("res://assets/sprites/characters/Villager.png")
	sprite.hframes = 4
	sprite.vframes = 7
	sprite.offset = Vector2(0, -6)
	sprite.set_script(load("res://scripts/player/actor_sprite.gd"))
	root.add_child(sprite)
	_save(root, "res://scenes/world/npc.tscn")


## 锁门：含阻挡碰撞体 + 门贴图。
func _make_locked_door() -> void:
	var root: Node2D = Node2D.new()
	root.name = "LockedDoor"
	root.set_script(load("res://scripts/world/locked_door.gd"))
	root.set("blocker_path", NodePath("Blocker"))
	root.set("sprite_path", NodePath("Sprite"))

	var blocker: StaticBody2D = StaticBody2D.new()
	blocker.name = "Blocker"
	blocker.collision_layer = 1
	blocker.collision_mask = 0
	var shape: CollisionShape2D = CollisionShape2D.new()
	shape.name = "Shape"
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(16, 16)
	shape.shape = rect
	blocker.add_child(shape)
	root.add_child(blocker)

	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = load("res://assets/tilesets/TilesetRelief.png")
	sprite.region_enabled = true
	sprite.region_rect = Rect2(5 * 16, 6 * 16, 16, 16)
	root.add_child(sprite)

	_save(root, "res://scenes/world/locked_door.tscn")


# ============================================================================
# 工具
# ============================================================================

## 创建一个带交互范围的标准交互物根节点。
func _make_area(scene_name: String, script_path: String) -> Area2D:
	var root: Area2D = Area2D.new()
	root.name = scene_name
	root.collision_layer = LAYER_INTERACTABLE
	root.collision_mask = LAYER_PLAYER
	root.set_script(load(script_path))
	var shape: CollisionShape2D = CollisionShape2D.new()
	shape.name = "Shape"
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(REACH, REACH)
	shape.shape = rect
	root.add_child(shape)
	return root


## 加一个精灵子节点。
func _add_sprite(root: Node, tex_path: String, hframes: int, frame: int, offset: Vector2) -> void:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = load(tex_path)
	if hframes > 1:
		sprite.hframes = hframes
		sprite.frame = frame
	sprite.offset = offset
	root.add_child(sprite)


## 保存场景。
func _save(root: Node, path: String) -> void:
	_set_owner_recursive(root, root)
	var packed: PackedScene = PackedScene.new()
	var err: int = packed.pack(root)
	if err != OK:
		push_error("[GenerateWorldScenes] pack 失败 %s：%d" % [path, err])
		root.queue_free()
		return
	ResourceSaver.save(packed, path)
	root.queue_free()


func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner_node
		_set_owner_recursive(child, owner_node)
