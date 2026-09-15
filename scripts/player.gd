class_name PlayerCharacter
extends CharacterBody3D

signal lives_changed(current_lives: int)
signal player_eliminated()
## Slots totais: faca e pistola fixas; 1 slot para arma de crate (pegar outra
## troca, dropando a da mao no chao). Emitidos onde o jogador e simulado
## (partida local ou servidor).
signal crate_weapon_broken(kind: int)
signal crate_weapon_dropped(kind: int, mag: int, reserve: int, durability: int)

## Ordem segue WeaponStats.Kind: as armas de crate ficam por ultimo.
enum Weapon { KNIFE, PISTOL, SHOTGUN, UZI, MAGNUM }

const BULLET_SCENE := preload("res://scenes/bullet.tscn")
const KNIFE_ATTACK_DURATION := 0.4
const KNIFE_DOOR_REACH := 1.8
const MAX_LIVES := 3
const MAX_RESERVE_AMMO := 144
const VISION_RANGE := 32.0
const VISION_HALF_ANGLE := deg_to_rad(70.0)
const VISION_ARC_SEGMENTS := 32
# Bolha curta em todas as direcoes: o jogador percebe o que chega por tras.
const PROXIMITY_VISION_RADIUS := 4.0
const PROXIMITY_ARC_SEGMENTS := 40
const VISION_ARC_RADIUS := VISION_RANGE
const VISION_ARC_Y := -0.85
const VISION_OVERLAY_ALPHA := 0.18
const SONAR_DURATION := 4.0
const SONAR_INTERVAL := 10.0
const SONAR_REVEAL_RADIUS := 45.0
## Raio de coleta por interacao de armas no chao (crates e dropadas).
const GROUND_INTERACT_RADIUS := 2.8
const UNSTUCK_LOCATOR_SCRIPT: GDScript = preload("res://scripts/player_unstuck_locator.gd")
# Recarga do botao "Destravar personagem": sem ela o botao vira voo/escalada.
const UNSTUCK_COOLDOWN := 5.0

@export var speed := 6.5
@export var sprint_speed := 8.0
@export var acceleration := 40.0
@export var jump_velocity := 5.5
@export var gravity := 22.0
@export var max_health := 100
@export var max_stamina := 100.0
@export var stamina_drain_per_second := 34.0
@export var stamina_recovery_per_second := 24.0
@export var knife_damage := 30
@export var pistol_damage := 35
@export var local_slot := 0
@export var lives := MAX_LIVES

var is_eliminated := false

var owner_peer_id := 1
var input_action_prefix := "player_1_"
var input_device_name := "Teclado"
var simulation_enabled := true
var reads_local_input := true
var is_local_controller := true

@onready var model: Node3D = $Model
@onready var head: Node3D = $Model/Head
@onready var torso_mesh: MeshInstance3D = $Model/Torso
@onready var left_arm: Node3D = $Model/LeftArm
@onready var right_arm: Node3D = $Model/RightArm
@onready var left_leg: Node3D = $Model/LeftLeg
@onready var right_leg: Node3D = $Model/RightLeg
@onready var weapon_holder: Node3D = $Model/Weapons
@onready var knife_model: Node3D = $Model/RightArm/Knife
@onready var pistol_model: Node3D = $Model/Weapons/Pistol
@onready var muzzle_flash: CSGBox3D = $Model/Weapons/Pistol/MuzzleFlash
@onready var collision_shape: CollisionShape3D = $CollisionShape

var health := 100
var stamina := 100.0
var stamina_recovery_delay := 0.0
var is_sprinting := false
var current_weapon := Weapon.KNIFE
var pistol_ammo := 12
var reserve_ammo := 96
var attack_cooldown := 0.0
var muzzle_flash_time := 0.0
var gunshot_noise_time := 0.0
var noise_radius := 0.0
var pistol_stance_time := 0.0
var pistol_recoil_time := 0.0
## Arma de crate em maos mantem a pose de mira com duas maos por um tempo.
var crate_weapon_stance_time := 0.0
var knife_attack_time := 0.0
var hit_reaction_time := 0.0
var hit_direction := Vector3.ZERO
var walk_time := 0.0
var spawn_position := Vector3.ZERO
var vision_overlay: MeshInstance3D
var move_input := Vector2.ZERO
var aim_input := Vector2.ZERO
var jump_pressed := false
var sprint_pressed := false
var attack_pressed := false
var knife_pressed := false
var pistol_pressed := false
var reload_pressed := false
var interact_pressed := false
var shotgun_pressed := false
var uzi_pressed := false
var magnum_pressed := false
var drop_pressed := false
var weapon_slots := WeaponSlots.new()
## Ultima revisao do inventario aplicada pelo snapshot; -1 = nunca aplicado.
var slots_revision := -1
var crate_weapon_rng := RandomNumberGenerator.new()
var crate_weapon_models: Dictionary = {}
var sonar_pulse_time := 0.0
var sonar_interval_timer := SONAR_INTERVAL
var network_target_position := Vector3.ZERO
var unstuck_cooldown := 0.0
## Sobe a cada teleporte do servidor (destravar, respawn); o cliente pula a
## interpolacao, que colidiria com o que prendeu o boneco.
var teleport_sequence := 0
var network_target_rotation := 0.0
var remote_buttons: Dictionary = {}
var remote_input_age := 0.0
var color_index := -1
var zombie_kills := 0


func _ready() -> void:
	health = max_health
	stamina = max_stamina
	safe_margin = 0.08
	max_slides = 6
	spawn_position = global_position
	network_target_position = global_position
	network_target_rotation = rotation.y
	_apply_player_color()
	_build_crate_weapon_models()
	_update_weapon_models()
	_create_vision_overlay()


