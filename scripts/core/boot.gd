## Boot —— 启动入口 / 常驻服务装配（= 官方意义上的 "Main" 控制器）
##
## 【负责什么】
##   项目主场景，扮演官方《Scene organization》推荐的 **Main 控制器**角色：
##     1. 建立场景树容器 `World` / `GUI` / `Menus`（按"关系"组织，而非平铺在 root）。
##     2. 把跨关卡常驻 UI 挂进 GUI / Menus 容器并登记进 UIRegistry。
##     3. 决定启动后进入哪个局面（交给 GameFlow）。
##
## 【目标场景树】
##   root
##   ├── (autoloads)  EventBus / UIRegistry / PauseManager / GameFlow / ...
##   └── Boot  ← run/main_scene，get_tree().current_scene
##       ├── World (Node2D)     ← 只挂当前关卡实例（换关只动这一个子节点）
##       ├── GUI (CanvasLayer)  ← 局内 HUD：HUD / BossHealthBar
##       └── Menus (CanvasLayer)← 菜单层：TutorialUI / DialogUI / 三选一 / 背包 / 结算 / 暂停
##
## 【为什么容器挂在 Boot 下而不是 root 下】
##   官方要求 GUI 要能跨场景存活，最简单可靠的方式是让它不属于关卡子树。挂在
##   Boot（常驻主场景）下即可：换关卡只换 World 的子节点，GUI/Menus 天然不受影响。
##   同时容器把"谁属于世界、谁属于界面"变成显式结构，而不是靠命名猜测。
##
## 【挂哪个节点】
##   scenes/core/boot.tscn 的根节点（Node）。project.godot 的 run/main_scene 指向它。
##
## 【依赖谁】
##   UIRegistry（容器与窗口登记）、GameFlow（局面迁移）、TutorialSystem。
##
## 【怎么扩展】
##   新增常驻 UI：在 PERSISTENT_UI 里加一行"场景路径 → (节点名, 容器)"。
extends Node

# ============================================================================
# @export
# ============================================================================

## 启动后进入的关卡 id（主菜单点"新的冒险"时用）。
@export var start_level: StringName = &"town"
## 启动后进入的入口点名。
@export var start_entry: StringName = &"start"
## 是否跳过主菜单直接进游戏（调试用）。
@export var skip_menu: bool = false
## 是否显示主菜单。
@export var show_menu: bool = true

# ============================================================================
# 常量
# ============================================================================

## 容器枚举：常驻 UI 挂到哪一层。
enum Layer { GUI, MENUS }

## 常驻 UI 清单：{ 场景路径: [节点名, 容器] }。按顺序挂载，后者层级更高。
##
## 【为什么用数组而不是内联字典】GDScript 的 const 里可以用字面量数组构造，
##   但用 `Vector2`/枚举值做成员也可行；这里 [名字, Layer] 比拆两个字典更紧凑。
const PERSISTENT_UI: Dictionary = {
	"res://scenes/ui/hud.tscn": ["HUD", Layer.GUI],
	"res://scenes/ui/tutorial_ui.tscn": ["TutorialUI", Layer.MENUS],
	"res://scenes/ui/boss_health_bar.tscn": ["BossHealthBar", Layer.GUI],
	# 对话框是 EventBus.dialog_requested / dialog_sequence_requested 的唯一接收端，
	# 缺了它 NPC 说话、路牌、系统提示会全部静默。
	# 它内部是两条互不干扰的通道（顶部提示条 / 底部对话条）；
	# 教程文字只走 TutorialUI，不在这里重复显示。
	"res://scenes/ui/dialog_ui.tscn": ["DialogUI", Layer.MENUS],
	"res://scenes/ui/modifier_choice.tscn": ["ModifierChoice", Layer.MENUS],
	"res://scenes/ui/inventory_ui.tscn": ["InventoryUI", Layer.MENUS],
	"res://scenes/ui/game_over.tscn": ["GameOverUI", Layer.MENUS],
	"res://scenes/ui/pause_menu.tscn": ["PauseMenu", Layer.MENUS],
}

