class_name ZombieSnapshotCodec
extends RefCounted

## Codifica o estado dos zumbis em bytes compactos para o snapshot de rede.
## Um Dictionary serializado custava 324 bytes por zumbi; aqui sao 16 (22 se
## morto). Tipo e aparencia nao viajam: o cliente deriva os dois do nome
## "ZombieSpawn<id>", igual ao servidor.
## Layout little-endian por zumbi:
##   u32 id | i16 x | i16 y | i16 z | u8 rotacao | u16 vida | u8 flags | u16 seq. ataque
##   [i16 vx | i16 vy | i16 vz]  somente quando flags tem IS_DEAD
## Uso:
##   var bytes := ZombieSnapshotCodec.encode(states)
##   var states := ZombieSnapshotCodec.decode(bytes)

const NAME_PREFIX := "ZombieSpawn"
const POSITION_SCALE := 0.02
const VELOCITY_SCALE := 0.01
const FLAG_IS_DEAD := 1
const ALIVE_RECORD_BYTES := 16
const DEAD_RECORD_BYTES := 22


## Estados vindos de zombie.get_network_state() com "network_id" preenchido.
## Uso: var payload := ZombieSnapshotCodec.encode([{"network_id": 7, "position": Vector3.ZERO, ...}])
static func encode(states: Array) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = false
	for state_value in states:
		var state := state_value as Dictionary
		var network_id := int(state.get("network_id", -1))
		if network_id < 0:
			push_error("Estado de zumbi sem network_id valido: %s; esperado inteiro >= 0." % state)
			continue
		var position: Vector3 = state.get("position", Vector3.ZERO)
		var is_dead := bool(state.get("is_dead", false))
		buffer.put_u32(network_id)
		_put_quantized(buffer, position.x, POSITION_SCALE)
		_put_quantized(buffer, position.y, POSITION_SCALE)
		_put_quantized(buffer, position.z, POSITION_SCALE)
		buffer.put_u8(_encode_angle(float(state.get("rotation", 0.0))))
		buffer.put_u16(clampi(int(state.get("health", 0)), 0, 65535))
		buffer.put_u8(FLAG_IS_DEAD if is_dead else 0)
		buffer.put_u16(posmod(int(state.get("attack_sequence", 0)), 65536))
		if is_dead:
			var velocity: Vector3 = state.get("death_velocity", Vector3.ZERO)
			_put_quantized(buffer, velocity.x, VELOCITY_SCALE)
			_put_quantized(buffer, velocity.y, VELOCITY_SCALE)
			_put_quantized(buffer, velocity.z, VELOCITY_SCALE)
	return buffer.data_array


## Decodifica para Dictionaries aceitos por zombie.apply_network_state().
## Payload truncado para no ultimo zumbi completo e registra erro.
## Uso: for state in ZombieSnapshotCodec.decode(payload): ...
static func decode(payload: PackedByteArray) -> Array[Dictionary]:
	var states: Array[Dictionary] = []
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = false
	buffer.data_array = payload
	while buffer.get_available_bytes() >= ALIVE_RECORD_BYTES:
		var network_id := buffer.get_u32()
		var position := Vector3(_get_quantized(buffer, POSITION_SCALE), _get_quantized(buffer, POSITION_SCALE), _get_quantized(buffer, POSITION_SCALE))
		var rotation := _decode_angle(buffer.get_u8())
		var health := buffer.get_u16()
		var flags := buffer.get_u8()
		var attack_sequence := buffer.get_u16()
		var state := {
			"name": NAME_PREFIX + str(network_id),
			"position": position,
			"rotation": rotation,
			"health": health,
			"is_dead": flags & FLAG_IS_DEAD != 0,
			"attack_sequence": attack_sequence,
		}
		if flags & FLAG_IS_DEAD != 0:
			if buffer.get_available_bytes() < DEAD_RECORD_BYTES - ALIVE_RECORD_BYTES:
				push_error("Snapshot de zumbi truncado no id %d; faltam bytes da velocidade de morte." % network_id)
				break
			state["death_velocity"] = Vector3(_get_quantized(buffer, VELOCITY_SCALE), _get_quantized(buffer, VELOCITY_SCALE), _get_quantized(buffer, VELOCITY_SCALE))
		states.append(state)
	if buffer.get_available_bytes() > 0 and buffer.get_available_bytes() < ALIVE_RECORD_BYTES:
		push_error("Snapshot de zumbi com %d bytes sobrando; esperado multiplo de registros completos." % buffer.get_available_bytes())
	return states


## Agrupa estados em lotes cujo payload codificado cabe em `max_bytes`, para
## cada RPC nao ser fragmentado pelo ENet (MTU ~1400 bytes).
## Uso: for packet_states in ZombieSnapshotCodec.split_into_packets(states, 1100): ...
static func split_into_packets(states: Array, max_bytes: int) -> Array[Array]:
	var packets: Array[Array] = []
	if max_bytes < DEAD_RECORD_BYTES:
		push_error("Orcamento de pacote %d bytes menor que um registro (%d); esperado >= %d." % [max_bytes, DEAD_RECORD_BYTES, DEAD_RECORD_BYTES])
		return packets
	var current: Array = []
	var current_bytes := 0
	for state in states:
		var size := record_size(state)
		if current_bytes + size > max_bytes and not current.is_empty():
			packets.append(current)
			current = []
			current_bytes = 0
		current.append(state)
		current_bytes += size
	if not current.is_empty() or packets.is_empty():
		packets.append(current)
	return packets


## Tamanho em bytes de um estado codificado (para montar pacotes abaixo do MTU).
## Uso: var size := ZombieSnapshotCodec.record_size(state)
static func record_size(state: Dictionary) -> int:
	return DEAD_RECORD_BYTES if bool(state.get("is_dead", false)) else ALIVE_RECORD_BYTES


static func _put_quantized(buffer: StreamPeerBuffer, value: float, scale: float) -> void:
	buffer.put_16(clampi(roundi(value / scale), -32768, 32767))


static func _get_quantized(buffer: StreamPeerBuffer, scale: float) -> float:
	return float(buffer.get_16()) * scale


static func _encode_angle(angle: float) -> int:
	return posmod(roundi(wrapf(angle, 0.0, TAU) / TAU * 256.0), 256)


static func _decode_angle(encoded: int) -> float:
	return wrapf(float(encoded) / 256.0 * TAU, -PI, PI)
