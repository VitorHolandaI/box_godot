class_name ZombieLab
extends Node3D

## Cena de teste montada no editor (F6): os zumbis instanciados no cenario
## simulam sozinhos, porque `simulation_enabled` nasce true (zombie.gd). O
## player e dirigido pelo PlayerBotAI, o mesmo dos bots do jogo, para ver as
## interacoes de cada variante sem montar partida.
## Uso: abra `scenes/zumbi_lab.tscn` e aperte F6.
##
## Teclas (nao conflitam com as do player, que sao WASD/F/R/E/1-7):
##   [ ]  escolhe a variante          - =  quantidade (1,2,5,10,25,50,100)
##   K    spawna a quantidade na frente do player
##   L    mata todos                  M    limpa a cena

const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")
const REPORT_INTERVAL_SECONDS := 2.0
const COUNT_STEPS: Array[int] = [1, 2, 5, 10, 25, 50, 100]
const MAX_SPAWN_BATCH := 200
const SPAWN_DISTANCE := 6.0
const ARC_STEP_DEGREES := 12.0
const HUD_MARGIN := Vector2(16.0, 12.0)

## Player que o bot dirige. Arraste o no do player da cena aqui.
@export var player: CharacterBody3D
## No pai dos zumbis: e a lista que o bot usa para escolher alvo, e onde os
## zumbis novos sao criados.
@export var zombies_parent: Node3D
## Camera propria: o player.tscn nao tem camera (ela vem do main/split-screen).
@export var camera: Camera3D
@export var camera_offset := Vector3(0.0, 6.0, 10.0)
## Desligue para assumir o player com o teclado e ver pelo olhar do jogador.
@export var drive_player_with_bot := true
## Variante que a tecla K cria (indice de ZombieMutator.Type, 0 a 20).
@export var spawn_variant_index := 0
## Quantidade que a tecla K cria por vez.
@export var spawn_count := 1

var _bot_ai := PlayerBotAI.new()
var _report_timer := 0.0
var _hud: Label


func _ready() -> void:
	# Resolve por caminho quando o Inspector nao preencheu (cena aberta direto no
	# editor/headless nao passa pelo main, que e quem normalmente injeta tudo).
	if player == null:
		player = get_node_or_null("Player") as CharacterBody3D
	if zombies_parent == null:
		zombies_parent = get_node_or_null("Zumbis") as Node3D
	if camera == null:
		camera = get_node_or_null("Camera") as Camera3D
	if camera != null:
		camera.current = true
	# As acoes player_1_* so existem depois que o menu configura os jogadores; sem
	# isso o player.gd enche o log de erro de InputMap a cada frame.
	if GameConfig.player_input_configs.is_empty():
		GameConfig.configure_local_players([GameConfig.create_keyboard_config(0)])
	# O caminho de bot do PlayerBotAI e o mesmo de uma partida com bot: puro,
	# sem depender de input local nem de servidor.
	NetworkSession.bot_mode = drive_player_with_bot
	_build_hud()
	_startup_spawn_from_arguments()
	_update_hud()
	print(JSON.stringify({
		"event": "zombie_lab_started",
		"player": is_instance_valid(player),
		"zombies_parent": is_instance_valid(zombies_parent),
		"camera": is_instance_valid(camera),
		"bot_driving": drive_player_with_bot,
	}))


func _physics_process(delta: float) -> void:
	_follow_player(delta)
	# Report antes do return: com o bot desligado (voce no teclado) o log headless
	# continua mostrando zumbis vivos e vida do player.
	_report_timer += delta
	if _report_timer >= REPORT_INTERVAL_SECONDS:
		_report_timer = 0.0
		_report()
	if not drive_player_with_bot or not is_instance_valid(player):
		return
	_bot_ai.update(delta, get_tree())
	# collect_inputs exige Array[Node] tipado; [player] cru nao converte.
	var players: Array[Node] = [player]
	var states := _bot_ai.collect_inputs(players, zombies_parent, get_tree())
	if not states.is_empty():
		# call(): o tipo exportado e CharacterBody3D e o metodo e do player.gd.
		player.call("apply_network_input", states[0] as Dictionary)


func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	match key_event.physical_keycode:
		KEY_BRACKETLEFT:
			_cycle_variant(-1)
		KEY_BRACKETRIGHT:
			_cycle_variant(1)
		KEY_MINUS:
			_step_count(-1)
		KEY_EQUAL:
			_step_count(1)
		KEY_K:
			_spawn_batch()
		KEY_L:
			_kill_all()
		KEY_M:
			_clear_all()


## Troca a variante pela lista de ZombieMutator.Type, dando a volta no fim.
func _cycle_variant(step: int) -> void:
	spawn_variant_index = posmod(spawn_variant_index + step, ZombieMutator.TYPE_COUNT)
	_update_hud()


