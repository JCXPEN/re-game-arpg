## DialogUI —— 对话框（常驻 UI）：**提示条**与**对话条**两条互不干扰的通道
##
## 【负责什么】
##   把"要显示的字"按语义分成两条通道。旧实现只有一条队列，于是提示和对话
##   互相顶掉（教程提示会打断 NPC 对话、并且把对话的结算回调丢掉）。
##
##   1. **提示条 Notice（完全非阻塞）** —— `EventBus.dialog_requested(text, duration)`
##      路牌、系统提示走这里。顶部居中细条，不暂停、不锁输入、不发 dialog_opened，
##      玩家可以边走边看、边打边看。关闭途径有三条，任一条都能关掉：
##        · 点击提示条本身   · 到时自动消失   · 超过 notice_max_lifetime 硬上限
##      → 结构上不可能"赖着死不掉"。
##
##   2. **对话条 Bar（半阻塞）** —— `EventBus.dialog_script_requested(script, cb)`
##      或兼容入口 `EventBus.dialog_sequence_requested(speaker, lines, cb)`。
##      NPC 多句对话走这里。底部细条，逐句推进，播完回调结算奖励。
##      关闭方式走**全项目统一契约**（判定集中在 PopupManager）：
##        · 按 **J** / 按 **回车** / 鼠标**左键点条内任意处** → 关闭（= 取消，不结算）
##        · 点"继续 / 关闭"按钮 → 推进（按钮自己 accept_event()，不和关闭打架）
##        · 按 **F** → 推进（对话条原本的交互语义，保留）
##        · 右键 → 直接结束
##
## 【内容从哪来：结构化对话】
##   对话内容不再是"一串裸字符串"，而是 `DialogueScript`（整段）+ `DialogueLine`（逐句）：
##     · 每句可单独指定**说话人 / 文本样式 / 显示方式 / 打字速度 / 语音**
##     · 每句可带**立绘 / 头像 / 头像位置 / 表情状态**（`PortraitSlot`，已接渲染挂点）
##     · 整段可设默认说话人、默认立绘与表情、对话条样式、整段自动推进
##   本文件**只负责演**：把结构化数据翻译成"改哪个变体、显示几个字、什么时候往下走"。
##   排版数值（字号、行距、颜色）全部在 Theme；文案全部在 .tres。
##
## 【自适应排版：对话框不再是固定尺寸】
##   旧实现把对话条钉死成 176×48，于是：
##     · 短句（"你终于醒了"）也占满整条，右侧一大片空白；
##     · 长句在 166px 的文字区里一行只放得下 ~13 个汉字，硬生生堆到 11 行，
##       面板一路长到 210px 高、顶边跑到 y = **-52**（半个对话框在屏幕外），
##       连"说话人 + 继续按钮"那一行都被顶出可视区 —— 关都关不掉。
##   现在：**先量字，再定框**。
##     · 宽度：按整句的自然宽度贴合（短句收窄），上限 `bar_max_width`（长句换行）；
##     · 高度：由内容撑开，底部锚定往上长；预测高度写进 custom_minimum_size，
##       避免"先按旧尺寸画一帧再跳"的抖动；
##     · 行数上限：单句超过 `bar_max_lines` 时**自动分页**（按标点断句，
##       均分成若干页，翻页就是正常的"继续"），于是任何长度的文本都不会溢出、
##       也不会出现"要滚动才能看完"的对话框。
##
## 【互斥】
##   对话条与教程 / 帮助窗口**不能同时出现**。屏幕上已有别的窗口时，
##   新来的这一段进 PopupManager 的队列（按优先级），等前一个关闭后再显示；
##   绝不覆盖——覆盖会静默丢掉前一个窗口的结算回调。
##   提示条（Notice）是非阻塞 toast，不受互斥约束，见 PopupManager 文件头。
##
## 【为什么不再全局锁输入】
##   旧代码让 Player / Interactable 读静态 `is_open` 来"让出 F 键与移动"，
##   一旦对话框因为换场景 / 玩家死亡 / 回调指向已释放对象而没能关闭，
##   新关卡的玩家就会**一出生就被永久锁住移动与攻击**（这就是"卡游戏进程"）。
##   现在对话条只做一件互斥：**吞掉重复的 interact**，防止一句话被反复重开；
##   其余一律不拦——玩家随时可以走开，走出 cancel_distance 对话自动结束。
##   对话永远不夺取控制权，这是本期最重要的一条手感。
##
## 【窗口开着 = 世界停着】
##   对话条是**模态窗口**：它显示期间通过 PauseManager 持有冻结令牌（`Cover.WORLD`：
##   只停世界，不遮屏幕），于是
##     · 玩家**不能**一边读对话一边跑动 / 挨打（读对话时被敌人围殴是"窗口存在时
##       还能移动受伤"这类反馈的直接来源）；
##     · 对话也**不会**因为玩家走动而被"走远即取消"瞬间收掉 —— 那是"NPC 窗口
##       根本没出现"的体感来源（窗口闪一下就没了）。
##   关闭入口在冻结期间全部可用（J / 回车 / 点条 / F / 右键 / 关闭按钮，本层是
##   PROCESS_MODE_ALWAYS），关掉即恢复运行 —— 旧实现"对话锁输入导致永久卡死"的
##   病根不在这里：那条旧 bug 是"改输入而不持令牌"，谁都能把状态改坏；
##   现在冻结是 PauseManager 的令牌，唯一所有者 + 多条强制收尾 + 死持有者回收兜底。
##
## 【所有"异常退出"都会强制收尾】
##   换关卡(EventBus.scene_changed) / 玩家死亡(player_died) / **被独占屏幕的窗口盖住**
##   (PauseManager.covers_screen()) / 玩家走远(兜底) —— 这些情况都调用
##   cancel_conversation()，保证 `is_open` 与冻结令牌都不会跨场景残留。
##
## 【奖励回调不会丢】
##   正常推进到结束 → 调用 on_finished 结算奖励；
##   中途被打断（走开 / 换场景 / 死亡）→ 明确取消，**不**结算，
##   NPC 也不会因此消耗掉 `once`，玩家可以再谈一次。
##
## 【顶部两条消息会打架吗（实测过）】
##   HUD 的 Toast（"[F] 交谈"、拾取提示）也在顶部居中。提示条往下长时会压住它，
##   实测 3 行提示条（y 6..66）就盖住了固定 y=40 的 Toast。所以本文件额外暴露
##   `notice_bottom()`：HUD 据此把自己的 Toast 排在提示条**下方**，两者永不重叠。
##   两个都是临时消息，谁先来谁在上面，不需要更复杂的调度。
##
## 【挂哪个节点】
##   scenes/ui/dialog_ui.tscn 的根节点（CanvasLayer），由 Boot 常驻挂载。
##   场景节点约定（**改结构前先看 `tools/*_test.gd`，这些路径是测试契约**）：
##     Root/Notice/NoticeText                            提示条
##     Root/Bar/VBox/Header/Speaker                      说话人
##     Root/Bar/VBox/Header/Avatar                       小头像（预留，默认隐藏）
##     Root/Bar/VBox/Header/Action                       推进按钮
##     Root/Bar/VBox/Text                                对话正文
##     Root/Portrait                                     立绘（预留，默认隐藏）
##
## 【依赖谁】
##   EventBus（dialog_requested / dialog_sequence_requested / dialog_script_requested /
##   scene_changed / player_died）、PopupManager（互斥与统一关闭键）、AudioManager（逐字语音）。
##   两个纯助手协作类（不独立存在，随本窗口创建）：
##     DialogTypography —— 排版测量（量字 / 折行 / 分页 / 面板尺寸），见其文件头。
##     DialogTypewriter —— 打字机状态（此刻显示几个字），见其文件头。
class_name DialogUI
extends CanvasLayer