func _physics_process(delta: float) -> void:
	if is_eliminated:
		velocity = Vector3.ZERO
		return

	attack_cooldown = maxf(attack_cooldown - delta, 0.0)
	unstuck_cooldown = maxf(unstuck_cooldown - delta, 0.0)
	crate_weapon_stance_time = maxf(crate_weapon_stance_time - delta, 0.0)
	muzzle_flash_time = maxf(muzzle_flash_time - delta, 0.0)
	pistol_stance_time = maxf(pistol_stance_time - delta, 0.0)
	pistol_recoil_time = maxf(pistol_recoil_time - delta, 0.0)
	knife_attack_time = maxf(knife_attack_time - delta, 0.0)
	hit_reaction_time = maxf(hit_reaction_time - delta, 0.0)
	sonar_pulse_time = maxf(sonar_pulse_time - delta, 0.0)
	sonar_interval_timer = maxf(sonar_interval_timer - delta, 0.0)
	if sonar_interval_timer <= 0.0:
		trigger_sonar()
	_poll_local_sonar()
	muzzle_flash.visible = muzzle_flash_time > 0.0
	if not simulation_enabled:
		var previous_position := global_position
		var target_pos := global_position.lerp(network_target_position, minf(delta * 16.0, 1.0))
		var motion := target_pos - global_position
		if motion.length_squared() > 0.00001:
			var col := move_and_collide(motion)
			if col != null:
				move_and_collide(col.get_remainder().slide(col.get_normal()))
		rotation.y = lerp_angle(rotation.y, network_target_rotation, minf(delta * 16.0, 1.0))
		PlayerAnimator.animate_pose(self, delta, previous_position.distance_squared_to(global_position) > 0.0001)
		return

	if reads_local_input:
		_poll_input()
	else:
		remote_input_age += delta
		if remote_input_age > 0.3:
			move_input = Vector2.ZERO
			aim_input = Vector2.ZERO
	_handle_interaction_input()
	_handle_weapon_input()

	if not is_on_floor():
		velocity.y -= gravity * delta

	if jump_pressed and is_on_floor():
		velocity.y = jump_velocity

	var direction := Vector3(move_input.x, 0.0, move_input.y).normalized()
	_update_stamina(delta, not direction.is_zero_approx() and sprint_pressed)
	_update_noise(delta, direction)
	if not aim_input.is_zero_approx():
		var target_rotation := atan2(-aim_input.x, -aim_input.y)
		rotation.y = lerp_angle(rotation.y, target_rotation, minf(delta * 14.0, 1.0))
	elif not direction.is_zero_approx():
		var target_rotation := atan2(-direction.x, -direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, minf(delta * 14.0, 1.0))
	var target_velocity := direction * (sprint_speed if is_sprinting else speed)

	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)

	move_and_slide()
	PlayerAnimator.animate_pose(self, delta, direction.length() > 0.0 and is_on_floor())
	_clear_transient_input()


func get_local_input_state() -> Dictionary:
	return {
		"slot": local_slot,
		"move": Input.get_vector(input_action_prefix + "left", input_action_prefix + "right", input_action_prefix + "up", input_action_prefix + "down"),
		"jump": Input.is_action_pressed(input_action_prefix + "jump"),
		"sprint": Input.is_action_pressed(input_action_prefix + "sprint"),
		"attack": Input.is_action_pressed(input_action_prefix + "attack"),
		"knife": Input.is_action_pressed(input_action_prefix + "knife"),
		"pistol": Input.is_action_pressed(input_action_prefix + "pistol"),
		"reload": Input.is_action_pressed(input_action_prefix + "reload"),
		"interact": Input.is_action_pressed(input_action_prefix + "interact"),
		"shotgun": Input.is_action_pressed(input_action_prefix + "shotgun"),
		"uzi": Input.is_action_pressed(input_action_prefix + "uzi"),
		"magnum": Input.is_action_pressed(input_action_prefix + "magnum"),
		"drop": Input.is_action_pressed(input_action_prefix + "drop_weapon"),
		"aim": aim_input,
	}


func apply_network_input(state: Dictionary) -> void:
	var requested_move: Variant = state.get("move", Vector2.ZERO)
	move_input = requested_move.limit_length(1.0) if requested_move is Vector2 else Vector2.ZERO
	var requested_aim: Variant = state.get("aim", Vector2.ZERO)
	aim_input = requested_aim.limit_length(1.0) if requested_aim is Vector2 else Vector2.ZERO
	jump_pressed = _network_button_just_pressed("jump", bool(state.get("jump", false)))
	sprint_pressed = bool(state.get("sprint", false))
	attack_pressed = _network_button_just_pressed("attack", bool(state.get("attack", false)))
	knife_pressed = _network_button_just_pressed("knife", bool(state.get("knife", false)))
	pistol_pressed = _network_button_just_pressed("pistol", bool(state.get("pistol", false)))
	reload_pressed = _network_button_just_pressed("reload", bool(state.get("reload", false)))
	interact_pressed = _network_button_just_pressed("interact", bool(state.get("interact", false)))
	shotgun_pressed = _network_button_just_pressed("shotgun", bool(state.get("shotgun", false)))
	uzi_pressed = _network_button_just_pressed("uzi", bool(state.get("uzi", false)))
	magnum_pressed = _network_button_just_pressed("magnum", bool(state.get("magnum", false)))
	drop_pressed = _network_button_just_pressed("drop", bool(state.get("drop", false)))
	remote_input_age = 0.0


