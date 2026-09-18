# ActRPG —— 2D 俯视动作 ARPG

Godot **4.7.2** 制作的实时动作 ARPG。视角为 2D 俯视 3/4（top-down），
关卡结构遵循「城镇据点 → 野外 → 地牢 → Boss 房 → 回城」。

> 关卡设计原则见 [docs/LEVEL_DESIGN.md](docs/LEVEL_DESIGN.md)，
> 素材来源与许可证见 [docs/ASSETS.md](docs/ASSETS.md)，
> 开发过程与踩坑记录见 [docs/LOG.md](docs/LOG.md)，
> 系统架构见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)、
> 架构演进提案（现代场景/流程/UI 管理）见 [docs/ARCHITECTURE_REFACTOR.md](docs/ARCHITECTURE_REFACTOR.md)，
> 测试报告见 [docs/QA_REPORT.md](docs/QA_REPORT.md)、修复对照见 [docs/QA_FIXES.md](docs/QA_FIXES.md)。

## 快速开始

用 Godot 4.7.2 打开本目录，F5 运行。启动后是主菜单，点「新的冒险」开始。

```bash
GODOT="D:/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
"$GODOT" --path . --resolution 1280x720
```

## 现在能玩到什么

**完整流程**：主菜单 → 新手教程（分步引导）→ 边境小镇 → 风鸣平原 →
古代地牢一层 → 地牢二层 → 独眼巨人巢穴 → 击败 Boss → 通关结算。

| 关卡 | 内容 | 教学重点 |
|---|---|---|
| 边境小镇 | NPC 对话、提示牌、存档点 | 移动、交互 |
| 风鸣平原 | 10 只近战怪、2 个宝箱、治愈泉 | 普攻、翻滚、蓄力 |
| 古代地牢 · 一层 | 13 只怪（含远程法师）、宝箱、存档点、锁门 | 法术、远程应对、词条构筑 |
| 古代地牢 · 二层 | 15 只怪（含冲锋精英）、钥匙锁门 | 精英应对、钥匙机制 |
| 独眼巨人巢穴 | Boss（420 血）+ 柱子掩体 + 存档点 | 观察前摇、走位 |

**战斗手感**：三段连击、蓄力重击、翻滚无敌帧、输入缓冲、土狼时间、
后摇取消、命中顿帧、屏幕震动、受击闪白、死亡溶解、伤害飘字、暴击金数字。

**系统**：武器（近战/远程/双手，6 把样例）、法术（火/冰/雷 × 弹道/范围/附魔）、
技能（主动 + 被动）、Roguelite 词条（21 个词条 × 4 稀有度 × 三选一）、
背包与装备栏、存档点与复活。

### 操作

| 操作 | 键位 |
|---|---|
| 移动（8 向） | WASD / 方向键 / 左摇杆 |
| 普攻（三段连击） | 鼠标左键 / J / 手柄 X |
| 蓄力重击 | 按住鼠标右键 / K / 手柄 Y |
| 翻滚（带无敌帧） | 空格 / Shift / 手柄 A |
| 法术 1/2/3 | Q / E / R |
| 主动技能 1/2 | 1 / 2 |
| 交互（宝箱/存档点/提示牌/NPC） | F |
| 背包 | Tab / I |
| 暂停菜单 | Esc |

游戏内随时可按 Esc →「操作说明」查看完整按键与机制说明。

## 目录结构

