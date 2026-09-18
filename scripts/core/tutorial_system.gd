## TutorialSystem —— 新手教程系统（Autoload 单例）
##
## 【负责什么】
##   按顺序播放 TutorialStep：显示提示、监听玩家是否完成指定动作、推进到下一步。
##   只在"新档"（GameState.tutorial_completed 为 false）时运行。
##
## 【挂哪个节点】
##   project.godot 的 [autoload] 注册为 `TutorialSystem`。
##
## 【依赖谁】
##   DataRegistry（读教程步骤）、EventBus（显示提示）、GameState（记录是否看过）。
##
## 【怎么扩展】
##   加步骤只需新增 .tres；加"完成条件"在 _is_action_done 里加一个分支。
##
## 【冻结（pause_game）怎么工作 —— 本项目对"系统级阻塞"的唯一实现】
##   本系统是教程步骤冻结令牌的唯一所有者（`PauseManager.freeze(PAUSE_OWNER, ...)`）：
##     · 冻结与否由**当前这一刻的状态推导**（`_sync_pause()`），不是"在若干出口里
##       手动成对 freeze/unfreeze" —— 后者漏掉任何一个出口都会把玩家永久冻住；
##     · 冻结与"这一步是否独占屏幕"分开声明：教程提示不遮挡下方窗口，
##       所以声明 `Cover.WORLD`，让对话条在被冻住的世界里照常显示（见 PauseManager）；
##     · 步骤被误配（要求玩家在世界里做事却冻结世界）时，护栏会拒绝冻结（见
##       `_step_wants_freeze`），否则完成条件永远不可能达成 —— 表现为"NPC 对话
##       点了没反应 / 永远不显示"。
##
## 【注意】
##   本脚本注册为 autoload `TutorialSystem`，所以**不能**再写 class_name
##   （同名会和 autoload 冲突，报 "hides an autoload singleton"）。
extends Node

# ============================================================================
# 信号
# ============================================================================

## 教程完成。
signal finished()

# ============================================================================
# 私有变量
# ============================================================================

## 排好序的步骤列表。
var _steps: Array[TutorialStep] = []
## 当前步骤索引。
var _index: int = -1
## 当前步骤是否正在显示。
var _active: bool = false
## 当前步骤的计时器。
var _timer: float = 0.0
## 当前步骤是否已满足推进条件。
var _step_done: bool = false
## 教程是否已启用（新档才启用）。
var _enabled: bool = false
## 已完成的动作集合（用于触发条件判断）。
var _done_actions: Dictionary = {}
## 已播过的步骤索引集合，避免换关卡时重复播同一步。
var _shown_steps: Dictionary = {}
## 当前步骤是否要冻结世界。在 `_show_step` 里按**数据 + 语义护栏**算一次，
## 之后由 `_sync_pause()` 把它同步给 PauseManager。
##
## 【为什么不直接读 `_steps[_index].pause_game`】因为这个值与"这一步在屏幕上要不要
##   独占"必须完全一致（UI 的输入/Esc 路由也读它），而护栏（见 `_step_wants_freeze`）
##   会让"数据说冻结、语义不允许"的步骤落回非阻塞。算一次存起来，两个消费者就不会各说各话。
var _current_freeze: bool = false

# ============================================================================
# 常量
# ============================================================================

## 本系统在 PauseManager 里的令牌 id。
const PAUSE_OWNER: StringName = &"tutorial"

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	# 【为什么必须 ALWAYS】本系统的推进靠 _process 里的倒计时与完成条件判定。
	# 只要有任意一步配了 pause_game = true，get_tree().paused 就会把它一起冻住：
	# 教程面板还挂在屏幕上，但 auto_hide 永不倒数、_is_action_done 永不检查，
	# 玩家按 F 也推不动（本节点收不到 _unhandled_input）→ 教程死锁。
	# 当前数据里还没有配 pause_game 的步骤，属潜伏缺陷；这里提前兜住。
	# 与 TutorialUI / HelpPanel 一致：“停的是游戏世界，活的是弹窗”。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_steps()
	EventBus.scene_changed.connect(_on_scene_changed)
	# 监听玩家动作，用于推进"做了某事才算完成"的步骤。
	EventBus.hit_landed.connect(_on_hit_landed)
	EventBus.modifier_chosen.connect(func(_m: ModifierData) -> void: _mark_action(&"pick_modifier"))
	# 玩家开始与 NPC 对话 → 标记"交谈"完成。教程里"靠近村民按 [F] 交谈"这一步
	# 用它当完成条件：这一步要求玩家**在世界里做事**，所以绝不能冻结世界
	# （见 _step_wants_freeze 的护栏），并且"说了话"才算过关，而不是等 8 秒自动消失。
	EventBus.dialog_opened.connect(func() -> void: _mark_action(&"talk"))
	# 是否启用由 Boot 决定（新档启用，老档跳过）。
	set_process(false)


