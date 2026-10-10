# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name EscortMerchant
extends Node3D

## O vendedor de armas da escolta: figura parada, toda de preto, dentro de cada
## casa de checkpoint. Nao anda, nao luta e nao tem colisao (o jogador atravessa
## se quiser) — o que vale e a loja (EscortShopMenu) abrir quando o jogador chega
## perto. Entra no grupo "escort_merchant" para a UI achar por proximidade.
## Uso: var m := EscortMerchant.new_merchant(root, "EscortMerchant1")

const MEMBER_SCRIPT := preload("res://scripts/escort_family_member.gd")
## Preto quase puro: blusa e calca saem praticamente iguais (todo de preto).
const PITCH_BLACK := Color(0.05, 0.05, 0.06)
## Raio em que o jogador pode abrir a loja a partir do mercador.
const SHOP_RADIUS := 4.5


## Cria o mercador ja na arvore (o chamador so ajusta posicao/rotacao).
## Uso: EscortMerchant.new_merchant(root, "EscortMerchant1")
static func new_merchant(parent: Node, merchant_name: String) -> EscortMerchant:
	var merchant := EscortMerchant.new()
	merchant.name = merchant_name
	var model := MEMBER_SCRIPT._make_civilian_model(PITCH_BLACK, 1.0)
	var weapons := model.get_node_or_null("Weapons")
	if weapons != null:
		weapons.visible = false
	_paint_black_suit(model)
	merchant.add_child(model)
	merchant.add_child(_make_sign())
	parent.add_child(merchant)
	return merchant


## Pinta a roupa de preto em TODAS as malhas do corpo. `_paint_civilian` so
## acerta os nos com nome conhecido e alguns modelos ficavam com o torso claro;
## aqui varre as MeshInstance3D e deixa a cabeca (rosto) de fora.
## Uso: interno de new_merchant.
static func _paint_black_suit(model: Node3D) -> void:
	var black := StandardMaterial3D.new()
	black.albedo_color = PITCH_BLACK
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if _is_head_part(mesh, model):
			continue
		mesh.material_override = black


## Esta malha pertence ao subtree da cabeca (rosto fica com a pele)? Uso interno.
static func _is_head_part(node: Node, model: Node3D) -> bool:
	var current := node.get_parent()
	while current != null and current != model:
		if String(current.name) == "Head":
			return true
		current = current.get_parent()
	return false


## Placa flutuante para o jogador achar o vendedor de longe.
static func _make_sign() -> Label3D:
	var sign := Label3D.new()
	sign.text = "MERCADOR"
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.pixel_size = 0.012
	sign.position = Vector3(0.0, 2.3, 0.0)
	sign.modulate = Color(1.0, 0.9, 0.4)
	return sign


func _ready() -> void:
	add_to_group("escort_merchant")
