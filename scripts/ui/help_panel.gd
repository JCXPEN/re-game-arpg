## HelpPanel —— 操作说明 / 新手帮助（模态弹窗）
##
## 【负责什么】
##   展示按键说明、战斗机制、系统说明。可从主菜单或暂停菜单打开。
##   文案集中在 _build_help_text()，改文案不碰布局。
##
## 【挂哪个节点】
##   scenes/ui/help_panel.tscn 的根节点（CanvasLayer）。
##
## 【怎么关掉 —— 这是本面板最重要的契约】
##   它经常在"暂停中"被打开（暂停菜单 → 操作说明），所以必须满足：
##     1. process_mode = ALWAYS：否则 get_tree().paused 为 true 时，
##        Control 的 gui_input 与 _unhandled_input 全部失效，按钮点不动、
##        Esc 也按不动 —— 这就是"教程窗口关不掉"的根因。
##     2. 统一关闭契约（与教程/对话框完全一致）：按 **J** / 按 **回车** /
##        鼠标**左键点窗口内任意位置**。判定集中在 PopupManager。
##     3. 提供**多条**互相独立的退出途径：关闭按钮 / Esc / F / 右键 /
##        点击面板外的暗色遮罩。任何一条失效都不会把玩家困住。
##     4. 不改游戏原有的暂停状态、不抢焦点、不读任何全局 UI 开关：
##        打开时记住"游戏本来是不是停的"，关闭时精确还原
##        ——从暂停菜单进来，关掉就该回到暂停菜单，而不是把游戏放跑了。
##     5. 系统级窗口：显示期间冻结游戏（角色不能动/不能交互），关闭后恢复。
##
## 【依赖谁】
##   无（纯展示）。
class_name HelpPanel
extends CanvasLayer

# ============================================================================
# 常量
# ============================================================================

## 本窗口在 PopupManager 里的身份 id（互斥 / 排队用）。
const POPUP_ID: StringName = &"help"
## 本窗口在 PauseManager 里的暂停令牌 id。
const PAUSE_OWNER: StringName = &"help"

# ============================================================================
# @export
# ============================================================================

## 面板根节点。
@export var panel_path: NodePath
## 文本标签（RichTextLabel）。
@export var label_path: NodePath
## 关闭按钮。
@export var close_button_path: NodePath
## 面板外的暗色遮罩（点击即关闭）。
@export var dimmer_path: NodePath

# ============================================================================
# 私有变量
# ============================================================================

var _panel: Control
var _label: RichTextLabel
var _dimmer: Control

# ============================================================================
# 静态获取
# ============================================================================

## 取全局唯一的 HelpPanel，没有就用 scene 现建一个并挂到 Menus 容器。
## 【为什么按 id 复用】见 SettingsPanel.acquire 的同名注释：主菜单与暂停菜单是
##   两个入口，各自 instantiate 会让树上出现两个 HelpPanel，Esc/可见性会作用错对象。
static func acquire(scene: PackedScene) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var reg: Node = tree.root.get_node_or_null(NodePath("UIRegistry"))
	var existing: Node = null
	if reg != null:
		existing = reg.call(&"window_for", &"help_panel")
	if existing != null:
		return existing
	if scene == null:
		return null
	var inst: Node = scene.instantiate()
	inst.name = "HelpPanel"
	var parent: Node = tree.root
	if reg != null:
		parent = reg.call(&"menus_container")
	parent.add_child(inst)
	return inst


# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	# 必须在暂停时也能收输入，见文件头注释。
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not panel_path.is_empty():
		_panel = get_node_or_null(panel_path) as Control
	if not label_path.is_empty():
		_label = get_node_or_null(label_path) as RichTextLabel
	if not dimmer_path.is_empty():
		_dimmer = get_node_or_null(dimmer_path) as Control
	if not close_button_path.is_empty():
		var btn: Button = get_node_or_null(close_button_path) as Button
		if btn != null:
			btn.pressed.connect(close)
	if _dimmer != null:
		_panel_input(_dimmer)
	if _panel != null:
		# 统一契约：面板内左键也能关（旧实现只认右键，玩家点面板没反应）。
		_panel_input(_panel)
	if _label != null:
		_label.bbcode_enabled = true
		_label.text = _build_help_text()
	visible = false
	# Esc 交给 UIInputRouter 集中仲裁（不再自己监听，避免抢事件）。
	add_to_group(UIInputRouter.GROUP)
	# 登记进 UI 注册表：调用方按 id 访问，不再按树路径查名。
	UIRegistry.register(&"help_panel", self)


# ============================================================================
# UIInputRouter 契约
# ============================================================================

func ui_layer_priority() -> int:
	return UIInputRouter.LAYER_HELP


func is_blocking_ui() -> bool:
	return visible


func ui_window_id() -> StringName:
	return POPUP_ID


## 轮到本窗口处理 Esc：关闭。
func route_esc() -> bool:
	if not visible:
		return false
	close()
	return true


## 回主菜单时强制收起（不碰 PauseManager —— 整局重置会统一清令牌）。
func force_close() -> void:
	visible = false
	PauseManager.unfreeze(PAUSE_OWNER)
	PopupManager.release(POPUP_ID)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# 统一关闭键：J / 回车（判定在 PopupManager，全项目同一套）。
	# F 额外保留：本面板历史上就支持，玩家也已经习惯。
	#
	# 【Esc 为什么**不**在这里处理】_unhandled_input 是广播语义，本面板和
	#   暂停菜单会同时收到 Esc，谁先谁后取决于挂载顺序 —— 玩家按一下 Esc
	#   可能同时关掉两层。Esc 统一交给 UIInputRouter 仲裁。
	if PopupManager.is_close_key(event) or event.is_action_pressed(&"interact"):
		close()
		get_viewport().set_input_as_handled()