func get_network_state() -> Dictionary:
	return {
		"position": global_position,
		"rotation": rotation.y,
		"health": health,
		"stamina": stamina,
		"sprinting": is_sprinting,
		"weapon": int(current_weapon),
		"pistol_ammo": pistol_ammo,
		"reserve_ammo": reserve_ammo,
		"pistol_stance": pistol_stance_time,
		"pistol_recoil": pistol_recoil_time,
		"knife_attack": knife_attack_time,
		"muzzle_flash": muzzle_flash_time,
		"hit_reaction": hit_reaction_time,
		"hit_dir_x": hit_direction.x,
		"lives": lives,
		"eliminated": is_eliminated,
		"zombie_kills": zombie_kills,
		"teleport_sequence": teleport_sequence,
		"weapon_slots": weapon_slots.serialize(),
	}


func apply_network_state(state: Dictionary) -> void:
	var position_value: Variant = state.get("position")
	if position_value is Vector3:
		network_target_position = position_value
	var received_teleport := int(state.get("teleport_sequence", teleport_sequence))
	if received_teleport != teleport_sequence:
		teleport_sequence = received_teleport
		global_position = network_target_position
		velocity = Vector3.ZERO
	network_target_rotation = float(state.get("rotation", network_target_rotation))
	health = clampi(int(state.get("health", health)), 0, max_health)
	stamina = clampf(float(state.get("stamina", stamina)), 0.0, max_stamina)
	is_sprinting = bool(state.get("sprinting", false))
	pistol_ammo = clampi(int(state.get("pistol_ammo", pistol_ammo)), 0, 12)
	reserve_ammo = maxi(int(state.get("reserve_ammo", reserve_ammo)), 0)
	var next_weapon := clampi(int(state.get("weapon", int(current_weapon))), 0, Weapon.size() - 1) as Weapon
	if next_weapon != current_weapon:
		current_weapon = next_weapon
		_update_weapon_models()
	var net_slots: Variant = state.get("weapon_slots")
	if net_slots is Dictionary and int((net_slots as Dictionary).get("revision", -1)) != slots_revision:
		weapon_slots.from_dict(net_slots)
		slots_revision = int((net_slots as Dictionary).get("revision", slots_revision))
		_update_weapon_models()
	pistol_stance_time = maxf(float(state.get("pistol_stance", 0.0)), pistol_stance_time)
	pistol_recoil_time = maxf(float(state.get("pistol_recoil", 0.0)), pistol_recoil_time)
	knife_attack_time = maxf(float(state.get("knife_attack", 0.0)), knife_attack_time)
	muzzle_flash_time = maxf(float(state.get("muzzle_flash", 0.0)), muzzle_flash_time)
	hit_reaction_time = maxf(float(state.get("hit_reaction", 0.0)), hit_reaction_time)
	hit_direction.x = float(state.get("hit_dir_x", hit_direction.x))
	lives = clampi(int(state.get("lives", lives)), 0, MAX_LIVES)
	zombie_kills = maxi(zombie_kills, int(state.get("zombie_kills", zombie_kills)))
	var next_eliminated := bool(state.get("eliminated", is_eliminated))
	if next_eliminated != is_eliminated:
		is_eliminated = next_eliminated
		visible = not is_eliminated
		collision_layer = 0 if is_eliminated else 1
		collision_mask = 0 if is_eliminated else 1


func _handle_weapon_input() -> void:
	_equip_weapon_from_input()
	if drop_pressed:
		_drop_current_crate_weapon()
	if reload_pressed and current_weapon == Weapon.PISTOL:
		_reload_pistol()
	elif reload_pressed and WeaponStats.is_crate_weapon(current_weapon):
		weapon_slots.reload(current_weapon)
	if attack_pressed and attack_cooldown <= 0.0:
		match current_weapon:
			Weapon.KNIFE:
				_attack_with_knife()
			Weapon.PISTOL:
				_fire_pistol()
			_:
				_fire_crate_weapon()


func _equip_weapon_from_input() -> void:
	for request in [[knife_pressed, Weapon.KNIFE], [pistol_pressed, Weapon.PISTOL], [shotgun_pressed, Weapon.SHOTGUN], [uzi_pressed, Weapon.UZI], [magnum_pressed, Weapon.MAGNUM]]:
		if not bool(request[0]):
			continue
		var requested: int = request[1]
		if requested == Weapon.KNIFE or requested == Weapon.PISTOL or weapon_slots.has_kind(requested):
			current_weapon = requested
			pistol_stance_time = 0.0
			crate_weapon_stance_time = 10.0 if WeaponStats.is_crate_weapon(requested) else 0.0
			_update_weapon_models()


## Dispara a arma de crate em maos: pellets, desgaste, falha quando degradada
## e quebra em 0 (fallback automatico para a faca). Server/offline.
## Uso: chamado pelo _handle_weapon_input com arma de crate equipada.
func _fire_crate_weapon() -> void:
	var state := weapon_slots.state_of(current_weapon)
	if state.is_empty():
		current_weapon = Weapon.KNIFE
		_update_weapon_models()
		return
	if int(state["mag"]) <= 0:
		weapon_slots.reload(current_weapon)
		return
	if weapon_slots.is_degraded(current_weapon) and crate_weapon_rng.randf() < float(WeaponStats.stats_for(current_weapon)["jam_chance"]):
		# Falha de mecanismo: gasta cooldown, nao gasta bala nem durabilidade.
		attack_cooldown = 0.35
		return
	weapon_slots.consume_mag(current_weapon)
	attack_cooldown = float(WeaponStats.stats_for(current_weapon)["attack_cooldown"])
	muzzle_flash_time = 0.08
	gunshot_noise_time = 0.6
	crate_weapon_stance_time = 10.0
	_fire_pellets(current_weapon)
	if weapon_slots.wear(current_weapon) <= 0:
		_break_crate_weapon(current_weapon)


