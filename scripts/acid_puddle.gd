# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name AcidPuddle
extends Node3D

## Poca de acido do cuspidor: disco verde no chao que queima jogadores dentro do
## raio e some sozinha. Onde ha simulacao (servidor/partida local) `damages` e
## verdadeiro; no cliente e so o visual enviado por RPC.
## Uso:
##   var puddle := AcidPuddle.new()
##   puddle.damages = not NetworkSession.is_client()
##   get_tree().current_scene.add_child(puddle)
##   puddle.global_position = alvo

const RADIUS := 2.2
const LIFETIME := 5.0
const TICK_INTERVAL := 0.5
const DAMAGE_PER_TICK := 6
const ACID_COLOR := Color(0.55, 0.95, 0.15)

var damages := false
var elapsed := 0.0
var _tick_elapsed := 0.0
var _material: StandardMaterial3D


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(ACID_COLOR, 0.6)
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.emission_enabled = true
	_material.emission = ACID_COLOR
	_material.emission_energy_multiplier = 0.8
	var mesh := CylinderMesh.new()
	mesh.top_radius = RADIUS
	mesh.bottom_radius = RADIUS
	mesh.height = 0.04
	mesh.radial_segments = 20
	mesh.material = _material
	var disc := MeshInstance3D.new()
	disc.name = "AcidDisc"
	disc.mesh = mesh
	disc.position.y = 0.06
	add_child(disc)


func _physics_process(delta: float) -> void:
	elapsed += maxf(delta, 0.0)
	if elapsed >= LIFETIME:
		queue_free()
		return
	if _material != null:
		_material.albedo_color.a = 0.6 * (1.0 - elapsed / LIFETIME)
	if not damages:
		return
	_tick_elapsed += maxf(delta, 0.0)
	while _tick_elapsed >= TICK_INTERVAL:
		_tick_elapsed -= TICK_INTERVAL
		_burn_players_inside()


func _burn_players_inside() -> void:
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		if player == null or not player.has_method("take_damage"):
			continue
		var offset := player.global_position - global_position
		offset.y = 0.0
		if offset.length() <= RADIUS:
			player.take_damage(DAMAGE_PER_TICK, Vector3.ZERO, "acid", null)