# ============================================================================
# 公开方法
# ============================================================================

func open() -> void:
	# 互斥：屏幕上已经有别的窗口 → 排队，等它关掉再显示，绝不覆盖。
	if PopupManager.try_acquire(POPUP_ID):
		_show_now()
	else:
		PopupManager.enqueue(POPUP_ID, PopupManager.PRIORITY_HELP, _show_now)


## 真正显示（可能立刻，也可能等前面的窗口关掉之后被 PopupManager 叫醒）。
func _show_now() -> void:
	visible = true
	# 每次打开都回到顶部，避免上次滚动位置残留让人以为没内容。
	if _label != null:
		_label.scroll_to_line(0)
	if not close_button_path.is_empty():
		var btn: Button = get_node_or_null(close_button_path) as Button
		if btn != null:
			btn.grab_focus()
	# 系统级窗口：冻结游戏，关掉才恢复。
	_freeze_game()


func close() -> void:
	visible = false
	# 解冻 + 交还弹窗位置，两件都要做，否则下一个排队的窗口轮不到。
	_unfreeze_game()
	PopupManager.release(POPUP_ID)


## 当前是否显示中。
func is_open() -> bool:
	return visible


# ============================================================================
# 私有方法
# ============================================================================

## 冻结游戏逻辑（系统级窗口的硬性要求）。
##
## 【为什么走 PauseManager 而不是自己记 _paused_by_me】
##   本面板多半是从暂停菜单里打开的，那时游戏已经被暂停菜单冻结。
##   旧写法"看到已 paused 就不接管"看似正确，但一旦暂停菜单先关掉，
##   本面板就暴露在一个"我以为别人负责、别人以为我负责"的空档里。
##   PauseManager 的令牌集合让"谁要它停着"变成显式的，不存在空档。
func _freeze_game() -> void:
	PauseManager.freeze(PAUSE_OWNER)


## 解冻：只交还自己那一个令牌。
func _unfreeze_game() -> void:
	PauseManager.unfreeze(PAUSE_OWNER)


## 给某个 Control 接上关闭手势：左键（统一契约）+ 右键（快捷退出）。
##
## 【和"关闭"按钮为什么不冲突】
##   关闭按钮是 Button，处理按下时 BaseButton 会自己 accept_event()，
##   事件不再冒泡到这里，所以点按钮只走按钮自己的逻辑，不会关两次。
func _panel_input(ctrl: Control) -> void:
	ctrl.gui_input.connect(func(event: InputEvent) -> void:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb == null or not mb.pressed:
			return
		if PopupManager.is_close_click(event) or mb.button_index == MOUSE_BUTTON_RIGHT:
			close()
			get_viewport().set_input_as_handled())


## 组装帮助文本（BBCode）。标题用主题里的 HeadingLabel 同色强调。
func _build_help_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b][color=#ffd966]移动与视角[/color][/b]")
	lines.append("  WASD / 方向键 / 左摇杆 —— 八方向移动")
	lines.append("  鼠标 —— 决定法术与远程攻击的瞄准方向")
	lines.append("")
	lines.append("[b][color=#ffd966]战斗[/color][/b]")
	lines.append("  鼠标左键 / J —— 普攻，连按可打出三段连击")
	lines.append("  按住鼠标右键 / K —— 蓄力重击，蓄满伤害与范围最大")
	lines.append("  空格 / Shift —— 翻滚，[color=#8fd05a]翻滚期间无敌[/color]")
	lines.append("  翻滚可以[color=#ffd966]取消攻击后摇[/color]，被打断时优先翻滚")
	lines.append("")
	lines.append("[b][color=#ffd966]法术与技能[/color][/b]")
	lines.append("  Q / E / R —— 释放三个法术槽（消耗 MP，有冷却）")
	lines.append("  1 / 2 —— 释放主动技能")
	lines.append("")
	lines.append("[b][color=#ffd966]探索[/color][/b]")
	lines.append("  F —— 与宝箱 / 存档点 / 提示牌 / NPC 交互")
	lines.append("  Tab / I —— 打开背包")
	lines.append("  Esc —— 暂停菜单")
	lines.append("")
	lines.append("[b][color=#ffd966]核心机制[/color][/b]")
	lines.append("  · [color=#ffd966]命中顿帧[/color]：打中敌人瞬间画面短暂停顿，越重的武器越明显")
	lines.append("  · [color=#ffd966]受击硬直[/color]：被打中会短暂无法行动，注意保持距离")
	lines.append("  · [color=#ffd966]词条构筑[/color]：每清空一个房间可获得三选一强化，一局内有效")
	lines.append("  · [color=#ffd966]存档点[/color]：交互后回满状态并记录复活点")
	lines.append("")
	lines.append("[b][color=#ffd966]目标[/color][/b]")
	lines.append("  从边境小镇出发 → 穿过风鸣平原 → 探索古代地牢")
	lines.append("  → 击败巢穴深处的独眼巨人 → 回城")
	lines.append("")
	lines.append("[i][color=#a9a49b]点「关闭」按钮、按 Esc / F，或右键面板即可关闭本说明。[/color][/i]")
	return "\n".join(lines)
