## PauseMenu —— 暂停菜单
##
## 【负责什么】
##   游戏中按 Esc 暂停：继续 / 操作说明 / 设置 / 返回主菜单 / 退出。
##   冻结游戏走 PauseManager.freeze(OWNER)，不自己裸写 get_tree().paused。
##
## 【挂哪个节点】
##   scenes/ui/pause_menu.tscn 的根节点（CanvasLayer），由 Boot 常驻挂载。
##
## 【依赖谁】
##   SceneDirector、GameState、AudioManager、PauseManager、UIInputRouter。
##
## 【Esc 为什么不再自己监听】
##   本菜单是 PERSISTENT_UI 里**最后**挂载的常驻层，而 Godot 的
##   _unhandled_input 按场景树逆序广播 —— 于是它**最先**收到 Esc，会把事件
##   吃掉并 toggle()，导致屏幕上层的教程/帮助永远收不到 Esc（关不掉）。
##   现在 Esc 由 UIInputRouter 集中仲裁：本菜单只注册成"路由目标"，
##   轮到它时才收到 route_esc()。
class_name PauseMenu
extends CanvasLayer

# ============================================================================
# @export
# ============================================================================

## 操作说明面板场景。
@export var help_panel_scene: PackedScene
## 设置面板场景。
@export var settings_panel_scene: PackedScene
## 主菜单场景（返回主菜单时用）。
@export var main_menu_scene: PackedScene

# ============================================================================
# 常量
# ============================================================================

## 本菜单在 PauseManager 里的令牌 id。
const PAUSE_OWNER: StringName = &"pause_menu"

# ============================================================================
# 私有变量
# ============================================================================

var _buttons: Dictionary = {}
var _help_panel: CanvasLayer
var _settings_panel: CanvasLayer

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_theme()
	_collect_buttons()
	visible = false
	# 注册为 Esc 路由目标：轮到本菜单时由 UIInputRouter 调 route_esc()。
	add_to_group(UIInputRouter.GROUP)
	# 登记进 UI 注册表：调用方按 id 访问，不再按树路径查名。
	UIRegistry.register(&"pause_menu", self)
	# 注册"没有阻塞窗口时，Esc 打开暂停菜单"的回调。
	UIInputRouter.set_pause_opener(func() -> void: open())
	# 暂停时不接收角色输入，但本菜单必须能响应。
	EventBus.player_died.connect(_on_player_died)


# ============================================================================
# UIInputRouter 契约
# ============================================================================

## 本窗口在 Esc 路由里的层级。
func ui_layer_priority() -> int:
	return UIInputRouter.LAYER_PAUSE_MENU


## 是否阻塞型窗口（挡住玩家、需要玩家处理）。
func is_blocking_ui() -> bool:
	return visible


## 窗口标识（调试 / 测试用）。
func ui_window_id() -> StringName:
	return &"pause_menu"


## 轮到本窗口处理 Esc。返回 true 表示已消费。
##
## 【子面板优先】帮助/设置开着时，Esc 先关子面板而不是收起整个暂停菜单
##   —— 否则玩家会一次退两层，体感很突兀。
##
## 【为什么必须调子面板的 close() 而不是直接 visible=false】
##   子面板被打开时各自登记了副作用：HelpPanel 持有 PauseManager 令牌并占着
##   PopupManager 槽位，SettingsPanel 需要把音量落盘。直接改 visible 会绕过这些
##   收尾：令牌/槽位永久泄漏（下一个弹窗永远轮不到），设置改动丢失。
##   close() 是它们自己的收尾契约，必须走它。
func route_esc() -> bool:
	if _help_panel != null and _help_panel.visible:
		_close_panel(_help_panel)
		return true
	if _settings_panel != null and _settings_panel.visible:
		_close_panel(_settings_panel)
		return true
	if visible:
		close()
		return true
	return false


# ============================================================================
# 公开方法
# ============================================================================

## 切换暂停状态。
func toggle() -> void:
	if visible:
		close()
	else:
		open()


## 暂停游戏并显示菜单。
func open() -> void:
	if visible:
		return
	visible = true
	PauseManager.freeze(PAUSE_OWNER)
	# 通知局面状态机（GameFlow 只记录局面，不重复冻结；见其 set_paused 注释）。
	GameFlow.set_paused(true)
	# 让"继续"按钮获得焦点，方便手柄/键盘操作。
	if _buttons.has("resume"):
		(_buttons["resume"] as Button).grab_focus()


