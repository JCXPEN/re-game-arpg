# 开发日志（LOG.md）

按时间倒序记录每次改动：改了什么、为什么、验证方式。

---

## 2026-09-15（二）—— "窗口开着 = 世界停着"：教程窗口真正冻结 + NPC 对话不再闪没

### 用户反馈（实测复现）

> "冻结依然存在 bug，在窗口存在时我依然可以移动和受伤！npc 窗口依然没有。"

用真实一局（boot + 城镇 + 真实输入）逐项取证（临时复现脚本，已删）：

| 取证项 | 结果 |
|---|---|
| 教程窗口显示时按住方向键 0.5s | **位移 55.4px** —— 世界根本没冻结 |
| 此刻 `paused` / 令牌 | `false` / 空 —— 因为 14 条教程步骤**没有一条**配 `pause_game = true`，冻结代码是死代码 |
| 站到村民旁按 F | 对话条**能**弹出（截图 `repro_03` 可见） |
| 但玩家一边移动一边读 | **26px 就被"走远即取消"收掉** —— 窗口闪一下就没了，体感即"NPC 窗口没有" |
| 教程面板 vs HUD Toast | 面板把 y=40 的 "[F] 交谈" Toast **整个埋在背后**，玩家根本不知道要按 F |

结论：上一轮把冻结**机制**修可靠了（令牌/所有权/护栏），但**策略**仍是"教程提示不冻结、
对话不冻结"，与用户的预期（窗口开着 = 世界停着）相反；而"对话开着还能跑"又直接
制造了"NPC 窗口闪没"的第二症状。

### 改了什么

**1) 对话条成为模态窗口：开着 = 世界冻结（`Cover.WORLD`）**

- `DialogUI._show_pending()` 开条时 `PauseManager.set_frozen(&"dialog", true, WORLD, self)`，
  `_end_bar()` 关条时交还；`release_popup=false`（马上要重开一段）时保持连续，
  不发中途的 freeze_ended/freeze_started（与"连续阻塞步之间冻结不断"同一条原则）。
- 效果：读对话时**不能**跑动、**不会**挨打；对话**不会**被走动瞬间取消；
  关闭入口（J/回车/点条/F/右键/关闭按钮）在冻结期间全部可用，关掉即恢复。
  旧"对话锁输入导致永久卡死"的病根不在这里——那次是**改输入**而不是**持令牌**；
  现在冻结是 PauseManager 的令牌（唯一所有者 + 多条强制收尾 + 死持有者回收兜底）。
- 新增 `DialogUI.force_close()`：补齐 GameFlow 换局契约（收起 + 交还弹窗位置 + 冻结令牌），
  消灭"只把 visible 关掉、is_open/令牌残留"的说不清状态。
- "走远即取消"降级为**兜底路径**保留（冻结万一没生效 / 被击退时仍能脱身）。

**2) 教程步骤数据：系统级提示真的冻结**

- 14 条步骤补 `pause_game`：纯"读说明"的步骤（000/002/011/012/013/020/021/023/030/031/040）
  = `true`；要玩家**在世界里做事**的三条（010 普攻 / 022 三选一 / 001 交谈）= `false`
  ——上一轮加的护栏（`_step_wants_freeze`）本来也会拒绝冻结它们，这里把数据写对，避免告警。
- `step_001 "与 NPC 交谈"` 补 `trigger_action = &"talk"`：这一步现在**真的以"说了话"为完成条件**
  （TutorialSystem 监听 `dialog_opened` 打标），不再等 8 秒自动消失；也因为它要求玩家
  在世界里做事，所以不冻结——玩家能走近按 F，NPC 窗口才出得来。
- `tools/generate_tutorial.gd` 同步（重新生成不会丢掉这批标志）。

**3) HUD Toast 给教程面板让位**

- `TutorialUI` 新增静态 `panel_bottom`（每帧上报面板底边，与 `DialogUI.notice_bottom` 同一套机制）；
  HUD 的 Toast 排到 `maxf(40, notice_bottom, panel_bottom) + 4`。
  此前教程面板把 "[F] 交谈" Toast 埋在背后——玩家站在村民旁边却看不到提示。

**4) 测试契约同步（两处是有意变更，不是回归）**

- `weapon_dialog_test` B6 由"对话期间玩家依然能行动"改写为"**对话期间世界冻结、
  关掉即恢复、玩家永远拿得回控制权**"（后者才是当年"卡游戏进程"要保的性质）；
  B7"走开即取消"降级为兜底路径说明。
- 各套件的 `_quiet_tutorial()` 改为**先走系统的 dismiss 路径再 poke 私有状态**：
  教程窗口现在是模态的，直接 `set("_active", false)` 会把冻结令牌留在 PauseManager 里，
  让后续用例跑在冻结里（B10 的"F 触发不了交互"就是这么假失败的）。涉及
  `weapon_dialog_test / dialogue_system_test / ui_layout_probe / capture_dialog / freeze_contract_test / playability_check`。
- `freeze_contract_test` 新增 C0"窗口开着 = 世界冻结（教程提示与对话一视同仁）"，
  C2 补"补位的对话接管屏幕并持有自己的令牌"。套件 50 项。

### 验证

**端到端（真实一局 + 真实输入，临时脚本已删）**：
教程窗口显示 → `paused=true`、按住方向键位移 **0.00px**、玩家 `can_process=false`；
Esc 关掉 → `paused=false`、位移 55.4px（能跑）；走近村民按 F → 对话条弹出、
`paused=true`（读对话不挨打）；关掉对话 → 世界恢复。`freeze_contract_test` 50/50。

**全量回归 20 套件全绿**：`freeze_contract`(50) · `dialogue_system`(71) · `esc_lifecycle`(29) ·
`esc_contract`(39) · `game_flow`(31) · `ui_registry`(25) · `audit_regression`(36) ·
`verify_fixes`(18) · `playability`(15) · `delivery`(93) · `smoke`(42) · `combat`(9) ·
`combat_arch`(15) · `audit_found`(7) · `bug_hunt`(37) · `bug_hunt2`(5) ·
`settings_contract`(21) · `popup_contract`(15) · `material_isolation`(10)；
`weapon_dialog` 50/1（唯一红灯仍是既有问题：编辑器把已删的 `big_sword.tscn` 写回磁盘）；
`ui_layout_probe` 越界 0 / 裁剪 0 / 重叠 0。

### 经验（已可复用）

> "窗口开着 = 世界停着"要**成对**成立：窗口显示时申请冻结令牌，收起时交还；
> 语义上用 `Cover.WORLD`（只停世界、不遮屏幕），让"能不能看到 / 关不掉"与
> "世界停不停"解耦。另外，测试**绕过系统直接 poke 私有状态**时，必须先走系统的
> 正常退出路径把副作用（令牌/槽位）交还——否则测试自己制造出它想抓的 bug。

---

## 2026-09-15 —— 冻结逻辑重做：状态推导的暂停令牌 + 冻结期间对话照常显示

### 症状

1. 教程的系统级步骤（`TutorialStep.pause_game`）"有时冻不住、有时解不冻"。
2. 与之相关：**NPC 对话在冻结期间无法显示** —— 对话会静默消失，连奖励回调一起丢。

现网数据里还没有配 `pause_game = true` 的步骤，所以症状是潜伏的；但冻结**记账**上已经有一条
必现的泄漏路径（见根因 1.a），且"对话被冻结误伤"在系统级冻结一出现时就会立刻显形。

### 根因

**1) `TutorialSystem` 用"私有布尔 + 成对 freeze/unfreeze"记账 —— 漏一条出口就永久冻住**

```gdscript
var _pause_owner_active: bool = false          # "我冻过没有"
if step.pause_game:
	_pause_owner_active = true
	PauseManager.freeze(PAUSE_OWNER)           # 冻
func _release_pause():                         # 解
	if not _pause_owner_active: return
	_pause_owner_active = false
	PauseManager.unfreeze(PAUSE_OWNER)
```

- **a. `skip_tutorial()` 漏了 `_release_pause()`**：玩家在阻塞步显示期间点"跳过"→
  界面收起了，令牌却留在 PauseManager 里 → **世界永久冻结、屏幕上没有任何东西解释原因**
  （只能强退）。`_finish()` 同样只靠"推进路径会先解冻"侥幸成立。
- **b. `_advance()` 先解冻再显示下一步**，下一步若是阻塞步又冻回来：两件事之间会发
  `freeze_ended` + `freeze_started`，持有者集合短暂变空 —— 任何监听冻结状态的系统
  （BGM / AI / 自动存档 / 过场）都会在那一下以为"游戏恢复了"。连续两个阻塞步之间
  **冻结必须是连续的**，这才是"冻结可靠"的含义。
- **c. 判据分叉**：`is_current_step_blocking()`（UI 的输入与 Esc 路由用）直接读
  `step.pause_game`，而冻结走另一条 if —— 任何一处调整（例如后面加的语义护栏）
  都会让"UI 认为这是阻塞窗口、系统却没冻结"，结果是两个窗口抢屏。

**2) `DialogUI._process` 用 `if get_tree().paused` 一揽子收掉对话 —— 把"世界停了"错当成"有人盖住我"**

```gdscript
if close_when_paused and get_tree().paused:
	if is_open: cancel_conversation()      # 整段话 + on_finished 奖励回调一起丢
	if notice_open: dismiss_notice()
```

- 系统级冻结（教程提示 / Boss 出场 / 未来任何 `Cover.WORLD` 的冻结）只是"世界停一下"，
  对话条层级比它高、也照样收得到输入 —— 收掉纯属误伤：玩家看到的是"对话闪一下就没了"，
  NPC 的一次性奖励也被白丢。
- 反过来，对话正排队等显示时世界被冻住，会"刚显示就被收掉"。

**3) `PauseManager` 答不出"这个冻结会不会盖住我"**，也管不了"持有者被释放却没交还令牌"
（令牌集合里只有一个 `paused` 位，没有屏幕语义、没有存活校验）。

### 改了什么

**1) `PauseManager` —— 冻结声明带上屏幕语义 + 自愈**

- 新增 `Cover { WORLD, SCREEN }`：`WORLD` = 只停世界（屏幕留给下层窗口）；
  `SCREEN` = 停世界 + 独占屏幕（自带遮罩，下层应当让位）。**默认 SCREEN**（保守：
  宁可多收一次下层窗口，也不要"被盖住却看不见也关不掉"）。
- 新增**声明式**入口 `set_frozen(owner_id, want, cover, owner)`：期望状态由调用方从
  自己的状态推导，天然幂等 —— 不需要任何布尔"记得准"，多调/漏调都不会产生错误状态。
- 新增 `covers_screen()`：有没有"独占屏幕"的持有者。判定集中在声明冻结的地方，
  不再让每个窗口去猜。
- `freeze(id, cover, owner)` 可绑定发起者对象；`_process` 每帧回收"对象已释放却没交还
  令牌"的条目（冻结泄漏的最后一道防线）。
  （踩坑：已释放实例读回来可能是 `null`，也可能是"已释放引用"，后者赋给强类型
  `Object` 变量会直接报 `Trying to assign invalid previously freed instance` ——
  必须按 `Variant` 取、两种形态都判。）

**2) `TutorialSystem` —— 冻结由状态推导，四条出口全部同步**

- `_pause_owner_active` 换成 `_current_freeze`（在 `_show_step` 里算一次），并由
  `_sync_pause()` 同步给 PauseManager；`_show_step / _advance / dismiss_current_step /
  skip_tutorial / reset / _finish / start_tutorial` 全部调它。
- `_advance()` 改成"先定下一步 → 再同步冻结"：连续阻塞步之间令牌不交还，
  **冻结连续不断**（不再发中途的 `freeze_ended`/`freeze_started`）。
- `skip_tutorial()` 补交还令牌，并补发收起信号（旧实现还会把面板留在屏幕上）。
- 新增**语义护栏** `_step_wants_freeze()`：`pause_game = true` 但 `trigger_action` 非空
  （要玩家在世界里做事才算完成，例如"靠近村民按 [F] 交谈"）的步骤**拒绝冻结** ——
  世界一停，完成条件永远不可能达成，表现为"按 F 没反应、NPC 对话永远不显示"。
  冻结必须与"这一步能不能完成"自洽，而不是无条件相信一个数据开关。护栏会 `push_warning`。
- `is_current_step_blocking()` 改为读同一个 `_current_freeze`：UI 与系统永远同源。
- 顺带：`_process` / `_unhandled_input` 加下标校验（`_steps` 被换掉时不再越界崩溃）。

**3) `DialogUI` —— 只在"真的被盖住"时让位**

- 判据从 `get_tree().paused` 换成 `PauseManager.covers_screen()`：被暂停菜单 / 背包 /
  三选一 / 结算这类**带全屏遮罩**的窗口盖住时才收掉（这是旧规则真正要防的场景）；
  系统级冻结期间对话条照常逐字显示、照常能推进与结算。
