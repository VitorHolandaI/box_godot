class_name NetworkFlowAudit
extends RefCounted

## Auditoria automatica dos fluxos principais da partida, do lado do
## servidor dedicado. Amostra o mundo a cada 0,5 s durante N segundos e
## imprime um relatorio JSON "FLOW_AUDIT" com PASS/FAIL por fluxo. Encerra
## o processo ao terminar (0 quando os fluxos nucleares passaram).
## Fluxos nucleares (falha = exit 1): peer_loaded, zombie_spawned, zombie_killed.
## Fluxos de observacao podem nao ocorrer numa partida curta: ficam marcados
## como "not_reached" sem falhar (ex.: airdrop so existe a partir da onda 2).
## Uso: godot --headless --path . -- --server --server-port=7020 --flow-audit=75

const SAMPLE_INTERVAL := 0.5
const CORE_FLOWS: Array[String] = ["peer_loaded", "zombie_spawned", "zombie_killed"]
## Fluxos que exigem bot sobreviver a onda (wave_advanced), progredir ate a
## onda 2 (airdrop), tocar porta etc. — observados, mas nao reprovam o teste.
const OPTIONAL_FLOWS: Array[String] = ["airdrop_launched", "ground_weapon_seen", "wave_advanced", "game_over_fired", "door_changed"]

var duration_seconds := 0.0
var elapsed_seconds := 0.0
var evidence := {}
var samples: Array = []
var _sample_elapsed := 0.0
var _initial_wave_index := 0
var _first_sample_done := false
var _finished := false


## Le --flow-audit=SEGUNDOS da linha de comando; 0 desativa a auditoria.
## Uso: var audit := NetworkFlowAudit.from_arguments(OS.get_cmdline_user_args())
static func from_arguments(arguments: PackedStringArray) -> NetworkFlowAudit:
	var audit := NetworkFlowAudit.new()
	for argument in arguments:
		if not argument.begins_with("--flow-audit="):
			continue
		var raw_value := argument.trim_prefix("--flow-audit=")
		if not raw_value.is_valid_float() or float(raw_value) <= 0.0:
			push_error("Valor invalido para --flow-audit: '%s'; esperado numero de segundos > 0." % raw_value)
			continue
		audit.duration_seconds = float(raw_value)
	return audit


func is_enabled() -> bool:
	return duration_seconds > 0.0


## Amostra o estado do servidor e imprime o relatorio no fim.
## Uso: no _process do servidor: flow_audit.tick(delta, self)
func tick(delta: float, main: Node) -> void:
	if _finished or not NetworkSession.is_server():
		return
	elapsed_seconds += delta
	_sample_elapsed += delta
	if _sample_elapsed >= SAMPLE_INTERVAL:
		_sample_elapsed = 0.0
		_collect_sample(main)
	if elapsed_seconds < duration_seconds:
		return
	_finished = true
	var report := build_report(main)
	print("FLOW_AUDIT %s" % JSON.stringify(report))
	var exit_code := 0
	for failed_flow in report["core_failed"]:
		push_error("FLOW_AUDIT falhou no fluxo nuclear '%s'." % failed_flow)
		exit_code = 1
	main.get_tree().quit(exit_code)


func _collect_sample(main: Node) -> void:
	var tree := main.get_tree()
	_mark("peer_loaded", NetworkSession.loaded_peers.size() > 0)
	var zombies: Node = main.get("zombies")
	_mark("zombie_spawned", zombies != null and zombies.get_child_count() > 0)
	var controller: RefCounted = main.get("survival_wave_controller")
	if controller != null:
		var wave_index := int(controller.get("wave_index"))
		if not _first_sample_done:
			_initial_wave_index = wave_index
			_first_sample_done = true
		samples.append({
			"t": snappedf(elapsed_seconds, 0.1),
			"wave": wave_index,
			"kills": int(controller.get("total_kills")),
			"alive_in_wave": int(controller.get("alive_in_wave")),
			"zombies": zombies.get_child_count(),
			"game_over": bool(controller.get("game_over")),
		})
		_mark("zombie_killed", int(controller.get("total_kills")) > 0)
		_mark("wave_advanced", wave_index > _initial_wave_index)
		_mark("game_over_fired", bool(controller.get("game_over")))
	_mark("ground_weapon_seen", not tree.get_nodes_in_group("ground_weapons").is_empty())
	_mark("supply_seen", not tree.get_nodes_in_group("wave_supply_pickups").is_empty() or not tree.get_nodes_in_group("ground_supplies").is_empty())
	for pickup in tree.get_nodes_in_group("ground_weapons"):
		if pickup.has_method("land"):
			_mark("airdrop_launched", true)
			break
	for door in tree.get_nodes_in_group("destructible_door"):
		if bool(door.get("is_open")) or bool(door.get("is_destroyed")):
			_mark("door_changed", true)
			break


func _mark(flow: String, happened: bool) -> void:
	if happened:
		evidence[flow] = true


func build_report(main: Node) -> Dictionary:
	var flows := {}
	var failed: Array[String] = []
	var all_flows: Array[String] = ["peer_loaded", "zombie_spawned", "zombie_killed", "wave_advanced", "game_over_fired", "door_changed", "supply_seen", "ground_weapon_seen", "airdrop_launched"]
	for flow in all_flows:
		var observed: bool = bool(evidence.get(flow, false))
		if observed:
			flows[flow] = "ok"
		elif OPTIONAL_FLOWS.has(flow):
			flows[flow] = "not_reached"
		else:
			flows[flow] = "failed"
			failed.append(flow)
	var core_failed: Array[String] = []
	for flow in CORE_FLOWS:
		if flows.get(flow, "") == "failed":
			core_failed.append(flow)
	var controller: RefCounted = main.get("survival_wave_controller")
	var zombies_node: Node = main.get("zombies")
	return {
		"seconds": snappedf(elapsed_seconds, 0.1),
		"flows": flows,
		"failed": failed,
		"total_kills": int(controller.get("total_kills")) if controller != null else -1,
		"wave_index": int(controller.get("wave_index")) if controller != null else -1,
		"zombies_alive": zombies_node.get_child_count() if zombies_node != null else -1,
		"core_failed": core_failed,
		"samples": samples,
	}