# ============================================================================
# 静态查询（供 Interactable / HUD / 测试零成本访问，不用先拿到节点引用）
# ============================================================================

## 对话条（多句对话）是否打开。Interactable 据此吞掉重复的 interact。
static var is_open: bool = false
## 提示条是否可见。**不**阻塞任何输入。
## 对外的语义是"顶部被提示条占着"，HUD 用它把自己的 Toast 排到提示条下面。
static var notice_open: bool = false
## 当前提示条的底边 y（画布坐标）。没有提示条时为 0。
## HUD 读它来避开提示条，见文件头【顶部两条消息会打架吗】。
static var notice_bottom: float = 0.0

# ============================================================================
# 常量
# ============================================================================

## 默认打字机速度（字符/秒）。可被 `DialogueLine.chars_per_sec` 逐句覆盖。
const CHARS_PER_SEC: float = 45.0

## 逐字语音的节奏：每显示这么多字响一次（避免每个字都响、变成机关枪）。
## 1 = 每个字都响；数值越大越稀。整句的音色由 `DialogueLine.voice_pitch` 决定。
const VOICE_EVERY: int = 3

## 本窗口（对话条）在 PopupManager 里的身份 id，互斥 / 排队用。
const POPUP_ID: StringName = &"dialog"

## 文本样式 → Theme 里的 Label 类型变体名。
## 定义在 DialogTypography（排版域）；这里保留静态转发 ——
## `DialogUI.variation_for` 是测试契约（dialogue_system_test 直接调用）。
static func variation_for(style: DialogueLine.Style) -> StringName:
	return DialogTypography.variation_for(style)

# ============================================================================
# @export —— 节点
# ============================================================================

@export_group("节点")
@export var notice_panel_path: NodePath
@export var notice_text_path: NodePath
@export var bar_panel_path: NodePath
@export var vbox_path: NodePath
@export var header_path: NodePath
@export var speaker_path: NodePath
@export var text_path: NodePath
@export var action_button_path: NodePath
@export var avatar_path: NodePath
@export var portrait_path: NodePath

# ============================================================================
# @export —— 手感
# ============================================================================

@export_group("手感")
## 玩家离开发起对话的位置超过这个距离（像素），对话自动结束。这是
## "随时能脱身"的兜底：不需要先找到关闭按钮，直接走开就行。
@export_range(8.0, 200.0, 1.0, "suffix:px") var cancel_distance: float = 26.0
## 提示条的硬上限（秒）。0 = 不限。设为正数可保证提示最迟在这个时间内消失
## ——即使某处把 duration 配成了 0（路牌"常驻"）。
@export_range(0.0, 120.0, 1.0, "suffix:s") var notice_max_lifetime: float = 20.0
## 被"独占屏幕"的窗口（暂停菜单 / 背包 / 三选一 / 结算 / 帮助…）盖住时，
## 是否自动收掉对话条与提示条。默认收掉 —— 它们自带全屏遮罩，会把本层压在下面，
## 那时对话"看不见也关不掉"，玩家只能强退。
##
## 【注意判据不是 get_tree().paused】"世界被冻住"与"有人盖住我"是两件事：
##   教程系统提示 / Boss 出场这类系统级冻结只声明 `Cover.WORLD`（世界停一下、
##   屏幕仍归下层），此时本条照常显示、照常能推能关 —— 见 PauseManager.Cover。
@export var close_when_paused: bool = true

# ============================================================================
# @export —— 自适应排版
# ============================================================================

