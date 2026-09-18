## UILayoutProbe —— UI 布局"越界 / 重叠 / 被裁剪"客观探针（编辑器工具场景）
##
## 【负责什么】
##   在**真实运行的游戏**里（真 UI 树、真主题、真字体）遍历常驻 UI 的 Control 子树，
##   逐节点打印 `global_rect` 与 `get_combined_minimum_size()`，并判定三类硬伤：
##     · **OUT 越界**：visible 的控件 rect 跑出 320×180 视口（含负数方向）。
##     · **CLIP 被裁剪**：控件自己的内容最小尺寸 > 它实际拿到的尺寸
##       —— 这就是"文字被切掉 / 需要滚动才能看完"的根因。
##     · **OVERLAP 重叠**：两个互不相干的可见控件矩形相交
##       —— "提示条压住飘字"这类撞车就是这么发现的。
##   三类判定都用 `get_combined_minimum_size()` 而不是 `size`：容器未完成布局时
##   `size` 会短暂为 0，用它判定等于什么都没测（见 skill 第 8 节）。
##
## 【为什么要有它】
##   "对话框太大 / 元素超出边界 / 文字排不下"这类问题**目测不可靠**：
##   截图里看着像"溢出"的条纹，实测只是背景木纹透过 90% 不透明面板。
##   所以先把几何量化成数字，再动布局；改完再跑一次对比，才是可验证的。
##
## 【踩过的坑：量之前必须先把字打出来】
##   对话是打字机逐字显示的，`_show_line()` 先把文本清空再逐帧填。
##   如果刚发完信号就量，量到的是**空文本**（1 行高），于是"长句也不会撑大面板"
##   这种假结论就出来了。所以每次发完必须 `advance()` 一次跳到"整句显示"再量。
##
## 【跑法】
##   Godot --headless --path . --quit-after 300 res://tools/ui_layout_probe.tscn
##   退出码：0 = 无 OUT/CLIP/OVERLAP；1 = 有（可直接当回归守卫用）。
##   **必须带 `--quit-after`**：脚本一旦解析失败就没有任何代码负责退出，
##   进程会一直挂着（实测挂出 4 个 150~380MB 的僵尸进程）。
##
## 【依赖谁】
##   boot.tscn（真实启动流程）、DialogUI、EventBus。只读，不改任何场景/资源。
extends Node

# ============================================================================
# 常量
# ============================================================================

## 基准画布尺寸（project.godot 的 viewport_width/height）。
const CANVAS: Vector2 = Vector2(320, 180)
## 浮点比较容差：布局算出来的 320.0001 不该被报成越界。
const EPS: float = 0.05
## 要检查的常驻 UI 根节点名（挂在 root 下）。
## 注意：不能写成 `PackedStringArray([...])`——构造函数不是常量表达式，会编译失败。
const TARGETS: PackedStringArray = ["DialogUI", "HUD"]

## 允许重叠的白名单：键是 "路径A|路径B"（字典序），值写清为什么允许。
## 空表示"任何两个互不相关的可见控件都不许相交"——这是最严的判据，
## 一旦真的需要例外，请在这里写明理由而不是放宽判定本身。
const OVERLAP_ALLOWED: Dictionary = {}

## 纯布局容器（引擎类名）。它们不画任何像素，只负责摆位置。
const LAYOUT_ONLY_TYPES: Array[String] = [
	"Control", "VBoxContainer", "HBoxContainer", "GridContainer",
	"MarginContainer", "CenterContainer", "ScrollContainer", "TabContainer",
]

## 用例文本：短句 / 长句 / 超长句，覆盖"自适应"的三档。
const SHORT_LINE: String = "你终于醒了，勇者。"
const LONG_LINE: String = "你终于醒了，勇者。这片土地已经被诅咒了整整三年，村里的井水都干了，愿意听我把话说完吗？"
const HUGE_LINE: String = "北境的寒风从来不会怜悯任何人。三年前那场大雪埋掉了整整一个村子，活下来的人不到十分之一。如今同样的乌云又压了过来，而领主却把仅剩的粮食全部锁进了地窖。孩子，我不管你是为了赏金还是为了名声，我只求你一件事——在你还能选择的时候，选那条能让更多人活下来的路。"

# ============================================================================
# 私有变量
# ============================================================================

