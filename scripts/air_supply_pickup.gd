class_name AirSupplyPickup
extends RigidBody3D

## Crate de airdrop estilo battle royale: caixa GRANDE que cai de paraquedas
## com fisica, bate no chao e abre espalhando as armas ao redor como pickups
## interativos (pega uma de cada vez, as outras continuam no chao).
## Grupo "ground_weapons" (interacao por proximidade); replica por nome via
## GroundWeaponSync. Uso:
##   var crate := AirSupplyPickup.new()
##   crate.setup([WeaponStats.Kind.SHOTGUN, WeaponStats.Kind.UZI])

const KIND_COLORS: Dictionary = {
	WeaponStats.Kind.SHOTGUN: Color(0.55, 0.36, 0.14),
	WeaponStats.Kind.UZI: Color(0.16, 0.17, 0.2),
	WeaponStats.Kind.MAGNUM: Color(0.3, 0.1, 0.12),
}

const DROP_HEIGHT := 24.0
const DESCEND_SPEED := 5.0
## Altura de repouso do corpo rigido no chao (metade da altura da caixa).
const REST_HEIGHT := 0.7
const EJECT_RADIUS := 1.5
## Crate marcada no minimapa e expira em 10 minutos sem coleta.
const DEFAULT_LIFETIME := 600.0

var weapon_kinds: Array[int] = []
var dropped := false
## Crates restauradas pelo sync chegam no nivel do chao: sem nova queda.
var starts_landed := false
## Expiracao configuravel (testes usam valores curtos).
var lifetime_seconds := DEFAULT_LIFETIME
var model_root: Node3D
var parachute_root: Node3D
var elapsed := 0.0
var lifetime_elapsed := 0.0


func setup(kinds: Array[int]) -> void:
	weapon_kinds = kinds.duplicate()


func _ready() -> void:
	add_to_group("ground_weapons")
	# Corpo rigido de verdade: cai, bate e fica. Nao colide com jogador
	# (layer 16) para ninguem prender dentro do crate.
	collision_layer = 16
	collision_mask = 1
	lock_rotation = true
	linear_damp = 0.5
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	if not starts_landed:
		position.y += DROP_HEIGHT
	else:
		land()
	_build_visuals()
	_build_collision()


func _physics_process(delta: float) -> void:
	elapsed += delta
	# Expiracao so na autoridade (offline/servidor); no cliente o no some
	# quando o sync por nome nota a remocao no servidor.
	if not NetworkSession.is_client():
		lifetime_elapsed += delta
		if lifetime_elapsed >= lifetime_seconds:
			GroundWeaponSync.mark_dirty()
			queue_free()
			return
	if dropped:
		if model_root != null:
			model_root.rotation.y += delta * 0.6
		return
	# Queda controlada: desce lento com o paraquedas balancando ate o chao.
	position.y -= DESCEND_SPEED * delta
	_update_parachute_sway(delta)
	if position.y <= REST_HEIGHT:
		land()


## Aterrissou: congela a caixa, guarda o paraquedas e ejeta as armas ao redor
## (apenas na autoridade; clientes recebem os pickups pelo sync por nome).
func land() -> void:
	if dropped:
		return
	dropped = true
	freeze = true
	if parachute_root != null:
		parachute_root.visible = false
	if not NetworkSession.is_client():
		_eject_weapons()


func _eject_weapons() -> void:
	# Cada arma vira um pickup independente no chao: escolhe qual quero, uma
	# por interacao. Crate fica como marco (sem armas) ate expirar.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var scene_root := get_tree().current_scene
	var count: int = weapon_kinds.size()
	for index in count:
		var pickup := GroundWeaponPickup.new()
		pickup.name = "CrateWeapon%d" % (Time.get_ticks_usec() % 100000 + index)
		var state := _full_state_for(weapon_kinds[index])
		pickup.setup(weapon_kinds[index], int(state["mag"]), int(state["reserve"]), int(state["durability"]))
		scene_root.add_child(pickup)
		var angle := TAU * float(index) / float(maxi(count, 1)) + rng.randf_range(-0.4, 0.4)
		var radius := EJECT_RADIUS + rng.randf_range(0.0, 0.5)
		var offset := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		pickup.global_position = global_position + offset
	weapon_kinds.clear()
	GroundWeaponSync.mark_dirty()


func _update_parachute_sway(delta: float) -> void:
	if parachute_root == null:
		return
	parachute_root.rotation.y += delta * 1.2
	parachute_root.rotation.z = sin(elapsed * 2.0) * 0.08
	parachute_root.position.x = sin(elapsed * 1.3) * 0.15


## Coleta por interacao: agora as armas ficam espalhadas no chao ao redor da
## caixa; a caixa em si nao entrega nada (nao aparece para o botao E).
func interact_with(_player: Node) -> void:
	pass


func _build_visuals() -> void:
	model_root = Node3D.new()
	model_root.name = "Model"
	model_root.position.y = 0.0
	add_child(model_root)
	var crate_mat := StandardMaterial3D.new()
	crate_mat.albedo_color = Color(0.45, 0.32, 0.16)
	crate_mat.roughness = 0.7
	var strap_mat := StandardMaterial3D.new()
	strap_mat.albedo_color = Color(0.9, 0.75, 0.1)
	strap_mat.emission_enabled = true
	strap_mat.emission = strap_mat.albedo_color
	strap_mat.emission_energy_multiplier = 0.35
	_add_box(Vector3(1.8, 1.2, 1.4), Vector3.ZERO, crate_mat)
	_add_box(Vector3(1.86, 0.14, 1.46), Vector3(0.0, 0.0, 0.0), strap_mat)
	_add_box(Vector3(1.86, 0.14, 1.46), Vector3(0.0, 0.42, 0.0), crate_mat)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.3)
	light.light_energy = 1.0
	light.omni_range = 4.0
	light.position.y = 0.9
	model_root.add_child(light)
	_build_parachute()


func _build_parachute() -> void:
	parachute_root = Node3D.new()
	parachute_root.name = "Parachute"
	parachute_root.position.y = 2.0
	add_child(parachute_root)
	var canopy_mat := StandardMaterial3D.new()
	canopy_mat.albedo_color = Color(0.85, 0.2, 0.15)
	canopy_mat.roughness = 0.8
	var canopy := MeshInstance3D.new()
	var dome := BoxMesh.new()
	dome.size = Vector3(2.8, 0.32, 2.8)
	canopy.mesh = dome
	canopy.material_override = canopy_mat
	canopy.position.y = 0.7
	parachute_root.add_child(canopy)
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.85, 0.85, 0.85)
	for offset_x in [-1.0, 1.0]:
		for offset_z in [-0.7, 0.7]:
			var line := MeshInstance3D.new()
			var line_mesh := BoxMesh.new()
			line_mesh.size = Vector3(0.04, 1.6, 0.03)
			line.mesh = line_mesh
			line.material_override = line_mat
			line.position = Vector3(offset_x * 0.5, -0.25, offset_z * 0.5)
			line.rotation.x = atan2(offset_z * 0.5, 2.1)
			line.rotation.z = -atan(offset_x * 0.9 / 2.0)
			parachute_root.add_child(line)


func _build_collision() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.8, 1.2, 1.4)
	shape.shape = box
	shape.position.y = 0.6
	add_child(shape)


func _add_box(size: Vector3, position: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	model_root.add_child(instance)


func _full_state_for(kind: int) -> Dictionary:
	var stats := WeaponStats.stats_for(kind)
	return {"mag": stats["mag_size"], "reserve": stats["grant_reserve"], "durability": stats["max_durability"]}
