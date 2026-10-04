shader_type canvas_item;

// 挂在承载文字的 CanvasGroup 上：读取组缓冲（只有文字），按碎块场把文字碎裂成块并吸向 origin。
// 参数默认值等于原画面；节奏由 AnimationPlayer 改写 shatter。
#include "res://assets/shaders/shard_field.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec2 origin = vec2(0.5);
uniform float shatter = 0.0;
uniform float sectors = 72.0;
uniform float r_min = 0.03;
uniform float spread = 0.35;
uniform float jitter = 0.25;
uniform float outer_first = 0.0;
uniform float loosen = 0.18;
uniform float trail = 0.08;
uniform vec3 crack_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float crack = 0.0;

vec4 group_at(vec2 uv) {
	vec4 c = textureLod(screen_tex, uv, 0.0);
	// CanvasGroup 缓冲是预乘 alpha，取样后还原
	if (c.a > 0.0001) c.rgb /= c.a;
	return c;
}

void fragment() {
	if (shatter <= 0.0) {
		COLOR = group_at(SCREEN_UV);
	} else {
		float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
		vec2 scale = vec2(aspect, 1.0);
		vec2 p = (SCREEN_UV - origin) * scale;
		float r_max = length(max(origin, 1.0 - origin) * scale) * 1.02;
		vec4 out_col = vec4(0.0);
		int idx = -1;
		// 上层碎块在此处没有笔画时继续向下查找，最多叠 4 层
		for (int k = 0; k < 4; k++) {
			vec2 src;
			float a;
			float e;
			if (!shard_lookup(p, shatter, sectors, r_min, r_max, spread, jitter, outer_first, loosen, trail, SCREEN_PIXEL_SIZE.y, true, idx, src, a, e)) break;
			vec4 c = group_at(origin + src / scale);
			if (c.a * a > 0.002) {
				c.rgb = mix(c.rgb, crack_color, clamp(e * crack, 0.0, 1.0));
				out_col = vec4(c.rgb, c.a * a);
				break;
			}
		}
		COLOR = out_col;
	}
}
