class_name AirdropPlane
extends Node3D

## Aviao voxel que cruza o mapa BAIXO (visivel sobre as ruas) e solta o crate
## de armas no ponto de queda. Roda no servidor e nos clientes (visual
## identico); so a autoridade conecta reached_drop_point.
## Uso:
##   var plane := AirdropPlane.new()
##   plane.configure(Vector3(-180, 12, 0), Vector3(180, 12, 0), Vector3.ZERO)
##   add_child(plane)

signal reached_drop_point

const SPEED := 26.0

var start_position := Vector3.ZERO
var drop_position := Vector3.ZERO
var end_position := Vector3.ZERO
var drop_progress := 0.0
var flight_progress := 0.0
var dropped := false


func configure(new_start: Vector3, new_end: Vector3, new_drop: Vector3) -> void:
	start_position = new_start
	end_position = new_end
	drop_position = new_drop


func _ready() -> void:
	global_position = start_position
	dropped = false
	var to_drop := drop_position - start_position
	var to_end := end_position - start_position
	if to_end.length_squared() > 0.01:
		drop_progress = clampf(to_drop.dot(to_end) / to_end.length_squared(), 0.0, 1.0)
		rotation.y = heading_for(to_end)
	_build_plane()


func _physics_process(delta: float) -> void:
	if flight_progress >= 1.0:
		queue_free()
		return
	flight_progress = minf(flight_progress + SPEED * delta / maxf(start_position.distance_to(end_position), 0.1), 1.0)
	global_position = start_position.lerp(end_position, flight_progress)
	if not dropped and flight_progress >= drop_progress:
		dropped = true
		reached_drop_point.emit()


## Yaw que aponta o nariz do modelo para a direcao do voo. O nariz fica em +Z
## (a cauda e o estabilizador em -Z), entao o sinal e o direto: com
## atan2(-x, -z) o aviao cruzava o mapa de rabo pra frente.
## Uso: rotation.y = heading_for(to_end)
static func heading_for(direction: Vector3) -> float:
	return atan2(direction.x, direction.z)


## Modelo voxel: fuselagem, asas fixas e cauda. Sem fisica.
func _build_plane() -> void:
	var fuselage := StandardMaterial3D.new()
	fuselage.albedo_color = Color(0.72, 0.75, 0.78)
	fuselage.roughness = 0.6
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.2, 0.32, 0.45)
	accent.roughness = 0.7
	_add_box(Vector3(1.4, 1.4, 8.0), Vector3.ZERO, fuselage)
	_add_box(Vector3(10.0, 0.3, 1.8), Vector3(0.0, 0.1, 0.4), accent)
	_add_box(Vector3(4.0, 0.3, 1.4), Vector3(0.0, 0.95, -3.4), accent)
	_add_box(Vector3(0.3, 1.8, 1.4), Vector3(0.0, 1.1, -3.6), accent)


func _add_box(size: Vector3, position: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	add_child(instance)
