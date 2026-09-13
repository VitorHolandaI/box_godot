class_name ModularBuildingBuilder
extends RefCounted

## Construtor procedural de predios montados peca por peca a partir de blocos 3D modulares.
## Suporta andares multiplos andaveis com escadas reais, sacadas, terraco caminhavel e iluminacao.
## Uso:
##   var bldg := ModularBuildingBuilder.build_procedural_building("store", rng)

const AMMO_PICKUP_SCENE: PackedScene = preload("res://scenes/ammo_pickup.tscn")
const CUTOUT_SHADER: Shader = preload("res://shaders/building_cutout.gdshader")
const WATERTOWER_MODEL: String = "res://assets/models/city/watertower.gltf"
const DUMPSTER_MODEL: String = "res://assets/models/city/dumpster.gltf"
const PALLET_MODEL: String = "res://assets/models/modular_urban/pallet.glb"
const BOX_MODEL: String = "res://assets/models/city/box_A.gltf"
const BENCH_MODEL: String = "res://assets/models/modular_urban/detail-bench.glb"
const TILE_SCALE: float = 3.2

const PALETTES: Array[Color] = [
	Color(0.85, 0.40, 0.30), # Red Brick
	Color(0.92, 0.85, 0.72), # Sandstone Stucco
	Color(0.35, 0.48, 0.58), # Slate Blue
	Color(0.88, 0.76, 0.52), # Warm Ochre
	Color(0.55, 0.42, 0.32), # Timber Brown
	Color(0.42, 0.45, 0.48), # Concrete Granite
	Color(0.82, 0.58, 0.38), # Terracotta
]


static func build_procedural_building(kind: String, rng: RandomNumberGenerator) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "ProcBldg_" + kind

	var grid_w := 3
	var grid_d := 3
	var num_floors := 1
	var style := "a" if rng.randf() < 0.5 else "b"
	var wall_color := PALETTES[rng.randi_range(0, PALETTES.size() - 1)]

	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = wall_color
	wall_mat.roughness = 0.85

	var trim_mat := StandardMaterial3D.new()
	trim_mat.albedo_color = wall_color.darkened(0.28)
	trim_mat.roughness = 0.75

	match kind:
		"house":
			grid_w = 3
			grid_d = 3
			num_floors = 1 if rng.randf() < 0.5 else 2
		"store", "grocery":
			grid_w = 3 if kind == "store" else 4
			grid_d = 3
			num_floors = 1 if rng.randf() < 0.4 else 2
		"apartment":
			grid_w = 3 if rng.randf() < 0.5 else 4
			grid_d = 3
			num_floors = rng.randi_range(2, 3)
		"mall":
			grid_w = 4
			grid_d = 4
			num_floors = 2
		_:
			grid_w = 3
			grid_d = 3
			num_floors = 1

	var cutout_wall_mat := ShaderMaterial.new()
	cutout_wall_mat.shader = CUTOUT_SHADER
	cutout_wall_mat.set_shader_parameter("base_color", Color(wall_color.r, wall_color.g, wall_color.b, 1.0))
	cutout_wall_mat.set_shader_parameter("material_roughness", 0.85)
	cutout_wall_mat.set_shader_parameter("cutout_radius", 8.5)

	var cutout_trim_mat := ShaderMaterial.new()
	cutout_trim_mat.shader = CUTOUT_SHADER
	var trim_c := wall_color.darkened(0.28)
	cutout_trim_mat.set_shader_parameter("base_color", Color(trim_c.r, trim_c.g, trim_c.b, 1.0))
	cutout_trim_mat.set_shader_parameter("material_roughness", 0.75)
	cutout_trim_mat.set_shader_parameter("cutout_radius", 8.5)

	var door_x := rng.randi_range(1, grid_w - 2)
	_create_floor_and_ceiling(body, grid_w, grid_d, num_floors)

	for floor_idx in num_floors:
		var f_mat: Material = cutout_wall_mat
		var f_trim: Material = cutout_trim_mat
		_assemble_floor(body, floor_idx, grid_w, grid_d, style, door_x, f_mat, f_trim, rng)
		if floor_idx < num_floors - 1:
			_create_staircase(body, floor_idx, grid_w, grid_d)

	_assemble_roof(body, num_floors, grid_w, grid_d, style, cutout_wall_mat, cutout_trim_mat, rng)
	_create_perimeter_colliders(body, grid_w, grid_d, num_floors, door_x)
	_create_interior(body, grid_w, grid_d, num_floors, rng)

	return body


