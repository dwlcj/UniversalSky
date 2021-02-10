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

// Global.
// x = contrast, y = tonemap level, exposure..
uniform vec3 _color_correction_params;
uniform vec4 _ground_color: hint_color;

// Atmospheric Scattering.
uniform float _atm_darkness;
uniform float _atm_sun_intensity;
uniform vec4 _atm_day_tint: hint_color;
uniform vec4 _atm_horizon_light_tint: hint_color;
uniform vec4 _atm_night_tint: hint_color;

// x = ymultiplier, y= down offset, z = horizon offset.
uniform vec3 _atm_params = vec3(1.0, 0.0, 0.0);

// Sun mie phase.
uniform vec4 _atm_sun_mie_tint: hint_color;
uniform float _atm_sun_mie_intensity;
uniform vec4 _atm_moon_mie_tint: hint_color;
uniform float _atm_moon_mie_intensity;
uniform vec3 _atm_beta_ray;
uniform vec3 _atm_beta_mie;
uniform vec3 _atm_sun_partial_mie_phase;
uniform vec3 _atm_moon_partial_mie_phase;

// Sun.
uniform vec4 _sun_disk_color;
uniform float _sun_disk_size;

// Moon.
uniform sampler2D _moon_texture;
uniform vec4 _moon_color: hint_color = vec4(1.0);
uniform float _moon_size;

// Background.
uniform sampler2D _background_texture: hint_albedo;
uniform vec4 _background_color;

// Stars Field.
uniform vec4 _stars_field_color;
uniform sampler2D _stars_field_texture: hint_albedo;
uniform float _stars_scintillation;
uniform float _stars_scintillation_speed;

uniform sampler2D _noiseTex: hint_albedo;

// Clouds.
uniform float _clouds_coverage;
uniform float _clouds_thickness;
uniform float _clouds_absorption;
uniform int _clouds_step;
uniform float _clouds_noise_freq;
uniform float _clouds_sky_tint_fade;
uniform float _clouds_intensity;
uniform float _clouds_size;
uniform float _clouds_wind_speed;
uniform vec3 _clouds_wind_direction;
uniform sampler2D _clouds_texture;

// Coords.
uniform vec3 _sun_direction;
uniform vec3 _moon_direction;
uniform mat3 _moon_matrix;
uniform mat3 _deep_space_matrix;

// Math constants.
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

// Atmospheric scattering constants.
const float kRAYLEIGH_ZENITH_LENGTH = 8.4e3;
const float kMIE_ZENITH_LENGTH = 1.25e3;


float saturate(float value){
	return clamp(value, 0.0, 1.0);
}

vec3 saturateRGB(vec3 value){
	return clamp(value.rgb, 0.0, 1.0);
}

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

//==============================================================================
// Clouds based in Danil Implementation.
// MIT License.
// See: See: https://github.com/danilw/godot-utils-and-other/tree/master/Dynamic%20sky%20and%20reflection.
float noise(vec3 p){
	vec3 pos = vec3(p * 0.01);
	pos.z *= 256.0;
	vec2 offset = vec2(0.317, 0.123);
	vec4 uv= vec4(0.0);
	uv.xy = pos.xy + offset * floor(pos.z);
	uv.zw = uv.xy + offset;
	float x1 = textureLod(_clouds_texture, uv.xy, 0.0).r;
	float x2 = textureLod(_clouds_texture, uv.zw, 0.0).r;
	return mix(x1, x2, fract(pos.z));
}

float fbm(vec3 p, float l){
	float ret;
	ret = 0.51749673 * noise(p);  
	p *= l;
	ret += 0.25584929 * noise(p); 
	p *= l; 
	ret += 0.12527603 * noise(p); 
	p *= l;
	ret += 0.06255931 * noise(p);
	return ret;
}

float getNoiseClouds(vec3 p){
	float freq = _clouds_noise_freq; //2.76434;
	return fbm(p, freq);
}

