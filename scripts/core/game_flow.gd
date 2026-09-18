## GameFlow —— 局面状态机 + 局面生命周期入口（Autoload 单例）
##
## 【负责什么】
##   1. **局面状态机**：唯一回答"现在游戏处于哪个局面"，并把合法转移固化成表。
##      BOOT → MENU → PLAYING ⇄ PAUSED → GAME_OVER，非法转移直接拒绝并告警。
##   2. **一次状态迁移的全部副作用**：进入某个局面时该清理什么、该挂什么、该播什么，
##      集中在 `_enter_*` 里，保证"从任意局面进入 MENU"只有一条路径。
##
## 【为什么是 Autoload —— 对照官方文档】
##   Godot 官方《Singletons》明确把 autoload 的适用场景之一定义为
##   "Can handle switching scenes and between-scene transitions."
##   GameFlow 正是做场景/局面切换与转场的协调者，且需要被所有 UI 与测试全局访问；
##   它不持有任何玩法数据（数据在 GameState / LevelData），只做编排，符合 autoload 的边界。
##
## 【为什么需要状态机，而不是像旧 SessionFlow 那样只写清理函数】
##   旧实现把"回主菜单"的 7 步清理写成一个函数 `teardown_to_menu()`，任何新入口
##   （死亡重开、跳过菜单、未来加过场）都可能绕过它或漏步。状态机让"当前局面"变成
##   可查询、可断言的单一真相，转移必须过 `LEGAL_TRANSITIONS`，非法转移会被拒绝并告警。
##
## 【与 PauseManager 的关系 —— 不冲突，各有其职】
##   · GameFlow 管"**局面**"（宏观：在菜单 / 在玩 / 已结算）。
##   · PauseManager 管"**paused 位**"（微观：谁要求冻结游戏树），它仍是暂停的唯一真相。
##   PAUSED 局面由暂停菜单通过 `set_paused()` 通知，GameFlow 只记录，不重复冻结。
##
## 【为什么不做成 class_name】注册为 autoload `GameFlow`，同名 class_name 会冲突。
extends Node

# ============================================================================
# 状态机定义
# ============================================================================

## 游戏局面。
enum State {
	BOOT,       ## 启动装配中（尚未进入任何界面）。
	MENU,       ## 主菜单。
	PLAYING,    ## 局内进行中（含被模态 UI 覆盖但未暂停菜单的情况）。
	PAUSED,     ## 暂停菜单打开。
	GAME_OVER,  ## 死亡 / 通关结算界面。
}

## 合法转移表。数字键是源状态，值是允许到达的目标状态集合。
##
## 【为什么用表而不是散落的 if】把"哪些转移合法"变成**数据**，可被测试直接断言，
##   也让人一眼看清整个局面流转图。非法转移会在 `request()` 里被拒绝并告警。
const LEGAL_TRANSITIONS: Dictionary = {
	State.BOOT: [State.MENU, State.PLAYING],
	State.MENU: [State.PLAYING, State.BOOT],
	State.PLAYING: [State.PAUSED, State.GAME_OVER, State.MENU],
	State.PAUSED: [State.PLAYING, State.MENU, State.GAME_OVER],
	State.GAME_OVER: [State.PLAYING, State.MENU],
}

## 状态中文名（日志 / 测试可读）。
const STATE_NAMES: Dictionary = {
	State.BOOT: "BOOT",
	State.MENU: "MENU",
	State.PLAYING: "PLAYING",
	State.PAUSED: "PAUSED",
	State.GAME_OVER: "GAME_OVER",
}

# ============================================================================
# 常量
# ============================================================================

## 主菜单 BGM 的场景路径（主菜单自己的音乐，与关卡无关）。
const MENU_MUSIC_PATH: String = "res://assets/audio/music/1 - Adventure Begin.ogg"

## 主菜单音乐在 AudioManager 里的归属。
const MENU_MUSIC_OWNER: StringName = &"menu"

