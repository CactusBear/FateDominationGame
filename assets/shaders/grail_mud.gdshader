shader_type canvas_item;

// 黑圣杯黑泥后处理：读取已绘制的屏幕画面，叠加「高光染红 + 心跳脉动 + 孔内积泥 + 漫过圆环下部 + 沿环外缘下坠 + 底部积液上涨 + 自上而下退去」。
// 挂在铺满屏幕的 ColorRect 上，放在要被淹没的节点之后。所有参数默认值等于原画面不变，
// 节奏由外部 AnimationPlayer 改写参数实现，本文件不含时间轴；泥面流纹读 TIME，动画停住时泥仍在流。
// 圆孔与光环（云框）的几何由参数声明，按背景实测填写，着色器不从画面猜测轮廓。
// 保证：pool = 1 时任意宽高比、任意孔位都满屏；drain = 1 时完全退净。

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
// 孔中心（屏幕 UV）与半径、光环外缘半径（屏高单位），按背景主体实测填写。
uniform vec2 hole_center = vec2(0.5, 0.5);
uniform float hole_radius = 0.3;
uniform float ring_outer = 0.5;
// 云框：圆环下方左右两侧云团内缘到孔中心的水平距离（屏高单位），x 为孔中心高度处，y 为屏幕底部处，中间线性过渡。
// 下坠泥流的左右边界贴着这条线走，按背景实测填写。
uniform vec2 frame_left = vec2(0.46, 0.43);
uniform vec2 frame_right = vec2(0.56, 0.45);

// 高光染红程度 0..1：越亮的地方越红，暗部只轻微压暗偏红。
uniform float corrupt = 0.0;
uniform vec3 corrupt_color : source_color = vec3(0.86, 0.05, 0.07);
// 心跳脉动 0..1：画面以孔为中心外推一下，孔外光环增亮。
uniform float pulse = 0.0;

// 孔内积泥 0..1：泥面从孔底往上涨的比例。
uniform float hole_fill = 0.0;
// 漫环 0..1：泥越过孔下缘铺满光环下部，覆盖角从正下方向两侧扩到 spill_span。
uniform float spill = 0.0;
// 漫环最大覆盖角（弧度，自正下方量起，单侧）。
uniform float spill_span = 1.75;
// 下坠 0..1：泥从光环下部沿云框内缘垂落，1 时落到屏幕底部以下。
uniform float fall = 0.0;
// 积液 0..1：泥在屏幕底部积起并上涨，1 时满屏。
uniform float pool = 0.0;
// 退去 0..1：黑泥自上而下退去；1 时完全退净。
uniform float drain = 0.0;
// 泥边暗红余光强度。
uniform float rim = 0.0;

// 前缘起伏幅度（屏高单位）与流纹速度。
uniform float edge_noise = 0.03;
uniform float flow_speed = 0.35;
uniform vec3 mud_color : source_color = vec3(0.025, 0.012, 0.02);
uniform vec3 sheen_color : source_color = vec3(0.42, 0.36, 0.48);
uniform vec3 rim_color : source_color = vec3(0.5, 0.04, 0.07);

float hash21(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return s / 0.875;
}

