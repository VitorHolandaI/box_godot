class_name WeaponStats
extends RefCounted

## Tabela de stats das armas de crate (escopetas, automaticas, rifles e armas
## futuristas). Fonte unica: crates, drops, municao de classe, modelo na mao e
## tracer leem daqui. A faca e a
## pistola padrao nao tem durabilidade e sao permanentes; as de crate se
## desgastam a cada disparo e quebram em 0 (fallback para a faca).
## Uso:
##   var stats := WeaponStats.stats_for(PlayerCharacter.Weapon.SHOTGUN)
##   if stats.is_empty(): return # arma padrao

## Durabilidade triplicada (pedido de jogo): armas de crate quebravam rapido demais.
## Mesma ordem de PlayerCharacter.Weapon (o jogador usa os mesmos inteiros).
enum Kind { KNIFE, PISTOL, SHOTGUN, UZI, MAGNUM, DOUBLE_BARREL, CARBINE, SAWED_OFF, AUTO_SHOTGUN, LASER_RIFLE, PLASMA_SMG, RAILGUN, AK47, M4, AUG, BERETTA, SNIPER, BAZOOKA }

const DEFAULT_TRACER_COLOR := Color(1.0, 0.72, 0.08)

const STATS_BY_KIND: Dictionary = {
	Kind.SHOTGUN: {
		"label": "Escopeta",
		"damage": 10,
		"pellets": 8,
		"mag_size": 6,
		"max_reserve": 24,
		"grant_reserve": 24,
		"attack_cooldown": 0.85,
		"max_durability": 120,
		"degraded_below": 48,
		"jam_chance": 0.15,
		"spread_deg": 9.0,
		"degraded_spread_deg": 16.0,
		"noise_radius": 75.0,
		"color": Color(0.55, 0.36, 0.14),
		"model": "shotgun",
	},
	Kind.UZI: {
		"label": "Uzi",
		"damage": 8,
		"pellets": 1,
		"mag_size": 30,
		"max_reserve": 240,
		"grant_reserve": 240,
		"attack_cooldown": 0.11,
		"is_auto": true,
		"max_durability": 360,
		"degraded_below": 120,
		"jam_chance": 0.06,
		"spread_deg": 3.0,
		"degraded_spread_deg": 6.0,
		"noise_radius": 65.0,
		"color": Color(0.16, 0.17, 0.2),
		"model": "smg",
	},
	Kind.MAGNUM: {
		"label": "Magnum",
		"damage": 55,
		"pellets": 1,
		"mag_size": 6,
		"max_reserve": 18,
		"grant_reserve": 18,
		"attack_cooldown": 0.65,
		"max_durability": 90,
		"degraded_below": 36,
		"jam_chance": 0.10,
		"spread_deg": 1.0,
		"degraded_spread_deg": 2.5,
		"noise_radius": 70.0,
		"color": Color(0.3, 0.1, 0.12),
		"model": "revolver",
	},
	Kind.DOUBLE_BARREL: {
		"label": "Escopeta Dupla",
		"damage": 12,
		"pellets": 12,
		"mag_size": 2,
		"max_reserve": 14,
		"grant_reserve": 14,
		"attack_cooldown": 0.7,
		"max_durability": 78,
		"degraded_below": 30,
		"jam_chance": 0.12,
		"spread_deg": 14.0,
		"degraded_spread_deg": 20.0,
		"noise_radius": 80.0,
		"color": Color(0.42, 0.2, 0.1),
		"model": "double_barrel",
	},
	Kind.CARBINE: {
		"label": "Carabina",
		"damage": 48,
		"pellets": 1,
		"mag_size": 10,
		"max_reserve": 60,
		"grant_reserve": 60,
		"attack_cooldown": 0.5,
		"max_durability": 240,
		"degraded_below": 84,
		"jam_chance": 0.08,
		"spread_deg": 0.7,
		"degraded_spread_deg": 2.0,
		"noise_radius": 72.0,
		"color": Color(0.14, 0.22, 0.16),
		"model": "rifle",
	},
	Kind.SAWED_OFF: {
		"label": "Escopeta Serrada",
		"damage": 15,
		"pellets": 10,
		"mag_size": 2,
		"max_reserve": 20,
		"grant_reserve": 20,
		"attack_cooldown": 0.45,
		"max_durability": 90,
		"degraded_below": 30,
		"jam_chance": 0.12,
		"spread_deg": 22.0,
		"degraded_spread_deg": 30.0,
		"noise_radius": 80.0,
		"color": Color(0.35, 0.2, 0.1),
		"model": "short_shotgun",
	},
	Kind.AUTO_SHOTGUN: {
		"label": "Escopeta Automatica",
		"damage": 9,
		"pellets": 6,
		"mag_size": 12,
		"max_reserve": 48,
		"grant_reserve": 36,
		"attack_cooldown": 0.28,
		"is_auto": true,
		"max_durability": 150,
		"degraded_below": 50,
		"jam_chance": 0.1,
		"spread_deg": 11.0,
		"degraded_spread_deg": 18.0,
		"noise_radius": 80.0,
		"color": Color(0.2, 0.22, 0.24),
		"model": "auto_shotgun",
	},
	Kind.LASER_RIFLE: {
		"label": "Rifle Laser",
		"damage": 70,
		"pellets": 1,
		"mag_size": 12,
		"max_reserve": 60,
		"grant_reserve": 48,
		"attack_cooldown": 0.4,
		"max_durability": 200,
		"degraded_below": 60,
		"jam_chance": 0.04,
		"spread_deg": 0.2,
		"degraded_spread_deg": 1.0,
		"noise_radius": 40.0,
		"color": Color(0.85, 0.88, 0.92),
		"tracer_color": Color(0.2, 0.9, 1.0),
		"model": "sci_rifle",
	},
	Kind.PLASMA_SMG: {
		"label": "SMG de Plasma",
		"damage": 16,
		"pellets": 1,
		"mag_size": 40,
		"max_reserve": 240,
		"grant_reserve": 200,
		"attack_cooldown": 0.08,
		"is_auto": true,
		"max_durability": 400,
		"degraded_below": 120,
		"jam_chance": 0.03,
		"spread_deg": 4.0,
		"degraded_spread_deg": 7.0,
		"noise_radius": 45.0,
		"color": Color(0.25, 0.1, 0.35),
		"tracer_color": Color(0.9, 0.25, 1.0),
		"model": "sci_smg",
	},
	## Railgun: tiro atravessa ate `pierce` alvos na mesma linha.
	Kind.RAILGUN: {
		"label": "Railgun",
		"damage": 260,
		"pellets": 1,
		"pierce": 6,
		"mag_size": 3,
		"max_reserve": 15,
		"grant_reserve": 12,
		"attack_cooldown": 1.3,
		"max_durability": 60,
		"degraded_below": 18,
		"jam_chance": 0.05,
		"spread_deg": 0.0,
		"degraded_spread_deg": 0.8,
		"noise_radius": 90.0,
		"color": Color(0.1, 0.12, 0.16),
		"tracer_color": Color(0.3, 1.0, 0.5),
		"model": "railgun",
	},
	Kind.AK47: {
		"label": "AK-47",
		"damage": 30,
		"pellets": 1,
		"mag_size": 30,
		"max_reserve": 180,
		"grant_reserve": 120,
		"attack_cooldown": 0.12,
		"is_auto": true,
		"max_durability": 300,
		"degraded_below": 100,
		"jam_chance": 0.06,
		"spread_deg": 3.5,
		"degraded_spread_deg": 7.0,
		"noise_radius": 75.0,
		"color": Color(0.35, 0.22, 0.12),
		"model": "ak",
	},
	Kind.M4: {
		"label": "M4",
		"damage": 24,
		"pellets": 1,
		"mag_size": 30,
		"max_reserve": 210,
		"grant_reserve": 150,
		"attack_cooldown": 0.09,
		"is_auto": true,
		"max_durability": 330,
		"degraded_below": 110,
		"jam_chance": 0.04,
		"spread_deg": 2.2,
		"degraded_spread_deg": 5.0,
		"noise_radius": 70.0,
		"color": Color(0.12, 0.12, 0.13),
		"model": "assault_rifle",
	},
	Kind.AUG: {
		"label": "AUG",
		"damage": 27,
		"pellets": 1,
		"mag_size": 30,
		"max_reserve": 180,
		"grant_reserve": 120,
		"attack_cooldown": 0.1,
		"is_auto": true,
		"max_durability": 300,
		"degraded_below": 100,
		"jam_chance": 0.04,
		"spread_deg": 1.6,
		"degraded_spread_deg": 4.0,
		"noise_radius": 70.0,
		"color": Color(0.3, 0.36, 0.24),
		"model": "bullpup",
	},
	Kind.BERETTA: {
		"label": "Beretta",
		"damage": 28,
		"pellets": 1,
		"mag_size": 15,
		"max_reserve": 90,
		"grant_reserve": 60,
		"attack_cooldown": 0.2,
		"max_durability": 400,
		"degraded_below": 120,
		"jam_chance": 0.03,
		"spread_deg": 1.5,
		"degraded_spread_deg": 3.0,
		"noise_radius": 55.0,
		"color": Color(0.1, 0.1, 0.11),
		"model": "handgun",
	},
	Kind.SNIPER: {
		"label": "Sniper",
		"damage": 320,
		"pellets": 1,
		"mag_size": 5,
		"max_reserve": 25,
		"grant_reserve": 20,
		"attack_cooldown": 1.5,
		"pierce": 2,
		"max_durability": 90,
		"degraded_below": 30,
		"jam_chance": 0.05,
		"spread_deg": 0.0,
		"degraded_spread_deg": 0.5,
		"noise_radius": 95.0,
		"color": Color(0.2, 0.24, 0.18),
		"model": "sniper",
	},
	## Bazuca: explode no primeiro impacto ferindo tudo em `explosive_radius`.
	Kind.BAZOOKA: {
		"label": "Bazuca",
		"damage": 150,
		"pellets": 1,
		"mag_size": 1,
		"max_reserve": 6,
		"grant_reserve": 4,
		"attack_cooldown": 2.2,
		"explosive_radius": 5.0,
		"tracer_color": Color(1.0, 0.4, 0.1),
		"max_durability": 30,
		"degraded_below": 10,
		"jam_chance": 0.05,
		"spread_deg": 0.0,
		"degraded_spread_deg": 1.0,
		"noise_radius": 110.0,
		"color": Color(0.25, 0.32, 0.18),
		"model": "launcher",
	},
}


