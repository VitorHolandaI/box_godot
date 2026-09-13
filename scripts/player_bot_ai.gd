class_name PlayerBotAI
extends RefCounted

const PATROL_POINTS: Array[Vector3] = [
	Vector3(0.0, 0.12, 0.0),
	Vector3(22.0, 0.12, 0.0),
	Vector3(22.0, 0.12, 22.0),
	Vector3(0.0, 0.12, 22.0),
	Vector3(-22.0, 0.12, 22.0),
	Vector3(-22.0, 0.12, -22.0),
	Vector3(0.0, 0.12, -22.0),
	Vector3(22.0, 0.12, -22.0),
]

var bot_elapsed := 0.0
var bot_saw_player := false
var bot_moved := false
var bot_used_stamina := false
var bot_saw_bullet := false
var bot_killed_zombie := false
var bot_saw_zombie_attack := false
var bot_spawn_position := Vector3.ZERO
var bot_target_zombie: Node3D = null

var patrol_indices: Dictionary = {}
var last_positions: Dictionary = {}
var stuck_timers: Dictionary = {}
var unstuck_dirs: Dictionary = {}
var unstuck_durations: Dictionary = {}
var strafe_dirs: Dictionary = {}
var strafe_timers: Dictionary = {}
var bot_kills := 0


## Atualiza contadores e valida condicoes de teste ou desempenho.
## Uso:
##   bot_ai.update(delta, get_tree())
func update(delta: float, tree: SceneTree) -> void:
	bot_elapsed += delta
	if not NetworkSession.bot_mode:
		return
	if not bot_saw_bullet and not tree.get_nodes_in_group("network_bullet_visuals").is_empty():
		bot_saw_bullet = true
	if bot_saw_player and bot_killed_zombie and bot_moved and bot_saw_bullet and bot_used_stamina:
		print("BOT_TEST_PASS: conectou, correu, viu a bala e matou um zumbi.")
		tree.quit(0)
	elif bot_elapsed >= 20.0:
		push_error("BOT_TEST_FAIL: player=%s moved=%s stamina=%s attack=%s bullet=%s kill=%s" % [
			bot_saw_player, bot_moved, bot_used_stamina, bot_saw_zombie_attack, bot_saw_bullet, bot_killed_zombie
		])
		tree.quit(3)


func notify_bullet() -> void:
	bot_saw_bullet = true


func notify_zombie_states(zombie_states: Array) -> void:
	for state_value in zombie_states:
		if not state_value is Dictionary:
			continue
		var state: Dictionary = state_value
		if bool(state.get("is_dead", false)):
			if NetworkSession.bot_mode:
				bot_killed_zombie = true
			bot_kills += 1
		if int(state.get("attack_sequence", 0)) > 0:
			bot_saw_zombie_attack = true


func notify_player_state(state: Dictionary, is_local: bool) -> void:
	if not NetworkSession.bot_mode or not is_local:
		return
	if float(state.get("stamina", 100.0)) < 99.0:
		bot_used_stamina = true
	var current_pos: Variant = state.get("position")
	if current_pos is Vector3:
		if not bot_saw_player:
			bot_spawn_position = current_pos
			bot_saw_player = true
		elif bot_spawn_position.distance_to(current_pos) > 0.5:
			bot_moved = true


## Gera acoes de entrada para jogadores controlados por bot.
## Uso:
##   var inputs := bot_ai.collect_inputs(players, zombies_node, tree)
func collect_inputs(local_players: Array[Node], zombies_node: Node, tree: SceneTree) -> Array:
	if local_players.is_empty():
		return []
	if NetworkSession.bot_mode:
		return [_generate_test_bot_input(local_players[0] as Node3D, zombies_node)]
	var states: Array = []
	for player_node in local_players:
		var player := player_node as Node3D
		if is_instance_valid(player):
			states.append(_generate_autoplay_input(player, int(player.get("local_slot")), zombies_node, tree))
	return states


