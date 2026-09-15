class_name WeaponStats
extends RefCounted

## Tabela de stats das armas de crate (escopeta, Uzi, Magnum). A faca e a
## pistola padrao nao tem durabilidade e sao permanentes; as de crate se
## desgastam a cada disparo e quebram em 0 (fallback para a faca).
## Uso:
##   var stats := WeaponStats.stats_for(PlayerCharacter.Weapon.SHOTGUN)
##   if stats.is_empty(): return # arma padrao

enum Kind { KNIFE, PISTOL, SHOTGUN, UZI, MAGNUM }

const STATS_BY_KIND: Dictionary = {
	Kind.SHOTGUN: {
		"label": "Escopeta",
		"damage": 10,
		"pellets": 8,
		"mag_size": 6,
		"max_reserve": 24,
		"grant_reserve": 24,
		"attack_cooldown": 0.85,
		"max_durability": 40,
		"degraded_below": 16,
		"jam_chance": 0.15,
		"spread_deg": 9.0,
		"degraded_spread_deg": 16.0,
		"noise_radius": 75.0,
	},
	Kind.UZI: {
		"label": "Uzi",
		"damage": 8,
		"pellets": 1,
		"mag_size": 30,
		"max_reserve": 120,
		"grant_reserve": 120,
		"attack_cooldown": 0.11,
		"max_durability": 120,
		"degraded_below": 40,
		"jam_chance": 0.06,
		"spread_deg": 3.0,
		"degraded_spread_deg": 6.0,
		"noise_radius": 65.0,
	},
	Kind.MAGNUM: {
		"label": "Magnum",
		"damage": 55,
		"pellets": 1,
		"mag_size": 6,
		"max_reserve": 18,
		"grant_reserve": 18,
		"attack_cooldown": 0.65,
		"max_durability": 30,
		"degraded_below": 12,
		"jam_chance": 0.10,
		"spread_deg": 1.0,
		"degraded_spread_deg": 2.5,
		"noise_radius": 70.0,
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
