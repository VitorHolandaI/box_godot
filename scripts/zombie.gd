extends CharacterBody3D

signal died(killer: Node)
## Perseguindo ha STRANDED_SECONDS sem chegar perto e longe do alvo: o servidor
## realoca em vez de deixar o zumbi escondido segurando o fim da onda.
signal stranded(zombie: Node)

const FlockCoordinatorClass = preload("res://scripts/zombie_flock_coordinator.gd")
const INDOOR_ROUTER_SCRIPT: GDScript = preload("res://scripts/zombie_indoor_router.gd")
const HIT_REACTION_DURATION := 0.24
const ATTACK_ANIMATION_DURATION := 0.5
const VISION_RANGE := 24.0
const VISION_HALF_ANGLE := deg_to_rad(70.0)
const SMELL_RANGE := 10.0
const ALERT_RADIUS := 16.0
const ALERT_FORGET_TIME := 6.0
const SENSE_CHECK_INTERVAL := 0.25
const WANDER_SPEED_FACTOR := 0.4
const TARGET_SWITCH_COOLDOWN := 1.0
const TARGET_SWITCH_DISTANCE_MARGIN := 2.0
const MELEE_RANGE := 1.25
const MELEE_VERTICAL_RANGE := 1.4
const DOOR_ATTACK_RANGE := 1.9
const DOOR_ATTACK_HEIGHT := 0.9
const FEET_OFFSET := 1.1
const FLOCK_PUSH_GAIN := 1.5
const FLOCK_PUSH_MAX_SPEED_RATIO := 0.5
const DISSOLVE_OUT_TIME := 1.4
const REASSEMBLE_TIME := 0.5
const DISSOLVE_VISUAL_SCRIPT: GDScript = preload("res://scripts/zombie_dissolve_visual.gd")
const PROGRESS_WATCH_SCRIPT: GDScript = preload("res://scripts/zombie_progress_watch.gd")
const WALL_DETOUR_SCRIPT: GDScript = preload("res://scripts/zombie_wall_detour.gd")
const NAVIGATION_SCRIPT: GDScript = preload("res://scripts/procedural/navigation/building_navigation.gd")
const STUCK_LOG_SECONDS := 15.0
const STRANDED_SECONDS := 40.0
const STRANDED_MIN_TARGET_DISTANCE := 30.0
# Maior que qualquer passo entre snapshots: salto assim e realocacao, nao corrida.
const NETWORK_SNAP_DISTANCE := 8.0

@export var speed := 2.2
@export var gravity := 22.0
@export var max_health := 100
@export var attack_damage := 10

@onready var model: Node3D = $Model
@onready var left_arm: Node3D = $Model/LeftArm
@onready var right_arm: Node3D = $Model/RightArm
@onready var left_leg: Node3D = $Model/LeftLeg
@onready var right_leg: Node3D = $Model/RightLeg
@onready var health_label: Label3D = $HealthLabel
@onready var collision_shape: CollisionShape3D = $CollisionShape

enum ZombieType {
	WALKER = 0,
	ONE_ARM = 1,
	CRAWLER = 2,
	LIMPER = 3,
	SPRINTER = 4,
	HALF_ARM = 5,
	ONE_LEG = 6,
	HALF_LEG = 7,
	HALF_HEAD = 8,
	BRUTE = 9,
	SCREAMER = 10,
}

enum LodLevel {
	NEAR = 0,
	MID = 1,
	FAR = 2,
}

