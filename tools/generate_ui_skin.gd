## GenerateUISkin —— 生成像素风 UI 九宫格贴图（编辑器工具脚本）
##
## 【负责什么】
##   用代码画出按钮/面板的九宫格源图，输出到 res://assets/sprites/ui/theme/gen/。
##   这些图是"带正确立体语义"的：
##     · normal / hover  = **凸起**（上/左亮、下/右暗）
##     · pressed         = **凹陷**（上/左暗、下/右亮）——翻转斜面
##     · disabled        = **扁平**（无斜面），低对比，一眼就不是可按的
##
## 【为什么程序化生成而不是继续用素材包里的图】
##   素材包的 button_*.png 是 16×8 的小图，而且状态语义是错的：
##     · button_pressed 整体压暗（avgLum 75.6）**比 button_disabled（83.7）还暗**，
##       按下去看起来像"失效/变灰"，而不是"被按进去"；
##     · pressed 顶行整行透明，按钮按下时还会"缩水"；
##     · nine_path_focus 是 8×8 的**实心块带黑洞**，当焦点框用会把整个按钮盖住。
##   自己画能保证：状态语义正确、尺寸可控、配色跟随主题 token。
##
## 【怎么运行】
##   Godot --headless --path . res://tools/generate_ui_skin.tscn
##   跑完必须再跑一次 `Godot --headless --import`，否则新 PNG 没有 .import 元数据。
##
## 【设计依据】
##   状态阶梯参考 passivestar/godot-minimal-theme（hover/pressed 由基色派生）
##   与 godotengine/godot 的 default_theme.cpp（pressed 最深、disabled 用低对比区分），
##   再叠加像素 UI 的"凸起/凹陷"斜面约定。
extends Node

# ============================================================================
# 常量
# ============================================================================

const OUT_DIR := "res://assets/sprites/ui/theme/gen/"

## 九宫格源图边长。取 12：四角各 3px（斜面 1px + 外描边 1px + 填充 1px），
## 中间 6px 是**纯色**，纵向拉伸到任意按钮高度都是无损的（Nearest 过滤下依然硬边）。
const SLICE := 12
## 四角固定区边长。必须 >= 3，否则斜面会被拉伸糊掉。
const MARGIN := 3

## 关闭按钮 × 图标的边长（正方形）。取 9：两条对角各 7px，四角留 1px 透明边距，
## 整数倍放大（视口 320×180 → 4x）后每条对角线是 4 物理像素，清晰不糊。
const ICON_SIZE := 9

## 斜面模式。
enum Bevel {
	RAISED,   ## 凸起：上/左亮、下/右暗
	SUNKEN,   ## 凹陷：上/左暗、下/右亮
	FLAT,     ## 扁平：无斜面（disabled 用）
}

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var count: int = 0

	# --- 中性按钮（次要操作 / 列表项）---
	count += _emit("btn_normal",
		Color8(0x27, 0x21, 0x36),   ## fill
		Color8(0x4A, 0x42, 0x65),   ## 亮边
		Color8(0x16, 0x12, 0x1F),   ## 暗边
		Color8(0x3A, 0x33, 0x50),   ## 外描边
		Bevel.RAISED)
	count += _emit("btn_hover",
		Color8(0x33, 0x2C, 0x46),
		Color8(0x56, 0x4E, 0x74),
		Color8(0x1C, 0x17, 0x28),
		Color8(0xE8, 0xA3, 0x3D),   ## hover 起描边转金：明确的"可点"信号
		Bevel.RAISED)
	count += _emit("btn_pressed",
		Color8(0x1A, 0x15, 0x24),   ## fill：比 normal 深 = 真的被按进去
		Color8(0x4A, 0x42, 0x65),   ## 亮边（SUNKEN 时落到下/右）
		Color8(0x16, 0x12, 0x1F),   ## 暗边（SUNKEN 时落到上/左）
		Color8(0xE8, 0xA3, 0x3D),   ## 金色描边保证"按下"不会读成"禁用"
		Bevel.SUNKEN)
	count += _emit("btn_disabled",
		Color8(0x1F, 0x1B, 0x2A),
		Color8(0x1F, 0x1B, 0x2A),   ## 无斜面
		Color8(0x1F, 0x1B, 0x2A),
		Color8(0x2A, 0x25, 0x37),   ## 低对比灰边
		Bevel.FLAT)

	# --- 主按钮（强调色填充，用于"开始冒险"这类主行动）---
	count += _emit("btn_primary_normal",
		Color8(0xD9, 0x8E, 0x2B), Color8(0xF0, 0xB4, 0x5A),
		Color8(0xA9, 0x66, 0x1F), Color8(0x8A, 0x5A, 0x22), Bevel.RAISED)
	count += _emit("btn_primary_hover",
		Color8(0xEB, 0xA2, 0x3A), Color8(0xFF, 0xCE, 0x72),
		Color8(0xC0, 0x7A, 0x24), Color8(0xFF, 0xD9, 0x80), Bevel.RAISED)
	count += _emit("btn_primary_pressed",
		Color8(0xB8, 0x72, 0x1F), Color8(0xF0, 0xB4, 0x5A),
		Color8(0xA9, 0x66, 0x1F), Color8(0xFF, 0xD9, 0x80), Bevel.SUNKEN)
	count += _emit("btn_primary_disabled",
		Color8(0x5A, 0x4E, 0x38), Color8(0x5A, 0x4E, 0x38),
		Color8(0x5A, 0x4E, 0x38), Color8(0x4A, 0x40, 0x30), Bevel.FLAT)

	# --- 面板：深色底 + 冷灰描边 + 顶部一道极淡高光 ---
	count += _emit("panel_bg",
		Color8(0x14, 0x12, 0x1C), Color8(0x20, 0x1C, 0x2C),
		Color8(0x0B, 0x0A, 0x10), Color8(0x3A, 0x33, 0x50), Bevel.RAISED)

	# --- 凹槽（背包格子 / 进度条底 / 输入框）：反向斜面 ---
	count += _emit("well_bg",
		Color8(0x0E, 0x0C, 0x14), Color8(0x2A, 0x24, 0x38),
		Color8(0x07, 0x06, 0x0B), Color8(0x32, 0x2C, 0x44), Bevel.SUNKEN)

	# --- 关闭按钮的 × 图标（见下方 _emit_icon_close 的说明）---
	count += _emit_icon_close()

	print("[GenerateUISkin] 已生成 %d 张九宫格贴图 → %s（%d×%d，四角 %dpx）"
		% [count, OUT_DIR, SLICE, SLICE, MARGIN])
	print("[GenerateUISkin] 下一步：Godot --headless --import")
	get_tree().quit()


