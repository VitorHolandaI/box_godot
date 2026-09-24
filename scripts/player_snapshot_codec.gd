# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name PlayerSnapshotCodec
extends RefCounted

## Estado dos jogadores em bytes compactos para o snapshot de rede. O Dictionary
## tinha ~708 bytes e ia um jogador por RPC para cada peer (N x N chamadas a
## 10 Hz): no benchmark da VPS o envio foi de 1,5 ms com 12 jogadores a 7-14 ms
## com 24. Aqui sao RECORD_BYTES por jogador e varios por pacote.
## Layout little-endian por jogador:
##   s32 peer | u8 slot | f32 x y z | u16 rotacao | u16 vida | u16 stamina*10
##   | u8 flags (0 correndo, 1 eliminado, 2 caido, 3 tem slots) | u8 arma
##   | u8 municao pistola | u16 reserva | u16 ms postura, recuo, faca, clarao, tranco
##   | i8 hit_dir_x*127 | u8 vidas | u32 abates | u16 teleporte | u8 reviver*255
##   | u8 granadas, facas, ataque aereo, swat
##   | u8 time | u8 protecao*10 | u8 abates | u8 mortes | u8 reservado (PVP)
##   [u16 tamanho | var_to_bytes(weapon_slots)] quando flags tem 3
## Uso:
##   var payload := PlayerSnapshotCodec.encode(states, {"123:0": true})
##   var states := PlayerSnapshotCodec.decode(payload)

## 51 bytes base + 5 do mata-mata (time/protecao/abates/mortes/reserva).
const RECORD_BYTES := 56
const FLAG_SPRINTING := 1
const FLAG_ELIMINATED := 2
const FLAG_DOWNED := 4
const FLAG_HAS_SLOTS := 8
const TIMER_KEYS := ["pistol_stance", "pistol_recoil", "knife_attack", "muzzle_flash", "hit_reaction"]


## `include_slots` tem as chaves dos jogadores cujo weapon_slots vai junto.
## Uso: var payload := PlayerSnapshotCodec.encode([state], {})
static func encode(states: Array, include_slots: Dictionary) -> PackedByteArray:
	var payload := PackedByteArray()
	var offset := 0
	for state_value in states:
		var state := state_value as Dictionary
		var key := String(state.get("key", ""))
		var key_parts := key.split(":")
		if key_parts.size() != 2 or not key_parts[0].is_valid_int() or not key_parts[1].is_valid_int():
			push_error("Chave de jogador invalida no snapshot: '%s'; esperado 'peer:slot'." % key)
			continue
		var slots_bytes := _slots_bytes(state, include_slots.has(key))
		payload.resize(offset + RECORD_BYTES + (2 + slots_bytes.size() if not slots_bytes.is_empty() else 0))
		_write_record(payload, offset, state, int(key_parts[0]), int(key_parts[1]), not slots_bytes.is_empty())
		offset += RECORD_BYTES
		if slots_bytes.is_empty():
			continue
		payload.encode_u16(offset, slots_bytes.size())
		for index in slots_bytes.size():
			payload[offset + 2 + index] = slots_bytes[index]
		offset += 2 + slots_bytes.size()
	return payload


## Dictionaries com as mesmas chaves de player.get_network_state() mais "key".
## Payload truncado para no ultimo jogador completo e registra erro.
## Uso: for state in PlayerSnapshotCodec.decode(payload): ...
static func decode(payload: PackedByteArray) -> Array[Dictionary]:
	var states: Array[Dictionary] = []
	var offset := 0
	while payload.size() - offset >= RECORD_BYTES:
		var state := _read_record(payload, offset)
		var flags := payload.decode_u8(offset + 23)
		offset += RECORD_BYTES
		if flags & FLAG_HAS_SLOTS != 0:
			if payload.size() - offset < 2 or payload.size() - offset - 2 < payload.decode_u16(offset):
				push_error("Snapshot de jogador truncado na chave %s; faltam bytes dos slots de arma." % state["key"])
				break
			var slots_size := payload.decode_u16(offset)
			var slots_value: Variant = bytes_to_var(payload.slice(offset + 2, offset + 2 + slots_size))
			if slots_value is Dictionary:
				state["weapon_slots"] = slots_value
			offset += 2 + slots_size
		states.append(state)
	if offset < payload.size() and payload.size() - offset < RECORD_BYTES:
		push_error("Snapshot de jogador com %d bytes sobrando; esperado registro completo de %d." % [payload.size() - offset, RECORD_BYTES])
	return states