var health := 100
var zombie_type := ZombieType.WALKER
var appearance_hash := 0
var lod_level: LodLevel = LodLevel.NEAR
var is_cluster_leader := true
var horde_id := -1
var flock_separation_vector := Vector3.ZERO
var lod_tick_skip_counter := 0
var alert_target: CharacterBody3D = null
var alert_forget_timer := 0.0
var target_switch_cooldown := 0.0
var sense_check_cooldown := 0.0
var wander_direction := Vector3.ZERO
var wander_time := 0.0
var attack_cooldown := 0.0
var attack_animation_time := 0.0
var attack_sequence := 0
var last_applied_attack_sequence := -1
var hit_reaction_time := 0.0
var hit_direction := Vector3.ZERO
var hit_kind := ""
var walk_time := 0.0
## Variante forçada pela onda (mix percentual); -1 = hash aleatorio original.
var forced_variant := -1
## Grito do screamer: intervalo aleatorio entre gritos.
var scream_cooldown := 0.0
## Cache dos nos de pose (Model/bracos/pernas): 1 lookup de Dictionary no
## lugar de 6 get_node_or_null por tick animado.
var _pose_nodes: Dictionary = {}
var death_velocity := Vector3.ZERO
var is_dead := false
var simulation_enabled := true
var network_target_position := Vector3.ZERO
var network_target_rotation := 0.0
var sound_investigate_position := Vector3.ZERO
var sound_investigate_timer := 0.0
var is_investigating_sound := false
var groan_audio_cooldown := 2.0
var vision_visible := true
var visual_opacity := 1.0
var indoor_router = INDOOR_ROUTER_SCRIPT.new()
var progress_watch = PROGRESS_WATCH_SCRIPT.new()
var wall_detour = WALL_DETOUR_SCRIPT.new()
var _watched_target: Node = null
var _stuck_logged := false
var _dissolve_visual = null


func _ready() -> void:
	add_to_group("zombies")
	_configure_variant()
	health = max_health
	safe_margin = 0.08
	max_slides = 6
	network_target_position = global_position
	network_target_rotation = rotation.y
	health_label.text = "%d/%d" % [health, max_health]
	_collect_fade_meshes()


