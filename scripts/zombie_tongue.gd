class_name ZombieTongue
extends RefCounted

## Lingua do puxador (estilo Smoker): de MIN_RANGE a MAX_RANGE e vendo o alvo,
## prende e puxa o jogador ate ele. Solta com BREAK_DAMAGE de dano levado
## durante a puxada, sem linha de visao, quando o jogador chega perto ou apos
## MAX_PULL_SECONDS; depois espera COOLDOWN_SECONDS.
## Uso:
##   if lingua.can_grab(distancia, ve_alvo): lingua.start()
##   var puxao := lingua.update(delta, pos_zumbi, pos_alvo, ve_alvo, dano_desde_o_bote)

const MIN_RANGE := 6.0
const MAX_RANGE := 14.0
const PULL_SPEED := 3.5
const PULL_DPS := 5.0
const BREAK_DAMAGE := 40
const RELEASE_DISTANCE := 1.6
const MAX_PULL_SECONDS := 4.0
const COOLDOWN_SECONDS := 8.0

var _pulling := false
var _elapsed := 0.0
var _cooldown := 0.0


func can_grab(distance: float, sees_target: bool) -> bool:
	return not _pulling and _cooldown <= 0.0 and sees_target and distance >= MIN_RANGE and distance <= MAX_RANGE


func start() -> void:
	_pulling = true
	_elapsed = 0.0


func is_pulling() -> bool:
	return _pulling


## Conta a recarga entre botes (chamado todo tick de simulacao).
## Uso: lingua.tick_cooldown(delta)
func tick_cooldown(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)


## Velocidade do puxao (do alvo para o zumbi) ou zero quando soltou.
## Uso: var puxao := lingua.update(delta, global_position, alvo.global_position, true, dano)
func update(delta: float, zombie_position: Vector3, target_position: Vector3, sees_target: bool, damage_since_grab: int) -> Vector3:
	if not _pulling:
		return Vector3.ZERO
	_elapsed += delta
	var offset := zombie_position - target_position
	offset.y = 0.0
	if damage_since_grab >= BREAK_DAMAGE or not sees_target or _elapsed >= MAX_PULL_SECONDS or offset.length() <= RELEASE_DISTANCE:
		release()
		return Vector3.ZERO
	return offset.normalized() * PULL_SPEED


func release() -> void:
	if _pulling:
		_cooldown = COOLDOWN_SECONDS
	_pulling = false
