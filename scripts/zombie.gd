extends CharacterBody3D

const FlockCoordinatorClass = preload("res://scripts/zombie_flock_coordinator.gd")
const HIT_REACTION_DURATION := 0.24
const ATTACK_ANIMATION_DURATION := 0.5
const VISION_RANGE := 24.0
const VISION_HALF_ANGLE := deg_to_rad(70.0)
const SMELL_RANGE := 10.0
const ALERT_RADIUS := 16.0
const ALERT_FORGET_TIME := 6.0
const SENSE_CHECK_INTERVAL := 0.25
const WANDER_SPEED_FACTOR := 0.4

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
}

enum LodLevel {
	NEAR = 0,
	MID = 1,
	FAR = 2,
}

var health := 100
var zombie_type := ZombieType.WALKER
var lod_level: LodLevel = LodLevel.NEAR
var is_cluster_leader := true
var flock_separation_vector := Vector3.ZERO
var lod_tick_skip_counter := 0
var alert_target: CharacterBody3D = null
var alert_forget_timer := 0.0
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
var death_velocity := Vector3.ZERO
var is_dead := false
var simulation_enabled := true
var network_target_position := Vector3.ZERO
var network_target_rotation := 0.0
var sound_investigate_position := Vector3.ZERO
var sound_investigate_timer := 0.0
var is_investigating_sound := false


func _ready() -> void:
	add_to_group("zombies")
	_configure_variant()
	health = max_health
	safe_margin = 0.08
	max_slides = 6
	network_target_position = global_position
	network_target_rotation = rotation.y
	health_label.text = "%d/%d" % [health, max_health]


func _physics_process(delta: float) -> void:
	if not simulation_enabled:
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
		return
	if is_dead:
		return

	if lod_level == LodLevel.FAR and alert_target == null and not is_investigating_sound:
		lod_tick_skip_counter = (lod_tick_skip_counter + 1) % 3
		if lod_tick_skip_counter != 0:
			global_position.x += velocity.x * delta
			global_position.z += velocity.z * delta
			return

	attack_cooldown = maxf(attack_cooldown - delta, 0.0)
	attack_animation_time = maxf(attack_animation_time - delta, 0.0)
	hit_reaction_time = maxf(hit_reaction_time - delta, 0.0)
	if not is_on_floor():
		velocity.y -= gravity * delta

	_update_senses(delta)
	var target := alert_target
	var is_walking := false
	if hit_reaction_time > 0.0:
		velocity.x = move_toward(velocity.x, hit_direction.x * 3.5, 18.0 * delta)
		velocity.z = move_toward(velocity.z, hit_direction.z * 3.5, 18.0 * delta)
	elif is_instance_valid(target):
		var offset := target.global_position - global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance > 1.25:
			var direction := offset.normalized()
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
			if is_on_wall():
				velocity = velocity.slide(get_wall_normal())
			rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(delta * 8.0, 1.0))
			is_walking = true
		else:
			velocity.x = move_toward(velocity.x, 0.0, speed)
			velocity.z = move_toward(velocity.z, 0.0, speed)
			if attack_cooldown <= 0.0:
				target.take_damage(attack_damage, offset.normalized())
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
				velocity = velocity.slide(get_wall_normal())
			rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(delta * 5.0, 1.0))
			is_walking = true
		else:
			velocity.x = move_toward(velocity.x, 0.0, speed * delta)
			velocity.z = move_toward(velocity.z, 0.0, speed * delta)
			if sound_investigate_timer <= 1.0:
				is_investigating_sound = false
	else:
		is_investigating_sound = false
		_update_wander(delta)
		velocity.x = move_toward(velocity.x, wander_direction.x * speed * WANDER_SPEED_FACTOR, 8.0 * delta)
		velocity.z = move_toward(velocity.z, wander_direction.z * speed * WANDER_SPEED_FACTOR, 8.0 * delta)
		if wander_direction.length_squared() > 0.01:
			rotation.y = lerp_angle(rotation.y, atan2(-wander_direction.x, -wander_direction.z), minf(delta * 4.0, 1.0))
			is_walking = true

	if flock_separation_vector.length_squared() > 0.001:
		velocity.x += flock_separation_vector.x * 1.5
		velocity.z += flock_separation_vector.z * 1.5

	move_and_slide()
	_animate_pose(delta, is_walking and is_on_floor())


