class_name PlayerCharacter
extends CharacterBody3D

signal lives_changed(current_lives: int)
signal player_eliminated()

enum Weapon { KNIFE, PISTOL }

const BULLET_SCENE := preload("res://scenes/bullet.tscn")
const KNIFE_ATTACK_DURATION := 0.4
const MAX_LIVES := 3
const MAX_RESERVE_AMMO := 96
const VISION_RANGE := 32.0
const VISION_HALF_ANGLE := deg_to_rad(70.0)
const VISION_ARC_SEGMENTS := 32
const VISION_ARC_RADIUS := VISION_RANGE
const VISION_ARC_Y := -0.85
const VISION_OVERLAY_ALPHA := 0.18
const SONAR_DURATION := 4.0
const SONAR_COOLDOWN := 6.0

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
var reserve_ammo := 48
var attack_cooldown := 0.0
var muzzle_flash_time := 0.0
var gunshot_noise_time := 0.0
var noise_radius := 0.0
var pistol_stance_time := 0.0
var pistol_recoil_time := 0.0
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
var sonar_pressed := false
var sonar_pulse_time := 0.0
var sonar_cooldown := 0.0
var network_target_position := Vector3.ZERO
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
	_update_weapon_models()
	_create_vision_overlay()


func _physics_process(delta: float) -> void:
	if is_eliminated:
		velocity = Vector3.ZERO
		return

	attack_cooldown = maxf(attack_cooldown - delta, 0.0)
	muzzle_flash_time = maxf(muzzle_flash_time - delta, 0.0)
	pistol_stance_time = maxf(pistol_stance_time - delta, 0.0)
	pistol_recoil_time = maxf(pistol_recoil_time - delta, 0.0)
	knife_attack_time = maxf(knife_attack_time - delta, 0.0)
	hit_reaction_time = maxf(hit_reaction_time - delta, 0.0)
	sonar_pulse_time = maxf(sonar_pulse_time - delta, 0.0)
	sonar_cooldown = maxf(sonar_cooldown - delta, 0.0)
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
	if sonar_pressed:
		trigger_sonar()
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
	}


func apply_network_state(state: Dictionary) -> void:
	var position_value: Variant = state.get("position")
	if position_value is Vector3:
		network_target_position = position_value
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
	if knife_pressed:
		current_weapon = Weapon.KNIFE
		knife_attack_time = 0.0
		_update_weapon_models()
	elif pistol_pressed:
		current_weapon = Weapon.PISTOL
		pistol_stance_time = 0.0
		_update_weapon_models()

	if reload_pressed and current_weapon == Weapon.PISTOL:
		_reload_pistol()
	if attack_pressed and attack_cooldown <= 0.0:
		if current_weapon == Weapon.KNIFE:
			_attack_with_knife()
		else:
			_fire_pistol()


func _handle_interaction_input() -> void:
	if not interact_pressed:
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


func _attack_with_knife() -> void:
	attack_cooldown = 0.45
	knife_attack_time = KNIFE_ATTACK_DURATION
	var target := _find_knife_target()
	if target != null and target.has_method("take_damage"):
		target.take_damage(knife_damage, -global_transform.basis.z, "knife", self)


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
	for target in _get_combat_targets():
		var offset := target.global_position - global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance <= best_distance and forward.dot(offset.normalized()) > 0.6:
			var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.6, target.global_position + Vector3.UP * 0.6, 1)
			query.exclude = [get_rid()]
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
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
	get_tree().call_group("zombies", "hear_gunshot", origin, 65.0)
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
	is_eliminated = false
	visible = true
	collision_layer = 2
	collision_mask = 23
	health = max_health
	stamina = max_stamina
	hit_reaction_time = 0.0
	pistol_ammo = 12
	reserve_ammo = 48


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


## Dispara o pulso sonar que revela os zumbis proximos no minimapa.
## Respeita o cooldown para nao virar um radar permanente.
## Uso: player.trigger_sonar()
func trigger_sonar() -> void:
	if sonar_cooldown > 0.0 or is_eliminated:
		return
	sonar_pulse_time = SONAR_DURATION
	sonar_cooldown = SONAR_COOLDOWN


## Informa se o pulso sonar esta ativo para desenhar os pontos de zumbi.
## Uso: if player.is_sonar_active(): ...
func is_sonar_active() -> bool:
	return sonar_pulse_time > 0.0


func get_sonar_text() -> String:
	if is_sonar_active():
		return "Sonar: ativo"
	if sonar_cooldown > 0.0:
		return "Sonar: %.1fs" % sonar_cooldown
	return "Sonar: pronto"


func can_see_position(target_position: Vector3) -> bool:
	if is_eliminated:
		return false
	var offset := target_position - global_position
	offset.y = 0.0
	var distance := offset.length()
	if distance <= 0.01 or distance > VISION_RANGE:
		return false
	return -global_transform.basis.z.dot(offset / distance) >= cos(VISION_HALF_ANGLE)


func get_lives_text() -> String:
	if is_eliminated or lives <= 0:
		return "Vidas: [ELIMINADO]"
	return "Vidas: %s (%d/%d)" % ["❤".repeat(lives), lives, MAX_LIVES]


func is_alive() -> bool:
	return not is_eliminated and health > 0


func get_weapon_name() -> String:
	return "Faca (%d dano)" % knife_damage if current_weapon == Weapon.KNIFE else "Pistola (%d dano)" % pistol_damage


func get_ammo_text() -> String:
	return "Municao: --" if current_weapon == Weapon.KNIFE else "Municao: %d/%d" % [pistol_ammo, reserve_ammo]


func get_stamina_text() -> String:
	return "Stamina: %d/%d" % [roundi(stamina), roundi(max_stamina)]


func _update_weapon_models() -> void:
	knife_model.visible = current_weapon == Weapon.KNIFE
	pistol_model.visible = current_weapon == Weapon.PISTOL


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
		surface.add_vertex(_vision_arc_point(first_angle))
		surface.add_vertex(_vision_arc_point(second_angle))
	return surface.commit()


func _vision_arc_point(angle: float) -> Vector3:
	return Vector3(sin(angle) * VISION_ARC_RADIUS, 0.02, -cos(angle) * VISION_ARC_RADIUS)


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
	sonar_pressed = Input.is_action_just_pressed(input_action_prefix + "sonar")


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
	sonar_pressed = false


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
