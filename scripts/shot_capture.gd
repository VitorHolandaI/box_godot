extends Node
## Captura automática de frames para o README/docs (dev-only).
##
## Uso: godot --path . --resolution 1920x1080 -- --capture=dist/capturas --shot=hero-horda
## Sem `--capture` este nó nem é criado (main.gd consulta ShotCapture.is_requested),
## então o modo é inerte em jogo normal, servidor e testes.
##
## Cada receita posiciona os jogadores locais, planta uma horda em volta,
## (opcionalmente) troca a câmera e espera um aquecimento antes de salvar o PNG.
## O frame sai do viewport raiz (com HUD e minimapa) ou do SubViewport do
## jogador 0 (sem HUD), conforme `hud` da receita.

const DEFAULT_DIR := "dist/capturas"
const READY_TIMEOUT := 45.0
const RENDER_SETTLE_DRAWS := 3
const MOMENT_TIMEOUT := 16.0
const ZOMBIE_SHOT_PREFIX := "zumbi-"
# Contagem vem do enum de variantes para nao drifar (zombie_mutator.gd).
const ZOMBIE_VARIANT_COUNT := ZombieMutator.TYPE_COUNT
const PERF_HUD_PATH := "Interface/PerformanceHUD"
const ENVIRONMENT_PATH := "Environment"

