## TutorialStep —— 新手教程的一步（数据驱动）
##
## 【负责什么】
##   描述教程中的一步：显示什么文字、要玩家做什么、在哪个关卡触发。
##   教程内容全部做成 .tres，改文案/加步骤不用动代码。
##
## 【挂哪个节点】
##   不是节点。保存在 res://data/tutorial/*.tres，由 TutorialSystem 按 order 排序播放。
##
## 【怎么扩展】
##   新增一步 = 新建一个 .tres 并设好 order。新增触发类型 = 在 GameEnums 里
##   加 TutorialTrigger 枚举 + TutorialSystem 里加判断分支。
class_name TutorialStep
extends Resource

# ============================================================================
# 基础
# ============================================================================

## 播放顺序，小的先播。
@export_range(0, 999, 1) var order: int = 0
## 标题（显示在提示框顶部）。
@export var title: String = "操作提示"
## 正文。支持多行。
@export_multiline var text: String = ""
## 提示图标（可空）。
@export var icon: Texture2D

# ============================================================================
# 触发条件
# ============================================================================

## 在哪个关卡触发。空表示任意关卡。
@export var level_id: StringName = &""
## 进入关卡后延迟多少秒再显示。
@export_range(0.0, 30.0, 0.1, "suffix:s") var delay: float = 0.5
## 是否必须等玩家按下"确认"才继续（false 则自动消失）。
@export var require_confirm: bool = false
## 自动消失时长（require_confirm 为 false 时生效）。
@export_range(0.5, 30.0, 0.5, "suffix:s") var auto_hide: float = 5.0
## 是否要求玩家完成某个动作才推进到下一步。
## 可选值见 GameEnums.TutorialTrigger 的说明；空表示"看完即完成"。
## 已接入的动作：`attack`（命中敌人）、`pick_modifier`（选完三选一）、
## `talk`（开始与 NPC 对话，由 `dialog_opened` 打标）。
## 注意：非空即"要玩家在世界里做事"→ 本步骤不允许冻结世界（见 pause_game）。
@export var trigger_action: StringName = &""

# ============================================================================
# 表现
# ============================================================================

## 是否暂停游戏（重要提示用 true，操作提示用 false）。
##
## 【注意：不是"填了就一定冻结"】要求玩家在世界里做事才能完成的步骤
##   （`trigger_action` 非空，例如"靠近村民按 [F] 交谈"）即使填 true 也**不会**冻结
##   —— 冻结会让完成条件永远无法达成。判定见 `TutorialSystem._step_wants_freeze()`：
##   冻结必须与"这一步能不能完成"自洽，而不是无条件相信一个数据开关。
@export var pause_game: bool = false
