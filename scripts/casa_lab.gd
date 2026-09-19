class_name CasasLab
extends Node3D

## Inspecao das construcoes procedurais: monta uma de cada arquetipo gerado
## (casa, loja, mercado, apartamento) lado a lado num chao plano, sem partida
## nenhuma, para olhar a planta e o interior de perto.
## Uso: abra `scenes/casas_lab.tscn` e aperte F6. Por padrao o player entra na
## cena e a camera fica em TERCEIRA pessoa atras dele: da para ver o boneco
## andando (WASD anda, mouse mira, ESC solta). Com `usar_player = false` no
## Inspector volta a camera de voo (WASD/Q/E/Shift) para olhar por fora.
##
## O caminho de geracao e o MESMO do jogo: BuildingAssembler3D.build_lot(kind,
## rng), exatamente o que o city_generator.gd:222 chama para montar cada lote -
## inclusive o predio multi-andar, que vai pelo modular_building_builder. Usar o
## assembler de teste (building_assembler.gd) aqui deixava o apartamento como um
## amontoado de paineis: ele nao e o caminho de predio do jogo.

const BUILDING_ASSEMBLER_3D := preload("res://scripts/building_assembler_3d.gd")
const PLAYER_SCENE := preload("res://scenes/player.tscn")

## Arquetipos que o building_generator reconhece hoje (city_generator monta os
## mesmos quatro; "house" e o que os testes de telhado usam).
const ARCHETYPES: Array[String] = ["house", "store", "grocery", "apartment"]
## Distancia entre as construcoes na fileira (a maior planta cabe com folga).
const FILEIRA_ESPACO := 26.0
const CHAO_TAMANHO := Vector3(150.0, 1.0, 70.0)
const VOO_VELOCIDADE := 14.0
const VOO_ACELERACAO := 3.0

@export var semente := 240912
@export var gerar_na_abertura := true
## Player do jogo na cena, com a camera em terceira pessoa atras dele.
## Desligue para usar a camera de voo de inspecao.
@export var usar_player := true
@export var player_inicial := Vector3(0.0, 1.0, 22.0)
## Quanto a camera fica atras e acima do boneco (a terceira pessoa).
@export var camera_offset := Vector3(0.0, 4.5, 8.0)
@export var camera_foco_altura := 1.2
@export var camera_inicial := Vector3(0.0, 24.0, 44.0)

var _camera: Camera3D
var _player: CharacterBody3D
var _gerados := 0


func _ready() -> void:
	# As acoes player_1_* nascem no menu (GameConfig); sem isso o player.gd loga
	# erro de InputMap a cada frame e o WASD nao anda.
	if GameConfig.player_input_configs.is_empty():
		GameConfig.configure_local_players([GameConfig.create_keyboard_config(0)])
	_build_environment()
	if usar_player:
		_build_player()
	else:
		_build_camera()
	if gerar_na_abertura:
		build_row()
	print(JSON.stringify({
		"event": "casas_lab_started",
		"arquetipos": ARCHETYPES.size(),
		"gerados": _gerados,
		"player": usar_player,
	}))


## Monta uma construcao de cada arquetipo em fileira, com o nome flutuando em
## cima. Uso: build_row() (chamado no _ready ou na mao pelo editor).
func build_row() -> void:
	var rng := RandomNumberGenerator.new()
	for index in ARCHETYPES.size():
		var archetype := ARCHETYPES[index]
		rng.seed = semente + index
		var building := BUILDING_ASSEMBLER_3D.build_lot(archetype, rng) as StaticBody3D
		if building == null:
			push_error("casas_lab: arquetipo '%s' nao devolveu StaticBody3D do BuildingAssembler3D.build_lot; esperado lote montado." % archetype)
			continue
		add_child(building)
		var offset := float(index) - float(ARCHETYPES.size() - 1) * 0.5
		building.position = Vector3(offset * FILEIRA_ESPACO, 0.0, 0.0)
		_add_name_label(archetype.to_upper(), building.position + Vector3(0.0, 13.0, 0.0))
		_gerados += 1


## Chao, sol e ambiente: sem isso a cena abre preta e sem piso para as
## construcoes apoiarem.
func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.42, 0.52, 0.66)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.75, 0.78)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)

	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = CHAO_TAMANHO
	shape.shape = box
	ground.add_child(shape)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = CHAO_TAMANHO
	visual.mesh = mesh
	ground.add_child(visual)
	ground.position = Vector3(0.0, -CHAO_TAMANHO.y * 0.5, 0.0)
	add_child(ground)


## Player do jogo com camera em TERCEIRA pessoa: o boneco fica visivel
## andando e a camera o segue de tras (mesmo esquema do lab de zumbis).
func _build_player() -> void:
	_player = PLAYER_SCENE.instantiate() as CharacterBody3D
	if _player == null:
		push_error("casas_lab: player.tscn nao instanciou; esperado CharacterBody3D.")
		return
	add_child(_player)
	_player.global_position = player_inicial
	# A camera nao e filha do player: ela segue a posicao dele, entao nao gira
	# junto com a mira e o boneco continua visivel de tras.
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.global_position = _player.global_position + camera_offset
	_camera.look_at(_player.global_position + Vector3.UP * camera_foco_altura, Vector3.UP)
	_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Segue o boneco de tras: e o que permite ver a caminhada, que era o pedido.
## Uso: chamado a cada tick de fisica.
func _physics_process(delta: float) -> void:
	if not usar_player or _camera == null or not is_instance_valid(_player):
		return
	var focus := _player.global_position
	_camera.global_position = _camera.global_position.lerp(focus + camera_offset, minf(delta * 4.0, 1.0))
	_camera.look_at(focus + Vector3.UP * camera_foco_altura, Vector3.UP)


func _build_camera() -> void:
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.global_position = camera_inicial
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	_camera.current = true


## Placa com o nome do arquetipo acima da construcao, para nao se perder na
## fileira. Uso: _add_name_label("HOUSE", posicao)
func _add_name_label(text: String, position: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 96
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = position
	add_child(label)


## Camera de voo livre: e a forma de olhar o interior de perto sem partida.
## Uso: WASD/Space/Ctrl ou Q/E, com Shift acelerando.
func _process(delta: float) -> void:
	if _camera == null or usar_player:
		return
	var direction := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		direction -= _camera.global_transform.basis.z
	if Input.is_physical_key_pressed(KEY_S):
		direction += _camera.global_transform.basis.z
	if Input.is_physical_key_pressed(KEY_A):
		direction -= _camera.global_transform.basis.x
	if Input.is_physical_key_pressed(KEY_D):
		direction += _camera.global_transform.basis.x
	if Input.is_physical_key_pressed(KEY_E):
		direction += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q):
		direction -= Vector3.UP
	if direction.length_squared() <= 0.0001:
		return
	var speed := VOO_VELOCIDADE
	if Input.is_physical_key_pressed(KEY_SHIFT):
		speed *= VOO_ACELERACAO
	_camera.global_position += direction.normalized() * speed * delta
