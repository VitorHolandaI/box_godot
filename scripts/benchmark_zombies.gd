class_name BenchmarkZombies
extends Node3D

## Benchmark de capacidade maxima de zumbis e consumo de RAM/CPU no servidor.
## Mede tempo de fisica, objetos ativos, heap do Godot e VmRSS do sistema operacional.
## Uso:
##   godot --headless --path . -- --benchmark-zombies

const ZOMBIE_SCENE: PackedScene = preload("res://scenes/zombie.tscn")
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIERS: Array[int] = [0, 50, 100, 150, 200, 300, 400, 600, 800, 1000, 1500, 2000, 2500, 3000, 4000, 5000]
const WARMUP_FRAMES := 35
const SAMPLE_FRAMES := 30

var world_settle_frames := 90
var current_tier_idx := 0
var frame_counter := 0
var is_warming_up := true
var sample_physics_times: Array[float] = []
var sample_static_mems: Array[float] = []
var sample_rss_mems: Array[float] = []
var sample_fps: Array[float] = []
var tier_results: Array[Dictionary] = []

var main_world: Node3D = null
var zombies_container: Node3D = null
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	print("================================================================================")
	print("  INICIANDO BENCHMARK DE ESTRESSE DE ZUMBIS (CAPACIDADE, RAM E CPU)")
	print("================================================================================")
	rng.seed = 98765
	main_world = MAIN_SCENE.instantiate() as Node3D
	main_world.set_process(false)
	add_child(main_world)

	zombies_container = main_world.get_node_or_null("Zombies") as Node3D
	if zombies_container != null:
		for child in zombies_container.get_children():
			child.free()


func _physics_process(_delta: float) -> void:
	if world_settle_frames > 0:
		world_settle_frames -= 1
		if world_settle_frames == 0:
			print("Mundo estabilizado. Iniciando medicao dos patamares...")
			_start_tier(0)
		return

	frame_counter += 1
	if is_warming_up:
		if frame_counter >= WARMUP_FRAMES:
			is_warming_up = false
			frame_counter = 0
		return

	_sample_current_frame()

	if frame_counter >= SAMPLE_FRAMES:
		_finish_current_tier()
		current_tier_idx += 1
		if current_tier_idx >= TIERS.size():
			_print_final_report()
			get_tree().quit(0)
			return
		_start_tier(current_tier_idx)


func _start_tier(idx: int) -> void:
	var target_count: int = TIERS[idx]
	print("Testando patamar de %d zumbis..." % target_count)
	_adjust_zombie_count(target_count)
	frame_counter = 0
	is_warming_up = true
	sample_physics_times.clear()
	sample_static_mems.clear()
	sample_rss_mems.clear()
	sample_fps.clear()


func _adjust_zombie_count(target: int) -> void:
	if zombies_container == null:
		return
	var current: int = zombies_container.get_child_count()
	while current < target:
		var z := _spawn_zombie(current, rng)
		zombies_container.add_child(z)
		current += 1
	while current > target:
		var child := zombies_container.get_child(current - 1)
		child.free()
		current -= 1


func _spawn_zombie(index: int, rand_gen: RandomNumberGenerator) -> Node3D:
	var z := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	z.name = "BenchZombie%d" % index
	var angle := rand_gen.randf() * TAU
	var dist := rand_gen.randf_range(8.0, 75.0)
	z.position = Vector3(cos(angle) * dist, 1.0, sin(angle) * dist)
	z.set("simulation_enabled", true)
	return z


func _sample_current_frame() -> void:
	var phys_t := float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0 # ms
	var stat_mem := float(Performance.get_monitor(Performance.MEMORY_STATIC)) / (1024.0 * 1024.0) # MB
	var rss_mem := float(_get_system_rss_kb()) / 1024.0 # MB
	var fps := float(Performance.get_monitor(Performance.TIME_FPS))

	sample_physics_times.append(phys_t)
	sample_static_mems.append(stat_mem)
	sample_rss_mems.append(rss_mem)
	sample_fps.append(fps)


