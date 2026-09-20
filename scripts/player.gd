class_name PlayerCharacter
extends CharacterBody3D

signal lives_changed(current_lives: int)
## Morte em PVP: o main credita o abate (killer pode ser null) e agenda o
## respawn num ponto longe dos vivos.
signal pvp_died(killer: Node)
signal player_eliminated()
## Slots totais: faca e pistola fixas; 1 slot para arma de crate (pegar outra
## troca, dropando a da mao no chao). Emitidos onde o jogador e simulado
## (partida local ou servidor).
signal crate_weapon_broken(kind: int)
signal crate_weapon_dropped(kind: int, mag: int, reserve: int, durability: int)
## Emitido quando o jogador troca entre isometrica e primeira pessoa; o
## split_screen_manager reconstroi a camera e o HUD.
signal first_person_changed(enabled: bool)

## Ordem segue WeaponStats.Kind: as armas de crate ficam por ultimo.
## Mesma ordem de WeaponStats.Kind (os inteiros viajam na rede e nos slots).
enum Weapon { KNIFE, PISTOL, SHOTGUN, UZI, MAGNUM, DOUBLE_BARREL, CARBINE, SAWED_OFF, AUTO_SHOTGUN, LASER_RIFLE, PLASMA_SMG, RAILGUN, AK47, M4, AUG, BERETTA, SNIPER, BAZOOKA, CROSSBOW, GRENADE_LAUNCHER, CHAINSAW, FLAMETHROWER }

const BULLET_SCENE := preload("res://scenes/bullet.tscn")
const KNIFE_ATTACK_DURATION := 0.4
const KNIFE_DOOR_REACH := 1.8
const MAX_LIVES := 3
const MAX_RESERVE_AMMO := 144
## PVP: teto de reserva da pistola. O survival limita a 144 porque a municao e
## recurso escasso; no mata-mata isso so atrapalha.
const MAX_RESERVE_AMMO_PVP := 999
## Cone de visao aposentado (pedido de jogo): o jogador ve todo zumbi a ate
## VIEW_RADIUS em qualquer direcao, sem raio de oclusao (mais barato que o cone).
const VIEW_RADIUS := 35.0
const SONAR_DURATION := 4.0
const SONAR_INTERVAL := 10.0
const SONAR_REVEAL_RADIUS := 45.0
## Raio de coleta por interacao de armas no chao (crates e dropadas).
const GROUND_INTERACT_RADIUS := 2.8
## Porta pode ser usada antes de encostar nela; ainda exige o raycast estar na
## frente do boneco, para nao abrir porta atraves de parede.
const DOOR_INTERACT_REACH := 3.5
## Segurando interagir ao lado do caido, reanimacao completa em ~3s.
const REVIVE_DURATION := 3.0
## Pellet tracer: menor/mais curto que o tracer da pistola.
const PELLET_VISUAL_SCALE := Vector3(0.55, 0.55, 0.45)
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
## Vidas zeradas: caido no chao, reativavel por aliado (interagir segurado).
## Ninguem salva? Rodada nova devolve a todos (restore_wave_lives).
var is_downed := false
var revive_progress := 0.0

