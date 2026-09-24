# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
extends Camera3D

## Camera em primeira pessoa presa na cabeca do alvo. A pe: o yaw vem do corpo
## (ou do `camera_yaw` livre do FPS) e o pitch do `view_pitch`; a posicao e o
## corpo + altura dos olhos. Dirigindo: usa a ancora `Seat/DriverEye` do carro,
## entao a camera acompanha a suspensao junto com o boneco e o mouse gira a
## cabeca em relacao ao rumo do veiculo (`drive_look_yaw`). Esconde a cabeca
## para nao ver o interior do boneco. Uso (split_screen_manager):
##   camera.set_script(FIRST_PERSON_CAMERA_SCRIPT)
##   camera.set("target", player)

## Altura dos olhos acima dos pes (boneco tem 2,34 m; cabeca ~1,5 m).
const EYE_HEIGHT := 1.5
## Camada de render usada so para esconder a cabeca desta camera: a cabeca vai
## para essa camada e o cull_mask da camera a exclui. Assim ela some apenas na
## visao de 1a pessoa, e nao no mundo (no split o outro jogador via um boneco
## sem cabeca).
## ATENCAO: `1 << HEAD_RENDER_LAYER` tem de cair dentro do cull_mask padrao do
## Godot (`0xFFFFF`, layers 1..20), senao TODAS as cameras deixam de renderizar
## a cabeca. Layer 20 = bit 19; usar 20 aqui vira layer 21 e some pra todos.
const HEAD_RENDER_LAYER := 19

var target: Node3D
## Layers originais das malhas da cabeca, para restaurar ao sair.
var _head_original_layers: Dictionary = {}


func _ready() -> void:
	fov = 78.0
	near = 0.05
	cull_mask &= ~(1 << HEAD_RENDER_LAYER)
	# Dentro do predio a camera nao pode cortar parede/teto.
	RenderingServer.global_shader_parameter_set(&"cutout_enabled", false)


func _process(_delta: float) -> void:
	if not is_instance_valid(target):
		return
	global_transform = _target_transform()
	_set_head_hidden(bool(target.get("first_person")))


## Transform da camera para o alvo atual. Dirigindo, a posicao e a orientacao
## vem do carro; a pe, do corpo + altura dos olhos.
## Uso: interno de _process
func _target_transform() -> Transform3D:
	var driver_car: Variant = target.get("driving_car")
	if driver_car != null and is_instance_valid(driver_car) and driver_car.has_method("driver_eye_transform"):
		var eye: Transform3D = driver_car.call("driver_eye_transform")
		var look := Basis.from_euler(Vector3(float(target.get("view_pitch")), float(target.get("drive_look_yaw")), 0.0))
		# look aplicado no espaco do carro: olhar em frente = para-brisa.
		return Transform3D(eye.basis * look, eye.origin)
	# Passageiro (atirador) fica em pe e atira como a pe: usa a camera normal.
	var is_first_person := bool(target.get("first_person"))
	var yaw := float(target.get("camera_yaw")) if is_first_person else target.rotation.y
	var pitch := float(target.get("view_pitch")) if is_first_person else 0.0
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	return Transform3D(basis, target.global_position + Vector3.UP * EYE_HEIGHT)


## Some com a cabeca (e olhos/capacete) so nesta camera: move as malhas para a
## camada HEAD_RENDER_LAYER, que o cull_mask desta camera exclui.
func _set_head_hidden(hidden: bool) -> void:
	var head := target.get_node_or_null("Model/Head") as Node3D
	if head == null:
		return
	_set_hidden_layers(head, hidden)


func _set_hidden_layers(node: Node, hidden: bool) -> void:
	if node is VisualInstance3D:
		var visual := node as VisualInstance3D
		if hidden:
			if not _head_original_layers.has(visual):
				_head_original_layers[visual] = visual.layers
			visual.layers = 1 << HEAD_RENDER_LAYER
		elif _head_original_layers.has(visual):
			visual.layers = int(_head_original_layers[visual])
	for child in node.get_children():
		_set_hidden_layers(child, hidden)


## Ao trocar de volta para a isometrica a camera e destruida: devolve a cabeca,
## senao ela fica invisivel no modo normal. Uso: automatico.
func _exit_tree() -> void:
	if is_instance_valid(target):
		_set_head_hidden(false)
	# Devolve o recorte para a isometrica (o manager reavalia se ha varios).
	RenderingServer.global_shader_parameter_set(&"cutout_enabled", true)