- 提示条额外一条：**别的窗口占屏时让位**（顶部只有一条消息的位置，教程/帮助也是顶部面板）。
  显式排掉本窗口自己的 id，所以"提示条与对话条同屏"这条硬契约不受影响。

**4) 文档同步**：`docs/ARCHITECTURE.md`（§5.5 / §9.1 / §9.4 / §9.5 与两份 HTML 快照里的同一句）、
`tutorial_step.gd` 的 `pause_game` 字段说明、`tutorial_ui.gd` 的文件头。

### 验证

**新增 `tools/freeze_contract_test.{gd,tscn}`（45 项全绿）**，四组：

- **A 冻结由状态推导**：阻塞步真的冻结 / 推进后真的恢复；**连续两个阻塞步之间不发
  `freeze_ended`、也不重复发 `freeze_started`**（旧实现的两条路径在这里必红）；
  `skip_tutorial()` / `reset()` / 教程结束都交还令牌（旧实现的 `skip_tutorial()` 泄漏）；
  语义护栏让"pause_game + trigger_action"的步骤保持非阻塞，且 UI 与系统答案一致；
  重复 `_sync_pause()` 幂等（无信号抖动）。
- **B 冻结声明**：`Cover.WORLD` 冻结世界但不算"盖住别人"、`Cover.SCREEN` 算、
  默认按 SCREEN；持有者被 `free()` 后令牌自动回收且世界恢复运行。
- **C 冻结期间与之后的对话**：`Cover.WORLD` 冻结期间对话照常弹出、打字机照常跑完、
  照常能推进到下一句并结算（回调恰好一次），解冻后照常显示；
  阻塞教程步冻结期间对话排队不抢屏，**教程一关就补位显示**、内容完整、奖励照发；
  被 `Cover.SCREEN` 的窗口盖住时对话收掉（旧意图保留）；
  提示条在系统冻结期间能显示、别的窗口占屏时让位且不波及对话条。

**全量回归 20 套件**：`freeze_contract`(45) · `dialogue_system`(71) · `esc_lifecycle`(29) ·
`esc_contract`(39) · `game_flow`(31) · `ui_registry`(25) · `audit_regression`(36) ·
`verify_fixes`(18) · `playability`(15) · `delivery`(93) · `smoke`(42) · `combat`(9) ·
`combat_arch`(15) · `audit_found`(7) · `bug_hunt`(37) · `bug_hunt2`(5) ·
`settings_contract`(21) · `popup_contract`(15) · `material_isolation`(10) 全绿；
`ui_layout_probe` 越界 0 / 裁剪 0 / 重叠 0。
（唯一的红灯仍是既有问题：编辑器把已删的 `scenes/weapons/big_sword.tscn` 写回磁盘，
与本轮改动无关。）

### 怎么调

- "这次冻结要不要占屏"：调用 `PauseManager.freeze/set_frozen` 时传 `Cover.WORLD` / `Cover.SCREEN`。
- 对话/提示条是否允许被盖住时自动收掉：`dialog_ui.gd` 的 `@export close_when_paused`。
- 教程步骤的冻结策略与护栏：`TutorialSystem._step_wants_freeze()`（数据仍是 `TutorialStep.pause_game`）。

### 经验（已可复用）

> 冻结/暂停这类"全局开关"只有两种写法是可靠的：**① 由状态推导 + 同步（幂等）**，
> 或 **② 令牌集合 + 存活兜底**（持有者死了自动回收）。绝不写"我用一个布尔记住我改过它"。
> 同理，**"世界停了" ≠ "屏幕被占了"**：下层 UI 是否让位，必须问"谁在占屏"，
> 而不是拿 `paused` 一揽子判断 —— 否则一次系统级冻结就会把玩家正在读的内容静默丢掉。

## 2026-09-13（深夜）—— 修复受击闪红串染：材质每实例隔离

### 症状

打中一个敌人后，屏幕上**其余敌人同时全部变红**（看起来像对象池没有隔离实例）。

### 根因（不是对象池，是**共享可变资源**）

敌人/玩家场景把一个 `ShaderMaterial` 子资源**同时**挂在根节点 `flash_material`
和 `Sprite.material` 上：

```
[sub_resource type="ShaderMaterial" id="ShaderMaterial_flash"]   # 一个对象
...
flash_material = SubResource("ShaderMaterial_flash")   # Enemy 根
material = SubResource("ShaderMaterial_flash")          # Sprite（同一个）
```

Godot 的**子资源默认在所有场景实例间共享**（除非 `resource_local_to_scene = true`）。
于是 10 个敌人共用同一份材质对象，`Actor._flash()` 给其中一个设
`flash_amount = 1.0`，等于把那份共享材质改了 —— 其余 9 个精灵跟着一起闪红。

旧代码其实"想"避免重复复制：

```gdscript
if _sprite.material == null or not (_sprite.material is ShaderMaterial):
	_sprite.material = flash_material.duplicate()
```

但场景**已经**给 Sprite 预挂了那份共享 `ShaderMaterial`，条件不成立 → 直接改共享对象。
这是"复制只在没有材质时发生"的反模式：**是否 copy 取决于场景是否预挂材质**，很脆弱。

### 修了什么

**1) `Actor`：每实例独占材质（权威修复）**

- 新增 `_owned_material` 字段 + `_ensure_owned_material()`：从模板 `duplicate()` 出
  **本实例独占**的一份并缓存，`_ready()` 时即私有化；此后闪白 / 溶解 / 描边都只改自己这份。
- `_flash()` 与 `_play_death_effect()` 改走该方法。
- 复制**只发生一次**（不是每次受击都复制），所以不会像旧 QA 报的那样泄漏材质。

**2) `EnemyBase._apply_elite_outline()`**：改用基类的独占材质，不再自己 `duplicate()`
（否则基类缓存的那份失去引用，两边各改各的，行为靠运气对齐）。

**3) 场景层双保险**：`enemy.tscn` / `player.tscn` 的 `ShaderMaterial_flash`
加 `resource_local_to_scene = true`。这是 Godot 处理"子资源需要按实例隔离"的**标准做法**，
让场景层也不可能共享；与代码层的 `_ensure_owned_material` 互为冗余（任一单独成立即可）。

### 验证

- **新增 `tools/material_isolation_test.tscn`（10 项）**：生成多个敌人，只打一个，断言
  被打者闪白生效、**其余保持 0**、各实例材质是不同对象、共享模板未被污染；
  并覆盖玩家 vs 敌人、精英描边 vs 普通敌人两类跨类型串扰。
  该测试在**修复前会失败**（"敌人各自持有不同材质对象" + "其余敌人没有跟着变红"）。
- 全量 **20 套件全绿**（新增本套件），`ui_layout_probe` 0/0/0。
- 顺手修两条测试自身的 **flaky**：用固定值写滑块时，若上次运行恰好存了同一值，
  `value_changed` 不触发导致假失败 → 改为"挑一个与当前不同的值"（`esc_lifecycle` / `settings_contract`）。

### 经验（已可复用）

> 凡是"每个实例要各自改参数"的资源（ShaderMaterial / Curve / Gradient / Shape…），
> 要么在场景里标 `resource_local_to_scene = true`，要么在代码里显式 `duplicate()`
> 并保证**每实例一份**。绝不能依赖"当前有没有被预挂"来决定是否复制。

---

## 2026-09-13（夜）—— 架构重构：GameFlow 状态机 / 容器化场景树 / 服务职责分离

### 背景

用户指出"没有真正的现代游戏树管理系统"，要求按教科书做法重构整个项目，并先出设计文档。
设计调研见 `docs/ARCHITECTURE_REFACTOR.md`（读了官方三篇文档 + 5 个高星模板源码）。
文档确认：服务层/暂停/Esc 仲裁/弹窗互斥已经是对的，缺的是 **树的归属** 与 **局面的单一真相** 两层。
用户确认后按三阶段实施，**每阶段全量回归全绿**。

### 阶段 1 —— GameFlow 状态机（替代 SessionFlow）

- **新增** `scripts/core/game_flow.gd`（autoload）：`enum State {BOOT,MENU,PLAYING,PAUSED,GAME_OVER}`
  + `LEGAL_TRANSITIONS` 表；`request()` 校验合法性（非法拒绝并告警），
  `start_run()` / `teardown_to_menu()` 为迁移入口，副作用集中在 `_enter_*`。
- `PauseMenu.open/close` → `GameFlow.set_paused()`；`GameOverUI` → `notify_game_over()` / `request(PLAYING)`；
  `Boot._ready` 驱动 `request(MENU)` 或 `start_run()`。
- **删除** `scripts/core/session_flow.gd`（全部调用点改名到 GameFlow）。
- 边界：GameFlow 管"局面"，`PauseManager` 令牌仍是"paused 位"的唯一真相。
- 新增 `tools/game_flow_test.tscn`（31 项）。

### 阶段 2 —— 容器化场景树 + UIRegistry

- **新增** `scripts/core/ui_registry.gd`（autoload）：持有 `World/GUI/Menus` 容器 +
  `register/window_for/find_by_name/level_parent/gui_container/menus_container`。
- `Boot` 建立 `Boot/World`、`Boot/GUI`、`Boot/Menus`；`PERSISTENT_UI` 改为 `[节点名, 容器]`。
- `SceneDirector` 关卡改挂 `UIRegistry.level_parent()`（World），无容器时回退 root。
- 各窗口 `_ready` 里登记进注册表；`SettingsPanel/HelpPanel.acquire` 改按 id 取；
  `GameFlow` 的清理与菜单挂载改走注册表。**root 直属子节点从 20+ 降为 autoloads + Boot 一个。**
- 测试适配：5 个测试的 `_root()` 改 `find_by_name()`，因此 **77 处 `Root/...` 内部路径契约一处未改**。
- 新增 `tools/ui_registry_test.tscn`（25 项）。

### 阶段 3 —— 状态与服务职责分离

- **新增** `scripts/core/save_manager.gd`（autoload）：只做存档 IO（JSON + 版本头 + 路径）。
  `GameState.save_game/load_game` 委托它；`GameState` 保留为状态持有者（官方认可 autoload 存全局变量）。
- **新增** `scripts/core/settings_service.gd`（autoload）：设置的读写与应用集中于此（线性↔dB、旧键迁移、
  AudioServer/DisplayServer）。`SettingsPanel` 重写为**只渲染 + 转发**（改动即时生效并落盘）。
- `settings_contract_test` 扩到 21 项。

### 踩坑

- `UIRegistry.get_window()` 与 `Node.get_window()` 签名冲突（编译报错），改名 `window_for()`。
- 测试与截图工具用 `get_node_or_null("TutorialUI")` 按 root 直属子节点找窗口，容器化后找不到 →
  改走 `UIRegistry.find_by_name()`（递归兜底），迁移期无需逐个改路径。
- 拆出 SettingsService 后"落盘时机"从"关闭时"变成"改动即落盘"，两条测试的旧断言据此更新。
- 一条测试自身缺陷：用固定值 0.4 改滑块，若上次运行恰好存了 0.4 则 `value_changed` 不触发而假失败 →
  改为"挑一个与当前不同的值"。

### 验证

**全量 19 套件全绿**：`game_flow`(31) · `ui_registry`(25) · `esc_lifecycle`(29) · `esc_contract`(39) ·
`settings_contract`(21) · `popup_contract`(15) · `audit_regression`(36) · `audit_found`(7) ·
`smoke`(42) · `combat`(9) · `combat_arch`(15) · `delivery`(93) · `playability`(15) ·
`verify_fixes`(17) · `dialogue_system`(71) · `weapon_dialog`(49) · `bug_hunt`(37) ·
`bug_hunt2`(5) · `ui_layout_probe`（越界 0 / 裁剪 0 / 重叠 0）。

### 未做（有意识的取舍，见重构文档 §13）

- `GameState` 的完整 `Resource` 化：96 个调用点，全量重写收益低风险高；只拆出 IO 这一最小正确切分。
- 后台线程加载 / 加载屏：当前关卡小，无必要。
- `LevelLoader` 独立成类：容器化目标已由 `SceneDirector` + `UIRegistry.level_parent()` 达成。

---

## 2026-09-13（傍晚）—— 修复设置面板无法退出 + 滑块不可见；重构设置 UI

### 背景

用户报两个具体问题，并要求"重新搞一套 UI，参考真正的 ARPG 项目，去 GitHub 上找找别人的实现"：

1. 游戏中按 Esc 打开菜单、点"设置"后**无法退出**（点确定/按 Esc 都没反应）。
2. 设置里的**滑块看不见线条**（只有一个方块把手，没有轨道）。

### 排查（全部本地复现 + 像素级取证）