var owner_peer_id := 1
var input_action_prefix := "player_1_"
var input_device_name := "Teclado"
var simulation_enabled := true
var reads_local_input := true
var is_local_controller := true
## Soldado do esquadrao SWAT: invulneravel, ignora troca de arma e nao gasta
## municao nem durabilidade (suporte temporario; ver SwatSquadBot.configure).
var is_swat_bot := false
const SWAT_UNIFORM_COLOR := Color(0.07, 0.08, 0.1)
## Mata-mata: dinheiro, placar e janela de compra (autoridade no servidor).
var pvp_money := 0
var pvp_kills := 0
var pvp_deaths := 0
## Segundos restantes de compra e de respawn (0 = liberado / vivo).
var pvp_buy_left := 0.0
var pvp_respawn_left := 0.0
## Ultimo a machucar este jogador: e quem leva o credito do abate.
var last_attacker: Node = null
const PVP_START_PISTOL_MAG := 12
const PVP_START_PISTOL_RESERVE := 240
var infinite_ammo := false

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
var move_input := Vector2.ZERO
var aim_input := Vector2.ZERO
## Mira pelo cursor (isometrica) e primeira pessoa. `camera_yaw` e o yaw livre
## do modo FPS (o corpo segue ele); `view_pitch` inclina so a camera.
const AIM_SENSITIVITY := 0.0022
const AIM_PITCH_LIMIT := 1.35
var mouse_aim := true
var first_person := false
var camera_yaw := 0.0
var view_pitch := 0.0
## Camera/viewport do jogador, setados pelo split_screen_manager, para projetar
## o cursor no chao. `mouse_owner` diz quem controla o unico cursor (P1).
var aim_camera: Camera3D = null
var aim_viewport: Viewport = null
var mouse_owner := true
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
var double_barrel_pressed := false
var carbine_pressed := false
var drop_pressed := false
## Tab (ou botao do controle) cicla faca -> pistola -> arma de crate.
var cycle_weapon_pressed := false
var grenade_pressed := false
var throw_knife_pressed := false
var air_strike_pressed := false
var swat_pressed := false
## Granadas, facas de arremesso e chamadas (PlayerThrowables usa).
var equipment := PlayerEquipment.new()
var equipment_cooldown := 0.0
## Puxado pela lingua ou preso pelo espreitador: velocidade imposta por um tempo.
var forced_move_velocity := Vector3.ZERO
var forced_move_time := 0.0
var weapon_slots := WeaponSlots.new()
## Ultima revisao do inventario aplicada pelo snapshot; -1 = nunca aplicado.
var slots_revision := -1
var crate_weapon_rng := RandomNumberGenerator.new()
var crate_weapon_models: Dictionary = {}
var sonar_pulse_time := 0.0
var sonar_interval_timer := SONAR_INTERVAL
## Buffer de interpolacao dos snapshots do servidor (mesmo do zumbi): o proxy
## do aliado remoto procura o par de amostras que envolve o tempo de render em
## vez de perseguir o ultimo pacote, que dava o "teleporte" do jogador.
var snapshot_buffer := SnapshotInterpBuffer.new()
var unstuck_cooldown := 0.0
## Sobe a cada teleporte do servidor (destravar, respawn); o cliente pula a
## interpolacao, que colidiria com o que prendeu o boneco.
var teleport_sequence := 0
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
	mouse_aim = GameConfig.mouse_aim_enabled
	first_person = GameConfig.first_person_enabled
	camera_yaw = rotation.y
	snapshot_buffer.reset(float(Time.get_ticks_msec()), global_position, rotation.y)
	_apply_player_color()
	_build_crate_weapon_models()
	_update_weapon_models()


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
	_poll_view_toggle()
	muzzle_flash.visible = muzzle_flash_time > 0.0
	if not simulation_enabled:
		var previous_position := global_position
		# Interpolacao por buffer com atraso adaptativo; o move_and_collide segue
		# no caminho do alvo para nao atravessar parede.
		snapshot_buffer.sample(float(Time.get_ticks_msec()))
		var target_pos := snapshot_buffer.position
		var motion := target_pos - global_position
		if motion.length_squared() > 0.00001:
			var col := move_and_collide(motion)
			if col != null:
				move_and_collide(col.get_remainder().slide(col.get_normal()))
		rotation.y = lerp_angle(rotation.y, snapshot_buffer.rotation, minf(delta * 16.0, 1.0))
		PlayerAnimator.animate_pose(self, delta, previous_position.distance_squared_to(global_position) > 0.0001)
		return

	if is_downed:
		# Caido (so onde e simulado: offline/servidor): sem acao; o aliado
		# segurando interagir reanima em ~3s. O proxy do cliente apenas
		# interpola, para nao brigar com o progresso sincronizado.
		velocity = Vector3.ZERO
		_update_revive_by_others(delta)
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
	equipment_cooldown = maxf(equipment_cooldown - delta, 0.0)
	_handle_equipment_input()
	_update_revive_by_others(delta)

	if not is_on_floor():
		velocity.y -= gravity * delta

	if jump_pressed and is_on_floor():
		velocity.y = jump_velocity

	var direction := Vector3(move_input.x, 0.0, move_input.y).normalized()
	_update_stamina(delta, not direction.is_zero_approx() and sprint_pressed)
	_update_noise(delta, direction)
	if first_person:
		# FPS: o yaw vem do mouse (sem suavizar), o corpo inteiro segue.
		rotation.y = camera_yaw
	elif not aim_input.is_zero_approx():
		var target_rotation := atan2(-aim_input.x, -aim_input.y)
		rotation.y = lerp_angle(rotation.y, target_rotation, minf(delta * 14.0, 1.0))
	elif not direction.is_zero_approx():
		var target_rotation := atan2(-direction.x, -direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, minf(delta * 14.0, 1.0))
	var target_velocity := direction * (sprint_speed if is_sprinting else speed)

	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)
	if forced_move_time > 0.0:
		forced_move_time = maxf(forced_move_time - delta, 0.0)
		velocity.x = forced_move_velocity.x
		velocity.z = forced_move_velocity.z

	move_and_slide()
	PlayerAnimator.animate_pose(self, delta, direction.length() > 0.0 and is_on_floor())
	_clear_transient_input()


func get_local_input_state() -> Dictionary:
	return {
		"slot": local_slot,
		"move": _aim_relative_move(Input.get_vector(input_action_prefix + "left", input_action_prefix + "right", input_action_prefix + "up", input_action_prefix + "down")),
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
		"double_barrel": Input.is_action_pressed(input_action_prefix + "double_barrel"),
		"carbine": Input.is_action_pressed(input_action_prefix + "carbine"),
		"drop": Input.is_action_pressed(input_action_prefix + "drop_weapon"),
		"cycle": Input.is_action_pressed(input_action_prefix + "cycle_weapon"),
		"grenade": Input.is_action_pressed(input_action_prefix + "grenade"),
		"throw_knife": Input.is_action_pressed(input_action_prefix + "throw_knife"),
		"air_strike": Input.is_action_pressed(input_action_prefix + "air_strike"),
		"swat": Input.is_action_pressed(input_action_prefix + "swat"),
		"aim": _local_aim_input(),
	}