var _out: int = 0
var _clip: int = 0
var _overlap: int = 0
var _issues: Array[String] = []
## 当前一轮里收集到的可见 Control（重叠检测用）：{path, rect, text}
var _boxes: Array[Dictionary] = []

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	var boot: Node = load("res://scenes/core/boot.tscn").instantiate()
	boot.name = "Boot"
	boot.set("skip_menu", true)
	get_tree().root.add_child.call_deferred(boot)
	for i: int in 60:
		await get_tree().process_frame

	_quiet_tutorial()
	await get_tree().process_frame

	print("")
	print("========== UILayoutProbe（视口 %s）==========" % str(get_viewport().get_visible_rect().size))
	await _dump("A. 初始（无对话）")

	await _show_sequence("村民", SHORT_LINE, "B. 短句")
	await _show_sequence("村民", LONG_LINE, "C. 长句")
	await _show_sequence("村民", HUGE_LINE, "D. 超长句")
	await _show_sequence("", SHORT_LINE, "E. 无说话人（旁白）")

	# F：三条"临时消息"同屏 —— 提示条 + HUD Toast + 对话条。
	# 这是最容易撞车的一帧（也是旧版真的撞了的一帧：提示条 6..66 盖住 y=40 的 Toast）。
	EventBus.dialog_requested.emit("路牌：前方是野外的入口，走过去就能离开小镇，路上小心野兽。", 0.0)
	EventBus.toast_requested.emit("获得：生命药水")
	EventBus.dialog_sequence_requested.emit("铁匠",
		PackedStringArray(["提示条在上面，对话条在下面。"]), Callable())
	await _settle()
	var ui: Node = get_tree().root.get_node_or_null("DialogUI")
	if ui != null:
		ui.call("advance")
	await _settle()
	await _dump("F. 提示条 + HUD Toast + 对话条 同屏")
	await _force_finish()

	print("")
	print("################################################")
	print("# 布局探针：越界 %d 处，被裁剪 %d 处，重叠 %d 处" % [_out, _clip, _overlap])
	for s: String in _issues:
		print("  - " + s)
	print("################################################")
	get_tree().quit(0 if (_out == 0 and _clip == 0 and _overlap == 0) else 1)


# ============================================================================
# 私有方法 —— 驱动
# ============================================================================

## 发一段对话、跳到"整句显示"、量一次、收掉。
func _show_sequence(speaker: String, line: String, title: String) -> void:
	EventBus.dialog_sequence_requested.emit(speaker, PackedStringArray([line]), Callable())
	await _settle()
	# 关键：打字机刚起步时文本是空的，必须先跳到整句再量，否则量到的是空文本。
	var ui: Node = get_tree().root.get_node_or_null("DialogUI")
	if ui != null:
		ui.call("advance")
	await _settle()
	await _dump(title)
	await _force_finish()


func _settle() -> void:
	# 布局是异步收敛的（容器要等一轮 size 变化），多跑几帧再量。
	for i: int in 4:
		await get_tree().process_frame


## 收掉当前对话条 / 提示条，让下一个用例从干净状态开始。
##
## 【为什么直接读 DialogUI.is_open 而不是 get("is_open")】
##   `is_open` 是 **static var**，不是实例属性；`ui.get("is_open")` 会返回 null，
##   `bool(null)` == false → 清理循环一次都不跑，上一段对话就一直挂着。
func _force_finish() -> void:
	var ui: Node = get_tree().root.get_node_or_null("DialogUI")
	if ui == null:
		return
	var loop: int = 0
	while DialogUI.is_open and loop < 400:
		ui.call("advance")
		loop += 1
	ui.call("cancel_conversation")
	ui.call("dismiss_notice")
	await _settle()


## 让教程停手并收起它的面板（**不**写存档，探针不该改玩家档）。
## 【先 dismiss 再 poke】教程窗口是模态的，直接 poke 会把冻结令牌留在 PauseManager 里。
func _quiet_tutorial() -> void:
	TutorialSystem.dismiss_current_step()
	TutorialSystem.set("_enabled", false)
	TutorialSystem.set("_active", false)
	TutorialSystem.set("_index", -1)
	TutorialSystem.set_process(false)
	EventBus.tutorial_step_shown.emit(-1, "", "", false)
	PauseManager.clear_all()


# ============================================================================
# 私有方法 —— 遍历与判定
# ============================================================================

## 遍历目标 UI 的可见 Control，打印几何并判定越界 / 裁剪 / 重叠。
func _dump(title: String) -> void:
	print("")
	print("--- %s ---" % title)
	_boxes.clear()
	for target_name: String in TARGETS:
		var root_node: Node = get_tree().root.get_node_or_null(target_name)
		if root_node == null:
			print("  [SKIP] 找不到 %s" % target_name)
			continue
		print("  [%s]" % target_name)
		_walk(root_node, "", target_name)
	_check_overlap()


func _walk(node: Node, indent: String, tag: String) -> void:
	if node is Control:
		var c: Control = node as Control
		if c.is_visible_in_tree():
			var r: Rect2 = c.get_global_rect()
			var m: Vector2 = c.get_combined_minimum_size()
			var rel: String = _rel_path(c, tag)
			var name_path: String = tag + rel
			var extra: String = ""
			if c is Label:
				extra = "  \"%s\"" % _ellipsis((c as Label).text, 28)
			print("    %s%s  rect=(%.1f,%.1f %.1f×%.1f)  min=(%.1f×%.1f)  %s%s"
				% [indent, c.name, r.position.x, r.position.y, r.size.x, r.size.y,
					m.x, m.y, _flags(r, m), extra])
			_check_bounds(name_path, r)
			_check_clip(name_path, r, m)
			var is_empty: bool = c is Label and (c as Label).text.strip_edges() == ""
			_boxes.append({
				"path": name_path,
				"rect": r,
				"empty": is_empty,
				"passthrough": _is_passthrough(c),
			})
	for child: Node in node.get_children():
		_walk(child, indent + "  ", tag)


