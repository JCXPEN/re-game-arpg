## TutorialUI —— 新手教程提示面板
##
## 【负责什么】
##   在屏幕顶部居中显示教程文字，带一个可选的图标。教程**只有这一条显示通道**，
##   不再同时往对话框发一份（旧实现里同一句话会在屏幕上下各出现一次）。
##   只有"需要玩家按键确认"的步骤才显示按键提示；自动消失的步骤不显示，
##   免得等于在骗玩家按键盘。
##   它只监听 EventBus.tutorial_step_shown，不关心教程逻辑。
##
## 【必须能关 —— 统一关闭契约】
##   玩家随时可以关掉本窗口（判定集中在 PopupManager，全项目一致）：
##     · 用鼠标**左键点窗口内任意位置**（不只是 ✕ 按钮）+ 右键快捷退出
##     · 按 **J** / **回车**（阻塞型步骤：世界已停，J/空格都没别的含义）
##     · 非阻塞型步骤只认**回车**：此时世界还在跑，J 是普攻、空格是翻滚，
##       用统一关闭键会把这两个操作吃掉（"翻滚按了没反应"）。
##   另有 auto_hide 自动消失兜底。这是硬性要求——开场教程无论怎么写，
##   **都要能让玩家主动跳过**；任何"必须等到 N 秒后才消失"的步骤都至少
##   留一条玩家主动可用的退出路径，否则就把玩家永久锁死了。
##
## 【为什么不接"点窗口外面关闭"】
##   想接就得让 Root 变成 mouse_filter=STOP 的全屏透明层，而 Root 是常驻挂载的
##   ——那等于给整个游戏糊一层看不见的膜，吞掉所有鼠标点击（"游戏没法运行"的
##   根因，见 git 历史）。所以只认"窗口内"，窗口外照常穿透，游戏该玩还是能玩。
##
## 【阻塞与否由数据决定 —— TutorialStep.pause_game】
##   · pause_game = true（系统级重要提示）：冻结游戏树 + 独占弹窗位置，
##     关闭后精确还原。冻结走 PauseManager 令牌并声明 `Cover.WORLD`：
##     **世界停一下、屏幕仍归下层** —— 于是对话条在被冻住的世界里照常显示
##     （"一冻结就把 NPC 的话丢掉"是被修掉的病灶）。本窗口靠
##     process_mode = ALWAYS 在暂停中继续收输入 —— 这就是"区分游戏树"：
##     停的是游戏世界，活的是弹窗。
##   · pause_game = false（操作类提示，例如"靠近村民按 [F] 交谈"）：**不冻结、不占屏**。
##     它只是一个浮层，玩家可以边走边打边读，NPC 对话照常弹出。
##   · 带 trigger_action 的步骤即使 pause_game = true 也会被系统拒绝冻结
##     （冻结会让完成条件永远达不成），所以本窗口的"是不是阻塞窗口"必须问系统
##     （见 _is_blocking_step），不能自己读 pause_game 猜。
##
##   【为什么不能一律冻结】旧实现无条件冻结 + 无条件抢弹窗位置，于是"与 NPC 交谈"
##   这一步在它自己的提示期间根本做不到：世界暂停 → NPC 的 Area2D 收不到玩家进入；
##   就算强制交互，对话请求也会被 PopupManager 排进队列 —— 玩家按 F 毫无反应，
##   过几秒提示自己消失后对话才"迟到的冒出来"。
##   冻结的唯一所有者是 TutorialSystem（按 pause_game 决定），本窗口只负责画与收。
##
## 【挂哪个节点】
##   scenes/ui/tutorial_ui.tscn 的根节点（CanvasLayer），由 Boot 常驻挂载。
##
## 【依赖谁】
##   EventBus.tutorial_step_shown。
class_name TutorialUI
extends CanvasLayer

# ============================================================================
# @export
# ============================================================================

## 面板容器。
@export var panel_path: NodePath
## 标题文字（可空，用于需要强调的步骤）。
@export var title_label_path: NodePath
## 正文文字。
@export var label_path: NodePath
## 图标。
@export var icon_path: NodePath
## 需要按键确认时显示的提示。
@export var hint_path: NodePath
## "关闭 / 跳过"按钮（可空，但强烈建议连）。
@export var close_button_path: NodePath
## 点击空白处关闭用的根（一般 = panel 自身）。
@export var dismiss_area_path: NodePath

