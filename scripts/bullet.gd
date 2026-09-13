extends Node3D

@export var speed := 16.0
@export var damage := 35
@export var lifetime := 2.5

var direction := Vector3.FORWARD
var causes_damage := true
var shooter: CollisionObject3D = null


## Configura a direcao, o dano e o atirador do projetil para suporte a fogo amigo.
## Uso:
##   bullet.setup(Vector3.FORWARD, 35, true, player)
func setup(new_direction: Vector3, new_damage: int, new_causes_damage: bool = true, new_shooter: CollisionObject3D = null) -> void:
	direction = new_direction.normalized()
	damage = new_damage
	causes_damage = new_causes_damage
	shooter = new_shooter
	look_at(global_position + direction, Vector3.UP)


func _physics_process(delta: float) -> void:
	var next_position := global_position + direction * speed * delta
	# Mascara 7 = 1 (Mundo) | 2 (Jogador) | 4 (Zumbi) -> permite fogo amigo
	var query := PhysicsRayQueryParameters3D.create(global_position, next_position, 7)
	if shooter != null:
		query.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider: Object = hit.collider
		if collider == shooter:
			global_position = next_position
			lifetime -= delta
			return
		if causes_damage and collider.has_method("take_damage"):
			collider.take_damage(damage, direction, "bullet")
		queue_free()
		return

	global_position = next_position
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
