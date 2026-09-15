class_name AirSupplyPickup
extends Area3D

## Crate de airdrop: desce de paraquedas com varias armas, coleta por
## interacao. Grupo "ground_weapons" (mesma interacao das armas dropadas);
## replica por nome via GroundWeaponSync.
## Uso:
##   var crate := AirSupplyPickup.new()
##   crate.name = "AirCrate3"
##   crate.setup([WeaponStats.Kind.SHOTGUN, WeaponStats.Kind.UZI])

var weapon_kinds: Array[int] = []
var dropped := false
## Crates restauradas pelo sync chegam no nivel do chao: sem nova queda.
var starts_landed := false
## Crate fica marcado no minimapa e expira em 10 minutos sem coleta.
var lifetime_seconds := 600.0
var lifetime_elapsed := 0.0
var model_root: Node3D
var parachute_root: Node3D
var elapsed := 0.0

const DESCEND_SPEED := 6.0
const DROP_HEIGHT := 26.0


func setup(kinds: Array[int]) -> void:
	weapon_kinds = kinds.duplicate()


func _ready() -> void:
	add_to_group("ground_weapons")
	collision_layer = 0
	collision_mask = 2
	monitoring = not NetworkSession.is_client()
	if not starts_landed:
		position.y += DROP_HEIGHT
	else:
		dropped = true
	_build_visuals()
	_build_collision()


func _physics_process(delta: float) -> void:
	elapsed += delta
	if not dropped:
		position.y -= DESCEND_SPEED * delta
		if position.y <= 0.02:
			position.y = 0.02
			dropped = true
			parachute_root.visible = false
			return
		_update_parachute_sway(delta)
		return
	# Expiracao so na autoridade (offline/servidor); no cliente o no some
	# quando o sync por nome nota a remocao no servidor.
	if not NetworkSession.is_client():
		lifetime_elapsed += delta
		if lifetime_elapsed >= lifetime_seconds:
			queue_free()
			return
	if model_root != null:
		model_root.rotation.y += delta * 0.6


func _update_parachute_sway(delta: float) -> void:
	if parachute_root == null:
		return
	parachute_root.rotation.y += delta * 1.2
	parachute_root.rotation.z = sin(elapsed * 2.0) * 0.08


## Coleta por interacao: entrega UMA arma por interacao (arma repetida vira
## municao); as demais ficam no crate para a proxima pegada.
## Uso: crate.interact_with(player)
func interact_with(player: Node) -> void:
	for kind in weapon_kinds:
		var result := String(player.call("take_crate_weapon", kind))
		if result != "full":
			weapon_kinds.erase(kind)
			break
	if weapon_kinds.is_empty():
		queue_free()


func _build_visuals() -> void:
	model_root = Node3D.new()
	model_root.name = "Model"
	model_root.position.y = 0.4
	add_child(model_root)
	var crate_mat := StandardMaterial3D.new()
	crate_mat.albedo_color = Color(0.45, 0.32, 0.16)
	crate_mat.roughness = 0.7
	var strap_mat := StandardMaterial3D.new()
	strap_mat.albedo_color = Color(0.9, 0.75, 0.1)
	strap_mat.emission_enabled = true
	strap_mat.emission = strap_mat.albedo_color
	strap_mat.emission_energy_multiplier = 0.35
	_add_box(Vector3(0.9, 0.6, 0.7), Vector3.ZERO, crate_mat)
	_add_box(Vector3(0.94, 0.08, 0.74), Vector3(0.0, 0.0, 0.0), strap_mat)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.3)
	light.light_energy = 0.8
	light.omni_range = 3.0
	model_root.add_child(light)
	_build_parachute()


func _build_parachute() -> void:
	parachute_root = Node3D.new()
	parachute_root.name = "Parachute"
	parachute_root.position.y = 1.6
	add_child(parachute_root)
	var canopy_mat := StandardMaterial3D.new()
	canopy_mat.albedo_color = Color(0.85, 0.2, 0.15)
	canopy_mat.roughness = 0.8
	var canopy := MeshInstance3D.new()
	var dome := BoxMesh.new()
	dome.size = Vector3(2.2, 0.28, 2.2)
	canopy.mesh = dome
	canopy.material_override = canopy_mat
	canopy.position.y = 0.6
	parachute_root.add_child(canopy)
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.85, 0.85, 0.85)
	for offset_x in [-0.8, 0.8]:
		for offset_z in [-0.5, 0.5]:
			var line := MeshInstance3D.new()
			var line_mesh := BoxMesh.new()
			line_mesh.size = Vector3(0.03, 1.3, 0.03)
			line.mesh = line_mesh
			line.material_override = line_mat
			line.position = Vector3(offset_x * 0.5, -0.2, offset_z)
			line.rotation.x = atan2(offset_z * 0.4, 1.6)
			line.rotation.z = -atan(offset_x * 1.2 / 1.6)
			parachute_root.add_child(line)


func _build_collision() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 1.2, 1.2)
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