# ============================================================================
# 常量
# ============================================================================

## 本窗口在 PopupManager 里的身份 id（互斥 / 排队用）。仅阻塞型步骤会占用它。
const POPUP_ID: StringName = &"tutorial"

# ============================================================================
# 私有变量
# ============================================================================

var _panel: Control
var _title: Label
var _label: Label
var _icon: TextureRect
var _hint: Label
var _close_btn: Button
var _dismiss_area: Control
## 当前教程面板的底边 y（画布坐标）。没有面板时为 0。
##
## 【为什么对外暴露】HUD 的 Toast（"[F] 交谈"、拾取提示）固定在顶部 y=40，
## 而教程面板也画在顶部 —— 面板一展开就会把 Toast 埋在背后，玩家看不到
## "[F] 交谈"的提示（这正是"走近村民却不知道按 F / NPC 窗口出不来"体感的来源之一）。
## HUD 每帧读这个值，把自己的 Toast 排到面板**下方**（与 DialogUI.notice_bottom 同一套机制）。
static var panel_bottom: float = 0.0

## 当前正在显示的步骤序号（-1 = 没有）。
var _current_step: int = -1
## 当前步骤是否要求玩家手动确认。
var _current_require_confirm: bool = false
## 当前步骤是否为"系统级阻塞"（冻结游戏 + 独占弹窗位置）。
## 由 TutorialSystem 按 TutorialStep.pause_game 判定，见文件头说明。
var _current_blocking: bool = false
## 淡出补间。
var _tween: Tween
## 当前步骤有没有被玩家主动关掉（被关掉就不让"auto_hide"再回填）。
var _dismissed_by_player: bool = false
## 待显示的步骤内容。被别的窗口挡住时先存这儿，轮到自己再显示
## ——直接覆盖会丢掉前一个窗口的结算回调。
var _pending: Dictionary = {}

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	# 即使游戏被暂停（如暂停菜单弹出时）也要响应输入并能关掉。
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not panel_path.is_empty():
		_panel = get_node_or_null(panel_path) as Control
	if not title_label_path.is_empty():
		_title = get_node_or_null(title_label_path) as Label
	if not label_path.is_empty():
		_label = get_node_or_null(label_path) as Label
	if not icon_path.is_empty():
		_icon = get_node_or_null(icon_path) as TextureRect
	if not hint_path.is_empty():
		_hint = get_node_or_null(hint_path) as Label
	if not close_button_path.is_empty():
		_close_btn = get_node_or_null(close_button_path) as Button
	if not dismiss_area_path.is_empty():
		_dismiss_area = get_node_or_null(dismiss_area_path) as Control
	if _close_btn != null:
		_close_btn.pressed.connect(_on_close_pressed)
	if _dismiss_area != null:
		# 点窗口内任意处即可关闭（左键走统一契约，右键是快捷退出）。
		# 面板里的 ✕ 按钮会自己吃掉落在它身上的点击，不会重复触发关闭。
		_dismiss_area.gui_input.connect(_on_dismiss_input)
	if _panel != null:
		_panel.visible = false
		# 兜底复位：场景从 .tscn 实例化时，作者可能把 modulate.a 调成 0 做淡入用。
		# 不显式归位就会出现"窗口显示着却全透明"的幽灵面板。
		_panel.modulate.a = 1.0
	_set_hint_visible(false)
	# Esc 交给 UIInputRouter 集中仲裁（本窗口不再自己监听，避免和暂停菜单抢）。
	add_to_group(UIInputRouter.GROUP)
	# 登记进 UI 注册表：调用方按 id 访问，不再按树路径查名。
	UIRegistry.register(&"tutorial", self)
	EventBus.tutorial_step_shown.connect(_on_step_shown)


func _process(_delta: float) -> void:
	# 面板底边每帧上报：面板会随文本换行 / 入场动画改变高度，
	# 而 HUD 的 Toast 必须一直待在它下面（本层是 ALWAYS，冻结期间也照常上报）。
	if _panel != null and _panel.visible:
		panel_bottom = _panel.get_global_rect().end.y
	elif panel_bottom != 0.0:
		panel_bottom = 0.0


