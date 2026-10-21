# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
extends Node

const ACTIONS := ["up", "down", "left", "right", "jump", "sprint", "attack", "knife", "pistol", "reload", "interact", "sonar", "shotgun", "uzi", "magnum", "drop_weapon", "double_barrel", "carbine", "cycle_weapon", "grenade", "throw_knife", "air_strike", "swat", "buy", "view"]
const SETTINGS_PATH := "user://settings.cfg"
const MAX_SAVED_SERVERS := 12
const MIN_SERVER_PORT := 1024
const MAX_SERVER_PORT := 65535
const OFFICIAL_SERVER := {"address": "bitssand.blog", "port": 27015, "label": "Servidor Oficial"}
const SUPPORTED_RESOLUTIONS: Array[Vector2i] = [
	Vector2i(800, 600),
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
]
## 0 = ilimitado. Limites comuns de monitor para o jogador escolher.
const FPS_OPTIONS: Array[int] = [0, 30, 60, 90, 120, 144, 240]
## Escala de renderizacao 3D: menos pixels renderizados, mais desempenho.
const RENDER_SCALE_OPTIONS: Array[float] = [0.5, 0.65, 0.8, 1.0]
const FOV_MIN := 60
const FOV_MAX := 100

enum GraphicsQuality { LOW, MEDIUM, HIGH, ULTRA }
enum WindowMode { WINDOWED, FULLSCREEN, EXCLUSIVE }

var local_player_count := 1
var player_input_configs: Array[Dictionary] = []
var graphics_resolution := Vector2i(1280, 720)
var graphics_quality := GraphicsQuality.HIGH
var graphics_window_mode := WindowMode.WINDOWED
var graphics_vsync := true
var graphics_max_fps := 60
var graphics_render_scale := 1.0
var graphics_shadows := true
var graphics_fog := true
var graphics_fov := 72
var audio_master_volume := 1.0
var saved_servers: Array[Dictionary] = []
var official_server_seeded := false
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
	_load_graphics_settings()
	Engine.max_fps = graphics_max_fps
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
		elif argument == "--quality=ultra":
			graphics_quality = GraphicsQuality.ULTRA
	_apply_window_settings()
	_apply_audio_settings()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


## Controle arrancado da USB no meio da partida: o dono dele volta ao teclado
## antes que qualquer menu perceba, senao fica sem comando nenhum.
func _on_joy_connection_changed(device_id: int, connected: bool) -> void:
	if connected:
		return
	release_unplugged_joypad(device_id)


## Aplica e salva cada opcao na hora (a UI nao precisa de botao "Aplicar").
## Toda validacao cita o valor recebido e o formato esperado.

func set_resolution(resolution: Vector2i) -> Error:
	if resolution not in SUPPORTED_RESOLUTIONS:
		push_error("Resolucao invalida %s; esperado um valor de %s." % [resolution, SUPPORTED_RESOLUTIONS])
		return ERR_INVALID_PARAMETER
	graphics_resolution = resolution
	_apply_window_settings()
	return _save_graphics_settings()


func set_window_mode(mode: int) -> Error:
	if mode < WindowMode.WINDOWED or mode > WindowMode.EXCLUSIVE:
		push_error("Modo de janela invalido %d; esperado entre %d e %d." % [mode, WindowMode.WINDOWED, WindowMode.EXCLUSIVE])
		return ERR_INVALID_PARAMETER
	graphics_window_mode = mode as WindowMode
	_apply_window_settings()
	return _save_graphics_settings()


func set_vsync(enabled: bool) -> Error:
	graphics_vsync = enabled
	_apply_window_settings()
	return _save_graphics_settings()


func set_max_fps(value: int) -> Error:
	if value != 0 and value < 15:
		push_error("Limite de FPS invalido %d; esperado 0 (ilimitado) ou >= 15." % value)
		return ERR_INVALID_PARAMETER
	graphics_max_fps = value
	_apply_window_settings()
	return _save_graphics_settings()


func set_render_scale(scale: float) -> Error:
	if scale <= 0.0 or scale > 1.0:
		push_error("Escala de render invalida %f; esperado um valor em (0, 1]." % scale)
		return ERR_INVALID_PARAMETER
	graphics_render_scale = scale
	apply_render_scale_to_viewports(get_tree())
	return _save_graphics_settings()


func set_quality(quality: int) -> Error:
	if quality < GraphicsQuality.LOW or quality > GraphicsQuality.ULTRA:
		push_error("Qualidade invalida %d; esperado entre %d e %d." % [quality, GraphicsQuality.LOW, GraphicsQuality.ULTRA])
		return ERR_INVALID_PARAMETER
	graphics_quality = quality as GraphicsQuality
	return _save_graphics_settings()


