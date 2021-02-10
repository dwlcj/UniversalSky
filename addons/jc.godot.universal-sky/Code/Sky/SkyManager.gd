tool extends Node
"""========================================================
°                       Universal Sky.
°                   ======================
°
°   Category: Sky.
°   -----------------------------------------------------
°   Description:
°       Dynamic Skydome.
°   -----------------------------------------------------
°   Copyright:
°               J. Cuellar 2020. MIT License.
°                   See: LICENSE Archive.
========================================================"""


"""
8. Add Atmosphere.
9. Add Fog.
10. Add TOD.
11. Add clouds.
"""

#-------------------
# Resources.
#-------------------
# Shaders. 
var _SKYPASS_SHADER =\
preload("res://addons/jc.godot.universal-sky-common/Shaders/Skypass.shader")

var _FOGPASS_SHADER =\
preload("res://addons/jc.godot.universal-sky-common/Shaders/Fogpass.shader")

var _MOONPASS_SHADER =\
preload("res://addons/jc.godot.universal-sky-common/Shaders/SimpleMoon.shader")

# Textures.
var _DEFAULT_MOON_TEXTURE =\
preload("res://addons/jc.godot.universal-sky-common/Assets/ThirdParty/Graphics/Textures/MoonMap/MoonMap.png")

var _DEFAULT_BACKGROUND_TEXTURE =\
preload("res://addons/jc.godot.universal-sky-common/Assets/ThirdParty/Graphics/Textures/MilkyWay/Milkyway.jpg")

var _DEFAULT_STARS_FIELD_TEXTURE =\
preload("res://addons/jc.godot.universal-sky-common/Assets/ThirdParty/Graphics/Textures/MilkyWay/StarField.jpg")

var _DEFAULT_STARS_FIELD_NOISE_TEXTURE =\
preload("res://addons/jc.godot.universal-sky-common/Assets/MyAssets/Graphics/Textures/noise.jpg")

# Scenes.
var _MOON_RENDER =\
preload("res://addons/jc.godot.universal-sky-common/Scenes/Moon/MoonRender.tscn")

var _DEFAULT_SUN_MOON_LIGHT_CURVE_FADE =\
preload("res://addons/jc.godot.universal-sky-common/Resources/SunMoonLightFade.tres")

# Meshes.
var _sky_mesh:= SphereMesh.new()
var _fog_mesh:= QuadMesh.new()

# Materials.
var _skypass_material:= ShaderMaterial.new()
var _fogpass_material:= ShaderMaterial.new()
var _moonpass_material:= ShaderMaterial.new()

# Instances.
var _sky_node: MeshInstance = null
var _fog_node: MeshInstance = null
var _moon_instance: Viewport
var _moon_viewport_texture: ViewportTexture
var _moon_instance_transform: Spatial
var _moon_instance_mesh: MeshInstance
#-------------------
# Constants.
#-------------------
const _DEFAULT_ORIGIN:= Vector3(0.0000001, 0.0000001, 0.0000001)
const _MAX_EXTRA_CULL_MARGIN:= 16384.0
const _SKY_INSTANCE_NAME:= "SkyNode"
const _FOG_INSTANCE_NAME:= "FogNode"
const _MOON_INSTANCE_NAME:= "MoonRender"
const _SUN_DIR_PARAM:= "_sun_direction"
const _MOON_DIR_PARAM:= "_moon_direction"
const _COLOR_CORRECTION_PARAMS:= "_color_correction_params"

#-------------------
# Properties
#-------------------
# Global.
var _init_properties_ok: bool = false

var sky_visible:= true setget set_sky_visible
func set_sky_visible(value: bool) -> void:
	sky_visible = value
	if not _init_properties_ok: return 
	assert(_sky_node != null)
	_sky_node.visible = value

export var skydome_radius: float = 10.0 setget set_skydome_radius
func set_skydome_radius(value: float) -> void:
	skydome_radius = value
	if not _init_properties_ok: return
	assert(_sky_node != null)
	_sky_node.transform.basis.x = Vector3(value, 0.0, 0.0)
	_sky_node.transform.basis.y = Vector3(0.0, value, 0.0)
	_sky_node.transform.basis.z = Vector3(0.0, 0.0, value)

var contrast_level: float = 0.0 setget set_contrast_level
func set_contrast_level(value: float) -> void:
	contrast_level = value
	set_color_correction_params(value, tonemaping, exposure)

