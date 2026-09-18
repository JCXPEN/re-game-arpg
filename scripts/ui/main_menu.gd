## MainMenu —— 主菜单
##
## 【负责什么】
##   游戏启动后的第一屏：开始新游戏 / 继续 / 操作说明 / 设置 / 退出。
##   所有按钮行为通过 @export 的 action 名分派，不写死节点路径。
##
## 【挂哪个节点】
##   scenes/ui/main_menu.tscn 的根节点（Control）。Boot 在启动时加载它。
##
## 【依赖谁】
##   SceneDirector（开始游戏）、GameState（继续/新档）、AudioManager。
##
## 【怎么扩展】
##   加按钮：在场景里加一个 Button，命名以 btn_ 开头，本脚本会自动接线。
class_name MainMenu
extends Control

# ============================================================================
# @export
# ============================================================================

## 游戏起始关卡。
@export var start_level: StringName = &"town"
## 操作说明面板场景。
@export var help_panel_scene: PackedScene
## 设置面板场景。
@export var settings_panel_scene: PackedScene
## 菜单背景色（没有背景图时用纯色）。
@export var background_color: Color = Color(0.055, 0.055, 0.078)
## 标题文字。
@export var title_text: String = "ActRPG"

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
	# 登记进 UI 注册表：调用方按 id 访问，不再按树路径查名。
	UIRegistry.register(&"main_menu", self)
	# 【为什么不是裸写 get_tree().paused = false】暂停位由 PauseManager 唯一持有。
	#   主菜单出现意味着"这一局结束了"，正确做法是把所有令牌作废（清空），
	#   而不是绕过所有权直接改 paused —— 后者会让仍持有令牌的窗口
	#   与新局状态对不上，是"暂停状态错乱"的一大来源。
	PauseManager.clear_all()
	_apply_theme()
	_collect_buttons()
	_connect_buttons()
	_setup_title()
	# "继续"按钮在没有任何存档时禁用。
	if _buttons.has("continue"):
		var has_save: bool = FileAccess.file_exists(GameState.SAVE_PATH)
		(_buttons["continue"] as Button).disabled = not has_save
	# 主菜单 BGM：GameFlow 在 teardown 时已切好；直接进这里（F5 单跑菜单）
	# 时补一次，保证菜单永远有自己的音乐。
	#
	# 【为什么用 play_music_for + 明确 owner】音乐归属是"BGM 与场景是否匹配"的
	#   判定依据。菜单曲若不带 owner，之后切关卡时按 owner 比对会误判，
	#   出现"沿用上一首"类的错配。这里显式登记 MENU_MUSIC_OWNER。
	if not AudioManager.is_playing_music() or AudioManager.get_music_owner() != GameFlow.MENU_MUSIC_OWNER:
		AudioManager.play_music_for(GameFlow.MENU_MUSIC_OWNER, GameFlow.load_menu_music_stream())


## 主菜单里按 Esc：默认不做任何事（避免误退出）。
##
## 【为什么必须先让开有阻塞窗口的情况 —— 这是"主菜单设置关不掉"的根因】
##   MainMenu 是普通 root 子节点，_unhandled_input 的投递顺序**早于** UIInputRouter
##   （router 是 autoload，逆序时最后收到）。旧实现无条件 `set_input_as_handled()`，
##   于是玩家在主菜单打开"设置/操作说明"后按 Esc：事件被 MainMenu 抢走吞掉，
##   router 永远收不到，子面板**关不掉**，玩家被困在设置界面里。
##   正确语义：有阻塞窗口（设置/说明）时让开，交给 router 路由给它自己去关。
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause"):
		return
	if UIInputRouter.has_blocking_ui():
		return
	# 真的在主菜单、没有任何弹窗 → 吃掉，避免误触发暂停菜单。
	get_viewport().set_input_as_handled()


# ============================================================================
# 私有方法
# ============================================================================

## 应用统一主题。
func _apply_theme() -> void:
	if ResourceLoader.exists("res://resources/ui_theme.tres"):
		theme = load("res://resources/ui_theme.tres")


