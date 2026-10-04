shader_type canvas_item;
#include "res://assets/shaders/shard_field.gdshaderinc"

// 分区传送门。时间线、速度与曝光由 AnimationPlayer 提供，不读取 TIME。
// 内区保持圆边界，以非线性径向映射模拟景深拉远；外区逼近但不重复采到黑孔。
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec2 center = vec2(0.5);
uniform float hole_radius = 0.37;
uniform float seam_width = 0.018;
uniform float inner_angle = 0.0;
uniform float outer_angle = 0.0;
uniform float inner_depth = 1.0;
uniform float outer_zoom = 1.0;
uniform float aperture_scale = 1.0;
// 曝光窗口内的角位移和对数尺度变化，由动画曲线的速度计算。
uniform float inner_blur_angle = 0.0;
uniform float outer_blur_angle = 0.0;
uniform float radial_blur = 0.0;
uniform float center_light = 0.0;
// 白光推进方向：0 从中心向孔边扩开，1 从孔边（云环）向中心收拢。
uniform float light_origin = 0.0;
// 内收白光在推进阶段的最大不透明度（0..1）；1 为一扫过即满白。
uniform float light_hold = 1.0;
uniform float cloud_light = 0.0;
uniform float blue_cover = 0.0;
uniform float white_cover = 0.0;
uniform vec3 light_color : source_color = vec3(1.0, 0.975, 0.94);
// 外区（云）碎裂吸入：shatter 为进度，0 时外区为原画面；碎块离开后露出 light_color。
// 碎块在白光之上、全屏白之下绘制，飞进孔里时仍看得见。
uniform float shatter = 0.0;
uniform float shard_sectors = 96.0;
uniform float shard_spread = 0.45;
uniform float shard_jitter = 0.25;
uniform float shard_outer_first = 0.0;
uniform float shard_loosen = 0.15;
uniform float shard_trail = 0.1;
uniform vec3 crack_color : source_color = vec3(1.0, 0.97, 0.9);
uniform float crack = 0.0;
const int SAMPLES = 10;