# ============================================================================
# 私有变量
# ============================================================================

var _world: Node2D
var _gui: CanvasLayer
var _menus: CanvasLayer

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	_build_containers()
	_install_persistent_ui()
	# 【为什么需要这条兜底】常驻层是 Boot 在启动时挂一次就不管了的。
	#   历史上 PauseMenu / GameOverUI 会在"返回主菜单"时 queue_free() 掉自己，
	#   于是玩家回到菜单再开新游戏时，那一层 UI 永久消失（Esc 没反应 / 死亡无界面）。
	#   根因已在各 UI 里修掉，但"常驻层被误删且无人重建"是一整类回归，
	#   这里加一道守卫：每进一个关卡都确认常驻层齐全，缺了就地补上。
	EventBus.scene_changed.connect(_on_scene_changed)
	# 局面迁移全部交给 GameFlow（唯一入口）。Boot 只负责"装配 + 决定进哪个局面"。
	if skip_menu or not show_menu:
		_begin_game()
	else:
		_enter_main_menu()


# ============================================================================
# 私有方法 —— 容器
# ============================================================================

## 建立 World / GUI / Menus 三个容器，并交给 UIRegistry（供关卡与窗口按归属挂载）。
func _build_containers() -> void:
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)

	_gui = CanvasLayer.new()
	_gui.name = "GUI"
	_gui.layer = 10
	add_child(_gui)

	_menus = CanvasLayer.new()
	_menus.name = "Menus"
	_menus.layer = 30
	add_child(_menus)

	UIRegistry.attach_containers(_world, _gui, _menus)


## 某个常驻 UI 应挂到哪个容器。
func _container_for(layer: int) -> Node:
	return _gui if layer == Layer.GUI else _menus


# ============================================================================
# 私有方法 —— 常驻 UI
# ============================================================================

## 挂载常驻 UI 到对应容器。窗口在自己的 _ready 里登记进 UIRegistry。
func _install_persistent_ui() -> void:
	for path: String in PERSISTENT_UI.keys():
		_mount_persistent_ui(path)


## 挂载单个常驻 UI（装配与兜底重建共用）。
func _mount_persistent_ui(path: String) -> void:
	if not ResourceLoader.exists(path):
		push_warning("[Boot] 缺少 UI 场景：%s" % path)
		return
	var info: Array = PERSISTENT_UI[path]
	var node_name: String = info[0]
	var parent: Node = _container_for(info[1])
	var scene: PackedScene = load(path)
	if scene == null:
		return
	var node: Node = scene.instantiate()
	node.name = node_name
	# boot._ready 阶段正在设置子节点，必须延迟挂载。
	parent.add_child.call_deferred(node)


## 换关卡时核对常驻 UI 是否齐全，缺了就补挂。
##
## 【为什么只补不重建已有的】已存在的节点可能正持有玩家的交互状态（背包开合、
##   血条绑定），无脑重建会闪屏并丢状态。只处理"整层消失了"这一种情况。
func _on_scene_changed(_scene: Node) -> void:
	for path: String in PERSISTENT_UI.keys():
		var node_name: String = PERSISTENT_UI[path][0]
		if UIRegistry.find_by_name(node_name) != null:
			continue
		push_warning("[Boot] 常驻 UI 缺失，已重新挂载：%s" % node_name)
		_mount_persistent_ui(path)


# ============================================================================
# 私有方法 —— 局面
# ============================================================================

## 进入主菜单局面。菜单的实例化由 GameFlow 统一负责（避免两处各建一个菜单）。
## Boot 只负责把"起始关卡"这个配置交给 GameFlow。
func _enter_main_menu() -> void:
	GameFlow.start_level = start_level
	GameFlow.start_entry = start_entry
	GameFlow.request(GameFlow.State.MENU)


## 直接开始游戏（跳过菜单）。
##
## 与主菜单"新的冒险"走同一个入口 GameFlow.start_run，保证状态迁移一致
## （先完整清理再进关，不会带着上一局残留）。
func _begin_game() -> void:
	GameFlow.start_run(start_level, start_entry)
	TutorialSystem.start_tutorial()
