class_name SnapshotInterpBuffer
extends RefCounted

## Interpolacao dos snapshots de rede no client (zumbi e jogador), com margem
## para jitter. O atraso e adaptativo: a 10 Hz ficava em 200 ms; a 20 Hz fica
## em 100 ms. Com pacote atrasado cresce ate MAX_DELAY_MS.
##
## A regra que importa e: o tempo de render (agora - atraso) tem que cair ENTRE
## duas amostras guardadas. Por isso o buffer guarda varias amostras e procura o
## par que envolve o render time. Guardar so as duas ultimas e usar atraso de 2
## intervalos coloca o render time ANTES da amostra mais antiga, o peso trava em
## 0 e o proxy deixa de interpolar: so salta para a amostra anterior, de 10 em
## 10 Hz. Medido com o servidor a 10 Hz: 25 de 29 frames parados e salto de
## 0,5 m num quadro — travada constante em tudo que se move.
## Uso:
##   var buffer := SnapshotInterpBuffer.new()
##   buffer.reset(Time.get_ticks_msec(), global_position, rotation.y)
##   buffer.push(Time.get_ticks_msec(), nova_posicao, nova_rotacao, global_position, rotation.y)
##   buffer.sample(Time.get_ticks_msec())
##   global_position = buffer.position

const DEFAULT_INTERVAL_MS := 50.0
## Dois intervalos: aguenta um pacote atrasado ou perdido sem congelar.
const DELAY_INTERVALS := 2.0
## Abaixo de 75 ms o jitter comum deixa o proxy sem um par de amostras.
const MIN_DELAY_MS := 75.0
const MAX_DELAY_MS := 450.0
## Peso do intervalo novo na media (jitter medido, nao so o ultimo pacote).
const INTERVAL_WEIGHT := 0.25
## Acima de MAX_DELAY_MS a amostra entra no buffer sem alongar mais a espera.
const MAX_INTERVAL_MS := MAX_DELAY_MS / DELAY_INTERVALS
## Amostras guardadas: cobrem o atraso (2 intervalos) mais a mais nova, com
## folga; o descarte e pelo tamanho, entao o custo por frame fica limitado.
const MAX_SAMPLES := 8
## Salto maior que isso e realocacao do servidor (spawn, unstuck, teleporte) e
## reinicia o buffer em vez de deslizar pelo mapa.
const DEFAULT_SNAP_DISTANCE := 8.0

var position := Vector3.ZERO
var rotation := 0.0
var delay_ms := MIN_DELAY_MS
var snap_distance := DEFAULT_SNAP_DISTANCE

var _times_ms: Array[float] = []
var _positions: Array[Vector3] = []
var _rotations: Array[float] = []
var _interval_ms := DEFAULT_INTERVAL_MS
var _last_arrival_ms := NAN


## Estado inicial: uma amostra no transforme atual, para o no recem-criado nao
## teleportar no primeiro snapshot.
## Uso: buffer.reset(Time.get_ticks_msec(), global_position, rotation.y)
func reset(now_ms: float, start_position: Vector3, start_rotation: float) -> void:
	_times_ms.clear()
	_positions.clear()
	_rotations.clear()
	_append(now_ms, start_position, start_rotation)
	position = start_position
	rotation = start_rotation
	_last_arrival_ms = NAN


## Empurra o snapshot novo. `node_position`/`node_rotation` sao o transforme
## atual do no, usado so na primeira amostra: a interpolacao comeca de onde ele
## esta em vez de pular para o primeiro pacote. Devolve true quando o salto foi
## grande demais e o buffer reiniciou.
## Uso: if buffer.push(agora, posicao, rotacao, global_position, rotation.y): reiniciou()
func push(now_ms: float, new_position: Vector3, new_rotation: float, node_position: Vector3, node_rotation: float) -> bool:
	if _times_ms.is_empty():
		_append(now_ms - _interval_ms, node_position, node_rotation)
		_append(now_ms, new_position, new_rotation)
		_last_arrival_ms = now_ms
		return true
	if _positions[_positions.size() - 1].distance_to(new_position) > snap_distance:
		reset(now_ms, new_position, new_rotation)
		_last_arrival_ms = now_ms
		return true
	var arrival_interval_ms := now_ms - _last_arrival_ms if is_finite(_last_arrival_ms) else 0.0
	_append(now_ms, new_position, new_rotation)
	_last_arrival_ms = now_ms
	_update_delay(arrival_interval_ms)
	return false


## Avanca a pose interpolada no tempo de render (agora - atraso), procurando o
## par de amostras que envolve esse instante. Sem amostra nova (pacote atrasado)
## a pose para na ultima em vez de extrapolar: extrapolar atravessa parede.
## Uso: buffer.sample(Time.get_ticks_msec())
func sample(now_ms: float) -> void:
	var count := _times_ms.size()
	if count == 0:
		return
	var render_ms := now_ms - delay_ms
	if count == 1 or render_ms <= _times_ms[0]:
		position = _positions[0]
		rotation = _rotations[0]
		return
	if render_ms >= _times_ms[count - 1]:
		position = _positions[count - 1]
		rotation = _rotations[count - 1]
		return
	for index in count - 1:
		var start_ms := _times_ms[index]
		var end_ms := _times_ms[index + 1]
		if render_ms > end_ms:
			continue
		var span := end_ms - start_ms
		var weight := 1.0 if span <= 0.001 else (render_ms - start_ms) / span
		position = _positions[index].lerp(_positions[index + 1], weight)
		rotation = lerp_angle(_rotations[index], _rotations[index + 1], weight)
		return


## Intervalo medio entre snapshots que o buffer esta usando (diagnostico).
## Uso: print(buffer.interval_ms())
func interval_ms() -> float:
	return _interval_ms


## Amostras guardadas neste instante (diagnostico e teste).
## Uso: if buffer.sample_count() < 2: esperando()
func sample_count() -> int:
	return _times_ms.size()


func _append(time_ms: float, sample_position: Vector3, sample_rotation: float) -> void:
	_times_ms.append(time_ms)
	_positions.append(sample_position)
	_rotations.append(sample_rotation)
	while _times_ms.size() > MAX_SAMPLES:
		_times_ms.pop_front()
		_positions.pop_front()
		_rotations.pop_front()


func _update_delay(arrival_interval_ms: float) -> void:
	if arrival_interval_ms <= 0.0 or arrival_interval_ms > MAX_INTERVAL_MS * 4.0:
		# Buraco grande (jogador entrou agora, servidor retomou): nao inflaciona
		# a media com um outlier que nunca se repete.
		return
	_interval_ms = lerpf(_interval_ms, clampf(arrival_interval_ms, 1.0, MAX_INTERVAL_MS), INTERVAL_WEIGHT)
	# O atraso nunca pode passar do historico guardado: o render time precisa
	# cair ENTRE duas amostras. Com snapshots rapidos (servidor a 15-30 Hz) o
	# piso de MIN_DELAY_MS sozinho estourava a janela e o proxy voltava a
	# congelar/saltar, calado. MAX_SAMPLES - 2 deixa sempre um par em volta.
	var history_ms := float(MAX_SAMPLES - 2) * _interval_ms
	delay_ms = clampf(_interval_ms * DELAY_INTERVALS, MIN_DELAY_MS, MAX_DELAY_MS)
	delay_ms = minf(delay_ms, maxf(history_ms, _interval_ms))
