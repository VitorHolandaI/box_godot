# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
extends Node3D

const LIMB_STATE_SCRIPT: GDScript = preload("res://scripts/zombie_limb_state.gd")

const SKIN_COLOR := Color(0.3, 0.58, 0.24)
const SHIRT_COLOR := Color(0.28, 0.16, 0.12)
const PANTS_COLOR := Color(0.18, 0.2, 0.22)
const EYE_COLOR := Color(0.75, 0.05, 0.04)
# Camada exclusiva dos cadaveres: colide com o mundo (mascara 1) mas nao com
# jogadores nem zumbis, para o corpo no chao nao prender ninguem dentro de casa.
const CORPSE_COLLISION_LAYER := 32

var torso_body: RigidBody3D
## Escala do corpo do zumbi (brute, Tita...). Definida ANTES de entrar na arvore:
## as partes nascem no tamanho certo em _ready. Antes o gigante virava corpo pequeno.
var body_scale := Vector3.ONE
## Cores [pele, tronco, pernas] para um cadaver que NAO e de zumbi — o corpo do
## jogador no mata-mata, pintado na cor do time. Vazio usa a paleta do zumbi
## sorteada pelo appearance_hash. Definir ANTES do setup.
var color_override: Array[Color] = []


## Corpo sai do solver assim que assenta (parado) e, no limite, apos 6s.
## A remocao continua sendo do corpse_cleanup_policy (mantem os 50m).
const SETTLE_FREEZE_TIME := 6.0
const SETTLE_CHECK_DELAY := 1.2
const SETTLE_VELOCITY_SQ := 0.06

var settle_age := 0.0
var froze := false


func _ready() -> void:
	torso_body = _create_torso()
	var head := _create_head()
	_create_limb("LeftArm", Vector3(0.3, 0.84, 0.34), Vector3(-0.56, 0.42, 0.0), SKIN_COLOR, 0.8)
	_create_limb("RightArm", Vector3(0.3, 0.84, 0.34), Vector3(0.56, 0.42, 0.0), SKIN_COLOR, 0.8)
	_create_limb("LeftLeg", Vector3(0.34, 0.84, 0.36), Vector3(-0.2, -0.4, 0.0), PANTS_COLOR, 1.2)
	_create_limb("RightLeg", Vector3(0.34, 0.84, 0.36), Vector3(0.2, -0.4, 0.0), PANTS_COLOR, 1.2)

	_create_neck_joint()
	_create_joint("LeftShoulderJoint", NodePath("../Torso"), NodePath("../LeftArm"), Vector3(-0.56, 0.84, 0.0))
	_create_joint("RightShoulderJoint", NodePath("../Torso"), NodePath("../RightArm"), Vector3(0.56, 0.84, 0.0))
	_create_joint("LeftHipJoint", NodePath("../Torso"), NodePath("../LeftLeg"), Vector3(-0.2, 0.02, 0.0))
	_create_joint("RightHipJoint", NodePath("../Torso"), NodePath("../RightLeg"), Vector3(0.2, 0.02, 0.0))


func _physics_process(delta: float) -> void:
	if froze:
		return
	settle_age += delta
	# Congela cedo quando o corpo ja esta parado (tipico 1-2s); no pior caso,
	# o teto de 6s. Derruba o spike do solver em pico de mortes.
	if settle_age >= SETTLE_FREEZE_TIME:
		_freeze_all()
		return
	if settle_age >= SETTLE_CHECK_DELAY and _all_limbs_still():
		_freeze_all()


func _all_limbs_still() -> bool:
	for child in get_children():
		var limb_body := child as RigidBody3D
		if limb_body != null and is_instance_valid(limb_body) and limb_body.linear_velocity.length_squared() > SETTLE_VELOCITY_SQ:
			return false
	return true


func _freeze_all() -> void:
	froze = true
	for child in get_children():
		var limb_body := child as RigidBody3D
		if limb_body != null and is_instance_valid(limb_body):
			limb_body.freeze = true
		var joint := child as Joint3D
		if joint != null:
			joint.node_a = NodePath()
			joint.node_b = NodePath()


