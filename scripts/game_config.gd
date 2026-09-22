extends Node

const ACTIONS := ["up", "down", "left", "right", "jump", "sprint", "attack", "knife", "pistol", "reload", "interact", "sonar", "shotgun", "uzi", "magnum", "drop_weapon", "double_barrel", "carbine", "cycle_weapon", "grenade", "throw_knife", "air_strike", "swat", "buy", "view"]
const SETTINGS_PATH := "user://settings.cfg"
const MAX_SAVED_SERVERS := 12
const MIN_SERVER_PORT := 1024
const MAX_SERVER_PORT := 65535
const SUPPORTED_RESOLUTIONS: Array[Vector2i] = [
	Vector2i(800, 600),
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
]

enum GraphicsQuality { LOW, MEDIUM, HIGH }

var local_player_count := 1
var player_input_configs: Array[Dictionary] = []
var graphics_resolution := Vector2i(1280, 720)
var graphics_quality := GraphicsQuality.HIGH
var graphics_fullscreen := false
var saved_servers: Array[Dictionary] = []
## Mira pelo cursor do mouse (isometrica) e cameras em primeira pessoa. O menu
## de configuracoes e a tecla "view" alternam a primeira pessoa por jogador.
var mouse_aim_enabled := true
var first_person_enabled := false
## Verdadeiro enquanto um menu esta aberto: o jogador solta o mouse e para de
## recapturar (senao o cursor sumia ao fechar o menu com a primeira pessoa ligada).
var menu_open := false


## Abre/fecha um menu de jogo cuidando do cursor junto: abrir solta o mouse,
## fechar devolve o controle para a camera de cada jogador local (em primeira
## pessoa ela prende o cursor de novo). Virou funcao unica porque o menu da
## partida fazia esse par e o menu de arma do mata-mata nao fazia: em primeira
## pessoa o painel abria sem cursor para clicar e o mouse-look continuava
## girando o boneco (ver PlayerCharacter._input).
## Uso: GameConfig.set_menu_open(get_tree(), true)
func set_menu_open(tree: SceneTree, open: bool) -> void:
	menu_open = open
	if open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if tree == null:
		return
	for node in tree.get_nodes_in_group("player"):
		if node.get("is_local_controller") == true and node.has_method("_apply_mouse_capture"):
			node.call("_apply_mouse_capture")


func _ready() -> void:
	Engine.max_fps = 60
	_load_graphics_settings()
	var cli_args: Array[String] = []
	cli_args.append_array(OS.get_cmdline_user_args())
	cli_args.append_array(OS.get_cmdline_args())
	for argument in cli_args:
		if argument.begins_with("--max-fps="):
			Engine.max_fps = maxi(int(argument.trim_prefix("--max-fps=")), 15)
		elif argument == "--quality=low":
			graphics_quality = GraphicsQuality.LOW
		elif argument == "--quality=medium":
			graphics_quality = GraphicsQuality.MEDIUM
		elif argument == "--quality=high":
			graphics_quality = GraphicsQuality.HIGH
	_apply_window_settings()


func apply_graphics_settings(resolution: Vector2i, quality: int, fullscreen: bool) -> Error:
	if resolution not in SUPPORTED_RESOLUTIONS:
		push_error("Resolucao invalida %s; esperado um valor de %s." % [resolution, SUPPORTED_RESOLUTIONS])
		return ERR_INVALID_PARAMETER
	if quality < GraphicsQuality.LOW or quality > GraphicsQuality.HIGH:
		push_error("Qualidade invalida %d; esperado valor entre %d e %d." % [quality, GraphicsQuality.LOW, GraphicsQuality.HIGH])
		return ERR_INVALID_PARAMETER
	graphics_resolution = resolution
	graphics_quality = quality as GraphicsQuality
	graphics_fullscreen = fullscreen
	_apply_window_settings()
	return _save_graphics_settings()


func get_saved_servers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for server in saved_servers:
		result.append(server.duplicate(true))
	return result