var tonemaping: float = 0.0 setget set_tonemaping
func set_tonemaping(value: float) -> void:
	tonemaping = value
	set_color_correction_params(contrast_level, value, exposure)

var exposure: float = 1.3 setget set_exposure
func set_exposure(value: float) -> void:
	exposure = value
	set_color_correction_params(contrast_level, tonemaping, value)

func set_color_correction_params(contrast: float, tonemap: float, expo: float) -> void:
	var params:= Vector3(contrast, tonemap, expo)
	_skypass_material.set_shader_param(_COLOR_CORRECTION_PARAMS, params)
	_fogpass_material.set_shader_param(_COLOR_CORRECTION_PARAMS, params)

var ground_color:= Color(0.3, 0.3, 0.3, 1.0) setget set_ground_color
func set_ground_color(value: Color) -> void:
	ground_color = value 
	_skypass_material.set_shader_param("_ground_color", value)


# Near Space.
# Sun Coords..
var sun_azimuth: float = 0.0 setget set_sun_azimuth
func set_sun_azimuth(value: float) -> void:
	sun_azimuth = value
	_set_sun_coords(value, sun_altitude)

var sun_altitude: float = -57.0 setget set_sun_altitude
func set_sun_altitude(value: float) -> void:
	sun_altitude = value
	_set_sun_coords(sun_azimuth, value)

var _finish_set_sun_position := false
var _sun_transform := Transform()
func get_sun_transform() -> Transform: 
	return _sun_transform

var sun_direction:= Vector3.ZERO
signal sun_direction_changed(value)
signal sun_transform_changed(value)

# Sun Graphics.
var sun_disk_color:= Color(0.996094, 0.541334, 0.140076, 1.0) setget set_sun_disk_color
func set_sun_disk_color(value: Color) -> void:
	sun_disk_color = value 
	value.r *=  sun_disk_multiplier
	value.g *=  sun_disk_multiplier
	value.b *=  sun_disk_multiplier
	_skypass_material.set_shader_param("_sun_disk_color", value)

var sun_disk_size: float = 0.015 setget set_sun_disk_size
func set_sun_disk_size(value: float) -> void:
	sun_disk_size = value
	_skypass_material.set_shader_param("_sun_disk_size", value)

var sun_disk_multiplier: float = 2.0 setget set_sun_disk_multiplier
func set_sun_disk_multiplier(value: float) -> void:
	sun_disk_multiplier = value 
	set_sun_disk_color(sun_disk_color)


# Sun Light.
var _sun_light_enable: bool = false
var _sun_light_node: DirectionalLight = null
var _sun_light_altitude_mult: float = 0.0
var sun_light_path: NodePath setget set_sun_light_path
func set_sun_light_path(value: NodePath) -> void:
	sun_light_path = value
	if value != null:
		_sun_light_node = get_node_or_null(value)
	_sun_light_enable = true if _sun_light_node != null else false
	set_sun_light_color(sun_light_color)
	set_sun_light_energy(sun_light_energy)
	_set_sun_coords(sun_azimuth, sun_altitude)

var sun_light_color:= Color(0.984314, 0.843137, 0.788235) setget set_sun_light_color
func set_sun_light_color(value: Color) -> void:
	sun_light_color = value
	_set_sun_light_color(value, sun_horizon_light_color)

var sun_horizon_light_color:= Color(1, 0.384314, 0.243137) setget set_sun_horizon_light_color
func set_sun_horizon_light_color(value: Color) -> void:
	sun_horizon_light_color = value
	_set_sun_light_color(sun_light_color, value)

var sun_light_energy: float = 1.0 setget set_sun_light_energy
func set_sun_light_energy(value: float) -> void:
	sun_light_energy = value
	_set_sun_light_intensity()

# Moon.
var moon_azimuth: float setget set_moon_azimuth
func set_moon_azimuth(value: float) -> void:
	moon_azimuth = value
	_set_moon_coords(value, moon_altitude)

var moon_altitude: float setget set_moon_altitude
func set_moon_altitude(value: float) -> void:
	moon_altitude = value
	_set_moon_coords(moon_azimuth, value)


var _finish_set_moon_position := false
var _moon_transform := Transform()
func get_moon_transform() -> Transform:
	return _moon_transform

var moon_direction := Vector3.ZERO
signal moon_direction_changed(value)
signal moon_transform_changed(value)

