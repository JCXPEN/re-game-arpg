## Transition —— 场景切换遮罩（软边光圈 + 暖色描边）
##
## 【负责什么】
##   在关卡切换时盖一张全屏遮罩，用"光圈收拢 / 绽放"掩盖加载瞬间与场景替换。
##   视觉由 shaders/transition.gdshader 完成，本脚本只负责：时序、参数下发、
##   以及"duration 之后一定返回"的契约。
##
## 【挂哪个节点】
##   scenes/core/transition.tscn 的根节点（CanvasLayer），由 SceneDirector 实例化。
##   遮罩矩形与材质在运行时懒创建（见 _ensure_rect），场景文件保持极简。
##
## 【依赖谁】
##   无。SceneDirector 通过 `has_method("fade_out"/"fade_in")` 鸭子类型调用，
##   所以这个脚本可以整体替换成别的转场（翻页、马赛克…）而不改 SceneDirector。
##
## 【怎么扩展】
##   想换转场图案改 shaders/transition.gdshader；想调色/调边改下面的 @export，
##   全部参数在编辑器里可视化调整，不需要碰 shader 代码。
##
## 【关键设计 1 —— 为什么用计时器而不是 await tween.finished】
##   fade_out / fade_in 是"可被后来的调用取代"的：如果新的动画 kill 掉旧 tween，
##   旧 tween 的 finished 信号永远不会发出，正在 await 它的调用方会**永久挂起**
##   （SceneDirector 的 _changing 标志就再也回不到 false，之后所有场景切换都被丢弃）。
##   所以这里用"动画 + 独立计时器"两条腿：动画只管视觉，计时器负责兑现
##   "duration 之后一定返回"的契约。
##
## 【关键设计 2 —— 为什么 tween 也 ignore_time_scale】
##   契约计时器一直带 ignore_time_scale=true，但旧版视觉 tween 没有：
##   命中顿帧（Engine.time_scale ≈ 0.05）时，计时器按时到点、tween 才走了 5%，
##   遮罩会被"瞬间钉"到终值 —— 表现为转场突然一闪。现在两者同轨（都忽略时间缩放），
##   视觉与契约永远一致。
##
## 【关键设计 3 —— 静止时零开销】
##   progress = 0 时把矩形 visible 置 false：不产生 draw call、不占填充率。
##   只有在转场的几百毫秒里它才真正参与渲染。
extends CanvasLayer

# ============================================================================
# 常量
# ============================================================================

## 全屏遮罩的 shader。加载失败时自动退回"纯色 alpha 淡变"（见 _ensure_rect）。
const MASK_SHADER: Shader = preload("res://shaders/transition.gdshader")

# ============================================================================
# @export
# ============================================================================

## 幕布颜色。默认取主题的 C_VOID（#0B0A10），比纯黑更贴合项目的冷深紫基调。
@export var color: Color = Color("#0B0A10")
## 光圈边缘的暖金强调色（主题 C_ACCENT_HI）。设为全透明可关掉描边。
@export var rim_color: Color = Color("#FFD980")
## 转场层高度，确保盖住所有 HUD。
@export_range(0, 128, 1) var layer_index: int = 100
## 边缘柔和度（归一化单位，1.0 = 屏幕短边长度）。越小边越硬朗。
@export_range(0.01, 0.4, 0.005) var edge_softness: float = 0.085
## 描边宽度（归一化单位）。
@export_range(0.01, 0.3, 0.005) var rim_width: float = 0.032
## 描边强度。0 = 无描边，只有光圈。
@export_range(0.0, 2.0, 0.05) var rim_strength: float = 0.55
## 描边外侧的扩散光晕强度。调大会糊成一团雾，建议 ≤ 0.3。
@export_range(0.0, 1.0, 0.05) var halo_strength: float = 0.22
## 边缘像素抖动幅度（只在光圈边缘附近生效）。0 = 完美圆形，越大越"手绘"。
@export_range(0.0, 0.1, 0.001) var grain: float = 0.008
## 幕布暗角强度。
@export_range(0.0, 1.0, 0.05) var vignette: float = 0.35
## 光圈中心漂移量：收拢时视线前移、展开时回正，给转场一个方向感。
@export_range(0.0, 0.3, 0.01) var drift: float = 0.06
## 是否使用 shader 遮罩。关掉则退回旧的"纯色 alpha 淡入淡出"。
@export var use_shader: bool = true

# ============================================================================
# 私有变量
# ============================================================================

## 全屏遮罩矩形。
var _rect: ColorRect
## 遮罩材质。为 null 时表示走"纯色 alpha"兜底路径。
var _mat: ShaderMaterial
## 当前补间，重复调用时先杀掉旧的。
var _tween: Tween
## 动画代次。每次新动画 +1，旧的计时器醒来后发现自己过期就直接返回。
var _sequence: int = 0
## 当前进度缓存。新动画从这里起步，避免"接不上旧动画"造成跳变。
var _progress: float = 0.0

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	layer = layer_index
	_ensure_rect()


# ============================================================================
# 公开方法
# ============================================================================

## 收拢光圈，直到画面被完全盖住。await 结束后可以安全换场景。
func fade_out(duration: float) -> void:
	await _animate(1.0, duration)