@export_group("自适应排版")
## 对话条最小宽度（短句再短也不会比这个窄，避免出现"一个字一条"的碎片条）。
@export_range(64.0, 320.0, 1.0, "suffix:px") var bar_min_width: float = 108.0
## 对话条最大宽度。长句在这个宽度内换行。
@export_range(96.0, 320.0, 1.0, "suffix:px") var bar_max_width: float = 296.0
## 对话条离屏幕底边的距离（要垫在技能栏上方）。
@export_range(0.0, 120.0, 1.0, "suffix:px") var bar_bottom_margin: float = 22.0
## 单页最多显示几行正文。超长文本会按标点自动分页（翻页 = 正常的"继续"），
## 这样任何长度的文本都不会撑破屏幕、也不需要滚动。
@export_range(1, 12, 1) var bar_max_lines: int = 3
## 打字机每打出一个字是否让对话框抖一下（`DialogueLine.shake` 打开时生效）的强度。
@export_range(0.0, 4.0, 0.5, "suffix:px") var shake_amplitude: float = 1.0
## 提示条最小 / 最大宽度。上限刻意比对话条窄（70% vs 92%）：
## 提示条只是"路过看一眼"的次要消息，不该和对话正文抢同样的视觉分量。
@export_range(64.0, 320.0, 1.0, "suffix:px") var notice_min_width: float = 96.0
@export_range(96.0, 320.0, 1.0, "suffix:px") var notice_max_width: float = 224.0

# ============================================================================
# 私有变量
# ============================================================================

var _notice_panel: Control
var _notice_text: Label
var _bar_panel: Control
var _vbox: VBoxContainer
var _header: HBoxContainer
var _speaker_label: Label
var _text_label: Label
var _action_button: Button
var _avatar: TextureRect
var _portrait: TextureRect

## 展平后的"页"列表。每项：
##   {line: DialogueLine, text: String, first: bool, last: bool}
## first/last 表示这一页是不是"该行的第一页 / 最后一页"，用于决定
## 换行时才更新说话人与立绘、以及最后一行才结算奖励。
var _entries: Array[Dictionary] = []
## 当前页下标。
var _index: int = 0

## 整段对话（结构化）。由它派生说话人 / 立绘 / 表情的默认值。
var _script: DialogueScript
## 整段播完后的回调（可能为空 Callable）。
var _on_finished: Callable

## 排版测量助手与打字机状态（纯逻辑协作类，职责域拆分见各自文件头）。
var _typo: DialogTypography
var _tw: DialogTypewriter = DialogTypewriter.new()
## 是否正在打字。**镜像 _tw.typing** —— 测试契约在实例上读这个字段。
var _typing: bool = false
## 当前页的显示方式与参数。
var _display: DialogueLine.Display = DialogueLine.Display.TYPEWRITER
var _auto_delay: float = 1.6
var _auto_elapsed: float = 0.0
## 当前页所属的 DialogueLine（立绘 / 表情 / 语音都从它取）。
var _current_line: DialogueLine
## 逐字语音：已打了几个字（每 `VOICE_EVERY` 个响一次）。
var _voice_counter: int = 0

## 对话/提示的起算位置（玩家位置），用于"走远即消失"。
var _anchor: Vector2 = Vector2.ZERO
## 提示条已存活时间 / 配置时长（<=0 表示常驻，仍受硬上限与点击约束）。
var _notice_elapsed: float = 0.0
var _notice_duration: float = 0.0
## 玩家引用缓存（走远判断用）。
var _player: Node2D
## 待显示的整段对话。被别的窗口（教程/帮助）挡住时先存这儿，
## 轮到自己再显示——直接覆盖会丢掉前一个窗口的结算回调。
var _pending: Dictionary = {}

## 对话条的基准 offset（抖动要在此基础上叠加，不能无限累积）。
var _bar_base_offsets: PackedFloat32Array = PackedFloat32Array()
## 抖动计时。
var _shake_time: float = 0.0

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	# 打开背包 / 暂停菜单时游戏会被 pause，本界面必须能在暂停状态下响应
	# （否则提示条停住不走、按钮点不动 → 又变成"关不掉"）。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_resolve_nodes()
	# 排版查询优先用对话条面板（它自己不挂变体），没有则退回提示条 ——
	# 原因见 DialogTypography.theme_source 的说明。
	if _bar_panel != null:
		_typo = DialogTypography.new(_bar_panel)
	else:
		_typo = DialogTypography.new(_notice_panel)
	_hide_bar()
	_hide_notice()
	# 鼠标优先：面板自己吃掉左键 = 推进；提示条则左键 = 立即收起。
	if _bar_panel != null:
		_bar_panel.gui_input.connect(_on_bar_gui_input)
		# 记下基准 offset：抖动是"基准 + 偏移"，不能直接改基准本身。
		_bar_base_offsets = PackedFloat32Array([
			_bar_panel.offset_left, _bar_panel.offset_top,
			_bar_panel.offset_right, _bar_panel.offset_bottom])
	if _notice_panel != null:
		_notice_panel.gui_input.connect(_on_notice_gui_input)
	if _action_button != null:
		_action_button.pressed.connect(_on_action_pressed)
	EventBus.dialog_requested.connect(_on_dialog_requested)
	EventBus.dialog_sequence_requested.connect(_on_sequence_requested)
	EventBus.dialog_script_requested.connect(_on_script_requested)
	# 顶部只有一条消息的位置：**别的**窗口占屏时提示条让位（教程/帮助也是顶部面板，
	# 会和提示条画在同一块地方）。对话条在底部，**不**受这条影响 ——
	# "提示条与对话条可以同屏"是刻意设计，所以必须排掉本窗口自己的 id。
	PopupManager.popup_opened.connect(_on_popup_opened)
	# 异常退出兜底：换关卡 / 玩家死亡都必须收尾，否则对话框会跨场景赖着不走。
	EventBus.scene_changed.connect(_on_scene_changed)
	EventBus.player_died.connect(_on_player_died)
	# 登记进 UI 注册表：调用方按 id 访问，不再按树路径查名。
	UIRegistry.register(&"dialog", self)


