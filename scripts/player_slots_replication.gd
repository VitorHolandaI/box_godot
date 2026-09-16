class_name PlayerSlotsReplication
extends RefCounted

## Decide quando o dicionario de slots de arma (a parte grande do estado do
## jogador) entra no snapshot: nas RESEND_SNAPSHOTS seguintes a cada mudanca de
## revisao (o snapshot e nao confiavel) e, fora isso, a cada REFRESH_SNAPSHOTS
## para quem acabou de entrar. A fase do refresh vem da chave do jogador, para
## os slots de todos nao cairem no mesmo snapshot.
## Uso:
##   var tracker := PlayerSlotsReplication.new()
##   if tracker.should_include(key, weapon_slots.revision, snapshot_sequence): incluir()

const RESEND_SNAPSHOTS := 3
const REFRESH_SNAPSHOTS := 20

var _last_revision: Dictionary = {}
var _resend_left: Dictionary = {}


## Uso: tracker.should_include("123:0", 7, 4012)
func should_include(key: String, revision: int, snapshot_sequence: int) -> bool:
	if int(_last_revision.get(key, -1)) != revision:
		_last_revision[key] = revision
		_resend_left[key] = RESEND_SNAPSHOTS
	var left := int(_resend_left.get(key, 0))
	if left > 0:
		_resend_left[key] = left - 1
		return true
	return refresh_due(key, snapshot_sequence)


## Uso: PlayerSlotsReplication.refresh_due("123:0", 40)
static func refresh_due(key: String, snapshot_sequence: int) -> bool:
	return posmod(snapshot_sequence + absi(key.hash()), REFRESH_SNAPSHOTS) == 0


## Jogador saiu: esquece a revisao para nao crescer sem limite.
## Uso: tracker.forget("123:0")
func forget(key: String) -> void:
	_last_revision.erase(key)
	_resend_left.erase(key)
