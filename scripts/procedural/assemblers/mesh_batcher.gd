# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name ProceduralMeshBatcher
extends RefCounted

## Junta as caixas estaticas de um edificio num unico MeshInstance3D com uma
## superficie por material. Cada parede/laje/movel era um no proprio e a cidade
## passava de 10 mil draw calls (30 fps na GPU integrada). Portas, luzes,
## suprimentos e colisoes nao sao tocados: so filhos diretos MeshInstance3D com
## malha primitiva e sem script.
## Uso: var merged := ProceduralMeshBatcher.merge_static_meshes(building)

const MERGED_NODE_NAME := "MergedStaticMeshes"


## Devolve quantos MeshInstance3D foram fundidos (0 se nada mudou).
## Uso: ProceduralMeshBatcher.merge_static_meshes(building)
static func merge_static_meshes(body: Node3D) -> int:
	var groups: Dictionary = {}
	var merged_nodes: Array[MeshInstance3D] = []
	for child in body.get_children():
		var instance := child as MeshInstance3D
		if not _is_mergeable(instance):
			continue
		var material := (instance.mesh as PrimitiveMesh).material
		if not groups.has(material):
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			groups[material] = surface
		(groups[material] as SurfaceTool).append_from(instance.mesh, 0, instance.transform)
		merged_nodes.append(instance)
	if merged_nodes.size() < 2:
		return 0
	var merged_mesh := ArrayMesh.new()
	for material in groups:
		var surface := groups[material] as SurfaceTool
		surface.set_material(material)
		surface.commit(merged_mesh)
	var merged := MeshInstance3D.new()
	merged.name = MERGED_NODE_NAME
	merged.mesh = merged_mesh
	body.add_child(merged)
	for node in merged_nodes:
		body.remove_child(node)
		node.free()
	return merged_nodes.size()


static func _is_mergeable(instance: MeshInstance3D) -> bool:
	if instance == null or instance.get_script() != null or not instance.visible:
		return false
	if not instance.mesh is PrimitiveMesh or instance.get_child_count() > 0:
		return false
	return (instance.mesh as PrimitiveMesh).material != null and instance.material_override == null