var moon_color:= Color(1.0, 1.0, 1.0, 0.3) setget set_moon_color
func set_moon_color(value: Color) -> void: 
	moon_color = value
	_skypass_material.set_shader_param("_moon_color", value)

var moon_size: float = 0.09 setget set_moon_size
func set_moon_size(value: float) -> void:
	moon_size = value
	_skypass_material.set_shader_param("_moon_size", value)

var enable_set_moon_texture: bool = false setget set_enable_set_moon_texture
func set_enable_set_moon_texture(value: bool) -> void:
	enable_set_moon_texture = value
	if not value:
		set_moon_texture(_DEFAULT_MOON_TEXTURE)
	
	property_list_changed_notify()

var moon_texture: Texture = null setget set_moon_texture
func set_moon_texture(value: Texture) -> void:
	moon_texture = value
	_moonpass_material.set_shader_param("_texture", value)
	

var moon_texture_size: int = 2 setget set_moon_texture_size
func set_moon_texture_size(value: int) -> void:
	moon_texture_size = value
	if not _init_properties_ok: return
	assert(_moon_instance != null)
	match value:
		0: _moon_instance.size = Vector2(64, 64)
		1: _moon_instance.size = Vector2(128, 128)
		2: _moon_instance.size = Vector2(256, 256)
		3: _moon_instance.size = Vector2(512, 512)
		4: _moon_instance.size = Vector2(1024, 1024)
		
	_set_moon_viewport_texture()

# Moon Light
var _moon_light_node: DirectionalLight = null
var _moon_light_enable: bool = false
var _moon_light_altitude_mult: float = 0.0

var moon_light_path: NodePath setget set_moon_light_path
func set_moon_light_path(value: NodePath) -> void:
	moon_light_path = value 
	if value != null:
		_moon_light_node = get_node_or_null(value)
	_moon_light_enable = true if _moon_light_node != null else false
	
	set_moon_light_color(moon_light_color)
	set_moon_light_energy(moon_light_energy)
	_set_moon_coords(moon_azimuth, moon_altitude)

var moon_light_color:= Color(0.572549, 0.776471, 0.956863) setget set_moon_light_color
func set_moon_light_color(value: Color) -> void:
	moon_light_color = value
	if _moon_light_enable:
		_moon_light_node.light_color = value

var moon_light_energy: float = 0.3 setget set_moon_light_energy
func set_moon_light_energy(value: float) -> void:
	moon_light_energy = value
	_set_moon_light_intensity()

var use_custom_sun_moon_light_fade: bool = false setget set_use_custom_sun_moon_light_fade
func set_use_custom_sun_moon_light_fade(value: bool) -> void:
	use_custom_sun_moon_light_fade = value
	if not value:
		set_sun_moon_light_fade(_DEFAULT_SUN_MOON_LIGHT_CURVE_FADE)
	
	property_list_changed_notify()

var sun_moon_light_fade: Curve setget set_sun_moon_light_fade
func set_sun_moon_light_fade(value: Curve) -> void:
	sun_moon_light_fade = value
	_set_moon_light_intensity()

signal is_day(value)

#====================- Deep Space -====================#
var _deep_space_basis := Basis()

var deep_space_euler: Vector3 = Vector3.ZERO setget set_deep_space_euler
func set_deep_space_euler(value: Vector3) -> void:
	deep_space_euler  = value
	_deep_space_basis = Basis(value)
	deep_space_quat   = _deep_space_basis.get_rotation_quat()
	_set_deep_space_matrix()

var deep_space_quat: Quat = Quat.IDENTITY setget set_deep_space_quat
func set_deep_space_quat(value: Quat) -> void:
	deep_space_quat   = value 
	_deep_space_basis = Basis(value)
	deep_space_euler  = _deep_space_basis.get_euler()
	_set_deep_space_matrix()

# Background.
var background_color: Color = Color(0.19, 0.19, 0.19, 0.3) setget set_background_color
func set_background_color(value: Color) -> void:
	background_color = value 
	_skypass_material.set_shader_param("_background_color", value)

var enable_set_background_texture: bool = false setget set_enable_set_background_texture
func set_enable_set_background_texture(value: bool) -> void:
	enable_set_background_texture = value
	if not value:
		set_background_texture(_DEFAULT_BACKGROUND_TEXTURE)
	
	property_list_changed_notify()

var background_texture: Texture = null setget set_background_texture
func set_background_texture(value: Texture) -> void:
	background_texture = value
	_skypass_material.set_shader_param("_background_texture", value)

