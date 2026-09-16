extends RefCounted

## Regressoes do snapshot binario de jogadores. Antes cada jogador ia num RPC
## proprio (~708 bytes de Dictionary) para cada peer: N x N chamadas a 10 Hz, e
## no benchmark da VPS o envio foi de 1,5 ms (12 jogadores) a 7-14 ms (24).
## Uso: PlayerSnapshotCodecTests.new().run(test_root)

const CODEC_SCRIPT := preload("res://scripts/player_snapshot_codec.gd")
const SLOTS_TRACKER_SCRIPT := preload("res://scripts/player_slots_replication.gd")
const PLAYER_SCENE := preload("res://scenes/player.tscn")


func run(test_root: Node) -> void:
	_test_roundtrip_keeps_player_state(test_root)
	_test_record_without_slots_is_compact(test_root)
	_test_many_players_share_packets(test_root)
	_test_truncated_payload_keeps_complete_records(test_root)
	_test_slots_sent_on_change_and_periodically(test_root)


func _real_state(test_root: Node, key: String) -> Dictionary:
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.set("reads_local_input", false)
	test_root.add_child(player)
	player.call("take_crate_weapon", WeaponStats.Kind.UZI)
	player.global_position = Vector3(-123.45, 3.5, 67.25)
	player.rotation.y = 1.25
	player.set("health", 73)
	player.set("stamina", 42.5)
	player.set("is_sprinting", true)
	player.set("pistol_stance_time", 7.5)
	player.set("hit_direction", Vector3(-0.5, 0.0, 0.0))
	player.set("zombie_kills", 321)
	player.set("teleport_sequence", 9)
	player.set("revive_progress", 0.5)
	var state: Dictionary = player.get_network_state()
	state["key"] = key
	player.free()
	return state


func _test_roundtrip_keeps_player_state(test_root: Node) -> void:
	print("Testando snapshot binario de jogador ida e volta...")
	var state := _real_state(test_root, "2147483647:3")
	var decoded: Array[Dictionary] = CODEC_SCRIPT.decode(CODEC_SCRIPT.encode([state], {"2147483647:3": true}))
	if decoded.size() != 1:
		_fail(test_root, "Esperado 1 jogador decodificado; veio %d." % decoded.size())
		return
	var got: Dictionary = decoded[0]
	var mismatches: Array[String] = []
	if got["key"] != state["key"]:
		mismatches.append("key")
	if (got["position"] as Vector3).distance_to(state["position"]) > 0.01:
		mismatches.append("position")
	if absf(angle_difference(float(got["rotation"]), float(state["rotation"]))) > 0.001:
		mismatches.append("rotation")
	for int_key in ["health", "weapon", "pistol_ammo", "reserve_ammo", "lives", "zombie_kills", "teleport_sequence"]:
		if int(got[int_key]) != int(state[int_key]):
			mismatches.append(int_key)
	for bool_key in ["sprinting", "eliminated", "downed"]:
		if bool(got[bool_key]) != bool(state[bool_key]):
			mismatches.append(bool_key)
	for float_key in ["stamina", "pistol_stance", "pistol_recoil", "knife_attack", "muzzle_flash", "hit_reaction", "hit_dir_x", "revive_progress"]:
		if absf(float(got[float_key]) - float(state[float_key])) > 0.01:
			mismatches.append(float_key)
	if got.get("weapon_slots") != state["weapon_slots"]:
		mismatches.append("weapon_slots")
	if not mismatches.is_empty():
		_fail(test_root, "Campos divergentes no snapshot de jogador: %s; enviado=%s recebido=%s." % [mismatches, state, got])
		return
	print("PASS: Snapshot binario de jogador preserva o estado.")