func _process(delta: float) -> void:
	# 【只在"被独占屏幕的窗口盖住"时收掉，不再看见 paused 就一律收】
	#   旧判据是 `if get_tree().paused`：只要世界被冻住就杀掉对话。但"世界停了"
	#   和"有人盖住我"是两件事，误伤的后果很实在：
	#     · 教程的系统级提示（Cover.WORLD）一冻结，玩家正在读的整段 NPC 对话
	#       连同它的结算回调会被静默丢掉 —— 表现为"NPC 对话无法显示"、
	#       奖励也没发（NPC 的一次性奖励只能再谈一次才拿得到）；
	#     · 反过来，本条自己排队等着显示时世界被冻住，也会"刚显示就被收掉"。
	#   现在判据落在冻结声明者身上（PauseManager.covers_screen()）：
	#   真被暂停菜单/背包/结算这类带全屏遮罩的窗口盖住才让位；
	#   单纯的系统冻结期间，本条照常逐字显示、照常能推进/关闭，
	#   冻结结束后也照常继续（本层是 PROCESS_MODE_ALWAYS，不受 paused 影响）。
	if close_when_paused and PauseManager.covers_screen():
		if is_open:
			cancel_conversation()
		if notice_open:
			dismiss_notice()
		return
	if is_open:
		_tick_typing(delta)
		_tick_auto(delta)
		_tick_shake(delta)
		_tick_walk_away()
		_update_portrait()
	if notice_open:
		_tick_notice(delta)


## 键盘：**统一关闭键（J / 回车）关掉当前窗口**；F 保留为"推进对话"。
func _unhandled_input(event: InputEvent) -> void:
	# 统一关闭键：J / 回车。判定放在 PopupManager，全项目共用一套。
	if PopupManager.is_close_key(event):
		if is_open:
			# 读完最后一句算"完成并结算"，中途按算"取消"。
			dismiss_by_player()
			get_viewport().set_input_as_handled()
		elif notice_open:
			# 提示条是非阻塞 toast：收起来，但**不**吞掉这次按键——
			# 否则玩家按 J 想普攻却打不出来，手感很怪。
			dismiss_notice()
		return
	if not is_open:
		return
	# F 保留为"推进对话"的快捷键（对话条原本的交互语义，予以保留）。
	if event.is_action_pressed(&"interact"):
		advance()
		get_viewport().set_input_as_handled()


# ============================================================================
# 公开方法
# ============================================================================

## 推进对话：正在打字 → 先显示整页；否则下一页；已是最后一页 → 结束并结算。
func advance() -> void:
	if not is_open:
		return
	if _typing:
		_finish_typing()
		return
	_index += 1
	if _index >= _entries.size():
		_end_bar(true)
		return
	_show_entry()


## 跳过打字机动画：立即把整句补全并把 `_typing` 置回 false。
## 两个入口（advance 推进键 / dismiss_by_player 关闭键）都走这里，保证判定一致。
func _finish_typing() -> void:
	if not _typing:
		return
	var full: String = _tw.finish()
	_typing = false
	if _text_label != null:
		_text_label.text = full
	_refresh_action_label()


## 结束当前对话且**不**结算奖励。所有"异常退出"（走开 / 换场景 / 死亡 / 暂停）走这里。
func cancel_conversation() -> void:
	_end_bar(false)


## **玩家主动关闭**对话条（左键点条内 / 按 J / 按回车）走这里。
##
## 【为什么最后一页算"完成"、中途算"取消"】
##   已经读到最后一页再关掉 = 这段对话听完了，理应结算奖励；
##   中途关掉 = 没听完，按取消处理（不结算，NPC 的 once 也不消耗，回来能重听）。
##   这样"点条上任意处关闭"就不会白白吃掉玩家的一次性奖励
##   ——否则玩家只是想关掉窗口，结果奖励没了，等于被系统惩罚了一次。
##
## 【为什么打字中要"先补全再判定"】
##   旧实现的条件是 `at_last and not _typing`，于是"最后一页还在逐字显示时按 J"
##   被算成中途取消——奖励静默丢失。而 J 同时是普攻键，玩家打怪顺手按到就会中招，
##   且屏幕上没有任何提示说明奖励没了。
##   正确语义：打字未完成时先补全整句（这一次关闭只当"跳过动画"），
##   玩家再按一次才真正关闭并按"已完成"结算。与 advance() 的两段式手感一致。
func dismiss_by_player() -> void:
	if not is_open:
		return
	if _typing:
		_finish_typing()
		return
	var at_last: bool = _entries.is_empty() or _index + 1 >= _entries.size()
	_end_bar(at_last)


## GameFlow 换局契约：强制收起并交还一切（弹窗位置 + 冻结令牌）。
##
## 【为什么要有它】回主菜单 / 重开一局时 GameFlow 会对常驻 UI 调 force_close()。
##   只把 visible 关掉而留着 is_open / 冻结令牌，会出现"菜单里游戏是停的"
##   这种说不清的状态 —— 收尾必须与申请对偶。
func force_close() -> void:
	cancel_conversation()
	dismiss_notice()
	PopupManager.release(POPUP_ID)


## 立即收起提示条。
func dismiss_notice() -> void:
	_hide_notice()
	_notice_elapsed = 0.0
	_notice_duration = 0.0
	if notice_open:
		notice_open = false
	notice_bottom = 0.0


## 兼容旧接口：把当前正在显示的东西全部收掉。
func close() -> void:
	cancel_conversation()
	dismiss_notice()


# ============================================================================
# 私有方法 —— 节点
# ============================================================================

func _resolve_nodes() -> void:
	if not notice_panel_path.is_empty():
		_notice_panel = get_node_or_null(notice_panel_path) as Control
	if not notice_text_path.is_empty():
		_notice_text = get_node_or_null(notice_text_path) as Label
	if not bar_panel_path.is_empty():
		_bar_panel = get_node_or_null(bar_panel_path) as Control
	if not vbox_path.is_empty():
		_vbox = get_node_or_null(vbox_path) as VBoxContainer
	if not header_path.is_empty():
		_header = get_node_or_null(header_path) as HBoxContainer
	if not speaker_path.is_empty():
		_speaker_label = get_node_or_null(speaker_path) as Label
	if not text_path.is_empty():
		_text_label = get_node_or_null(text_path) as Label
	if not action_button_path.is_empty():
		_action_button = get_node_or_null(action_button_path) as Button
	if not avatar_path.is_empty():
		_avatar = get_node_or_null(avatar_path) as TextureRect
	if not portrait_path.is_empty():
		_portrait = get_node_or_null(portrait_path) as TextureRect


