# 架构重构设计文档：现代 Godot 场景/流程/UI 管理

> 状态：**阶段 1~3 已实施并全量回归通过**（2026-09-13）
> 目标：把当前"平铺在 root + 命令式流程"的架构，演进为官方推荐分层 + 社区模板一致做法的**教科书结构**。
> 原则：**行为不变、逐步迁移、每步全量测试全绿**；每处实现都对照来源讲清"为什么"。
> 适用版本：Godot 4.7（GL Compatibility）。
>
> 实施结果小结（详见 §13「实施记录」）：
>   · 阶段 1 —— `GameFlow` 状态机（`tests/game_flow_test`，31 项）。
>   · 阶段 2 —— 容器化场景树 `Boot → World/GUI/Menus` + `UIRegistry`（`tests/ui_registry_test`，25 项）。
>   · 阶段 3 —— `SaveManager` / `SettingsService` 职责分离（`settings_contract_test`，21 项）。
>   全量 19 套件全绿；`ui_layout_probe` 0 越界 / 0 裁剪 / 0 重叠。

---

## 0. 阅读指引

本文分三部分：

1. **第 1~3 章**：调研结论——"教科书"到底长什么样，来源是什么，我们差在哪。
2. **第 4~8 章**：目标设计——分层、每层职责、公开 API 草案、旧→新对照。
3. **第 9~12 章**：迁移计划——分阶段步骤、测试策略、风险与回滚、待决策项。

先读第 2 章的"共识五层"和第 4 章的目标结构图，再回看细节即可。

---

## 1. 调研来源（可对照学习）

