extends RefCounted

## Regressoes da fila de ataque: no maximo MAX_ATTACKERS_PER_TARGET zumbis
## batem no mesmo jogador; os outros perto esperam parados sem move_and_slide.
## Na VPS a horda colada no jogador levou move_and_slide a 88 ms num frame (0004fbb).
## Uso: ZombieCrowdSlotsTests.new().run(test_root)

const CROWD_SLOTS_SCRIPT := preload("res://scripts/zombie_crowd_slots.gd")
const TARGET_ID := 4242
const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")


func run(test_root: Node) -> void:
	_test_full_ring_makes_close_zombies_wait(test_root)
	_test_attacker_counted_once_and_expires(test_root)
	_test_attacker_never_waits_for_itself(test_root)
	await _test_zombie_waits_in_queue_near_player(test_root)


func _test_full_ring_makes_close_zombies_wait(test_root: Node) -> void:
	print("Testando zumbi perto esperando vaga com o anel de ataque cheio...")
	var slots = CROWD_SLOTS_SCRIPT.new()
	var cap: int = CROWD_SLOTS_SCRIPT.MAX_ATTACKERS_PER_TARGET
	var not_full_waits: bool = slots.should_wait(TARGET_ID, 999, 2.5, 10)
	for attacker_id in cap:
		slots.register_attacker(TARGET_ID, attacker_id, 10)
	var close_waits: bool = slots.should_wait(TARGET_ID, 999, 2.5, 10)
	var far_waits: bool = slots.should_wait(TARGET_ID, 999, CROWD_SLOTS_SCRIPT.HOLD_DISTANCE + 1.0, 10)
	var other_target_waits: bool = slots.should_wait(TARGET_ID + 1, 999, 2.5, 10)
	if not_full_waits or not close_waits or far_waits or other_target_waits:
		_fail(test_root, "Com %d atacantes so quem esta a <= %.1f m do mesmo alvo espera; vazio=%s perto=%s longe=%s outro=%s." % [cap, CROWD_SLOTS_SCRIPT.HOLD_DISTANCE, not_full_waits, close_waits, far_waits, other_target_waits])
		return
	print("PASS: Anel cheio faz os de perto esperarem.")


func _test_attacker_counted_once_and_expires(test_root: Node) -> void:
	print("Testando atacante contado uma vez e vaga liberada quando some...")
	var slots = CROWD_SLOTS_SCRIPT.new()
	var cap: int = CROWD_SLOTS_SCRIPT.MAX_ATTACKERS_PER_TARGET
	for _repeat in 3:
		for attacker_id in cap - 1:
			slots.register_attacker(TARGET_ID, attacker_id, 20)
	var repeated_waits: bool = slots.should_wait(TARGET_ID, 999, 2.0, 20)
	for attacker_id in cap:
		slots.register_attacker(TARGET_ID, attacker_id, 20)
	var expired_frame: int = 20 + CROWD_SLOTS_SCRIPT.ATTACKER_TTL_FRAMES + 1
	var after_expiry_waits: bool = slots.should_wait(TARGET_ID, 999, 2.0, expired_frame)
	if repeated_waits or after_expiry_waits:
		_fail(test_root, "Registrar o mesmo atacante de novo nao ocupa outra vaga e atacante sumido libera; repetido=%s expirado=%s." % [repeated_waits, after_expiry_waits])
		return
	print("PASS: Atacante contado uma vez e vaga liberada.")


func _test_attacker_never_waits_for_itself(test_root: Node) -> void:
	print("Testando atacante do anel cheio sem esperar a propria vaga...")
	var slots = CROWD_SLOTS_SCRIPT.new()
	for attacker_id in CROWD_SLOTS_SCRIPT.MAX_ATTACKERS_PER_TARGET:
		slots.register_attacker(TARGET_ID, attacker_id, 30)
	if slots.should_wait(TARGET_ID, 0, 2.0, 30):
		_fail(test_root, "Zumbi que ja ocupa vaga nao deveria esperar (recuou um pouco do alcance).")
		return
	print("PASS: Atacante nao espera a propria vaga.")


func _test_zombie_waits_in_queue_near_player(test_root: Node) -> void:
	print("Testando zumbi real esperando na fila perto do jogador...")
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	test_root.add_child(player)
	player.global_position = Vector3(-700.0, 60.0, -700.0)
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	zombie.set("forced_variant", 0)
	test_root.add_child(zombie)
	zombie.global_position = player.global_position + Vector3(2.5, 0.0, 0.0)
	zombie.set("alert_target", player)
	zombie.set("attack_cooldown", 5.0)
	var frame := Engine.get_physics_frames()
	for attacker_id in CROWD_SLOTS_SCRIPT.MAX_ATTACKERS_PER_TARGET:
		CROWD_SLOTS_SCRIPT.shared.register_attacker(player.get_instance_id(), attacker_id, frame)
	zombie.call("_run_physics_tick", 1.0 / 30.0)
	var horizontal_speed := Vector2(zombie.velocity.x, zombie.velocity.z).length()
	zombie.free()
	player.free()
	await test_root.get_tree().process_frame
	if horizontal_speed > 0.001:
		_fail(test_root, "Com o anel cheio o zumbi a 2,5 m deveria esperar parado; velocidade horizontal %.3f." % horizontal_speed)
		return
	print("PASS: Zumbi espera vaga parado perto do jogador.")


func _fail(test_root: Node, message: String) -> void:
	push_error("FALHA: " + message)
	test_root.set_meta("unit_test_failed", true)
