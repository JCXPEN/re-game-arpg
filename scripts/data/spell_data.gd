## SpellData —— 法术定义（元素 × 形态）
##
## 【负责什么】
##   描述一个法术：什么元素、什么形态、消耗多少 MP、吟唱多久、冷却多久、
##   生成什么场景/特效。SpellCaster 只读这个资源，不关心是火球还是冰锥。
##
## 【挂哪个节点】
##   不是节点。保存在 res://data/spells/*.tres。
##
## 【依赖谁】
##   GameEnums（Element/SpellForm）、AttackData（法术伤害也复用攻击数据）。
##
## 【怎么扩展】
##   新元素/新形态只需在 GameEnums 里加枚举值 + 在这里加分支，不用改 SpellCaster
##   的主流程。附魔类法术通过 enchant_attack 覆盖武器的攻击数据来实现。
class_name SpellData
extends Resource

# ---------------------------------------------------------------- 基础 ----
@export var display_name: String = "未命名法术"
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var rarity: GameEnums.Rarity = GameEnums.Rarity.COMMON

# ---------------------------------------------------------------- 分类 ----
## 元素属性，决定命中特效颜色与抗性计算。
@export var element: GameEnums.Element = GameEnums.Element.FIRE
## 法术形态，决定释放流程走哪条分支。
@export var form: GameEnums.SpellForm = GameEnums.SpellForm.PROJECTILE

# ---------------------------------------------------------------- 消耗 ----
## 法力消耗。不足则无法释放。
@export_range(0.0, 500.0, 1.0) var mana_cost: float = 12.0
## 冷却时间（秒）。受 COOLDOWN_RATE 词条影响。
@export_range(0.0, 30.0, 0.05, "suffix:s") var cooldown: float = 1.2
## 吟唱时间（秒）。吟唱期间移动速度下降且被打断会失败。
@export_range(0.0, 5.0, 1.0 / 60.0, "suffix:s") var cast_time: float = 0.0
## 吟唱期间的移动速度倍率。
@export_range(0.0, 1.0, 0.05) var cast_move_mult: float = 0.3
## 释放后的公共后摇（秒），期间不能再次施法。
@export_range(0.0, 2.0, 1.0 / 60.0, "suffix:s") var recovery: float = 0.25

# ---------------------------------------------------------------- 效果 ----
## 伤害数据（复用 AttackData：弹道/范围伤害都用它）。
@export var attack_data: AttackData
## 弹道场景（form == PROJECTILE 时生成）。
@export var projectile_scene: PackedScene
## 范围特效场景（form == AREA 时在目标点生成）。
@export var area_scene: PackedScene
## 附魔时替换的武器攻击数据（form == ENCHANT 时生效）。
@export var enchant_attack: AttackData
## 附魔持续时间（秒）。
@export_range(0.0, 60.0, 0.5, "suffix:s") var enchant_duration: float = 8.0

# ---------------------------------------------------------------- 表现 ----
## 吟唱时角色脚下生成的特效（魔法阵等）。
@export var cast_effect: PackedScene
## 释放音效。
@export var cast_sfx: AudioStream
## 命中音效。
@export var impact_sfx: AudioStream
