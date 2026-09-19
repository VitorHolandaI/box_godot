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
const FLOOR_PLAN_SCRIPT := preload("res://scripts/floor_plan_generator.gd")

## Arquetipos que o building_generator reconhece hoje (city_generator monta os
## mesmos quatro; "house" e o que os testes de telhado usam).
const ARCHETYPES: Array[String] = ["house", "store", "grocery", "apartment"]
## Distancia entre as construcoes na fileira (a maior planta cabe com folga).
const FILEIRA_ESPACO := 26.0
const CHAO_TAMANHO := Vector3(150.0, 1.0, 70.0)
const VOO_VELOCIDADE := 14.0
const VOO_ACELERACAO := 3.0
## Planta: metro por celula, origem no chao e cor por quarto.
const PLAN_CELL := 1.0
const PLAN_ORIGIN := Vector3(0.0, 0.05, 20.0)
const PLAN_COLORS: Array[Color] = [
	Color(0.85, 0.75, 0.35),
	Color(0.45, 0.70, 0.85),
	Color(0.65, 0.80, 0.45),
	Color(0.85, 0.55, 0.55),
	Color(0.70, 0.60, 0.85),
]

@export var semente := 240912
@export var gerar_na_abertura := true
## Player do jogo na cena, com a camera em terceira pessoa atras dele.
## Desligue para usar a camera de voo de inspecao.
@export var usar_player := true
@export var player_inicial := Vector3(0.0, 1.0, 22.0)
## Quanto a camera fica atras e acima do boneco. A camera de verdade do jogo e
## o local_camera.gd (usado pelo split_screen_manager no PVP/sobrevivência);
## enquanto ele nao entra aqui, este offset imita a distancia dele.
@export var camera_offset := Vector3(0.0, 6.5, 14.0)
@export var camera_foco_altura := 1.2
@export var camera_inicial := Vector3(0.0, 24.0, 44.0)
## Desenha a PLANTA gerada (treemap) como lajes no chao, na frente da fileira.
@export var mostrar_planta := true
@export var planta_celulas := Vector2i(14, 10)

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
	if mostrar_planta:
		build_plan_view()
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


## Planta gerada (floor_plan_generator) desenhada como lajes no chao: da para
## ver a distribuicao dos quartos e as portas sem virar parede ainda.
## Uso: build_plan_view() (chamado no _ready quando mostrar_planta).
func build_plan_view() -> void:
	var plan := FLOOR_PLAN_SCRIPT.generate(planta_celulas.x, planta_celulas.y, semente, FLOOR_PLAN_SCRIPT.HOUSE_PROGRAM)
	var rooms: Array = plan["rooms"]
	for index in rooms.size():
		var room: Dictionary = rooms[index]
		var rect := room["rect"] as Rect2i
		var center := Vector2(float(rect.position.x) + float(rect.size.x) * 0.5, float(rect.position.y) + float(rect.size.y) * 0.5)
		var slab := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(maxf(float(rect.size.x) - 0.2, 0.2), 0.1, maxf(float(rect.size.y) - 0.2, 0.2)) * PLAN_CELL
		var material := StandardMaterial3D.new()
		material.albedo_color = PLAN_COLORS[index % PLAN_COLORS.size()]
		box.material = material
		slab.mesh = box
		slab.position = PLAN_ORIGIN + Vector3(center.x * PLAN_CELL, 0.0, center.y * PLAN_CELL)
		add_child(slab)
		_add_name_label(String(room["name"]), slab.position + Vector3(0.0, 1.2, 0.0))
	# Porta como pilarzinho vermelho na parede comum, para ver a circulacao.
	for door in plan["doors"]:
		var cell: Vector2i = door["cell"]
		var post := MeshInstance3D.new()
		var post_box := BoxMesh.new()
		post_box.size = Vector3(0.4, 0.9, 0.4)
		var post_material := StandardMaterial3D.new()
		post_material.albedo_color = Color(0.9, 0.25, 0.2)
		post_box.material = post_material
		post.mesh = post_box
		post.position = PLAN_ORIGIN + Vector3(float(cell.x) * PLAN_CELL, 0.45, float(cell.y) * PLAN_CELL)
		add_child(post)
	print(JSON.stringify({
		"event": "casas_lab_plan",
		"quartos": rooms.size(),
		"portas": (plan["doors"] as Array).size(),
	}))


## Chao, sol e ambiente: sem isso a cena abre preta e sem piso para as
## construcoes apoiarem.
func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.42, 0.52, 0.66)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.86, 0.86, 0.90)
	# Interior de predio ficava escuro demais para inspecionar a planta.
	environment.ambient_light_energy = 1.15
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.shadow_enabled = true
	sun.light_energy = 1.15
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