## Agrupa jogadores em pacotes de ate `max_bytes` (um jogador sozinho maior
## que o orcamento ainda vai, num pacote so dele).
## Uso: for packet in PlayerSnapshotCodec.split_into_packets(states, include_slots, 1100): ...
static func split_into_packets(states: Array, include_slots: Dictionary, max_bytes: int) -> Array[Array]:
	var packets: Array[Array] = []
	var current: Array = []
	var current_bytes := 0
	for state in states:
		var size := record_size(state, include_slots.has(String((state as Dictionary).get("key", ""))))
		if current_bytes + size > max_bytes and not current.is_empty():
			packets.append(current)
			current = []
			current_bytes = 0
		current.append(state)
		current_bytes += size
	if not current.is_empty() or packets.is_empty():
		packets.append(current)
	return packets


## Uso: PlayerSnapshotCodec.record_size(state, false) -> RECORD_BYTES
static func record_size(state: Dictionary, with_slots: bool) -> int:
	var slots_bytes := _slots_bytes(state, with_slots)
	return RECORD_BYTES + (2 + slots_bytes.size() if not slots_bytes.is_empty() else 0)


static func _slots_bytes(state: Dictionary, with_slots: bool) -> PackedByteArray:
	var slots: Variant = state.get("weapon_slots")
	if not with_slots or not slots is Dictionary:
		return PackedByteArray()
	return var_to_bytes(slots)


static func _write_record(payload: PackedByteArray, offset: int, state: Dictionary, peer_id: int, slot: int, has_slots: bool) -> void:
	var position: Vector3 = state.get("position", Vector3.ZERO)
	var flags := (FLAG_SPRINTING if bool(state.get("sprinting", false)) else 0) \
		| (FLAG_ELIMINATED if bool(state.get("eliminated", false)) else 0) \
		| (FLAG_DOWNED if bool(state.get("downed", false)) else 0) \
		| (FLAG_HAS_SLOTS if has_slots else 0)
	# s32, nao u32: o ENet sorteia id de peer de 32 bits COM sinal (o esquadrao
	# SWAT usa ids negativos reservados). Em u32 o cliente lia -1001 como
	# 4294966295 e nao achava o no: o estado era descartado e o soldado ficava
	# parado na origem, invisivel.
	payload.encode_s32(offset, peer_id)
	payload.encode_u8(offset + 4, clampi(slot, 0, 255))
	payload.encode_float(offset + 5, position.x)
	payload.encode_float(offset + 9, position.y)
	payload.encode_float(offset + 13, position.z)
	payload.encode_u16(offset + 17, posmod(roundi(wrapf(float(state.get("rotation", 0.0)), 0.0, TAU) / TAU * 65536.0), 65536))
	payload.encode_u16(offset + 19, clampi(int(state.get("health", 0)), 0, 65535))
	payload.encode_u16(offset + 21, clampi(roundi(float(state.get("stamina", 0.0)) * 10.0), 0, 65535))
	payload.encode_u8(offset + 23, flags)
	payload.encode_u8(offset + 24, clampi(int(state.get("weapon", 0)), 0, 255))
	payload.encode_u8(offset + 25, clampi(int(state.get("pistol_ammo", 0)), 0, 255))
	payload.encode_u16(offset + 26, clampi(int(state.get("reserve_ammo", 0)), 0, 65535))
	for index in TIMER_KEYS.size():
		payload.encode_u16(offset + 28 + index * 2, clampi(roundi(float(state.get(TIMER_KEYS[index], 0.0)) * 1000.0), 0, 65535))
	payload.encode_s8(offset + 38, clampi(roundi(float(state.get("hit_dir_x", 0.0)) * 127.0), -127, 127))
	payload.encode_u8(offset + 39, clampi(int(state.get("lives", 0)), 0, 255))
	payload.encode_u32(offset + 40, clampi(int(state.get("zombie_kills", 0)), 0, 4294967295))
	payload.encode_u16(offset + 44, posmod(int(state.get("teleport_sequence", 0)), 65536))
	payload.encode_u8(offset + 46, clampi(roundi(float(state.get("revive_progress", 0.0)) * 255.0), 0, 255))
	var equipment_counts: Variant = state.get("equipment", PackedByteArray())
	for index in 4:
		var count := 0
		if equipment_counts is PackedByteArray and index < (equipment_counts as PackedByteArray).size():
			count = (equipment_counts as PackedByteArray)[index]
		payload.encode_u8(offset + 47 + index, clampi(count, 0, 255))
	# Mata-mata: time (255 = fora da partida), abates, mortes e a protecao de
	# respawn em decimos de segundo. Antes estes 5 bytes levavam dinheiro e
	# tempo de compra, que sairam com a economia (ver TdmMatch).
	payload.encode_u8(offset + 51, clampi(int(state.get("pvp_team", -1)), -1, 254) if int(state.get("pvp_team", -1)) >= 0 else 255)
	payload.encode_u8(offset + 52, clampi(roundi(float(state.get("spawn_protection_left", 0.0)) * 10.0), 0, 255))
	payload.encode_u8(offset + 53, clampi(int(state.get("pvp_kills", 0)), 0, 255))
	payload.encode_u8(offset + 54, clampi(int(state.get("pvp_deaths", 0)), 0, 255))
	payload.encode_u8(offset + 55, 0)


