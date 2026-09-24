# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name CarroLab
extends Node3D

## Laboratorio do carro dirigivel: mapa vazio (so o chao texturizado), um carro
## e um bot dirigindo ele sozinho, com a MESMA camera isometrica do survival.
##
## Uso:
##   godot --path . labs/carro_lab.tscn
##   godot --path . labs/carro_lab.tscn -- --sem-bot

const CAR_SCENE := preload("res://scenes/drivable_car.tscn")
const CAR_BOT_SCRIPT := preload("res://scripts/car_bot_driver.gd")
const LOCAL_CAMERA_SCRIPT := preload("res://scripts/local_camera.gd")
const GROUND_TEXTURE: Texture2D = preload("res://assets/models/modular_urban/Textures/concrete.png")

const GROUND_SIZE := Vector2(600.0, 600.0)
## Metros por repeticao da textura do chao: da referencia visual de movimento.
const GROUND_TEXTURE_METERS := 4.0

@export var bot_dirige := true

var _car: DrivableCar
var _bot: Node
var _camera: Camera3D


func _ready() -> void:
	if "--sem-bot" in OS.get_cmdline_user_args():
		bot_dirige = false
	_build_ground()
	_build_lighting()
	_build_car()
	_build_camera()


## Sem luz e sem ambiente o mapa vazio renderiza preto: material PBR nao tem
## luz propria. Sol + ceu de fundo + ambiente de cor.
## Uso: interno de _ready
func _build_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sol"
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.light_energy = 1.2
	add_child(sun)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.45, 0.55, 0.68)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.5, 0.55, 0.62)
	environment.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.name = "Ambiente"
	world_env.environment = environment
	add_child(world_env)


func _build_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Chao"
	add_child(ground)

	var shape := BoxShape3D.new()
	shape.size = Vector3(GROUND_SIZE.x, 1.0, GROUND_SIZE.y)
	var collision := CollisionShape3D.new()
	collision.name = "Colisao"
	collision.shape = shape
	collision.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(collision)

	var plane := PlaneMesh.new()
	plane.size = GROUND_SIZE
	var material := StandardMaterial3D.new()
	material.albedo_texture = GROUND_TEXTURE
	material.uv1_scale = Vector3(GROUND_SIZE.x / GROUND_TEXTURE_METERS, GROUND_SIZE.y / GROUND_TEXTURE_METERS, 1.0)
	material.roughness = 0.95
	plane.material = material
	var visual := MeshInstance3D.new()
	visual.name = "Piso"
	visual.mesh = plane
	ground.add_child(visual)


func _build_car() -> void:
	_car = CAR_SCENE.instantiate() as DrivableCar
	_car.name = "CarroDoLab"
	_car.position = Vector3(0.0, 0.5, 0.0)
	add_child(_car)
	if not bot_dirige:
		return
	_bot = CAR_BOT_SCRIPT.new()
	_bot.name = "BotMotorista"
	_bot.set("car", _car)
	add_child(_bot)
	_car.enter(_bot)


func _build_camera() -> void:
	_camera = LOCAL_CAMERA_SCRIPT.new()
	_camera.name = "CameraDoLab"
	add_child(_camera)
	_camera.set("target", _car)
	_camera.make_current()
