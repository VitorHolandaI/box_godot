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

# Municao farta (pedido de jogo): 5 itens de cada classe no mapa e reposicao a
# cada 30 s. A queda por abate e ocasional e pequena (pedido: "nao muita").
const RESTOCK_INTERVAL := 30.0
const MIN_ITEMS_PER_CLASS := 5
const KILL_DROP_CHANCE := 0.08
const KILL_DROP_AMOUNT_FACTOR := 0.5
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