func _fire_pellets(weapon_kind: int) -> void:
	var stats := WeaponStats.stats_for(weapon_kind)
	var pellet_count := int(stats["pellets"])
	var spread_deg := float(stats["degraded_spread_deg"] if weapon_slots.is_degraded(weapon_kind) else stats["spread_deg"])
	var base_direction := Vector3(aim_input.x, 0.0, aim_input.y).normalized()
	if base_direction.is_zero_approx():
		base_direction = -global_transform.basis.z
	var origin := global_position + Vector3.UP * 0.55
	for pellet_index in pellet_count:
		var angle_offset := 0.0
		if pellet_count > 1:
			angle_offset = deg_to_rad(spread_deg) * (float(pellet_index) - float(pellet_count - 1) / 2.0) / (float(pellet_count) / 2.0)
		var pellet_direction := base_direction.rotated(Vector3.UP, angle_offset)
		# Hitscan: 1 ray por pellet, dano na hora; sem node por pellet.
		Bullet.hitscan_damage(origin + pellet_direction * 0.12, pellet_direction, int(stats["damage"]), self)
		if NetworkSession.is_offline():
			_spawn_pellet_visual(origin + pellet_direction * 0.12, pellet_direction)
	ZombieFlockCoordinator.relay_sound(get_tree(), origin, float(stats["noise_radius"]))
	if NetworkSession.is_offline():
		AudioFeedback.play_gunshot(origin)
	if NetworkSession.is_server():
		get_tree().current_scene.replicate_bullet_visual(origin, base_direction, pellet_count)


## Tracer local da escopeta (offline): visual puro, sem dano.
func _spawn_pellet_visual(origin: Vector3, direction: Vector3) -> void:
	var bullet := BULLET_SCENE.instantiate() as Node3D
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = origin
	bullet.setup(direction, 0, false)
	bullet.add_to_group("network_bullet_visuals")


## Arma de crate quebrou: sai do slot, cai o braco para a faca e quebra em
## pedacos no chao. Roda onde o jogador e simulado; clientes recebem o evento.
func _break_crate_weapon(weapon_kind: int) -> void:
	weapon_slots.remove_kind(weapon_kind)
	if current_weapon == weapon_kind:
		current_weapon = Weapon.KNIFE
	_update_weapon_models()
	_spawn_break_debris()
	crate_weapon_broken.emit(weapon_kind)


func _spawn_break_debris() -> void:
	WeaponBreakDebris.spawn(get_tree().current_scene, global_position + Vector3.UP * 1.1)


func _drop_current_crate_weapon() -> void:
	var dropped_kind := current_weapon
	if not WeaponStats.is_crate_weapon(dropped_kind):
		return
	var dropped_state := weapon_slots.remove_kind(dropped_kind)
	if dropped_state.is_empty():
		return
	current_weapon = Weapon.KNIFE
	_update_weapon_models()
	crate_weapon_dropped.emit(dropped_kind, int(dropped_state.get("mag", 0)), int(dropped_state.get("reserve", 0)), int(dropped_state.get("durability", 0)))


## Coleta por interacao: arma de crate em crate airdrop.
## Retorna "granted"/"merged"/"swapped"/"full".
## Uso: crate.interact_with(self)
func take_crate_weapon(weapon_kind: int) -> String:
	var stats := WeaponStats.stats_for(weapon_kind)
	return _accept_weapon_offer(weapon_kind, {"mag": int(stats["mag_size"]), "reserve": int(stats["grant_reserve"]), "durability": int(stats["max_durability"])})


## Coleta por interacao de arma dropada no chao.
## Uso: pickup.interact_with(self)
func take_ground_weapon(weapon_kind: int, weapon_mag: int, weapon_reserve: int, weapon_durability: int) -> String:
	return _accept_weapon_offer(weapon_kind, {"mag": weapon_mag, "reserve": weapon_reserve, "durability": weapon_durability})


func _accept_weapon_offer(weapon_kind: int, incoming_state: Dictionary) -> String:
	if not WeaponStats.is_crate_weapon(weapon_kind):
		return "full"
	if weapon_slots.has_kind(weapon_kind):
		# Arma repetida vira municao: entra so o que o no chao carregava.
		var gained := weapon_slots.add_reserve(weapon_kind, int(incoming_state["reserve"]))
		return "merged" if gained > 0 else "full"
	if weapon_slots.has_free_slot():
		weapon_slots.grant(weapon_kind)
		weapon_slots.state_by_kind[weapon_kind] = {
			"mag": clampi(int(incoming_state["mag"]), 0, int(WeaponStats.stats_for(weapon_kind)["mag_size"])),
			"reserve": clampi(int(incoming_state["reserve"]), 0, int(WeaponStats.stats_for(weapon_kind)["max_reserve"])),
			"durability": clampi(int(incoming_state["durability"]), 0, int(WeaponStats.stats_for(weapon_kind)["max_durability"])),
		}
		# Arma coletada equipa na mao; e ela que dropa ao trocar depois.
		current_weapon = weapon_kind
		_update_weapon_models()
		return "granted"
	# Slot cheio: se a arma na mao e de crate, troca (a antiga cai no chao).
	if WeaponStats.is_crate_weapon(current_weapon):
		_drop_current_crate_weapon()
		if weapon_slots.has_free_slot():
			weapon_slots.grant(weapon_kind)
			weapon_slots.state_by_kind[weapon_kind] = {
				"mag": clampi(int(incoming_state["mag"]), 0, int(WeaponStats.stats_for(weapon_kind)["mag_size"])),
				"reserve": clampi(int(incoming_state["reserve"]), 0, int(WeaponStats.stats_for(weapon_kind)["max_reserve"])),
				"durability": clampi(int(incoming_state["durability"]), 0, int(WeaponStats.stats_for(weapon_kind)["max_durability"])),
			}
			current_weapon = weapon_kind
			_update_weapon_models()
			return "swapped"
	return "full"