static func _create_floor_and_ceiling(body: StaticBody3D, w: int, d: int, floors: int) -> void:
	var total_w := float(w) * TILE_SCALE
	var total_d := float(d) * TILE_SCALE
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.24, 0.22, 0.20)
	floor_mat.roughness = 0.85

	# Piso terreo solido
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(total_w, 0.12, total_d)
	floor_mesh.material = floor_mat
	var floor_inst := MeshInstance3D.new()
	floor_inst.name = "GroundFloor"
	floor_inst.mesh = floor_mesh
	floor_inst.position = Vector3(0.0, 0.06, 0.0)
	body.add_child(floor_inst)

	# Lajes intermediarias e cobertura com shader de cutout para revelar o andar inteiro
	var cutout_slab_mat := ShaderMaterial.new()
	cutout_slab_mat.shader = CUTOUT_SHADER
	cutout_slab_mat.set_shader_parameter("base_color", Color(0.24, 0.22, 0.20, 1.0))
	cutout_slab_mat.set_shader_parameter("material_roughness", 0.9)
	cutout_slab_mat.set_shader_parameter("cutout_radius", 8.5)

	# Lajes intermediarias para andares superiores com abertura da escada
	for fl in range(1, floors):
		var y_fl := float(fl) * TILE_SCALE
		var slab_w := total_w - 2.2
		var slab_mesh := BoxMesh.new()
		slab_mesh.size = Vector3(slab_w, 0.14, total_d)
		slab_mesh.material = cutout_slab_mat
		var slab_inst := MeshInstance3D.new()
		slab_inst.name = "FloorSlab_%d" % fl
		slab_inst.mesh = slab_mesh
		slab_inst.position = Vector3(1.1, y_fl - 0.07, 0.0)
		body.add_child(slab_inst)
		_add_box_shape(body, Vector3(slab_w, 0.14, total_d), Vector3(1.1, y_fl - 0.07, 0.0))

		# Trecho frontal a esquerda da escada
		var front_slab := BoxMesh.new()
		front_slab.size = Vector3(2.2, 0.14, total_d * 0.4)
		front_slab.material = cutout_slab_mat
		var front_inst := MeshInstance3D.new()
		front_inst.mesh = front_slab
		front_inst.position = Vector3(-total_w * 0.5 + 1.1, y_fl - 0.07, total_d * 0.3)
		body.add_child(front_inst)
		_add_box_shape(body, Vector3(2.2, 0.14, total_d * 0.4), Vector3(-total_w * 0.5 + 1.1, y_fl - 0.07, total_d * 0.3))

	# Cobertura plana caminhavel com shader de cutout
	var roof_mesh := BoxMesh.new()
	roof_mesh.size = Vector3(total_w, 0.15, total_d)
	roof_mesh.material = cutout_slab_mat
	var roof_inst := MeshInstance3D.new()
	roof_inst.name = "CeilingSlab"
	roof_inst.mesh = roof_mesh
	var roof_y := float(floors) * TILE_SCALE - 0.075
	roof_inst.position = Vector3(0.0, roof_y, 0.0)
	body.add_child(roof_inst)
	_add_box_shape(body, Vector3(total_w, 0.15, total_d), Vector3(0.0, roof_y, 0.0))


