class_name ZombieCrowdSlots
extends RefCounted

## Fila de ataque por jogador, estilo Left 4 Dead: no maximo
## MAX_ATTACKERS_PER_TARGET zumbis batem no mesmo alvo; os outros que chegam a
## HOLD_DISTANCE esperam parados (sem move_and_slide) ate abrir vaga. Sem isso a
## horda que nao cabia no anel ficava escorregando entre o flock (1,6 m) e o
## alvo, e na VPS move_and_slide chegou a 88 ms num frame (0004fbb).
## Atacante que nao se registra por ATTACKER_TTL_FRAMES (morreu, alvo fugiu)
## libera a vaga.
## Uso:
##   ZombieCrowdSlots.shared.register_attacker(target.get_instance_id(), get_instance_id(), Engine.get_physics_frames())
##   if ZombieCrowdSlots.shared.should_wait(target_id, my_id, distance, frame): segurar()

const MAX_ATTACKERS_PER_TARGET := 8
const HOLD_DISTANCE := 3.0
## Cobre o maior atraso do orcamento de tick perto do jogador (1 + 3 extras).
const ATTACKER_TTL_FRAMES := 6

static var shared := ZombieCrowdSlots.new()

## target_id -> {attacker_id: ultimo physics frame em que bateu}
var _attackers_by_target: Dictionary = {}


## Zumbi em alcance de golpe ocupa (ou renova) uma vaga no alvo.
## Uso: slots.register_attacker(target_id, zombie_id, Engine.get_physics_frames())
func register_attacker(target_id: int, attacker_id: int, physics_frame: int) -> void:
	if not _attackers_by_target.has(target_id):
		_attackers_by_target[target_id] = {}
	var attackers: Dictionary = _attackers_by_target[target_id]
	attackers[attacker_id] = physics_frame


## true quando o anel do alvo esta cheio e este zumbi, fora dele, ja chegou perto.
## Uso: if slots.should_wait(target_id, zombie_id, 2.4, frame): velocity = Vector3.ZERO
func should_wait(target_id: int, zombie_id: int, distance: float, physics_frame: int) -> bool:
	if distance > HOLD_DISTANCE or not _attackers_by_target.has(target_id):
		return false
	var attackers: Dictionary = _attackers_by_target[target_id]
	_drop_expired(attackers, physics_frame)
	if attackers.has(zombie_id):
		return false
	return attackers.size() >= MAX_ATTACKERS_PER_TARGET


func _drop_expired(attackers: Dictionary, physics_frame: int) -> void:
	for attacker_id in attackers.keys():
		if physics_frame - int(attackers[attacker_id]) > ATTACKER_TTL_FRAMES:
			attackers.erase(attacker_id)