func has_free_weapon_slot() -> bool:
	return weapon_slots.has_free_slot()


func _handle_interaction_input() -> void:
	if not interact_pressed:
		return
	# Coleta por interacao tem prioridade: crates airdrop e armas dropadas
	# proximas sao pegue pelo tecla E, sem depender de raycast de porta.
	var ground_weapon := _find_nearest_ground_weapon()
	if ground_weapon != null:
		ground_weapon.call("interact_with", self)
		return
	var ray_start := head.global_position
	var ray_end := ray_start - global_transform.basis.z * 2.5
	var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end, 1, [self])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var collider: Node = hit.get("collider")
	while collider != null:
		if collider.has_method("interact"):
			collider.interact()
			return
		collider = collider.get_parent()


## Arma no chao mais proxima dentro do raio de interacao (crates airdrop e
## armas dropadas compartilham o grupo "ground_weapons").
## Uso: var arma := player._find_nearest_ground_weapon()
func _find_nearest_ground_weapon() -> Node:
	var best: Node = null
	var best_distance := GROUND_INTERACT_RADIUS
	for node in get_tree().get_nodes_in_group("ground_weapons"):
		var pickup := node as Node3D
		if pickup == null or not is_instance_valid(pickup):
			continue
		# Crate vazia (ja aberta) nao deve "engolir" o botao E: as armas
		# dela ficam espalhadas ao redor como pickups proprios.
		if pickup is AirSupplyPickup and (pickup as AirSupplyPickup).weapon_kinds.is_empty():
			continue
		var distance := global_position.distance_to(pickup.global_position)
		if distance < best_distance and pickup.has_method("interact_with"):
			best_distance = distance
			best = pickup
	return best


func _attack_with_knife() -> void:
	attack_cooldown = 0.45
	knife_attack_time = KNIFE_ATTACK_DURATION
	var target := _find_knife_target()
	if target != null and target.has_method("take_damage"):
		target.take_damage(knife_damage, -global_transform.basis.z, "knife", self)
		return
	var door := _find_knife_door()
	if door != null:
		door.take_damage(knife_damage, -global_transform.basis.z, "knife", self)


## Porta inteira logo a frente, ao alcance da faca. Bater repetidamente
## arromba a porta (tambem funciona com ela aberta).
## Uso: var door := _find_knife_door()
func _find_knife_door() -> Node:
	var ray_start := global_position + Vector3.UP * 0.2
	var ray_end := ray_start - global_transform.basis.z * KNIFE_DOOR_REACH
	var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var collider: Node = hit.get("collider")
	while collider != null:
		if collider.is_in_group("destructible_door") and not bool(collider.get("is_destroyed")):
			return collider
		collider = collider.get_parent()
	return null


func _get_combat_targets() -> Array[Node3D]:
	var candidates: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("zombies"):
		var z := node as Node3D
		if z != null and is_instance_valid(z) and not bool(z.get("is_dead")):
			candidates.append(z)
	for player_node in get_tree().get_nodes_in_group("player"):
		if player_node != self and is_instance_valid(player_node):
			candidates.append(player_node as Node3D)
	return candidates


func _find_knife_target() -> Node3D:
	var best_target: Node3D = null
	var best_distance := 1.7
	var forward := -global_transform.basis.z
	# No maximo 4 rays por facada: cercado, os 4 mais proximos bastam.
	var rays_used := 0
	for target in _get_combat_targets():
		if rays_used >= 4:
			break
		var offset := target.global_position - global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance <= best_distance and forward.dot(offset.normalized()) > 0.6:
			var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.6, target.global_position + Vector3.UP * 0.6, 1)
			query.exclude = [get_rid()]
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			rays_used += 1
			if not hit.is_empty():
				continue
			best_distance = distance
			best_target = target
	return best_target


func _fire_pistol() -> Node3D:
	if pistol_ammo <= 0:
		_reload_pistol()
		return null

	pistol_ammo -= 1
	attack_cooldown = 0.25
	muzzle_flash_time = 0.07
	gunshot_noise_time = 0.6
	pistol_stance_time = 8.0
	pistol_recoil_time = 0.12
	# Nasce dentro do colisor para uma arma atravessando a parede nao disparar do lado de fora.
	var origin := global_position + Vector3.UP * 0.55
	var bullet_direction := Vector3(aim_input.x, 0.0, aim_input.y).normalized()
	if bullet_direction.is_zero_approx():
		bullet_direction = -global_transform.basis.z
	var bullet := BULLET_SCENE.instantiate() as Node3D
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = origin + bullet_direction * 0.12
	bullet.setup(bullet_direction, pistol_damage, true, self)
	ZombieFlockCoordinator.relay_sound(get_tree(), origin, 65.0)
	if NetworkSession.is_offline():
		AudioFeedback.play_gunshot(origin)
	if NetworkSession.is_server():
		get_tree().current_scene.replicate_bullet_visual(bullet.global_position, bullet_direction)
	return bullet