## 回主菜单时需要强制收起的常驻 UI 节点名。
##
## 【为什么是 Array 而不是 PackedStringArray】const 的取值必须是编译期常量表达式，
##   `PackedStringArray([...])` 是构造调用，不算常量（会报 "isn't a constant
##   expression"）；字面量数组可以。遍历时元素就是 String，够用。
const TRANSIENT_UI: Array[String] = [
	"InventoryUI",
	"HelpPanel",
	"SettingsPanel",
	"ModifierChoice",
	"GameOverUI",
	"DialogUI",
	"TutorialUI",
]

## 只在"局内"显示、回主菜单时必须收起的常驻 UI。
##
## 【为什么和 TRANSIENT_UI 分开】HUD / Boss 血条没有 force_close()，只靠
##   `set_active(false)` 收起；而且**进入关卡时必须重新显示**。若把它们塞进
##   TRANSIENT_UI，start_run 调用的 teardown(false) 也会把 HUD 关掉，
##   而没有任何代码再开回来 —— 玩家进关后没有血条、没有技能栏。
const GAMEPLAY_UI: Array[String] = [
	"HUD",
	"BossHealthBar",
]

# ============================================================================
# 信号
# ============================================================================

## 局面发生变化。参数为 (旧状态, 新状态)。
signal state_changed(from: State, to: State)

# ============================================================================
# 私有变量
# ============================================================================

## 当前局面。初始为 BOOT，装配完成后由 Boot 驱动进入 MENU / PLAYING。
var _state: State = State.BOOT
## 最近一次挂上的主菜单节点（`teardown_to_menu` 返回用）。
var _main_menu: Node

## 主菜单"新的冒险"使用的起始关卡 / 入口。由 Boot 在进入 MENU 前配置，
## 建菜单时写进其 @export（保持"关卡配置由入口提供"的单一来源）。
var start_level: StringName = &"town"
var start_entry: StringName = &"start"

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


# ============================================================================
# 公开方法 —— 状态查询
# ============================================================================

## 当前局面。
func state() -> State:
	return _state


## 当前局面的中文名（日志 / 测试）。
func state_name(value: int = -1) -> String:
	var s: int = _state if value < 0 else value
	return STATE_NAMES.get(s, "UNKNOWN")


## 是否处于"局内"（进行中或暂停中）。
func is_playing() -> bool:
	return _state == State.PLAYING or _state == State.PAUSED


## 是否处于主菜单。
func is_in_menu() -> bool:
	return _state == State.MENU


## 目标局面是否可由当前局面合法到达。
func can_transition(to: State) -> bool:
	if to == _state:
		return true
	var allowed: Array = LEGAL_TRANSITIONS.get(_state, [])
	return allowed.has(to)


# ============================================================================
# 公开方法 —— 状态转移
# ============================================================================

## 请求转移到目标局面。返回 true 表示转移已发生（或目标即当前）。
##
## 【非法转移的处理】打印告警并返回 false，**不改变状态**。宁可让调用方看到
##   一次失败，也不要静默进入一个说不清的局面。测试可直接断言返回值。
func request(to: State) -> bool:
	if to == _state:
		return true
	if not can_transition(to):
		push_warning("[GameFlow] 非法转移被拒绝：%s → %s（允许：%s）" % [
			state_name(), state_name(to), str(LEGAL_TRANSITIONS.get(_state, []))])
		return false
	var from: State = _state
	_exit_state(from, to)
	_state = to
	_enter_state(to, from)
	state_changed.emit(from, to)
	return true


