class_name SolidVenue
extends StaticBody3D

const CUTOUT_SHADER := preload("res://shaders/building_cutout.gdshader")
const AMMO_PICKUP_SCENE := preload("res://scenes/ammo_pickup.tscn")
const DESTRUCTIBLE_DOOR_SCRIPT := preload("res://scripts/destructible_door.gd")
const APARTMENT := "apartment"
const HOUSE := "house"
const STORE := "store"
const GROCERY := "grocery"
const MALL := "mall"
const VALID_KINDS := [HOUSE, STORE, GROCERY, MALL, APARTMENT]

var venue_kind := HOUSE
var wall_color := Color(0.48, 0.25, 0.18)


## Configura o tipo de construcao e a cor externa das paredes.
## Uso:
##   venue.configure("house", Color(0.48, 0.25, 0.18))
func configure(kind: String, color: Color) -> void:
	if kind not in VALID_KINDS:
		push_error("Tipo de construcao invalido '%s'; esperado um de %s." % [kind, VALID_KINDS])
		return
	venue_kind = kind
	wall_color = color


func _ready() -> void:
	var dimensions := _get_dimensions()
	_create_hollow_building(dimensions)
	_create_roof(dimensions)
	_create_facade_details(dimensions)
	_create_interior_lighting(dimensions)
	_create_interior(dimensions)
	_spawn_building_ammo(dimensions)


func _get_dimensions() -> Vector3:
	if venue_kind == STORE:
		return Vector3(10.0, 5.0, 9.0)
	if venue_kind == GROCERY:
		return Vector3(14.0, 5.5, 11.0)
	if venue_kind == MALL:
		return Vector3(15.0, 8.0, 14.0)
	if venue_kind == APARTMENT:
		return Vector3(11.0, 7.0, 10.0)
	return Vector3(8.0, 4.0, 8.0)


func _get_floor_color() -> Color:
	if venue_kind == HOUSE:
		return Color(0.44, 0.27, 0.17)
	if venue_kind == STORE:
		return Color(0.38, 0.40, 0.42)
	if venue_kind == GROCERY:
		return Color(0.52, 0.50, 0.46)
	if venue_kind == MALL:
		return Color(0.60, 0.60, 0.62)
	return Color(0.34, 0.32, 0.30)


func _create_hollow_building(dimensions: Vector3) -> void:
	var wall_mat := _cutout_material(wall_color, 0.9)
	var floor_mat := _cutout_material(_get_floor_color(), 0.95)
	var thickness := 0.4
	var door_w := 2.2
	var door_h := 2.4
	var wall_h := dimensions.y
	var half_x := dimensions.x * 0.5
	var half_z := dimensions.z * 0.5

	_create_box_with_collision("Floor", Vector3(dimensions.x, 0.12, dimensions.z), Vector3(0.0, -0.06, 0.0), floor_mat)

	var side_w := (dimensions.x - door_w) * 0.5
	_create_box_with_collision("FrontLeft", Vector3(side_w, wall_h, thickness), Vector3(-(door_w + side_w) * 0.5, wall_h * 0.5, -half_z), wall_mat)
	_create_box_with_collision("FrontRight", Vector3(side_w, wall_h, thickness), Vector3((door_w + side_w) * 0.5, wall_h * 0.5, -half_z), wall_mat)

	var header_h := wall_h - door_h
	if header_h > 0.1:
		_create_box_with_collision("DoorHeader", Vector3(door_w, header_h, thickness), Vector3(0.0, door_h + header_h * 0.5, -half_z), wall_mat)
	var door = DESTRUCTIBLE_DOOR_SCRIPT.new()
	door.name = "BuildingDoor"
	door.configure(Vector3(door_w, door_h, thickness), wall_mat)
	door.position = Vector3(0.0, 0.0, -half_z)
	add_child(door)

	_create_box_with_collision("Back", Vector3(dimensions.x, wall_h, thickness), Vector3(0.0, wall_h * 0.5, half_z), wall_mat)
	_create_box_with_collision("Left", Vector3(thickness, wall_h, dimensions.z), Vector3(-half_x, wall_h * 0.5, 0.0), wall_mat)
	_create_box_with_collision("Right", Vector3(thickness, wall_h, dimensions.z), Vector3(half_x, wall_h * 0.5, 0.0), wall_mat)