## 懒查找玩家（走远判断用）。找不到返回 null，不报错。
func _resolve_player() -> Node2D:
	if _player != null and is_instance_valid(_player):
		return _player
	_player = get_tree().get_first_node_in_group(&"player") as Node2D
	return _player


func _player_position() -> Vector2:
	var p: Node2D = _resolve_player()
	return p.global_position if p != null else Vector2.ZERO


# ============================================================================
# 私有方法 —— 提示条（非阻塞）
# ============================================================================

## 单句提示。duration > 0 到时自动消失；duration <= 0 常驻（但仍可点击 / 走开 / 到硬上限）。
func _on_dialog_requested(message: String, duration: float) -> void:
	if message.strip_edges() == "" or _notice_panel == null:
		return
	if _notice_text != null:
		_notice_text.text = message
	_fit_notice(message)
	_notice_panel.visible = true
	_notice_panel.modulate.a = 1.0
	_notice_duration = duration
	_notice_elapsed = 0.0
	_anchor = _player_position()
	# 刻意不发 dialog_opened：提示条不阻塞任何输入，玩家可以边走边打边看。
	notice_open = true
	# 立刻把底边报出去：HUD 的 Toast 要在这一帧就把自己排到提示条下面。
	notice_bottom = _notice_panel.get_global_rect().end.y


func _tick_notice(delta: float) -> void:
	_notice_elapsed += delta
	# 持续刷新底边：提示条会按文本换行变高，HUD 的 Toast 要跟着往下让。
	if _notice_panel != null:
		notice_bottom = _notice_panel.get_global_rect().end.y
	# 1) 硬上限兜底：无论 duration 配成什么，都不可能永远赖在屏幕上。
	if notice_max_lifetime > 0.0 and _notice_elapsed >= notice_max_lifetime:
		dismiss_notice()
		return
	# 2) 定时自动消失。
	if _notice_duration > 0.0 and _notice_elapsed >= _notice_duration:
		dismiss_notice()
		return
	# 3) 常驻提示（duration <= 0，例如路牌"一直显示"）：玩家走开就收掉。
	if _notice_duration <= 0.0:
		var p: Node2D = _resolve_player()
		if p != null and p.global_position.distance_to(_anchor) > cancel_distance:
			dismiss_notice()


func _hide_notice() -> void:
	if _notice_panel != null:
		_notice_panel.visible = false


## 让提示条按文本自适应：短提示收窄，长提示换行、往下长。
## 尺寸由 DialogTypography 量出来，这里只负责"摆"（锚定控件要靠 offset 才收得窄）。
func _fit_notice(message: String) -> void:
	if _notice_panel == null or _notice_text == null:
		return
	var size: Vector2 = _typo.measure_notice_size(message, _notice_panel,
		notice_min_width, notice_max_width)
	_notice_panel.custom_minimum_size = size
	# 同对话条：锚定控件的宽度由 offset 决定，光设最小宽度是收不窄的。
	var half: float = size.x * 0.5
	_notice_panel.offset_left = -half
	_notice_panel.offset_right = half


# ============================================================================
# 私有方法 —— 对话条（半阻塞）：入口
# ============================================================================

## 兼容入口：一串纯文本。内部转成 DialogueScript，走的还是同一套显示逻辑。
func _on_sequence_requested(speaker: String, lines: PackedStringArray, on_finished: Callable) -> void:
	_on_script_requested(DialogueScript.from_strings(speaker, lines), on_finished)


## 正式入口：结构化对话。
func _on_script_requested(script: DialogueScript, on_finished: Callable) -> void:
	# 没有内容也要保证回调被执行，否则发起方的奖励会永远发不出去。
	if script == null or not script.has_content() or _bar_panel == null:
		_call_safely(on_finished)
		return
	script = _sanitize(script)
	_pending = {"script": script, "cb": on_finished}
	# 互斥：屏幕上已经有**别的**窗口（教程 / 帮助）→ 排队等它关掉，绝不覆盖。
	# 同一个 id（又找 NPC 说话）视为"刷新内容"，直接播。
	if PopupManager.try_acquire(POPUP_ID):
		_show_pending()
	else:
		PopupManager.enqueue(POPUP_ID, PopupManager.PRIORITY_DIALOG, _show_pending)


## 丢掉内容为空的句子 —— 空行会显示成一个空对话框，纯属噪声。
func _sanitize(script: DialogueScript) -> DialogueScript:
	var kept: Array[DialogueLine] = []
	for line: DialogueLine in script.lines:
		if line != null and line.text.strip_edges() != "":
			kept.append(line)
	if kept.size() == script.lines.size():
		return script
	var copy: DialogueScript = script.duplicate(true) as DialogueScript
	copy.lines = kept
	return copy


## 真正开播 _pending 里那一段。可能是"立刻"，也可能等前面的窗口关掉之后。
func _show_pending() -> void:
	if _pending.is_empty() or _bar_panel == null:
		return
	if is_open:
		# 又来一段对话（例如另一个 NPC）：旧的按"被取消"收尾，不静默丢弃它的回调。
		# 这里必须传 release_popup=false —— 我们本来就是当前的占用者、马上要重开，
		# 一旦 release 会让 PopupManager 立刻叫醒队列里的下一个窗口，变成两个抢屏。
		push_warning("[DialogUI] 新对话打断了未结束的对话，旧的按取消处理")
		_end_bar(false, false)
	_script = _pending["script"]
	_on_finished = _pending["cb"]
	_entries = _build_entries(_script)
	_index = 0
	_anchor = _player_position()
	_bar_panel.visible = true
	if not is_open:
		is_open = true
		EventBus.dialog_opened.emit()
	# 【窗口开着 = 世界停着】见文件头。声明 Cover.WORLD：对话条不遮屏幕，
	# 只是"世界停一下" —— 玩家读对话期间不会继续跑动 / 挨打，
	# 对话也不会被"走远即取消"瞬间收掉。
	PauseManager.set_frozen(POPUP_ID, true, PauseManager.Cover.WORLD, self)
	_show_entry()


