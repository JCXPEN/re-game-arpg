## ItemData —— 物品定义（消耗品 / 材料 / 装备）
##
## 【负责什么】
##   背包与掉落系统的最小数据单元。同一份数据既能当消耗品（药水）也能当装备
##   （武器/护甲），靠 kind 区分。
##
## 【挂哪个节点】
##   不是节点。保存在 res://data/items/*.tres。
##
## 【依赖谁】
##   GameEnums、WeaponData（装备型物品可引用武器数据）。
##
## 【怎么扩展】
##   新物品类型加 kind 分支；数值一律走 @export，不在代码里写死。
class_name ItemData
extends Resource

## 物品类别。
enum Kind {
	CONSUMABLE, ## 消耗品：使用后生效
	MATERIAL,   ## 材料：仅用于合成/计数
	EQUIPMENT,  ## 装备：可穿戴
	KEY         ## 关键道具：不能丢弃，用于开门
}

# ---------------------------------------------------------------- 身份 ----
## 唯一 id，背包用 StringName 做键。
@export var id: StringName = &""
@export var display_name: String = "未命名物品"
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var kind: Kind = Kind.CONSUMABLE
@export var rarity: GameEnums.Rarity = GameEnums.Rarity.COMMON

# ---------------------------------------------------------------- 堆叠 ----
## 最大堆叠数。1 表示不可堆叠（装备）。
@export_range(1, 999, 1) var max_stack: int = 99
## 是否可丢弃。
@export var can_drop: bool = true

# ---------------------------------------------------------------- 消耗品 ----
## 使用时恢复的生命。
@export_range(0.0, 9999.0, 1.0) var heal_amount: float = 0.0
## 使用时恢复的法力。
@export_range(0.0, 9999.0, 1.0) var mana_amount: float = 0.0
## 使用冷却。
@export_range(0.0, 60.0, 0.05, "suffix:s") var use_cooldown: float = 0.5
## 使用音效。
@export var use_sfx: AudioStream

# ---------------------------------------------------------------- 装备 ----
## 装备槽位（kind == EQUIPMENT 时使用）。
@export var equip_slot: GameEnums.EquipSlot = GameEnums.EquipSlot.WEAPON
## 如果是武器，指向武器数据。
@export var weapon_data: WeaponData
## 装备提供的属性加成：键为 GameEnums.StatKind，值为数值。
@export var stat_bonus: Dictionary = {}

# ---------------------------------------------------------------- 价格 ----
@export_range(0, 999999, 1) var buy_price: int = 0
@export_range(0, 999999, 1) var sell_price: int = 0
