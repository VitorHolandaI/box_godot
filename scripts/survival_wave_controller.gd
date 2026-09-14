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
var _spawn_elapsed := 0.0


func _init(callback: Callable = Callable()) -> void:
	spawn_callback = callback


func tick(delta: float) -> void:
	if complete or not spawn_callback.is_valid():
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


func get_hud_text() -> String:
	if complete:
		return "SOBREVIVENCIA CONCLUIDA | Horas: %d | Abates: %d" % [schedule.wave_count(), total_kills]
	var current_hour := wave_index + 1
	return "Hora %d/%d | Onda %d/%d | Abates: %d | Restantes: %d/%d" % [current_hour, schedule.wave_count(), current_hour, schedule.wave_count(), total_kills, alive_in_wave, schedule.target_for(wave_index)]