func _physics_process(delta: float) -> void:
	if not simulation_enabled:
		_update_visual_fade(delta)
		if lod_level != LodLevel.NEAR:
			lod_tick_skip_counter = (lod_tick_skip_counter + 1) % 4
			if lod_tick_skip_counter != 0:
				return
		var previous_position := global_position
		var target_pos := global_position.lerp(network_target_position, minf(delta * 14.0, 1.0))
		var motion := target_pos - global_position
		if motion.length_squared() > 0.00001:
			var col := move_and_collide(motion)
			if col != null:
				move_and_collide(col.get_remainder().slide(col.get_normal()))
		rotation.y = lerp_angle(rotation.y, network_target_rotation, minf(delta * 14.0, 1.0))
		attack_animation_time = maxf(attack_animation_time - delta, 0.0)
		hit_reaction_time = maxf(hit_reaction_time - delta, 0.0)
		if not is_dead:
			_animate_pose(delta, previous_position.distance_squared_to(global_position) > 0.0001)
			_update_groan_audio(delta)
		return
	if is_dead:
		return
	_update_visual_fade(delta)
	var has_active_target := is_instance_valid(alert_target) or is_investigating_sound
	if lod_level != LodLevel.NEAR and not has_active_target:
		lod_tick_skip_counter = (lod_tick_skip_counter + 1) % 4
		if not is_cluster_leader or lod_tick_skip_counter != 0:
			global_position.x += velocity.x * delta
			global_position.z += velocity.z * delta
			return

	attack_cooldown = maxf(attack_cooldown - delta, 0.0)
	target_switch_cooldown = maxf(target_switch_cooldown - delta, 0.0)
	attack_animation_time = maxf(attack_animation_time - delta, 0.0)
	hit_reaction_time = maxf(hit_reaction_time - delta, 0.0)
	if not is_on_floor():
		velocity.y -= gravity * delta

	_update_senses(delta)
	_update_scream(delta)
	var target := alert_target
	var is_walking := false
	var melee_target := _find_nearest_melee_player() if attack_cooldown <= 0.0 else null
	if hit_reaction_time > 0.0:
		velocity.x = move_toward(velocity.x, hit_direction.x * 3.5, 18.0 * delta)
		velocity.z = move_toward(velocity.z, hit_direction.z * 3.5, 18.0 * delta)
	elif melee_target != null:
		_perform_melee_attack(melee_target)
	elif is_instance_valid(target):
		var target_offset := target.global_position - global_position
		var horizontal_offset := target_offset
		horizontal_offset.y = 0.0
		var distance := horizontal_offset.length()
		var same_level := absf(target_offset.y) <= MELEE_VERTICAL_RANGE
		if distance > MELEE_RANGE or not same_level:
			_watch_chase_progress(target, delta)
			var direction := _chase_direction(target, horizontal_offset, delta)
			# Na rua nao ha navmesh: contorna muros e predios pela tangente.
			if not indoor_router.has_route:
				var line_clear: bool = wall_detour.is_active() and _has_line_of_sight(target)
				direction = wall_detour.steer(delta, global_position, direction, progress_watch.blocked_seconds, get_wall_normal() if is_on_wall() else Vector3.ZERO, line_clear)
			if is_on_wall() and _try_attack_blocking_door(direction):
				# Zumbi nao abre porta: fica parado golpeando ate ela quebrar.
				velocity.x = 0.0
				velocity.z = 0.0
			else:
				velocity.x = direction.x * speed
				velocity.z = direction.z * speed
			rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(delta * 8.0, 1.0))
			is_walking = true
		else:
			velocity.x = move_toward(velocity.x, 0.0, speed)
			velocity.z = move_toward(velocity.z, 0.0, speed)
			progress_watch.reset()
			if attack_cooldown <= 0.0:
				_attack_target_or_door(target)
				attack_cooldown = 0.9
				attack_animation_time = ATTACK_ANIMATION_DURATION
				attack_sequence += 1
	elif is_investigating_sound and sound_investigate_timer > 0.0:
		sound_investigate_timer -= delta
		var offset := sound_investigate_position - global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance > 1.8:
			var direction := offset.normalized()
			var slow_speed: float = speed * 0.60
			velocity.x = direction.x * slow_speed
			velocity.z = direction.z * slow_speed
			if is_on_wall():
				var wall_normal := get_wall_normal()
				if wall_normal.length_squared() > 0.0001:
					velocity = velocity.slide(wall_normal)
			rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(delta * 5.0, 1.0))
			is_walking = true
		else:
			velocity.x = move_toward(velocity.x, 0.0, speed * delta)
			velocity.z = move_toward(velocity.z, 0.0, speed * delta)
			if sound_investigate_timer <= 1.0:
				is_investigating_sound = false
	else:
		is_investigating_sound = false
		if is_cluster_leader:
			_update_wander(delta)
		velocity.x = move_toward(velocity.x, wander_direction.x * speed * WANDER_SPEED_FACTOR, 8.0 * delta)
		velocity.z = move_toward(velocity.z, wander_direction.z * speed * WANDER_SPEED_FACTOR, 8.0 * delta)
		if wander_direction.length_squared() > 0.01:
			rotation.y = lerp_angle(rotation.y, atan2(-wander_direction.x, -wander_direction.z), minf(delta * 4.0, 1.0))
			is_walking = true

	var flock_push := _flock_push(Vector3(velocity.x, 0.0, velocity.z))
	velocity.x += flock_push.x
	velocity.z += flock_push.z

	move_and_slide()
	_animate_pose(delta, is_walking and is_on_floor())
	_update_groan_audio(delta)


## Screamer: grita de tempos em tempos e a horda ouve o grito a 30m.
## Reusa a rota de ruido (hear_gunshot) para atrair os lideres de cluster.
## Uso: chamado a cada tick de simulacao (server/offline).
func _update_scream(delta: float) -> void:
	if int(zombie_type) != ZombieType.SCREAMER:
		return
	scream_cooldown = maxf(scream_cooldown - delta, 0.0)
	if scream_cooldown > 0.0:
		return
	scream_cooldown = randf_range(7.0, 11.0)
	ZombieFlockCoordinator.relay_sound(get_tree(), global_position, 28.0)


func _update_senses(delta: float) -> void:
	if not is_cluster_leader:
		return
	sense_check_cooldown -= delta
	if sense_check_cooldown > 0.0:
		return
	sense_check_cooldown = SENSE_CHECK_INTERVAL
	if not _is_living_player(alert_target):
		alert_target = null
	var detected := _find_nearest_detectable_player()
	if detected == alert_target:
		alert_forget_timer = ALERT_FORGET_TIME
	elif detected != null and _should_switch_target(detected):
		if alert_target == null:
			_alert_nearby_zombies(detected)
		alert_target = detected
		target_switch_cooldown = TARGET_SWITCH_COOLDOWN
		alert_forget_timer = ALERT_FORGET_TIME
	elif alert_target != null:
		alert_forget_timer -= SENSE_CHECK_INTERVAL
		if alert_forget_timer <= 0.0:
			alert_target = null


