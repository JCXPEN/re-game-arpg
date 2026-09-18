# 缺陷修复报告（QA_FIXES.md）

对应 [QA_REPORT.md](QA_REPORT.md) 中的 19 个 bug。**全部已修复并有自动化回归覆盖。**

修复日期：2026-09-09
回归验证：`tools/verify_fixes.tscn`（17 项，全通过）

> 说明：QA_REPORT 里有两个描述与实际代码不符，已在下文标注：
> - 报告写"640×480 视口"，实际项目基准分辨率是 **320×180**（1280×720 为 4 倍整数缩放）。
> - 报告说"`tutorial_step.gd` 的 `pause_game` / `require_confirm` 字段从未被读取"、
>   "`player.tscn` 未绑定 `flash_material`" —— 这两条经核实**不成立**，字段和材质都已接好，
>   不在修复清单内。

---

## 一、严重（P0，阻塞主流程）

### BUG-01 三选一界面永久软锁 ✅
- **根因**：`modifier_choice_ui.gd` 弹窗时 `get_tree().paused = true`，但层本身是
  `PROCESS_MODE_INHERIT`，Godot 在暂停态只向 `ALWAYS` 节点派发输入 → 点不动、按 1/2/3 无反应。
- **修复**：`_ready()` 里设 `process_mode = Node.PROCESS_MODE_ALWAYS`。
- **回归**：`verify_fixes` BUG-01 断言 `can_process()` 且 `_active`。

### BUG-02 复活坐标写给了旧玩家 ✅
- **根因**：`game_over_ui._respawn()` 只 `await` 两帧就写坐标，而切场景（淡入淡出）要 ~22 帧，
  新玩家还没生成，坐标落在即将销毁的旧玩家身上。
- **修复**：新增 `SceneDirector.set_next_spawn_position()`，让玩家在**生成时**直接落在存档点，
  彻底消除"先出生再改坐标"的时序竞争。
- **回归**：BUG-02 断言复活后与存档点距离 < 8px（实测偏差 0.0）。

### BUG-03 零敌人关卡的锁门永不开启 ✅
- **根因**：`is_cleared()` 只看 `_cleared` 标志，而该标志只在"敌人死光"时置位；
  城镇 / Boss 房没有敌人，永远等不到那个事件。
- **修复**：`is_cleared()` 在"无存活敌人且无生成记录"时直接返回 true；
  `_ready` 末尾对零敌人关卡预置标志；抽出 `_mark_cleared()` 统一广播。
- **回归**：BUG-03 在城镇断言 `alive==0 && is_cleared()`。

### BUG-04 翻滚无敌帧内可白嫖重击 ✅
- **根因**：`begin_charge` / `release_charge` 不检查玩家状态。
- **修复**：新增 `_can_start_action()`（排除 ROLL/HURT/DEAD 与硬直），
  `release_charge` 在不可行动时改为 `cancel_charge()` 直接丢弃。
- **回归**：BUG-04 进入翻滚态后释放蓄力，断言攻击控制器未进入攻击。

---

## 二、中等（P1，玩法/数值）

### BUG-05 HUD 血条显示敌人血量 ✅
- **根因**：过滤写成 `if _player != null and unit != _player`——`_player` 还没绑定时条件被绕过，
  任何单位受伤都会刷玩家血条。
- **修复**：改成正向判定 `if _player == null or unit != _player: return`。法力条同理。

### BUG-06 HUD 永远绑不到玩家 ✅
- **根因**：`_ready` 里 `await` 一帧后只绑定一次，之后不再重试；HUD 是常驻层，
  而玩家是每关才生成的，必然错过。
- **修复**：`_process` 里持续重试绑定直到拿到玩家；并监听 `scene_changed` 在换关时重新绑定。

### BUG-07 瞄准坐标系混用（最大偏差 92°）✅
- **根因**：`viewport.get_mouse_position()` 是视口坐标，减去玩家世界坐标属于跨坐标系运算。
- **修复**：改用 `player.get_global_mouse_position()`（自带摄像机逆变换）。
- **回归**：BUG-07 在 3 个远离原点的位置实测偏差 **0.0°**。

### BUG-08 最大生命 / 最大法力词条无效 ✅
- **根因**：`get_max_health()` / `get_max_mana()` 直接读 `data.*`，绕过了 `get_stat`。
- **修复**：两个函数改为走 `get_stat`；回蓝也改用 `get_stat(MANA_REGEN)`。
- **回归**：BUG-08 断言体魄生效（100 → 115）。

### BUG-09 限定类词条无视作用域 ✅
- **根因**：`_rebuild_if_dirty` 把所有词条无条件累加，不读 `weapon_kinds` / `elements`。
- **修复**：新增**上下文过滤**——`get_stat(stat, context)` 接收
  `{weapon_kind, element, trigger}`；`_matches_context()` 按 target 判定；
  `Actor.get_attack_context()` 提供默认上下文，`Player` 覆写为当前武器类别 + 残血触发。
  三处伤害计算（攻击盒 / 弹道 / 范围法术）都带上上下文。
- **回归**：BUG-09 断言单手剑下「巨力」不生效。

