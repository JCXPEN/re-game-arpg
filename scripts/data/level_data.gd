## LevelData —— 关卡/房间定义
##
## 【负责什么】
##   描述一个可切换的场景：它属于哪个区域、从哪里进入、有哪些出入口、是否是
##   Boss 房、BGM 是什么。SceneDirector 用它来做场景切换与回城。
##
## 【挂哪个节点】
##   不是节点。保存在 res://data/levels/*.tres。
##
## 【依赖谁】
##   GameEnums。
##
## 【怎么扩展】
##   新增关卡时新建 .tres，并在 SceneDirector 的关卡表里登记；不要改代码逻辑。
class_name LevelData
extends Resource

# ---------------------------------------------------------------- 身份 ----
## 关卡唯一 id，SceneDirector 用它查找。
@export var id: StringName = &""
@export var display_name: String = "未命名区域"
## 实际场景文件。
@export var scene: PackedScene
## 区域类型，用于 UI 显示与小地图配色。
@export_enum("Town", "Field", "Dungeon", "Boss") var area_type: String = "Field"

# ---------------------------------------------------------------- 连接 ----
## 本关卡的出入口：Dictionary 形式 { entry_point_id: StringName, target_level: StringName,
## target_entry: StringName, locked_until_cleared: bool }。
@export var exits: Array[Dictionary] = []
## 玩家进入本关卡的默认出生点名（从别的关卡传过来的 entry_point 会覆盖它）。
@export var default_entry: StringName = &"start"

# ---------------------------------------------------------------- 内容 ----
## 本关卡需要清掉的房间 id 列表（全清后解锁关底门）。
@export var room_ids: Array[StringName] = []
## 是否是 Boss 房。
@export var is_boss_room: bool = false
## 本关的 Boss id（is_boss_room 时使用）。
@export var boss_id: StringName = &""

# ---------------------------------------------------------------- 表现 ----
## 背景音乐。
@export var bgm: AudioStream
## 环境色调（用 CanvasModulate 叠加）。
@export var ambient_color: Color = Color.WHITE
## 摄像机边界（像素）。Vector4 的 xy 为左上角、zw 为右下角。
@export var camera_bounds: Rect2 = Rect2(0, 0, 640, 360)
