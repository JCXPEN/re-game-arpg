## PauseManager —— 游戏暂停的**唯一所有者**（Autoload 单例）
##
## 【负责什么】
##   统一管理 `get_tree().paused`：谁想冻结游戏就 `freeze(owner_id)`，
##   想解冻就 `unfreeze(owner_id)`。**只要还有任何一个持有者没交还令牌，
##   游戏就保持暂停**；全部交还后才真正 resume。
##
## 【为什么需要它 —— 这是真实的缺陷】
##   原来每个窗口自己写一份 `_paused_by_me` + `get_tree().paused = false`：
##   `tutorial_ui` / `help_panel` / `inventory_ui` 各有一份，`tutorial_system`
##   还直接裸写 `get_tree().paused = true/false`。这套写法有三个必然的坑：
##
##     1. **叠加即错**：教程（自己 pause）之上再开帮助（看到已 paused 就不接管），
##        关掉帮助时没事；但如果先开帮助（接管）再开教程（不接管），
##        关掉**帮助**时它会把自己那次 resume —— 而教程还在屏幕上，游戏却跑起来了。
##     2. **外部抢先改状态就失控**：任何一处 `paused = false`（例如主菜单 _ready）
##        都会让所有持有者记的"我造成过暂停"变成脏数据，后续 resume 语义全乱。
##     3. **没有唯一真相**：出问题时没人能回答"现在到底是谁在保持暂停"。
##
##   令牌计数把这个模型变回可判定的：**持有者集合非空 ⇔ paused == true**。
##
## 【和 PROCESS_MODE_ALWAYS 的关系】
##   本管理器只负责 paused 这一位。想在暂停中继续收输入的窗口仍要自己设
##   `process_mode = PROCESS_MODE_ALWAYS` —— 那是"活着的例外"，两件事不冲突。
##
## 【令牌为什么必须带"是否独占屏幕"这一个语义位】
##   "世界停了"与"屏幕被谁占着"是两件不同的事，而**下层窗口要不要让位**取决于后者：
##     · 暂停菜单 / 背包 / 三选一 / 结算 / 帮助：自带全屏遮罩，把对话条压在下面 →
##       那时对话"看不见也关不掉"，必须主动收掉（见 Cover.SCREEN）；
##     · 教程系统提示 / Boss 出场这类系统级冻结：只是"世界停一下"，屏幕仍留给
##       下层窗口（对话条照常显示、照常能推能关，见 Cover.WORLD）。
##   把这条语义放在**声明冻结的地方**，比让每个窗口自己去猜"现在 paused 是不是因为
##   有人盖住我"要可靠得多 —— 后者正是旧实现里"一暂停就把 NPC 对话杀掉"的病灶：
##   一次教程冻结会把玩家正在读的整段话连同奖励回调一起静默丢掉。
##
## 【为什么不用 class_name】
##   注册为 autoload `PauseManager`，同名 class_name 会冲突。
extends Node

# ============================================================================
# 常量 / 枚举
# ============================================================================

## 冻结对"屏幕"的影响。声明冻结时必须一并说清，默认按 SCREEN（保守：宁可多收一次
## 下层窗口，也不要出现"被盖住却看不见也关不掉"）。
enum Cover {
	WORLD,   ## 只冻结世界：屏幕留给下层窗口（不遮挡任何东西）。
	SCREEN,  ## 冻结世界 + 独占屏幕（自带遮罩）→ 下层窗口应当主动收掉。
}

# ============================================================================
# 信号
# ============================================================================

## 游戏被真正冻结（从"未暂停"变成"暂停"）。
signal freeze_started()
## 游戏被真正恢复（最后一个持有者交还令牌）。
signal freeze_ended()
## 持有者集合发生变化（调试 / 测试用）。
signal holders_changed(holders: Array)

# ============================================================================
# 私有变量
# ============================================================================

