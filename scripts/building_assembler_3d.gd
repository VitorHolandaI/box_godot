# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name BuildingAssembler3D
extends RefCounted

## Montador procedural de lotes e edificios utilizando modelos 3D CC0 (Kenney e KayKit).
## Randomiza tipos de construcoes, toldos, cercas, calcadas e acessorios urbanos.
## Uso:
##   var lot_node := BuildingAssembler3D.build_lot("house", rng)

const AMMO_PICKUP_SCENE: PackedScene = preload("res://scenes/ammo_pickup.tscn")
const ModularBuilder: GDScript = preload("res://scripts/modular_building_builder.gd")

const SUBURBAN_HOUSES: Array[String] = [
	"res://assets/models/kenney_suburban/building-type-a.glb",
	"res://assets/models/kenney_suburban/building-type-b.glb",
	"res://assets/models/kenney_suburban/building-type-c.glb",
	"res://assets/models/kenney_suburban/building-type-d.glb",
	"res://assets/models/kenney_suburban/building-type-e.glb",
	"res://assets/models/kenney_suburban/building-type-f.glb",
	"res://assets/models/kenney_suburban/building-type-g.glb",
	"res://assets/models/kenney_suburban/building-type-h.glb",
	"res://assets/models/kenney_suburban/building-type-i.glb",
	"res://assets/models/kenney_suburban/building-type-j.glb",
	"res://assets/models/kenney_suburban/building-type-k.glb",
	"res://assets/models/kenney_suburban/building-type-l.glb",
	"res://assets/models/kenney_suburban/building-type-m.glb",
	"res://assets/models/kenney_suburban/building-type-n.glb",
	"res://assets/models/kenney_suburban/building-type-o.glb",
	"res://assets/models/kenney_suburban/building-type-p.glb",
	"res://assets/models/kenney_suburban/building-type-q.glb",
	"res://assets/models/kenney_suburban/building-type-r.glb",
	"res://assets/models/kenney_suburban/building-type-s.glb",
	"res://assets/models/kenney_suburban/building-type-t.glb",
	"res://assets/models/kenney_suburban/building-type-u.glb",
]

const COMMERCIAL_BUILDINGS: Array[String] = [
	"res://assets/models/kenney_commercial/building-a.glb",
	"res://assets/models/kenney_commercial/building-b.glb",
	"res://assets/models/kenney_commercial/building-c.glb",
	"res://assets/models/kenney_commercial/building-d.glb",
	"res://assets/models/kenney_commercial/building-e.glb",
	"res://assets/models/kenney_commercial/building-f.glb",
	"res://assets/models/kenney_commercial/building-g.glb",
	"res://assets/models/kenney_commercial/building-h.glb",
	"res://assets/models/kenney_commercial/building-i.glb",
	"res://assets/models/kenney_commercial/building-j.glb",
	"res://assets/models/kenney_commercial/building-k.glb",
	"res://assets/models/kenney_commercial/building-l.glb",
	"res://assets/models/kenney_commercial/building-m.glb",
	"res://assets/models/kenney_commercial/building-n.glb",
]

const SKYSCRAPERS: Array[String] = [
	"res://assets/models/kenney_commercial/building-skyscraper-a.glb",
	"res://assets/models/kenney_commercial/building-skyscraper-b.glb",
	"res://assets/models/kenney_commercial/building-skyscraper-c.glb",
	"res://assets/models/kenney_commercial/building-skyscraper-d.glb",
	"res://assets/models/kenney_commercial/building-skyscraper-e.glb",
]

const KAYKIT_BUILDINGS: Array[String] = [
	"res://assets/models/city/building_A.gltf",
	"res://assets/models/city/building_B.gltf",
	"res://assets/models/city/building_C.gltf",
	"res://assets/models/city/building_D.gltf",
	"res://assets/models/city/building_E.gltf",
	"res://assets/models/city/building_F.gltf",
	"res://assets/models/city/building_G.gltf",
	"res://assets/models/city/building_H.gltf",
]

