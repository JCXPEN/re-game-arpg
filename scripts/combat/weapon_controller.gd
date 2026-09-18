 ## WeaponController —— 武器场景控制器
##
## 【负责什么】
##   武器是一个独立场景，自己负责：朝向（跟随瞄准）、挥砍动画、判定盒的位置与
##   旋转、刀光特效。角色只负责"拿着它"，不关心它怎么打人。
##   这是"攻击效果与角色解耦"的核心：换武器 = 换场景，不用改角色脚本。
##
## 【挂哪个节点】
##   作为武器场景的根节点（Node2D）。推荐结构：
##     WeaponController (本脚本)   ← 朝瞄准方向旋转
##       └─ SwingPivot (Node2D)    ← 挥砍时在弧线内扫动
##            ├─ Sprite2D          ← 武器贴图（握把在原点）
##            └─ AttackBox (Area2D)← 判定盒，沿 +X 偏移，随武器一起转
##                  └─ CollisionShape2D
##   旋转半径来自 WeaponData.orbit_radius（见 _apply_weapon_data）：
##   根节点在角色原点，贴图沿 +X 再推出半径 → 整把武器绕使用者画圈。
##   如果场景里没有 SwingPivot，会自动创建一个（方便最简场景）。
##
## 【依赖谁】
##   WeaponData（数值/场景/弧线）、AttackData（单次挥砍的帧数据）、AttackBox（判定）。
##
## 【怎么扩展】
##   新武器 = 只新建 WeaponData（填好贴图/判定/弧线/是否跟随瞄准），
##   **不用新建场景、不用改角色或本脚本**。全项目共用 res://scenes/weapons/weapon.tscn，
##   武器之间的差异由 WeaponData 的字段描述，由 setup() 在运行时套用。
##   只有需要自定义节点结构（自带拖尾/粒子）的武器，才在 WeaponData.weapon_scene
##   里覆盖成专用场景。
class_name WeaponController
extends Node2D

## 通用武器场景。所有武器共用；WeaponData.weapon_scene 为空时用它。
const DEFAULT_SCENE: String = "res://scenes/weapons/weapon.tscn"

# ============================================================================
# 信号
# ============================================================================

## 挥砍判定窗口开启（可用于挂特效/音效）。
signal swing_started(data: AttackData)
## 挥砍判定窗口结束。
signal swing_finished(data: AttackData)
## 本次挥砍命中目标。携带最终伤害信息，供使用者做吸血/加怒等反应。
signal hit_landed(target: Actor, info: DamageInfo)

# ============================================================================
# @export
# ============================================================================

## 武器数据。由使用者（PlayerCombat/敌人）注入。
@export var weapon_data: WeaponData
## 武器贴图节点。
@export var sprite_path: NodePath
## 挥砍支点（在弧线内扫动的节点）。留空则自动创建。
@export var swing_pivot_path: NodePath
## 判定盒。
@export var attack_box_path: NodePath
## 判定形状。
@export var attack_shape_path: NodePath
## 是否每帧把朝向对齐到 aim_direction（远程武器可以不转）。
## 场景里的值只是"没绑 WeaponData 时"的兜底；setup() 会用 WeaponData.rotate_to_aim 覆盖，
## 这样同一把通用场景能同时服务近战（跟随瞄准）和远程（不跟随）。
@export var rotate_to_aim: bool = true

# ============================================================================
# 私有变量
# ============================================================================

## 使用者（持有武器的 Actor）。
var _wielder: Actor
## 当前瞄准方向（世界空间单位向量）。
var _aim_direction: Vector2 = Vector2.RIGHT
## 挥砍支点。
var _swing_pivot: Node2D
## 武器贴图。
var _sprite: Sprite2D
## 判定盒。
var _attack_box: AttackBox
## 判定形状。
var _attack_shape: CollisionShape2D
## 当前挥砍的动画补间。
var _swing_tween: Tween
## 当前挥砍的弧线角度（度）。
var _swing_arc: float = 90.0
## 基础旋转（武器相对使用者朝向的偏移）。
var _base_rotation: float = 0.0

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	_resolve_nodes()
	if _attack_box != null:
		# 判定盒的命中事件由武器自己处理：它知道"这一下是什么武器打的"。
		_attack_box.hit_confirmed.connect(_on_hit_confirmed)


func _process(_delta: float) -> void:
	if not rotate_to_aim or _aim_direction.length_squared() < 0.0001:
		return
	# 武器整体旋转到瞄准方向：判定盒是它的子节点，于是判定跟着武器转。
	rotation = _aim_direction.angle() + _base_rotation
	# 朝左时如果只靠旋转，武器会被转 180° 变成"倒着拿"。正确做法是水平镜像
	# （flip_h）：贴图自带 held_rotation（-90°）后，镜像轴必须是 X——
	# 用 flip_v 会把刀刃翻到瞄准反方向。
	if _sprite != null:
		_sprite.flip_h = _aim_direction.x < 0.0