func _create_roof(dimensions: Vector3) -> void:
	var roof_h := 0.65 if venue_kind == HOUSE else 0.45
	var roof_size := Vector3(dimensions.x + 0.8, roof_h, dimensions.z + 0.8)
	_create_box("Roof", roof_size, Vector3(0.0, dimensions.y + roof_h * 0.5, 0.0), _cutout_material(Color(0.18, 0.16, 0.15), 0.95))
	if venue_kind == HOUSE:
		_create_box("Chimney", Vector3(0.75, 1.3, 0.75), Vector3(2.1, dimensions.y + 0.9, 1.5), _cutout_material(Color(0.24, 0.12, 0.08), 0.95))


func _create_facade_details(dim: Vector3) -> void:
	var dark_trim := _cutout_material(Color(0.20, 0.20, 0.22), 0.85)
	var glass_mat := _cutout_material(Color(0.18, 0.28, 0.38), 0.25, 0.4)
	var half_x := dim.x * 0.5
	var half_z := dim.z * 0.5

	# Marquise / Toldo sobre a porta
	_create_box("Awning", Vector3(3.2, 0.12, 1.2), Vector3(0.0, 2.5, -half_z - 0.5), dark_trim)

	# Rodape exterior de pedra / fundacao
	var base_h := 0.45
	_create_box("TrimLeft", Vector3(0.46, base_h, dim.z + 0.06), Vector3(-half_x, base_h * 0.5, 0.0), dark_trim)
	_create_box("TrimRight", Vector3(0.46, base_h, dim.z + 0.06), Vector3(half_x, base_h * 0.5, 0.0), dark_trim)
	_create_box("TrimBack", Vector3(dim.x + 0.06, base_h, 0.46), Vector3(0.0, base_h * 0.5, half_z), dark_trim)

	# Janelas e vitrines da fachada
	if venue_kind in [STORE, GROCERY, MALL]:
		var win_w := (half_x - 1.6)
		if win_w > 1.0:
			_create_box("ShowcaseL", Vector3(win_w, 2.0, 0.08), Vector3(-(1.5 + win_w * 0.5), 1.6, -half_z - 0.21), glass_mat)
			_create_box("ShowcaseR", Vector3(win_w, 2.0, 0.08), Vector3(1.5 + win_w * 0.5, 1.6, -half_z - 0.21), glass_mat)
	else:
		_create_box("WinSideL1", Vector3(0.08, 1.4, 1.6), Vector3(-half_x - 0.21, 2.0, -1.5), glass_mat)
		_create_box("WinSideL2", Vector3(0.08, 1.4, 1.6), Vector3(-half_x - 0.21, 2.0, 1.5), glass_mat)
		_create_box("WinSideR1", Vector3(0.08, 1.4, 1.6), Vector3(half_x + 0.21, 2.0, -1.5), glass_mat)
		_create_box("WinSideR2", Vector3(0.08, 1.4, 1.6), Vector3(half_x + 0.21, 2.0, 1.5), glass_mat)
		_create_box("WinBack", Vector3(2.0, 1.4, 0.08), Vector3(0.0, 2.0, half_z + 0.21), glass_mat)


func _create_interior_lighting(dim: Vector3) -> void:
	var fixture_mat := StandardMaterial3D.new()
	fixture_mat.albedo_color = Color(0.95, 0.90, 0.70)
	fixture_mat.emission_enabled = true
	fixture_mat.emission = Color(0.95, 0.90, 0.70)
	fixture_mat.emission_energy_multiplier = 0.8
	_create_box("CeilingLamp", Vector3(0.8, 0.08, 0.8), Vector3(0.0, dim.y - 0.05, 0.0), fixture_mat)

	var light := OmniLight3D.new()
	light.name = "InteriorLight"
	light.light_color = Color(1.0, 0.92, 0.75)
	light.light_energy = 1.25
	light.omni_range = maxf(dim.x, dim.z) * 0.8
	light.position = Vector3(0.0, dim.y - 0.4, 0.0)
	add_child(light)


