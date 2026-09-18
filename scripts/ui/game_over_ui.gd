## GameOverUI —— 死亡 / 胜利结算界面
##
## 【负责什么】
##   玩家死亡时显示"你倒下了"，提供"从存档点复活 / 返回主菜单"；
##   Boss 被击败时显示通关结算（用时、击杀数、获得的词条）。
##
## 【挂哪个节点】
##   scenes/ui/game_over.tscn 的根节点（CanvasLayer），由 Boot 常驻挂载。
##
## 【依赖谁】
##   EventBus（player_died / boss_defeated）、GameState、SceneDirector。
class_name GameOverUI
extends CanvasLayer

# ============================================================================
# @export
# ============================================================================

## 标题标签。
@export var title_path: NodePath
## 正文标签。
@export var body_path: NodePath
## 主菜单场景。
@export var main_menu_scene: PackedScene
## 是否在显示时暂停游戏。
@export var pause_game: bool = true

# ============================================================================
# 常量
# ============================================================================

## 本窗口在 PauseManager 里的暂停令牌 id。
const PAUSE_OWNER: StringName = &"game_over"

# ============================================================================
# 私有变量
# ============================================================================

var _title: Label
var _body: Label
var _buttons: Dictionary = {}
## 当前显示的是死亡还是胜利。
var _is_victory: bool = false

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not title_path.is_empty():
		_title = get_node_or_null(title_path) as Label
	if not body_path.is_empty():
		_body = get_node_or_null(body_path) as Label
	_collect_buttons()
	_apply_theme()
	visible = false
	# Esc 交给 UIInputRouter 仲裁（死亡/胜利界面层级最高，Esc 不该穿透去开暂停菜单）。
	add_to_group(UIInputRouter.GROUP)
	# 登记进 UI 注册表：调用方按 id 访问，不再按树路径查名。
	UIRegistry.register(&"game_over", self)
	EventBus.player_died.connect(_on_player_died)
	EventBus.boss_defeated.connect(_on_boss_defeated)


# ============================================================================
# UIInputRouter 契约
# ============================================================================

func ui_layer_priority() -> int:
	return UIInputRouter.LAYER_VICTORY if _is_victory else UIInputRouter.LAYER_GAME_OVER


func is_blocking_ui() -> bool:
	return visible


func ui_window_id() -> StringName:
	return &"game_over"


## 轮到本窗口处理 Esc：死亡界面按 Esc 不做事（避免误触复活/退出），
## 但**必须返回 true** 吃掉它，否则会穿透下去弹出暂停菜单叠在死亡界面上。
func route_esc() -> bool:
	return visible


## 回主菜单时强制收起。
func force_close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# 死亡界面按交互键 = 复活。
	if _is_victory:
		return
	if event.is_action_pressed(&"interact") or event.is_action_pressed(&"attack"):
		_respawn()
		get_viewport().set_input_as_handled()


# ============================================================================
# 私有方法
# ============================================================================

func _collect_buttons() -> void:
	_buttons.clear()
	for child: Node in find_children("btn_*", "Button", true, false):
		var btn: Button = child as Button
		if btn != null:
			_buttons[btn.name.trim_prefix("btn_")] = btn
	for action: String in _buttons.keys():
		(_buttons[action] as Button).pressed.connect(_on_action.bind(action))


func _apply_theme() -> void:
	# CanvasLayer 没有 theme 属性，主题要设在内部 Root(Control) 上。
	if not ResourceLoader.exists("res://resources/ui_theme.tres"):
		return
	var root: Control = get_node_or_null("Root") as Control
	if root != null:
		root.theme = load("res://resources/ui_theme.tres")


func _on_action(action: String) -> void:
	match action:
		"respawn":
			_respawn()
		"main_menu":
			_go_main_menu()
		_:
			pass


## 死亡界面。
func _on_player_died() -> void:
	_is_victory = false
	_show_panel("你倒下了", "从最近的存档点重新出发，或返回主菜单。", true)


## 胜利界面。
func _on_boss_defeated(_boss_id: StringName) -> void:
	_is_victory = true
	# 结算数据。
	var minutes: int = int(GameState.run_time) / 60
	var seconds: int = int(GameState.run_time) % 60
	var mods: int = ModifierSystem.get_owned_count()
	var body: String = "用时 %d:%02d　　击杀 %d　　词条 %d\n\n恭喜你击败了独眼巨人，边境恢复了和平。" % [
		minutes, seconds, GameState.run_kills, mods
	]
	_show_panel("通关！", body, false)
	GameState.end_run(true)


## 显示面板。
func _show_panel(title_text: String, body_text: String, show_respawn: bool) -> void:
	if _title != null:
		_title.text = title_text
		_title.add_theme_color_override("font_color",
			Color(1.0, 0.85, 0.3) if _is_victory else Color(0.95, 0.4, 0.4))
	if _body != null:
		_body.text = body_text
	# 复活按钮只在死亡时显示。
	if _buttons.has("respawn"):
		(_buttons["respawn"] as Button).visible = show_respawn
	visible = true
	if pause_game:
		PauseManager.freeze(PAUSE_OWNER)
	# 通知局面状态机：进入 GAME_OVER 局面（见 GameFlow.notify_game_over）。
	GameFlow.notify_game_over()


## 从存档点复活。
func _respawn() -> void:
	visible = false
	if pause_game:
		PauseManager.unfreeze(PAUSE_OWNER)
	# 复活 = 回到局内进行中。
	GameFlow.request(GameFlow.State.PLAYING)
	var respawn: Dictionary = GameState.get_respawn_point()
	var level_id: StringName = respawn.get("level", &"")
	if level_id == &"":
		# 没存过档就回起点。
		level_id = &"town"
	# 关键：把坐标交给 SceneDirector，让玩家在**生成时**就落在存档点。
	# 不能先 change_to_level 再改坐标——切场景是异步的（淡入淡出 ~22 帧），
	# 那两帧里新玩家还没生成，坐标会写给即将被销毁的旧玩家。
	var spawn_pos: Vector2 = respawn.get("position", Vector2.ZERO)
	if spawn_pos != Vector2.ZERO:
		SceneDirector.set_next_spawn_position(spawn_pos)
	# 死亡不该剥夺玩家的构筑，所以这里不调 start_run，只重新加载关卡。
	SceneDirector.change_to_level(level_id, &"")


## 返回主菜单：整局状态由 GameFlow 统一清理（含 BGM / 弹窗队列 / 关卡引用）。
##
## 【为什么不能 queue_free() 自己】
##   与 PauseMenu 同因：本界面是 Boot 启动时挂上的**常驻层**。
##   曾经这里末尾写了 `queue_free()`，导致"死亡 → 返回主菜单 → 再开新游戏"之后
##   结算界面永久消失：玩家死亡时游戏暂停了却没有任何 UI，只剩下一个卡死的黑屏。
func _go_main_menu() -> void:
	visible = false
	GameFlow.teardown_to_menu()
