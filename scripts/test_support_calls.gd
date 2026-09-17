extends RefCounted

## Regressoes das chamadas de apoio (pedido de variedade): cargas ganhas por
## onda, ataque aereo que bombardeia uma linha depois do atraso e o esquadrao
## SWAT como 4 jogadores de verdade simulados (Uzi, municao infinita,
## invulneraveis, fora do grupo "player" e com leash do dono).
## Uso: await SupportCallsTests.new().run(test_root)

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")
const AIR_STRIKE_SCRIPT := preload("res://scripts/air_strike.gd")
const MAIN_SCRIPT := preload("res://scripts/main.gd")
const SWAT_BOT_SCRIPT := preload("res://scripts/swat_squad_bot.gd")


func run(test_root: Node) -> void:
	_test_wave_rewards(test_root)
	await _test_air_strike_bombs_line_after_delay(test_root)
	_test_swat_bot_is_a_server_driven_soldier(test_root)
	_test_swat_uzi_never_spends_ammo_and_never_dies(test_root)
	_test_swat_input_is_tactical_and_leashed(test_root)
	await _test_swat_does_not_shoot_through_wall(test_root)
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


## O soldado e um jogador real do servidor, mas fora do grupo "player": os
## zumbis ignoram, nada colide com ele e o GAME OVER/revive/minimapa nao veem.
func _test_swat_bot_is_a_server_driven_soldier(test_root: Node) -> void:
	print("Testando soldado SWAT como jogador simulado fora do grupo player...")
	var bot := PLAYER_SCENE.instantiate() as CharacterBody3D
	test_root.add_child(bot)
	SWAT_BOT_SCRIPT.configure(bot, 0)
	var in_player_group: bool = bot.is_in_group("player")
	var layer := bot.collision_layer
	var mask := bot.collision_mask
	var invulnerable: bool = bool(bot.get("is_swat_bot")) and bool(bot.get("infinite_ammo"))
	var reads_input: bool = bool(bot.get("reads_local_input"))
	var local_controller: bool = bool(bot.get("is_local_controller"))
	bot.free()
	if in_player_group or layer != 0 or (mask & 4) != 0 or not invulnerable or reads_input or local_controller:
		_fail(test_root, "SWAT: no grupo player=%s (esperado false), layer=%d (0), mask=%d sem o layer de zumbi (4), marcado=%s, le teclado=%s, controle local=%s." % [in_player_group, layer, mask, invulnerable, reads_input, local_controller])
		return
	print("PASS: Soldado SWAT fora do grupo player, sem colisao e invulneravel.")


func _test_swat_uzi_never_spends_ammo_and_never_dies(test_root: Node) -> void:
	print("Testando Uzi com municao infinita e soldado que nao morre...")
	var bot := PLAYER_SCENE.instantiate() as CharacterBody3D
	bot.set("reads_local_input", false)
	test_root.add_child(bot)
	SWAT_BOT_SCRIPT.configure(bot, 0)
	var equipped: bool = bot.equip_crate_weapon(WeaponStats.Kind.UZI)
	var mag_size := int(WeaponStats.stats_for(WeaponStats.Kind.UZI)["mag_size"])
	bot.set("attack_cooldown", 0.0)
	bot.apply_network_input({"slot": 0, "move": Vector2.ZERO, "aim": Vector2.ZERO, "attack": true, "sprint": false})
	for _shot in mag_size * 2:
		bot.set("attack_cooldown", 0.0)
		bot.call("_handle_weapon_input")
	var mag_left := int((bot.get("weapon_slots") as WeaponSlots).state_of(WeaponStats.Kind.UZI).get("mag", -1))
	var weapon_now := int(bot.get("current_weapon"))
	var durability := int((bot.get("weapon_slots") as WeaponSlots).state_of(WeaponStats.Kind.UZI).get("durability", -1))
	bot.take_damage(500)
	var survived: int = int(bot.get("health"))
	bot.free()
	if not equipped or weapon_now != int(WeaponStats.Kind.UZI):
		_fail(test_root, "SWAT deveria sair armado de Uzi; equipou=%s arma=%d." % [equipped, weapon_now])
		return
	if mag_left != mag_size or durability <= 0:
		_fail(test_root, "Uzi do SWAT nao pode gastar pente nem durabilidade; pente=%d (esperado %d), durabilidade=%d." % [mag_left, mag_size, durability])
		return
	if survived != 100:
		_fail(test_root, "Soldado SWAT nao pode tomar dano; vida apos 500 de dano=%d (esperado 100)." % survived)
		return
	print("PASS: Uzi infinita e soldado invulneravel.")