func _process(delta: float) -> void:
	# 【为什么连下标一起校验】_steps / _index 会在换局、数据重载、测试打桩时被改写，
	# 一旦 "正在显示" 与 "下标有效" 不一致，下面第一行就会越界崩溃 ——
	# 冻结系统尤其不能靠"状态恰好一致"活着。
	if not _active or _index < 0 or _index >= _steps.size():
		return
	# 检查"完成条件"。
	if not _step_done and _is_action_done(_steps[_index].trigger_action):
		_step_done = true
		if not _steps[_index].require_confirm:
			_advance()
		return
	# 自动隐藏。
	if not _steps[_index].require_confirm:
		_timer -= delta
		if _timer <= 0.0:
			_advance()


func _unhandled_input(event: InputEvent) -> void:
	if not _active or _index < 0 or _index >= _steps.size():
		return
	# 需要确认的步骤，按交互键推进。
	if _steps[_index].require_confirm and event.is_action_pressed(&"interact"):
		_advance()
		get_viewport().set_input_as_handled()


# ============================================================================
# 公开方法
# ============================================================================

## 开始教程（Boot 在开新档时调用）。
func start_tutorial() -> void:
	if GameState.tutorial_completed:
		return
	_enabled = true
	_index = -1
	_shown_steps.clear()
	set_process(true)
	# 兜底：重开教程时先把自己那份冻结状态归零（旧局可能停在某个阻塞步上）。
	_active = false
	_current_freeze = false
	_sync_pause()
	# 如果已经在某个关卡里，立刻尝试播第一步。
	_try_start_next()


## 跳过教程（玩家在菜单里选"跳过"）。
func skip_tutorial() -> void:
	_enabled = false
	_active = false
	_current_freeze = false
	_index = -1
	set_process(false)
	# 收起可能正挂在屏幕上的提示（含它占用的弹窗位置）。
	EventBus.tutorial_step_shown.emit(-1, "", "", false)
	# 交还冻结令牌：这一步漏掉的话，玩家在"阻塞型步骤显示期间选择跳过"时
	# 会被永久冻在暂停里 —— 界面没了，游戏也不动，只能强退。
	_sync_pause()
	GameState.tutorial_completed = true
	GameState.save_game()
	EventBus.toast_requested.emit("已跳过教程")


## 教程是否正在进行。
func is_running() -> bool:
	return _enabled


## 复位整个教程状态（回主菜单 / 换局时用）。
##
## 【为什么必须要它】_enabled / _active / _index / _shown_steps 都是**跨场景**
##   状态。回主菜单再开新档时若不复位，新档会接着上一局的 index 往下走，
##   表现为"教程从中间开始 / 第一步永远不播"。
##   注意只清"进度"，**不动** GameState.tutorial_completed（那是存档语义）。
func reset() -> void:
	_enabled = false
	_active = false
	_current_freeze = false
	_index = -1
	_step_done = false
	_timer = 0.0
	_shown_steps.clear()
	_done_actions.clear()
	set_process(false)
	# 交还可能还握着的暂停令牌（换局时旧令牌全部作废，这里只是兜底）。
	# 换局路径上 PauseManager.clear_all() 也会清一遍，两处互为冗余。
	_sync_pause()


## 当前步骤索引（调试用）。
func get_current_index() -> int:
	return _index


## 当前这一步是否属于"系统级阻塞"（要冻结游戏、独占屏幕）。
##
## 判定依据见 `_step_wants_freeze`（数据 `TutorialStep.pause_game` + 语义护栏）：
##   true  —— 重要提示：世界停下来，玩家读完/关掉再继续；
##   false —— 操作类提示（"靠近村民按 [F] 交谈"、"打不过就翻滚"…）：
##            世界照常跑，提示只是顶部浮层。**必须是非阻塞的**，否则提示自己
##            就成了完成条件（世界暂停 → NPC 收不到玩家、对话被排队）。
##
## 【为什么由本系统回答】冻结与占屏都属于"这一步要不要玩家停下来"的语义，
##   而那是本系统按 order 播放的数据；让唯一的所有者回答，UI 与系统才不会各说各话。
##   注意返回值与 `_sync_pause()` 用的是**同一个** `_current_freeze`：
##   UI 认为"这是阻塞窗口"而系统没冻结（或反之）会导致两个窗口同时抢屏。
func is_current_step_blocking() -> bool:
	if not _active:
		return false
	return _current_freeze


