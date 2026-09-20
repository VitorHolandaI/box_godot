extends Camera3D

## Camera em primeira pessoa presa na cabeca do alvo. O yaw vem do corpo (ou do
## `camera_yaw` livre do FPS) e o pitch do `view_pitch`. Esconde a cabeca para
## nao ver o interior do boneco. Uso (split_screen_manager):
##   camera.set_script(FIRST_PERSON_CAMERA_SCRIPT)
##   camera.set("target", player)

## Altura dos olhos acima dos pes (boneco tem 2,34 m; cabeca ~1,5 m).
const EYE_HEIGHT := 1.5

var target: Node3D


func _ready() -> void:
	fov = 78.0
	near = 0.05


func _process(_delta: float) -> void:
	if not is_instance_valid(target):
		return
	var is_first_person := bool(target.get("first_person"))
	var yaw := float(target.get("camera_yaw")) if is_first_person else target.rotation.y
	var pitch := float(target.get("view_pitch")) if is_first_person else 0.0
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	global_transform = Transform3D(basis, target.global_position + Vector3.UP * EYE_HEIGHT)
	_set_head_hidden(is_first_person)


## Some com a cabeca (e olhos/capacete) enquanto a camera esta dentro dela.
func _set_head_hidden(hidden: bool) -> void:
	var head := target.get_node_or_null("Model/Head") as Node3D
	if head != null and head.visible == hidden:
		head.visible = not hidden


## Ao trocar de volta para a isometrica a camera e destruida: devolve a cabeca,
## senao ela fica invisivel no modo normal. Uso: automatico.
func _exit_tree() -> void:
	if is_instance_valid(target):
		_set_head_hidden(false)
