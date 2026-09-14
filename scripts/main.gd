extends Node3D

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")
const ZOMBIE_RAGDOLL_SCENE := preload("res://scenes/zombie_ragdoll.tscn")
const BULLET_SCENE := preload("res://scenes/bullet.tscn")
const FLOCK_COORDINATOR_SCRIPT := preload("res://scripts/zombie_flock_coordinator.gd")
const ZOMBIE_SPAWN_SCHEDULE_SCRIPT := preload("res://scripts/zombie_spawn_schedule.gd")
const ZOMBIE_SPAWN_LOCATOR_SCRIPT := preload("res://scripts/zombie_spawn_locator.gd")
const SURVIVAL_WAVE_CONTROLLER_SCRIPT := preload("res://scripts/survival_wave_controller.gd")
const DOOR_NETWORK_STATE_SCRIPT := preload("res://scripts/door_network_state.gd")
const WAVE_SUPPLY_CONTROLLER_SCRIPT := preload("res://scripts/wave_supply_controller.gd")
const SUPPLY_NETWORK_STATE_SCRIPT := preload("res://scripts/supply_network_state.gd")
const MAX_LOCAL_PLAYERS := 4
const GLOBAL_ACTIVE_ZOMBIE_TARGET := 600
const MAX_CORPSES := 20
const SPAWN_INTERVAL := 1.0
const INPUT_INTERVAL := 1.0 / 30.0
const SNAPSHOT_INTERVAL := 1.0 / 10.0
const MAX_ZOMBIES_PER_SNAPSHOT_PACKET := 4
const MAX_PLAYERS_PER_SNAPSHOT_PACKET := 2
const PLAYER_VISION_UPDATE_INTERVAL := 0.12
const PLAYER_SPAWN_POINTS := [
	Vector3(-13.0, 1.18, 9.5),
	Vector3(-11.0, 1.18, 9.5),
	Vector3(-13.0, 1.18, 12.5),
	Vector3(-11.0, 1.18, 12.5),
]

@onready var players_node: Node3D = $Players
@onready var zombies: Node3D = $Zombies
@onready var split_screen = $Interface/SplitScreen
@onready var sun: DirectionalLight3D = $Sun
@onready var in_game_menu: Control = $Interface/InGameMenu
@onready var safehouse_door: Node = get_node_or_null("GeneratedCity/CentralSafehouse/SafehouseDoor")

var local_players: Array[Node] = []
var network_players: Dictionary = {}
var corpses: Array[Node] = []
var ragdolls: Array[Node] = []
var ragdolls_by_zombie: Dictionary = {}
var spawn_index := 0
var input_elapsed := 0.0
var snapshot_elapsed := 0.0
var zombie_snapshot_sequence := 0
var received_zombie_snapshot_sequence := -1
var received_zombie_snapshot_chunks: Dictionary = {}
var received_zombie_names: Dictionary = {}
var smoke_test_mode := false
var player_vision_elapsed := 0.0
var bot_ai := PlayerBotAI.new()
var zombie_spawn_schedule = ZOMBIE_SPAWN_SCHEDULE_SCRIPT.new(GLOBAL_ACTIVE_ZOMBIE_TARGET, SPAWN_INTERVAL)
var zombie_spawn_locator = ZOMBIE_SPAWN_LOCATOR_SCRIPT.new()
var survival_wave_controller
var wave_supply_controller


func _ready() -> void:
	survival_wave_controller = SURVIVAL_WAVE_CONTROLLER_SCRIPT.new(Callable(self, "_spawn_zombie"))
	if not NetworkSession.is_client():
		wave_supply_controller = WAVE_SUPPLY_CONTROLLER_SCRIPT.new(get_tree(), NetworkSession.world_seed)
		survival_wave_controller.wave_started.connect(wave_supply_controller.refresh_wave)
		survival_wave_controller.wave_started.connect(_reset_wave_lives)
		wave_supply_controller.refresh_wave(0)
	var coordinator = FLOCK_COORDINATOR_SCRIPT.new()
	coordinator.name = "ZombieFlockCoordinator"
	add_child(coordinator)

	if not NetworkSession.bot_name.is_empty():
		DisplayServer.window_set_title("Box Godot - %s" % NetworkSession.bot_name)
	sun.shadow_enabled = GameConfig.uses_world_shadows()
	if NetworkSession.is_offline():
		var configs := _get_local_player_configs()
		for slot in configs.size():
			_spawn_offline_player(slot, configs[slot])
		split_screen.configure(local_players)
		return

	NetworkSession.roster_changed.connect(_reconcile_network_players)
	NetworkSession.server_lost.connect(_on_server_lost)
	_configure_network_zombies()
	_reconcile_network_players()
	smoke_test_mode = NetworkSession.is_server() and "--smoke-test-zombie" in OS.get_cmdline_user_args()
	if smoke_test_mode:
		_spawn_zombie(Vector3(-8.5, 1.0, 9.5))
		var smoke_zombie := zombies.get_child(-1) as CharacterBody3D
		smoke_zombie.set("health", 35)
		smoke_zombie.set("speed", 0.0)
	_notify_scene_loaded.call_deferred()


