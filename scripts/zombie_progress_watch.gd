class_name ZombieProgressWatch
extends RefCounted

## Mede se um zumbi perseguindo um alvo esta de fato avancando. Amostra a cada
## SAMPLE_INTERVAL: `blocked_seconds` conta amostras seguidas quase paradas
## (encostado em parede ou quina); `no_progress_seconds` conta o tempo desde a
## ultima vez que a distancia ate o alvo caiu PROGRESS_DISTANCE abaixo do melhor
## valor (pega quem desliza sem fim ao longo de um muro). Trocar de alvo zera.
## Uso:
##   watch.update(delta, zombie.global_position, target.global_position)
##   if watch.blocked_seconds >= 2.0: comecar_desvio()

const SAMPLE_INTERVAL := 1.0
const MIN_SPEED := 0.35
const PROGRESS_DISTANCE := 1.5

var blocked_seconds := 0.0
var no_progress_seconds := 0.0
var _elapsed := 0.0
var _has_sample := false
var _last_position := Vector3.ZERO
var _best_distance := INF


## Registra o tempo de perseguicao; so avalia no fim de cada janela.
## Uso: watch.update(1.0 / 60.0, global_position, target.global_position)
func update(delta: float, position: Vector3, target_position: Vector3) -> void:
	_elapsed += maxf(delta, 0.0)
	if _elapsed < SAMPLE_INTERVAL:
		return
	var window := _elapsed
	_elapsed = 0.0
	var distance := position.distance_to(target_position)
	if not _has_sample:
		_has_sample = true
		_last_position = position
		_best_distance = distance
		return
	var moved := position.distance_to(_last_position)
	_last_position = position
	blocked_seconds = blocked_seconds + window if moved < MIN_SPEED * window else 0.0
	if distance < _best_distance - PROGRESS_DISTANCE:
		_best_distance = distance
		no_progress_seconds = 0.0
		return
	no_progress_seconds += window


## Zera as medidas (novo alvo, ataque corpo a corpo ou zumbi realocado).
## Uso: watch.reset()
func reset() -> void:
	blocked_seconds = 0.0
	no_progress_seconds = 0.0
	_elapsed = 0.0
	_has_sample = false
	_best_distance = INF
