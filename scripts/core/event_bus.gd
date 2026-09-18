## EventBus —— 全局信号总线（Autoload 单例）
##
## 【负责什么】
##   跨系统通信的唯一通道。任何两个系统（玩家/敌人/UI/构筑/关卡）之间都不允许
##   互相持有引用，只能通过这里的信号收发。这样任一系统可以被单独删除或替换。
##
## 【挂哪个节点】
##   project.godot 的 [autoload] 中注册为 `EventBus`，全局可直接访问。
##
## 【依赖谁】
##   不依赖任何东西。必须最先初始化（autoload 列表第一位），否则别人连不上。
##
## 【怎么扩展】
##   新增信号时按"领域_事件"命名（如 `combat_hit_landed`），并在下方分区里归类。
##   信号只带最必要的参数；复杂数据请传 Resource 或 Dictionary。
##
## 【约定】
##   本文件只放 signal 声明，不放任何逻辑与状态，避免变成上帝对象。
extends Node

# ============================================================================
# 战斗事件
# ============================================================================

## 某单位受到伤害。amount 为最终扣血量，is_crit 用于飘字区分颜色。
signal damage_dealt(target: Node, amount: float, is_crit: bool, hit_position: Vector2)
## 命中落地（攻击方视角），用于顿帧、音效、屏幕震动。
signal hit_landed(attacker: Node, target: Node, amount: float, knockback: Vector2)
## 单位死亡。killer 可能为 null（例如环境伤害）。
signal unit_died(unit: Node, killer: Node)
## 单位血量变化（UI 用）。ratio 已归一化到 0~1。
signal health_changed(unit: Node, current: float, maximum: float)
## 单位蓝量（MP）变化。
signal mana_changed(unit: Node, current: float, maximum: float)

# ============================================================================
# 玩家 / 成长事件
# ============================================================================

## 玩家等级或属性变化，UI 刷新用。
signal player_stats_changed(stats: Dictionary)
## 获得经验。
signal experience_gained(amount: int, current: int, required: int)
## 玩家死亡 / 复活。
signal player_died()
signal player_revived()
## 获得物品（背包 UI 用）。
signal item_acquired(item_id: StringName, count: int)
## 装备变更。
signal equipment_changed(slot: StringName, item_id: StringName)

# ============================================================================
# Roguelite 构筑事件
# ============================================================================

## 请求弹出三选一界面（词条候选列表）。由战斗/关卡触发，UI 响应。
signal modifier_choice_requested(candidates: Array[ModifierData])
## 玩家选定了某个词条。
signal modifier_chosen(modifier: ModifierData)
## 一局开始 / 结束（局内构筑清零的时机）。
signal run_started()
signal run_ended(victory: bool)

# ============================================================================
# 关卡 / 场景事件
# ============================================================================

## 请求切换场景（由门、楼梯、传送点发出）。SceneDirector 响应。
signal scene_change_requested(target: StringName, entry_point: StringName)
## 场景切换完成，参数为新场景根节点。
signal scene_changed(scene: Node)
## 房间清怪完成（用于关门/开门逻辑）。
signal room_cleared(room_id: StringName)
## Boss 被击败。
signal boss_defeated(boss_id: StringName)

# ============================================================================
# UI / 系统事件
# ============================================================================

## 显示一条飘字（伤害数字、拾取提示等）。
signal floating_text_requested(text: String, world_position: Vector2, color: Color)
## 通用提示信息。
signal toast_requested(message: String)
## 请求显示一条**非阻塞**单句提示（路牌、系统提示）。→ 顶部提示条。
## duration > 0 到时自动消失；duration <= 0 常驻（点击 / 走开 / 硬上限都能收掉）。
## 它**不**暂停游戏、**不**锁输入、**不**发 dialog_opened：玩家可以边走边打边看。
signal dialog_requested(message: String, duration: float)
## 请求显示一段**多句**对话（NPC 用）。→ 底部对话条。
## speaker 为空则不显示名字栏；lines 按顺序逐句推进，鼠标点击 / F 推进；
## 全部播完（或被推进到结束）时调用 on_finished，供发起方结算奖励。
## 中途被打断（玩家走开 / 换场景 / 死亡 / 打开背包）会取消，**不**调用 on_finished。
##
## 【与 dialog_script_requested 的分工】
##   本信号是**兼容入口**：只给"一串纯文本 + 一个说话人"的简单场合。
##   它内部会被 `DialogueScript.from_strings()` 转成结构化数据再送进去，
##   所以不需要为它单独维护一套显示逻辑。
signal dialog_sequence_requested(speaker: String, lines: PackedStringArray, on_finished: Callable)
## 请求显示一段**结构化**对话（DialogueScript）。→ 底部对话条。
##
## 与 dialog_sequence_requested 的区别只在"内容从哪来"：本信号的内容带有
## 逐句文本样式、显示方式、立绘 / 头像 / 表情、逐字语音等字段，
## 是"多样化、可编辑对话"的正式入口；后者只是它的降级包装。
## 结算语义完全一致：正常播完调用 on_finished，中途被打断则取消、不调用。
signal dialog_script_requested(script: DialogueScript, on_finished: Callable)
## 对话的"立绘 / 表情状态"发生变化（供未来的角色立绘层订阅）。
## line 可能为 null（对话结束 / 收起时）。
## 现在只有 `DialogUI` 内部的头像与立绘挂点会直接用它，
## 单独抽成信号是为了让"按表情切帧的立绘"能独立接上，不用改对话系统。
signal portrait_state_changed(line: DialogueLine)
## 对话条（多句对话）已打开。要防止"一次按键既推进对话又重新触发交互"的模块
## （可交互物）监听它；**不要**再据此锁玩家移动/攻击——那会把玩家卡死。
signal dialog_opened()
## 对话条已关闭（正常播完或被取消都会发）。
signal dialog_closed()
## 新手教程请求显示某一步。由 TutorialSystem 发出。
## step_index < 0 表示"收起提示"。
## require_confirm 为 true 时提示面板会显示"需要玩家确认"的按钮文案。
## 教程面板**只是显示层**：它自己不推进教程，玩家的点击会回调
## TutorialSystem.dismiss_current_step()，由系统决定下一步。
signal tutorial_step_shown(step_index: int, title: String, text: String, require_confirm: bool)
## 教程全部完成。
signal tutorial_finished()
## 顿帧请求（时长秒）。HitStop 单例响应。
signal hit_stop_requested(duration: float)
## 屏幕震动请求（强度、时长）。摄像机响应。
signal camera_shake_requested(amplitude: float, duration: float)
