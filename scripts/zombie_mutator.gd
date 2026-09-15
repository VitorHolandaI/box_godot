class_name ZombieMutator
extends RefCounted

## Gerenciador e configurador procedural de variantes anatomicas e mutilacoes de zumbis.
## Suporta 9 variantes com anatomia, amputacoes, materiais e gait visual especificos.

enum Type {
	WALKER = 0,
	ONE_ARM = 1,
	CRAWLER = 2,
	LIMPER = 3,
	SPRINTER = 4,
	HALF_ARM = 5,
	ONE_LEG = 6,
	HALF_LEG = 7,
	HALF_HEAD = 8,
	## Tanque: lento, muita vida e golpe forte; corpo maior.
	BRUTE = 9,
	## Grita periodicamente e atrai a horda pela audicao.
	SCREAMER = 10,
}

const SKIN_PALETTE: Array[Color] = [
	Color(0.28, 0.52, 0.22),
	Color(0.36, 0.44, 0.40),
	Color(0.46, 0.30, 0.26),
	Color(0.22, 0.35, 0.25),
]
const SHIRT_PALETTE: Array[Color] = [
	Color(0.28, 0.16, 0.12),
	Color(0.18, 0.24, 0.32),
	Color(0.48, 0.44, 0.40),
	Color(0.22, 0.26, 0.18),
]
const PANTS_PALETTE: Array[Color] = [
	Color(0.18, 0.20, 0.22),
	Color(0.16, 0.22, 0.30),
	Color(0.32, 0.28, 0.22),
]


## Aplica estetica, paleta de cores e deformacoes anatomicas no zumbi.
## Uso:
##   ZombieMutator.apply_appearance(zombie, ZombieMutator.Type.HALF_ARM, hash_val)
static func apply_appearance(zombie: CharacterBody3D, z_type: int, hash_val: int) -> void:
	_apply_materials(zombie, hash_val)
	_apply_anatomy(zombie, z_type)


static func appearance_colors(hash_val: int) -> Array[Color]:
	return [
		SKIN_PALETTE[(hash_val / 5) % SKIN_PALETTE.size()],
		SHIRT_PALETTE[(hash_val / 20) % SHIRT_PALETTE.size()],
		PANTS_PALETTE[(hash_val / 80) % PANTS_PALETTE.size()],
	]


static func _apply_materials(zombie: CharacterBody3D, hash_val: int) -> void:
	var skin_mat := _quick_mat(SKIN_PALETTE[(hash_val / 5) % SKIN_PALETTE.size()], 0.9)
	var shirt_mat := _quick_mat(SHIRT_PALETTE[(hash_val / 20) % SHIRT_PALETTE.size()], 0.95)
	var pants_mat := _quick_mat(PANTS_PALETTE[(hash_val / 80) % PANTS_PALETTE.size()], 0.95)

	var head := zombie.get_node_or_null("Model/Head") as MeshInstance3D
	var torso := zombie.get_node_or_null("Model/Torso") as MeshInstance3D
	var left_arm := zombie.get_node_or_null("Model/LeftArm/Mesh") as MeshInstance3D
	var right_arm := zombie.get_node_or_null("Model/RightArm/Mesh") as MeshInstance3D
	var left_leg := zombie.get_node_or_null("Model/LeftLeg/Mesh") as MeshInstance3D
	var right_leg := zombie.get_node_or_null("Model/RightLeg/Mesh") as MeshInstance3D

	if head != null:
		head.material_override = skin_mat
	if torso != null:
		torso.material_override = shirt_mat
	if left_arm != null:
		left_arm.material_override = skin_mat
	if right_arm != null:
		right_arm.material_override = skin_mat
	if left_leg != null:
		left_leg.material_override = pants_mat
	if right_leg != null:
		right_leg.material_override = pants_mat