func _reload_pistol() -> void:
	var bullets_needed := 12 - pistol_ammo
	var bullets_loaded := mini(bullets_needed, reserve_ammo)
	pistol_ammo += bullets_loaded
	reserve_ammo -= bullets_loaded


func register_zombie_kill() -> void:
	if NetworkSession.is_client():
		return
	zombie_kills += 1


## Adiciona municao a reserva do jogador ate o limite MAX_RESERVE_AMMO.
## Retorna a quantidade de municao efetivamente adicionada.
## Uso:
##   var adicionado := player.add_ammo(24)
func add_ammo(amount: int) -> int:
	if amount <= 0 or reserve_ammo >= MAX_RESERVE_AMMO:
		return 0
	var space := MAX_RESERVE_AMMO - reserve_ammo
	var added := mini(amount, space)
	reserve_ammo += added
	return added


## Informa se o jogador pode coletar mais municao.
## Uso:
##   if player.can_pickup_ammo():
func can_pickup_ammo() -> bool:
	return reserve_ammo < MAX_RESERVE_AMMO


## Recupera vida sem ultrapassar o maximo e retorna o total recebido.
## Uso: var recovered := player.add_health(30)
func add_health(amount: int) -> int:
	if amount <= 0 or health <= 0 or is_eliminated or health >= max_health:
		return 0
	var recovered := mini(amount, max_health - health)
	health += recovered
	return recovered


## Informa se o jogador pode consumir um suprimento de vida.
## Uso: if player.can_pickup_health():
func can_pickup_health() -> bool:
	return health > 0 and health < max_health and not is_eliminated


## Aplica dano ao jogador, acionando flinch de impacto e empurrao fisico.
## Uso:
##   player.take_damage(25, Vector3.FORWARD, "bullet")
func take_damage(amount: int, attack_direction: Vector3 = Vector3.ZERO, _damage_kind: String = "bullet", _source: Node = null) -> void:
	if is_eliminated:
		return
	health = maxi(health - amount, 0)
	hit_reaction_time = 0.35
	hit_direction = attack_direction.normalized()
	velocity += hit_direction * 4.5 + Vector3.UP * 1.2
	if health == 0:
		lives -= 1
		lives_changed.emit(lives)
		if lives <= 0:
			lives = 0
			is_eliminated = true
			player_eliminated.emit()
			velocity = Vector3.ZERO
			visible = false
			collision_layer = 0
			collision_mask = 0
		else:
			respawn()


func respawn() -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO
	teleport_sequence += 1
	is_eliminated = false
	visible = true
	collision_layer = 2
	collision_mask = 23
	health = max_health
	stamina = max_stamina
	hit_reaction_time = 0.0
	pistol_ammo = 12
	reserve_ammo = 96


## Botao "Destravar personagem": leva o boneco ao primeiro espaco livre acima
## (ou ao redor) e deixa a gravidade assentar. Roda onde o jogador e simulado
## (partida local ou servidor). Falso durante a recarga ou sem espaco livre.
## Uso: if not player.unstuck(): mostrar_aviso()
func unstuck() -> bool:
	if is_eliminated or unstuck_cooldown > 0.0:
		return false
	var target: Vector3 = UNSTUCK_LOCATOR_SCRIPT.find_free_position(self)
	if target == UNSTUCK_LOCATOR_SCRIPT.NO_FREE_POSITION:
		return false
	global_position = target
	velocity = Vector3.ZERO
	unstuck_cooldown = UNSTUCK_COOLDOWN
	teleport_sequence += 1
	return true


func set_spawn_position(position: Vector3) -> void:
	spawn_position = position


## Reinicia o contador de vidas ao comecar uma nova onda de sobrevivencia.
## Jogadores eliminados voltam na Safehouse com 3 vidas e vida cheia.
## Uso: player.restore_wave_lives()
func restore_wave_lives() -> void:
	lives = MAX_LIVES
	lives_changed.emit(lives)
	if not is_eliminated:
		return
	respawn()


func configure_vision_overlay(layer: int) -> void:
	if vision_overlay == null or layer < 1 or layer > 20:
		return
	vision_overlay.set_layer_mask_value(1, false)
	vision_overlay.set_layer_mask_value(layer, true)
	vision_overlay.visible = not is_eliminated


## Dispara o pulso sonar que revela os zumbis proximos no minimapa. O pulso e
## passivo (automatico a cada SONAR_INTERVAL) mas tambem pode ser antecipado
## manualmente. Uso: player.trigger_sonar()
func trigger_sonar() -> void:
	if is_eliminated or sonar_pulse_time > 0.0:
		return
	sonar_pulse_time = SONAR_DURATION
	sonar_interval_timer = SONAR_INTERVAL


## Informa se o pulso sonar esta ativo para desenhar os pontos de zumbi.
## Uso: if player.is_sonar_active(): ...
func is_sonar_active() -> bool:
	return sonar_pulse_time > 0.0


func get_sonar_reveal_radius() -> float:
	return SONAR_REVEAL_RADIUS


func get_sonar_text() -> String:
	if is_sonar_active():
		return "Sonar: ativo"
	return "Sonar: %ds" % ceili(sonar_interval_timer)


func can_see_position(target_position: Vector3) -> bool:
	if is_eliminated:
		return false
	var offset := target_position - global_position
	offset.y = 0.0
	var distance := offset.length()
	if distance <= PROXIMITY_VISION_RADIUS:
		return true
	if distance > VISION_RANGE:
		return false
	return -global_transform.basis.z.dot(offset / distance) >= cos(VISION_HALF_ANGLE)


