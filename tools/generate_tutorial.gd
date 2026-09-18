## GenerateTutorial —— 生成新手教程步骤（编辑器工具脚本）
##
## 【负责什么】
##   把教程文案写成 .tres，按关卡分段：城镇教基础操作，野外教战斗，地牢教机制。
##
## 【怎么运行】
##   Godot --headless --path . res://tools/generate_tutorial.tscn
extends Node

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("res://data/tutorial")
	# pause_game 语义（与 TutorialSystem._step_wants_freeze 的护栏配套）：
	#   · 纯"读说明"的系统级提示 → true：窗口开着时世界冻结（不能跑动/挨打）；
	#   · 要玩家**在世界里做事**的步骤（attack / talk / pick_modifier）→ false：
	#     冻结会让完成条件永远达不成（护栏也会兜底拒绝）。
	# --- 城镇：移动与交互 ---
	_step(0, "欢迎来到边境小镇", "用 WASD / 方向键移动。\n先在小镇里走走，熟悉一下操作。", &"town", 1.0, false, 6.0, &"", true)
	_step(1, "与 NPC 交谈", "靠近村民按 [F] 交谈。\n他们会给你提示和道具。", &"town", 0.5, false, 8.0, &"talk", false)
	_step(2, "前往野外", "小镇右侧的出口通往风鸣平原。\n走过去会自动切换场景。", &"town", 0.5, false, 6.0, &"", true)

	# --- 野外：战斗基础 ---
	_step(10, "战斗：普攻", "靠近敌人，用 [鼠标左键] 或 [J] 攻击。\n连按可以打出三段连击。", &"field", 1.2, false, 8.0, &"attack", false)
	_step(11, "翻滚与无敌", "按 [空格] 翻滚。翻滚期间无敌，\n还能取消攻击后摇，是保命的关键。", &"field", 0.5, false, 8.0, &"", true)
	_step(12, "蓄力重击", "按住 [鼠标右键] 蓄力，松开释放重击。\n蓄满伤害和范围都最大。", &"field", 0.5, false, 8.0, &"", true)
	_step(13, "打开宝箱", "主路之外的角落常有宝箱。\n靠近按 [F] 打开。", &"field", 0.5, false, 6.0, &"", true)

	# --- 地牢：进阶机制 ---
	_step(20, "法术与技能", "[Q]/[E]/[R] 释放三个法术，[1]/[2] 释放技能。\n法术消耗 MP，注意蓝量。", &"dungeon_1", 1.2, false, 8.0, &"", true)
	_step(21, "远程敌人", "法师会保持距离放火球。\n用翻滚接近，或用远程手段反制。", &"dungeon_1", 0.5, false, 8.0, &"", true)
	_step(22, "清空房间得强化", "清光一个房间的所有敌人后，\n会弹出三选一强化。选一个让自己变强。", &"dungeon_1", 0.5, false, 8.0, &"pick_modifier", false)
	_step(23, "存档点", "地牢里有存档点（发光的法阵）。\n交互后回满状态并记录复活点，死亡不用从头再来。", &"dungeon_1", 0.5, false, 8.0, &"", true)

	# --- Boss 前厅 ---
	_step(30, "精英敌人", "赤武士会蓄力冲锋，冲锋前有停顿。\n看准时机翻滚躲开，再反击。", &"dungeon_2", 1.0, false, 8.0, &"", true)
	_step(31, "Boss 就在前方", "门后的巢穴里是独眼巨人。\n它攻击范围大，注意观察前摇。", &"dungeon_2", 0.5, false, 8.0, &"", true)

	# --- Boss 房 ---
	_step(40, "最终决战", "独眼巨人的重砸会造成大范围伤害。\n看到它抬手就翻滚拉开距离，攻击间隙再上前。", &"boss_room", 1.2, false, 9.0, &"", true)

	print("[GenerateTutorial] 教程步骤生成完毕")
	get_tree().quit()


# ============================================================================
# 私有方法
# ============================================================================

## 生成一步。
func _step(order: int, title: String, text: String, level_id: StringName,
		delay: float, require_confirm: bool, auto_hide: float, trigger: StringName,
		pause_game: bool = false) -> void:
	var step: TutorialStep = TutorialStep.new()
	step.order = order
	step.title = title
	step.text = text
	step.level_id = level_id
	step.delay = delay
	step.require_confirm = require_confirm
	step.auto_hide = auto_hide
	step.trigger_action = trigger
	step.pause_game = pause_game
	var err: int = ResourceSaver.save(step, "res://data/tutorial/step_%03d.tres" % order)
	if err != OK:
		push_error("[GenerateTutorial] 保存失败 step_%03d：%d" % [order, err])