static func _create_staircase(body: StaticBody3D, floor_idx: int, w: int, _d: int) -> void:
	var half_w := float(w - 1) * 0.5
	var stair_x := (-half_w * TILE_SCALE) + 1.1
	var base_y := float(floor_idx) * TILE_SCALE
	var stair_steps := 10
	var step_rise := TILE_SCALE / float(stair_steps)
	var step_run := 3.6 / float(stair_steps)

	var step_mat := StandardMaterial3D.new()
	step_mat.albedo_color = Color(0.40, 0.38, 0.36)
	step_mat.roughness = 0.8

	for i in stair_steps:
		var s_mesh := BoxMesh.new()
		s_mesh.size = Vector3(1.3, step_rise, step_run)
		s_mesh.material = step_mat
		var s_inst := MeshInstance3D.new()
		s_inst.name = "Stair_%d_%d" % [floor_idx, i]
		s_inst.mesh = s_mesh
		s_inst.position = Vector3(stair_x, base_y + float(i + 1) * step_rise - step_rise * 0.5, 0.4 - float(i) * step_run)
		body.add_child(s_inst)

	# Rampa de colisao inclinada suave para o CharacterBody3D subir fluidamente
	var ramp_shape := BoxShape3D.new()
	ramp_shape.size = Vector3(1.3, 0.15, 4.8)
	var ramp_col := CollisionShape3D.new()
	ramp_col.shape = ramp_shape
	ramp_col.position = Vector3(stair_x, base_y + TILE_SCALE * 0.5, -1.4)
	ramp_col.rotation.x = atan2(TILE_SCALE, 3.6)
	body.add_child(ramp_col)

	# Guarda-corpo da escada
	var rail_mat := StandardMaterial3D.new()
	rail_mat.albedo_color = Color(0.18, 0.18, 0.18)
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(0.06, 0.9, 4.8)
	rail_mesh.material = rail_mat
	var rail_inst := MeshInstance3D.new()
	rail_inst.name = "StairRailing_%d" % floor_idx
	rail_inst.mesh = rail_mesh
	rail_inst.position = Vector3(stair_x + 0.65, base_y + TILE_SCALE * 0.5 + 0.45, -1.4)
	rail_inst.rotation.x = atan2(TILE_SCALE, 3.6)
	body.add_child(rail_inst)


static func _assemble_floor(
		body: StaticBody3D, floor_idx: int, w: int, d: int,
		style: String, door_x: int, mat: Material, trim_mat: Material, rng: RandomNumberGenerator
) -> void:
	var y_pos := float(floor_idx) * TILE_SCALE
	var half_w := float(w - 1) * 0.5
	var half_d := float(d - 1) * 0.5

	# Fachada frontal (Z = half_d, virada para +Z)
	for gx in w:
		var px := (float(gx) - half_w) * TILE_SCALE
		var pz := half_d * TILE_SCALE
		if gx == 0 or gx == w - 1:
			var corner_rot := 0.0 if gx == 0 else -PI * 0.5
			_add_piece(body, "wall-%s-corner.glb" % style, Vector3(px, y_pos, pz), corner_rot, mat, trim_mat)
		elif floor_idx == 0 and gx == door_x:
			_add_piece(body, "wall-%s-open.glb" % style, Vector3(px, y_pos, pz), 0.0, mat, trim_mat)
		elif floor_idx > 0 and gx == door_x:
			# Porta aberta para sacada no andar superior
			_add_piece(body, "wall-%s-open.glb" % style, Vector3(px, y_pos, pz), 0.0, mat, trim_mat)
			_add_piece(body, "balcony-type-a.glb", Vector3(px, y_pos, pz), 0.0)
			_add_box_shape(body, Vector3(2.6, 0.12, 1.4), Vector3(px, y_pos - 0.06, pz + 0.8))
			_add_box_shape(body, Vector3(2.6, 1.1, 0.1), Vector3(px, y_pos + 0.55, pz + 1.5))
		else:
			var piece := "wall-%s-window.glb" % style if rng.randf() < 0.65 else "wall-%s.glb" % style
			_add_piece(body, piece, Vector3(px, y_pos, pz), 0.0, mat, trim_mat)

	# Parede traseira (Z = -half_d, virada para -Z)
	for gx in w:
		var px := (float(gx) - half_w) * TILE_SCALE
		var pz := -half_d * TILE_SCALE
		if gx == 0 or gx == w - 1:
			var corner_rot := PI * 0.5 if gx == 0 else PI
			_add_piece(body, "wall-%s-corner.glb" % style, Vector3(px, y_pos, pz), corner_rot, mat, trim_mat)
		else:
			var piece := "wall-%s-window.glb" % style if rng.randf() < 0.5 else "wall-%s.glb" % style
			_add_piece(body, piece, Vector3(px, y_pos, pz), PI, mat, trim_mat)

	# Paredes laterais (X = -half_w e X = half_w)
	for gz in range(1, d - 1):
		var pz := (float(gz) - half_d) * TILE_SCALE
		var piece_l := "wall-%s-window.glb" % style if rng.randf() < 0.5 else "wall-%s.glb" % style
		_add_piece(body, piece_l, Vector3(-half_w * TILE_SCALE, y_pos, pz), PI * 0.5, mat, trim_mat)
		var piece_r := "wall-%s-window.glb" % style if rng.randf() < 0.5 else "wall-%s.glb" % style
		_add_piece(body, piece_r, Vector3(half_w * TILE_SCALE, y_pos, pz), -PI * 0.5, mat, trim_mat)


