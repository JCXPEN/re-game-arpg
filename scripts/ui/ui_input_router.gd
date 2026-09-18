## UIInputRouter —— 全局 UI 输入的**唯一仲裁者**（Autoload 单例）
##
## 【负责什么】
##   把"Esc / 统一关闭键该归谁"从"九个节点各自 _unhandled_input 抢事件"
##   收敛成**一次集中仲裁**：按层级挑出唯一应该处理本次输入的窗口，
##   只调用它一个，其余窗口收不到。
##
## 【为什么需要它 —— 这是真实的缺陷，不是洁癖】
##   Godot 的 _unhandled_input 是**广播**语义：事件按场景树逆序逐个投递给所有
##   实现者，除非有人 set_input_as_handled()。原来的实现里 PauseMenu 是
##   boot.PERSISTENT_UI 里**最后**挂载的常驻层，于是它**最先**收到 Esc：
##     · 教程窗口正显示（paused=true）时按 Esc
##     → PauseMenu 抢先把事件吃掉并 toggle() 打开暂停菜单
##     → TutorialUI 永远收不到 Esc，教程关不掉
##     → 屏幕上同时挂着教程 + 暂停菜单，两个窗口都以为自己拥有屏幕
##   实证见 tools/esc_diag4.tscn 的投递顺序打印。
##
## 【仲裁规则（层级从高到低）】
##   1. 已在屏幕上、且**阻塞型**的窗口（教程 > 三选一 > 暂停 > 帮助 > 设置
##      > 背包 > 死亡界面）—— Esc 先给最上面那一个，交给它自己决定"关闭"。
##   2. 没有阻塞窗口时，Esc 才是"打开暂停菜单"。
##
## 【为什么"阻塞型"要单独标出来】
##   提示条（toast）是非阻塞的，它不该抢 Esc；三选一虽然阻塞但用数字键选，
##   也不该被 Esc 关掉（那是要奖励的）。这些语义留在各窗口自己的
##   `handles_esc()` / `route_esc()` 里，路由器只负责**排序与单选**。
##
## 【怎么扩展】
##   新增一个会挡玩家的窗口：实现 `ui_layer_priority() -> int`、
##   `is_blocking_ui() -> bool`、`route_esc() -> bool` 三个方法，
##   然后在 _ready 里 `add_to_group(&"ui_router_target")`。路由器会自动发现它。
##
## 【为什么不用 class_name】
##   注册为 autoload `UIInputRouter`，同名 class_name 会报
##   "hides an autoload singleton"（同 PopupManager / TutorialSystem）。
extends Node

# ============================================================================
# 常量
# ============================================================================

## 会被路由器纳入候选的节点分组名。
const GROUP: StringName = &"ui_router_target"

## 层级：数字大的优先拿到 Esc。留足间隔以便将来插入。
const LAYER_VICTORY: int = 95
const LAYER_GAME_OVER: int = 90
const LAYER_TUTORIAL: int = 80
const LAYER_MODIFIER_CHOICE: int = 70
const LAYER_PAUSE_MENU: int = 60
const LAYER_SETTINGS: int = 55
const LAYER_HELP: int = 50
const LAYER_INVENTORY: int = 40

# ============================================================================
# 私有变量
# ============================================================================

## 是否接管 Esc 的全局分发。关掉后各窗口退回自己处理（测试对照用）。
var _enabled: bool = true
## 打开暂停菜单的回调（由 PauseMenu 注册；路由器不直接持有它）。
var _pause_opener: Callable = Callable()

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	# 本 router 必须在暂停中也能收输入，否则暂停后 Esc 就没反应了。
	process_mode = Node.PROCESS_MODE_ALWAYS


## 【为什么收发在 _unhandled_input，但又"抢"在其他窗口前面】
##   Esc 走 _unhandled_input 是必须的 —— 只有到这一层才确定"GUI 控件没消费它"，
##   否则玩家在按钮上敲 Esc 会被我们提前截胡。
##   Godot 的 _unhandled_input 按场景树**逆序**广播，本 router 是 autoload，
##   在 root 的子节点里**排在所有 UI 之前**（autoload 最先添加）→ 逆序时它
##   **最后**收到。这正好是我们想要的：普通窗口先有自己的机会，
##   到 router 这里再统一裁决"谁该管 Esc"。
##   （issue 里的老实现是 PauseMenu 最先收到，所以才抢跑。）
func _unhandled_input(event: InputEvent) -> void:
	if handle_cancel(event):
		get_viewport().set_input_as_handled()


