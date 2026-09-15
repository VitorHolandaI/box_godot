class_name GroundWeaponPickup
extends Area3D

## Arma dropada no chao (pelo jogador ou reutilizada pelo airdrop). Pega por
## interacao (tecla interact) dentro de um raio curto; nunca por colisao
## automatica. Replica por nome via GroundWeaponSync.
## Uso:
##   var pickup := GroundWeaponPickup.new()
##   pickup.setup(WeaponStats.Kind.UZI, 22, 80, 95)
##   tree.current_scene.add_child(pickup)

const KIND_COLORS: Dictionary = {
	WeaponStats.Kind.SHOTGUN: Color(0.55, 0.36, 0.14),
	WeaponStats.Kind.UZI: Color(0.16, 0.17, 0.2),
	WeaponStats.Kind.MAGNUM: Color(0.3, 0.1, 0.12),
}

var weapon_kind := WeaponStats.Kind.SHOTGUN
var mag := 0
var reserve := 0
var durability := 0
var model_root: Node3D
var elapsed := 0.0


func setup(kind: int, weapon_mag: int, weapon_reserve: int, weapon_durability: int) -> void:
	weapon_kind = kind
	mag = weapon_mag
	reserve = weapon_reserve
	durability = weapon_durability


func _ready() -> void:
	add_to_group("ground_weapons")
	collision_layer = 0
	collision_mask = 2
	monitoring = false
	monitorable = true
	_build_visuals()
	_build_collision()


func _process(delta: float) -> void:
	elapsed += delta
	if model_root != null:
		model_root.position.y = 0.32 + sin(elapsed * 2.4) * 0.04


## Coleta por interacao: retorna "granted"/"merged"/"full"; o chamador remove
## o no so quando a arma saiu do chao. Uso: var r := pickup.interact_with(player)
func interact_with(player: Node) -> String:
	var result: String = player.call("take_ground_weapon", weapon_kind, mag, reserve, durability)
	if result != "full":
		queue_free()
	return result


func _build_visuals() -> void:
	model_root = Node3D.new()
	model_root.name = "Model"
	model_root.position.y = 0.32
	add_child(model_root)
	var body := StandardMaterial3D.new()
	body.albedo_color = KIND_COLORS.get(weapon_kind, Color(0.2, 0.2, 0.2))
	body.roughness = 0.5
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.95, 0.78, 0.12)
	accent.emission_enabled = true
	accent.emission = accent.albedo_color
	accent.emission_energy_multiplier = 0.4
	_add_box(Vector3(0.46, 0.14, 0.14), Vector3.ZERO, body)
	_add_box(Vector3(0.1, 0.16, 0.1), Vector3(0.0, -0.08, 0.0), accent)
	var light := OmniLight3D.new()
	light.light_color = accent.albedo_color
	light.light_energy = 0.5
	light.omni_range = 2.2
	model_root.add_child(light)


func _build_collision() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.9, 0.9, 0.9)
	shape.shape = box
	shape.position.y = 0.32
	add_child(shape)


func _add_box(size: Vector3, position: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	model_root.add_child(instance)