| 症状 | 根因 |
|---|---|
| 设置无法退出 | `SettingsPanel._ready` **漏设 `process_mode = ALWAYS`**。它常从暂停菜单打开，此时 `paused=true`，默认 `INHERIT` 节点 `can_process()=false` → **按钮点不动、滑块拖不动**。实测 `process_mode=0, can_process=false`。 |
| 滑块无线条 | `slider` 样式盒用的是 `_slice("well_bg", 0.0)` / `_flat()`，**content_margin 全 0 → 样式盒最小高度 0**，而 HSlider 按样式盒最小高度画轨道 → 轨道宽高为 0，什么都不画，只剩把手图标。隔离实验证实：content_margin=0 无轨道，=3/4/6 有清晰轨道。 |
| 主菜单里设置也关不掉 | `MainMenu._unhandled_input` 无条件 `set_input_as_handled()` 吞掉 Esc，而 MainMenu 的投递顺序早于 UIInputRouter（router 是 autoload，逆序时最后收到）→ router 收不到 Esc，子面板关不掉。 |
| 树上出现两个 SettingsPanel | 主菜单与暂停菜单各自 `instantiate()` 面板，`_settings_panel` 各持一份；Esc/可见性作用到错误对象。 |

### 参考的 GitHub 项目

- **`KonyD/action-rpg-template`**（Godot 4.4+ ARPG 模板）—— 关键：它用的**就是本项目同一套 Ninja Adventure 素材**（`h_slidder_grabber.png` 同款文件名），设置菜单是"标签 + HSlider + 贴图把手"的极简布局。
- `uheartbeast/arpg-reference`、`TinyTakinTeller/TakinGodotTemplate`、`ClarkWain/godot-arpg-kit`、`mandrille/goliath-arpg`（4.7 俯视 ARPG）—— 参考其设置入口/音频总线/存档组织方式。
- 结论：设置面板不该做成"满屏面板 + 分贝滑块"，而应是**小面板、线性 0..1 音量 + 百分比、贴图把手 + 有厚度的轨道**。

### 改了什么

**1) `SettingsPanel` 重写（`scripts/ui/settings_panel.gd`）**

- **补 `process_mode = PROCESS_MODE_ALWAYS`**（真正的"无法退出"根因）。
- 音量改 **0..1 线性值** + 右侧百分比显示；`linear_to_db()` 应用（0 → -80dB）。旧的 `-40..6` 分贝滑块对玩家无意义且听感非线性。
- 新增**全屏开关**（`CheckButton`）、**返回/确定**双按钮（走 `close()` 的 SAVE 路径）。
- 读档兼容旧格式（`audio/*_db` 自动迁移到 `volume/*`）。
- 新增静态 `SettingsPanel.acquire(root, scene)`：**全局唯一实例**，两个菜单共用。

**2) `HelpPanel` 同样补 `acquire()`**，两个菜单共用同一实例。

**3) `MainMenu._unhandled_input`**：有阻塞窗口（设置/说明）时**让开**，Esc 交给 router 路由给子面板自己关；只有在"真主菜单、无弹窗"时才吃掉 Esc。

**4) `PauseMenu._open_help/_open_settings`** 改用 `acquire()`。

**5) Theme 生成器（`tools/generate_theme.gd`）**

- 新增 `_slider_track()`：轨道 = 暗色凹槽 + 1px 描边 + 上下 content_margin（`SLIDER_TRACK_PAD`）→ **轨道有确定厚度，永远可见**；填充段用同一内边距保证对齐。
- 新增 `HSeparator`/`VSeparator` 样式（默认皮肤的几乎不可见）。

**6) 场景生成器（`tools/generate_ui_scenes.gd`）**

- 设置面板重排：标题 + 三行"标签 / 滑块(expand) / 百分比" + 分隔线 + 全屏开关 + 返回/确定。
- 面板用 `PRESET_CENTER` + `grow BOTH` 按内容尺寸居中（写死 offsets 曾导致 192px > 视口 180px 溢出）。
- 新增 `_make_slider_row_full()` / `_make_toggle_row()` 辅助。

### 验证

- **新增 `tools/settings_contract_test`（19 项全绿）**：面板 ALWAYS / 暂停中可交互 / 轨道非零高度（含填充段等高）/ 暂停菜单与主菜单两条 Esc 退出路径 / 点确定关闭并落盘 / 两入口同一实例。
- **全量 16 套件全绿**：`settings_contract`(19) · `esc_lifecycle`(29) · `esc_contract`(39) · `popup_contract`(15) · `audit_regression`(36) · `audit_found`(7) · `smoke`(42) · `combat`(9) · `combat_arch`(15) · `delivery`(93) · `playability`(15) · `verify_fixes`(17) · `dialogue_system`(71) · `weapon_dialog`(49) · `bug_hunt`(37) · `bug_hunt2`(5)。
- `ui_layout_probe`：越界 0 / 裁剪 0 / 重叠 0。
- **真机截图** `docs/qa_settings/`：设置面板 208×161 居中，三条轨道全部可见、带填充段与百分比；Esc 前后对比图确认主菜单路径也能关闭（"确定"按钮橙色像素 3619 → 0）。
- 顺手清掉编辑器复活的孤儿场景 `scenes/weapons/big_sword.tscn`（`weapon_dialog_test` 48/1 → 49/0；这是既有问题，非本次改动引入）。

### 已知限制 / 下一步

- 全屏开关用 `WINDOW_MODE_FULLSCREEN`；多显示器 / 独占全屏的细分模式尚未提供下拉选择。
- 设置项目前只有音量与全屏；分辨率、按键重绑、语言还未做，但 `acquire()` + 分区的结构已留好扩展位。

---

## 2026-09-13（下午）—— Esc 生命周期重构：暂停所有权 / 场景切换取消 / 音频归属

### 背景

用户报两个症状并要求"全面排查 + 一致健壮的修复"：

1. 在系统提示界面按 Esc 后**角色仍在移动**——暂停机制没真正冻结游戏循环与输入。
2. 按 Esc 返回主菜单后 **UI 渲染/状态错乱**，且 **BGM 与当前场景不匹配**（切换/叠加/未停止）。

### 排查方法（先复现，再改）

现有 13 个套件**全绿**，说明症状落在它们没覆盖的路径上。为此写了 6 个一次性端到端复现脚本
（跑真实 boot + 真实关卡 + 真实 `Input.parse_input_event`），逐条证伪/证实。结果：

| 复现项 | 结果 |
|---|---|
| 直接按 Esc 开暂停菜单（真实输入/合成输入） | ✅ 正确冻结，**未复现** |
| 教程/帮助/设置/背包 各种阻塞窗口叠加 × Esc | 20 条不变量全对，**未复现** |
| **外部直写 `get_tree().paused` 后暂停菜单失效** | ❌ **复现**：缓存位脱节 → `freeze()` 静默失效 → 角色照跑 |
| **回主菜单后 HUD / Boss 血条残留可见 + 技能栏残留** | ❌ **复现**：常驻局内 UI 从不随主菜单收起 |
| **主菜单 BGM 归属为空** | ❌ **复现**：`play_music()` 不登记 owner |
| **转场中途（fade=0）返回主菜单** | ❌ **复现**：在途协程把关卡挂回、关卡 BGM 重播；`_spawn_player` 对 null 崩溃 |
| **暂停菜单子面板绕过 `close()`**（Esc 关设置不落盘；关帮助不还槽位/令牌） | ❌ **复现** |

### 关于原始症状的结论

症状 1 在当前代码里**未能复现**：`_unhandled_input` 有 `set_input_as_handled()`、`pause_menu` 在
`_ready` 就设 `PROCESS_MODE_ALWAYS`、真实输入下角色位移为 0。但它指向的**架构缺陷真实存在**：
一旦有任何外部代码直写 `get_tree().paused`，`PauseManager` 的缓存位就与真实位脱节，
`freeze()` 静默失效 → 暂停菜单开着而角色照跑。这正是用户描述现象成立所需的**唯一条件**。
所以按"根因"修，而不是辩解"无法复现"：把权威从缓存位改回真实位（见下）。

### 改了什么

**1) `PauseManager`：权威 = 真实 `paused` 位，不是缓存**

- 新增 `_process` 每帧 `_reconcile()`：令牌集合与真实 `paused` 不一致就纠正（不变量：**持有者非空 ⇔ paused**）。任何外部直写最多存活一帧。
- `_apply()` / `clear_all()` 改为先读真实位再决定写不写，不再以 `_applied` 缓存为准。

**2) `SceneDirector`：可取消的场景切换**

- 引入**代次令牌** `_generation`：`change_to_level` 记下自己的 `gen`，每个 `await` 后校验；`detach_level()` 会 `_generation += 1` 令所有在途切换作废。
- `_swap_scene` 改为"本地变量暂存 → 确认未被取消 → 一次性提交 `_current_level`/`_current_scene`/玩家/BGM"；取消时释放本地临时场景，不污染跨场景状态。
- `_spawn_player` 对 `_current_scene` 判空。
- 这些一起修掉了"转场中途回主菜单 → 主菜单背后活着一局游戏、BGM 是关卡曲"。

**3) `SessionFlow`：一条完整的回主菜单路径**

- `teardown_to_menu` **第一件事**就是 `SceneDirector.detach_level()` 作废在途转场。
- 新增 `GAMEPLAY_UI`（HUD / Boss 血条）：回主菜单时 `set_active(false)` 收起并清状态；`start_run` 时 `set_active(true)` 摆回局内。**进关前不隐藏**（否则进关后没血条）。
- 菜单 BGM 走 `play_music_for(MENU_MUSIC_OWNER, ...)`，归属明确为 `menu`。

**4) UI 生命周期**

- `HUD` / `BossHealthBar` 新增 `set_active()` + `force_close()`：HUD 停止每帧重绑玩家并清技能栏；Boss 血条解绑（Boss 随关卡释放）。`ModifierChoice.force_close()` 补交还暂停令牌。
- `PauseMenu`：帮助/设置一律走 `open()` / `close()` 契约（不再直接改 `visible`）；`_on_player_died` 走 `close()` 交还令牌。

**5) 音频与入口**

- `AudioManager.play_music()` 委托 `play_music_for(&"music", ...)`，不再留空 owner。
- `MainMenu` / `Boot` 的"开始游戏"统一走 `SessionFlow.start_run`，状态迁移只有一个入口。

### 验证

- **新增 `tools/esc_lifecycle_test`（29 项全绿）**：真实 boot + 真实关卡 + 真实输入，覆盖
  A 暂停真冻结 / B 缓存位脱节 / C 子面板契约（含落盘、槽位、令牌）/ D 回主菜单 UI+音频清理 /
  E 转场中途取消。
- **全量 15 套件全绿**：`esc_lifecycle`(29) · `esc_contract`(39) · `popup_contract`(15) ·
  `audit_regression`(36) · `audit_found`(7) · `smoke`(42) · `combat`(9) · `combat_arch`(15) ·
  `delivery`(93) · `playability`(15) · `verify_fixes`(17) · `dialogue_system`(71) ·
  `weapon_dialog`(49) · `bug_hunt`(37) · `bug_hunt2`(5)。
- **真机截图**（`tools/capture_esc.tscn`，真实窗口）→ `docs/qa_esc/`：回主菜单那张图里
  HUD 血条/技能栏已不再残留（修复前截图里叠在主菜单左上角）。
- 顺带修正 `tools/bug_hunt_test.gd` 狩猎 1b：它按**固定 60 帧**等场景切换，而本次修复让
  首次转场的淡入淡出真正执行，固定帧数在慢帧下会误判"切换失败"。改为**等到
  `is_changing()` 归位**（带上限兜底），是测试的时序假设问题，不是产品缺陷。

### 已知限制 / 下一步

- `PauseManager._process` 每帧核对真实位：正常路径零成本（只读一个 bool），仅在不一致时写。
  这换来了"外部直写最多存活一帧"的鲁棒性。
- 场景切换仍非事务式（没有"切换失败回滚"）；本次只保证**可取消**与**不产生幽灵关卡**。

---

## 2026-09-13 —— 代码审计 bug_report（B01–B34）全量修复 + 永久回归守卫

### 背景

拿到一份对本项目的代码审计报告，共 34 项缺陷（6 项已实证复现、17 项代码交叉核实、
其余静态高置信度）。用户选择「全部 34 项都修」+「并入永久回归套件并补测试」。

### 做的事

**生产代码**（14 个脚本）——按条目修复，要点见审计文档「七、修复完成状态」。
几条最关键的：

- `Actor.apply_damage()` 改为返回 `bool`，三处伤害入口（`attack_box` / `projectile` /
  `area_spell`）全部 `if not ... : return`。此前打尸体/无敌帧目标照样飘字、顿帧、震屏、
  吸血，弹道还空耗穿透次数。
- `Actor.would_stagger()` 成为唯一的打断判定谓词（`super_armor` 直接免疫，否则按
  `poise_damage >= data.poise`）。`EnemyBase._on_damaged` 与 `apply_damage` 内部共用，
  不再各写一套——此前 Boss 霸体形同虚设，被轻击连打每次都断。
