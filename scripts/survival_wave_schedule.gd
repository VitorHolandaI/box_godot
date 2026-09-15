class_name SurvivalWaveSchedule
extends RefCounted

const TARGETS: Array[int] = [10, 20, 30, 40, 60, 80, 120, 140, 160, 180, 200, 220, 240, 260, 280, 300, 320, 340, 360, 380, 400, 420, 440, 460, 480, 500, 520, 540, 560, 580, 600]
## Indices de onda que recebem airdrop de armas (Hora = indice + 1).
const AIRDROP_WAVES: Array[int] = [2, 6, 10, 14, 18, 22, 26, 30]


func wave_count() -> int:
	return TARGETS.size()


func target_for(wave_index: int) -> int:
	if wave_index < 0 or wave_index >= TARGETS.size():
		return 0
	return TARGETS[wave_index]


func is_final_wave(wave_index: int) -> bool:
	return wave_index == TARGETS.size() - 1


## Onda cai crate de armas (de paraquedas, via airdrop).
## Uso: if schedule.is_airdrop_wave(wave_index): ...
func is_airdrop_wave(wave_index: int) -> bool:
	return AIRDROP_WAVES.has(wave_index)


## Armas dentro do crate da onda: fixas nas primeiras (Hora 3 escopeta;
## Hora 7 escopeta+Uzi; Hora 11 Uzi+Magnum) e sorteadas de forma
## deterministica por seed nas seguintes.
## Uso: var kinds := schedule.crate_kinds_for_wave(6, world_seed)
func crate_kinds_for_wave(wave_index: int, world_seed: int) -> Array[int]:
	if wave_index == 2:
		return [WeaponStats.Kind.SHOTGUN]
	if wave_index == 6:
		return [WeaponStats.Kind.SHOTGUN, WeaponStats.Kind.UZI]
	if wave_index == 10:
		return [WeaponStats.Kind.UZI, WeaponStats.Kind.MAGNUM]
	if wave_index < 2:
		return []
	var all_kinds: Array[int] = [WeaponStats.Kind.SHOTGUN, WeaponStats.Kind.UZI, WeaponStats.Kind.MAGNUM]
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed * 7919 + wave_index
	var count := 2 + (rng.randi() % 2)
	var picked: Array[int] = []
	while picked.size() < count:
		var kind: int = all_kinds[rng.randi() % all_kinds.size()]
		if not picked.has(kind):
			picked.append(kind)
	return picked