func apply_network_input(state: Dictionary) -> void:
	var requested_move: Variant = state.get("move", Vector2.ZERO)
	move_input = requested_move.limit_length(1.0) if requested_move is Vector2 else Vector2.ZERO
	var requested_aim: Variant = state.get("aim", Vector2.ZERO)
	aim_input = requested_aim.limit_length(1.0) if requested_aim is Vector2 else Vector2.ZERO
	# Cliques acumulam ate o tick de fisica consumir (_clear_transient_input):
	# dois pacotes de input no mesmo frame (jitter da internet) faziam o segundo
	# apagar o clique do primeiro, perdendo tiro, recarga ou coleta. A funcao vem
	# antes do "or" para sempre atualizar o estado anterior do botao.
	jump_pressed = _network_button_just_pressed("jump", bool(state.get("jump", false))) or jump_pressed
	sprint_pressed = bool(state.get("sprint", false))
	attack_pressed = _network_button_just_pressed("attack", bool(state.get("attack", false))) or attack_pressed
	knife_pressed = _network_button_just_pressed("knife", bool(state.get("knife", false))) or knife_pressed
	pistol_pressed = _network_button_just_pressed("pistol", bool(state.get("pistol", false))) or pistol_pressed
	reload_pressed = _network_button_just_pressed("reload", bool(state.get("reload", false))) or reload_pressed
	interact_pressed = _network_button_just_pressed("interact", bool(state.get("interact", false))) or interact_pressed
	shotgun_pressed = _network_button_just_pressed("shotgun", bool(state.get("shotgun", false))) or shotgun_pressed
	uzi_pressed = _network_button_just_pressed("uzi", bool(state.get("uzi", false))) or uzi_pressed
	magnum_pressed = _network_button_just_pressed("magnum", bool(state.get("magnum", false))) or magnum_pressed
	double_barrel_pressed = _network_button_just_pressed("double_barrel", bool(state.get("double_barrel", false))) or double_barrel_pressed
	carbine_pressed = _network_button_just_pressed("carbine", bool(state.get("carbine", false))) or carbine_pressed
	drop_pressed = _network_button_just_pressed("drop", bool(state.get("drop", false))) or drop_pressed
	cycle_weapon_pressed = _network_button_just_pressed("cycle", bool(state.get("cycle", false))) or cycle_weapon_pressed
	grenade_pressed = _network_button_just_pressed("grenade", bool(state.get("grenade", false))) or grenade_pressed
	throw_knife_pressed = _network_button_just_pressed("throw_knife", bool(state.get("throw_knife", false))) or throw_knife_pressed
	air_strike_pressed = _network_button_just_pressed("air_strike", bool(state.get("air_strike", false))) or air_strike_pressed
	swat_pressed = _network_button_just_pressed("swat", bool(state.get("swat", false))) or swat_pressed
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
		"downed": is_downed,
		"revive_progress": revive_progress,
		"equipment": equipment.to_counts(),
		"pvp_money": pvp_money,
		"pvp_kills": pvp_kills,
		"pvp_deaths": pvp_deaths,
		"pvp_buy_left": pvp_buy_left,
	}


func apply_network_state(state: Dictionary) -> void:
	var position_value: Variant = state.get("position")
	var received_teleport := int(state.get("teleport_sequence", teleport_sequence))
	if position_value is Vector3:
		var next_position: Vector3 = position_value
		var next_rotation := float(state.get("rotation", snapshot_buffer.rotation))
		if received_teleport != teleport_sequence:
			# Teleporte autorizado (destravar/respawn): o buffer reinicia e o no
			# pula, senao o proxy deslizaria atravessando o mapa.
			snapshot_buffer.reset(float(Time.get_ticks_msec()), next_position, next_rotation)
			global_position = next_position
			rotation.y = next_rotation
			velocity = Vector3.ZERO
		elif snapshot_buffer.push(float(Time.get_ticks_msec()), next_position, next_rotation, global_position, rotation.y):
			global_position = snapshot_buffer.position
			rotation.y = snapshot_buffer.rotation
	teleport_sequence = received_teleport
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
	var next_downed := bool(state.get("downed", is_downed))
	if next_downed != is_downed:
		if next_downed:
			is_downed = true
			visible = true
			collision_layer = 2
			collision_mask = 0
			if model != null:
				model.rotation.x = deg_to_rad(-86.0)
		else:
			_clear_downed()
	revive_progress = clampf(float(state.get("revive_progress", revive_progress)), 0.0, 1.0)
	var equipment_counts: Variant = state.get("equipment")
	if equipment_counts is PackedByteArray:
		equipment.apply_counts(equipment_counts)
	if NetworkSession.pvp_mode:
		pvp_money = maxi(pvp_money, int(state.get("pvp_money", pvp_money)))
		pvp_kills = maxi(pvp_kills, int(state.get("pvp_kills", pvp_kills)))
		pvp_deaths = maxi(pvp_deaths, int(state.get("pvp_deaths", pvp_deaths)))
		pvp_buy_left = float(state.get("pvp_buy_left", pvp_buy_left))
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
	# Armas automaticas (Uzi) atiram segurando; as outras sao por aperto.
	var wants_to_attack := attack_pressed
	if bool(WeaponStats.stats_for(current_weapon).get("is_auto", false)):
		wants_to_attack = _is_attack_held()
	if wants_to_attack and attack_cooldown <= 0.0:
		match current_weapon:
			Weapon.KNIFE:
				_attack_with_knife()
			Weapon.PISTOL:
				_fire_pistol()
			_:
				_fire_crate_weapon()


