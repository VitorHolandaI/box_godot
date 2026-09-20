extends StaticBody3D

## Duble de teste de zumbi para o atropelamento do carro: entra no grupo
## "zombies" e conta o dano recebido, sem carregar a IA e a cena do zumbi real.
## Uso: var alvo := RunOverTargetTest.new()

var damage_taken := 0
var last_damage_kind := ""


func _ready() -> void:
	add_to_group("zombies")


func take_damage(amount: int, _direction: Vector3, kind: String = "bullet", _source: Node = null) -> void:
	damage_taken += amount
	last_damage_kind = kind