## Receitas de captura. `player_positions` sobrepõe `player_pos` por slot;
## `camera.offset` é relativo ao jogador 0 e olha para ele (mesma convenção da
## câmera padrão: yaw 0). `zombies.pattern` aceita "cross" (4 faixas de rua, só
## em cruzamento) ou "ring".
const RECIPES := {
	"hero-horda": {
		"hud": true,
		"players": 1,
		"player_pos": Vector3(24.0, 1.0, 24.0),
		"camera": {"offset": Vector3(0.0, 20.0, 17.5), "fov": 72.0},
		"zombies": {"count": 30, "pattern": "cross", "radius_min": 6.0, "radius_max": 18.0, "lane": 3.0},
		"warmup": 2.6,
	},
	"horda-onda-alta": {
		"hud": true,
		"players": 1,
		"player_pos": Vector3(-24.0, 1.0, 24.0),
		"camera": {"offset": Vector3(0.0, 20.0, 18.0), "fov": 72.0},
		"zombies": {"count": 34, "pattern": "cross", "radius_min": 6.0, "radius_max": 20.0, "lane": 3.0},
		"warmup": 2.2,
	},
	"cidade-ampla": {
		"hud": false,
		"players": 1,
		"player_pos": Vector3(24.0, 1.0, 24.0),
		"camera": {"offset": Vector3(0.0, 64.0, 50.0), "fov": 72.0},
		"zombies": {"count": 0},
		"fog": false,
		"warmup": 0.4,
	},
	"sonar": {
		"hud": true,
		"players": 1,
		"player_pos": Vector3(24.0, 1.0, 24.0),
		"camera": {"offset": Vector3(0.0, 22.0, 19.5), "fov": 72.0},
		"zombies": {"count": 18, "pattern": "cross", "radius_min": 8.0, "radius_max": 22.0, "lane": 3.0},
		"warmup": 2.0,
		"actions": ["sonar"],
	},
	"aereo-na-horda": {
		"hud": true,
		"players": 1,
		"player_pos": Vector3(24.0, 1.0, 24.0),
		"camera": {"offset": Vector3(0.0, 23.0, 20.0), "fov": 72.0},
		"zombies": {"count": 28, "pattern": "cross", "radius_min": 6.0, "radius_max": 18.0, "lane": 3.0},
		"pose_health": true,
		"actions": [{"name": "air_strike", "delay": 1.0}],
		"wait_for": "airstrike_bombs",
		"settle": 0.1,
	},
	"granada-na-horda": {
		"hud": true,
		"players": 1,
		"player_pos": Vector3(-24.0, 1.0, -24.0),
		"camera": {"offset": Vector3(0.0, 21.0, 18.5), "fov": 72.0},
		"zombies": {"count": 24, "pattern": "cross", "radius_min": 6.0, "radius_max": 16.0, "lane": 3.0},
		"pose_health": true,
		"actions": [{"name": "grenade_volley", "count": 3, "spacing": 1.0, "delay": 1.0}],
		"wait_for": "grenade_explosion",
		"settle": 0.05,
	},
	"swat-aliado": {
		"hud": true,
		"players": 1,
		"player_pos": Vector3(24.0, 1.0, -24.0),
		"camera": {"offset": Vector3(0.0, 25.0, 22.0), "fov": 72.0},
		"zombies": {"count": 30, "pattern": "cross", "radius_min": 6.0, "radius_max": 17.0, "lane": 3.0},
		"pose_health": true,
		"actions": [{"name": "swat", "delay": 0.3}],
		"warmup": 1.1,
	},
	"airdrop": {
		"hud": true,
		"players": 1,
		"player_pos": Vector3(-24.0, 1.0, 24.0),
		# Camera mais rasa que o padrao: o aviao voa a 16 m e passa por cima da
		# vista top-down, entao precisa de ceu no quadro.
		"camera": {"offset": Vector3(0.0, 22.0, 34.0), "fov": 72.0},
		"zombies": {"count": 8, "pattern": "cross", "radius_min": 24.0, "radius_max": 34.0, "lane": 3.0},
		"pose_health": true,
		"actions": [{"name": "airdrop", "delay": 0.2}],
		"wait_for": "airdrop_dropped",
		"settle": 0.3,
	},
	"airdrop-aviao": {
		"hud": true,
		"players": 1,
		"player_pos": Vector3(-24.0, 1.0, 24.0),
		"camera": {"offset": Vector3(0.0, 14.0, 20.0), "fov": 45.0},
		"aim_at": "plane",
		"zombies": {"count": 6, "pattern": "cross", "radius_min": 26.0, "radius_max": 36.0, "lane": 3.0},
		"pose_health": true,
		"actions": [{"name": "airdrop", "delay": 0.2}],
		"wait_for": "airdrop_plane_near",
		"settle": 0.05,
	},
	"pvp-loadout": {
		"hud": true,
		"players": 1,
		"pose_health": true,
		"wait_for": "pvp_live",
		"moment_timeout": 220.0,
		"actions_after_moment": true,
		"actions": [{"name": "loadout_menu", "delay": 0.4}],
		"settle": 0.8,
	},
	"pvp-mata-mata": {
		"hud": true,
		"players": 1,
		"pose_health": true,
		"wait_for": "pvp_live",
		"moment_timeout": 220.0,
		"settle": 8.0,
	},
	"pvp-fim-de-partida": {
		"hud": true,
		"players": 1,
		"pose_health": true,
		"wait_for": "pvp_match_end",
		"moment_timeout": 280.0,
		"settle": 0.5,
	},
	"tela-dividida": {
		"hud": true,
		"players": 4,
		"player_positions": [
			Vector3(24.0, 1.0, 24.0),
			Vector3(-24.0, 1.0, 24.0),
			Vector3(24.0, 1.0, -24.0),
			Vector3(-24.0, 1.0, -24.0),
		],
		"zombies": {"count": 10, "pattern": "cross", "radius_min": 9.0, "radius_max": 20.0, "lane": 3.0},
		"warmup": 1.7,
	},
	"carro-dirigindo": {
		"hud": true,
		"players": 1,
		"camera": {"offset": Vector3(0.0, 8.0, 12.0), "fov": 68.0},
		"camera_target": "car",
		"camera_follow": "car",
		"zombies": {"count": 0},
		"warmup": 1.4,
		"movie_seconds": 4.8,
	},
	"fps-combate": {
		"hud": true,
		"players": 1,
		"player_pos": Vector3(24.0, 1.0, 24.0),
		"first_person": true,
		"zombies": {"count": 7, "pattern": "ring", "radius_min": 12.0, "radius_max": 18.0, "lane": 2.0, "start_angle_degrees": -90.0},
		"pose_health": true,
		"actions": ["pistol"],
		"warmup": 1.2,
		"movie_seconds": 4.8,
		"movie_action": "attack",
	},
	"multiplayer-pvp": {
		"hud": true,
		"players": 1,
		"camera": {"offset": Vector3(0.0, 7.0, 10.0), "fov": 64.0},
		"aim_at": "pvp_fight",
		"zombies": {"count": 0},
		"pose_health": true,
		"wait_for": "pvp_live",
		"moment_timeout": 220.0,
		"settle": 2.0,
		"movie_seconds": 4.8,
	},
}


static func is_requested() -> bool:
	return not capture_directory().is_empty()


static func capture_directory() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			return argument.trim_prefix("--capture=").strip_edges()
	return ""


static func shot_name() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shot="):
			return argument.trim_prefix("--shot=").strip_edges()
	return ""


static func recipe_names() -> Array[String]:
	var names: Array[String] = []
	for key: Variant in RECIPES.keys():
		names.append(String(key))
	for index in ZOMBIE_VARIANT_COUNT:
		names.append("%s%02d" % [ZOMBIE_SHOT_PREFIX, index])
	names.sort()
	return names


func _ready() -> void:
	_run()