func get_lives_text() -> String:
	if is_eliminated or lives <= 0:
		return "Vidas: [ELIMINADO]"
	return "Vidas: %s (%d/%d)" % ["❤".repeat(lives), lives, MAX_LIVES]


func is_alive() -> bool:
	return not is_eliminated and health > 0


func get_weapon_name() -> String:
	match current_weapon:
		Weapon.KNIFE:
			return "Faca (%d dano)" % knife_damage
		Weapon.PISTOL:
			return "Pistola (%d dano)" % pistol_damage
		_:
			var state := weapon_slots.state_of(current_weapon)
			var stats := WeaponStats.stats_for(current_weapon)
			return "%s (%d dano) | Durab %d/%d" % [stats["label"], stats["damage"], state.get("durability", 0), stats["max_durability"]]


func get_ammo_text() -> String:
	match current_weapon:
		Weapon.KNIFE:
			return "Municao: --"
		Weapon.PISTOL:
			return "Municao: %d/%d" % [pistol_ammo, reserve_ammo]
		_:
			var state := weapon_slots.state_of(current_weapon)
			return "Municao: %d/%d" % [state.get("mag", 0), state.get("reserve", 0)]


## Slots visiveis no HUD: faca e pistola fixas + a arma de crate em maos.
## Uso: split_screen.hud_labels[0].text += player.get_weapon_slots_text()
func get_weapon_slots_text() -> String:
	var crate_label := "-"
	for kind in weapon_slots.kinds:
		crate_label = String(WeaponStats.stats_for(kind)["label"])
	return "Armas: Faca | Pistola | %s" % crate_label


func get_stamina_text() -> String:
	return "Stamina: %d/%d" % [roundi(stamina), roundi(max_stamina)]


func _update_weapon_models() -> void:
	knife_model.visible = current_weapon == Weapon.KNIFE
	pistol_model.visible = current_weapon == Weapon.PISTOL
	for kind in crate_weapon_models:
		var crate_model := crate_weapon_models[kind] as Node3D
		crate_model.visible = current_weapon == kind
		var flash := crate_model.get_node_or_null("Flash") as MeshInstance3D
		if flash != null:
			flash.visible = crate_model.visible and muzzle_flash_time > 0.0

func _build_crate_weapon_models() -> void:
	var kinds := [Weapon.SHOTGUN, Weapon.UZI, Weapon.MAGNUM]
	for kind in kinds:
		var stats := WeaponStats.stats_for(kind)
		var weapon_node := Node3D.new()
		weapon_node.name = "CrateWeapon%d" % kind
		weapon_node.visible = false
		weapon_holder.add_child(weapon_node)
		var body := StandardMaterial3D.new()
		body.albedo_color = _crate_weapon_color(kind)
		body.roughness = 0.45
		body.metallic = 0.5
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color(0.45, 0.3, 0.16)
		wood.roughness = 0.7
		match kind:
			Weapon.SHOTGUN:
				# Escopeta grande: cano longo, bombeamento e coronha de madeira.
				_add_weapon_box(weapon_node, Vector3(0.95, 0.14, 0.14), Vector3(0.08, 0.0, 0.0), body)
				_add_weapon_box(weapon_node, Vector3(0.22, 0.16, 0.16), Vector3(-0.2, -0.05, 0.0), body)
				_add_weapon_box(weapon_node, Vector3(0.3, 0.18, 0.14), Vector3(-0.5, -0.08, 0.0), wood)
				_add_weapon_box(weapon_node, Vector3(0.14, 0.22, 0.12), Vector3(-0.72, -0.14, 0.0), wood)
			Weapon.UZI:
				_add_weapon_box(weapon_node, Vector3(0.55, 0.16, 0.14), Vector3.ZERO, body)
				_add_weapon_box(weapon_node, Vector3(0.12, 0.3, 0.12), Vector3(-0.05, -0.2, 0.0), body)
				_add_weapon_box(weapon_node, Vector3(0.1, 0.34, 0.08), Vector3(0.06, 0.22, 0.0), body)
			_:
				_add_weapon_box(weapon_node, Vector3(0.5, 0.15, 0.13), Vector3.ZERO, body)
				_add_weapon_box(weapon_node, Vector3(0.13, 0.24, 0.1), Vector3(-0.14, -0.16, 0.0), wood)
		var flash := _add_weapon_box(weapon_node, Vector3(0.12, 0.08, 0.08), Vector3(0.34, 0.0, 0.0), _muzzle_material())
		flash.name = "Flash"
		flash.visible = false
		crate_weapon_models[kind] = weapon_node


func _crate_weapon_color(kind: int) -> Color:
	match kind:
		Weapon.SHOTGUN:
			return Color(0.55, 0.36, 0.14)
		Weapon.UZI:
			return Color(0.16, 0.17, 0.2)
		_:
			return Color(0.3, 0.1, 0.12)


func _muzzle_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.72, 0.08)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.35, 0.02)
	material.emission_energy_multiplier = 3.0
	return material


func _add_weapon_box(parent: Node3D, size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	parent.add_child(instance)
	return instance


func _create_vision_overlay() -> void:
	vision_overlay = MeshInstance3D.new()
	vision_overlay.name = "VisionArc"
	vision_overlay.visible = false
	vision_overlay.position.y = VISION_ARC_Y
	vision_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vision_overlay.mesh = _build_vision_arc_mesh()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 1.0, 1.0, VISION_OVERLAY_ALPHA)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	vision_overlay.material_override = material
	add_child(vision_overlay)