const PATH_STONES: String = "res://assets/models/kenney_suburban/path-stones-long.glb"
const FENCE_MODEL: String = "res://assets/models/kenney_suburban/fence-1x4.glb"
const PLANTER_MODEL: String = "res://assets/models/kenney_suburban/planter.glb"
const DUMPSTER_MODEL: String = "res://assets/models/city/dumpster.gltf"
const WATERTOWER_MODEL: String = "res://assets/models/city/watertower.gltf"
const BENCH_MODEL: String = "res://assets/models/city/bench.gltf"
const TRASH_MODEL: String = "res://assets/models/city/trash_A.gltf"
const BUSH_MODEL: String = "res://assets/models/city/bush.gltf"
const AWNING_MODEL: String = "res://assets/models/kenney_commercial/detail-awning-wide.glb"
const GARAGE_MODEL: String = "res://assets/models/modular_urban/wall-a-garage.glb"
const BARRIER_MODEL: String = "res://assets/models/modular_urban/detail-barrier-type-a.glb"


## Constroi um lote completo e procedural com colisoes, arquitetura 3D e props.
## Pode gerar o predio peca por peca modularmente ou por arquetipo suburbano.
## Uso:
##   var lot := BuildingAssembler3D.build_lot("house", rng)
static func build_lot(kind: String, rng: RandomNumberGenerator) -> StaticBody3D:
	if rng.randf() < 0.55:
		return ModularBuilder.build_procedural_building(kind, rng)

	var body := StaticBody3D.new()
	body.name = "Lot_" + kind

	match kind:
		"house":
			_build_house(body, rng)
		"store", "grocery":
			_build_commercial(body, rng, kind == "grocery")
		"apartment", "mall":
			_build_highrise(body, rng, kind == "mall")
		_:
			_build_house(body, rng)

	return body


static func _build_house(body: StaticBody3D, rng: RandomNumberGenerator) -> void:
	var model_path := SUBURBAN_HOUSES[rng.randi_range(0, SUBURBAN_HOUSES.size() - 1)]
	var house_scale := 8.0
	_instantiate_model(body, model_path, Vector3(0.0, 0.0, 1.2), 0.0, house_scale)
	_create_box_collider(body, Vector3(10.4, 6.8, 8.4), Vector3(0.0, 3.4, 1.2))

	# Caminho de pedras da porta ate a calcada frontal
	_instantiate_model(body, PATH_STONES, Vector3(0.0, 0.02, -4.5), 0.0, 7.2)

	# Cercas laterais do quintal
	_instantiate_model(body, FENCE_MODEL, Vector3(-5.8, 0.0, 1.2), PI * 0.5, 5.4)
	_instantiate_model(body, FENCE_MODEL, Vector3(5.8, 0.0, 1.2), PI * 0.5, 5.4)
	_create_box_collider(body, Vector3(0.4, 1.5, 6.0), Vector3(-5.8, 0.75, 1.2))
	_create_box_collider(body, Vector3(0.4, 1.5, 6.0), Vector3(5.8, 0.75, 1.2))

	# Arbusto ou canteiro ornamental
	if rng.randf() < 0.65:
		_instantiate_model(body, PLANTER_MODEL, Vector3(-3.8, 0.0, -3.8), 0.0, 4.8)
	if rng.randf() < 0.65:
		_instantiate_model(body, BUSH_MODEL, Vector3(3.8, 0.0, -3.8), 0.0, 3.6)

	# Caixa de municao no quintal dos fundos
	_spawn_ammo_pickup(body, Vector3(rng.randf_range(-3.5, 3.5), 0.15, 6.0))

	# Muro perimetral do lote com abertura para a calcada
	if rng.randf() < 0.75:
		_create_lot_perimeter_wall(body)


