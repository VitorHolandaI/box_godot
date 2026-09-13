class_name SafehouseBuilder
extends RefCounted

## Construtor procedural da Safehouse fortificada com arquitetura loft de 2 andares,
## mezanino perimetral, escadaria real, estacoes de respawn e shader de aura de corte (bola aura).
## Uso:
##   var safehouse := SafehouseBuilder.build_safehouse()

const AMMO_PICKUP_SCENE: PackedScene = preload("res://scenes/ammo_pickup.tscn")
const CUTOUT_SHADER: Shader = preload("res://shaders/building_cutout.gdshader")
const FLOOR_HEIGHT: float = 3.2

const MODEL_PALLET: String = "res://assets/models/modular_urban/pallet.glb"
const MODEL_BOX_A: String = "res://assets/models/city/box_A.gltf"
const MODEL_BOX_B: String = "res://assets/models/city/box_B.gltf"
const MODEL_BENCH: String = "res://assets/models/modular_urban/detail-bench.glb"
const MODEL_BARRIER: String = "res://assets/models/modular_urban/detail-barrier-strong-type-a.glb"
const MODEL_AWNING: String = "res://assets/models/modular_urban/detail-awning-wide.glb"


static func build_safehouse() -> StaticBody3D:
	var house := StaticBody3D.new()
	house.name = "DetailedSafehouse"

	# Materiais com Shader de Cutout (Aura / Bola de visibilidade do jogador)
	var cutout_wall_mat := _create_cutout_material(Color(0.38, 0.41, 0.36), 0.88)
	var cutout_floor_mat := _create_cutout_material(Color(0.24, 0.25, 0.23), 0.90)
	var wood_mat := _create_cutout_material(Color(0.44, 0.30, 0.18), 0.80)

	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.22, 0.23, 0.21)
	ground_mat.roughness = 0.9

	_build_ground_floor(house, ground_mat)
	_build_mezzanine_walkways(house, cutout_floor_mat)
	_build_all_cutout_walls(house, cutout_wall_mat)
	_build_staircase(house, wood_mat)
	_build_respawn_bunks(house)
	_build_tactical_armory(house)
	_build_balcony(house, cutout_floor_mat)
	_build_sanctuary_lighting(house)

	return house