## Stats da arma; dicionario vazio para faca/pistola padrao.
## Uso: var stats := WeaponStats.stats_for(kind)
static func stats_for(kind: int) -> Dictionary:
	return STATS_BY_KIND.get(kind, {})


## So armas de crate degradam; faca e pistola padrao sao permanentes.
## Uso: if WeaponStats.is_crate_weapon(kind): ...
static func is_crate_weapon(kind: int) -> bool:
	return STATS_BY_KIND.has(kind)


## Armas de crate em ordem de tipo (fonte unica para crate, drop e modelos).
## Uso: for kind in WeaponStats.crate_kinds(): ...
static func crate_kinds() -> Array[int]:
	var kinds: Array[int] = []
	for kind in STATS_BY_KIND:
		kinds.append(int(kind))
	kinds.sort()
	return kinds


## Cor do corpo da arma (modelo na mao, pickup no chao e crate).
## Uso: var cor := WeaponStats.color_for(WeaponStats.Kind.UZI)
static func color_for(kind: int) -> Color:
	return stats_for(kind).get("color", Color(0.2, 0.2, 0.2))


## Cor do tracer: armas futuristas tem cor propria; o resto usa o amarelo padrao.
## Uso: var cor := WeaponStats.tracer_color_for(WeaponStats.Kind.PLASMA_SMG)
static func tracer_color_for(kind: int) -> Color:
	return stats_for(kind).get("tracer_color", DEFAULT_TRACER_COLOR)
