# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name AmmoPickup
extends Area3D

const RESPAWN_DELAY := 30.0
const DEFAULT_AMMO := 24

@export var ammo_amount := DEFAULT_AMMO
@export var respawns := true

var is_collected := false
var respawn_timer := 0.0
var elapsed := 0.0
var base_y := 0.3

var model_root: Node3D = null
var collision_shape: CollisionShape3D = null


func _ready() -> void:
	add_to_group("ammo_pickups")
	collision_layer = 0
	collision_mask = 2
	body_entered.connect(_on_body_entered)
	_build_visuals()
	_build_collision()


func _process(delta: float) -> void:
	elapsed += delta
	if not is_collected and model_root != null:
		model_root.rotation.y += delta * 1.6
		model_root.position.y = base_y + sin(elapsed * 3.0) * 0.06

	if is_collected and respawns and (NetworkSession.is_server() or NetworkSession.is_offline()):
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			reactivate()


func _on_body_entered(body: Node3D) -> void:
	if is_collected:
		return
	if not NetworkSession.is_server() and not NetworkSession.is_offline():
		return
	if not body.is_in_group("player"):
		return
	if body.has_method("can_pickup_ammo") and not bool(body.call("can_pickup_ammo")):
		return
	if body.has_method("add_ammo"):
		var added: int = int(body.call("add_ammo", ammo_amount))
		if added > 0:
			collect()


## Executa a coleta do item de municao.
## Uso:
##   pickup.collect()
func collect() -> void:
	is_collected = true
	visible = false
	if collision_shape != null:
		collision_shape.set_deferred("disabled", true)
	respawn_timer = RESPAWN_DELAY
	if NetworkSession.is_server():
		_sync_collected.rpc()


## Reativa o item de municao apos o tempo de recarga.
## Uso:
##   pickup.reactivate()
func reactivate() -> void:
	is_collected = false
	visible = true
	if collision_shape != null:
		collision_shape.set_deferred("disabled", false)
	if NetworkSession.is_server():
		_sync_reactivated.rpc()


@rpc("authority", "call_remote", "reliable")
func _sync_collected() -> void:
	is_collected = true
	visible = false


@rpc("authority", "call_remote", "reliable")
func _sync_reactivated() -> void:
	is_collected = false
	visible = true


func _build_visuals() -> void:
	model_root = Node3D.new()
	model_root.name = "Model"
	model_root.position.y = base_y
	add_child(model_root)

	var green_mat := StandardMaterial3D.new()
	green_mat.albedo_color = Color(0.24, 0.35, 0.18)
	green_mat.roughness = 0.65

	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.14, 0.16, 0.12)
	dark_mat.roughness = 0.5

	var yellow_mat := StandardMaterial3D.new()
	yellow_mat.albedo_color = Color(0.95, 0.80, 0.15)
	yellow_mat.emission_enabled = true
	yellow_mat.emission = Color(0.95, 0.80, 0.15)
	yellow_mat.emission_energy_multiplier = 0.3

	_add_box(model_root, Vector3(0.50, 0.28, 0.32), Vector3.ZERO, green_mat)
	_add_box(model_root, Vector3(0.52, 0.06, 0.34), Vector3(0.0, 0.15, 0.0), dark_mat)
	_add_box(model_root, Vector3(0.51, 0.05, 0.33), Vector3(0.0, 0.0, 0.0), yellow_mat)
	_add_box(model_root, Vector3(0.18, 0.04, 0.06), Vector3(0.0, 0.20, 0.0), dark_mat)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.3)
	light.light_energy = 0.65
	light.omni_range = 2.8
	light.position.y = 0.25
	model_root.add_child(light)


func _build_collision() -> void:
	collision_shape = CollisionShape3D.new()
	collision_shape.name = "Collision"
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 0.9, 1.0)
	collision_shape.shape = shape
	collision_shape.position.y = base_y
	add_child(collision_shape)


func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = pos
	parent.add_child(instance)