# ============================================================================
# UIInputRouter 契约
# ============================================================================

## 本窗口在 Esc 路由里的层级：教程是最优先的阻塞窗口。
func ui_layer_priority() -> int:
	return UIInputRouter.LAYER_TUTORIAL


## 是否阻塞型窗口。
## 只有"系统级阻塞"步骤（pause_game = true）才算：操作类提示是浮层，
## 不该拦下 Esc、也不该拦住别的窗口。
func is_blocking_ui() -> bool:
	return _panel != null and _panel.visible and _current_step >= 0 and _current_blocking


## 窗口标识。
func ui_window_id() -> StringName:
	return POPUP_ID


## 轮到本窗口处理 Esc：关掉当前步骤。
##
## 【为什么返回 true 即便没步骤可关】只要本窗口在屏幕上，Esc 就不该穿透到
##   下层去开暂停菜单 —— 否则玩家想跳过一句提示，结果弹出暂停菜单，
##   两个窗口叠在一起（这正是修复前的实测现象）。
func route_esc() -> bool:
	if _current_step < 0:
		return true
	dismiss_current()
	return true


## 回主菜单时强制收起（不推进教程系统，因为整局都要重置了）。
##
## 【为什么必须把 modulate.a 也复位】上面 _hide() 的教训：一旦有过一次在
##   paused 期间发起的淡出，modulate.a 可能停在中途（甚至 0）。这里只设
##   visible=false 的话，下次窗口再显示时会是**半透明/全透明**的"幽灵窗口"。
##   隐藏 + 不透明度复位必须成对，否则状态会跨局累积。
func force_close() -> void:
	_dismissed_by_player = true
	_current_step = -1
	_current_blocking = false
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if _panel != null:
		_panel.visible = false
		_panel.modulate.a = 1.0
	_set_hint_visible(false)
	if _close_btn != null:
		_close_btn.visible = false
	# 交还弹窗位置（没占过也是无害的 no-op）。解冻由 TutorialSystem.reset() 负责。
	PopupManager.release(POPUP_ID)


# ============================================================================
# 输入
# ============================================================================

func _unhandled_input(event: InputEvent) -> void:
	# 教程没在显示就别吞按键。
	if _panel == null or not _panel.visible or _current_step < 0:
		return
	# 鼠标点击一律交给面板的 gui_input / 按钮，这里只管键盘。
	if event is InputEventMouseButton:
		return
	# 【Esc 为什么不在这里处理】曾经这里判了 ui_cancel，但 Godot 的
	#   _unhandled_input 是广播：PauseMenu（最后挂载 → 最先收到）会先把 Esc
	#   吃掉并弹出暂停菜单，本窗口永远等不到。现在 Esc 统一交给
	#   UIInputRouter 仲裁（见路由契约区的 route_esc）。
	#
	# 【阻塞型】世界已经停了，J / 回车都不会被游戏消费，直接按统一契约关掉。
	if _current_blocking:
		if PopupManager.is_close_key(event):
			dismiss_current()
			get_viewport().set_input_as_handled()
		return
	# 【非阻塞型】世界还在跑：此刻 J = 普攻、空格（= ui_accept）= 翻滚。
	# 若照搬统一关闭键，玩家一边读提示一边打架时会遇到"翻滚/攻击按了没反应"。
	# 所以这里只认**回车**（游戏里没有任何绑定）；点击面板 / ✕ / 自动消失照旧。
	if event is InputEventKey:
		var k: InputEventKey = event as InputEventKey
		if k.pressed and not k.echo \
				and (k.keycode == KEY_ENTER or k.physical_keycode == KEY_ENTER
					or k.keycode == KEY_KP_ENTER or k.physical_keycode == KEY_KP_ENTER):
			dismiss_current()
			get_viewport().set_input_as_handled()


# ============================================================================
# 私有方法
# ============================================================================

