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
static func hitscan_damage(origin: Vector3, direction: Vector3, damage: int, shooter: CollisionObject3D, pierce: int = 1) -> void:
	if shooter == null or not shooter.is_inside_tree():
		return
	var space := shooter.get_world_3d().direct_space_state
	var reach := origin + direction * HITSACAN_RANGE
	var exclude: Array[RID] = [shooter.get_rid()]
	# Railgun (pierce > 1): cada alvo atingido entra no exclude e o raio segue
	# ate o proximo; parede ou objeto sem take_damage para o tiro.
	for _hit_index in maxi(pierce, 1):
		var collider := first_hit_collider(space, origin, reach, exclude)
		var target := _damageable_ancestor(collider as Node)
		if target == null:
			return
		target.take_damage(damage, direction, "bullet", shooter)
		if collider is CollisionObject3D:
			exclude.append((collider as CollisionObject3D).get_rid())


## Tiro explosivo (bazuca): voa ate o primeiro impacto (ou o alcance) e fere
## tudo no raio com queda pela distancia; jogadores levam so um quinto do dano.
## Devolve o ponto de impacto para o efeito visual.
## Uso: var ponto := Bullet.explosive_shot(origem, direcao, 150, player, 5.0)
static func explosive_shot(origin: Vector3, direction: Vector3, damage: int, shooter: CollisionObject3D, radius: float) -> Vector3:
	var reach := origin + direction * HITSACAN_RANGE
	if shooter == null or not shooter.is_inside_tree():
		return reach
	var query := PhysicsRayQueryParameters3D.create(origin, reach, BULLET_MASK, [shooter.get_rid()])
	var hit := shooter.get_world_3d().direct_space_state.intersect_ray(query)
	var impact: Vector3 = hit.get("position", reach)
	ZombieVariantAbilities.area_damage(shooter.get_tree(), impact, radius, maxi(damage / 5, 1), damage, damage, shooter)
	return impact


static func _damageable_ancestor(node: Node) -> Node:
	while node != null:
		if node.has_method("take_damage"):
			return node
		node = node.get_parent()
	return null


## Aparencia do tracer visual pela arma: cor e tamanho proprios (bala grossa,
## feixe longo, foguete). Multiplica a escala ja aplicada (pellets menores).
## Materiais em cache por cor: a horda de tracers nao cria material por bala.
## Uso: Bullet.style_tracer(bullet, WeaponStats.Kind.LASER_RIFLE)
static func style_tracer(bullet: Node3D, weapon_kind: int) -> void:
	bullet.scale *= WeaponStats.tracer_scale_for(weapon_kind)
	var tracer_speed := WeaponStats.tracer_speed_for(weapon_kind)
	if tracer_speed > 0.0 and bullet is Bullet:
		(bullet as Bullet).speed = tracer_speed
	var color := WeaponStats.tracer_color_for(weapon_kind)
	if color == WeaponStats.DEFAULT_TRACER_COLOR:
		return
	var mesh := bullet.get_node_or_null("Mesh") as MeshInstance3D
	if mesh != null:
		mesh.material_override = _tracer_material(color)


static var _tracer_materials: Dictionary = {}


static func _tracer_material(color: Color) -> StandardMaterial3D:
	if _tracer_materials.has(color):
		return _tracer_materials[color]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 5.0
	_tracer_materials[color] = material
	return material