## Distancia de spawn das variantes com habilidade de alcance: nascer colado
## esconde o arranque da investida/pulo/cuspe. CHARGE 5-14 m, JUMP 4-12 m,
## SPIT 4-12 m (o spitter mantem 8).
const VARIANT_LONG_RANGE_DISTANCE := {
	15: 12.0,
	16: 13.0,
	17: 12.0,
	18: 12.0,
	# O stalker e quase invisivel ate chegar perto: nascer colado esconde isso.
	20: 16.0,
}
const VARIANT_DEFAULT_DISTANCE := 7.0


## Receita de GIF por variante de zumbi: um bicho so, camera perto, o jogador
## aguenta os golpes (pose_health) e a cena segue viva depois do PNG para o
## --write-movie gravar o ataque (o GIF e cortado do fim do video).
func _variant_recipe(index: int) -> Dictionary:
	var distance := float(VARIANT_LONG_RANGE_DISTANCE.get(index, VARIANT_DEFAULT_DISTANCE))
	# O curandeiro levanta cadaveres recentes: sem corpo na cena nao ha o que
	# mostrar, entao a receita dele planta vitimas e mata logo depois.
	var corpses := {"count": 3, "radius": 6.0, "kill_after": 0.7} if index == ZombieMutator.Type.HEALER else {}
	# Quem nasce longe precisa de camera mais alta para caber no quadro.
	# Quem nasce longe precisa de camera mais alta para ENTRAR no quadro desde o
	# comeco (12,5 m deixava o spawn de 13 m acima da borda).
	var offset := Vector3(0.0, 16.0, 13.5) if distance > 10.0 else Vector3(0.0, 9.0, 7.5)
	return {
		"hud": true,
		"players": 1,
		"player_pos": Vector3(24.0, 1.0, 24.0),
		"camera": {"offset": offset, "fov": 72.0},
		"zombies": {"count": 1, "variant": index, "pattern": "ring", "radius_min": distance, "radius_max": distance, "lane": 1.0, "start_angle_degrees": -90.0},
		"corpses": corpses,
		"pose_health": true,
		"warmup": 1.2,
		"movie_seconds": 4.4,
	}


## Indice da variante quando o nome da receita e "zumbi-NN" (-1 caso contrario).
func _variant_index_from_shot(shot: String) -> int:
	if not shot.begins_with(ZOMBIE_SHOT_PREFIX):
		return -1
	var raw := shot.trim_prefix(ZOMBIE_SHOT_PREFIX)
	if not raw.is_valid_int():
		return -1
	var index := int(raw)
	return index if index >= 0 and index < ZOMBIE_VARIANT_COUNT else -1


func _run() -> void:
	var main := get_parent()
	var output_directory := capture_directory()
	var shot := shot_name()
	if DisplayServer.get_name() == "headless":
		_abort("captura precisa de janela; '--headless' nao renderiza (use --resolution e um display)")
	var variant_index := _variant_index_from_shot(shot)
	if not RECIPES.has(shot) and variant_index < 0:
		_abort("receita desconhecida '%s'; validas: %s" % [shot, ", ".join(recipe_names())])
	var recipe: Dictionary = _variant_recipe(variant_index) if variant_index >= 0 else RECIPES[shot]
	await _force_window_size()
	if not await _wait_for_world(main):
		_abort("mundo nao ficou pronto em %.0fs (seed, modo ou cidade falhou)" % READY_TIMEOUT)
	var players := _local_players(main)
	var expected_players := int(recipe.get("players", 1))
	if players.size() != expected_players:
		_abort("receita '%s' espera %d jogador(es) local(is) e o jogo tem %d; passe --local-players=%d" % [shot, expected_players, players.size(), expected_players])
	_place_players(main, players, recipe)
	await _apply_view_mode(players, recipe)
	_hide_performance_hud(main)
	_apply_atmosphere(main, recipe)
	_apply_camera(main, players, recipe)
	_plant_horde(main, players, recipe, shot)
	await _plant_corpses(main, players, recipe, shot)
	var keep_alive := bool(recipe.get("pose_health", false))
	var actions_after := bool(recipe.get("actions_after_moment", false))
	if not actions_after:
		await _apply_actions(main, players, recipe)
	if recipe.has("wait_for"):
		# Receitas com efeito (bomba, granada, aviao, fase do PVP) esperam o
		# evento da cena: com os frames lentos da captura, contar segundos erra.
		await _wait_for_moment(main, players[0] as Node3D, String(recipe["wait_for"]), keep_alive, float(recipe.get("moment_timeout", MOMENT_TIMEOUT)))
		if actions_after:
			await _apply_actions(main, players, recipe)
		await _warmup_seconds(float(recipe.get("settle", 0.3)), players[0] as Node3D, keep_alive, main, recipe)
		# Reenquadra por ultimo: o aviao e os bots se movem durante o settle.
		_reframe_camera(main, recipe)
	else:
		await _warmup_seconds(float(recipe.get("warmup", 2.0)), players[0] as Node3D, keep_alive, main, recipe)
	await _wait_frames(RENDER_SETTLE_DRAWS)
	var image := _grab_frame(main, bool(recipe.get("hud", true)))
	if image == null:
		_abort("nao foi possivel ler o viewport para a receita '%s'" % shot)
	var file_path := output_directory.path_join("%s.png" % shot)
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory))
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		_abort("nao foi possivel criar '%s' para a captura: erro %d" % [output_directory, directory_error])
	var save_error := image.save_png(file_path)
	if save_error != OK:
		_abort("falha ao salvar '%s': erro %d" % [file_path, save_error])
	var movie_seconds := float(recipe.get("movie_seconds", 0.0))
	if movie_seconds > 0.0:
		# O video (--write-movie) grava do inicio ao fim do processo: manter a
		# cena viva aqui da ao ffmpeg (-sseof) o trecho do ataque para cortar.
		await _warmup_seconds(movie_seconds, players[0] as Node3D, keep_alive, main, recipe)
	print(JSON.stringify({
		"event": "shot_saved",
		"shot": shot,
		"path": file_path,
		"size": [image.get_width(), image.get_height()],
		"hud": bool(recipe.get("hud", true)),
		"world_seed": NetworkSession.world_seed,
		"window_size": DisplayServer.window_get_size(),
		"viewport_size": Vector2i(get_viewport().get_visible_rect().size),
		"content_scale_size": get_window().content_scale_size,
		"content_scale_mode": get_window().content_scale_mode,
	}))
	get_tree().quit(0)


