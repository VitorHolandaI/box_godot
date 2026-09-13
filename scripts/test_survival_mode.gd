extends RefCounted

const SURVIVAL_WAVE_SCHEDULE_SCRIPT := preload("res://scripts/survival_wave_schedule.gd")
const SURVIVAL_WAVE_CONTROLLER_SCRIPT := preload("res://scripts/survival_wave_controller.gd")
const RAGDOLL_SCENE := preload("res://scenes/zombie_ragdoll.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")


func run(test_root: Node) -> void:
	_test_wave_schedule(test_root)
	_test_wave_controller(test_root)
	_test_audio_streams(test_root)
	_test_ragdoll_appearance(test_root)
	_test_nearest_target_and_melee(test_root)


func _test_wave_schedule(test_root: Node) -> void:
	print("Testando progressao das ondas de sobrevivencia...")
	var schedule = SURVIVAL_WAVE_SCHEDULE_SCRIPT.new()
	var expected := [10, 20, 30, 40, 60, 80, 120, 140, 160]
	for index in expected.size():
		if schedule.target_for(index) != expected[index]:
			_fail(test_root, "Onda %d esperava %d zumbis." % [index + 1, expected[index]])
			return
	if schedule.target_for(schedule.wave_count() - 1) != 600 or not schedule.is_final_wave(schedule.wave_count() - 1):
		_fail(test_root, "A ultima onda deveria terminar em 600 zumbis.")
		return
	print("PASS: Progressao de ondas validada.")


func _test_wave_controller(test_root: Node) -> void:
	print("Testando controle autoritativo de uma onda...")
	var controller = SURVIVAL_WAVE_CONTROLLER_SCRIPT.new(func() -> bool:
		return true
	)
	for _index in 10:
		controller.tick(0.2)
	if controller.spawned_in_wave != 10 or controller.alive_in_wave != 10:
		_fail(test_root, "Controle deveria produzir 10 zumbis e manter 10 vivos; produziu %d/%d." % [controller.spawned_in_wave, controller.alive_in_wave])
		return
	for _index in 10:
		controller.register_death()
	controller.tick(0.01)
	if controller.wave_index != 1 or controller.total_kills != 10:
		_fail(test_root, "Controle deveria avançar para a segunda onda apos limpar a primeira.")
		return
	print("PASS: Controle de ondas e abates validado.")


func _test_audio_streams(test_root: Node) -> void:
	print("Testando streams reais de tiro e gemido de zumbi...")
	if not AudioFeedback.has_audio_streams():
		_fail(test_root, "AudioFeedback deveria criar streams reais para tiro e gemido.")
		return
	print("PASS: Streams reais de audio disponiveis.")


func _test_ragdoll_appearance(test_root: Node) -> void:
	print("Testando preservacao da skin no ragdoll...")
	var ragdoll := RAGDOLL_SCENE.instantiate() as Node3D
	test_root.add_child(ragdoll)
	ragdoll.call("setup", Vector3.ZERO, 0, 12345)
	var torso := ragdoll.get_node("Torso/Mesh") as MeshInstance3D
	var material := torso.mesh.material as StandardMaterial3D
	var expected: Color = ZombieMutator.appearance_colors(12345)[1]
	if material.albedo_color != expected:
		_fail(test_root, "Ragdoll deveria preservar a cor de camisa da variante morta.")
		ragdoll.free()
		return
	ragdoll.free()
	print("PASS: Skin da variante preservada no ragdoll.")


func _test_nearest_target_and_melee(test_root: Node) -> void:
	print("Testando alvo mais proximo e ataque oportunista no multiplayer...")
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	var far_player := PLAYER_SCENE.instantiate() as CharacterBody3D
	var near_player := PLAYER_SCENE.instantiate() as CharacterBody3D
	test_root.add_child(zombie)
	test_root.add_child(far_player)
	test_root.add_child(near_player)
	zombie.position = Vector3.ZERO
	far_player.position = Vector3(0.0, 1.0, 8.0)
	near_player.position = Vector3(0.0, 1.0, 3.0)
	zombie.call("_update_senses", 0.25)
	if zombie.get("alert_target") != near_player:
		_fail(test_root, "Zumbi deveria escolher o jogador vivo mais proximo.")
		zombie.free()
		far_player.free()
		near_player.free()
		return
	var previous_health: int = near_player.health
	zombie.set("alert_target", far_player)
	zombie.set("target_switch_cooldown", 1.0)
	near_player.position = Vector3(0.0, 0.8, 0.8)
	zombie.call("_physics_process", 0.01)
	if near_player.health >= previous_health or zombie.get("alert_target") != far_player:
		_fail(test_root, "Zumbi deveria atacar jogador proximo sem trocar alvo; vida=%d, ataque=%d, alvo=%s." % [near_player.health, zombie.attack_sequence, zombie.alert_target.name if zombie.alert_target != null else "null"])
		zombie.free()
		far_player.free()
		near_player.free()
		return
	zombie.free()
	far_player.free()
	near_player.free()
	print("PASS: Alvo estavel e ataque oportunista validados.")


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