func _build_vision_arc_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in VISION_ARC_SEGMENTS:
		var first_angle := lerpf(-VISION_HALF_ANGLE, VISION_HALF_ANGLE, float(segment) / VISION_ARC_SEGMENTS)
		var second_angle := lerpf(-VISION_HALF_ANGLE, VISION_HALF_ANGLE, float(segment + 1) / VISION_ARC_SEGMENTS)
		surface.add_vertex(Vector3.ZERO)
		surface.add_vertex(_vision_arc_point(first_angle, VISION_ARC_RADIUS))
		surface.add_vertex(_vision_arc_point(second_angle, VISION_ARC_RADIUS))
	# Bolha de proximidade so fora do cone, para nao dobrar a opacidade na frente.
	var proximity_start := VISION_HALF_ANGLE
	var proximity_end := TAU - VISION_HALF_ANGLE
	for segment in PROXIMITY_ARC_SEGMENTS:
		var first_angle := lerpf(proximity_start, proximity_end, float(segment) / PROXIMITY_ARC_SEGMENTS)
		var second_angle := lerpf(proximity_start, proximity_end, float(segment + 1) / PROXIMITY_ARC_SEGMENTS)
		surface.add_vertex(Vector3.ZERO)
		surface.add_vertex(_vision_arc_point(first_angle, PROXIMITY_VISION_RADIUS))
		surface.add_vertex(_vision_arc_point(second_angle, PROXIMITY_VISION_RADIUS))
	return surface.commit()


func _vision_arc_point(angle: float, radius: float) -> Vector3:
	return Vector3(sin(angle) * radius, 0.02, -cos(angle) * radius)


func _update_noise(delta: float, direction: Vector3) -> void:
	gunshot_noise_time = maxf(gunshot_noise_time - delta, 0.0)
	if gunshot_noise_time > 0.0:
		noise_radius = 45.0
	elif hit_reaction_time > 0.0:
		noise_radius = 16.0
	elif knife_attack_time > 0.0:
		noise_radius = 6.0
	elif is_sprinting and not direction.is_zero_approx():
		noise_radius = 18.0
	elif not direction.is_zero_approx():
		noise_radius = 7.0
	elif not is_on_floor():
		noise_radius = 9.0
	else:
		noise_radius = 0.0


func _update_stamina(delta: float, wants_to_sprint: bool) -> void:
	stamina_recovery_delay = maxf(stamina_recovery_delay - delta, 0.0)
	is_sprinting = wants_to_sprint and stamina > 0.0
	if is_sprinting:
		stamina = maxf(stamina - stamina_drain_per_second * delta, 0.0)
		stamina_recovery_delay = 0.8
		return
	if stamina_recovery_delay <= 0.0:
		stamina = minf(stamina + stamina_recovery_per_second * delta, max_stamina)


func _poll_input() -> void:
	move_input = Input.get_vector(input_action_prefix + "left", input_action_prefix + "right", input_action_prefix + "up", input_action_prefix + "down")
	jump_pressed = Input.is_action_just_pressed(input_action_prefix + "jump")
	sprint_pressed = Input.is_action_pressed(input_action_prefix + "sprint")
	attack_pressed = Input.is_action_just_pressed(input_action_prefix + "attack")
	knife_pressed = Input.is_action_just_pressed(input_action_prefix + "knife")
	pistol_pressed = Input.is_action_just_pressed(input_action_prefix + "pistol")
	reload_pressed = Input.is_action_just_pressed(input_action_prefix + "reload")
	interact_pressed = Input.is_action_just_pressed(input_action_prefix + "interact")
	shotgun_pressed = Input.is_action_just_pressed(input_action_prefix + "shotgun")
	uzi_pressed = Input.is_action_just_pressed(input_action_prefix + "uzi")
	magnum_pressed = Input.is_action_just_pressed(input_action_prefix + "magnum")
	drop_pressed = Input.is_action_just_pressed(input_action_prefix + "drop_weapon")


## Le o pulso sonar apenas para o avatar controlado localmente. No cliente de
## rede o jogador nao le input de movimento (o servidor e autoritativo), mas o
## sonar e local e continua funcionando.
## Uso: chamado a cada tick de fisica.
func _poll_local_sonar() -> void:
	if not is_local_controller:
		return
	if Input.is_action_just_pressed(input_action_prefix + "sonar"):
		trigger_sonar()


func _network_button_just_pressed(action: String, pressed: bool) -> bool:
	var was_pressed := bool(remote_buttons.get(action, false))
	remote_buttons[action] = pressed
	return pressed and not was_pressed


func _clear_transient_input() -> void:
	jump_pressed = false
	attack_pressed = false
	knife_pressed = false
	pistol_pressed = false
	reload_pressed = false
	interact_pressed = false
	shotgun_pressed = false
	uzi_pressed = false
	magnum_pressed = false
	drop_pressed = false


## Define o indice de cor do uniforme do jogador.
## Uso:
##   player.set_color_index(0)
func set_color_index(index: int) -> void:
	color_index = index
	_apply_player_color()


func _apply_player_color() -> void:
	var colors := [Color(0.2, 0.3, 0.13), Color(0.28, 0.22, 0.11), Color(0.12, 0.25, 0.28), Color(0.3, 0.12, 0.1)]
	var active_index := color_index if color_index >= 0 else local_slot
	var uniform_material := StandardMaterial3D.new()
	uniform_material.albedo_color = colors[posmod(active_index, colors.size())]
	uniform_material.roughness = 0.8
	$Model/Torso.material_override = uniform_material
	$Model/LeftArm/Mesh.material_override = uniform_material
	$Model/RightArm/Mesh.material_override = uniform_material
