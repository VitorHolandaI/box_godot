class_name SurvivalWaveController
extends RefCounted

signal state_changed
signal wave_started(wave_index: int)

const SURVIVAL_WAVE_SCHEDULE_SCRIPT := preload("res://scripts/survival_wave_schedule.gd")
const SPAWN_INTERVAL := 0.18

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
## simular spawn. Uso: controller.set_sync_state(wave_index, kills)
## Estado vindo do servidor (cliente nao simula ondas): alinha o HUD sem
## simular spawn. Uso: controller.set_sync_state(new_wave_index, kills)
func set_sync_state(new_wave_index: int, kills: int) -> void:
	total_kills = maxi(kills, 0)
	if new_wave_index < 0 or complete:
		return
	wave_index = new_wave_index
	spawned_in_wave = schedule.target_for(wave_index)
	alive_in_wave = maxi(schedule.target_for(wave_index) - total_kills, 0)
	state_changed.emit()


## Game over: para tudo; o HUD espera um jogador para reiniciar.
func trigger_game_over() -> void:
	game_over = true
	state_changed.emit()


## Alguem entrou de novo: horda zerada recomeca do comeco.
func restart() -> void:
	game_over = false
	complete = false
	wave_index = 0
	spawned_in_wave = 0
	alive_in_wave = 0
	total_kills = 0
	_spawn_elapsed = 0.0
	state_changed.emit()


func get_hud_text() -> String:
	if game_over:
		return "GAME OVER | Aguardando jogador para reiniciar a horda..."
	if complete:
		return "SOBREVIVENCIA CONCLUIDA | Horas: %d | Abates: %d" % [schedule.wave_count(), total_kills]
	var current_hour := wave_index + 1
	return "Hora %d/%d | Onda %d/%d | Abates: %d | Restantes: %d/%d" % [current_hour, schedule.wave_count(), current_hour, schedule.wave_count(), total_kills, alive_in_wave, schedule.target_for(wave_index)]
