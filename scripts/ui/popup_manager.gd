## PopupManager —— 弹窗/对话窗口的统一调度器 + 统一关闭契约（Autoload 单例）
##
## 【负责什么】
##   1. **互斥**：同一时刻只允许一个"窗口型"弹窗存在（对话条 / 教程 / 帮助）。
##      第二个来源想弹时**不会直接覆盖**（那会丢掉前一个的结算回调），
##      而是进队列，等前一个关闭后再按优先级依次显示。
##   2. **统一关闭契约**：所有窗口认同一组关闭输入（J / 回车 / 窗口内左键），
##      判定函数集中在本文件，避免每个弹窗各写一套、再漏掉某一个。
##
## 【为什么不做成 class_name】
##   本脚本注册为 autoload `PopupManager`；同名 class_name 会报
##   "hides an autoload singleton"（和 TutorialSystem 同样的处理办法）。
##
## 【挂哪个节点】
##   project.godot 的 [autoload]，排在 EventBus 之后。
##
## 【依赖谁】
##   无（纯状态机 + 输入判定，不依赖任何 UI 节点，可单独测试）。
##
## 【怎么扩展】
##   新增一种弹窗：给它一个 id；显示前 try_acquire(id)，被占用时
##   enqueue(id, 优先级, 显示回调)，关闭时 release(id)。
##
## 【提示条为什么不算"窗口"、不参与互斥】
##   DialogUI 的提示条是**非阻塞 toast**（顶部一条、不锁输入、不抢焦点），
##   它和对话条同时出现是刻意设计（见 weapon_dialog_test
##   "提示不能顶掉对话"用例：notice 与 bar 必须能同屏）。
##   这里的互斥只管"会挡住玩家、需要玩家处理"的窗口。
##
## 【为什么用物理键判定 J 而不是 action】
##   J 在 InputMap 里绑的是普攻，而弹窗打开时它必须是"关闭"。
##   走 action 会随玩家改键而漂移；直接读物理键语义才稳定。
##   弹窗**打开期间**由本管理器接管这些键，关闭后交还游戏。
extends Node

# ============================================================================
# 常量
# ============================================================================

## 窗口优先级（数字大的先显示）。教程 > 帮助 > 对话：
## 教程是开机必经流程，被别的窗口插队会导致新手卡住。
const PRIORITY_TUTORIAL: int = 100
const PRIORITY_HELP: int = 60
const PRIORITY_DIALOG: int = 50

# ============================================================================
# 信号
# ============================================================================

## 某个窗口开始显示（含从队列里被叫醒）。
signal popup_opened(id: StringName)
## 某个窗口已关闭并让出位置。
signal popup_closed(id: StringName)

# ============================================================================
# 私有变量
# ============================================================================

## 当前占用屏幕的窗口 id；空串表示没有。
var _active: StringName = &""
## 等待中的窗口：{id, priority, cb, seq}。
var _queue: Array[Dictionary] = []
## 入队序号，用于同优先级时"先到先得"。
var _seq: int = 0

# ============================================================================
# 公开方法 —— 互斥调度
# ============================================================================

## 当前是否有窗口在显示。
func is_active() -> bool:
	return _active != &""


## 当前显示的窗口 id（没有则为空串）。
func active_id() -> StringName:
	return _active


## 尝试占用屏幕。成功返回 true（调用方应当立即显示）；
## 屏幕已被别的窗口占用则返回 false（调用方应当改为 enqueue）。
func try_acquire(id: StringName) -> bool:
	if _active == &"" or _active == id:
		_active = id
		popup_opened.emit(id)
		return true
	return false


## 把窗口排进等待队列。同一 id 重复入队只更新内容与优先级，不排两次。
## show_cb 是"轮到它时"的显示回调（一般就是该窗口自己的 _show_now()）。
func enqueue(id: StringName, priority: int, show_cb: Callable) -> void:
	for entry: Dictionary in _queue:
		if entry["id"] == id:
			entry["priority"] = priority
			entry["cb"] = show_cb
			return
	_seq += 1
	_queue.append({
		"id": id,
		"priority": priority,
		"cb": show_cb,
		"seq": _seq,
	})


## 释放屏幕占用。是活跃窗口 → 立刻叫醒队列里的下一个；
## 只是排在队里还没显示的（例如玩家换关卡了）→ 直接丢弃，
## 免得留下一个指向已释放对象的幽灵回调。
func release(id: StringName) -> void:
	if _active != id:
		_drop_queued(id)
		return
	_active = &""
	popup_closed.emit(id)
	_pump()


## 清空队列（换关卡 / 回主菜单时用：还没显示的窗口一律作废）。
func clear_queue() -> void:
	_queue.clear()


## 彻底清场：清空队列 **并且** 让出当前占屏。
##
## 【和 release() 的区别】release(id) 是"某个窗口自己关掉了"，
##   会顺手叫醒队列里的下一个（_pump）。回主菜单 / 换局时正相反：
##   队列里的回调多半指向即将被释放的关卡对象，叫醒它们就是引爆幽灵回调。
##   所以这里只清、不 pump。
##
## 【为什么还要发 popup_closed】占屏的窗口可能正在等这个信号收尾
##   （例如对话条要据此决定是否结算）。不发的话它会一直以为自己还占着屏幕。
func release_all() -> void:
	_queue.clear()
	if _active == &"":
		return
	var was: StringName = _active
	_active = &""
	popup_closed.emit(was)


# ============================================================================
# 公开方法 —— 统一关闭输入判定
# ============================================================================

## 是否为"统一关闭键"：J 或回车（含小键盘回车）。
## 同时兼容 ui_accept（默认绑回车/空格），玩家改过键也不会失灵。
func is_close_key(event: InputEvent) -> bool:
	if event is InputEventKey:
		var k: InputEventKey = event as InputEventKey
		if k.pressed and not k.echo:
			if _is_key(k, KEY_J) or _is_key(k, KEY_ENTER) or _is_key(k, KEY_KP_ENTER):
				return true
	if event.is_action_pressed(&"ui_accept"):
		return true
	return false


## 是否为"统一关闭点击"：鼠标左键按下。
##
## 【为什么只判左键、且能和按钮共存】
##   按钮（BaseButton）处理按下时会自己 accept_event()，事件不会再冒泡到
##   父面板的 gui_input，所以"点按钮 = 按钮自己的功能"，
##   "点面板空白处 = 关闭"，两者天然不冲突，不需要额外做坐标排除。
func is_close_click(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		return mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	return false


# ============================================================================
# 私有方法
# ============================================================================

## 物理键码或布局键码命中任意一个都算（适配非 QWERTY 布局）。
func _is_key(k: InputEventKey, keycode: int) -> bool:
	return k.keycode == keycode or k.physical_keycode == keycode


## 叫醒队列里的下一个窗口（优先级高者优先，同级先到先得）。
func _pump() -> void:
	if _active != &"" or _queue.is_empty():
		return
	_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["priority"] != b["priority"]:
			return a["priority"] > b["priority"]
		return a["seq"] < b["seq"])
	var next: Dictionary = _queue.pop_front()
	var id: StringName = next["id"]
	_active = id
	popup_opened.emit(id)
	var cb: Callable = next["cb"]
	if cb.is_valid():
		cb.call()


## 从队列里移除某个 id（它还没轮到就被取消了）。
func _drop_queued(id: StringName) -> void:
	for i: int in range(_queue.size() - 1, -1, -1):
		if _queue[i]["id"] == id:
			_queue.remove_at(i)
