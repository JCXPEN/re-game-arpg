## DialogueLine —— 对话的**一句**（结构化数据的最小单元）
##
## 【负责什么】
##   描述"一句话要怎么演"：谁说的、说什么、用什么样式、哪些字逐个打出来、
##   要不要自动推进、要不要配立绘/头像/表情。
##   本文件**只描述数据**，不做任何显示；显示全部由 `DialogUI` 负责。
##
## 【挂哪个节点】
##   不是节点。保存在 `res://data/dialogue/*.tres`，被 `DialogueScript.lines` 引用。
##
## 【依赖谁】
##   无。刻意不依赖任何 UI / EventBus —— 数据层要能被单测直接构造。
##
## 【怎么扩展】
##   · 想加一种"文本样式"→ 在 `Style` 里加枚举 + 在 `tools/generate_theme.gd` 的
##     对话变体里加同名 Label 变体（样式只存在于 Theme，节点上不许写 override）。
##   · 想加一种"显示方式"→ 在 `Display` 里加枚举 + 在 `DialogUI._show_line` 里加分支。
##   · 玩法相关的临时字段一律塞 `meta`，不要为了一个玩法往这里加 @export。
##
## 【为什么说话人放在"行"上、而整段也有 speaker_default】
##   一段对话里换人是常态（长老说完村民插一句）。行级 `speaker` 非空就覆盖整段默认，
##   为空则回落到 `DialogueScript.speaker_default`。这样"整段一个人"不用每行重复写名字，
##   而"半路换人"也不用为此拆成两段对话（拆段会丢掉一次性奖励的结算语义）。
class_name DialogueLine
extends Resource

# ============================================================================
# enum
# ============================================================================

## 文本样式。**每一项都必须对应 ui_theme.tres 里的一个 Label 类型变体**，
## 由 `tools/generate_theme.gd` 的 `_setup_dialogue_variations()` 定义。
## 这里刻意只放"语义"，不放字号/颜色 —— 数值全部集中在主题生成器里。
enum Style {
	BODY,     ## 常规对白：正常字色、正文字号
	EMPHASIS, ## 强调：高亮金色，用于关键情报
	WHISPER,  ## 低语 / 旁白：更暗、更小的提示字号
	SHOUT,    ## 呼喊：更大更亮，用于情绪爆发
	SYSTEM,   ## 系统音 / 机械提示：冷色，和世界观对白区分开
}

## 显示方式。
enum Display {
	TYPEWRITER, ## 逐字打出（默认，像素 RPG 的手感来源）
	INSTANT,    ## 立即显示整句（系统提示、快节奏场景用）
	AUTO,       ## 逐字打出后自动推进，不需要玩家点
}

## 头像 / 立绘出现的位置（**预留字段**，已接好渲染挂点）。
enum PortraitSlot {
	NONE,   ## 不显示（默认）
	LEFT,   ## 对话框左侧
	RIGHT,  ## 对话框右侧
	CENTER, ## 屏幕中央（大立绘 / 过场）
	INLINE, ## 名字左边的小头像（16×16，跟着表头排版走）
}

# ============================================================================
# @export —— 文本
# ============================================================================

@export_group("文本")
## 说话人。空 = 用整段的 `DialogueScript.speaker_default`；都为空则不显示名字栏。
@export var speaker: String = ""
## 正文。可以多行，`DialogUI` 会按宽度自动折行，**不需要**手工数换行符。
@export_multiline var text: String = ""
## 文本样式（决定用哪个 Label 变体）。
@export var style: Style = Style.BODY

# ============================================================================
# @export —— 显示方式
# ============================================================================

@export_group("显示方式")
## 怎么把这句话显示出来。
@export var display: Display = Display.TYPEWRITER
## `AUTO` 用：整句显示完之后停顿多久自动推进（秒）。
@export_range(0.2, 10.0, 0.1, "suffix:s") var auto_delay: float = 1.6
## 打字速度覆盖（字符/秒）。<=0 表示用 `DialogUI` 的全局默认值。
@export_range(0.0, 240.0, 1.0, "suffix:cps") var chars_per_sec: float = 0.0

# ============================================================================
# @export —— 立绘 / 头像 / 表情（预留，已接好渲染挂点）
# ============================================================================

@export_group("立绘与表情")
## 立绘 / 头像贴图。为空则不显示任何东西（默认就是空）。
@export var portrait: Texture2D
## 放在哪里，见 `PortraitSlot`。
@export var portrait_slot: PortraitSlot = PortraitSlot.NONE
## 立绘相对挂点的微调（像素）。
## **注意**：`Vector2` 不能挂 `@export_range`（那是给 float / float 数组用的，
## 挂上去会直接编译失败），所以这里只给默认值。
@export var portrait_offset: Vector2 = Vector2.ZERO
## 是否左右镜像立绘（省一张素材）。
@export var portrait_flip: bool = false
## 表情状态名，如 &"smile" / &"angry"。本行若为空则用整段的默认表情。
## 语义交给表现层：`DialogUI` 会把它透传给 `EventBus.portrait_state_changed`，
## 未来接"按表情切帧的立绘"时不需要改这里。
@export var expression: StringName = &""

# ============================================================================
# @export —— 表现
# ============================================================================

@export_group("表现")
## 逐字显示时每个字的语音音效（空 = 静音）。同一句里会按 `voice_pitch` 微调音高。
@export var voice_sfx: AudioStream
## 语音音高（避免同一句里"哒哒哒"完全一样）。
@export_range(0.5, 2.0, 0.01) var voice_pitch: float = 1.0
## 这句话显示时是否让对话框轻微抖动（惊讶 / 震动场景）。
@export var shake: bool = false

# ============================================================================
# @export —— 扩展
# ============================================================================

@export_group("扩展")
## 预留字段。玩法层可往里塞任何东西（条件、跳转目标、任务标记…），
## 表现层完全不解释它。**不复用 meta 存表现参数** —— 表现参数请加正经 @export。
@export var meta: Dictionary = {}

# ============================================================================
# 公开方法
# ============================================================================

## 这句话最终由谁来说。空表示"没有名字栏"。
func resolve_speaker(script_default: String) -> String:
	return speaker if speaker.strip_edges() != "" else script_default


## 这句话最终用哪张立绘（行级优先，回落到整段默认）。
func resolve_portrait(script_default: Texture2D) -> Texture2D:
	return portrait if portrait != null else script_default


## 这句话最终的显示方式。
## `script_auto_all`（整段强制自动推进）优先级最高：它一开，本行无论是打字机还是
## 瞬显，都会在播完后自己往下走 —— 用于"自动播放的过场对话"，不需要逐行去改。
func resolve_display(script_auto_all: bool) -> Display:
	return Display.AUTO if script_auto_all else display


## 这句话最终的打字速度。<=0 表示"用调用方的默认值"。
func resolve_chars_per_sec(global_default: float) -> float:
	return chars_per_sec if chars_per_sec > 0.0 else global_default


## 这句话一共要打多少个字（后续按宽度分页时要用）。
func text_length() -> int:
	return text.length()


## 纯文本行：给"只想快速写一句话"的场合用（代码里构造、测试里造数据）。
static func make(line_text: String, line_speaker: String = "",
		line_style: Style = Style.BODY,
		line_display: Display = Display.TYPEWRITER) -> DialogueLine:
	var line: DialogueLine = DialogueLine.new()
	line.text = line_text
	line.speaker = line_speaker
	line.style = line_style
	line.display = line_display
	return line
