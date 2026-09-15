extends RefCounted

## Regressoes do snapshot binario de zumbis (banda de rede).
## Uso: ZombieSnapshotCodecTests.new().run(test_root)

const CODEC_SCRIPT := preload("res://scripts/zombie_snapshot_codec.gd")


func run(test_root: Node) -> void:
	_test_round_trip_keeps_state(test_root)
	_test_packets_fit_budget(test_root)
	_test_truncated_payload_is_rejected(test_root)


func _test_round_trip_keeps_state(test_root: Node) -> void:
	print("Testando ida e volta do snapshot binario de zumbis...")
	var alive := {"network_id": 4242, "position": Vector3(-123.456, 3.21, 88.8), "rotation": -2.5, "health": 85, "is_dead": false, "attack_sequence": 1234}
	var dead := {"network_id": 7, "position": Vector3(1.0, 0.5, -1.0), "rotation": 1.0, "health": 0, "is_dead": true, "attack_sequence": 3, "death_velocity": Vector3(2.5, -1.25, 0.5)}
	var payload: PackedByteArray = CODEC_SCRIPT.encode([alive, dead])
	var decoded: Array[Dictionary] = CODEC_SCRIPT.decode(payload)
	if payload.size() != CODEC_SCRIPT.ALIVE_RECORD_BYTES + CODEC_SCRIPT.DEAD_RECORD_BYTES or decoded.size() != 2:
		_fail(test_root, "Snapshot deveria ter %d bytes e 2 zumbis; bytes=%d zumbis=%d." % [CODEC_SCRIPT.ALIVE_RECORD_BYTES + CODEC_SCRIPT.DEAD_RECORD_BYTES, payload.size(), decoded.size()])
		return
	var first := decoded[0]
	var rotation_error := absf(angle_difference(float(first["rotation"]), -2.5))
	var position_ok := (first["position"] as Vector3).distance_to(alive["position"]) <= CODEC_SCRIPT.POSITION_SCALE
	if first["name"] != "ZombieSpawn4242" or not position_ok or rotation_error > TAU / 256.0 or int(first["health"]) != 85 or int(first["attack_sequence"]) != 1234 or bool(first["is_dead"]):
		_fail(test_root, "Zumbi vivo decodificado errado: %s." % first)
		return
	var second := decoded[1]
	if not bool(second["is_dead"]) or (second["death_velocity"] as Vector3).distance_to(dead["death_velocity"]) > CODEC_SCRIPT.VELOCITY_SCALE:
		_fail(test_root, "Zumbi morto deveria trazer velocidade de morte: %s." % second)
		return
	print("PASS: Snapshot binario preserva id, posicao, rotacao, vida, ataque e morte.")


func _test_packets_fit_budget(test_root: Node) -> void:
	print("Testando pacotes de zumbis abaixo do orcamento de bytes...")
	var states: Array = []
	for index in 600:
		states.append({"network_id": index, "position": Vector3(index, 1.0, -index), "is_dead": index % 7 == 0})
	var packets: Array[Array] = CODEC_SCRIPT.split_into_packets(states, 1100)
	var total := 0
	for packet in packets:
		var size := CODEC_SCRIPT.encode(packet).size()
		total += packet.size()
		if size > 1100:
			_fail(test_root, "Pacote de %d bytes excede o orcamento de 1100." % size)
			return
	if total != 600 or packets.size() > 10:
		_fail(test_root, "600 zumbis deveriam caber em no maximo 10 pacotes; pacotes=%d zumbis=%d." % [packets.size(), total])
		return
	print("PASS: 600 zumbis cabem em %d pacotes abaixo do MTU." % packets.size())


func _test_truncated_payload_is_rejected(test_root: Node) -> void:
	print("Testando snapshot binario truncado...")
	var payload: PackedByteArray = CODEC_SCRIPT.encode([{"network_id": 1, "position": Vector3.ZERO, "is_dead": false}, {"network_id": 2, "position": Vector3.ZERO, "is_dead": false}])
	payload.resize(payload.size() - 3)
	var decoded: Array[Dictionary] = CODEC_SCRIPT.decode(payload)
	if decoded.size() != 1:
		_fail(test_root, "Payload truncado deveria decodificar so o zumbi completo; decodificou %d." % decoded.size())
		return
	print("PASS: Snapshot truncado descarta o registro incompleto.")


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