func save_server(address: String, port: int, label: String = "") -> Error:
	var normalized_address := address.strip_edges()
	if normalized_address.is_empty() or port < MIN_SERVER_PORT or port > MAX_SERVER_PORT:
		push_error("Servidor invalido '%s:%d'; esperado endereco e porta entre %d e %d." % [normalized_address, port, MIN_SERVER_PORT, MAX_SERVER_PORT])
		return ERR_INVALID_PARAMETER
	var entry := {"address": normalized_address, "port": port, "label": label.strip_edges()}
	for index in saved_servers.size():
		if saved_servers[index]["address"] == normalized_address and int(saved_servers[index]["port"]) == port:
			saved_servers[index] = entry
			return _save_network_settings()
	saved_servers.push_front(entry)
	if saved_servers.size() > MAX_SAVED_SERVERS:
		saved_servers.pop_back()
	return _save_network_settings()


func remove_saved_server(address: String, port: int) -> Error:
	for index in range(saved_servers.size() - 1, -1, -1):
		var entry: Dictionary = saved_servers[index]
		if entry["address"] == address and int(entry["port"]) == port:
			saved_servers.remove_at(index)
	return _save_network_settings()


func get_msaa_3d() -> int:
	if graphics_quality == GraphicsQuality.LOW:
		return Viewport.MSAA_DISABLED
	if graphics_quality == GraphicsQuality.MEDIUM:
		return Viewport.MSAA_2X
	return Viewport.MSAA_4X


func get_forest_tree_count() -> int:
	if graphics_quality == GraphicsQuality.LOW:
		return 500
	if graphics_quality == GraphicsQuality.MEDIUM:
		return 1000
	return 1600


func uses_world_shadows() -> bool:
	return graphics_quality != GraphicsQuality.LOW


func _load_graphics_settings() -> bool:
	var config := ConfigFile.new()
	var error := config.load(SETTINGS_PATH)
	if error == ERR_FILE_NOT_FOUND:
		return false
	if error != OK:
		push_error("Nao foi possivel carregar %s: %s." % [SETTINGS_PATH, error_string(error)])
		return false

	var saved_resolution: Variant = config.get_value("graphics", "resolution", graphics_resolution)
	if saved_resolution is Vector2i and saved_resolution in SUPPORTED_RESOLUTIONS:
		graphics_resolution = saved_resolution
	else:
		push_warning("Resolucao salva invalida %s; usando %s." % [saved_resolution, graphics_resolution])
	graphics_quality = clampi(
		int(config.get_value("graphics", "quality", graphics_quality)),
		GraphicsQuality.LOW,
		GraphicsQuality.HIGH
	) as GraphicsQuality
	graphics_fullscreen = bool(config.get_value("graphics", "fullscreen", graphics_fullscreen))
	mouse_aim_enabled = bool(config.get_value("gameplay", "mouse_aim", mouse_aim_enabled))
	first_person_enabled = bool(config.get_value("gameplay", "first_person", first_person_enabled))
	var configured_servers: Variant = config.get_value("network", "saved_servers", [])
	if configured_servers is Array:
		for configured_server in configured_servers:
			if configured_server is Dictionary:
				var address := String(configured_server.get("address", "")).strip_edges()
				var port := int(configured_server.get("port", 0))
				if not address.is_empty() and port >= MIN_SERVER_PORT and port <= MAX_SERVER_PORT:
					saved_servers.append({"address": address, "port": port, "label": String(configured_server.get("label", ""))})
	return true


func _save_graphics_settings() -> Error:
	var config := ConfigFile.new()
	var load_error := config.load(SETTINGS_PATH)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		push_error("Nao foi possivel atualizar %s: %s." % [SETTINGS_PATH, error_string(load_error)])
		return load_error
	config.set_value("graphics", "resolution", graphics_resolution)
	config.set_value("graphics", "quality", int(graphics_quality))
	config.set_value("graphics", "fullscreen", graphics_fullscreen)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_error("Nao foi possivel salvar %s: %s." % [SETTINGS_PATH, error_string(error)])
	return error


## Salva mira pelo mouse e primeira pessoa; valem para os jogadores locais.
## Uso: GameConfig.set_mouse_aim(false)
func set_mouse_aim(enabled: bool) -> Error:
	mouse_aim_enabled = enabled
	return _save_gameplay_settings()


## Uso: GameConfig.set_first_person(true)
func set_first_person(enabled: bool) -> Error:
	first_person_enabled = enabled
	return _save_gameplay_settings()