func _finish_current_tier() -> void:
	var count: int = TIERS[current_tier_idx]
	var avg_phys := _average(sample_physics_times)
	var avg_mem := _average(sample_static_mems)
	var avg_rss := _average(sample_rss_mems)
	var avg_fps := _average(sample_fps)

	var res := {
		"count": count,
		"physics_ms": avg_phys,
		"heap_mb": avg_mem,
		"rss_mb": avg_rss,
		"fps": avg_fps,
	}
	tier_results.append(res)
	print("  -> %4d zumbis: Fisica=%6.2f ms | Heap=%6.1f MB | RSS=%6.1f MB | FPS=%4.0f" % [
		count, avg_phys, avg_mem, avg_rss, avg_fps
	])


func _average(arr: Array[float]) -> float:
	if arr.is_empty():
		return 0.0
	var sum := 0.0
	for val in arr:
		sum += val
	return sum / float(arr.size())


func _print_final_report() -> void:
	print("\n================================================================================")
	print("                       RELATORIO FINAL DE BENCHMARK")
	print("================================================================================")
	print("| Zumbis | Tempo Fisica (ms) | Heap Godot (MB) | RSS SO (MB) | FPS Servidor |")
	print("|--------|-------------------|-----------------|-------------|--------------|")
	for r in tier_results:
		print("| %6d | %17.2f | %15.2f | %11.2f | %12.0f |" % [
			int(r["count"]), float(r["physics_ms"]), float(r["heap_mb"]), float(r["rss_mb"]), float(r["fps"])
		])
	print("================================================================================")

	# Analise de regressao linear e custos unitarios
	var baseline: Dictionary = tier_results[0]
	var base_heap: float = float(baseline["heap_mb"])
	var base_rss: float = float(baseline["rss_mb"])
	var base_phys: float = float(baseline["physics_ms"])

	var highest: Dictionary = tier_results[tier_results.size() - 1]
	var high_count: float = float(highest["count"])
	if high_count > 0.0:
		var delta_heap_kb := (float(highest["heap_mb"]) - base_heap) * 1024.0
		var delta_rss_kb := (float(highest["rss_mb"]) - base_rss) * 1024.0
		var delta_phys_us := (float(highest["physics_ms"]) - base_phys) * 1000.0

		var heap_per_zombie_kb := delta_heap_kb / high_count
		var rss_per_zombie_kb := delta_rss_kb / high_count
		var phys_per_zombie_us := delta_phys_us / high_count

		var max_60fps := int((16.66 - base_phys) * 1000.0 / maxf(phys_per_zombie_us, 0.001))
		var max_30fps := int((33.33 - base_phys) * 1000.0 / maxf(phys_per_zombie_us, 0.001))

		print("\n--- CUSTO UNITARIO POR ZUMBI ---")
		print("  - Memoria RAM (Heap Godot):      %6.2f KB / zumbi" % heap_per_zombie_kb)
		print("  - Memoria RAM (Processo SO RSS): %6.2f KB / zumbi" % rss_per_zombie_kb)
		print("  - Custo de CPU de Fisica:        %6.2f us (microsegundos) / zumbi / frame" % phys_per_zombie_us)
		print("\n--- CAPACIDADE MAXIMA ESTIMADA DO SERVIDOR ---")
		print("  - Limite para 60 FPS estaveis (budget 16.6ms): ~%d zumbis simultaneos" % maxi(max_60fps, 0))
		print("  - Limite para 30 FPS estaveis (budget 33.3ms): ~%d zumbis simultaneos" % maxi(max_30fps, 0))
		print("================================================================================\n")


static func _get_system_rss_kb() -> int:
	var file := FileAccess.open("/proc/self/status", FileAccess.READ)
	if file == null:
		return 0
	while not file.eof_reached():
		var line := file.get_line()
		if line.begins_with("VmRSS:"):
			var parts := line.split(" ", false)
			if parts.size() >= 2:
				return int(parts[1])
	return 0
