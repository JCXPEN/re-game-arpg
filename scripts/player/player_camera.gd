## PlayerCamera —— 俯视 2D 跟随摄像机
##
## 【负责什么】
##   平滑跟随 + 速度前瞻 + 死区 + 边界钳制 + 屏幕震动。全部参数 @export，
##   美术/策划可以直接在 Inspector 里调手感，不需要改代码。
##
## 【挂哪个节点】
##   作为 Camera2D 挂在玩家场景里（或关卡里单独一个摄像机节点）。
##   若挂在玩家下，跟随会自然跟随；本脚本仍支持"独立摄像机 + set_target"模式。
##
## 【依赖谁】
##   EventBus.camera_shake_requested。
##
## 【怎么扩展】
##   想加"进 Boss 房时锁定镜头"，调用 set_bounds() 换边界即可；
##   想加"受击拉近"，加一个 zoom 偏移通道，别动位置计算。
##
## 【为什么不用 Camera2D 自带的 position_smoothing】
##   自带的平滑不区分死区与前瞻，且震动会和平滑互相打架。手写一层更可控：
##   目标点 = 玩家位置 + 前瞻偏移，先钳制边界，再做死区判断，最后平滑。
class_name PlayerCamera
extends Camera2D

# ============================================================================
# @export
# ============================================================================

## 跟随目标。留空则用父节点。
@export var target_path: NodePath
## 跟随平滑速度（越大越紧跟，0 表示硬跟随）。
@export_range(0.0, 30.0, 0.1) var follow_speed: float = 8.0
## 速度前瞻：按玩家速度提前偏移镜头，让玩家看得见前方。
@export_range(0.0, 2.0, 0.05) var look_ahead_factor: float = 0.35
## 前瞻最大偏移（像素），防止高速移动时镜头甩太远。
@export_range(0.0, 200.0, 1.0) var look_ahead_max: float = 24.0
## 前瞻平滑速度。
@export_range(0.1, 30.0, 0.1) var look_ahead_speed: float = 3.0
## 死区半径（像素）。目标在死区内移动时镜头不动，避免镜头抖。
@export_range(0.0, 200.0, 1.0) var deadzone_radius: float = 10.0
## 摄像机边界。xy 为左上角，zw 为右下角。宽或高为 0 时表示该轴不限制。
@export var bounds: Rect2 = Rect2(0, 0, 0, 0)
## 是否启用边界钳制。
@export var clamp_to_bounds: bool = true
## 震动衰减速度。
@export_range(1.0, 60.0, 1.0) var shake_decay: float = 22.0
## 震动频率（每秒抖动次数）。
@export_range(1.0, 120.0, 1.0) var shake_frequency: float = 42.0

# ============================================================================
# 私有变量
# ============================================================================

## 跟随目标引用。
var _target: Node2D
## 当前平滑后的镜头位置（不含震动）。
var _smoothed_position: Vector2 = Vector2.ZERO
## 当前前瞻偏移。
var _look_ahead: Vector2 = Vector2.ZERO
## 上一帧目标位置，用于算速度。
var _last_target_position: Vector2 = Vector2.ZERO
## 当前震动强度。
var _shake_amplitude: float = 0.0
## 震动剩余时间。
var _shake_time: float = 0.0
## 震动相位累加器（用正弦而不是纯随机，抖动更"有节奏"）。
var _shake_phase: float = 0.0
## 是否已初始化位置（首帧直接吸附，避免从 (0,0) 滑过来）。
var _initialized: bool = false

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	# 强制在物理帧之后更新，保证跟随的是移动后的位置，不会抖。
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	if not target_path.is_empty():
		_target = get_node_or_null(target_path) as Node2D
	if _target == null:
		_target = get_parent() as Node2D
	if _target != null:
		_smoothed_position = _target.global_position
		_last_target_position = _target.global_position
		global_position = _smoothed_position
		_initialized = true
	EventBus.camera_shake_requested.connect(shake)


func _physics_process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	_update_follow(delta)
	_update_shake(delta)


# ============================================================================
# 公开方法
# ============================================================================

## 设置跟随目标。
func set_target(node: Node2D) -> void:
	_target = node
	if node != null:
		# 首帧必须立刻钳制：玩家出生点常在地图角落（如城镇 (48,48)），
		# 若直接吸附到玩家坐标，摄像机视野会有一半在地图外 → 画面出现黑边，
		# 要等它慢慢 lerp 回边界内才消失。
		var pos: Vector2 = node.global_position
		if clamp_to_bounds:
			pos = _clamp_to_bounds(pos)
		_smoothed_position = pos
		_last_target_position = node.global_position
		global_position = _smoothed_position
		_initialized = true