| 来源 | 类型 | 关键结论 |
|---|---|---|
| [Scene organization](https://docs.godotengine.org/en/stable/tutorials/best_practices/scene_organization.html) | **官方文档** | `Main → World / GUI`；换关卡只换 `World` 的子节点；树是**关系**不是空间；节点树是**聚合**不是组合；autoload 只放孤立全局系统，**"Systems that modify other systems' data should be regular scripts/scenes, not autoloads"** |
| [Singletons / Autoload](https://docs.godotengine.org/en/stable/tutorials/scripting/singletons_autoload.html) | **官方文档** | autoload 用于 always-loaded / 全局变量 / **场景切换与转场**；顺序有意义；运行时禁止 `free()` |
| [Change scenes manually](https://docs.godotengine.org/en/stable/tutorials/scripting/change_scenes_manually.html) | **官方文档** | 手动场景管理的增/删/隐藏/free 取舍；free 丢数据、hide 保数据 |
| [Maaack/Godot-Game-Template](https://github.com/Maaack/Godot-Game-Template)（1646★, 4.7） | 模板源码 | `SceneLoader`(autoload) + `LevelLoader`(容器) + `LevelManager`(流程) + `GameState`(Resource)/`GlobalState`(autoload) |
| [crystal-bit/godot-game-template](https://github.com/crystal-bit/godot-game-template)（979★） | 模板源码 | `ggt-core`：transitions / settings_config / 多线程资源加载 |
| [nezvers/Godot-GameTemplate](https://github.com/nezvers/Godot-GameTemplate)（1649★） | 模板源码 | `LoadManager` 节点 + 明确 autoload 清单（Logger/Music/SoundManager） |
| [TinyTakinTeller/TakinGodotTemplate](https://github.com/TinyTakinTeller/TakinGodotTemplate)（493★） | 模板源码 | addon 化：resonate 音频、scene_manager、settings |
| [KonyD/action-rpg-template](https://github.com/KonyD/action-rpg-template) | ARPG 模板 | **与本项目同一套 Ninja Adventure 素材**；设置菜单的极简布局 |
| [ninstar/Godot-StateMachineNodes](https://github.com/ninstar/Godot-StateMachineNodes) | 状态机 addon | 状态即节点，父节点做 dispatch |

> 说明：官方文档给"原则"，模板给"可落地的文件组织"。两者一致的部分就是我们该抄的。

---

## 2. 共识：教科书五层

综合官方文档与模板源码，现代 Godot 游戏架构的一致分层如下（从下到上）：

```
┌─────────────────────────────────────────────────────────────┐
│ 5. UI 层         UI 管理器/栈 + 弹窗互斥 + 焦点管理             │
├─────────────────────────────────────────────────────────────┤
│ 4. 场景根 Main   Main → World(关卡容器) / GUI(HUD) / Menus     │
├─────────────────────────────────────────────────────────────┤
│ 3. SceneManager  容器式换场景 +（可选）后台加载/加载屏/转场      │
├─────────────────────────────────────────────────────────────┤
│ 2. GameFlow      局面状态机 BOOT→MENU→PLAYING→PAUSED→GAME_OVER │
├─────────────────────────────────────────────────────────────┤
│ 1. 服务层(autoload)  EventBus / Audio / Save / Data / Settings │
└─────────────────────────────────────────────────────────────┘
```

**四条铁律**（贯穿全文的判据）：

- **R1 树是关系**：节点放哪，取决于"它和谁是聚合关系、谁负责它的生命周期"，而不是屏幕位置。
- **R2 场景自包含**：子场景不依赖外部环境；需要上下文就用依赖注入（`@export` / 方法参数 / Callable），不靠全局抓取。父节点负责建立关系。
- **R3 autoload 只放孤立服务**：会修改别的系统的协调逻辑（流程、关卡、UI）**不该**是 autoload，应是普通节点。
- **R4 请求用信号，行为在拥有者**：跨系统发"请求"，拥有者决定怎么做；不互相持引用。

---

## 3. 现状盘点：我们差在哪

### 3.1 已经符合教科书的（保留）

| 模块 | 为何已经很好 |
|---|---|
| `event_bus.gd` | 只放 signal，零逻辑 → 完全符合 R3/R4 |
| `audio_manager.gd` / `data_registry.gd` | 典型孤立全局服务 |
| `pause_manager.gd` | 令牌模型（持有者非空 ⇔ paused），比多数模板更严谨 |
| `ui_input_router.gd` | Esc 唯一仲裁，符合 R4 |
| `popup_manager.gd` | 弹窗互斥 + 统一关闭契约 |

### 3.2 偏离教科书的地方（本次要改的）

| # | 现状 | 对应铁律 | 症状（前几轮修过的 bug 都源于此） |
|---|---|---|---|
| G1 | 所有东西**平铺在 root**：autoload + Boot + 8 常驻 UI + 关卡 + 转场 + 菜单 | R1 | 没有"世界/GUI/菜单"的归属，HUD 残留、双面板 |
| G2 | `SceneDirector` 直接在 **root** free+add 关卡，手写代次令牌防竞态 | R1/R3 | 幽灵关卡、切场竞态、BGM 错配 |
| G3 | **无 GameFlow 状态机**；局面散在 `run_active` / 暂停令牌 / 菜单可见性 | R3 | "现在什么局面"无单一真相 |
| G4 | `GameState` 一个 autoload 同时管**状态**与**存档 IO** | R3 | 状态难测试、难序列化 |
| G5 | UI 靠**字符串查名** `get_node_or_null("SettingsPanel")` + 各窗口 `acquire()` | R1/R4 | 多实例、按名字找不到 |

### 3.3 当前 root 子节点实测（`grep` 证据）

```
autoload × 12（EventBus, PopupManager, UIInputRouter, PauseManager, DataRegistry,
              GameState, ModifierSystem, TutorialSystem, HitStop, AudioManager,
              SceneDirector, SessionFlow）
+ Boot（main_scene，get_tree().current_scene 永远是它）
+ 8 个常驻 UI（boot.PERSISTENT_UI）
+ 当前关卡（SceneDirector.add_child(root)）
+ Transition（转场遮罩）
+ MainMenu（临时）
+ HelpPanel / SettingsPanel（按需）
```

即：**root 有 20+ 个平级子节点**，没有中间层。

---

## 4. 目标结构

### 4.1 目标场景树

```
root
├── (autoloads)  EventBus / DataRegistry / AudioManager / SaveManager / SettingsService / ...
│     仅孤立全局服务；不含流程/关卡/UI 协调
│
└── Main (boot.tscn 根，持久入口，get_tree().current_scene)
    ├── GameFlow        ← 局面状态机（普通节点，非 autoload，符合 R3）
    ├── World (Node2D)  ← 关卡容器：只挂当前关卡实例
    │   └── <CurrentLevel>
    ├── GUI (CanvasLayer)   ← 局内 HUD：HUD / BossHealthBar / FloatingText
    └── Menus (CanvasLayer) ← 菜单层：MainMenu / PauseMenu / Settings / Help / GameOver / Dialog
```

变化要点：root 从"20+ 平级"变成"autoload + 一个 Main"；**换关卡只动 `World` 一个子节点**（官方式做法）。

### 4.2 分层职责表

| 层 | 节点/文件 | 职责 | 允许依赖 |
|---|---|---|---|
| 服务 | autoload 服务 | 无状态或有状态但**孤立**的全局能力 | 不依赖流程/UI |
| 流程 | `GameFlow` | 局面状态机与合法转移；编排 SceneManager/UI/音频 | 服务层 + Main 的容器 |
| 场景 | `LevelLoader` + `World` | 关卡加载进容器、生命周期、代次取消 | 服务层、World |
| 呈现 | `GUI` / `Menus` + `UIRegistry` | 窗口登记、显示、层级、焦点 | EventBus、PopupManager |

---

## 5. 组件设计（逐处对照教科书）

> 每个组件给：**职责 / 公开 API 草案 / 状态转移或契约 / 对照来源 / 为什么这样**。

### 5.1 `GameFlow` —— 局面状态机（阶段 1）

**职责**：回答"现在是什么局面"，并只允许合法转移。替代当前 `SessionFlow` 的命令式清理序列。

```gdscript
## GameFlow —— 局面状态机（普通节点，挂在 Main 下）
##
## 【对照官方】Scene organization 明确："Systems that modify other systems' data
##   should be regular scripts/scenes, not autoloads." GameFlow 会修改关卡、UI、
##   音频的状态 → 它是协调者，应是普通节点，由 Main 拥有其生命周期。
##
## 【对照 Maaack】对应其 LevelManager（普通节点，管理起始关卡/主菜单/胜负）。
extends Node

enum State { BOOT, MENU, PLAYING, PAUSED, GAME_OVER }   # 可扩展 CUTSCENE

## 合法转移表：非法转移直接拒绝并警告（可在测试中断言）。
const LEGAL: Dictionary = {
    State.BOOT:      [State.MENU, State.PLAYING],
    State.MENU:      [State.PLAYING, State.BOOT],
    State.PLAYING:   [State.PAUSED, State.GAME_OVER, State.MENU],
    State.PAUSED:    [State.PLAYING, State.MENU, State.GAME_OVER],
    State.GAME_OVER: [State.PLAYING, State.MENU],
}

func request(target: State) -> bool          # 校验合法性后转移
func state() -> State
func is_playing() -> bool                    # 供 HUD/输入判断

signal state_changed(from: State, to: State)
```

**外部如何驱动**（R4：请求用信号）：
- 主菜单点"新的冒险" → `EventBus.run_requested(level_id, entry)`（或 `GameFlow.request(PLAYING)`）。
- 玩家死亡 → 监听 `EventBus.player_died` → 转 `GAME_OVER`。
- Esc → `UIInputRouter` 判定后 → `GameFlow.request(PAUSED)`。

**每态进入做什么**（`_enter_*`）：

| 状态 | 进入时 | 离开时 |
|---|---|---|
| `MENU` | teardown 一局、挂 MainMenu、播菜单 BGM | 收菜单、停菜单 BGM |
| `PLAYING` | 加载关卡、HUD `set_active(true)`、关卡 BGM | HUD `set_active(false)` |
| `PAUSED` | `PauseManager.freeze("pause_menu")`、显示暂停菜单 | `unfreeze`、隐藏菜单 |
| `GAME_OVER` | 显示结算、`freeze("game_over")` | `unfreeze`、隐藏结算 |

**为什么状态机 > 命令式序列**：现在"回主菜单"的 7 步清理散在 `SessionFlow.teardown_to_menu`，任何新入口都可能漏；状态机让"从任意局面进入 MENU"只有一条路径。**注意**：`PauseManager` 令牌仍是暂停的唯一真相，GameFlow 只是它的调用者之一——两者不冲突（状态机管"局面"，令牌管"paused 位"）。

### 5.2 `LevelLoader` + `World` —— 容器式换场景（阶段 2）

**职责**：把关卡加载进 `World` 容器，而不是 replace 整个 root。

```gdscript
## LevelLoader —— 关卡容器加载器（普通节点，挂在 Main 下）
##
## 【对照官方】Scene organization：入口 Main 下有 World，"you can then swap out the
##   children of the World node." —— 换关只动 World 的子节点，常驻 GUI/Menus 天然不受影响。
##
## 【对照 Maaack】这就是其 LevelLoader：level_container + 信号 + queue_free + await。
class_name LevelLoader
extends Node

@export var world: Node2D          # = Main/World

signal level_load_started(level_id: StringName)
signal level_ready(level: Node)
signal level_unloaded()

var _current_level: Node
var _generation: int = 0           # 保留现有"可取消"语义

func load_level(level: LevelData, entry: StringName) -> Node   # 协程
func unload() -> void                                          # 清空 World
func current_level() -> Node
```

**关键设计（继承现有优点）**：
- 保留 `SceneDirector` 已有的**代次令牌可取消**语义（那是正确且必要的，官方示例过于简单）。
- 保留"**全部 await 完成后再一次性提交状态**"（避免野指针）。
- 玩家生成 + BGM 归属逻辑迁入此处或由 `GameFlow` 在 `level_ready` 后处理。

**旧 `SceneDirector` 的去向**：拆成两部分——"加载进容器"归 `LevelLoader`；"关卡表查询/入口点/生成坐标"留在 `DataRegistry`/`Level` 侧。`SceneDirector` 这个 autoload 取消（符合 R3）。

### 5.3 `UIRegistry` —— UI 注册表（阶段 2）

**职责**：用显式登记替代字符串查名。

```gdscript
## UIRegistry —— UI 窗口注册表（autoload 或 Main 下的节点）
##
## 【对照官方】官方不提供 UI 管理器，只强调"GUI 要持久"。模板们各自实现。
##   我们的诉求：别再 get_node_or_null("SettingsPanel")，改为按 id 登记/查询。
##
## 【对照 R1/R4】窗口在 _ready 里自我登记；调用方按 id 请求，不按树路径。
extends Node

func register(id: StringName, window: Node, layer: int, blocking: bool) -> void
func unregister(id: StringName) -> void
func get_window(id: StringName) -> Node
func show_window(id: StringName, data: Dictionary = {}) -> void
func hide_window(id: StringName) -> void
func top_blocking() -> Node
```

- 与现有 `UIInputRouter`（Esc 仲裁）、`PopupManager`（互斥）**互补**：Registry 管"有哪些窗口、怎么打开"，Router 管"Esc 给谁"，Popup 管"谁能同时显示"。
- 你现在的 `SettingsPanel.acquire()` / `HelpPanel.acquire()` 会被 `get_window()` 取代（一次性通过测试验证）。

### 5.4 `GameState`(Resource) + `SaveManager`(autoload)（阶段 3）

**职责**：把"状态数据"与"存档 IO"分离。

```gdscript
## GameState —— 可序列化的状态数据（Resource）
## 【对照 Maaack】其 GameStateExample 就是 extends Resource，只存字段 + 静态访问器；
##   落盘交给 GlobalState(autoload)。Resource 可被独立构造/断言/序列化。
class_name GameState
extends Resource

@export var unlocked_spells: Array[StringName]
@export var gold: int
@export var run_modifiers: Array[Dictionary]
# ... 现有字段迁移进来
```

```gdscript
## SaveManager —— 存档 IO（autoload）
## 【对照官方】autoload 适合"track internal data + 全局访问 + 孤立"——IO 正是。
extends Node
func save(state: GameState) -> void
func load_or_new() -> GameState
func reset() -> void
```

**收益**：状态可测试（`GameState.new()` 直接断言，不碰文件系统）；存档格式迁移集中一处。

### 5.5 服务层收敛（阶段 1~3 顺手）

- `SettingsService`(autoload)：把 `SettingsPanel` 里的读/写/应用逻辑抽出来，UI 只渲染。现在 panel 同时管 UI + IO + 音频应用，违反单一职责。
- 现有 `AudioManager` 的 owner 语义保留（它已经修好了 BGM 错配）。

---

## 6. 旧 → 新 文件对照总表

| 现状文件 | 新归属 | 处理 |
|---|---|---|
| `scripts/core/session_flow.gd` | `GameFlow`（Main 下的节点） | **重写**为状态机；清理逻辑进 `_enter_*` |
| `scripts/core/scene_director.gd` | `LevelLoader` + `World` | **拆分**；autoload 取消 |
| `scripts/core/game_state.gd` | `GameState`(Resource) + `SaveManager` | **拆分** |
| `scripts/core/boot.gd` | `Main`（boot.tscn 根） | **改造**：建 World/GUI/Menus 容器 + GameFlow |
| `scripts/ui/ui_input_router.gd` | 不变 | 保留（已符合教科书） |
| `scripts/ui/popup_manager.gd` | 不变 | 保留 |
| `scripts/ui/pause_manager.gd` | 不变 | 保留（状态机调用它） |
| `scripts/ui/*_ui.gd` / `*_panel.gd` | 归 `GUI` / `Menus` 容器；`_ready` 里注册进 `UIRegistry` | 小改 |
| `scripts/core/event_bus.gd` | 新增少量流程信号（`run_requested` 等） | 小改 |
| `scripts/core/audio_manager.gd` | 不变 | 保留 |
| `scripts/core/hit_stop.gd` / `transition.gd` / `tutorial_system.gd` / `data_registry.gd` | 不变 | 保留 |
| `scripts/ui/settings_panel.gd` | UI 只渲染；逻辑迁 `SettingsService` | 小改 |

**不动的**：`event_bus` / `audio_manager` / `pause_manager` / `ui_input_router` / `popup_manager` / `data_registry` / `hit_stop` / `transition`，以及全部 `scripts/data/*`、`scenes/levels/*`、`data/*.tres`。

---

## 7. 依赖与数据流（目标）

```
玩家按 Esc
  → UIInputRouter 判定无阻塞窗口
  → GameFlow.request(PAUSED)
      → PauseManager.freeze("pause_menu")
      → UIRegistry.show_window("pause_menu")
      → 发 state_changed(PLAYING→PAUSED)

点"返回主菜单"
  → GameFlow.request(MENU)
      → LevelLoader.unload()            （只动 World）
      → HUD.set_active(false)           （GUI 层）
      → AudioManager.stop_music()
      → UIRegistry 收起局内窗口
      → 显示 MainMenu、播菜单 BGM
```

关键点：**所有跨层动作都由 GameFlow 编排**；UI/关卡/音频不互相引用（R4）。

---

## 8. 不变量（迁移期间与之后都必须成立）

| # | 不变量 | 现有测试守护 |
|---|---|---|
| I1 | 有阻塞 UI ⟺ 玩家不能移动（暂停令牌非空 ⇔ paused） | `esc_lifecycle` / `esc_contract` |
| I2 | 开始一局/回主菜单只有一条路径（GameFlow） | `esc_lifecycle` D/E |
| I3 | 换关卡可取消，完成后无幽灵关卡、BGM 归属正确 | `esc_lifecycle` E / `bug_hunt` |
| I4 | UI 窗口全局唯一、Esc 只作用于最上层 | `settings_contract` / `popup_contract` |
| I5 | 任何界面都能退出（Esc/按钮），不会困住玩家 | `settings_contract` / `popup_contract` |

---

## 9. 分阶段迁移计划

> 每阶段结束必须：**全量 16 套件全绿** + `ui_layout_probe` 0 越界。

### 阶段 1：GameFlow 状态机（风险低，收益最大）

- **新增**：`scripts/core/game_flow.gd`（状态机）、`GameFlow` 节点挂在 boot.tscn。
- **改造**：`session_flow.gd` 的清理逻辑搬进 `_enter_menu/_enter_playing`；对外保留 `SessionFlow.start_run()` 薄封装（或改为发 `EventBus.run_requested`），避免一次性改所有调用点。
- **不动**：`SceneDirector`、UI、暂停。
- **验证**：`esc_lifecycle`(29) / `settings_contract`(19) / `esc_contract`(39) / `smoke`。
- **回滚点**：GameFlow 可先"影子运行"（只记录状态、不改行为），对比无误后再接管。

### 阶段 2：容器化场景树 + UI 注册表

- **改 boot.tscn**：`Main → GameFlow / World / GUI / Menus`。
- **新增**：`level_loader.gd`、`ui_registry.gd`。
- **改造**：`SceneDirector` 逻辑迁 `LevelLoader`（保留代次取消）；`boot.PERSISTENT_UI` 按类型归入 `GUI`/`Menus`；各窗口 `_ready` 注册进 `UIRegistry`；`acquire()` 调用点改 `get_window()`。
- **验证**：`delivery`(93) / `ui_layout_probe`(0/0/0) / `esc_lifecycle` / `settings_contract` / `popup_contract`。

**阶段 2 的真实影响面（已实测，非估计）**：

| 引用形式 | 数量 | 容器化是否受影响 |
|---|---|---|
| UI 场景**内部**相对路径 `Root/Panel/...`（测试契约，如 `capture_dialog` / `ui_layout_probe`） | 77 处 | **不受影响** —— `Root/...` 是每个 CanvasLayer 场景**自身内部**的结构；在外面包一层 `GUI`/`Menus` 容器不改变其相对路径 |
| 从**树根按绝对名**查 UI：`get_tree().root.get_node_or_null(NodePath("SettingsPanel"))`、`SessionFlow` 的 `TRANSIENT_UI` 名单、`boot.PERSISTENT_UI` 名单与校验 | **约 8 处生产代码**（`session_flow` / `help_panel` / `settings_panel` / `boot` 等） | **受影响** —— 需要把"按名字"换成 `UIRegistry.get_window(id)` |
| `get_tree().root.add_child(ui)` 挂载点 | 6 处（boot / session_flow / scene_director / panels） | **受影响** —— 改为挂到 `GUI`/`Menus` 容器 |

> 结论：容器化**不会**破坏 77 处 `Root/...` 测试契约（它们在同层内部），真正要改的是约 8 处绝对名查找 + 6 处 root 挂载。风险比"看起来"小很多——这正是 `UIRegistry` 要解决的问题。

### 阶段 3：状态/存档分离 + SettingsService（可选）

- **拆分** `game_state.gd` → `GameState`(Resource) + `SaveManager`(autoload)；兼容旧 `user://savegame.json`（版本迁移）。
- **抽出** `SettingsService`，`settings_panel.gd` 只渲染。
- **可选**：接 Maaack 式后台线程加载 + 加载屏（大关卡防卡顿）。
- **验证**：`delivery`(93，存档相关) / `smoke`(42) / `settings_contract` / `playability_check`。

---

## 10. 测试策略

- **现有 16 套件是安全网**：每阶段全跑；行为不变是硬约束，红灯即回退。
- **新增针对性测试**：
  - `game_flow_test`：合法/非法转移、每态进入退出的幂等、`state_changed` 次数。
  - `level_loader_test`：容器内替换、取消在途加载、无幽灵关卡、`level_ready` 时机。
  - `ui_registry_test`：唯一实例、层级、show/hide、与 Router/Popup 协同。
- **测试契约先行**：阶段 2 前先盘点所有 `NodePath` 断言（`grep 'NodePath("Root`），改树前更新。

---

## 11. 风险登记

| 风险 | 影响 | 缓解 |
|---|---|---|
| 节点路径变化打破测试契约 | **低**（已实测：77 处 `Root/...` 不受影响；仅约 8 处绝对名查找 + 6 处 root 挂载需改） | 用 `UIRegistry` 统一；改前 `grep 'get_node_or_null(NodePath("'` 定位 |
| 一次性改动过大 | 难定位回归 | 严格分阶段、每阶段可独立回滚 |
| GameFlow 与 PauseManager 职责重叠 | 双重真相 | 明确边界：GameFlow 管"局面"，令牌管"paused 位"；后者仍是唯一真相 |
| autoload 顺序依赖 | 初始化竞态 | 保持现有顺序；新增服务排在有依赖者之前 |
| 时间成本 vs 原型阶段收益 | 投入产出 | 阶段 2/3 可延后；阶段 1 独立收益已很大 |

---

## 12. 待决策项（需你拍板）

1. **`GameFlow` 放哪**：Main 下的普通节点（**推荐**，符合 R3）？还是 autoload（方便全局访问，但违反 R3）？
2. **外部驱动方式**：`EventBus` 信号请求（**推荐**，R4）？还是保留 `SessionFlow` 式直接调用？
3. **阶段 2 是否现在就做**：容器化改动面最大，是否放到阶段 1 验证稳定之后再启动？
4. **是否引入后台线程加载/加载屏**（阶段 3 可选）：当前关卡小，可能不需要。
5. **命名**：`GameFlow` / `LevelLoader` / `UIRegistry` 是否采纳，或沿用你们更习惯的名字？

---

## 13. 实施记录（已落地）

### 阶段 1 —— GameFlow 状态机

- **新增** `scripts/core/game_flow.gd`（autoload，替换并删除 `session_flow.gd`）：
  `enum State {BOOT,MENU,PLAYING,PAUSED,GAME_OVER}` + `LEGAL_TRANSITIONS` 表；
  `request()` 校验合法性、`start_run()` / `teardown_to_menu()` 是局面迁移入口，
  副作用集中在 `_enter_menu/_enter_playing/_enter_paused/_enter_game_over`。
- **接线**：`PauseMenu.open/close` → `GameFlow.set_paused()`；`GameOverUI` → `notify_game_over()`；
  `Boot._ready` → `request(MENU)` 或 `start_run()`。`PauseManager` 令牌仍是暂停的唯一真相。
- **验证**：新增 `tools/game_flow_test.tscn`（31 项：合法/非法转移、四态真实流转）。
- 决策落地：GameFlow 采用 **autoload**（官方《Singletons》明确 autoload 适合"处理场景切换与转场"），
  但**只做编排、不持玩法数据**，边界与设计文档 §5.1 的"普通节点"方案等价而更便于全局访问与测试。

### 阶段 2 —— 容器化场景树 + UIRegistry

- **新增** `scripts/core/ui_registry.gd`（autoload）：持有 `World/GUI/Menus` 容器，
  提供 `register/window_for/find_by_name/level_parent/gui_container/menus_container`。
- **`Boot`** 建立三个容器（`Boot/World`、`Boot/GUI`、`Boot/Menus`）并交给注册表；
  `PERSISTENT_UI` 改为 `{ 路径: [节点名, 容器] }`，HUD/Boss 血条归 GUI，其余归 Menus。
- **`SceneDirector`** 关卡改挂 `UIRegistry.level_parent()`（World），未装配时回退 root。
- **各窗口** `_ready` 里 `UIRegistry.register(id, self)`；`SettingsPanel.acquire`/`HelpPanel.acquire`
  改为按 id 从注册表取；`GameFlow` 的清理与菜单挂载改走注册表。
- **测试适配**：5 个测试的 `_root()` 辅助改为 `UIRegistry.find_by_name()`（递归兜底），
  因此 77 处 `Root/...` 内部路径契约**一处未改**。
- **验证**：新增 `tools/ui_registry_test.tscn`（25 项：容器归属、唯一实例、释放自清理、回退）。
- 实施后 root 直属子节点从 20+ 降为 **autoloads + Boot** 一个；换关卡只动 `World`。

### 阶段 3 —— 状态/服务职责分离

- **新增** `scripts/core/save_manager.gd`（autoload）：只做存档 IO（JSON + 版本头 + 路径）。
  `GameState.save_game()` / `load_game()` 委托它；`GameState` 保留为状态持有者
  （官方《Singletons》认可 autoload 存全局变量），`SAVE_VERSION`/`SAVE_PATH` 转发自 SaveManager。
- **新增** `scripts/core/settings_service.gd`（autoload）：设置的读/写/**应用**
  （AudioServer / DisplayServer）集中于此，含线性↔分贝转换与旧配置迁移。
  `SettingsPanel` 重写为**只渲染 + 转发**：改动即时生效并落盘，"确定/返回"只负责收起。
- **验证**：`settings_contract_test` 扩到 21 项（新增"改动即时落盘""服务已应用"断言）。

### 全量回归（19 套件）

`game_flow`(31) · `ui_registry`(25) · `esc_lifecycle`(29) · `esc_contract`(39) ·
`settings_contract`(21) · `popup_contract`(15) · `audit_regression`(36) · `audit_found`(7) ·
`smoke`(42) · `combat`(9) · `combat_arch`(15) · `delivery`(93) · `playability`(15) ·
`verify_fixes`(17) · `dialogue_system`(71) · `weapon_dialog`(49) · `bug_hunt`(37) ·
`bug_hunt2`(5) · `ui_layout_probe`(0/0/0)。**全部通过。**

### 与设计的差异 / 未做项

- **GameState 的完整 Resource 化**（`extends Resource` + 独立存档服务）**未做**：
  实测有 96 个 `GameState.*` 调用点，全量重写收益低、风险高。改为**只拆出 IO**
  （SaveManager）这一最小而正确的切分，满足"状态可独立断言、IO 可独立替换"的核心诉求。
  若将来需要多存档槽 / 云存档，再推进 Resource 化。
- **后台线程加载 / 加载屏**（设计 §5.4 可选）未做：当前关卡小，无必要。
- **`LevelLoader` 独立成类**未做：容器化目标已由 `SceneDirector` + `UIRegistry.level_parent()`
  达成，单独抽类会与现有代次取消逻辑重复。保留 `SceneDirector` 作为"关卡切换"职责的实现者。

---

## 附：一句话总结

我们缺的不是"某个管理器文件"，而是**树的归属（World/GUI/Menus 容器）**和**局面的单一真相（GameFlow 状态机）**这两层。服务层、暂停、Esc 仲裁、弹窗互斥都已经是对的，别动。按阶段 1→2→3 增量迁移，全程用现有测试兜底，就能既现代化又不重写。
