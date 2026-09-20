class_name LotFeasibility
extends RefCounted

## Decide o arquetipo de cada lote por viabilidade, no lugar do sorteio seco:
## pontua area, quantos lados do lote dao para a rua, declive e distrito, e
## escolhe por peso. A ideia vem da atribuicao de edificio por restricao
## (Scharl et al., CESCG 2010) e do ZoneSpawnSystem do Cities Skylines 2 - a
## pesquisa completa esta em procedures/geracao-de-plantas-pesquisa.md.
##
## Uso:
##   var features := {
##       "area": 361.0, "street_sides": 2, "slope": 0.0,
##       "district": "urban", "survival": false,
##   }
##   var archetype := LotFeasibility.choose_archetype(features, rng)

const ARCHETYPES: Array[String] = ["house", "store", "grocery", "gun_shop", "apartment"]

## Acima deste declive (rise/run) o lote nao recebe construcao: casa em encosta
## ingreme flutua ou enterra. 0.35 ~ 19 graus.
const MAX_BUILDABLE_SLOPE := 0.35
## Distancia extra alem de meia-largura da rua para a calcada/afastamento. Uma
## lateral do lote a menos que isso do eixo da rua conta como frente de rua.
const STREET_MARGIN := 5.0
## Cosseno minimo entre a lateral do lote e o rumo da via para valer como frente:
## sem isso uma via perpendicular contaria so por encostar num canto do lote.
const STREET_PARALLEL_DOT := 0.7
## Area (m2) a partir da qual o lote comporta mercado e apartamento.
const LARGE_LOT_AREA := 300.0
## Area maxima (m2) de um lote de loja de esquina; acima disso a loja some.
const SMALL_LOT_AREA := 450.0
## Multiplicadores do modo sobrevivencia: o mapa quer casas, nao densidade.
const SURVIVAL_HOUSE_SCALE := 1.6
const SURVIVAL_COMMERCE_SCALE := 0.4
const SURVIVAL_APARTMENT_SCALE := 0.05


## Pesos por arquetipo (0 = nao cabe no lote). Uso:
##   var weights := LotFeasibility.archetype_weights(features)
static func archetype_weights(features: Dictionary) -> Dictionary:
	if not _features_are_valid(features):
		return _zero_weights()
	var slope := float(features["slope"])
	if slope > MAX_BUILDABLE_SLOPE:
		return _zero_weights()
	return {
		"house": _house_weight(features),
		"store": _store_weight(features),
		"grocery": _grocery_weight(features),
		"gun_shop": _gun_shop_weight(features),
		"apartment": _apartment_weight(features),
	}


## Escolhe um arquetipo por sorteio ponderado (deterministico pela seed do rng).
## Devolve "" quando nenhum arquetipo cabe (ex.: lote em declive forte).
## Uso: var archetype := LotFeasibility.choose_archetype(features, rng)
static func choose_archetype(features: Dictionary, pick_rng: RandomNumberGenerator) -> String:
	var weights := archetype_weights(features)
	var total := 0.0
	for archetype in ARCHETYPES:
		total += float(weights[archetype])
	if total <= 0.0:
		return ""
	var roll := pick_rng.randf() * total
	for archetype in ARCHETYPES:
		roll -= float(weights[archetype])
		if roll <= 0.0:
			return archetype
	return ARCHETYPES[ARCHETYPES.size() - 1]


## Quantas das quatro laterais do lote correm a menos de STREET_MARGIN de
## alguma via. Uso:
##   var sides := LotFeasibility.street_facing_sides(lot.position, lot.size, city.roads)
static func street_facing_sides(lot_position: Vector2, lot_size: Vector2, roads: Array) -> int:
	var min_corner := lot_position - lot_size * 0.5
	var max_corner := lot_position + lot_size * 0.5
	var sides: Array[Array] = [
		[Vector2(min_corner.x, min_corner.y), Vector2(max_corner.x, min_corner.y)],
		[Vector2(max_corner.x, min_corner.y), Vector2(max_corner.x, max_corner.y)],
		[Vector2(min_corner.x, max_corner.y), Vector2(max_corner.x, max_corner.y)],
		[Vector2(min_corner.x, min_corner.y), Vector2(min_corner.x, max_corner.y)],
	]
	var count := 0
	for side in sides:
		if _side_touches_street(side[0], side[1], roads):
			count += 1
	return count