static func _build_commercial(body: StaticBody3D, rng: RandomNumberGenerator, is_grocery: bool) -> void:
	if rng.randf() < 0.5:
		var model_path := COMMERCIAL_BUILDINGS[rng.randi_range(0, COMMERCIAL_BUILDINGS.size() - 1)]
		var scale_val := 7.5
		_instantiate_model(body, model_path, Vector3(0.0, 0.0, 0.0), 0.0, scale_val)
		var bldg_w := 8.5 if not is_grocery else 10.0
		var bldg_h := 9.5
		_create_box_collider(body, Vector3(bldg_w, bldg_h, 8.5), Vector3(0.0, bldg_h * 0.5, 0.0))
		_instantiate_model(body, AWNING_MODEL, Vector3(0.0, 3.4, -4.2), 0.0, 5.4)
	else:
		var model_idx := rng.randi_range(2, 5)
		var model_path: String = KAYKIT_BUILDINGS[model_idx]
		var scale_val := 4.8
		_instantiate_model(body, model_path, Vector3(0.0, 0.0, 0.0), 0.0, scale_val)
		_create_box_collider(body, Vector3(9.6, 11.2, 9.6), Vector3(0.0, 5.6, 0.0))

	# Cacamba de lixo no beco dos fundos
	_instantiate_model(body, DUMPSTER_MODEL, Vector3(-4.5, 0.0, 5.2), 0.0, 2.0)
	_create_box_collider(body, Vector3(2.4, 1.8, 1.8), Vector3(-4.5, 0.9, 5.2))

	# Banco ou lixeira na calcada da frente
	if rng.randf() < 0.6:
		_instantiate_model(body, BENCH_MODEL, Vector3(4.2, 0.0, -5.2), 0.0, 2.0)
		_create_box_collider(body, Vector3(2.0, 1.0, 0.8), Vector3(4.2, 0.5, -5.2))
	if rng.randf() < 0.6:
		_instantiate_model(body, TRASH_MODEL, Vector3(-4.5, 0.0, -5.2), 0.0, 2.0)

	if rng.randf() < 0.55:
		_create_underground_garage_ramp(body)

	_spawn_ammo_pickup(body, Vector3(4.2, 0.15, 5.2))


static func _build_highrise(body: StaticBody3D, rng: RandomNumberGenerator, is_mall: bool) -> void:
	if is_mall or rng.randf() < 0.45:
		var model_idx := rng.randi_range(6, 7)
		var model_path: String = KAYKIT_BUILDINGS[model_idx]
		var scale_val := 5.0
		_instantiate_model(body, model_path, Vector3(0.0, 0.0, 0.0), 0.0, scale_val)
		var bldg_h := 15.0
		_create_box_collider(body, Vector3(10.0, bldg_h, 10.0), Vector3(0.0, bldg_h * 0.5, 0.0))
		_instantiate_model(body, WATERTOWER_MODEL, Vector3(2.4, bldg_h, 2.4), 0.0, 1.8)
	else:
		var model_path := SKYSCRAPERS[rng.randi_range(0, SKYSCRAPERS.size() - 1)]
		var scale_val := 6.5
		_instantiate_model(body, model_path, Vector3(0.0, 0.0, 0.0), 0.0, scale_val)
		var bldg_h := 18.5
		_create_box_collider(body, Vector3(9.0, bldg_h, 9.0), Vector3(0.0, bldg_h * 0.5, 0.0))
		_instantiate_model(body, WATERTOWER_MODEL, Vector3(0.0, bldg_h, 0.0), 0.0, 2.0)

	_instantiate_model(body, DUMPSTER_MODEL, Vector3(5.6, 0.0, 2.5), PI * 0.5, 2.0)
	_create_box_collider(body, Vector3(1.8, 1.8, 2.5), Vector3(5.6, 0.9, 2.5))
	_spawn_ammo_pickup(body, Vector3(-5.0, 0.15, 4.8))

	if rng.randf() < 0.65:
		_create_underground_garage_ramp(body)


static func _instantiate_model(parent: Node3D, path: String, offset: Vector3, rot_y: float, scale_val: float) -> Node3D:
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("Falha ao carregar modelo 3D em '%s'." % path)
		return null
	var inst := scene.instantiate() as Node3D
	inst.position = offset
	inst.rotation.y = rot_y
	inst.scale = Vector3.ONE * scale_val
	parent.add_child(inst)
	return inst


