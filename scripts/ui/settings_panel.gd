## SettingsPanel —— 设置面板（渲染 + 转发）
##
## 【负责什么】
##   只做两件事：**把当前设置画出来**、**把玩家改动交给 SettingsService**。
##   它不读配置文件、不碰 AudioServer/DisplayServer —— 那些是 SettingsService 的职责。
##
## 【挂哪个节点】
##   scenes/ui/settings_panel.tscn 的根节点（CanvasLayer）。
##
## 【依赖谁】
##   SettingsService（设置读写与应用）、UIRegistry / UIInputRouter（登记与关闭契约）。
##
## 【为什么必须 process_mode = ALWAYS —— 这是"设置无法退出"的根因】
##   本面板最常从**暂停菜单**里打开，此时 get_tree().paused == true。
##   而 Godot 只向 PROCESS_MODE_ALWAYS 的节点派发输入：默认 INHERIT 的节点在暂停
##   状态下 can_process() 为 false，**按钮点不动、滑块也拖不动**。
##   HelpPanel/TutorialUI 都有这一行，本面板曾经漏了。
##
## 【关闭契约】
##   走 UIInputRouter 的 Esc 仲裁（route_esc → close），并额外提供"返回/确定"按钮。
##   按钮在 ALWAYS 下可点，任何一条途径都能退出，不会把玩家困住。
class_name SettingsPanel
extends CanvasLayer

# ============================================================================
# 常量
# ============================================================================

## 本窗口在 UIRegistry / UIInputRouter 里的 id。
const POPUP_ID: StringName = &"settings"

# ============================================================================
# @export
# ============================================================================

## 面板根节点。
@export var panel_path: NodePath
## 主音量滑块（0..1 线性）。
@export var master_slider_path: NodePath
## 音效滑块。
@export var sfx_slider_path: NodePath
## 音乐滑块。
@export var music_slider_path: NodePath
## "确定"按钮。
@export var close_button_path: NodePath
## "返回"按钮。
@export var back_button_path: NodePath
## 全屏开关（CheckButton）。
@export var fullscreen_path: NodePath

# ============================================================================
# 私有变量
# ============================================================================

var _panel: Control
var _master: HSlider
var _sfx: HSlider
var _music: HSlider
var _fullscreen: CheckButton
## 正在用代码回填控件时置 true，避免 value_changed 回调被当成玩家输入。
var _loading: bool = false

# ============================================================================
# 静态获取
# ============================================================================

## 取全局唯一的 SettingsPanel，没有就用 scene 现建一个并挂到 Menus 容器。
##
## 【为什么要"唯一复用"而不是各入口各自 instantiate】
##   设置面板有两个入口：主菜单和暂停菜单。各建各的话，玩家"暂停里开过设置 →
##   回主菜单再开设置"就会在树上留下**两个** SettingsPanel，Esc 路由、可见性、
##   force_close 全都会作用到错误的那一个上。
##
## 【为什么按 id 从 UIRegistry 取，而不是按节点名在 root 下找】
##   窗口现在挂在 `Menus` 容器下，不再直属 root；"按名字查"也正是本项目要淘汰的
##   反模式（见 UIRegistry 文件头）。统一走注册表 id 查询。
static func acquire(scene: PackedScene) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var reg: Node = tree.root.get_node_or_null(NodePath("UIRegistry"))
	var existing: Node = null
	if reg != null:
		existing = reg.call(&"window_for", &"settings")
	if existing != null:
		return existing
	if scene == null:
		return null
	var inst: Node = scene.instantiate()
	inst.name = "SettingsPanel"
	var parent: Node = tree.root
	if reg != null:
		parent = reg.call(&"menus_container")
	parent.add_child(inst)
	return inst

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	# 关键，见文件头：暂停中也要能点按钮 / 拖滑块 / 收到路由来的 Esc。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_resolve_nodes()
	_connect_buttons()
	_apply_theme()
	_connect_signals()
	_sync_from_service()
	visible = false
	# 登记进注册表 + 交给路由器仲裁 Esc。
	UIRegistry.register(POPUP_ID, self)
	add_to_group(UIInputRouter.GROUP)

# ============================================================================
# UIInputRouter 契约
# ============================================================================

