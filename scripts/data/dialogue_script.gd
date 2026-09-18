## DialogueScript —— 对话的**一整段**（结构化对话配置的顶层资源）
##
## 【负责什么】
##   把"一段对话"变成一个可以整段保存、整段复用的 `.tres`：
##   默认说话人 / 默认立绘 / 默认表情 / 逐句内容 / 对话条样式 / 是否强制自动推进。
##   它是 NPC 对话、剧情过场、系统旁白的**统一内容来源**。
##
## 【挂哪个节点】
##   不是节点。保存在 `res://data/dialogue/*.tres`。
##   NPC 用 `@export var dialogue: DialogueScript` 引用它（见 `scripts/world/npc.gd`）。
##
## 【依赖谁】
##   DialogueLine（每一句）。刻意**不**依赖 EventBus / UI。
##
## 【怎么扩展】
##   · 新的"整段级"表现（例如"整段都加回声"）→ 在 `DialogueScript` 加 @export，
##     在 `DialogUI._show_pending` 里读一次、对本段所有行生效。
##   · 条件分支 / 多结局对话 → 用 `meta` 挂后续步骤，或新写一个"对话调度器"，
##     **不要**把 if/else 塞进本类（本类只描述"演什么"，不描述"接下来演哪段"）。
##
## 【为什么 lines 用 Array[DialogueLine] 而不是 Dictionary/数组套数组】
##   Dictionary 在编辑器里没法校验字段名，写错一个键要到运行时才发现；
##   Array[DialogueLine] 在 Inspector 里是"一个个可展开的对象"，策划直接改文案，
##   且有静态类型 —— `DataRegistry` 也能按 `class_name` 把它归类进资源库。
class_name DialogueScript
extends Resource

# ============================================================================
# enum
# ============================================================================

## 整段的"对话条样式"。决定对话框本身的形态，和单句的文本样式正交。
enum BarStyle {
	NORMAL,   ## 常规：底部细条，圆角硬边（默认）
	NARRATOR, ## 旁白：无名、居中、略窄，用于"很久以前……"这类叙事
	SYSTEM,   ## 系统：贴顶、更暗，用于系统播报
}

# ============================================================================
# @export —— 身份与默认值
# ============================================================================

@export_group("身份")
## 唯一 id，便于按 id 从资源库取回（空表示不参与索引）。
@export var id: StringName = &""
## 本段的默认说话人。行级 `DialogueLine.speaker` 非空时以行为准。
@export var speaker_default: String = ""

@export_group("默认表现")
## 本段的默认立绘（行级优先）。
@export var portrait_default: Texture2D
## 本段的默认头像 / 立绘位置（行级优先）。
@export var portrait_slot_default: DialogueLine.PortraitSlot = DialogueLine.PortraitSlot.NONE
## 本段的默认表情状态名（行级优先）。
@export var expression_default: StringName = &""
## 对话条样式。
@export var bar_style: BarStyle = BarStyle.NORMAL
## 是否整段强制自动推进（过场用）。开了之后每句播完自动往下走。
@export var auto_advance_all: bool = false
## 自动推进时每句的默认停顿（行级 `auto_delay` 非 0 时以行为准）。
@export_range(0.2, 10.0, 0.1, "suffix:s") var auto_delay_default: float = 1.6

@export_group("内容")
## 逐句内容，按顺序播放。
@export var lines: Array[DialogueLine] = []

@export_group("扩展")
## 预留字段。玩法层可挂任务 id、触发条件、后续步骤等，表现层不解释。
@export var meta: Dictionary = {}

# ============================================================================
# 公开方法
# ============================================================================

## 有没有实际内容（空段不应该开对话窗口）。
func has_content() -> bool:
	return not lines.is_empty()


## 句子数量。
func line_count() -> int:
	return lines.size()


## 取第 i 句；越界返回 null（调用方自己判空，不要在这里抛）。
func get_line(index: int) -> DialogueLine:
	if index < 0 or index >= lines.size():
		return null
	return lines[index]


## 把本段的所有文本拼起来（调试 / 测试 / 字数统计用）。
func joined_text() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for line: DialogueLine in lines:
		if line != null:
			parts.append(line.text)
	return "\n".join(parts)


## 本段的纯文本句数统计（含空行），供"排版是否合理"的自检用。
func longest_line_length() -> int:
	var longest: int = 0
	for line: DialogueLine in lines:
		if line != null:
			longest = maxi(longest, line.text.length())
	return longest


## 从旧的 `PackedStringArray` 造一段对话 —— **兼容层**。
##
## 【为什么需要它】
##   改造前 NPC 用 `PackedStringArray` 存文案，`EventBus.dialog_sequence_requested`
##   也以它为参数，测试里大量构造这种数据。直接删掉会让所有既有 NPC/测试一起炸。
##   所以保留旧入口，在**进入 UI 的瞬间**转成 DialogueLine，内部只认结构化数据。
static func from_strings(speaker: String, raw_lines: PackedStringArray,
		style: DialogueLine.Style = DialogueLine.Style.BODY) -> DialogueScript:
	var script: DialogueScript = DialogueScript.new()
	script.speaker_default = speaker
	script.lines = []
	for raw: String in raw_lines:
		# 旧格式没有行级说话人，全部回落到 speaker_default。
		script.lines.append(DialogueLine.make(raw, "", style))
	return script


## 从一串纯文本快速造一段对话（测试 / 代码构造用）。
static func from_text_array(texts: Array[String], speaker: String = "") -> DialogueScript:
	var script: DialogueScript = DialogueScript.new()
	script.speaker_default = speaker
	script.lines = []
	for t: String in texts:
		script.lines.append(DialogueLine.make(t))
	return script
