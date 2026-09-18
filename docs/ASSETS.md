# 素材登记表（ASSETS.md）

本文件登记项目中**每一个**第三方素材的来源与许可证。规则：

1. 只使用开源免费素材，**禁止 AI 生成图片**，禁止纯色块占位。
2. 全项目只用一套像素风格：**16×16 像素网格**，来源为 Ninja Adventure Asset Pack
   （角色/怪物/Boss/武器/特效/音效）+ Kenney Tiny Dungeon/Tiny Town（备用瓦片）。
3. 新增素材必须在本表补一行；否则视为未登记素材，不得入库。

---

## 一、主素材包：Ninja Adventure Asset Pack

| 项目 | 内容 |
|---|---|
| 名称 | Ninja Adventure Asset Pack |
| 作者 | Pixel-boy、AAA |
| 来源 | https://pixel-boy.itch.io/ninja-adventure-asset-pack |
| 备用镜像 | https://github.com/MarioLDD/Kuroshiro-adventure （`Assets/NinjaAdventure/`，含 `LICENSE.txt`） |
| 许可证 | **CC0 1.0 Universal（公共领域）** |
| 许可证证据 | 包内 `LICENSE.txt` 全文为 CC0 1.0；包内 `README.md` 写明 "They are released under the Creative Commons Zero (CC0) license." |
| 署名要求 | 不强制，但作者希望署名（已在 README 致谢） |
| 用途 | 角色、怪物、Boss、武器、特效、瓦片、音效、音乐 |

### 规格约定

- **角色/怪物表**：单张 PNG，`4 列 × 7 行`，每帧 `16×16`（整图 64×112）。
  - 列 = 朝向：`0=下 1=上 2=左 3=右`
  - 行 = 动作：`0=待机 1..4=行走 4=攻击 5=翻滚/跳跃 6=死亡`
  - 例外：部分怪物表为 `4×4`（64×64），代码按贴图高度自动判断（见 `enemy_base.gd`）。
- **特效表**：横向帧带，代码按 `hframes` 切帧（见 `fx_sprite.gd`）。
- **瓦片**：`16×16` 网格。

### 已登记文件清单

#### 角色 `assets/sprites/characters/`（64×112，4×7）

| 文件 | 原路径 | 用途 |
|---|---|---|
| BlueNinja.png | `Actor/Characters/BlueNinja/SpriteSheet.png` | 玩家 |
| NinjaRed.png | `Actor/Characters/NinjaRed/SpriteSheet.png` | 备用玩家皮肤 |
| NinjaGray.png | `Actor/Characters/NinjaGray/SpriteSheet.png` | 备用 |
| NinjaGreen.png | `Actor/Characters/NinjaGreen/SpriteSheet.png` | 备用 |
| Skeleton.png | `Actor/Characters/Skeleton/SpriteSheet.png` | 骷髅兵 |
| SorcererBlack.png | `Actor/Characters/SorcererBlack/SpriteSheet.png` | 黑法师 |
| NinjaMageBlack.png | `Actor/Characters/NinjaMageBlack/SpriteSheet.png` | 备用法师 |
| Knight.png | `Actor/Characters/Knight/SpriteSheet.png` | Boss（独眼巨人） |
| RedSamurai.png | `Actor/Characters/RedSamurai/redsamurai.png` | 冲锋精英 |
| SkeletonDemon.png | `Actor/Characters/SkeletonDemon/SpriteSheet.png` | 备用精英 |
| Vampire.png | `Actor/Characters/Vampire/SpriteSheet.png` | 备用 |
| Tengu.png | `Actor/Characters/Tengu/SpriteSheet.png` | 备用 |
| Villager.png | `Actor/Characters/Villager/SpriteSheet.png` | 城镇 NPC |
| OldMan.png | `Actor/Characters/OldMan/SpriteSheet.png` | 城镇 NPC |
| Princess.png | `Actor/Characters/Princess/SpriteSheet.png` | 城镇 NPC |
| GoldKnight.png | `Actor/Characters/GoldKnight/SpriteSheet.png` | 备用 |
| Shadow.png | `Actor/Characters/Shadow.png` | 角色影子 |

