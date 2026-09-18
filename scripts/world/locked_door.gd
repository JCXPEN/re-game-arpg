## LockedDoor —— 锁门（清怪解锁 / 钥匙解锁）
##
## 【负责什么】
##   阻挡通往下一区域的通道，直到满足条件：
##     - 条件 A：本关所有敌人被清光（level_cleared）
##     - 条件 B：玩家持有指定钥匙（requires_key）
##   条件满足后播放开门动画并允许通行。
##
## 【挂哪个节点】
##   scenes/world/locked_door.tscn 的根节点。
##   含 CollisionShape2D（阻挡）+ Sprite2D（门贴图）+ Area2D（检测玩家）。
##
## 【依赖谁】
##   EventBus（room_cleared）、GameState（钥匙）。
##
## 【怎么扩展】
##   需要"多钥匙/多条件"时扩展 _is_unlocked()，不要改开门流程。
class_name LockedDoor
extends Node2D

# ============================================================================
# 信号
# ============================================================================

## 门被解锁。
signal unlocked()

# ============================================================================
# @export
# ============================================================================

## 是否要求清光本关敌人。
@export var require_clear: bool = true
## 是否要求钥匙。
@export var requires_key: bool = false
## 需要的钥匙物品 id。
@export var key_item_id: StringName = &"dungeon_key"
## 阻挡碰撞体节点路径。
@export var blocker_path: NodePath
## 门精灵节点路径。
@export var sprite_path: NodePath
## 解锁提示文字。
@export var locked_message: String = "门被锁住了，先清空这一层的敌人。"
## 开锁音效。
@export var unlock_sfx: AudioStream

# ============================================================================
# 私有变量
# ============================================================================

## 是否已解锁。
var _is_open: bool = false
## 阻挡碰撞体。
var _blocker: CollisionShape2D
## 门精灵。
var _sprite: Sprite2D

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	if not blocker_path.is_empty():
		_blocker = get_node_or_null(blocker_path) as CollisionShape2D
	if _blocker == null:
		_blocker = get_node_or_null("Blocker") as CollisionShape2D
	if not sprite_path.is_empty():
		_sprite = get_node_or_null(sprite_path) as Sprite2D
	if _sprite == null:
		_sprite = get_node_or_null("Sprite") as Sprite2D
	if unlock_sfx == null:
		unlock_sfx = load("res://assets/audio/sfx/PowerUp1.wav")
	EventBus.room_cleared.connect(_on_room_cleared)
	# 钥匙到手也是解锁条件之一，事件驱动比每帧轮询便宜。
	EventBus.item_acquired.connect(_on_item_acquired)
	EventBus.scene_changed.connect(_on_scene_changed)
	# 【为什么延后一帧】_on_scene_changed 时关卡根节点的 _ready 还没跑完，
	# 此刻 SceneDirector.get_current_scene() / is_cleared() 都还是上一关的状态，
	# 直接判断会把"上一关已清空"误当成"本关已清空"，于是 require_clear 的锁门
	# 在玩家进关的瞬间就自动开了（等于没有门）。
	await get_tree().process_frame
	_refresh_lock_state()
	# 【为什么去掉每帧轮询】旧实现在 _process 里每帧反射调用
	# get_current_scene() + has_method() + call()，永不停歇。
	# 现在改由事件驱动：清场走 room_cleared，钥匙走 item_acquired，
	# 另有关卡切换兜底。三个触发点覆盖全部解锁途径，无需再轮询。


# ============================================================================
# 公开方法
# ============================================================================

## 门是否已开。
func is_open() -> bool:
	return _is_open


# ============================================================================
# 私有方法
# ============================================================================

## 检查解锁条件，满足则开门。
func _refresh_lock_state() -> void:
	if _is_open:
		return
	var clear_ok: bool = true
	if require_clear:
		var level: Node = SceneDirector.get_current_scene()
		clear_ok = level != null and level.has_method("is_cleared") and level.call("is_cleared") as bool
	var key_ok: bool = true
	if requires_key:
		key_ok = GameState.has_item(key_item_id)
	if clear_ok and key_ok:
		_open()


func _open() -> void:
	_is_open = true
	if _blocker != null:
		_blocker.set_deferred("disabled", true)
	if _sprite != null:
		var tween: Tween = create_tween()
		# 开门表现：向上滑出并淡出。
		tween.set_parallel(true)
		tween.tween_property(_sprite, "position:y", _sprite.position.y - 20.0, 0.4)
		tween.tween_property(_sprite, "modulate:a", 0.0, 0.4)
	AudioManager.play_sfx(unlock_sfx)
	EventBus.toast_requested.emit("门开了！")
	unlocked.emit()


# ============================================================================
# 信号回调
# ============================================================================

func _on_room_cleared(_room_id: StringName) -> void:
	_refresh_lock_state()


## 拿到物品 → 可能正是本门要的钥匙。只关心钥匙时直接比对 id。
func _on_item_acquired(item_id: StringName, _count: int) -> void:
	if requires_key and item_id == key_item_id:
		_refresh_lock_state()


## 换关卡 → 条件可能已经满足（例如回到一个已清空的层）。
func _on_scene_changed(_scene: Node) -> void:
	_refresh_lock_state()