func _generate_test_bot_input(player: Node3D, zombies_node: Node) -> Dictionary:
	if not is_instance_valid(bot_target_zombie) or bool(bot_target_zombie.get("is_dead")):
		bot_target_zombie = _find_nearest_live_zombie(player.global_position, zombies_node)
	var move := Vector2.ZERO
	var aim := Vector2.ZERO
	if is_instance_valid(bot_target_zombie):
		var offset: Vector3 = bot_target_zombie.global_position - player.global_position
		offset.y = 0.0
		aim = Vector2(offset.x, offset.z).normalized()
		var min_dist := 1.0 if not bot_saw_zombie_attack else 3.0
		if offset.length() > min_dist:
			move = Vector2(offset.x, offset.z).normalized()
	var attack_cycle := fmod(bot_elapsed, 0.4)
	var can_shoot := bot_saw_zombie_attack or bot_elapsed > 4.5
	return {
		"slot": 0,
		"move": move,
		"aim": aim,
		"jump": false,
		"sprint": true,
		"attack": can_shoot and attack_cycle < 0.14,
		"knife": false,
		"pistol": fmod(bot_elapsed, 1.0) < 0.25,
		"reload": false,
	}


func _generate_autoplay_input(player: Node3D, slot: int, zombies_node: Node, _tree: SceneTree) -> Dictionary:
	var player_pos := player.global_position
	var target := _find_nearest_live_zombie(player_pos, zombies_node)
	var move_plan := _calculate_movement(player, slot, target)
	var combat_plan := _calculate_combat(player, slot, target)
	var aim := Vector2.ZERO
	if target != null:
		var to_target: Vector3 = target.global_position - player_pos
		to_target.y = 0.0
		if not to_target.is_zero_approx():
			aim = Vector2(to_target.x, to_target.z).normalized()
	elif not (move_plan["move"] as Vector2).is_zero_approx():
		aim = move_plan["move"]

	return {
		"slot": slot,
		"move": move_plan["move"],
		"aim": aim,
		"jump": move_plan["jump"],
		"sprint": move_plan["sprint"],
		"attack": combat_plan["attack"],
		"knife": combat_plan["knife"],
		"pistol": combat_plan["pistol"],
		"reload": combat_plan["reload"],
	}


func _calculate_movement(player: Node3D, slot: int, target: Node3D) -> Dictionary:
	var delta := 0.05
	_update_unstuck_logic(player, slot, delta)
	var unstuck_dur: float = unstuck_durations.get(slot, 0.0)
	if unstuck_dur > 0.0:
		unstuck_durations[slot] = unstuck_dur - delta
		var unstick_vec: Vector2 = unstuck_dirs.get(slot, Vector2.UP)
		return {"move": unstick_vec, "jump": true, "sprint": true}

	var strafe_time: float = strafe_timers.get(slot, 0.0) + delta
	strafe_timers[slot] = strafe_time
	var strafe_dir: float = strafe_dirs.get(slot, 1.0)
	if strafe_time > 1.8:
		strafe_timers[slot] = 0.0
		strafe_dir = -strafe_dir
		strafe_dirs[slot] = strafe_dir

	var stamina: float = float(player.get("stamina"))
	var ammo: int = int(player.get("pistol_ammo"))
	var reserve: int = int(player.get("reserve_ammo"))
	if ammo + reserve < 18:
		var ammo_pickup := _find_nearest_ammo_pickup(player.global_position, player.get_tree())
		if ammo_pickup != null:
			var to_pickup: Vector3 = ammo_pickup.global_position - player.global_position
			to_pickup.y = 0.0
			var pickup_dir := Vector2(to_pickup.x, to_pickup.z).normalized()
			return {"move": pickup_dir, "jump": false, "sprint": stamina > 25.0}

	if target != null:
		var offset: Vector3 = target.global_position - player.global_position
		offset.y = 0.0
		var dist := offset.length()
		var dir := Vector2(offset.x, offset.z).normalized()
		var perp := Vector2(-dir.y, dir.x) * strafe_dir
		if ammo == 0 and reserve > 0:
			return {"move": -dir, "jump": false, "sprint": stamina > 20.0}
		var uses_melee := ammo + reserve == 0 or dist <= 2.2
		if uses_melee:
			if dist > 1.55:
				var careful_approach := (dir * 0.75 + perp * 0.4).normalized()
				return {"move": careful_approach, "jump": false, "sprint": false}
			if dist >= 1.3:
				return {"move": perp, "jump": false, "sprint": false}
			var careful_retreat := (-dir * 0.8 + perp * 0.2).normalized()
			return {"move": careful_retreat, "jump": false, "sprint": false}
		if dist > 6.5:
			return {"move": dir, "jump": false, "sprint": stamina > 20.0}
		if dist >= 3.0:
			var tactical := (dir * 0.15 + perp * 0.85).normalized()
			return {"move": tactical, "jump": false, "sprint": false}
		return {"move": -dir * 0.95, "jump": fmod(bot_elapsed, 2.0) < 0.12, "sprint": stamina > 15.0}

	var p_index: int = patrol_indices.get(slot, slot % PATROL_POINTS.size())
	var waypoint := PATROL_POINTS[p_index]
	var way_offset := waypoint - player.global_position
	way_offset.y = 0.0
	if way_offset.length() < 3.0:
		p_index = (p_index + 1) % PATROL_POINTS.size()
		patrol_indices[slot] = p_index
		waypoint = PATROL_POINTS[p_index]
		way_offset = waypoint - player.global_position
		way_offset.y = 0.0
	var way_dir := Vector2(way_offset.x, way_offset.z).normalized()
	return {"move": way_dir, "jump": false, "sprint": stamina > 30.0}