float cloudsDensity(vec3 p, vec3 offset, float t){
	vec3 pos = p * 0.0212242 + offset;
	float dens = getNoiseClouds(pos);
	float cov = 1.0 - _clouds_coverage;
	dens *= smoothstep(cov, cov + t, dens);
	return saturate(dens);
}

vec4 cloudsRender(vec3 pos, float tim){
	vec4 ret;
	pos.xy = pos.xz / pos.y;
	vec3 wind = _clouds_wind_direction * (tim * _clouds_wind_speed);
	
	float marchStep = float(_clouds_step) * _clouds_thickness;
	vec3 dirStep = pos * marchStep;
	pos *= _clouds_size;
	
	float t = _clouds_intensity; float a = 0.0;
	for(int i = 0; i < _clouds_step; i++){
		float h = float(i) / float(_clouds_step);
		float density = cloudsDensity(pos, wind, h);
		float sh = saturate(exp(-_clouds_absorption * density * marchStep));
		t *= sh;
		ret += (t * (exp(h) * 0.571428571) * density * marchStep);
		a += (1.0 - sh);
		pos += dirStep;
	}
	return vec4(ret.rgb, a);
}

//==============================================================================

float disk(vec3 norm, vec3 coords, lowp float size){
	float dist = length(norm - coords);
	return 1.0 - step(size, dist);
}

float miePhase(float mu, vec3 partial){
	return kPI4 * (partial.x) * (pow(partial.y - partial.z * mu, -1.5));
}

float rayleighPhase(float mu){
	return k3PI16 * (1.0 + mu * mu);
}

// Simple optical depth.
void _opticalDepth(float y, out float sr, out float sm){
	y = max(0.03, y + 0.03) + _atm_params.y;
	y = 1.0 / (y * _atm_params.x);
	sr = y * kRAYLEIGH_ZENITH_LENGTH;
	sm = y * kMIE_ZENITH_LENGTH;
}


void opticalDepth(float y, out float sr, out float sm)
{
	y = max(0.0, y);
	y = saturate(y * _atm_params.x);
	
	float zenith = acos(y);
	zenith = cos(zenith) + 0.15 * pow(93.885 - ((zenith * 180.0) / kPI), -1.253);
	zenith = 1.0 / (zenith + _atm_params.y);
	
	sr = zenith * kRAYLEIGH_ZENITH_LENGTH;
	sm = zenith * kMIE_ZENITH_LENGTH;
}

vec3 atmosphericScattering(float sr, float sm, vec2 mu, vec3 mult){
	vec3 betaMie = _atm_beta_mie;
	vec3 betaRay = _atm_beta_ray;
	
	vec3 extcFactor = saturateRGB(exp(-(betaRay * sr + betaMie * sm)));
	vec3 finalExtcFactor = mix(1.0 - extcFactor, (1.0 - extcFactor) * extcFactor, mult.x);
	
	float rayleighPhase = rayleighPhase(mu.x);
	
	vec3 BRT = betaRay * rayleighPhase;
	vec3 BMT = betaMie * miePhase(mu.x, _atm_sun_partial_mie_phase);
	BMT *= _atm_sun_mie_intensity * _atm_sun_mie_tint.rgb;
	
	vec3 BRMT = (BRT + BMT) / (betaRay + betaMie);
	
	vec3 scatter = _atm_sun_intensity * (BRMT * finalExtcFactor) * _atm_day_tint.rgb;
	scatter *= mult.y;
	scatter = mix(scatter, scatter * (1.0 - extcFactor), _atm_darkness);
	
	vec3 lcol = mix(_atm_day_tint.rgb, _atm_horizon_light_tint.rgb, mult.x);
	vec3 nscatter = (1.0 - extcFactor) * _atm_night_tint.rgb;
	nscatter += miePhase(mu.y, _atm_moon_partial_mie_phase) * 
		_atm_moon_mie_tint.rgb * _atm_moon_mie_intensity * 0.001;
	return (scatter * lcol) + nscatter;
}