# ============================================================================
# 私有方法
# ============================================================================

## 从 DataRegistry 读所有教程步骤并排序。
func _load_steps() -> void:
	_steps.clear()
	for res: Resource in DataRegistry.get_all(&"TutorialStep"):
		var step: TutorialStep = res as TutorialStep
		if step != null:
			_steps.append(step)
	_steps.sort_custom(func(a: TutorialStep, b: TutorialStep) -> bool: return a.order < b.order)


## 尝试开始下一步。
##
## 【关键】不能"跳过所有不匹配的步骤"——start_tutorial 往往在还没有当前关卡时
## 被调用（主菜单阶段），此时每一步都不匹配，一跳过就把 14 步全走完并直接 _finish()，
## 表现为"教程瞬间自毁、一帧都没播"。
## 正确语义：如果当前步骤不属于本关卡，就**原地等待**，等切到该关卡再播。
func _try_start_next() -> void:
	var next_index: int = _index + 1
	if next_index >= _steps.size():
		_finish()
		return
	var step: TutorialStep = _steps[next_index]
	# 没有当前关卡（主菜单阶段）→ 保持待命，等 scene_changed 再试。
	var level: LevelData = SceneDirector.get_current_level()
	if level == null:
		_index = next_index
		return
	if not _step_matches_level(step):
		# 本步属于其它关卡：原地待命，不要跳过。
		_index = next_index
		return
	_index = next_index
	_show_step(_steps[_index])


## 该步骤是否应该在当前关卡播放。
func _step_matches_level(step: TutorialStep) -> bool:
	if step.level_id == &"":
		return true
	var level: LevelData = SceneDirector.get_current_level()
	return level != null and level.id == step.level_id


## 显示一步。
func _show_step(step: TutorialStep) -> void:
	_active = true
	_step_done = false
	_timer = step.auto_hide
	_shown_steps[_index] = true
	# 冻结与否在这里**算一次**，然后由 `_sync_pause()` 同步给 PauseManager：
	# 想冻就已经冻着、不想冻就保证没冻 —— 不需要"我冻过没有"的布尔记账。
	_current_freeze = _step_wants_freeze(step)
	_sync_pause()
	# 教程文字**只**走 TutorialUI 一条通道（顶部提示面板）。
	# 旧实现同时又发一次 dialog_requested，于是同一句话在屏幕上出现两遍
	# （顶部面板 + 底部对话框），既占画面又让人以为弹了两个东西。
	# 第三个参数 require_confirm 决定要不要显示"按 F 继续"——自动消失的步骤
	# 不该提示按键，否则等于在骗玩家按键盘。
	EventBus.tutorial_step_shown.emit(_index, step.title, step.text, step.require_confirm)


## 推进到下一步。
## 冻结状态由 `_sync_pause()` 在**下一步确定之后**统一同步：
##   · 下一步仍是阻塞步 → 令牌一直没交还，冻结连续不断；
##   · 下一步是普通提示   → 令牌在这里交还，世界恢复。
## 旧写法是"先 unfreeze、再 show 下一步（可能又 freeze）"，中间会发一次
## freeze_ended / freeze_started 并让持有者集合短暂变空 —— 任何监听冻结状态的系统
## （BGM、AI、自动存档、过场）都会在那一下以为"游戏恢复了"。
func _advance() -> void:
	if not _active:
		return
	_active = false
	_current_freeze = false
	# 通知 UI 收起提示（UI 会同时让出它占的弹窗位置）。
	EventBus.tutorial_step_shown.emit(-1, "", "", false)
	_try_start_next()
	_sync_pause()


## 玩家主动跳过当前步骤（按 Esc / 点击关闭按钮 / 点空白）。
##
## 【为什么有这条】
##   开场教程`auto_hide=6.0`——它不需要玩家做任何事就自动消失，
##   但旧实现里玩家**无法手动关**。如果玩家已经懂了，硬等 6 秒还挡视线。
##   现在允许玩家主动 dismiss，立即推进到下一步（自然衔接）。
##
## 【注意】
##   必须勾上 `_shown_steps[_index]`——不然切场景时 on_scene_changed 看到这步还没
##   shown，会再次 _show_step，结果就是"绕过关闭再被同一句提示糊一脸"。
func dismiss_current_step() -> void:
	if not _active:
		return
	if _index < 0 or _index >= _steps.size():
		return
	_active = false
	_current_freeze = false
	_shown_steps[_index] = true
	EventBus.tutorial_step_shown.emit(-1, "", "", false)
	_try_start_next()
	_sync_pause()