func _update_unstuck_logic(player: Node3D, slot: int, delta: float) -> void:
	var last_pos: Vector3 = last_positions.get(slot, player.global_position)
	var dist := player.global_position.distance_to(last_pos)
	last_positions[slot] = player.global_position
	var stuck_t: float = stuck_timers.get(slot, 0.0)
	if dist < 0.10:
		stuck_t += delta
		if stuck_t > 0.45:
			stuck_t = 0.0
			unstuck_durations[slot] = 0.7
			var angle := randf() * TAU
			unstuck_dirs[slot] = Vector2(cos(angle), sin(angle))
	else:
		stuck_t = maxf(stuck_t - delta * 1.5, 0.0)
	stuck_timers[slot] = stuck_t


func _calculate_combat(player: Node3D, _slot: int, target: Node3D) -> Dictionary:
	var ammo := int(player.get("pistol_ammo"))
	var reserve := int(player.get("reserve_ammo"))
	var weapon := int(player.get("current_weapon"))
	var attack_pulse := fmod(bot_elapsed, 0.28) < 0.12
	var switch_pulse := fmod(bot_elapsed, 0.45) < 0.14

	if target == null:
		if ammo < 12 and reserve > 0:
			return {"attack": false, "knife": false, "pistol": false, "reload": switch_pulse}
		return {"attack": false, "knife": false, "pistol": false, "reload": false}

	var offset: Vector3 = target.global_position - player.global_position
	var dist := offset.length()
	offset.y = 0.0
	var forward: Vector3 = -player.global_transform.basis.z
	var aligned: bool = forward.dot(offset.normalized()) > 0.65

	if dist <= 2.2 or (ammo == 0 and reserve == 0):
		var want_knife: bool = weapon != 0 and switch_pulse
		return {"attack": attack_pulse and aligned, "knife": want_knife, "pistol": false, "reload": false}

	var want_pistol: bool = weapon != 1 and switch_pulse
	if ammo == 0 and reserve > 0:
		return {"attack": false, "knife": false, "pistol": want_pistol, "reload": switch_pulse}
	var can_shoot: bool = aligned and dist <= 30.0 and attack_pulse
	return {"attack": can_shoot, "knife": false, "pistol": want_pistol, "reload": false}


func _find_nearest_live_zombie(player_pos: Vector3, zombies_node: Node) -> Node3D:
	if zombies_node == null:
		return null
	var nearest: Node3D = null
	var nearest_distance := 55.0
	for child in zombies_node.get_children():
		var zombie := child as Node3D
		if zombie == null or bool(zombie.get("is_dead")):
			continue
		var dist := zombie.global_position.distance_to(player_pos)
		if dist < nearest_distance:
			nearest_distance = dist
			nearest = zombie
	return nearest


func _find_nearest_ammo_pickup(player_pos: Vector3, tree: SceneTree) -> Node3D:
	if tree == null:
		return null
	var nearest: Node3D = null
	var nearest_distance := 35.0
	for pickup_node in tree.get_nodes_in_group("ammo_pickups"):
		var pickup := pickup_node as Node3D
		if pickup == null or not pickup.visible:
			continue
		var dist := pickup.global_position.distance_to(player_pos)
		if dist < nearest_distance:
			nearest_distance = dist
			nearest = pickup
	return nearest
