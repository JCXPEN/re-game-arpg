## EnemyData —— 敌人定义（AI 参数 + 掉落 + 表现）
##
## 【负责什么】
##   在 CharacterData 之上叠加"敌人特有的东西"：AI 类型、感知范围、攻击数据、
##   掉落、经验。EnemyBase 读它来配置状态机。
##
## 【挂哪个节点】
##   不是节点。保存在 res://data/enemies/*.tres。
##
## 【依赖谁】
##   CharacterData（内嵌继承属性）、AttackData、GameEnums。
##
## 【怎么扩展】
##   EnemyBase 通过 kind 选择状态机；新增敌人种类只需新建 .tres 并指定 kind，
##   不用写新脚本。要新 AI 行为才加脚本。
class_name EnemyData
extends Resource

# ---------------------------------------------------------------- 基础 ----
## 数据 id（DataRegistry 的索引键）。用于"击败记录 / 关卡 boss_id"这类需要稳定
## 标识符的场合——display_name 是本地化文案，随时可能改，不能当 id 用。
## 留空时 load 阶段会退回文件名；仍为空则该敌人不参与击败登记。
@export var id: StringName = &""
@export var display_name: String = "未命名敌人"
## 内嵌的角色属性面板。
@export var stats: CharacterData
## 稀有度/危险度，UI 上显示血条颜色。
@export var kind: GameEnums.EnemyKind = GameEnums.EnemyKind.MELEE
## 是否算精英（血条更醒目、掉落更好）。
@export var is_elite: bool = false
## 是否算 Boss（触发 Boss 血条与击败事件）。
@export var is_boss: bool = false
## 击杀掉落的金币数。旧实现把 `add_gold(1)` 硬编码在死亡回调里，
## 精英与 Boss 和杂兵拿一样多；现在按数据配置。
@export_range(0, 9999, 1) var gold_reward: int = 1

# ---------------------------------------------------------------- AI ----
## 感知半径：进入后开始追击/警戒。
@export_range(0.0, 1000.0, 5.0) var detect_range: float = 120.0
## 失去目标后继续追多久（秒）。
@export_range(0.0, 30.0, 0.5, "suffix:s") var lose_target_time: float = 3.0
## 进入攻击的距离。
@export_range(0.0, 500.0, 2.0) var attack_range: float = 22.0
## 两次攻击之间的间隔。
@export_range(0.05, 10.0, 0.05, "suffix:s") var attack_cooldown: float = 1.2
## 法师保持的理想距离（CASTER 用）。
@export_range(0.0, 500.0, 2.0) var preferred_range: float = 90.0
## 冲锋前的蓄力时间（CHARGER 用）。
@export_range(0.0, 5.0, 0.05, "suffix:s") var charge_time: float = 0.7
## 冲锋速度倍率（CHARGER 用）。
@export_range(1.0, 8.0, 0.1) var charge_speed_mult: float = 4.0
## 巡逻/游荡半径（没发现玩家时的活动范围）。
@export_range(0.0, 500.0, 5.0) var wander_radius: float = 40.0

# ---------------------------------------------------------------- 武器 ----
## 敌人使用的武器数据。判定盒挂在武器里 → 判定跟随敌人朝向。
## 留空则用敌人场景自带的判定盒。
## 与玩家共用同一套 WeaponData + 通用武器场景，敌人不需要自己的武器 .tscn。
@export var weapon: WeaponData
## 自定义武器场景（可选）。留空则使用通用武器场景。
## 只有当该敌人的武器需要特殊节点结构时才填。
@export var weapon_scene: PackedScene

# ---------------------------------------------------------------- 攻击 ----
## 近战/冲锋的攻击数据。
@export var melee_attack: AttackData
## 远程弹道场景（CASTER 用）。
@export var projectile_scene: PackedScene
## 远程攻击数据。
@export var ranged_attack: AttackData

# ---------------------------------------------------------------- 掉落 ----
## 击杀获得的经验。
@export_range(0, 99999, 1) var experience_reward: int = 10
## 掉落表：数组元素为 { item_id: StringName, chance: float } 形式的 Dictionary。
@export var drop_table: Array[Dictionary] = []
## 掉落物场景。
@export var drop_scene: PackedScene

# ---------------------------------------------------------------- 表现 ----
## 死亡特效场景。
@export var death_effect: PackedScene
## 受击音效。
@export var hurt_sfx: AudioStream
## 攻击音效。
@export var attack_sfx: AudioStream