func ui_layer_priority() -> int:
	return UIInputRouter.LAYER_SETTINGS


func is_blocking_ui() -> bool:
	return visible


func ui_window_id() -> StringName:
	return POPUP_ID


## 轮到本窗口处理 Esc：关闭。返回 true 表示已消费。
func route_esc() -> bool:
	if not visible:
		return false
	close()
	return true


## 回主菜单时强制收起。
func force_close() -> void:
	close()

# ============================================================================
# 公开方法
# ============================================================================

func open() -> void:
	# 每次打开都从服务同步（可能在别处被改过），再显示。
	_sync_from_service()
	visible = true
	if _master != null:
		_master.grab_focus()


## 关闭。设置已在改动时即时生效并落盘，这里无需额外保存。
func close() -> void:
	visible = false


func is_open() -> bool:
	return visible

# ============================================================================
# 私有方法 —— 节点 / 连线
# ============================================================================

func _resolve_nodes() -> void:
	if not panel_path.is_empty():
		_panel = get_node_or_null(panel_path) as Control
	if not master_slider_path.is_empty():
		_master = get_node_or_null(master_slider_path) as HSlider
	if not sfx_slider_path.is_empty():
		_sfx = get_node_or_null(sfx_slider_path) as HSlider
	if not music_slider_path.is_empty():
		_music = get_node_or_null(music_slider_path) as HSlider
	if not fullscreen_path.is_empty():
		_fullscreen = get_node_or_null(fullscreen_path) as CheckButton
	if _panel == null:
		_panel = get_node_or_null("Root/Panel") as Control


func _connect_buttons() -> void:
	for path: NodePath in [close_button_path, back_button_path]:
		if path.is_empty():
			continue
		var btn: Button = get_node_or_null(path) as Button
		if btn != null:
			btn.pressed.connect(close)


func _connect_signals() -> void:
	for s: HSlider in [_master, _sfx, _music]:
		if s != null:
			s.value_changed.connect(_on_volume_changed.bind(s))
	if _fullscreen != null:
		_fullscreen.toggled.connect(_on_fullscreen_toggled)


func _apply_theme() -> void:
	# CanvasLayer 没有 theme 属性，主题要设在内部 Root(Control) 上。
	if ResourceLoader.exists("res://resources/ui_theme.tres") and _panel != null:
		_panel.theme = load("res://resources/ui_theme.tres")

# ============================================================================
# 私有方法 —— 同步
# ============================================================================

## 用服务里的值回填控件（不触发"应用"，因为服务已应用过了）。
func _sync_from_service() -> void:
	_loading = true
	if _master != null:
		_master.value = SettingsService.master_volume()
	if _sfx != null:
		_sfx.value = SettingsService.sfx_volume()
	if _music != null:
		_music.value = SettingsService.music_volume()
	if _fullscreen != null:
		_fullscreen.button_pressed = SettingsService.is_fullscreen()
	_loading = false
	_refresh_value_labels()


func _refresh_value_labels() -> void:
	_refresh_value_label(_master)
	_refresh_value_label(_sfx)
	_refresh_value_label(_music)


## 刷新某行右侧的百分比标签（约定：滑块父节点下有个名为 Value 的 Label）。
func _refresh_value_label(s: HSlider) -> void:
	if s == null:
		return
	var value_label: Label = s.get_parent().get_node_or_null("Value") as Label
	if value_label == null:
		return
	var pct: int = int(round(clampf(s.value, 0.0, 1.0) * 100.0))
	value_label.text = "静音" if pct <= 0 else "%d%%" % pct

# ============================================================================
# 信号回调 —— 把玩家改动转发给服务
# ============================================================================

func _on_volume_changed(_value: float, _source: HSlider) -> void:
	if _loading:
		return
	# 三个滑块一起交给服务（它负责应用 + 落盘），避免各自持有一份状态。
	SettingsService.set_volumes(
		_master.value if _master != null else SettingsService.master_volume(),
		_sfx.value if _sfx != null else SettingsService.sfx_volume(),
		_music.value if _music != null else SettingsService.music_volume())
	_refresh_value_labels()


func _on_fullscreen_toggled(pressed: bool) -> void:
	if _loading:
		return
	SettingsService.set_fullscreen(pressed)