## 收集所有 btn_ 开头的按钮，按其后缀作为 action 名。
func _collect_buttons() -> void:
	_buttons.clear()
	for child: Node in find_children("btn_*", "Button", true, false):
		var btn: Button = child as Button
		if btn != null:
			# btn_new_game → "new_game"
			_buttons[btn.name.trim_prefix("btn_")] = btn


## 给每个按钮接上对应处理。
func _connect_buttons() -> void:
	for action: String in _buttons.keys():
		var btn: Button = _buttons[action]
		btn.pressed.connect(_on_menu_action.bind(action))


## 设置标题文字。
func _setup_title() -> void:
	var title: Label = find_child("Title", true, false) as Label
	if title != null:
		title.text = title_text


## 按钮分派。
func _on_menu_action(action: String) -> void:
	match action:
		"new_game":
			_start_new_game()
		"continue":
			_continue_game()
		"help":
			_open_help()
		"settings":
			_open_settings()
		"quit":
			get_tree().quit()
		_:
			push_warning("[MainMenu] 未知菜单动作：%s" % action)


## 开始新游戏：重置存档（保留局外解锁？——新档就全清）。
##
## 【为什么走 GameFlow.start_run 而不是直接 change_to_level】
##   start_run 会先做一次完整的 teardown（清暂停令牌 / 弹窗队列 / 教程状态 /
##   收起残留 UI / 取消在途转场），再挂关卡。直接切场景会绕过这些清理，
##   留下跨局脏状态。状态迁移只认一个入口。
func _start_new_game() -> void:
	GameState.reset_save()
	GameFlow.start_run(start_level, &"start")
	# 新档要播放新手教程（必须在 start_run 的 teardown 之后，否则会被 reset 掉）。
	TutorialSystem.start_tutorial()
	queue_free()


## 继续游戏：读档并从复活点/起点开始。
func _continue_game() -> void:
	GameState.load_game()
	var respawn: Dictionary = GameState.get_respawn_point()
	var level_id: StringName = respawn.get("level", &"")
	if level_id == &"":
		level_id = start_level
	# 继续游戏不重播教程（tutorial_completed 存在存档里）。
	GameFlow.start_run(level_id, &"")
	queue_free()


## 打开操作说明。
##
## 【为什么必须调 open() 而不是只 add_child】
##   子面板的 _ready() 末尾都会 `visible = false`（它们本来是给暂停菜单按需调用的）。
##   只 instantiate + add_child 的话，面板建出来是**隐藏**的，玩家第 1 次点击毫无反应；
##   第 2 次点击走 `_help_panel != null` 分支直接 visible = true 才"奇迹般"出现。
##   统一入口是 open()：它负责可见性 + PopupManager 互斥 + 冻结游戏 + 聚焦。
##
## 【为什么用 HelpPanel.acquire】按名字复用全局唯一实例，避免"暂停菜单与主菜单
##   各建一个"导致 Esc 路由作用到错误面板（关不掉）。详见该静态方法注释。
func _open_help() -> void:
	_help_panel = HelpPanel.acquire(help_panel_scene) as CanvasLayer
	_panel_open(_help_panel)


## 打开设置。
## 【为什么同 _open_help】SettingsPanel 有完全一样的隐藏初值，踩的是同一个坑。
func _open_settings() -> void:
	_settings_panel = SettingsPanel.acquire(settings_panel_scene) as CanvasLayer
	_panel_open(_settings_panel)


## 用统一入口唤醒面板：优先 open()，没有该方法才退回直接置 visible。
##
## 【为什么要判 has_method】
##   主菜单不关心面板内部实现，只认契约"能打开"。用 has_method 而不是强转类型，
##   是为了让任何实现了 open()/close() 的面板都能挂进主菜单（含测试替身）。
func _panel_open(panel: CanvasLayer) -> void:
	if panel == null:
		return
	if panel.has_method(&"open"):
		panel.call(&"open")
	else:
		panel.visible = true
