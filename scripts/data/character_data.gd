## CharacterData —— 角色基础属性模板（玩家 / 敌人共用）
##
## 【负责什么】
##   一份"属性面板"：生命、法力、攻击、防御、移速、暴击等。玩家和敌人都用它，
##   保证伤害公式只有一套。
##
## 【挂哪个节点】
##   不是节点。保存在 res://data/characters/*.tres 与 res://data/enemies/*.tres。
##
## 【依赖谁】
##   仅 GameEnums。
##
## 【怎么扩展】
##   属性永远走 GameEnums.StatKind 这套键，这样词条系统可以无差别地改玩家和敌人。
class_name CharacterData
extends Resource

# ---------------------------------------------------------------- 身份 ----
@export var display_name: String = "未命名单位"
## 角色精灵图（4 列 × 7 行的 64×112 表）。
@export var sprite_texture: Texture2D
## 碰撞体半径（像素）。俯视视角下只用圆形碰撞。
@export_range(1.0, 64.0, 0.5) var body_radius: float = 6.0
## 精灵相对脚底中心的偏移（让脚踩在地面格子上）。
@export var sprite_offset: Vector2 = Vector2(0, -6)

# ---------------------------------------------------------------- 属性 ----
@export_range(1.0, 9999.0, 1.0) var max_health: float = 100.0
@export_range(0.0, 9999.0, 1.0) var max_mana: float = 50.0
@export_range(0.0, 999.0, 1.0) var attack_power: float = 10.0
@export_range(0.0, 999.0, 1.0) var defense: float = 0.0
## 移动速度（像素/秒）。16px 网格下 90~140 是舒适区间。
@export_range(10.0, 600.0, 5.0) var move_speed: float = 110.0
## 每秒回蓝。
@export_range(0.0, 100.0, 0.5) var mana_regen: float = 3.0
## 暴击率 0~1。
@export_range(0.0, 1.0, 0.01) var crit_chance: float = 0.05
## 暴击伤害倍率。
@export_range(1.0, 5.0, 0.05) var crit_damage: float = 1.5
## 冷却缩减 0~0.75（上限 75%，防止 0 冷却）。
@export_range(0.0, 0.75, 0.01) var cooldown_rate: float = 0.0
## 攻击速度倍率。1.0 为基准，>1 更快（会整体缩短攻击的前摇/判定/后摇）。
@export_range(0.25, 4.0, 0.05) var attack_speed: float = 1.0
## 吸血比例：造成伤害的多少转化为治疗。0 表示不吸血。
@export_range(0.0, 1.0, 0.01) var life_steal: float = 0.0
## 拾取半径（像素）。
@export_range(0.0, 200.0, 2.0) var pickup_range: float = 24.0

# ---------------------------------------------------------------- 受击 ----
## 受击硬直时长（秒）。硬直期间不能行动。
@export_range(0.0, 1.0, 1.0 / 60.0, "suffix:s") var hurt_time: float = 0.18
## 韧性：受到多少削韧才被打断。0 表示必定被打断。
@export_range(0.0, 500.0, 1.0) var poise: float = 0.0
## 无敌帧时长（受击后 / 翻滚）。
@export_range(0.0, 2.0, 1.0 / 60.0, "suffix:s") var invuln_time: float = 0.4

# ---------------------------------------------------------------- 抗击退 / 霸体 ----
## 击退抗性 0~1：0 = 全额吃击退，1 = 完全不被击退。
## Boss 设 1.0 就完全站桩，精英设 0.5 左右会被推动一点点——不用改任何代码。
@export_range(0.0, 1.0, 0.05) var knockback_resist: float = 0.0
## 霸体：true 时受击不会进入硬直（但依然掉血、依然会闪红）。
## 用于 Boss / 精英，避免被玩家连打到无法行动。
@export var super_armor: bool = false
## 受击击退衰减速度。越大停得越快（0 = 用 Actor 默认值）。
@export_range(0.0, 60.0, 1.0) var knockback_damping: float = 0.0

# ---------------------------------------------------------------- 受击表现 ----
## 受击闪色。默认红色（被打的通用反馈），可改成元素色。
@export var hurt_flash_color: Color = Color(1.0, 0.25, 0.25)
## 受击闪色持续时间。
@export_range(0.02, 0.6, 0.01, "suffix:s") var hurt_flash_time: float = 0.12
## 受击抖动强度（像素）。0 表示不抖。
@export_range(0.0, 12.0, 0.5) var hurt_shake_intensity: float = 2.0
## 受击抖动时长。
@export_range(0.0, 0.5, 0.01, "suffix:s") var hurt_shake_time: float = 0.12
## 死亡溶解时长（秒）。0 表示不溶解直接消失。
@export_range(0.0, 3.0, 0.05, "suffix:s") var death_dissolve_time: float = 0.5
## 死亡后是否淡出并销毁节点。Boss 可设 false 保留尸体。
@export var destroy_on_death: bool = true
