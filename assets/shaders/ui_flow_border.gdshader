shader_type canvas_item;

// 通用 UI 流动边框：沿控件矩形外缘画一圈金框，并让一段亮光沿边框循环流动。
// 只决定颜色与透明度，不采样纹理；fragment 输入的 COLOR 已含节点与祖先的调制，
// 因此可以叠加在呼吸、淡入之上，而不会被覆盖。
// 坐标系用节点本地像素（ColorRect 从 (0,0) 画到 rect_size），尺寸由调用方传入：
// 着色器拿不到节点尺寸，控件尺寸变化时必须由脚本更新 rect_size。
uniform vec2 rect_size = vec2(72.0, 560.0);
uniform float border_width : hint_range(0.5, 16.0) = 4.0;
uniform float edge_softness : hint_range(0.0, 12.0) = 1.5;
uniform vec4 frame_color : source_color = vec4(0.9098, 0.8039, 0.5255, 1.0);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.3;
uniform float flow_alpha : hint_range(0.0, 1.0) = 1.0;
// 速度/间距/长度都按像素给：控件大小差别很大（收起的窄条与展开的整屏）时观感一致
uniform float glow_size = 26.0;
uniform float flow_speed = 300.0;
uniform float flow_spacing = 700.0;
uniform float flow_length = 560.0;

void fragment() {
	float inherit_a = COLOR.a;
	vec2 sz = max(rect_size, vec2(1.0));
	// 用 UV 反算本地像素坐标：UV 一定覆盖 0..1，比 fragment 的 VERTEX 可靠
	vec2 p = UV * sz;
	// 到最近一条边的距离：用来裁出边框本身
	// 矩形之外的像素一律不画：rect_size 比实际绘制区域小时 min() 会取到负值，
	// 整片区域会被当成"贴边"而亮起来。
	float d = min(min(p.x, sz.x - p.x), min(p.y, sz.y - p.y));
	float inside = step(0.0, p.x) * step(p.x, sz.x) * step(0.0, p.y) * step(p.y, sz.y);
	float edge = inside * (1.0 - smoothstep(border_width, border_width + edge_softness, d));
	if (edge <= 0.0) {
		COLOR = vec4(0.0);
	} else {
		// 顺时针周长参数：上边从左到右 → 右边从上到下 → 下边从右到左 → 左边从下到上。
		// 每条边取"最近边"的表达式，角点只算一次，四段首尾相接因此整体连续。
		float per = 2.0 * (sz.x + sz.y);
		float best = p.y;
		float t = p.x;
		if (sz.x - p.x < best) {
			best = sz.x - p.x;
			t = sz.x + p.y;
		}
		if (sz.y - p.y < best) {
			best = sz.y - p.y;
			t = sz.x + sz.y + (sz.x - p.x);
		}
		if (p.x < best) {
			t = 2.0 * sz.x + sz.y + (sz.y - p.y);
		}
		// 光流：相位沿周长前进（t 增大方向就是绕框方向）。flow_spacing 决定周线上同时有几条
		// 光流（控件越大条数越多、间距保持像素级一致），每条长 flow_length 像素，中心最亮、
		// 两侧平滑收尾；绕回点落在两条光流之间的暗区，接缝不可见。
		float ph = fract((t - TIME * flow_speed) / per);
		float count = max(1.0, round(per / max(flow_spacing, 1.0)));
		float u = abs(fract(ph * count + 0.5) - 0.5) * 2.0;
		float half_w = clamp((flow_length * 0.5 * count) / per, 0.02, 1.0);
		float band = 1.0 - smoothstep(0.0, half_w, u);
		// 光流 = 细亮线 + 内侧柔和辉光；底线只是一圈暗金，没有光流经过时也能看出框
		float shape = max(edge, (1.0 - smoothstep(border_width, border_width + glow_size, d)) * 0.5);
		float a = max(edge * base_alpha, shape * flow_alpha * band) * inherit_a;
		COLOR = vec4(frame_color.rgb, a);
	}
}
