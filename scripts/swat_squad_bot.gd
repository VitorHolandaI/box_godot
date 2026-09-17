class_name SwatSquadBot
extends RefCounted

## Esquadrao SWAT: 4 soldados que sao jogadores de verdade simulados pelo
## servidor (mesmo PlayerBotAI do bot de teste) e nao um adorno preso no
## jogador. Escolhas de jogo:
## - nao entram no grupo "player": os zumbis ignoram eles (so atiram) e o GAME
##   OVER / revive / minimapa nao veem os bots;
## - invulneraveis (nada aplica dano) e sem colisao propria: nao travam zumbi
##   nem jogador, so o cenario;
## - Uzi e municao infinita: nao param para recarregar;
## - presos a um raio do jogador que chamou (leash), cacando zumbi por perto.
## Uso:
##   var key := SwatSquadBot.key_for(1, 0)
##   SwatSquadBot.configure(bot, 0)
##   if SwatSquadBot.is_swat_key(key): ...

const COUNT := 4
const DURATION_SECONDS := 20.0
## Leash medido do jogador que chamou: o bot volta quando passa disso.
const LEASH_DISTANCE := 40.0
## Distancia que ele mantem do alvo enquanto atira (Uzi e curta, mas ele nao
## quer ficar colado no zumbi).
const ENGAGE_DISTANCE := 3.0
const KEEP_DISTANCE := 6.5
## Onde ele fica quando nao ha zumbi: formacao em volta do dono, para nao
## empilhar os quatro no mesmo ponto.
const FORMATION_RADIUS := 3.2
## Id de peer reservado para os soldados (negativo: o ENet so atribui ids
## positivos). A chave precisa continuar no formato "peer:slot" que o
## PlayerSnapshotCodec valida, entao o esquadrao id vira o peer.
const NPC_PEER_ID_BASE := -1000
## Uso: var key := SwatSquadBot.key_for(squad_id, 2)
static func key_for(squad_id: int, index: int) -> String:
	return "%d:%d" % [NPC_PEER_ID_BASE - squad_id, index]


## Uso: if SwatSquadBot.is_swat_key(key): continue
static func is_swat_key(key: String) -> bool:
	var parts := key.split(":")
	if parts.size() != 2 or not parts[0].is_valid_int():
		return false
	return int(parts[0]) <= NPC_PEER_ID_BASE


## Chaves das `count` vagas do esquadrao.
## Uso: for key in SwatSquadBot.keys_for(squad_id, SwatSquadBot.COUNT): ...
static func keys_for(squad_id: int, count: int = COUNT) -> Array[String]:
	var keys: Array[String] = []
	for index in count:
		keys.append(key_for(squad_id, index))
	return keys


## Posicao de formacao do bot `index` em volta do dono (ocioso).
## Uso: var alvo := SwatSquadBot.formation_position(anchor.global_position, 1)
static func formation_position(anchor_position: Vector3, index: int) -> Vector3:
	var angle := TAU * float(index) / float(COUNT)
	return anchor_position + Vector3(cos(angle), 0.0, sin(angle)) * FORMATION_RADIUS


## Deixa o nó jogavel como bot do esquadrao: fora do grupo "player" (zumbi
## ignora), sem colisao propria (layer 0) e sem bater em zumbi, invulneravel,
## municao infinita e marcado para a IA nao trocar de arma.
## Uso: SwatSquadBot.configure(bot, 0)
static func configure(bot: Node3D, index: int) -> void:
	bot.remove_from_group("player")
	var body := bot as CollisionObject3D
	if body != null:
		# Layer 0: nada colide com ele. Mask sem o layer dos zumbis (4) para o
		# zumbi nao empurrar/segurar o bot: so o cenario e os outros jogadores.
		body.collision_layer = 0
		body.collision_mask = 23 & ~4
	bot.set("is_swat_bot", true)
	bot.set("infinite_ammo", true)
	bot.set("reads_local_input", false)
	# Sem isso o bot leria o teclado do jogador local (sonar) usando o prefixo
	# de acoes padrao.
	bot.set("is_local_controller", false)
	bot.set("input_device_name", "SWAT %d" % (index + 1))


## Tempo restante do esquadrao; <= 0 quando acabou.
## Uso: if SwatSquadBot.remaining_seconds(elapsed, 19.5) > 0.0: ...
static func remaining_seconds(elapsed: float, duration: float = DURATION_SECONDS) -> float:
	return duration - elapsed