## 当前持有暂停令牌的 id 集合。**空 ⇒ 未暂停**。
var _holders: Array[StringName] = []
## 每个持有者是否"独占屏幕"：{ owner_id: bool }。缺项按 true（保守）处理。
var _covers: Dictionary = {}
## 每个持有者绑定的对象（可空）：{ owner_id: Object }。
##
## 【为什么记它】持有者如果**没交还令牌就被释放**（窗口被 queue_free、关卡对象没了），
##   令牌会永远留在集合里 → 游戏永久暂停，而且没有任何界面解释为什么。
##   绑定之后由 `_prune_dead_holders()` 每帧兜底：对象已经失效 ⇒ 自动交还。
var _owners: Dictionary = {}
## 上一次真实应用的 paused 值。**只用于观测 / 避免重复发信号，不是权威**。
## 权威永远是 `get_tree().paused` 本身 —— 见 `_apply()` / `_reconcile()`。
var _applied: bool = false

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## 每帧校对"令牌集合"与"真实 paused 位"是否一致。
##
## 【为什么必须每帧校对 —— 这是真实的架构缺陷】
##   旧实现把 `_applied` 当作"我已经把 paused 写成什么了"的权威缓存。
##   一旦有**任何**外部代码直接写 `get_tree().paused`（旧版 main_menu._ready、
##   截图工具、将来某个图省事的系统，甚至引擎层面的状态重置），缓存就与真实位
##   脱节：此后 `freeze()` 看到 `want == _applied` 便**直接返回，什么都不写**。
##   结果是"PauseManager 认为自己已暂停、is_frozen() 返回 true，而游戏世界照常
##   运行"—— 玩家按 Esc 开了暂停菜单，角色却还能移动、还能放技能。
##
##   校对以真实位为准，把模型拉回不变量：**持有者集合非空 ⇔ paused == true**。
##   任何一次外部直写最多存活一帧就被纠正。
func _process(_delta: float) -> void:
	_prune_dead_holders()
	_reconcile()


## 把真实 paused 位与令牌集合对齐。只在真的不一致时写，避免无谓的抖动与信号。
func _reconcile() -> void:
	var want: bool = not _holders.is_empty()
	if get_tree().paused == want:
		_applied = want
		return
	_apply()


## 交还"持有者已被释放"的令牌 —— 冻结泄漏的最后一道防线。
##
## 【为什么必须有】令牌是"谁要求停着"的唯一真相，而持有者是会死的对象
##   （窗口被 queue_free、关卡里的对象随关卡销毁）。一旦有人没来得及 unfreeze
##   就消失了，令牌会永远留着 → 游戏永久暂停、屏幕上却没有任何东西解释原因。
##   这里以"绑定的对象是否还有效"为准，每帧兜底回收（持有者数量很少，成本可忽略）。
func _prune_dead_holders() -> void:
	if _owners.is_empty():
		return
	var dead: Array[StringName] = []
	for id: StringName in _owners.keys():
		# 【为什么按 Variant 取、并且两种"没了"的形态都要判】
		#   已释放的实例读回来可能是 null，也可能是一个"已释放引用"
		#   （赋给强类型 Object 变量会直接报 "Trying to assign invalid previously
		#   freed instance"）。两种都表示持有者已经不在了，都要回收。
		var obj: Variant = _owners[id]
		if obj == null or not is_instance_valid(obj):
			dead.append(id)
	if dead.is_empty():
		return
	var changed: bool = false
	for id: StringName in dead:
		_owners.erase(id)
		_covers.erase(id)
		if not _holders.has(id):
			continue
		_holders.erase(id)
		changed = true
		push_warning("[PauseManager] 持有者 %s 已被释放却未交还令牌，已自动回收" % id)
	if not changed:
		return
	holders_changed.emit(_holders.duplicate())
	_apply()


# ============================================================================
# 公开方法
# ============================================================================

