class_name PlayerBotAI
extends RefCounted

## Alcance de tiro do esquadrao SWAT (Uzi) e stamina minima para sprintar.
const SQUAD_ENGAGE_RANGE := 32.0
const SQUAD_SPRINT_STAMINA := 20.0
## O alvo (com linha de visao) e rebuscado a cada N s por bot: o raycast nao
## precisa rodar em todo tick.
const SQUAD_TARGET_INTERVAL := 0.25
## Candidatos testados por busca, do mais perto para o mais longe: sem isso o
## bot mira num zumbi atras da parede e fura o cenario (medido no smoke: 253 de
## 258 tiros acertaram o Safehouse).
const SQUAD_LOS_CANDIDATES := 5

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
var _squad_targets: Dictionary = {}
var _squad_target_timers: Dictionary = {}
## Pulsos de ataque por vaga em PVP: pistola e semi-automatica e so dispara na
## BORDA do botao; mandar "attack" segurado fazia o bot atirar uma vez e parar.
var _pvp_attack_timers: Dictionary = {}
const PVP_ATTACK_CYCLE := 0.25
const PVP_ATTACK_PULSE := 0.12


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


## Entrada de um bot em mata-mata PVP: caca o jogador inimigo mais perto,
## mantem distancia de tiro, sai do cerco e nunca fica parado (patrulha quando
## nao ha ninguem a vista). Sem troca de arma: em PVP o bot comeca de pistola.
## `hunt_position` e para onde ir quando nao ha inimigo a vista (o main manda a
## proxima esquina da rota pelas ruas; sem isso o bot atravessava o predio reto
## e ficava empurrando parede).
## Uso: bot.apply_network_input(ai.collect_pvp_input(bot, tree, slot, delta, rumo))
func collect_pvp_input(player: Node3D, tree: SceneTree, slot: int, delta: float, hunt_position: Vector3 = Vector3.ZERO) -> Dictionary:
	var target := _nearest_enemy_player(player, tree)
	var target_offset := Vector3.ZERO
	var target_dist := 0.0
	if target != null:
		target_offset = target.global_position - player.global_position
		target_offset.y = 0.0
		target_dist = target_offset.length()
	var move := _pvp_movement(player, slot, target, target_offset, target_dist, delta, hunt_position)
	var aim := move
	if target_dist > 0.01:
		aim = Vector2(target_offset.x, target_offset.z).normalized()
	var pulse := float(_pvp_attack_timers.get(slot, 0.0)) + delta
	if pulse >= PVP_ATTACK_CYCLE:
		pulse = 0.0
	_pvp_attack_timers[slot] = pulse
	var in_range: bool = target != null and target_dist <= SQUAD_ENGAGE_RANGE
	var can_attack: bool = _squad_can_attack(player, target, target_offset, target_dist) or in_range
	return {
		"slot": slot,
		"move": move,
		"aim": aim,
		"jump": false,
		"sprint": float(player.get("stamina")) > SQUAD_SPRINT_STAMINA,
		"attack": can_attack and pulse < PVP_ATTACK_PULSE,
		"knife": false,
		"pistol": false,
		"reload": false,
	}


## Entradas de todos os jogadores locais em PVP (um estado por jogador).
## Uso: var inputs := ai.collect_pvp_inputs(local_players, get_tree(), delta)
func collect_pvp_inputs(local_players: Array[Node], tree: SceneTree, delta: float) -> Array:
	var states: Array = []
	for index in local_players.size():
		var player := local_players[index] as Node3D
		if is_instance_valid(player):
			states.append(collect_pvp_input(player, tree, index, delta))
	return states