func _find_visible_player() -> CharacterBody3D:
	var forward := -global_transform.basis.z
	for player_node in get_tree().get_nodes_in_group("player"):
		var player := player_node as CharacterBody3D
		if player == null or player.health <= 0 or bool(player.get("is_eliminated")):
			continue
		var offset := player.global_position - global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance > VISION_RANGE:
			continue
		if forward.angle_to(offset.normalized()) > VISION_HALF_ANGLE:
			continue
		if not _has_line_of_sight(player):
			continue
		return player
	return null


## Todo zumbi sabe a posicao do jogador vivo mais proximo, mesmo sem visao:
## a horda persegue continuamente e quebra as portas que bloqueiam o caminho.
## Uso: var alvo := zombie._find_nearest_detectable_player()
func _find_nearest_detectable_player() -> CharacterBody3D:
	return _find_closest_living_player()


func _is_living_player(player: Variant) -> bool:
	if player == null or not is_instance_valid(player) or not player is CharacterBody3D:
		return false
	var player_body := player as CharacterBody3D
	return not player_body.is_queued_for_deletion() and int(player_body.get("health")) > 0 and not bool(player_body.get("is_eliminated"))


func _should_switch_target(candidate: CharacterBody3D) -> bool:
	if candidate == null or candidate == alert_target:
		return false
	if not _is_living_player(alert_target):
		return true
	if target_switch_cooldown > 0.0:
		return false
	return global_position.distance_to(candidate.global_position) + TARGET_SWITCH_DISTANCE_MARGIN <= global_position.distance_to(alert_target.global_position)


func _find_nearest_melee_player() -> CharacterBody3D:
	var nearest: CharacterBody3D = null
	var nearest_distance := MELEE_RANGE
	for player in ZombieFlockCoordinator.get_living_players(get_tree()):
		var player_body := player as CharacterBody3D
		if not _is_living_player(player_body):
			continue
		var distance := global_position.distance_to(player_body.global_position)
		if distance <= nearest_distance and absf(player_body.global_position.y - global_position.y) <= MELEE_VERTICAL_RANGE:
			nearest = player_body
			nearest_distance = distance
	return nearest


func _perform_melee_attack(target: CharacterBody3D) -> void:
	_attack_target_or_door(target)
	attack_cooldown = 0.9
	attack_animation_time = ATTACK_ANIMATION_DURATION
	attack_sequence += 1


func _attack_target_or_door(target: CharacterBody3D) -> void:
	if absf(target.global_position.y - global_position.y) > MELEE_VERTICAL_RANGE:
		return
	var ray_start := global_position + Vector3.UP * 0.8
	var ray_end := target.global_position + Vector3.UP * 0.8
	var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		target.take_damage(attack_damage, (target.global_position - global_position).normalized(), "melee", self)
		return
	var collider: Node = hit.get("collider")
	while collider != null:
		var parent: Node = collider.get_parent()
		if collider == target:
			target.take_damage(attack_damage, (target.global_position - global_position).normalized(), "melee", self)
			return
		if collider.is_in_group("destructible_door") or (parent != null and parent.has_method("take_damage")):
			if collider.has_method("take_damage"):
				collider.take_damage(attack_damage, (target.global_position - global_position).normalized())
			else:
				parent.take_damage(attack_damage, (target.global_position - global_position).normalized())
			return
		collider = collider.get_parent()


## Um zumbi bloqueado por uma porta fechada no caminho ate o jogador ataca a
## porta ate destrui-la. Zumbis nunca abrem portas.
## Uso: if _try_attack_blocking_door(direction): velocity = Vector3.ZERO
func _try_attack_blocking_door(direction: Vector3) -> bool:
	var door := _find_door_ahead(direction)
	if door == null:
		return false
	_attack_door(door)
	return true