## O compositor pode entregar a janela num tamanho arbitrario; forca a maior
## area 16:9 que cabe na tela (teto 1920x1080) e confirma lendo de volta.
func _force_window_size() -> void:
	var screen := DisplayServer.screen_get_size()
	var target := Vector2i(mini(screen.x, 1920), mini(screen.y, 1080))
	target.y = int(round(float(target.x) * 9.0 / 16.0)) if int(round(float(target.x) * 9.0 / 16.0)) <= screen.y else target.y
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(target)
	var window := get_window()
	# O compositor Wayland entrega tamanho logico arbitrario (240x291, 960x1161);
	# com stretch em VIEWPORT a resolucao de RENDER vira exatamente o content
	# scale, independente do que a janela fisica ficou.
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.content_scale_size = target
	await _wait_frames(3)
	var split_screen: Variant = get_parent().get("split_screen")
	if split_screen != null and (split_screen as Node).has_method("_layout_views"):
		(split_screen as Node).call("_layout_views")
	await _wait_frames(2)
	print(JSON.stringify({
		"event": "shot_window",
		"screen": screen,
		"requested": target,
		"actual": DisplayServer.window_get_size(),
	}))


## Espera a cidade procedural e os jogadores locais existirem.
func _wait_for_world(main: Node) -> bool:
	var elapsed := 0.0
	while elapsed < READY_TIMEOUT:
		var city_ready_variant: Variant = main.call("_procedural_city_ready")
		var city_ready := city_ready_variant is bool and bool(city_ready_variant)
		if city_ready and not _local_players(main).is_empty():
			return true
		await _wait_frames(1)
		elapsed += get_process_delta_time()
	return false


func _local_players(main: Node) -> Array:
	var players: Array = main.get("local_players")
	var alive: Array = []
	for player_variant: Variant in players:
		var player: Node3D = player_variant as Node3D
		if is_instance_valid(player):
			alive.append(player)
	return alive


## Teleporta cada jogador local para a posicao da receita e zera a velocidade,
## para o frame nao depender de onde o spawn do mundo caiu.
func _place_players(main: Node, players: Array, recipe: Dictionary) -> void:
	var positions: Array = recipe.get("player_positions", [])
	for index in players.size():
		var player: Node3D = players[index] as Node3D
		var target: Vector3 = recipe.get("player_pos", player.global_position)
		if index < positions.size():
			target = positions[index]
		player.global_position = target
		if player.has_method("set_spawn_position"):
			player.call("set_spawn_position", target)
		if player is CharacterBody3D:
			(player as CharacterBody3D).velocity = Vector3.ZERO


func _apply_view_mode(players: Array, recipe: Dictionary) -> void:
	if not bool(recipe.get("first_person", false)):
		return
	for player_variant: Variant in players:
		var player := player_variant as Node3D
		if player != null and player.has_method("set_first_person"):
			player.call("set_first_person", true)
	await _wait_frames(2)


## O overlay de debug (F3) nunca aparece em frame de divulgacao; o campo `hud`
## da receita decide apenas se a captura inclui o HUD/minimapa do jogo.
func _hide_performance_hud(main: Node) -> void:
	var overlay: CanvasItem = main.get_node_or_null(PERF_HUD_PATH) as CanvasItem
	if overlay != null:
		overlay.visible = false