static func _assemble_roof(
		body: StaticBody3D, floors: int, w: int, d: int, style: String, mat: Material, trim_mat: Material, rng: RandomNumberGenerator
) -> void:
	var y_pos := float(floors) * TILE_SCALE
	var half_w := float(w - 1) * 0.5
	var half_d := float(d - 1) * 0.5

	# Parapeito perimetral reto (elimina telhas inclinadas bizarras no meio do terraco)
	for gx in w:
		var px := (float(gx) - half_w) * TILE_SCALE
		_add_piece(body, "wall-%s-low.glb" % style, Vector3(px, y_pos, half_d * TILE_SCALE), 0.0, mat, trim_mat)
		_add_piece(body, "wall-%s-low.glb" % style, Vector3(px, y_pos, -half_d * TILE_SCALE), PI, mat, trim_mat)
	for gz in range(1, d - 1):
		var pz := (float(gz) - half_d) * TILE_SCALE
		_add_piece(body, "wall-%s-low.glb" % style, Vector3(-half_w * TILE_SCALE, y_pos, pz), PI * 0.5, mat, trim_mat)
		_add_piece(body, "wall-%s-low.glb" % style, Vector3(half_w * TILE_SCALE, y_pos, pz), -PI * 0.5, mat, trim_mat)

	# Colisao perimetral do parapeito da cobertura
	var total_w := float(w) * TILE_SCALE
	var total_d := float(d) * TILE_SCALE
	_add_box_shape(body, Vector3(total_w, 1.2, 0.3), Vector3(0.0, y_pos + 0.6, half_d * TILE_SCALE))
	_add_box_shape(body, Vector3(total_w, 1.2, 0.3), Vector3(0.0, y_pos + 0.6, -half_d * TILE_SCALE))
	_add_box_shape(body, Vector3(0.3, 1.2, total_d), Vector3(-half_w * TILE_SCALE, y_pos + 0.6, 0.0))
	_add_box_shape(body, Vector3(0.3, 1.2, total_d), Vector3(half_w * TILE_SCALE, y_pos + 0.6, 0.0))

	# Caixa d'agua no terraco
	if rng.randf() < 0.7:
		_add_direct_model(body, WATERTOWER_MODEL, Vector3(0.0, y_pos, 0.0), 0.0, 1.4)
		_add_box_shape(body, Vector3(1.8, 2.5, 1.8), Vector3(0.0, y_pos + 1.25, 0.0))