## Empurrao de Boids limitado a metade da velocidade propria. Enquanto o zumbi
## segue uma rota interna, a parte que empurra contra o caminho e descartada:
## a separacao da multidao espalhava a horda para os cantos dos comodos e
## anulava a rota de saida (zumbis parados com a porta ao lado).
## Uso: velocity += _flock_push(Vector3(velocity.x, 0.0, velocity.z))
func _flock_push(desired_velocity: Vector3) -> Vector3:
	if flock_separation_vector.length_squared() <= 0.001:
		return Vector3.ZERO
	var push := (flock_separation_vector * FLOCK_PUSH_GAIN).limit_length(speed * FLOCK_PUSH_MAX_SPEED_RATIO)
	push.y = 0.0
	if not indoor_router.has_route or desired_velocity.length_squared() <= 0.0001:
		return push
	var forward := desired_velocity.normalized()
	var backward_amount := push.dot(forward)
	return push - forward * backward_amount if backward_amount < 0.0 else push


## Direcao horizontal de perseguicao. Dentro (ou em direcao a) um edificio
## segue o navmesh: sai do comodo pela porta, usa a escada e contorna moveis.
## Na rua aberta vai em linha reta ate o alvo.
## Uso: var direction := _chase_direction(target, target.global_position - global_position, delta)
func _chase_direction(target: CharacterBody3D, horizontal_offset: Vector3, delta: float) -> Vector3:
	var feet := global_position - Vector3.UP * FEET_OFFSET
	var target_feet := target.global_position - Vector3.UP * FEET_OFFSET
	var waypoint: Vector3 = indoor_router.next_waypoint(get_tree(), feet, target_feet, delta)
	if not indoor_router.has_route:
		return horizontal_offset.normalized()
	var to_waypoint := waypoint - feet
	to_waypoint.y = 0.0
	if to_waypoint.length_squared() < 0.0001:
		return horizontal_offset.normalized()
	return to_waypoint.normalized()


func _watch_chase_progress(target: CharacterBody3D, delta: float) -> void:
	if target != _watched_target:
		_watched_target = target
		_stuck_logged = false
		progress_watch.reset()
		wall_detour.reset()
	progress_watch.update(delta, global_position, target.global_position)
	if progress_watch.no_progress_seconds >= STRANDED_SECONDS and global_position.distance_to(target.global_position) >= STRANDED_MIN_TARGET_DISTANCE:
		progress_watch.reset()
		stranded.emit(self)
		return
	if not FlockCoordinatorClass.debug_stuck_zombies or _stuck_logged or progress_watch.no_progress_seconds < STUCK_LOG_SECONDS:
		return
	_stuck_logged = true
	print(JSON.stringify({
		"event": "zombie_stuck",
		"zombie": String(name),
		"position": [snappedf(global_position.x, 0.1), snappedf(global_position.y, 0.1), snappedf(global_position.z, 0.1)],
		"target": [snappedf(target.global_position.x, 0.1), snappedf(target.global_position.y, 0.1), snappedf(target.global_position.z, 0.1)],
		"blocked_seconds": progress_watch.blocked_seconds,
		"has_route": indoor_router.has_route,
		"in_building": NAVIGATION_SCRIPT.find_for_position(get_tree(), global_position - Vector3.UP * FEET_OFFSET) != null,
		"on_wall": is_on_wall(),
		"on_floor": is_on_floor(),
		"lod": int(lod_level),
		"leader": is_cluster_leader,
	}))


## Move o zumbi encalhado para um novo ponto e zera rota, medidor e desvio.
## Uso: zombie.relocate(spawn_locator.pick_spawn_position(get_tree()))
func relocate(new_position: Vector3) -> void:
	global_position = new_position
	velocity = Vector3.ZERO
	indoor_router.invalidate()
	progress_watch.reset()
	wall_detour.reset()


func _attack_door(door: Node) -> void:
	if attack_cooldown > 0.0:
		return
	door.take_damage(attack_damage, (door.global_position - global_position).normalized(), "melee", self)
	attack_cooldown = 0.9
	attack_animation_time = ATTACK_ANIMATION_DURATION
	attack_sequence += 1