## step_index < 0 表示收起；require_confirm 决定要不要显示按键提示。
func _on_step_shown(step_index: int, title: String, text: String, require_confirm: bool) -> void:
	if _panel == null:
		return
	# 兼容旧的"清场"信号：标题和正文都空 → 收起。
	if step_index < 0 or (title.strip_edges() == "" and text.strip_edges() == ""):
		_hide()
		return
	_pending = {
		"step": step_index,
		"title": title,
		"text": text,
		"confirm": require_confirm,
	}
	# 【只有阻塞型步骤才抢弹窗位置】
	#   阻塞型（系统级）：互斥 —— 屏幕上已经有**别的**窗口就排队等它关掉，绝不覆盖
	#   （覆盖会静默丢掉前一个窗口的结算回调）。同一个 id（教程自己连着走下一步）
	#   视为"刷新内容"，直接显示。
	#   非阻塞型（操作提示）：直接显示、不占位。抢位会把 NPC 对话、路牌提示排进队列，
	#   玩家按 F 看起来毫无反应 —— 而"靠近村民按 F 交谈"这类提示恰恰要求玩家能交互。
	if not _is_blocking_step():
		_show_pending()
		return
	if PopupManager.try_acquire(POPUP_ID):
		_show_pending()
	else:
		PopupManager.enqueue(POPUP_ID, PopupManager.PRIORITY_TUTORIAL, _show_pending)


## 真正把 _pending 里的这一步画到屏幕上。
## 可能是"立刻"，也可能是"等前面那个窗口关掉之后"才被 PopupManager 叫醒。
func _show_pending() -> void:
	if _pending.is_empty() or _panel == null:
		return
	var title: String = _pending["title"]
	_current_step = _pending["step"]
	_current_require_confirm = _pending["confirm"]
	_current_blocking = _is_blocking_step()
	_dismissed_by_player = false
	if _title != null:
		_title.visible = not title.is_empty()
		_title.text = title
	if _label != null:
		_label.text = _pending["text"]
	_set_hint_visible(_current_require_confirm)
	if _close_btn != null:
		_close_btn.visible = true
	_panel.visible = true
	_panel.modulate.a = 1.0
	# 轻微上浮入场，吸引注意但不打断操作。
	_panel.position.y += 6.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	# 入场动画也挂 ALWAYS：阻塞型步骤在 TutorialSystem 那边已经把游戏停住了，
	# 若 tween 是 PAUSABLE 的，它会刚建好就被冻住（面板停在偏移 6px 处）。
	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(_panel, "position:y", _panel.position.y - 6.0, 0.25)
	# 【冻结不在这里做】由 TutorialSystem 按 TutorialStep.pause_game 统一决定
	# （见文件头）：本窗口只负责画与收，避免同一个暂停令牌被两个模块各冻/各解一次。


## 窗口内的关闭手势：左键（统一契约）+ 右键（快捷退出）。
##
## 【为什么现在左键也关】
##   旧实现只认右键，玩家用最直觉的左键点面板毫无反应
##   ——这正是"教程窗口关不掉"的体感来源。现在左键是统一关闭契约的一部分。
##   （教程弹出时游戏本来就是冻结的，不存在"一边跑一边误关"的问题了。）
##
## 【和 ✕ 按钮为什么不冲突】
##   ✕ 是按钮，处理按下时 BaseButton 会自己 accept_event()，
##   事件不再冒泡到面板，所以点 ✕ 只走按钮自己的关闭，不会关两次。
##
## 【为什么不用全屏 dimmer 做"点空白处关闭"】
##   曾经把 Root 设成 mouse_filter=STOP，结果 Root 是全屏且常驻挂载的
##   ——游戏一启动就多了一层透明膜吞掉所有鼠标点击（"游戏没法运行"的根因）。
##   所以 Root 永远保持 IGNORE，只有面板这一小块接收点击。
func _on_dismiss_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if PopupManager.is_close_click(event) or mb.button_index == MOUSE_BUTTON_RIGHT:
		dismiss_current()
		get_viewport().set_input_as_handled()


func _on_close_pressed() -> void:
	dismiss_current()