static func _create_perimeter_colliders(body: StaticBody3D, w: int, d: int, floors: int, door_x: int) -> void:
	var h := float(floors) * TILE_SCALE
	var half_w := float(w - 1) * 0.5
	var half_d := float(d - 1) * 0.5
	var total_w := float(w) * TILE_SCALE
	var total_d := float(d) * TILE_SCALE
	var wall_thick := 1.6

	# Traseira com espessura solida
	_add_box_shape(body, Vector3(total_w + wall_thick, h, wall_thick), Vector3(0.0, h * 0.5, -half_d * TILE_SCALE))
	# Laterais que cobrem os cantos completamente
	_add_box_shape(body, Vector3(wall_thick, h, total_d + wall_thick), Vector3(-half_w * TILE_SCALE, h * 0.5, 0.0))
	_add_box_shape(body, Vector3(wall_thick, h, total_d + wall_thick), Vector3(half_w * TILE_SCALE, h * 0.5, 0.0))

	# Frente com abertura na porta e verga superior
	var door_px := (float(door_x) - half_w) * TILE_SCALE
	var door_w := 2.0
	var left_w := (door_px - door_w * 0.5) - (-total_w * 0.5 - wall_thick * 0.5)
	if left_w > 0.1:
		var left_center := (-total_w * 0.5 - wall_thick * 0.5) + left_w * 0.5
		_add_box_shape(body, Vector3(left_w, h, wall_thick), Vector3(left_center, h * 0.5, half_d * TILE_SCALE))
	var right_w := (total_w * 0.5 + wall_thick * 0.5) - (door_px + door_w * 0.5)
	if right_w > 0.1:
		var right_center := (total_w * 0.5 + wall_thick * 0.5) - right_w * 0.5
		_add_box_shape(body, Vector3(right_w, h, wall_thick), Vector3(right_center, h * 0.5, half_d * TILE_SCALE))

	# Verga superior sobre a porta (impede teleporte/pulo por cima do vao)
	var header_h := h - 2.5
	if header_h > 0.1:
		_add_box_shape(body, Vector3(door_w, header_h, wall_thick), Vector3(door_px, 2.5 + header_h * 0.5, half_d * TILE_SCALE))


static func _create_interior(body: StaticBody3D, w: int, d: int, floors: int, rng: RandomNumberGenerator) -> void:
	for fl in floors:
		_create_interior_lighting(body, w, d, fl)

	_create_partition_wall(body, w, d)
	_create_furniture(body, w, d, rng)

	# Cacamba de lixo no beco exterior
	var half_w := float(w - 1) * 0.5
	if rng.randf() < 0.6:
		_add_direct_model(body, DUMPSTER_MODEL, Vector3(-half_w * TILE_SCALE - 1.5, 0.0, 0.0), PI * 0.5, 1.6)
		_add_box_shape(body, Vector3(1.5, 1.6, 2.2), Vector3(-half_w * TILE_SCALE - 1.5, 0.8, 0.0))


static func _create_interior_lighting(body: StaticBody3D, w: int, d: int, floor_idx: int) -> void:
	var base_y := float(floor_idx) * TILE_SCALE
	var fixture_mat := StandardMaterial3D.new()
	fixture_mat.albedo_color = Color(0.98, 0.95, 0.85)
	fixture_mat.emission_enabled = true
	fixture_mat.emission = Color(0.98, 0.95, 0.85)
	fixture_mat.emission_energy_multiplier = 2.0

	var lamp_mesh := BoxMesh.new()
	lamp_mesh.size = Vector3(0.6, 0.08, 0.6)
	lamp_mesh.material = fixture_mat
	var lamp_inst := MeshInstance3D.new()
	lamp_inst.name = "CeilingLamp_%d" % floor_idx
	lamp_inst.mesh = lamp_mesh
	lamp_inst.position = Vector3(0.0, base_y + 2.9, 0.0)
	body.add_child(lamp_inst)

	var light := OmniLight3D.new()
	light.name = "InteriorLight_%d" % floor_idx
	light.light_color = Color(1.0, 0.92, 0.78)
	light.light_energy = 1.8
	light.omni_range = maxf(float(w), float(d)) * TILE_SCALE * 0.85
	light.omni_attenuation = 1.0
	light.position = Vector3(0.0, base_y + 2.7, 0.0)
	body.add_child(light)