func _equip_weapon_from_input() -> void:
	if cycle_weapon_pressed:
		_equip_weapon(next_weapon_in_cycle(current_weapon, weapon_slots.kinds))
	for request in [[knife_pressed, Weapon.KNIFE], [pistol_pressed, Weapon.PISTOL], [shotgun_pressed, Weapon.SHOTGUN], [uzi_pressed, Weapon.UZI], [magnum_pressed, Weapon.MAGNUM], [double_barrel_pressed, Weapon.DOUBLE_BARREL], [carbine_pressed, Weapon.CARBINE]]:
		if not bool(request[0]):
			continue
		var requested: int = request[1]
		if requested == Weapon.KNIFE or requested == Weapon.PISTOL or weapon_slots.has_kind(requested):
			_equip_weapon(requested)


func _equip_weapon(requested: int) -> void:
	if requested == current_weapon:
		return
	current_weapon = requested
	pistol_stance_time = 0.0
	crate_weapon_stance_time = 10.0 if WeaponStats.is_crate_weapon(requested) else 0.0
	_update_weapon_models()


## Proxima arma do ciclo do Tab: faca, pistola e as armas de crate que o
## jogador tem, voltando para a faca.
## Uso: var proxima := PlayerCharacter.next_weapon_in_cycle(Weapon.PISTOL, weapon_slots.kinds)
static func next_weapon_in_cycle(current: int, owned_crate_kinds: Array[int]) -> int:
	var order: Array[int] = [Weapon.KNIFE, Weapon.PISTOL]
	order.append_array(owned_crate_kinds)
	var index := order.find(current)
	return order[(index + 1) % order.size()]


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
	if not infinite_ammo:
		weapon_slots.consume_mag(current_weapon)
	attack_cooldown = float(WeaponStats.stats_for(current_weapon)["attack_cooldown"])
	muzzle_flash_time = 0.08
	gunshot_noise_time = 0.6
	crate_weapon_stance_time = 10.0
	_fire_pellets(current_weapon)
	if not infinite_ammo and weapon_slots.wear(current_weapon) <= 0:
		_break_crate_weapon(current_weapon)


func _fire_pellets(weapon_kind: int) -> void:
	var stats := WeaponStats.stats_for(weapon_kind)
	var pellet_count := int(stats["pellets"])
	var spread_deg := float(stats["degraded_spread_deg"] if weapon_slots.is_degraded(weapon_kind) else stats["spread_deg"])
	var base_direction := Vector3(aim_input.x, 0.0, aim_input.y).normalized()
	if base_direction.is_zero_approx():
		base_direction = -global_transform.basis.z
	var origin := global_position + Vector3.UP * 0.55
	if stats.has("cone_range"):
		_fire_cone_weapon(weapon_kind, stats, origin, base_direction)
		return
	for pellet_index in pellet_count:
		var angle_offset := 0.0
		if pellet_count > 1:
			angle_offset = deg_to_rad(spread_deg) * (float(pellet_index) - float(pellet_count - 1) / 2.0) / (float(pellet_count) / 2.0)
		var pellet_direction := base_direction.rotated(Vector3.UP, angle_offset)
		# Hitscan: 1 ray por pellet, dano na hora; sem node por pellet.
		if stats.has("explosive_radius"):
			var impact := Bullet.explosive_shot(origin + pellet_direction * 0.12, pellet_direction, int(stats["damage"]), self, float(stats["explosive_radius"]))
			get_tree().current_scene.call("show_explosion", impact, float(stats["explosive_radius"]))
		else:
			Bullet.hitscan_damage(origin + pellet_direction * 0.12, pellet_direction, int(stats["damage"]), self, int(stats.get("pierce", 1)))
		if NetworkSession.is_offline():
			_spawn_pellet_visual(origin + pellet_direction * 0.12, pellet_direction, pellet_index, pellet_count, weapon_kind)
	ZombieFlockCoordinator.relay_sound(get_tree(), origin, float(stats["noise_radius"]))
	if NetworkSession.is_offline():
		AudioFeedback.play_gunshot(origin, weapon_kind)
	if NetworkSession.is_server():
		get_tree().current_scene.replicate_bullet_visual(origin, base_direction, pellet_count, spread_deg, weapon_kind)