# Stars Field. 
var stars_field_color: Color = Color(1.0, 1.0, 1.0, 1.0) setget set_stars_field_color
func set_stars_field_color(value: Color) -> void:
	stars_field_color = value
	_skypass_material.set_shader_param("_stars_field_color", value)

var enable_set_stars_field_texture: bool = false setget set_enable_set_stars_field_texture
func set_enable_set_stars_field_texture(value: bool) -> void:
	enable_set_stars_field_texture = value
	if not value:
		set_stars_field_texture(_DEFAULT_STARS_FIELD_TEXTURE)
	
	property_list_changed_notify()

var stars_field_texture: Texture = null setget set_stars_field_texture
func set_stars_field_texture(value: Texture) -> void:
	stars_field_texture = value 
	_skypass_material.set_shader_param("_stars_field_texture", value)

var stars_scintillation: float = 1.0 setget set_stars_scintillation
func set_stars_scintillation(value: float) -> void:
	stars_scintillation = value 
	_skypass_material.set_shader_param("_stars_scintillation", value)

var stars_scintillation_speed: float = 0.024 setget set_stars_scintillation_speed
func set_stars_scintillation_speed(value: float) -> void:
	stars_scintillation_speed = value 
	_skypass_material.set_shader_param("_stars_scintillation_speed", value)

# Fog.
var fog_visible:= true setget set_fog_visible
func set_fog_visible(value: bool) -> void:
	fog_visible = value 
	if not _init_properties_ok: return
	assert(_fog_node != null)
	_fog_node.visible = value
	
func _init():
	_init_resources()
	_sky_node = get_node_or_null(_SKY_INSTANCE_NAME)
	_fog_node = get_node_or_null(_FOG_INSTANCE_NAME)
	_moon_instance = get_node_or_null(_MOON_INSTANCE_NAME)
	if _sky_node != null && _fog_node != null && _moon_instance != null:
		_init_properties_ok = true
		_init_mesh_instances()
	
	_skypass_material.set_shader_param("_noise_tex", _DEFAULT_STARS_FIELD_NOISE_TEXTURE)

func _notification(what: int) -> void:
	pass

func _enter_tree() -> void:
	_build_dome()
	init_properties()
	_set_nodes_owner() # Debug.

func _exit_tree() -> void:
	pass


func _ready():
	#var all_child_nodes = get_children()
	#print(all_child_nodes)
	_set_sun_coords(sun_azimuth, sun_altitude)
	_set_moon_coords(moon_azimuth, moon_altitude)
	#set_sun_light_path(sun_light_path)
	#set_moon_light_path(moon_light_path)
	pass

func init_properties() -> void:
	_init_properties_ok = true
	set_sky_visible(sky_visible)
	set_skydome_radius(skydome_radius)
	set_contrast_level(contrast_level)
	set_tonemaping(tonemaping)
	set_exposure(exposure)
	set_ground_color(ground_color)
	set_use_custom_sun_moon_light_fade(use_custom_sun_moon_light_fade)
	
	set_sun_azimuth(sun_azimuth)
	set_sun_altitude(sun_altitude)
	set_sun_disk_color(sun_disk_color)
	set_sun_disk_multiplier(sun_disk_multiplier)
	set_sun_disk_size(sun_disk_size)
	set_sun_light_path(sun_light_path)
	set_sun_light_color(sun_light_color)
	set_sun_horizon_light_color(sun_horizon_light_color)
	set_sun_light_energy(sun_light_energy)
	
	set_moon_altitude(moon_altitude)
	set_moon_azimuth(moon_azimuth)
	
	set_moon_color(moon_color)
	set_moon_size(moon_size)
	set_enable_set_moon_texture(enable_set_moon_texture)
	if enable_set_moon_texture:
		set_moon_texture(moon_texture)
	
	set_moon_texture_size(moon_texture_size)
	set_moon_light_path(moon_light_path)
	set_moon_light_color(moon_light_color)
	set_moon_light_energy(moon_light_energy)
	
	set_deep_space_euler(deep_space_euler)
	set_background_color(background_color)
	set_enable_set_background_texture(enable_set_background_texture)
	if enable_set_background_texture:
		set_background_texture(background_texture)
	
	set_stars_field_color(stars_field_color)
	set_enable_set_stars_field_texture(enable_set_stars_field_texture)
	if enable_set_stars_field_texture:
		set_stars_field_texture(stars_field_texture)
	
	set_stars_scintillation(stars_scintillation)
	set_stars_scintillation_speed(stars_scintillation_speed)
	
	
	set_fog_visible(fog_visible)


