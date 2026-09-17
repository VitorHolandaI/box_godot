class_name SnapshotInterpBuffer
extends RefCounted

## Interpolacao de snapshots com margem para jitter de rede, compartilhada por
## zumbi e jogador no client. Guarda duas amostras e devolve a pose no tempo de
## render (agora - delay). O delay se adapta ao intervalo real de chegada: com
## os 100 ms cravados do servidor fica em 200 ms; com pacote atrasado (a sonda
## de lag mediu 128 ms de media e 1,6 s no pior na VPS) cresce ate MAX_DELAY_MS.
## Sem essa margem o proxy congela esperando o proximo snapshot e depois pula —
## e o "teleporte" que o jogador ve. O delay e sempre >= 1 intervalo, entao a
## interpolacao nunca fica na borda do buffer.
## Uso:
##   var buffer := SnapshotInterpBuffer.new()
##   buffer.reset(Time.get_ticks_msec(), global_position, rotation.y)
##   buffer.push(Time.get_ticks_msec(), nova_posicao, nova_rotacao, global_position, rotation.y)
##   buffer.sample(Time.get_ticks_msec())
##   global_position = buffer.position

const DEFAULT_INTERVAL_MS := 100.0
## Dois intervalos de snapshot: e a regra classica (aguenta um pacote perdido).
const DELAY_INTERVALS := 2.0
const MIN_DELAY_MS := 150.0
const MAX_DELAY_MS := 450.0
## Peso do intervalo novo na media (jitter medido, nao so o ultimo pacote).
const INTERVAL_WEIGHT := 0.25
## Acima de MAX_DELAY_MS a amostra entra no buffer sem alongar mais a espera.
const MAX_INTERVAL_MS := MAX_DELAY_MS / DELAY_INTERVALS
## Salto maior que isso e realocacao do servidor (spawn, unstuck, teleporte) e
## reinicia o buffer em vez de deslizar pelo mapa.
const DEFAULT_SNAP_DISTANCE := 8.0

var position := Vector3.ZERO
var rotation := 0.0
var delay_ms := MIN_DELAY_MS
var snap_distance := DEFAULT_SNAP_DISTANCE

var _interval_ms := DEFAULT_INTERVAL_MS
var _prev_position := Vector3.ZERO
var _prev_rotation := 0.0
var _prev_ms := 0.0
var _next_position := Vector3.ZERO
var _next_rotation := 0.0
var _next_ms := 0.0
var _has_sample := false
var _last_arrival_ms := NAN


## Estado inicial: as duas amostras no mesmo instante, para o no recem-criado
## nao teleportar no primeiro snapshot.
## Uso: buffer.reset(Time.get_ticks_msec(), global_position, rotation.y)
func reset(now_ms: float, start_position: Vector3, start_rotation: float) -> void:
	_seed(now_ms, now_ms, start_position, start_rotation, start_position, start_rotation)
	_last_arrival_ms = NAN


## Empurra o snapshot novo. `node_position`/`node_rotation` sao o transforme
## atual do no, usado so na primeira amostra: a interpolacao comeca de onde ele
## esta em vez de pular para o primeiro pacote. Devolve true quando o salto foi
## grande demais e o buffer reiniciou.
## Uso: if buffer.push(agora, posicao, rotacao, global_position, rotation.y): reiniciou()
func push(now_ms: float, new_position: Vector3, new_rotation: float, node_position: Vector3, node_rotation: float) -> bool:
	if not _has_sample:
		_seed(now_ms - _interval_ms, now_ms, node_position, node_rotation, new_position, new_rotation)
		_last_arrival_ms = now_ms
		return true
	if position.distance_to(new_position) > snap_distance:
		reset(now_ms, new_position, new_rotation)
		_last_arrival_ms = now_ms
		return true
	var arrival_interval_ms := now_ms - _last_arrival_ms if is_finite(_last_arrival_ms) else 0.0
	_prev_position = _next_position
	_prev_rotation = _next_rotation
	_prev_ms = _next_ms
	_next_position = new_position
	_next_rotation = new_rotation
	_next_ms = now_ms
	_last_arrival_ms = now_ms
	_update_delay(arrival_interval_ms)
	return false


## Avanca a pose interpolada no tempo de render (agora - delay). Quando o
## buffer fica sem amostra nova (pacote atrasado) a pose para na ultima amostra
## em vez de extrapolar: extrapolar atravessa parede.
## Uso: buffer.sample(Time.get_ticks_msec())
func sample(now_ms: float) -> void:
	if not _has_sample:
		return
	var span := _next_ms - _prev_ms
	if span <= 0.001:
		position = _next_position
		rotation = _next_rotation
		return
	var weight := clampf(((now_ms - delay_ms) - _prev_ms) / span, 0.0, 1.0)
	position = _prev_position.lerp(_next_position, weight)
	rotation = lerp_angle(_prev_rotation, _next_rotation, weight)


## Intervalo medio entre snapshots que o buffer esta usando (diagnostico).
## Uso: print(buffer.interval_ms())
func interval_ms() -> float:
	return _interval_ms


## Quanto o render time passou da ultima amostra, em ms; > 0 significa buffer
## sem amostra nova (congelando ate o proximo pacote). Diagnostico.
## Uso: if buffer.starvation_ms(agora) > 0.0: esperando()
func starvation_ms(now_ms: float) -> float:
	return (now_ms - delay_ms) - _next_ms


func _seed(prev_ms: float, next_ms: float, prev_position: Vector3, prev_rotation: float, next_position: Vector3, next_rotation: float) -> void:
	_prev_position = prev_position
	_prev_rotation = prev_rotation
	_prev_ms = prev_ms
	_next_position = next_position
	_next_rotation = next_rotation
	_next_ms = next_ms
	_has_sample = true
	position = next_position
	rotation = next_rotation


func _update_delay(arrival_interval_ms: float) -> void:
	if arrival_interval_ms <= 0.0 or arrival_interval_ms > MAX_INTERVAL_MS * 4.0:
		# Buraco grande (jogador entrou agora, servidor retomou): nao inflaciona
		# a media com um outlier que nunca se repete.
		return
	_interval_ms = lerpf(_interval_ms, clampf(arrival_interval_ms, 1.0, MAX_INTERVAL_MS), INTERVAL_WEIGHT)
	delay_ms = clampf(_interval_ms * DELAY_INTERVALS, MIN_DELAY_MS, MAX_DELAY_MS)
