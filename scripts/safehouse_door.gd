class_name SafehouseDoor
extends Node3D

const CLOSED_PANEL_ANGLE := 0.0
const OPEN_PANEL_ANGLE := -PI * 0.5
const PANEL_SPEED := 4.5
const CLOSE_HOLD_TIME := 0.75
## O E manual vale por este tempo; depois a presenca automatica retoma o
## controle (abre ao chegar, fecha ao sair) em vez de travar no estado.
const MANUAL_OVERRIDE_GRACE := 2.0

@onready var panel: AnimatableBody3D = $Panel
@onready var detection_area: Area3D = $DetectionArea

var open_requested := false
var manual_override := false
var manual_hold_elapsed := 0.0
var close_elapsed := 0.0
var panel_angle := CLOSED_PANEL_ANGLE


func _ready() -> void:
	add_to_group("safehouse_door")
	panel.rotation.y = panel_angle
	_update_panel_collision()


func _physics_process(delta: float) -> void:
	if NetworkSession.is_client():
		_animate_panel(delta)
		return
	update_for_actor_presence(_has_nearby_living_actor(), delta)


## Toggles the safehouse entrance between open and closed.
## Usage: door.interact()
func interact() -> void:
	manual_override = true
	manual_hold_elapsed = 0.0
	open_requested = not open_requested
	close_elapsed = 0.0


## Safehouse doors cannot be damaged by zombies or weapons. Mesma assinatura das
## outras portas: bala e explosao passam 4 argumentos (antes dava erro de script).
## Usage: door.take_damage(10, Vector3.FORWARD)
func take_damage(_amount: int, _attack_direction: Vector3 = Vector3.ZERO, _damage_kind: String = "bullet", _attacker: Node = null, _hit_position: Vector3 = Vector3.INF) -> void:
	return


## Updates the authoritative door target from current entrance occupancy.
## Usage: door.update_for_actor_presence(has_living_actor, delta)
func update_for_actor_presence(has_actor: bool, delta: float) -> void:
	if manual_override:
		# O E e um override temporario: expira e o modo automatico volta
		# (antes ele nunca expirava e a porta travava no ultimo estado).
		manual_hold_elapsed += maxf(delta, 0.0)
		if manual_hold_elapsed >= MANUAL_OVERRIDE_GRACE:
			manual_override = false
			close_elapsed = 0.0
		_animate_panel(delta)
		return
	if has_actor:
		open_requested = true
		close_elapsed = 0.0
	elif open_requested:
		close_elapsed += maxf(delta, 0.0)
		if close_elapsed >= CLOSE_HOLD_TIME:
			open_requested = false
			close_elapsed = 0.0
	_animate_panel(delta)


## Applies the server's door target to a client-side visual proxy.
## Usage: door.apply_network_open_state(snapshot_door_open)
func apply_network_open_state(should_open: bool) -> void:
	open_requested = should_open
	manual_override = false
	close_elapsed = 0.0
	_update_panel_collision()


## Returns the target state replicated in multiplayer snapshots.
## Usage: var should_open := door.is_open_requested()
func is_open_requested() -> bool:
	return open_requested


func _has_nearby_living_actor() -> bool:
	for body in detection_area.get_overlapping_bodies():
		if not is_instance_valid(body) or body.is_queued_for_deletion():
			continue
		if body.is_in_group("player"):
			if not bool(body.get("is_eliminated")) and int(body.get("health")) > 0:
				return true
	return false


func _animate_panel(delta: float) -> void:
	var target_angle := OPEN_PANEL_ANGLE if open_requested else CLOSED_PANEL_ANGLE
	panel_angle = move_toward(panel_angle, target_angle, PANEL_SPEED * maxf(delta, 0.0))
	panel.rotation.y = panel_angle
	_update_panel_collision()


func _update_panel_collision() -> void:
	var fully_closed := not open_requested and is_equal_approx(panel_angle, CLOSED_PANEL_ANGLE)
	panel.collision_layer = 1 if fully_closed else 0