float luma_of(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float px = SCREEN_PIXEL_SIZE.y;
	float aa = px * 1.5;
	vec2 d = (SCREEN_UV - hole_center) * vec2(aspect, 1.0);
	float r = length(d);
	float X = d.x;
	float Y = SCREEN_UV.y;
	float cy = hole_center.y;
	float R = hole_radius;

	// 脉动外推：镜像采样，越界折回，避免 clamp 拉出边缘条纹
	vec2 suv = SCREEN_UV - (SCREEN_UV - hole_center) * 0.014 * pulse;
	suv = abs(mod(suv + 1.0, 2.0) - 1.0);
	vec3 col = texture(screen_tex, suv).rgb;

	// 高光染红
	float luma = luma_of(col);
	float hi = smoothstep(0.35, 0.95, luma);
	vec3 tainted = mix(col * vec3(0.62, 0.42, 0.5), corrupt_color * (0.2 + 0.85 * luma * luma), hi);
	col = mix(col, tainted, clamp(corrupt, 0.0, 1.0));

	// 心跳：孔外光环增亮
	float ring_x = (r - R * 1.18) / max(R * 0.22, 0.0001);
	col += corrupt_color * exp(-ring_x * ring_x) * pulse * 0.55;

	// 分支条件只依赖 uniform，全屏走同一路径，分支内的 dFdx/dFdy 有定义
	if (hole_fill > 0.0001 || spill > 0.0001 || fall > 0.0001 || pool > 0.0001) {
		float t = TIME * flow_speed;
		float Yr = d.y;
		float RO = max(ring_outer, R + 0.01);
		float theta = atan(abs(X), Yr); // 0 为正下方，PI 为正上方
		// 每一列的差异：一股股先后落下的泥舌
		float tongue = vnoise(vec2(X * 7.0, 2.3)) * 0.65 + vnoise(vec2(X * 19.0, 5.9)) * 0.35;
		float wobble = (fbm(vec2(X * 5.0, Y * 2.0) - vec2(0.0, t)) - 0.5) * edge_noise * 2.0;
		float inside = -1.0; // 到泥边的带符号距离（屏高单位），正为泥内
		float in_ring = -1.0;
		float in_pool = -1.0;

		// ① 孔内积泥：泥面自孔底上涨
		if (hole_fill > 0.0001) {
			float level = cy + R - clamp(hole_fill, 0.0, 1.0) * 2.0 * R + wobble * 0.5;
			inside = max(inside, min(Y - level, R + 0.004 - r));
		}
		float s = clamp(spill, 0.0, 1.0);
		float span = s * spill_span;
		// ② 漫环：自孔下缘越过光环向外，外缘贴着光环（云框）止住；覆盖角向两侧扩
		if (spill > 0.0001) {
			float rf = R + clamp(s * 3.0, 0.0, 1.0) * (RO - R);
			float dout = rf + wobble * 0.3 - r;
			float dang = (span + (tongue - 0.5) * 0.35 * (1.0 - s) - theta) * r;
			in_ring = min(min(r - R + 0.006, dout), dang);
			inside = max(inside, in_ring);
		}
		// ③ 下坠：从光环外圆下缘挂下的泥帘，左右贴云框内缘；只在已被漫环覆盖的角度内下坠
		float in_fall = -1.0;
		if (fall > 0.0001) {
			float fl = clamp(fall, 0.0, 1.0);
			float k = clamp(Yr / max(1.0 - cy, 0.0001), 0.0, 1.0);
			float fw = X < 0.0 ? mix(frame_left.x, frame_left.y, k) : mix(frame_right.x, frame_right.y, k);
			// 云框边带不规则起伏，像泥贴着云团鼓包流过
			fw += (fbm(vec2(Y * 9.0 - t * 1.5, X < 0.0 ? 3.0 : 11.0)) - 0.5) * edge_noise * 1.6;
			float ax = min(abs(X), RO);
			float edge = sqrt(max(RO * RO - ax * ax, 0.0));
			float dtop = Yr - edge + 0.012;
			float len = fl * 1.3 - (1.0 - fl) * 0.25 * tongue;
			float dbot = edge + len + wobble - Yr;
			float dside = fw - abs(X);
			float dang = (span - atan(ax, edge)) * RO;
			in_fall = min(min(min(dtop, dbot), dside), dang);
			inside = max(inside, in_fall);
		}
		// ④ 积液：自屏幕底部上涨，液面有起伏；pool = 1 时液面在屏幕顶部以上
		if (pool > 0.0001) {
			float lv = mix(1.04, -0.08 - edge_noise, clamp(pool, 0.0, 1.0));
			float wave = (fbm(vec2(X * 3.0 + t * 0.6, 7.0)) - 0.5) * edge_noise * 1.5;
			in_pool = Y - lv + wave;
			inside = max(inside, in_pool);
		}
		// ⑤ 退去线：自上而下，拉丝处退得慢；drain = 1 时线在屏幕下方以外
		float lag = pow(vnoise(vec2(X * 22.0, 1.3)), 8.0) * 0.25;
		float line = mix(-0.4, 1.4 + edge_noise, clamp(drain, 0.0, 1.0)) - lag + wobble;
		inside = min(inside, Y - line);

		float m = smoothstep(-aa, aa, inside);
		// 泥外侧暗红余光
		col += rim_color * exp(-max(-inside, 0.0) / 0.02) * (1.0 - m) * rim * 0.5;

		// 流向：环上沿半径向外，下坠区竖直向下且越往下越快，积液区为横向波纹，孔内为缓慢翻涌
		float w_ring = step(max(in_fall, in_pool), in_ring);
		float w_pool = step(max(in_fall, in_ring), in_pool) * step(0.0, in_pool);
		float speed = 1.0 + 2.5 * clamp(Yr, 0.0, 1.0);
		float q_down = fbm(vec2(X * 26.0, Y * 2.2 - t * 2.4 * speed));
		float q_ring = fbm(vec2(theta * 9.0, r * 3.0 - t * 2.4));
		float q_pool = fbm(vec2(X * 5.0 + t * 0.4, Y * 30.0 - t * 1.2));
		float streak = mix(mix(q_down, q_ring, w_ring), q_pool, w_pool);
		// 细亮水线：顺流拉长的高光丝
		float thread = pow(1.0 - abs(fbm(vec2(X * 48.0, Y * 1.6 - t * 3.0 * speed)) * 2.0 - 1.0), 14.0) * (1.0 - w_pool) * (1.0 - w_ring);
		// 高度场：边缘薄、内部厚的圆润截面 + 顺流拉长的水束起伏
		float thick = smoothstep(0.0, 0.05, inside);
		float h = thick * 0.08 + (streak - 0.5) * 0.03 * (0.35 + 0.65 * thick) + thread * 0.004;
		vec3 nrm = normalize(vec3(-dFdx(h) / px * 0.5, -dFdy(h) / px * 0.5, 1.0));
		vec3 Ld = normalize(vec3(-0.35, -0.8, 0.5));
		float diff = max(dot(nrm, Ld), 0.0);
		float spec = pow(max(dot(nrm, normalize(Ld + vec3(0.0, 0.0, 1.0))), 0.0), 40.0);
		float fres = pow(1.0 - nrm.z, 2.0);
		vec3 mud = mud_color * (0.5 + 0.7 * diff) + sheen_color * (spec * 0.75 + fres * 0.4);
		// 边缘薄处透出被折射、压暗的背景，泥体中心不透
		vec2 ruv = abs(mod(SCREEN_UV + nrm.xy * 0.02 + 1.0, 2.0) - 1.0);
		vec3 refr = texture(screen_tex, ruv).rgb * vec3(0.2, 0.12, 0.15);
		mud = mix(refr + sheen_color * spec * 0.6, mud, smoothstep(0.0, 0.5, thick));
		mud += sheen_color * thread * 0.35 * thick;
		col = mix(col, mud, m);
	}
	COLOR = vec4(col, 1.0);
}
