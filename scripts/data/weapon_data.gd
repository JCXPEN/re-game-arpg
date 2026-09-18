## WeaponData —— 武器定义
##
## 【负责什么】
##   描述一把武器的全部表现：类别、攻击连段、蓄力重击、远程弹道、手持偏移、
##   图标与音效。PlayerCombat 只认这个资源，不认具体武器名字。
##
## 【挂哪个节点】
##   不是节点。保存在 res://data/weapons/*.tres，由 PlayerCombat 的 @export 引用。
##
## 【依赖谁】
##   AttackData（攻击帧数据）、GameEnums（武器类别）。
##
## 【怎么扩展】
##   新增"武器特性"（如吸血、破甲）时优先做成 ModifierData 挂到 modifier_pool，
##   而不是往这里加一堆 bool，保持武器数据本身干净。
class_name WeaponData
extends Resource

# ---------------------------------------------------------------- 基础 ----
## 显示名（UI 用）。
@export var display_name: String = "未命名武器"
## 描述文本。
@export_multiline var description: String = ""
## 图标（背包/装备栏显示）。
@export var icon: Texture2D
## 手持时的武器贴图（叠在角色精灵上）。
@export var held_texture: Texture2D
## 手持贴图相对角色中心的偏移（像素）。朝右为基准，朝左时自动镜像 X。
@export var held_offset: Vector2 = Vector2(8, 0)
## 手持贴图旋转（度）。用于让武器贴合挥砍角度。
## 本项目美术包的 SpriteInHand 贴图统一是"握把在上、刃/头朝下"画的（弓横画），
## 而引擎约定武器贴图的攻击方向沿 +X（武器节点会旋转到瞄准方向），
## 所以默认逆时针转 90°（Godot Y 轴朝下，负角度 = 视觉逆时针）把刃对准 +X。
## 换用"刃朝右"惯例的美术包时，在对应 .tres 里覆写为 0 即可。
@export var held_rotation: float = -90.0
## 旋转半径（像素）：武器贴图绕使用者画圈的半径。
## 实现上把贴图沿武器 +X（朝向方向）再推出这个距离 —— 根节点每帧转到瞄准角，
## 贴图就在半径 = orbit_radius（+ held_offset）的圆上跑，半径 0 = 武器贴在身上。
## **只影响观感**：判定盒仍按 hitbox_offset / AttackData.hitbox_offset 摆，
## 所以"武器离身体多远"和"能打多远"是两个独立的旋钮。
## 半径给得很大（>15 左右）时刃会伸到判定盒外，那时再把这把武器的 hitbox_offset 加大。
## 想给单把武器单独配半径，就在它的 .tres 里加一行：orbit_radius = 16.0
@export_range(0.0, 64.0, 1.0, "suffix:px") var orbit_radius: float = 12.0

# ---------------------------------------------------------------- 分类 ----
@export var kind: GameEnums.WeaponKind = GameEnums.WeaponKind.MELEE
## 装备槽位。目前武器固定占 WEAPON 槽。
@export var slot: GameEnums.EquipSlot = GameEnums.EquipSlot.WEAPON
## 稀有度（影响 UI 边框颜色）。
@export var rarity: GameEnums.Rarity = GameEnums.Rarity.COMMON

# ---------------------------------------------------------------- 攻击 ----
## 三段连击的第一段。通过 AttackData.next_combo 串起第 2、3 段。
@export var combo_1: AttackData
## 蓄力重击（按住重击键蓄满后释放）。
@export var heavy_attack: AttackData
## 蓄满所需时间。达到该时间才打出最大伤害/范围。
@export_range(0.1, 3.0, 0.05, "suffix:s") var charge_time: float = 0.6
## 蓄力期间的移动速度倍率（越重越慢）。
@export_range(0.0, 1.0, 0.05) var charge_move_mult: float = 0.35

# ---------------------------------------------------------------- 远程 ----
## 远程武器发射的弹道场景。仅 kind == RANGED 时使用。
@export var projectile_scene: PackedScene
## 发射冷却（远程武器用这个控制射速，而非连击）。
@export_range(0.05, 3.0, 0.01, "suffix:s") var projectile_cooldown: float = 0.35
## 一次发射几发（散射）。
@export_range(1, 12, 1) var projectile_count: int = 1
## 散射角度（度）。projectile_count > 1 时生效。
@export_range(0.0, 90.0, 1.0, "suffix:°") var spread_degrees: float = 0.0

# ---------------------------------------------------------------- 属性 ----
## 攻击力加成（武器自带的攻击力，与角色基础攻击力相加）。
@export_range(0.0, 999.0, 1.0) var attack_bonus: float = 0.0
## 攻速倍率：>1 更快。会同时缩放 AttackData 的 startup/recovery。
@export_range(0.25, 3.0, 0.05) var attack_speed: float = 1.0
## 攻击范围倍率：缩放判定盒尺寸。
@export_range(0.25, 3.0, 0.05) var range_mult: float = 1.0

# ---------------------------------------------------------------- 场景 ----
## 武器场景。全项目**只有一把**通用武器场景 res://scenes/weapons/weapon.tscn，
## 所有武器共用它；武器之间的差异一律由本资源的字段描述（数据驱动），
## 不再"一把武器一个 .tscn"。
## 只有确实需要自定义节点结构（如自带拖尾粒子）的武器才在这里覆盖，
## 留空即使用通用场景。
@export var weapon_scene: PackedScene
## 挥砍特效场景（刀光）。由武器在判定窗口生成。
@export var swing_effect_scene: PackedScene
## 挥砍时武器贴图相对角色的旋转范围（度）。负值向一侧扫，正值向另一侧。
## 例如 90 表示从 -45° 扫到 +45°。
@export_range(0.0, 360.0, 5.0) var swing_arc_degrees: float = 90.0
## 挥砍动画时长（秒）。用于武器贴图的扫动与刀光节奏。
@export_range(0.05, 1.5, 1.0 / 60.0, "suffix:s") var swing_duration: float = 0.18
## 武器是否每帧跟随瞄准方向旋转。
## 近战（剑/刀/锤）为 true：刀尖始终指哪打哪；
## 远程（弓/法杖）为 false：武器只做挥砍动画，弹道方向由发射器单独算，
## 否则弓会"跟着鼠标转圈"，看起来很怪。
@export var rotate_to_aim: bool = true
## 判定盒相对武器支点的偏移（像素，沿武器 +X 方向推出）。
## 这是"武器没配 AttackData 时"的兜底值；有 AttackData 时以 AttackData 为准。
@export var hitbox_offset: Vector2 = Vector2(22, 0)
## 判定盒尺寸（像素）。同样是 AttackData 缺席时的兜底值。
@export var hitbox_size: Vector2 = Vector2(30, 26)

# ---------------------------------------------------------------- 音效 ----
@export var swing_sfx: AudioStream
@export var hit_sfx: AudioStream