## Jogador inimigo vivo mais perto (o proprio bot e os caidos ficam de fora).
## Uso: var alvo := _nearest_enemy_player(bot, tree)
func _nearest_enemy_player(player: Node3D, tree: SceneTree) -> Node3D:
	if tree == null:
		return null
	var nearest: Node3D = null
	var nearest_distance := 1e9
	for node in tree.get_nodes_in_group("player"):
		var candidate := node as Node3D
		if candidate == null or candidate == player or not is_instance_valid(candidate):
			continue
		if bool(candidate.get("is_eliminated")) or bool(candidate.get("is_swat_bot")):
			continue
		var distance := candidate.global_position.distance_to(player.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = candidate
	return nearest


## Movimento do bot em PVP: cerco (foge de 2+ inimigos colados), aproxima de
## longe, recua de perto e ciranda na faixa de tiro; sem alvo, patrulha.
func _pvp_movement(player: Node3D, slot: int, target: Node3D, target_offset: Vector3, target_dist: float, delta: float, hunt_position: Vector3 = Vector3.ZERO) -> Vector2:
	_update_unstuck_logic(player, slot, delta)
	var unstuck_duration: float = unstuck_durations.get(slot, 0.0)
	if unstuck_duration > 0.0:
		unstuck_durations[slot] = unstuck_duration - delta
		return unstuck_dirs.get(slot, Vector2.UP)
	_strafe_bootstrap(slot, slot)
	var strafe_time: float = strafe_timers.get(slot, 0.0) + delta
	strafe_timers[slot] = strafe_time
	var strafe_dir: float = strafe_dirs.get(slot, 1.0)
	if strafe_time > 1.6:
		strafe_timers[slot] = 0.0
		strafe_dir = -strafe_dir
		strafe_dirs[slot] = strafe_dir
	if target == null:
		# Sem inimigo a vista: segue a rota pelas ruas ate o lado inimigo.
		var to_hunt := hunt_position - player.global_position
		to_hunt.y = 0.0
		if to_hunt.length() < 4.0:
			return Vector2.ZERO
		return Vector2(to_hunt.x, to_hunt.z).normalized()
	var dir := Vector2(target_offset.x, target_offset.z).normalized()
	var perpendicular := Vector2(-dir.y, dir.x) * strafe_dir
	if target_dist > 12.0:
		return dir
	if target_dist < 4.0:
		return (-dir * 0.9 + perpendicular * 0.3).normalized()
	return (dir * 0.1 + perpendicular * 0.95).normalized()


## Entrada de um soldado do esquadrao SWAT: caca o zumbi mais perto dentro do
## alcance, mantem distancia de tiro, sai do cerco e volta para o dono quando
## passa do leash. Nunca troca de arma (Uzi) nem recarrega: municao infinita.
## `slot` separa o estado interno de cada bot; `formation_index` e a vaga dele
## na formacao em volta do dono (0..COUNT-1).
## Uso: bot.apply_network_input(ai.collect_squad_input(bot, dono, zombies, slot, i))
func collect_squad_input(player: Node3D, anchor: Node3D, zombies_node: Node, slot: int, formation_index: int, delta: float) -> Dictionary:
	var player_pos := player.global_position
	var anchor_pos := player_pos
	if is_instance_valid(anchor):
		anchor_pos = (anchor as Node3D).global_position
	var to_anchor := anchor_pos - player_pos
	to_anchor.y = 0.0
	var target := _squad_target_for(player, zombies_node, slot, delta)
	var target_offset := Vector3.ZERO
	var target_dist := 0.0
	if target != null:
		target_offset = target.global_position - player_pos
		target_offset.y = 0.0
		target_dist = target_offset.length()
	var move_plan := _squad_movement(player, slot, formation_index, target, target_offset, target_dist, anchor_pos, to_anchor, zombies_node, delta)
	var aim: Vector2 = move_plan["move"]
	if target != null and not target_offset.is_zero_approx():
		aim = Vector2(target_offset.x, target_offset.z).normalized()
	return {
		"slot": slot,
		"move": move_plan["move"],
		"aim": aim,
		"jump": move_plan["jump"],
		"sprint": move_plan["sprint"],
		"attack": _squad_can_attack(player, target, target_offset, target_dist),
		"knife": false,
		"pistol": false,
		"reload": false,
	}


## Uzi atira segurando o botao: alinhado, dentro do alcance e com linha de tiro.
func _squad_can_attack(player: Node3D, target: Node3D, target_offset: Vector3, target_dist: float) -> bool:
	if target_dist <= 0.01 or target_dist > SQUAD_ENGAGE_RANGE:
		return false
	if not is_instance_valid(player) or not is_instance_valid(target):
		return false
	var forward: Vector3 = -player.global_transform.basis.z
	if forward.dot(target_offset.normalized()) <= 0.6:
		return false
	return _has_shot_line(player, target)


## Alvo do soldado: o zumbi vivo mais perto dentro do alcance E com linha de
## visao. A busca roda a cada SQUAD_TARGET_INTERVAL; entre as buscas vale o
## cache (alvo que morre ou sai do alcance cai fora sozinho).
## Uso: var alvo := _squad_target_for(bot, zombies, slot, delta)
func _squad_target_for(player: Node3D, zombies_node: Node, slot: int, delta: float) -> Node3D:
	_squad_target_timers[slot] = float(_squad_target_timers.get(slot, 0.0)) - delta
	var cached = _squad_targets.get(slot)
	var cache_valid: bool = cached != null and is_instance_valid(cached) and not bool((cached as Node).get("is_dead"))
	if cache_valid and float(_squad_target_timers[slot]) > 0.0:
		return cached as Node3D
	if not cache_valid and float(_squad_target_timers[slot]) > 0.0:
		return null
	_squad_target_timers[slot] = SQUAD_TARGET_INTERVAL
	var target := _nearest_visible_zombie(player, zombies_node)
	_squad_targets[slot] = target
	return target


func _nearest_visible_zombie(player: Node3D, zombies_node: Node, max_distance: float = SQUAD_ENGAGE_RANGE) -> Node3D:
	if zombies_node == null:
		return null
	var origin := player.global_position
	var candidates: Array = []
	for node in zombies_node.get_children():
		var zombie := node as Node3D
		if zombie == null or bool(zombie.get("is_dead")):
			continue
		var dist := zombie.global_position.distance_to(origin)
		if dist > max_distance:
			continue
		candidates.append({"node": zombie, "dist": dist})
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(first: Dictionary, second: Dictionary) -> bool: return float(first["dist"]) < float(second["dist"]))
	for index in mini(candidates.size(), SQUAD_LOS_CANDIDATES):
		var zombie: Node3D = candidates[index]["node"]
		if _has_shot_line(player, zombie):
			return zombie
	return null


