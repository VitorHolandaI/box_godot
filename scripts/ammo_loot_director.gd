class_name AmmoLootDirector
extends RefCounted

## Decide quando e qual municao por classe aparece no mapa. Antes so nascia 1
## item de cada classe por troca de hora, expirava em 3 min e no servidor vazio
## nem nascia: uzi e escopeta ficavam sem municao. Agora (1) zumbi abatido de vez
## em quando solta municao de qualquer classe, com meia carga, e (2) a cada
## RESTOCK_INTERVAL o mapa e completado ate MIN_ITEMS_PER_CLASS itens de cada classe.
## Uso:
##   if director.is_restock_due(delta): for kind in AmmoLootDirector.kinds_to_restock(AmmoLootDirector.count_supplies(tree)): spawn(kind)
##   var kind := AmmoLootDirector.drop_kind_for_kill(randf(), randf())

# Municao farta (pedido de jogo): varias caixas de cada classe no mapa e reposicao a
# cada 30 s. A queda por abate e ocasional e pequena (pedido: "nao muita").
const RESTOCK_INTERVAL := 30.0
# 3 por classe: com 17 classes sao 51 caixas; mais que isso a lista do chao
# (replicada inteira a cada mudanca) fica grande demais para a rede.
const MIN_ITEMS_PER_CLASS := 3
const KILL_DROP_CHANCE := 0.08
const KILL_DROP_AMOUNT_FACTOR := 0.5
## Arma solta por zumbi (horda enorme: faz sentido achar armas nela), com pente
## cheio, pouca reserva e ja desgastada. 30% por pedido de jogo; o limite e o
## tempo curto no chao seguram o tamanho da lista replicada.
const WEAPON_DROP_CHANCE := 0.3
const MAX_ZOMBIE_WEAPON_DROPS := 30
const ZOMBIE_WEAPON_LIFETIME := 90.0
const WEAPON_DROP_RESERVE_FACTOR := 0.25
const WEAPON_DROP_MIN_WEAR := 0.4
const WEAPON_DROP_MAX_WEAR := 0.8
## Tipos repostos pelo mapa: municao de pistola e de cada arma de crate.
const RESTOCKED_KINDS: Array[int] = [
	GroundSupplyPickup.Kind.AMMO,
	GroundSupplyPickup.Kind.AMMO_SHOTGUN,
	GroundSupplyPickup.Kind.AMMO_UZI,
	GroundSupplyPickup.Kind.AMMO_MAGNUM,
	GroundSupplyPickup.Kind.AMMO_DOUBLE_BARREL,
	GroundSupplyPickup.Kind.AMMO_CARBINE,
	GroundSupplyPickup.Kind.AMMO_SAWED_OFF,
	GroundSupplyPickup.Kind.AMMO_AUTO_SHOTGUN,
	GroundSupplyPickup.Kind.AMMO_LASER,
	GroundSupplyPickup.Kind.AMMO_PLASMA,
	GroundSupplyPickup.Kind.AMMO_RAIL,
	GroundSupplyPickup.Kind.AMMO_AK47,
	GroundSupplyPickup.Kind.AMMO_M4,
	GroundSupplyPickup.Kind.AMMO_AUG,
	GroundSupplyPickup.Kind.AMMO_BERETTA,
	GroundSupplyPickup.Kind.AMMO_SNIPER,
	GroundSupplyPickup.Kind.AMMO_ROCKET,
]
## Quantidade por item: um pente e pouco da arma (a reserva maxima fica a cargo
## de WeaponSlots.add_reserve).
const AMOUNT_BY_KIND: Dictionary = {
	GroundSupplyPickup.Kind.HEALTH: 35,
	GroundSupplyPickup.Kind.AMMO: 36,
	GroundSupplyPickup.Kind.AMMO_SHOTGUN: 12,
	GroundSupplyPickup.Kind.AMMO_UZI: 90,
	GroundSupplyPickup.Kind.AMMO_MAGNUM: 8,
	GroundSupplyPickup.Kind.AMMO_DOUBLE_BARREL: 6,
	GroundSupplyPickup.Kind.AMMO_CARBINE: 30,
	GroundSupplyPickup.Kind.AMMO_SAWED_OFF: 10,
	GroundSupplyPickup.Kind.AMMO_AUTO_SHOTGUN: 18,
	GroundSupplyPickup.Kind.AMMO_LASER: 18,
	GroundSupplyPickup.Kind.AMMO_PLASMA: 80,
	GroundSupplyPickup.Kind.AMMO_RAIL: 4,
	GroundSupplyPickup.Kind.AMMO_AK47: 60,
	GroundSupplyPickup.Kind.AMMO_M4: 60,
	GroundSupplyPickup.Kind.AMMO_AUG: 60,
	GroundSupplyPickup.Kind.AMMO_BERETTA: 30,
	GroundSupplyPickup.Kind.AMMO_SNIPER: 6,
	GroundSupplyPickup.Kind.AMMO_ROCKET: 2,
}

