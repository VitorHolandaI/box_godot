class_name ZombieLab
extends Node3D

## Cena de teste montada no editor (F6): os zumbis instanciados no cenario
## simulam sozinhos, porque `simulation_enabled` nasce true (zombie.gd). O
## player e dirigido pelo PlayerBotAI, o mesmo dos bots do jogo, para ver as
## interacoes de cada variante sem montar partida.
## Uso: abra `scenes/zumbi_lab.tscn`, escolha a variante no Inspector de cada
## zumbi (campo `Forced Variant`) e aperte F6.

const REPORT_INTERVAL_SECONDS := 2.0

## Player que o bot dirige. Arraste o no do player da cena aqui.
@export var player: CharacterBody3D
## No pai dos zumbis: e a lista que o bot usa para escolher alvo.
@export var zombies_parent: Node3D
## Camera propria: o player.tscn nao tem camera (ela vem do main/split-screen).
@export var camera: Camera3D
@export var camera_offset := Vector3(0.0, 6.0, 10.0)
## Desligue para assumir o player com o teclado e ver pelo olhar do jogador.
@export var drive_player_with_bot := true

var _bot_ai := PlayerBotAI.new()
var _report_timer := 0.0


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
	print(JSON.stringify({
		"event": "zombie_lab_started",
		"player": is_instance_valid(player),
		"zombies_parent": is_instance_valid(zombies_parent),
		"camera": is_instance_valid(camera),
		"bot_driving": drive_player_with_bot,
	}))


func _physics_process(delta: float) -> void:
	_follow_player(delta)
	if not drive_player_with_bot or not is_instance_valid(player):
		return
	_bot_ai.update(delta, get_tree())
	# collect_inputs exige Array[Node] tipado; [player] cru nao converte.
	var players: Array[Node] = [player]
	var states := _bot_ai.collect_inputs(players, zombies_parent, get_tree())
	if not states.is_empty():
		# call(): o tipo exportado e CharacterBody3D e o metodo e do player.gd.
		player.call("apply_network_input", states[0] as Dictionary)
	_report_timer += delta
	if _report_timer >= REPORT_INTERVAL_SECONDS:
		_report_timer = 0.0
		_report()


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
