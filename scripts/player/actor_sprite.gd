## ActorSprite —— 像素角色精灵播放器
##
## 【负责什么】
##   素材包的角色表是"4 列（朝向）× 7 行（动作）"的单张贴图，用 Sprite2D 的
##   hframes/vframes + frame_coords 比 AnimatedSprite2D 更省资源也更好配。
##   本组件负责：按朝向选列、按动作选行、按帧率推进动画帧。
##
## 【挂哪个节点】
##   挂在角色场景的 Sprite2D 节点上（不是根节点）。
##   必须在 Inspector 里指定 texture，并把 hframes 设为 4、vframes 设为 7。
##
## 【依赖谁】
##   无。纯表现层，不碰战斗逻辑。
##
## 【怎么扩展】
##   新增动作：在 ANIM_ROWS 常量里加一行"动作名 → 行号数组"即可；
##   想换不同布局（比如 8 方向），把 hframes/vframes 和朝向映射改成 @export 配置。
##
## 【为什么用 frame_coords 而不是 SpriteFrames】
##   整张表只导入一次，运行时只改两个整数；SpriteFrames 要为每个动作建一堆
##   AtlasTexture 子资源，既占内存又难维护。
class_name ActorSprite
extends Sprite2D

# ============================================================================
# 常量
# ============================================================================

## 动作名 → 使用的行号序列。行号来自素材包自身的约定（见 docs/ASSETS.md）。
const ANIM_ROWS: Dictionary = {
	&"idle": [0],
	&"walk": [0, 1, 2, 3],
	&"attack": [4],
	&"roll": [5],
	&"dead": [6],
}
## 朝向 → 列号。素材包约定：下=0、上=1、左=2、右=3。
const DIR_TO_COLUMN: Dictionary = {
	&"down": 0,
	&"up": 1,
	&"left": 2,
	&"right": 3,
}

# ============================================================================
# @export
# ============================================================================

## 动画播放速度（帧/秒）。
@export_range(1.0, 30.0, 0.5) var fps: float = 8.0
## 当前动作名。
##
## 【为什么 setter 里没有"值相同就提前返回"的短路】
##   曾经写的是 `if animation == value: return`，本意是省一次 _apply_frame，
##   但它把 **restart 语义**一起吞掉了：
##     play_anim(&"attack", true) 先把 animation 设成同样的值 → setter 直接 return
##     → `_frame_index = 0.0` 根本没执行 → 连打同一段攻击时只有第一下播动画，
##     后面几下都停在上一段的最后一帧。restart 的判定必须发生在"相等判断"之前。
@export var animation: StringName = &"idle":
	set(value):
		animation = value
		_frame_index = 0.0
		_apply_frame()
## 当前朝向名（down/up/left/right）。
@export var direction: StringName = &"down":
	set(value):
		direction = value
		_apply_frame()
## 是否正在播放（false 时冻结在当前帧）。
@export var playing: bool = true
## 朝向优先用"横向还是纵向"判定：俯视 3/4 视角下，斜向移动时横纵都有分量，
## 这个阈值决定斜着走时显示侧面还是背面/正面。0.5 表示横纵分量相等时取纵向。
@export_range(0.0, 1.0, 0.05) var vertical_bias: float = 0.5

# ============================================================================
# 私有变量
# ============================================================================

## 当前动画帧的浮点索引，用于按 delta 推进。
var _frame_index: float = 0.0

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	# 兜底：如果 .tscn 里没设好分帧，这里按素材包约定补上，避免显示成整张图。
	if hframes != 4:
		hframes = 4
	if vframes != 7:
		vframes = 7
	_apply_frame()


func _process(delta: float) -> void:
	if not playing:
		return
	var rows: Array = ANIM_ROWS.get(animation, [0])
	# 单帧动作（idle/attack/dead）不需要推进。
	if rows.size() <= 1:
		return
	_frame_index = fmod(_frame_index + fps * delta, float(rows.size()))
	_apply_frame()


# ============================================================================
# 公开方法
# ============================================================================

## 播放某个动作。重复调用同一动作不会重置帧（避免走路时脚一直抖）；
## 需要连击第二段重播同名动画时传 restart = true 强制从头播。
func play_anim(anim_name: StringName, restart: bool = false) -> void:
	if animation == anim_name and not restart:
		return
	# 注意：restart 的分支必须显式归零帧，不能再依赖 animation 的 setter 帮我们做。
	# setter 里没有短路（见其说明），但同样的值赋给它时 _frame_index 会被归零——
	# 这是有意的：只要走到这里，就代表"要来一次播放"。
	animation = anim_name
	if restart:
		_frame_index = 0.0
		_apply_frame()


## 根据移动方向设置朝向。零向量时保持原朝向。
func face_direction(move_dir: Vector2) -> void:
	if move_dir.length_squared() < 0.0001:
		return
	# 斜向移动时用分量大小决定朝向：横向分量占优就看侧面，否则看正面/背面。
	if absf(move_dir.x) >= absf(move_dir.y) * (1.0 / maxf(vertical_bias, 0.01)):
		direction = &"right" if move_dir.x > 0.0 else &"left"
	else:
		direction = &"down" if move_dir.y > 0.0 else &"up"


## 根据方向向量直接设置朝向（不经过阈值判断），用于攻击时锁定朝向。
func set_facing(dir_name: StringName) -> void:
	if DIR_TO_COLUMN.has(dir_name):
		direction = dir_name


# ============================================================================
# 私有方法
# ============================================================================

## 把 (朝向, 当前帧) 映射到贴图上的具体格子。
func _apply_frame() -> void:
	var rows: Array = ANIM_ROWS.get(animation, [0])
	var row: int = rows[clampi(int(_frame_index), 0, rows.size() - 1)]
	var col: int = DIR_TO_COLUMN.get(direction, 0)
	frame_coords = Vector2i(col, row)
