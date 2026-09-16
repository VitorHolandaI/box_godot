extends RefCounted

## Regressoes das chamadas de apoio (pedido de variedade): cargas ganhas por
## onda e ataque aereo que bombardeia uma linha depois do atraso, so em zumbis.
## Uso: await SupportCallsTests.new().run(test_root)

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")
const AIR_STRIKE_SCRIPT := preload("res://scripts/air_strike.gd")
const MAIN_SCRIPT := preload("res://scripts/main.gd")
const SWAT_SCRIPT := preload("res://scripts/swat_squad.gd")


func run(test_root: Node) -> void:
	_test_wave_rewards(test_root)
	await _test_air_strike_bombs_line_after_delay(test_root)
	await _test_swat_follows_caller_shoots_and_leaves(test_root)
	_test_main_answers_calls(test_root)


func _test_wave_rewards(test_root: Node) -> void:
	print("Testando cargas de ataque aereo e SWAT ganhas por onda...")
	var equipment := PlayerEquipment.new()
	var air_waves: Array[int] = []
	var swat_waves: Array[int] = []
	for wave_index in 10:
		var before_air := equipment.count_of(PlayerEquipment.Item.AIR_STRIKE)
		var before_swat := equipment.count_of(PlayerEquipment.Item.SWAT)
		PlayerEquipment.grant_wave_rewards([equipment], wave_index)
		if equipment.count_of(PlayerEquipment.Item.AIR_STRIKE) > before_air:
			air_waves.append(wave_index)
		if equipment.count_of(PlayerEquipment.Item.SWAT) > before_swat:
			swat_waves.append(wave_index)
		# Usa as cargas para o limite nao esconder as proximas.
		equipment.try_consume(PlayerEquipment.Item.AIR_STRIKE)
		equipment.try_consume(PlayerEquipment.Item.SWAT)
	if air_waves != [2, 5, 8] or swat_waves != [4, 9]:
		_fail(test_root, "Cargas por onda: aereo esperado nas ondas [2, 5, 8] e SWAT em [4, 9]; veio aereo=%s swat=%s." % [air_waves, swat_waves])
		return
	print("PASS: Ataque aereo a cada 3 ondas e SWAT a cada 5.")


func _test_air_strike_bombs_line_after_delay(test_root: Node) -> void:
	print("Testando ataque aereo bombardeando a linha depois do atraso...")
	var target := Vector3(1500.0, 1.0, 1400.0)
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.set("reads_local_input", false)
	player.set("simulation_enabled", false)
	player.position = target + Vector3(2.0, 0.0, 0.0)
	test_root.add_child(player)
	var on_line: Array[CharacterBody3D] = []
	for offset in [-5.0, 0.0, 5.0]:
		var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
		zombie.position = target + Vector3(0.0, 0.0, offset)
		zombie.set("max_health", 1000)
		test_root.add_child(zombie)
		zombie.set("health", 1000)
		zombie.set_physics_process(false)
		on_line.append(zombie)
	var off_line := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	off_line.position = target + Vector3(AIR_STRIKE_SCRIPT.RADIUS + 6.0, 0.0, 0.0)
	test_root.add_child(off_line)
	off_line.set_physics_process(false)
	var strike = AIR_STRIKE_SCRIPT.new()
	test_root.add_child(strike)
	strike.set_process(false)
	strike.setup(target, Vector3.FORWARD, true)
	await test_root.get_tree().physics_frame
	strike.advance(AIR_STRIKE_SCRIPT.DELAY_SECONDS - 0.1)
	var hurt_early := on_line.any(func(zombie: CharacterBody3D) -> bool: return int(zombie.get("health")) < 1000)
	for _step in 40:
		if is_instance_valid(strike) and not strike.is_queued_for_deletion():
			strike.advance(0.1)
	var all_line_hurt := on_line.all(func(zombie: CharacterBody3D) -> bool: return int(zombie.get("health")) < 1000)
	var off_safe := int(off_line.get("health")) == int(off_line.get("max_health"))
	var player_safe := int(player.get("health")) == int(player.get("max_health"))
	var finished: bool = not is_instance_valid(strike) or strike.is_queued_for_deletion()
	for zombie in on_line:
		zombie.free()
	off_line.free()
	player.free()
	if hurt_early or not all_line_hurt or not off_safe or not player_safe or not finished:
		_fail(test_root, "Ataque aereo: ferido antes do atraso=%s, linha toda ferida=%s, fora da linha seguro=%s, jogador seguro=%s, terminou=%s." % [hurt_early, all_line_hurt, off_safe, player_safe, finished])
		return
	print("PASS: Ataque aereo bombardeia a linha depois do atraso e poupa jogadores.")


