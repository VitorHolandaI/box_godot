class_name ZombieWallDetour
extends RefCounted

## Desvio de parede para zumbis na rua (sem rota de navmesh), no estilo "bug
## algorithm": depois de TRIGGER_BLOCKED_SECONDS parado contra um obstaculo,
## segue a parede pela tangente ate a linha reta ate o alvo ficar livre (ou ate
## MAX_DETOUR_SECONDS). Um desvio curto de tempo fixo nao bastava: ao acabar, a
## linha reta puxava o zumbi de volta para o mesmo ponto do muro. O lado inicial
## e o mais alinhado com o alvo; se bloquear de novo sem ter saido do lugar
## (quina concava), troca de lado.
## Uso:
##   var clear := detour.is_active() and _has_line_of_sight(target)
##   direction = detour.steer(delta, global_position, direction, watch.blocked_seconds, wall_normal, clear)

const TRIGGER_BLOCKED_SECONDS := 1.0
const MIN_DETOUR_SECONDS := 0.5
const MAX_DETOUR_SECONDS := 8.0
const FLIP_WINDOW_SECONDS := 4.0
const WALL_PUSH := 0.3
const DEAD_END_DISTANCE := 1.5

var _elapsed := 0.0
var _active := false
var _since_last_detour := INF
var _side := 1.0
var _direction := Vector3.ZERO
var _start_position := Vector3.INF


## Direcao horizontal a seguir neste tick: a desejada ou a do desvio em curso.
## `wall_normal` e zero quando nao ha parede encostada; `line_to_target_clear`
## so e consultado durante o desvio.
## Uso: var direction := detour.steer(1.0 / 60.0, global_position, desired, 1.2, Vector3.LEFT, false)
func steer(delta: float, position: Vector3, desired: Vector3, blocked_seconds: float, wall_normal: Vector3, line_to_target_clear: bool) -> Vector3:
	var step := maxf(delta, 0.0)
	_since_last_detour += step
	var flat_normal := Vector3(wall_normal.x, 0.0, wall_normal.z)
	var touching_wall := flat_normal.length_squared() >= 0.01
	if _active:
		return _continue_detour(step, desired, flat_normal, touching_wall, line_to_target_clear)
	if blocked_seconds < TRIGGER_BLOCKED_SECONDS or not touching_wall:
		return desired
	var tangent := _tangent(flat_normal.normalized())
	var toward_target := 1.0 if tangent.dot(desired) >= 0.0 else -1.0
	var dead_end := _since_last_detour < FLIP_WINDOW_SECONDS and position.distance_to(_start_position) < DEAD_END_DISTANCE
	_side = -_side if dead_end else toward_target
	_start_position = position
	_active = true
	_elapsed = 0.0
	_direction = (tangent * _side + flat_normal.normalized() * WALL_PUSH).normalized()
	return _direction


func _continue_detour(step: float, desired: Vector3, flat_normal: Vector3, touching_wall: bool, line_to_target_clear: bool) -> Vector3:
	_elapsed += step
	var clear_enough := line_to_target_clear and _elapsed >= MIN_DETOUR_SECONDS
	if clear_enough or _elapsed >= MAX_DETOUR_SECONDS:
		_active = false
		_since_last_detour = 0.0
		return desired
	# Encostado numa parede nova (quina convexa), vira junto mantendo o lado.
	if touching_wall:
		_direction = (_tangent(flat_normal.normalized()) * _side + flat_normal.normalized() * WALL_PUSH).normalized()
	return _direction


static func _tangent(flat_normal: Vector3) -> Vector3:
	return Vector3(-flat_normal.z, 0.0, flat_normal.x)


func is_active() -> bool:
	return _active


## Cancela o desvio (zumbi realocado ou alvo trocado).
## Uso: detour.reset()
func reset() -> void:
	_active = false
	_elapsed = 0.0
	_since_last_detour = INF
	_side = 1.0
	_direction = Vector3.ZERO
	_start_position = Vector3.INF