## 玩家主动关闭当前步骤。
##
## 同步调用 TutorialSystem.dismiss_current_step()：UI 收起的同时让教程系统
## 把 _active 复位并推进到下一步（前提是 TutorialSystem 已在 autoload 里）。
## 不能只关 UI —— 不然教程系统还以为"还在播放"，等几秒一拍脑袋又 _advance，
## 体感是"明明关了又自己冒出来"。
func dismiss_current() -> void:
	if _current_step < 0:
		return
	_dismissed_by_player = true
	_current_step = -1
	# _hide() 内部负责：解冻游戏 + 把 PopupManager 的位置让出来
	# （两件事都做了，下一个排队的窗口才轮得到）。
	_hide()
	# 通知系统推进。注意：必须在 _hide() 之后调用，避免 UI 信号再次回调到这里。
	if Engine.has_singleton(&"TutorialSystem") or _has_autoload(&"TutorialSystem"):
		var ts: Node = _get_tutorial_system()
		if ts != null and ts.has_method(&"dismiss_current_step"):
			ts.call(&"dismiss_current_step")


func _has_autoload(name: StringName) -> bool:
	# 检查 root 的 autoload 注册表里有没有这个名字。
	# 直接访问 SceneTree.root 而不是用全局名，避免单例未挂时崩溃。
	var root: Node = get_tree().root if get_tree() != null else null
	if root == null:
		return false
	for n: Node in root.get_children():
		if n.name == name:
			return true
	return false


func _get_tutorial_system() -> Node:
	var root: Node = get_tree().root if get_tree() != null else null
	if root == null:
		return null
	for n: Node in root.get_children():
		if n.name == &"TutorialSystem":
			return n
	return null


## 按键提示只在"确实需要按键"的步骤出现。
func _set_hint_visible(shown: bool) -> void:
	if _hint != null:
		_hint.visible = shown


## 隐藏并彻底复位。
##
## 【为什么必须在建 tween 之前先把 visible 关掉 —— 这是实测抓出来的严重 bug】
##   旧实现是"先建 0.3s 淡出 tween，在 tween_callback 里再设 visible = false"。
##   但本窗口是**系统级窗口**，显示期间 `get_tree().paused == true`，而
##   `create_tween()` 默认绑在 PAUSABLE 的节点上 → **tween 根本不会推进**。
##   后果：_unfreeze_game() 已经执行（游戏恢复运行），但回调永远不触发，
##   `_panel.visible` 永远停在 true、`modulate.a` 永远停在 0。
##   玩家看到的是"窗口没了，却像有块透明玻璃挡着屏幕"，
##   切到主菜单后还叠着一层透明层 —— 这就是"回主菜单后 UI 渲染/状态错乱"。
##   所以：状态（visible / modulate）同步改完，tween 只做锦上添花的淡出。
func _hide() -> void:
	if _panel == null:
		return
	_current_step = -1
	_current_blocking = false
	_set_hint_visible(false)
	if _close_btn != null:
		_close_btn.visible = false
	# 交还弹窗位置。非阻塞步骤从没占过位置，release 对未占用的 id 是无害 no-op。
	# 解冻不在这里做：冻结令牌的唯一所有者是 TutorialSystem（见其 _sync_pause()，
	# 它会随 UI 关闭而把状态同步为"不冻"）。
	PopupManager.release(POPUP_ID)
	# 先同步复位（不依赖 tween 是否还在跑），再补一个淡出动画。
	_panel.visible = false
	_panel.modulate.a = 1.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	# tween 挂到 ALWAYS 上，避免在"尚未解冻"的调用路径里被卡住。
	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(_panel, "modulate:a", 0.0, 0.15)


## 当前这一步是否属于"系统级阻塞"（冻结游戏 + 独占弹窗位置）。
##
## 问 TutorialSystem 要答案，而不是在本窗口里猜：
##   冻结与独占都属于"这一步要不要玩家停下来"的语义，而那是 TutorialStep.pause_game
##   的数据；让唯一的所有者（TutorialSystem）回答，两个模块才不会各说各话。
##
## 没有 TutorialSystem（单测里裸挂本 UI、或系统未启动）→ 一律视为**非阻塞**：
## 宁可少冻结一次，也不要"谁都不负责解冻"地把游戏冻住。
func _is_blocking_step() -> bool:
	var ts: Node = _get_tutorial_system()
	if ts != null and ts.has_method(&"is_current_step_blocking"):
		return bool(ts.call("is_current_step_blocking"))
	return false
