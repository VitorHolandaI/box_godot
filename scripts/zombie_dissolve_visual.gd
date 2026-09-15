class_name ZombieDissolveVisual
extends RefCounted

## Visual de desintegracao de um zumbi ao sair do campo de visao. Enquanto o
## corpo esta inteiro as pecas usam materiais compartilhados por cor (poucas
## dezenas para o jogo todo); so durante o sumiço o zumbi troca para copias
## proprias, onde o uniform `dissolve_amount` pode variar sem afetar os outros.
## Uso:
##   var dissolve := ZombieDissolveVisual.new($Model)
##   dissolve.set_dissolve(0.5)
##   ZombieDissolveVisual.emit_dust(zombie, Color(0.4, 0.3, 0.2))

const DISSOLVE_SHADER: Shader = preload("res://shaders/zombie_dissolve.gdshader")
const DUST_NODE_NAME := "DissolveDust"
const DUST_AMOUNT := 12
const DUST_LIFETIME := 1.3
const DISSOLVE_PARAMETER := &"dissolve_amount"

static var _shared_by_color: Dictionary = {}

var meshes: Array[GeometryInstance3D] = []
var _shared_materials: Array[ShaderMaterial] = []
var _own_by_color: Dictionary = {}
var _using_own_materials := false


## Converte as pecas do modelo para o shader de dissolucao preservando a cor.
## Uso: var dissolve := ZombieDissolveVisual.new(model)
func _init(model: Node3D) -> void:
	if model == null:
		push_error("Modelo nulo ao preparar dissolucao; esperado Node3D com malhas do zumbi.")
		return
	for node in model.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		var shared := material_for_color(_piece_color(geometry))
		geometry.material_override = shared
		meshes.append(geometry)
		_shared_materials.append(shared)


## Material compartilhado (inteiro, dissolve 0) da cor pedida.
## Uso: var material := ZombieDissolveVisual.material_for_color(Color.RED)
static func material_for_color(color: Color) -> ShaderMaterial:
	var key := color.to_html(false)
	if _shared_by_color.has(key):
		return _shared_by_color[key]
	var material := ShaderMaterial.new()
	material.shader = DISSOLVE_SHADER
	material.set_shader_parameter("albedo_color", color)
	material.set_shader_parameter(DISSOLVE_PARAMETER, 0.0)
	_shared_by_color[key] = material
	return material


## 0 = corpo inteiro (volta aos materiais compartilhados), 1 = desfeito.
## Uso: dissolve.set_dissolve(1.0 - visual_opacity)
func set_dissolve(amount: float) -> void:
	var clamped := clampf(amount, 0.0, 1.0)
	if clamped <= 0.0:
		_assign_shared_materials()
		return
	_assign_own_materials()
	for material in _own_by_color.values():
		(material as ShaderMaterial).set_shader_parameter(DISSOLVE_PARAMETER, clamped)


func is_using_own_materials() -> bool:
	return _using_own_materials


## Nuvem de po que sobe e deriva com o vento a partir do corpo.
## Uso: ZombieDissolveVisual.emit_dust(self, shirt_color)
static func emit_dust(zombie: Node3D, color: Color) -> void:
	var dust := zombie.get_node_or_null(DUST_NODE_NAME) as CPUParticles3D
	if dust == null:
		dust = _create_dust()
		zombie.add_child(dust)
	dust.color = color.darkened(0.35)
	dust.restart()


func _assign_shared_materials() -> void:
	if not _using_own_materials:
		return
	for index in meshes.size():
		if is_instance_valid(meshes[index]):
			meshes[index].material_override = _shared_materials[index]
	_using_own_materials = false


func _assign_own_materials() -> void:
	if _using_own_materials:
		return
	for index in meshes.size():
		var shared := _shared_materials[index]
		if not _own_by_color.has(shared):
			_own_by_color[shared] = shared.duplicate()
		if is_instance_valid(meshes[index]):
			meshes[index].material_override = _own_by_color[shared]
	_using_own_materials = true


static func _create_dust() -> CPUParticles3D:
	var dust := CPUParticles3D.new()
	dust.name = DUST_NODE_NAME
	dust.emitting = false
	dust.one_shot = true
	dust.amount = DUST_AMOUNT
	dust.lifetime = DUST_LIFETIME
	dust.explosiveness = 0.35
	dust.local_coords = false
	dust.position = Vector3(0.0, 0.6, 0.0)
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(0.35, 0.8, 0.25)
	dust.direction = Vector3(0.6, 1.0, 0.2)
	dust.spread = 35.0
	dust.initial_velocity_min = 0.6
	dust.initial_velocity_max = 1.6
	dust.gravity = Vector3(0.5, 0.9, 0.0)
	dust.damping_min = 0.4
	dust.damping_max = 1.2
	dust.scale_amount_min = 0.5
	dust.scale_amount_max = 1.0
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	dust.scale_amount_curve = shrink
	var grain := BoxMesh.new()
	grain.size = Vector3(0.06, 0.06, 0.06)
	var grain_material := StandardMaterial3D.new()
	grain_material.vertex_color_use_as_albedo = true
	grain_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grain.material = grain_material
	dust.mesh = grain
	return dust


static func _piece_color(geometry: GeometryInstance3D) -> Color:
	var override_material := geometry.material_override as BaseMaterial3D
	if override_material != null:
		return override_material.albedo_color
	var shader_override := geometry.material_override as ShaderMaterial
	if shader_override != null and shader_override.shader == DISSOLVE_SHADER:
		return shader_override.get_shader_parameter("albedo_color")
	var mesh_instance := geometry as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null and mesh_instance.mesh.get_surface_count() > 0:
		var surface_material := mesh_instance.mesh.surface_get_material(0) as BaseMaterial3D
		if surface_material != null:
			return surface_material.albedo_color
	return Color(0.5, 0.5, 0.5)