func _init_resources() -> void:
	_sky_mesh.radial_segments = 32
	_sky_mesh.rings = 16
	_skypass_material.shader = _SKYPASS_SHADER
	_skypass_material.setup_local_to_scene()
	_skypass_material.render_priority = -125
	
	_fog_mesh.size = Vector2(2.0, 2.0);
	_fogpass_material.shader = _FOGPASS_SHADER
	_fogpass_material.render_priority = 123;
	
	_moonpass_material.shader = _MOONPASS_SHADER
	_moonpass_material.setup_local_to_scene()

func _build_dome() -> void:
	# Skydome.
	_sky_node = get_node_or_null(_SKY_INSTANCE_NAME)
	if _sky_node == null:
		_sky_node = MeshInstance.new()
		_sky_node.name = _SKY_INSTANCE_NAME
		self.add_child(_sky_node)
	
	# Fog.
	_fog_node = get_node_or_null(_FOG_INSTANCE_NAME)
	if _fog_node == null:
		_fog_node = MeshInstance.new()
		_fog_node.name = _FOG_INSTANCE_NAME
		self.add_child(_fog_node)
	
	# Moon.
	_moon_instance = get_node_or_null(_MOON_INSTANCE_NAME)
	if _moon_instance == null:
		_moon_instance = _MOON_RENDER.instance() 
		self.add_child(_moon_instance)
	
	_init_mesh_instances()
	
func _init_mesh_instances() -> void:
	assert(_sky_node != null)
	_sky_node.transform.origin = _DEFAULT_ORIGIN
	_sky_node.mesh = _sky_mesh
	_sky_node.extra_cull_margin = _MAX_EXTRA_CULL_MARGIN
	_sky_node.cast_shadow = _sky_node.SHADOW_CASTING_SETTING_OFF
	_sky_node.material_override = _skypass_material
	
	assert(_fog_node != null)
	_fog_node.transform.origin = Vector3.ZERO
	_fog_node.mesh = _fog_mesh 
	_fog_node.extra_cull_margin = _MAX_EXTRA_CULL_MARGIN
	_fog_node.cast_shadow = _sky_node.SHADOW_CASTING_SETTING_OFF
	_fog_node.material_override = _fogpass_material
	
	assert(_moon_instance != null)
	_moon_instance_transform = _moon_instance.get_node_or_null("MoonTransform")
	_moon_instance_mesh = _moon_instance_transform.get_node_or_null("Camera/Mesh")
	_moon_instance_mesh.material_override = _moonpass_material

func _set_nodes_owner() -> void: # Debug.
	_sky_node.owner = self.get_tree().edited_scene_root
	_fog_node.owner = self.get_tree().edited_scene_root
	_moon_instance.owner = self.get_tree().edited_scene_root

func _set_sun_coords(azimuth: float, altitude: float) -> void:
	if not _init_properties_ok: return
	assert(_sky_node != null)
	azimuth = deg2rad(azimuth); altitude = deg2rad(altitude)
	_finish_set_sun_position = false
	if not _finish_set_sun_position:
		_sun_transform.origin = SkyMath.to_orbit(altitude, azimuth)
		_finish_set_sun_position = true
	if _finish_set_sun_position:
		_sun_transform = _sun_transform.looking_at(_sky_node.transform.origin, Vector3(0.0, 1.0, 0.0))
		
	emit_signal("sun_transform_changed", _sun_transform)
	
	# Sun direction.
	sun_direction = _sun_transform.origin - _sky_node.transform.origin
	emit_signal("sun_direction_changed", sun_direction)
	_set_day_state(altitude)
	
	_skypass_material.set_shader_param(_SUN_DIR_PARAM, sun_direction)
	_fogpass_material.set_shader_param(_SUN_DIR_PARAM, sun_direction)
	_moonpass_material.set_shader_param(_SUN_DIR_PARAM, sun_direction)
	
	if _sun_light_enable: 
		_sun_light_node.transform.origin = _sun_transform.origin
		_sun_light_node.transform.basis = _sun_transform.basis
	_sun_light_altitude_mult = SkyMath.saturate(sun_direction.y + 0.25)
		
	_set_sun_light_color(sun_light_color, sun_horizon_light_color)
	_set_sun_light_intensity()
	_set_moon_light_intensity()
	
	#_set_night_intensity 


