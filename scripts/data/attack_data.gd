## AttackData —— 一次攻击的完整描述（帧数据 + 伤害 + 手感）
##
## 【负责什么】
##   把"攻击"从代码里彻底抽出来：每一段连击、每一次蓄力、每个敌人招式都是
##   一个 AttackData 资源。战斗系统只读这些字段，不知道具体是谁在打。
##
## 【挂哪个节点】
##   不是节点。被 WeaponData / SpellData / EnemyData / AbilityData 以 @export 持有，
##   自身保存在 res://data/ 下的 .tres 里。
##
## 【依赖谁】
##   仅依赖 GameEnums 的枚举。
##
## 【怎么扩展】
##   想加"多段判定/位移/召唤"，就在下面追加 @export 字段，并在 AttackController
##   里读取；不要改已有字段的语义，否则旧 .tres 会变味。
##
## 【时间单位说明】
##   所有时间都用**秒**，但游戏手感通常按 60FPS 的"帧"思考。下方 @export_range
##   的 step 设为 1.0/60.0，Inspector 里拖动就是整帧，避免出现 0.0166 这种脏值。
class_name AttackData
extends Resource

# ---------------------------------------------------------------- 时间轴 ----
## 前摇：按下攻击到判定生效之间的时间。越长越"重"。
@export_range(0.0, 2.0, 1.0 / 60.0, "suffix:s") var startup: float = 0.12
## 判定持续：攻击盒开启的时间窗口。
@export_range(0.0, 2.0, 1.0 / 60.0, "suffix:s") var active: float = 0.10
## 后摇：判定结束到可以再次行动。**可被翻滚/下一段连击取消**，这是手感关键。
@export_range(0.0, 3.0, 1.0 / 60.0, "suffix:s") var recovery: float = 0.22
## 从后摇开始算起，多久之后允许输入下一段连击（提前输入会被缓冲）。
@export_range(0.0, 3.0, 1.0 / 60.0, "suffix:s") var combo_window: float = 0.18

# ---------------------------------------------------------------- 伤害 ----
## 基础伤害。最终伤害 = (基础 + 攻击力*缩放) * 各种词条乘区。
@export var damage: float = 10.0
## 攻击力对伤害的缩放系数。0 表示纯固定伤害。
@export_range(0.0, 5.0, 0.05) var attack_scaling: float = 1.0
@export var element: GameEnums.Element = GameEnums.Element.NONE
## 削韧/硬直值：命中后给目标施加的硬直强度，越高越容易打断敌人。
@export_range(0.0, 200.0, 1.0) var poise_damage: float = 10.0

# ---------------------------------------------------------------- 手感 ----
## 击退力度（像素/秒）。0 表示原地硬直不后退。
@export_range(0.0, 2000.0, 10.0) var knockback: float = 220.0
## 命中顿帧时长。武器越重顿帧越长，是"打击感"的第一来源。
@export_range(0.0, 0.5, 1.0 / 60.0, "suffix:s") var hitstop: float = 0.06
## 命中时屏幕震动强度（像素）。
@export_range(0.0, 40.0, 0.5) var shake: float = 3.0
## 攻击时的自身位移（前冲），像素/秒。重击/冲刺斩用得上。
@export var self_motion: Vector2 = Vector2.ZERO
## 攻击判定盒相对角色的偏移与尺寸（像素）。
@export var hitbox_offset: Vector2 = Vector2(20, 0)
@export var hitbox_size: Vector2 = Vector2(28, 24)
## 命中特效场景。null 表示不生成。
@export var hit_effect: PackedScene
## 攻击挥动音效（起手播放）。
@export var swing_sfx: AudioStream
## 命中音效（打到目标时播放）。
@export var hit_sfx: AudioStream

# ---------------------------------------------------------------- 连击 ----
## 下一段连击的数据。null 表示这是最后一段。
@export var next_combo: AttackData
## 这段连击可以取消进翻滚的时机（相对后摇起点）。用于"翻滚取消后摇"。
@export_range(0.0, 1.0, 0.05) var roll_cancel_at: float = 0.0