static func _apply_anatomy(zombie: CharacterBody3D, z_type: int) -> void:
	var model := zombie.get_node_or_null("Model") as Node3D
	if model == null:
		return

	match z_type:
		Type.ONE_ARM:
			zombie.set("speed", 2.0)
			zombie.set("max_health", 85)
			_hide_node(zombie, "Model/LeftArm/Mesh")
			_create_stump(zombie.get_node_or_null("Model/LeftArm") as Node3D, Vector3(0.0, -0.1, 0.0))
		Type.HALF_ARM:
			zombie.set("speed", 2.1)
			zombie.set("max_health", 90)
			_shorten_limb(zombie, "Model/LeftArm/Mesh")
			_create_stump(zombie.get_node_or_null("Model/LeftArm") as Node3D, Vector3(0.0, -0.42, 0.0))
		Type.CRAWLER:
			_setup_crawler(zombie, model)
		Type.LIMPER:
			zombie.set("speed", 1.65)
			zombie.set("max_health", 90)
			var r_leg := zombie.get_node_or_null("Model/RightLeg") as Node3D
			if r_leg != null:
				r_leg.rotation.z = deg_to_rad(10.0)
			model.rotation.z = deg_to_rad(8.0)
		Type.SPRINTER:
			zombie.set("speed", 3.1)
			zombie.set("max_health", 70)
			model.rotation.x = deg_to_rad(15.0)
		Type.ONE_LEG:
			zombie.set("speed", 1.5)
			zombie.set("max_health", 80)
			_hide_node(zombie, "Model/LeftLeg/Mesh")
			_create_stump(zombie.get_node_or_null("Model/LeftLeg") as Node3D, Vector3(0.0, -0.05, 0.0))
		Type.HALF_LEG:
			zombie.set("speed", 1.6)
			zombie.set("max_health", 85)
			_shorten_limb(zombie, "Model/RightLeg/Mesh")
			_create_stump(zombie.get_node_or_null("Model/RightLeg") as Node3D, Vector3(0.0, -0.42, 0.0))
			model.rotation.z = deg_to_rad(7.0)
		Type.HALF_HEAD:
			zombie.set("speed", 2.3)
			zombie.set("max_health", 95)
			_create_split_head(zombie)
		Type.BRUTE:
			zombie.set("speed", 1.15)
			zombie.set("max_health", 320)
			zombie.set("attack_damage", 26)
			_setup_brute(model)
		Type.SCREAMER:
			zombie.set("speed", 2.4)
			zombie.set("max_health", 85)
			_setup_screamer(zombie)
		Type.WALKER:
			zombie.set("speed", 2.2)
			zombie.set("max_health", 100)


static func _setup_crawler(zombie: CharacterBody3D, model: Node3D) -> void:
	zombie.set("speed", 1.4)
	zombie.set("max_health", 75)
	model.position.y = -0.45
	model.rotation.x = deg_to_rad(65.0)
	var head := zombie.get_node_or_null("Model/Head") as Node3D
	if head != null:
		head.rotation.x = deg_to_rad(-50.0)
	var col_shape := zombie.get_node_or_null("CollisionShape") as CollisionShape3D
	if col_shape != null:
		col_shape.position = Vector3(0.0, -0.3, 0.0)
	var health_lbl := zombie.get_node_or_null("HealthLabel") as Label3D
	if health_lbl != null:
		health_lbl.position.y = 0.95


## Brute: corpo maior e ombreiras de paletizado escuro para leitura imediata.
static func _setup_brute(model: Node3D) -> void:
	if model != null:
		model.scale = Vector3(1.35, 1.25, 1.35)
	var head := model.get_node_or_null("Head") as Node3D
	if head != null:
		head.scale = Vector3(1.2, 1.15, 1.2)
	var health_label := model.get_parent().get_node_or_null("HealthLabel") as Label3D
	if health_label != null:
		health_label.position.y += 0.55


## Screamer: tronco vermelho vivo e mandibula aberta, para ser reconhecido
## antes do grito. Uso: chamado por apply_appearance no spawn.
static func _setup_screamer(zombie: CharacterBody3D) -> void:
	var torso := zombie.get_node_or_null("Model/Torso") as MeshInstance3D
	if torso != null:
		torso.material_override = _quick_mat(Color(0.55, 0.08, 0.08), 0.9)
	var head := zombie.get_node_or_null("Model/Head") as Node3D
	if head != null:
		head.rotation.x = deg_to_rad(-12.0)
		_add_box(head, Vector3(0.2, 0.12, 0.16), Vector3(0.0, -0.14, -0.24), Color(0.75, 0.72, 0.65))


static func _hide_node(parent: Node, path: String) -> void:
	var node := parent.get_node_or_null(path) as Node3D
	if node != null:
		node.visible = false


static func _shorten_limb(parent: Node, path: String) -> void:
	var mesh := parent.get_node_or_null(path) as MeshInstance3D
	if mesh != null:
		mesh.scale = Vector3(0.9, 0.48, 0.9)
		mesh.position = Vector3(0.0, -0.21, 0.0)


static func _create_stump(parent: Node3D, pos: Vector3) -> void:
	if parent == null:
		return
	_add_box(parent, Vector3(0.28, 0.16, 0.28), pos, Color(0.55, 0.07, 0.08))
	_add_box(parent, Vector3(0.09, 0.16, 0.09), pos + Vector3(0.0, -0.09, 0.0), Color(0.88, 0.86, 0.80))


