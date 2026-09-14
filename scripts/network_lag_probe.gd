class_name NetworkLagProbe
extends RefCounted

## Mede, do lado do cliente, o atraso percebido de um servidor remoto: RTT do
## ENet e o espacamento entre snapshots completos de zumbis. O servidor envia
## snapshots a cada 100 ms; intervalos maiores indicam que o tick de fisica do
## servidor esta estourando o orcamento (lag de simulacao, nao de rede).
## Uso:
##   godot --headless --path . -- --bot-player=195.35.42.208 --lag-probe=30

const EXPECTED_SNAPSHOT_INTERVAL_MS := 100.0

var duration_seconds := 0.0
var elapsed_seconds := 0.0
var rtt_samples: Array[float] = []
var snapshot_interval_samples: Array[float] = []
var zombie_count_samples: Array[int] = []
var frame_time_samples: Array[float] = []
var _last_complete_usec := -1
var _current_sequence := -1
var _current_packets: Dictionary = {}
var _current_zombie_count := 0
var _rtt_sample_timer := 0.0


## Le `--lag-probe=SEGUNDOS` da linha de comando; 0 desativa a sonda.
## Uso: var probe := NetworkLagProbe.from_arguments(OS.get_cmdline_user_args())
static func from_arguments(arguments: PackedStringArray) -> NetworkLagProbe:
	var probe := NetworkLagProbe.new()
	for argument in arguments:
		if not argument.begins_with("--lag-probe="):
			continue
		var raw_value := argument.trim_prefix("--lag-probe=")
		if not raw_value.is_valid_float() or float(raw_value) <= 0.0:
			push_error("Valor invalido para --lag-probe: '%s'; esperado numero de segundos > 0." % raw_value)
			continue
		probe.duration_seconds = float(raw_value)
	return probe


func is_enabled() -> bool:
	return duration_seconds > 0.0


## Registra a chegada de um pacote de snapshot de zumbis.
## Uso: probe.record_zombie_packet(sequence, packet_index, packet_count, states.size(), Time.get_ticks_usec())
func record_zombie_packet(sequence: int, packet_index: int, packet_count: int, zombie_count: int, now_usec: int) -> void:
	if sequence != _current_sequence:
		_current_sequence = sequence
		_current_packets.clear()
		_current_zombie_count = 0
	if _current_packets.has(packet_index):
		return
	_current_packets[packet_index] = true
	_current_zombie_count += zombie_count
	if _current_packets.size() != packet_count:
		return
	if _last_complete_usec >= 0:
		snapshot_interval_samples.append(float(now_usec - _last_complete_usec) / 1000.0)
	_last_complete_usec = now_usec
	zombie_count_samples.append(_current_zombie_count)


## Registra a duracao de um frame renderizado (ms) para medir FPS do cliente.
## Uso: probe.record_frame_time(delta * 1000.0)
func record_frame_time(frame_ms: float) -> void:
	if elapsed_seconds > 3.0:
		frame_time_samples.append(frame_ms)


## Avanca o relogio da sonda; devolve true quando a medicao terminou.
## Uso: if probe.tick(delta, rtt_ms): print(probe.build_report())
func tick(delta: float, rtt_ms: float) -> bool:
	elapsed_seconds += delta
	_rtt_sample_timer -= delta
	if _rtt_sample_timer <= 0.0 and rtt_ms >= 0.0:
		_rtt_sample_timer = 0.5
		rtt_samples.append(rtt_ms)
	return elapsed_seconds >= duration_seconds


func build_report() -> Dictionary:
	var late_snapshots := 0
	for interval in snapshot_interval_samples:
		if interval > EXPECTED_SNAPSHOT_INTERVAL_MS * 1.5:
			late_snapshots += 1
	return {
		"event": "lag_probe_report",
		"seconds": snappedf(elapsed_seconds, 0.1),
		"rtt_ms_avg": snappedf(_average(rtt_samples), 0.1),
		"snapshot_interval_ms_avg": snappedf(_average(snapshot_interval_samples), 0.1),
		"snapshot_interval_ms_p95": snappedf(_percentile(snapshot_interval_samples, 0.95), 0.1),
		"snapshot_interval_ms_max": snappedf(_percentile(snapshot_interval_samples, 1.0), 0.1),
		"complete_snapshots": snapshot_interval_samples.size(),
		"late_snapshots": late_snapshots,
		"zombies_last": zombie_count_samples.back() if not zombie_count_samples.is_empty() else 0,
		"frame_ms_avg": snappedf(_average(frame_time_samples), 0.01),
		"frame_ms_p95": snappedf(_percentile(frame_time_samples, 0.95), 0.01),
	}


static func _average(samples: Array) -> float:
	if samples.is_empty():
		return 0.0
	var total := 0.0
	for sample in samples:
		total += float(sample)
	return total / float(samples.size())


static func _percentile(samples: Array[float], fraction: float) -> float:
	if samples.is_empty():
		return 0.0
	var sorted_samples := samples.duplicate()
	sorted_samples.sort()
	return float(sorted_samples[mini(int(float(sorted_samples.size()) * fraction), sorted_samples.size() - 1)])