```
re-game-arpg/
├── project.godot            # 输入映射 / autoload / 物理层 / 像素渲染
├── assets/                  # 全部 CC0 素材（见 docs/ASSETS.md）
├── data/                    # 全部数值：89 个 .tres，禁止硬编码
│   ├── attacks/ weapons/ spells/ abilities/
│   ├── characters/ enemies/ modifiers/ items/ levels/ tutorial/
├── scripts/
│   ├── core/                # EventBus / DataRegistry / GameState / GameFlow /
│   │                        # SceneDirector / Transition / HitStop / SaveManager /
│   │                        # AudioManager / SettingsService / UIRegistry /
│   │                        # TutorialSystem / Boot
│   ├── data/                # 12 个 Resource 定义 + GameEnums
│   ├── combat/              # Actor / DamageInfo / AttackBox / AttackController /
│   │                        # WeaponController / Projectile / AreaSpell / Ability
│   ├── player/              # Player / PlayerCombat / PlayerCamera / ActorSprite
│   ├── enemies/             # EnemyBase（三合一状态机）
│   ├── world/               # LevelRuntime / Interactable / Chest / SavePoint /
│   │                        # SignPost / NPC / HealSpring / LockedDoor
│   ├── roguelite/           # ModifierSystem
│   ├── ui/                  # HUD / MainMenu / PauseMenu / PauseManager /
│   │                        # SettingsPanel / HelpPanel / DialogUI / TutorialUI /
│   │                        # InventoryUI / BossHealthBar / GameOverUI /
│   │                        # ModifierChoiceUI / FloatingText / PopupManager /
│   │                        # UIInputRouter
│   └── fx/                  # FxSprite
├── scenes/
│   ├── core/ player/ enemies/ fx/
│   ├── weapons/             # 1 个通用武器场景（换武器 = 换 .tres）
│   ├── world/               # 6 个交互物场景
│   ├── levels/              # 5 个关卡（程序化生成）
│   └── ui/                  # 12 个界面
├── shaders/                 # hit_flash.gdshader（闪白+溶解+描边）/ transition.gdshader（转场光圈遮罩）
├── resources/               # ui_theme.tres / tilesets
├── tools/                   # 生成器与测试（不参与运行）
└── docs/                    # 8 篇文档（LEVEL_DESIGN / ASSETS / LOG / ARCHITECTURE /
                             # ARCHITECTURE_REFACTOR / QA_REPORT / QA_FIXES 等）
                             # + qa_* 截图目录
```

规模：64 个运行时 GDScript（约 13600 行）+ 36 个工具/测试脚本（约 12500 行）、
31 个游戏场景、89 个数据资源。

## 架构约定

1. **数值全走 Resource**：任何伤害/速度/冷却都来自 `.tres`，代码里不写死数字。
2. **DataRegistry 是唯一的数据入口**：其他系统只问它要数据，不自己 `load()` 路径。
3. **跨系统通信只走 EventBus 信号**：系统之间不互相持有引用。
4. **场景里能配的一律 `@export`**：节点引用用 `NodePath` 在 `.tscn` 里挂好，
   不硬编码 `get_node("路径")`。
5. **属性读取必须走 `Actor.get_stat()`**：它是词条乘区的唯一入口。
6. **碰撞方向定死**：攻击盒主动（`monitoring`），受击盒被动（`monitorable`），
   避免一次命中被双方各结算一次。
7. **转场动画用"动画 + 契约计时器"双轨**：补间可被取代，但 `fade_out/fade_in`
   保证按时返回，绝不挂起调用方（见 `scripts/core/transition.gd`）。
8. **武器是独立场景，攻击效果与角色解耦**：判定盒挂在武器的 SwingPivot 下，
   武器转 → 判定跟着转。换武器 = 换场景，不用改角色脚本
   （见 `scripts/combat/weapon_controller.gd`）。
9. **抗击退 / 霸体走数据**：`CharacterData.knockback_resist` 设 1.0 = Boss 完全
   不被击退，`super_armor` = 受击不硬直。**不需要为 Boss 写任何特判**。

## 开发工具