func _set_moon_coords(azimuth: float, altitude: float) -> void:
	if not _init_properties_ok: return
	assert(_sky_node != null)
	azimuth = deg2rad(azimuth); altitude = deg2rad(altitude)
	_finish_set_moon_position = false
	if not _finish_set_moon_position:
		_moon_transform.origin = SkyMath.to_orbit(altitude, azimuth, 1.0)
		_finish_set_moon_position = true
	if _finish_set_moon_position:
		_moon_transform = _moon_transform.looking_at(_sky_node.transform.origin, Vector3(-1.0, 0.0, 0.0))
	
	emit_signal("moon_transform_changed", _moon_transform)
	
	# Moon Direction.
	moon_direction = _moon_transform.origin - _sky_node.transform.origin
	emit_signal("moon_direction_changed", moon_direction)
	
	_skypass_material.set_shader_param(_MOON_DIR_PARAM, moon_direction)
	_skypass_material.set_shader_param("_moon_matrix", _moon_transform.basis)
	_fogpass_material.set_shader_param(_MOON_DIR_PARAM, moon_direction)
	_moonpass_material.set_shader_param(_SUN_DIR_PARAM, sun_direction)
	
	_moon_instance_transform.transform.origin = _moon_transform.origin
	_moon_instance_transform.transform.basis = _moon_transform.basis
	
	if _moon_light_enable:
		_moon_light_node.transform.origin = _moon_transform.origin 
		_moon_light_node.transform.basis = _moon_transform.basis
	_moon_light_altitude_mult = SkyMath.saturate(moon_direction.y + 0.30)
	set_moon_light_color(moon_light_color)
	_set_moon_light_intensity()
	
	#_set_night_intensity()


func _set_moon_viewport_texture() -> void:
	_moon_viewport_texture = _moon_instance.get_texture()
	_skypass_material.set_shader_param("_moon_texture", _moon_viewport_texture)

func _set_day_state(value: float, threshold: float = 1.80) -> void:
	if abs(value) > threshold:
		emit_signal("is_day", false)
		set_light_enable(false)
	else:
		emit_signal("is_day", true)
		set_light_enable(true)

func set_light_enable(value: bool) -> void:
	if _sun_light_enable:
		_sun_light_node.visible = value
	if _moon_light_enable:
		_moon_light_node.visible = !value;

func _set_sun_light_color(dayCol: Color, horizonCol: Color) -> void:
	if _sun_light_enable:
		_sun_light_node.light_color = lerp(horizonCol, dayCol, _sun_light_altitude_mult)

func _set_sun_light_intensity() -> void:
	if _sun_light_enable:
		_sun_light_node.light_energy = lerp(0.0, sun_light_energy, _sun_light_altitude_mult)

func _set_moon_light_intensity() -> void:
	if _moon_light_enable:
		var l: float = lerp(0.0, moon_light_energy, _moon_light_altitude_mult)
		var curveFade = (1.0 - sun_direction.y) * 0.5
		_moon_light_node.light_energy = l * sun_moon_light_fade.interpolate(curveFade)

func _set_deep_space_matrix() -> void:
	_skypass_material.set_shader_param("_deep_space_matrix", _deep_space_basis)

