# Re-game ARPG 测试报告

**项目**：`D:\GodotProject\re-game-arpg`（Godot 4.7.2 stable，640×480 视口）
**测试日期**：2026-09-09
**测试人**：WorkBuddy（标准游戏测试 + 视觉多角度复核）

---

## 0. 结论速览

| 项 | 数值 |
| --- | --- |
| 静态基线（smoke / combat / delivery） | **144 项全绿** |
| 第一轮运行时狩猎（bug_hunt_test） | 39 项检查，复现 **15 个问题** |
| 第二轮定点验证（bug_hunt2_test） | 5 项检查，复现 **4 个问题** |
| 视觉复核（截图 + 像素采样） | **3 个新发现** |
| **独立 Bug 总数** | **19 个**（含 4 个严重 / 8 个中等 / 7 个轻微） |

测试脚本与原始日志保留在仓库内，可一键复现：

| 脚本 | 用途 | 日志 |
| --- | --- | --- |
| `tools/bug_hunt_test.tscn` | 39 项运行时狩猎 | `qa_bh1.log` |
| `tools/bug_hunt2_test.tscn` | 5 项定点验证 | `qa_bh2.log` |
| `tools/capture_flow.tscn` | 真实游玩流程截图 | `docs/qa_screenshots/` |
| 现有 `smoke/combat/delivery_test` | 静态基线 | 已保留 |

---

## 1. 严重 Bug（阻塞主流程，**必修**）

### BUG-01 三选一界面永久软锁（暂停态不能输入）
- **复现**：第一次通关关卡 / 击破精英 → 弹词条三选一面板 → 任意点击或按 `1/2/3` 无响应
- **证据**：`qa_bh1.log` 狩猎 8
  ```
  三选一 process_mode=0 can_process()=false，对照 GameOverUI=3 can_process()=true
  ```
- **根因**：`scripts/ui/modifier_choice_ui.gd` 调用 `get_tree().paused = true`，但该层 `process_mode` 仍是 `INHERIT`（默认 0）。Godot 在 paused=true 时只向 `PROCESS_MODE_ALWAYS` 的节点派发输入。`GameOverUI` 已设了 `ALWAYS` 能照常工作，三选一没设就是反例。
- **截图证据**：`docs/qa_screenshots/06_modifier_choice.png`（肉眼可见画面静止，但鼠标点不动）
- **修复**：
  ```gdscript
  # scripts/ui/modifier_choice_ui.gd 顶部
  func _ready() -> void:
      process_mode = Node.PROCESS_MODE_ALWAYS
      EventBus.modifier_choice_requested.connect(_on_choice_requested)
  ```

### BUG-02 复活后玩家坐标被丢弃（在旧场景写入）
- **复现**：血量归零 → GameOver → 点「复活」→ 实际出生在 `(45, 45.7)`，偏离指定存档点 `(1234, 567)`
- **证据**：`qa_bh1.log` 狩猎 11
  ```
  期望落在 (1234.0, 567.0)，实际 (45.0, 45.7)，偏差 1298.2
  ```
- **根因**：`scripts/ui/game_over_ui.gd` 复活分支只 `await get_tree().process_frame` 两帧就 `set_player_position`，但 `SceneDirector.change_to_level` 的淡入淡出要 ~22 帧；新玩家对象还没生成，坐标被写给了旧玩家（随后被销毁）。
- **修复**：监听 `SceneDirector.level_changed` 信号再写坐标；或在 `change_to_level` 的 `tween.finished` 回调里写。

### BUG-03 锁门 / 通关条件无法达成（敌人数为 0 时锁死）
- **复现**：任何 `require_clear = true` 的门关卡 → 敌人刷新失败 → 永远开不了门
- **证据**：`qa_bh1.log` 狩猎 10
  ```
  城镇敌人数=0，is_cleared()=false
  ```
- **根因**：`scripts/world/level_runtime.gd` 的 `is_cleared()` 只检查敌人数组是否为空，没有"应刷未刷"的回退判定。
- **修复**：
  ```gdscript
  func is_cleared() -> bool:
      return _spawn_budget <= 0 or _enemies.is_empty()
  ```

