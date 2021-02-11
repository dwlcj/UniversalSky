/*========================================================
°                       Universal Sky.
°                   ======================
°
°   Category: Sky.
°   -----------------------------------------------------
°   Description:
°        Atmospheric Scattering Fog.
°   -----------------------------------------------------
°   Copyright:
°               J. Cuellar 2020. MIT License.
°                   See: LICENSE Archive.
========================================================*/
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_always, unshaded;

uniform float _density;
uniform vec3 _sun_direction;
uniform vec3 _moon_direction;

// x = contrast, y = tonemap level, exposure.
uniform vec3 _color_correction_params; 

// Atmospheric Scattering.
uniform float _atm_darkness;
uniform float _atm_sun_intensity;
uniform vec4 _atm_day_tint: hint_color;
uniform vec4 _atm_horizon_light_tint: hint_color;
uniform vec4 _atm_night_tint: hint_color;

// x = ymultiplier, y = down offset, z = horizon offset.
uniform vec3 _atm_params = vec3(1.0, 0.0, 0.0); 

uniform vec4 _atm_sun_mie_tint: hint_color;
uniform float _atm_sun_mie_intensity;
uniform vec4 _atm_moon_mie_tint: hint_color;
uniform float _atm_moon_mie_intensity;
uniform vec3 _atm_beta_ray;
uniform vec3 _atm_beta_mie;
uniform vec3 _atm_sun_partial_mie_phase;
uniform vec3 _atm_moon_partial_mie_phase;
uniform float _atm_rayleigh_zenith_length;
uniform float _atm_mie_zenith_length;
uniform vec2 _depth_params;

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

float beerLaw(float d, float factor){
	return exp(-d * factor);
}

float rayleighPhase(float mu){
	return k3PI16 * (1.0 + mu * mu);
}

float miePhase(float mu, vec3 partial){
	return kPI4 * (partial.x) * (pow(partial.y - partial.z * mu, -1.5));
}

void opticalDepth(float y, out float sr, out float sm){
	y = max(0.03, y + 0.03) + _atm_params.y;
	y = 1.0 / (y * _atm_params.x);
	sr = y * _atm_rayleigh_zenith_length;
	sm = y * _atm_mie_zenith_length;
}

void _opticalDepth(float y, out float sr, out float sm)
{
	y = max(0.0, y);
	y = saturate(y * _atm_params.x);
	
	float zenith = acos(y);
	zenith = cos(zenith) + 0.15 * pow(93.885 - ((zenith * 180.0) / kPI), -1.253);
	zenith = 1.0 / (zenith + _atm_params.y);
	
	sr = zenith * _atm_rayleigh_zenith_length;
	sm = zenith * _atm_mie_zenith_length;
}

vec3 atmosphericScattering(float sr, float sm, vec2 mu, vec3 mult, float depth){
	vec3 betaMie = _atm_beta_mie;
	vec3 betaRay = _atm_beta_ray;
	
	vec3 extcFactor = saturateRGB(exp(-(betaRay * sr + betaMie * sm)));
	vec3 finalExtcFactor = mix(1.0 - extcFactor, (1.0 - extcFactor) * extcFactor, mult.x);
	
	float rayleighPhase = rayleighPhase(mu.x);
	vec3 BRT = betaRay * rayleighPhase * saturate(depth * _depth_params.x);
	vec3 BMT = betaMie * miePhase(mu.x, _atm_sun_partial_mie_phase) * saturate(depth * _depth_params.y);
	BMT *= _atm_sun_mie_intensity * _atm_sun_mie_tint.rgb;
	
	vec3 BRMT = (BRT + BMT) / (betaRay + betaMie);
	vec3 scatter = _atm_sun_intensity * (BRMT * finalExtcFactor) * _atm_day_tint.rgb * mult.y;
	scatter = mix(scatter, scatter * (1.0 - extcFactor), _atm_darkness);
	
	vec3 lcol = mix(_atm_day_tint.rgb, _atm_horizon_light_tint.rgb, mult.x);
	vec3 nscatter = (1.0 - extcFactor) * _atm_night_tint.rgb;
	nscatter += miePhase(mu.y, _atm_moon_partial_mie_phase) * 
		_atm_moon_mie_tint.rgb * _atm_moon_mie_intensity * 0.001;
	return (scatter * lcol) + nscatter;
}

varying mat4 camera;
varying vec4 angle_mult;

void vertex(){
	POSITION = vec4(VERTEX.xy, -1.0, 1.0);
	angle_mult.x = saturate(1.0 - _sun_direction.y);
	angle_mult.y = saturate(_sun_direction.y + 0.45);
	angle_mult.z = saturate(-_sun_direction.y + 0.30);
	angle_mult.w = saturate(-_sun_direction.y + 0.60);
	camera = CAMERA_MATRIX;
}

void fragment(){
	float depthRaw = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV, depthRaw) * 2.0 - 1.0;
	
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
  	view.xyz /= view.w;
	
	vec3 ray = normalize(view.xyz);
	ray = (camera * vec4(ray.xyz, 0.0)).xyz;

	float linearDepth = -view.z;
	float fogFactor = 1.0 - beerLaw(linearDepth, _density);
	
	vec2 mu = vec2(dot(_sun_direction, ray), dot(_moon_direction, ray));
	float sr; float sm; opticalDepth(ray.y + _atm_params.z, sr, sm);
	vec3 scatter = atmosphericScattering(sr, sm, mu.xy, angle_mult.xyz, linearDepth);
	
	vec3 tint = scatter; 
	vec4 fogColor = vec4(tint.rgb, 1.0) * fogFactor;
	fogColor = vec4(saturateRGB(fogColor.rgb), saturate(fogColor.a));
	
	if(depthRaw > 0.999999){
		fogColor = vec4(0.0);
	}
	fogColor.rgb = tonemapPhoto(fogColor.rgb, _color_correction_params.z, _color_correction_params.y);
	fogColor.rgb = contrastLevel(fogColor.rgb, _color_correction_params.x);
	
	ALBEDO = fogColor.rgb;
	ALPHA = fogColor.a;
}

