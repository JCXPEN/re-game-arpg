## ModifierData —— Roguelite 词条定义
##
## 【负责什么】
##   一个词条 = 一条"对谁、改什么、怎么改、改多少"的规则。三选一 UI 从这里取候选，
##   ModifierSystem 把选中的词条累加成属性乘区。
##
## 【挂哪个节点】
##   不是节点。保存在 res://data/modifiers/*.tres。
##
## 【依赖谁】
##   GameEnums（ModifierTarget/StatKind/ModifierOp/Rarity）。
##
## 【怎么扩展】
##   新词条优先用现有 target + stat + op 组合表达；确实需要新机制（如"击杀回血"）
##   再加 target 枚举并实现对应处理器，保持数据驱动。
class_name ModifierData
extends Resource

# ---------------------------------------------------------------- 基础 ----
@export var display_name: String = "未命名词条"
@export_multiline var description: String = ""
@export var icon: Texture2D

# ---------------------------------------------------------------- 稀有度 ----
@export var rarity: GameEnums.Rarity = GameEnums.Rarity.COMMON
## 抽取权重。越高越常见；稀有词条权重低。
@export_range(0.0, 100.0, 0.5) var weight: float = 10.0
## 同一局内最多能叠几层。0 表示无限。
@export_range(0, 20, 1) var max_stacks: int = 0

# ---------------------------------------------------------------- 作用方式 ----
## 作用对象：属性 / 武器 / 技能 / 全局规则。
@export var target: GameEnums.ModifierTarget = GameEnums.ModifierTarget.STAT
## 修改哪个数值。
@export var stat: GameEnums.StatKind = GameEnums.StatKind.ATTACK_POWER
## 修改方式：加法 / 百分比 / 独立乘区。
@export var op: GameEnums.ModifierOp = GameEnums.ModifierOp.FLAT
## 修改量。含义随 op 变化：FLAT 是绝对值，PERCENT 是 0.15 表示 +15%。
@export var value: float = 0.0
## 每层叠加时 value 的增量（用于"每层 +5%，可叠 5 层"）。
@export var value_per_stack: float = 0.0

# ---------------------------------------------------------------- 特殊规则 ----
## 作用于特定武器类别时才生效（target == WEAPON 时使用）。
## 空数组表示对全部武器生效。
@export var weapon_kinds: Array[GameEnums.WeaponKind] = []
## 作用于特定元素法术时才生效（target == ABILITY 时使用）。
## 空数组表示全部法术生效。
@export var elements: Array[GameEnums.Element] = []
## 触发条件标签（如 "on_kill"、"on_crit"、"low_health"）。空表示常驻。
@export var trigger_tag: StringName = &""

# ---------------------------------------------------------------- 表现 ----
## 选中时的音效。
@export var pick_sfx: AudioStream
## 稀有度对应的 UI 颜色（在 Inspector 里不用填，由代码按 rarity 推导）。
func get_rarity_color() -> Color:
	match rarity:
		GameEnums.Rarity.COMMON:
			return Color(0.78, 0.78, 0.78)
		GameEnums.Rarity.RARE:
			return Color(0.36, 0.62, 1.0)
		GameEnums.Rarity.EPIC:
			return Color(0.72, 0.42, 1.0)
		GameEnums.Rarity.LEGENDARY:
			return Color(1.0, 0.78, 0.25)
		_:
			return Color.WHITE