func _get_property_list() -> Array:
	var ret: Array
	ret.push_back({name = "Dynamic Sky", type=TYPE_NIL, usage=PROPERTY_USAGE_CATEGORY})
	
	# Global.
	ret.push_back({name = "Global", type=TYPE_NIL, usage=PROPERTY_USAGE_GROUP})
	ret.push_back({name = "sky_visible", type = TYPE_BOOL})
	ret.push_back({name = "skydome_radius", type = TYPE_REAL})
	ret.push_back({name = "contrast_level", type=TYPE_REAL, hint=PROPERTY_HINT_RANGE, hint_string="0.0, 1.0"})
	ret.push_back({name = "tonemaping", type=TYPE_REAL, hint=PROPERTY_HINT_RANGE, hint_string="0.0, 1.0"})
	ret.push_back({name = "exposure", type = TYPE_REAL})
	ret.push_back({name = "ground_color", type = TYPE_COLOR})
	ret.push_back({name = "use_custom_sun_moon_light_fade", type=TYPE_BOOL})
	if use_custom_sun_moon_light_fade:
		ret.push_back({name = "sun_moon_light_fade", type=TYPE_OBJECT, hint=PROPERTY_HINT_RESOURCE_TYPE, hint_string="Curve"})
	
	# Sun. 
	ret.push_back({name = "Sun", type=TYPE_NIL, usage=PROPERTY_USAGE_GROUP})
	ret.push_back({name = "sun_altitude", type=TYPE_REAL, hint=PROPERTY_HINT_RANGE, hint_string="-180.0, 180.0"})
	ret.push_back({name = "sun_azimuth", type=TYPE_REAL, hint=PROPERTY_HINT_RANGE, hint_string="-180, 180"})
	ret.push_back({name = "sun_disk_color", type=TYPE_COLOR})
	ret.push_back({name = "sun_disk_multiplier", type=TYPE_REAL, hint=PROPERTY_HINT_RANGE, hint_string="0.0, 2.0"})
	ret.push_back({name = "sun_disk_size", type=TYPE_REAL, hint=PROPERTY_HINT_RANGE, hint_string="0.0, 1.0"})
	ret.push_back({name = "sun_light_path", type=TYPE_NODE_PATH})
	ret.push_back({name = "sun_light_color", type=TYPE_COLOR})
	ret.push_back({name = "sun_horizon_light_color", type=TYPE_COLOR})
	ret.push_back({name = "sun_light_energy", type=TYPE_REAL, hint=PROPERTY_HINT_RANGE, hint_string="0.0, 8.0"})
	
	# Moon.
	ret.push_back({name = "Moon", type=TYPE_NIL, usage=PROPERTY_USAGE_GROUP})
	ret.push_back({name = "moon_altitude", type=TYPE_REAL, hint=PROPERTY_HINT_RANGE, hint_string="-180.0, 180.0"})
	ret.push_back({name = "moon_azimuth", type=TYPE_REAL, hint=PROPERTY_HINT_RANGE, hint_string="-180.0, 180.0"})
	ret.push_back({name = "moon_color", type=TYPE_COLOR})
	ret.push_back({name = "moon_size", type=TYPE_REAL, hint=PROPERTY_HINT_RANGE, hint_string="0.0, 1.0"})
	ret.push_back({name = "moon_texture_size", type=TYPE_INT, hint=PROPERTY_HINT_ENUM, hint_string="64, 128, 256, 512, 1024"})
	ret.push_back({name = "enable_set_moon_texture", type=TYPE_BOOL})
	if enable_set_moon_texture:
		ret.push_back({name = "moon_texture", type=TYPE_OBJECT, hint=PROPERTY_HINT_FILE, hint_string="Texture"})
	
	ret.push_back({name = "moon_light_path", type=TYPE_NODE_PATH})
	ret.push_back({name = "moon_light_color", type=TYPE_COLOR})
	ret.push_back({name = "moon_light_energy", type=TYPE_REAL, hint=PROPERTY_HINT_RANGE, hint_string="0.0, 8.0"})
	
	# Deep Space.
	ret.push_back({name = "DeepSpace", type=TYPE_NIL, usage=PROPERTY_USAGE_GROUP})
	ret.push_back({name = "deep_space_euler", type=TYPE_VECTOR3})
	ret.push_back({name = "background_color", type=TYPE_COLOR})
	ret.push_back({name = "enable_set_background_texture", type=TYPE_BOOL})
	if enable_set_background_texture:
		ret.push_back({name = "background_texture", type=TYPE_OBJECT, hint=PROPERTY_HINT_FILE, hint_string="Texture"})
	
	ret.push_back({name = "stars_field_color", type=TYPE_COLOR})
	ret.push_back({name = "enable_set_stars_field_texture", type=TYPE_BOOL})
	if enable_set_stars_field_texture:
		ret.push_back({name = "stars_field_texture", type=TYPE_OBJECT, hint=PROPERTY_HINT_FILE, hint_string="Texture"})
	
	ret.push_back({name = "stars_scintillation", type=TYPE_REAL, hint=PROPERTY_HINT_RANGE, hint_string="0.0, 1.0"})
	ret.push_back({name = "stars_scintillation_speed", type=TYPE_REAL, hint=PROPERTY_HINT_RANGE, hint_string="0.0, 0.1"})
	
	# Fog. 
	ret.push_back({name = "Fog", type=TYPE_NIL, usage=PROPERTY_USAGE_GROUP})
	ret.push_back({name = "fog_visible", type=TYPE_BOOL})
	
	return ret;