varying vec3 world_coords;
varying vec4 moon_coords;
varying vec3 deep_space_coords;
varying vec4 angle_mult;

void vertex(){
	world_coords = (WORLD_MATRIX * vec4(VERTEX, 1e-5)).xyz;
	moon_coords.xyz  = mul(_moon_matrix, VERTEX).xyz / _moon_size + 0.5;
	moon_coords.w = dot(world_coords, _moon_direction); 
	deep_space_coords.xyz = (_deep_space_matrix * VERTEX).xyz;
	
	angle_mult.x = saturate(1.0 - _sun_direction.y);
	angle_mult.y = saturate(_sun_direction.y + 0.45);
	angle_mult.z = saturate(-_sun_direction.y + 0.30);
	angle_mult.w = saturate(-_sun_direction.y + 0.60);
	
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1e-5)).xyz;
}

void fragment(){
	vec3 norm = normalize(world_coords);
	
	// Atmospheric Scattering.
	vec2 mu = vec2(dot(_sun_direction, norm), dot(_moon_direction, norm));

	float sr; float sm;
	opticalDepth(norm.y + _atm_params.z, sr, sm);
	vec3 scatter = atmosphericScattering(sr, sm, mu.xy, angle_mult.xyz);
	
	// Sun Disk.
	vec3 sunDisk = disk(norm, _sun_direction, _sun_disk_size) * _sun_disk_color.rgb;
	sunDisk.rgb *= scatter.rgb;
	
	// Moon.
	vec4 moon = texture(_moon_texture, vec2(-moon_coords.x+1.0, moon_coords.y));
	moon.rgb *= _moon_color.rgb;
	moon.rgb = contrastLevel(moon.rgb, _moon_color.a);
	moon *= saturate(moon_coords.w);
	moon.rgb *= moon.a;
	float moonMask = saturate(1.0 - moon.a);
	
	vec4 nearSpace = vec4(0.0);
	nearSpace.rgb += sunDisk.rgb * moonMask;
	nearSpace.rgb += moon.rgb;
	
	// Deep Space.
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
	
	float starsScintillation = textureLod(_noiseTex, UV + (TIME * _stars_scintillation_speed), 0.0).r;
	starsScintillation = mix(1.0, starsScintillation * 1.5, _stars_scintillation);
	
	vec3 starsField = textureLod(_stars_field_texture, deepSpaceUV, 0.0).rgb * _stars_field_color.rgb;
	starsField = saturateRGB(mix(starsField.rgb, starsField.rgb * starsScintillation, _stars_scintillation));
	deepSpace.rgb += starsField.rgb * moonMask;
	deepSpace.rgb *= angle_mult.z;
	ALBEDO = scatter.rgb + nearSpace.rgb + deepSpace.rgb;
	
	// Clouds.
	vec4 clouds = cloudsRender(norm, TIME);
	clouds.a = saturate(clouds.a);
	clouds.rgb *= mix(mix(vec3(1.0), _atm_horizon_light_tint.rgb, angle_mult.x), 
		_atm_night_tint.rgb, angle_mult.w);
	clouds.a = mix(clouds.a, 0.0, saturate((-norm.y + 0.25) * 5.0));
	ALBEDO = mix(ALBEDO, clouds.rgb + mix(vec3(0.0), scatter, _clouds_sky_tint_fade), clouds.a);
	
	ALBEDO = mix(ALBEDO, _ground_color.rgb * scatter, saturate((-norm.y - _atm_params.z)*100.0));
	//ALBEDO = tonemapACES(ALBEDO, _color_correction_params.z, _color_correction_params.y);
	ALBEDO = tonemapPhoto(ALBEDO, _color_correction_params.z, _color_correction_params.y);
	ALBEDO = contrastLevel(ALBEDO, _color_correction_params.x);
}
