# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
extends StaticBody3D

## Duble de teste para o atropelamento do carro: entra no grupo pedido
## ("zombies" ou "player") e conta o dano recebido, sem carregar a IA e a cena
## do zumbi nem a do jogador.
## Uso:
##   var alvo := RunOverTargetTest.new()
##   alvo.target_group = "player"   # antes do add_child

var damage_taken := 0
var last_damage_kind := ""
## Grupo em que o duble entra. Trocavel porque o carro atropela zumbi E jogador.
var target_group := "zombies"
## Carro em que este duble esta sentado; quem esta a bordo nao e atropelado.
var riding_car: Node = null


func _ready() -> void:
	add_to_group(target_group)


func take_damage(amount: int, _direction: Vector3, kind: String = "bullet", _source: Node = null) -> void:
	damage_taken += amount
	last_damage_kind = kind
