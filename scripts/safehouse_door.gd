class_name SafehouseDoor
extends Node3D

const CLOSED_PANEL_Y := 1.56
const OPEN_PANEL_Y := 4.76
const PANEL_SPEED := 4.0
const CLOSE_HOLD_TIME := 0.75

@onready var panel: AnimatableBody3D = $Panel
@onready var detection_area: Area3D = $DetectionArea

var open_requested := false
var close_elapsed := 0.0
var panel_height := CLOSED_PANEL_Y


func _ready() -> void:
	add_to_group("safehouse_door")
	panel.position.y = panel_height
	_update_panel_collision()


func _physics_process(delta: float) -> void:
	if NetworkSession.is_client():
		_animate_panel(delta)
		return
	update_for_actor_presence(_has_nearby_living_actor(), delta)


## Updates the authoritative door target from current entrance occupancy.
## Usage: door.update_for_actor_presence(has_living_actor, delta)
func update_for_actor_presence(has_actor: bool, delta: float) -> void:
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
		elif body.is_in_group("zombies") and not bool(body.get("is_dead")):
			return true
	return false


func _animate_panel(delta: float) -> void:
	var target_y := OPEN_PANEL_Y if open_requested else CLOSED_PANEL_Y
	panel_height = move_toward(panel_height, target_y, PANEL_SPEED * maxf(delta, 0.0))
	panel.position.y = panel_height
	_update_panel_collision()


func _update_panel_collision() -> void:
	var fully_closed := not open_requested and is_equal_approx(panel_height, CLOSED_PANEL_Y)
	panel.collision_layer = 1 if fully_closed and not NetworkSession.is_client() else 0