- 打断也吃冷却：`_on_damaged` 的打断分支补写 `_attack_cooldown`。此前只有
  `_tick_attack` 的自然结束分支写，走打断路径永远到不了 → 越打敌人出手越快。
- `EnemyBase._resolve_boss_id()`：节点 meta `boss_id` > `EnemyData.id` > `&""`。
  此前用中文 `display_name` 登记，`is_boss_defeated(&"boss_cyclops")` 永远 false。
- `swing_started` / `swing_finished` 都挪到 ACTIVE 边界发，`interrupt()` 在
  ACTIVE/RECOVERY 补发 finished。此前被打断的挥砍永远不回收，刀光留在场上、音效循环。
- 宝箱一次性状态落盘（`GameState.opened_chests`，键 = 关卡/宝箱），重进不重复领取。
- `_paused_by_me` 暂停所有权铺开（`inventory_ui` 跟上 `help_panel`），
  从暂停菜单进背包再关掉，游戏仍保持暂停。

**新增测试套件**

- `tools/audit_found_test.{gd,tscn}` —— 7 项可实证用例。
  结果：`7 项，复现 0 个问题`（原为「复现 6 个」）。
- `tools/audit_regression_test.{gd,tscn}` —— 34 条断言 / 16 组，覆盖 B09–B32。
  结果：`34 通过，0 失败`。

**顺手清掉**：孤儿场景 `scenes/weapons/big_sword.tscn`（被开着的编辑器反复写回磁盘）。
删场景 + `.uid` + `*-folding-*.cfg` + 从 `editor_layout.cfg` 的 `open_scenes` 摘除。
`weapon_dialog_test` 由 48/1 变为 49/0。

### 踩坑（写测试自身的缺陷，都记进 skill 了）

首跑 `audit_regression_test` 报 21 通过 / 5 失败，**5 条全是打桩问题**：

1. **文档注释冒充代码**。本项目要求注释里引代码片段，`find`/`contains` 会命中注释。
   → 断言前剥整行注释（`_strip_comment_lines`）。
2. **同一字符串多次出现**。`_attack_cooldown = enemy_data.attack_cooldown` 在
   `enemy_base.gd` 有 3 处，全局 `find` 只拿最靠前那个。→ 只切函数体
   （`_function_body`）。
3. **脱离场景树的节点没有生命周期**。`Actor.new()` 不走 `_ready()` 是 0 血；
   `AttackController.new()` 不挂树就永远停在 STARTUP；`ActorSprite.new()` 不 `_ready()`
   就 `vframes = 1`、设 `frame_coords` 越界。

### 验证

13 个套件全绿：`audit_found_test`(7) · `audit_regression_test`(34) · `combat_test`(9) ·
`combat_arch_test`(15) · `popup_contract_test`(13) · `dialogue_system_test`(71) ·
`smoke_test`(42) · `verify_fixes`(17) · `playability_check`(15) · `delivery_test`(93) ·
`bug_hunt_test`(37) · `bug_hunt2_test`(5) · `weapon_dialog_test`(49)。

---

## 2026-09-11 —— UI 重做：设计 token + 状态派生 + 按下态语义修正

### 背景

用户反馈"UI 太丑"且"按下去的状态反直觉"。先量化定位，再去 GitHub 找标准做法。

### 查到的根因（硬数据）

1. **按下态比禁用态还暗**：素材包 `button_pressed` 平均亮度 75.6，
   而 `button_disabled` 是 83.7 → 按下去看起来像"变灰失效"。
   且 pressed 顶行整行透明，按钮还会"缩水"。
2. **按下时文字完全不动**：三态 `content_margin` 一模一样，
   只有颜色变化，没有任何"被压下去"的反馈。
3. **焦点框是块带洞的 8×8 图**：`nine_path_focus` 是实心块 + 中心黑洞，
   还用 `AXIS_STRETCH_MODE_TILE` 平铺，Tab 上去整个按钮被橙色块盖住。
4. **满屏饱和橙、没有层级**：主按钮和次要按钮长得一样，金色强调失去意义
   （`ui_pause` 高饱和像素占比 11.3%）。
5. 12 个场景里散落 8 处 `theme_override_colors/font_color` 硬编码。

### 采纳的设计语言（来源）

- `passivestar/godot-minimal-theme`：**状态由基色派生**，不为每态手挑颜色。
- `godotengine/godot` 的 `default_theme.cpp`：pressed 用最深填充，
  disabled 用低对比区分——两者语义不重叠。
- `uheartbeast/Heart-Platformer-Godot-4`：像素 UI 的四态映射与字色翻转。
- Nebula UI / Static UI（Godot 官方论坛）：皮肤只定义十余个颜色，
  hover/pressed 由皮肤派生。
- 像素 UI 通行的立体约定：**凸起 = 可点，凹陷 = 已按下，扁平 = 不可点**。

### 改了什么

| 文件 | 改动 |
|---|---|
| `tools/generate_ui_skin.gd`（新增） | 程序化生成 10 张 12×12 九宫格贴图到 `assets/sprites/ui/theme/gen/`；正常/悬停=凸起、按下=凹陷、禁用=扁平 |
| `tools/generate_theme.gd` | 重写为设计 token + 状态派生；按下时 `content_margin` 上+1/下-1（文字下沉 1px）；焦点改为"不画中心 + 1px 金边 + 外扩"的细环；新增 PrimaryButton / AccentLabel |
| `scenes/ui/main_menu.tscn` | "新的冒险"→PrimaryButton，"退出"→DangerButton，副标题→MutedLabel，建立主次层级 |
| 7 个 `scenes/ui/*.tscn` | 清除 8 处硬编码字体色，改挂主题类型变体 |
| `tools/capture_skin.gd`（新增） | 用真实 Button 渲染四态样张，供像素级核验 |
| `tools/weapon_dialog_test.gd` | 修 flaky：`_wait_typing_done` 改为等"文本 == 预期整句" |

### 验证（全部为实测数值，非目测）

- 逐行亮度剖面（视口行）：normal 顶 80.3 / 底 23.7（凸起）；
  pressed 顶 23.7 / 底 80.3（**斜面翻转**）；disabled 顶=底=33.3（扁平）。
- 填充阶梯：disabled 33.3 < normal 42.0 < hover 55.0，
  pressed 27.7 最深但描边 152（金），与 disabled 描边 44.7 明确区分。
- 按下时文字下沉 **+1.18 视口像素**（4 个变体一致）。
- hover 与 normal 差异：Button +13.0 / Primary +17.7 / Quiet +28.7 / Danger +7.3。
- 画面：`ui_pause` 高饱和 11.3% → **0.8%**，`ui_help` 5.4% → **0.4%**。
- 回归：delivery 93/93、weapon_dialog **47/47（连跑 5 次全绿）**、combat 9/9、
  combat_arch 15/15、playability 15/15。

### 踩坑记录

- 第一版样张脚本直接 `stylebox.draw(canvas_item, rect)`，画出来一片纯白——
  绕过了控件状态机与内容边距，画不出"文字下沉"这类内容层行为。改用真实 Button。
- `_emit(name, fill, light, dark, ...)` 的 light/dark 是**明暗**语义不是上下语义，
  我按"上暗下亮"传值，结果凹陷又变回凸起。已在函数文档写明。
- 按钮真实高度是 **31 视口像素**（12px 点阵字行高 23 + 内容边距 8），
  `set_size(26)` 会被最小尺寸顶回去；按 26 取样会差一行、误判成"扁平"。
- 编辑器开着时（当前有 2 个 Godot 进程），被删掉的 `scenes/weapons/big_sword.tscn`
  会被 open_scenes 重新存回磁盘。清完要立刻复测。

---

## 2026-09-11（深夜）—— 修复"游戏没法运行"与字号统一管理

### 问题 1（致命）：全屏 UI 吞掉所有鼠标点击，游戏完全没法玩

**现象**：进入游戏后点什么都没反应，等于"游戏没法运行"。

**根因**：上一轮给教程面板加"点空白处关闭"时，把 `scenes/ui/tutorial_ui.tscn` 里
Root 的 `mouse_filter` 从 `2`(IGNORE) 改成了 `0`(STOP)。而这个 Root 是
**锚点铺满全屏、且由 Boot 常驻挂载**的 Control —— 游戏一启动就多了一层透明膜，
把鼠标点击全吃了，玩家点不到世界里的任何东西。

**修复**：
- Root 恢复 `mouse_filter = 2`(IGNORE)，始终让点击穿透到游戏；
- `dismiss_area_path` 改指向 `Root/Panel`（只有面板那一小块接收点击）；
- `TutorialUI._on_dismiss_input()` 只保留右键关闭（左键留给关闭按钮，避免跑动中误触）。

**新增守卫**：`tools/playability_check.tscn`（15 项），专门查这类致命问题：
- 有没有常驻 UI 在全屏吞鼠标点击；
- 屏幕各处点击能否落到游戏世界；
- 玩家能否移动/攻击；
- 教程面板点关闭按钮 / 按 Esc 能否关掉；
- 帮助面板在 `paused=true` 下能否关掉。

### 问题 2：字号散落、中文糊成一团

**根因（真正原因）**：主题里统一设了 `default_font_size = 12`，但**12 个 UI 场景里
散落着 35 处 `theme_override_font_sizes`**（8px 有 21 处，还有 6/7/9/10/11/14/20），
节点级 override 优先级高于主题，把统一字号挨个踩掉了。
Fusion Pixel 是 12px 点阵字，在 6~8px 下做非整数缩放，汉字笔画必然糊。
这同时违反了换肤文档"皮肤集中在 Theme"的原则。

**修复**：
1. 用脚本一次性清除全部 35 处 override，按原字号语义改挂主题类型变体
   （`TitleLabel` / `HeadingLabel` / `HintLabel`），其余回落主题正文。
2. 主题字号阶收敛为四档，且**只在 `tools/generate_theme.gd` 一处定义**：
   `FS_TITLE=20`、`FS_HEADING=14`、`FS_BODY=12`、`FS_HINT=10`。
   正文固定 12 = 点阵设计尺寸，1:1 渲染最锐利。
3. `oversampling` 从 `1.0`（等于禁用）改为 `4.0`，让字体按 4 倍分辨率栅格化再缩小，
   进一步保证锐利。
4. 按钮声明高度从 13 抬到 24：12px 字行高 16 + 内容边距上下各 4 = 24，
   否则文字会溢出按钮（实测 `help_panel/Close` 旧值 13 < 需要 16）。

**核验**：`font_probe` 实测四档字号下所有 UI 文字控件**零溢出**
（此前 `help_panel/Close` 报高度溢出）。

### 问题 3：big_sword.tscn 反复复活

孤儿场景被 Godot 编辑器的 `open_scenes` / `filesystem_cache` 反复带回。
本轮把文件、`editor_layout.cfg`、`project_metadata.cfg`、`filesystem_cache10`、
`.godot/editor/big_sword.tscn-*` 全部清理，重新 `--import` 后确认不再复活。

### 验证

- `weapon_dialog_test` 47/47（连跑 3 次一致，此前偶发的"点击没推进"是 headless
  高帧率下的竞态，非真回归）
- `delivery_test` 93/93、`combat_test` 9/9、`combat_arch_test` 15/15
- `playability_check` 15/15
- 合计 179 项通过，0 失败
- 截图：`docs/qa_final/`（10 张）

---

## 2026-09-11（晚）—— 教程无法关闭 / 开场无法跳过 / 字体 / GUI 换肤 / 瓦片错用

### 修复 1：中文字体替换

**问题**：游戏内中文显示为方块（tofu）。`assets/fonts/NormalFont.ttf` 实际是 "NinjaAdventure"，
只有约 150 个字符且基本无 CJK，Godot  fallback 也拿不到系统字体时就成豆腐块。

**修复**：
- 下载 Fusion Pixel Font 12px 比例简中版（TakWolf，SIL OFL 1.1）：
  `https://github.com/TakWolf/fusion-pixel-font`
- 放置到 `assets/fonts/FusionPixel12px.ttf`，并配 `.import`：
  `antialiasing=0`、`subpixel_positioning=0`、`oversampling=1.0`、`hinting=0`。
- 删除原 `NormalFont.ttf` 及 `.import`；`tools/generate_theme.gd` 与 `resources/ui_theme.tres`
  已指向新字体；默认字号由 8 提到 12。

**弃用方案**：zpix.ttf 商用授权业务用 ¥7000，不符合项目约定，未采用。

---

### 修复 2：UI 按 Godot 官方 GUI 换肤文档重做

**问题**：皮肤零散，部分控件（滑块、滚动条、复选框、LineEdit）仍用 Godot 内置灰皮，
与像素风格脱节。

**修复**：全量重写 `tools/generate_theme.gd`，遵循官方换肤最佳实践：
- 单一 Theme 资源 `resources/ui_theme.tres` 做唯一皮肤来源；
- 按钮用 3-slice `StyleBoxTexture`，面板/输入框用 `StyleBoxFlat`，
  都显式设置 `texture_margin` 与 `content_margin`；