## 把整段对话"展平"成若干**页**。
##
## 【为什么要展平】
##   推进只认一个下标，翻页 / 换句是同一件事。否则每加一种"跨行表现"
##   （逐行打字、逐行立绘、逐行自动推进）都要在推进逻辑里加一层 if。
func _build_entries(script: DialogueScript) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var width: float = _typo.bar_text_width(_bar_panel, bar_max_width)
	for line: DialogueLine in script.lines:
		var style_name: StringName = variation_for(line.style)
		var pages: PackedStringArray = _typo.paginate(line.text, style_name, width, bar_max_lines)
		for i: int in pages.size():
			entries.append({
				"line": line,
				"text": pages[i],
				"first": i == 0,
				"last": i == pages.size() - 1,
			})
	return entries


# ============================================================================
# 私有方法 —— 对话条：显示与推进
# ============================================================================

## 显示当前这一页。
func _show_entry() -> void:
	if _index < 0 or _index >= _entries.size():
		_end_bar(true)
		return
	var entry: Dictionary = _entries[_index]
	var line: DialogueLine = entry["line"]
	_current_line = line
	var full_text: String = entry["text"]
	_shake_time = 0.0
	_voice_counter = 0

	# 1) 文本样式 → Theme 变体（字号/颜色/行距都在主题里，节点上不写 override）。
	if _text_label != null:
		_text_label.theme_type_variation = variation_for(line.style)

	# 2) 说话人：整段默认 + 本行覆盖。空则隐藏名字栏。
	var name: String = line.resolve_speaker(_script.speaker_default)
	if _speaker_label != null:
		_speaker_label.text = name
		_speaker_label.visible = name.strip_edges() != ""

	# 3) 显示方式：整段强制自动推进优先。
	_display = line.resolve_display(_script.auto_advance_all)
	_auto_delay = line.auto_delay if line.auto_delay > 0.0 else _script.auto_delay_default
	_auto_elapsed = 0.0

	# 4) 定尺寸（**必须在填文本之前**：宽度决定了要折几行）。
	_fit_bar(full_text, line.style)

	# 5) 填内容：起打字机，再把打字标志镜像回本实例（测试契约读 _typing）。
	_tw.begin(full_text, line.resolve_chars_per_sec(CHARS_PER_SEC),
		_display == DialogueLine.Display.INSTANT)
	_typing = _tw.typing
	if _text_label != null:
		_text_label.text = "" if _typing else full_text
	_refresh_action_label()
	_update_portrait()
	_apply_avatar(line)
	EventBus.portrait_state_changed.emit(line)


## 按钮文案跟着当前状态走，保证"最后一页一定看得到关闭入口"。
##
## 【为什么文案只有两个字】
##   按钮宽度由文案决定，而表头行的高度/宽度直接吃掉对话框的面积。
##   实测"显示全文"（4 字）会让按钮宽 64px，占掉 176px 宽的对话条的 36%。
##   统一压成 2 个字后按钮最宽 40px，短句的对话框能真正收窄。
func _refresh_action_label() -> void:
	if _action_button == null:
		return
	if _typing:
		_action_button.text = "全文"
		_action_button.tooltip_text = "点击立即显示整句（也可按 F / Enter）"
	elif _index + 1 < _entries.size():
		_action_button.text = "继续"
		_action_button.tooltip_text = "点击继续下一句（也可按 F / Enter）"
	else:
		_action_button.text = "关闭"
		_action_button.tooltip_text = "点击结束对话（也可按 F / Enter）"


func _tick_typing(delta: float) -> void:
	if not _typing or _text_label == null:
		return
	var shown_text: String = _tw.tick(delta)
	_text_label.text = shown_text
	_play_voice(shown_text.length())
	if not _tw.typing:
		_typing = false
		_refresh_action_label()


## 逐字语音：每 `VOICE_EVERY` 个字响一次（走 AudioManager，自动跟随音效音量）。
##
## 【为什么是固定节奏 + 行级音高，而不是"每行配一个语速"】
##   AudioManager.play_sfx 自己已经叠了随机音高，逐字连打不会死板；
##   这里只需决定"多久响一次"（节奏）和"整句偏高还是偏低"（音色）。
##   把节奏做成 UI 常量、音高留给 `DialogueLine.voice_pitch`，
##   数据层就不必为每个字音再学习一套参数。
func _play_voice(shown: int) -> void:
	if _current_line == null or _current_line.voice_sfx == null:
		return
	if shown <= 0 or shown == _voice_counter:
		return
	if shown % VOICE_EVERY != 0:
		return
	_voice_counter = shown
	AudioManager.play_sfx(_current_line.voice_sfx, 0.0, _current_line.voice_pitch)


## AUTO 显示方式：打完之后停一会儿自己往下走。
## 打字期间不计时 —— 否则"还没打完就翻页"，看起来像丢字。
func _tick_auto(delta: float) -> void:
	if _display != DialogueLine.Display.AUTO or _typing:
		return
	_auto_elapsed += delta
	if _auto_elapsed < _auto_delay:
		return
	_auto_elapsed = 0.0
	advance()


