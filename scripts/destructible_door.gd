class_name DestructibleDoor
extends AnimatableBody3D

const DEBRIS_EFFECT_SCRIPT: GDScript = preload("res://scripts/door_debris_effect.gd")
const PANEL_SPEED := 4.5
const OPEN_SWING := PI * 0.5
const HIT_SHAKE_DURATION := 0.18
const HIT_SHAKE_AMPLITUDE := 0.05
const KNOB_COLOR := Color(0.72, 0.56, 0.18)

## Emitido quando a porta abre, fecha ou quebra; o servidor replica so isso.
signal network_state_changed(door: Node)

var panel_size := Vector3(2.2, 2.4, 0.14)
var panel_material: Material
var max_health := 75
var health := 75
var is_open := false
var is_destroyed := false
var target_rotation_y := 0.0
var swing_direction := 1.0
var hit_shake_time := 0.0
var _hinge_offset := Vector3.ZERO
var _panel_node: Node3D
var _received_network_state := false


## Configures a door before it is added to the scene tree. A non-zero
## `requested_swing_direction` overrides the legacy axis-derived swing.
## Usage: door.configure(Vector3(2.2, 2.4, 0.14), wall_material, -1.0)
func configure(size: Vector3, material: Material, requested_swing_direction: float = 0.0) -> void:
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		push_error("Tamanho de porta invalido %s; esperado um Vector3 positivo." % size)
		return
	panel_size = size
	panel_material = material
	if not is_zero_approx(requested_swing_direction):
		swing_direction = signf(requested_swing_direction)
		return
	swing_direction = 1.0 if panel_size.z > panel_size.x else -1.0


func _ready() -> void:
	add_to_group("destructible_door")
	health = max_health
	_create_panel()
	# Porta ociosa = parada no espaco: fisica desligada ate um evento acorda
	# (interact/take_damage/apply_network_state). 388 portas paradas nao
	# podem custar ~1 ms/frame so para responder "nada a fazer".
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if hit_shake_time > 0.0:
		_update_hit_shake(delta)
	if is_destroyed:
		# Destruida nao precisa mais de fisica: painel oculto e colisao off.
		set_physics_process(false)
		return
	target_rotation_y = OPEN_SWING * swing_direction if is_open else 0.0
	rotation.y = move_toward(rotation.y, target_rotation_y, PANEL_SPEED * maxf(delta, 0.0))
	if hit_shake_time <= 0.0 and absf(rotation.y - target_rotation_y) < 0.001:
		set_physics_process(false)


## Toggles the door. When opening, the leaf swings away from the player who
## interacted; zombies never open doors, they can only break them.
## Usage: door.interact(player)
func interact(opener: Node3D = null) -> void:
	if is_destroyed:
		return
	if not is_open and opener != null:
		_set_swing_away_from(opener.global_position)
	is_open = not is_open
	set_physics_process(true)
	network_state_changed.emit(self)


## Seleciona o lado oposto a quem abriu. A folha horizontal gira para +/- Z;
## a vertical gira para -/+ X, por causa do pivot no inicio do vao. Uso: interno.
func _set_swing_away_from(opener_position: Vector3) -> void:
	var local_opener := to_local(opener_position)
	if panel_size.x > panel_size.z and not is_zero_approx(local_opener.z):
		swing_direction = signf(local_opener.z)
	elif panel_size.z > panel_size.x and not is_zero_approx(local_opener.x):
		swing_direction = -signf(local_opener.x)


## Damages a building door, open or closed. Zombie claws, the player's knife
## and bullets all count; at zero health the door bursts into debris and stops
## blocking the doorway.
## Usage: door.take_damage(25, attacker_forward, "knife", player)
func take_damage(amount: int, attack_direction: Vector3 = Vector3.ZERO, _damage_kind: String = "bullet", _attacker: Node = null, _hit_position: Vector3 = Vector3.INF) -> void:
	if amount <= 0 or is_destroyed:
		return
	health = maxi(health - amount, 0)
	set_physics_process(true)
	if health > 0:
		hit_shake_time = HIT_SHAKE_DURATION
		return
	_break_apart(attack_direction, true)


