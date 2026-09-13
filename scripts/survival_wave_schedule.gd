class_name SurvivalWaveSchedule
extends RefCounted

const TARGETS: Array[int] = [10, 20, 30, 40, 60, 80, 120, 140, 160, 180, 200, 220, 240, 260, 280, 300, 320, 340, 360, 380, 400, 420, 440, 460, 480, 500, 520, 540, 560, 580, 600]


func wave_count() -> int:
	return TARGETS.size()


func target_for(wave_index: int) -> int:
	if wave_index < 0 or wave_index >= TARGETS.size():
		return 0
	return TARGETS[wave_index]


func is_final_wave(wave_index: int) -> bool:
	return wave_index == TARGETS.size() - 1
