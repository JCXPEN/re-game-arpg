# re-game-arpg 架构说明文档

> 2.5D 俯视动作 Roguelite ARPG · Godot 4.7.2 · 像素风
>
> 本文基于项目实际代码逐文件阅读整理，描述其**运行架构、模块边界、数据流与约定**。
> 修改任何脚本/场景/UI/数据前，请先对照本文与 `.workbuddy/skills/godot-arpg-conventions/SKILL.md`。

---

## 目录

1. [项目概览](#)
2. [技术栈与工程配置](#)
3. [目录结构总览](#)
4. [运行时架构与启动流程](#)
5. [核心系统（Autoload 单例）](#5-autoload)
6. [数据层](#)
7. [战斗系统](#)
8. [世界与可交互物](#)
9. [UI 系统](#9-ui)
10. [Roguelite 词条系统](#10-roguelite)
11. [特效系统](#)
12. [构建与资源管线（tools/ 生成器）](#12-tools)
13. [项目约定速查](#)
14. [测试体系](#)
15. [如何运行 / 扩展 / 排错](#)
---

## 1. 项目概览

**re-game-arpg** 是一款 2.5D 俯视视角的动作 Roguelite 原型：玩家从城镇出发，进入野外、地牢，最终挑战 Boss 房。核心循环是「清怪 → 三选一词条成长 → 变强 → 打更硬的怪」。

设计理念（贯穿整个代码库）：

- **行为即代码，数值即数据**：所有可调参数（伤害、速度、冷却、字号、颜色）一律外置到 `@export` / `Theme` / `.tres` / 生成器脚本，代码只描述行为逻辑。
- **系统解耦**：任意两个系统互不持有引用，只通过 `EventBus` 信号通信，任一系统可被单独删除或替换。
- **数据驱动**：一把武器 = 一个 `WeaponData` 资源，不为武器建专属 `.tscn`；词条、敌人、关卡、教程全是目录扫描发现的资源。
- **资源由生成器产出**：所有 `.tscn` / `.tres` 由 `tools/` 下的生成器脚本唯一生成，不直接手改产物。

---

## 2. 技术栈与工程配置

| 项 | 值 |
|---|---|
| 引擎 | Godot 4.7.2（`GL Compatibility` 渲染后端） |
| 主场景 | `res://scenes/core/boot.tscn` |
| 分辨率 | 视口 **320×180**，4 倍整数拉伸到 **1280×720** |
| 字体 | Fusion Pixel 12px（点阵，SIL OFL 1.1），导入参数 `oversampling=4.0`（"放大再缩小"以保清晰） |
| 语言 | GDScript（全静态类型） |
| 存档 | `user://savegame.json`（自定义 JSON 序列化） |

### 输入映射（InputMap）

| 动作 | 含义 | 备注 |
|---|---|---|
| `move_left` / `move_right` / `move_up` / `move_down` | 移动（四向，组合成向量） | 斜向已归一化 |
| `attack` | 轻攻击 | 后摇可取消 |
| `heavy_attack` | 重攻击（按下蓄力 / 松开释放） | |
| `roll` | 翻滚 | 带无敌帧 |
| `spell_1/2/3` | 法术槽 | |
| `ability_1/2` | 主动技能槽 | |
| `interact` | 交互 / 确认 | 同时用于教程确认、帮助关闭 |
| `pause` | 暂停菜单 | |
| `ui_accept` / `ui_cancel` | 通用确认/取消（物理键判定，含 J/回车等） | 关闭弹窗用 |

### 碰撞层约定（`project.godot` 的 `[layer_names]`）

| 层 | 含义 |
|---|---|
| 1 | World（地形/墙） |
| 2 | PlayerBody |
| 3 | EnemyBody |
| 4 | PlayerHurtbox |
| 5 | EnemyHurtbox |
| 6 | PlayerAttack |
| 7 | EnemyAttack |
| 8 | Pickup |
| 9 | Projectile |
| 10 | Interactable |

受击盒（`Hurtbox`）只 `monitorable`、不 `monitoring`；攻击盒/弹道主动扫描。这是"被动受击、主动攻击"分离的基础。

---

## 3. 目录结构总览

```
re-game-arpg/
├── project.godot                # 工程配置：autoload、渲染、输入、碰撞层
├── boot.gd / boot.tscn         # 实际上 boot 在 scenes/core/
├── scenes/                     # 所有场景（由 tools/ 生成器产出）
│   ├── core/                   # boot、transition（转场遮罩）
│   ├── player/                 # player.tscn
│   ├── enemies/                # enemy.tscn（所有敌人共用）
│   ├── fx/                     # projectile / area_spell / enemy_projectile
│   ├── levels/                 # town / field / dungeon_1/2 / boss_room
│   ├── ui/                     # 各 UI 面板场景
│   ├── weapons/                # weapon.tscn（武器通用场景）
│   └── world/                  # npc / chest / sign_post / locked_door / save_point / heal_spring
├── scripts/                    # 79 个 .gd，按域分子目录
│   ├── core/                   # boot, event_bus, data_registry, game_state,
│   │                           #   scene_director, tutorial_system, hit_stop,
│   │                           #   audio_manager, transition
│   ├── data/                   # *Data 资源类 + game_enums + damage_info
│   ├── combat/                 # actor, attack_controller, weapon_controller,
│   │                           #   projectile, ability, area_spell, attack_box
│   ├── player/                 # player, player_combat, player_camera, actor_sprite
│   ├── enemies/                # enemy_base
│   ├── world/                  # level_runtime, interactable, npc, chest, ...
│   ├── ui/                     # hud, dialog_ui, tutorial_ui, help_panel,
│   │                           #   popup_manager, main_menu, pause_menu, ...
│   ├── roguelite/             # modifier_system
│   └── fx/                     # fx_sprite
├── data/                       # 67 个 .tres 数据资源（武器/法术/技能/敌人/
│                               #   词条/关卡/教程/攻击帧/物品/角色）
├── resources/                  # ui_theme.tres + 3 套 tileset
├── assets/                     # 美术/音频/字体/特效贴图（499 个文件）
├── tools/                     # 生成器 + 测试（71 个文件）
└── docs/                       # 文档、日志、QA 截图
```

**脚本/场景数量**：79 个 `.gd`、55 个 `.tscn`（含 `big_sword.tscn` 孤儿，详见 §15）。

---

## 4. 运行时架构与启动流程

### 4.1 Autoload 初始化顺序

`project.godot` 的 `[autoload]` 段（顺序有意义）：

```
EventBus → PopupManager → DataRegistry → GameState → ModifierSystem
         → TutorialSystem → HitStop → AudioManager → SceneDirector
```

- **EventBus 必须第一**：其余 autoload 在 `_ready` 里 `connect` 信号，若 EventBus 未就绪则连不上。
- SceneDirector 放最后：它依赖 DataRegistry 与 EventBus，且不必在其它系统之前存在。

### 4.2 启动流程图

```
[Engine 启动]
   │  按 project.godot 顺序实例化 9 个 autoload（仅注册/连信号，不做玩法）
   ▼
[Boot._ready]  (scenes/core/boot.tscn 是 main_scene)
   ├─ _install_persistent_ui()   挂 8 个常驻 UI 到 root（call_deferred）
   │     HUD / TutorialUI / BossHealthBar / DialogUI / ModifierChoice
   │     / InventoryUI / GameOverUI / PauseMenu
   └─ _show_main_menu()  → 实例化 MainMenu 挂到 root
   ▼
[玩家点"开始"（或 skip_menu）]
   └─ _begin_game()
        ├─ GameState.start_run()        // 清空局内状态，emit run_started
        ├─ TutorialSystem.start_tutorial()  // 新档才启用
        └─ SceneDirector.change_to_level(&"town", &"start")
             │
             ▼  _fade_out → _swap_scene → _fade_in
                  ├─ queue_free 旧场景（await process_frame）
                  ├─ 实例化 LevelData.scene → 挂到 root（call_deferred）
                  ├─ await process_frame
                  ├─ _spawn_player(entry_point)   // 复用或新建 Player
                  ├─ AudioManager.play_music(level.bgm)
                  └─ EventBus.scene_changed.emit(scene)
                       └─ HUD._on_scene_changed → 解绑旧玩家，等待重新绑定
                       └─ TutorialSystem._on_scene_changed → 评估当前步骤是否该播
```

**关键时序约束**（踩过的坑，已在代码注释固化）：

- `_ready()` 里往 `root` 加节点必须 `call_deferred`，否则报 `Parent node is busy setting up children` 并静默失败。
- `call_deferred` / `queue_free` 后必须 `await get_tree().process_frame` 才生效，否则紧接着操作拿到空节点。
- 常驻 HUD 在开场几帧必然拿不到玩家（玩家每关重建），用"每帧重试绑定直到成功"而不是一次性绑定。

### 4.3 关卡流转

`SceneDirector` 是唯一负责场景切换的服务：

- `change_to_level(level_id, entry_point)`：检查 `_changing` 防连点 → 记代次 → 淡出 → 换场景 → 放玩家 → 淡入。每个 `await` 后校验代次，保证**可取消**；`_changing` 一定复位（否则后续所有切换会被静默丢弃）。详见 §5.4。
- `set_next_spawn_position(pos)`：**必须在** `change_to_level` 之前调用，玩家生成时直接落在该坐标（存档点复活用），而非先出生再改坐标——后者会与异步切换抢时序。
- 出口 `Trigger` 由 `LevelRuntime._connect_doors()` 监听，玩家踩到 → `EventBus.scene_change_requested` → SceneDirector 响应。

### 4.4 局面生命周期（GameFlow 状态机）

`scripts/core/game_flow.gd`（autoload）既是"开始一局 / 回主菜单"的唯一入口，也是**局面状态机**：

- **状态**：`enum State { BOOT, MENU, PLAYING, PAUSED, GAME_OVER }`，转移必须过 `LEGAL_TRANSITIONS` 表；非法转移被 `request()` 拒绝并告警（返回 false）。
- `start_run(level_id, entry)`：清理上一局 → 显式激活局内 UI → `GameState.start_run` → 记录 PLAYING → 切关卡。主菜单"新的冒险/继续"、死亡复活、Boot 跳菜单都走它。
- `teardown_to_menu(load_menu_music)`：**先** `SceneDirector.detach_level()`（作废在途转场）→ `PauseManager.clear_all()` → 收起 GAMEPLAY_UI（HUD/Boss 血条）→ 收起 TRANSIENT_UI（背包/帮助/设置/三选一/结算/对话/教程，优先走各自 `force_close()`）→ `PopupManager.release_all()` → `TutorialSystem.reset()` → 停关卡 BGM、按需播**带 owner=menu** 的菜单曲 → 挂主菜单 → 记录 MENU。
- 参数 `load_menu_music=false` 专供 `start_run` 的"进关前清理"：不清可见性、不播菜单曲、不挂菜单、不改局面。
- **与 PauseManager 的边界**：GameFlow 管"局面"，`PauseManager` 令牌管"paused 位"，后者仍是暂停的唯一真相。PAUSED 由 `PauseMenu.open/close` 通过 `set_paused()` 同步。

### 4.5 场景树容器（Boot = Main 控制器）

按官方《Scene organization》的 `Main → World / GUI` 结构，`Boot` 在启动时建立三个容器：

```
Boot (run/main_scene)
├── World (Node2D)      ← 只挂当前关卡实例；换关卡只动这一个子节点
├── GUI (CanvasLayer)   ← 局内 HUD：HUD / BossHealthBar
└── Menus (CanvasLayer) ← 菜单层：TutorialUI / DialogUI / 三选一 / 背包 / 结算 / 暂停
```

`UIRegistry`（autoload）持有这些容器并提供窗口登记（见 §9.4）。root 直属子节点因此只剩 autoloads + Boot。

---

## 5. 核心系统（Autoload 单例）

### 5.1 EventBus —— 通信中枢

`scripts/core/event_bus.gd`。**只放 `signal` 声明，不放任何逻辑与状态**（否则会变成上帝对象）。信号按域分区：

- **战斗**：`damage_dealt` / `hit_landed` / `unit_died` / `health_changed` / `mana_changed`
- **玩家/成长**：`player_stats_changed` / `experience_gained` / `player_died` / `item_acquired` / `equipment_changed`
- **Roguelite**：`modifier_choice_requested` / `modifier_chosen` / `run_started` / `run_ended`
- **关卡**：`scene_change_requested` / `scene_changed` / `room_cleared` / `boss_defeated`
- **UI/系统**：`floating_text_requested` / `toast_requested` / `dialog_requested` / `dialog_sequence_requested` / `dialog_opened` / `dialog_closed` / `tutorial_step_shown` / `tutorial_finished` / `hit_stop_requested` / `camera_shake_requested`

**约定**：信号名 `领域_事件`；复杂数据传 `Resource` 或 `Dictionary`；`Callable` 回调必须安全调用（见 §13）。

### 5.2 DataRegistry —— 数据注册中心

`scripts/core/data_registry.gd`。启动时扫描 `res://data/` 下 9 个目录，按 `class_name` 归类建索引，提供 O(1) 查询。

- **为什么用目录扫描而非手写列表**：新加 `.tres` 只需丢文件，策划/美术不碰代码。导出后 `.pck` 内 `ResourceLoader.list_directory` 同样可用。
- 资源 id 优先级：**显式 id 字段 > 文件名**（不用 `display_name`，避免改中文名就查不到）。
- `class_name` 必填：缺了 `get_script().get_global_name()` 为空，该资源被跳过并 `push_warning`。
- 查询失败一律 `push_warning`（静默失败最难查）。

### 5.3 GameState —— 运行状态与存档

`scripts/core/game_state.gd`。保存"跨场景存活"的数据，且**严格区分局内/局外**：

- **局外（永久）**：`unlocked_spells/abilities/weapons`、`gold`、`defeated_bosses`、`furthest_level`、`tutorial_completed`、`inventory`。
- **局内（run 结束清零）**：`run_modifiers`、`run_active`、`run_kills`、`run_time`、`respawn_*`。

`start_run()` 清空局内并 `emit run_started`（ModifierSystem 监听以清词条）；`end_run(victory)` 清词条并 `save_game()`。**不直接引用玩家节点**——破坏"系统不互相持有引用"约定。

### 5.4 SceneDirector —— 场景切换服务

`scripts/core/scene_director.gd`（autoload）。场景切换是**协程**（淡出 → 换场景 → 淡入，横跨十几帧），因此必须能**取消**：

- **代次（generation）令牌**：`change_to_level` 开始时 `_generation += 1` 并记住自己的 `gen`；每个 `await` 之后比对，对不上就立刻返回，绝不再碰 `_current_scene` / BGM / 玩家。
- **提交顺序**：新场景先以本地变量实例化、挂树，等所有 `await` 走完、确认没被取消，才**一次性提交** `_current_level` / `_current_scene` / 玩家 / BGM。取消路径只需释放本地临时场景，不污染跨场景状态。
- `detach_level()`（回主菜单）会 `_generation += 1` 并清空引用，令所有在途切换作废。**否则**玩家在转场中途按 Esc 返回主菜单后，那条被"抛弃"的协程醒来会把关卡挂回 root、重播关卡 BGM —— 主菜单背后活着一局游戏（用户报的"BGM 与场景不匹配 / UI 状态错乱"的直接成因）。`fade_time = 0` 时竞态窗口最窄，是必测点。
- 玩家生成 `_spawn_player` 对 `_current_scene` 判空，避免切换失败时对 null 调用 `get_node_or_null` 崩溃。

### 5.5 TutorialSystem —— 新手教程

`scripts/core/tutorial_system.gd`（注意：它是 autoload，**不能**写 `class_name`，否则与单例冲突）。

- 从 DataRegistry 读 `TutorialStep` 按 `order` 排序；只在 `GameState.tutorial_completed == false` 时启用。
- 步骤显示走**唯一**通道 `EventBus.tutorial_step_shown`（顶部面板），**不**再发 `dialog_requested`（旧实现两路都发，同一句话出现两遍）。
- 关键语义：当前步骤不属于本关卡时**原地待命**，等 `scene_changed` 再播——绝不能"跳过不匹配的步骤"，否则主菜单阶段就把 14 步全走完自毁。
- `pause_game` 步骤会**经 `PauseManager` 令牌**冻结世界：冻结状态由当前步骤推导（`_sync_pause()`），每一条出口（推进/关闭/跳过/复位/结束）都同步一次，**不做"成对 freeze/unfreeze + 私有布尔"的记账**（那样漏一条出口就会把玩家永久冻住）；连续两个阻塞步之间令牌不交还，冻结连续不断。玩家可主动 `dismiss_current_step()` 跳过自动隐藏的步骤。
- **语义护栏**：`pause_game = true` 但 `trigger_action` 非空（要求玩家在世界里做事才算完成）的步骤**不冻结** —— 冻结会让完成条件永远不可能达成（教程死锁、"与 NPC 交谈"那一步的对话永远不显示）。见 `TutorialSystem._step_wants_freeze()`。
- **数据即策略**：纯"读说明"的步骤配 `pause_game = true`（窗口开着 = 世界冻结，不能跑动/挨打）；要求玩家做事的三步（010 普攻 / 022 三选一 / 001 交谈）配 `false`。`step_001` 的完成条件是 `trigger_action = &"talk"`——由 `dialog_opened` 打标，**说了话才算过关**，而不是等 8 秒自动消失。

### 5.6 HitStop —— 命中顿帧

`scripts/core/hit_stop.gd`。命中瞬间把 `Engine.time_scale` 压到接近 0 持续极短，制造"刀刀到肉"手感。

- 计时器必须用 `ignore_time_scale = true` 的 `create_timer`，否则 time_scale 压低后计时器也被拖慢，顿帧永不结束。
- 用 `_token` 代次处理嵌套顿帧：只有"最后一次请求"有权恢复 `time_scale`。
- `tree_exiting` 强制复位（切场景不留残顿帧）。

### 5.6.1 SaveManager —— 存档 IO 服务

`scripts/core/save_manager.gd`。**只做磁盘读写**：JSON 序列化/反序列化、版本头校验、路径管理。
它不认识任何游戏字段含义——那是状态持有者（`GameState`）的知识。
`GameState.save_game()/load_game()` 委托它，因此状态可脱离文件系统被断言（对照官方"autoload 适合存全局变量 / 修改他人数据的系统应是普通脚本"的切分）。

### 5.6.2 SettingsService —— 设置服务

`scripts/core/settings_service.gd`。集中管理玩家设置的**读写与应用**：线性↔分贝转换、`ConfigFile` 持久化、`AudioServer`/`DisplayServer` 应用、旧配置键迁移。
`SettingsPanel` 因此重写为**只渲染 + 转发**（改动即时生效并落盘，"确定/返回"只负责关闭）。

### 5.7 AudioManager —— 音频服务

`scripts/core/audio_manager.gd`。预创建 16 个 `AudioStreamPlayer` 池；`play_sfx` 从池取空闲播放器（全忙则丢弃），随机音调避免重复音效呆板；`play_music` 同曲不重启。`stream == null` 静默返回（允许数据留空）。

**音乐归属（owner）是"BGM 与场景是否匹配"的判定依据**：

- `play_music_for(owner, stream, restart)` 是正式入口，owner 如 `&"menu"` / `&"level:town"`。owner 相同且同曲才不重启；owner 变了强制换（同一首曲子在不同场景也要重头放）。
- `play_music(stream)` 是便捷入口，内部委托给 `play_music_for(&"music", ...)`，**不再**留下空 owner —— 否则主菜单放出的曲子没有归属，切场景时按 owner 比对必然错位。
- `stop_music()` 停止播放器并清空 `_current_music` / `_music_owner` 三者，保证"停干净"。
- 关卡没配 BGM 时由 `SceneDirector` 调 `stop_music()`，**不**沿用上一首（沿用就是 BGM 错配的直接成因）。

### 5.8 PopupManager —— 弹窗互斥调度

`scripts/ui/popup_manager.gd`（autoload，顺序紧随 EventBus，确保最先就绪）。解决"多来源同时弹窗"问题：

- 同一时刻只放一个活动弹窗；晚到的进按**优先级**排序的队列（教程 100 > 帮助 60 > 对话 50）。
- `is_close_key(event)` / `is_close_click(event)` 集中判定统一关闭手势（J / 回车 / 左键）。
- 提示条（Notice）是非阻塞 toast，**不参与互斥**。

---

## 6. 数据层

`scripts/data/` 下是一组 **资源类（`*.gd` + `*.tres`）**，描述"是什么"而非"怎么动"。

| 资源类 | 文件 | 描述 |
|---|---|---|
| `CharacterData` | `data/characters/*.tres` | 角色基础属性模板：血量/法力/攻防/移速/暴击/韧性/击退抗性/受击表现/死亡溶解参数 |
| `EnemyData` | `data/enemies/*.tres` | 敌人属性（含 AI 类型、掉落） |
| `WeaponData` | `data/weapons/*.tres` | 武器：贴图、判定盒偏移/尺寸、挥砍弧线、是否跟随瞄准、范围倍率、关联场景 |
| `AttackData` | `data/attacks/*.tres` | 单次攻击的帧数据：前摇/判定/后摇、连击窗口、取消窗口、自位移、命中盒 |
| `SpellData` | `data/spells/*.tres` | 法术：投射物/区域、元素、伤害、冷却 |
| `AbilityData` | `data/abilities/*.tres` | 主动技能（冲刺/治疗/旋风斩等） |
| `ModifierData` | `data/modifiers/*.tres` | 词条：作用目标、操作类型(FLAT/PERCENT/MULTIPLY)、数值、叠加上限、权重、作用域过滤 |
| `ItemData` | `data/items/*.tres` | 物品（金币/钥匙/药水） |
| `LevelData` | `data/levels/*.tres` | 关卡：场景引用、默认入口、BGM、相机边界、环境色 |
| `TutorialStep` | `data/tutorial/*.tres` | 教程步骤：顺序、标题、文本、是否需确认、是否暂停、自动隐藏时长、适用关卡 |
| `GameEnums` | `data/game_enums.gd` | 全局枚举：`StatKind` / `ModifierTarget` / `ModifierOp` / `Element` 等 |
| `DamageInfo` | `data/damage_info.gd` | 伤害信息载体：amount / is_crit / knockback / poise_damage / source / element |

**唯一属读取口**：`Actor.get_stat(kind, context)`（见 §7.1）。任何伤害/移动/冷却计算都必须走它，否则 Roguelite 词条全部失效。

---

## 7. 战斗系统

战斗是一条"基类 → 组件"的清晰链路，把"数值"与"行为"彻底分离。

### 7.1 Actor —— 有血条单位的基类

`scripts/combat/actor.gd`（`extends CharacterBody2D`）。玩家、敌人、Boss 的公共部分：血量/法力、受伤结算（乘法减伤 `dmg * 100/(100+def)`）、无敌帧、硬直、击退（指数衰减）、死亡（溶解/淡出）。

- `get_stat(kind, context)`：**全游戏唯一的属性读取口**。玩家经 `ModifierSystem.apply_stat` 叠加词条；敌人直接取 `CharacterData`。
- `get_attack_context()`：默认空（敌人不吃词条），玩家覆写返回当前武器类别/残血触发。
- `apply_damage(info)`：唯一扣血入口。霸体不进硬直；击退按 `knockback_resist` 打折（Boss 设 1.0 即站桩）。
- 受击表现（闪色 + 抖动 + 溶解）全部参数来自 CharacterData，Boss/精英可调。
- **着色器材质必须每实例独占**：`Actor._ready()` 调 `_ensure_owned_material()` 从 `flash_material`
  模板 `duplicate()` 出本实例一份并缓存，闪白/溶解/精英描边都只改这一份。
  场景层再用 `resource_local_to_scene = true` 做第二道保险。
  【为什么必须这样】`ShaderMaterial` 是可变资源，Godot 的**子资源默认跨实例共享**；
  共用一份就会"一个敌人受击、全体一起闪红"（见 §13 与 LOG 2026-09-13 深夜）。
  规则：任何"每实例要各自改参数"的资源（ShaderMaterial / Curve / Gradient / Shape…）
  都要按实例隔离，不能依赖"当前有没有被预挂"来决定是否复制。

### 7.2 Player —— 玩家角色

`scripts/player/player.gd`（`extends Actor`）。把输入翻译成动作，实现三大量产手感规则：

1. **输入缓冲**：攻击/翻滚早按被记住，窗口一到立刻执行。
2. **土狼时间(Coyote)**：离开可行动状态后极短时间仍允许出招。
3. **后摇取消**：攻击后摇可被翻滚或移动取消。

- 状态机 `enum State { IDLE, MOVE, ATTACK, ROLL, HURT, DEAD }`。
- 用 `_unhandled_input` 而非 `_input`：UI 打开时按键不驱动角色。
- **关键修复**：对话**不再**锁玩家动作（旧实现 `if DialogUI.is_open: return` 会导致对话框因换场景/死亡/回调悬空没关掉时，新玩家一出生就被永久锁死）。对话期间照样能移动/攻击/翻滚，走开即"结束对话"。

### 7.3 AttackController —— 攻击时间轴

`scripts/combat/attack_controller.gd`（组件，挂在玩家/敌人场景里）。驱动"前摇 → 判定 → 后摇"三段，实现输入缓冲、连击衔接（`combo_window` 内接下一段）、后摇取消（`can_cancel()`）。

- 用"时间累加器 + `enum Phase`"而非三个 Timer 节点，最直观且方便整体乘攻速倍率。
- 判定盒位置/旋转委托给 `WeaponController`（配置了武器时）或自带 `AttackBox`。

### 7.4 WeaponController —— 武器解耦

`scripts/combat/weapon_controller.gd`（独立场景根节点，`extends Node2D`）。**换武器 = 换数据，不换脚本/场景**：

- 全项目共用 `res://scenes/weapons/weapon.tscn`，差异由 `WeaponData` 字段描述，`setup(data, wielder)` 运行时套用。
- 结构：`WeaponController → SwingPivot → { Sprite2D, AttackBox(Area2D) }`。根节点每帧转到瞄准角，判定盒随武器转 → "判定跟随武器而非角色"。
- `static func create(data, wielder)`：统一实例化入口，`weapon_scene` 有值用专用场景，否则用通用场景。
- 每把武器实例持有自己的 `CollisionShape2D`（`.duplicate()`），避免共用资源互相污染判定尺寸。

### 7.5 其余战斗组件

| 文件 | 职责 |
|---|---|
| `combat/projectile.gd` | 玩家投射物（弓箭/法球），命中触发 `DamageInfo` |
| `combat/area_spell.gd` | 区域法术（火环/冰爆），持续/瞬时判定 |
| `combat/attack_box.gd` | 攻击判定盒，`hit_confirmed(target, info)` 信号 |
| `combat/ability.gd` | 主动技能逻辑（冲刺/旋风斩/治疗等） |

---

## 8. 世界与可交互物

### 8.1 LevelRuntime —— 关卡运行时

`scripts/world/level_runtime.gd`（`extends Node2D`，挂在每关根节点）。把"静态配置"变"活的玩法"：

- 按 `LevelData` + 敌人池随机生成敌人（以关卡名为种子保证布局一致；避开玩家 `min_spawn_distance`）。
- 监听出口 `Trigger` → 切场景；统计清怪进度，全清后 `room_cleared` 并**弹三选一词条**（Roguelite 入口）。
- `CanvasModulate` 套环境色（地牢更暗、野外偏暖）。
- 零敌人关卡（城镇/Boss 房）直接判为已清空，否则 `require_clear` 的锁门会永久锁死。
- Boss 由场景里带 `boss_id` meta 的标记点生成。

### 8.2 可交互物（`Interactable` 体系）

基类 `scripts/world/interactable.gd`（`extends Area2D`，监听 `interact` 输入 + 玩家进入范围）。派生：

| 脚本 | 文件 | 交互 |
|---|---|---|
| `npc.gd` | `scenes/world/npc.tscn` | 触发 `dialog_sequence_requested` 多句对话 |
| `chest.gd` | `world/chest.tscn` | 开箱给物品 |
| `sign_post.gd` | `world/sign_post.tscn` | 触发 `dialog_requested` 顶部提示 |
| `locked_door.gd` | `world/locked_door.tscn` | 持有钥匙才放行 |
| `save_point.gd` | `world/save_point.tscn` | 记录复活点 |
| `heal_spring.gd` | `world/heal_spring.tscn` | 回血 |

**交互设计原则**：`interact`(F) 只作快捷键，面板/交互以鼠标为主；交互物**不再读** `DialogUI.is_open` 去屏蔽动作（曾因此永久锁死玩家）。

---

## 9. UI 系统

### 9.1 总原则（来自踩坑固化）

1. `process_mode = PROCESS_MODE_ALWAYS`：暂停菜单/背包 `get_tree().paused=true` 时，继承默认 `PAUSED` 的 UI 收不到输入——这就是"教程窗口关不掉"的根因。
2. 全屏常驻 `Control.mouse_filter = 2`(IGNORE)：曾经把 `tutorial_ui` 的 Root 设 STOP 想做"点空白关闭"，结果游戏一启动多了一层透明膜吞掉所有点击（"游戏没法运行"真凶）。
3. 任何挡玩家的面板必须 ≥2 条玩家主动退出途径。
4. UI 是**只读消费者**：监听 EventBus 刷新，从不主动抓玩法节点。
5. 鼠标优先，键盘只是快捷键。

### 9.2 统一关闭契约（PopupManager 驱动）

所有弹窗支持 **J / 回车 / 窗口内左键** 关闭；左键点面板内任意处（非按钮）即关，按钮用 `BaseButton.accept_event()` 吞掉事件 → 与关闭操作天然互斥。

### 9.3 对话框两条通道（`dialog_ui.gd`）

由 `EventBus` 驱动，互不干扰：

| 通道 | 信号 | 行为 | 是否暂停 |
|---|---|---|---|
| **提示条**（Notice） | `dialog_requested(text, duration)` | 顶部非阻塞单句 | 否，不锁输入、不发 `dialog_opened` |
| **对话条**（Bar） | `dialog_sequence_requested(speaker, lines, on_finished)` | 底部逐句推进，播完回调结算 | **是（模态）**：开条即持 `Cover.WORLD` 冻结令牌，关条交还 |

对话条关闭语义：读到最后一句再关 = 结算奖励；中途关 = 取消不结算。`on_finished` 为 `Callable`，回调前先清状态（避免回调里再开对话时数据错乱）。

**窗口开着 = 世界停着**：对话条是模态窗口——显示期间玩家不能跑动、不会挨打，对话也不会被"走远即取消"收掉；关闭入口（J/回车/点条/F/右键）在冻结期间全部可用（本层 `PROCESS_MODE_ALWAYS`），关掉即恢复。冻结走 `PauseManager` 令牌（`Cover.WORLD`：只停世界、不遮屏幕），不是改玩家输入——后者才是当年"对话锁输入导致永久卡死"的病灶。

**对话在"冻结期间"也要能显示**：对话条只在**被独占屏幕的窗口盖住**时才收掉（`PauseManager.covers_screen()`），不再"看见 `paused` 就一律收"。系统级冻结（教程提示 / Boss 出场）期间，NPC 的整段话照常逐字显示、照常能推进与结算；被暂停菜单/背包这类带遮罩的窗口盖住时才让位（否则会被压在遮罩下面"看不见也关不掉"）。

### 9.4 教程/系统弹窗（`tutorial_ui.gd` + `help_panel.gd`）

- **TutorialUI**：顶部面板，只负责显示 `tutorial_step_shown` 与关闭手势，自身不推进教程（回调 `TutorialSystem.dismiss_current_step()`）。**是否冻结游戏 / 独占屏幕由数据决定**：`TutorialStep.pause_game == true`（系统级提示）才冻结并独占弹窗位置；操作类提示（"靠近村民按 [F] 交谈"）是**非阻塞浮层**，世界照常运行、NPC 对话照常弹出。冻结令牌的唯一所有者是 `TutorialSystem`（见 §9.5）。判据只有一处（`TutorialSystem._step_wants_freeze` → `is_current_step_blocking()`），UI 的输入/Esc 路由与系统的冻结永远同源，不会"一边以为还停着、另一边已经放跑"。
- **HelpPanel**：操作说明，常从暂停菜单打开。提供 5 条退出途径（关闭按钮/ Esc / F / 右键 / 点遮罩）。每次 `open()` 都 `PauseManager.freeze(&"help")`、`close()` 都 `unfreeze` —— 暂停是**令牌**不是布尔位，所以它不用（也不该）记"是不是我暂停的"。

### 9.5 系统级弹窗冻结游戏（暂停的唯一所有权）

游戏暂停的**唯一真相**是 `PauseManager`（autoload）的**令牌集合**，`get_tree().paused` 只是它写出去的结果：

- 谁要冻结游戏就 `PauseManager.freeze(owner_id)`，不要就 `unfreeze(owner_id)`，或直接用**声明式**的 `set_frozen(owner_id, want)`（期望状态由调用方从自己的状态推导，天然幂等，不依赖任何布尔记住"我冻过没有"）。**持有者集合非空 ⇔ `paused == true`**。
- 教程/帮助/背包/三选一/结算各自持自己的令牌，叠加时关掉任意一个都**不会**把游戏"放跑"。
- **每个令牌都带"是否独占屏幕"的声明**（`Cover.WORLD` / `Cover.SCREEN`，默认 SCREEN）。"世界停一下"与"屏幕被谁占着"是两件事：暂停菜单/背包/结算自带全屏遮罩，会盖住下层窗口（对话条必须收掉，否则"看不见也关不掉"）；教程提示这类系统级冻结只声明 `WORLD`，下层窗口照常显示。判定集中在 `PauseManager.covers_screen()`，**不让每个窗口去猜"现在 paused 是不是因为我被人盖住了"**。
- **权威是真实 `paused` 位，不是缓存**：`PauseManager._process` 每帧把令牌集合与真实位对齐。任何外部直写 `get_tree().paused` 最多存活一帧就被纠正——旧实现的 `_applied` 缓存一旦与真实位脱节，`freeze()` 会静默失效，导致"暂停菜单开着、角色还能动"。
- **持有者会死，令牌不会自己消失**：`freeze(id, cover, owner)` 可绑定发起冻结的对象，`_process` 每帧回收"对象已释放却没交还令牌"的条目 —— 冻结泄漏的最后一道防线（否则玩家会在"世界冻着、界面没了"的状态下永久锁死）。
- 窗口自身 `PROCESS_MODE_ALWAYS` 仍收输入——**停的是游戏世界，活的是弹窗**。
- `clear_all()` 是**换局语义**：回主菜单时把所有旧令牌作废并恢复运行。

### 9.5.1 Esc 的唯一仲裁者（UIInputRouter）

`_unhandled_input` 是广播语义，多个窗口各自监听必然"抢跑"。Esc 因此集中到 `UIInputRouter`：

- 有阻塞窗口在屏幕上 → Esc 只交给**层级最高的那一个**（教程 > 三选一 > 暂停 > 帮助 > 设置 > 背包 > 结算），由它 `route_esc()` 决定行为；即便它不关（三选一必须选），也**不允许**穿透去开暂停菜单。
- 没有阻塞窗口 → Esc 才是"打开暂停菜单"。

### 9.5.2 子面板必须走 open()/close() 契约

暂停菜单里的帮助/设置是"开时登记副作用、关时收尾"的窗口（帮助占 PopupManager 槽位与暂停令牌，设置要落盘音量）。因此暂停菜单**只能**通过 `open()` / `close()` 操作它们，不能直接改 `visible` —— 直接改会绕过收尾，造成弹窗槽位/暂停令牌泄漏、音量设置丢失。

**子面板必须 `PROCESS_MODE_ALWAYS`。** 它们最常从**暂停菜单**里打开，此时 `get_tree().paused == true`；Godot 只向 `ALWAYS` 节点派发输入，默认 `INHERIT` 的面板 `can_process()` 为 false，**按钮点不动、滑块也拖不动** → "打开设置后无法退出"。`HelpPanel` / `TutorialUI` / `SettingsPanel` 三者的 `_ready` 都显式设了这一行。

### 9.5.3 子面板全局唯一实例

设置/帮助面板有两个入口（主菜单、暂停菜单）。若各入口各自 `instantiate()`，树上会出现**两个**同名面板，Esc 路由、可见性、`force_close` 都会作用到错误的那一个上。因此统一走 `SettingsPanel.acquire(scene)` / `HelpPanel.acquire(scene)`：按注册表 id 复用，缺了才建，保证全场景唯一。

### 9.5.4 UIRegistry —— 场景树容器 + 窗口注册表

`scripts/core/ui_registry.gd`（autoload）。三件事：

1. **持有容器** `World` / `GUI` / `Menus`；`level_parent()` / `gui_container()` / `menus_container()` 供关卡与窗口按归属挂载，未装配时回退 root（测试安全）。
2. **按 id 登记窗口**：各窗口 `_ready` 里 `UIRegistry.register(id, self)`；调用方用 `window_for(id)` / `find_by_name(name)` 访问，**不再按树路径查名**。
3. 与 `UIInputRouter`（Esc 仲裁）、`PopupManager`（互斥）**互补**：Registry 管"有哪些窗口、怎么拿到"，Router 管"Esc 给谁"，Popup 管"谁能同时显示"。

### 9.6 菜单体系

| 场景 | 职责 |
|---|---|
| `main_menu.tscn` | 主菜单：开始/继续/跳过教程 |
| `pause_menu.tscn` | 暂停：继续/设置/帮助/退出 |
| `settings_panel.tscn` | 设置（音量等） |
| `inventory_ui.tscn` | 背包（来自 GameState.inventory） |
| `modifier_choice.tscn` | 三选一词条（响应 `modifier_choice_requested`） |
| `game_over.tscn` | 死亡/胜利结算 |
| `boss_health_bar.tscn` | Boss 血条（监听 `unit_died`/`health_changed`） |
| `hud.tscn` | 主 HUD（血/蓝/技能栏/飘字/提示） |

### 9.7 皮肤与 Theme

- 唯一皮肤来源 `resources/ui_theme.tres`，由 `tools/generate_theme.gd` 生成（设计令牌 + 类型变体 `TitleLabel`/`HeadingLabel`/`HintLabel`/`AccentLabel`/`PrimaryButton`/`DangerButton`/`QuietButton`）。
- 节点上**禁止** `theme_override_*`：曾散落 35 处字号覆盖 + 8 处字体色覆盖，优先级高于主题，导致中文糊成一团。
- 九宫格贴图由 `tools/generate_ui_skin.gd` 程序化生成（12×12、四角 3px、中间纯色纵向无损）。
- **交互四态语义不重叠**：normal 凸起 / hover 凸起+金色 / pressed 最深+凹陷+金色描边+文字下沉 1px / disabled 扁平+低对比。pressed 绝不能比 disabled 还灰（"按下去反直觉"的主因）。
- ✕ 关闭按钮用**程序生成的 `icon_close.png`**（点阵字体无 U+2715 字形，原 `text="✕"` 渲染成豆腐块）。

---

## 10. Roguelite 词条系统

`scripts/roguelite/modifier_system.gd`（autoload）。一局内词条的收集与结算：

- **为什么独立一层**：`CharacterData` 是 `.tres` 资源，运行时改会污染文件；词条是"临时叠加层"，run 结束直接丢弃。
- **结算顺序固定** `FLAT → PERCENT → MULTIPLY`：`final = (base + FLAT) * (1 + PERCENT) * MULTIPLY`。顺序不能改，否则同组合算出不同结果。
- **上下文过滤**：词条有作用域（`巨力`只对双手武器、`烈焰精通`只对火系）。取值时带 `context`（武器类别/元素/触发标签），乘区表按上下文分别缓存（`_cache`）。
- **叠层公式**：`n*value + value_per_stack * n(n-1)/2`（旧写法 `(value+vps*(n-1))*n` 多乘了一遍）。
- `roll_candidates(3)`：按 `weight` 加权、不放回抽样，满层词条不出现。
- 监听 `EventBus.run_started` → `clear()`。

---

## 11. 特效系统

`scripts/fx/fx_sprite.gd` + `assets/fx/*`（按元素/类型分目录：elemental/magic/projectile/slash/smoke）。

- 命中表现由 `Actor` 的 `flash_material`（ShaderMaterial 溶解/闪色）驱动，参数来自 CharacterData。
- 顿帧（`HitStop`）、屏幕震动（`camera_shake_requested`）经 EventBus 解耦触发。
- 刀光/拖尾由 `WeaponController` 在挥砍时挂载，`SwingPivot` 扫动产生"挥砍"而非"戳一下"。

---

## 12. 构建与资源管线（tools/ 生成器）

`tools/` 下的生成器是全项目 `.tscn` / `.tres` 的**唯一作者**。

| 脚本 | 产出 |
|---|---|
| `generate_theme.gd` | `resources/ui_theme.tres` |
| `generate_ui_skin.gd` | `assets/sprites/ui/theme/gen/*`（九宫格 + `icon_close.png`） |
| `generate_levels.gd` | 5 个关卡 `.tscn` + TileSet + LevelData |
| `generate_ui_scenes.gd` | 主菜单/暂停/设置/说明/教程/Boss血条/背包/结算 |
| `generate_world_scenes.gd` | 世界交互物场景 |
| `generate_weapon_scenes.gd` | 武器场景 |
| `generate_tutorial.gd` | 教程步骤 `.tres` |
| `generate_data.gd` | `data/**/*.tres` |

**运行方式**（必须用"运行场景"模式，**不要** `--script`——被加载场景引用 autoload，`--script` 模式不注册 autoload 会编译失败）：

```bash
Godot --headless --path . res://tools/generate_theme.tscn
```

**规则**：改布局/皮肤/关卡 → 改生成器 → 重跑生成器 → 回归测试。绝不手改产物。

---

## 13. 项目约定速查

（完整版见 `.workbuddy/skills/godot-arpg-conventions/SKILL.md`）

1. **禁用 `@onready`**（全项目 0 处）。节点引用一律 `@export var xxx_path: NodePath` + `_ready()` 里 `_resolve_nodes()` 用 `get_node_or_null() as 类型`，全项目 62 处。
2. **五段式文件头**（55/55 覆盖）：【负责什么】【挂哪个节点】【依赖谁】【怎么扩展】（+【为什么…】解释反直觉设计）。
3. **文件内分区顺序**：信号 → enum → 常量 → @export → 私有变量 → 生命周期 → 公开 → 私有 → 信号回调；私有成员 `_` 前缀。
4. **`class_name` 必填**（40 个脚本）；全静态类型；字面量 `StringName` 用 `&""`（145 处）；数值走 `@export_range`（125 处）。
5. **EventBus 单向**：系统间不互相持有引用，只收发信号；`Callable` 回调必须安全调用（校验 `is_valid()` + `is_instance_valid()`）。
6. **UI 硬规则**：`PROCESS_MODE_ALWAYS`；全屏 Control `mouse_filter=2`；≥2 条退出途径；禁止全局静态开关锁玩家。
7. **资源由生成器产出**；数据驱动（一把武器一个 `WeaponData`）。
8. **测试即契约**：每个 bug 补守卫测试。

---

## 14. 测试体系

`tools/*_test.tscn` + `tools/playability_check.tscn` 是可运行回归守卫。断言风格：`_check(ok, msg, detail)`，结束 `get_tree().quit(0 if _fail==0 else 1)`。

| 测试 | 覆盖 |
|---|---|
| `popup_contract_test` | 弹窗统一关闭、互斥、冻结游戏（13 项，新增） |
| `weapon_dialog_test` | 对话两条通道、点击/键盘语义、回调结算（49 项） |
| `playability_check` | 全屏吞点击、点击落世界、玩家移动/攻击、教程/帮助可关（15 项） |
| `combat_arch_test` | 战斗架构契约（15 项） |
| `delivery_test` | 交付验收（93 项） |

**护规则**：flaky 先确认再改代码（连跑 3 次一致才判真回归）；自检断言用 `is_visible_in_tree()`（非 `visible`）、`get_combined_minimum_size()`（非 `size`）；UI 视觉用 PIL 数值化验证（斜面方向/状态阶梯/内容位移/画面艳度），且先打印真实 `RECT` 再取样（按钮真实高 31 视口 px）。

---

## 15. 如何运行 / 扩展 / 排错

### 运行游戏
```
Godot_v4.7.2-stable_win64.exe --path D:/GodotProject/re-game-arpg
```
（编辑器内直接 F5 亦可；截图/真机用无控制台版 exe）

### 扩展清单
| 想加什么 | 动哪里 |
|---|---|
| 新武器 | 新建 `data/weapons/xxx.tres`（填 WeaponData 字段），无需新场景 |
| 新词条 | 新建 `data/modifiers/xxx.tres` + 在 `GameEnums.ModifierTarget`/`_matches_context` 加作用域 |
| 新敌人 | 新建 `data/enemies/xxx.tres`，复用 `enemy.tscn` |
| 新关卡 | `data/levels/xxx.tres` + `generate_levels.gd` + `resources/tilesets/` |
| 新教程步骤 | 新建 `data/tutorial/step_xxx.tres` |
| 新 UI 面板 | 写 `scripts/ui/xxx.gd`（五段式头、`NodePath` 引用、`PROCESS_MODE_ALWAYS`）+ 生成器 |

### 已知坑 / 排错
- **改 `.tscn` 被覆盖**：你手改了 `scenes/ui/*.tscn`，一跑生成器就没了 → 改生成器。
- **`big_sword.tscn` 孤儿**：`scenes/weapons/big_sword.tscn` 是历史遗留（武器 *data* 保留，多余场景删掉）。若编辑器（Steam Godot）开着，会被 `open_scenes` 缓存**复活**——删场景要连 `.godot/editor/editor_layout.cfg` 的 `open_scenes`、`project_metadata.cfg`、`filesystem_cache10`、`.godot/editor/<场景>-*` 一起清。
- **对话框关不掉/锁死**：检查是否又出现了"读 `is_open` 去屏蔽玩家动作"或"全屏 Control `mouse_filter=STOP`"。
- **词条不生效**：确认伤害/移速计算走的是 `Actor.get_stat()` 而非直接读 `data.xxx`。
- **中文糊/错位**：检查是否出现 `theme_override_font_sizes`；改 `generate_theme.gd` 比手改节点更稳。

---

*文档基于 2026-09-12 代码快照整理。任何架构改动请同步更新本文与 `docs/LOG.md`。*