## Sets initial velocity and angular momentum to make the corpse fall realistically.
## Usage:
##   ragdoll.setup(Vector3(0.0, 1.0, -2.5), 0)
func setup(initial_velocity: Vector3, z_type: int = 0, appearance_hash: int = 0, limb_loss_mask: int = 0) -> void:
	_apply_appearance_colors(appearance_hash)
	match z_type:
		1: # ONE_ARM
			_remove_limb_and_joint("LeftArm", "LeftShoulderJoint")
		2: # CRAWLER
			_remove_limb_and_joint("LeftLeg", "LeftHipJoint")
			_remove_limb_and_joint("RightLeg", "RightHipJoint")
			if is_instance_valid(torso_body):
				torso_body.rotation.x = deg_to_rad(55.0)
		5: # HALF_ARM
			_shorten_rigid_limb("LeftArm")
		6: # ONE_LEG
			_remove_limb_and_joint("LeftLeg", "LeftHipJoint")
		7: # HALF_LEG
			_shorten_rigid_limb("RightLeg")
		8: # HALF_HEAD
			var head := get_node_or_null("Head")
			if is_instance_valid(head):
				for child in head.get_children():
					if child is MeshInstance3D and child.position.x > 0.05:
						child.queue_free()
	_apply_limb_loss_mask(limb_loss_mask)

	if is_instance_valid(torso_body):
		torso_body.linear_velocity = initial_velocity * 1.1 + Vector3(
			randf_range(-0.4, 0.4),
			randf_range(0.8, 1.6),
			randf_range(-0.4, 0.4)
		)
		torso_body.angular_velocity = Vector3(
			randf_range(-2.0, 2.0),
			randf_range(-1.0, 1.0),
			randf_range(-2.0, 2.0)
		)
	for child in get_children():
		var limb_body := child as RigidBody3D
		if limb_body == null or limb_body == torso_body:
			continue
		limb_body.linear_velocity = initial_velocity * 0.85 + Vector3(
			randf_range(-0.25, 0.25),
			randf_range(0.3, 0.8),
			randf_range(-0.25, 0.25)
		)


func _apply_appearance_colors(appearance_hash: int) -> void:
	var colors: Array = color_override if color_override.size() == 3 else ZombieMutator.appearance_colors(appearance_hash)
	_set_body_color(torso_body, colors[1])
	_set_body_color(get_node_or_null("Head") as RigidBody3D, colors[0])
	_set_body_color(get_node_or_null("LeftArm") as RigidBody3D, colors[0])
	_set_body_color(get_node_or_null("RightArm") as RigidBody3D, colors[0])
	_set_body_color(get_node_or_null("LeftLeg") as RigidBody3D, colors[2])
	_set_body_color(get_node_or_null("RightLeg") as RigidBody3D, colors[2])


func _set_body_color(body: RigidBody3D, color: Color) -> void:
	if body == null:
		return
	var mesh := body.get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null:
		return
	var material := mesh.mesh.material as StandardMaterial3D
	if material == null:
		return
	material.albedo_color = color


func _remove_limb_and_joint(limb_name: String, joint_name: String) -> void:
	var limb := get_node_or_null(limb_name)
	if is_instance_valid(limb):
		limb.queue_free()
	var joint := get_node_or_null(joint_name)
	if is_instance_valid(joint):
		joint.queue_free()


func _apply_limb_loss_mask(limb_loss_mask: int) -> void:
	if limb_loss_mask & LIMB_STATE_SCRIPT.LEFT_ARM != 0:
		_remove_limb_and_joint("LeftArm", "LeftShoulderJoint")
	if limb_loss_mask & LIMB_STATE_SCRIPT.RIGHT_ARM != 0:
		_remove_limb_and_joint("RightArm", "RightShoulderJoint")
	if limb_loss_mask & LIMB_STATE_SCRIPT.LEFT_LEG != 0:
		_remove_limb_and_joint("LeftLeg", "LeftHipJoint")
	if limb_loss_mask & LIMB_STATE_SCRIPT.RIGHT_LEG != 0:
		_remove_limb_and_joint("RightLeg", "RightHipJoint")


