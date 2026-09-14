class_name WaveSupplyPickup
extends Area3D

enum SupplyKind { HEALTH, AMMO }

@export var supply_kind := SupplyKind.HEALTH
@export var supply_amount := 30

var is_available := true
var model_root: Node3D
var collision_shape: CollisionShape3D
var elapsed := 0.0


func _ready() -> void:
	add_to_group("wave_supply_pickups")
	collision_layer = 0
	collision_mask = 2
	body_entered.connect(_on_body_entered)
	_build_visuals()
	_build_collision()


func _process(delta: float) -> void:
	if not is_available or model_root == null:
		return
	elapsed += delta
	model_root.rotation.y += delta * 1.4
	model_root.position.y = 0.32 + sin(elapsed * 3.0) * 0.05


## Define a disponibilidade autoritativa do suprimento.
## Uso: pickup.set_available(false)
func set_available(available: bool) -> void:
	is_available = available
	visible = available
	if collision_shape != null:
		collision_shape.set_deferred("disabled", not available)


## Aplica em clientes o estado recebido no snapshot do servidor.
## Uso: pickup.apply_network_state(true)
func apply_network_state(available: bool) -> void:
	set_available(available)


func _on_body_entered(body: Node3D) -> void:
	if not is_available or (not NetworkSession.is_server() and not NetworkSession.is_offline()):
		return
	if not body.is_in_group("player"):
		return
	var received := 0
	if supply_kind == SupplyKind.HEALTH and body.has_method("add_health"):
		received = int(body.call("add_health", supply_amount))
	elif supply_kind == SupplyKind.AMMO and body.has_method("add_ammo"):
		received = int(body.call("add_ammo", supply_amount))
	if received > 0:
		set_available(false)


func _build_visuals() -> void:
	model_root = Node3D.new()
	model_root.name = "Model"
	model_root.position.y = 0.32
	add_child(model_root)
	var primary := StandardMaterial3D.new()
	primary.albedo_color = Color(0.78, 0.12, 0.12) if supply_kind == SupplyKind.HEALTH else Color(0.24, 0.35, 0.18)
	primary.roughness = 0.62
	var bright := StandardMaterial3D.new()
	bright.albedo_color = Color(0.96, 0.96, 0.92) if supply_kind == SupplyKind.HEALTH else Color(0.95, 0.78, 0.12)
	bright.emission_enabled = true
	bright.emission = bright.albedo_color
	bright.emission_energy_multiplier = 0.35
	_add_box(Vector3(0.52, 0.30, 0.38), Vector3.ZERO, primary)
	if supply_kind == SupplyKind.HEALTH:
		_add_box(Vector3(0.30, 0.07, 0.04), Vector3(0.0, 0.0, -0.21), bright)
		_add_box(Vector3(0.07, 0.22, 0.04), Vector3(0.0, 0.0, -0.21), bright)
	else:
		_add_box(Vector3(0.50, 0.05, 0.36), Vector3(0.0, 0.17, 0.0), bright)
	var light := OmniLight3D.new()
	light.light_color = primary.albedo_color.lightened(0.35)
	light.light_energy = 0.55
	light.omni_range = 2.4
	model_root.add_child(light)


func _build_collision() -> void:
	collision_shape = CollisionShape3D.new()
	collision_shape.name = "Collision"
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.9, 0.9, 0.9)
	collision_shape.shape = shape
	collision_shape.position.y = 0.32
	add_child(collision_shape)


func _add_box(size: Vector3, position: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	model_root.add_child(instance)