## 暂停菜单打开 / 关闭时由 PauseMenu 通知。
##
## 【为什么不由 GameFlow 直接 freeze】暂停的唯一真相是 PauseManager 的令牌集合。
##   PauseMenu 负责 freeze/unfreeze；这里只同步"局面"记录，避免出现两套真相。
##
## 【为什么非法时静默而不是告警】模态 UI（教程/背包等）会在没有暂停菜单时也冻结游戏树，
##   而它们不该把局面改成 PAUSED。只有"暂停菜单"这一种来源才代表 PAUSED 局面，
##   所以仅当处于 PLAYING ⇄ PAUSED 时才更新，其它情况按"与局面无关"静默忽略。
func set_paused(paused: bool) -> void:
	if paused:
		if _state == State.PLAYING:
			request(State.PAUSED)
	elif _state == State.PAUSED:
		request(State.PLAYING)


## 结算界面显示时由 GameOverUI 通知（死亡 / 通关都算 GAME_OVER 局面）。
## 仅当正在局内时才转移；否则静默忽略（例如测试单独调用结算面板）。
func notify_game_over() -> void:
	if is_playing():
		request(State.GAME_OVER)


# ============================================================================
# 公开方法 —— 局面生命周期入口
# ============================================================================

## 开始一局（新档 / 继续游戏 / 死亡重开 / 跳过菜单都走这里）。
##
## 【为什么先清理再进关】可能从 MENU 或 GAME_OVER 进入，先做一次完整清理，
##   保证新局不带任何上一局残留（弹窗队列、教程状态、旧关卡引用、暂停令牌）。
func start_run(level_id: StringName, entry_point: StringName = &"") -> void:
	_cleanup_run()
	# teardown 不负责局内 UI 可见性（见 GAMEPLAY_UI 注释），这里显式摆回局内状态。
	_set_gameplay_ui_visible(true)
	GameState.start_run()
	# 先记录局面再加载关卡：加载是协程，期间任何查询都应看到 PLAYING。
	if _state != State.PLAYING:
		request(State.PLAYING)
	SceneDirector.change_to_level(level_id, entry_point)


## 回主菜单：完整清理 + 挂主菜单。返回挂好的菜单节点（测试用）。
##
## load_menu_music：
##   true  —— 真正回主菜单：清理 + 停关卡 BGM + 播菜单曲 + 收起局内 UI + 挂主菜单，
##            并把局面转移到 MENU。
##   false —— 只做"进关前的清理"：清暂停令牌 / 弹窗 / 教程 / 关卡引用，不动可见性与 BGM，
##            也不改局面（供 start_run 内部与测试使用）。
func teardown_to_menu(load_menu_music: bool = true) -> Node:
	_cleanup_run()
	if not load_menu_music:
		return null
	if _state != State.MENU:
		request(State.MENU)
	return _main_menu


## 主菜单 BGM 流。找不到文件时返回 null（AudioManager 会静默忽略）。
func load_menu_music_stream() -> AudioStream:
	if not ResourceLoader.exists(MENU_MUSIC_PATH):
		return null
	return load(MENU_MUSIC_PATH) as AudioStream


# ============================================================================
# 私有方法 —— 状态进入 / 离开
# ============================================================================

func _exit_state(from: State, _to: State) -> void:
	# 离开 PAUSED 时确保暂停令牌被交还（若暂停菜单没来得及关，兜底恢复运行）。
	if from == State.PAUSED:
		PauseManager.unfreeze(&"pause_menu")


func _enter_state(to: State, _from: State) -> void:
	match to:
		State.MENU:
			_enter_menu()
		State.PLAYING:
			_enter_playing()
		State.PAUSED:
			_enter_paused()
		State.GAME_OVER:
			_enter_game_over()
		_:
			pass


## 进入主菜单：停关卡 BGM、播菜单曲、收起局内 UI、挂主菜单。
func _enter_menu() -> void:
	AudioManager.stop_music()
	AudioManager.play_music_for(MENU_MUSIC_OWNER, load_menu_music_stream())
	_set_gameplay_ui_visible(false)
	_main_menu = _show_main_menu()


## 进入局内：确保局内 UI 激活（玩家/HUD 由 SceneDirector 与关卡负责）。
func _enter_playing() -> void:
	_set_gameplay_ui_visible(true)