- 13 个类型变体（TitleLabel / HeadingLabel / MutedLabel / HintLabel / ToastLabel /
  DangerLabel / DangerButton / QuietButton / CardButton / HealthBar / ManaBar / BossBar /
  CardPanel / Dimmer），节点上只写 `theme_type_variation`，样式集中管理。

生成后 `resources/ui_theme.tres` 覆盖 33 个控件类型。

---

### 修复 3：操作说明（教程）窗口无法关闭

**根因**：从暂停菜单打开「操作说明」时，`get_tree().paused = true`，
`HelpPanel` 的 `process_mode` 随父节点被暂停，`Control.gui_input`、按钮信号、`_unhandled_input`
全部失效——玩家点按钮、按 Esc、右键都没反应。

**修复**：
- `scripts/ui/help_panel.gd` 设 `process_mode = PROCESS_MODE_ALWAYS`；
- 四条互相独立的退出路径：关闭按钮、Esc / F、右键面板、点面板外遮罩；
- 打开时自动滚动到顶部并抓取焦点；
- `scenes/ui/help_panel.tscn` 补上 `dimmer_path = NodePath("Root/Dimmer")`，
  并把 `Dimmer` 设为 `mouse_filter=0`。

---

### 修复 4：开场/启动教程窗口无法跳过

**根因**：开场第一步 `auto_hide = 6.0`，但 `TutorialUI` 没提供任何手动关闭路径，
玩家必须硬等 6 秒。

**修复**：
- `scripts/core/event_bus.gd` 把信号改为四参数：
  `tutorial_step_shown(step_index, title, text, require_confirm)`。
- `scripts/core/tutorial_system.gd` 更新所有 emit 位置并新增 `dismiss_current_step()`，
  玩家主动关闭时系统会推进到下一步并正确复位状态。
- `scripts/ui/tutorial_ui.gd` 改接四参数信号，新增：
  - 关闭按钮（"✕"）；
  - Esc / Enter / Space 关闭；
  - 右键/点空白处关闭；
  - 关闭时同步调用 `TutorialSystem.dismiss_current_step()`，避免"关掉又冒出来"。
- `scenes/ui/tutorial_ui.tscn` 改 Root 为 `mouse_filter=STOP`，新增 Title、Close 节点，
  正文与标题分开。
- 同步更新所有旧 emit 调用点：`tools/capture_dialog.gd`、`tools/weapon_dialog_test.gd`。

---

### 修复 5：地砖与墙壁贴图错用

**根因**：
- `tools/generate_levels.gd` 中城镇地板 `FLOOR_TOWN = TilesetInteriorFloor(12,1)`，
  实际是一块单色填充，不是地板；
- 野外草地 `FLOOR_GRASS = TilesetNature(4,19)`，实际是树干/树底，不是草地；
- 通过 PIL 对图集做逐块扫描确认：TilesetInteriorFloor(1,1) 是可用砖纹，
  TilesetFloor(4,12)/(0,12)/(2,12)/(15,12) 是可用绿色草地，TilesetNature 无合适草地。

**修复**：
- 城镇地板：`FLOOR_TOWN = InteriorFloor(1,1)`；
- 野外草地：`FLOOR_GRASS = TilesetFloor(4,12)`，并新增 `TEX_FLOOR` 引用；
- 城镇/野外墙壁保持 `TilesetRelief(5,6)` 红砖；
- 重跑 `tools/generate_levels.tscn` 生成 5 个关卡场景；
- `docs/ASSETS.md` 同步更新瓦片与字体说明。

---

### 验证

- 回归测试：weapon_dialog_test 47/47、combat_test 9/9、combat_arch_test 15/15、
  delivery_test 93/93，全部通过。
- 真机截图 10 张存于 `docs/qa_after_fix/`，可直观看到中文字体正常、城镇砖纹地板、
  野外绿色草地、帮助面板与暂停菜单的新主题。
- 清理临时诊断文件：`tools/ui_audit.*`、`tools/probe_font.*`、`.tmpfont/`、`.tmptiles/`。

---

## 2026-09-09（夜）—— 角色/武器解耦与受击系统重构

用户反馈三个核心问题，本轮全部解决：

### 问题 1：攻击判定跟随角色，而不是跟随武器（最严重）

**现象**：判定盒是玩家场景里的一个固定子节点，位置永远在角色中心右侧，
角色转身、走动、瞄准都不影响它。而且判定盒（24×20）比受击盒（半径 7 → 直径 14）
虽然大一些，但因为它不跟随武器，实际命中非常别扭——更像 FTG 的固定拳脚框，
不适合 ARPG。

**修复**：把武器做成**独立场景**，判定盒挂在武器里：

```
WeaponController        ← 旋转到瞄准方向
  └─ SwingPivot         ← 挥砍时在弧线内扫动
	   ├─ Sprite        ← 武器贴图
	   └─ AttackBox     ← 判定盒（跟着武器转 + 扫）
```

判定盒是 SwingPivot 的子节点，武器一转它就转——判定天然跟随武器。
实测：朝右判定盒在 +22，朝左 -22，朝上 -28。

### 问题 2：没有武器场景

**修复**：新增 `tools/generate_weapon_scenes.gd`，生成 6 个武器场景
（sword / katana / big_sword / hammer / bow / wand）。
`WeaponData.weapon_scene` 指向它们；玩家和敌人都按数据实例化武器。
换武器 = 换场景，**不用改角色脚本**。

### 问题 3：状态机太简单，攻击/受击/死亡没动画

**修复**：
- 攻击动画绑定到**武器**（`WeaponController` 负责挥砍扫动与刀光），
  角色脚本不碰动画细节——这是合理的分层。
- `AttackController` 预留 `set_weapon()` / `get_weapon()` 接口，
  有武器时委托武器，没有时退回旧判定盒（兼容）。
- 受击：着色器**红闪** + 精灵**抖动**，参数（颜色/时长/强度）全部来自
  `CharacterData`。
- 死亡：着色器**溶解** + 淡出，同样数据驱动。

### 问题 4：敌人需要抗击退属性

**修复**：`CharacterData` 新增：
- `knockback_resist` 0~1 —— **Boss 设 1.0 完全不被击退，精英设 0.5 推得动但推不远**
- `super_armor` —— 霸体，受击不进硬直（Boss/精英用）
- `knockback_damping` —— 击退衰减速度

这样"Boss 不被击退"和"精英是否霸体"**只需改数据，不用写任何特判脚本**。

### 关键设计决定

| 决定 | 理由 |
|---|---|
| 武器做成独立场景 | 攻击效果与角色解耦；换武器不改角色 |
| 判定盒挂 SwingPivot 下 | 判定跟随武器旋转/扫动，而不是固定框 |
| 攻击动画归武器 | 角色只管状态机，表现细节归武器 |
| 受击/死亡表现放 Actor 基类 | 玩家/敌人/Boss 共用，不重复实现 |
| 抗击退/霸体走数据 | 免去 Boss 特判，配置即可 |

### 数据/场景改动

- `CharacterData` +7 字段（抗击退、霸体、衰减、闪色、抖动、溶解、销毁）
- `WeaponData` +4 字段（weapon_scene、swing_effect_scene、swing_arc、swing_duration）
- `EnemyData` +1 字段（weapon_scene）
- 新增 `scripts/combat/weapon_controller.gd`
- 新增 `scenes/weapons/*.tscn`（6 个）
- 玩家/敌人场景各加 `WeaponMount` 节点；判定盒尺寸 24×20 → 34×28（玩家）、
  18×16 → 30×26（敌人），受击盒半径 7 → 6，**确保判定明显大于受击**

### 踩坑

| 问题 | 原因 | 解决 |
|---|---|---|
| 朝左时武器倒着拿 | 只靠 rotation 转 180° | 加 `flip_v` 垂直翻转，做成镜像 |
| 敌人武器实例找不到 | 测试只查直接子节点 | 武器挂在 WeaponMount 下，递归查 |
| combat_test 3 项失败 | 测试还在操作旧的固定判定盒 | 改为从武器取判定盒，并按真实瞄准方向摆敌人 |
| 霸体检查被静默跳过 | 调用异步函数没加 await | 补 `await` |

### 验证

新增 `tools/combat_arch_test.tscn`（14 项），专测本轮架构：
判定跟随武器、判定>受击、武器场景绑定、换武器重建、Boss 免疫击退、
精英半免疫、Boss 霸体（掉血无硬直无击退）、受击闪色/抖动、死亡溶解。

完整套件 **217 项全通过**：
smoke 42 / combat 9 / delivery 93 / hunt 37 / hunt2 5 / verify_fixes 17 / combat_arch 14。

截图验收：武器在四个朝向都正确跟随（朝左为镜像）；受击时角色整体变红。

---

## 2026-09-09（晚）—— 修复 QA 报告的 19 个缺陷

QA 报告（`docs/QA_REPORT.md`）用运行时狩猎 + 视觉复核找出 19 个问题。
逐条核实、修复、并加自动化回归。详细对照见 `docs/QA_FIXES.md`。

### 核实过程

先**验证每一条是否真实存在**，而不是照单全收：
- 用 `bug_hunt_test` / `bug_hunt2_test` 复现：确认 15 + 4 个问题真实存在。
- 报告有 2 条与代码不符，已标注不计入修复：
  - "640×480 视口" —— 实际基准是 320×180。
  - "tutorial_step 的 pause_game/require_confirm 从未读取"、"player.tscn 未绑 flash_material"
	—— 经查这两处都已接好，不成立。
- BUG-18（文字模糊）核实后是**字体回退**导致（字体仅含 150 个拉丁字形，中文走系统字体），
  不是 bug，只做了整数像素落位优化。

### 修复的 19 条（按严重度）

| # | 问题 | 根因一句话 |
|---|---|---|
| 01 | 三选一永久软锁 | 暂停态只向 ALWAYS 节点派发输入，该层是 INHERIT |
| 02 | 复活坐标写错对象 | 切场景异步，2 帧后新玩家还没生成 |
| 03 | 零敌人关卡锁门不开 | is_cleared 只认"敌人死光"事件 |
| 04 | 翻滚白嫖重击 | 蓄力释放不检查玩家状态 |
| 05 | 血条显示敌人血量 | 过滤条件在 _player 为空时被绕过 |
| 06 | HUD 绑不到玩家 | 只绑定一次，不重试 |
| 07 | 瞄准偏 92° | 视口坐标减世界坐标 |
| 08 | 生命/法力词条无效 | get_max_* 绕过 get_stat |
| 09 | 限定词条越界生效 | 不读 weapon_kinds/elements |
| 10 | 叠层多算一遍 | 公式写成 (v + vps*(n-1)) * n |
| 11 | 同名词条被吞 | 用 display_name 做字典键 |
| 12 | 蓄力打断后移速残留 | 只清标志位，没复位倍率 |
| 13 | 飘字不消失 | 暂停态不推进 + 回调挂在并行补间上 |
| 14/15 | 教程瞬间自毁 | 跳过所有不匹配步骤，主菜单阶段全被跳过 |
| 16 | 镜头黑边 | set_target 吸附玩家坐标但不钳制边界 |
| 17 | 血条看不出血量 | background 与 fill 用同一个 stylebox |
| 18 | 文字模糊 | 字体缺中文字形，走系统回退（已缓解） |
| 19 | 全局词条不触发 | 没有任何代码提供 trigger 上下文 |

### 关键设计改动

1. **`SceneDirector.set_next_spawn_position()`** —— 复活坐标从"事后写入"改为
   "生成时落位"，根除异步时序竞争。
2. **`Actor.get_attack_context()` + `ModifierSystem` 上下文过滤** —— 词条按
   `{weapon_kind, element, trigger}` 作用域生效，让限定词条和残血词条真正可用。
3. **`PlayerCombat.cancel_charge()`** —— 蓄力取消统一入口，翻滚/受击/越权释放都走它。
4. **契约计时器模式** —— 飘字/转场等"可能被取代"的动画，用独立计时器兑现
   "duration 后一定返回/释放"的契约，不依赖补间是否存活。

### 测试改进

测试本身也修了两个 harness 缺陷（否则会误报）：
- `bug_hunt_test` 瞄准项原本在测试里**重抄了旧表达式**，改为调用真实 `_aim_direction()`。
- `bug_hunt2_test` 飘字项按帧数等待（headless 90 帧≈0.6s < 0.75s 寿命），改为按真实时间等待。

### 验证

```bash
GODOT="D:/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
"$GODOT" --headless --path . res://tools/smoke_test.tscn      # 42/42
"$GODOT" --headless --path . res://tools/combat_test.tscn     # 9/9
"$GODOT" --headless --path . res://tools/delivery_test.tscn   # 93/93
"$GODOT" --headless --path . res://tools/bug_hunt_test.tscn   # 复现 0
"$GODOT" --headless --path . res://tools/bug_hunt2_test.tscn  # 复现 0
"$GODOT" --headless --path . res://tools/verify_fixes.tscn    # 17/17
```

