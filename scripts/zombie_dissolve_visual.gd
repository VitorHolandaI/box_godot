class_name ZombieDissolveVisual
extends RefCounted

## Visual de desintegracao dos zumbis ao sair do campo de visao. Troca os
## materiais das pecas por um shader de dissolucao compartilhado por cor e
## solta uma nuvem de po quando o corpo comeca a se desfazer.
## Uso:
##   var meshes := ZombieDissolveVisual.prepare_meshes(model)
##   ZombieDissolveVisual.set_dissolve(meshes, 0.5)
##   ZombieDissolveVisual.emit_dust(zombie, Color(0.4, 0.3, 0.2))

const DISSOLVE_SHADER: Shader = preload("res://shaders/zombie_dissolve.gdshader")
const DUST_NODE_NAME := "DissolveDust"
const DUST_AMOUNT := 36
const DUST_LIFETIME := 1.3
const DISSOLVE_PARAMETER := &"dissolve_amount"

# Um material por cor para todo o jogo: 600 zumbis reaproveitam poucas dezenas.
static var _materials_by_color: Dictionary = {}


## Converte todas as GeometryInstance3D do modelo para o shader de dissolucao
## preservando a cor de cada peca, e devolve a lista para animar.
## Uso: _fade_meshes = ZombieDissolveVisual.prepare_meshes($Model)
static func prepare_meshes(model: Node3D) -> Array[GeometryInstance3D]:
	var meshes: Array[GeometryInstance3D] = []
	if model == null:
		push_error("Modelo nulo ao preparar dissolucao; esperado Node3D com malhas do zumbi.")
		return meshes
	for node in model.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		var color := _piece_color(geometry)
		geometry.material_override = material_for_color(color)
		meshes.append(geometry)
	return meshes


## Material compartilhado da cor pedida.
## Uso: var material := ZombieDissolveVisual.material_for_color(Color.RED)
static func material_for_color(color: Color) -> ShaderMaterial:
	var key := color.to_html(false)
	if _materials_by_color.has(key):
		return _materials_by_color[key]
	var material := ShaderMaterial.new()
	material.shader = DISSOLVE_SHADER
	material.set_shader_parameter("albedo_color", color)
	_materials_by_color[key] = material
	return material


## 0 = corpo inteiro, 1 = totalmente desfeito.
## Uso: ZombieDissolveVisual.set_dissolve(_fade_meshes, 1.0 - visual_opacity)
static func set_dissolve(meshes: Array[GeometryInstance3D], amount: float) -> void:
	var clamped := clampf(amount, 0.0, 1.0)
	for geometry in meshes:
		if is_instance_valid(geometry):
			geometry.set_instance_shader_parameter(DISSOLVE_PARAMETER, clamped)


## Nuvem de po que sobe e deriva com o vento a partir do corpo.
## Uso: ZombieDissolveVisual.emit_dust(self, shirt_color)
static func emit_dust(zombie: Node3D, color: Color) -> void:
	var dust := zombie.get_node_or_null(DUST_NODE_NAME) as CPUParticles3D
	if dust == null:
		dust = _create_dust()
		zombie.add_child(dust)
	dust.color = color.darkened(0.35)
	dust.restart()


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