func _notify_scene_loaded() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout
	NetworkSession.notify_scene_loaded()


func _process(delta: float) -> void:
	_update_player_vision(delta)
	if NetworkSession.is_client() or smoke_test_mode:
		return
	if NetworkSession.survival_mode:
		survival_wave_controller.tick(delta)
		return
	if not zombie_spawn_schedule.is_spawn_due(delta):
		return
	var alive_count := get_tree().get_nodes_in_group("zombies").size()
	if zombie_spawn_schedule.has_capacity(alive_count) and not _spawn_zombie():
		push_warning("Spawn de zumbi adiado: nenhum ponto autorizado esta livre.")


func _physics_process(delta: float) -> void:
	if NetworkSession.is_client():
		if NetworkSession.bot_mode or NetworkSession.autoplay_bot:
			bot_ai.update(delta, get_tree())
		input_elapsed += delta
		if input_elapsed >= INPUT_INTERVAL:
			input_elapsed = 0.0
			_submit_inputs.rpc_id(NetworkSession.SERVER_ID, _collect_local_inputs())
	elif NetworkSession.is_server():
		snapshot_elapsed += delta
		if snapshot_elapsed >= SNAPSHOT_INTERVAL:
			snapshot_elapsed = 0.0
			if not NetworkSession.peer_slots.is_empty() and _loaded_peers_match(NetworkSession.peer_slots, NetworkSession.loaded_peers):
				_send_player_snapshots(_collect_player_states())
				_send_zombie_snapshots(_collect_zombie_states())


func register_corpse(corpse: Node) -> void:
	if NetworkSession.is_client():
		return
	corpses.append(corpse)
	if corpses.size() > MAX_CORPSES:
		var oldest_corpse: Node = corpses.pop_front()
		if is_instance_valid(oldest_corpse):
			oldest_corpse.queue_free()


func spawn_zombie_ragdoll(position: Vector3, rotation: float, velocity: Vector3, z_type: int = 0, appearance_hash: int = 0, source_name: String = "") -> void:
	if not source_name.is_empty() and is_instance_valid(ragdolls_by_zombie.get(source_name)):
		return
	var ragdoll := ZOMBIE_RAGDOLL_SCENE.instantiate()
	add_child(ragdoll)
	ragdoll.position = position
	ragdoll.rotation.y = rotation
	ragdoll.setup(velocity, z_type, appearance_hash)
	ragdolls.append(ragdoll)
	if not source_name.is_empty():
		ragdoll.set_meta("source_zombie", source_name)
		ragdolls_by_zombie[source_name] = ragdoll
	if ragdolls.size() > MAX_CORPSES:
		var oldest_ragdoll: Node = ragdolls.pop_front()
		if is_instance_valid(oldest_ragdoll):
			var oldest_source := String(oldest_ragdoll.get_meta("source_zombie", ""))
			if not oldest_source.is_empty():
				ragdolls_by_zombie.erase(oldest_source)
			oldest_ragdoll.queue_free()


func replicate_bullet_visual(spawn_position: Vector3, bullet_direction: Vector3) -> void:
	if not NetworkSession.is_server():
		return
	for peer_id in NetworkSession.loaded_peers:
		_spawn_bullet_visual.rpc_id(int(peer_id), spawn_position, bullet_direction)


@rpc("authority", "call_remote", "reliable")
func _spawn_bullet_visual(spawn_position: Vector3, bullet_direction: Vector3) -> void:
	if not NetworkSession.is_client():
		return
	AudioFeedback.play_gunshot(spawn_position)
	if NetworkSession.bot_mode or NetworkSession.autoplay_bot:
		bot_ai.notify_bullet()
	var bullet = BULLET_SCENE.instantiate()
	add_child(bullet)
	bullet.global_position = spawn_position
	bullet.setup(bullet_direction, 0, false)
	bullet.add_to_group("network_bullet_visuals")


