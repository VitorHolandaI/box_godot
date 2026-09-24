# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name DoorDebrisEffect
extends Node3D

## Animacao de porta arrombada: a folha se parte em tabuas e lascas que voam
## na direcao do golpe, quicam no chao e desaparecem. So visual (sem corpos
## fisicos), entao nao pesa na simulacao nem bloqueia a passagem.
## Uso:
##   var debris := DoorDebrisEffect.new()
##   debris.configure(Vector3(1.4, 2.75, 0.12), Vector3.FORWARD, material, 1234)
##   door.add_child(debris)

const PLANK_COLUMNS := 3
const PLANK_ROWS := 2
const SPLINTER_COUNT := 6
const GRAVITY := 14.0
const BOUNCE_DAMPING := 0.35
const FADE_START := 1.1
const LIFETIME := 1.8

var panel_size := Vector3(1.4, 2.75, 0.12)
var push_direction := Vector3.FORWARD
var piece_material: Material = null
var random_seed := 0
var elapsed := 0.0
var pieces: Array[MeshInstance3D] = []
var linear_velocities: Array[Vector3] = []
var angular_velocities: Array[Vector3] = []


## Define tamanho da folha (espaco local da porta), direcao global do golpe,
## material e seed para que clientes vejam lascas parecidas.
## Uso: debris.configure(panel_size, attack_direction, panel_material, name.hash())
func configure(size: Vector3, direction: Vector3, material: Material, seed_value: int) -> void:
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		push_error("Tamanho de destrocos invalido %s; esperado Vector3 positivo." % size)
		return
	panel_size = size
	push_direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector3.FORWARD
	piece_material = material
	random_seed = seed_value


func _ready() -> void:
	name = "DoorDebris"
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var local_push := (global_transform.basis.inverse() * push_direction).normalized() if is_inside_tree() else push_direction
	var along_x := panel_size.x >= panel_size.z
	var panel_width := panel_size.x if along_x else panel_size.z
	for column in PLANK_COLUMNS:
		for row in PLANK_ROWS:
			var size := Vector3(panel_width / PLANK_COLUMNS * 0.92, panel_size.y / PLANK_ROWS * 0.92, minf(panel_size.x, panel_size.z))
			var along := (float(column) + 0.5) / PLANK_COLUMNS * panel_width
			var offset := Vector3(along, (float(row) + 0.5) / PLANK_ROWS * panel_size.y, 0.0)
			_add_piece(_orient_size(size, along_x), _orient_offset(offset, along_x), local_push, rng, 1.0)
	for _splinter in SPLINTER_COUNT:
		var size := Vector3(0.08, rng.randf_range(0.25, 0.6), 0.05)
		var offset := Vector3(rng.randf() * panel_width, rng.randf_range(0.3, panel_size.y), 0.0)
		_add_piece(_orient_size(size, along_x), _orient_offset(offset, along_x), local_push, rng, 1.6)


func _physics_process(delta: float) -> void:
	elapsed += delta
	for index in pieces.size():
		_advance_piece(index, delta)
	if elapsed >= FADE_START:
		var transparency := clampf((elapsed - FADE_START) / (LIFETIME - FADE_START), 0.0, 1.0)
		for piece in pieces:
			piece.transparency = transparency
	if elapsed >= LIFETIME:
		queue_free()


func _advance_piece(index: int, delta: float) -> void:
	var piece := pieces[index]
	var velocity := linear_velocities[index]
	velocity.y -= GRAVITY * delta
	piece.position += velocity * delta
	piece.rotation += angular_velocities[index] * delta
	var half_height := 0.05
	if piece.position.y < half_height:
		piece.position.y = half_height
		velocity.y = absf(velocity.y) * BOUNCE_DAMPING
		velocity.x *= 0.6
		velocity.z *= 0.6
		angular_velocities[index] *= 0.5
	linear_velocities[index] = velocity


func _add_piece(size: Vector3, offset: Vector3, local_push: Vector3, rng: RandomNumberGenerator, speed_scale: float) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = piece_material
	var piece := MeshInstance3D.new()
	piece.mesh = mesh
	piece.position = offset
	piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(piece)
	pieces.append(piece)
	var lateral := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0))
	linear_velocities.append((local_push * rng.randf_range(2.5, 4.5) + lateral * 1.2 + Vector3.UP * rng.randf_range(1.0, 3.0)) * speed_scale)
	angular_velocities.append(Vector3(rng.randf_range(-9.0, 9.0), rng.randf_range(-6.0, 6.0), rng.randf_range(-9.0, 9.0)))


static func _orient_size(size: Vector3, along_x: bool) -> Vector3:
	return size if along_x else Vector3(size.z, size.y, size.x)


static func _orient_offset(offset: Vector3, along_x: bool) -> Vector3:
	return offset if along_x else Vector3(0.0, offset.y, offset.x)
