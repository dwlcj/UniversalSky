/*========================================================
°                       Universal Sky.
°                   ======================
°
°   Category: Skydome.
°   -----------------------------------------------------
°   Description:
°       Sky dome pass.
°   -----------------------------------------------------
°   Copyright:
°               J. Cuellar 2020. MIT License.
°                   See: LICENSE Archive.
========================================================*/
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_front, skip_vertex_transform;

// Sun.
uniform vec4 _sun_disk_color;
uniform float _sun_disk_size;
uniform vec3 _sun_direction;

// Moon.
uniform sampler2D _moon_texture;
uniform vec4 _moon_color: hint_color = vec4(1.0);
uniform float _moon_size;
uniform vec3 _moon_direction;
uniform mat3 _moon_matrix;

// x = contrast, y = tonemap level, exposure..
uniform vec3 _color_correction_params;
uniform vec4 _ground_color: hint_color;

// Background.
uniform sampler2D _background_texture: hint_albedo;
uniform vec4 _background_color;

// Stars Field.
uniform vec4 _stars_field_color;
uniform sampler2D _stars_field_texture: hint_albedo;
uniform float _stars_scintillation;
uniform float _stars_scintillation_speed;

uniform sampler2D _noise_tex: hint_albedo;

uniform mat3 _deep_space_matrix;

// Common.
// Math Constants.
const float kPI          = 3.1415927f;
const float kINV_PI      = 0.3183098f;
const float kHALF_PI     = 1.5707963f;
const float kINV_HALF_PI = 0.6366198f;
const float kQRT_PI      = 0.7853982f;
const float kINV_QRT_PI  = 1.2732395f;
const float kPI4         = 12.5663706f;
const float kINV_PI4     = 0.0795775f;
const float k3PI16       = 0.1193662f;
const float kTAU         = 6.2831853f;
const float kINV_TAU     = 0.1591549f;
const float kE           = 2.7182818f;

float saturate(float value){
	return clamp(value, 0.0, 1.0);
}

vec3 saturateRGB(vec3 value){
	return clamp(value.rgb, 0.0, 1.0);
}

// pow3
vec3 contrastLevel(vec3 vec, float level){
	return mix(vec, vec * vec * vec, level);
}

vec3 tonemapPhoto(vec3 color, float exposure, float level){
	color.rgb *= exposure;
	return mix(color.rgb, 1.0 - exp(-color.rgb), level);
}

vec3 tonemapACES(vec3 color, float exposure, float level){
	color.rgb *= exposure;
	const vec3  a = vec3(2.51);
	const float b = 0.03;
	const float c = 2.43;
	const float d = 0.59;
	const float e = 0.14;
	vec3 ret = (color.rgb * (a * color.rgb + b)) / (color.rgb * (c * color.rgb + d) + e);
	return mix(color.rgb, ret, level);
}

vec3 mul(mat3 mat, vec3 vec){
	vec3 ret;
	ret.x = dot(mat[0].xyz, vec.xyz);
	ret.y = dot(mat[1].xyz, vec.xyz);
	ret.z = dot(mat[2].xyz, vec.xyz);
	return ret;
}

vec2 equirectUV(vec3 norm){
	vec2 ret;
	ret.x = (atan(norm.x, norm.z) + kPI) * kINV_TAU;
	ret.y = acos(norm.y) * kINV_PI;
	return ret;
}

float random(vec2 uv){
	float ret = dot(uv, vec2(12.9898, 78.233));
	return fract(43758.5453 * sin(ret));
}

float disk(vec3 norm, vec3 coords, lowp float size){
	float dist = length(norm - coords);
	return 1.0 - step(size, dist);
}


varying vec4 world_pos;
varying vec4 moon_coords;
varying vec3 deep_space_coords;
varying vec4 angle_mult;
void vertex(){
	world_pos = (WORLD_MATRIX * vec4(VERTEX, 1.0));
	moon_coords.xyz  = mul(_moon_matrix, VERTEX).xyz / _moon_size + 0.5;
	moon_coords.w = dot(world_pos.xyz, _moon_direction); 
	deep_space_coords.xyz = (_deep_space_matrix * VERTEX).xyz;
	angle_mult.x = saturate(1.0 - _sun_direction.y);
	angle_mult.y = saturate(_sun_direction.y + 0.45);
	angle_mult.z = saturate(-_sun_direction.y + 0.30);
	angle_mult.w = saturate(-_sun_direction.y + 0.60);
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1e-5)).xyz;
}

void fragment(){
	vec3 col = vec3(0.0);
	vec3 ray = normalize(world_pos).xyz;
	
	// Atmospheric Scattering.
	vec3 scatter = vec3(1.0);
	
	vec3 nearSpace = vec3(0.0);
	
	// SunDisk.
	vec3 sunDisk = disk(ray, _sun_direction, _sun_disk_size) * 
		_sun_disk_color.rgb * scatter.rgb;
	
	// Moon.
	vec4 moon = texture(_moon_texture, vec2(-moon_coords.x+1.0, moon_coords.y));
	moon.rgb = contrastLevel(moon.rgb * _moon_color.rgb, _moon_color.a);
	moon *= saturate(moon_coords.w);
	//moon.rgb *= moon.a;
	float moonMask = saturate(1.0 - moon.a);
	nearSpace = moon.rgb + (sunDisk.rgb * moonMask);
	
	col.rgb += nearSpace;
	
	vec3 deepSpace = vec3(0.0);
	vec2 deepSpaceUV = equirectUV(normalize(deep_space_coords));
	
	// Background.
	vec3 deepSpaceBackground = textureLod(_background_texture, deepSpaceUV, 0.0).rgb;
	deepSpaceBackground *= _background_color.rgb;
	deepSpaceBackground = contrastLevel(deepSpaceBackground, _background_color.a);
	deepSpace.rgb += deepSpaceBackground.rgb * moonMask;
	
	// Stars Field.
	/*float starsScintillation = random(UV);
	starsScintillation = sin((TIME * _stars_scintillation_speed) * starsScintillation);*/
	
	float starsScintillation = textureLod(_noise_tex, UV + (TIME * _stars_scintillation_speed), 0.0).r;
	starsScintillation = mix(1.0, starsScintillation * 1.5, _stars_scintillation);
	
	vec3 starsField = textureLod(_stars_field_texture, deepSpaceUV, 0.0).rgb * _stars_field_color.rgb;
	starsField = saturateRGB(mix(starsField.rgb, starsField.rgb * starsScintillation, _stars_scintillation));
	//deepSpace.rgb -= saturate(starsField.r*10.0);
	deepSpace.rgb += starsField.rgb * moonMask;
	deepSpace.rgb *= angle_mult.z;
	col.rgb += deepSpace.rgb;
	
	col.rgb = mix(col.rgb, _ground_color.rgb * scatter, saturate((-ray.y)*100.0));
	col.rgb = tonemapPhoto(col.rgb, _color_correction_params.z, _color_correction_params.y);
	col.rgb = contrastLevel(col.rgb, _color_correction_params.x);
	
	ALBEDO = col.rgb;
}