var _restock_elapsed := INF


## Verdadeiro na primeira chamada e depois a cada RESTOCK_INTERVAL.
## Uso: if director.is_restock_due(delta): restock()
func is_restock_due(delta: float) -> bool:
	_restock_elapsed += maxf(delta, 0.0)
	if _restock_elapsed < RESTOCK_INTERVAL:
		return false
	_restock_elapsed = 0.0
	return true


## Tipo de item que o zumbi solta ao morrer, ou -1: em KILL_DROP_CHANCE das
## mortes, municao de uma classe sorteada (qualquer uma, tenha o jogador a arma
## ou nao). `roll` decide se cai e `pick` qual classe, ambos 0..1 (injetados
## para teste deterministico).
## Uso: var kind := AmmoLootDirector.drop_kind_for_kill(randf(), randf())
static func drop_kind_for_kill(roll: float, pick: float) -> int:
	if roll >= KILL_DROP_CHANCE:
		return -1
	var index := clampi(int(pick * RESTOCKED_KINDS.size()), 0, RESTOCKED_KINDS.size() - 1)
	return RESTOCKED_KINDS[index]


## Toda arma de crate pode sair de zumbi (variedade maxima).
## Uso: var armas := AmmoLootDirector.droppable_weapons()
static func droppable_weapons() -> Array[int]:
	return WeaponStats.crate_kinds()


## Arma que o zumbi solta ao morrer: {"kind", "mag", "reserve", "durability"} ou
## {} quando nao cai. `roll` decide se cai, `pick` a arma e `wear` o desgaste (0..1).
## Uso: var arma := AmmoLootDirector.weapon_drop_for_kill(randf(), randf(), randf())
static func weapon_drop_for_kill(roll: float, pick: float, wear: float) -> Dictionary:
	if roll >= WEAPON_DROP_CHANCE:
		return {}
	var weapons := droppable_weapons()
	var kind := weapons[clampi(int(pick * weapons.size()), 0, weapons.size() - 1)]
	var stats := WeaponStats.stats_for(kind)
	var durability_fraction := lerpf(WEAPON_DROP_MIN_WEAR, WEAPON_DROP_MAX_WEAR, clampf(wear, 0.0, 1.0))
	return {
		"kind": kind,
		"mag": int(stats["mag_size"]),
		"reserve": roundi(float(stats["grant_reserve"]) * WEAPON_DROP_RESERVE_FACTOR),
		"durability": maxi(roundi(float(stats["max_durability"]) * durability_fraction), 1),
	}


## Carga do item solto por zumbi: metade da caixa espalhada pelo mapa.
## Uso: var amount := AmmoLootDirector.drop_amount_for(GroundSupplyPickup.Kind.AMMO_UZI)
static func drop_amount_for(supply_kind: int) -> int:
	return maxi(roundi(float(amount_for(supply_kind)) * KILL_DROP_AMOUNT_FACTOR), 1)


## Itens que faltam para cada classe chegar ao minimo, a partir da contagem atual.
## Uso: var faltando := AmmoLootDirector.kinds_to_restock({GroundSupplyPickup.Kind.AMMO_UZI: 1})
static func kinds_to_restock(counts: Dictionary) -> Array[int]:
	var missing: Array[int] = []
	for supply_kind in RESTOCKED_KINDS:
		for _index in maxi(MIN_ITEMS_PER_CLASS - int(counts.get(supply_kind, 0)), 0):
			missing.append(supply_kind)
	return missing


## Quantos itens de cada tipo estao no chao agora.
## Uso: var counts := AmmoLootDirector.count_supplies(get_tree())
static func count_supplies(tree: SceneTree) -> Dictionary:
	var counts: Dictionary = {}
	for node in tree.get_nodes_in_group("ground_supplies"):
		if node is GroundSupplyPickup and not node.is_queued_for_deletion():
			var supply_kind := int((node as GroundSupplyPickup).supply_kind)
			counts[supply_kind] = int(counts.get(supply_kind, 0)) + 1
	return counts


## Item de municao da classe de uma arma de crate, ou -1.
## Uso: var kind := AmmoLootDirector.supply_kind_for_weapon(WeaponStats.Kind.UZI)
static func supply_kind_for_weapon(weapon_kind: int) -> int:
	for supply_kind in GroundSupplyPickup.KIND_TO_WEAPON:
		if int(GroundSupplyPickup.KIND_TO_WEAPON[supply_kind]) == weapon_kind:
			return int(supply_kind)
	return -1


static func amount_for(supply_kind: int) -> int:
	return int(AMOUNT_BY_KIND.get(supply_kind, 10))
