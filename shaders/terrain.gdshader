shader_type spatial;
// Terrain: five ground textures blended by the vertex colour (a splat map).
// Layer 0 is the base; R, G, B, A are layers 1-4. Textures tile in world metres.
render_mode cull_back;

uniform sampler2D alb0 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D alb1 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D alb2 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D alb3 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D alb4 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm0 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm1 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm2 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm3 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm4 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 scales = vec4(0.25, 0.3, 0.3, 0.25);   // tiles per metre, layers 1-4
uniform float scale0 = 0.25;
uniform vec3 tint = vec3(1.0);
uniform float sharpness = 6.0;   // how crisp the borders between layers are

varying vec4 splat;
varying vec3 wpos;

void vertex() {
	splat = COLOR;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz;
	vec4 c0 = texture(alb0, uv * scale0);
	vec4 c1 = texture(alb1, uv * scales.x);
	vec4 c2 = texture(alb2, uv * scales.y);
	vec4 c3 = texture(alb3, uv * scales.z);
	vec4 c4 = texture(alb4, uv * scales.w);
	// height-like blend: brighter (higher) texels win at the borders
	float w0 = max(0.0, 1.0 - splat.r - splat.g - splat.b - splat.a);
	vec4 w1 = splat;
	vec4 lum = vec4(dot(c1.rgb, vec3(0.33)), dot(c2.rgb, vec3(0.33)), dot(c3.rgb, vec3(0.33)), dot(c4.rgb, vec3(0.33)));
	float l0 = dot(c0.rgb, vec3(0.33));
	vec4 h = w1 + lum * 0.3;
	float h0 = w0 + l0 * 0.3;
	float m = max(max(max(h.x, h.y), max(h.z, h.w)), h0) - 1.0 / sharpness;
	vec4 b = max(h - m, 0.0) * step(0.001, w1);
	float b0 = max(h0 - m, 0.0) * step(0.001, w0);
	float sum = b0 + b.x + b.y + b.z + b.w + 1e-5;
	b /= sum;
	b0 /= sum;
	ALBEDO = (c0.rgb * b0 + c1.rgb * b.x + c2.rgb * b.y + c3.rgb * b.z + c4.rgb * b.w) * tint;
	vec3 n = texture(nrm0, uv * scale0).rgb * b0 + texture(nrm1, uv * scales.x).rgb * b.x
		+ texture(nrm2, uv * scales.y).rgb * b.y + texture(nrm3, uv * scales.z).rgb * b.z
		+ texture(nrm4, uv * scales.w).rgb * b.w;
	NORMAL_MAP = n;
	ROUGHNESS = 0.92;
}