## 设置边界（进新房间/新关卡时调用）。传 Rect2(0,0,0,0) 表示不限制。
func set_bounds(new_bounds: Rect2) -> void:
	bounds = new_bounds
	# 换边界后立刻把当前位置收进新边界，避免切换瞬间露出黑边。
	if clamp_to_bounds and _initialized:
		_smoothed_position = _clamp_to_bounds(_smoothed_position)
		global_position = _smoothed_position


## 触发屏幕震动。
func shake(amplitude: float, duration: float) -> void:
	if amplitude <= 0.0 or duration <= 0.0:
		return
	# 叠加而不是覆盖：连续命中时震感会累积，但不超过上限。
	_shake_amplitude = maxf(_shake_amplitude, amplitude)
	_shake_time = maxf(_shake_time, duration)


# ============================================================================
# 私有方法
# ============================================================================

## 跟随主逻辑：目标点 → 边界钳制 → 死区 → 平滑 → 前瞻 → 震动。
func _update_follow(delta: float) -> void:
	var target_pos: Vector2 = _target.global_position
	# 速度前瞻：用目标本帧位移估算速度方向。
	var target_velocity: Vector2 = (target_pos - _last_target_position) / maxf(delta, 0.0001)
	_last_target_position = target_pos
	var desired_ahead: Vector2 = target_velocity * look_ahead_factor
	if desired_ahead.length() > look_ahead_max:
		desired_ahead = desired_ahead.normalized() * look_ahead_max
	_look_ahead = _look_ahead.lerp(desired_ahead, clampf(look_ahead_speed * delta, 0.0, 1.0))
	var desired: Vector2 = target_pos + _look_ahead
	# 死区：目标离当前镜头中心不超过半径时，不更新目标点，镜头保持静止。
	if _smoothed_position.distance_to(desired) <= deadzone_radius:
		desired = _smoothed_position
	# 边界钳制：把镜头中心限制在 bounds 内，同时考虑视口半宽半高，
	# 否则会看到地图外的黑边。
	if clamp_to_bounds:
		desired = _clamp_to_bounds(desired)
	# 平滑：follow_speed 为 0 时硬跟随（首帧也走这里，避免滑入）。
	if follow_speed <= 0.0 or not _initialized:
		_smoothed_position = desired
		_initialized = true
	else:
		_smoothed_position = _smoothed_position.lerp(desired, clampf(follow_speed * delta, 0.0, 1.0))


## 把镜头中心钳制到关卡边界内。
func _clamp_to_bounds(pos: Vector2) -> Vector2:
	if bounds.size.x <= 0.0 and bounds.size.y <= 0.0:
		return pos
	# 视口半尺寸决定镜头中心能走多远。
	var half: Vector2 = get_viewport_rect().size * 0.5 / zoom
	var result: Vector2 = pos
	if bounds.size.x > 0.0:
		# 地图比屏幕窄时，直接居中，避免左右抖动。
		if bounds.size.x <= half.x * 2.0:
			result.x = bounds.position.x + bounds.size.x * 0.5
		else:
			result.x = clampf(pos.x, bounds.position.x + half.x, bounds.position.x + bounds.size.x - half.x)
	if bounds.size.y > 0.0:
		if bounds.size.y <= half.y * 2.0:
			result.y = bounds.position.y + bounds.size.y * 0.5
		else:
			result.y = clampf(pos.y, bounds.position.y + half.y, bounds.position.y + bounds.size.y - half.y)
	return result


## 震动：在平滑位置基础上叠加一个正弦抖动，衰减到 0。
func _update_shake(delta: float) -> void:
	if _shake_time > 0.0:
		_shake_time = maxf(0.0, _shake_time - delta)
		_shake_phase += delta * shake_frequency
		# 用两个不同频率的正弦叠加，避免抖动呈现明显的单一方向往复。
		var offset: Vector2 = Vector2(sin(_shake_phase * 1.0), sin(_shake_phase * 1.7)) * _shake_amplitude
		global_position = _smoothed_position + offset
		# 震动结束后归零强度。
		if _shake_time <= 0.0:
			_shake_amplitude = 0.0
			global_position = _smoothed_position
	else:
		global_position = _smoothed_position
	_shake_amplitude = maxf(0.0, _shake_amplitude - shake_decay * delta)