# ============================================================================
# 公开方法 —— 注册
# ============================================================================

## 注册"Esc 打开暂停菜单"的实现方（PauseMenu 在 _ready 里调）。
func set_pause_opener(cb: Callable) -> void:
	_pause_opener = cb


## 开关接管（测试用）。
func set_routing_enabled(value: bool) -> void:
	_enabled = value


# ============================================================================
# 公开方法 —— 输入入口
# ============================================================================

## 统一处理"取消/暂停"类输入。返回 true 表示本次输入已被消费。
##
## 各窗口**不再**自己监听 Esc：只要在 _unhandled_input 里把事件转给这里，
## 或者干脆不实现 _unhandled_input（本 router 通过 group 主动分发）。
func handle_cancel(event: InputEvent) -> bool:
	if not _enabled:
		return false
	if not _is_cancel_event(event):
		return false
	# 1) 找最上层的阻塞窗口，让它自己处理。
	var target: Node = _top_blocking_target()
	if target != null:
		var handled: bool = _try_route_esc(target)
		# 不管它认不认（有些窗口 Esc 不关，例如三选一），
		# 只要它是当前最上层窗口，就不该让 Esc 穿透下去开暂停菜单。
		return handled
	# 2) 没有阻塞窗口 → Esc 打开暂停菜单。
	if _pause_opener.is_valid():
		_pause_opener.call()
		return true
	return false


# ============================================================================
# 私有方法 —— 判定
# ============================================================================

## 是否为"取消/暂停"输入：物理键 Esc，或 action pause / ui_cancel。
##
## 【为什么同时认物理键与 action】项目里 Esc 绑在 `pause`；但玩家可能改键，
##   也可能用手柄（pause 也绑了手柄 back）。物理键 + action 双认才稳。
func _is_cancel_event(event: InputEvent) -> bool:
	if not event.is_pressed() or event.is_echo():
		return false
	if event is InputEventKey:
		var k: InputEventKey = event as InputEventKey
		if k.keycode == KEY_ESCAPE or k.physical_keycode == KEY_ESCAPE:
			return true
	return event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel")


## 找出"当前是否真的有阻塞窗口在屏幕上"。
func has_blocking_ui() -> bool:
	return _top_blocking_target() != null


## 挑出最上层的阻塞窗口。
##
## 【排序口径】先比层级，层级相同比**加入场景树的顺序**（后加的在上）。
##   这样同一管理层级内的相对顺序也稳定，不依赖 group 遍历顺序（那是不保证的）。
func _top_blocking_target() -> Node:
	var best: Node = null
	var best_layer: int = -2147483648
	var best_order: int = -1
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		if not is_instance_valid(node):
			continue
		if not _is_blocking(node) or not _is_on_screen(node):
			continue
		var layer: int = _layer_of(node)
		var order: int = _tree_order(node)
		if layer > best_layer or (layer == best_layer and order > best_order):
			best = node
			best_layer = layer
			best_order = order
	return best


func _is_blocking(node: Node) -> bool:
	if node.has_method(&"is_blocking_ui"):
		return bool(node.call(&"is_blocking_ui"))
	return false


func _is_on_screen(node: Node) -> bool:
	if node is CanvasItem:
		var ci: CanvasItem = node as CanvasItem
		return ci.visible and ci.is_visible_in_tree()
	# 非 CanvasItem（理论上不会走到，group 里只放 UI）
	return true


func _layer_of(node: Node) -> int:
	if node.has_method(&"ui_layer_priority"):
		return int(node.call(&"ui_layer_priority"))
	return 0


## 节点在场景树里的"加入顺序"。用 get_index() 只能比同父兄弟，
## 这里用 root 的递归序号，跨父节点也可比。
func _tree_order(node: Node) -> int:
	var order: int = 0
	var cursor: Node = node
	while cursor != null and cursor != get_tree().root:
		order += cursor.get_index() + 1
		cursor = cursor.get_parent()
	return order


func _try_route_esc(target: Node) -> bool:
	if target.has_method(&"route_esc"):
		return bool(target.call(&"route_esc"))
	return false


# ============================================================================
# 便捷查询
# ============================================================================

## 当前最上层阻塞窗口的 id（调试 / 测试用）。
func top_blocking_id() -> StringName:
	var t: Node = _top_blocking_target()
	if t == null:
		return &""
	if t.has_method(&"ui_window_id"):
		return StringName(t.call(&"ui_window_id"))
	return StringName(t.name)