## Algumas receitas (vista aerea) perdem a cidade na nevoa; `"fog": false`
## desliga a nevoa so nesta captura, sem mexer no jogo.
func _apply_atmosphere(main: Node, recipe: Dictionary) -> void:
	if bool(recipe.get("fog", true)):
		return
	var environment_node := main.get_node_or_null(ENVIRONMENT_PATH) as WorldEnvironment
	if environment_node == null or environment_node.environment == null:
		push_warning("shot_capture: receita pede 'fog: false' mas nao achei '%s'" % ENVIRONMENT_PATH)
		return
	environment_node.environment.fog_enabled = false


## Substitui a camera do jogador 0 pela camera da receita: desliga o script
## (que persegue o alvo todo frame) e fixa transform/fov na mao.
func _apply_camera(main: Node, players: Array, recipe: Dictionary) -> void:
	if not recipe.has("camera"):
		return
	var settings: Dictionary = recipe["camera"]
	var camera := _camera_for_player(main, 0)
	if camera == null:
		push_warning("shot_capture: receita pede camera mas nao achei a camera do jogador 0")
		return
	var player: Node3D = players[0] as Node3D
	var camera_target := _camera_target(player, recipe)
	var offset: Vector3 = settings.get("offset", Vector3(0.0, 19.0, 17.1))
	camera.set_process(false)
	camera.global_transform = Transform3D(Basis.IDENTITY, camera_target.global_position + offset).looking_at(camera_target.global_position, Vector3.UP)
	camera.fov = float(settings.get("fov", 72.0))


func _camera_target(player: Node3D, recipe: Dictionary) -> Node3D:
	if String(recipe.get("camera_target", "player")) != "car":
		return player
	for car_variant: Variant in get_tree().get_nodes_in_group("drivable_cars"):
		var car := car_variant as Node3D
		if car != null and is_instance_valid(car):
			return car
	push_warning("shot_capture: receita pede camera no carro, mas nenhum carro existe")
	return player


## Reenquadra a camera no objeto da receita ("aim_at": "plane") logo antes do
## frame: a camera esta com set_process(false) e o aviao se move durante a espera.
func _reframe_camera(main: Node, recipe: Dictionary) -> void:
	var aim := String(recipe.get("aim_at", ""))
	if aim == "plane":
		var planes := _children_with_script(main, "airdrop_plane.gd")
		if planes.is_empty():
			push_warning("shot_capture: receita pede 'aim_at: plane' mas nao ha aviao na cena")
			return
		var plane_camera := _camera_for_player(main, 0)
		if plane_camera == null:
			return
		plane_camera.look_at((planes[0] as Node3D).global_position, Vector3.UP)
		return
	if aim == "pvp_fight":
		var camera := _camera_for_player(main, 0)
		if camera == null:
			return
		var anchor := _pvp_fight_anchor(main)
		if anchor == Vector3.ZERO:
			push_warning("shot_capture: 'aim_at: pvp_fight' sem jogadores remotos na cena")
			return
		var options: Dictionary = recipe.get("camera", {})
		var offset: Vector3 = options.get("offset", Vector3(0.0, 26.0, 24.0))
		camera.set_process(false)
		camera.global_transform = Transform3D(Basis.IDENTITY, anchor + offset).looking_at(anchor + Vector3(0.0, 1.0, 0.0), Vector3.UP)


## Meio do par de jogadores remotos mais proximo: os bots brigam longe da base,
## entao o frame do jogador parado na base nao mostra luta nenhuma.
func _pvp_fight_anchor(main: Node) -> Vector3:
	var remotes := _remote_players(main)
	if remotes.is_empty():
		return Vector3.ZERO
	if remotes.size() == 1:
		return remotes[0].global_position
	var best_distance := INF
	var anchor := remotes[0].global_position
	for i in remotes.size():
		for j in range(i + 1, remotes.size()):
			var a := remotes[i]
			var b := remotes[j]
			var distance := a.global_position.distance_to(b.global_position)
			if distance < best_distance:
				best_distance = distance
				anchor = (a.global_position + b.global_position) * 0.5
	return anchor


## Jogadores que nao sao os locais deste processo (adversarios/bots replicados).
func _remote_players(main: Node) -> Array[Node3D]:
	var found: Array[Node3D] = []
	var players_node := main.get_node_or_null("Players")
	if players_node == null:
		return found
	var locals: Array = main.get("local_players")
	for child: Node in players_node.get_children():
		var player := child as Node3D
		if player == null or locals.has(player):
			continue
		found.append(player)
	return found


