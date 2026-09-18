## NPC —— 可对话的城镇 NPC
##
## 【负责什么】
##   玩家靠近按 F 时弹出对话条，逐句显示对话（鼠标点击 / F 推进），
##   整段说完后触发奖励（给道具/金币/解锁法术）。
##   对话内容全部由 @export 配置，策划改文案不用碰代码。
##
## 【挂哪个节点】
##   scenes/world/npc.tscn 的根节点（继承 Interactable）。
##
## 【依赖谁】
##   EventBus（对话请求）、GameState（发奖励）、DialogUI（显示）。
##
## 【推进逻辑在哪】
##   不在本脚本：整段 lines 交给 DialogUI 排队播放，由它负责推进/关闭。
##   这样 NPC 不用自己维护"说到第几句"的状态，也不会和 F 键的交互检测打架。
##
## 【打断语义】
##   对话期间玩家可以自由走动/攻击（对话不锁操作），走出一定距离对话即被
##   取消，**不**算说完。`once` 与奖励只在真正结算时才生效，所以半路走开
##   不会白白消耗掉一次性的奖励。
class_name NPC
extends Interactable

# ============================================================================
# @export
# ============================================================================

## NPC 名字（显示在对话条上方）。
@export var npc_name: String = "村民"
## 对话内容，按顺序逐条显示。**最简单的写法**：只写文案。
## 需要逐句换样式 / 换说话人 / 配立绘头像时，改用 `dialogue`（它的优先级更高）。
@export var lines: PackedStringArray = PackedStringArray(["你好，旅行者。"])
## 结构化对话（可选）。填了就**优先用它**，`lines` 被忽略。
##
## 【为什么两种并存而不是一刀切】
##   `lines` 是"一句话说完"的便利写法（生成器、快速摆一个村民都用它，测试也大量依赖）；
##   `dialogue` 是"要表现"的正式写法（文本样式、显示方式、立绘头像表情、逐字语音）。
##   两者在 UI 层是**同一条路径**：`lines` 会被 `DialogueScript.from_strings()`
##   转成结构化数据再显示，所以显示行为、结算时机完全一致，不存在两套逻辑。
@export var dialogue: DialogueScript
## 对话全部结束后给予的物品 id（可空）。
@export var give_item_id: StringName = &""
## 对话全部结束后给的金币。
@export var give_gold: int = 0
## 对话结束后解锁的法术 id（可空）。
@export var unlock_spell_id: StringName = &""
## 是否只说一次（说完就不再触发）。
@export var once: bool = false

# ============================================================================
# 私有变量
# ============================================================================

## 是否已经说完（once 用）。
var _finished: bool = false

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	super._ready()
	prompt_text = "交谈"
	face_player = true
	cooldown = 0.3
	if interact_sfx == null:
		interact_sfx = load("res://assets/audio/sfx/Coin.wav")


# ============================================================================
# 私有方法
# ============================================================================

func _on_interact(_actor: Node) -> void:
	if once and _finished:
		# 已经说过：只给一句简短回应，不再重复奖励。
		EventBus.dialog_requested.emit("%s：路上小心。" % npc_name, 2.0)
		return
	# 结构化对话优先（带了样式/立绘/显示方式的那一套）。
	if dialogue != null and dialogue.has_content():
		# 整段交给 DialogUI 播放；正常播完才回调结算奖励。
		EventBus.dialog_script_requested.emit(dialogue, _grant_rewards)
		return
	if lines.is_empty():
		return
	# 整段交给 DialogUI 排队播放；正常播完才回调结算奖励。
	# 注意这里**不**提前把 `_finished` 置位：玩家要是听一半走开（对话被取消），
	# 这次交谈就当没发生过，回来还能重听——否则一次性奖励会被半句话白白吃掉。
	EventBus.dialog_sequence_requested.emit(npc_name, lines, _grant_rewards)


## 对话结束的奖励结算。只有正常播完（或被玩家跳到最后一句）才会走到这里。
func _grant_rewards() -> void:
	_finished = true
	if give_gold > 0:
		GameState.add_gold(give_gold)
		EventBus.floating_text_requested.emit("+%d 金币" % give_gold, global_position + Vector2(0, -16), Color(1, 0.85, 0.3))
	if give_item_id != &"":
		GameState.add_item(give_item_id, 1)
		var item: ItemData = DataRegistry.get_item(give_item_id)
		if item != null:
			EventBus.toast_requested.emit("获得：%s" % item.display_name)
	if unlock_spell_id != &"":
		GameState.unlock_spell(unlock_spell_id)
		var spell: SpellData = DataRegistry.get_spell(unlock_spell_id)
		if spell != null:
			EventBus.toast_requested.emit("学会法术：%s" % spell.display_name)
