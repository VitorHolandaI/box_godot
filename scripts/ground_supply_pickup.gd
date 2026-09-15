class_name GroundSupplyPickup
extends Area3D

## Item de vida/municao espalhado pelo mapa: coleta por tocar (jogador anda
## por cima). Nasce por onda e expira sozinho; replica por nome via
## GroundWeaponSync. Uso:
##   var item := GroundSupplyPickup.new()
##   item.setup(GroundSupplyPickup.Kind.HEALTH, 35)
##   tree.current_scene.add_child(item)

enum Kind { HEALTH, AMMO }

const DEFAULT_LIFETIME := 180.0

var supply_kind := Kind.HEALTH
var amount := 35
## Item some sozinho; contagem roda apenas na autoridade (offline/servidor).
var lifetime_seconds := DEFAULT_LIFETIME
var lifetime_elapsed := 0.0
var model_root: Node3D
var elapsed := 0.0


func setup(kind: int, pickup_amount: int) -> void:
	supply_kind = kind
	amount = pickup_amount


func _ready() -> void:
	add_to_group("ground_supplies")
	collision_layer = 0
	collision_mask = 2
	monitoring = not NetworkSession.is_client()
	body_entered.connect(_on_body_entered)
	_build_visuals()
	_build_collision()


func _physics_process(delta: float) -> void:
	elapsed += delta
	if NetworkSession.is_client():
		return
	lifetime_elapsed += delta
	if lifetime_elapsed >= lifetime_seconds:
		queue_free()
		return
	if model_root != null:
		model_root.position.y = 0.3 + sin(elapsed * 2.6) * 0.05


func _on_body_entered(body: Node3D) -> void:
	if NetworkSession.is_client():
		return
	if not body.is_in_group("player"):
		return
	var received := 0
	if supply_kind == Kind.HEALTH and body.has_method("add_health"):
		received = int(body.call("add_health", amount))
	elif supply_kind == Kind.AMMO and body.has_method("add_ammo"):
		received = int(body.call("add_ammo", amount))
	# Reserva cheia / vida cheia deixa o item no chao para quem precisa.
	if received > 0:
		queue_free()


func _build_visuals() -> void:
	model_root = Node3D.new()
	model_root.name = "Model"
	model_root.position.y = 0.3
	add_child(model_root)
	var is_health := supply_kind == Kind.HEALTH
	var primary := StandardMaterial3D.new()
	primary.albedo_color = Color(0.78, 0.12, 0.12) if is_health else Color(0.24, 0.35, 0.18)
	primary.roughness = 0.6
	var bright := StandardMaterial3D.new()
	bright.albedo_color = Color(0.96, 0.96, 0.92) if is_health else Color(0.95, 0.78, 0.12)
	bright.emission_enabled = true
	bright.emission = bright.albedo_color
	bright.emission_energy_multiplier = 0.4
	_add_box(Vector3(0.4, 0.28, 0.32), Vector3.ZERO, primary)
	if is_health:
		_add_box(Vector3(0.22, 0.06, 0.03), Vector3(0.0, 0.0, -0.17), bright)
		_add_box(Vector3(0.06, 0.2, 0.03), Vector3(0.0, 0.0, -0.17), bright)
	else:
		_add_box(Vector3(0.38, 0.05, 0.3), Vector3(0.0, 0.16, 0.0), bright)
	var light := OmniLight3D.new()
	light.light_color = primary.albedo_color.lightened(0.35)
	light.light_energy = 0.5
	light.omni_range = 2.2
	model_root.add_child(light)


func _build_collision() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	shape.shape = box
	shape.position.y = 0.4
	add_child(shape)


func _add_box(size: Vector3, position: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	model_root.add_child(instance)
