# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name FramePerfProbe
extends RefCounted

## Sonda de custo por frame para caçar as micro travadas com a horda de 200.
## A 60 Hz o frame tem 16,7 ms; o que passa disso aparece como tremida. Cada
## sistema pesado mede o proprio trecho (zumbis, flock, snapshots...) e a sonda:
## - a cada REPORT_SECONDS imprime `perf_report` (FPS, p95, frames fora do
##   orcamento, frames com 2+ ticks de fisica e custo medio/maximo por secao);
## - num frame >= HITCH_FRAME_MS imprime `perf_hitch` com a quebra daquele frame.
## Ligada por padrao (server e client); `--perf-probe=off` desliga.
## Uso:
##   var start := FramePerfProbe.begin()
##   ...trabalho...
##   FramePerfProbe.end("flock", start)

const REPORT_SECONDS := 5.0
const BUDGET_FRAME_MS := 17.5
const HITCH_FRAME_MS := 33.0
const HITCH_LOG_INTERVAL_MSEC := 1000
## Secao que e fatia de outra (ex.: move_and_slide dentro de zombie_ai) nao
## soma de novo no total medido do hitch.
const NESTED_SECTION_PREFIX := "sub:"

## Sonda do jogo em andamento; os pontos medidos (zumbi, flock) falam com ela.
static var active: FramePerfProbe = null

var enabled := true
var _frame_usec: Dictionary = {}
var _frame_physics_steps := 0
var _window_usec: Dictionary = {}
var _window_max_usec: Dictionary = {}
var _window_frame_ms: Array[float] = []
var _window_seconds := 0.0
var _window_multi_physics_frames := 0
var _window_physics_steps_max := 0
var _last_hitch_msec := -HITCH_LOG_INTERVAL_MSEC


## `--perf-probe=off` desliga; qualquer outro argumento mantem ligada.
## Uso: var probe := FramePerfProbe.from_arguments(OS.get_cmdline_user_args())
static func from_arguments(arguments: PackedStringArray) -> FramePerfProbe:
	var probe := FramePerfProbe.new()
	probe.enabled = not arguments.has("--perf-probe=off")
	return probe


## Marca o inicio de um trecho medido; 0 quando nao ha sonda ativa.
## Uso: var start := FramePerfProbe.begin()
static func begin() -> int:
	if active == null or not active.enabled:
		return 0
	return Time.get_ticks_usec()


## Fecha o trecho aberto por begin() e soma no frame atual.
## Uso: FramePerfProbe.end("zombie_ai", start)
static func end(section: String, start_usec: int) -> void:
	if start_usec == 0 or active == null or not active.enabled:
		return
	active.record_section(section, Time.get_ticks_usec() - start_usec)


## Soma microssegundos gastos numa secao durante o frame corrente.
## Uso: probe.record_section("flock", 1500)
func record_section(section: String, usec: int) -> void:
	_frame_usec[section] = int(_frame_usec.get(section, 0)) + usec


## Conta um tick de fisica; 2+ no mesmo frame = frame anterior estourou.
## Uso: probe.record_physics_step()
func record_physics_step() -> void:
	_frame_physics_steps += 1


## Fecha o frame renderizado e devolve as linhas JSON a imprimir (hitch e/ou
## relatorio). `context` entra nas linhas (role, zumbis, monitores do motor).
## Uso: for line in probe.finish_frame(delta * 1000.0, Time.get_ticks_msec(), ctx): print(JSON.stringify(line))
func finish_frame(frame_ms: float, now_msec: int, context: Dictionary) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	if not enabled:
		return lines
	if frame_ms >= HITCH_FRAME_MS and now_msec - _last_hitch_msec >= HITCH_LOG_INTERVAL_MSEC:
		_last_hitch_msec = now_msec
		lines.append(_build_hitch_line(frame_ms, context))
	_accumulate_frame(frame_ms)
	if _window_seconds >= REPORT_SECONDS:
		lines.append(_build_report(context))
		_reset_window()
	return lines


func _accumulate_frame(frame_ms: float) -> void:
	for section in _frame_usec:
		var usec := int(_frame_usec[section])
		_window_usec[section] = int(_window_usec.get(section, 0)) + usec
		_window_max_usec[section] = maxi(int(_window_max_usec.get(section, 0)), usec)
	_window_frame_ms.append(frame_ms)
	_window_seconds += frame_ms / 1000.0
	if _frame_physics_steps >= 2:
		_window_multi_physics_frames += 1
	_window_physics_steps_max = maxi(_window_physics_steps_max, _frame_physics_steps)
	_frame_usec.clear()
	_frame_physics_steps = 0


func _build_hitch_line(frame_ms: float, context: Dictionary) -> Dictionary:
	var sections := {}
	var measured_ms := 0.0
	for section in _frame_usec:
		var section_ms := float(_frame_usec[section]) / 1000.0
		sections[section] = snappedf(section_ms, 0.01)
		if not String(section).begins_with(NESTED_SECTION_PREFIX):
			measured_ms += section_ms
	var line := {
		"event": "perf_hitch",
		"frame_ms": snappedf(frame_ms, 0.1),
		"physics_steps": _frame_physics_steps,
		"sections_ms": sections,
		# Resto = motor de fisica, render, GC e o que nao tem medicao propria.
		"unaccounted_ms": snappedf(maxf(frame_ms - measured_ms, 0.0), 0.01),
	}
	line.merge(context)
	return line


func _build_report(context: Dictionary) -> Dictionary:
	var frames := _window_frame_ms.size()
	var over_budget := 0
	var over_hitch := 0
	var total_ms := 0.0
	for frame_ms in _window_frame_ms:
		total_ms += frame_ms
		if frame_ms > BUDGET_FRAME_MS:
			over_budget += 1
		if frame_ms >= HITCH_FRAME_MS:
			over_hitch += 1
	var sorted_ms := _window_frame_ms.duplicate()
	sorted_ms.sort()
	var sections := {}
	for section in _window_usec:
		sections[section] = {
			"avg": snappedf(float(_window_usec[section]) / 1000.0 / float(frames), 0.01),
			"max": snappedf(float(_window_max_usec[section]) / 1000.0, 0.01),
		}
	var report := {
		"event": "perf_report",
		"frames": frames,
		"fps": snappedf(float(frames) / maxf(_window_seconds, 0.001), 0.1),
		"frame_ms_avg": snappedf(total_ms / float(maxi(frames, 1)), 0.01),
		"frame_ms_p95": snappedf(float(sorted_ms[mini(int(frames * 0.95), frames - 1)]), 0.01),
		"frame_ms_max": snappedf(float(sorted_ms[frames - 1]), 0.01),
		"frames_over_budget": over_budget,
		"frames_over_33ms": over_hitch,
		"multi_physics_frames": _window_multi_physics_frames,
		"physics_steps_max": _window_physics_steps_max,
		"sections_ms": sections,
	}
	report.merge(context)
	return report


func _reset_window() -> void:
	_window_usec.clear()
	_window_max_usec.clear()
	_window_frame_ms.clear()
	_window_seconds = 0.0
	_window_multi_physics_frames = 0
	_window_physics_steps_max = 0
