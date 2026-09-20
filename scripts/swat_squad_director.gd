class_name SwatSquadDirector
extends RefCounted

## Esquadrao SWAT chamado pelo jogador: 4 soldados por 20 s que sao jogadores
## de verdade simulados no servidor (IA do bot de teste, Uzi, municao infinita
## e leash do dono). Saiu do main.gd para o suporte parar de disputar espaco
## com a sobrevivencia.
##
## O `world` e o no da partida (scenes/main.tscn): ele continua dono da arvore
## de nos, dos RPCs e do dicionario de jogadores de rede.
##
## Uso:
##   var swat := SwatSquadDirector.new(self)
##   var squad_id := swat.begin_squad(caller)   # no servidor/offline
##   swat.update(delta)                          # no _physics_process

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

var world: Node3D
## Esquadroes vivos: id -> {"keys": Array[String], "anchor": WeakRef, "elapsed": float}.
var squads: Dictionary = {}
## Cerebro dos soldados: mesma IA do bot de teste, em modo esquadrao.
var bot_ai := PlayerBotAI.new()
var _next_squad_id := 0


func _init(world_node: Node3D = null) -> void:
	world = world_node


func is_empty() -> bool:
	return squads.is_empty()


func squad_count() -> int:
	return squads.size()


## Abre um esquadrao novo e devolve o id, para o chamador replicar por RPC.
## Uso: var squad_id := swat.begin_squad(caller)
func begin_squad(anchor: Node3D) -> int:
	_next_squad_id += 1
	enlist(_next_squad_id, anchor)
	return _next_squad_id


## Cria os 4 soldados do esquadrao (servidor/offline e, pelo RPC, nos clientes).
## No cliente o dono nao existe: quem manda na posicao e o snapshot de jogadores.
func enlist(squad_id: int, anchor: Node3D) -> void:
	var keys := SwatSquadBot.keys_for(squad_id)
	for index in keys.size():
		_spawn_bot(keys[index], index, anchor)
	# WeakRef, nao o no: depois que o dono desconecta o objeto liberado segue no
	# dicionario e comparar/castar ele levanta "Trying to cast a freed object".
	squads[squad_id] = {"keys": keys, "anchor": weakref(anchor) if is_instance_valid(anchor) else null, "elapsed": 0.0}


func _spawn_bot(key: String, index: int, anchor: Node3D) -> void:
	var bot = PLAYER_SCENE.instantiate()
	bot.name = "SwatBot_%s" % key.replace(":", "_")
	bot.set("owner_peer_id", int(key.split(":")[0]))
	bot.local_slot = index
	bot.simulation_enabled = NetworkSession.is_server() or NetworkSession.is_offline()
	SwatSquadBot.configure(bot, index)
	var spawn_position := world.global_position
	if is_instance_valid(anchor):
		spawn_position = SwatSquadBot.formation_position((anchor as Node3D).global_position, index)
	bot.position = spawn_position
	world.players_node.add_child(bot, true)
	bot.set_spawn_position(bot.global_position)
	bot.set_color_index(index)
	if bot.simulation_enabled:
		world.call("_connect_crate_weapon_signals", bot)
		bot.equip_crate_weapon(WeaponStats.Kind.UZI)
	world.network_players[key] = bot


## Fim do esquadrao: libera os 4 soldados deste processo.
func retire(squad_id: int) -> void:
	var squad_value: Variant = squads.get(squad_id)
	if squad_value == null:
		return
	squads.erase(squad_id)
	for key_value in (squad_value as Dictionary)["keys"]:
		var key := String(key_value)
		var bot = world.network_players.get(key)
		world.network_players.erase(key)
		world.player_slots_replication.forget(key)
		if is_instance_valid(bot):
			bot.queue_free()


## Avanca os esquadroes: expira quem passou do tempo ou perdeu o dono, e
## alimenta a IA de cada soldado. Roda onde a partida e simulada.
## Uso: chamado em _physics_process.
func update(delta: float) -> void:
	for squad_id_value in squads.keys().duplicate():
		var squad_id := int(squad_id_value)
		var squad: Dictionary = squads[squad_id]
		squad["elapsed"] = float(squad["elapsed"]) + delta
		if SwatSquadBot.remaining_seconds(float(squad["elapsed"])) <= 0.0:
			_retire_everywhere(squad_id)
			continue
		var anchor := anchor_of(squad)
		if squad["anchor"] != null and anchor == null:
			# Dono sumiu (desconectou): o esquadrao era suporte dele e vai embora.
			_retire_everywhere(squad_id)
			continue
		_tick_bots(squad_id, squad, anchor, delta)


## Dono do esquadrao, ou null quando ele ja foi liberado.
func anchor_of(squad: Dictionary) -> Node3D:
	var anchor_ref: Variant = squad["anchor"]
	if anchor_ref is WeakRef:
		return (anchor_ref as WeakRef).get_ref() as Node3D
	return null


func _retire_everywhere(squad_id: int) -> void:
	retire(squad_id)
	if NetworkSession.is_server():
		world.call("broadcast_swat_retire", squad_id)


func _tick_bots(squad_id: int, squad: Dictionary, anchor: Node3D, delta: float) -> void:
	var keys: Array = squad["keys"]
	for index in keys.size():
		var bot = world.network_players.get(String(keys[index]))
		if not is_instance_valid(bot):
			continue
		# Vaga unica por soldado: o dicionario interno da IA (strafe, preso,
		# ultima posicao) nao pode ser compartilhado entre esquadroes vivos.
		var slot := squad_id * SwatSquadBot.COUNT + index
		bot.apply_network_input(bot_ai.collect_squad_input(bot, anchor, world.zombies, slot, index, delta))