# ============================================================================
# 私有方法
# ============================================================================

## 画一张九宫格源图并落盘。返回 1（便于累计计数）。
##
## 像素布局（以 SLICE=12 为例）：
##   0        : 外描边
##   1        : 斜面亮边（凹陷时为暗边）
##   2        : 填充  ← 与中间同色，保证拉伸区边界无跳变
##   3..8     : 填充（可拉伸区）
##   9        : 填充
##   10       : 斜面暗边（凹陷时为亮边）
##   11       : 外描边
## 【参数语义（别再传反了）】
##   light = **亮边色**（凸起时贴在上/左，凹陷时贴在下/右）
##   dark  = **暗边色**（凸起时贴在下/右，凹陷时贴在上/左）
##   两者是按"明暗"传的，不是按"上下"传的 —— 翻转由 bevel 参数负责，
##   调用方只需要给出正确的亮/暗两个颜色。
##   曾经在 pressed 里把两个值按"上暗下亮"传进去，结果凹陷又变回凸起，
##   按下和没按看起来一模一样。
func _emit(name: String, fill: Color, light: Color, dark: Color,
		outline: Color, bevel: Bevel) -> int:
	var img: Image = Image.create(SLICE, SLICE, false, Image.FORMAT_RGBA8)
	var last: int = SLICE - 1
	for y: int in SLICE:
		for x: int in SLICE:
			var c: Color = fill
			if x == 0 or y == 0 or x == last or y == last:
				c = outline
			elif y == last - 1 or x == last - 1:
				# 下/右边：凸起时为暗，凹陷时为亮。
				c = dark if bevel == Bevel.RAISED else (light if bevel == Bevel.SUNKEN else fill)
			elif y == 1 or x == 1:
				# 上/左边：凸起时为亮，凹陷时为暗。
				c = light if bevel == Bevel.RAISED else (dark if bevel == Bevel.SUNKEN else fill)
			img.set_pixel(x, y, c)
	var path: String = OUT_DIR + name + ".png"
	var err: int = img.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("[GenerateUISkin] 保存失败：%s（err=%d）" % [path, err])
		return 0
	return 1


## 画关闭按钮的 × 图标并落盘。返回 1（便于累计计数）。
##
## 【为什么不用文字 "✕"】
##   项目用的 Fusion Pixel 是点阵中文字体，字库里没有 U+2715 这个字形，
##   渲染出来是"豆腐块"（或悄悄回退到系统字体，和整体像素风不一致），
##   而且不同平台/不同缩放下的回退结果还不一样。
##   直接画一张图 = 完全不依赖字体，任何平台、任何分辨率都长一个样。
##
## 【画法】
##   主对角 (i,i) 与副对角 (i,last-i)，i 取 1..last-1，四角各留 1px 透明边距，
##   保证图标在按钮里是"居中、不顶边"的。
##   颜色直接烘焙进图片（浅暖白），所以不依赖主题的 icon 着色，
##   在深色面板上对比度恒定。
func _emit_icon_close() -> int:
	var img: Image = Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var last: int = ICON_SIZE - 1
	var ink: Color = Color8(0xE8, 0xE3, 0xD9)
	for i: int in range(1, last):
		img.set_pixel(i, i, ink)          ## 主对角 ↘
		img.set_pixel(i, last - i, ink)   ## 副对角 ↗
	return _save_img(img, "icon_close")


## 把一张 Image 存成 PNG。返回 1/0（便于累计计数）。
func _save_img(img: Image, name: String) -> int:
	var path: String = OUT_DIR + name + ".png"
	var err: int = img.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("[GenerateUISkin] 保存失败：%s（err=%d）" % [path, err])
		return 0
	return 1
