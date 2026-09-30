shader_type canvas_item;

// 通用 UI 遮罩。只决定像素透明度，不改颜色。
// shape 0：沿 fade_dir 方向按 UV 线性渐隐，fade_start 处全透明、fade_end 处全显示（立绘边缘融入背景）。
// shape 1：圆形裁切，softness 是边缘羽化宽度（圆形头像）。
// 其他取值不裁切，方便调用方临时关掉遮罩而不用换材质。
uniform int shape = 0;
uniform vec2 fade_dir = vec2(1.0, 0.0);
uniform float fade_start = 0.0;
uniform float fade_end = 0.5;
uniform float softness = 0.01;

void fragment() {
	float a = 1.0;
	if (shape == 0) {
		float t = dot(UV, normalize(fade_dir));
		a = smoothstep(fade_start, fade_end, t);
	} else if (shape == 1) {
		float d = distance(UV, vec2(0.5));
		a = 1.0 - smoothstep(0.5 - softness, 0.5, d);
	}
	// fragment 输入的 COLOR 已包含纹理、节点调制色和祖先透明度。
	// 只叠加遮罩，不能重新采样纹理覆盖继承的淡入透明度。
	COLOR.a *= a;
}