func _save_gameplay_settings() -> Error:
	var config := ConfigFile.new()
	var load_error := config.load(SETTINGS_PATH)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		push_error("Nao foi possivel atualizar %s: %s." % [SETTINGS_PATH, error_string(load_error)])
		return load_error
	config.set_value("gameplay", "mouse_aim", mouse_aim_enabled)
	config.set_value("gameplay", "first_person", first_person_enabled)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_error("Nao foi possivel salvar gameplay em %s: %s." % [SETTINGS_PATH, error_string(error)])
	return error


func _save_network_settings() -> Error:
	var config := ConfigFile.new()
	var load_error := config.load(SETTINGS_PATH)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		push_error("Nao foi possivel atualizar %s: %s." % [SETTINGS_PATH, error_string(load_error)])
		return load_error
	config.set_value("network", "saved_servers", saved_servers)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_error("Nao foi possivel salvar servidores em %s: %s." % [SETTINGS_PATH, error_string(error)])
	return error


func _apply_window_settings() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if graphics_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(graphics_resolution)


func configure_local_players(configs: Array[Dictionary]) -> void:
	player_input_configs.clear()
	for config in configs:
		player_input_configs.append(config.duplicate(true))
	local_player_count = player_input_configs.size()
	_apply_input_map()


func create_keyboard_config(slot: int) -> Dictionary:
	var profiles := [
		[KEY_W, KEY_S, KEY_A, KEY_D, KEY_SPACE, KEY_SHIFT, KEY_F, KEY_1, KEY_2, KEY_R, KEY_E, KEY_Q, KEY_3, KEY_4, KEY_5, KEY_G, KEY_6, KEY_7, KEY_TAB, KEY_C, KEY_V, KEY_Z, KEY_X, KEY_B, KEY_H],
		[KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SHIFT, KEY_CTRL, KEY_ENTER, KEY_DELETE, KEY_END, KEY_PAGEDOWN, KEY_HOME, KEY_PAGEUP, KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_INSERT, KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_0, KEY_KP_ENTER, KEY_F7],
		[KEY_I, KEY_K, KEY_J, KEY_L, KEY_U, KEY_Y, KEY_O, KEY_7, KEY_8, KEY_P, KEY_0, KEY_9, KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_BRACKETRIGHT, KEY_N, KEY_M, KEY_COMMA, KEY_PERIOD, KEY_BRACKETLEFT, KEY_F7],
		[KEY_Z, KEY_X, KEY_C, KEY_V, KEY_B, KEY_G, KEY_N, KEY_M, KEY_COMMA, KEY_PERIOD, KEY_Q, KEY_H, KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_T, KEY_SEMICOLON, KEY_APOSTROPHE, KEY_SLASH, KEY_BACKSLASH, KEY_MINUS, KEY_F7],
	]
	var bindings: Dictionary = {}
	var profile: Array = profiles[slot % profiles.size()]
	for action_index in ACTIONS.size():
		var event := InputEventKey.new()
		event.physical_keycode = profile[action_index]
		bindings[ACTIONS[action_index]] = event
	return {
		"device_type": "keyboard",
		"device_id": -1,
		"device_name": "Teclado",
		"bindings": bindings,
	}


func create_gamepad_config(device_id: int) -> Dictionary:
	var bindings: Dictionary = {}
	bindings["up"] = _create_joy_motion(device_id, JOY_AXIS_LEFT_Y, -1.0)
	bindings["down"] = _create_joy_motion(device_id, JOY_AXIS_LEFT_Y, 1.0)
	bindings["left"] = _create_joy_motion(device_id, JOY_AXIS_LEFT_X, -1.0)
	bindings["right"] = _create_joy_motion(device_id, JOY_AXIS_LEFT_X, 1.0)
	bindings["jump"] = _create_joy_button(device_id, JOY_BUTTON_A)
	bindings["sprint"] = _create_joy_button(device_id, JOY_BUTTON_B)
	bindings["attack"] = _create_joy_button(device_id, JOY_BUTTON_X)
	bindings["knife"] = _create_joy_button(device_id, JOY_BUTTON_LEFT_SHOULDER)
	bindings["pistol"] = _create_joy_button(device_id, JOY_BUTTON_RIGHT_SHOULDER)
	bindings["reload"] = _create_joy_button(device_id, JOY_BUTTON_Y)
	bindings["interact"] = _create_joy_button(device_id, JOY_BUTTON_DPAD_UP)
	bindings["sonar"] = _create_joy_button(device_id, JOY_BUTTON_DPAD_RIGHT)
	bindings["grenade"] = _create_joy_button(device_id, JOY_BUTTON_DPAD_DOWN)
	bindings["throw_knife"] = _create_joy_button(device_id, JOY_BUTTON_DPAD_LEFT)
	bindings["air_strike"] = _create_joy_button(device_id, JOY_BUTTON_START)
	bindings["swat"] = _create_joy_button(device_id, JOY_BUTTON_BACK)
	return {
		"device_type": "gamepad",
		"device_id": device_id,
		"device_name": "Controle %d" % (device_id + 1),
		"bindings": bindings,
	}