func _create_interior(dimensions: Vector3) -> void:
	var mat := _cutout_material(wall_color.darkened(0.12), 0.92)
	match venue_kind:
		HOUSE:
			_create_house_layout(dimensions, mat)
		STORE:
			_create_store_layout(dimensions, mat)
		GROCERY:
			_create_grocery_layout(dimensions, mat)
		APARTMENT:
			_create_apartment_layout(dimensions, mat)
		MALL:
			_create_mall_layout(dimensions, mat)


func _create_house_layout(dim: Vector3, mat: Material) -> void:
	var wall_h := dim.y * 0.85
	var thick := 0.3
	_create_partition_x("HallWall", -3.8, 3.8, 0.2, 0.0, 1.8, wall_h, thick, mat)
	_create_partition_z("BedWall", 0.2, 3.8, 0.8, 1.8, 1.4, wall_h, thick, mat)
	# Balcao da cozinha
	var counter_mat := _cutout_material(Color(0.28, 0.22, 0.18), 0.8)
	_create_box_with_collision("KitchenCounter", Vector3(2.2, 0.9, 0.6), Vector3(-2.2, 0.45, 1.6), counter_mat)


func _create_store_layout(dim: Vector3, mat: Material) -> void:
	var wall_h := dim.y * 0.85
	var thick := 0.3
	_create_partition_x("StockWall", -4.8, 4.8, 1.0, -1.5, 2.0, wall_h, thick, mat)
	_create_partition_z("OfficeWall", 1.0, 4.3, 1.5, 2.5, 1.4, wall_h, thick, mat)
	# Balcao de atendimento e caixa
	var counter_mat := _cutout_material(Color(0.25, 0.24, 0.22), 0.75)
	_create_box_with_collision("ServiceCounter", Vector3(2.6, 0.95, 0.7), Vector3(2.0, 0.475, -1.2), counter_mat)
	# Estante de estoque
	_create_box_with_collision("StockRack", Vector3(2.8, 1.8, 0.5), Vector3(2.8, 0.9, 2.8), counter_mat)


func _create_grocery_layout(dim: Vector3, mat: Material) -> void:
	var wall_h := dim.y * 0.85
	var thick := 0.35
	_create_partition_x("BackroomWall", -6.8, 6.8, 1.8, 0.0, 2.6, wall_h, thick, mat)
	_create_partition_z("ColdStorageWall", 1.8, 5.3, -2.5, 3.4, 1.6, wall_h, thick, mat)
	# Balcao de caixa
	var counter_mat := _cutout_material(Color(0.26, 0.28, 0.30), 0.8)
	_create_box_with_collision("CheckoutStand", Vector3(2.2, 0.9, 0.6), Vector3(-3.2, 0.45, -2.5), counter_mat)
	# Gondola central de supermercado
	_create_box_with_collision("GroceryAisle", Vector3(3.8, 1.6, 0.8), Vector3(0.0, 0.8, -0.6), counter_mat)


func _create_apartment_layout(dim: Vector3, mat: Material) -> void:
	var wall_h := dim.y * 0.85
	var thick := 0.3
	_create_partition_z("LeftHall", -4.8, 4.8, -1.3, -1.0, 1.8, wall_h, thick, mat)
	_create_partition_z("RightHall", -4.8, 4.8, 1.3, -1.0, 1.8, wall_h, thick, mat)
	_create_partition_x("UnitAWall", -5.3, -1.3, 0.5, -3.3, 1.5, wall_h, thick, mat)
	_create_partition_x("UnitBWall", 1.3, 5.3, 0.5, 3.3, 1.5, wall_h, thick, mat)
	# Portaria / Console da entrada
	var desk_mat := _cutout_material(Color(0.26, 0.22, 0.20), 0.8)
	_create_box_with_collision("LobbyDesk", Vector3(1.8, 0.95, 0.5), Vector3(0.0, 0.475, -2.8), desk_mat)