## Motosserra/lanca-chamas: dano em cone no tick, visual de labareda/faisca.
func _fire_cone_weapon(weapon_kind: int, stats: Dictionary, origin: Vector3, direction: Vector3) -> void:
	WeaponConeAttack.strike(get_tree(), origin, direction, stats, self)
	ZombieFlockCoordinator.relay_sound(get_tree(), origin, float(stats["noise_radius"]))
	if NetworkSession.is_offline():
		WeaponConeVisual.spawn(get_tree().current_scene, origin, direction, weapon_kind)
		AudioFeedback.play_gunshot(origin, weapon_kind)
	if NetworkSession.is_server():
		get_tree().current_scene.replicate_bullet_visual(origin, direction, 1, 0.0, weapon_kind)


## Tracer de pellet: menor e deslocado em leque, para NAO parecer o tracer
## unico da pistola. Visual puro, sem dano.
func _spawn_pellet_visual(origin: Vector3, direction: Vector3, pellet_index: int, pellet_count: int, weapon_kind: int) -> void:
	var bullet := BULLET_SCENE.instantiate() as Node3D
	get_tree().current_scene.add_child(bullet)
	bullet.scale = PELLET_VISUAL_SCALE
	bullet.global_position = origin + _pellet_side_offset(direction, pellet_index, pellet_count)
	bullet.setup(direction, 0, false)
	Bullet.style_tracer(bullet, weapon_kind)
	bullet.add_to_group("network_bullet_visuals")


## Deslocamento lateral pequeno por pellet (leque de tracers visivel).
func _pellet_side_offset(direction: Vector3, pellet_index: int, pellet_count: int) -> Vector3:
	var side := Vector3.UP.cross(direction).normalized()
	return side * (float(pellet_index) - float(pellet_count - 1) / 2.0) * 0.05


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


## Arma de crate guardada (na mao ou no slot) deste tipo.
## Uso: if player.has_crate_weapon(WeaponStats.Kind.UZI): ...
func has_crate_weapon(weapon_kind: int) -> bool:
	return weapon_slots.has_kind(weapon_kind)


## Quanto cabe na reserva da arma de crate deste tipo (0 sem a arma).
## Uso: var espaco := player.crate_reserve_space(WeaponStats.Kind.UZI)
func crate_reserve_space(weapon_kind: int) -> int:
	return weapon_slots.free_reserve_space(weapon_kind)


## Municao vinda de uma arma igual no chao; devolve quanto entrou.
## Uso: var entrou := player.absorb_ground_ammo(WeaponStats.Kind.UZI, 40)
func absorb_ground_ammo(weapon_kind: int, amount: int) -> int:
	return weapon_slots.add_reserve(weapon_kind, amount)


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
	# Slot cheio: troca pela arma de crate guardada, esteja ela na mao ou nao
	# (com faca/pistola na mao pelo Tab, antes voltava "full" e nada acontecia).
	if not weapon_slots.kinds.is_empty():
		current_weapon = weapon_slots.kinds[0]
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


## Adiciona municao a reserva da arma de crate informada; 0 se nao possui.
## Uso: item de municiao de classe chama add_crate_reserve(UZI, 90)
func add_crate_reserve(kind: int, amount: int) -> int:
	if not weapon_slots.has_kind(kind):
		return 0
	return weapon_slots.add_reserve(kind, amount)


func has_free_weapon_slot() -> bool:
	return weapon_slots.has_free_slot()


## Botao de ataque segurado: input local usa Input, rede usa o estado cru
## que o servidor recebeu (30 Hz). Uso: armas automaticas.
func _is_attack_held() -> bool:
	if reads_local_input:
		return Input.is_action_pressed(input_action_prefix + "attack")
	return bool(remote_buttons.get("attack", false))


## Reanimacao (D): um aliado de pe segurando INTERAGIR ao lado do caido
## reanima em ~3s; sem aliado, o progresso decai. Roda onde o revividor e
## simulado (servidor/offline) e mexe no node do caido.
func _update_revive_by_others(delta: float) -> void:
	if is_eliminated:
		return
	var target := _find_nearest_downed_player()
	var helping := target != null and _is_interact_held()
	if target != null:
		if helping:
			target.revive_progress += delta / REVIVE_DURATION
			if target.revive_progress >= 1.0:
				target.revive_downed()
		else:
			target.revive_progress = maxf(target.revive_progress - delta * 0.6, 0.0)
	elif not helping:
		# Ninguem perto: o proprio caido decai se sobrou progresso solto.
		revive_progress = maxf(revive_progress - delta * 0.6, 0.0)


func _find_nearest_downed_player() -> PlayerCharacter:
	var best: PlayerCharacter = null
	var best_distance := GROUND_INTERACT_RADIUS
	for node in get_tree().get_nodes_in_group("player"):
		var candidate := node as PlayerCharacter
		if candidate == null or not is_instance_valid(candidate) or candidate == self:
			continue
		if not candidate.is_downed or bool(candidate.get("is_eliminated")):
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


