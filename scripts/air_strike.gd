# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name AirStrike
extends Node3D

## Ataque aereo chamado pelo jogador: fumaca vermelha marca o alvo e, depois de
## DELAY_SECONDS, BOMB_COUNT bombas caem em linha na direcao da mira. So a
## autoridade causa dano (zumbis e portas); o cliente ve a fumaca e recebe as
## explosoes pelo show_explosion replicado.
## Uso:
##   var ataque := AirStrike.new()
##   cena.add_child(ataque)
##   ataque.setup(alvo, direcao, true)

const TARGET_DISTANCE := 14.0
const DELAY_SECONDS := 2.5
const BOMB_COUNT := 6
const BOMB_INTERVAL := 0.2
const LINE_LENGTH := 12.0
const RADIUS := 5.0
const ZOMBIE_DAMAGE := 300
const DOOR_DAMAGE := 80
const NOISE_RADIUS := 140.0

var target := Vector3.ZERO
var line_direction := Vector3.FORWARD
var authoritative := true
var elapsed := 0.0
var bombs_dropped := 0


func setup(target_point: Vector3, direction: Vector3, deals_damage: bool) -> void:
	target = target_point
	var flat := Vector3(direction.x, 0.0, direction.z)
	line_direction = flat.normalized() if not flat.is_zero_approx() else Vector3.FORWARD
	authoritative = deals_damage
	global_position = target
	if not ServerTickPolicy.is_dedicated_server():
		_build_marker()


func _process(delta: float) -> void:
	advance(delta)


## Avanca o relogio e solta as bombas vencidas; some depois da ultima.
## Uso: ataque.advance(delta)
func advance(delta: float) -> void:
	elapsed += delta
	while bombs_dropped < BOMB_COUNT and elapsed >= DELAY_SECONDS + bombs_dropped * BOMB_INTERVAL:
		_drop_bomb(bomb_point(bombs_dropped))
		bombs_dropped += 1
	if bombs_dropped >= BOMB_COUNT:
		queue_free()


## Ponto da bomba `index` na linha centrada no alvo.
## Uso: var ponto := ataque.bomb_point(0)
func bomb_point(index: int) -> Vector3:
	var t := float(index) / float(maxi(BOMB_COUNT - 1, 1)) - 0.5
	return target + line_direction * LINE_LENGTH * t


func _drop_bomb(point: Vector3) -> void:
	if not authoritative or not is_inside_tree():
		return
	ZombieVariantAbilities.area_damage(get_tree(), point, RADIUS, 0, ZOMBIE_DAMAGE, DOOR_DAMAGE, null)
	ZombieFlockCoordinator.relay_sound(get_tree(), point, NOISE_RADIUS)
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("show_explosion"):
		scene.call("show_explosion", point, RADIUS)


func _build_marker() -> void:
	var smoke := CPUParticles3D.new()
	smoke.amount = 24
	smoke.lifetime = 1.6
	smoke.direction = Vector3.UP
	smoke.spread = 15.0
	smoke.initial_velocity_min = 1.5
	smoke.initial_velocity_max = 3.0
	smoke.gravity = Vector3(0.3, 0.6, 0.0)
	smoke.scale_amount_min = 1.0
	smoke.scale_amount_max = 2.5
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.35
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.15, 0.1)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.1, 0.05)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	smoke.mesh = mesh
	add_child(smoke)
