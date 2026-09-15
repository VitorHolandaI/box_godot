class_name ProceduralStairAssembler
extends RefCounted

const BOX_BUILDER: GDScript = preload("res://scripts/procedural/assemblers/box_builder.gd")
const BUILDING_MATERIALS: GDScript = preload("res://scripts/procedural/assemblers/building_materials.gd")

## Monta lajes com vao, lances de escada, rampas de colisao e guarda-corpos a
## partir de `building.stair_flights`. A rampa usa o comprimento real da
## inclinacao para que a superficie termine exatamente no topo da laje de cima.
## Uso:
##   ProceduralStairAssembler.add_floor_slab(body, building, 1, 3.4, material)
##   ProceduralStairAssembler.add_flights(body, building)

const SLAB_THICKNESS := 0.12
const RAMP_THICKNESS := 0.14
const RAMP_BURY_LENGTH := 0.15
# Com topo rente a laje, a quina da laje (somada ao safe_margin do CharacterBody)
# aparece como parede de ~50 graus e trava quem sobe. O topo fica 4 cm acima: quem
# desce passa por um degrau que a esfera da capsula vence com contato de ~22 graus.
const RAMP_TOP_LIFT := 0.04
const STEP_COUNT := 10
const HOLE_MARGIN := 0.2
const RAILING_HEIGHT := 1.0
const RAILING_THICKNESS := 0.08


## Laje do andar; acima do terreo ela recebe o vao do lance que chega nela.
## Uso: ProceduralStairAssembler.add_floor_slab(body, building, floor_index, floor_y, material)
static func add_floor_slab(body: StaticBody3D, building, floor_index: int, floor_y: float, material: Material) -> void:
	var arriving_flight := flight_arriving_at(building, floor_index)
	if arriving_flight.is_empty():
		BOX_BUILDER.add_box(body, "Floor_%d" % floor_index, Vector3(building.width, SLAB_THICKNESS, building.depth), Vector3(building.width * 0.5, floor_y, building.depth * 0.5), material, true)
		return
	var hole := flight_hole_rect(arriving_flight)
	var width: float = building.width
	var depth: float = building.depth
	_add_slab_piece(body, "Floor_%d_Left" % floor_index, Rect2(0.0, 0.0, hole.position.x, depth), floor_y, material)
	_add_slab_piece(body, "Floor_%d_Right" % floor_index, Rect2(hole.end.x, 0.0, width - hole.end.x, depth), floor_y, material)
	_add_slab_piece(body, "Floor_%d_Front" % floor_index, Rect2(hole.position.x, 0.0, hole.size.x, hole.position.y), floor_y, material)
	_add_slab_piece(body, "Floor_%d_Back" % floor_index, Rect2(hole.position.x, hole.end.y, hole.size.x, depth - hole.end.y), floor_y, material)
	_add_hole_railings(body, arriving_flight, floor_index, floor_y)


## Degraus visuais e rampa de colisao de cada lance.
## Uso: ProceduralStairAssembler.add_flights(body, building)
static func add_flights(body: StaticBody3D, building) -> void:
	var step_material: Material = BUILDING_MATERIALS.opaque(Color(0.35, 0.35, 0.37), building.floor_height, false, 0.0, 0.86, true)
	for flight in building.stair_flights:
		var floor_index := int(flight["floor_index"])
		var base_y: float = float(floor_index) * building.floor_height
		_add_steps(body, flight, base_y, building.floor_height, step_material)
		body.add_child(build_ramp_collision(flight, base_y, building.floor_height))


## Retangulo (x, z) do vao aberto na laje acima de um lance.
## Uso: var hole := ProceduralStairAssembler.flight_hole_rect(flight)
static func flight_hole_rect(flight: Dictionary) -> Rect2:
	var half_width := float(flight["width"]) * 0.5 + HOLE_MARGIN
	var near_z := minf(float(flight["bottom_z"]), float(flight["top_z"]))
	var far_z := maxf(float(flight["bottom_z"]), float(flight["top_z"]))
	return Rect2(float(flight["center_x"]) - half_width, near_z, half_width * 2.0, far_z - near_z)