## Interagir segurado: local via Input; na rede via estado cru recebido.
func _is_interact_held() -> bool:
	if reads_local_input:
		return Input.is_action_pressed(input_action_prefix + "interact")
	return bool(remote_buttons.get("interact", false))


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
	var ray_end := ray_start - global_transform.basis.z * DOOR_INTERACT_REACH
	var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end, 1, [self])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var collider: Node = hit.get("collider")
	while collider != null:
		if collider.has_method("interact"):
			if collider.is_in_group("destructible_door"):
				collider.interact(self)
			else:
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
		# Distancia no chao: a origem do boneco fica ~1 m acima do item.
		var distance := Vector2(global_position.x - pickup.global_position.x, global_position.z - pickup.global_position.z).length()
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


func _find_knife_target() -> Node3D:
	var best_target: Node3D = null
	var best_distance := 1.7
	var forward := -global_transform.basis.z
	# No maximo 4 rays por facada: cercado, os 4 mais proximos bastam.
	# Varre os grupos direto (sem montar array de 600 alvos por facada).
	var rays_used := 0
	for group_name in ["zombies", "player"]:
		for target_value in get_tree().get_nodes_in_group(group_name):
			if rays_used >= 4:
				return best_target
			var target := target_value as Node3D
			if target == null or not is_instance_valid(target) or target == self:
				continue
			if target_value is Node3D and (target_value as Node).get("is_dead") == true:
				continue
			var offset := target.global_position - global_position
			offset.y = 0.0
			var distance := offset.length()
			if distance <= best_distance and forward.dot(offset / distance) > 0.6:
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


## Adiciona municao a reserva do jogador ate o limite do modo.
## Retorna a quantidade de municao efetivamente adicionada.
## Uso:
##   var adicionado := player.add_ammo(24)
func add_ammo(amount: int) -> int:
	var reserve_cap := _reserve_ammo_cap()
	if amount <= 0 or reserve_ammo >= reserve_cap:
		return 0
	var space := reserve_cap - reserve_ammo
	var added := mini(amount, space)
	reserve_ammo += added
	return added


## Informa se o jogador pode coletar mais municao.
## Uso:
##   if player.can_pickup_ammo():
func can_pickup_ammo() -> bool:
	return reserve_ammo < _reserve_ammo_cap()


## Teto da reserva de pistola: bem maior no mata-mata.
## Uso: var espaco := _reserve_ammo_cap() - reserve_ammo
func _reserve_ammo_cap() -> int:
	return MAX_RESERVE_AMMO_PVP if NetworkSession.pvp_mode else MAX_RESERVE_AMMO


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
func take_damage(amount: int, attack_direction: Vector3 = Vector3.ZERO, _damage_kind: String = "bullet", source: Node = null, _hit_position: Vector3 = Vector3.INF) -> void:
	if is_swat_bot:
		# Soldado do esquadrao e suporte, nao baixa: nada machuca ele.
		return
	if is_eliminated or is_downed:
		# Caido fica fora do combate ate ser reanimado (ou virar a rodada).
		return
	if is_instance_valid(source) and source != self:
		last_attacker = source
	health = maxi(health - amount, 0)
	hit_reaction_time = 0.35
	hit_direction = attack_direction.normalized()
	velocity += hit_direction * 4.5 + Vector3.UP * 1.2
	if health == 0:
		if NetworkSession.pvp_mode:
			_pvp_die()
			return
		lives -= 1
		lives_changed.emit(lives)
		if lives <= 0:
			lives = 0
			# Fim das vidas NAO elimina: cai no chao e fica reativavel.
			_go_downed()
		else:
			respawn()


## Morte no mata-mata: sai do combate, perde as armas compradas (volta com
## pistola) e avisa o main, que credita o abate e agenda o respawn.
## Uso: chamado pelo take_damage quando NetworkSession.pvp_mode.
func _pvp_die() -> void:
	var killer: Node = last_attacker if is_instance_valid(last_attacker) else null
	last_attacker = null
	pvp_deaths += 1
	pvp_respawn_left = PvpMatch.RESPAWN_SECONDS
	is_eliminated = true
	visible = false
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	health = 0
	reset_pvp_loadout()
	pvp_died.emit(killer)


## Volta a pistola e faca, sem armas de crate (economia nova a cada vida).
## Uso: player.reset_pvp_loadout()
func reset_pvp_loadout() -> void:
	for kind in weapon_slots.kinds.duplicate():
		weapon_slots.remove_kind(kind)
	current_weapon = Weapon.PISTOL
	pistol_ammo = PVP_START_PISTOL_MAG
	reserve_ammo = PVP_START_PISTOL_RESERVE
	_update_weapon_models()


## Respawna em PVP no ponto escolhido pelo main (longe dos vivos), com a janela
## de compra reaberta. Uso: player.pvp_respawn_at(posicao)
func pvp_respawn_at(respawn_position: Vector3) -> void:
	global_position = respawn_position
	velocity = Vector3.ZERO
	teleport_sequence += 1
	is_eliminated = false
	is_downed = false
	visible = true
	collision_layer = 2
	collision_mask = 23
	health = max_health
	stamina = max_stamina
	hit_reaction_time = 0.0
	pvp_respawn_left = 0.0
	pvp_buy_left = PvpMatch.BUY_SECONDS
	reset_pvp_loadout()


