# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name EscortShop
extends RefCounted

## Catalogo e regra de compra da loja da escolta (o mercador de preto em cada
## checkpoint). A UI (EscortShopMenu) so chama price_of/purchase; a regra fica
## aqui para testar sem cena e para o servidor validar a compra.
## Uso: var aviso := EscortShop.purchase(player, WeaponStats.Kind.UZI)

const PRICE_BY_KIND: Dictionary = {
	WeaponStats.Kind.SHOTGUN: 60,
	WeaponStats.Kind.UZI: 90,
	WeaponStats.Kind.SAWED_OFF: 100,
	WeaponStats.Kind.DOUBLE_BARREL: 110,
	WeaponStats.Kind.MAGNUM: 120,
	WeaponStats.Kind.CARBINE: 150,
	WeaponStats.Kind.AUTO_SHOTGUN: 180,
	WeaponStats.Kind.AK47: 200,
	WeaponStats.Kind.M4: 200,
	WeaponStats.Kind.AUG: 210,
	WeaponStats.Kind.SNIPER: 220,
}


## Variantes a venda, em ordem de preco. Uso: for kind in EscortShop.sellable_kinds()
static func sellable_kinds() -> Array[int]:
	var kinds: Array[int] = []
	for kind in PRICE_BY_KIND:
		kinds.append(int(kind))
	kinds.sort()
	return kinds


## Preco da arma; 0 quando fora de estoque. Uso: var preco := EscortShop.price_of(kind)
static func price_of(kind: int) -> int:
	return int(PRICE_BY_KIND.get(kind, 0))


## Compra: valida estoque, saldo e slot, desconta e entrega a arma. Devolve "" no
## sucesso ou a mensagem do porque falhou (a UI mostra a mesma). Reembolsa se a
## entrega falhar depois do debito.
## Uso: var aviso := EscortShop.purchase(player, WeaponStats.Kind.SHOTGUN)
static func purchase(player: Node, kind: int) -> String:
	var price := price_of(kind)
	if price <= 0:
		return "Arma fora de estoque."
	if player == null or not is_instance_valid(player):
		return "Sem jogador para comprar."
	if not player.has_method("has_crate_weapon"):
		return "Este corpo nao aceita arma."
	if player.has_crate_weapon(kind):
		return "Voce ja tem essa arma."
	if not player.has_free_weapon_slot():
		return "Sem espaco para outra arma."
	if not player.spend_money(price):
		return "Dinheiro insuficiente (precisa de $%d)." % price
	var status := String(player.take_crate_weapon(kind))
	if status == "full":
		player.add_money(price)
		return "Nao foi possivel guardar a arma."
	return ""
