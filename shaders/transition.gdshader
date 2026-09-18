// ============================================================================
// transition.gdshader —— 场景切换遮罩
// ============================================================================
//
// 【画的是什么】
//   一张全屏矩形，用"软边光圈（iris）+ 暖金描边 + 像素抖动"表现转场：
//     progress = 0 → 完全透明（画面正常）
//     progress = 1 → 完全不透明（画面被彻底盖住，可以安全换场景）
//   光圈半径在两者之间线性收放，收拢时从四周向中心闭合，展开时由中心绽放。
//
// 【为什么不用纯黑 ColorRect 淡入淡出】
//   1) 纯 alpha 淡变在 320×180 的点阵画面上是"整屏均匀变暗"，没有方向感和层次；
//   2) 与项目"冷深紫底 + 单一暖金强调色"的设计语言对不上（见 tools/generate_theme.gd）；
//   3) 收尾阶段整屏加深 + 光圈封口，玩家看到的是"一扇门合上/打开"，
//      而不是"灯被调暗"，转场被感知为演出而非卡顿。
//
// 【技术要点】
//   1) 坐标系归一到"短边 = 1"：任何宽高比下光圈都是正圆，
//      横屏 / 竖屏 / 带黑边的整数缩放窗口都不会变成椭圆。
//   2) 全部计算都是 ALU（无贴图采样、无循环），单次全屏 quad，
//      GL Compatibility 下零负担；静止时脚本会把节点 visible=false，直接零开销。
//   3) render_mode unshaded：遮罩不该被场景里的 Light2D 照亮（地牢火把会把黑幕染红）。
//   4) 抖动噪点按像素锁定（floor(UV * rect_size)）并与像素风一致，不会出现
//      "半像素糊边"；且只在光圈边缘附近生效（见 grain），远处暗场保持干净，
//      封口阶段自动归零，保证 progress=1 时没有漏光孔洞。
//
// 【参数从哪来】
//   scripts/core/transition.gd 在每次动画前 set_shader_parameter() 写入，
//   可在编辑器里通过该节点的 @export 调整。
shader_type canvas_item;
render_mode blend_mix, unshaded;

// ---------------------------------------------------------------------------
// 参数
// ---------------------------------------------------------------------------

/** 转场进度：0 = 全透明（世界可见），1 = 全不透明（世界被完全盖住）。 */
uniform float progress : hint_range(0.0, 1.0) = 0.0;
/** 遮罩矩形尺寸（像素）。用于把坐标归一到"短边 = 1"，保证光圈是正圆。 */
uniform vec2 rect_size = vec2(320.0, 180.0);
/** 幕布主体色。默认取主题的 C_VOID（#0B0A10），比纯黑更贴合项目冷深紫基调。 */
uniform vec4 fill_color : source_color = vec4(0.043, 0.039, 0.063, 1.0);
/** 光圈边缘的暖金强调色（主题 C_ACCENT_HI）。 */
uniform vec4 rim_color : source_color = vec4(1.0, 0.851, 0.502, 1.0);
/** 边缘柔和度（归一化单位，1.0 = 短边长度）。越小边越硬。 */
uniform float edge_softness : hint_range(0.001, 0.4) = 0.085;
/** 描边宽度（归一化单位）。 */
uniform float rim_width : hint_range(0.01, 0.3) = 0.032;
/** 描边强度。 */
uniform float rim_strength : hint_range(0.0, 2.0) = 0.55;
/** 描边外侧的扩散光晕强度。 */
uniform float halo_strength : hint_range(0.0, 1.0) = 0.22;
/**
 * 边缘像素抖动幅度（归一化单位）。0 = 完美圆形，越大越"手绘"。
 * 【为什么只在边缘生效】抖动若作用于整屏，暗场的平滑渐变会被逐像素扰动出
 *   ±1~2 级的"脏噪点"（320×180 下放大后尤其明显）。这里用边界权重把它锁在
 *   光圈边缘附近：边缘更有手绘感，远处暗场保持干净。
 */
