# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name VoxelCharacterBuilder
extends RefCounted

## Troca as caixas dos personagens por malhas de voxels (estilo Veloren),
## mantendo os mesmos nos/posicoes (`Model/Head`, `LeftArm/Mesh`, ...) para nao
## quebrar animacao, hitbox nem mutacoes (ZombieMutator).
##
## A cor de cada parte continua vindo do material (pele/camisa/calca/botas):
## as malhas compartilham um material com `vertex_color_use_as_albedo`, e os
## vertices carregam so um sombreado cinza por voxel. Assim pintar o boneco e
## so trocar a cor do material, sem remontar a malha.
##
## Uso: VoxelCharacterBuilder.apply_to_model($Model)

## Lado alvo de um voxel. A grade e ajustada por eixo para a malha fechar
## exatamente no tamanho original da caixa.
const VOXEL_SIZE := 0.085
const ROUND_TRIM := 1

static var _mesh_cache: Dictionary = {}
static var _material: StandardMaterial3D = null
static var _shade_materials: Dictionary = {}


## Aplica a malha voxel nas partes do humanoide e preserva a cor atual de cada
## uma num material com sombreamento por vertice. Uso: apply_to_model($Model)
static func apply_to_model(model: Node3D) -> void:
	if model == null:
		return
	_apply_part(model, "Head", "head")
	_apply_part(model, "Torso", "torso")
	_apply_part(model, "LeftArm/Mesh", "limb")
	_apply_part(model, "RightArm/Mesh", "limb")
	_apply_part(model, "LeftLeg/Mesh", "leg")
	_apply_part(model, "RightLeg/Mesh", "leg")


## Malha voxel de uma peca, compartilhada por todos os personagens do mesmo
## tamanho. Uso: VoxelCharacterBuilder.part_mesh(Vector3(0.54,0.54,0.54), "head")
static func part_mesh(size: Vector3, kind: String) -> ArrayMesh:
	var key := _cache_key(size, kind)
	var cached: Variant = _mesh_cache.get(key)
	if cached != null:
		return cached as ArrayMesh
	var mesh := _build(size, kind)
	_mesh_cache[key] = mesh
	return mesh


## Material compartilhado das malhas (sombreado cinza nos vertices).
static func character_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_material.roughness = 0.9
	return _material


## Material com a cor de uma parte e sombreamento por vertice ligado.
## Uso: VoxelCharacterBuilder.shaded_material(color)
static func shaded_material(color: Color, roughness: float = 0.9) -> StandardMaterial3D:
	var key := "%s|%.2f" % [color.to_html(true), roughness]
	var cached: Variant = _shade_materials.get(key)
	if cached != null:
		return cached as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shade_materials[key] = material
	return material


static func _apply_part(model: Node3D, path: String, kind: String) -> void:
	var node := model.get_node_or_null(path) as MeshInstance3D
	if node == null:
		return
	var original := node.mesh
	if original == null:
		return
	var size := original.get_aabb().size
	if size.length_squared() < 0.0001:
		return
	var color := _part_color(node, original)
	node.mesh = part_mesh(size, kind)
	node.material_override = shaded_material(color)


## Cor atual da parte: material_override, senao o material da caixa original.
static func _part_color(node: MeshInstance3D, original: Mesh) -> Color:
	var material := node.material_override
	if material == null and original.get_surface_count() > 0:
		material = original.surface_get_material(0)
	if material is StandardMaterial3D:
		return (material as StandardMaterial3D).albedo_color
	return Color(0.7, 0.7, 0.7)


static func _cache_key(size: Vector3, kind: String) -> String:
	return "%s|%.3f,%.3f,%.3f" % [kind, size.x, size.y, size.z]


static func _build(size: Vector3, kind: String) -> ArrayMesh:
	var dims := Vector3i(
		maxi(roundi(size.x / VOXEL_SIZE), 2),
		maxi(roundi(size.y / VOXEL_SIZE), 2),
		maxi(roundi(size.z / VOXEL_SIZE), 2)
	)
	var step := size / Vector3(dims)
	var origin := -size * 0.5
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in dims.x:
		for y in dims.y:
			for z in dims.z:
				if not _solid(kind, Vector3i(x, y, z), dims):
					continue
				var corner := origin + Vector3(x, y, z) * step
				for direction in _DIRECTIONS:
					var neighbor := Vector3i(x, y, z) + direction
					if _solid_at(kind, neighbor, dims):
						continue
					_add_face(surface, corner, step, direction, _voxel_shade(x, y, z, direction))
	surface.set_material(character_material())
	return surface.commit()


const _DIRECTIONS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]


## Somente as faces que tocam o ar viram triangulos (interior e descartado).
static func _add_face(surface: SurfaceTool, corner: Vector3, step: Vector3, direction: Vector3i, color: Color) -> void:
	var right := Vector3.ZERO
	var up := Vector3.ZERO
	if direction.x != 0:
		right = Vector3(0.0, 0.0, step.z)
		up = Vector3(0.0, step.y, 0.0)
	elif direction.y != 0:
		right = Vector3(step.x, 0.0, 0.0)
		up = Vector3(0.0, 0.0, step.z)
	else:
		right = Vector3(step.x, 0.0, 0.0)
		up = Vector3(0.0, step.y, 0.0)
	var base := corner
	if direction.x > 0:
		base.x += step.x
	if direction.y > 0:
		base.y += step.y
	if direction.z > 0:
		base.z += step.z
	var normal := Vector3(direction)
	for vertex in [base, base + right, base + right + up, base, base + right + up, base + up]:
		surface.set_color(color)
		surface.set_normal(normal)
		surface.add_vertex(vertex)


## Sombreado por voxel: variacao suave + faces de baixo mais escuras (AO falso).
static func _voxel_shade(x: int, y: int, z: int, direction: Vector3i) -> Color:
	var hash := absi(x * 73856093 + y * 19349663 + z * 83492791) % 1000
	var brightness := 0.82 + 0.18 * (float(hash) / 999.0)
	if direction.y < 0:
		brightness *= 0.78
	elif direction.y == 0:
		brightness *= 0.92
	brightness = clampf(brightness, 0.55, 1.0)
	return Color(brightness, brightness, brightness, 1.0)


static func _solid_at(kind: String, cell: Vector3i, dims: Vector3i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.z < 0 or cell.x >= dims.x or cell.y >= dims.y or cell.z >= dims.z:
		return false
	return _solid(kind, cell, dims)


## Forma de cada peca em voxels: chanfros e afinamentos para nao ser so uma
## caixa subdividida. Uso: interno de _build.
static func _solid(kind: String, cell: Vector3i, dims: Vector3i) -> bool:
	var edge_x := cell.x == 0 or cell.x == dims.x - 1
	var edge_z := cell.z == 0 or cell.z == dims.z - 1
	match kind:
		"head":
			# Topo chanfrado e queixo mais estreito que o cranio.
			if cell.y == dims.y - 1 and (edge_x or edge_z):
				return false
			if cell.y == 0 and edge_x:
				return false
			return true
		"torso":
			# Cantos verticais e cintura chanfrados.
			if edge_x and edge_z:
				return false
			if cell.y == 0 and edge_x:
				return false
			return true
		"limb":
			# Pontas (ombro e mao) arredondadas nos cantos.
			var end := cell.y <= ROUND_TRIM or cell.y >= dims.y - 1 - ROUND_TRIM
			return not (edge_x and edge_z and end)
		"leg":
			# Coluna octogonal, com o pe mais estreito.
			if edge_x and edge_z:
				return false
			if cell.y == 0 and (edge_x or edge_z):
				return false
			return true
	return true