## Anda pelos degraus de COUNT_STEPS em vez de 1 em 1: subir ate 100 no +/- daria
## 99 apertos. Valor fora da lista (setado no Inspector) recomeca do primeiro.
func _step_count(step: int) -> void:
	var current := COUNT_STEPS.find(spawn_count)
	if current < 0:
		current = 0
	spawn_count = COUNT_STEPS[clampi(current + step, 0, COUNT_STEPS.size() - 1)]
	_update_hud()


## Cria spawn_count zumbis da variante escolhida em arco na frente do player.
func _spawn_batch() -> void:
	if zombies_parent == null or not is_instance_valid(player):
		return
	var total := clampi(spawn_count, 1, MAX_SPAWN_BATCH)
	for index in total:
		var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
		if zombie == null:
			continue
		# forced_variant tem que valer antes do _ready, que e quem le a variante.
		zombie.set("forced_variant", spawn_variant_index)
		zombie.position = _spawn_position_in_front(index, total)
		zombies_parent.add_child(zombie)
	_update_hud()


## Ponto de spawn: arco centrado na frente do player, para um lote nao nascer
## todo empilhado no mesmo lugar.
func _spawn_position_in_front(index: int, total: int) -> Vector3:
	var player_node := player as Node3D
	var focus := player_node.global_position
	var forward := -player_node.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var angle := (float(index) - float(total - 1) * 0.5) * deg_to_rad(ARC_STEP_DEGREES)
	var offset := forward.rotated(Vector3.UP, angle) * SPAWN_DISTANCE
	return focus + offset + Vector3.UP * 0.2


## Tira os zumbis vivos pelo caminho normal de dano, para passar pela morte de
## verdade (drops, ragdoll, habilidades de morte).
func _kill_all() -> void:
	if zombies_parent == null:
		return
	for child in zombies_parent.get_children():
		if bool(child.get("is_dead")):
			continue
		child.call("take_damage", 999999, Vector3.ZERO)


## Remove tudo de uma vez, inclusive cadaveres: a cena volta ao estado inicial.
func _clear_all() -> void:
	if zombies_parent == null:
		return
	for child in zombies_parent.get_children():
		child.queue_free()
	_update_hud()


## Atalho de linha de comando para testar sem teclado (e checar em headless):
##   godot --headless --path . --fixed-fps 60 --quit-after 240 \
##     res://scenes/zumbi_lab.tscn -- --lab-spawn=8
func _startup_spawn_from_arguments() -> void:
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--lab-spawn="):
			continue
		var raw_value := argument.trim_prefix("--lab-spawn=")
		if not raw_value.is_valid_int() or int(raw_value) <= 0 or int(raw_value) > MAX_SPAWN_BATCH:
			push_error("Valor invalido para --lab-spawn: '%s'; esperado inteiro de 1 a %d." % [raw_value, MAX_SPAWN_BATCH])
			return
		spawn_count = int(raw_value)
		_spawn_batch()
		return


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = HUD_MARGIN
	_hud.add_theme_font_size_override("font_size", 20)
	_hud.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_hud.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_hud.add_theme_constant_override("outline_size", 4)
	layer.add_child(_hud)


## Mostra o que a tecla vai criar, para nao spawnar variante errada no escuro.
func _update_hud() -> void:
	if _hud == null:
		return
	_hud.text = "variante [ ]: %s (%d)   quantidade - =: %d   K spawna   L mata   M limpa" % [
		String(ZombieMutator.Type.find_key(spawn_variant_index)),
		spawn_variant_index,
		spawn_count,
	]


## Camera segue o player de longe para caber a interacao inteira na tela.
func _follow_player(delta: float) -> void:
	if camera == null or not is_instance_valid(player):
		return
	var focus := (player as Node3D).global_position
	camera.global_position = camera.global_position.lerp(focus + camera_offset, minf(delta * 4.0, 1.0))
	camera.look_at(focus + Vector3.UP)


## Uma linha a cada REPORT_INTERVAL_SECONDS, tambem legivel no headless: prova
## que a IA rodou (zumbis vivos) e mostra o dano que o bot esta levando.
func _report() -> void:
	var alive := 0
	var total := 0
	if zombies_parent != null:
		for child in zombies_parent.get_children():
			total += 1
			if not bool(child.get("is_dead")):
				alive += 1
	var player_health := 0.0
	if is_instance_valid(player):
		player_health = float(player.get("health"))
	print(JSON.stringify({
		"event": "zombie_lab_report",
		"zombies_alive": alive,
		"zombies_total": total,
		"player_health": snappedf(player_health, 0.1),
	}))
