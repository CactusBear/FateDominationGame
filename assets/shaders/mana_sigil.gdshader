shader_type canvas_item;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool breathing = false;
uniform float breath_period : hint_range(0.1, 10.0) = 2.8;
uniform float breath_min : hint_range(0.0, 1.0) = 0.45;
uniform float breath_max : hint_range(1.0, 2.0) = 1.15;
void fragment() {
	vec4 ink = texture(TEXTURE, UV);
	float glow = 1.0;
	if (breathing) {
		float pulse = 0.5 - 0.5 * cos(TIME * 6.28318530718 / breath_period);
		// 只调制半透明的辉光；实心符文和独立的数字不参与呼吸。
		float halo_weight = (1.0 - smoothstep(0.25, 0.85, ink.a)) * smoothstep(0.25, 0.32, length(UV - vec2(0.5)));
		glow = mix(1.0, mix(breath_min, breath_max, pulse), halo_weight);
	}
	COLOR = vec4(tint.rgb, clamp(ink.a * glow, 0.0, 1.0) * COLOR.a);
}
