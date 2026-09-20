class_name SwatSmokeTest
extends RefCounted

## Teste rapido da chamada de SWAT (`--smoke-test-swat`), so de desenvolvimento:
## no servidor cria zumbis em volta do jogador, chama o esquadrao e imprime o
## estado dos soldados a cada 2 s; no cliente confere que os soldados existem
## AQUI e que se movem, e encerra com o resumo.
##
## O caso do cliente e o que justifica existir: com o id de peer negativo lido
## como u32 o estado era descartado e o soldado ficava parado na origem,
## invisivel, sem erro nenhum no log.
##
## Uso:
##   godot --headless --path . -- --server --smoke-test-swat
##   godot --headless --path . -- --join=IP --server-port=P --smoke-test-swat

## Zumbis criados em volta do jogador para medir o dano do esquadrao.
const TARGET_RING_COUNT := 6
const TARGET_RING_RADIUS := 10.0

var world: Node3D
var swat: SwatSquadDirector
var _elapsed := 0.0
var _called := false
var _report_in := 0.0
var _done_in := -1.0
var _targets: Array[Node] = []
## Cliente: primeira posicao vista de cada soldado, para medir deslocamento.
var _first_seen: Dictionary = {}


func _init(world_node: Node3D = null, squad_director: SwatSquadDirector = null) -> void:
	world = world_node
	swat = squad_director


## Uso: chamado todo frame quando --smoke-test-swat esta ligado.
func tick(delta: float) -> void:
	_elapsed += delta
	if NetworkSession.is_client():
		_tick_client(delta)
		return
	if not _called:
		_try_call_squad()
		return
	if swat.is_empty():
		_finish_server(delta)
		return
	_report_in -= delta
	if _report_in > 0.0:
		return
	_report_in = 2.0
	print_report()


## Espera a cidade e o jogador, cerca ele de zumbis e chama o esquadrao.
func _try_call_squad() -> void:
	if _elapsed < 2.5 or not world.call("_procedural_city_ready"):
		return
	var caller := world.get_tree().get_first_node_in_group("player") as Node3D
	if caller == null:
		return
	_targets.clear()
	for index in TARGET_RING_COUNT:
		var angle := TAU * float(index) / float(TARGET_RING_COUNT)
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * TARGET_RING_RADIUS
		if world.call("_spawn_zombie", caller.global_position + offset):
			_targets.append(world.zombies.get_child(-1))
	world.call("call_swat", caller, -caller.global_transform.basis.z)
	_called = true
	_report_in = 2.0
	print(JSON.stringify({"event": "swat_smoke_called", "squads": swat.squad_count()}))


## Esquadrao inteiro expirou: imprime o resumo e espera alguns segundos (tempo
## de o cliente receber o retire) antes de fechar.
func _finish_server(delta: float) -> void:
	if _done_in < 0.0:
		print_report()
		print(JSON.stringify({"event": "swat_smoke_done", "elapsed": snappedf(_elapsed, 0.1)}))
		_done_in = 6.0
		return
	_done_in -= delta
	if _done_in <= 0.0:
		world.get_tree().quit(0)


func _visible_bots() -> Array[Node]:
	var bots: Array[Node] = []
	for player_node in world.players_node.get_children():
		if bool(player_node.get("is_swat_bot")):
			bots.append(player_node)
	return bots


func _travel_of(bot: Node) -> float:
	var start: Vector3 = _first_seen.get(bot.name, (bot as Node3D).global_position)
	return (bot as Node3D).global_position.distance_to(start)


func _tick_client(delta: float) -> void:
	var bots := _visible_bots()
	for bot in bots:
		if not _first_seen.has(bot.name):
			_first_seen[bot.name] = (bot as Node3D).global_position
	if fmod(_elapsed, 2.0) < delta:
		var travels: Array[float] = []
		for bot in bots:
			travels.append(snappedf(_travel_of(bot), 0.1))
		print(JSON.stringify({"event": "swat_seen", "alive": bots.size(), "travel": travels}))
	if _elapsed < 8.0:
		return
	if bots.is_empty() and _elapsed < 20.0:
		# Sem esquadrao nenhum: nao espera para sempre (o teste tem timeout, mas
		# um smoke que trava ate ser morto nao serve de sinal).
		return
	var max_travel := 0.0
	var at_origin := 0
	for bot in bots:
		max_travel = maxf(max_travel, _travel_of(bot))
		if (bot as Node3D).global_position.length() < 1.0:
			at_origin += 1
	print(JSON.stringify({
		"event": "swat_seen_done",
		"alive": bots.size(),
		"max_travel": snappedf(max_travel, 0.1),
		"at_origin": at_origin,
	}))
	world.get_tree().quit(0)


## Estado dos soldados: distancia do dono, arma, pente e vida.
func print_report() -> void:
	for squad_id_value in swat.squads:
		var squad: Dictionary = swat.squads[squad_id_value]
		var anchor := swat.anchor_of(squad)
		var rows: Array = []
		for index in (squad["keys"] as Array).size():
			rows.append(_row_for(String((squad["keys"] as Array)[index]), index, anchor))
		print(JSON.stringify({
			"event": "swat_smoke",
			"squad": int(squad_id_value),
			"elapsed": snappedf(float(squad["elapsed"]), 0.1),
			"zombies": world.zombies.get_child_count(),
			"kills": world.survival_wave_controller.total_kills if world.survival_wave_controller != null else -1,
			"targets_hp": _targets.map(func(z: Node) -> int: return int(z.get("health")) if is_instance_valid(z) else -1),
			"bots": rows,
		}))


func _row_for(key: String, index: int, anchor: Node3D) -> Dictionary:
	var bot = world.network_players.get(key)
	if not is_instance_valid(bot):
		return {"index": index, "alive": false}
	var slots: WeaponSlots = bot.get("weapon_slots")
	var kind := int(bot.get("current_weapon"))
	var anchor_distance := -1.0
	if anchor != null:
		anchor_distance = bot.global_position.distance_to(anchor.global_position)
	return {
		"index": index,
		"alive": true,
		"dist_anchor": snappedf(anchor_distance, 0.1),
		"weapon": kind,
		"mag": int(slots.state_of(kind).get("mag", -1)),
		"health": int(bot.get("health")),
	}