func _camera_for_player(main: Node, index: int) -> Camera3D:
	var split_screen: Variant = main.get("split_screen")
	if split_screen == null:
		return null
	var viewports: Variant = (split_screen as Node).get("viewports")
	if not (viewports is Array) or index >= (viewports as Array).size():
		return null
	var viewport: SubViewport = (viewports as Array)[index] as SubViewport
	if viewport == null:
		return null
	for child: Node in viewport.get_children():
		if child is Camera3D:
			return child as Camera3D
	return null


## Acoes da receita, em ordem, cada uma com o proprio delay (segundos depois
## do inicio da captura). Aceita a forma curta "sonar" ou {"name": ..., "delay": 2.2}.
func _apply_actions(main: Node, players: Array, recipe: Dictionary) -> void:
	var actions: Array = recipe.get("actions", [])
	if actions.is_empty():
		return
	var player: Node3D = players[0] as Node3D
	for entry_variant: Variant in actions:
		var entry: Dictionary = entry_variant if entry_variant is Dictionary else {"name": String(entry_variant)}
		await _wait_seconds(float(entry.get("delay", 0.0)))
		await _run_action(main, player, entry)


func _run_action(main: Node, player: Node3D, entry: Dictionary) -> void:
	var action := String(entry.get("name", ""))
	match action:
		"sonar":
			if player.has_method("trigger_sonar"):
				player.call("trigger_sonar")
		"grenade":
			await _press_player_action(player, "grenade")
		"grenade_volley":
			await _throw_grenade_volley(player, int(entry.get("count", 3)), float(entry.get("spacing", 1.0)))
		"air_strike":
			# A call so existe se o jogador tiver a carga; a onda da 1 a cada 3.
			_grant_item(player, PlayerEquipment.Item.AIR_STRIKE, 2)
			await _press_player_action(player, "air_strike")
		"swat":
			_grant_item(player, PlayerEquipment.Item.SWAT, 1)
			await _press_player_action(player, "swat")
		"airdrop":
			_request_airdrop(main, player)
		"pistol":
			await _press_player_action(player, "pistol")
		"loadout_menu":
			_open_loadout_menu(main)
		_:
			push_warning("shot_capture: acao desconhecida '%s'" % action)


## Serie de granadas no mesmo alvo. A explosao dura so 0,55 s (BloaterBurstEffect),
## entao uma granada unica quase nunca cai no frame; em serie sempre tem uma
## explodindo enquanto as outras estao no ar.
func _throw_grenade_volley(player: Node3D, count: int, spacing: float) -> void:
	_grant_item(player, PlayerEquipment.Item.GRENADE, count)
	for _index in count:
		await _press_player_action(player, "grenade")
		await _wait_seconds(spacing)


## O LoadoutMenu reage a evento de input (nao a polling de acao), entao
## Input.action_press nao abre o painel; aqui ele e aberto direto, so na captura.
func _open_loadout_menu(main: Node) -> void:
	var menus := _children_with_script(main, "loadout_menu.gd")
	if menus.is_empty():
		push_warning("shot_capture: nao achei o LoadoutMenu para abrir o painel")
		return
	var panel: Variant = menus[0].get("_panel")
	if panel is CanvasItem:
		(panel as CanvasItem).visible = true


## Simula a tecla da acao por alguns frames. Os flags *_pressed do jogador sao
## reescritos pelo input a cada frame, entao setar a variavel direto nao chega
## no _handle_equipment_input (a granada/call simplesmente nao acontecia).
func _press_player_action(player: Node3D, action: String) -> void:
	var action_name := "%s%s" % [String(player.get("input_action_prefix")), action]
	Input.action_press(action_name)
	await _wait_frames(3)
	Input.action_release(action_name)
	await _wait_frames(2)


## Espera a cena chegar no momento da receita (bomba caindo, granada explodida,
## aviao soltando o crate), mantendo o jogador de pe enquanto isso.
func _wait_for_moment(main: Node, player: Node3D, moment: String, keep_alive: bool, timeout: float) -> void:
	var elapsed := 0.0
	while elapsed < timeout:
		await _wait_frames(1)
		elapsed += get_process_delta_time()
		if keep_alive and is_instance_valid(player):
			var _healed := int(player.call("add_health", 10000))
		if _moment_reached(main, moment, elapsed):
			return
	push_warning("shot_capture: momento '%s' nao chegou em %.1fs" % [moment, timeout])