vec2 rotate_point(vec2 p, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// 从中心沿 dir（宽高比校正空间）到屏幕边界的距离；中心不在屏幕正中也成立。
float screen_edge_distance(vec2 dir, float aspect) {
	vec2 lo = -center * vec2(aspect, 1.0);
	vec2 hi = (1.0 - center) * vec2(aspect, 1.0);
	float tx = dir.x > 0.00001 ? hi.x / dir.x : (dir.x < -0.00001 ? lo.x / dir.x : 1e6);
	float ty = dir.y > 0.00001 ? hi.y / dir.y : (dir.y < -0.00001 ? lo.y / dir.y : 1e6);
	return min(tx, ty);
}

vec3 sample_zone(vec2 d, float aspect, bool inside, float history) {
	float radius = max(hole_radius, 0.001);
	float r = length(d) / max(aperture_scale, 0.001);
	vec2 dir = length(d) > 0.00001 ? normalize(d) : vec2(0.0);
	float angle = outer_angle - outer_blur_angle * history;
	float source_r;
	if (inside) {
		angle = inner_angle - inner_blur_angle * history;
		// 圆周映回原圆周，中心层次拉远，边界不因缩放漂移。
		source_r = radius * pow(clamp(r / radius, 0.0, 1.0), 1.0 / max(inner_depth, 0.01));
	} else {
		// 从孔边向外计算推进，避免放大后在外区再出现第二个黑孔。
		float zoom = max(outer_zoom * exp(-radial_blur * history), 0.01);
		source_r = radius + max(r - radius, 0.0) / zoom;
	}
	vec2 sdir = rotate_point(dir, -angle);
	if (!inside) {
		// 外区越界时只在「孔边—该方向屏幕边」之间径向折回，避免旋转后折回采到黑孔。
		float edge_r = screen_edge_distance(sdir, aspect);
		float span = max(edge_r - radius, 0.001);
		float x = mod(source_r - radius, span * 2.0);
		source_r = radius + (x > span ? span * 2.0 - x : x);
	}
	vec2 uv = center + sdir * source_r / vec2(aspect, 1.0);
	// 内区不会越界；保留镜像折回作数值兜底，避免 clamp 拉出条纹。
	uv = abs(mod(uv + 1.0, 2.0) - 1.0);
	return texture(screen_tex, uv).rgb;
}

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 d = (SCREEN_UV - center) * vec2(aspect, 1.0);
	float r = length(d);
	float radius = max(hole_radius * aperture_scale, 0.001);
	float rn = r / radius;
	float seam = max(seam_width * aperture_scale, SCREEN_PIXEL_SIZE.y);
	float outside = smoothstep(radius - seam, radius + seam, r);
	// 内外分别积累，历史采样不跨区；只在窄交界带混合。
	vec3 inner = vec3(0.0);
	vec3 outer = vec3(0.0);
	// 拖影权重：中心清楚，越接近当前窗口最远角越强，任意宽高比都按实际角点计算。
	float far_corner = length(max(center, 1.0 - center) * vec2(aspect, 1.0));
	float edge = smoothstep(radius * 0.15, far_corner, r);
	bool moving = abs(inner_blur_angle) + abs(outer_blur_angle) + abs(radial_blur) > 0.0001;
	if (moving) {
		for (int i = 0; i < SAMPLES; i++) {
			float history = float(i) / float(SAMPLES - 1) * edge;
			if (outside < 1.0) inner += sample_zone(d, aspect, true, history);
			if (outside > 0.0) outer += sample_zone(d, aspect, false, history);
		}
		inner /= float(SAMPLES);
		outer /= float(SAMPLES);
	} else {
		if (outside < 1.0) inner = sample_zone(d, aspect, true, 0.0);
		if (outside > 0.0 && shatter <= 0.0) outer = sample_zone(d, aspect, false, 0.0);
	}
	// 碎裂开始后，外区底色换成白光，云只存在于碎块里。
	if (shatter > 0.0) outer = light_color;
	vec3 col = mix(inner, outer, outside);
	// 中央蓝色区域保持原样；只有圆孔外的云获得逐渐增强的光。
	float cloud_zone = smoothstep(0.94, 1.10, rn);
	float cloud_glow = clamp(cloud_light, 0.0, 1.0) * cloud_zone;
	col = mix(col, col + light_color * 0.62, cloud_glow);
	// 白光由云环向圆心延伸：前沿从外向内推进，云本身是光源。
	float cover_progress = clamp(blue_cover, 0.0, 1.0);
	float cover_front = mix(1.12, -0.10, cover_progress);
	float blue_white = smoothstep(cover_front - 0.14, cover_front + 0.14, rn);
	// 沿多个相邻方向回采云环，形成云的连续延伸，避免中心生成均匀白圆。
	vec2 ray_dir = length(d) > 0.00001 ? normalize(d) : vec2(1.0, 0.0);
	vec3 cloud_source = vec3(0.0);
	for (int j = 0; j < 5; j++) {
		float q = float(j) / 4.0 - 0.5;
		vec2 sample_dir = rotate_point(ray_dir, q * 0.20);
		cloud_source += sample_zone(sample_dir * radius * (1.02 + q * 0.10), aspect, false, 0.0);
	}
	cloud_source /= 5.0;
	vec3 cloud_white = min(cloud_source * (1.10 + 0.45 * cover_progress) + light_color * 0.04, vec3(1.0));
	col = mix(col, cloud_white, blue_white * cover_progress);
	// 孔边桥接：内侧最后一段使用同一圈云光，保证云环向内延伸时没有亮度断缝。
	float rim_bridge = (1.0 - outside) * smoothstep(0.76, 1.02, rn) * clamp(max(cloud_light, cover_progress), 0.0, 1.0);
	col = mix(col, cloud_white, rim_bridge * 0.92);
	col = mix(col, vec3(1.0), clamp(white_cover, 0.0, 1.0));
	COLOR = vec4(col, 1.0);
}
