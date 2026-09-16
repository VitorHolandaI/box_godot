class_name SurvivalWaveSchedule
extends RefCounted

const TARGETS: Array[int] = [200, 20, 30, 40, 60, 80, 120, 140, 160, 180, 200, 220, 240, 260, 280, 300, 320, 340, 360, 380, 400, 420, 440, 460, 480, 500, 520, 540, 560, 580, 600]
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


## Onda de chefe: o super zumbi (Tita) nasce nas horas 10, 20, 30...
## Uso: if schedule.is_boss_wave(wave_index): spawn_titan()
func is_boss_wave(wave_index: int) -> bool:
	return wave_index >= 0 and (wave_index + 1) % 10 == 0


## Onda cai crate de armas (de paraquedas, via airdrop).
## Uso: if schedule.is_airdrop_wave(wave_index): ...
func is_airdrop_wave(wave_index: int) -> bool:
	return AIRDROP_WAVES.has(wave_index)


## Mix de variantes por fase da partida, em porcentagens somando 100.
## Cada fase adiciona variantes e reequilibra o resto da horda.
const VARIANT_MIXES: Array[Dictionary] = [
	# Hora 1-2: horda basica com especiais leves desde o comeco (pedido de jogo,
	# estilo Left 4 Dead): leaper, cuspidor, bloater, investida e saltador.
	{
		ZombieMutator.Type.WALKER: 50,
		ZombieMutator.Type.JUMPER: 5,
		ZombieMutator.Type.LIMPER: 10,
		ZombieMutator.Type.ONE_ARM: 8,
		ZombieMutator.Type.ONE_LEG: 5,
		ZombieMutator.Type.LEAPER: 6,
		ZombieMutator.Type.SPITTER: 6,
		ZombieMutator.Type.BLOATER: 5,
		ZombieMutator.Type.CHARGER: 5,
	},
	# Hora 3-6: corredores e rastejantes entram; puxador, curandeiro e
	# espreitador (pedido de variedade) tiram vaga do walker comum.
	{
		ZombieMutator.Type.WALKER: 12,
		ZombieMutator.Type.SMOKER: 4,
		ZombieMutator.Type.HEALER: 4,
		ZombieMutator.Type.STALKER: 4,
		ZombieMutator.Type.JUMPER: 4,
		ZombieMutator.Type.LEAPER: 5,
		ZombieMutator.Type.LIMPER: 10,
		ZombieMutator.Type.ONE_ARM: 10,
		ZombieMutator.Type.CRAWLER: 10,
		ZombieMutator.Type.SPRINTER: 10,
		ZombieMutator.Type.HALF_ARM: 10,
		ZombieMutator.Type.SPITTER: 6,
		ZombieMutator.Type.BLOATER: 6,
		ZombieMutator.Type.CHARGER: 5,
	},
	# Hora 7-10: brute tanque, cabecas divididas e mais especiais.
	{
		ZombieMutator.Type.WALKER: 6,
		ZombieMutator.Type.SMOKER: 4,
		ZombieMutator.Type.HEALER: 4,
		ZombieMutator.Type.STALKER: 4,
		ZombieMutator.Type.JUMPER: 4,
		ZombieMutator.Type.BLOATER: 6,
		ZombieMutator.Type.LEAPER: 6,
		ZombieMutator.Type.CRAWLER: 10,
		ZombieMutator.Type.SPRINTER: 12,
		ZombieMutator.Type.LIMPER: 5,
		ZombieMutator.Type.HALF_HEAD: 10,
		ZombieMutator.Type.BRUTE: 8,
		ZombieMutator.Type.HALF_ARM: 9,
		ZombieMutator.Type.SPITTER: 6,
		ZombieMutator.Type.CHARGER: 6,
	},
	# Hora 11+: screamer atrai a horda de longe; armored exige faca ou mais tiros.
	{
		ZombieMutator.Type.WALKER: 5,
		ZombieMutator.Type.SMOKER: 4,
		ZombieMutator.Type.HEALER: 4,
		ZombieMutator.Type.STALKER: 4,
		ZombieMutator.Type.JUMPER: 5,
		ZombieMutator.Type.BLOATER: 6,
		ZombieMutator.Type.LEAPER: 7,
		ZombieMutator.Type.ARMORED: 8,
		ZombieMutator.Type.CRAWLER: 8,
		ZombieMutator.Type.SPRINTER: 9,
		ZombieMutator.Type.HALF_HEAD: 6,
		ZombieMutator.Type.BRUTE: 6,
		ZombieMutator.Type.SCREAMER: 7,
		ZombieMutator.Type.LIMPER: 5,
		ZombieMutator.Type.ONE_ARM: 6,
		ZombieMutator.Type.SPITTER: 5,
		ZombieMutator.Type.CHARGER: 5,
	},
]


## Mix da fase da onda: indice 0 ate Hora 2, 1 ate Hora 5, 2 ate Hora 9,
## 3 nas seguintes. Uso: var mix := schedule.variant_mix_for_wave(wave_index)
func variant_mix_for_wave(wave_index: int) -> Dictionary:
	var stage := 0
	if wave_index >= 2:
		stage = 1
	if wave_index >= 6:
		stage = 2
	if wave_index >= 10:
		stage = 3
	return VARIANT_MIXES[stage]


## Escolhe a variante com rolagem deterministica 0..99 contra o mix da fase.
## Uso: var tipo := schedule.pick_variant(wave_index, rolagem)
func pick_variant(wave_index: int, roll_percent: int) -> int:
	var mix := variant_mix_for_wave(wave_index)
	var cumulative := 0
	var ordered_kinds := mix.keys()
	ordered_kinds.sort()
	for kind in ordered_kinds:
		cumulative += int(mix[kind])
		if int(roll_percent) < cumulative:
			return int(kind)
	return int(ordered_kinds[0])


## Armas dentro do crate da onda: todo crate cai com 3 armas. As primeiras
## horas sao fixas; as seguintes sorteiam 3 distintas por seed.
## Uso: var kinds := schedule.crate_kinds_for_wave(6, world_seed)
func crate_kinds_for_wave(wave_index: int, world_seed: int) -> Array[int]:
	if wave_index == 2:
		return [WeaponStats.Kind.SHOTGUN, WeaponStats.Kind.UZI, WeaponStats.Kind.MAGNUM]
	if wave_index == 6:
		return [WeaponStats.Kind.SHOTGUN, WeaponStats.Kind.UZI, WeaponStats.Kind.DOUBLE_BARREL]
	if wave_index == 10:
		return [WeaponStats.Kind.MAGNUM, WeaponStats.Kind.DOUBLE_BARREL, WeaponStats.Kind.CARBINE]
	if wave_index == 14:
		return [WeaponStats.Kind.CARBINE, WeaponStats.Kind.DOUBLE_BARREL, WeaponStats.Kind.SHOTGUN]
	if wave_index == 18:
		return [WeaponStats.Kind.CARBINE, WeaponStats.Kind.UZI, WeaponStats.Kind.DOUBLE_BARREL]
	if wave_index < 2:
		return []
	var all_kinds: Array[int] = WeaponStats.crate_kinds()
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed * 7919 + wave_index
	var picked: Array[int] = []
	while picked.size() < 3:
		var kind: int = all_kinds[rng.randi() % all_kinds.size()]
		if not picked.has(kind):
			picked.append(kind)
	return picked
