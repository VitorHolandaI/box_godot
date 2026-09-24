# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name BenchmarkIndoorEscape
extends Node3D

## Benchmark da rota de fuga dos zumbis presos dentro de casas procedurais.
## Coloca zumbis nos comodos dos fundos, o jogador atras da casa e mede o
## custo de fisica por frame e quantos zumbis conseguem sair pela porta.
## `script_ms` e medido por frame entre dois nos carimbadores (prioridade minima
## e maxima de fisica); `engine_physics_ms` vem do monitor do Godot, que so
## atualiza uma vez por segundo e serve apenas como media grosseira.
## Uso:
##   godot --headless --path . -- --benchmark-indoor-escape
##   godot --headless --path . -- --benchmark-indoor-escape --closed-doors

const ZOMBIE_SCENE: PackedScene = preload("res://scenes/zombie.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const FLOCK_COORDINATOR_SCRIPT: GDScript = preload("res://scripts/zombie_flock_coordinator.gd")
const BUILDING_GENERATOR_SCRIPT: GDScript = preload("res://scripts/procedural/generators/building_generator.gd")
const BUILDING_ASSEMBLER_SCRIPT: GDScript = preload("res://scripts/procedural/assemblers/building_assembler.gd")
const CITY_ASSEMBLER_SCRIPT: GDScript = preload("res://scripts/procedural/assemblers/city_assembler.gd")
const HOUSE_COUNT := 12
const ZOMBIES_PER_HOUSE := 25
const HOUSE_SPACING := 16.0
const SETTLE_FRAMES := 30
const DEFAULT_SAMPLE_FRAMES := 900

var frame_counter := 0
var frame_start_usec := 0
var script_samples: Array[float] = []
var sample_frames := DEFAULT_SAMPLE_FRAMES
var physics_samples: Array[float] = []
var house_bounds: Array[AABB] = []
var zombie_house_index: Dictionary = {}
var bait_player: CharacterBody3D = null


func _ready() -> void:
	_add_frame_stamp(-1000000, _stamp_frame_start)
	_add_frame_stamp(1000000, _stamp_frame_end)
	var coordinator := FLOCK_COORDINATOR_SCRIPT.new() as Node
	add_child(coordinator)
	var ground := _create_ground()
	add_child(ground)
	var closed_doors := "--closed-doors" in OS.get_cmdline_user_args()
	sample_frames = _read_sample_frames(OS.get_cmdline_user_args())
	for house_index in HOUSE_COUNT:
		_spawn_house_with_zombies(house_index, closed_doors)
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.set("reads_local_input", false)
	player.set("simulation_enabled", false)
	player.set("is_local_controller", false)
	player.position = Vector3(HOUSE_COUNT * HOUSE_SPACING * 0.5, 1.2, 30.0)
	add_child(player)
	bait_player = player
	print(JSON.stringify({"event": "indoor_escape_start", "zombies": HOUSE_COUNT * ZOMBIES_PER_HOUSE, "closed_doors": closed_doors}))


func _physics_process(_delta: float) -> void:
	frame_counter += 1
	# A isca nao pode morrer: sem jogador vivo a horda para de perseguir e o
	# benchmark mediria zumbis ociosos em vez da rota de fuga.
	bait_player.set("health", int(bait_player.get("max_health")))
	if frame_counter <= SETTLE_FRAMES:
		return
	physics_samples.append(float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
	if frame_counter < SETTLE_FRAMES + sample_frames:
		return
	_print_report()
	get_tree().quit(0)


func _add_frame_stamp(priority: int, callback: Callable) -> void:
	var stamp := FrameStamp.new()
	stamp.process_physics_priority = priority
	stamp.on_physics_tick = callback
	add_child(stamp)


func _stamp_frame_start() -> void:
	frame_start_usec = Time.get_ticks_usec()


func _stamp_frame_end() -> void:
	if frame_counter > SETTLE_FRAMES:
		script_samples.append(float(Time.get_ticks_usec() - frame_start_usec) / 1000.0)


func _spawn_house_with_zombies(house_index: int, closed_doors: bool) -> void:
	var blueprint = BUILDING_GENERATOR_SCRIPT.generate(240912 + house_index, "house")
	var house: StaticBody3D = BUILDING_ASSEMBLER_SCRIPT.assemble(blueprint)
	house.name = "BenchHouse%d" % house_index
	house.position = Vector3(float(house_index) * HOUSE_SPACING, 0.16, 0.0)
	add_child(house)
	var house_min := house.position
	var house_max := house.position + Vector3(blueprint.width, blueprint.floor_height, blueprint.depth)
	CITY_ASSEMBLER_SCRIPT.configure_cutout_bounds(house, house_min, house_max)
	house_bounds.append(AABB(house_min, house_max - house_min))
	if not closed_doors:
		for door in house.find_children("Door_*", "AnimatableBody3D", true, false):
			door.take_damage(int(door.get("max_health")), Vector3.FORWARD, "melee", null)
	var rng := RandomNumberGenerator.new()
	rng.seed = house_index
	for zombie_index in ZOMBIES_PER_HOUSE:
		var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
		zombie.name = "IndoorZombie%d_%d" % [house_index, zombie_index]
		zombie.position = house.position + Vector3(rng.randf_range(0.8, 9.2), 0.9, rng.randf_range(4.7, 5.6))
		add_child(zombie)
		zombie_house_index[zombie] = house_index


static func _read_sample_frames(arguments: PackedStringArray) -> int:
	for argument in arguments:
		if not argument.begins_with("--sample-frames="):
			continue
		var raw_value := argument.trim_prefix("--sample-frames=")
		if not raw_value.is_valid_int() or int(raw_value) <= 0:
			push_error("Valor invalido para --sample-frames: '%s'; esperado inteiro > 0." % raw_value)
			continue
		return int(raw_value)
	return DEFAULT_SAMPLE_FRAMES


func _create_ground() -> StaticBody3D:
	var ground := StaticBody3D.new()
	ground.name = "BenchGround"
	var shape := BoxShape3D.new()
	shape.size = Vector3(600.0, 0.2, 600.0)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(HOUSE_COUNT * HOUSE_SPACING * 0.5, 0.0, 0.0)
	ground.add_child(collision)
	return ground


func _print_report() -> void:
	var escaped := 0
	var trapped_positions: Array[String] = []
	for zombie_node in zombie_house_index:
		var zombie := zombie_node as CharacterBody3D
		var bounds: AABB = house_bounds[int(zombie_house_index[zombie_node])]
		var flat_bounds := AABB(Vector3(bounds.position.x, -100.0, bounds.position.z), Vector3(bounds.size.x, 200.0, bounds.size.z))
		if not flat_bounds.has_point(zombie.global_position):
			escaped += 1
		elif trapped_positions.size() < 8:
			var local := zombie.global_position - bounds.position
			trapped_positions.append("(%.1f,%.1f)" % [local.x, local.z])

	print(JSON.stringify({
		"event": "indoor_escape_report",
		"zombies": zombie_house_index.size(),
		"escaped": escaped,
		"script_ms_avg": snappedf(_average(script_samples), 0.01),
		"script_ms_p95": snappedf(_percentile(script_samples, 0.95), 0.01),
		"script_ms_max": snappedf(_percentile(script_samples, 1.0), 0.01),
		"engine_physics_ms_avg": snappedf(_average(physics_samples), 0.01),
		"frames": physics_samples.size(),
		"trapped_sample_local_xz": trapped_positions,
	}))


static func _average(samples: Array[float]) -> float:
	if samples.is_empty():
		return 0.0
	var total := 0.0
	for sample in samples:
		total += sample
	return total / float(samples.size())


static func _percentile(samples: Array[float], fraction: float) -> float:
	if samples.is_empty():
		return 0.0
	var sorted_samples := samples.duplicate()
	sorted_samples.sort()
	return sorted_samples[mini(int(float(sorted_samples.size()) * fraction), sorted_samples.size() - 1)]


## Carimba o inicio/fim do tick de fisica dos scripts conforme sua prioridade.
class FrameStamp:
	extends Node

	var on_physics_tick: Callable

	func _physics_process(_delta: float) -> void:
		on_physics_tick.call()
