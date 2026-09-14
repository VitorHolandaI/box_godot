class_name ZombieIndoorRouter
extends RefCounted

## Guia um zumbi pelo navmesh do edificio em que ele (ou o alvo) esta:
## sai de comodos, desce/sobe escadas e atravessa vaos de porta. Fora de
## qualquer edificio devolve "sem rota" e o zumbi persegue em linha reta.
## O caminho e recalculado em intervalos, nunca a cada frame, para que
## centenas de zumbis presos nao custem uma busca por tick.
## Uso:
##   var router := ZombieIndoorRouter.new()
##   var waypoint := router.next_waypoint(get_tree(), feet, target_feet, delta)
##   if router.has_route: direction = waypoint - feet

const NAVIGATION_SCRIPT: GDScript = preload("res://scripts/procedural/navigation/building_navigation.gd")
const REPLAN_INTERVAL := 0.5
const REPLAN_JITTER := 0.25
const WAYPOINT_REACHED_DISTANCE := 0.45
const WAYPOINT_VERTICAL_TOLERANCE := 1.2

var has_route := false
var replan_count := 0
var _path := PackedVector3Array()
var _path_index := 0
var _replan_timer := -1.0


## Proximo ponto global a perseguir. `has_route` fica falso quando nenhum
## edificio envolve o zumbi nem o alvo, ou quando o caminho terminou.
## Uso: var waypoint := router.next_waypoint(tree, zombie_feet, target_feet, 1.0 / 60.0)
func next_waypoint(tree: SceneTree, zombie_feet: Vector3, target_feet: Vector3, delta: float) -> Vector3:
	_replan_timer -= delta
	if _replan_timer <= 0.0:
		_replan(tree, zombie_feet, target_feet)
	while _path_index < _path.size() and _is_waypoint_reached(zombie_feet, _path[_path_index]):
		_path_index += 1
	has_route = _path_index < _path.size()
	return _path[_path_index] if has_route else target_feet


## Descarta o caminho atual; o proximo pedido recalcula imediatamente.
## Uso: router.invalidate()
func invalidate() -> void:
	_replan_timer = -1.0


func _replan(tree: SceneTree, zombie_feet: Vector3, target_feet: Vector3) -> void:
	# Jitter espalha os replanejamentos de uma horda que nasceu no mesmo frame.
	_replan_timer = REPLAN_INTERVAL + randf() * REPLAN_JITTER
	replan_count += 1
	_path = PackedVector3Array()
	_path_index = 0
	var navigation = NAVIGATION_SCRIPT.find_for_position(tree, zombie_feet)
	if navigation == null:
		navigation = NAVIGATION_SCRIPT.find_for_position(tree, target_feet)
	if navigation == null:
		return
	_path = navigation.get_path_between(zombie_feet, target_feet)
	# O primeiro ponto e a projecao do proprio zumbi no navmesh.
	_path_index = 1 if _path.size() > 1 else 0


func _is_waypoint_reached(zombie_feet: Vector3, waypoint: Vector3) -> bool:
	if absf(zombie_feet.y - waypoint.y) > WAYPOINT_VERTICAL_TOLERANCE:
		return false
	var horizontal := Vector2(zombie_feet.x - waypoint.x, zombie_feet.z - waypoint.z)
	return horizontal.length() <= WAYPOINT_REACHED_DISTANCE
