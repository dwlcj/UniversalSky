tool
class_name SkyDome extends Node
"""========================================================
°                       Universal Sky.
°                   ======================
°
°   Category: Sky.
°   -----------------------------------------------------
°   Description:
°       Skydome Base.
°   -----------------------------------------------------
°   Copyright:
°               J. Cuellar 2020. MIT License.
°                   See: LICENSE Archive.
========================================================"""
#-------------------
# Resources.
#-------------------
# Meshes.
var _sky_mesh:= SphereMesh.new()
var _fog_mesh:= QuadMesh.new()

# Materials.
var _skypass_material:= ShaderMaterial.new()
var _fogpass_material:= ShaderMaterial.new()

# Nodes.
var _sky_node: MeshInstance = null
var _fog_node: MeshInstance = null

#-------------------
# Constants.
#-------------------
const _DEFAULT_ORIGIN:= Vector3(0.0000001, 0.0000001, 0.0000001)


#-------------------
# Engine functions.
#-------------------
func _on_notification(what: int) -> void: pass
func _notification(what: int) -> void:
	_on_notification(what)

func _on_enter_tree() -> void: pass
func _enter_tree() -> void:
	_on_enter_tree()

func _on_exit_tree() -> void: pass
func _exit_tree() -> void:
	_on_exit_tree()

func _on_ready() -> void: pass
func _ready() -> void:
	_on_ready()

func _on_process(delta: float) -> void: pass
func _process(delta: float) -> void:
	_on_process(delta)

