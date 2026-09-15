class_name BloaterBurstEffect
extends Node3D

## Nuvem verde da explosao do bloater: esfera translucida que cresce ate o raio
## de dano e some. So visual (dano e aplicado por ZombieVariantAbilities).
## Uso:
##   var effect := BloaterBurstEffect.new()
##   get_tree().current_scene.add_child(effect)
##   effect.global_position = zombie.global_position

const DURATION := 0.55
const START_ALPHA := 0.55
const BURST_COLOR := Color(0.55, 0.8, 0.15)

var elapsed := 0.0
var color := BURST_COLOR
var max_radius := ZombieVariantAbilities.BURST_RADIUS
var _material: StandardMaterial3D
var _sphere: MeshInstance3D


## Cor e raio final; o pisao do Tita usa o mesmo efeito, laranja e maior.
## Uso: effect.configure(Color.ORANGE, 6.0)
func configure(effect_color: Color, radius: float) -> void:
	color = effect_color
	max_radius = maxf(radius, 0.5)


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(color, START_ALPHA)
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	mesh.material = _material
	_sphere = MeshInstance3D.new()
	_sphere.mesh = mesh
	_sphere.scale = Vector3.ONE * 0.3
	add_child(_sphere)


func _process(delta: float) -> void:
	elapsed += delta
	var progress := clampf(elapsed / DURATION, 0.0, 1.0)
	_sphere.scale = Vector3.ONE * lerpf(0.3, max_radius, ease(progress, 0.4))
	_material.albedo_color.a = START_ALPHA * (1.0 - progress)
	if progress >= 1.0:
		queue_free()