## 申请冻结游戏。同一 id 重复申请只记一次，但会**更新**它的 `cover` / `owner`（幂等）。
##
## cover：本次冻结是否独占屏幕，见 `Cover`。默认 SCREEN（保守：宁可多收一次下层窗口）。
## owner：可选的对象（一般是发起冻结的节点）。它被释放时令牌自动交还，见 `_prune_dead_holders`。
func freeze(owner_id: StringName, cover: Cover = Cover.SCREEN, owner: Object = null) -> void:
	if owner_id == &"":
		push_warning("[PauseManager] freeze 需要非空 owner_id，已忽略")
		return
	_covers[owner_id] = cover == Cover.SCREEN
	if owner != null:
		_owners[owner_id] = owner
	if _holders.has(owner_id):
		return
	_holders.append(owner_id)
	holders_changed.emit(_holders.duplicate())
	_apply()


## 声明式冻结：把"我要不要冻结"直接同步过来，而不是自己记状态、成对调用 freeze/unfreeze。
##
## 【为什么它是本项目推荐的入口】成对调用要求调用方**每一个出口**都不漏
##   （本项目的教程系统就漏在 `skip_tutorial()` 上，把玩家永久冻在了暂停里）。
##   声明式写法天然幂等：期望状态由调用方从它自己的状态推导，多调/漏调都不会
##   产生错误状态，也不需要任何一个布尔"记得准"。
func set_frozen(owner_id: StringName, frozen: bool,
		cover: Cover = Cover.SCREEN, owner: Object = null) -> void:
	if frozen:
		freeze(owner_id, cover, owner)
	else:
		unfreeze(owner_id)


## 交还冻结令牌。不持有则忽略（幂等）。
func unfreeze(owner_id: StringName) -> void:
	_covers.erase(owner_id)
	_owners.erase(owner_id)
	if not _holders.has(owner_id):
		return
	_holders.erase(owner_id)
	holders_changed.emit(_holders.duplicate())
	_apply()


## 强制清空所有令牌并恢复游戏。
## 【什么时候用】回主菜单 / 重开一局 —— 此时所有旧窗口的令牌都已经没有意义，
##   留着它们只会让新局一开始就是暂停的。这**不是**绕过所有权，而是"换局"语义。
func clear_all() -> void:
	# 即便令牌本来就空，也要核对真实位：外部可能把 paused 留成了 true。
	if _holders.is_empty() and not get_tree().paused:
		_covers.clear()
		_owners.clear()
		_applied = false
		return
	_holders.clear()
	_covers.clear()
	_owners.clear()
	holders_changed.emit(_holders.duplicate())
	_apply()


## 是否有**独占屏幕**的持有者（见 Cover）。
##
## 【谁该问它】会被"更高的窗口"盖住的下层 UI（对话条是典型）：
##   世界被冻住但没人盖住它时，它应当继续显示、继续能关；一旦有独占屏幕的窗口
##   出现（暂停菜单 / 背包 / 结算…），它必须让位，否则会被压在遮罩下面"看不见也关不掉"。
##   判断依据是**冻结的声明者自己说了算**，而不是"paused 为真"这种一揽子猜测。
func covers_screen() -> bool:
	for id: StringName in _holders:
		# 缺项按 true：没声明过就按"可能盖住"处理（保守，宁可让下层让位）。
		if bool(_covers.get(id, true)):
			return true
	return false


## 是否处于冻结状态（以令牌集合为准，不信外部值）。
func is_frozen() -> bool:
	return not _holders.is_empty()

## 当前持有者（副本，供调试 / 测试断言）。
func get_holders() -> Array:
	return _holders.duplicate()

## 某窗口是否持有令牌。
func holds(owner_id: StringName) -> bool:
	return _holders.has(owner_id)

## 持有者数量。
func holder_count() -> int:
	return _holders.size()


# ============================================================================
# 私有方法
# ============================================================================

## 把令牌集合的真实状态写进 `get_tree().paused`。
##
## 【为什么以真实 paused 位为准、而不是比对缓存】
##   缓存在"外部直写 paused"后会脱节，导致 freeze 静默失效（见 `_process` 注释）。
##   这里先读真实位：位已经对了就只同步缓存、不发信号；位不对才写。
func _apply() -> void:
	var want: bool = not _holders.is_empty()
	if get_tree().paused == want:
		_applied = want
		return
	_applied = want
	get_tree().paused = want
	if want:
		freeze_started.emit()
	else:
		freeze_ended.emit()
