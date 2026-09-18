## DialogTypewriter —— 打字机状态机（纯逻辑，不碰节点）
##
## 【负责什么】
##   只回答一个问题："当前这页文本，此刻应该显示出几个字"。
##   把文本、速度、是否瞬时显示收进来，逐帧推进；打完自动置 typing=false。
##   至于"显示到哪块 Label、要不要配音、按钮文案怎么改"，都是 DialogUI 的事。
##
## 【为什么抽成独立类】
##   "跳过动画"有两个入口（advance 的推进键、dismiss_by_player 的关闭键），
##   两处必须完全一致，否则又会出现"某个键按下时被判成没听完"的偏差。
##   状态收在一个对象里后，两个入口调的是同一个 finish()，天然不会走偏。
class_name DialogTypewriter
extends RefCounted

## 当前页完整文本。
var text: String = ""
## 本句打字速度（字符/秒），来自 `DialogueLine.resolve_chars_per_sec`。
var chars_per_sec: float = 45.0
## 是否正在打字。DialogUI 把它镜像到自己的 `_typing`（测试契约读那一边）。
var typing: bool = false

var _count: float = 0.0


## 开始一页。instant = true（INSTANT 显示方式）直接视为全文已显示。
func begin(p_text: String, p_chars_per_sec: float, instant: bool) -> void:
	text = p_text
	chars_per_sec = p_chars_per_sec
	_count = 0.0
	typing = not instant


## 推进一帧，返回此刻应显示的字符串（恰好打完时返回全文并置 typing=false）。
## 未在打字中时原样返回全文（幂等，不产生回退）。
func tick(delta: float) -> String:
	if not typing:
		return text
	_count += delta * chars_per_sec
	var shown: int = mini(int(_count), text.length())
	if shown >= text.length():
		typing = false
	return text.substr(0, shown)


## 立即补全整页（"跳过动画"），返回全文。
func finish() -> String:
	_count = float(text.length())
	typing = false
	return text


## 清空（对话结束 / 换关卡时的收尾复位）。
func reset() -> void:
	text = ""
	_count = 0.0
	typing = false