**204 项检查全通过**；截图重新验收确认黑边消失、血条有对比度。

---

## 2026-09-09（下午）—— 完善到可交付级别

在原型基础上补齐"可交付"所需的内容与流程层。

### 新增：关卡设计哲学

`docs/LEVEL_DESIGN.md` —— 定义全项目统一的关卡设计原则：
三拍循环（压力→释放→奖励）、关卡结构模板（入口安全区→战斗房→岔路宝箱→存档点→关底门）、
房间尺寸约束（战斗房 11~14 格宽、走廊 ≥2 格）、敌人布置原则（入口 5 格内不放怪、
单房间 ≤5 只、近战:远程 ≈2:1）、难度曲线、每关检查清单。
**生成器按这份文档的约束来写**，不是先写代码再补文档。

### 新增：交互物系统（6 种）

| 文件 | 作用 |
|---|---|
| `scripts/world/interactable.gd` | 基类：范围检测、提示、冷却、一次性 |
| `scripts/world/chest.gd` | 宝箱：金币 + 固定物品，开箱切帧动画 |
| `scripts/world/save_point.gd` | 存档点：回满血蓝 + 写档 + 记录复活点 |
| `scripts/world/sign_post.gd` | 提示牌：显示长文本，不打断操作 |
| `scripts/world/npc.gd` | NPC：逐句对话 + 给道具/金币/解锁法术 |
| `scripts/world/heal_spring.gd` | 治愈泉：踩上去自动恢复，带冷却 |
| `scripts/world/locked_door.gd` | 锁门：清怪解锁 或 钥匙解锁 |

配套：`tools/generate_world_scenes.gd` 生成 6 个交互物场景（碰撞层统一）。

### 新增：新手教程系统（数据驱动）

- `scripts/data/tutorial_step.gd` —— 教程步骤资源（顺序/关卡/延迟/完成条件）
- `scripts/core/tutorial_system.gd` —— 按关卡推进、监听玩家动作、可跳过
- `scripts/ui/tutorial_ui.gd` —— 顶部提示面板
- `tools/generate_tutorial.gd` —— 14 个步骤，覆盖城镇→野外→地牢→Boss

### 新增：完整 UI 层（11 个界面）

主菜单、暂停菜单、设置（音量）、操作说明、教程提示、HUD、背包/装备、
Boss 血条、死亡/胜利结算、三选一词条、伤害飘字。
- `tools/generate_theme.gd` 用素材生成 `resources/ui_theme.tres` 统一外观
- `tools/generate_ui_scenes.gd` 生成全部界面场景

### 新增：GameState 扩展

背包（增删查/序列化）、复活点（关卡 + 坐标）、教程完成标记，全部进存档。

### 重构：关卡生成器（4 关 → 5 关）

按设计文档重写 `tools/generate_levels.gd`：
- 城镇：NPC ×2、提示牌、存档点
- 野外：10 怪、2 宝箱、治愈泉、岩石障碍簇、存档点
- 地牢一层：13 怪（含法师）、宝箱房、存档房、清怪锁门
- 地牢二层（新）：15 怪（含精英）、钥匙房、隐蔽宝箱房、钥匙锁门
- Boss 房：Boss + 2×2 柱子掩体 + 入口存档点
- 每关配置 `ambient_color` 做区域色调（地牢冷暗、野外暖、Boss 偏紫）

### 本阶段踩的坑

| 问题 | 现象 | 原因 | 解决 |
|---|---|---|---|
| autoload 与 class_name 冲突 | `Class "TutorialSystem" hides an autoload singleton` | 脚本既注册为 autoload 又写了同名 `class_name` | 去掉 `class_name` |
| 转场永久挂起 | 连续切关卡时后续切换全被丢弃 | `fade_in/fade_out` await 的 tween 被新调用 kill，`finished` 永不发出 | 改成"动画 + 独立契约计时器"双轨；`is_inside_tree()` 保护 |
| 背包关闭后画面变暗 | 全屏遮罩没跟着隐藏 | 只隐藏了面板，没隐藏 Dimmer | 显式控制 Dimmer 可见性 |
| CanvasLayer 没有 theme 属性 | `Invalid assignment of property 'theme'` | 主题只能设在 Control 上 | 主题设在内部 Root(Control) |
| UI 节点路径不对 | 教程文字不显示 | `Text` 在 `HBox` 里，路径漏了一层 | 用 `find_child(recursive=true)` 兜底 |
| 面板拉满屏 | 帮助面板的关闭按钮被拉成整屏高 | PanelContainer 会拉伸唯一子节点 | 用 VBox 管理，文本扩展、按钮自然高 |
| 亮橙面板压文字 | 帮助文字在橙底上看不清 | 素材九宫格中心是高饱和装饰色 | 面板改用深色 StyleBoxFlat + 橙色描边 |
| Boss 房柱子像"洞" | 单格墙在开阔地面上很怪 | 单格没有体积感 | 改成 2×2 |
| ambient_color 没生效 | 地牢没有变暗 | LevelData 引用场景、场景又要引用 LevelData，形成循环 | 场景不引用 .tres，改从 SceneDirector 取 |
| 测试误判"关卡加载失败" | 连续切关卡时后几次被丢弃 | `change_to_level` 在转场期间会静默丢弃请求 | 加 `SceneDirector.is_changing()`，测试先等空闲 |

### 验证方式

```bash
GODOT="D:/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"

"$GODOT" --headless --path . --import
"$GODOT" --headless --path . res://tools/generate_data.tscn
"$GODOT" --headless --path . res://tools/generate_levels.tscn
"$GODOT" --headless --path . res://tools/generate_world_scenes.tscn
"$GODOT" --headless --path . res://tools/generate_ui_scenes.tscn
"$GODOT" --headless --path . res://tools/generate_theme.tscn
"$GODOT" --headless --path . res://tools/generate_tutorial.tscn

"$GODOT" --headless --path . res://tools/smoke_test.tscn      # 42/42
"$GODOT" --headless --path . res://tools/combat_test.tscn     # 9/9
"$GODOT" --headless --path . res://tools/delivery_test.tscn   # 93/93

"$GODOT" --path . --resolution 1280x720 res://tools/capture_all.tscn
```

结果：**144 项检查全通过**；截图逐张目视验收（5 个关卡 + 主菜单 + 操作说明 +
暂停 + 背包 + 教程 + 死亡 + 设置 + 三选一），确认瓦片接缝、区域色调、
UI 布局与可读性均正常。

### 仍然已知的限制

- 附魔法术的 `cast_effect` 视觉未接入（数据字段已就位）。
- 敌人是直线追击，不会绕墙（关卡用宽走廊规避，后续可接 NavigationRegion2D）。
- 被动技能未在装备时自动挂载到玩家。
- 商店 / 合成系统未做（需求未要求）。

---

## 2026-09-09 —— 从零搭建 ActRPG 原型（全阶段）

### 背景

原 `D:\GodotProject\re-game-arpg` 是一个旧实验工程（球形自动战斗 demo，含自己的
git 历史）。按新需求重建，旧工程**改名归档**为 `re-game-arpg-legacy-20260909`，
未删除、git 历史完整保留。

### 环境确认

- 引擎：Godot **4.7.2.stable.official**（`D:\Godot_v4.7.2-stable_win64.exe\`）
- 离线文档：`D:\GodotProject\godot-docs-html-stable`（版本为 **4.6**，比引擎低一个
  小版本）。凡涉及 API 均先查文档确认，尤其确认了 `TileMap` 已弃用、改用
  **`TileMapLayer`**（4.3+）。
- 素材源站可达性：GitHub / Kenney / OpenGameArt 均 200；itch.io 在本机 DNS 被
  污染（解析到 Facebook IP），因此改用 OpenGameArt + GitHub 镜像获取同一 CC0 素材包。

### 关键决策与踩坑记录

| 问题 | 现象 | 原因 | 解决 |
|---|---|---|---|
| 旧工程冲突 | 目标目录已有旧项目 | — | 改名归档，不覆盖 |
| 素材包不完整 | GitHub `pixel-boy/NinjaAdventure` 只有 4 个角色 | 那是作者的示例工程，非完整包 | 从 `MarioLDD/Kuroshiro-adventure` 稀疏克隆 `Assets/NinjaAdventure`（含完整角色/怪物/Boss/FX/音频 + `LICENSE.txt`） |
| 瓦片平铺出现黑点阵 | 草地每格右下角有暗点，平铺后成整齐黑点 | 选到了装饰性瓦片 | 写脚本逐块"平铺 4×4 渲染"目视筛选，改用 (4,19) |
| 墙体不接缝 | 墙是 blob 装饰块，拼接后断裂 | 选到了自动图块而非实心瓦片 | 逐块计算"边缘与中心色差"筛出可平铺实心墙 |
| `DataRegistry` 加载 0 个文件 | 启动即报"找不到关卡" | 用 `ResourceLoader.exists()` 判断**目录**，对目录返回 false | 改用 `DirAccess.dir_exists_absolute()` |
| id 冲突 | 两个词条 display_name 都是"龙之心" | 曾用 `display_name` 当查询键 | 改用**文件名**做键（稳定、唯一、与显示名解耦） |
| `add_child` 失败 | boot 阶段 `Parent node is busy` | 在 `_ready` 中直接 `add_child` | 改 `call_deferred` + 等帧 |
| 转场 tween 空引用 | `Required object "rp_target" is null` | 转场层还没入树就被淡入淡出 | `_ensure_rect()` 懒创建遮罩，不依赖 `_ready` 时序 |
| `AttackData` 缺字段 | 命中时 `Invalid access to property 'hit_sfx'`，**伤害静默丢失** | 脚本字段名 `sfx` 与调用方 `hit_sfx` 不一致 | 拆成 `swing_sfx` / `hit_sfx` 两个字段 |
| 子类成员重名 | `Player`/`EnemyBase` 与父类 `Actor` 的 `_sprite` 等冲突 | GDScript 不允许子类重声明父类成员 | 子类改用强类型别名（`_player_sprite` / `_enemy_sprite`） |
| 碰撞双倍伤害风险 | — | 攻受双方都监听会各触发一次 | 定死方向：**攻击盒主动 `monitoring=true`，受击盒被动 `monitorable=true`** |

### 新增/修改文件清单

**工程配置**
- `project.godot` —— 输入映射（移动/攻击/重击/翻滚/法术×3/技能×2/交互/背包/暂停）、
  autoload（EventBus/DataRegistry/GameState/ModifierSystem/HitStop/AudioManager/
  SceneDirector）、物理层命名、像素渲染设置（320×180 基准、整数缩放、最近邻采样）

**核心单例 `scripts/core/`**
- `event_bus.gd` —— 全局信号总线（只放 signal，不放逻辑）
- `data_registry.gd` —— 扫描 `res://data/` 并建索引，全项目唯一的"数据在哪"知情者
- `game_state.gd` —— 局外解锁/局内临时状态分离，JSON 存档
- `hit_stop.gd` —— 顿帧（用 `ignore_time_scale` 定时器，代次防重叠）
- `audio_manager.gd` —— 音效播放器池 + 音乐切换
- `scene_director.gd` —— 关卡切换、入口点、转场淡入淡出
- `transition.gd` / `boot.gd`

**数据层 `scripts/data/`**（8 个 Resource 类 + `game_enums.gd` 共享枚举）
- `attack_data.gd`（帧数据/伤害/手感）、`weapon_data.gd`、`spell_data.gd`、
  `ability_data.gd`、`modifier_data.gd`、`character_data.gd`、`enemy_data.gd`、
  `level_data.gd`、`item_data.gd`

**战斗 `scripts/combat/`**
- `actor.gd` —— 所有可受伤单位基类（血量/防御减伤/无敌/硬直/击退/词条乘区）
- `damage_info.gd` —— 伤害载体（强类型，不用 Dictionary）
- `attack_box.gd` —— 主动判定盒，伤害结算唯一入口
- `attack_controller.gd` —— 前摇→判定→后摇时间轴，输入缓冲 + 连击衔接 + 后摇取消
- `projectile.gd` / `area_spell.gd` / `ability.gd`

**玩家 `scripts/player/`**
- `player.gd` —— 状态机（待机/移动/攻击/翻滚/硬直/死亡），土狼时间、输入缓冲、
  翻滚无敌帧、后摇取消
- `player_combat.gd` —— 武器/法术/技能路由、蓄力、冷却、手持武器朝向
- `player_camera.gd` —— 平滑跟随 + 前瞻 + 死区 + 边界钳制 + 震动（全 @export）
- `actor_sprite.gd` —— 4×7 角色表播放器（`frame_coords` 而非 SpriteFrames）

**敌人 `scripts/enemies/enemy_base.gd`**
- 状态机（待机/游荡/追击/攻击/冲锋/硬直/死亡），三种 AI 由 `EnemyData.kind` 切换；
  精英/Boss 描边、死亡溶解

