class_name CarBotDriver
extends Node

## Motorista de IA do laboratorio do carro: segue uma rota circular de pontos e
## entrega steer/throttle pelo mesmo contrato do jogador (`get_vehicle_input`,
## lido por `DrivableCar.driver_input`). Nao precisa de `enter_vehicle`: o carro
## so chama de volta se o ocupante tiver o metodo.
##
## Uso: bot.car = car; car.enter(bot)

@export var throttle := 0.55
@export var waypoint_radius := 90.0
@export var waypoint_count := 4
## Distancia em que o ponto conta como alcancado e a rota avanca.
@export var waypoint_reach := 7.0
## Angulo (rad) em que o bot ja esterça o maximo; acima disso so freia.
@export var full_steer_angle := 0.7

var car: VehicleBody3D = null
var _waypoints: Array[Vector3] = []
var _index := 0
var _steer := 0.0
var _throttle := 0.0


func _ready() -> void:
	var count := maxi(waypoint_count, 1)
	for step in count:
		var angle := TAU * float(step) / float(count)
		_waypoints.append(Vector3(cos(angle) * waypoint_radius, 0.0, sin(angle) * waypoint_radius))


func _physics_process(_delta: float) -> void:
	if car == null or not is_instance_valid(car) or _waypoints.is_empty():
		_steer = 0.0
		_throttle = 0.0
		return
	var to_target := _waypoints[_index] - car.global_position
	to_target.y = 0.0
	if to_target.length() < waypoint_reach:
		_index = (_index + 1) % _waypoints.size()
		return
	var forward := -car.global_transform.basis.z
	var angle := forward.signed_angle_to(to_target.normalized(), Vector3.UP)
	_steer = clampf(angle / full_steer_angle, -1.0, 1.0)
	# Em curva fechada alivia o acelerador; reta acelera de novo.
	_throttle = throttle if absf(angle) < 1.0 else throttle * 0.35


func get_vehicle_input() -> Dictionary:
	return {"steer": _steer, "throttle": _throttle, "brake": false}