func _moment_reached(main: Node, moment: String, elapsed: float) -> bool:
	match moment:
		"airstrike_bombs":
			for strike: Node in _children_with_script(main, "air_strike.gd"):
				var bombs: Variant = strike.get("bombs_dropped")
				if bombs != null and int(bombs) >= 2:
					return true
			return false
		"grenade_exploded":
			# A granada some da cena ao explodir; o piso de 1 s evita capturar
			# antes de ela ser arremessada.
			return elapsed > 1.0 and _children_with_script(main, "thrown_grenade.gd").is_empty()
		"airdrop_plane_near":
			# Perto do ponto de soltura (drop_progress, ~0.5 do voo) e nao de 0.92:
			# depois de soltar o aviao ja esta a 160 m e sai minusculo no quadro.
			for plane: Node in _children_with_script(main, "airdrop_plane.gd"):
				var progress := float(plane.get("flight_progress"))
				var drop_at := float(plane.get("drop_progress"))
				if progress >= drop_at - 0.06:
					return true
			return false
		"grenade_explosion":
			return not _find_with_script(main, "bloater_burst_effect.gd").is_empty()
		"pvp_live":
			# O cliente recebe o texto do HUD do servidor: "MATA-MATA ..." com a
			# partida rolando, "FIM ..." quando acaba.
			return String(main.get("pvp_state_text")).begins_with("MATA-MATA")
		"pvp_match_end":
			return String(main.get("pvp_state_text")).begins_with("FIM")
		"airdrop_dropped":
			var planes := _children_with_script(main, "airdrop_plane.gd")
			if planes.is_empty():
				return elapsed > 3.0
			for plane: Node in planes:
				if bool(plane.get("dropped")):
					return true
			return false
		_:
			push_warning("shot_capture: momento desconhecido '%s'" % moment)
			return true


## Procura o script em toda a arvore: a explosao nasce dentro do no de efeitos,
## nao como filho direto da cena.
func _find_with_script(root: Node, script_file: String) -> Array[Node]:
	var found: Array[Node] = []
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		var attached: Script = node.get_script() as Script
		if attached != null and attached.resource_path.ends_with(script_file):
			found.append(node)
		for child: Node in node.get_children():
			pending.append(child)
	return found


## Filhos diretos da cena principal cujo script e o arquivo indicado.
func _children_with_script(main: Node, script_file: String) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in main.get_children():
		var attached: Script = child.get_script() as Script
		if attached != null and attached.resource_path.ends_with(script_file):
			found.append(child)
	return found


## Espera o aquecimento. Com `pose_health` o jogador e mantido de pe: o frame e
## posado e a horda nao pode matar o alvo antes da captura (aereo/swat/airdrop
## precisam de 4 a 8 s de cena).
func _warmup_seconds(seconds: float, player: Node3D, keep_alive: bool, main: Node = null, recipe: Dictionary = {}) -> void:
	var remaining := seconds
	while remaining > 0.0:
		var step := minf(0.25, remaining)
		await _wait_seconds(step)
		remaining -= step
		_follow_camera(main, player, recipe)
		if keep_alive and is_instance_valid(player):
			var _healed := int(player.call("add_health", 10000))
		if String(recipe.get("movie_action", "")) == "attack":
			await _press_player_action(player, "attack")


func _follow_camera(main: Node, player: Node3D, recipe: Dictionary) -> void:
	if main == null or String(recipe.get("camera_follow", "")) != "car":
		return
	var camera := _camera_for_player(main, 0)
	if camera == null:
		return
	var target := _camera_target(player, recipe)
	var settings: Dictionary = recipe.get("camera", {})
	var offset: Vector3 = settings.get("offset", Vector3(0.0, 8.0, 12.0))
	camera.global_transform = Transform3D(Basis.IDENTITY, target.global_position + offset).looking_at(target.global_position, Vector3.UP)


func _grant_item(player: Node3D, item: int, amount: int) -> void:
	var equipment: PlayerEquipment = player.get("equipment")
	if equipment == null:
		push_warning("shot_capture: jogador sem equipment para conceder item %d" % item)
		return
	equipment.add(item, amount)


## Pede o airdrop logo a frente do jogador; o aviao nasce a 190 m e leva ~7,3 s
## ate soltar o crate (SPEED 26 em airdrop_plane.gd).
func _request_airdrop(main: Node, player: Node3D) -> void:
	var forward := -player.global_transform.basis.z
	forward.y = 0.0
	var drop_position: Vector3 = player.global_position + forward.normalized() * 16.0
	drop_position.y = player.global_position.y
	main.call("_launch_airdrop", drop_position, WeaponStats.crate_kinds())