func _find_door_ahead(direction: Vector3) -> Node:
	var from := global_position + Vector3.UP * DOOR_ATTACK_HEIGHT
	var to := from + direction.normalized() * DOOR_ATTACK_RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var collider: Node = hit.get("collider")
	while collider != null:
		if collider.is_in_group("destructible_door") and not bool(collider.get("is_open")):
			return collider
		collider = collider.get_parent()
	return null


func _find_heard_player() -> CharacterBody3D:
	for player_node in get_tree().get_nodes_in_group("player"):
		var player := player_node as CharacterBody3D
		if player == null or player.health <= 0 or bool(player.get("is_eliminated")):
			continue
		var noise_radius := float(player.get("noise_radius"))
		if noise_radius <= 0.0:
			continue
		if global_position.distance_to(player.global_position) <= noise_radius:
			return player
	return null


func _find_smelled_player() -> CharacterBody3D:
	for player_node in get_tree().get_nodes_in_group("player"):
		var player := player_node as CharacterBody3D
		if player == null or player.health <= 0 or bool(player.get("is_eliminated")):
			continue
		if global_position.distance_to(player.global_position) <= SMELL_RANGE:
			return player
	return null


func _has_line_of_sight(player: CharacterBody3D) -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 1.2
	var to := player.global_position + Vector3.UP * 1.0
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = [get_rid()]
	var result := space.intersect_ray(query)
	return result.is_empty()


func _alert_nearby_zombies(target: CharacterBody3D) -> void:
	if FlockCoordinatorClass.instance != null:
		FlockCoordinatorClass.instance.alert_cluster(self, target)
		return
	var radius_squared := ALERT_RADIUS * ALERT_RADIUS
	for zombie in get_tree().get_nodes_in_group("zombies"):
		if zombie == self:
			continue
		if zombie.global_position.distance_squared_to(global_position) > radius_squared:
			continue
		zombie.receive_alert(target)


func receive_alert(target: CharacterBody3D) -> void:
	if is_dead or not simulation_enabled or is_instance_valid(alert_target):
		return
	alert_target = target
	alert_forget_timer = ALERT_FORGET_TIME


func _update_wander(delta: float) -> void:
	wander_time -= delta
	if wander_time > 0.0:
		return
	wander_time = randf_range(2.0, 5.0)
	if randf() < 0.4:
		wander_direction = Vector3.ZERO
		return
	var angle := randf() * TAU
	wander_direction = Vector3(cos(angle), 0.0, sin(angle))


## Applies incoming damage, triggers flinch reaction, and alerts the zombie to attacker.
## Usage:
##   zombie.take_damage(35, Vector3.FORWARD, "bullet")
func take_damage(amount: int, attack_direction: Vector3, damage_kind: String = "bullet", source: Node = null) -> void:
	if is_dead or not simulation_enabled:
		return

	health = maxi(health - mini(amount, max_health), 0)
	health_label.text = "%d/%d" % [health, max_health]
	hit_direction = attack_direction.normalized()
	hit_kind = damage_kind
	hit_reaction_time = HIT_REACTION_DURATION
	velocity += hit_direction * (4.2 if damage_kind == "bullet" else 3.2) + Vector3.UP * 1.0
	if health == 0:
		_die(source)
		return
	if alert_target == null:
		var attacker := _find_closest_living_player()
		if attacker != null:
			alert_target = attacker
			alert_forget_timer = ALERT_FORGET_TIME
			_alert_nearby_zombies(attacker)