# ============================================================================
# 公开方法
# ============================================================================

## 绑定武器数据与使用者。
func setup(data: WeaponData, wielder: Actor) -> void:
	weapon_data = data
	_wielder = wielder
	_resolve_nodes()
	_apply_weapon_data()
	# 立刻按武器数据套一次判定盒（偏移/尺寸）。
	# 真正挥砍时 begin_swing() 会用 AttackData 再覆盖一次（AttackData 优先），
	# 这里只是保证"武器一拿起来"判定盒就已经是正确的尺寸。
	_apply_hitbox_shape(null)


## 统一的武器实例化入口。
##
## 调用方（PlayerCombat / 敌人）只需要给出 WeaponData，不用知道场景路径、
## 不用判断"这把武器该用哪个 .tscn"——全部由这里决定：
##   WeaponData.weapon_scene 有值 → 用它（自定义结构）；
##   否则 → 用通用场景 DEFAULT_SCENE。
##
## 返回 null 表示没有可用武器数据或场景加载失败，调用方按"无武器"处理即可。
static func create(data: WeaponData, wielder: Actor) -> WeaponController:
	if data == null:
		return null
	var path: String = DEFAULT_SCENE
	if data.weapon_scene != null and not data.weapon_scene.resource_path.is_empty():
		path = data.weapon_scene.resource_path
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		push_warning("[WeaponController] 武器场景加载失败：%s" % path)
		return null
	var instance: WeaponController = scene.instantiate() as WeaponController
	if instance == null:
		push_warning("[WeaponController] 武器场景根节点不是 WeaponController：%s" % path)
		return null
	instance.setup(data, wielder)
	return instance


## 瞄准原点 —— 武器**真正绕其旋转的中心**（世界坐标）。
##
## 【为什么必须有这个接口】
##   武器的旋转中心是它自己的原点，而这个原点由**挂载点**决定
##   （player.tscn / enemy.tscn 的 WeaponMount 在 y = -6，用来对齐"手"的高度），
##   它**不等于**角色原点 —— 角色原点是脚下（Sprite.offset = (0, -6) 正是为此）。
##   瞄准角若从角色原点算起，刀尖与判定盒就指不到鼠标：两者差 6px，
##   鼠标离角色越近偏得越多（离 30px 时约 11°，贴脸时甚至会把刀指到反方向）。
##
## 【为什么放在武器里】"绕哪儿转"是武器自己的事：调用方（PlayerCombat / 敌人 AI）
##   只需问武器要锚点，不必知道挂载点叫什么、在哪一层、偏移多少。
##   以后调整 WeaponMount 位置或换成不同体型的角色，瞄准代码一行都不用改。
func get_aim_origin() -> Vector2:
	return global_position


## 设置瞄准方向（世界空间）。由使用者每帧驱动。
## 方向应当从 `get_aim_origin()` 出发计算，见其说明。
func set_aim(direction: Vector2) -> void:
	if direction.length_squared() > 0.0001:
		_aim_direction = direction.normalized()


## 开始一次挥砍。attack_data 为该段的帧数据。
func begin_swing(attack_data: AttackData) -> void:
	if attack_data == null:
		return
	_apply_hitbox_shape(attack_data)
	if _attack_box != null:
		_attack_box.begin_swing(attack_data)
	_start_swing_animation(attack_data)
	swing_started.emit(attack_data)


## 结束挥砍。
func end_swing() -> void:
	if _attack_box != null:
		_attack_box.end_swing()
	_stop_swing_animation()
	if _attack_box != null and _attack_box.attack_data != null:
		swing_finished.emit(_attack_box.attack_data)


## 当前判定盒（供外部查询）。
func get_attack_box() -> AttackBox:
	return _attack_box


## 武器贴图节点（供外部做翻转等表现）。
func get_sprite() -> Sprite2D:
	return _sprite


# ============================================================================
# 私有方法
# ============================================================================