func action_name(slot: int, action: String) -> StringName:
	return StringName("player_%d_%s" % [slot + 1, action])


## Troca uma tecla do jogador local e reaplica o InputMap na hora (menu do Esc).
## Uso: GameConfig.set_player_binding(0, "grenade", evento)
func set_player_binding(slot: int, action: String, event: InputEvent) -> void:
	if slot < 0 or slot >= player_input_configs.size() or not ACTIONS.has(action) or event == null:
		push_error("Troca de tecla invalida: jogador=%d acao='%s' evento=%s; esperado jogador local existente e acao de ACTIONS." % [slot, action, event])
		return
	(player_input_configs[slot]["bindings"] as Dictionary)[action] = event
	_apply_input_map()


func _apply_input_map() -> void:
	for slot in player_input_configs.size():
		var bindings: Dictionary = player_input_configs[slot]["bindings"]
		for action in ACTIONS:
			var mapped_action := action_name(slot, action)
			if not InputMap.has_action(mapped_action):
				InputMap.add_action(mapped_action, 0.2)
			InputMap.action_erase_events(mapped_action)
			var event := bindings.get(action) as InputEvent
			if event == null:
				event = _fallback_binding(slot, action, player_input_configs[slot])
			if event != null:
				InputMap.action_add_event(mapped_action, event)


const FALLBACK_KEYS: Dictionary = {"sonar": KEY_Q, "shotgun": KEY_3, "uzi": KEY_4, "magnum": KEY_5, "drop_weapon": KEY_G, "double_barrel": KEY_6, "carbine": KEY_7, "cycle_weapon": KEY_TAB, "grenade": KEY_C, "throw_knife": KEY_V, "air_strike": KEY_Z, "swat": KEY_X, "buy": KEY_B, "view": KEY_H}
const FALLBACK_JOY_BUTTONS: Dictionary = {
	"sonar": JOY_BUTTON_DPAD_RIGHT,
	# Selecao direta de arma foi para as paletas: D-pad e Start/Back ficaram com
	# granada, faca, ataque aereo e SWAT (no controle ha o ciclo de armas).
	"shotgun": JOY_BUTTON_PADDLE2,
	"uzi": JOY_BUTTON_PADDLE1,
	"magnum": JOY_BUTTON_RIGHT_STICK,
	"drop_weapon": JOY_BUTTON_LEFT_STICK,
	"double_barrel": JOY_BUTTON_PADDLE3,
	"carbine": JOY_BUTTON_PADDLE4,
	"grenade": JOY_BUTTON_DPAD_DOWN,
	"throw_knife": JOY_BUTTON_DPAD_LEFT,
	"air_strike": JOY_BUTTON_START,
	"swat": JOY_BUTTON_BACK,
	"cycle_weapon": JOY_BUTTON_MISC1,
}


## Bindings antigos pode nao conter acoes novas (ex.: sonar, escopeta). Garante
## um controle padrao para o jogador nao ficar sem a acao.
func _fallback_binding(_slot: int, action: String, config: Dictionary) -> InputEvent:
	if not FALLBACK_KEYS.has(action):
		return null
	if String(config.get("device_type", "keyboard")) == "gamepad":
		var device_id := int(config.get("device_id", -1))
		return _create_joy_button(device_id, FALLBACK_JOY_BUTTONS.get(action, JOY_BUTTON_DPAD_RIGHT))
	var key := InputEventKey.new()
	key.physical_keycode = FALLBACK_KEYS[action]
	return key


func _create_joy_button(device_id: int, button_index: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = device_id
	event.button_index = button_index
	return event


func _create_joy_motion(device_id: int, axis: JoyAxis, axis_value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = device_id
	event.axis = axis
	event.axis_value = axis_value
	return event