func _test_record_without_slots_is_compact(test_root: Node) -> void:
	print("Testando registro de jogador sem slots de arma...")
	var state := _real_state(test_root, "7:0")
	var payload: PackedByteArray = CODEC_SCRIPT.encode([state], {})
	var decoded: Array[Dictionary] = CODEC_SCRIPT.decode(payload)
	var size_ok: bool = payload.size() == CODEC_SCRIPT.RECORD_BYTES and CODEC_SCRIPT.record_size(state, false) == CODEC_SCRIPT.RECORD_BYTES
	if not size_ok or decoded.size() != 1 or decoded[0].has("weapon_slots"):
		_fail(test_root, "Registro sem slots deveria ter %d bytes e nao trazer weapon_slots; veio %d bytes e %s." % [CODEC_SCRIPT.RECORD_BYTES, payload.size(), decoded])
		return
	print("PASS: Registro de jogador sem slots tem %d bytes." % payload.size())


func _test_many_players_share_packets(test_root: Node) -> void:
	print("Testando 24 jogadores em poucos pacotes abaixo do MTU...")
	var template := _real_state(test_root, "0:0")
	var states: Array = []
	var include_slots: Dictionary = {}
	for index in 24:
		var state := template.duplicate(true)
		state["key"] = "%d:%d" % [1000 + index, 0]
		states.append(state)
		if index % 6 == 0:
			include_slots[state["key"]] = true
	var packets: Array[Array] = CODEC_SCRIPT.split_into_packets(states, include_slots, 1100)
	var total := 0
	for packet in packets:
		var payload: PackedByteArray = CODEC_SCRIPT.encode(packet, include_slots)
		if payload.size() > 1100:
			_fail(test_root, "Pacote de jogadores com %d bytes passa do orcamento de 1100." % payload.size())
			return
		total += CODEC_SCRIPT.decode(payload).size()
	if total != 24 or packets.size() > 3:
		_fail(test_root, "24 jogadores deveriam caber em ate 3 pacotes; vieram %d pacotes com %d jogadores." % [packets.size(), total])
		return
	print("PASS: 24 jogadores em %d pacotes." % packets.size())


func _test_truncated_payload_keeps_complete_records(test_root: Node) -> void:
	print("Testando snapshot de jogador truncado...")
	var state := _real_state(test_root, "5:1")
	var second := state.duplicate(true)
	second["key"] = "6:0"
	var payload: PackedByteArray = CODEC_SCRIPT.encode([state, second], {})
	var decoded: Array[Dictionary] = CODEC_SCRIPT.decode(payload.slice(0, payload.size() - 3))
	if decoded.size() != 1 or decoded[0]["key"] != "5:1":
		_fail(test_root, "Payload truncado deveria manter so o primeiro jogador completo; veio %s." % [decoded])
		return
	print("PASS: Snapshot truncado mantem os jogadores completos.")


func _test_slots_sent_on_change_and_periodically(test_root: Node) -> void:
	print("Testando envio de slots de arma so quando mudam ou periodicamente...")
	var tracker = SLOTS_TRACKER_SCRIPT.new()
	var sends: Array[bool] = []
	# Revisao 1 por 30 snapshots, depois muda para 2.
	for snapshot in 30:
		sends.append(tracker.should_include("9:0", 1, snapshot))
	sends.append(tracker.should_include("9:0", 2, 30))
	var first_burst := sends.slice(0, SLOTS_TRACKER_SCRIPT.RESEND_SNAPSHOTS).all(func(sent: bool) -> bool: return sent)
	var quiet := sends.slice(SLOTS_TRACKER_SCRIPT.RESEND_SNAPSHOTS, 30).count(true)
	var expected_quiet := 0
	for snapshot in range(SLOTS_TRACKER_SCRIPT.RESEND_SNAPSHOTS, 30):
		if SLOTS_TRACKER_SCRIPT.refresh_due("9:0", snapshot):
			expected_quiet += 1
	if not first_burst or quiet != expected_quiet or not sends[30]:
		_fail(test_root, "Slots: rajada inicial=%s, reenvios quietos=%d (esperado %d), mudanca enviada=%s." % [first_burst, quiet, expected_quiet, sends[30]])
		return
	print("PASS: Slots de arma enviados na mudanca e a cada %d snapshots." % SLOTS_TRACKER_SCRIPT.REFRESH_SNAPSHOTS)


func _fail(test_root: Node, message: String) -> void:
	push_error("FALHA: " + message)
	test_root.set_meta("unit_test_failed", true)