## 从全盖状态绽放回画面。
func fade_in(duration: float) -> void:
	await _animate(0.0, duration)


# ============================================================================
# 私有方法 —— 构建
# ============================================================================

## 懒创建遮罩矩形与材质。
## 为什么不能只在 _ready 里建：本节点由 SceneDirector 用 call_deferred 挂载，
## 调用方可能在 _ready 之前就触发淡出（boot 阶段就是这种情况），
## 所以每次动画前都确保 _rect 存在。
func _ensure_rect() -> void:
	if _rect != null and is_instance_valid(_rect):
		return
	_rect = ColorRect.new()
	_rect.name = "Mask"
	if _make_material():
		# shader 路径下 COLOR 由 shader 全权输出，这里必须是白色：
		# ColorRect 的 color 会作为顶点色参与调制，留着黑+alpha 0 会把遮罩乘成透明。
		_rect.color = Color.WHITE
	else:
		_rect.color = Color(color.r, color.g, color.b, 0.0)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 遮罩本身不接收鼠标事件，否则会挡住 UI 点击。
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 尺寸变化（窗口缩放 / 分辨率切换）时同步给 shader，保证光圈始终是正圆。
	_rect.resized.connect(_sync_shader_size)
	_rect.visible = false
	add_child(_rect)
	_sync_shader_size()
	_push_params()


## 构建 shader 材质。失败时返回 false，调用方走纯色兜底路径。
func _make_material() -> bool:
	if not use_shader or MASK_SHADER == null:
		return false
	_mat = ShaderMaterial.new()
	_mat.shader = MASK_SHADER
	_rect.material = _mat
	return true


## 把 @export 的参数下发给 shader。改参数后无需重建材质。
func _push_params() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("fill_color", color)
	_mat.set_shader_parameter("rim_color", rim_color)
	_mat.set_shader_parameter("edge_softness", edge_softness)
	_mat.set_shader_parameter("rim_width", rim_width)
	_mat.set_shader_parameter("rim_strength", rim_strength)
	_mat.set_shader_parameter("halo_strength", halo_strength)
	_mat.set_shader_parameter("grain", grain)
	_mat.set_shader_parameter("vignette", vignette)
	_mat.set_shader_parameter("drift", drift)
	_mat.set_shader_parameter("progress", _progress)


## 把遮罩的实际像素尺寸告诉 shader（光圈正圆化的依据）。
func _sync_shader_size() -> void:
	if _mat == null or _rect == null:
		return
	var size: Vector2 = _rect.size
	# 还没完成布局时退到视口尺寸，避免用 0 尺寸算出一片空白。
	if (size.x <= 0.0 or size.y <= 0.0) and is_inside_tree():
		size = get_viewport().get_visible_rect().size
	_mat.set_shader_parameter("rect_size", size)


# ============================================================================
# 私有方法 —— 动画
# ============================================================================

## 把遮罩视觉推到 target（1 = 全盖，0 = 全透），并保证 duration 后一定返回。
func _animate(target_alpha: float, duration: float) -> void:
	var clamped: float = maxf(duration, 0.01)
	_sequence += 1
	var my_sequence: int = _sequence
	_ensure_rect()
	_sync_shader_size()
	# 还没入树时（SceneDirector 用 call_deferred 挂载的第一帧）拿不到 SceneTree，
	# 计时器建不了。直接落到终值即可——反正此时也没东西需要被遮住。
	if not is_inside_tree():
		_apply(target_alpha)
		return
	# 视觉动画：旧的直接杀掉，只保留最新一次。
	if _tween != null and _tween.is_valid():
		_tween.kill()
	# 从**当前进度**起步继续补间：连点两次转场时会从半途接上，而不是闪回 0。
	_tween = create_tween()
	# EASE_OUT = 先快后缓：转场"立刻有反应、结尾稳稳停住"。
	# 【为什么是 QUAD 而不是 CUBIC】fade_time 只有 0.18s（约 11 帧），
	#   CUBIC 的头部太急，第一帧就吃掉大半行程，看起来是"啪"地一下；
	#   QUAD 保留响应感，同时把行程摊平到每一帧，读出连续收拢的动势。
	_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 与下面的契约计时器同轨：命中顿帧时不减速，避免结尾被"钉"到终值。
	_tween.set_ignore_time_scale(true)
	_tween.tween_method(_apply, _progress, target_alpha, clamped)
	# 契约计时器：即使补间被后来的调用取代/杀掉，这里也会按时返回。
	# 第 4 个参数 ignore_time_scale = true，避免顿帧（time_scale≈0）时转场卡住。
	await get_tree().create_timer(clamped, true, false, true).timeout
	# 如果这期间已经有更新的动画接手，本次就不负责收尾。
	if my_sequence != _sequence:
		return
	# 保险起见，把最终值直接写死，避免补间因浮点误差没落到位。
	_apply(target_alpha)


## 把进度写进材质（或兜底色），并处理"静止时不可见"。
func _apply(value: float) -> void:
	_progress = clampf(value, 0.0, 1.0)
	if _mat != null:
		_mat.set_shader_parameter("progress", _progress)
	else:
		_rect.color.a = _progress
	# progress 归零后彻底退出渲染：不产生 draw call，静止期零开销。
	_rect.visible = _progress > 0.0005
