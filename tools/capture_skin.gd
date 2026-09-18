## CaptureSkinSheet —— 用**真实 Button 节点**渲染四态样张并截图
##
## 【负责什么】
##   实例化真实的 Button（挂各类型变体），摆成
##   normal / hover / pressed / disabled 四列，截图到 user://skin/skin_sheet.png。
##
## 【为什么用真实 Button 而不是直接 box.draw()】
##   第一版直接 `stylebox.draw(canvas_item, rect)` 画出来是一片纯白——
##   那样绕过了控件的状态机与内容边距，画出来的不是玩家看到的东西，
##   而且会把"文字有没有下沉"这类**内容层**的行为整个漏掉。
##   用真实 Button 才能验证到"按下时文字位移"这种关键反馈。
##
## 【怎么运行】
##   Godot --resolution 1280x720 res://tools/capture_skin.tscn
##   鼠标会被 warp 到第 0 行第 1 格以产生真实 hover。
extends Control

const VARIANTS := ["Button", "PrimaryButton", "QuietButton", "DangerButton"]
const STATES := ["normal", "hover", "pressed", "disabled"]
const CELL_W := 74.0
## 按钮真实高度由"字体行高 + 内容边距"决定（12px 点阵字行高约 23 + 8 = 31），
## 写 26 会被最小尺寸顶回去，导致采样窗口和画面对不上。
const CELL_H := 32.0
const GAP_X := 4.0
const GAP_Y := 8.0
const X0 := 4.0
const Y0 := 12.0

var _buttons: Array[Button] = []


func _ready() -> void:
	var theme: Theme = load("res://resources/ui_theme.tres") as Theme
	if theme != null:
		self.theme = theme
	for r: int in VARIANTS.size():
		for c: int in STATES.size():
			var btn := Button.new()
			btn.theme_type_variation = StringName(VARIANTS[r])
			btn.text = STATES[c]
			btn.toggle_mode = true          ## 让 pressed 态能稳定保持
			btn.set_position(Vector2(X0 + float(c) * (CELL_W + GAP_X),
				Y0 + float(r) * (CELL_H + GAP_Y)))
			btn.set_size(Vector2(CELL_W, CELL_H))
			btn.set_meta(&"cell", "%s/%s" % [VARIANTS[r], STATES[c]])
			# hover 无法用代码稳定触发（warp_mouse 用窗口坐标、事件注入又打不中），
			# 所以直接把 hover 的 StyleBox 顶到 normal 位——走的还是真实绘制路径。
			if STATES[c] == "hover" and theme != null:
				var hover_box: StyleBox = theme.get_stylebox("hover", VARIANTS[r])
				if hover_box != null:
					btn.add_theme_stylebox_override("normal", hover_box)
				btn.add_theme_color_override("font_color",
					theme.get_color("font_hover_color", VARIANTS[r]))
			_buttons.append(btn)
			if STATES[c] == "pressed":
				btn.set_pressed_no_signal(true)
			elif STATES[c] == "disabled":
				btn.disabled = true
			add_child(btn)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	# 输出每个按钮的**真实矩形**（最小尺寸可能把 set_size 顶大），供外部精确取样。
	for b: Button in _buttons:
		var rc: Rect2 = b.get_rect()
		print("[CaptureSkin] RECT %s %d %d %d %d" % [b.get_meta(&"cell"),
			int(rc.position.x), int(rc.position.y), int(rc.size.x), int(rc.size.y)])
	var img: Image = get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://skin")
	var path := "user://skin/skin_sheet.png"
	var err: int = img.save_png(ProjectSettings.globalize_path(path))
	print("[CaptureSkin] %s（err=%d）→ %s"
		% ["保存完毕" if err == OK else "保存失败", err, ProjectSettings.globalize_path(path)])
	get_tree().quit()