#### 怪物 `assets/sprites/monsters/`（64×64，4×4）

Slime、Snake、Mushroom、Spirit、Racoon、Cyclope、SpiderRed、Dragon、Eye、Larva、
Mole、Owl、Skull、KappaGreen、LanternRed、MouseBlack、AxolotBlue、Lizard2、
Mollusc2、FishRed（共 20 个）

#### Boss `assets/sprites/bosses/`

| 目录 | 原路径 | 说明 |
|---|---|---|
| DemonCyclop/ | `Actor/Boss/DemonCyclop/` | Idle/Walk/Hit/Sprite |
| GiantRedSamurai/ | `Actor/Boss/GiantRedSamurai/` | 含左右攻击与蓄力 |
| TenguRed/ | `Actor/Boss/TenguRed/` | 含攻击/变形 |
| GiantFrog/ | `Actor/Boss/GiantFrog/` | 含跳跃/蓄力 |

#### 武器 `assets/sprites/weapons/<名>/`

每把武器含 `Sprite.png`（背包图标）与 `SpriteInHand.png`（手持贴图）。

Sword、Sword2、Katana、Axe、BigSword、Hammer、Lance、Lance2、MagicWand、
Bow、Bow2、Book、Bone、Club、Whip、Rapier、Sai（共 17 把）

> 注：`Bow/SpriteInHand.png` 由 `Bow/Sprite.png` 复制而来（原包未提供弓的手持图）。

#### 物品与 UI `assets/sprites/items/`、`assets/sprites/ui/`

| 文件 | 原路径 | 用途 |
|---|---|---|
| PotionLife.png | `Items/Potion/LifePot.png` | 生命药水 |
| PotionMana.png | `Items/Potion/MilkPot.png` | 法力药水 |
| PotionEmpty.png | `Items/Potion/EmptyPot.png` | 空瓶 |
| ChestSmall.png | `Items/Treasure/LittleTreasureChest.png` | 小宝箱 |
| ChestBig.png | `Items/Treasure/BigTreasureChest.png` | 大宝箱 |
| Coin.png | `Items/Treasure/GoldCoin.png` | 金币 |
| Key.png | `Items/Treasure/GoldKey.png` | 钥匙 |
| ScrollFire/Ice/Thunder.png | `Items/Scroll/Scroll*.png` | 法术卷轴图标 |
| Heart.png / HeartHalf.png | `Ui/LifeReceptacle/heart*.png` | 生命图标 |
| BarFill.png / BarUnder.png | `Ui/LifeBarMini*.png` | 条状 UI |

#### 特效 `assets/fx/`