static func _create_cutout_material(color: Color, roughness: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = CUTOUT_SHADER
	mat.set_shader_parameter("base_color", color)
	mat.set_shader_parameter("material_roughness", roughness)
	mat.set_shader_parameter("cutout_radius", 8.5)
	return mat


static func _build_ground_floor(house: StaticBody3D, ground_mat: Material) -> void:
	var floor_inst := MeshInstance3D.new()
	floor_inst.name = "GroundFloorMesh"
	var b_mesh := BoxMesh.new()
	b_mesh.size = Vector3(12.8, 0.16, 12.8)
	b_mesh.material = ground_mat
	floor_inst.mesh = b_mesh
	floor_inst.position = Vector3(0.0, 0.08, 0.0)
	house.add_child(floor_inst)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(12.8, 0.16, 12.8)
	col.shape = shape
	col.position = Vector3(0.0, 0.08, 0.0)
	house.add_child(col)


static func _build_mezzanine_walkways(house: StaticBody3D, cutout_mat: Material) -> void:
	# Mezanino em anel perimetral com atrio central aberto de 7x7m
	# Passarela Sul (traseira)
	_add_floor_block(house, "Floor2South", Vector3(12.6, 0.14, 2.4), Vector3(0.0, FLOOR_HEIGHT, 5.1), cutout_mat)
	# Passarela Norte (frontal)
	_add_floor_block(house, "Floor2North", Vector3(12.6, 0.14, 2.4), Vector3(0.0, FLOOR_HEIGHT, -5.1), cutout_mat)
	# Passarela Leste
	_add_floor_block(house, "Floor2East", Vector3(2.4, 0.14, 7.8), Vector3(5.1, FLOOR_HEIGHT, 0.0), cutout_mat)
	# Passarela Oeste (ao lado da escada)
	_add_floor_block(house, "Floor2West", Vector3(2.4, 0.14, 7.8), Vector3(-5.1, FLOOR_HEIGHT, 0.0), cutout_mat)


static func _add_floor_block(parent: Node3D, node_name: String, sz: Vector3, pos: Vector3, mat: Material) -> void:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = node_name + "Mesh"
	var box := BoxMesh.new()
	box.size = sz
	box.material = mat
	mesh_inst.mesh = box
	mesh_inst.position = pos
	parent.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	col.name = node_name + "Col"
	var shape := BoxShape3D.new()
	shape.size = sz
	col.shape = shape
	col.position = pos
	parent.add_child(col)


static func _build_all_cutout_walls(house: StaticBody3D, cutout_mat: Material) -> void:
	# Todas as paredes usam CUTOUT_SHADER para que a bola/aura de corte revele o interior
	# Parede Sul (traseira voltada para a camera superior)
	_add_wall_block(house, Vector3(12.8, 6.4, 0.3), Vector3(0.0, 3.2, 6.25), cutout_mat)
	# Parede Leste
	_add_wall_block(house, Vector3(0.3, 6.4, 12.8), Vector3(6.25, 3.2, 0.0), cutout_mat)
	# Parede Oeste
	_add_wall_block(house, Vector3(0.3, 6.4, 12.8), Vector3(-6.25, 3.2, 0.0), cutout_mat)

	# Fachada Norte - Terreo: Portal largo central de 4.0m
	_add_wall_block(house, Vector3(4.3, 3.2, 0.3), Vector3(-4.15, 1.6, -6.25), cutout_mat)
	_add_wall_block(house, Vector3(4.3, 3.2, 0.3), Vector3(4.15, 1.6, -6.25), cutout_mat)
	_add_wall_block(house, Vector3(4.2, 0.8, 0.3), Vector3(0.0, 2.8, -6.25), cutout_mat)

	# Fachada Norte - 2o Andar
	_add_wall_block(house, Vector3(4.6, 3.2, 0.3), Vector3(-4.0, 4.8, -6.25), cutout_mat)
	_add_wall_block(house, Vector3(4.6, 3.2, 0.3), Vector3(4.0, 4.8, -6.25), cutout_mat)
	_add_wall_block(house, Vector3(3.6, 1.0, 0.3), Vector3(0.0, 5.9, -6.25), cutout_mat)


static func _add_wall_block(parent: Node3D, sz: Vector3, pos: Vector3, mat: Material) -> void:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = sz
	box.material = mat
	mesh_inst.mesh = box
	mesh_inst.position = pos
	parent.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = sz
	col.shape = shape
	col.position = pos
	parent.add_child(col)


static func _build_staircase(house: StaticBody3D, wood_mat: Material) -> void:
	var steps := 12
	var stair_x := -4.7
	var start_z := 2.6
	var end_z := -2.6
	var step_run := (start_z - end_z) / float(steps)
	var step_rise := FLOOR_HEIGHT / float(steps)

	for i in steps:
		var step_inst := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(2.0, step_rise, step_run * 1.08)
		b.material = wood_mat
		step_inst.mesh = b
		step_inst.position = Vector3(stair_x, float(i + 1) * step_rise - step_rise * 0.5, start_z - float(i) * step_run)
		house.add_child(step_inst)

	var ramp_col := CollisionShape3D.new()
	var ramp_shape := BoxShape3D.new()
	var ramp_length := sqrt(pow(start_z - end_z, 2) + pow(FLOOR_HEIGHT, 2))
	ramp_shape.size = Vector3(2.0, 0.12, ramp_length)
	ramp_col.shape = ramp_shape
	ramp_col.position = Vector3(stair_x, FLOOR_HEIGHT * 0.5, (start_z + end_z) * 0.5)
	ramp_col.rotation.x = atan2(FLOOR_HEIGHT, start_z - end_z)
	house.add_child(ramp_col)

	var rail := MeshInstance3D.new()
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(0.08, 0.85, ramp_length)
	rail_mesh.material = wood_mat
	rail.mesh = rail_mesh
	rail.position = Vector3(stair_x + 0.95, FLOOR_HEIGHT * 0.5 + 0.45, (start_z + end_z) * 0.5)
	rail.rotation.x = ramp_col.rotation.x
	house.add_child(rail)


static func _build_respawn_bunks(house: StaticBody3D) -> void:
	var stations := [
		{"pos": Vector3(-4.8, 0.14, 2.5), "num": 1, "color": Color(0.2, 0.5, 0.8)},
		{"pos": Vector3(-4.8, 0.14, -2.5), "num": 2, "color": Color(0.8, 0.3, 0.2)},
		{"pos": Vector3(4.8, 0.14, 2.5), "num": 3, "color": Color(0.2, 0.7, 0.3)},
		{"pos": Vector3(4.8, 0.14, -2.5), "num": 4, "color": Color(0.9, 0.7, 0.2)},
	]
	for st in stations:
		var base_pos: Vector3 = st["pos"]
		var pad := MeshInstance3D.new()
		var p_mesh := BoxMesh.new()
		p_mesh.size = Vector3(2.2, 0.04, 1.8)
		var p_mat := StandardMaterial3D.new()
		p_mat.albedo_color = (st["color"] as Color).darkened(0.5)
		pad.mesh = p_mesh
		pad.position = base_pos + Vector3(0.0, 0.02, 0.0)
		house.add_child(pad)

		var bed := MeshInstance3D.new()
		var b_mesh := BoxMesh.new()
		b_mesh.size = Vector3(1.6, 0.28, 0.9)
		var b_mat := StandardMaterial3D.new()
		b_mat.albedo_color = Color(0.28, 0.32, 0.24)
		bed.mesh = b_mesh
		bed.position = base_pos + Vector3(0.0, 0.16, 0.0)
		house.add_child(bed)

		var pillow := MeshInstance3D.new()
		var pil_mesh := BoxMesh.new()
		pil_mesh.size = Vector3(0.35, 0.1, 0.75)
		var pil_mat := StandardMaterial3D.new()
		pil_mat.albedo_color = Color(0.82, 0.82, 0.78)
		pillow.mesh = pil_mesh
		pillow.position = base_pos + Vector3(-0.55, 0.32, 0.0)
		house.add_child(pillow)

		var medkit := MeshInstance3D.new()
		var m_mesh := BoxMesh.new()
		m_mesh.size = Vector3(0.3, 0.2, 0.4)
		var m_mat := StandardMaterial3D.new()
		m_mat.albedo_color = Color(0.92, 0.92, 0.92)
		medkit.mesh = m_mesh
		medkit.position = base_pos + Vector3(0.7, 0.12, 0.5)
		house.add_child(medkit)


static func _build_tactical_armory(house: StaticBody3D) -> void:
	var pallet := _load_model(MODEL_PALLET, Vector3(0.0, 0.14, 4.0), Vector3.ONE * 1.5)
	if pallet != null:
		house.add_child(pallet)

	var box1 := _load_model(MODEL_BOX_A, Vector3(-0.4, 0.35, 4.0), Vector3.ONE * 1.2)
	if box1 != null:
		house.add_child(box1)

	var box2 := _load_model(MODEL_BOX_B, Vector3(0.4, 0.35, 4.1), Vector3.ONE * 1.2)
	if box2 != null:
		house.add_child(box2)

	var ammo_ground := AMMO_PICKUP_SCENE.instantiate() as Node3D
	ammo_ground.position = Vector3(0.0, 0.8, 4.0)
	ammo_ground.set("respawns", true)
	house.add_child(ammo_ground)

	var bench := _load_model(MODEL_BENCH, Vector3(2.6, 0.14, 4.0), Vector3.ONE * 1.5)
	if bench != null:
		house.add_child(bench)

	var bar_l := _load_model(MODEL_BARRIER, Vector3(-2.8, 0.14, -6.1), Vector3.ONE * 1.4)
	if bar_l != null:
		house.add_child(bar_l)
	var bar_r := _load_model(MODEL_BARRIER, Vector3(2.8, 0.14, -6.1), Vector3.ONE * 1.4)
	if bar_r != null:
		house.add_child(bar_r)

	var awning := _load_model(MODEL_AWNING, Vector3(0.0, 3.2, -6.3), Vector3.ONE * 1.6)
	if awning != null:
		house.add_child(awning)


static func _build_balcony(house: StaticBody3D, cutout_mat: Material) -> void:
	var balcony_floor := MeshInstance3D.new()
	var b_mesh := BoxMesh.new()
	b_mesh.size = Vector3(6.0, 0.14, 2.0)
	b_mesh.material = cutout_mat
	balcony_floor.mesh = b_mesh
	balcony_floor.position = Vector3(0.0, FLOOR_HEIGHT, -7.2)
	house.add_child(balcony_floor)

	var b_col := CollisionShape3D.new()
	var b_shape := BoxShape3D.new()
	b_shape.size = Vector3(6.0, 0.14, 2.0)
	b_col.shape = b_shape
	b_col.position = Vector3(0.0, FLOOR_HEIGHT, -7.2)
	house.add_child(b_col)

	var bar_front1 := _load_model(MODEL_BARRIER, Vector3(-1.6, FLOOR_HEIGHT + 0.08, -8.15), Vector3.ONE * 1.2)
	if bar_front1 != null:
		house.add_child(bar_front1)
	var bar_front2 := _load_model(MODEL_BARRIER, Vector3(1.6, FLOOR_HEIGHT + 0.08, -8.15), Vector3.ONE * 1.2)
	if bar_front2 != null:
		house.add_child(bar_front2)

	var ammo_upper := AMMO_PICKUP_SCENE.instantiate() as Node3D
	ammo_upper.position = Vector3(0.0, FLOOR_HEIGHT + 0.6, -5.1)
	ammo_upper.set("respawns", true)
	house.add_child(ammo_upper)


static func _build_sanctuary_lighting(house: StaticBody3D) -> void:
	# Lustre / Iluminacao central acolhedora no atrio (ampla iluminacao ambar)
	var ground_light := OmniLight3D.new()
	ground_light.name = "SanctuaryGroundLight"
	ground_light.light_color = Color(1.0, 0.85, 0.62)
	ground_light.light_energy = 2.4
	ground_light.omni_range = 16.0
	ground_light.shadow_enabled = false
	ground_light.position = Vector3(0.0, 3.2, 0.0)
	house.add_child(ground_light)

	# Iluminacao de trabalho na passarela superior
	var upper_light := OmniLight3D.new()
	upper_light.name = "SanctuaryUpperLight"
	upper_light.light_color = Color(0.92, 0.94, 1.0)
	upper_light.light_energy = 1.6
	upper_light.omni_range = 12.0
	upper_light.shadow_enabled = false
	upper_light.position = Vector3(0.0, FLOOR_HEIGHT + 2.6, 3.0)
	house.add_child(upper_light)

	# Holofote defensivo frontal iluminando a rua
	var spotlight := SpotLight3D.new()
	spotlight.name = "ExteriorDefensiveSpotlight"
	spotlight.light_color = Color(1.0, 0.95, 0.82)
	spotlight.light_energy = 2.4
	spotlight.spot_range = 30.0
	spotlight.spot_angle = 40.0
	spotlight.shadow_enabled = false
	spotlight.position = Vector3(0.0, FLOOR_HEIGHT + 2.8, -6.4)
	spotlight.rotation_degrees = Vector3(-35.0, 0.0, 0.0)
	house.add_child(spotlight)


static func _load_model(path: String, pos: Vector3, scl: Vector3) -> Node3D:
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var inst := scene.instantiate() as Node3D
	inst.position = pos
	inst.scale = scl
	return inst
