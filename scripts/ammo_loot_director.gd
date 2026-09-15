class_name AmmoLootDirector
extends RefCounted

## Decide quando e qual municao por classe aparece no mapa. Antes so nascia 1
## item de cada classe por troca de hora, expirava em 3 min e no servidor vazio
## nem nascia: uzi e escopeta ficavam sem municao. Agora (1) zumbi abatido pode
## soltar municao da arma de quem matou e (2) a cada RESTOCK_INTERVAL o mapa e
## completado ate MIN_ITEMS_PER_CLASS itens de cada classe.
## Uso:
##   if director.is_restock_due(delta): for kind in AmmoLootDirector.kinds_to_restock(AmmoLootDirector.count_supplies(tree)): spawn(kind)
##   var kind := director.drop_kind_for_kill(killer, randf())

# Municao farta (pedido de jogo): 5 itens de cada classe no mapa, reposicao a
# cada 30 s e queda frequente de quem mata.
const RESTOCK_INTERVAL := 30.0
const MIN_ITEMS_PER_CLASS := 5
const CLASS_DROP_CHANCE := 0.2
const PISTOL_DROP_CHANCE := 0.1
## Tipos repostos pelo mapa: municao de pistola e de cada arma de crate.
const RESTOCKED_KINDS: Array[int] = [
	GroundSupplyPickup.Kind.AMMO,
	GroundSupplyPickup.Kind.AMMO_SHOTGUN,
	GroundSupplyPickup.Kind.AMMO_UZI,
	GroundSupplyPickup.Kind.AMMO_MAGNUM,
	GroundSupplyPickup.Kind.AMMO_DOUBLE_BARREL,
	GroundSupplyPickup.Kind.AMMO_CARBINE,
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


## Tipo de item que o zumbi solta ao morrer, ou -1. A classe segue a arma de
## crate de quem matou; sem arma de crate, chance menor de municao de pistola.
## `roll` e 0..1 (injetado para teste deterministico).
## Uso: var kind := director.drop_kind_for_kill(killer, randf())
func drop_kind_for_kill(killer: Node, roll: float) -> int:
	if killer == null or not is_instance_valid(killer) or not killer.is_in_group("player"):
		return -1
	var slots: Variant = killer.get("weapon_slots")
	if slots is WeaponSlots and not (slots as WeaponSlots).kinds.is_empty():
		if roll >= CLASS_DROP_CHANCE:
			return -1
		return supply_kind_for_weapon(int((slots as WeaponSlots).kinds[0]))
	return GroundSupplyPickup.Kind.AMMO if roll < PISTOL_DROP_CHANCE else -1


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