| 文件 | 原路径 | 用途 |
|---|---|---|
| slash/Slash.png 等 6 个 | `FX/SlashFx/*/SpriteSheet.png` | 近战刀光 |
| elemental/Fire.png | `FX/Elemental/Flam/SpriteSheet.png` | 火 |
| elemental/Ice.png | `FX/Elemental/Ice/SpriteSheet.png` | 冰 |
| elemental/Thunder.png | `FX/Elemental/Thunder/SpriteSheet.png` | 雷 |
| elemental/Rock.png | `FX/Elemental/Rock/SpriteSheet.png` | 岩 |
| elemental/Plant.png | `FX/Elemental/Plant/SpriteSheet.png` | 草 |
| magic/Circle*.png 等 6 个 | `FX/Magic/*/SpriteSheet*.png` | 魔法阵/光环/护盾 |
| projectile/*.png（6 个） | `FX/Projectile/*.png` | 弹道 |
| smoke/Smoke*.png | `FX/Smoke/*/SpriteSheet.png` | 烟雾 |

#### 瓦片 `assets/tilesets/`

TilesetInteriorFloor、TilesetNature、TilesetRelief、TilesetDungeon、TilesetFloor、
TilesetFloorB、TilesetFloorDetail、TilesetHole、TilesetHouse、TilesetLogic、
TilesetWater、TilesetField、TilesetDesert、TilesetElement、TilesetReliefDetail、
TilesetVillageAbandoned、TilesetWallSimple、TilesetInterior、Elements、Pipes（共 20 个）

**当前关卡实际使用的瓦片**（见 `tools/generate_levels.gd` 顶部常量）：

| 用途 | 贴图 | 图集坐标 | 选择理由 |
|---|---|---|---|
| 城镇地板 | TilesetInteriorFloor.png | (1,1) | 浅色砖纹，可无缝平铺；与地牢共用避免色相割裂 |
| 地牢地板 | TilesetInteriorFloor.png | (1,1) | 浅色砖纹，可无缝平铺 |
| 地牢墙 | TilesetInteriorFloor.png | (16,7) | 灰绿石墙，可无缝平铺 |
| 野外草地 | TilesetFloor.png | (4,12) | **修正**：原本误用 TilesetNature (4,19) 当草地，但那是树干/树底；改为 TilesetFloor 的纯草，色块均匀、可平铺 |
| 城镇/野外墙 | TilesetRelief.png | (5,6) | 红砖墙，可无缝平铺 |

> 选瓦片时逐块做了"平铺测试"（重复 4×4 渲染后目视检查接缝与暗点），
> 淘汰了 (12,1) 这类是单色块、(17,3) 这类带黑点、平铺后会出现整齐黑点阵的瓦片。
> TilesetNature 在所有候选坐标里都没找到能"无缝平铺 + 看起来像草地"的瓦片，
> 所以野外改走 TilesetFloor。

#### 音频 `assets/audio/`

- **音效 sfx/**（20 个，来自 `Sounds/Game/`）：Hit、Hit1-3、Explosion、Explosion2、
  Fire、Fireball、Magic1-3、Jump、Coin、Gold1、PowerUp1、Success1、Alert、Kill、
  MiniImpact、Spirit
- **音乐 music/**（6 个，来自 `Musics/`）：1 - Adventure Begin（城镇）、23 - Road（野外）、
  21 - Dungeon（地牢）、17 - Fight（Boss）、2 - The Cave、26 - Lost Village

#### 字体 `assets/fonts/`

- `FusionPixel12px.ttf`（Fusion Pixel Font，12px 比例模式，**SIL OFL 1.1**）
  - 来源：https://github.com/TakWolf/fusion-pixel-font
  - 选择原因：像素风、12px 整数、同时含拉丁/简中/繁中/日/韩字形，
    完全离线，无网络字体回退需求；
    原项目里的 `NormalFont.ttf`（"NinjaAdventure"）只有拉丁字母，
    中文字符落到游戏里全是 tofu——这是 UI 看一片方块的根因。
  - 导入参数：`antialiasing=0`、`subpixel_positioning=0`、`hinting=0`、
    `oversampling=4.0`（按 4 倍分辨率栅格化再缩小，保证锐利）——保持像素硬边。
  - **字号只由主题统一管理**：`tools/generate_theme.gd` 里的
    `FS_TITLE=20` / `FS_HEADING=14` / `FS_BODY=12` / `FS_HINT=10`。
    正文固定 12 = 点阵设计尺寸（1:1 渲染最锐利；设成 6~8 会非整数缩放，汉字糊）。
    **禁止**在 `.tscn` 里写 `theme_override_font_sizes`（曾因此出现 35 处散落字号
    把主题踩掉），需要差异时用类型变体 `TitleLabel`/`HeadingLabel`/`HintLabel`。
  - 视口为 320×180（4 倍整数拉伸到 1280×720），12px 占屏高 6.7%，一行可放 20+ 汉字。
  - 按钮等控件高度需 ≥24（12px 行高 16 + 内容边距上下各 4），否则文字溢出。
  - 替代方案评估过但**不采用**：
    - zpix.ttf（SolidZORO）：商用许可证（业务用 ¥7000）——不符合本项目"只开源"的约定
    - 系统级 CJK 字体：跨平台不一致，破坏像素风
- 历史：原 `NormalFont.ttf` 已删除（无引用）。

#### UI 主题素材 `assets/sprites/ui/theme/gen/`（10 个，**程序化生成**）

由 `tools/generate_ui_skin.gd` 生成（改配色/立体语义改那里，再跑
`--headless --import`）。统一 12×12、四角 3px 的九宫格，**中间区是纯色，
所以纵向拉伸到任意按钮高度都是无损的**。

| 文件 | 用途 | 立体语义 |
|---|---|---|
| btn_normal / btn_hover.png | 中性按钮常态 / 悬停 | 凸起 |
| btn_pressed.png | 中性按钮按下 | **凹陷**（斜面翻转） |
| btn_disabled.png | 中性按钮禁用 | 扁平（无斜面） |
| btn_primary_*.png | 主按钮四态 | 同上，金色填充 |
| panel_bg.png | 面板底 | 轻微凸起 |
| well_bg.png | 凹槽（进度条底 / 输入框） | 凹陷 |

> **为什么不再用素材包自带的 button_*.png**：那套 16×8 图的状态语义是错的
> ——`button_pressed` 平均亮度 75.6 比 `button_disabled`（83.7）还暗，
> 按下去像"失效"；且 pressed 顶行整行透明会让按钮缩水。详见 `docs/LOG.md`。

#### UI 主题素材 `assets/sprites/ui/theme/`（20 个，素材包原图）

来自 `Ui/Theme/Theme1/`。**按钮四态已改由上面的 `gen/` 提供**，
以下仅滑块/复选框等图标类仍在使用：

#### 对话框素材 `assets/sprites/ui/dialog/`（8 个）

来自 `Ui/Dialog/`：DialogBox、DialogBoxFaceset、DialogInfo、DialogueBoxSimple、
ChoiceBox、FacesetBox、YesButton、NoButton。当前未使用，保留供对话 UI 扩展。

#### 表情素材 `assets/sprites/emote/`（30 个）

来自 `Ui/Emote/`，当前未使用，保留供 NPC 表情/教程指引扩展。

#### 教程图标

- `assets/sprites/ui/Tuto.png`（来自 `Ui/Tuto.png`）

---

## 二、备用素材包：Kenney Tiny Dungeon / Tiny Town

已下载评估，**当前未使用**（Ninja Adventure 的瓦片已够用），保留以备扩展。

| 项目 | 内容 |
|---|---|
| 名称 | Tiny Dungeon 1.0 / Tiny Town 1.1 |
| 作者 | Kenney |
| 来源 | https://kenney.nl/assets/tiny-dungeon 、https://kenney.nl/assets/tiny-town |
| 许可证 | **CC0 1.0**（包内 `License.txt` 明文："License: (Creative Commons Zero, CC0)"） |
| 署名 | 不强制 |

---

## 三、自制素材

| 类型 | 说明 |
|---|---|
| 着色器 | `shaders/*.gdshader` 全部手写，无第三方来源 |
| 数据资源 | `data/**/*.tres` 全部由 `tools/generate_data.gd` 生成，无外部来源 |
| 关卡 | `scenes/levels/*.tscn` 由 `tools/generate_levels.gd` 程序化生成 |
| 武器场景 | `scenes/weapons/*.tscn` 由 `tools/generate_weapon_scenes.gd` 生成，贴图复用上面的武器素材 |
| 交互物场景 | `scenes/world/*.tscn` 由 `tools/generate_world_scenes.gd` 生成 |
| UI 场景/主题 | `scenes/ui/*.tscn`、`resources/ui_theme.tres` 由 `tools/generate_ui_scenes.gd` / `generate_theme.gd` 生成 |

**本项目未使用任何 AI 生成图片。**