func _shorten_rigid_limb(limb_name: String) -> void:
	var limb := get_node_or_null(limb_name) as RigidBody3D
	if not is_instance_valid(limb):
		return
	limb.scale = Vector3(0.9, 0.5, 0.9)
	limb.mass *= 0.5


## Um tiro no cadaver remove o corpo do chao, evitando montanhas de corpos
## presas dentro de casa. Uso: ragdoll.take_damage(35, Vector3.FORWARD, "bullet")
func take_damage(_amount: int, _attack_direction: Vector3 = Vector3.ZERO, _damage_kind: String = "bullet", _attacker: Node = null, _hit_position: Vector3 = Vector3.INF) -> void:
	if is_queued_for_deletion():
		return
	queue_free()


func _create_torso() -> RigidBody3D:
	var body := _create_rigid_box("Torso", Vector3(0.8, 0.84, 0.42), Vector3(0.0, 0.44, 0.0), SHIRT_COLOR, 3.0)
	return body


func _create_head() -> RigidBody3D:
	var head := _create_rigid_box("Head", Vector3(0.56, 0.56, 0.56), Vector3(0.0, 1.14, 0.0), SKIN_COLOR, 1.0)
	_add_eye(head, Vector3(-0.12, 0.05, -0.285))
	_add_eye(head, Vector3(0.12, 0.05, -0.285))
	return head


func _create_limb(limb_name: String, limb_size: Vector3, limb_offset: Vector3, limb_color: Color, limb_mass: float) -> RigidBody3D:
	return _create_rigid_box(limb_name, limb_size, limb_offset, limb_color, limb_mass)


## Posicao local escalada, subindo junto com os pes (mesma regra do zumbi vivo).
func _scaled(local_position: Vector3) -> Vector3:
	return local_position * body_scale + Vector3.UP * ZombieMutator.MODEL_FEET_Y * (1.0 - body_scale.y)


func _create_rigid_box(node_name: String, base_size: Vector3, base_position: Vector3, color: Color, base_mass: float) -> RigidBody3D:
	var box_size := base_size * body_scale
	var box_position := _scaled(base_position)
	var body := RigidBody3D.new()
	body.name = node_name
	body.mass = base_mass * body_scale.x * body_scale.y * body_scale.z
	body.collision_layer = CORPSE_COLLISION_LAYER
	body.collision_mask = 1
	body.linear_damp = 1.2
	body.angular_damp = 2.4
	body.position = box_position
	add_child(body)

	var shape := BoxShape3D.new()
	shape.size = box_size
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	body.add_child(collision)

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	var mesh := BoxMesh.new()
	mesh.size = box_size
	mesh.material = material
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = mesh
	body.add_child(mesh_instance)
	return body


func _add_eye(parent_body: RigidBody3D, eye_position: Vector3) -> void:
	var eye_material := StandardMaterial3D.new()
	eye_material.albedo_color = EYE_COLOR
	eye_material.emission_enabled = true
	eye_material.emission = Color(0.3, 0.01, 0.0)

	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.08, 0.08, 0.02) * body_scale
	mesh.material = eye_material

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.position = eye_position * body_scale
	parent_body.add_child(mesh_instance)


func _create_neck_joint() -> void:
	var joint := ConeTwistJoint3D.new()
	joint.name = "NeckJoint"
	joint.node_a = NodePath("../Torso")
	joint.node_b = NodePath("../Head")
	joint.position = _scaled(Vector3(0.0, 0.86, 0.0))
	joint.rotation.z = PI * 0.5
	joint.swing_span = deg_to_rad(28.0)
	joint.twist_span = deg_to_rad(35.0)
	joint.softness = 0.6
	joint.relaxation = 1.2
	joint.exclude_nodes_from_collision = true
	add_child(joint)


func _create_joint(joint_name: String, path_a: NodePath, path_b: NodePath, anchor: Vector3) -> void:
	var joint := PinJoint3D.new()
	joint.name = joint_name
	joint.node_a = path_a
	joint.node_b = path_b
	joint.position = _scaled(anchor)
	joint.exclude_nodes_from_collision = true
	add_child(joint)