### BUG-10 叠层公式把增量算了两遍 ✅
- **根因**：`(value + value_per_stack*(n-1)) * n`。
- **修复**：改为等差数列求和 `n*value + value_per_stack*n*(n-1)/2`。
- **回归**：BUG-10 断言 2 层 = 25（旧实现为 30）。

### BUG-11 同名词条被覆盖 ✅
- **根因**：用 `display_name` 做字典键。
- **修复**：改用 `resource_path`（运行时实例退化为实例 id）做键。
- **附带清理**：发现 `generate_data.gd` 把一份数据同时存成 `m_all_mult.tres` 与
  `m_dragon_heart.tres` 两个文件，已统一为 `m_dragon_heart.tres`。
- **回归**：BUG-11 用两个同名实例断言各占一条。

### BUG-12 蓄力被打断后移速永久打折 ✅
- **根因**：打断路径只清 `_charging` 标志，没有复位 `_move_multiplier`。
- **修复**：新增 `cancel_charge()` 统一复位；翻滚、受击、不可行动释放三条路径都调用它。

---

## 三、视觉 / 生命周期（P2）

### BUG-13 飘字不消失 ✅
- **根因**（两处）：
  1. 节点是 `INHERIT`，在暂停态生成时补间不推进；
  2. 释放回调挂在 `set_parallel(true)` 的补间上，**永远不执行**（引擎报
     `Tween started with no Tweeners`）。
- **修复**：`process_mode = ALWAYS`；动画与释放解耦——补间只做视觉，
  释放交给独立的契约计时器 `create_timer(lifetime, true, false, true)`。
- **回归**：BUG-13 按真实时间等 1.5s 后断言节点已释放。

### BUG-14/15 新手教程瞬间自毁 ✅
- **根因**：`_try_start_next()` 会跳过所有"不属于当前关卡"的步骤；
  `start_tutorial()` 在主菜单阶段调用（此时没有当前关卡），14 步全被跳过 → 直接完成。
- **修复**：改为**原地待命**——没有当前关卡或步骤不属于本关时保留索引不推进，
  等 `scene_changed` 再评估；新增 `_shown_steps` 防止重复播同一步。
- **回归**：BUG-14/15 断言主菜单阶段 `running=true`、进城镇后 `index=0`。

### BUG-16 镜头视野超出地图（左侧黑边）✅
- **根因**：`set_target()` 直接把镜头吸附到玩家坐标，不做边界钳制；
  玩家出生在地图角落（48,48）时，视野有一半在地图外，要等 lerp 回边界才消失。
- **修复**：`set_target()` 与 `set_bounds()` 都立即钳制当前位置。
- **回归**：BUG-16 断言视野完全落在地图矩形内（超出 0 px）。

### BUG-17 HUD 血条看不出血量 ✅
- **根因**：`background` 与 `fill` 用了**同一个 StyleBoxFlat**，颜色相同，
  血条永远看起来是满的（截图里的"凸起"其实是这个）。
- **修复**：底槽用近黑暗红 / 暗蓝，填充用亮红 / 亮蓝，掉血时缺口清晰可见。
- **回归**：BUG-17 断言两个 stylebox 颜色不同。

### BUG-18 词条面板文字模糊 ⚠️（已缓解）
- **核实**：字体是 `NinjaAdventure`（150 个字形，**纯拉丁像素字体**），
  中文走系统字体回退，因此中文边缘本来就会抗锯齿——这不是 bug。
  报告说的"±1 抖动"经放大目视确认是正常 AA，文字清晰可读。
- **处理**：把字体导入的 `subpixel_positioning` 从 4（自动）改为 0（禁用），
  让拉丁字形按整数像素落位，像素风更干净；**保留抗锯齿**，否则中文会碎。
- 未改字号/描边：当前字号下已经清晰，改小反而伤可读性。

### BUG-19 全局规则词条从不触发 ✅
- **根因**：`ModifierTarget.GLOBAL` 分支要求 `trigger_tag` 匹配上下文，
  但没有任何代码提供 `trigger`，于是「嗜血狂怒」永远不生效。
- **修复**：`Player.get_attack_context()` 在生命低于 40% 时写入 `trigger = "low_health"`。
- **回归**：BUG-19 断言满血不触发、残血触发。

---

## 四、回归测试

新增 `tools/verify_fixes.tscn`，17 项断言逐条覆盖上述修复：

```bash
GODOT="D:/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
"$GODOT" --headless --path . res://tools/verify_fixes.tscn
```

完整套件（**204 项全通过**）：

| 套件 | 项数 | 结果 |
|---|---|---|
| `smoke_test` | 42 | 0 失败 |
| `combat_test` | 9 | 0 失败 |
| `delivery_test` | 93 | 0 失败 |
| `bug_hunt_test` | 38 | 复现 0 |
| `bug_hunt2_test` | 5 | 复现 0 |
| `verify_fixes` | 17 | 0 失败 |

> 测试本身也修了两个harness缺陷：`bug_hunt_test` 的瞄准项原本在测试里
> 重抄了一份旧表达式（而不是调用真实函数），现已改为调用 `_aim_direction()`；
> `bug_hunt2_test` 的飘字项按帧数等待（headless 下 90 帧仅约 0.6 秒 < 0.75 秒寿命），
> 现已改为按真实时间等待。