func _test_swat_follows_caller_shoots_and_leaves(test_root: Node) -> void:
	print("Testando SWAT seguindo quem chamou, atirando e indo embora...")
	var origin := Vector3(1600.0, 1.0, 1400.0)
	var caller := PLAYER_SCENE.instantiate() as CharacterBody3D
	caller.set("reads_local_input", false)
	caller.set("simulation_enabled", false)
	caller.position = origin
	test_root.add_child(caller)
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	zombie.position = origin + Vector3(0.0, 0.0, -10.0)
	zombie.set("max_health", 5000)
	test_root.add_child(zombie)
	zombie.set("health", 5000)
	zombie.set_physics_process(false)
	var far_zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	far_zombie.position = origin + Vector3(SWAT_SCRIPT.ENGAGE_RANGE + 15.0, 0.0, 0.0)
	test_root.add_child(far_zombie)
	far_zombie.set_physics_process(false)
	var squad = SWAT_SCRIPT.new()
	test_root.add_child(squad)
	squad.set_process(false)
	squad.setup(1, caller, true)
	await test_root.get_tree().physics_frame
	# Quem chamou anda 6 m; o esquadrao acompanha.
	caller.global_position = origin + Vector3(6.0, 0.0, 0.0)
	for _step in 20:
		squad.advance(0.1)
	var shot := int(zombie.get("health")) < 5000
	var far_safe := int(far_zombie.get("health")) == int(far_zombie.get("max_health"))
	var soldiers: Array = squad.soldier_positions()
	var near_caller: bool = soldiers.size() == SWAT_SCRIPT.SOLDIER_COUNT and soldiers.all(func(position: Vector3) -> bool: return Vector2(position.x - caller.global_position.x, position.z - caller.global_position.z).length() <= SWAT_SCRIPT.FOLLOW_RADIUS + 1.0)
	for _step in int(SWAT_SCRIPT.DURATION_SECONDS * 10.0):
		if is_instance_valid(squad) and not squad.is_queued_for_deletion():
			squad.advance(0.1)
	var left: bool = not is_instance_valid(squad) or squad.is_queued_for_deletion()
	caller.free()
	zombie.free()
	far_zombie.free()
	if not shot or not far_safe or not near_caller or not left:
		_fail(test_root, "SWAT: atirou no zumbi a 10 m=%s, poupou o fora do alcance=%s, soldados perto de quem chamou=%s (%s), foi embora=%s." % [shot, far_safe, near_caller, soldiers, left])
		return
	print("PASS: SWAT segue quem chamou, atira na horda e vai embora.")


func _test_main_answers_calls(test_root: Node) -> void:
	print("Testando cena principal atendendo ataque aereo e SWAT...")
	var main_world: Node = MAIN_SCRIPT.new()
	var answers := main_world.has_method("call_air_strike") and main_world.has_method("call_swat")
	main_world.free()
	if not answers:
		_fail(test_root, "Main deveria ter call_air_strike e call_swat para PlayerThrowables pedir as chamadas.")
		return
	print("PASS: Cena principal atende as chamadas.")


func _fail(test_root: Node, message: String) -> void:
	push_error("FALHA: " + message)
	test_root.set_meta("unit_test_failed", true)
