class_name ProceduralStreetLightAssembler
extends RefCounted

## Postes de iluminacao ao longo das ruas procedurais, na mesma escala dos
## carros do pacote urbano (o modelo tem ~0.96 m; em escala 6 fica ~5.8 m,
## cerca de 2.5x a altura do jogador). Postes nunca caem dentro de lotes.
## Uso: ProceduralStreetLightAssembler.assemble(city_blueprint, parent, [safehouse_rect])

const STREETLIGHT_MODEL := "res://assets/models/city/streetlight.gltf"
const STREETLIGHT_SCALE := 6.0
const SPACING := 22.0
const CURB_CLEARANCE := 1.2
const MIN_LIGHT_DISTANCE := 8.0
const LOT_CLEARANCE := 1.0


## Espalha postes nas duas margens alternadas de cada trecho de rua.
## `blocked_areas` sao retangulos extras (x, z) onde nao pode haver poste.
## Uso: ProceduralStreetLightAssembler.assemble(city, self, [Rect2(-17, 4, 13, 13)])
static func assemble(city, parent: Node3D, blocked_areas: Array[Rect2] = []) -> int:
	var light_scene := load(STREETLIGHT_MODEL) as PackedScene
	if light_scene == null:
		push_error("Modelo de poste nao encontrado em '%s'; esperado PackedScene glTF." % STREETLIGHT_MODEL)
		return 0
	var blocked := _lot_areas(city)
	blocked.append_array(blocked_areas)
	var placed: Array[Vector2] = []
	for road in city.roads:
		if road.road_type == "alley":
			continue
		for placement in light_placements(road):
			var point: Vector2 = placement["position"]
			if _is_blocked(point, blocked) or _is_on_any_road(point, city.roads) or _is_near_existing(point, placed):
				continue
			placed.append(point)
			parent.add_child(_create_light(light_scene, point, placement["facing"]))
	return placed.size()


## Posicoes candidatas de um trecho: a cada SPACING, alternando a margem, com o
## braco da luminaria virado para o eixo da rua.
## Uso: var spots := ProceduralStreetLightAssembler.light_placements(road)
static func light_placements(road) -> Array[Dictionary]:
	var placements: Array[Dictionary] = []
	var along: Vector2 = road.finish - road.start
	var length := along.length()
	if length < 1.0:
		return placements
	var direction := along / length
	var normal := Vector2(-direction.y, direction.x)
	var side_offset: float = road.width * 0.5 + CURB_CLEARANCE
	var index := 0
	var distance := SPACING * 0.5
	while distance < length:
		var side := 1.0 if index % 2 == 0 else -1.0
		placements.append({
			"position": road.start + direction * distance + normal * side_offset * side,
			"facing": -normal * side,
		})
		distance += SPACING
		index += 1
	return placements


static func _create_light(scene: PackedScene, point: Vector2, facing: Vector2) -> Node3D:
	var light := scene.instantiate() as Node3D
	light.name = "StreetLight"
	light.position = Vector3(point.x, 0.12, point.y)
	# O braco do modelo aponta para -X local; gira para apontar para a rua.
	light.rotation.y = atan2(facing.y, -facing.x)
	light.scale = Vector3.ONE * STREETLIGHT_SCALE
	return light


static func _lot_areas(city) -> Array[Rect2]:
	var areas: Array[Rect2] = []
	for block in city.blocks:
		for lot in block.lots:
			if lot.building == null:
				continue
			var size: Vector2 = lot.building_footprint_size()
			areas.append(Rect2(lot.position - size * 0.5, size).grow(LOT_CLEARANCE))
	return areas


static func _is_blocked(point: Vector2, areas: Array[Rect2]) -> bool:
	for area in areas:
		if area.has_point(point):
			return true
	return false


## Evita postes plantados no asfalto de uma rua transversal nos cruzamentos.
static func _is_on_any_road(point: Vector2, roads: Array) -> bool:
	for road in roads:
		var closest := Geometry2D.get_closest_point_to_segment(point, road.start, road.finish)
		if closest.distance_to(point) < road.width * 0.5 + CURB_CLEARANCE * 0.5:
			return true
	return false


static func _is_near_existing(point: Vector2, placed: Array[Vector2]) -> bool:
	for other in placed:
		if other.distance_to(point) < MIN_LIGHT_DISTANCE:
			return true
	return false