## Avanca os relogios do PVP (compra e respawn). Roda onde o jogador e
## simulado (servidor/offline). Uso: player.tick_pvp(delta)
func tick_pvp(delta: float) -> void:
	pvp_buy_left = maxf(pvp_buy_left - delta, 0.0)
	if is_eliminated:
		pvp_respawn_left = maxf(pvp_respawn_left - delta, 0.0)


func respawn() -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO
	teleport_sequence += 1
	is_eliminated = false
	_clear_downed()
	visible = true
	collision_layer = 2
	collision_mask = 23
	health = max_health
	stamina = max_stamina
	hit_reaction_time = 0.0
	pistol_ammo = 12
	reserve_ammo = 96


## Fim das vidas: cai no chao (visivel, deitado, sem acao) e fica
## reativavel por aliado; se a rodada terminar, restore_wave_lives volta.
func _go_downed() -> void:
	is_downed = true
	revive_progress = 0.0
	velocity = Vector3.ZERO
	health = 0
	stamina = 0.0
	is_eliminated = false
	visible = true
	collision_layer = 2
	collision_mask = 0
	if model != null:
		model.rotation.x = deg_to_rad(-86.0)
	player_eliminated.emit()


## Reanimado por aliado: levanta com metade da vida e sem vidas extras.
func revive_downed() -> void:
	_clear_downed()
	health = maxi(max_health / 2, 1)
	stamina = max_stamina


func _clear_downed() -> void:
	is_downed = false
	revive_progress = 0.0
	if model != null and is_instance_valid(model):
		model.rotation.x = 0.0


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
	if not is_eliminated and not is_downed:
		return
	respawn()


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


## Zumbi dentro do raio de visao em qualquer direcao (sem cone e sem parede).
## Uso: if player.can_see_position(zombie.global_position): mostrar()
func can_see_position(target_position: Vector3) -> bool:
	if is_eliminated:
		return false
	var offset := target_position - global_position
	offset.y = 0.0
	return offset.length_squared() <= VIEW_RADIUS * VIEW_RADIUS


func get_lives_text() -> String:
	if NetworkSession.pvp_mode:
		# Vidas nao existem no mata-mata: a linha vira dinheiro e placar.
		return "PVP: $%d | %d/%d" % [pvp_money, pvp_kills, pvp_deaths]
	if is_downed:
		return "CAIDO | segure Interagir perto para reanimar"
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
			if NetworkSession.pvp_mode:
				return "%s (%d dano) | Durab ∞" % [stats["label"], stats["damage"]]
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
	return "Armas: Faca | Pistola | %s\n%s" % [crate_label, equipment.summary_text()]


## Movimento imposto por especial (lingua puxando, bote prendendo): vence o
## input do jogador por `seconds`. Uso: player.apply_forced_move(puxao, 0.2)
func apply_forced_move(forced_velocity: Vector3, seconds: float) -> void:
	forced_move_velocity = Vector3(forced_velocity.x, 0.0, forced_velocity.z)
	forced_move_time = maxf(seconds, 0.0)


## Granada, faca de arremesso e chamadas (autoridade).
## Uso: chamado no _physics_process depois das armas.
func _handle_equipment_input() -> void:
	PlayerThrowables.handle_input(self)


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
	for kind in WeaponStats.crate_kinds():
		var weapon_node := CrateWeaponModelBuilder.build(kind, _muzzle_material())
		weapon_holder.add_child(weapon_node)
		crate_weapon_models[kind] = weapon_node


func _muzzle_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.72, 0.08)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.35, 0.02)
	material.emission_energy_multiplier = 3.0
	return material


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
	move_input = _aim_relative_move(Input.get_vector(input_action_prefix + "left", input_action_prefix + "right", input_action_prefix + "up", input_action_prefix + "down"))
	aim_input = _local_aim_input()
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
	double_barrel_pressed = Input.is_action_just_pressed(input_action_prefix + "double_barrel")
	carbine_pressed = Input.is_action_just_pressed(input_action_prefix + "carbine")
	drop_pressed = Input.is_action_just_pressed(input_action_prefix + "drop_weapon")
	cycle_weapon_pressed = Input.is_action_just_pressed(input_action_prefix + "cycle_weapon")
	grenade_pressed = Input.is_action_just_pressed(input_action_prefix + "grenade")
	throw_knife_pressed = Input.is_action_just_pressed(input_action_prefix + "throw_knife")
	air_strike_pressed = Input.is_action_just_pressed(input_action_prefix + "air_strike")
	swat_pressed = Input.is_action_just_pressed(input_action_prefix + "swat")


## Le o pulso sonar apenas para o avatar controlado localmente. No cliente de
## rede o jogador nao le input de movimento (o servidor e autoritativo), mas o
## sonar e local e continua funcionando.
## Uso: chamado a cada tick de fisica.
func _poll_local_sonar() -> void:
	if not is_local_controller:
		return
	if Input.is_action_just_pressed(input_action_prefix + "sonar"):
		trigger_sonar()


