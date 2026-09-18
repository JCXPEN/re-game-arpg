## SignPost —— 提示牌
##
## 【负责什么】
##   玩家靠近按 F 时在屏幕**顶部**显示一条**非阻塞**提示（玩家可以边走边打边看，
##   不会被打断操作，点击提示条即可收起）。用于操作提示、剧情、路标。
##
## 【挂哪个节点】
##   scenes/world/sign_post.tscn 的根节点（继承 Interactable）。
##
## 【依赖谁】
##   EventBus（toast / 对话框请求）。
class_name SignPost
extends Interactable

# ============================================================================
# @export
# ============================================================================

## 要显示的文字。支持多行。
@export_multiline var message: String = "这里什么也没写。"
## 显示时长（秒）。0 表示"常驻"——但常驻仍有三条收尾途径：点击提示条、
## 玩家走开、或达到 DialogUI.notice_max_lifetime 硬上限，所以不会永远关不掉。
@export_range(0.0, 30.0, 0.5, "suffix:s") var display_time: float = 3.5

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	super._ready()
	prompt_text = "查看"
	cooldown = 0.5
	if interact_sfx == null:
		interact_sfx = load("res://assets/audio/sfx/MiniImpact.wav")


# ============================================================================
# 私有方法
# ============================================================================

func _on_interact(_actor: Node) -> void:
	EventBus.dialog_requested.emit(message, display_time)