static func _create_partition_wall(body: StaticBody3D, w: int, _d: int) -> void:
	var total_w := float(w) * TILE_SCALE
	var part_mat := StandardMaterial3D.new()
	part_mat.albedo_color = Color(0.38, 0.36, 0.34)
	part_mat.roughness = 0.9

	var segment_w := (total_w * 0.5) - 1.2
	if segment_w > 0.6:
		var z_pos := -0.5
		var left_x := -total_w * 0.25 - 0.6
		var right_x := total_w * 0.25 + 0.6
		_create_visual_and_col_box(body, "PartitionL", Vector3(segment_w, 2.8, 0.2), Vector3(left_x, 1.4, z_pos), part_mat)
		_create_visual_and_col_box(body, "PartitionR", Vector3(segment_w, 2.8, 0.2), Vector3(right_x, 1.4, z_pos), part_mat)


static func _create_furniture(body: StaticBody3D, _w: int, _d: int, rng: RandomNumberGenerator) -> void:
	var counter_mat := StandardMaterial3D.new()
	counter_mat.albedo_color = Color(0.42, 0.28, 0.16)
	counter_mat.roughness = 0.7
	_create_visual_and_col_box(body, "Counter", Vector3(2.2, 0.95, 0.7), Vector3(-1.4, 0.475, 1.2), counter_mat)

	_add_direct_model(body, BENCH_MODEL, Vector3(2.0, 0.0, 1.5), -PI * 0.5, 2.2)
	_add_direct_model(body, PALLET_MODEL, Vector3(2.0, 0.0, -2.4), 0.0, 1.8)
	_add_direct_model(body, BOX_MODEL, Vector3(2.0, 0.27, -2.4), rng.randf() * TAU, 4.5)

	# Coletavel de municao no terreo
	var pickup := AMMO_PICKUP_SCENE.instantiate() as Node3D
	pickup.position = Vector3(-1.4, 0.15, -2.0)
	body.add_child(pickup)


static func _create_visual_and_col_box(body: StaticBody3D, b_name: String, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var inst := MeshInstance3D.new()
	inst.name = b_name
	inst.mesh = mesh
	inst.position = pos
	body.add_child(inst)
	_add_box_shape(body, size, pos)


static func _add_piece(parent: Node3D, file_name: String, pos: Vector3, rot_y: float, mat: Material = null, trim_mat: Material = null) -> Node3D:
	var path := "res://assets/models/modular_urban/" + file_name
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("Peca modular nao encontrada: " + path)
		return null
	var inst := scene.instantiate() as Node3D
	inst.position = pos
	inst.rotation.y = rot_y
	inst.scale = Vector3.ONE * TILE_SCALE

	if mat != null and inst.get_child_count() > 0:
		var mesh_inst := inst.get_child(0) as MeshInstance3D
		if mesh_inst != null and mesh_inst.mesh != null:
			var sc := mesh_inst.mesh.get_surface_count()
			for s in sc:
				var smat := mesh_inst.mesh.surface_get_material(s)
				var sname := smat.resource_name.to_lower() if smat != null else ""
				if sname.contains("lines") or sname.contains("metal"):
					mesh_inst.set_surface_override_material(s, trim_mat if trim_mat != null else mat)
				elif sname.contains("concrete") or sname.contains("wall"):
					mesh_inst.set_surface_override_material(s, mat)
				elif sc <= 2:
					mesh_inst.set_surface_override_material(s, mat if s == 0 else trim_mat)

	parent.add_child(inst)
	return inst


static func _add_direct_model(parent: Node3D, path: String, pos: Vector3, rot_y: float, scale_val: float) -> Node3D:
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("Falha ao carregar modelo interior '%s'." % path)
		return null
	var inst := scene.instantiate() as Node3D
	inst.position = pos
	inst.rotation.y = rot_y
	inst.scale = Vector3.ONE * scale_val
	parent.add_child(inst)
	return inst


static func _add_box_shape(body: StaticBody3D, box_size: Vector3, box_pos: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = box_size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = box_pos
	body.add_child(col)