func _spawn_offline_player(slot: int, config: Dictionary) -> void:
	var player = PLAYER_SCENE.instantiate()
	player.name = "Player%d" % (slot + 1)
	player.local_slot = slot
	player.input_action_prefix = "player_%d_" % (slot + 1)
	player.input_device_name = config["device_name"]
	player.position = _get_player_spawn_position(slot)
	player.set_color_index(slot)
	players_node.add_child(player)
	player.set_spawn_position(player.global_position)
	local_players.append(player)


func _reconcile_network_players() -> void:
	var expected: Dictionary = {}
	for peer_value in NetworkSession.peer_slots:
		var peer_id := int(peer_value)
		var slot_count := clampi(int(NetworkSession.peer_slots[peer_value]), 0, MAX_LOCAL_PLAYERS)
		for slot in slot_count:
			var key := _player_key(peer_id, slot)
			expected[key] = true
			if not network_players.has(key):
				_spawn_network_player(peer_id, slot, key)

	for key in network_players.keys():
		if expected.has(key):
			continue
		var player = network_players[key]
		network_players.erase(key)
		if is_instance_valid(player):
			player.queue_free()
	_refresh_local_views()


func _spawn_network_player(peer_id: int, slot: int, key: String) -> void:
	var player = PLAYER_SCENE.instantiate()
	player.name = "Player_%d_%d" % [peer_id, slot]
	player.owner_peer_id = peer_id
	player.local_slot = slot
	player.simulation_enabled = NetworkSession.is_server()
	player.reads_local_input = false
	player.position = _get_player_spawn_position(network_players.size())
	player.set_color_index(network_players.size())

	if peer_id == NetworkSession.local_peer_id() and slot < GameConfig.player_input_configs.size():
		var config: Dictionary = GameConfig.player_input_configs[slot]
		player.input_action_prefix = "player_%d_" % (slot + 1)
		if NetworkSession.autoplay_bot:
			player.input_device_name = NetworkSession.bot_name if not NetworkSession.bot_name.is_empty() else "Bot"
		else:
			player.input_device_name = config["device_name"]
	else:
		player.input_device_name = "Rede"

	players_node.add_child(player, true)
	player.set_spawn_position(player.global_position)
	network_players[key] = player


func _refresh_local_views() -> void:
	local_players.clear()
	var local_id := NetworkSession.local_peer_id()
	var local_count := int(NetworkSession.peer_slots.get(local_id, 0))
	for slot in local_count:
		var player = network_players.get(_player_key(local_id, slot))
		if player != null:
			local_players.append(player)
	split_screen.configure(local_players)


func _collect_local_inputs() -> Array:
	if NetworkSession.bot_mode or NetworkSession.autoplay_bot:
		return bot_ai.collect_inputs(local_players, zombies, get_tree())
	if in_game_menu.is_open:
		return _collect_neutral_inputs()
	var states: Array = []
	for player in local_players:
		if is_instance_valid(player):
			states.append(player.get_local_input_state())
	return states


func _collect_neutral_inputs() -> Array:
	var states: Array = []
	for player in local_players:
		if not is_instance_valid(player):
			continue
		states.append({
			"slot": player.local_slot,
			"move": Vector2.ZERO,
			"jump": false,
			"sprint": false,
			"attack": false,
			"knife": false,
			"pistol": false,
			"reload": false,
		})
	return states


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_inputs(states: Array) -> void:
	if not NetworkSession.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var allowed_slots := int(NetworkSession.peer_slots.get(sender_id, 0))
	if allowed_slots == 0 or states.size() > allowed_slots:
		return
	for state_value in states:
		if not state_value is Dictionary:
			continue
		var state: Dictionary = state_value
		var slot := int(state.get("slot", -1))
		if slot < 0 or slot >= allowed_slots:
			continue
		var player = network_players.get(_player_key(sender_id, slot))
		if player != null:
			player.apply_network_input(state)


func _collect_player_states() -> Array:
	var states: Array = []
	for key in network_players:
		var player = network_players[key]
		if not is_instance_valid(player):
			continue
		var state: Dictionary = player.get_network_state()
		state["key"] = key
		states.append(state)
	return states


func _collect_zombie_states() -> Array:
	var states: Array = []
	for zombie in zombies.get_children():
		if not zombie.has_method("get_network_state"):
			continue
		var state: Dictionary = zombie.get_network_state()
		state["name"] = zombie.name
		states.append(state)
	return states


