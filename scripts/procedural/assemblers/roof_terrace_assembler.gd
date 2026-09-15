class_name ProceduralRoofTerraceAssembler
extends RefCounted

## Terraco acessivel no topo do predio: laje com o vao do ultimo lance, mureta
## em volta e casinha da escada fechada em tres lados, aberta do lado de chegada.
## Uso: ProceduralRoofTerraceAssembler.add_terrace(body, building, floor_material, wall_material)

const BOX_BUILDER: GDScript = preload("res://scripts/procedural/assemblers/box_builder.gd")
const STAIR_ASSEMBLER: GDScript = preload("res://scripts/procedural/assemblers/stair_assembler.gd")
const PARAPET_HEIGHT := 1.1
const PARAPET_THICKNESS := 0.2
const BULKHEAD_HEIGHT := 2.7
const BULKHEAD_WALL_THICKNESS := 0.12
const BULKHEAD_MARGIN := 0.35
const BULKHEAD_ROOF_THICKNESS := 0.14
# Altura extra do volume de navegacao acima do ultimo andar: inclui a laje e a
# mureta do terraco, mas deixa o teto da casinha fora (seria ilha inalcancavel).
const NAVIGATION_HEADROOM := 2.0


## Monta laje, mureta e casinha sobre o ultimo andar.
## Uso: ProceduralRoofTerraceAssembler.add_terrace(body, building, floor_material, wall_material)
static func add_terrace(body: StaticBody3D, building, floor_material: Material, wall_material: Material) -> void:
	var arriving: Dictionary = STAIR_ASSEMBLER.flight_arriving_at(building, building.floors)
	if arriving.is_empty():
		push_error("Terraco de '%s' sem lance chegando ao andar %d; esperado stair_flights com floor_index %d." % [building.archetype, building.floors, building.floors - 1])
		return
	var roof_y: float = float(building.floors) * building.floor_height
	STAIR_ASSEMBLER.add_floor_slab(body, building, building.floors, roof_y, floor_material)
	_add_parapet(body, building, roof_y, wall_material)
	_add_stair_bulkhead(body, arriving, roof_y, wall_material)


static func _add_parapet(body: StaticBody3D, building, roof_y: float, material: Material) -> void:
	var width: float = building.width
	var depth: float = building.depth
	var center_y := roof_y + PARAPET_HEIGHT * 0.5
	var half := PARAPET_THICKNESS * 0.5
	BOX_BUILDER.add_box(body, "RoofParapetFront", Vector3(width, PARAPET_HEIGHT, PARAPET_THICKNESS), Vector3(width * 0.5, center_y, half), material, true)
	BOX_BUILDER.add_box(body, "RoofParapetBack", Vector3(width, PARAPET_HEIGHT, PARAPET_THICKNESS), Vector3(width * 0.5, center_y, depth - half), material, true)
	BOX_BUILDER.add_box(body, "RoofParapetLeft", Vector3(PARAPET_THICKNESS, PARAPET_HEIGHT, depth), Vector3(half, center_y, depth * 0.5), material, true)
	BOX_BUILDER.add_box(body, "RoofParapetRight", Vector3(PARAPET_THICKNESS, PARAPET_HEIGHT, depth), Vector3(width - half, center_y, depth * 0.5), material, true)


## Paredes laterais e do pe do lance, mais o teto. O lado do topo do lance
## (onde se chega no terraco) fica aberto.
static func _add_stair_bulkhead(body: StaticBody3D, flight: Dictionary, roof_y: float, material: Material) -> void:
	var hole: Rect2 = STAIR_ASSEMBLER.flight_hole_rect(flight)
	var top_z := float(flight["top_z"])
	var foot_z := float(flight["bottom_z"]) + signf(float(flight["bottom_z"]) - top_z) * BULKHEAD_MARGIN
	var near_z := minf(top_z, foot_z)
	var span_z := absf(foot_z - top_z)
	var left_x := hole.position.x - BULKHEAD_MARGIN
	var right_x := hole.end.x + BULKHEAD_MARGIN
	var span_x := right_x - left_x
	var center_y := roof_y + BULKHEAD_HEIGHT * 0.5
	BOX_BUILDER.add_box(body, "RoofStairBulkheadLeft", Vector3(BULKHEAD_WALL_THICKNESS, BULKHEAD_HEIGHT, span_z), Vector3(left_x, center_y, near_z + span_z * 0.5), material, true)
	BOX_BUILDER.add_box(body, "RoofStairBulkheadRight", Vector3(BULKHEAD_WALL_THICKNESS, BULKHEAD_HEIGHT, span_z), Vector3(right_x, center_y, near_z + span_z * 0.5), material, true)
	BOX_BUILDER.add_box(body, "RoofStairBulkheadFoot", Vector3(span_x, BULKHEAD_HEIGHT, BULKHEAD_WALL_THICKNESS), Vector3(left_x + span_x * 0.5, center_y, foot_z), material, true)
	BOX_BUILDER.add_box(body, "RoofStairBulkheadRoof", Vector3(span_x + BULKHEAD_WALL_THICKNESS, BULKHEAD_ROOF_THICKNESS, span_z), Vector3(left_x + span_x * 0.5, roof_y + BULKHEAD_HEIGHT, near_z + span_z * 0.5), material, true)