func _update_senses(delta: float) -> void:
	if not is_cluster_leader and lod_level != LodLevel.NEAR:
		return
	sense_check_cooldown -= delta
	if sense_check_cooldown > 0.0:
		return
	sense_check_cooldown = SENSE_CHECK_INTERVAL
	var detected := _find_visible_player()
	if detected == null:
		detected = _find_heard_player()
	if detected == null:
		detected = _find_smelled_player()
	if detected != null:
		if alert_target == null:
			_alert_nearby_zombies(detected)
		alert_target = detected
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
func take_damage(amount: int, attack_direction: Vector3, damage_kind: String) -> void:
	if is_dead or not simulation_enabled:
		return

	health = maxi(health - mini(amount, max_health), 0)
	health_label.text = "%d/%d" % [health, max_health]
	hit_direction = attack_direction.normalized()
	hit_kind = damage_kind
	hit_reaction_time = HIT_REACTION_DURATION
	velocity += hit_direction * (4.2 if damage_kind == "bullet" else 3.2) + Vector3.UP * 1.0
	if health == 0:
		_die()
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
	for player_node in get_tree().get_nodes_in_group("player"):
		var player := player_node as CharacterBody3D
		if player == null or player.health <= 0 or bool(player.get("is_eliminated")):
			continue
		var distance := global_position.distance_to(player.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest = player
	return closest


## Notifica o zumbi do som de um tiro se propagando.
## O som atenua com a distancia. Zumbis ecolocalizam a origem do som e
## comecam a caminhar devagar em direcao ao local do estampido.
## Uso:
##   zombie.hear_gunshot(origin, 65.0)
func hear_gunshot(origin: Vector3, max_radius: float = 65.0) -> void:
	if is_dead:
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


func _die() -> void:
	is_dead = true
	death_velocity = velocity
	velocity = Vector3.ZERO
	remove_from_group("zombies")
	health_label.visible = false
	collision_shape.set_deferred("disabled", true)
	model.visible = false
	var scene := get_tree().current_scene
	if scene.has_method("register_corpse"):
		scene.register_corpse(self)
	if not NetworkSession.is_server():
		_spawn_ragdoll()


func _spawn_ragdoll() -> void:
	var scene := get_tree().current_scene
	if scene.has_method("spawn_zombie_ragdoll"):
		scene.spawn_zombie_ragdoll(global_position, rotation.y, death_velocity, int(zombie_type))


func _configure_variant() -> void:
	var hash_val := absi(name.hash())
	zombie_type = (hash_val % 9) as ZombieType
	ZombieMutator.apply_appearance(self, int(zombie_type), hash_val)


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

	ZombieMutator.animate_variant_pose(self, int(zombie_type), delta, is_walking, attack_weight, walk_time)
	ZombieMutator.animate_hit_reaction(
		self,
		delta,
		hit_reaction_time,
		HIT_REACTION_DURATION,
		hit_direction,
		hit_kind,
		int(zombie_type),
		attack_weight
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
	}


func apply_network_state(state: Dictionary) -> void:
	var position_value: Variant = state.get("position")
	if position_value is Vector3:
		network_target_position = position_value
	network_target_rotation = float(state.get("rotation", network_target_rotation))
	health = clampi(int(state.get("health", health)), 0, max_health)
	health_label.text = "%d/%d" % [health, max_health]
	if state.has("zombie_type"):
		var net_type := int(state.get("zombie_type"))
		if net_type != int(zombie_type):
			zombie_type = net_type as ZombieType
			ZombieMutator.apply_appearance(self, int(zombie_type), absi(name.hash()))
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
		health_label.visible = false
		collision_shape.set_deferred("disabled", true)
		model.visible = false
		_spawn_ragdoll()
