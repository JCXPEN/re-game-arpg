## GameEnums —— 全项目共享的枚举定义
##
## 【负责什么】
##   把"跨多个 Resource 和脚本都要用"的枚举集中到一处，避免每个文件各定义一套
##   导致 Inspector 里数值语义不一致。
##
## 【挂哪个节点】
##   不是节点。通过 `class_name GameEnums` 全局静态访问，例如 `GameEnums.Element.FIRE`。
##
## 【依赖谁】
##   不依赖任何东西。
##
## 【怎么扩展】
##   新增枚举时**只能追加在末尾**，不要插入或重排——否则已保存的 .tres 里的整数
##   会指向错误的枚举值，造成数据静默错位。
class_name GameEnums
extends RefCounted

## 伤害元素类型。决定命中特效颜色与元素抗性计算。
enum Element {
	NONE,   ## 无属性（普通物理）
	FIRE,   ## 火：持续灼烧
	ICE,    ## 冰：减速
	THUNDER ## 雷：连锁/麻痹
}

## 法术形态。决定生成什么场景、如何命中。
enum SpellForm {
	PROJECTILE, ## 弹道：直线飞行，碰到目标爆炸
	AREA,       ## 范围：在目标点生成 AOE
	ENCHANT     ## 附魔：临时强化武器
}

## 武器类别。决定动画帧、攻击方式与手感参数。
enum WeaponKind {
	MELEE,     ## 近战单手：快速三段连击
	RANGED,    ## 远程：发射弹道
	TWO_HANDED ## 双手：慢速大范围高伤
}

## 词条稀有度。决定出现权重与 UI 配色。
enum Rarity {
	COMMON,   ## 普通（灰）
	RARE,     ## 稀有（蓝）
	EPIC,     ## 史诗（紫）
	LEGENDARY ## 传说（金）
}

## 词条作用对象。决定 ModifierData 怎么把效果套用上去。
enum ModifierTarget {
	STAT,    ## 直接改属性（攻/防/速…）
	WEAPON,  ## 改武器（伤害倍率、攻速、范围）
	ABILITY, ## 改技能/法术（冷却、消耗、伤害）
	GLOBAL   ## 全局规则（暴击率、吸血、闪避…）
}

## 可被词条修改的数值键。用 StringName 做键，ModifierData 里存这个枚举。
enum StatKind {
	MAX_HEALTH,     ## 最大生命
	MAX_MANA,       ## 最大法力
	ATTACK_POWER,   ## 攻击力
	DEFENSE,        ## 防御
	MOVE_SPEED,     ## 移动速度
	ATTACK_SPEED,   ## 攻击速度
	CRIT_CHANCE,    ## 暴击率
	CRIT_DAMAGE,    ## 暴击伤害倍率
	COOLDOWN_RATE,  ## 冷却缩减
	MANA_REGEN,     ## 回蓝
	LIFE_STEAL,     ## 吸血
	PICKUP_RANGE    ## 拾取范围
}

## 词条修改方式。加法在乘法的**前面**结算，顺序固定：先 flat，再 percent，最后 multiply。
enum ModifierOp {
	FLAT,       ## 固定值加减（+10 攻击）
	PERCENT,    ## 百分比加减（+15% 攻击）
	MULTIPLY    ## 独立乘区（×1.2，多个之间相乘）
}

## 装备槽位。
enum EquipSlot {
	WEAPON,
	ARMOR,
	TRINKET
}

## 敌人 AI 类型。决定实例化哪个状态机脚本。
enum EnemyKind {
	MELEE,  ## 近战小怪：追击 → 攻击
	CASTER, ## 远程法师：保持距离 → 吟唱
	CHARGER ## 冲锋精英：蓄力 → 冲撞
}

## 状态机通用状态标签，仅用于调试打印与 UI 显示。
enum ActorState {
	IDLE,
	MOVE,
	ATTACK,
	ROLL,
	HURT,
	DEAD,
	CAST,
	CHARGE
}
