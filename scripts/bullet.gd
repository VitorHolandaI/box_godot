class_name Bullet
extends Node3D

@export var speed := 16.0
@export var damage := 35
@export var lifetime := 2.5
## Alcance do hitscan de pellet (vive como o projetil: 2.5s x 16 m/s).
const HITSACAN_RANGE := 48.0
# Mascara 39 = 7 (Mundo/Jogador/Zumbi) | 32 (cadaver) -> tiro tambem
# limpa o corpo no chao, sem dar colisao de jogador no cadaver.
const BULLET_MASK := 39
## Tiro que causa dano testa uma esfera ao longo do trajeto, nao um raio fino.
## Online o cliente ve o zumbi 100-250 ms atrasado (snapshot + interpolacao):
## o tracer acertava na tela e o raio do servidor passava ao lado ("bala nao
## conta"). Paredes seguem bloqueando porque a esfera para nelas.
const HIT_TOLERANCE_RADIUS := 0.3

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
	if causes_damage:
		_advance_damaging(next_position, delta)
		return
	var query := PhysicsRayQueryParameters3D.create(global_position, next_position, BULLET_MASK)
	if shooter != null:
		query.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider: Object = hit.collider
		if collider == shooter:
			global_position = next_position
			lifetime -= delta
			return
		if causes_damage:
			_apply_damage(collider)
		queue_free()
		return

	global_position = next_position
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


## Projetil autoritativo (servidor/partida local): trajeto com tolerancia.
func _advance_damaging(next_position: Vector3, delta: float) -> void:
	var exclude: Array[RID] = []
	if shooter != null:
		exclude.append(shooter.get_rid())
	var collider := first_hit_collider(get_world_3d().direct_space_state, global_position, next_position, exclude)
	if collider != null:
		_apply_damage(collider)
		queue_free()
		return
	global_position = next_position
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


## Primeiro colisor que uma esfera de HIT_TOLERANCE_RADIUS encontra indo de
## `from` a `to`, ou null. Uso: var alvo := Bullet.first_hit_collider(space, a, b, [player.get_rid()])
static func first_hit_collider(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID]) -> Object:
	var sphere := SphereShape3D.new()
	sphere.radius = HIT_TOLERANCE_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, from)
	query.motion = to - from
	query.collision_mask = BULLET_MASK
	query.exclude = exclude
	var fractions := space.cast_motion(query)
	if fractions.size() < 2 or fractions[1] >= 1.0:
		return null
	query.transform = Transform3D(Basis.IDENTITY, from + query.motion * fractions[1])
	query.motion = Vector3.ZERO
	var info := space.get_rest_info(query)
	if info.is_empty():
		return null
	return instance_from_id(int(info["collider_id"]))


func _apply_damage(collider: Object) -> void:
	var target: Node = collider as Node
	while target != null:
		if target.has_method("take_damage"):
			target.take_damage(damage, direction, "bullet", shooter)
			return
		target = target.get_parent()


## Hitscan instantaneo de pellet: um ray por pellet, sem Node3D nem fila de
## raycasts por tick (dano autoritativo na hora). Visual continua sendo
## tracer via RPC. Uso:
##   Bullet.hitscan_damage(origin, direcao, 10, player)
static func hitscan_damage(origin: Vector3, direction: Vector3, damage: int, shooter: CollisionObject3D) -> void:
	if shooter == null or not shooter.is_inside_tree():
		return
	var space := shooter.get_world_3d().direct_space_state
	var reach := origin + direction * HITSACAN_RANGE
	var exclude: Array[RID] = [shooter.get_rid()]
	var target: Node = first_hit_collider(space, origin, reach, exclude) as Node
	while target != null:
		if target.has_method("take_damage"):
			target.take_damage(damage, direction, "bullet", shooter)
			return
		target = target.get_parent()
