class_name DrivableCar
extends VehicleBody3D

## Carro dirigivel do MVP. O jogador entra com o "interagir" (E) quando esta
## perto; enquanto dirige ele fica preso ao assento, entao a camera isometrica
## que segue o player passa a seguir o carro sem codigo de camera proprio.
##
## Uso:
##   if not car.is_occupied(): car.enter(player)
##   car.exit_car()

const VISUAL_SCENE: PackedScene = preload("res://assets/models/jeep_military/military_jeep.glb")
## O jipe militar (Zsky, CC-BY 3.0) tem ~2,33 m de altura e o boneco do jogo tem
## 2,22 m: no fator 1,3 o veiculo casa com o boneco, como os demais carros.
const VISUAL_SCALE := 1.3
## O jipe encara +Z no GLB; o Godot usa -Z como frente. Gira 180 graus para o bico
## apontar para onde engine_force positivo empurra.
const MODEL_YAW := PI
## No GLB o fundo das rodas fica em y=-0,99. Este lift sobe o modelo para o pneu
## tocar o chao do carro (y=0) depois da escala.
const MODEL_GROUND_LIFT := 0.99
## Nome (case-insensitive) do material do para-brisa: vira transparente para a
## camera interna enxergar a rua.
const WINDOW_MATERIAL_KEYWORD := "window"
## Cor/alpha do vidro do para-brisa.
const WINDOW_COLOR := Color(0.6, 0.75, 0.85, 0.22)
## Abaixo disso o carro nao machuca ninguem (manobra, marcha lenta).
const RUN_OVER_MIN_SPEED := 4.0
const RUN_OVER_MAX_DAMAGE := 220
## Fracao do dano de atropelamento que volta para o carro: bater em um corpo
## tambem machuca a lataria, proporcional (zumbi e leve, quase nada).
const RUN_OVER_RECOIL := 0.08
## Forca do freio com o carro vazio, para nao sair sozinho ladeira abaixo.
const PARKING_BRAKE := 12.0
## Altura dos olhos acima do assento quando a cena nao tem o no DriverEye.
const DRIVER_EYE_FALLBACK_HEIGHT := 1.05

## Emitido quando a vida do carro zera (para o HUD/som). Uso: server e local.
signal car_destroyed

@export var max_engine_force := 1200.0
@export var max_steer := 0.32
@export var steer_speed := 2.6
## Teto de velocidade: sem arrasto o carro aceleraria sem limite com engine_force
## constante. Acima disso o motor e cortado.
@export var max_speed_kmh := 45.0
## Vida do carro: balas e explosoes entram por take_damage; em 0 ele para de vez.
@export var max_health := 500
## Armadura: fracao do dano recebido que a lataria de metal deixa passar. O carro
## serve de cobertura para quem esta dentro, entao toma menos que um boneco.
@export_range(0.05, 1.0) var damage_armor := 0.5
## Tanque cheio. Gasta com o acelerador (marcha lenta nao consome).
@export var max_fuel := 100.0
## Consumo por segundo com o acelerador acionado.
@export var fuel_burn_per_second := 1.4
## Queda brusca de velocidade (m/s) num unico tick de fisica = batida. Frear
## perde ~0,1 m/s por tick; bater em parede derruba metros de uma vez.
const CRASH_SPEED_LOSS := 2.0
## Vida perdida por m/s de queda acima do corte.
const CRASH_DAMAGE_PER_SPEED := 7.0
## Intervalo minimo entre dois danos de impacto (um choque com ricochete pode
## gerar mais de uma queda de velocidade).
const CRASH_COOLDOWN := 0.35

## Jogador que esta dirigindo; null quando vazio.
var driver: Node = null
var health := 500
var fuel := 100.0
var is_destroyed := false
## Tempo restante ate o proximo dano de impacto (varios contatos no mesmo choque
## contam como um so). Uso: _track_crash_damage
var _crash_cooldown := 0.0
## Velocidade do tick anterior, para medir a queda brusca de uma batida.
var _previous_speed := 0.0

## Volante visual proprio: o aro gira com o esterço por cima do volante estatico
## do modelo (o GLB e malha unica e nao da pra girar so a peca do volante).
const STEERING_WHEEL_SPIN := 5.0