func _send_player_snapshots(states: Array) -> void:
	var packet_count := maxi(ceili(float(states.size()) / MAX_PLAYERS_PER_SNAPSHOT_PACKET), 1)
	var door_open := safehouse_door != null and bool(safehouse_door.call("is_open_requested"))
	var building_door_states := DOOR_NETWORK_STATE_SCRIPT.collect(get_tree())
	var supply_states := SUPPLY_NETWORK_STATE_SCRIPT.collect(get_tree())
	for packet_index in packet_count:
		var packet_states: Array = []
		var first_state := packet_index * MAX_PLAYERS_PER_SNAPSHOT_PACKET
		var state_limit := mini(first_state + MAX_PLAYERS_PER_SNAPSHOT_PACKET, states.size())
		for state_index in range(first_state, state_limit):
			packet_states.append(states[state_index])
		for peer_id in NetworkSession.loaded_peers:
			_apply_player_snapshot.rpc_id(int(peer_id), packet_states, door_open, building_door_states, supply_states)


func _send_zombie_snapshots(states: Array) -> void:
	var packet_count := maxi(ceili(float(states.size()) / MAX_ZOMBIES_PER_SNAPSHOT_PACKET), 1)
	for packet_index in packet_count:
		var packet_states: Array = []
		var first_state := packet_index * MAX_ZOMBIES_PER_SNAPSHOT_PACKET
		var state_limit := mini(first_state + MAX_ZOMBIES_PER_SNAPSHOT_PACKET, states.size())
		for state_index in range(first_state, state_limit):
			packet_states.append(states[state_index])
		for peer_id in NetworkSession.loaded_peers:
			_apply_zombie_snapshot.rpc_id(int(peer_id), packet_states, zombie_snapshot_sequence, packet_index, packet_count)
	zombie_snapshot_sequence += 1


@rpc("authority", "call_remote", "unreliable_ordered")
func _apply_player_snapshot(player_states: Array, door_open: bool, building_door_states: Dictionary, supply_states: Array) -> void:
	if not NetworkSession.is_client():
		return
	if safehouse_door != null:
		safehouse_door.call("apply_network_open_state", door_open)
	DOOR_NETWORK_STATE_SCRIPT.apply(get_tree(), building_door_states)
	SUPPLY_NETWORK_STATE_SCRIPT.apply(get_tree(), supply_states)
	for state_value in player_states:
		if not state_value is Dictionary:
			continue
		var state: Dictionary = state_value
		var player = network_players.get(String(state.get("key", "")))
		if player != null:
			player.apply_network_state(state)
			bot_ai.notify_player_state(state, player in local_players)


@rpc("authority", "call_remote", "unreliable_ordered")
func _apply_zombie_snapshot(
		zombie_states: Array,
		snapshot_sequence: int,
		packet_index: int,
		packet_count: int
) -> void:
	if not NetworkSession.is_client():
		return
	if snapshot_sequence < received_zombie_snapshot_sequence or packet_count <= 0:
		return
	if packet_index < 0 or packet_index >= packet_count:
		return
	if snapshot_sequence > received_zombie_snapshot_sequence:
		received_zombie_snapshot_sequence = snapshot_sequence
		received_zombie_snapshot_chunks.clear()
		received_zombie_names.clear()
	received_zombie_snapshot_chunks[packet_index] = true
	if NetworkSession.bot_mode or NetworkSession.autoplay_bot:
		bot_ai.notify_zombie_states(zombie_states)
	_apply_zombie_states(zombie_states)
	if received_zombie_snapshot_chunks.size() == packet_count:
		_remove_missing_network_zombies()


func _apply_zombie_states(states: Array) -> void:
	for state_value in states:
		if not state_value is Dictionary:
			continue
		var state: Dictionary = state_value
		var zombie_name := String(state.get("name", ""))
		if zombie_name.is_empty() or zombie_name.length() > 64:
			continue
		received_zombie_names[zombie_name] = true
		var zombie := zombies.get_node_or_null(NodePath(zombie_name))
		if zombie == null:
			zombie = ZOMBIE_SCENE.instantiate()
			zombie.name = zombie_name
			zombie.simulation_enabled = false
			zombies.add_child(zombie, true)
			var initial_position: Variant = state.get("position")
			if initial_position is Vector3:
				zombie.global_position = initial_position
		zombie.apply_network_state(state)


func _remove_missing_network_zombies() -> void:
	for zombie in zombies.get_children():
		if not received_zombie_names.has(String(zombie.name)):
			zombie.queue_free()


