extends RefCounted

## Regressoes do corte de custo do servidor dedicado com a horda de 200
## (VPS 2 vCPU: IA dos zumbis 9-31 ms/frame e ate 8 ticks de fisica seguidos).
## Uso: ServerTickPolicyTests.new().run(test_root)

const SERVER_TICK_POLICY_SCRIPT := preload("res://scripts/server_tick_policy.gd")
const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")


func run(test_root: Node) -> void:
	_test_dedicated_tick_settings(test_root)
	_test_dedicated_detection(test_root)
	_test_zombie_slide_budget(test_root)


func _test_dedicated_tick_settings(test_root: Node) -> void:
	print("Testando tick de fisica do servidor dedicado...")
	var previous_ticks := Engine.physics_ticks_per_second
	var previous_steps := Engine.max_physics_steps_per_frame
	SERVER_TICK_POLICY_SCRIPT.apply_dedicated_tick()
	var ticks := Engine.physics_ticks_per_second
	var steps := Engine.max_physics_steps_per_frame
	Engine.physics_ticks_per_second = previous_ticks
	Engine.max_physics_steps_per_frame = previous_steps
	if ticks != 60 or steps != 2:
		_fail(test_root, "Servidor dedicado deveria rodar fisica a 60 Hz com no maximo 2 passos por frame; veio ticks=%d passos=%d." % [ticks, steps])
		return
	print("PASS: Tick de fisica do servidor dedicado validado.")


func _test_dedicated_detection(test_root: Node) -> void:
	print("Testando deteccao de servidor dedicado pela linha de comando...")
	var dedicated: bool = SERVER_TICK_POLICY_SCRIPT.is_dedicated_arguments(PackedStringArray(["--server", "--survival"]))
	var client: bool = SERVER_TICK_POLICY_SCRIPT.is_dedicated_arguments(PackedStringArray(["--bot-player=1.2.3.4"]))
	if not dedicated or client:
		_fail(test_root, "--server deveria marcar dedicado e --bot-player nao; dedicado=%s client=%s." % [dedicated, client])
		return
	print("PASS: Deteccao de servidor dedicado validada.")


func _test_zombie_slide_budget(test_root: Node) -> void:
	print("Testando limite de deslizes do move_and_slide do zumbi...")
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	test_root.add_child(zombie)
	var slides := zombie.max_slides
	zombie.free()
	if slides != 3:
		_fail(test_root, "Zumbi deveria usar max_slides=3 (move_and_slide era 60%% da IA); veio %d." % slides)
		return
	print("PASS: Limite de deslizes do zumbi validado.")


func _fail(test_root: Node, message: String) -> void:
	push_error("FALHA: " + message)
	test_root.set_meta("unit_test_failed", true)