## IA do esquadrao: ataca alinhado, nunca troca de arma, volta pro dono quando
## passa do leash e, sem alvo, ocupa a vaga na formacao.
func _test_swat_input_is_tactical_and_leashed(test_root: Node) -> void:
	print("Testando IA do esquadrao: Uzi, leash e formacao...")
	var zombies := Node3D.new()
	zombies.position = Vector3(2000.0, 1.0, 2000.0)
	test_root.add_child(zombies)
	var anchor := PLAYER_SCENE.instantiate() as CharacterBody3D
	anchor.set("reads_local_input", false)
	anchor.position = Vector3(2000.0, 1.0, 2000.0)
	test_root.add_child(anchor)
	var bot := PLAYER_SCENE.instantiate() as CharacterBody3D
	bot.set("reads_local_input", false)
	bot.position = anchor.global_position
	test_root.add_child(bot)
	SWAT_BOT_SCRIPT.configure(bot, 0)
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	zombies.add_child(zombie)
	# Global: o no "zumbis" fica longe do resto da cena de teste.
	zombie.global_position = bot.global_position + Vector3(0.0, 0.0, -10.0)
	zombie.set_physics_process(false)
	var ai := PlayerBotAI.new()
	var engaged: Dictionary = ai.collect_squad_input(bot, anchor, zombies, 0, 0, 0.033)
	var aiming_at_zombie := (engaged["aim"] as Vector2).distance_to(Vector2(0.0, -1.0)) < 0.2
	# Longe do dono, o leash manda de volta mesmo com zumbi por perto.
	bot.global_position = anchor.global_position + Vector3(SWAT_BOT_SCRIPT.LEASH_DISTANCE + 8.0, 0.0, 0.0)
	var leashed: Dictionary = ai.collect_squad_input(bot, anchor, zombies, 1, 1, 0.033)
	var back_toward_anchor: Vector2 = leashed["move"]
	# Sem alvo: vai para a vaga da formacao em volta do dono.
	zombie.free()
	bot.global_position = anchor.global_position + Vector3(12.0, 0.0, 0.0)
	var idle: Dictionary = ai.collect_squad_input(bot, anchor, zombies, 2, 2, 0.033)
	var to_anchor := Vector2(anchor.global_position.x - bot.global_position.x, anchor.global_position.z - bot.global_position.z).normalized()
	var idle_toward_anchor := (idle["move"] as Vector2).dot(to_anchor) > 0.5
	var switches_weapon: bool = bool(engaged["knife"]) or bool(engaged["pistol"]) or bool(engaged["reload"])
	var attacks: bool = bool(engaged["attack"])
	bot.free()
	anchor.free()
	zombies.free()
	if not attacks or not aiming_at_zombie or switches_weapon:
		_fail(test_root, "Com zumbi a 10 m alinhado o SWAT deveria atirar de Uzi sem trocar de arma; atirou=%s mirou=%s trocou=%s." % [attacks, aiming_at_zombie, switches_weapon])
		return
	if back_toward_anchor.dot(to_anchor) < 0.5:
		_fail(test_root, "Passando do leash (%s m) o SWAT deveria voltar para o dono; move=%s." % [SWAT_BOT_SCRIPT.LEASH_DISTANCE, back_toward_anchor])
		return
	if not idle_toward_anchor:
		_fail(test_root, "Sem alvo o SWAT deveria ir para a vaga da formacao perto do dono; move=%s." % [idle["move"]])
		return
	print("PASS: IA do esquadrao atira de Uzi, respeita o leash e forma em volta do dono.")


## Sem linha de visao o soldado nao atira: no smoke, 253 de 258 tiros dos bots
## acertaram o Safehouse porque o alvo era escolhido so pela distancia.
func _test_swat_does_not_shoot_through_wall(test_root: Node) -> void:
	print("Testando linha de visao do soldado SWAT (parede no caminho)...")
	var origin := Vector3(2400.0, 1.0, 2400.0)
	var anchor := PLAYER_SCENE.instantiate() as CharacterBody3D
	anchor.set("reads_local_input", false)
	anchor.position = origin
	test_root.add_child(anchor)
	var bot := PLAYER_SCENE.instantiate() as CharacterBody3D
	bot.set("reads_local_input", false)
	bot.position = origin
	test_root.add_child(bot)
	SWAT_BOT_SCRIPT.configure(bot, 0)
	var zombies := Node3D.new()
	test_root.add_child(zombies)
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	zombies.add_child(zombie)
	zombie.global_position = origin + Vector3(0.0, 0.0, -10.0)
	zombie.set_physics_process(false)
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 3.0, 0.4)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	wall.collision_layer = 1
	wall.collision_mask = 0
	test_root.add_child(wall)
	wall.global_position = origin + Vector3(0.0, 1.2, -5.0)
	await test_root.get_tree().physics_frame
	await test_root.get_tree().physics_frame
	var ai := PlayerBotAI.new()
	var blocked: Dictionary = ai.collect_squad_input(bot, anchor, zombies, 0, 0, 0.033)
	var blocked_attack: bool = bool(blocked["attack"])
	wall.queue_free()
	await test_root.get_tree().physics_frame
	await test_root.get_tree().physics_frame
	var clear: Dictionary = ai.collect_squad_input(bot, anchor, zombies, 1, 1, 0.033)
	var clear_attack: bool = bool(clear["attack"])
	bot.free()
	anchor.free()
	zombies.free()
	if blocked_attack:
		_fail(test_root, "Com parede no caminho o SWAT nao pode atirar (gastaria bala no cenario).")
		return
	if not clear_attack:
		_fail(test_root, "Sem a parede o SWAT deveria atirar; attack=%s." % clear_attack)
		return
	print("PASS: SWAT so atira com linha de visao.")


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
