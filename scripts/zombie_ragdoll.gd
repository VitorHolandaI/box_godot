extends Node3D

const SKIN_COLOR := Color(0.3, 0.58, 0.24)
const SHIRT_COLOR := Color(0.28, 0.16, 0.12)
const PANTS_COLOR := Color(0.18, 0.2, 0.22)
const EYE_COLOR := Color(0.75, 0.05, 0.04)

var torso_body: RigidBody3D


func _ready() -> void:
	torso_body = _create_torso()
	var head := _create_head()
	var left_arm := _create_limb("LeftArm", Vector3(0.3, 0.84, 0.34), Vector3(-0.56, 0.42, 0.0), SKIN_COLOR, 0.8)
	var right_arm := _create_limb("RightArm", Vector3(0.3, 0.84, 0.34), Vector3(0.56, 0.42, 0.0), SKIN_COLOR, 0.8)
	var left_leg := _create_limb("LeftLeg", Vector3(0.34, 0.84, 0.36), Vector3(-0.2, -0.4, 0.0), PANTS_COLOR, 1.2)
	var right_leg := _create_limb("RightLeg", Vector3(0.34, 0.84, 0.36), Vector3(0.2, -0.4, 0.0), PANTS_COLOR, 1.2)

	_create_neck_joint()
	_create_joint("LeftShoulderJoint", NodePath("../Torso"), NodePath("../LeftArm"), Vector3(-0.56, 0.84, 0.0))
	_create_joint("RightShoulderJoint", NodePath("../Torso"), NodePath("../RightArm"), Vector3(0.56, 0.84, 0.0))
	_create_joint("LeftHipJoint", NodePath("../Torso"), NodePath("../LeftLeg"), Vector3(-0.2, 0.02, 0.0))
	_create_joint("RightHipJoint", NodePath("../Torso"), NodePath("../RightLeg"), Vector3(0.2, 0.02, 0.0))


## Sets initial velocity and angular momentum to make the corpse fall realistically.
## Usage:
##   ragdoll.setup(Vector3(0.0, 1.0, -2.5), 0)
func setup(initial_velocity: Vector3, z_type: int = 0) -> void:
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


func _remove_limb_and_joint(limb_name: String, joint_name: String) -> void:
	var limb := get_node_or_null(limb_name)
	if is_instance_valid(limb):
		limb.queue_free()
	var joint := get_node_or_null(joint_name)
	if is_instance_valid(joint):
		joint.queue_free()


func _shorten_rigid_limb(limb_name: String) -> void:
	var limb := get_node_or_null(limb_name) as RigidBody3D
	if not is_instance_valid(limb):
		return
	limb.scale = Vector3(0.9, 0.5, 0.9)
	limb.mass *= 0.5


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


func _create_rigid_box(node_name: String, box_size: Vector3, box_position: Vector3, color: Color, mass_value: float) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = node_name
	body.mass = mass_value
	body.collision_layer = 4
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
	mesh.size = Vector3(0.08, 0.08, 0.02)
	mesh.material = eye_material

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.position = eye_position
	parent_body.add_child(mesh_instance)


func _create_neck_joint() -> void:
	var joint := ConeTwistJoint3D.new()
	joint.name = "NeckJoint"
	joint.node_a = NodePath("../Torso")
	joint.node_b = NodePath("../Head")
	joint.position = Vector3(0.0, 0.86, 0.0)
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
	joint.position = anchor
	joint.exclude_nodes_from_collision = true
	add_child(joint)