## 抖动：在基准 offset 上叠一个衰减的正弦偏移。
## 【为什么不改 position】锚定控件的位置由 anchors + offset 共同决定，
## 直接写 position 会在下一次容器布局时被覆盖掉。改 offset 才是稳的。
func _tick_shake(delta: float) -> void:
	if _bar_panel == null or _bar_base_offsets.size() < 4:
		return
	var want: bool = _current_line != null and _current_line.shake and _typing
	if not want:
		if _shake_time != 0.0:
			_shake_time = 0.0
			_restore_bar_offsets()
		return
	_shake_time += delta
	var amp: float = shake_amplitude * maxf(0.0, 1.0 - _shake_time * 2.0)
	var dx: float = sin(_shake_time * 62.0) * amp
	_bar_panel.offset_left = _bar_base_offsets[0] + dx
	_bar_panel.offset_right = _bar_base_offsets[2] + dx
	_bar_panel.offset_top = _bar_base_offsets[1]
	_bar_panel.offset_bottom = _bar_base_offsets[3]


func _restore_bar_offsets() -> void:
	if _bar_panel == null or _bar_base_offsets.size() < 4:
		return
	_bar_panel.offset_left = _bar_base_offsets[0]
	_bar_panel.offset_top = _bar_base_offsets[1]
	_bar_panel.offset_right = _bar_base_offsets[2]
	_bar_panel.offset_bottom = _bar_base_offsets[3]


## 玩家走远 → 自动结束。对话永不夺取控制权，这条是最后的保险。
func _tick_walk_away() -> void:
	var p: Node2D = _resolve_player()
	if p == null:
		return
	if p.global_position.distance_to(_anchor) > cancel_distance:
		cancel_conversation()


## 收尾。completed = true 才结算奖励；被打断则明确取消。
##
## release_popup：是否把 PopupManager 的位置让出来（默认让）。
##   只有"自己马上要重开一段"的场景才传 false，见 _show_pending 里的说明。
func _end_bar(completed: bool, release_popup: bool = true) -> void:
	_restore_bar_offsets()
	if not is_open:
		return
	var cb: Callable = _on_finished
	# 先清状态再回调：回调里可能立刻又开一段新对话。
	_hide_bar()
	_entries.clear()
	_index = 0
	_script = null
	_current_line = null
	_on_finished = Callable()
	_tw.reset()
	_typing = false
	_display = DialogueLine.Display.TYPEWRITER
	is_open = false
	EventBus.dialog_closed.emit()
	EventBus.portrait_state_changed.emit(null)
	# 【为什么先 release 再跑回调】回调（NPC 的 on_finished）里经常会立刻开新窗口
	#   ——发奖励提示条、开下一个对话、弹教程。如果先跑回调、后 release，
	#   那个新窗口刚 acquire 拿到的锁会被**本次** release 顺手让出去，
	#   PopupManager 的互斥就此失效，于是屏幕上同时出现两个窗口。
	#   先腾位置，回调里新开的窗口才能正常持锁。
	#
	# 【冻结与弹窗位置同进同出】release_popup=false 表示"马上要重开一段"
	#   （见 _show_pending），此时冻结保持连续 —— 不发中途的 freeze_ended/freeze_started，
	#   与"连续阻塞步之间冻结不断"是同一条原则。
	if release_popup:
		PauseManager.set_frozen(POPUP_ID, false)
		PopupManager.release(POPUP_ID)
	if completed:
		_call_safely(cb)


func _hide_bar() -> void:
	if _bar_panel != null:
		_bar_panel.visible = false
	if _avatar != null:
		_avatar.visible = false
	if _portrait != null:
		_portrait.visible = false


## 安全调用回调：发起方（NPC）可能已经被释放（换场景 / 被打死），
## 直接 call() 会报错并中断收尾流程。
func _call_safely(cb: Callable) -> void:
	if not cb.is_valid():
		return
	var obj: Object = cb.get_object()
	if obj != null and not is_instance_valid(obj):
		return
	cb.call()


# ============================================================================
# 私有方法 —— 排版应用（"量字 → 定框"的测量全部在 DialogTypography）
# ============================================================================

## 按文本给对话条定宽高：尺寸问 DialogTypography 要，这里只管写回面板。
##
## 【高度为什么底部锚定、往上长】
##   面板的高度本来就会由内容撑开，但 Label 在**下一帧**才重新折行，
##   不先写预测高度的话，换句时会看到"先按上一句的高度画一帧再跳"。
func _fit_bar(text: String, style: DialogueLine.Style) -> void:
	if _bar_panel == null:
		return
	var size: Vector2 = _typo.measure_bar_size(text, variation_for(style), _bar_panel,
		_header, _vbox, bar_min_width, bar_max_width)
	_bar_panel.custom_minimum_size = size
	_apply_bar_offsets(size.x, size.y)


## 把对话条摆成"宽 w、高 h、底边固定在 bar_bottom_margin"。
##
## 【为什么必须改 offset，而不是只改 custom_minimum_size】
##   锚定控件的矩形大小是由 anchors + offset 决定的，`custom_minimum_size` 只是**下限**。
##   场景里 Bar 写着 offset ±88（即 176 宽），此时就算把最小宽度设成 120，
##   实际宽度仍然是 176 —— 自适应形同虚设。要让"短句收窄"真正生效，
##   必须把左右 offset 一起改掉。
##   `grow_horizontal = BOTH` 保证：万一内容下限比 w 还大，它是往两边对称长，
##   而不是只往右长导致偏出屏幕中心。
func _apply_bar_offsets(width: float, height: float) -> void:
	if _bar_panel == null or _bar_base_offsets.size() < 4:
		return
	var bottom: float = -bar_bottom_margin
	var half: float = width * 0.5
	_bar_base_offsets[0] = -half
	_bar_base_offsets[1] = bottom - height
	_bar_base_offsets[2] = half
	_bar_base_offsets[3] = bottom
	_restore_bar_offsets()


# ============================================================================
# 私有方法 —— 立绘 / 头像 / 表情（预留挂点）
# ============================================================================

