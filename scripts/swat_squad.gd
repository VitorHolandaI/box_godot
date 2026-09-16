class_name SwatSquad
extends Node3D

## Esquadrao SWAT chamado pelo jogador: SOLDIER_COUNT soldados seguem quem
## chamou por DURATION_SECONDS e atiram no zumbi vivo mais perto dentro de
## ENGAGE_RANGE. Nao levam dano. Na autoridade o dano sai em nome de quem
## chamou (abates contam para ele); o cliente so recebe as posicoes a 10 Hz.
## Uso:
##   var squad := SwatSquad.new()
##   cena.add_child(squad)
##   squad.setup(id, jogador, true)

const SOLDIER_COUNT := 3
const DURATION_SECONDS := 20.0
const ENGAGE_RANGE := 22.0
const SHOT_INTERVAL := 0.25
const SHOT_DAMAGE := 30
const FOLLOW_RADIUS := 2.5
const MOVE_SPEED := 7.0
const SYNC_INTERVAL := 0.1
const TRACER_KIND := WeaponStats.Kind.M4
const MUZZLE_HEIGHT := 0.55
const BULLET_SCENE := preload("res://scenes/bullet.tscn")

var squad_id := 0
var caller: Node3D = null
var authoritative := true
var elapsed := 0.0
var soldiers: Array[Node3D] = []
var _shot_timers: Array[float] = []
var _network_targets := PackedVector3Array()
var _sync_elapsed := 0.0


func setup(id: int, called_by: Node3D, deals_damage: bool) -> void:
	squad_id = id
	name = "SwatSquad%d" % id
	caller = called_by
	authoritative = deals_damage
	for index in SOLDIER_COUNT:
		var soldier := Node3D.new()
		soldier.name = "Soldier%d" % index
		add_child(soldier)
		if not ServerTickPolicy.is_dedicated_server():
			_build_soldier_model(soldier)
		soldier.global_position = _slot(index) if is_instance_valid(caller) else global_position
		soldier.visible = authoritative
		soldiers.append(soldier)
		# Tiros defasados: os tres nao disparam no mesmo tick.
		_shot_timers.append(SHOT_INTERVAL * float(index) / SOLDIER_COUNT)


func _process(delta: float) -> void:
	advance(delta)


## Avanca o esquadrao: segue, atira e vai embora no fim do tempo.
## Uso: squad.advance(delta)
func advance(delta: float) -> void:
	elapsed += delta
	if elapsed >= DURATION_SECONDS or (authoritative and not is_instance_valid(caller)):
		queue_free()
		return
	if not authoritative:
		_follow_network_targets(delta)
		return
	for index in soldiers.size():
		_move_soldier(index, delta)
		_shot_timers[index] -= delta
		if _shot_timers[index] <= 0.0:
			_shot_timers[index] = SHOT_INTERVAL
			_shoot_nearest(soldiers[index])
	_sync_positions(delta)


func soldier_positions() -> Array:
	var positions: Array = []
	for soldier in soldiers:
		positions.append(soldier.global_position)
	return positions


## Cliente: posicoes vindas do servidor (a 10 Hz); os soldados deslizam ate elas.
## Uso: squad.apply_network_positions(posicoes)
func apply_network_positions(positions: PackedVector3Array) -> void:
	var first_sync := _network_targets.is_empty()
	_network_targets = positions
	for index in mini(positions.size(), soldiers.size()):
		soldiers[index].visible = true
		if first_sync:
			soldiers[index].global_position = positions[index]


func _slot(index: int) -> Vector3:
	var angle := TAU * float(index) / SOLDIER_COUNT + PI * 0.5
	return caller.global_position + Vector3(cos(angle), 0.0, sin(angle)) * FOLLOW_RADIUS


func _move_soldier(index: int, delta: float) -> void:
	var soldier := soldiers[index]
	soldier.global_position = soldier.global_position.move_toward(_slot(index), MOVE_SPEED * delta)


func _shoot_nearest(soldier: Node3D) -> void:
	var target := _nearest_zombie(soldier.global_position)
	if target == null:
		return
	var origin := soldier.global_position + Vector3.UP * MUZZLE_HEIGHT
	var offset := target.global_position - soldier.global_position
	var direction := Vector3(offset.x, 0.0, offset.z).normalized()
	soldier.rotation.y = atan2(-direction.x, -direction.z)
	Bullet.hitscan_damage(origin + direction * 0.3, direction, SHOT_DAMAGE, caller as CollisionObject3D, 1)
	var scene := get_tree().current_scene
	if NetworkSession.is_server() and scene != null and scene.has_method("replicate_bullet_visual"):
		scene.call("replicate_bullet_visual", origin, direction, 1, 0.0, TRACER_KIND)
	elif NetworkSession.is_offline():
		_spawn_tracer(origin, direction)


func _nearest_zombie(from: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance := ENGAGE_RANGE * ENGAGE_RANGE
	for node in get_tree().get_nodes_in_group("zombies"):
		var zombie := node as Node3D
		if zombie == null or bool(zombie.get("is_dead")):
			continue
		var distance := zombie.global_position.distance_squared_to(from)
		if distance < best_distance:
			best_distance = distance
			best = zombie
	return best


func _sync_positions(delta: float) -> void:
	if not NetworkSession.is_server():
		return
	_sync_elapsed += delta
	if _sync_elapsed < SYNC_INTERVAL:
		return
	_sync_elapsed = 0.0
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("replicate_swat_positions"):
		scene.call("replicate_swat_positions", squad_id, PackedVector3Array(soldier_positions()))


func _follow_network_targets(delta: float) -> void:
	for index in mini(_network_targets.size(), soldiers.size()):
		soldiers[index].global_position = soldiers[index].global_position.lerp(_network_targets[index], minf(delta * 12.0, 1.0))


func _spawn_tracer(origin: Vector3, direction: Vector3) -> void:
	var bullet := BULLET_SCENE.instantiate() as Node3D
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = origin + direction * 0.3
	bullet.setup(direction, 0, false)
	Bullet.style_tracer(bullet, TRACER_KIND)
	AudioFeedback.play_gunshot(origin, TRACER_KIND)


func _build_soldier_model(soldier: Node3D) -> void:
	var uniform := StandardMaterial3D.new()
	uniform.albedo_color = Color(0.08, 0.1, 0.18)
	var visor := StandardMaterial3D.new()
	visor.albedo_color = Color(0.2, 0.8, 1.0)
	visor.emission_enabled = true
	visor.emission = Color(0.2, 0.8, 1.0)
	CrateWeaponModelBuilder.add_box(soldier, Vector3(0.6, 0.8, 0.35), Vector3(0.0, 0.5, 0.0), uniform)
	CrateWeaponModelBuilder.add_box(soldier, Vector3(0.4, 0.4, 0.4), Vector3(0.0, 1.12, 0.0), uniform)
	CrateWeaponModelBuilder.add_box(soldier, Vector3(0.34, 0.1, 0.05), Vector3(0.0, 1.14, -0.21), visor)
	CrateWeaponModelBuilder.add_box(soldier, Vector3(0.22, 0.7, 0.24), Vector3(-0.16, -0.25, 0.0), uniform)
	CrateWeaponModelBuilder.add_box(soldier, Vector3(0.22, 0.7, 0.24), Vector3(0.16, -0.25, 0.0), uniform)
	CrateWeaponModelBuilder.add_box(soldier, Vector3(0.1, 0.1, 0.7), Vector3(0.28, 0.55, -0.3), uniform)