func _configure_network_zombies() -> void:
	if not NetworkSession.is_client():
		return
	for zombie in zombies.get_children():
		zombie.simulation_enabled = false


func _spawn_zombie(position_override: Variant = null) -> bool:
	var spawn_position: Vector3 = position_override as Vector3 if position_override is Vector3 else zombie_spawn_locator.pick_spawn_position(get_tree())
	if spawn_position == ZOMBIE_SPAWN_LOCATOR_SCRIPT.INVALID_SPAWN_POSITION:
		return false
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	zombie.name = "ZombieSpawn%d" % spawn_index
	zombies.add_child(zombie, true)
	zombie.died.connect(_on_zombie_died)
	zombie.global_position = spawn_position
	spawn_index += 1
	return true


func _on_zombie_died(_killer: Node) -> void:
	if NetworkSession.survival_mode:
		survival_wave_controller.register_death()


## Cada nova onda devolve 3 vidas a todos os jogadores, inclusive os que
## haviam sido eliminados. O cliente recebe o novo estado pelos snapshots.
## Uso: conectado ao sinal wave_started do SurvivalWaveController.
func _reset_wave_lives(_wave_index: int) -> void:
	if NetworkSession.is_client():
		return
	for player_node in get_tree().get_nodes_in_group("player"):
		var player := player_node as CharacterBody3D
		if player == null or not is_instance_valid(player) or not player.has_method("restore_wave_lives"):
			continue
		if players_node != null and not players_node.is_ancestor_of(player):
			continue
		player.restore_wave_lives()


func get_survival_hud_text() -> String:
	return survival_wave_controller.get_hud_text() if NetworkSession.survival_mode else ""


func _get_player_spawn_position(slot: int) -> Vector3:
	var spawn_slot := slot % PLAYER_SPAWN_POINTS.size()
	var marker_path := "GeneratedCity/CentralSafehouse/PlayerSpawn%d" % (spawn_slot + 1)
	var marker := get_node_or_null(marker_path) as Marker3D
	return marker.global_position if marker != null else PLAYER_SPAWN_POINTS[spawn_slot]


func _update_player_vision(delta: float) -> void:
	if NetworkSession.is_server() or local_players.is_empty():
		return
	player_vision_elapsed += delta
	if player_vision_elapsed < PLAYER_VISION_UPDATE_INTERVAL:
		return
	player_vision_elapsed = 0.0
	for zombie_node in get_tree().get_nodes_in_group("zombies"):
		var zombie := zombie_node as CharacterBody3D
		if zombie == null or not is_instance_valid(zombie) or bool(zombie.get("is_dead")):
			continue
		var visible_to_player := false
		for player_node in local_players:
			var player := player_node as CharacterBody3D
			if player == null or not is_instance_valid(player) or not player.can_see_position(zombie.global_position):
				continue
			if _has_clear_player_vision(player, zombie):
				visible_to_player = true
				break
		zombie.set_vision_visible(visible_to_player)


func _has_clear_player_vision(player: CharacterBody3D, zombie: CharacterBody3D) -> bool:
	var start := player.global_position + Vector3.UP * 1.1
	var end := zombie.global_position + Vector3.UP * 1.1
	var query := PhysicsRayQueryParameters3D.create(start, end, 1, [player, zombie])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _player_key(peer_id: int, slot: int) -> String:
	return "%d:%d" % [peer_id, slot]


func _loaded_peers_match(expected: Dictionary, loaded: Dictionary) -> bool:
	if expected.size() != loaded.size():
		return false
	for id in expected.keys():
		if not loaded.has(id):
			return false
	return true


func _on_server_lost() -> void:
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _get_local_player_configs() -> Array[Dictionary]:
	var forced_count := _get_forced_local_player_count()
	if forced_count > 0:
		var forced_configs: Array[Dictionary] = []
		for slot in forced_count:
			forced_configs.append(GameConfig.create_keyboard_config(slot))
		GameConfig.configure_local_players(forced_configs)

	if GameConfig.player_input_configs.is_empty():
		var default_configs: Array[Dictionary] = [GameConfig.create_keyboard_config(0)]
		GameConfig.configure_local_players(default_configs)
	return GameConfig.player_input_configs


func _get_forced_local_player_count() -> int:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--local-players="):
			return clampi(int(argument.trim_prefix("--local-players=")), 1, MAX_LOCAL_PLAYERS)
	return 0
