shader_type canvas_item;

// 通用的「环形涡流 + 噪声漂移」位移着色器。
// 只改采样坐标、不改颜色，可挂在任何以 UV 0..1 铺满的 TextureRect / Sprite 上。
//
// 画面按到 center 的距离分成两段：
//   · 环带（ring_inner..ring_outer）：绕 center 旋转，权重在带中心最强、两侧羽化到 0，所以边界不会撕裂。
//   · 环带以外（权重 1 - 环带权重）：按噪声 + 一个往复的风向做缓慢位移。
// 两段互不依赖：只要旋转就把 drift_amount 设 0，只要漂移就把 ring_speed / ring_swirl 设 0，不必换材质。

uniform vec2 center = vec2(0.5, 0.5);
// 长宽比补偿。UV 是各向异性的，横向乘以 宽/高 后距离才是真正的圆。
uniform vec2 aspect = vec2(1.0, 1.0);

// ---- 环形涡流 ----
uniform float ring_inner = 0.18;      // 环带内缘半径（补偿后的 UV 距离）
uniform float ring_outer = 0.45;      // 环带外缘半径
uniform float ring_feather = 0.08;    // 内外缘各自的羽化宽度
uniform float ring_speed = 0.08;      // 环带角速度，弧度/秒，负数反转
uniform float ring_swirl = 0.0;       // 附加角速度，靠内缘处最大、靠外缘处为 0，做出剪切感

// ---- 外围漂移 ----
uniform float drift_amount = 0.004;   // 位移幅度（UV）
uniform float drift_speed = 0.03;     // 噪声演化与风向往复的速度
uniform float drift_scale = 2.5;      // 噪声频率，越大云块越碎
uniform vec2 drift_bias = vec2(1.0, 0.0);  // 风向，会按 drift_speed 正弦往复，不会把贴图推出边界

// 节点最终调制色（modulate / self_modulate / 祖先透明度的合成）。
// vertex 阶段的 COLOR 就是这个顶点色；fragment 里要自己重新采样纹理，
// 就必须把它传下来乘回去，否则淡入淡出等 modulate 动画会失效。
varying vec4 node_modulate;

void vertex() {
	node_modulate = COLOR;
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
		u.y);
}

void fragment() {
	vec2 offset = (UV - center) * aspect;
	float dist = length(offset);

	// 环带权重：内缘淡入、外缘淡出
	float ring = smoothstep(ring_inner - ring_feather, ring_inner + ring_feather, dist)
		* (1.0 - smoothstep(ring_outer - ring_feather, ring_outer + ring_feather, dist));

	// 环带内的归一化位置（0 = 内缘，1 = 外缘），用于 ring_swirl 的径向差速
	float span = max(ring_outer - ring_inner, 0.0001);
	float radial = clamp((dist - ring_inner) / span, 0.0, 1.0);
	float angle = (ring_speed + ring_swirl * (1.0 - radial)) * TIME * ring;
	float s = sin(angle);
	float c = cos(angle);
	vec2 rotated = vec2(offset.x * c - offset.y * s, offset.x * s + offset.y * c);
	vec2 uv = center + rotated / aspect;

	// 环带以外的漂移：两张相位错开的噪声给出二维位移，再叠一个往复的风向
	float outside = 1.0 - ring;
	vec2 np = offset * drift_scale;
	float t = TIME * drift_speed;
	vec2 wander = vec2(
		value_noise(np + vec2(t, 0.0)),
		value_noise(np + vec2(0.0, t) + 17.3)) * 2.0 - 1.0;
	vec2 wind = drift_bias * sin(TIME * drift_speed * 6.2831853);
	uv += (wander + wind) * drift_amount * outside;

	// 重采样位移后的坐标，再乘回节点调制色
	COLOR = texture(TEXTURE, uv) * node_modulate;
}