## 255 no byte do time significa "fora da partida" (-1): o valor precisa passar
## por um byte sem sinal, e -1 nao cabe nele.
static func _decode_team(raw: int) -> int:
	return -1 if raw == 255 else raw


static func _read_record(payload: PackedByteArray, offset: int) -> Dictionary:
	var flags := payload.decode_u8(offset + 23)
	var state := {
		"key": "%d:%d" % [payload.decode_s32(offset), payload.decode_u8(offset + 4)],
		"position": Vector3(payload.decode_float(offset + 5), payload.decode_float(offset + 9), payload.decode_float(offset + 13)),
		"rotation": wrapf(float(payload.decode_u16(offset + 17)) / 65536.0 * TAU, -PI, PI),
		"health": payload.decode_u16(offset + 19),
		"stamina": float(payload.decode_u16(offset + 21)) / 10.0,
		"sprinting": flags & FLAG_SPRINTING != 0,
		"eliminated": flags & FLAG_ELIMINATED != 0,
		"downed": flags & FLAG_DOWNED != 0,
		"weapon": payload.decode_u8(offset + 24),
		"pistol_ammo": payload.decode_u8(offset + 25),
		"reserve_ammo": payload.decode_u16(offset + 26),
		"hit_dir_x": float(payload.decode_s8(offset + 38)) / 127.0,
		"lives": payload.decode_u8(offset + 39),
		"zombie_kills": payload.decode_u32(offset + 40),
		"teleport_sequence": payload.decode_u16(offset + 44),
		"revive_progress": float(payload.decode_u8(offset + 46)) / 255.0,
		"equipment": payload.slice(offset + 47, offset + 51),
		"pvp_team": _decode_team(payload.decode_u8(offset + 51)),
		"spawn_protection_left": float(payload.decode_u8(offset + 52)) / 10.0,
		"pvp_kills": payload.decode_u8(offset + 53),
		"pvp_deaths": payload.decode_u8(offset + 54),
	}
	for index in TIMER_KEYS.size():
		state[TIMER_KEYS[index]] = float(payload.decode_u16(offset + 28 + index * 2)) / 1000.0
	return state