**世界 `scripts/world/level_runtime.gd`**
- 按 LevelData 刷怪、Boss 生成、门触发切场景、清怪后弹三选一

**Roguelite `scripts/roguelite/modifier_system.gd`**
- 词条收集与乘区累加（FLAT→PERCENT→MULTIPLY）、按权重抽候选、局内清零

**UI `scripts/ui/`**
- `hud.gd`（血/蓝条、技能栏、飘字、提示）、`floating_text.gd`、
  `modifier_choice_ui.gd`（三选一，键鼠双操作）

**着色器 `shaders/hit_flash.gdshader`**
- 闪白 + 溶解 + 描边三合一，参数全 uniform 暴露

**生成工具 `tools/`**（编辑器脚本，不参与运行）
- `generate_data.gd` —— 生成 71 个 .tres
- `generate_levels.gd` —— 生成 3 套 TileSet + 4 个关卡 .tscn + 4 个 LevelData
- `smoke_test.gd` —— 42 项冒烟测试
- `combat_test.gd` —— 9 项战斗链路集成测试
- `capture_screens.gd` —— 无头截图

**文档**
- `docs/ASSETS.md` —— 素材登记表（来源/作者/许可证/规格）
- `docs/LOG.md` —— 本文件
- `README.md`

### 验证方式

```bash
GODOT="D:/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"

# 1. 导入资源、注册全局类
"$GODOT" --headless --path . --import

# 2. 重新生成数据（改过 *Data 脚本后必做）
"$GODOT" --headless --path . res://tools/generate_data.tscn

# 3. 重新生成关卡（改过 generate_levels.gd 后必做）
"$GODOT" --headless --path . res://tools/generate_levels.tscn

# 4. 冒烟测试（42 项）
"$GODOT" --headless --path . res://tools/smoke_test.tscn

# 5. 战斗链路测试（9 项）
"$GODOT" --headless --path . res://tools/combat_test.tscn

# 6. 截图（需窗口模式）
"$GODOT" --path . --resolution 1280x720 res://tools/capture_screens.tscn
```

结果：冒烟 42/42、战斗 9/9 全通过；四张关卡截图目视确认瓦片接缝、
角色朝向、手持武器、HUD 布局均正常。

### 已知限制 / 下一步

- 附魔法术、范围法术的视觉表现尚未接入 `cast_effect` 场景（数据字段已就位）。
- 背包/装备栏只有数据与信号，UI 未做（需求里是"够用即可"，留待后续）。
- 敌人寻路是直线追击，遇到墙体不会绕路；关卡用"宽走廊"规避，后续可接
  `NavigationRegion2D`。
- 技能被动（`Ability.apply_passive`）尚未在装备时自动挂载。
- 死亡后没有复活/回城流程，只广播 `player_died`。

---

## 2026-09-09 武器统一化 + NPC 对话框修复

### 武器：6 个场景合并为 1 个通用场景

**改动前**：sword/big_sword/katana/hammer/bow/wand 各一个 .tscn，结构 99% 相同，
差异（旋转与否/判定盒位置尺寸）硬编码在场景里。新增一把武器要建 .tres + .tscn 两个文件。

**改动后**：
- `scenes/weapons/weapon.tscn`（唯一通用场景）；新增武器 = 只建一个 .tres。
- `WeaponData` 新增字段：`rotate_to_aim`（近战 true / 弓杖 false）、
  `hitbox_offset` / `hitbox_size`（AttackData 缺席时的兜底判定值）。
- `WeaponController.create(data, wielder)` 静态工厂统一实例化入口；
  `WeaponData.weapon_scene` 变为可选覆盖（只有特殊结构武器才填）。
- `EnemyData` 新增 `weapon: WeaponData`（与玩家共用同一套武器数据）；
  `player_combat.gd` / `enemy_base.gd` 全部改走 `create()`。
- 生成器 `generate_weapon_scenes.gd` 改为生成通用场景；`generate_data.gd` 不再绑场景。
- **顺带修了一个隐患**：场景 sub_resource 的 RectangleShape2D 被所有武器实例共享，
  改 A 武器判定尺寸会连带改掉 B 武器的 —— `_resolve_nodes()` 现在会 duplicate 一份。

### 对话框：修复"NPC 对话不弹窗 / 不能按 F 跳过"

**根因**：`EventBus.dialog_requested` 信号**没有任何接收者**——NPC 说话、路牌、
教程长文本全部静默。

**新增**：
- `scripts/ui/dialog_ui.gd` + `scenes/ui/dialog_ui.tscn`（layer 35，Boot 常驻挂载）。
  - 单句提示走 `dialog_requested(text, duration)`；多句对话走
	`dialog_sequence_requested(speaker, lines, on_finished)`，播完/跳过后回调结算奖励。
  - 打字机逐字显示；**按 F 快进 → 下一句 → 关闭**（标准 RPG 手感）。
  - 静态 `DialogUI.is_open` 供任何模块零成本查询。
- 输入互斥：对话框打开时 `Interactable` 让出 F 键（否则一次 F 既推进对话又重新触发交互）、
  `Player` 锁住移动与技能（否则一边看对话一边把技能甩出去）。
- `npc.gd` 改为整段对话交给 DialogUI，不再自己维护"说到第几句"；奖励在关闭回调里结算。

### 验证

- 新增 `tools/weapon_dialog_test.tscn`：22 项检查全通过
  （武器统一化 7 项 + 对话弹窗/推进/关闭/回调/互斥 15 项）。
- 回归：冒烟 42/42、战斗 9/9、交付 93/93、战斗架构 15/15 全绿。
- 真机截图（`docs/qa_screenshots_dialog/`）：对话框弹出、三句逐句推进、
  关闭后「获得：生命药水」奖励到账，链路完整。

---

## 2026-09-10 武器贴图旋转修复（横持 → 正确朝向）

### 现象

武器贴图看起来是横着拿的，与瞄准方向差 90°。

### 根因

- **美术约定**：美术包的 `SpriteInHand` 贴图统一是「握把在上、刃/锤头/杖尖朝下」画的（弓横画）；
- **引擎约定**：武器根节点旋转到瞄准方向，贴图的攻击方向应沿 **+X**；
- 两者相差 90°，且朝左时的 `flip_v` 镜像逻辑是按"贴图刃朝 +X"设计的，对本美术包完全失效。

### 修复

- `weapon_data.gd`：`held_rotation` 默认值 `0.0 → -90.0`（Godot Y 轴朝下，负角度 = 视觉逆时针 90°），
  把刃对准 +X；换"刃朝右"惯例的美术包时在 .tres 里覆写 0 即可。
- `weapon_controller.gd`：朝左镜像 `flip_v → flip_h`（贴图自带 -90° 旋转后，
  flip_v 会把刃翻到瞄准反方向；flip_h 才是正确镜像轴，已用变换矩阵推导 + 截图验证）。
- 玩家兜底手持贴图（`_refresh_held_weapon`）同样读 `held_rotation`，自动一起修正。

### 验证

- 新增 `tools/capture_weapon_rot.tscn`：6 把武器 × 朝右/朝左/朝上 三排陈列截图，
  三个方向全部正确、镜像自然（弓/杖因 rotate_to_aim=false 保持静立姿势）。
- 真机截图（capture_flow → 04_field_combat）：剑横握在手上、刃朝瞄准方向，观感正常。
- 回归：冒烟 42/42、战斗 9/9、交付 93/93、战斗架构 15/15、武器+对话框 22/22 全绿。

### 顺带清理

- 删除了上个会话遗留复活的 `scenes/weapons/big_sword.tscn`（生成器已确认只产出统一场景）。
- 修复 `weapon_dialog_test` 对话推进断言的时序脆弱性：
  短句可能瞬间打完，此时按 F 是翻页而非快进；改为"等打字完 → 读屏 → F 翻页"的确定性循环。

---

## 2026-09-11 武器旋转半径（绕玩家画圈的半径）改为数据驱动

### 改了什么

- 新增 `WeaponData.orbit_radius`（`scripts/data/weapon_data.gd:43`，默认 **12.0**）：
  武器贴图绕使用者画圈的半径（半径 0 = 武器贴在身上）。
- `weapon_controller.gd:239`（`_apply_weapon_data()`）把贴图沿武器 +X 再推出该半径：
  `_sprite.position = Vector2(held_offset.x + orbit_radius, held_offset.y)`。
  根节点每帧转到瞄准角 → 贴图就在半径 = 半径值的圆上跑。
- 半径 0 = 旧行为（武器贴图嵌在身体里，实测贴图距身体 7.3px；半径 12 时为 19.1px）。

### 为什么只推贴图、不动判定盒

第一版是把挥砍支点（SwingPivot）整体外推，贴图与判定盒一起走。结果 `combat_test`
立刻报「攻击盒命中敌人并扣血（35.0 → 35.0）」等 3 项失败 —— 因为该测试把敌人放在
14px 处，判定盒外移 12px 后贴脸敌人落进了"身体与武器之间的死角"。
所以改成**只推贴图**：观感半径与攻击距离解耦，两把旋钮各调各的，战斗手感零变化。

### 怎么调

- 全局默认：`scripts/data/weapon_data.gd:43` 的 `orbit_radius`（改这一行即可）。
- 单把武器：在 `data/weapons/<id>.tres` 里加一行 `orbit_radius = 16.0` 覆盖默认值。
- 若把半径调得很大（>15 左右），刃会伸到判定盒外，那时再把该武器的 `hitbox_offset` 加大。

### 验证

- `combat_test` 9/9、`smoke_test` 42/42、`combat_arch_test` 15/15（判定盒世界偏移回到 22，未受影响）。
- `weapon_dialog_test` 新增第 6 项：贴图落在半径 + 手持偏移处、支点未被移动、
  判定盒不含半径（23 项，1 项既有失败见下）。
- 真机对照截图（`docs/qa_screenshots_weaponrot/orbit_radius_00|08|12|18.png`）：
  4 个半径下同机位特写，用于挑值。实测贴图距身体 7.3 / 15.1 / 19.1 / 25.1 px。
- 未重跑 `generate_data.tscn`：新增字段带默认值，71 个数据资源内容无需变化。

### 既有失败（未处理，待确认）

- `weapon_dialog_test` 的「6 个旧武器场景已删除」仍红：`scenes/weapons/big_sword.tscn` 又被带回来了。
  根因是 `.godot/editor/editor_layout.cfg` 与 `project_metadata.cfg` 的 open_scenes 里还列着它，
  编辑器（含 `--import`）启动时会重新打开并写回该文件。要根治得从编辑器打开列表里移除。

---

## 2026-09-11 对话系统重构：提示条 / 对话条两条通道

玩家反馈四个症状：**卡游戏进程、抢键盘、赖着死不掉、占画面**。逐条找到根因后重写。

### 症状 → 根因

| 症状 | 根因 |
|---|---|
| 卡游戏进程 | ① `Player` 读静态 `DialogUI.is_open`，把移动与**全部动作**清零 → 对话框一旦没关掉就是永久锁死；② 对话框是常驻层，**换关卡时不会自动关闭**，`is_open` 残留到新关卡 → 新玩家一出生就被锁；③ `TutorialSystem.pause_game` 会 `get_tree().paused = true` |
| 抢键盘 | 推进/关闭只认 `interact`(F) 与 `ui_accept`，还在 `_unhandled_input` 里 `set_input_as_handled()` 吃掉；而 `Root.mouse_filter = 2`(IGNORE) → **鼠标根本点不动对话框**。这是个鼠标瞄准 + 鼠标攻击的动作游戏 |
| 赖着死不掉 | ① 单队列：`dialog_requested` 会无条件覆盖 `_queue` 与 `_on_finished` → 教程提示/路牌会**顶掉正在进行的 NPC 对话并把它的奖励回调丢掉**；② `duration <= 0` 常驻时没有任何别的关闭途径（`sign_post` 注释写着"玩家走开就消失"，代码里没实现）；③ 换场景不清理 |
| 占画面 | 固定 260×48 的面板（基准画布 320×180 → 占宽 **81%**、占高 **27%**）；并且教程文字**同时**发 `tutorial_step_shown` 与 `dialog_requested`，同一句话在屏幕上下各显示一遍 |

### 改了什么

**1) `DialogUI` 拆成两条语义不同的通道**（`scripts/ui/dialog_ui.gd` + `scenes/ui/dialog_ui.tscn`）

- **提示条 Notice（完全非阻塞）** —— `dialog_requested(text, duration)`：顶部居中、宽约 148~160px
  （≤50%）、高自适应。点击即收 / 到时消失 / `notice_max_lifetime`（默认 20s）硬上限兜底。
  **不**暂停、**不**锁输入、**不**发 `dialog_opened` —— 玩家可以边走边打边看。
- **对话条 Bar（半阻塞）** —— `dialog_sequence_requested(...)`：底部 176×33（占宽 55%），
  垫在技能栏上方（`offset_bottom = -22`），不再压住 HUD 的技能栏。