## Linha de tiro livre ate o alvo, com a mesma mascara dos tiros: parede no
## caminho devolve false e o bot nao gasta bala no cenario.
func _has_shot_line(player: Node3D, target: Node3D) -> bool:
	var body := player as CollisionObject3D
	if body == null or not body.is_inside_tree():
		return false
	var from := player.global_position + Vector3.UP * 1.2
	var to := target.global_position + Vector3.UP * 0.9
	var collider := Bullet.first_hit_collider(player.get_world_3d().direct_space_state, from, to, [body.get_rid()])
	if collider == null:
		return true
	var node := collider as Node
	while node != null:
		if node == target:
			return true
		node = node.get_parent()
	return false


## Movimento tatico do soldado: leash primeiro, depois cerco, faixa de tiro e,
## sem alvo, a vaga na formacao em volta do dono.
func _squad_movement(player: Node3D, slot: int, formation_index: int, target: Node3D, target_offset: Vector3, target_dist: float, anchor_pos: Vector3, to_anchor: Vector3, zombies_node: Node, delta: float) -> Dictionary:
	_update_unstuck_logic(player, slot, delta)
	var unstuck_duration: float = unstuck_durations.get(slot, 0.0)
	if unstuck_duration > 0.0:
		unstuck_durations[slot] = unstuck_duration - delta
		return {"move": unstuck_dirs.get(slot, Vector2.UP), "jump": true, "sprint": true}
	var sprint := float(player.get("stamina")) > SQUAD_SPRINT_STAMINA
	var anchor_distance := to_anchor.length()
	# Passou do leash (ou ficou muito longe sem alvo): voltar vale mais que
	# perseguir zumbi.
	if anchor_distance > SwatSquadBot.LEASH_DISTANCE or (target == null and anchor_distance > SwatSquadBot.LEASH_DISTANCE * 0.6):
		return {"move": Vector2(to_anchor.x, to_anchor.z).normalized(), "jump": false, "sprint": sprint}
	if target == null:
		# Sem alvo no alcance de tiro: cacar o zumbi visivel mais perto dentro do
		# leash (o soldado avanca em sprint e passa a atirar quando chega).
		var hunt := _nearest_visible_zombie(player, zombies_node, SwatSquadBot.LEASH_DISTANCE)
		if hunt != null:
			var to_hunt := hunt.global_position - player.global_position
			to_hunt.y = 0.0
			if to_hunt.length() > SwatSquadBot.ENGAGE_DISTANCE:
				return {"move": Vector2(to_hunt.x, to_hunt.z).normalized(), "jump": false, "sprint": sprint}
		var formation := SwatSquadBot.formation_position(anchor_pos, formation_index)
		var to_slot := formation - player.global_position
		to_slot.y = 0.0
		if to_slot.length() < 0.6:
			return {"move": Vector2.ZERO, "jump": false, "sprint": false}
		return {"move": Vector2(to_slot.x, to_slot.z).normalized(), "jump": false, "sprint": sprint}
	var swarm := _swarm_flee_direction(player.global_position, zombies_node)
	if swarm != Vector2.ZERO:
		return {"move": swarm, "jump": false, "sprint": sprint}
	_strafe_bootstrap(slot, formation_index)
	var strafe_time: float = strafe_timers.get(slot, 0.0) + delta
	strafe_timers[slot] = strafe_time
	var strafe_dir: float = strafe_dirs.get(slot, 1.0)
	if strafe_time > 1.6:
		strafe_timers[slot] = 0.0
		strafe_dir = -strafe_dir
		strafe_dirs[slot] = strafe_dir
	var dir := Vector2(target_offset.x, target_offset.z).normalized()
	var perpendicular := Vector2(-dir.y, dir.x) * strafe_dir
	if target_dist > SwatSquadBot.KEEP_DISTANCE + 1.5:
		return {"move": (dir * 0.85 + perpendicular * 0.35).normalized(), "jump": false, "sprint": sprint}
	if target_dist < SwatSquadBot.ENGAGE_DISTANCE:
		return {"move": (-dir * 0.9 + perpendicular * 0.4).normalized(), "jump": false, "sprint": sprint}
	return {"move": (dir * 0.15 + perpendicular * 0.9).normalized(), "jump": false, "sprint": false}