## 把"当前要不要冻结世界"同步给 PauseManager（幂等，是本系统唯一的冻结入口）。
##
## 【为什么是"同步"而不是 freeze/unfreeze 成对调用 —— 这就是本系统曾经的缺陷】
##   旧写法用自己的布尔 `_pause_owner_active` 记住"我冻过没有"，再在若干出口里
##   手动 `unfreeze`。任何一条出口漏写（例如 `skip_tutorial()`）令牌就永久留在
##   PauseManager 里 —— 玩家在世界被冻结、界面又已消失的状态下被永久锁死；
##   反过来在"本来没冻"的路径上调用 unfreeze 又会把别人的令牌一起放跑。
##   现在改成：**期望状态由当前步骤推导**，每次状态变化都调一次本函数 ——
##   多调、漏调、重复调都不会产生错误状态，也不依赖任何布尔"记得准"。
##   owner 传 self：本系统被释放时由 PauseManager 兜底回收令牌。
func _sync_pause() -> void:
	PauseManager.set_frozen(PAUSE_OWNER, _should_freeze_now(),
		PauseManager.Cover.WORLD, self)


## 当前这一刻是否应该冻结世界。
func _should_freeze_now() -> bool:
	return _active and _current_freeze


## 这一步是否要冻结世界（在 `_show_step` 里调用一次，同时会告警一次数据问题）。
##
## 【数据 + 语义护栏，两者都要】
##   · 数据（`TutorialStep.pause_game`）说"这是不是系统级重要提示"；
##   · 护栏说"冻结之后这一步还做得完吗"：**要求玩家在世界里做事才能完成的步骤
##     （`trigger_action` 非空）绝不允许冻结** —— 世界一停，NPC 的 Area2D 收不到玩家、
##     攻击打不出去、三选一也弹不出来，完成条件永远不可能达成。
##     典型受害者就是"靠近村民按 [F] 交谈"这类步骤：一旦被误配成 `pause_game = true`，
##     玩家按 F 毫无反应、NPC 对话永远不显示 —— 表现为"对话系统坏了"，
##     实际是冻结把完成条件自己掐死了。
##   冻结必须与"这一步能不能完成"自洽，而不是无条件相信一个数据开关。
func _step_wants_freeze(step: TutorialStep) -> bool:
	if step == null or not step.pause_game:
		return false
	if step.trigger_action != &"":
		push_warning("[TutorialSystem] 步骤「%s」同时配了 pause_game 与 trigger_action(%s)："
			% [step.title, step.trigger_action]
			+ "冻结会让完成条件永远无法达成，已按非阻塞处理")
		return false
	return true


## 教程结束。
func _finish() -> void:
	_enabled = false
	_active = false
	_current_freeze = false
	set_process(false)
	# 兜底交还令牌：任何一条走到"教程结束"的路径都不该让世界留在冻结里。
	_sync_pause()
	GameState.tutorial_completed = true
	GameState.save_game()
	EventBus.tutorial_finished.emit()
	EventBus.toast_requested.emit("教程完成！祝你好运。")
	finished.emit()


## 该步骤的完成条件是否满足。
func _is_action_done(action: StringName) -> bool:
	if action == &"":
		return false
	return _done_actions.has(action)


## 记录一个已完成的动作。
func _mark_action(action: StringName) -> void:
	_done_actions[action] = true


# ============================================================================
# 信号回调
# ============================================================================

func _on_scene_changed(_scene: Node) -> void:
	if not _enabled or _active:
		return
	# 换关卡后重新评估"当前这一步"是否该播。
	# 注意要退一格：_try_start_next 取的是 _index+1，而主菜单阶段已经把
	# _index 推到了待播的那一步。
	if _index >= 0 and _index < _steps.size() and not _step_shown(_index):
		# 【为什么这里也要过 _step_matches_level】
		#   本入口曾经直接 _show_step(_steps[_index])，绕过了关卡过滤：
		#   在城镇里跳完 3 步后待播的是 field 的 step_010，
		#   这时玩家若先进了 boss_room，"战斗：普攻"就会在 Boss 房的门口糊脸——
		#   和 _try_start_next 的语义自相矛盾。两个入口必须走同一套判定。
		if _step_matches_level(_steps[_index]):
			_show_step(_steps[_index])
		return
	_try_start_next()


## 某一步是否已经播过。
func _step_shown(index: int) -> bool:
	return _shown_steps.has(index)


## 玩家成功命中敌人 → 标记"攻击"动作完成。
func _on_hit_landed(_attacker: Node, _target: Node, _amount: float, _knockback: Vector2) -> void:
	_mark_action(&"attack")