## Alterna isometrica/FPS pela tecla "view". Fora do _poll_input porque o cliente
## de rede nao le input de movimento (reads_local_input=false), mas o dono local
## ainda troca de camera. Uso: chamado a cada tick de fisica.
func _poll_view_toggle() -> void:
	if not is_local_controller:
		return
	if Input.is_action_just_pressed(input_action_prefix + "view"):
		toggle_first_person()


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
	double_barrel_pressed = false
	carbine_pressed = false
	drop_pressed = false
	cycle_weapon_pressed = false
	grenade_pressed = false
	throw_knife_pressed = false
	air_strike_pressed = false
	swat_pressed = false


## Look do FPS: o movimento do mouse gira o corpo (yaw) e inclina a camera
## (pitch). So o dono do cursor aplica, para nao girar todos os jogadores juntos.
func _input(event: InputEvent) -> void:
	if not first_person or not is_local_controller or not mouse_owner:
		return
	if GameConfig.menu_open or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		camera_yaw = wrapf(camera_yaw - motion.relative.x * AIM_SENSITIVITY, -PI, PI)
		view_pitch = clampf(view_pitch - motion.relative.y * AIM_SENSITIVITY, -AIM_PITCH_LIMIT, AIM_PITCH_LIMIT)


## Direcao de mira local (XZ no mundo). O FPS usa o yaw do mouse; a isometrica
## projeta o cursor no chao. Sem mira o corpo volta a virar para o movimento.
## Uso: chamado por _poll_input e por get_local_input_state.
func _local_aim_input() -> Vector2:
	if first_person:
		return Vector2(-sin(camera_yaw), -cos(camera_yaw))
	if GameConfig.mouse_aim_enabled and mouse_aim and mouse_owner:
		return _mouse_ground_direction()
	return Vector2.ZERO


## No FPS o WASD vira relativo ao olhar (W = frente da camera); na isometrica o
## movimento continua alinhado ao mundo/camera fixa. Uso: interno.
func _aim_relative_move(raw: Vector2) -> Vector2:
	if not first_person:
		return raw
	return raw.rotated(-camera_yaw)


## Projeta o cursor do viewport do jogador no plano do chao e devolve a direcao
## (XZ) do boneco ate o ponto. Uso: interno da mira.
func _mouse_ground_direction() -> Vector2:
	if aim_camera == null or not is_instance_valid(aim_camera) or aim_viewport == null or not is_instance_valid(aim_viewport):
		return Vector2.ZERO
	var screen_point := aim_viewport.get_mouse_position()
	var ray_origin := aim_camera.project_ray_origin(screen_point)
	var ray_direction := aim_camera.project_ray_normal(screen_point)
	var ground := Plane(Vector3.UP, global_position.y + 0.1)
	var hit: Variant = ground.intersects_ray(ray_origin, ray_direction)
	if hit == null:
		return Vector2.ZERO
	var offset := Vector2((hit as Vector3).x - global_position.x, (hit as Vector3).z - global_position.z)
	if offset.length_squared() < 0.04:
		return Vector2.ZERO
	return offset.normalized()


## Alterna isometrica <-> primeira pessoa. Uso: tecla "view" e menu.
func toggle_first_person() -> void:
	set_first_person(not first_person)


## Uso: player.set_first_person(true)
func set_first_person(enabled: bool) -> void:
	if first_person == enabled:
		return
	first_person = enabled
	if first_person:
		camera_yaw = rotation.y
		view_pitch = 0.0
	first_person_changed.emit(first_person)
	_apply_mouse_capture()


## Em FPS o cursor fica preso (o mouse olha); na isometrica ele volta a mirar.
## Com o menu aberto quem manda e o menu. Uso: interno.
func _apply_mouse_capture() -> void:
	if GameConfig.menu_open:
		return
	if first_person and is_local_controller:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif not _another_local_player_in_first_person():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Algum outro jogador local ja esta em primeira pessoa (cursor ja preso)?
## Uso: interno do _apply_mouse_capture.
func _another_local_player_in_first_person() -> bool:
	for node in get_tree().get_nodes_in_group("player"):
		if node != self and node.get("is_local_controller") == true and bool(node.get("first_person")):
			return true
	return false


## Equipa e seleciona uma arma de crate na autoridade (esquadrao SWAT com Uzi).
## Devolve false quando o tipo nao e arma de crate.
## Uso: if player.equip_crate_weapon(WeaponStats.Kind.UZI): ...
func equip_crate_weapon(kind: int) -> bool:
	if not WeaponStats.is_crate_weapon(kind):
		return false
	if not weapon_slots.has_kind(kind) and not weapon_slots.has_free_slot():
		return false
	weapon_slots.grant(kind)
	_equip_weapon(kind)
	return true


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
	# Soldado do esquadrao SWAT usa uniforme escuro proprio, igual nos dois
	# lados (o cliente nao ve o resto da configuracao do bot do servidor).
	uniform_material.albedo_color = SWAT_UNIFORM_COLOR if is_swat_bot else colors[posmod(active_index, colors.size())]
	uniform_material.roughness = 0.8
	$Model/Torso.material_override = uniform_material
	$Model/LeftArm/Mesh.material_override = uniform_material
	$Model/RightArm/Mesh.material_override = uniform_material
