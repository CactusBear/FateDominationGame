shader_type canvas_item;

// 跃迁后处理：读取已绘制的屏幕画面，以 center 为原点做
// 「镜头推进 + 向心吸入 + 涡旋 + 径向拖影 + 色散 + 冲击波 + 星线 + 闪白」。
// 挂在铺满屏幕的 ColorRect 上，放在要被吸入的节点之后。所有参数默认值等于原画面不变，
// 节奏由外部 AnimationPlayer 改写这些参数实现，本文件不含时间轴；星线由 line_travel 推进、
// 不读 TIME，所以动画停顿时星线和冲击波会一起定格。

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
// 吸入中心（屏幕 UV）。按背景主体实测填写。
uniform vec2 center = vec2(0.5, 0.5);
// 镜头推进倍数：1 不变，越大越近。
uniform float zoom = 1.0;
// 向心吸入：中心附近的内容被向圆心收拢的强度。
uniform float pull = 0.0;
// 涡旋角度（弧度），越靠近中心转得越多。
uniform float twist = 0.0;
// 径向拖影长度（0..1，按到中心的距离比例），同时拉长星线。
uniform float streak = 0.0;
// 色散偏移（按半径比例）。
uniform float chroma = 0.0;
// 屏幕抖动幅度（UV）。
uniform float shake = 0.0;

// 冲击波：环半径以屏高为单位；strength 为 0 时整段跳过。
uniform float wave_radius = 0.0;
uniform float wave_width = 0.07;
uniform float wave_strength = 0.0;

// 星线：从中心向外喷射的径向光线。lines 为亮度（0 关闭）；
// line_travel 为累计推进距离，只在冲刺时增加，停顿时不变，星线因此定格在半空。
uniform float lines = 0.0;
uniform float line_travel = 0.0;
uniform vec3 line_color_a : source_color = vec3(0.86, 0.92, 1.0);
uniform vec3 line_color_b : source_color = vec3(1.0, 0.86, 0.6);

// 闪白强度 0..1。
uniform float flash = 0.0;
uniform vec3 flash_color : source_color = vec3(0.92, 0.95, 1.0);

const int STREAK_SAMPLES = 12;

float hash11(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

// dir：已校正宽高比的单位方向；rs：采样半径（以屏高为单位）
vec3 sample_at(vec2 dir, float rs, float aspect) {
	vec2 uv = center + dir * rs / vec2(aspect, 1.0);
	// 镜像采样：越界时折回画面内，避免 clamp 把边缘像素拉成条纹
	uv = abs(mod(uv + 1.0, 2.0) - 1.0);
	return texture(screen_tex, uv).rgb;
}

// 一层星线：把圆周分成 count 个扇区，每个扇区按哈希决定有没有线、速度和起始位置。
vec3 star_layer(float a01, float r, float count, float seed, float px) {
	float cell = floor(a01 * count);
	float h1 = hash11(cell + seed);
	if (h1 < 0.45) {
		return vec3(0.0);
	}
	float h2 = hash11(cell + seed + 17.0);
	float h3 = hash11(cell + seed + 41.0);
	float speed = 0.6 + h2;
	float head = fract(h3 + line_travel * speed) * 1.7;
	float len = (0.07 + streak * 0.6) * speed * (0.3 + head);
	float along = clamp((r - (head - len)) / max(len, 0.0001), 0.0, 1.0);
	float on = step(head - len, r) * step(r, head);
	// 角向距离换算成弧长（屏高单位），线宽保持约 1~2.5 像素
	float lane = 0.2 + 0.6 * hash11(cell + seed + 73.0);
	float arc = abs(fract(a01 * count) - lane) * TAU / count * r;
	float width = (1.0 + 1.5 * h2) * px;
	float core = 1.0 - smoothstep(0.0, width, arc);
	float fade_in = smoothstep(0.04, 0.3, head);
	vec3 tint = mix(line_color_a, line_color_b, step(0.78, h1));
	return tint * core * on * along * along * fade_in;
}

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 uv0 = SCREEN_UV + shake * vec2(sin(TIME * 97.0), cos(TIME * 83.0));
	vec2 d = (uv0 - center) * vec2(aspect, 1.0);
	float r = length(d);

	// 涡旋：中心转得多，外圈衰减
	float ang = twist / (1.0 + r * 3.0);
	float cs = cos(ang);
	float sn = sin(ang);
	d = vec2(d.x * cs - d.y * sn, d.x * sn + d.y * cs);
	vec2 dir = r > 0.0001 ? d / r : vec2(0.0);

	// 推进 + 吸入：从更外圈取样，内容向圆心收拢
	float rs = r / zoom * (1.0 + pull * (1.0 - smoothstep(0.0, 0.9, r)));

	// 冲击波：环内对采样半径做折射偏移，并给环加一道亮边
	float ring = 0.0;
	if (wave_strength > 0.0001) {
		float x = (r - wave_radius) / wave_width;
		ring = exp(-x * x) * wave_strength;
		rs *= 1.0 - 0.06 * x * ring;
	}

	// 径向拖影：不需要时只读一次屏幕，省掉 36 次读取
	vec3 col;
	if (streak < 0.003 && chroma < 0.0005) {
		col = sample_at(dir, rs, aspect);
	} else {
		col = vec3(0.0);
		for (int i = 0; i < STREAK_SAMPLES; i++) {
			float k = float(i) / float(STREAK_SAMPLES);
			float rk = rs * (1.0 - streak * k);
			col.r += sample_at(dir, rk * (1.0 + chroma), aspect).r;
			col.g += sample_at(dir, rk, aspect).g;
			col.b += sample_at(dir, rk * (1.0 - chroma), aspect).b;
		}
		col /= float(STREAK_SAMPLES);
	}

	col += flash_color * ring * 0.35;

	if (lines > 0.001) {
		float a01 = atan(d.y, d.x) / TAU + 0.5;
		float px = SCREEN_PIXEL_SIZE.y;
		vec3 s = star_layer(a01, r, 160.0, 3.0, px) + star_layer(fract(a01 + 0.0031), r, 97.0, 11.0, px) * 0.7;
		col += s * lines;
	}

	col = mix(col, flash_color, clamp(flash, 0.0, 1.0));
	COLOR = vec4(col, 1.0);
}