## 进入暂停：PauseManager 的冻结由暂停菜单负责，这里只记录局面。
func _enter_paused() -> void:
	pass


## 进入结算：界面的显示由 GameOverUI 负责，这里只记录局面。
func _enter_game_over() -> void:
	pass


# ============================================================================
# 私有方法 —— 清理
# ============================================================================

## 清理上一局的跨场景残留。**这是"回主菜单"与"开始新局"共用的核心**。
##
## 【顺序很关键】
##   0) 先作废在途场景切换：暂停菜单/结算界面可能在一次转场进行中就被点"返回主菜单"。
##      detach_level() 会 +1 代次，令还卡在 await 上的 change_to_level 协程醒来后退出，
##      不再把关卡/BGM/玩家挂回来。
##   1) 暂停令牌全清：换局了，旧窗口的持有都失效。
##   2) 收起局内瞬态 UI（背包/帮助/设置/三选一/结算/对话/教程），优先走各自 force_close。
##   3) 弹窗队列作废（回调多指向即将释放的关卡对象）。
##   4) 教程跨场景状态复位。
##   5) 停关卡 BGM（若接下来不进关，会由 _enter_menu 补菜单曲）。
func _cleanup_run() -> void:
	SceneDirector.detach_level()
	PauseManager.clear_all()

	for name: String in TRANSIENT_UI:
		var ui: Node = UIRegistry.find_by_name(name)
		if ui == null:
			continue
		if ui.has_method(&"force_close"):
			ui.call(&"force_close")
		else:
			_set_visible(ui, false)

	PopupManager.release_all()
	if _has_autoload(&"TutorialSystem"):
		var ts: Node = _autoload(&"TutorialSystem")
		if ts != null and ts.has_method(&"reset"):
			ts.call(&"reset")

	AudioManager.stop_music()


## 统一设置局内常驻 UI（HUD / Boss 血条）的可见性。
## 隐藏时优先走 set_active(false)，让它们停止每帧重绑并清掉对已释放玩家的引用。
func _set_gameplay_ui_visible(visible_on: bool) -> void:
	for name: String in GAMEPLAY_UI:
		var ui: Node = UIRegistry.find_by_name(name)
		if ui == null:
			continue
		if ui.has_method(&"set_active"):
			ui.call(&"set_active", visible_on)
		elif visible_on:
			_set_visible(ui, true)
		elif ui.has_method(&"force_close"):
			ui.call(&"force_close")
		else:
			_set_visible(ui, false)


## 写节点的 visible（不假设它是 CanvasItem：CanvasLayer 也支持该属性）。
func _set_visible(node: Node, value: bool) -> void:
	node.set(&"visible", value)


## 主菜单是每次现建的临时层；已经有了就复用并显示（防连点）。
func _show_main_menu() -> Node:
	var existing: Node = UIRegistry.find_by_name("MainMenu")
	if existing != null:
		_set_visible(existing, true)
		_main_menu = existing
		return existing
	if not ResourceLoader.exists("res://scenes/ui/main_menu.tscn"):
		push_error("[GameFlow] 找不到主菜单场景")
		return null
	var menu: Node = (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate()
	menu.name = "MainMenu"
	# 主菜单需要知道起始关卡（由 Boot 在进入 MENU 前配置到 GameFlow）。
	menu.set("start_level", start_level)
	_main_menu = menu
	# 挂到 Menus 容器（与其它菜单层同属一层），Boot._ready 阶段用 deferred 入树。
	UIRegistry.menus_container().add_child.call_deferred(menu)
	return menu


func _has_autoload(name: StringName) -> bool:
	return get_tree() != null and get_tree().root.get_node_or_null(NodePath(name)) != null


func _autoload(name: StringName) -> Node:
	return get_tree().root.get_node_or_null(NodePath(name))
