// 极坐标碎块场：以原点为圆心，把平面切成「对数间距的环 × 扇区」，每环随机错位（像砌砖），
// 每块再先径向、后角向各二分（分割点随机），得到大小随半径变化、形状不规则的碎块。
// 碎块只沿径向被吸向圆心，并按半径比例缩小成粒子；因此逆映射只需沿径向逐环查找。
// 坐标单位：宽高比校正后的屏高单位。progress=0 时逐像素恒等（src == p）。

const int SHARD_MAX_RINGS = 64;

float shard_hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// 查找覆盖像素 p 的碎块。idx 为续查游标：首次传 -1；命中后再次调用会从更靠内的下一块继续，
// 用于上层碎块在该处透明时向下查找。返回是否命中；src 为该碎块对应的原始位置，
// alpha 为不透明度（含拖影衰减与末段消散），edge 为碎块边缘亮度（松动后显现的裂纹光）。
// sectors：一圈扇区数；r_min/r_max：环范围；spread：外圈到内圈的错峰占比；jitter：同环随机错峰；
// outer_first：1 外圈先碎、0 内圈先碎；loosen：起步松动（露缝）占单块时长的比例；
// trail：径向拖影长度系数；px：一个像素对应的长度；fill_core：最内环是否覆盖到圆心（否则只覆盖 r_min 以外）。
bool shard_lookup(vec2 p, float progress, float sectors, float r_min, float r_max,
		float spread, float jitter, float outer_first, float loosen, float trail, float px, bool fill_core,
		inout int idx, out vec2 src, out float alpha, out float edge) {
	src = p;
	alpha = 0.0;
	edge = 0.0;
	float r = length(p);
	float th = atan(p.y, p.x);
	float w = TAU / max(round(sectors), 3.0);
	float lq = log(1.0 + w);
	int n = clamp(int(ceil(log(max(r_max, r_min * 1.01) / r_min) / lq)), 1, SHARD_MAX_RINGS);
	float dur = max(1.0 - spread - jitter, 0.05);
	// 碎块只向内移动且拖影不超过已走距离，所以比本像素静止所在环更内的块到不了这里。
	int i0 = r <= r_min ? 0 : int(floor(log(r / r_min) / lq));
	// 扇区序号按整圈取模，跨越 ±π 的那一块两半用同一组随机数，不出现接缝。
	float ns = TAU / w;
	int start = idx < 0 ? n * 4 - 1 : idx - 1;
	for (int f = SHARD_MAX_RINGS * 4 - 1; f >= 0; f--) {
		if (f > start) continue;
		int ii = f / 4;
		if (ii < i0) break;
		int sub = f - ii * 4;
		int kr = sub / 2;
		int ka = sub - kr * 2;
		float fi = float(ii);
		float rr0 = (ii == 0 && fill_core) ? 0.0 : r_min * exp(lq * fi);
		float rr1 = r_min * exp(lq * (fi + 1.0));
		float off = shard_hash(vec3(fi, 7.0, 1.0)) * w;
		float j0 = floor((th - off) / w);
		float a0 = off + j0 * w;
		float j = mod(j0, ns);
		float rm = mix(rr0, rr1, 0.35 + 0.3 * shard_hash(vec3(fi, j, 5.0)));
		float am = a0 + w * (0.35 + 0.3 * shard_hash(vec3(fi, j, 9.0 + float(kr))));
		float sr0 = kr == 0 ? rr0 : rm;
		float sr1 = kr == 0 ? rm : rr1;
		float sa0 = ka == 0 ? a0 : am;
		float sa1 = ka == 0 ? am : a0 + w;
		float rc0 = max(0.5 * (sr0 + sr1), 1e-4);
		float ac = 0.5 * (sa0 + sa1);
		float ring_n = (fi + 0.5) / float(n);
		float order = mix(ring_n, 1.0 - ring_n, clamp(outer_first, 0.0, 1.0));
		float h = shard_hash(vec3(fi * 2.0 + float(kr), j * 2.0 + float(ka), 3.0));
		float u = clamp((progress - order * spread - h * jitter) / dur, 0.0, 1.0);
		float lu = clamp(u / max(loosen, 1e-4), 0.0, 1.0);
		float mu = clamp((u - loosen) / max(1.0 - loosen, 1e-4), 0.0, 1.0);
		// 松动阶段只亮裂纹、块不缩（缩了会在每块周围露出底色细框）；吸入：中心半径加速收向原点，
		// 块按半径比例缩小，末段再缩成粒子。
		float g = mix(1.0, 0.3, mu);
		float rc = rc0 * (1.0 - mu * mu);
		float s = (rc / rc0) * g;
		if (s < 0.003) continue;
		float src_r = rc0 + (r - rc) / s;
		// 拖影：在碎块外侧（来路方向）延伸，长度随速度增长、不超过已走距离。
		float tl = min(trail * 2.0 * mu * rc0, rc0 - rc) / s;
		if (src_r < sr0 || src_r > sr1 + tl) continue;
		float fade = src_r > sr1 ? 1.0 - (src_r - sr1) / max(tl, 1e-5) : 1.0;
		float sr_cl = clamp(src_r, sr0, sr1 - 1e-5);
		float src_a = ac + (th - ac) * r / (s * max(sr_cl, 1e-4));
		if (src_a < sa0 || src_a >= sa1) continue;
		idx = f;
		src = vec2(cos(src_a), sin(src_a)) * sr_cl;
		alpha = fade * fade * (1.0 - smoothstep(0.8, 1.0, mu));
		// 裂纹光：按屏幕像素量边距，只在松动阶段出现，碎块开始飞行后熄灭，避免满屏空心框。
		float dpx = min(min(src_r - sr0, sr1 - src_r), min(src_a - sa0, sa1 - src_a) * sr_cl) * s;
		edge = (1.0 - smoothstep(0.0, 2.0 * px, dpx)) * lu * (1.0 - smoothstep(0.0, 0.35, mu)) * (src_r > sr1 ? 0.0 : 1.0);
		return true;
	}
	return false;
}