## 相对目标根节点的路径，便于阅读与定位。
func _rel_path(node: Node, tag: String) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var cur: Node = node
	while cur != null and String(cur.name) != tag:
		parts.append(String(cur.name))
		cur = cur.get_parent()
	var out: String = ""
	for i: int in range(parts.size() - 1, -1, -1):
		out += "/" + parts[i]
	return out


## 这个控件是不是"透明通道"（布局容器 / 全屏常驻层）。
##
## 透明通道不参与重叠判定 —— 它们本身不画任何东西，和谁相交都不是缺陷。
## 注意 **PanelContainer 不算透明通道**：它真的会画一块面板背景，
## "对话框背景压住了技能栏"这种就是真缺陷，必须能抓到。
func _is_passthrough(c: Control) -> bool:
	if LAYOUT_ONLY_TYPES.has(c.get_class()):
		return true
	# 全屏常驻的 Control：按项目硬规则它的 mouse_filter 必须是 IGNORE，
	# 作用只是"给子节点提供一个坐标系"，不画东西。
	var r: Rect2 = c.get_global_rect()
	return r.size.x >= CANVAS.x - EPS and r.size.y >= CANVAS.y - EPS


func _ellipsis(s: String, limit: int) -> String:
	return s if s.length() <= limit else s.substr(0, limit) + "…"


## 只做标注用的短标记（不参与计数，计数在 _check_* 里统一做）。
func _flags(r: Rect2, m: Vector2) -> String:
	var tags: PackedStringArray = PackedStringArray()
	if _is_out(r):
		tags.append("OUT")
	if m.x > r.size.x + EPS or m.y > r.size.y + EPS:
		tags.append("CLIP")
	return " ".join(tags)


func _is_out(r: Rect2) -> bool:
	return r.position.x < -EPS or r.position.y < -EPS \
		or r.end.x > CANVAS.x + EPS or r.end.y > CANVAS.y + EPS


func _check_bounds(path: String, r: Rect2) -> void:
	if not _is_out(r):
		return
	_out += 1
	_issues.append("OUT  %s  rect=(%.1f,%.1f %.1f×%.1f) 越出画布 %s"
		% [path, r.position.x, r.position.y, r.size.x, r.size.y, str(CANVAS)])


func _check_clip(path: String, r: Rect2, m: Vector2) -> void:
	if m.x <= r.size.x + EPS and m.y <= r.size.y + EPS:
		return
	_clip += 1
	_issues.append("CLIP %s  内容需要 %.1f×%.1f，实际只有 %.1f×%.1f"
		% [path, m.x, m.y, r.size.x, r.size.y])


## 两两比较可见控件的矩形，报出"互不相干却相交"的组合。
##
## 【为什么要排掉"透明通道"】
##   全屏常驻的 Root、VBox/HBox 这类纯布局容器本身不画任何像素，
##   它们和任何东西相交都无所谓 —— 报出来全是假警报。
##   真正要抓的是"两个各自独立的可见元素撞在一起"，比如提示条压住 HUD 飘字。
##   判定见 `_is_passthrough()`。
##
## 【踩过的坑：曾经用"清单里有没有子节点"当容器判据】
##   那个判据在"对话框没打开"的那一帧会失效：Root 的 Notice/Bar 全隐藏 →
##   清单里只剩 Root 自己 → 被误判成叶子 → 和 HUD 的每个控件都报一次重叠
##   （实测 9 条假警报）。容器身份不该随可见性变化，所以改成按类名 / 全屏判定。
func _check_overlap() -> void:
	for i: int in _boxes.size():
		var a: Dictionary = _boxes[i]
		var pa: String = a["path"]
		if bool(a["passthrough"]) or _is_empty_label(a):
			continue
		for j: int in range(i + 1, _boxes.size()):
			var b: Dictionary = _boxes[j]
			var pb: String = b["path"]
			if bool(b["passthrough"]) or _is_empty_label(b):
				continue
			if _is_ancestor(pa, pb) or _is_ancestor(pb, pa):
				continue
			var ra: Rect2 = a["rect"]
			var rb: Rect2 = b["rect"]
			if not ra.intersects(rb):
				continue
			var inter: Rect2 = ra.intersection(rb)
			# 只报"有实际交集面积"的，边缘刚好贴住（面积为 0）不算。
			if inter.size.x * inter.size.y < 1.0:
				continue
			var key_l: String = pa if pa < pb else pb
			var key_r: String = pb if pa < pb else pa
			if OVERLAP_ALLOWED.has(key_l + "|" + key_r):
				continue
			_overlap += 1
			_issues.append("OVERLAP %s 与 %s 相交 %.0f×%.0f"
				% [pa, pb, inter.size.x, inter.size.y])


## 空 Label 不画任何东西，不该参与重叠判定。
func _is_empty_label(entry: Dictionary) -> bool:
	return bool(entry["empty"])


func _is_ancestor(maybe_ancestor: String, path: String) -> bool:
	return path.begins_with(maybe_ancestor + "/")
