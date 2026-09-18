## CaptureFlow —— 按真实游玩路径截图（专供视觉验收 / Bug 复核）
##
## 【负责什么】
##   capture_all.tscn 是"直接瞬移进关卡"，会掩盖掉只在真实流程里出现的问题
##   （例如主菜单停留后才点开始导致 HUD 没绑上玩家）。本脚本忠实复刻：
##     主菜单 → 点「新的冒险」→ 城镇 → 野外战斗 → 三选一 → 背包 / 暂停 / 结算
##
## 【怎么运行】
##   Godot --path . --resolution 1280x720 res://tools/capture_flow.tscn
extends Node

var _dir: String = "user://screenshots_flow"
## 真实主场景（boot），包含它自己的常驻 UI 安装逻辑。
var _boot: Node

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(_dir)
	# 关键：实例化真正的 boot.tscn，而不是手动拼一套 UI。
	_boot = load("res://scenes/core/boot.tscn").instantiate()
	_boot.name = "Boot"
	# boot._ready 里也在延迟挂载子节点，这里同样要延迟，否则报 "Parent node is busy"。
	get_tree().root.add_child.call_deferred(_boot)
	await get_tree().process_frame
	await get_tree().process_frame

	await _shot("01_main_menu")

	# 模拟玩家点「新的冒险」。
	var menu: Node = get_tree().root.get_node_or_null("MainMenu")
	if menu != null:
		var btn: Node = menu.find_child("btn_new_game", true, false)
		if btn != null:
			(btn as Button).pressed.emit()
		else:
			push_warning("[CaptureFlow] 主菜单里找不到 btn_new_game")
		await get_tree().process_frame

	# 等转场 + 关卡生成。
	await _settle()
	await _shot("02_town")

	# 去野外，让玩家/敌人同屏。
	SceneDirector.change_to_level(&"field", &"from_town")
	await _settle()
	await _shot("03_field")

	# 打一只怪：把敌人拖到玩家面前狠狠揍，验证飘字/扣血表现。
	await _fight()
	await _shot("04_field_combat")

	# 玩家掉血，看看血条是不是跟着变。
	var player: Node = get_tree().get_first_node_in_group(&"player")
	if player is Actor:
		var info: DamageInfo = DamageInfo.new()
		info.amount = 34.0
		info.source = null
		(player as Actor).grant_invulnerability(0.0)
		(player as Actor).apply_damage(info)
		await _settle(8)
		await _shot("05_player_hurt")

	# 三选一（Popped by 清怪 / 手动触发）。
	var mc: Node = get_tree().root.get_node_or_null("ModifierChoice")
	if mc != null:
		var cands: Array[ModifierData] = ModifierSystem.roll_candidates(3)
		EventBus.modifier_choice_requested.emit(cands)
		await _settle(6)
		await _shot("06_modifier_choice")

	# 背包。
	var inv: Node = get_tree().root.get_node_or_null("InventoryUI")
	if inv != null:
		GameState.add_gold(128)
		GameState.add_item(&"potion_life", 3)
		get_tree().paused = false
		mc.visible = false if mc != null else false
		inv.call("open")
		await _settle(6)
		await _shot("07_inventory")
		inv.call("close")

	# 暂停菜单。
	var pause: Node = get_tree().root.get_node_or_null("PauseMenu")
	if pause != null:
		pause.visible = true
		await _settle(6)
		await _shot("08_pause")
		pause.visible = false

	# 结算界面。
	var over: Node = get_tree().root.get_node_or_null("GameOverUI")
	if over != null:
		over.visible = true
		over.call("_show_panel", "你倒下了", "从最近的存档点重新出发，或返回主菜单。", true)
		await _settle(6)
		await _shot("09_gameover")
		over.visible = false
		get_tree().paused = false

	print("[CaptureFlow] 全部截图完成 → ", ProjectSettings.globalize_path(_dir))
	get_tree().quit()


## 让玩家和最近的敌人互相打一会儿。
func _fight() -> void:
	var player: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
	var enemies: Array[Node] = get_tree().get_nodes_in_group(&"enemy")
	if player == null or enemies.is_empty():
		return
	var target: Node2D = enemies[0] as Node2D
	if target == null:
		return
	# 把敌人挪到玩家右前方，保证镜头内能看见。
	target.global_position = player.global_position + Vector2(34.0, 0.0)
	await get_tree().physics_frame
	for i: int in 40:
		var combat: Node = player.get_node_or_null("Combat")
		if combat != null and combat.has_method("request_light_attack"):
			combat.call("request_light_attack")
		if i % 12 == 0:
			target.global_position = player.global_position + Vector2(34.0, 0.0)
		await get_tree().physics_frame


func _settle(extra_frames: int = 0) -> void:
	for i: int in 240:
		if not SceneDirector.is_changing():
			break
		await get_tree().process_frame
	for i: int in 8 + extra_frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_dir.path_join("%s.png" % label))
	print("[CaptureFlow] ", label)
