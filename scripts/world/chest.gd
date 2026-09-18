## Chest —— 宝箱
##
## 【负责什么】
##   打开后掉落物品/金币，播放开箱动画。一次性交互。
##
## 【挂哪个节点】
##   scenes/world/chest.tscn 的根节点（继承 Interactable）。
##   @export 配置掉落表，不写死奖励内容。
##
## 【依赖谁】
##   ItemData（DataRegistry 查询）、GameState（加金币）。
class_name Chest
extends Interactable

# ============================================================================
# @export
# ============================================================================

## 必定掉落的物品 id 列表。
@export var guaranteed_items: Array[StringName] = []
## 金币数量范围（随机）。
@export var gold_min: int = 5
@export var gold_max: int = 15
## 开箱后的贴图（可空）。留空则改用 sprite 的 frame 切换。
@export var opened_texture: Texture2D
## 开箱后设置的帧号（贴图是"关+开"两帧的图集时用这个，比换整张贴图省资源）。
@export var opened_frame: int = 1
## 开箱音效。
@export var open_sfx: AudioStream
## 宝箱唯一 id。必须在本关卡内唯一（建议用 "chest_01" 这种）。
##
## 【为什么必须有】旧实现只靠实例内的 `_used`（由 one_shot 维护）记录"开过了"，
##   这是个纯内存标记：死亡重进、切场景回来、读档之后全部归零，
##   于是同一个箱子可以无限重复领取金币与物品。
##   留空时退回"关卡 id + 节点路径"自动生成，仍能保证跨局唯一，只是改名会失效。
@export var chest_id: StringName = &""

# ============================================================================
# 生命周期
# ============================================================================

## 本宝箱在存档里的唯一键：`关卡id/宝箱id`。
var _chest_key: StringName = &""


func _ready() -> void:
	super._ready()
	one_shot = true
	prompt_text = "打开宝箱"
	if open_sfx == null:
		open_sfx = load("res://assets/audio/sfx/Gold1.wav")
	_chest_key = _build_chest_key()
	# 存档里已经开过 → 直接呈现"已开"的样子，不再给奖励。
	if GameState.is_chest_opened(_chest_key):
		_apply_opened_visual()


## 组装持久化键。显式 chest_id 优先，否则用"关卡id + 节点路径"兜底。
func _build_chest_key() -> StringName:
	var level: LevelData = SceneDirector.get_current_level()
	var level_part: String = String(level.id) if level != null else String(name)
	var chest_part: String = String(chest_id) if chest_id != &"" else str(get_path())
	return StringName("%s/%s" % [level_part, chest_part])


# ============================================================================
# 私有方法
# ============================================================================

func _on_interact(_actor: Node) -> void:
	# 双保险：one_shot 已挡住重复交互，但存档状态才是跨场景的那道门。
	if GameState.is_chest_opened(_chest_key):
		return
	# 先落盘再发奖励：即使奖励发放途中出意外（切场景 / 崩溃），
	# 也不会出现"钱到手了但标记没写"的重复领取窗口。
	GameState.mark_chest_opened(_chest_key)
	# 金币。
	var gold: int = randi_range(gold_min, gold_max)
	if gold > 0:
		GameState.add_gold(gold)
		EventBus.floating_text_requested.emit("+%d 金币" % gold, global_position + Vector2(0, -14), Color(1, 0.85, 0.3))
	# 固定物品。
	for item_id: StringName in guaranteed_items:
		var item: ItemData = DataRegistry.get_item(item_id)
		if item == null:
			continue
		GameState.add_item(item_id, 1)
		EventBus.floating_text_requested.emit(item.display_name, global_position + Vector2(0, -22), Color(0.7, 1.0, 0.7))
	_apply_opened_visual()
	EventBus.toast_requested.emit("获得宝物！")


## 换成"已开"的表现：贴图 + 弹跳。
func _apply_opened_visual() -> void:
	var sprite: Sprite2D = get_node_or_null("Sprite") as Sprite2D
	if sprite == null:
		return
	if opened_texture != null:
		sprite.texture = opened_texture
	elif sprite.hframes > 1:
		sprite.frame = clampi(opened_frame, 0, sprite.hframes - 1)
	var tween: Tween = create_tween()
	tween.tween_property(sprite, "scale", Vector2(1.25, 0.8), 0.08)
	tween.tween_property(sprite, "scale", Vector2.ONE, 0.12)