func set_shadows(enabled: bool) -> Error:
	graphics_shadows = enabled
	apply_live_environment()
	return _save_graphics_settings()


func set_fog(enabled: bool) -> Error:
	graphics_fog = enabled
	apply_live_environment()
	return _save_graphics_settings()


func set_fov(degrees: int) -> Error:
	if degrees < FOV_MIN or degrees > FOV_MAX:
		push_error("FOV invalido %d; esperado entre %d e %d." % [degrees, FOV_MIN, FOV_MAX])
		return ERR_INVALID_PARAMETER
	graphics_fov = degrees
	apply_live_fov()
	return _save_graphics_settings()


func set_master_volume(volume: float) -> Error:
	if volume < 0.0 or volume > 1.0:
		push_error("Volume invalido %f; esperado um valor entre 0 e 1." % volume)
		return ERR_INVALID_PARAMETER
	audio_master_volume = volume
	_apply_audio_settings()
	return _save_graphics_settings()


## Aplica o FOV escolhido sobre um FOV-base de camera (isometrica 72, FPS 78),
## preservando a diferenca entre as duas. Uso: camera.fov = GameConfig.camera_fov(78.0)
func camera_fov(base_default: float) -> float:
	return clampf(float(graphics_fov) + (base_default - 72.0), 30.0, 120.0)


## Copia sombras e nevoa para o mundo. Chamado por main.gd no inicio da partida.
func apply_environment_settings(environment: Environment, sun: DirectionalLight3D) -> void:
	if environment != null:
		environment.fog_enabled = graphics_fog
	if sun != null:
		sun.shadow_enabled = graphics_shadows


## Copia MSAA e escala de render para um SubViewport de jogador.
func apply_viewport_settings(viewport: SubViewport) -> void:
	viewport.msaa_3d = get_msaa_3d()
	viewport.scaling_3d_scale = graphics_render_scale


## Reaplica a escala de render nos SubViewports ja existentes (mudanca em partida).
func apply_render_scale_to_viewports(tree: SceneTree) -> void:
	if tree == null:
		return
	for node in tree.get_root().find_children("*", "SubViewport", true, false):
		(node as SubViewport).scaling_3d_scale = graphics_render_scale


## Reaplica sombras e nevoa no mundo atual (mudanca em partida).
func apply_live_environment() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var environments := tree.get_root().find_children("*", "WorldEnvironment", true, false)
	var suns := tree.get_root().find_children("*", "DirectionalLight3D", true, false)
	var environment: Environment = null
	if not environments.is_empty():
		environment = (environments[0] as WorldEnvironment).environment
	var sun: DirectionalLight3D = null
	if not suns.is_empty():
		sun = suns[0] as DirectionalLight3D
	apply_environment_settings(environment, sun)


## Reaplica o FOV nas cameras atuais (as cameras expoem apply_fov()).
func apply_live_fov() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_root().find_children("*", "Camera3D", true, false):
		if node.has_method("apply_fov"):
			node.call("apply_fov")


static func quality_label(quality: int) -> String:
	match quality:
		GraphicsQuality.LOW:
			return "Baixo"
		GraphicsQuality.MEDIUM:
			return "Medio"
		GraphicsQuality.HIGH:
			return "Alto"
		_:
			return "Ultra"


static func window_mode_label(mode: int) -> String:
	match mode:
		WindowMode.FULLSCREEN:
			return "Tela cheia"
		WindowMode.EXCLUSIVE:
			return "Tela cheia exclusiva"
		_:
			return "Janela"


static func fps_label(value: int) -> String:
	return "Ilimitado" if value <= 0 else "%d FPS" % value


static func render_scale_label(scale: float) -> String:
	return "%d%%" % int(roundf(scale * 100.0))


func get_saved_servers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for server in saved_servers:
		result.append(server.duplicate(true))
	return result


static func saved_servers_with_official_default(configured_servers: Variant, official_server_seeded: bool) -> Array[Dictionary]:
	var loaded_servers: Array[Dictionary] = []
	var official_already_saved := false
	if configured_servers is Array:
		for configured_server: Variant in configured_servers:
			if not configured_server is Dictionary:
				continue
			var address := String(configured_server.get("address", "")).strip_edges()
			var port := int(configured_server.get("port", 0))
			if address.is_empty() or port < MIN_SERVER_PORT or port > MAX_SERVER_PORT:
				continue
			var entry := {"address": address, "port": port, "label": String(configured_server.get("label", ""))}
			loaded_servers.append(entry)
			official_already_saved = official_already_saved or (address == OFFICIAL_SERVER["address"] and port == OFFICIAL_SERVER["port"])
	if not official_server_seeded and not official_already_saved:
		loaded_servers.push_front(OFFICIAL_SERVER.duplicate(true))
	return loaded_servers


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
	match graphics_quality:
		GraphicsQuality.LOW:
			return Viewport.MSAA_DISABLED
		GraphicsQuality.MEDIUM:
			return Viewport.MSAA_2X
		GraphicsQuality.HIGH:
			return Viewport.MSAA_4X
		_:
			return Viewport.MSAA_8X


