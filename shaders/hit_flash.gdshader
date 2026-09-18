// HitFlash —— 受击闪白 / 死亡溶解着色器
//
// 【负责什么】
//   在角色精灵上叠加白色闪光（受击反馈）与溶解消失（死亡反馈）。
//   两个效果共用一个 shader，靠参数分别控制，避免为每种效果各写一个。
//
// 【挂在哪里】
//   作为 ShaderMaterial 挂在 Sprite2D 上（见 player.tscn / enemy.tscn 的 Sprite 节点）。
//   所有参数都由 @export 的 uniform 暴露，可在 Inspector 里调。
//
// 【为什么不用 modulate 闪白】
//   modulate 会把整张图（含透明边缘）一起染色，而 shader 可以只对"不透明像素"
//   加白，边缘不会出现白边，像素风更干净。

shader_type canvas_item;

// 闪白强度：0 = 无闪白，1 = 纯白。
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
// 闪白颜色。默认纯白，可改成红/蓝表现元素伤害。
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// 溶解进度：0 = 完整，1 = 完全消失。
uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;
// 溶解边缘颜色（燃烧感）。
uniform vec4 dissolve_edge_color : source_color = vec4(1.0, 0.55, 0.15, 1.0);
// 溶解边缘宽度。
uniform float dissolve_edge_width : hint_range(0.0, 0.5) = 0.08;
// 是否启用描边（受击/精英标记）。
uniform float outline_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// 用贴图自身当溶解噪声，避免额外引入噪声图（像素风用贴图足够）。
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	// 完全透明的像素直接丢弃，不参与任何效果（保持像素边缘干净）。
	if (tex.a < 0.01) {
		COLOR = tex;
	} else {
		vec3 rgb = tex.rgb;

		// --- 描边：检测邻域是否有透明像素，有则说明自己在边缘 ---
		if (outline_amount > 0.0) {
			vec2 px = TEXTURE_PIXEL_SIZE;
			float a = texture(TEXTURE, UV + vec2(px.x, 0.0)).a
				+ texture(TEXTURE, UV - vec2(px.x, 0.0)).a
				+ texture(TEXTURE, UV + vec2(0.0, px.y)).a
				+ texture(TEXTURE, UV - vec2(0.0, px.y)).a;
			// 邻域 4 个方向都透明 => 当前像素在轮廓上。
			if (a < 0.5) {
				rgb = mix(rgb, outline_color.rgb, outline_amount);
			}
		}

		// --- 闪白 ---
		rgb = mix(rgb, flash_color.rgb, flash_amount);

		// --- 溶解：按噪声阈值逐像素消失，边缘发亮 ---
		float alpha = tex.a;
		if (dissolve_amount > 0.0) {
			float noise = hash(floor(UV / TEXTURE_PIXEL_SIZE));
			// 噪声低于进度阈值 => 该像素已被溶解。
			if (noise < dissolve_amount) {
				// 靠近阈值的像素染成边缘色，形成燃烧边。
				float edge = smoothstep(dissolve_amount - dissolve_edge_width, dissolve_amount, noise);
				rgb = mix(dissolve_edge_color.rgb, rgb, 1.0 - edge);
				// 边缘保持可见，内部完全消失。
				alpha = tex.a * step(noise, dissolve_amount - dissolve_edge_width * 0.5);
			}
		}
		COLOR = vec4(rgb, alpha);
	}
}