## Uma lateral encosta na rua quando a via corre paralela a ela e o ponto medio
## fica dentro do alcance. Via perpendicular apenas toca um canto do lote, e
## isso nao e frente de rua. Uso: interno.
static func _side_touches_street(start: Vector2, finish: Vector2, roads: Array) -> bool:
	var side_dir := (finish - start).normalized()
	var midpoint := (start + finish) * 0.5
	for road in roads:
		var road_dir: Vector2 = (road.finish - road.start).normalized()
		if absf(side_dir.dot(road_dir)) < STREET_PARALLEL_DOT:
			continue
		var reach := float(road.width) * 0.5 + STREET_MARGIN
		if Geometry2D.get_closest_point_to_segment(midpoint, road.start, road.finish).distance_to(midpoint) <= reach:
			return true
	return false


## Casa cabe em qualquer lote plano; vale mais no subúrbio e longe da rua.
static func _house_weight(features: Dictionary) -> float:
	var weight := 3.0
	if String(features["district"]) == "suburban":
		weight += 3.0
	if int(features["street_sides"]) <= 1:
		weight += 2.0
	if int(features["street_sides"]) >= 3:
		weight -= 1.0
	if bool(features["survival"]):
		weight *= SURVIVAL_HOUSE_SCALE
	return maxf(weight, 0.0)


## Loja de esquina: lote pequeno, urbano e com frente de rua.
static func _store_weight(features: Dictionary) -> float:
	if int(features["street_sides"]) == 0:
		return 0.0
	var weight := 0.5
	if float(features["area"]) <= SMALL_LOT_AREA:
		weight += 1.0
	if String(features["district"]) == "urban":
		weight += 1.0
	if int(features["street_sides"]) >= 2:
		weight += 0.5
	if bool(features["survival"]):
		weight *= SURVIVAL_COMMERCE_SCALE
	return maxf(weight, 0.0)


## Mercado: lote grande e com duas frentes de rua para carga e descarga.
static func _grocery_weight(features: Dictionary) -> float:
	if int(features["street_sides"]) == 0:
		return 0.0
	var weight := 1.0
	if float(features["area"]) >= LARGE_LOT_AREA:
		weight += 1.0
	if int(features["street_sides"]) >= 2:
		weight += 1.0
	if String(features["district"]) == "urban":
		weight += 0.5
	if bool(features["survival"]):
		weight *= SURVIVAL_COMMERCE_SCALE
	return maxf(weight, 0.0)


## Loja de armas: comercio urbano de rua, rara e menor que mercado.
static func _gun_shop_weight(features: Dictionary) -> float:
	if int(features["street_sides"]) == 0 or String(features["district"]) != "urban":
		return 0.0
	var weight := 0.35
	if int(features["street_sides"]) >= 2:
		weight += 0.25
	if bool(features["survival"]):
		weight *= SURVIVAL_COMMERCE_SCALE
	return weight


## Apartamento: lote grande, denso e so em zona urbana.
static func _apartment_weight(features: Dictionary) -> float:
	if String(features["district"]) != "urban" or int(features["street_sides"]) < 2:
		return 0.0
	# 3.0 = zona urbana com as duas frentes de rua que a guarda exige.
	var weight := 3.0
	if float(features["area"]) >= LARGE_LOT_AREA:
		weight += 2.0
	if bool(features["survival"]):
		weight *= SURVIVAL_APARTMENT_SCALE
	return maxf(weight, 0.0)


## Valida as chaves e os dominios das caracteristicas; erro traz o valor errado.
static func _features_are_valid(features: Dictionary) -> bool:
	for key in ["area", "street_sides", "slope", "district", "survival"]:
		if not features.has(key):
			push_error("Caracteristicas do lote sem a chave '%s'; esperado %s." % [key, features.keys()])
			return false
	if float(features["area"]) < 0.0:
		push_error("Area do lote invalida: %s; esperado >= 0." % features["area"])
		return false
	if int(features["street_sides"]) < 0 or int(features["street_sides"]) > 4:
		push_error("Frentes de rua invalidas: %s; esperado inteiro entre 0 e 4." % features["street_sides"])
		return false
	return true


static func _zero_weights() -> Dictionary:
	var weights := {}
	for archetype in ARCHETYPES:
		weights[archetype] = 0.0
	return weights