@onready var seat: Node3D = $Seat
@onready var exit_point: Node3D = $ExitPoint
## Assento traseiro: onde um passageiro pode sentar e atirar por cima do roll bar.
@onready var gunner_seat: Node3D = get_node_or_null("GunnerSeat")
## Ancora dos olhos do atirador traseiro (camera em 1a pessoa do passageiro).
@onready var gunner_eye: Node3D = get_node_or_null("GunnerEye")
## Ancora dos olhos do motorista, dentro da cabine aberta do jipe. O modelo e um
## jipe militar aberto, entao a camera fica no banco do motorista e ve a rua pelo
## para-brisa (tornado transparente em _build_visual).
@onready var driver_eye: Node3D = get_node_or_null("DriverEye")
@onready var steering_spin: Node3D = get_node_or_null("SteeringWheel/Tilt/Spin")


func _ready() -> void:
	add_to_group("drivable_cars")
	health = max_health
	fuel = max_fuel
	# Carência inicial: o carro nasce alguns centimetros no ar e cai; a queda de
	# spawn nao pode contar como batida.
	_crash_cooldown = 1.0
	_tune_suspension()
	# Centro de massa baixo: o chassi alto tomba sozinho na primeira curva.
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, 0.2, 0.0)
	_build_visual()
	var run_over_area := get_node_or_null("RunOverArea") as Area3D
	if run_over_area != null:
		run_over_area.body_entered.connect(_on_run_over_body)


## A mola default do VehicleWheel3D e fraca demais para o peso do carro: o
## chassi afunda ate raspar o asfalto e as rodas nao tracionam (carro parado
## mesmo com engine_force). Endurece a suspensao nas quatro rodas.
## Uso: interno de _ready
func _tune_suspension() -> void:
	for wheel in find_children("*", "VehicleWheel3D", true, false):
		wheel.suspension_stiffness = 95.0
		wheel.suspension_max_force = 30000.0
		wheel.suspension_travel = 0.22


## Instancia o modelo do jipe dentro do Visual: escala para o tamanho do boneco,
## gira o bico para -Z e sobe para o pneu tocar o chao. Deixa o para-brisa
## transparente e a carroceria visivel por dentro. Uso: interno de _ready.
func _build_visual() -> void:
	var visual := get_node_or_null("Visual") as Node3D
	if visual == null or VISUAL_SCENE == null:
		return
	var model := VISUAL_SCENE.instantiate() as Node3D
	if model == null:
		return
	model.scale = Vector3.ONE * VISUAL_SCALE
	model.rotation.y = MODEL_YAW
	model.position.y = MODEL_GROUND_LIFT * VISUAL_SCALE
	visual.add_child(model)
	# Vidro primeiro: o passe two-sided duplica o material ativo, entao se rodasse
	# antes ele copiaria o vidro ainda opaco.
	_make_windows_transparent(self)
	_make_body_two_sided(self)