## 解析场景里的节点，缺 SwingPivot 就建一个。
func _resolve_nodes() -> void:
	if not sprite_path.is_empty():
		_sprite = get_node_or_null(sprite_path) as Sprite2D
	if _sprite == null:
		_sprite = get_node_or_null("Sprite") as Sprite2D
	if not swing_pivot_path.is_empty():
		_swing_pivot = get_node_or_null(swing_pivot_path) as Node2D
	if _swing_pivot == null:
		_swing_pivot = get_node_or_null("SwingPivot") as Node2D
	if _swing_pivot == null:
		# 最简场景兜底：自动包一层支点，保证挥砍扫动逻辑可用。
		_swing_pivot = Node2D.new()
		_swing_pivot.name = "SwingPivot"
		add_child(_swing_pivot)
		if _sprite != null:
			var old_parent: Node = _sprite.get_parent()
			if old_parent != null:
				old_parent.remove_child(_sprite)
			_swing_pivot.add_child(_sprite)
	if not attack_box_path.is_empty():
		_attack_box = get_node_or_null(attack_box_path) as AttackBox
	if _attack_box == null:
		_attack_box = find_child("AttackBox", true, false) as AttackBox
	if not attack_shape_path.is_empty():
		_attack_shape = get_node_or_null(attack_shape_path) as CollisionShape2D
	if _attack_shape == null and _attack_box != null:
		_attack_shape = _attack_box.get_node_or_null("Shape") as CollisionShape2D
	# 判定形状默认与其它实例共享同一份资源（场景里的 sub_resource）。
	# 所有武器现在共用一个通用场景，如果不复制，改 A 武器的判定尺寸会
	# 连带改掉 B 武器的——必须让每把武器实例持有自己的形状。
	if _attack_shape != null and _attack_shape.shape != null \
			and not _attack_shape.shape.resource_local_to_scene:
		_attack_shape.shape = _attack_shape.shape.duplicate()


## 把武器数据应用到贴图与表现参数。
## 这里是"一把通用场景服务所有武器"的关键：所有差异都从 WeaponData 里取。
func _apply_weapon_data() -> void:
	if weapon_data == null:
		return
	if _sprite != null:
		_sprite.texture = weapon_data.held_texture
		# 旋转半径：贴图沿武器 +X（也就是"朝向"方向）再推出 orbit_radius。
		# 根节点每帧转到瞄准角 → 贴图就在半径 = orbit_radius（+ 手持偏移）的圆上跑。
		# 半径 0 = 老行为（武器贴图嵌在身体里）。判定盒不受影响，仍按
		# hitbox_offset 摆（见 _apply_hitbox_shape），观感与攻击距离两个旋钮互相独立。
		_sprite.position = Vector2(weapon_data.held_offset.x + weapon_data.orbit_radius, weapon_data.held_offset.y)
		_sprite.rotation_degrees = weapon_data.held_rotation
	_swing_arc = weapon_data.swing_arc_degrees
	# 近战跟随瞄准旋转，远程不跟随——由数据决定，而不是靠换场景。
	rotate_to_aim = weapon_data.rotate_to_aim


## 按 AttackData 设置判定盒的偏移与尺寸。
## 判定盒是 SwingPivot 的子节点，所以这里的位置是"武器局部坐标"——
## 武器一转，判定盒跟着转，天然做到"判定跟随武器而不是角色"。
func _apply_hitbox_shape(attack_data: AttackData) -> void:
	if _attack_box == null:
		return
	# 偏移：沿武器 +X 方向推出。优先级 AttackData > WeaponData > 场景默认值。
	if attack_data != null:
		_attack_box.position = attack_data.hitbox_offset
	elif weapon_data != null:
		_attack_box.position = weapon_data.hitbox_offset
	if _attack_shape == null:
		return
	var rect: RectangleShape2D = _attack_shape.shape as RectangleShape2D
	if rect == null:
		rect = RectangleShape2D.new()
		_attack_shape.shape = rect
	# 尺寸同理：AttackData 优先，没有就退回武器自身配置的兜底尺寸。
	var base_size: Vector2 = rect.size
	if attack_data != null:
		base_size = attack_data.hitbox_size
	elif weapon_data != null:
		base_size = weapon_data.hitbox_size
	var range_mult: float = weapon_data.range_mult if weapon_data != null else 1.0
	rect.size = base_size * range_mult


## 挥砍扫动：让 SwingPivot 在 ±arc/2 之间扫过。
## 判定盒挂在支点下，于是判定范围也跟着扫——这才像"挥砍"而不是"戳一下"。
func _start_swing_animation(attack_data: AttackData) -> void:
	if _swing_pivot == null:
		return
	var duration: float = weapon_data.swing_duration if weapon_data != null else attack_data.active
	duration = maxf(duration, 0.02)
	var half_arc: float = deg_to_rad(_swing_arc) * 0.5
	# 从一侧扫到另一侧。朝左时镜像，保证挥砍方向与朝向一致。
	var flip: float = -1.0 if _aim_direction.x < 0.0 else 1.0
	_swing_pivot.rotation = -half_arc * flip
	if _swing_tween != null and _swing_tween.is_valid():
		_swing_tween.kill()
	_swing_tween = create_tween()
	_swing_tween.tween_property(_swing_pivot, "rotation", half_arc * flip, duration)


func _stop_swing_animation() -> void:
	if _swing_tween != null and _swing_tween.is_valid():
		_swing_tween.kill()
	if _swing_pivot != null:
		_swing_pivot.rotation = 0.0


# ============================================================================
# 信号回调
# ============================================================================

## 判定盒确认命中。这里只做转发，具体反应（吸血/特效）由使用者决定。
func _on_hit_confirmed(target: Actor, info: DamageInfo) -> void:
	hit_landed.emit(target, info)
