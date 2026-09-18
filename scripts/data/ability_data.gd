## AbilityData —— 技能定义（主动 / 被动统一基类数据）
##
## 【负责什么】
##   描述一个技能：主动还是被动、冷却、消耗、释放条件、效果场景/参数。
##   主动技能由 Ability 实例执行，被动技能在装备时挂上钩子。
##
## 【挂哪个节点】
##   不是节点。保存在 res://data/abilities/*.tres。
##
## 【依赖谁】
##   GameEnums、AttackData（伤害型技能复用）。
##
## 【怎么扩展】
##   新增技能类型时，在 GameEnums 里加枚举 + 在 Ability 子类里实现；不要在这里
##   堆 if-else。数值调优全部通过本资源的 @export 完成，不碰代码。
class_name AbilityData
extends Resource

# ---------------------------------------------------------------- 基础 ----
@export var display_name: String = "未命名技能"
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var rarity: GameEnums.Rarity = GameEnums.Rarity.COMMON

# ---------------------------------------------------------------- 类型 ----
## true = 主动技能（需要按键、有冷却）；false = 被动技能（常驻生效）。
@export var is_active: bool = true
## 是否在装备/获得时立即生效（被动技能用）。
@export var apply_on_equip: bool = true

# ---------------------------------------------------------------- 消耗 ----
@export_range(0.0, 500.0, 1.0) var mana_cost: float = 0.0
@export_range(0.0, 60.0, 0.05, "suffix:s") var cooldown: float = 5.0
@export_range(0.0, 5.0, 1.0 / 60.0, "suffix:s") var cast_time: float = 0.0
@export_range(0.0, 2.0, 1.0 / 60.0, "suffix:s") var recovery: float = 0.2

# ---------------------------------------------------------------- 释放条件 ----
## 需要的最小等级。
@export_range(1, 99, 1) var required_level: int = 1
## 需要的最低生命比例（0~1）。用于"残血才能放"的技能。
@export_range(0.0, 1.0, 0.05) var required_health_ratio: float = 0.0
## 只能在移动时释放？false 表示需要站定。
@export var allow_while_moving: bool = true

# ---------------------------------------------------------------- 效果 ----
## 效果场景（召唤物、爆炸、光环等）。
@export var effect_scene: PackedScene
## 伤害数据（伤害型技能）。
@export var attack_data: AttackData
## 效果数值：含义由具体 Ability 子类解释（治疗量/护盾量/位移距离…）。
@export var effect_value: float = 0.0
## 持续时间（增益/减益/召唤）。
@export_range(0.0, 120.0, 0.5, "suffix:s") var duration: float = 0.0
## 被动技能要修改的属性。键为 GameEnums.StatKind，值为 ModifierOp 对应的数值。
@export var passive_stat_mods: Dictionary = {}
## 被动技能给属性的修改方式。
@export var passive_op: GameEnums.ModifierOp = GameEnums.ModifierOp.FLAT

# ---------------------------------------------------------------- 表现 ----
@export var cast_sfx: AudioStream
@export var cast_effect: PackedScene