## 把当前行的立绘 / 头像摆到该在的位置。
##
## 【为什么立绘用"每帧摆一次"而不是"显示时摆一次"】
##   对话条是自适应高度的，翻到长句时会变高、位置随之改变。
##   立绘要贴着对话条走，就必须跟着最新矩形走；每帧算一次只是几行数学，
##   比"监听尺寸变化信号 + 补摆"简单且不会漏。
func _update_portrait() -> void:
	if _portrait == null or _bar_panel == null:
		return
	var line: DialogueLine = _current_line
	if line == null:
		_portrait.visible = false
		return
	var tex: Texture2D = line.resolve_portrait(_script.portrait_default if _script != null else null)
	var slot: DialogueLine.PortraitSlot = line.portrait_slot
	if slot == DialogueLine.PortraitSlot.NONE and _script != null:
		slot = _script.portrait_slot_default
	# INLINE = 小头像，走表头（由 _apply_avatar 负责），不用大立绘。
	if tex == null or slot == DialogueLine.PortraitSlot.NONE \
			or slot == DialogueLine.PortraitSlot.INLINE:
		_portrait.visible = false
		return
	_portrait.texture = tex
	_portrait.flip_h = line.portrait_flip
	_portrait.visible = true
	var size: Vector2 = _cap_portrait_size(tex.get_size())
	_portrait.size = size
	var bar: Rect2 = _bar_panel.get_global_rect()
	var pos: Vector2 = Vector2.ZERO
	match slot:
		DialogueLine.PortraitSlot.LEFT:
			pos = Vector2(bar.position.x - size.x, bar.end.y - size.y)
		DialogueLine.PortraitSlot.RIGHT:
			pos = Vector2(bar.end.x, bar.end.y - size.y)
		_:
			# CENTER：屏幕中央、压在对话条上方。
			pos = Vector2((DialogTypography.CANVAS_W - size.x) * 0.5, bar.position.y - size.y)
	pos += line.portrait_offset
	pos.x = clampf(pos.x, 0.0, maxf(0.0, DialogTypography.CANVAS_W - size.x))
	pos.y = clampf(pos.y, 0.0, 180.0)
	_portrait.position = pos


## 立绘尺寸上限：允许立绘很大，但**不允许它把画面撑破**。
##
## 【为什么要在代码里做，而不是只靠场景节点的 stretch_mode】
##   TextureRect 默认 `EXPAND_KEEP_SIZE`，它的最小尺寸就是贴图原尺寸，
##   手动写 `size` 会被最小尺寸顶回去（想缩都缩不动）。所以场景里把
##   Portrait 的 expand_mode 设成 IGNORE_SIZE，再由这里统一算出"实际该多大"：
##   超出画布就等比缩到画布内，与"任何长度文本都不越界"是同一条底线。
func _cap_portrait_size(native: Vector2) -> Vector2:
	if native.x <= 0.0 or native.y <= 0.0:
		return native
	var limit: Vector2 = Vector2(DialogTypography.CANVAS_W, 180.0)
	if native.x <= limit.x and native.y <= limit.y:
		return native
	return native * minf(limit.x / native.x, limit.y / native.y)


## 小头像（表头里、名字左边）。没配就整块隐藏，表头不会因此变高。
func _apply_avatar(line: DialogueLine) -> void:
	if _avatar == null:
		return
	var tex: Texture2D = null
	var slot: DialogueLine.PortraitSlot = DialogueLine.PortraitSlot.NONE
	if line != null:
		tex = line.resolve_portrait(_script.portrait_default if _script != null else null)
		slot = line.portrait_slot
		if slot == DialogueLine.PortraitSlot.NONE and _script != null:
			slot = _script.portrait_slot_default
	_avatar.visible = tex != null and slot == DialogueLine.PortraitSlot.INLINE
	if _avatar.visible:
		_avatar.texture = tex


# ============================================================================
# 输入回调（鼠标优先）
# ============================================================================

## 点对话条内任意处 = **关闭**（统一契约）；右键同样是直接结束。
##
## 【"继续 / 关闭"按钮为什么还能正常推进、不和关闭打架】
##   按钮是 BaseButton，处理按下时会自己 accept_event()，事件不再冒泡到面板，
##   所以点按钮只走按钮自己的 advance()，不会"推进一次 + 关闭一次"。
##   要推进多句对话就点"继续"按钮（或按 F），要提前结束就点条上别处。
func _on_bar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if not mb.pressed:
			return
		# 左键（统一契约）→ 关闭：读完最后一页算结算，中途退出算取消。
		if PopupManager.is_close_click(event):
			dismiss_by_player()
			_bar_panel.accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			# 右键是明确的"别烦我"，一律按取消处理（不结算）。
			cancel_conversation()
			_bar_panel.accept_event()


## 点提示条 = 立即收起。
func _on_notice_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			dismiss_notice()
			_notice_panel.accept_event()


func _on_action_pressed() -> void:
	advance()


# ============================================================================
# 信号回调
# ============================================================================

func _on_scene_changed(_scene: Node) -> void:
	# 换关卡：发起对话的对象已经不在了，回调也指向旧场景 → 必须收尾，
	# 否则 is_open 会残留到新关卡，把新玩家永久锁住。
	cancel_conversation()
	dismiss_notice()
	# 换关卡后，还在排队等着显示的那段对话已经没有意义（发起它的 NPC 都不在了），
	# 一并丢掉，免得进新关卡后冷不丁弹出一段旧对话。
	_pending.clear()
	PopupManager.release(POPUP_ID)
	_player = null


func _on_player_died() -> void:
	cancel_conversation()
	dismiss_notice()
	PopupManager.release(POPUP_ID)


## 别的窗口（教程 / 帮助）占屏 → 提示条让位。
##
## 【为什么只收提示条、不动对话条】两条通道的语义不同：
##   · 提示条在**顶部**，会和同样画在顶部的教程/帮助面板叠在一起，所以让位；
##   · 对话条在**底部**，与任何窗口都不抢位置，而且"提示不打断对话"是硬契约
##     （见 weapon_dialog_test「提示不能顶掉对话」）。所以本函数对对话条一行不碰。
func _on_popup_opened(id: StringName) -> void:
	if id == POPUP_ID:
		return
	if notice_open:
		dismiss_notice()
