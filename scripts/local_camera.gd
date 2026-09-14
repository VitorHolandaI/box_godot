extends Camera3D

const OUTDOOR_OFFSET := Vector3(0.0, 19.0, 17.1)
# Dentro do predio as paredes sao cortadas a meia altura; um angulo um pouco
# inclinado (~65 graus) mostra a altura do corte em vez de linhas finas vistas
# de cima. O y precisa ser igual ao OUTDOOR_OFFSET: o shader deriva a posicao do
# jogador a partir da camera usando esse valor.
const INDOOR_OFFSET := Vector3(0.0, 19.0, 9.0)
const INTERIOR_FOCUS_PARAMETER := &"interior_focus_position"
const INSIDE_CHECK_INTERVAL := 0.15
const CAMERA_SMOOTH_SPEED := 7.0

var target: Node3D
var camera_offset := OUTDOOR_OFFSET
var containing_building: Node3D
var inside_check_elapsed := 0.0
var camera_initialized := false
# A sombra do sol e compartilhada por todas as viewports; so a primeira camera
# local publica o foco usado para esconder andares no passe de sombra.
static var interior_focus_owner: Camera3D = null


func _ready() -> void:
	rotation_degrees = Vector3(-48, 0, 0)
	fov = 72.0
	if not is_instance_valid(interior_focus_owner):
		interior_focus_owner = self


func _exit_tree() -> void:
	if interior_focus_owner == self:
		interior_focus_owner = null
		RenderingServer.global_shader_parameter_set(INTERIOR_FOCUS_PARAMETER, Vector3(0.0, -10000.0, 0.0))


func _process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	inside_check_elapsed -= delta
	if inside_check_elapsed <= 0.0:
		inside_check_elapsed = INSIDE_CHECK_INTERVAL
		containing_building = _find_containing_building()
	camera_offset = INDOOR_OFFSET if is_instance_valid(containing_building) else OUTDOOR_OFFSET
	if interior_focus_owner == self:
		RenderingServer.global_shader_parameter_set(INTERIOR_FOCUS_PARAMETER, target.global_position)
	var desired_position := target.global_position + camera_offset
	# A camera fica sempre atras/acima do alvo (offset x = 0), sem limitar a
	# posicao dentro da casa. Assim o shader de recorte, que deriva a posicao do
	# jogador da direcao da camera, continua seguindo o boneco e o yaw fica 0.
	var desired_transform := Transform3D(Basis.IDENTITY, desired_position).looking_at(target.global_position, Vector3.UP)
	if not camera_initialized:
		global_transform = desired_transform
		camera_initialized = true
		return
	var blend := minf(delta * CAMERA_SMOOTH_SPEED, 1.0)
	global_position = global_position.lerp(desired_position, blend)
	quaternion = quaternion.slerp(desired_transform.basis.get_rotation_quaternion(), blend)


func _find_containing_building() -> Node3D:
	for building in get_tree().get_nodes_in_group("visibility_building"):
		var min_value: Variant = building.get_meta("visibility_min", null)
		var max_value: Variant = building.get_meta("visibility_max", null)
		if min_value is Vector3 and max_value is Vector3 and _position_inside_bounds(target.global_position, min_value, max_value):
			return building as Node3D
	return null


func _position_inside_bounds(position: Vector3, minimum: Vector3, maximum: Vector3) -> bool:
	return position.x >= minimum.x and position.x <= maximum.x and position.y >= minimum.y and position.y <= maximum.y and position.z >= minimum.z and position.z <= maximum.z