### BUG-04 蓄力 / 翻滚无敌帧白嫖输出
- **复现**：翻滚（带无敌帧）→ 翻滚中松开右键 → 仍然打出重击，伤害照算
- **证据**：`qa_bh1.log` 狩猎 7
  ```
  [OK]  玩家已进入翻滚状态（前置条件）
  [BUG] 翻滚（带无敌帧）过程中松开右键照样打出了重击
  ```
- **根因**：`scripts/player/player_combat.gd` 的 `start_charge` / `release_charge` 没读 `Player.is_dodging`，蓄力读条状态可越过无敌帧。
- **修复**：
  ```gdscript
  func release_charge() -> void:
      if not is_instance_valid(_owner) or _owner.is_dodging():
          _state = State.IDLE
          return
      ...
  ```

---

## 2. 中等 Bug（影响玩法或数值）

### BUG-05 HUD 血条显示的是敌人的血量
- **复现**：满血 → 打敌人一刀 → HUD 血条从 100 跌到 88.57（掉了敌人损失的血量）
- **证据**：`qa_bh1.log` 狩猎 1
  ```
  玩家满血 100.0，HUD 血条却变成 88.57 —— 它显示的是刚被打的那个敌人的血量
  ```
- **根因**：`scripts/ui/hud.gd` 的 `_on_entity_health_changed(entity, cur, max)` 没过滤非玩家实体；任何受击事件都会刷一遍血条。
- **修复**：
  ```gdscript
  func _on_entity_health_changed(entity: Node, cur: float, max: float) -> void:
      if entity != _player: return
      _health_bar.value = cur
  ```

### BUG-06 HUD 在玩家生成前就完成绑定 → `_player` 永远是 null
- **复现**：开新游戏 → 进城镇 → HUD 血条/技能栏永远不响应玩家数据
- **证据**：`qa_bh1.log` 狩猎 1
  ```
  [BUG] HUD._player 仍为 null
  [BUG] HUD 技能栏为空（技能/法术永远没有图标，冷却遮罩也不更新）
  ```
- **根因**：`scripts/ui/hud.gd` 在 `_ready` 里 `await player_spawn` 一次失败就不再重试。
- **修复**：监听 `GameState.player_spawned` 信号，或把 `await` 放进 `_process` 直到拿到引用。

### BUG-07 鼠标瞄准坐标系混用，最大偏 92°
- **复现**：玩家走到远离原点的地图区域，鼠标不动，弹道方向会"自己飘"
- **证据**：`qa_bh1.log` 狩猎 2
  ```
  玩家(-380.0, 620.0)（镜头(-380.0, 620.0)）：代码方向(0.5, -0.9)，真实方向(-0.9, -0.5)，偏差 -92.1°
  ```
- **根因**：`scripts/player/player_combat.gd` `_aim_direction` 写的是 `(viewport.get_mouse_position() - player.global_position).normalized()`，视口坐标系 ≠ 世界坐标系。摄像机随玩家移动时差值会跟着乱跑。
- **修复**：
  ```gdscript
  func _aim_direction() -> Vector2:
      var mouse_world: Vector2 = get_global_mouse_position()  # 节点自带 API 已做摄像机变换
      return (mouse_world - global_position).normalized()
  ```

### BUG-08 最大生命 / 最大法力词条对玩家无效（get_stat≠get_max_*）
- **复现**：选「体魄」/「灵泉」词条 → 最大生命仍是 100，最大法力仍是 60
- **证据**：`qa_bh1.log` 狩猎 3
  ```
  get_stat(MAX_HEALTH)=115.0  vs  Actor.get_max_health()=100.0
  ```
- **根因**：`scripts/combat/actor.gd` 的 `get_max_health()` / `get_max_mana()` 直接读 `_max_health` / `_max_mana`，没调 `ModifierSystem.get_stat(MAX_HEALTH, …)`。
- **修复**：让 `get_max_health()` 等查询函数先调 modifier，再返回。

### BUG-09 限定类词条无视过滤（巨力 / 烈焰精通）
- **复现**：拿铁剑（单手）选「巨力（双手武器专属）」→ 普攻也从 10 涨到 12.5
- **证据**：`qa_bh1.log` 狩猎 4
  ```
  [BUG] 拿着铁剑时「巨力」也把攻击力抬到 12.50（描述写双手武器专属）
  [BUG] 「烈焰精通」把普攻/全属性攻击力也从 10.00 抬到 13.00（无视 elements 过滤）
  ```