## Applies the authoritative state received from the multiplayer server. The
## very first snapshot only mirrors state (a late joiner must not watch every
## old door explode); later transitions play the break animation.
## Usage: door.apply_network_state(true, false, -1.0)
func apply_network_state(should_open: bool, destroyed: bool, network_swing_direction: float = 0.0) -> void:
	var play_animation := _received_network_state
	_received_network_state = true
	if not is_zero_approx(network_swing_direction):
		swing_direction = signf(network_swing_direction)
	if destroyed and not is_destroyed:
		_break_apart(Vector3.ZERO, play_animation)
	if not destroyed:
		health = max_health
	if is_open != (should_open or destroyed):
		set_physics_process(true)
	is_open = should_open or destroyed


func _break_apart(attack_direction: Vector3, play_animation: bool) -> void:
	health = 0
	is_destroyed = true
	is_open = true
	hit_shake_time = 0.0
	network_state_changed.emit(self)
	var collision := get_node_or_null("DoorCollision") as CollisionShape3D
	if collision != null:
		collision.set_deferred("disabled", true)
	for part_name in ["DoorPanel", "DoorKnob"]:
		var part := get_node_or_null(part_name) as Node3D
		if part != null:
			part.visible = false
	# O servidor dedicado nao renderiza: pular os destrocos poupa CPU.
	if not play_animation or not is_inside_tree() or NetworkSession.is_server():
		return
	var debris = DEBRIS_EFFECT_SCRIPT.new()
	var direction := attack_direction if attack_direction.length_squared() > 0.0001 else -global_transform.basis.z
	debris.configure(panel_size, direction, panel_material, absi(String(get_path()).hash()))
	# Destrocos saem do angulo atual da folha, mesmo que a porta estivesse aberta.
	debris.position = Vector3.ZERO
	add_child(debris)


func _update_hit_shake(delta: float) -> void:
	var panel := _panel_node
	if panel == null:
		return
	hit_shake_time = maxf(hit_shake_time - delta, 0.0)
	var strength := hit_shake_time / HIT_SHAKE_DURATION
	var wobble := sin(hit_shake_time * 90.0) * HIT_SHAKE_AMPLITUDE * strength
	panel.position = _hinge_offset + Vector3(wobble, 0.0, wobble)
	panel.rotation.y = wobble * 0.6


## Macaneta dourada. Se a folha usa o shader de edificio, a macaneta herda a
## mesma regra de visibilidade por andar em vez de flutuar nos andares ocultos.
func _create_knob_material() -> Material:
	if panel_material is ShaderMaterial:
		var shader_knob := (panel_material as ShaderMaterial).duplicate() as ShaderMaterial
		shader_knob.set_shader_parameter("base_color", KNOB_COLOR)
		shader_knob.set_shader_parameter("material_metallic", 0.7)
		return shader_knob
	var standard_knob := StandardMaterial3D.new()
	standard_knob.albedo_color = KNOB_COLOR
	standard_knob.metallic = 0.7
	return standard_knob


func _create_panel() -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "DoorPanel"
	_panel_node = mesh
	var box_mesh := BoxMesh.new()
	box_mesh.size = panel_size
	box_mesh.material = panel_material
	mesh.mesh = box_mesh
	_hinge_offset = Vector3(panel_size.x * 0.5, panel_size.y * 0.5, 0.0) if panel_size.x > panel_size.z else Vector3(0.0, panel_size.y * 0.5, panel_size.z * 0.5)
	mesh.position = _hinge_offset
	add_child(mesh)
	var knob := MeshInstance3D.new()
	knob.name = "DoorKnob"
	var knob_mesh := SphereMesh.new()
	knob_mesh.radius = 0.07
	knob_mesh.height = 0.14
	knob_mesh.material = _create_knob_material()
	knob.mesh = knob_mesh
	if panel_size.z < panel_size.x:
		knob.position = _hinge_offset + Vector3(panel_size.x * 0.28, 0.0, -panel_size.z)
	else:
		knob.position = _hinge_offset + Vector3(-panel_size.x, 0.0, panel_size.z * 0.28)
	add_child(knob)

	var collision := CollisionShape3D.new()
	collision.name = "DoorCollision"
	var shape := BoxShape3D.new()
	shape.size = panel_size
	collision.shape = shape
	collision.position = _hinge_offset
	add_child(collision)