## Cada bot comeca a ciranda para um lado, para os quatro nao girarem juntos.
func _strafe_bootstrap(slot: int, formation_index: int) -> void:
	if strafe_dirs.has(slot):
		return
	strafe_dirs[slot] = 1.0 if posmod(formation_index, 2) == 0 else -1.0


func _generate_autoplay_input(player: Node3D, slot: int, zombies_node: Node, _tree: SceneTree) -> Dictionary:
	var player_pos := player.global_position
	var target := _find_nearest_live_zombie(player_pos, zombies_node)
	var move_plan := _calculate_movement(player, slot, target, zombies_node)
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


func _calculate_movement(player: Node3D, slot: int, target: Node3D, zombies_node: Node) -> Dictionary:
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
		# Cerco: com 2+ zumbis perto, fugir do centroide deles em sprint vale
		# mais que manter strafe — o bot morria cercado sem matar ninguem.
		var swarm := _swarm_flee_direction(player.global_position, zombies_node)
		if swarm != Vector2.ZERO:
			return {"move": swarm, "jump": false, "sprint": stamina > 20.0}
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


## Direcao de fuga do cerco: 2+ zumbis vivos a menos de 5 m devolvem o vetor
## ANTI-centroide normalizado; sem cerco devolve Vector2.ZERO.
## Uso: var flee := _swarm_flee_direction(player.global_position, zombies_node)
func _swarm_flee_direction(origin: Vector3, zombies_node: Node) -> Vector2:
	var close_count := 0
	var centroid := Vector3.ZERO
	for zombie_node in zombies_node.get_children():
		var zombie := zombie_node as Node3D
		if zombie == null or bool(zombie.get("is_dead")):
			continue
		var offset := zombie.global_position - origin
		offset.y = 0.0
		if offset.length() > 5.0:
			continue
		close_count += 1
		centroid += offset
	if close_count < 2:
		return Vector2.ZERO
	# centroid acumula OFFSETS relativos a origin: fugir = -media deles.
	var flee := -Vector3(centroid.x / float(close_count), 0.0, centroid.z / float(close_count))
	if flee.is_zero_approx():
		return Vector2.ZERO
	var flee_dir := Vector2(flee.x, flee.z).normalized()
	return flee_dir


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


func _find_nearest_live_zombie(player_pos: Vector3, zombies_node: Node, max_distance: float = 55.0) -> Node3D:
	if zombies_node == null:
		return null
	var nearest: Node3D = null
	var nearest_distance := max_distance
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