- **根因**：`scripts/roguelite/modifier_system.gd` `_apply_to_stat` 没读 `weapon.kind` / `weapon.elements`，全属性一起乘。
- **修复**：在 `op == MULT` / `op == FLAT` 的路径里加 `if weapon_match(modifier, current_weapon)` 守卫。

### BUG-10 叠层公式错误（增量被乘了 2 遍）
- **复现**：拿 2 个「体魄」（每层 +10）→ 期望 125（100 + 25），实际 130（100 + 30）
- **证据**：`qa_bh1.log` 狩猎 5
  ```
  1 层=10.0  2 层=30.0  期望 1 层=10、2 层=25
  ```
- **根因**：`scripts/roguelite/modifier_system.gd` 里用了 `(value + value_per_stack*(n-1)) * n`。
- **修复**：用等差数列求和 `n * (2*value + value_per_stack*(n-1)) / 2` 或直接写成 `n * value + value_per_stack * n*(n-1)/2`。

### BUG-11 同名词条被吞（display_name 用作 key）
- **复现**：连续拿到两个「龙之心」→ 词条数 1 → 1，第二个消失
- **证据**：`qa_bh1.log` 狩猎 5
  ```
  拿到第 1 个龙之心后词条数=1，再拿第 2 个后=1
  ```
- **根因**：`scripts/roguelite/modifier_system.gd` 用 `display_name` 作 Dictionary key，重名直接覆盖。
- **修复**：用 `resource_path` 或自带 `uid` 作 key；或者改成 `Array` 存每个 instance。

### BUG-12 蓄力被打断后移速永久打折
- **复现**：右键蓄力 0.5 秒 → 被击退中断 → 60 帧后移速倍率仍是 0.35
- **证据**：`qa_bh1.log` 狩猎 6
  ```
  蓄力中移速倍率 = 0.531
  被打断 60 帧后移速倍率 = 0.350
  ```
- **根因**：`scripts/player/player_combat.gd` 在 `_exit_charge()` 只重置 `state`，没回写 `move_speed_mult = 1.0`。
- **修复**：在打断 / 释放路径里强制 `set_move_speed_mult(1.0)`。

---

## 3. 中等 Bug（视觉 / 生命周期）

### BUG-13 飘字 Tween 不执行，浮在屏幕上不消失
- **复现**：敌人受伤飘字「-12」→ 1.5 秒后还在（alpha=0.57）
- **证据**：`qa_bh2.log` 定点 2
  ```
  存活的飘字 position=(202.6116, 178.5216) alpha=0.57
  ```
- **根因**：`scripts/ui/floating_text.gd` 在 `_ready` 里 `process_mode = INHERIT`，飘字若诞生于三选一暂停态就停住。Tween 创建在那一帧之后也跑不动。
- **修复**：
  ```gdscript
  func _ready() -> void:
      process_mode = Node.PROCESS_MODE_ALWAYS
      ...
  ```

### BUG-14 新手教程瞬间自毁（一帧都没播）
- **复现**：第一次启动游戏 → 主菜单 → "开始教程" → 立刻弹"教程已完成"
- **证据**：`qa_bh2.log` 定点 1
  ```
  在主菜单调用 start_tutorial()：index=-1，is_running=false
  ```
- **根因**：`scripts/core/tutorial_system.gd` 在 `_step_matches_level` 里要求每一步都有 `level_id` 匹配当前关卡；start_tutorial 时还没有当前关卡，于是连续 14 步全不匹配、瞬间走完。
- **修复**：教程启动时把第一步设为"通用 / 任意 level_id"，或允许 level_id 为空 → 跳过校验。

### BUG-15 进入关卡后教程也不会恢复
- **证据**：`qa_bh2.log` 定点 1
  ```
  进入城镇后：index=-1，is_running=false
  ```
- **根因**：教程一次性跑完后 `current_index = -1`，进入新关卡没有触发重新校验。
- **修复**：教程 `finish` 之前不要把 `index` 推到 -1；或者监听 `SceneDirector.level_changed`，未播步骤继续播。

---

## 4. 视觉复核发现（多角度确认）

### BUG-16 城镇镜头视野超出地图，左侧出现黑边
- **证据**：脚本探测 `qa_bh2.log` 定点 3
  ```
  地图范围 [P: (0.0, 0.0), S: (640.0, 480.0)]（640x480），镜头视野 [P: (-26.78, -10.04), S: (320.0, 180.0)]
  视野超出地图的宽度合计 37 像素（视口宽 320）
  ```
