# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name CasasLab
extends Node3D

## Inspecao das construcoes procedurais pelo caminho REAL do jogo: o blueprint
## sai do ProceduralBuildingGenerator (que agora gera o layout interno pela
## planta procedural, floor_plan_generator) e vira malha pelo
## ProceduralCityAssembler, exatamente como a cidade procedural monta cada lote.
##
## A ideia e GERAR: escolha o tipo (casa/loja/mercado/predio) e aperte Gerar
## para sortear outra seed e ver outro layout interno. Nao ha planta fixa.
##
## Uso: abra `labs/casas_lab.tscn` e aperte F6, ou:
##   godot --path . labs/casas_lab.tscn -- --lab-seed=18273 --lab-kind=house
##   godot --path . labs/casas_lab.tscn -- --lab-voo
##
## Teclas: [ ] troca o tipo, G gera outra seed, ESC solta o mouse para clicar
## nos botoes. A camera e a MESMA do survival/PVP (`local_camera.gd`).

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const FLOOR_PLAN_SCRIPT := preload("res://scripts/floor_plan_generator.gd")
const LOCAL_CAMERA_SCRIPT := preload("res://scripts/local_camera.gd")
const BUILDING_GENERATOR := preload("res://scripts/procedural/generators/building_generator.gd")
const CITY_ASSEMBLER := preload("res://scripts/procedural/assemblers/city_assembler.gd")
const LOT_BLUEPRINT := preload("res://scripts/procedural/blueprints/lot_blueprint.gd")

const KINDS: Array[String] = ["house", "store", "grocery", "gun_shop", "apartment"]
const KIND_LABELS := {"house": "CASA", "store": "LOJA", "grocery": "MERCADO", "gun_shop": "LOJA DE ARMAS", "apartment": "PREDIO"}

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
@export var kind_inicial := "house"
@export var gerar_na_abertura := true
## Player do jogo na cena, com a camera do survival/PVP. Desligue para usar a
## camera de voo de inspecao.
@export var usar_player := true
@export var player_inicial := Vector3(0.0, 1.0, 22.0)
@export var camera_inicial := Vector3(0.0, 24.0, 44.0)
## Desenha a PLANTA gerada (treemap) como lajes no chao. Desligado por padrao
## para nao competir com a inspecao da construcao.
@export var mostrar_planta := false
@export var planta_celulas := Vector2i(10, 8)

var _camera: Camera3D
var _player: CharacterBody3D
var _slot: Node3D
var _hud: Label
var _ui_mode := false


func _ready() -> void:
	_read_lab_arguments()
	# As acoes player_1_* nascem no menu (GameConfig); sem isso o player.gd loga
	# erro de InputMap a cada frame e o WASD nao anda.
	if GameConfig.player_input_configs.is_empty():
		GameConfig.configure_local_players([GameConfig.create_keyboard_config(0)])
	_build_environment()
	if usar_player:
		_build_player()
	else:
		_build_camera()
	_build_ui()
	if gerar_na_abertura:
		show_current()
	if mostrar_planta:
		build_plan_view()
	print(JSON.stringify({
		"event": "casas_lab_started",
		"kind": _current_kind(),
		"semente": semente,
		"player": usar_player,
	}))


## Monta a construcao do tipo e seed atuais, trocando a que estava na cena.
## Uso: show_current() (chamado no _ready e pelos botoes/teclas).
func show_current() -> void:
	_clear_variant()
	var kind := _current_kind()
	var blueprint = BUILDING_GENERATOR.generate(semente, kind)
	_slot = Node3D.new()
	_slot.name = "Gerado"
	add_child(_slot)
	var lot = LOT_BLUEPRINT.new("Lab_%s_%d" % [kind, semente], semente, "urban", Vector2.ZERO, Vector2(blueprint.width, blueprint.depth))
	lot.building = blueprint
	lot.building_rotation_y = 0.0
	CITY_ASSEMBLER.assemble_lot(_slot, lot)
	_update_hud()
	print(JSON.stringify({
		"event": "casas_lab_built",
		"kind": kind,
		"seed": semente,
		"arquetipo": String(blueprint.archetype),
		"tamanho": [blueprint.width, blueprint.depth],
		"comodos": _room_summary(blueprint),
	}))


## Contagem de comodos por tipo (todos os andares), para conferir que o programa
## mudou com a seed. Uso: interno do show_current.
func _room_summary(blueprint) -> String:
	var counts := {}
	for floor_blueprint in blueprint.floor_blueprints:
		for placement in floor_blueprint.units:
			_accumulate_room_types(placement["blueprint"], counts)
	var parts: Array[String] = []
	for room_type in counts:
		parts.append("%s x%d" % [room_type, counts[room_type]])
	return ", ".join(parts)