- 两条通道各有独立状态，互不覆盖：提示不会再顶掉对话，对话的 `on_finished` 也不会再被丢掉。

**2) 鼠标优先，键盘退居快捷键**

- 点对话条内任意处 = 推进；右上角按钮 = 继续/关闭（文案随状态走：`显示全文` → `继续` → `关闭`）；
  右键 = 直接结束；点提示条 = 立即收起。面板 `mouse_filter = STOP` 才接得住鼠标。
- 键盘只剩 F / Enter / Space，且只吞 `interact` 与 `ui_accept` 两个动作，不再抢别的键。

**3) 不再夺取控制权（"卡游戏进程"的正解）**

- `player.gd` 删掉两处 `DialogUI.is_open` 门闸（`_unhandled_input` / `_read_input`）：对话期间
  照样能移动、攻击、翻滚、放法术。
- 走出 `cancel_distance`（默认 26px）对话自动结束 —— 玩家不必去找关闭按钮，直接走开就能脱身。
- 四种"异常退出"统一走 `cancel_conversation()`：换关卡 / 玩家死亡 / 打开背包或暂停菜单 / 玩家走远。
- 走开属于**取消**，不结算奖励；`npc.gd` 的 `once` 标记从 `_on_interact` 移到 `_grant_rewards`，
  半路走开不再白白吃掉一次性奖励。
- 回调统一走 `_call_safely()`：发起方（NPC）已被释放时不再报错、不再中断收尾流程。

**4) 教程文字只显示一份**

- `tutorial_system.gd` 删掉重复的 `dialog_requested` 调用；`tutorial_step_shown` 增加第三个参数
  `require_confirm`，`tutorial_ui.gd` 据此决定要不要显示"按 F 继续"——自动消失的步骤不再骗玩家按键盘。

**5) 顺手清掉一个既有红灯**

- 删掉复活的 `scenes/weapons/big_sword.tscn`，并从 `.godot/editor/editor_layout.cfg`、
  `project_metadata.cfg` 的 open_scenes / recent_files 里摘除，解决"编辑器一启动就把它带回来"。

### 怎么调

- 走多远算走开 / 提示硬上限 / 暂停时是否收掉：`scripts/ui/dialog_ui.gd` 的 `@export`
  （`cancel_distance` / `notice_max_lifetime` / `close_when_paused`）。
- 两条通道的尺寸与位置：`scenes/ui/dialog_ui.tscn` 里 `Root/Notice`、`Root/Bar` 的 offset/grow。
- 打字机速度：`dialog_ui.gd` 的 `CHARS_PER_SEC`（45 字符/秒）。

### 验证

- `weapon_dialog_test` 从 22 项扩到 **48 项全绿**，新增：鼠标点击推进/关闭、提示条不阻塞、
  提示不打断对话、对话期间玩家输入仍有效、走开自动结束且不结算、换场景/死亡强制收尾、
  提示不会赖着不走、教程只走一条通道；也钉住了"`player.gd` 里不许再出现 `DialogUI.is_open`"。
- 全量回归：`smoke_test` 42/42、`combat_test` 9/9、`combat_arch_test` 15/15、
  `delivery_test` 93/93、`verify_fixes` 17/17。
- 真机截图（`docs/qa_screenshots_dialog/10..15_*.png`，由 `tools/capture_dialog.gd` 用**真实鼠标事件**驱动）：
  对话条 176×33、技能栏不再被遮住、提示条与对话条同屏互不干扰。
  对照旧图 `02_dialog_line1.png`（260×48 的整条黑板），面板面积约为旧版的 46%。

---

## 2026-09-12 对话系统第二轮：对话框自适应排版 + 结构化对话

### 症状 → 根因

玩家报的三个问题，用 `tools/ui_layout_probe.tscn`（遍历真实 UI 树打印
`global_rect` + `get_combined_minimum_size`）逐条量出来：

1. **"部分 UI 元素超出边界"** —— 不是"部分"，是**对话框本身**。
   一段 127 字的台词会让对话条长到 176×210，**顶边跑到 y = -52**：
   半个对话框在屏幕外，连"说话人 + 关闭按钮"那一行都被顶出可视区 —— 关都关不掉。
2. **"对话框尺寸过大"** —— 旧实现把对话条**钉死**成 176×48。
   短句（"你终于醒了"）也占满整条、右边一大片空白；长句挤在 166px 的文字区里
   一行只放得下 13 个汉字，硬堆到 11 行。
3. **"NPC 对话排版不协调"** —— 换行、字号、行距全靠 Label 默认值，
   底部锚定 + 固定高度 = 内容一多就往外冒。

### 改了什么

**1) 先量字，再定框（`dialog_ui.gd` 的 `_fit_bar` / `_apply_bar_offsets`）**

- **宽度**：用 `Font.get_string_size` 量整句自然宽度（**不能**问 Label —— 它开了
  autowrap 之后 `get_combined_minimum_size().x` 恒为 1，永远不说"我想多宽"），
  短句收窄、长句收到 `bar_max_width` 换行，再夹一个 `bar_min_width` 下限。
- **高度**：由内容撑开，底部锚定往上长；预测高度先写进 `custom_minimum_size`，
  避免"先按上一句的高度画一帧再跳"的抖动。
- **关键**：锚定控件的矩形大小由 `anchors + offset` 决定，`custom_minimum_size`
  只是**下限**。场景里 Bar 写着 offset ±88（=176 宽），光改最小宽度是**收不窄**的，
  必须把左右 offset 一起改掉，并让 `grow_horizontal = BOTH` 保证对称。
- **行数上限 + 自动分页**：单句超过 `bar_max_lines`(3) 就按标点均分成若干页，
  翻页就是正常的"继续"。于是**任何长度**的文本都不会溢出、也不会出现"要滚动才能看"。

实测：短句 108px、43 字 296px（2 行）、127 字分页后每页 ≤3 行。

**2) 结构化对话（新增 `DialogueLine` / `DialogueScript` 两个资源）**

对话内容不再是"一串裸字符串"，而是可整段保存、可复用的 `.tres`：

- `DialogueLine`：说话人 / 正文 / **文本样式**（BODY·EMPHASIS·WHISPER·SHOUT·SYSTEM）/
  **显示方式**（打字机·瞬显·自动推进）/ 打字速度 / 逐字语音 / 抖动 +
  **预留**：立绘、头像位置（NONE·LEFT·RIGHT·CENTER·INLINE）、表情状态、微调偏移、`meta`。
- `DialogueScript`：整段默认说话人 / 默认立绘与表情 / 对话条样式 / 整段强制自动推进 / 逐句数组。
- 新增入口 `EventBus.dialog_script_requested(script, on_finished)`；
  旧的 `dialog_sequence_requested(speaker, lines, cb)` 保留为**兼容层**（内部转成
  `DialogueScript.from_strings`），既有 NPC / 测试一处都不用改。
- `npc.gd` 新增 `@export var dialogue: DialogueScript`，优先级：`dialogue` > 旧 `lines`。
- 样式只存在于 Theme：`tools/generate_theme.gd` 新增
  `DialogBodyLabel` / `DialogEmphasisLabel` / `DialogWhisperLabel`(HINT 档) /
  `DialogShoutLabel`(HEADING 档) / `DialogSystemLabel` / `DialogSpeakerLabel` /
  `DialogActionButton`(20px，比默认按钮矮 4px) / `DialogPanel` / `DialogNoticePanel`（**不透明**）。
  节点上不写任何 `theme_override_*`。

**3) 截图取证时抓到两个**真**缺陷（GDScript 断言查不出来）**

- **INLINE 小头像把对话框撑爆**：`Avatar` 是 TextureRect，默认 `EXPAND_KEEP_SIZE`
  → 它的最小尺寸 = 贴图原尺寸。喂进去一张 64×112 的立绘，表头被顶到 112px、
  整个对话条从 51px 涨到 **138px**（顶边跑到 y=20）。修复：`expand_mode = 1`
  (IGNORE_SIZE)，头像被限制在 16×16。
- **立绘尺寸不受控**：`Portrait` 同样补 `expand_mode = 1`，并在 `_cap_portrait_size()`
  里把超过画布的立绘**等比缩到画布内** —— 与"任何长度文本都不越界"是同一条底线。
- **顺带修掉一处潜在崩溃**：`_play_voice` 读的是 `DialogueLine.voice_every`，
  而该属性**并不存在**（只有 `voice_pitch`）。今天没人给行配 `voice_sfx`，
  所以从没触发；一旦配了就会在打字循环里抛错、话说到一半停住。
  改为 UI 常量 `VOICE_EVERY = 3`（每 3 个字响一次）+ 给 `AudioManager.play_sfx`
  加了第 3 个参数 `pitch`，让行级 `voice_pitch` 真正生效。

**4) 顶部两条消息不再打架**

提示条（Notice）会按文本换行变高，之前会盖住固定 y=40 的 HUD Toast。
现在 `DialogUI.notice_bottom` 每帧对外暴露当前底边，HUD 在 `_process` 开头据此
把自己的 Toast 排到提示条**下方**（`maxf(40, notice_bottom + 4)`），两者永不重叠。

### 怎么调

- 自适应数值：`dialog_ui.gd` 的 `@export_group("自适应排版")`
  （`bar_min_width` / `bar_max_width` / `bar_bottom_margin` / `bar_max_lines` /
  `notice_min_width` / `notice_max_width`）。
- 字号 / 颜色 / 行距：`tools/generate_theme.gd` 的 `_setup_dialogue_variations()`，
  改完跑 `generate_theme.tscn` 重新生成 `resources/ui_theme.tres`。
- 逐字语音节奏：`dialog_ui.gd` 的 `VOICE_EVERY`；整句音高：`DialogueLine.voice_pitch`。
- 对话文案：`res://data/dialogue/*.tres`（Inspector 里直接编辑，策划可改）。

### 验证

- **新增** `tools/dialogue_system_test.tscn`：**71 项全绿**。分 A（结构化：数据模型回落、
  旧入口兼容、逐句样式→Theme 变体、三种显示方式、逐字语音不中断打字机）与
  B（排版：宽度随文本变化、任何长度不越界不裁剪、超长自动分页、立绘/头像/表情真的渲染、
  结算语义恰好一次、提示条自适应且不越界）两组。
- `tools/ui_layout_probe.tscn`：**越界 0 处 / 被裁剪 0 处 / 重叠 0 处**。
- **新增** `tools/verify_dialog_shots.py`：把截图脚本每帧打印的"引擎矩形"与截图里
  **实际画出来的像素**对账（PIL 数化），**41 项全绿**。它就是抓出上面两个
  TextureRect 缺陷的工具 —— 几何断言全绿时，像素里却是一个 138px 高的黑框。
- 截图：`tools/capture_dialog.tscn`（**窗口模式**，真实鼠标事件驱动，19 张），
  产物在 `res://Godot/app_userdata/ActRPG/screenshots_dialog/`。校验 0 处状态不符。
- 全量回归：`smoke_test` 42/42、`combat_test` 9/9、`combat_arch_test` 15/15、
  `delivery_test` 93/93、`verify_fixes` 17/17、`playability_check` 15/15、
  `popup_contract_test` 13/13、`weapon_dialog_test` 48/1
  （唯一红灯仍是编辑器进程把已删的 `big_sword.tscn` 写回磁盘，见 2026-09-11 那条）。

### 新增 / 修改文件

- 新增：`scripts/data/dialogue_line.gd`、`scripts/data/dialogue_script.gd`、
  `tools/dialogue_system_test.gd(.tscn)`、`tools/ui_layout_probe.gd(.tscn)`、
  `tools/verify_dialog_shots.py`。
- 重写：`scripts/ui/dialog_ui.gd`、`scenes/ui/dialog_ui.tscn`（节点路径是测试契约，未改名）。
- 修改：`scripts/core/event_bus.gd`（新信号）、`scripts/core/audio_manager.gd`（`play_sfx` 加 pitch）、
  `scripts/world/npc.gd`（`@export dialogue`）、`scripts/ui/hud.gd`（Toast 避开提示条）、
  `tools/generate_theme.gd`（对话变体）、`resources/ui_theme.tres`（重新生成）。

### 已知限制 / 下一步

- `DialogueScript.bar_style`（NORMAL / NARRATOR / SYSTEM）与 `DialogueLine.meta` 目前
  是**预留字段**：数据能配，表现层尚未消费（对话条样式还没有"旁白/系统"两种形态）。
- 立绘只有"贴左/贴右/居中/表头小头像"四种摆法，没有进出场动画与按表情切帧；
  表情目前只通过 `EventBus.portrait_state_changed` 透传出去，没有订阅者。
- 分页是"按标点均分"，还没有"逐字上屏 + 翻页"的滚屏手感；如果以后要打字机跨页，
  需要把 `_entries` 的展平粒度从"页"细化到"行"。