func _find_closest_living_player() -> CharacterBody3D:
	var closest: CharacterBody3D = null
	var closest_distance := INF
	# Cache de jogadores vivos do coordenador (0.25s) em vez de reescanear o
	# grupo por zumbi por sentido.
	for player in ZombieFlockCoordinator.get_living_players(get_tree()):
		var player_body := player as CharacterBody3D
		if player_body == null or player_body.health <= 0:
			continue
		var distance := global_position.distance_to(player_body.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest = player_body
	return closest


## Notifica o zumbi do som de um tiro se propagando.
## O som atenua com a distancia. Zumbis ecolocalizam a origem do som e
## comecam a caminhar devagar em direcao ao local do estampido.
## Uso:
##   zombie.hear_gunshot(origin, 65.0)
func hear_gunshot(origin: Vector3, max_radius: float = 65.0) -> void:
	if is_dead or not is_cluster_leader:
		return
	var distance := global_position.distance_to(origin)
	if distance > max_radius:
		return
	if alert_target != null and distance > 12.0:
		return
	var sound_intensity := 1.0 - (distance / max_radius)
	if sound_intensity <= 0.04:
		return
	var dispersion := (1.0 - sound_intensity) * 3.5
	var angle := randf() * TAU
	var offset := Vector3(cos(angle) * dispersion, 0.0, sin(angle) * dispersion)
	sound_investigate_position = origin + offset
	sound_investigate_timer = 6.0 + sound_intensity * 6.0
	is_investigating_sound = true


func _die(killer: Node = null) -> void:
	is_dead = true
	death_velocity = velocity
	velocity = Vector3.ZERO
	remove_from_group("zombies")
	visible = false
	vision_visible = false
	visual_opacity = 0.0
	health_label.visible = false
	collision_shape.set_deferred("disabled", true)
	model.visible = false
	if killer != null and killer.has_method("register_zombie_kill"):
		killer.register_zombie_kill()
	died.emit(killer)
	var scene := get_tree().current_scene
	if scene.has_method("register_corpse"):
		scene.register_corpse(self)
	if not NetworkSession.is_server():
		_spawn_ragdoll()


## Marca se o zumbi deve estar visivel para o FOV do jogador. A transicao
## nao e instantanea: _update_visual_fade interpola a opacidade do proxy.
## Uso: zombie.set_vision_visible(false)
func set_vision_visible(is_visible: bool) -> void:
	vision_visible = is_visible


## Desintegra (ou remonta) o proxy visual ao entrar/sair do FOV, do LOD
## distante ou apos a morte. Ao sair da visao o corpo vira po aos poucos, como
## um estalo do Thanos; ao voltar ele se remonta mais rapido e sem po.
## Uso: chamado a cada tick de fisica.
func _update_visual_fade(delta: float) -> void:
	var should_show := vision_visible and not is_dead and lod_level != LodLevel.FAR
	var target_opacity := 1.0 if should_show else 0.0
	var fade_time := REASSEMBLE_TIME if should_show else DISSOLVE_OUT_TIME
	var was_whole := visual_opacity >= 0.999
	visual_opacity = move_toward(visual_opacity, target_opacity, delta / fade_time)
	if visual_opacity <= 0.02:
		visible = false
		model.visible = false
		health_label.visible = false
		return
	visible = true
	model.visible = true
	health_label.visible = true
	# Po so quando a desintegracao comeca por perda de visao, e nunca no servidor.
	if was_whole and visual_opacity < 0.999 and not vision_visible and not is_dead and not NetworkSession.is_server():
		DISSOLVE_VISUAL_SCRIPT.emit_dust(self, ZombieMutator.appearance_colors(appearance_hash)[1])
	# Dissolve do shader e 100% visual: o servidor nao duplica material por
	# zumbi (36 corpos no solver + material copiado = custo sem retorno).
	if not NetworkSession.is_server():
		_dissolve_visual.set_dissolve(1.0 - visual_opacity)
	health_label.modulate.a = visual_opacity


func _collect_fade_meshes() -> void:
	_dissolve_visual = DISSOLVE_VISUAL_SCRIPT.new(model)


func _spawn_ragdoll() -> void:
	var scene := get_tree().current_scene
	if scene.has_method("spawn_zombie_ragdoll"):
		scene.spawn_zombie_ragdoll(global_position, rotation.y, death_velocity, int(zombie_type), appearance_hash, name)


func _configure_variant() -> void:
	appearance_hash = absi(name.hash())
	if forced_variant >= 0:
		# Onda escolhe a variante (mix percentual); hash vira visual coerente.
		zombie_type = forced_variant as ZombieType
		appearance_hash = appearance_hash + posmod(int(forced_variant) - appearance_hash % 11, 11)
	else:
		zombie_type = (appearance_hash % 11) as ZombieType
	ZombieMutator.apply_appearance(self, int(zombie_type), appearance_hash)


func _update_groan_audio(delta: float) -> void:
	groan_audio_cooldown = maxf(groan_audio_cooldown - delta, 0.0)
	if groan_audio_cooldown > 0.0 or not _has_nearby_player(18.0):
		return
	AudioFeedback.play_zombie_groan(global_position)
	groan_audio_cooldown = randf_range(3.0, 7.0)


func _has_nearby_player(max_distance: float) -> bool:
	# Cache de jogadores vivos do coordenador (0.25s): 36k allocs/s de
	# get_nodes_in_group apenas para decidir se geme viram 1 lookup.
	for player in ZombieFlockCoordinator.get_living_players(get_tree()):
		var player_node := player as Node3D
		if player_node != null and global_position.distance_to(player_node.global_position) <= max_distance:
			return true
	return false


func _animate_pose(delta: float, is_walking: bool) -> void:
	if NetworkSession.is_server() or "--benchmark-zombies" in OS.get_cmdline_user_args() or lod_level == LodLevel.FAR:
		return

	var attack_weight := 0.0
	if attack_animation_time > 0.0:
		var attack_progress := 1.0 - attack_animation_time / ATTACK_ANIMATION_DURATION
		attack_weight = sin(attack_progress * PI)

	if is_walking:
		var mult := 9.0 if zombie_type == ZombieType.SPRINTER else 5.5
		walk_time += delta * mult

	ZombieMutator.animate_variant_pose(self, int(zombie_type), delta, is_walking, attack_weight, walk_time, _pose_nodes)
	ZombieMutator.animate_hit_reaction(
		self,
		delta,
		hit_reaction_time,
		HIT_REACTION_DURATION,
		hit_direction,
		hit_kind,
		int(zombie_type),
		attack_weight,
		_pose_nodes
	)


func get_network_state() -> Dictionary:
	return {
		"position": global_position,
		"rotation": rotation.y,
		"health": health,
		"is_dead": is_dead,
		"death_velocity": death_velocity,
		"attack_animation_time": attack_animation_time,
		"attack_sequence": attack_sequence,
		"zombie_type": int(zombie_type),
		"appearance_hash": appearance_hash,
	}


func apply_network_state(state: Dictionary) -> void:
	var position_value: Variant = state.get("position")
	if position_value is Vector3:
		network_target_position = position_value
		# Realocado pelo servidor: teleporta, senao o proxy deslizaria pelo mapa
		# batendo em paredes no caminho.
		if global_position.distance_to(network_target_position) > NETWORK_SNAP_DISTANCE:
			global_position = network_target_position
	network_target_rotation = float(state.get("rotation", network_target_rotation))
	health = clampi(int(state.get("health", health)), 0, max_health)
	health_label.text = "%d/%d" % [health, max_health]
	if state.has("zombie_type"):
		var net_type := int(state.get("zombie_type"))
		appearance_hash = int(state.get("appearance_hash", appearance_hash))
		if net_type != int(zombie_type):
			zombie_type = net_type as ZombieType
			ZombieMutator.apply_appearance(self, int(zombie_type), appearance_hash)
			_collect_fade_meshes()
	var received_attack_sequence := int(state.get("attack_sequence", last_applied_attack_sequence))
	if last_applied_attack_sequence < 0:
		last_applied_attack_sequence = received_attack_sequence
		attack_animation_time = maxf(float(state.get("attack_animation_time", 0.0)), attack_animation_time)
	elif received_attack_sequence > last_applied_attack_sequence:
		last_applied_attack_sequence = received_attack_sequence
		attack_animation_time = ATTACK_ANIMATION_DURATION
	else:
		attack_animation_time = maxf(float(state.get("attack_animation_time", 0.0)), attack_animation_time)
	var died := bool(state.get("is_dead", false))
	if died and not is_dead:
		is_dead = true
		var death_velocity_value: Variant = state.get("death_velocity", Vector3.ZERO)
		death_velocity = death_velocity_value if death_velocity_value is Vector3 else Vector3.ZERO
		velocity = Vector3.ZERO
		remove_from_group("zombies")
		visible = false
		vision_visible = false
		visual_opacity = 0.0
		health_label.visible = false
		collision_shape.set_deferred("disabled", true)
		model.visible = false
		_spawn_ragdoll()