```bash
GODOT="D:/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"

# --- 内容生成（改过对应脚本后必须重跑）---
"$GODOT" --headless --path . res://tools/generate_data.tscn          # 70 个数据资源
"$GODOT" --headless --path . res://tools/generate_levels.tscn        # TileSet + 5 个关卡
"$GODOT" --headless --path . res://tools/generate_world_scenes.tscn  # 6 个交互物场景
"$GODOT" --headless --path . res://tools/generate_ui_scenes.tscn     # 12 个 UI 场景
"$GODOT" --headless --path . res://tools/generate_theme.tscn         # UI 主题
"$GODOT" --headless --path . res://tools/generate_ui_skin.tscn       # UI 皮肤/九宫格
"$GODOT" --headless --path . res://tools/generate_tutorial.tscn      # 14 个教程步骤
"$GODOT" --headless --path . res://tools/generate_weapon_scenes.tscn # 通用武器场景 weapon.tscn

# --- 测试（共 21 个回归套件，全部通过）---
"$GODOT" --headless --path . res://tools/smoke_test.tscn         # 42 项：数据/场景/玩家/摄像机
"$GODOT" --headless --path . res://tools/combat_test.tscn        # 9 项：攻击盒→受击盒链路
"$GODOT" --headless --path . res://tools/combat_arch_test.tscn   # 15 项：武器解耦/抗击退/霸体
"$GODOT" --headless --path . res://tools/material_isolation_test.tscn # 10 项：受击材质每实例隔离
"$GODOT" --headless --path . res://tools/delivery_test.tscn      # 93 项：关卡/交互物/UI/教程
"$GODOT" --headless --path . res://tools/game_flow_test.tscn     # 31 项：局面状态机/合法转移
"$GODOT" --headless --path . res://tools/ui_registry_test.tscn   # 25 项：容器归属/窗口注册表
"$GODOT" --headless --path . res://tools/esc_contract_test.tscn  # 39 项：Esc 仲裁/暂停所有权/音频
"$GODOT" --headless --path . res://tools/esc_lifecycle_test.tscn # 29 项：暂停冻结/回菜单/转场取消（端到端）
"$GODOT" --headless --path . res://tools/popup_contract_test.tscn # 15 项：弹窗互斥/统一关闭契约
"$GODOT" --headless --path . res://tools/freeze_contract_test.tscn # 50 项：教程冻结令牌/泄漏回收/提示让位
"$GODOT" --headless --path . res://tools/settings_contract_test.tscn # 21 项：设置面板退出/滑块可见性/即时落盘
"$GODOT" --headless --path . res://tools/dialogue_system_test.tscn # 71 项：结构化对话/自适应排版
"$GODOT" --headless --path . res://tools/weapon_dialog_test.tscn # 51 项：武器统一化 + 对话框
"$GODOT" --headless --path . res://tools/bug_hunt_test.tscn      # 37 项：运行时缺陷狩猎
"$GODOT" --headless --path . res://tools/bug_hunt2_test.tscn     # 5 项：定点验证
"$GODOT" --headless --path . res://tools/verify_fixes.tscn       # 17 项：19 个 QA Bug 回归
"$GODOT" --headless --path . res://tools/audit_found_test.tscn   # 7 项：审计定点复现
"$GODOT" --headless --path . res://tools/audit_regression_test.tscn # 36 项：审计修复项回归
"$GODOT" --headless --path . res://tools/playability_check.tscn  # 15 项：可玩性核验
"$GODOT" --headless --path . res://tools/ui_layout_probe.tscn    # 布局探针：越界/裁剪/重叠

# --- 截图（需窗口模式）---
"$GODOT" --path . --resolution 1280x720 res://tools/capture_all.tscn
"$GODOT" --path . --resolution 1280x720 res://tools/capture_esc.tscn        # Esc 路径 → docs/qa_esc/
"$GODOT" --path . --resolution 1280x720 res://tools/capture_dialog.tscn     # 对话排版 → docs/qa_screenshots_dialog/
"$GODOT" --path . --resolution 1280x720 res://tools/capture_flow.tscn       # 主流程界面 → docs/qa_final/
"$GODOT" --path . --resolution 1280x720 res://tools/capture_settings.tscn   # 设置面板 → docs/qa_settings/
"$GODOT" --path . --resolution 1280x720 res://tools/capture_skin.tscn       # UI 皮肤 → docs/qa_skin/
"$GODOT" --path . --resolution 1280x720 res://tools/capture_weapon_rot.tscn # 武器旋转判定 → docs/qa_screenshots_weaponrot/
```

> 改过 `scripts/data/*.gd` 后必须重跑 `generate_data.tscn`；
> 改过 `generate_levels.gd` 后必须重跑 `generate_levels.tscn`；
> 改过 `generate_ui_scenes.gd` 后必须重跑 `generate_ui_scenes.tscn`。

## 素材

全部为 **CC0**（公共领域），来源与许可证逐项登记在 [docs/ASSETS.md](docs/ASSETS.md)。
主素材包为 Pixel-boy / AAA 的 *Ninja Adventure Asset Pack*，16×16 像素风格。
**未使用任何 AI 生成图片。**