func _create_mall_layout(dim: Vector3, mat: Material) -> void:
	var wall_h := dim.y * 0.85
	var thick := 0.35
	_create_partition_z("LeftShopWall", -6.6, 2.5, -2.0, -2.0, 2.4, wall_h, thick, mat)
	_create_partition_z("RightShopWall", -6.6, 2.5, 2.0, -2.0, 2.4, wall_h, thick, mat)
	_create_partition_x("CourtWall", -7.2, 7.2, 2.5, 0.0, 3.0, wall_h, thick, mat)
	_create_box_with_collision("Pillar1", Vector3(0.8, dim.y, 0.8), Vector3(-1.0, dim.y * 0.5, 0.0), mat)
	_create_box_with_collision("Pillar2", Vector3(0.8, dim.y, 0.8), Vector3(1.0, dim.y * 0.5, 0.0), mat)
	# Canteiro / Expositor central da praca
	var planter_mat := _cutout_material(Color(0.25, 0.32, 0.22), 0.85)
	_create_box_with_collision("CenterCourt", Vector3(2.4, 0.4, 2.4), Vector3(0.0, 0.2, 4.6), planter_mat)


func _spawn_building_ammo(dim: Vector3) -> void:
	var pickup := AMMO_PICKUP_SCENE.instantiate() as Node3D
	var spawn_pos := Vector3(0.0, 0.15, 0.0)
	if venue_kind == HOUSE:
		spawn_pos = Vector3(2.2, 0.15, 2.2)
	elif venue_kind == STORE:
		spawn_pos = Vector3(2.0, 0.15, 2.5)
	elif venue_kind == GROCERY:
		spawn_pos = Vector3(3.5, 0.15, 3.2)
	elif venue_kind == APARTMENT:
		spawn_pos = Vector3(3.2, 0.15, 2.6)
	elif venue_kind == MALL:
		spawn_pos = Vector3(-3.5, 0.15, 0.0)
	pickup.position = spawn_pos
	add_child(pickup)


func _create_partition_x(
		w_name: String, start_x: float, end_x: float, z_pos: float,
		door_x: float, door_w: float, height: float, thick: float, mat: Material
) -> void:
	var left_w := (door_x - door_w * 0.5) - start_x
	if left_w > 0.1:
		_create_box_with_collision(w_name + "Left", Vector3(left_w, height, thick), Vector3(start_x + left_w * 0.5, height * 0.5, z_pos), mat)
	var right_w := end_x - (door_x + door_w * 0.5)
	if right_w > 0.1:
		_create_box_with_collision(w_name + "Right", Vector3(right_w, height, thick), Vector3(end_x - right_w * 0.5, height * 0.5, z_pos), mat)


func _create_partition_z(
		w_name: String, start_z: float, end_z: float, x_pos: float,
		door_z: float, door_w: float, height: float, thick: float, mat: Material
) -> void:
	var front_len := (door_z - door_w * 0.5) - start_z
	if front_len > 0.1:
		_create_box_with_collision(w_name + "Front", Vector3(thick, height, front_len), Vector3(x_pos, height * 0.5, start_z + front_len * 0.5), mat)
	var back_len := end_z - (door_z + door_w * 0.5)
	if back_len > 0.1:
		_create_box_with_collision(w_name + "Back", Vector3(thick, height, back_len), Vector3(x_pos, height * 0.5, end_z - back_len * 0.5), mat)


func _create_box_with_collision(node_name: String, box_size: Vector3, box_position: Vector3, material: Material) -> void:
	_create_box(node_name, box_size, box_position, material)
	var shape := BoxShape3D.new()
	shape.size = box_size
	var collision := CollisionShape3D.new()
	collision.name = node_name + "Collision"
	collision.position = box_position
	collision.shape = shape
	add_child(collision)


func _create_box(node_name: String, box_size: Vector3, box_position: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = box_position
	instance.mesh = mesh
	add_child(instance)


func _cutout_material(color: Color, roughness: float, metallic: float = 0.0) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CUTOUT_SHADER
	material.set_shader_parameter("base_color", color)
	material.set_shader_parameter("material_roughness", roughness)
	material.set_shader_parameter("material_metallic", metallic)
	return material
