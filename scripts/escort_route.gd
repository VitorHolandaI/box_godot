# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name EscortRoute
extends RefCounted

## Esquinas (fim de rua) da serpentina da escolta e o lote regular de cada uma,
## onde vive o predio procedural que serve de parada ao checkpoint. Fica num
## modulo proprio porque o GERADOR e o diretor precisam do MESMO centro de lote:
## o gerador forca ali um predio de 1 andar (casa/mercearia) e o diretor acha a
## porta dele. Se cada lado calcular por conta propria, os dois nao batem.
##
## A serpentina e HORIZONTAL: parte de (-72,-72), anda a rua de baixo inteira
## para o leste, sobe uma rua, volta a proxima horizontal inteira para o oeste, e
## assim pelas quatro. A PONTA de cada fileira tem casa; a ultima fileira termina
## na safehouse, no noroeste.
##
## Por que uma casa por PONTA (relato de 2026-09-28: "eles entram em 2 casas
## quase na mesma esquina"): na serpentina vertical anterior, cada fileira comeca
## e termina na MESMA rua horizontal, entao as paradas saiam de duas em duas, a
## 48 m uma da outra. Com a fileira horizontal elas ficam a ~150 m.
## Uso: var esquinas := EscortRoute.checkpoint_corners()

const OUTER := 72.0
const INNER := 24.0
## As oito linhas de rua da cidade procedural (mesmos valores de ROAD_LINES no
## procedural/generators/city_generator.gd), em x e em z.
const ROAD_LINES: Array[float] = [-72.0, -24.0, 24.0, 72.0]
## Meia largura da faixa andavel de uma rua. A via vertical tem 6 m e a
## horizontal 7 m; vale a mais estreita, que e a que aperta.
const ROAD_HALF_WIDTH := 3.0
## Lote reservado para a safehouse de chegada: fim da ultima fileira, no
## noroeste, com a porta virada para a rua de cima. O gerador deixa este lote
## vazio e o scripts/city_generator.gd constroi a casa nele.
const SAFEHOUSE_LOT := Vector2(-58.5, 58.5)
## Rua por onde a familia entra na safehouse (a porta dela olha para +Z). E a
## rua da ULTIMA fileira. Anda junto com o final_street_approach do diretor, que
## deriva isso da porta.
const SAFEHOUSE_STREET_Z := 72.0
## Quais viradas de route_corners() tem casa: as pontas das fileiras 1, 2 e 3.
## A ponta da fileira 4 e a propria safehouse.
const CHECKPOINT_CORNER_INDICES: Array[int] = [0, 2, 4]
## Nascimento da escolta, no canto sudoeste. O diretor reexporta como
## ESCORT_START (e o que o main.gd e os testes usam).
const START := Vector3(-72.0, 1.0, -72.0)
## Folga minima entre um carro parado e o corredor que a familia anda. O trio
## vai a 1,2 m do eixo e o civil que encosta num RigidBody perde o passo: o
## desvio de parede o manda rodear e ele anda de volta pela rota.
const CAR_CLEARANCE := 6.0
## Espacamento do centro de bloco ao centro de lote na grade regular do gerador
## (BLOCK 42 com 2x2 lotes de 19). Ver _lot_position no city_generator.
const LOT_OFFSET := 10.5
const LOT_STEP := 21.0


## Todas as viradas da serpentina, na ordem: as quatro ruas horizontais inteiras
## ligadas pelas verticais de fora. A quarta fileira (z=72, para o oeste) nao tem
## virada: ela termina na safehouse.
static func route_corners() -> Array[Vector3]:
	return [
		Vector3(OUTER, 1.0, -OUTER),   # fim da fileira 1 (leste)   <- casa 1
		Vector3(OUTER, 1.0, -INNER),   # sobe uma rua pela leste
		Vector3(-OUTER, 1.0, -INNER),  # fim da fileira 2 (oeste)   <- casa 2
		Vector3(-OUTER, 1.0, INNER),   # sobe uma rua pela oeste
		Vector3(OUTER, 1.0, INNER),    # fim da fileira 3 (leste)   <- casa 3
		Vector3(OUTER, 1.0, OUTER),    # sobe uma rua; a fileira 4 termina na base
	]


## As viradas que tem casa: so as PONTAS de fileira. As outras sao a subida de
## uma rua para a fileira seguinte, onde a familia nao para.
static func checkpoint_corners() -> Array[Vector3]:
	var corners := route_corners()
	var stops: Array[Vector3] = []
	for index in CHECKPOINT_CORNER_INDICES:
		stops.append(corners[index])
	return stops


## Lote regular de cada checkpoint (mesma ordem das esquinas). O gerador usa
## para reconhecer o lote e forcar o arquetipo; o diretor, para achar a porta.
## Uso: for center in EscortRoute.checkpoint_lot_centers(): ...
static func checkpoint_lot_centers() -> Array[Vector2]:
	var centers: Array[Vector2] = []
	for corner in checkpoint_corners():
		centers.append(Vector2(_nearest_lot_axis(corner.x), _nearest_lot_axis(corner.z)))
	return centers


## Centro de lote regular mais proximo de uma coordenada de rua. Uso interno.
static func _nearest_lot_axis(value: float) -> float:
	var best := 0.0
	var best_distance := INF
	for block_center in [-48.0, 0.0, 48.0]:
		for side in [-LOT_OFFSET, LOT_OFFSET]:
			var candidate: float = block_center + side
			var distance := absf(value - candidate)
			if distance < best_distance:
				best = candidate
				best_distance = distance
	return best


## Espinha da rota: so os pontos DE RUA, do nascimento ate a frente da
## safehouse. A ida de cada checkpoint ate a porta da casa fica de fora de
## proposito (esse trecho sai da rua).
## Uso: for index in range(1, EscortRoute.street_spine().size()): ...
static func street_spine() -> Array[Vector3]:
	var spine: Array[Vector3] = [START]
	spine.append_array(route_corners())
	var last: Vector3 = spine[spine.size() - 1]
	spine.append(Vector3(last.x, START.y, SAFEHOUSE_STREET_Z))
	spine.append(Vector3(SAFEHOUSE_LOT.x, START.y, SAFEHOUSE_STREET_Z))
	return spine


## Distancia horizontal de um ponto ate a espinha. Pura: da para perguntar sem
## cena nenhuma montada.
## Uso: if EscortRoute.distance_to_street_spine(vaga) < CAR_CLEARANCE: pula
static func distance_to_street_spine(point: Vector3) -> float:
	var target := Vector2(point.x, point.z)
	var spine := street_spine()
	var best := INF
	for index in range(1, spine.size()):
		var from := Vector2(spine[index - 1].x, spine[index - 1].z)
		var to := Vector2(spine[index].x, spine[index].z)
		best = minf(best, _distance_to_segment(target, from, to))
	return best


## Distancia de um ponto ao segmento [from, to]. Uso interno.
static func _distance_to_segment(point: Vector2, from: Vector2, to: Vector2) -> float:
	var leg := to - from
	if leg.length_squared() < 0.0001:
		return point.distance_to(from)
	var travel := clampf((point - from).dot(leg) / leg.length_squared(), 0.0, 1.0)
	return point.distance_to(from + leg * travel)