static func _create_box_collider(body: StaticBody3D, size: Vector3, center: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = center
	body.add_child(collision)


static func _spawn_ammo_pickup(body: StaticBody3D, pos: Vector3) -> void:
	var pickup := AMMO_PICKUP_SCENE.instantiate() as Node3D
	pickup.position = pos
	body.add_child(pickup)


static func _create_underground_garage_ramp(body: StaticBody3D) -> void:
	var ramp_mat := StandardMaterial3D.new()
	ramp_mat.albedo_color = Color(0.20, 0.20, 0.22)
	ramp_mat.roughness = 0.9

	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.48, 0.48, 0.46)
	wall_mat.roughness = 0.85

	# Rampa inclinada descendo para a garagem subterranea
	var ramp_mesh := BoxMesh.new()
	ramp_mesh.size = Vector3(3.2, 0.12, 5.8)
	ramp_mesh.material = ramp_mat
	var ramp_inst := MeshInstance3D.new()
	ramp_inst.name = "GarageRamp"
	ramp_inst.mesh = ramp_mesh
	ramp_inst.position = Vector3(5.6, -0.4, 0.0)
	ramp_inst.rotation.x = -0.22
	body.add_child(ramp_inst)

	var ramp_shape := BoxShape3D.new()
	ramp_shape.size = Vector3(3.2, 0.12, 5.8)
	var ramp_col := CollisionShape3D.new()
	ramp_col.shape = ramp_shape
	ramp_col.position = Vector3(5.6, -0.4, 0.0)
	ramp_col.rotation.x = -0.22
	body.add_child(ramp_col)

	# Muros de arrimo laterais
	_create_visual_box(body, "RampWallL", Vector3(0.3, 1.4, 5.8), Vector3(3.85, 0.2, 0.0), wall_mat)
	_create_box_collider(body, Vector3(0.3, 1.4, 5.8), Vector3(3.85, 0.2, 0.0))
	_create_visual_box(body, "RampWallR", Vector3(0.3, 1.4, 5.8), Vector3(7.35, 0.2, 0.0), wall_mat)
	_create_box_collider(body, Vector3(0.3, 1.4, 5.8), Vector3(7.35, 0.2, 0.0))

	# Portao da garagem subterranea
	_instantiate_model(body, GARAGE_MODEL, Vector3(5.6, -1.0, -2.8), 0.0, 3.2)
	_create_box_collider(body, Vector3(3.2, 2.5, 0.4), Vector3(5.6, 0.0, -2.8))

	# Barreira de protecao e municao
	_instantiate_model(body, BARRIER_MODEL, Vector3(7.35, 0.14, 2.6), PI * 0.5, 2.2)
	_spawn_ammo_pickup(body, Vector3(5.6, -0.85, -2.2))


static func _create_lot_perimeter_wall(body: StaticBody3D) -> void:
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.52, 0.48, 0.44)
	wall_mat.roughness = 0.88

	var wall_h := 1.2
	# Muros laterais do lote (X = -7.4 e X = 7.4)
	_create_visual_box(body, "LotWallL", Vector3(0.3, wall_h, 15.0), Vector3(-7.4, wall_h * 0.5, 0.0), wall_mat)
	_create_box_collider(body, Vector3(0.3, wall_h, 15.0), Vector3(-7.4, wall_h * 0.5, 0.0))
	_create_visual_box(body, "LotWallR", Vector3(0.3, wall_h, 15.0), Vector3(7.4, wall_h * 0.5, 0.0), wall_mat)
	_create_box_collider(body, Vector3(0.3, wall_h, 15.0), Vector3(7.4, wall_h * 0.5, 0.0))

	# Muro dos fundos
	_create_visual_box(body, "LotWallBack", Vector3(15.0, wall_h, 0.3), Vector3(0.0, wall_h * 0.5, 7.4), wall_mat)
	_create_box_collider(body, Vector3(15.0, wall_h, 0.3), Vector3(0.0, wall_h * 0.5, 7.4))

	# Muro frontal com abertura para passagem de pedestre da calcada
	_create_visual_box(body, "LotWallFrontL", Vector3(5.2, wall_h, 0.3), Vector3(-4.8, wall_h * 0.5, -7.4), wall_mat)
	_create_box_collider(body, Vector3(5.2, wall_h, 0.3), Vector3(-4.8, wall_h * 0.5, -7.4))
	_create_visual_box(body, "LotWallFrontR", Vector3(5.2, wall_h, 0.3), Vector3(4.8, wall_h * 0.5, -7.4), wall_mat)
	_create_box_collider(body, Vector3(5.2, wall_h, 0.3), Vector3(4.8, wall_h * 0.5, -7.4))


static func _create_visual_box(parent: Node3D, b_name: String, b_size: Vector3, b_pos: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = b_size
	mesh.material = mat
	var inst := MeshInstance3D.new()
	inst.name = b_name
	inst.mesh = mesh
	inst.position = b_pos
	parent.add_child(inst)
