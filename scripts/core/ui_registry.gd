## UIRegistry —— UI 窗口注册表 + 场景树容器（Autoload 单例）
##
## 【负责什么】
##   1. 持有 `World` / `GUI` / `Menus` 三个**容器节点**，让场景树按"关系"组织，
##      而不是所有节点平铺在 root 下。
##   2. 用 **id → 窗口** 的显式登记，替代全项目 `get_node_or_null(NodePath("SettingsPanel"))`
##      这类字符串查名。调用方按 id 请求，不关心窗口挂在哪一层。
##
## 【为什么需要它 —— 对照官方文档】
##   Godot 官方《Scene organization》："The key to scene organization is to consider the
##   SceneTree in **relational terms rather than spatial terms**." 以及入口结构应是
##   `Main → World / GUI`，换关卡时"swap out the children of the World node."
##   本注册表就是把这条落地：World 归属关卡，GUI/Menus 归属界面，且界面通过"名字"被访问。
##
## 【为什么窗口不直接挂 root】root 下平铺 20+ 节点时，"谁属于世界、谁属于界面"只能靠
##   命名猜测；一个容器层让归属显式，也让 `GameFlow` 能整层收拾（例如收起所有菜单窗口）。
##
## 【和 UIInputRouter / PopupManager 的分工】
##   · UIRegistry —— **有哪些窗口、怎么按 id 拿到**（本文件）。
##   · UIInputRouter —— Esc 该交给哪个窗口（仲裁）。
##   · PopupManager  —— 哪个窗口能同时占屏（互斥/排队）。
##   三者互补，都不互相取代。
##
## 【为什么不做成 class_name】注册为 autoload `UIRegistry`，同名 class_name 会冲突。
extends Node

# ============================================================================
# 私有变量
# ============================================================================

## id(StringName) → 窗口节点。
var _windows: Dictionary = {}
## 场景树容器。由 Boot 在装配时建立并 `attach_containers()` 注册到这里。
var world: Node2D
var gui: Node
var menus: Node

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


# ============================================================================
# 公开方法 —— 容器
# ============================================================================

## 注册三个容器节点（由 Boot 建立后调用）。
func attach_containers(world_node: Node2D, gui_node: Node, menus_node: Node) -> void:
	world = world_node
	gui = gui_node
	menus = menus_node


## 关卡实例应挂到哪个容器（没有 World 时退回 root，保证健壮）。
func level_parent() -> Node:
	if world != null and is_instance_valid(world):
		return world
	return get_tree().root


## 某个局内 HUD 窗口应挂到哪个容器。
func gui_container() -> Node:
	if gui != null and is_instance_valid(gui):
		return gui
	return get_tree().root


## 某个菜单窗口应挂到哪个容器。
func menus_container() -> Node:
	if menus != null and is_instance_valid(menus):
		return menus
	return get_tree().root


# ============================================================================
# 公开方法 —— 窗口登记 / 查询
# ============================================================================

## 登记一个窗口。同 id 覆盖（晚登记者生效）。
func register(id: StringName, window: Node) -> void:
	if id == &"" or window == null:
		return
	_windows[id] = window


## 注销一个窗口（窗口被释放时调用；不注销也没关系，查询会校验有效性）。
func unregister(id: StringName) -> void:
	_windows.erase(id)


## 按 id 取窗口。节点已被释放时返回 null 并顺手清掉登记。
func window_for(id: StringName) -> Node:
	if not _windows.has(id):
		return null
	var node: Variant = _windows.get(id)
	# 注意：已 free() 的对象读出来可能是 null，也可能是一个"已释放引用"。
	# 两种情况都必须清掉登记，否则会留下"查得到却用不了"的脏条目。
	if node == null or not is_instance_valid(node):
		_windows.erase(id)
		return null
	return node as Node


## 是否登记了某个 id（且节点有效）。
func has(id: StringName) -> bool:
	return window_for(id) != null


## 兼容"按节点名查"的旧用法：优先按 id 命中登记表；否则在 root 下递归按名找。
##
## 【为什么要这条兜底】部分测试/工具用节点名（如 "MainMenu"）访问窗口，
##   而 id 与节点名在本项目里是一致的。递归查找保证即使某窗口没登记也能找到，
##   迁移期不会因为漏登记而互相踩。
func find_by_name(node_name: String) -> Node:
	var by_id: Node = window_for(StringName(node_name))
	if by_id != null:
		return by_id
	var root: Node = get_tree().root if get_tree() != null else null
	if root == null:
		return null
	return root.find_child(node_name, true, false)


## 当前登记的全部 id（调试 / 测试）。
func registered_ids() -> Array:
	return _windows.keys()


## 某 id 所在容器（没有登记时返回 null）。
func container_of(id: StringName) -> Node:
	var node: Node = window_for(id)
	return node.get_parent() if node != null else null