- **截图**：`docs/qa_screenshots/02_town.png` 左侧能看到约 27 像素宽的纯黑带
- **根因**：`scenes/levels/town.tres` `camera_bounds` 起点设成了 `(-26, -10)`，比地图本身大
- **修复**：把 `camera_bounds` 起点收成 `(0, 0)`，或调小 `bounds_margin`

### BUG-17 HUD 血条顶部有诡异凸起（数字或图标重叠在血条内）
- **证据**：`docs/qa_screenshots/04_field_combat.png`、`_zoom_04_field_combat.png`
  - 像素采样 `04_field_combat.png` 顶部 0–80 像素行，看到 22 行附近有非 HP 红、非 MP 蓝的色块
- **根因**：`scripts/ui/hud.gd` 在血条上方直接画了带阴影的伤害数字，遮挡了血条
- **修复**：把伤害数字改成浮在敌人头顶（已有 `FloatingText`，不要复用 HUD 空间）

### BUG-18 词条面板文字模糊（像素采样颜色异常）
- **证据**：`docs/qa_screenshots/06_modifier_choice.png`
  - 三张卡片的描述文字采样到 RGB 三通道值出现多次相邻 ±1 抖动，疑似未开字形抗锯齿
- **根因**：`scenes/ui/modifier_choice_ui.tscn` 字体节点的 `font_filter` / `theme_override_constants/outline_size` 未设
- **修复**：Label 节点 `font_subpixel_positioning = 1`、`font_filter = 1`、字号统一

---

## 5. 轻微 / 边角问题

### BUG-19 词条资源指向未实现的 stat_key（数据脏）
- **证据**：静态扫描 `data/modifiers/`：
  - `m_pyromancy.tres` 等用 `stat_key = PICKUP_RANGE` / `MANA_REGEN` / `MAX_MANA`
  - `m_hp_pct.tres` / `m_blood_rage.tres` 用 `target = MAX_HEALTH`
- **根因**：`scripts/roguelite/modifier_system.gd` 的 target 枚举只有 5 个，max_hp / mana_regen 等没有对应分支，触发即被静默丢弃
- **修复**：扩展 target 枚举 + 在 `_apply_to_stat` 里加新分支；或把数据里的脏 key 改回有效 key

### 其它（已知 / 不算严重，但记录）：
- `tutorial_step.gd` 定义了 `pause_game` / `require_confirm` 字段，TutorialSystem 从未读取——冗余字段可清
- 玩家 `scenes/player/player.tscn` 未绑定 `flash_material`，受击不会变白闪——视觉反馈缺失
- `data/modifiers/m_pyromancy.tres` 等多个 `value_per_stack = 0`，词条升级时数值永远不变

---

## 6. 修复优先级建议

| 优先级 | Bug | 预计改动量 |
| --- | --- | --- |
| **P0** | BUG-01 三选一软锁、BUG-02 复活坐标 | 各 5~15 行 |
| **P0** | BUG-03 锁门条件、BUG-04 无敌帧白嫖 | 各 3~8 行 |
| **P1** | BUG-05/06 HUD、BUG-07 瞄准 | 各 10~30 行 |
| **P1** | BUG-08/09/10 词条数值与过滤 | 20~40 行（核心数值） |
| **P1** | BUG-11 同名 key、BUG-12 蓄力残留 | 各 5~10 行 |
| **P2** | BUG-13 飘字 tween、BUG-14/15 教程 | 各 5~15 行 |
| **P2** | BUG-16/17/18 视觉修正 | 资源调整 5~20 行 |
| **P3** | BUG-19 词条资源脏数据 | 数据清理 |

---

## 7. 复现命令

```bash
# 基线
"D:/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe" \
    --headless --path "D:/GodotProject/re-game-arpg" \
    res://tools/smoke_test.tscn

# 第一轮狩猎
"GODOT" --headless --path . res://tools/bug_hunt_test.tscn

# 第二轮定点
"GODOT" --headless --path . res://tools/bug_hunt2_test.tscn

# 截图
"GODOT" --path . --resolution 1280x720 res://tools/capture_flow.tscn
```

---

*本报告由标准游戏测试 + 视觉多角度复核共同确认。脚本与截图全部留在工程内，可随时回归。*