func get_forest_tree_count() -> int:
	match graphics_quality:
		GraphicsQuality.LOW:
			return 500
		GraphicsQuality.MEDIUM:
			return 1000
		GraphicsQuality.HIGH:
			return 1600
		_:
			return 2200


func uses_world_shadows() -> bool:
	return graphics_shadows


func _load_graphics_settings() -> bool:
	var config := ConfigFile.new()
	var error := config.load(SETTINGS_PATH)
	if error != OK and error != ERR_FILE_NOT_FOUND:
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
		GraphicsQuality.ULTRA
	) as GraphicsQuality
	# Migracao: settings antigos so tinham "fullscreen" (bool).
	var saved_window_mode: Variant = config.get_value("graphics", "window_mode", -1)
	if saved_window_mode is int and int(saved_window_mode) >= 0:
		graphics_window_mode = clampi(int(saved_window_mode), WindowMode.WINDOWED, WindowMode.EXCLUSIVE) as WindowMode
	elif bool(config.get_value("graphics", "fullscreen", false)):
		graphics_window_mode = WindowMode.FULLSCREEN
	graphics_vsync = bool(config.get_value("graphics", "vsync", graphics_vsync))
	graphics_max_fps = maxi(int(config.get_value("graphics", "max_fps", graphics_max_fps)), 0)
	graphics_render_scale = clampf(float(config.get_value("graphics", "render_scale", graphics_render_scale)), 0.5, 1.0)
	graphics_shadows = bool(config.get_value("graphics", "shadows", graphics_shadows))
	graphics_fog = bool(config.get_value("graphics", "fog", graphics_fog))
	graphics_fov = clampi(int(config.get_value("graphics", "fov", graphics_fov)), FOV_MIN, FOV_MAX)
	audio_master_volume = clampf(float(config.get_value("audio", "master_volume", audio_master_volume)), 0.0, 1.0)
	mouse_aim_enabled = bool(config.get_value("gameplay", "mouse_aim", mouse_aim_enabled))
	first_person_enabled = bool(config.get_value("gameplay", "first_person", first_person_enabled))
	var configured_servers: Variant = config.get_value("network", "saved_servers", [])
	official_server_seeded = bool(config.get_value("network", "official_server_seeded", false))
	saved_servers = saved_servers_with_official_default(configured_servers, official_server_seeded)
	if official_server_seeded:
		return true
	official_server_seeded = true
	var seed_error := _save_network_settings()
	if seed_error == OK:
		return true
	official_server_seeded = false
	return false


func _save_graphics_settings() -> Error:
	var config := ConfigFile.new()
	var load_error := config.load(SETTINGS_PATH)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		push_error("Nao foi possivel atualizar %s: %s." % [SETTINGS_PATH, error_string(load_error)])
		return load_error
	config.set_value("graphics", "resolution", graphics_resolution)
	config.set_value("graphics", "quality", int(graphics_quality))
	config.set_value("graphics", "window_mode", int(graphics_window_mode))
	config.set_value("graphics", "vsync", graphics_vsync)
	config.set_value("graphics", "max_fps", graphics_max_fps)
	config.set_value("graphics", "render_scale", graphics_render_scale)
	config.set_value("graphics", "shadows", graphics_shadows)
	config.set_value("graphics", "fog", graphics_fog)
	config.set_value("graphics", "fov", graphics_fov)
	config.set_value("audio", "master_volume", audio_master_volume)
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
	config.set_value("network", "official_server_seeded", official_server_seeded)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_error("Nao foi possivel salvar servidores em %s: %s." % [SETTINGS_PATH, error_string(error)])
	return error


func _apply_window_settings() -> void:
	Engine.max_fps = graphics_max_fps
	if DisplayServer.get_name() == "headless":
		return
	match graphics_window_mode:
		WindowMode.FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		WindowMode.EXCLUSIVE:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(graphics_resolution)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if graphics_vsync else DisplayServer.VSYNC_DISABLED)


func _apply_audio_settings() -> void:
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus < 0:
		return
	var volume := clampf(audio_master_volume, 0.0, 1.0)
	AudioServer.set_bus_mute(master_bus, volume <= 0.001)
	AudioServer.set_bus_volume_db(master_bus, linear_to_db(maxf(volume, 0.001)))


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
	# Tiro no gatilho direito (RT/R2), nao no X: e onde a mao ja esta.
	bindings["attack"] = _create_joy_motion(device_id, JOY_AXIS_TRIGGER_RIGHT, 1.0)
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


