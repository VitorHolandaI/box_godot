# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name WeaponSlots
extends RefCounted

## Inventario de armas de crate do jogador: 1 slot unico (o jogador tem 3
## armas no total: faca fixa, pistola fixa e uma arma de crate por vez). Pegar
## outra arma troca: a da mao cai no chao como pickup. Estado viaja no
## snapshot do servidor.
## Uso:
##   var slots := WeaponSlots.new()
##   slots.grant(WeaponStats.Kind.SHOTGUN)

const MAX_SLOTS := 1
## Mata-mata: a arma vem com MUITA reserva, mas desgasta igual ao survival. No
## survival a municao e um recurso escasso (voce repoe com drops); no mata-mata
## procurar municao so tira o jogador do tiroteio. A DURABILIDADE fica valendo:
## a arma e escolhida de graca, entao sem desgaste ela seria eterna — e e o
## desgaste que degrada (spread dobrado, chance de falha) e faz a arma do chao,
## largada por quem morreu, valer alguma coisa.
const PVP_RESERVE_MULTIPLIER := 4
const PVP_RESERVE_CAP := 2000

var kinds: Array[int] = []
var state_by_kind: Dictionary = {}
## Incrementa a cada mutacao: o snapshot replica so quando muda de fato.
var revision := 0


func _bump() -> void:
	revision += 1


func has_kind(kind: int) -> bool:
	return kinds.has(kind)


func has_free_slot() -> bool:
	return kinds.size() < MAX_SLOTS


## Coloca a arma num slot livre com pente/reserva cheios e durabilidade maxima.
## Uso: if slots.has_free_slot(): slots.grant(WeaponStats.Kind.UZI)
func grant(kind: int) -> void:
	if not WeaponStats.is_crate_weapon(kind) or kinds.has(kind) or not has_free_slot():
		return
	var stats := WeaponStats.stats_for(kind)
	kinds.append(kind)
	state_by_kind[kind] = {
		"mag": int(stats["mag_size"]),
		"reserve": _grant_reserve_for(stats),
		"durability": int(stats["max_durability"]),
	}


## Reserva que a arma recebe ao ser comprada/pega: no PVP multiplica e limita o
## excesso. Uso: var reserva := _grant_reserve_for(WeaponStats.stats_for(kind))
func _grant_reserve_for(stats: Dictionary) -> int:
	var reserve := int(stats["grant_reserve"])
	if NetworkSession.pvp_mode:
		reserve = mini(reserve * PVP_RESERVE_MULTIPLIER, PVP_RESERVE_CAP)
	return reserve
	_bump()


## Devolve o estado da arma (pente/reserva/durabilidade) e libera o slot.
## Uso: var estado := slots.remove_kind(kind)
func remove_kind(kind: int) -> Dictionary:
	kinds.erase(kind)
	var state: Dictionary = state_by_kind.get(kind, {})
	state_by_kind.erase(kind)
	_bump()
	return state


func state_of(kind: int) -> Dictionary:
	return state_by_kind.get(kind, {})


## Consome 1 bala do pente; false quando o pente ja esta vazio.
## Uso: if not slots.consume_mag(kind): slots.reload(kind)
func consume_mag(kind: int) -> bool:
	var state := state_of(kind)
	if state.is_empty() or int(state["mag"]) <= 0:
		return false
	state["mag"] = int(state["mag"]) - 1
	_bump()
	return true


## Recarrega o pente a partir da reserva da propria arma.
## Uso: slots.reload(kind)
func reload(kind: int) -> void:
	var state := state_of(kind)
	if state.is_empty():
		return
	var stats := WeaponStats.stats_for(kind)
	var needed := int(stats["mag_size"]) - int(state["mag"])
	var loaded := mini(needed, int(state["reserve"]))
	state["mag"] = int(state["mag"]) + loaded
	state["reserve"] = int(state["reserve"]) - loaded
	_bump()


## Adiciona municao a reserva da arma ate o limite da tabela de stats.
## Retorna o total efetivamente adicionado. Uso: var extra := slots.add_reserve(kind, 24)
func add_reserve(kind: int, amount: int) -> int:
	var state := state_of(kind)
	if amount <= 0 or state.is_empty():
		return 0
	var stats := WeaponStats.stats_for(kind)
	var space := int(stats["max_reserve"]) - int(state["reserve"])
	var added := mini(amount, space)
	state["reserve"] = int(state["reserve"]) + added
	_bump()
	return added


func free_reserve_space(kind: int) -> int:
	var state := state_of(kind)
	if state.is_empty():
		return 0
	var stats := WeaponStats.stats_for(kind)
	return int(stats["max_reserve"]) - int(state["reserve"])


## Desgasta a arma em 1 e devolve a durabilidade restante (0 = quebrada).
## Uso: var restante := slots.wear(kind)
func wear(kind: int) -> int:
	var state := state_of(kind)
	if state.is_empty():
		return 0
	state["durability"] = maxi(int(state["durability"]) - 1, 0)
	_bump()
	return int(state["durability"])


## Abaixo do limiar da tabela a arma degrada (spread dobra e chance de falha).
## Uso: if slots.is_degraded(kind): ...
func is_degraded(kind: int) -> bool:
	var state := state_of(kind)
	if state.is_empty():
		return false
	return int(state["durability"]) < int(WeaponStats.stats_for(kind)["degraded_below"])


## Prepara uma arma dropada no chao com o estado atual (pente/reserva/durab).
## Uso: var carga := slots.remove_kind(kind)
func serialize() -> Dictionary:
	var kinds_value: Array = []
	for kind in kinds:
		kinds_value.append(int(kind))
	return {"revision": revision, "kinds": kinds_value, "state_by_kind": state_by_kind.duplicate(true)}


func from_dict(dict: Dictionary) -> void:
	kinds.clear()
	state_by_kind.clear()
	revision = int(dict.get("revision", revision + 1))
	var stats := WeaponStats.STATS_BY_KIND
	var net_kinds: Variant = dict.get("kinds", [])
	if net_kinds is Array:
		for kind_value in net_kinds:
			var kind := int(kind_value)
			if stats.has(kind) and not kinds.has(kind) and kinds.size() < MAX_SLOTS:
				kinds.append(kind)
	var net_states: Variant = dict.get("state_by_kind", {})
	if net_states is Dictionary:
		for kind_value in (net_states as Dictionary):
			var kind := int(kind_value)
			if not stats.has(kind) or not kinds.has(kind):
				continue
			var entry: Dictionary = (net_states as Dictionary)[kind_value]
			state_by_kind[kind] = _clamp_state(kind, entry)
	# Estado ausente no snapshot recebe stats novos, para configs antigas.
	for kind in kinds:
		if not state_by_kind.has(kind):
			var full := WeaponStats.stats_for(kind)
			state_by_kind[kind] = _clamp_state(kind, {"mag": full["mag_size"], "reserve": full["grant_reserve"], "durability": full["max_durability"]})


func _clamp_state(kind: int, entry: Dictionary) -> Dictionary:
	var stats := WeaponStats.stats_for(kind)
	return {
		"mag": clampi(int(entry.get("mag", 0)), 0, int(stats["mag_size"])),
		"reserve": clampi(int(entry.get("reserve", 0)), 0, int(stats["max_reserve"])),
		"durability": clampi(int(entry.get("durability", 0)), 0, int(stats["max_durability"])),
	}