## Rampa inclinada cuja face superior liga o topo da laje de baixo a borda da
## laje de cima (RAMP_TOP_LIFT acima dela). O excesso de comprimento fica
## enterrado no pe do lance, nunca no topo.
## Uso: body.add_child(ProceduralStairAssembler.build_ramp_collision(flight, 0.0, 3.4))
static func build_ramp_collision(flight: Dictionary, base_y: float, floor_height: float) -> CollisionShape3D:
	var surface_offset := SLAB_THICKNESS * 0.5
	var bottom := Vector3(float(flight["center_x"]), base_y + surface_offset, float(flight["bottom_z"]))
	var top := Vector3(float(flight["center_x"]), base_y + floor_height + surface_offset + RAMP_TOP_LIFT, float(flight["top_z"]))
	var along := (top - bottom).normalized()
	var up_axis := Vector3.RIGHT.cross(along).normalized()
	if up_axis.y < 0.0:
		up_axis = -up_axis
	var slope_length := bottom.distance_to(top)
	var shape := BoxShape3D.new()
	shape.size = Vector3(float(flight["width"]), RAMP_THICKNESS, slope_length + RAMP_BURY_LENGTH)
	var ramp := CollisionShape3D.new()
	ramp.name = "StairRamp_%d" % int(flight["floor_index"])
	ramp.shape = shape
	var center := (bottom + top) * 0.5 - up_axis * RAMP_THICKNESS * 0.5 - along * RAMP_BURY_LENGTH * 0.5
	ramp.transform = Transform3D(Basis(Vector3.RIGHT, up_axis, Vector3.RIGHT.cross(up_axis)), center)
	return ramp


## Lance que termina no andar `floor_index` (o terraco e o andar `floors`), ou {}.
## Uso: var flight := ProceduralStairAssembler.flight_arriving_at(building, building.floors)
static func flight_arriving_at(building, floor_index: int) -> Dictionary:
	for flight in building.stair_flights:
		if int(flight["floor_index"]) + 1 == floor_index:
			return flight
	return {}


static func _add_steps(body: StaticBody3D, flight: Dictionary, base_y: float, floor_height: float, material: Material) -> void:
	var bottom_z := float(flight["bottom_z"])
	var top_z := float(flight["top_z"])
	var step_run := (top_z - bottom_z) / float(STEP_COUNT)
	for step in STEP_COUNT:
		var height := floor_height / float(STEP_COUNT) * float(step + 1)
		var z := bottom_z + step_run * (float(step) + 0.5)
		var size := Vector3(float(flight["width"]), height, absf(step_run))
		BOX_BUILDER.add_box(body, "Stair_%d_%d" % [int(flight["floor_index"]), step], size, Vector3(float(flight["center_x"]), base_y + height * 0.5, z), material, false)


## Guarda-corpo nas duas laterais do vao e na borda do pe do lance; a borda
## de chegada fica livre para quem sobe.
static func _add_hole_railings(body: StaticBody3D, flight: Dictionary, floor_index: int, floor_y: float) -> void:
	var hole := flight_hole_rect(flight)
	var rail_material: Material = BUILDING_MATERIALS.opaque(Color(0.16, 0.16, 0.17), BUILDING_MATERIALS.DEFAULT_FLOOR_HEIGHT)
	var rail_y := floor_y + RAILING_HEIGHT * 0.5
	var center_z := hole.position.y + hole.size.y * 0.5
	BOX_BUILDER.add_box(body, "StairRailLeft_%d" % floor_index, Vector3(RAILING_THICKNESS, RAILING_HEIGHT, hole.size.y), Vector3(hole.position.x, rail_y, center_z), rail_material, true)
	BOX_BUILDER.add_box(body, "StairRailRight_%d" % floor_index, Vector3(RAILING_THICKNESS, RAILING_HEIGHT, hole.size.y), Vector3(hole.end.x, rail_y, center_z), rail_material, true)
	var foot_z := float(flight["bottom_z"])
	BOX_BUILDER.add_box(body, "StairRailFoot_%d" % floor_index, Vector3(hole.size.x, RAILING_HEIGHT, RAILING_THICKNESS), Vector3(hole.position.x + hole.size.x * 0.5, rail_y, foot_z), rail_material, true)


static func _add_slab_piece(body: StaticBody3D, piece_name: String, area: Rect2, floor_y: float, material: Material) -> void:
	if area.size.x <= 0.05 or area.size.y <= 0.05:
		return
	BOX_BUILDER.add_box(body, piece_name, Vector3(area.size.x, SLAB_THICKNESS, area.size.y), Vector3(area.position.x + area.size.x * 0.5, floor_y, area.position.y + area.size.y * 0.5), material, true)

