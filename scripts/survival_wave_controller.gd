class_name SurvivalWaveController
extends RefCounted

signal state_changed
signal wave_started(wave_index: int)

const SURVIVAL_WAVE_SCHEDULE_SCRIPT := preload("res://scripts/survival_wave_schedule.gd")
const SPAWN_INTERVAL := 0.18
## GAME OVER com jogador presente reinicia sozinho depois deste tempo.
const GAME_OVER_RESTART_SECONDS := 8.0

var schedule = SURVIVAL_WAVE_SCHEDULE_SCRIPT.new()
var spawn_callback: Callable
var wave_index := 0
var spawned_in_wave := 0
var alive_in_wave := 0
var total_kills := 0
var complete := false
## Todo mundo caido/eliminado: horda zera e a partida espera novo jogador.
var game_over := false
var _spawn_elapsed := 0.0
var _game_over_elapsed := 0.0


func _init(callback: Callable = Callable()) -> void:
	spawn_callback = callback


func tick(delta: float) -> void:
	if complete or game_over or not spawn_callback.is_valid():
		return
	_spawn_elapsed += maxf(delta, 0.0)
	var target := schedule.target_for(wave_index)
	if spawned_in_wave < target and _spawn_elapsed >= SPAWN_INTERVAL:
		_spawn_elapsed = 0.0
		if bool(spawn_callback.call()):
			spawned_in_wave += 1
			alive_in_wave += 1
			state_changed.emit()
		return
	if spawned_in_wave < target or alive_in_wave > 0:
		return
	if schedule.is_final_wave(wave_index):
		complete = true
	else:
		wave_index += 1
		spawned_in_wave = 0
		_spawn_elapsed = 0.0
		wave_started.emit(wave_index)
	state_changed.emit()


func register_death() -> void:
	if alive_in_wave > 0:
		alive_in_wave -= 1
	total_kills += 1
	state_changed.emit()


## Estado vindo do servidor (cliente nao simula ondas): alinha o HUD sem
## simular spawn. `alive` e o restante real da onda no servidor; antes o
## cliente calculava alvo - abates totais, que somam todas as ondas.
## `is_game_over` tambem vem do servidor: sem ele o cliente ficava na tela de
## GAME OVER depois que a horda reiniciava.
## Uso: controller.set_sync_state(new_wave_index, kills, alive, false)
func set_sync_state(new_wave_index: int, kills: int, alive: int = -1, is_game_over: bool = false) -> void:
	total_kills = maxi(kills, 0)
	game_over = is_game_over
	if new_wave_index < 0 or complete:
		return
	wave_index = new_wave_index
	spawned_in_wave = schedule.target_for(wave_index)
	alive_in_wave = alive if alive >= 0 else maxi(schedule.target_for(wave_index) - total_kills, 0)
	state_changed.emit()


## Ninguem de pe: todos caidos/eliminados ou nenhum jogador conectado. Servidor
## vazio entra em game over de proposito (nao gasta CPU com horda sem alvo); quem
## entra depois reinicia a horda em main._on_peer_scene_loaded, inclusive na onda 0.
## Uso: if SurvivalWaveController.everyone_is_down(get_tree().get_nodes_in_group("player")): ...
static func everyone_is_down(players: Array) -> bool:
	for player_node in players:
		if not is_instance_valid(player_node) or (player_node as Node).is_queued_for_deletion():
			continue
		if player_node.get("is_downed") != true and player_node.get("is_eliminated") != true:
			return false
	return true


## Game over: para tudo; reinicia sozinho (tick_game_over) ou quando alguem entra.
func trigger_game_over() -> void:
	game_over = true
	_game_over_elapsed = 0.0
	state_changed.emit()


## Conta o tempo em GAME OVER e diz quando reiniciar. Antes so reiniciava quando
## um jogador NOVO entrava: quem caiu junto, ou a partida local, ficava parado
## sem zumbis. Sem jogadores o relogio fica zerado (servidor vazio espera).
## Uso: if controller.tick_game_over(delta, not players.is_empty()): _restart_survival()
func tick_game_over(delta: float, has_players: bool) -> bool:
	if not game_over or not has_players:
		_game_over_elapsed = 0.0
		return false
	_game_over_elapsed += maxf(delta, 0.0)
	return _game_over_elapsed >= GAME_OVER_RESTART_SECONDS


## Alguem entrou de novo: horda zerada recomeca do comeco.
func restart() -> void:
	game_over = false
	_game_over_elapsed = 0.0
	complete = false
	wave_index = 0
	spawned_in_wave = 0
	alive_in_wave = 0
	total_kills = 0
	_spawn_elapsed = 0.0
	state_changed.emit()


func get_hud_text() -> String:
	if game_over:
		return "GAME OVER | A horda recomeca em instantes..."
	if complete:
		return "SOBREVIVENCIA CONCLUIDA | Horas: %d | Abates: %d" % [schedule.wave_count(), total_kills]
	var current_hour := wave_index + 1
	return "Hora %d/%d | Onda %d/%d | Abates: %d | Restantes: %d/%d" % [current_hour, schedule.wave_count(), current_hour, schedule.wave_count(), total_kills, alive_in_wave, schedule.target_for(wave_index)]