static func _create_split_head(zombie: CharacterBody3D) -> void:
	var head := zombie.get_node_or_null("Model/Head") as Node3D
	if head == null:
		return
	var right_eye := head.get_node_or_null("RightEye") as Node3D
	if right_eye != null:
		right_eye.visible = false

	# Cerebro exposto e cavidade craniana lacerada
	_add_box(head, Vector3(0.22, 0.36, 0.42), Vector3(0.15, 0.10, -0.02), Color(0.50, 0.05, 0.07))
	_add_box(head, Vector3(0.16, 0.10, 0.36), Vector3(0.16, 0.24, -0.02), Color(0.68, 0.10, 0.12))
	_add_box(head, Vector3(0.04, 0.38, 0.44), Vector3(0.02, 0.10, -0.02), Color(0.84, 0.82, 0.76))


static func _add_box(parent: Node3D, box_size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	mesh.material = _quick_mat(color, 0.85)
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.position = pos
	parent.add_child(inst)
	return inst


static func _quick_mat(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat


## Atualiza as poses e a locomocao de acordo com a variante anatomica.
## Uso:
##   ZombieMutator.animate_variant_pose(zombie, z_type, delta, is_walking, attack_w, walk_time)
static func animate_variant_pose(
	zombie: CharacterBody3D,
	z_type: int,
	delta: float,
	is_walking: bool,
	attack_w: float,
	walk_time: float
) -> void:
	var left_arm := zombie.get_node_or_null("Model/LeftArm") as Node3D
	var right_arm := zombie.get_node_or_null("Model/RightArm") as Node3D
	var left_leg := zombie.get_node_or_null("Model/LeftLeg") as Node3D
	var right_leg := zombie.get_node_or_null("Model/RightLeg") as Node3D
	var model := zombie.get_node_or_null("Model") as Node3D
	var head := zombie.get_node_or_null("Model/Head") as Node3D

	if left_arm == null or right_arm == null or left_leg == null or right_leg == null or model == null:
		return

	var swing := sin(walk_time) * 0.52 if is_walking else 0.0

	match z_type:
		Type.CRAWLER:
			var crawl := sin(walk_time) * 0.6 if is_walking else 0.0
			left_arm.rotation.x = lerpf(left_arm.rotation.x, -0.65 + crawl + attack_w * 0.8, minf(delta * 12.0, 1.0))
			right_arm.rotation.x = lerpf(right_arm.rotation.x, -0.65 - crawl + attack_w * 0.8, minf(delta * 12.0, 1.0))
			var leg_drag := 1.45 + (sin(walk_time) * 0.08 if is_walking else 0.0)
			left_leg.rotation.x = lerpf(left_leg.rotation.x, leg_drag, minf(delta * 8.0, 1.0))
			right_leg.rotation.x = lerpf(right_leg.rotation.x, leg_drag + 0.05, minf(delta * 8.0, 1.0))
		Type.LIMPER, Type.HALF_LEG:
			var step := -sin(walk_time) * 0.55 if is_walking else 0.0
			left_leg.rotation.x = lerpf(left_leg.rotation.x, step, minf(delta * 10.0, 1.0))
			right_leg.rotation.x = lerpf(right_leg.rotation.x, 0.72 + (sin(walk_time) * 0.12 if is_walking else 0.0), minf(delta * 8.0, 1.0))
			model.position.y = lerpf(model.position.y, sin(walk_time) * -0.12 if is_walking else 0.0, minf(delta * 12.0, 1.0))
			left_arm.rotation.x = lerpf(left_arm.rotation.x, lerpf(step, 1.6, attack_w), minf(delta * 16.0, 1.0))
			right_arm.rotation.x = lerpf(right_arm.rotation.x, 0.18 + attack_w * 1.2, minf(delta * 12.0, 1.0))
		Type.ONE_ARM:
			right_arm.rotation.x = lerpf(right_arm.rotation.x, lerpf(-swing, 1.65, attack_w), minf(delta * 18.0, 1.0))
			left_leg.rotation.x = lerpf(left_leg.rotation.x, -swing, minf(delta * 10.0, 1.0))
			right_leg.rotation.x = lerpf(right_leg.rotation.x, swing, minf(delta * 10.0, 1.0))
		Type.HALF_ARM:
			right_arm.rotation.x = lerpf(right_arm.rotation.x, lerpf(-swing, 1.68, attack_w), minf(delta * 18.0, 1.0))
			var stump_flail := sin(walk_time * 1.8) * 0.35 + 0.3 if is_walking else 0.2
			left_arm.rotation.x = lerpf(left_arm.rotation.x, lerpf(stump_flail, 1.3, attack_w), minf(delta * 18.0, 1.0))
			left_leg.rotation.x = lerpf(left_leg.rotation.x, -swing, minf(delta * 10.0, 1.0))
			right_leg.rotation.x = lerpf(right_leg.rotation.x, swing, minf(delta * 10.0, 1.0))
		Type.ONE_LEG:
			var hop := sin(walk_time * 1.5) * 0.6 if is_walking else 0.0
			right_leg.rotation.x = lerpf(right_leg.rotation.x, hop, minf(delta * 14.0, 1.0))
			var hop_bob := absf(sin(walk_time * 1.5)) * 0.16 - 0.05 if is_walking else 0.0
			model.position.y = lerpf(model.position.y, hop_bob, minf(delta * 14.0, 1.0))
			left_arm.rotation.x = lerpf(left_arm.rotation.x, lerpf(hop * 0.8, 1.5, attack_w), minf(delta * 16.0, 1.0))
			right_arm.rotation.x = lerpf(right_arm.rotation.x, lerpf(-hop * 0.8, 1.5, attack_w), minf(delta * 16.0, 1.0))
		Type.HALF_HEAD:
			left_arm.rotation.x = lerpf(left_arm.rotation.x, lerpf(swing, 1.65, attack_w), minf(delta * 18.0, 1.0))
			right_arm.rotation.x = lerpf(right_arm.rotation.x, lerpf(-swing, 1.65, attack_w), minf(delta * 18.0, 1.0))
			left_leg.rotation.x = lerpf(left_leg.rotation.x, -swing, minf(delta * 10.0, 1.0))
			right_leg.rotation.x = lerpf(right_leg.rotation.x, swing, minf(delta * 10.0, 1.0))
			if head != null:
				var twitch := sin(walk_time * 2.8) * 0.12 if is_walking else 0.0
				head.rotation.z = lerpf(head.rotation.z, deg_to_rad(12.0) + twitch, minf(delta * 15.0, 1.0))
		Type.SPRINTER:
			var run_swing := sin(walk_time) * 0.78 if is_walking else 0.0
			left_arm.rotation.x = lerpf(left_arm.rotation.x, lerpf(run_swing, 1.7, attack_w), minf(delta * 20.0, 1.0))
			right_arm.rotation.x = lerpf(right_arm.rotation.x, lerpf(-run_swing, 1.7, attack_w), minf(delta * 20.0, 1.0))
			left_leg.rotation.x = lerpf(left_leg.rotation.x, -run_swing * 1.1, minf(delta * 14.0, 1.0))
			right_leg.rotation.x = lerpf(right_leg.rotation.x, run_swing * 1.1, minf(delta * 14.0, 1.0))
		_:
			left_arm.rotation.x = lerpf(left_arm.rotation.x, lerpf(swing, 1.65, attack_w), minf(delta * 18.0, 1.0))
			right_arm.rotation.x = lerpf(right_arm.rotation.x, lerpf(-swing, 1.65, attack_w), minf(delta * 18.0, 1.0))
			left_leg.rotation.x = lerpf(left_leg.rotation.x, -swing, minf(delta * 10.0, 1.0))
			right_leg.rotation.x = lerpf(right_leg.rotation.x, swing, minf(delta * 10.0, 1.0))


## Aplica animacao de impacto / flinch no zumbi quando recebe dano.
## Uso:
##   ZombieMutator.animate_hit_reaction(zombie, delta, hit_time, 0.24, hit_dir, "bullet", z_type, attack_w)
static func animate_hit_reaction(
	zombie: CharacterBody3D,
	delta: float,
	hit_time: float,
	duration: float,
	hit_dir: Vector3,
	hit_kind: String,
	z_type: int,
	attack_w: float
) -> void:
	var model := zombie.get_node_or_null("Model") as Node3D
	var head := zombie.get_node_or_null("Model/Head") as Node3D
	if model == null:
		return

	var hit_weight := sin((1.0 - hit_time / duration) * PI) if hit_time > 0.0 else 0.0
	var target_x := -0.45 * hit_weight if hit_kind == "bullet" else -0.18 * attack_w
	var target_z := -hit_dir.x * 0.42 * hit_weight if hit_kind == "knife" else -hit_dir.x * 0.25 * hit_weight

	if z_type == Type.CRAWLER:
		target_x += deg_to_rad(65.0)
	elif z_type == Type.SPRINTER:
		target_x += deg_to_rad(15.0)
	elif z_type == Type.LIMPER or z_type == Type.HALF_LEG:
		target_z += deg_to_rad(8.0)

	model.rotation.x = lerpf(model.rotation.x, target_x, minf(delta * 20.0, 1.0))
	model.rotation.z = lerpf(model.rotation.z, target_z, minf(delta * 20.0, 1.0))
	model.position.z = lerpf(model.position.z, 0.14 * hit_weight, minf(delta * 20.0, 1.0))

	if head != null:
		var head_x := -0.48 * hit_weight if hit_time > 0.0 else (deg_to_rad(-50.0) if z_type == Type.CRAWLER else 0.0)
		head.rotation.x = lerpf(head.rotation.x, head_x, minf(delta * 22.0, 1.0))