## Soma os tipos de comodo da unidade no dicionario de contagem. Uso: interno.
func _accumulate_room_types(unit, counts: Dictionary) -> void:
	for room in unit.rooms:
		var room_type := String(room.room_type)
		counts[room_type] = int(counts.get(room_type, 0)) + 1


func _current_kind() -> String:
	if KINDS.has(kind_inicial):
		return kind_inicial
	return KINDS[0]


func _clear_variant() -> void:
	if is_instance_valid(_slot):
		remove_child(_slot)
		_slot.queue_free()
	_slot = null


## Troca o tipo (casa/loja/mercado/predio) dando a volta no fim.
func _cycle_kind(step: int) -> void:
	var index := KINDS.find(_current_kind())
	kind_inicial = KINDS[posmod(index + step, KINDS.size())]
	show_current()


## Sorteia outra seed e regenera: e o "gerar" que mostra a variacao procedural.
func _generate_new_seed() -> void:
	semente = randi() % 1000000
	show_current()


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


## Player do jogo com a camera do survival/PVP (local_camera.gd com target no
## player), exatamente como o split_screen_manager monta.
func _build_player() -> void:
	_player = PLAYER_SCENE.instantiate() as CharacterBody3D
	if _player == null:
		push_error("casas_lab: player.tscn nao instanciou; esperado CharacterBody3D.")
		return
	add_child(_player)
	_player.global_position = player_inicial
	_camera = Camera3D.new()
	_camera.set_script(LOCAL_CAMERA_SCRIPT)
	add_child(_camera)
	_camera.set("target", _player)
	_camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_camera() -> void:
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.global_position = camera_inicial
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	_camera.current = true


## Barra: tipo (◀ ▶), Gerar e a seed atual. Uso: chamado no _ready.
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bar := HBoxContainer.new()
	bar.position = Vector2(16.0, 16.0)
	layer.add_child(bar)

	var previous := Button.new()
	previous.text = "◀ tipo"
	previous.pressed.connect(func() -> void: _cycle_kind(-1))
	bar.add_child(previous)

	_hud = Label.new()
	_hud.custom_minimum_size = Vector2(300.0, 0.0)
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hud.add_theme_font_size_override("font_size", 18)
	bar.add_child(_hud)

	var next := Button.new()
	next.text = "tipo ▶"
	next.pressed.connect(func() -> void: _cycle_kind(1))
	bar.add_child(next)

	var generate := Button.new()
	generate.text = "🎲 Gerar"
	generate.pressed.connect(_generate_new_seed)
	bar.add_child(generate)


func _update_hud() -> void:
	if _hud == null:
		return
	var hint := "ESC solta o mouse" if not _ui_mode else "ESC volta a andar"
	_hud.text = "%s · seed %d · [ ] tipo · G gerar · %s" % [KIND_LABELS.get(_current_kind(), _current_kind()), semente, hint]


## ESC alterna entre andar (mouse preso) e clicar nos botoes (mouse solto).
func _set_ui_mode(enabled: bool) -> void:
	_ui_mode = enabled
	if is_instance_valid(_player):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if enabled else Input.MOUSE_MODE_CAPTURED
		_player.set("reads_local_input", not enabled)
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	match key_event.physical_keycode:
		KEY_LEFT, KEY_BRACKETLEFT:
			_cycle_kind(-1)
		KEY_RIGHT, KEY_BRACKETRIGHT:
			_cycle_kind(1)
		KEY_G:
			_generate_new_seed()
		KEY_ESCAPE:
			_set_ui_mode(not _ui_mode)
		_:
			# ABNT2 nao cai em KEY_BRACKETRIGHT para ']'; o unicode cobre.
			if key_event.unicode == 91:
				_cycle_kind(-1)
			elif key_event.unicode == 93:
				_cycle_kind(1)


## Le os argumentos do lab (depois de `--`). Uso: --lab-seed=N, --lab-kind=house,
## --lab-voo.
func _read_lab_arguments() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--lab-voo":
			usar_player = false
		elif argument.begins_with("--lab-seed="):
			var raw_seed := argument.trim_prefix("--lab-seed=")
			if raw_seed.is_valid_int():
				semente = int(raw_seed)
			else:
				push_error("Valor invalido para --lab-seed: '%s'; esperado inteiro." % raw_seed)
		elif argument.begins_with("--lab-kind="):
			var raw_kind := argument.trim_prefix("--lab-kind=")
			if KINDS.has(raw_kind):
				kind_inicial = raw_kind
			else:
				push_error("Valor invalido para --lab-kind: '%s'; esperado um de %s." % [raw_kind, KINDS])


## Placa de nome usada pela planta. Uso: _add_name_label("SALA", posicao)
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
