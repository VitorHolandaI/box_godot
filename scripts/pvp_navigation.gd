class_name PvpNavigation
extends RefCounted

## Desvio de obstaculo para os bots de PVP. O projeto NAO tem navmesh (nem
## NavigationServer3D em lugar nenhum), entao o bot anda reto para o waypoint e
## travava na primeira parede: ficava oscilando no mesmo canto ate estourar a
## rodada (medido: 80 s parado dentro da casa com o alvo a 126 m). Aqui a
## direcao desejada e corrigida por uma sonda curta na frente: o bot tenta ir
## reto, depois vira 25 graus para cada lado, 55 e 90 — a primeira direcao livre
## vence. E o classico "context steering" de uma linha, sem navmesh.
##
## Esta parte e PURA (recebe as distancias medidas) para poder ser testada sem
## mundo de fisica; quem faz os raycasts e o PlayerBotAI.
##
## Uso:
##   var dir := PvpNavigation.choose_direction(desejado, distancias_da_sonda)

## Angulos testados, em graus, na ordem de preferencia: reto primeiro, depois
## desvios pequenos (25) e so entao os grandes (55, 90).
const PROBE_ANGLES_DEG: Array[float] = [0.0, 25.0, -25.0, 55.0, -55.0, 90.0, -90.0]
## Comprimento da sonda: uma parede a menos de PROBE_LENGTH ja faz o bot desviar.
const PROBE_LENGTH := 2.0
## Distancia a partir da qual a direcao conta como livre.
const BLOCKED_BELOW := 1.2
## Altura do ponto de sonda em relacao ao pe do bot (na altura do peito).
const PROBE_HEIGHT := 0.9


## Direcao corrigida: a mais proxima da desejada que estiver livre. Se todas
## estiverem bloqueadas, devolve a com mais espaco (desempate: ordem de
## PROBE_ANGLES_DEG). Vetor desejado nulo devolve ZERO.
## Uso: var dir := PvpNavigation.choose_direction(Vector2.RIGHT, [2.0, 2.0, 0.4, 2.0, 1.9, 2.0, 2.0])
static func choose_direction(desired: Vector2, probe_distances: Array) -> Vector2:
	if desired.length() < 0.001:
		return Vector2.ZERO
	var base := desired.normalized()
	for index in PROBE_ANGLES_DEG.size():
		if _free_distance(probe_distances, index) >= BLOCKED_BELOW:
			return base.rotated(deg_to_rad(PROBE_ANGLES_DEG[index]))
	var best_index := 0
	var best_distance := -1.0
	for index in PROBE_ANGLES_DEG.size():
		var distance := _free_distance(probe_distances, index)
		if distance > best_distance:
			best_distance = distance
			best_index = index
	return base.rotated(deg_to_rad(PROBE_ANGLES_DEG[best_index]))


## Direcao lateral para sair do prego: perpendicular a desejada, com o lado
## alternando por vaga (bots vizinhos saem para lados opostos em vez de se
## amontoarem). Substitui a direcao aleatoria antiga, que fazia o bot voltar
## para dentro da casa. Uso: var dir := PvpNavigation.side_step(desejado, slot)
static func side_step(desired: Vector2, slot: int) -> Vector2:
	if desired.length() < 0.001:
		return Vector2.ZERO
	var sign := 1.0 if slot % 2 == 0 else -1.0
	return desired.normalized().rotated(deg_to_rad(90.0 * sign))


static func _free_distance(probe_distances: Array, index: int) -> float:
	if index >= probe_distances.size():
		return 0.0
	var value: Variant = probe_distances[index]
	return float(value) if value is float or value is int else 0.0