## Controles conectados na maquina, no formato que selectable_devices espera.
## Unico ponto que fala com o singleton Input sobre joypads.
## Uso: GameConfig.selectable_devices(0, player_input_configs, GameConfig.connected_joypads())
func connected_joypads() -> Array[Dictionary]:
	var joypads: Array[Dictionary] = []
	for device_id in Input.get_connected_joypads():
		joypads.append({"id": device_id, "name": Input.get_joy_name(device_id)})
	return joypads


## Dispositivos que o jogador do slot pode escolher: o teclado sempre, e cada
## controle conectado que nenhum OUTRO jogador local ja esteja usando.
static func selectable_devices(slot: int, configs: Array, joypads: Array) -> Array[Dictionary]:
	var devices: Array[Dictionary] = [{"type": "keyboard", "id": -1, "name": "Teclado"}]
	for joypad: Variant in joypads:
		if not joypad is Dictionary:
			continue
		var device_id := int((joypad as Dictionary).get("id", -1))
		var users := slots_using_joypad(configs, device_id)
		if not users.is_empty() and not users.has(slot):
			continue
		var fallback_name := "Controle %d" % (device_id + 1)
		devices.append({"type": "gamepad", "id": device_id, "name": String((joypad as Dictionary).get("name", fallback_name))})
	return devices


## Slots locais que estao usando esse controle. Serve para a troca (impedir dois
## jogadores no mesmo controle) e para o desplugue (quem volta para o teclado).
static func slots_using_joypad(configs: Array, device_id: int) -> Array[int]:
	var slots: Array[int] = []
	for slot in configs.size():
		var config: Variant = configs[slot]
		if not config is Dictionary:
			continue
		var entry := config as Dictionary
		if String(entry.get("device_type", "keyboard")) == "gamepad" and int(entry.get("device_id", -1)) == device_id:
			slots.append(slot)
	return slots


## Esse slot local joga no controle? Quem joga no controle mira pelo analogico
## direito, e nao pelo cursor do mouse (que e unico e e do jogador 1).
static func slot_uses_gamepad(configs: Array, slot: int) -> bool:
	if slot < 0 or slot >= configs.size():
		return false
	var config: Variant = configs[slot]
	if not config is Dictionary:
		return false
	return String((config as Dictionary).get("device_type", "keyboard")) == "gamepad"


## Analogico direito do controle desse jogador, cru (sem zona morta). Zero
## quando ele joga no teclado. Unico ponto que le eixo de joypad.
## Uso: GameConfig.player_look_axis(local_slot)
func player_look_axis(slot: int) -> Vector2:
	if not slot_uses_gamepad(player_input_configs, slot):
		return Vector2.ZERO
	var device_id := int(player_input_configs[slot].get("device_id", -1))
	return Vector2(Input.get_joy_axis(device_id, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device_id, JOY_AXIS_RIGHT_Y))


## Troca o dispositivo de um jogador local durante a partida e reaplica o
## InputMap na hora. Devolve false quando o controle ja e de outro jogador, para
## o menu avisar em vez de dois bonecos andarem juntos.
## Uso: GameConfig.set_player_device(1, "gamepad", 0, "Generic X-Box pad")
func set_player_device(slot: int, device_type: String, device_id: int, device_name: String = "") -> bool:
	if slot < 0 or slot >= player_input_configs.size():
		push_error("Troca de dispositivo invalida: jogador=%d; esperado slot local de 0 a %d." % [slot, player_input_configs.size() - 1])
		return false
	if device_type != "keyboard" and device_type != "gamepad":
		push_error("Dispositivo invalido: '%s'; esperado 'keyboard' ou 'gamepad'." % device_type)
		return false
	if device_type == "keyboard":
		player_input_configs[slot] = create_keyboard_config(slot)
		_apply_input_map()
		return true
	var taken_by := slots_using_joypad(player_input_configs, device_id)
	if not taken_by.is_empty() and not taken_by.has(slot):
		return false
	var config := create_gamepad_config(device_id)
	if not device_name.is_empty():
		config["device_name"] = device_name
	player_input_configs[slot] = config
	_apply_input_map()
	return true


## Controle desplugado: quem estava nele volta ao teclado, senao o jogador fica
## sem comando nenhum no meio da partida. Devolve os slots afetados.
## Uso: GameConfig.release_unplugged_joypad(0)
func release_unplugged_joypad(device_id: int) -> Array[int]:
	var affected := slots_using_joypad(player_input_configs, device_id)
	for slot in affected:
		player_input_configs[slot] = create_keyboard_config(slot)
	if not affected.is_empty():
		_apply_input_map()
	return affected


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