## Vitimas para as variantes que usam cadaver (curandeiro levanta os recentes):
## planta zumbis na rua e mata por dano logo depois, deixando os ragdolls.
func _plant_corpses(main: Node, players: Array, recipe: Dictionary, shot: String) -> void:
	var settings: Dictionary = recipe.get("corpses", {})
	var count := int(settings.get("count", 0))
	if count <= 0:
		return
	var zombies_node := main.get("zombies") as Node3D
	if zombies_node == null:
		push_warning("shot_capture: receita pede cadaveres mas nao achei o no de zumbis")
		return
	var radius := float(settings.get("radius", 6.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(shot + "corpses") + NetworkSession.world_seed
	var player := players[0] as Node3D
	var victims: Array[Node] = []
	for slot in count:
		var angle := TAU * (float(slot) / float(count)) + rng.randf_range(-0.15, 0.15)
		var position := player.global_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		position.y = player.global_position.y
		var result: Variant = main.call("_spawn_zombie", position, 0)
		if result is bool and bool(result) and zombies_node.get_child_count() > 0:
			victims.append(zombies_node.get_child(-1))
	# Deixa os bichos aparecerem antes do golpe (o ragdoll nasce da morte).
	await _wait_seconds(float(settings.get("kill_after", 0.7)))
	for victim: Node in victims:
		if is_instance_valid(victim):
			victim.call("take_damage", 99999, Vector3.ZERO, "knife")
	print(JSON.stringify({"event": "shot_corpses_planted", "shot": shot, "victims": victims.size()}))


## Planta a horda da receita em volta de cada jogador local, com jitter
## deterministico (semente derivada do nome da receita) e espalhando os spawns
## em alguns frames para nao empilhar corpos no mesmo lugar.
func _plant_horde(main: Node, players: Array, recipe: Dictionary, shot: String) -> void:
	var zombie_settings: Dictionary = recipe.get("zombies", {})
	var count := int(zombie_settings.get("count", 0))
	if count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(shot) + NetworkSession.world_seed
	var pattern := String(zombie_settings.get("pattern", "cross"))
	var radius_min := float(zombie_settings.get("radius_min", 6.0))
	var radius_max := float(zombie_settings.get("radius_max", 20.0))
	var lane := float(zombie_settings.get("lane", 3.0))
	# Angulo inicial do anel: -90 graus poe o bicho em -Z, que e o lado OPOSTO a
	# camera (a camera fica em +Z) = na frente do boneco, vindo de frente.
	var start_angle := deg_to_rad(float(zombie_settings.get("start_angle_degrees", 0.0)))
	var spawned := 0
	var planted := 0
	for player_variant: Variant in players:
		var player: Node3D = player_variant as Node3D
		for slot in count:
			var position := _horde_position(player.global_position, pattern, radius_min, radius_max, lane, slot, count, rng, start_angle)
			var variant := int(zombie_settings.get("variant", -1))
			var result: Variant = main.call("_spawn_zombie", position, variant) if variant >= 0 else main.call("_spawn_zombie", position)
			if result is bool and bool(result):
				spawned += 1
			planted += 1
			if planted % 2 == 0:
				await _wait_frames(1)
	print(JSON.stringify({"event": "shot_horde_planted", "shot": shot, "requested": planted, "spawned": spawned}))


## Faixa de rua: distribui a horda pelas 4 direcoes cardinais (norte/sul/leste/
## oeste) a partir do jogador, para os zumbis caírem em asfalto e nao dentro de
## parede. "ring" espalha num anel completo.
func _horde_position(origin: Vector3, pattern: String, radius_min: float, radius_max: float, lane: float, slot: int, count: int, rng: RandomNumberGenerator, start_angle: float = 0.0) -> Vector3:
	var position := origin
	if pattern == "ring":
		var angle := start_angle + TAU * (float(slot) / maxf(float(count), 1.0)) + rng.randf_range(-0.15, 0.15)
		var radius := rng.randf_range(radius_min, radius_max)
		position += Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	else:
		var direction := slot % 4
		var along := radius_min + (radius_max - radius_min) * (float(slot / 4) / maxf(float(count) / 4.0, 1.0))
		var across := rng.randf_range(-lane, lane)
		match direction:
			0:
				position += Vector3(across, 0.0, along)
			1:
				position += Vector3(across, 0.0, -along)
			2:
				position += Vector3(along, 0.0, across)
			_:
				position += Vector3(-along, 0.0, across)
	position.y = origin.y
	return position


func _grab_frame(main: Node, with_hud: bool) -> Image:
	var viewport: Viewport = get_viewport()
	if not with_hud:
		var camera := _camera_for_player(main, 0)
		if camera != null:
			viewport = camera.get_viewport()
	var texture := viewport.get_texture()
	if texture == null:
		return null
	return texture.get_image()


func _wait_seconds(seconds: float) -> void:
	if seconds <= 0.0:
		return
	await get_tree().create_timer(seconds).timeout


func _wait_frames(frames: int) -> void:
	for _index in frames:
		await RenderingServer.frame_post_draw


func _abort(message: String) -> void:
	push_error("shot_capture: %s" % message)
	get_tree().quit(1)