## O GLB e single-sided (cull_back): visto de dentro do jipe aberto, a lataria
## era descartada e o interior sumia. Duplica cada material com cull_disabled.
## Uso: interno de _build_visual
func _make_body_two_sided(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.get_active_material(surface) as StandardMaterial3D
			if source == null:
				continue
			var two_sided := source.duplicate() as StandardMaterial3D
			two_sided.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh_instance.set_surface_override_material(surface, two_sided)


## O para-brisa e opaco no GLB (material "Windows_Jeep"): a camera interna so
## veria o vidro. Troca por um material translucido para enxergar a rua.
## Uso: interno de _build_visual
func _make_windows_transparent(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.get_active_material(surface) as StandardMaterial3D
			if source == null or not source.resource_name.to_lower().contains(WINDOW_MATERIAL_KEYWORD):
				continue
			var glass := StandardMaterial3D.new()
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glass.albedo_color = WINDOW_COLOR
			glass.cull_mode = BaseMaterial3D.CULL_DISABLED
			glass.roughness = 0.1
			glass.metallic = 0.0
			mesh_instance.set_surface_override_material(surface, glass)


func is_occupied() -> bool:
	return driver != null and is_instance_valid(driver)


## Coloca um ocupante no assento. Serve para o jogador (tem `enter_vehicle`) e
## para um motorista de IA/bot (so precisa de `get_vehicle_input`).
## Uso: car.enter(player)
func enter(occupant) -> bool:
	if is_occupied() or occupant == null or is_destroyed:
		return false
	driver = occupant
	if occupant.has_method("enter_vehicle"):
		occupant.call("enter_vehicle", self)
	return true


## Leva dano de balas, explosoes e do que tiver `take_damage`. Em 0 a lataria
## escurece e o carro para de vez. Uso: Bullet.hitscan_damage(...)
func take_damage(amount: int, _attack_direction: Vector3 = Vector3.ZERO, _damage_kind: String = "bullet", _attacker: Node = null, _hit_position: Vector3 = Vector3.INF) -> void:
	if amount <= 0 or is_destroyed:
		return
	# A lataria de metal absorve parte do golpe (armadura), mas nunca fica imune.
	var applied := maxi(int(round(float(amount) * damage_armor)), 1)
	health = maxi(health - applied, 0)
	if health <= 0:
		_destroy_car()


## Carro destruido: motor morre, freio de mao entra e a lataria queima (escurece).
## Uso: interno de take_damage
func _destroy_car() -> void:
	is_destroyed = true
	engine_force = 0.0
	brake = PARKING_BRAKE
	_tint_destroyed()
	car_destroyed.emit()


## Escurece a lataria para marcar o carro destruido, mantendo o matiz de cada
## material. Uso: interno de _destroy_car
func _tint_destroyed() -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.get_active_material(surface) as StandardMaterial3D
			if source == null:
				continue
			var tinted := source.duplicate() as StandardMaterial3D
			tinted.albedo_color = source.albedo_color.darkened(0.65)
			mesh_instance.set_surface_override_material(surface, tinted)


## Linha do HUD do carro (vida e gasolina). Uso: player.get_vehicle_hud_text()
func get_car_hud_text() -> String:
	var fuel_pct := int(round(fuel / maxf(max_fuel, 0.001) * 100.0))
	if is_destroyed:
		return "Carro: DESTRUIDO | Gas: %d%%" % fuel_pct
	return "Carro: %d/%d | Gas: %d%%" % [health, max_health, fuel_pct]


## Recarrega o tanque (posto/coletavel futuro). Uso: car.refuel(50.0)
func refuel(amount: float) -> void:
	fuel = clampf(fuel + amount, 0.0, max_fuel)


## Tira o ocupante e devolve o carro ao freio de estacionamento.
## Uso: car.exit_car()
func exit_car() -> void:
	if not is_occupied():
		return
	var leaving := driver
	driver = null
	engine_force = 0.0
	brake = PARKING_BRAKE
	steering = 0.0
	if leaving.has_method("exit_vehicle"):
		leaving.call("exit_vehicle")


## Passageiro do assento traseiro (atirador); null quando vazio.
var gunner: Node = null


func is_gunner_occupied() -> bool:
	return gunner != null and is_instance_valid(gunner)


## Senta um passageiro no assento traseiro (ele continua podendo mirar e atirar).
## Uso: car.enter_gunner(player)
func enter_gunner(occupant) -> bool:
	if is_gunner_occupied() or occupant == null or is_destroyed or occupant == driver:
		return false
	gunner = occupant
	if occupant.has_method("enter_vehicle_as_gunner"):
		occupant.call("enter_vehicle_as_gunner", self)
	return true


## Levanta o passageiro traseiro. Uso: car.exit_gunner()
func exit_gunner() -> void:
	if not is_gunner_occupied():
		return
	var leaving := gunner
	gunner = null
	if leaving.has_method("exit_gunner_seat"):
		leaving.call("exit_gunner_seat")


## Posicao de mundo onde o boneco senta (a camera segue o player).
## Uso: global_position = car.seat_position()
func seat_position() -> Vector3:
	return seat.global_position if seat != null else global_position


## Transform completo do assento (posicao + pitch/roll/yaw). O boneco preso ao
## assento recebe o transform inteiro para nao flutuar solto nas lombadas.
## Uso: global_transform = car.seat_transform()
func seat_transform() -> Transform3D:
	return seat.global_transform if seat != null else global_transform


## Transform de mundo dos olhos do motorista. Sem o no `DriverEye` cai de volta
## para uma altura acima do assento. Uso: first_person_camera
func driver_eye_transform() -> Transform3D:
	if driver_eye != null:
		return driver_eye.global_transform
	var fallback := seat_transform()
	fallback.origin += fallback.basis * Vector3(0.0, DRIVER_EYE_FALLBACK_HEIGHT, 0.0)
	return fallback


## Posicao de mundo do assento traseiro (atirador). Uso: passageiro
func gunner_seat_position() -> Vector3:
	return gunner_seat.global_position if gunner_seat != null else seat_position()


## Transform completo do assento traseiro. Uso: passageiro preso ao carro
func gunner_seat_transform() -> Transform3D:
	return gunner_seat.global_transform if gunner_seat != null else seat_transform()


## Transform de mundo dos olhos do atirador (camera em 1a pessoa do passageiro).
## Uso: first_person_camera
func gunner_eye_transform() -> Transform3D:
	if gunner_eye != null:
		return gunner_eye.global_transform
	var fallback := gunner_seat_transform()
	fallback.origin += fallback.basis * Vector3(0.0, DRIVER_EYE_FALLBACK_HEIGHT, 0.0)
	return fallback


## Posicao de mundo onde o boneco desce, fora do chassi.
## Uso: global_position = car.exit_position()
func exit_position() -> Vector3:
	return exit_point.global_position if exit_point != null else global_position


func speed_kmh() -> float:
	return linear_velocity.length() * 3.6


## Entrada de direcao do motorista (steer/throttle/brake). Vazio e freado
## quando ninguem dirige. Uso: var entrada := car.driver_input()
func driver_input() -> Dictionary:
	if not is_occupied():
		return {"steer": 0.0, "throttle": 0.0, "brake": true}
	return driver.call("get_vehicle_input") as Dictionary


func _physics_process(delta: float) -> void:
	_track_crash_damage(delta)
	if is_destroyed or not is_occupied():
		engine_force = 0.0
		brake = PARKING_BRAKE
		steering = move_toward(steering, 0.0, steer_speed * delta)
		_spin_steering_wheel()
		return
	var entrada := driver_input()
	var throttle := clampf(float(entrada.get("throttle", 0.0)), -1.0, 1.0)
	var target_steer := clampf(float(entrada.get("steer", 0.0)), -1.0, 1.0) * max_steer
	steering = move_toward(steering, target_steer, steer_speed * delta)
	_spin_steering_wheel()
	# Sem gasolina o motor morre igual ao freio: o carro fica so na inercia.
	if bool(entrada.get("brake", false)) or is_zero_approx(throttle) or fuel <= 0.0:
		brake = PARKING_BRAKE
		engine_force = 0.0
		return
	brake = 0.0
	# engine_force positivo empurra o VehicleBody3D para +Z local, mas o bico do
	# carro esta em -Z (convencao do Godot): sem o sinal negativo o W andava de re.
	engine_force = 0.0 if speed_kmh() >= max_speed_kmh else -throttle * max_engine_force
	fuel = maxf(fuel - fuel_burn_per_second * delta, 0.0)


## Gira o aro visual conforme o esterco atual. Uso: interno de _physics_process
func _spin_steering_wheel() -> void:
	if steering_spin != null:
		steering_spin.rotation.y = steering * STEERING_WHEEL_SPIN


## Dano de batida: qualquer choque que derrube a velocidade bruscamente num tick
## machuca o carro, proporcional a queda. Vale para predio, muro e outro carro
## (todos na camada de mundo). Uso: interno de _physics_process
func _track_crash_damage(delta: float) -> void:
	var speed := linear_velocity.length()
	_crash_cooldown = maxf(_crash_cooldown - delta, 0.0)
	if not is_destroyed and _crash_cooldown <= 0.0:
		var loss := _previous_speed - speed
		if loss >= CRASH_SPEED_LOSS:
			_crash_cooldown = CRASH_COOLDOWN
			var impact_damage := int(roundf((loss - CRASH_SPEED_LOSS) * CRASH_DAMAGE_PER_SPEED))
			take_damage(impact_damage, -linear_velocity.normalized(), "crash", null)
	_previous_speed = speed


## Dano de atropelamento em funcao da velocidade. Zero abaixo do corte; cresce
## ate RUN_OVER_MAX_DAMAGE. Puro para ser testado sem fisica.
## Uso: var dano := DrivableCar.run_over_damage(car.linear_velocity.length())
static func run_over_damage(speed: float) -> int:
	if speed < RUN_OVER_MIN_SPEED:
		return 0
	var excess := speed - RUN_OVER_MIN_SPEED
	var full_at := RUN_OVER_MIN_SPEED * 3.0
	var factor := clampf(excess / full_at, 0.0, 1.0)
	return int(roundf(lerpf(RUN_OVER_MIN_SPEED, float(RUN_OVER_MAX_DAMAGE), factor)))


## Aplica o atropelamento em um corpo, se ele for zumbi e a velocidade bastar.
## Uso: car.apply_run_over(zumbi)
func apply_run_over(body: Node) -> int:
	if body == null or not is_instance_valid(body) or not body.is_in_group("zombies"):
		return 0
	var damage := run_over_damage(linear_velocity.length())
	if damage <= 0 or not body.has_method("take_damage"):
		return 0
	body.call("take_damage", damage, linear_velocity.normalized(), "vehicle", driver)
	# Recuo proporcional: o corpo atingido tambem machuca o carro.
	var recoil := int(roundf(damage * RUN_OVER_RECOIL))
	if recoil > 0:
		take_damage(recoil, -linear_velocity.normalized(), "run_over", driver)
	return damage


func _on_run_over_body(body: Node) -> void:
	apply_run_over(body)