## 继续游戏。
func close() -> void:
	if not visible:
		# 即便已经不可见也要交还令牌，避免"令牌泄漏导致永久暂停"。
		PauseManager.unfreeze(PAUSE_OWNER)
		GameFlow.set_paused(false)
		return
	visible = false
	PauseManager.unfreeze(PAUSE_OWNER)
	GameFlow.set_paused(false)


## 兼容旧调用名（外部/测试可能还在用 resume()）。
func resume() -> void:
	close()


# ============================================================================
# 私有方法
# ============================================================================

func _apply_theme() -> void:
	# CanvasLayer 没有 theme 属性，主题要设在内部 Root(Control) 上。
	if not ResourceLoader.exists("res://resources/ui_theme.tres"):
		return
	var root: Control = get_node_or_null("Root") as Control
	if root != null:
		root.theme = load("res://resources/ui_theme.tres")


func _collect_buttons() -> void:
	_buttons.clear()
	for child: Node in find_children("btn_*", "Button", true, false):
		var btn: Button = child as Button
		if btn != null:
			_buttons[btn.name.trim_prefix("btn_")] = btn
	for action: String in _buttons.keys():
		(_buttons[action] as Button).pressed.connect(_on_action.bind(action))


func _on_action(action: String) -> void:
	match action:
		"resume":
			resume()
		"help":
			_open_help()
		"settings":
			_open_settings()
		"main_menu":
			_go_main_menu()
		"quit":
			get_tree().quit()
		_:
			push_warning("[PauseMenu] 未知动作：%s" % action)


## 打开操作说明。
##
## 【为什么必须调 open() 而不是只 visible=true】HelpPanel 打开时要登记
##   PauseManager 令牌与 PopupManager 槽位；只改 visible 会让它的状态机
##   与实际显示脱节（关闭时误以为"自己没开过"，收尾不完整）。
func _open_help() -> void:
	_help_panel = HelpPanel.acquire(help_panel_scene) as CanvasLayer
	_open_panel(_help_panel)


## 打开设置。
func _open_settings() -> void:
	_settings_panel = SettingsPanel.acquire(settings_panel_scene) as CanvasLayer
	_open_panel(_settings_panel)


## 走子面板的 open() 契约；没有该方法才退回直接置 visible（兼容测试替身）。
func _open_panel(panel: CanvasLayer) -> void:
	if panel == null:
		return
	if panel.has_method(&"open"):
		panel.call(&"open")
	else:
		panel.visible = true


## 走子面板的 close() 契约（负责各自的收尾：令牌 / 槽位 / 落盘）。
func _close_panel(panel: CanvasLayer) -> void:
	if panel == null:
		return
	if panel.has_method(&"close"):
		panel.call(&"close")
	else:
		panel.visible = false


## 返回主菜单。
##
## 【为什么不能 queue_free() 自己】
##   本菜单是 Boot 在启动时挂上的**常驻层**，和 MainMenu（每次现建的临时层）不同。
##   曾经这里末尾写了 `queue_free()`，于是"暂停 → 返回主菜单"之后本节点就没了，
##   Boot 也不会重建：再开新游戏时按 Esc 毫无反应，暂停功能永久失效。
##   正确做法是**只把界面收起来**（close），节点留在树上等下次要用。
##
## 【为什么整局清理交给 GameFlow】停 BGM、清弹窗队列、复位教程、断开
##   关卡引用这四件事缺一不可，散在这里写早晚漏掉一项（实测就漏了 BGM）。
##   收敛成一次 teardown_to_menu() 调用，语义也变成"这一局结束了"。
func _go_main_menu() -> void:
	close()
	# 子面板也要一起收掉（走各自 close() 契约，避免令牌/槽位/落盘被绕过），
	# 否则会浮在主菜单上面。
	_close_panel(_help_panel)
	_close_panel(_settings_panel)
	GameFlow.teardown_to_menu()


# ============================================================================
# 信号回调
# ============================================================================

## 玩家死亡时不弹暂停菜单（由 GameOverUI 接管）。
##
## 【为什么走 close() 而不是只 visible=false】暂停菜单开着时它持有暂停令牌；
##   只把界面藏起来会把令牌永久留在 PauseManager 里（新局一开始就是暂停的）。
##   close() 负责交还令牌，界面收起的语义完全一样。
func _on_player_died() -> void:
	close()