uniform float grain : hint_range(0.0, 0.1) = 0.008;
/** 幕布暗角强度：0 = 平色，1 = 边缘完全压黑。 */
uniform float vignette : hint_range(0.0, 1.0) = 0.35;
/** 光圈中心的漂移量（归一化单位）。收拢时视线前移，展开时回正。 */
uniform float drift : hint_range(0.0, 0.3) = 0.06;

// ---------------------------------------------------------------------------
// 工具
// ---------------------------------------------------------------------------

/// 便宜的 2D 哈希，用作"像素噪点"。无贴图依赖，GL Compatibility 友好。
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// ---------------------------------------------------------------------------
// 片元
// ---------------------------------------------------------------------------

void fragment() {
	float p = clamp(progress, 0.0, 1.0);

	// --- 归一化坐标：短边 = 1 的方形空间，光圈在任何宽高比下都是正圆 ---
	float short_side = max(min(rect_size.x, rect_size.y), 1.0);
	vec2 local = (UV - 0.5) * rect_size / short_side;
	// 收拢时光圈中心轻微上移：最后收束处略高于画面中心，视线有"向前/向上"的方向感；
	// 展开时随 p 回落，光从画面中心绽放。
	local.y += drift * p;
	float d = length(local);

	// --- 封口系数：最后 22% 把整屏压到不透明 ---
	// 【为什么必须有】光圈半径趋近 0 时，正中心仍会因软边而残留半透明像素；
	// 用它兜底，progress = 1 时 alpha 必然 = 1，换场景瞬间绝不会漏出半帧画面。
	float seal = smoothstep(0.78, 1.0, p);

	// --- 光圈半径：从"比对角还大"收到 0 ---
	// 起点大于半对角线，保证 p = 0 时整屏都在孔内（alpha 全 0，一帧不掉）。
	float max_radius = 0.5 * length(rect_size) / short_side + edge_softness + 0.02;
	float radius = mix(max_radius, 0.0, p);

	// --- 边缘像素抖动：按像素锁定，只在光圈边缘附近生效 ---
	// 封口阶段（seal → 1）与远离边缘的暗场都不扰动，保证 1) 不留孔洞 2) 远处干净。
	float noise = (hash21(floor(UV * rect_size) + floor(TIME * 6.0)) - 0.5) * 2.0;
	float edge_weight = exp(-pow((d - radius) / max(edge_softness * 2.0, 0.001), 2.0));
	d += noise * grain * (1.0 - seal) * edge_weight;

	// 外 = 1（盖住），孔内 = 0（透出画面）。
	float iris = smoothstep(radius - edge_softness, radius + edge_softness, d);
	float cover = max(iris, seal);

	// --- 描边与光晕：只在转场中途可见（两端各归零，避免静止时留一圈金边）---
	float band = exp(-pow((d - radius) / max(rim_width, 0.001), 2.0));
	float halo = exp(-pow((d - radius - rim_width * 1.6) / (rim_width * 1.7), 2.0));
	float visible_glow = 4.0 * p * (1.0 - p) * (1.0 - seal);
	float glow = band * rim_strength * visible_glow + halo * halo_strength * visible_glow;
	// 描边本身也参与不透明度：光圈边界处的 iris 只有 0.5，不抬 alpha 的话
	// 一圈亮边会被半透明稀释得灰蒙蒙，失去"发光边"的质感。
	cover = max(cover, band * rim_strength * visible_glow);

	// --- 配色：幕布主体 + 边缘暗角 + 暖金描边 ---
	vec3 col = fill_color.rgb * (1.0 - vignette * smoothstep(0.35, 1.0, d));
	col = mix(col, rim_color.rgb, clamp(glow, 0.0, 1.0));
	col += rim_color.rgb * clamp(glow - 1.0, 0.0, 0.5);

	COLOR = vec4(col, clamp(cover, 0.0, 1.0));
}
