extends RefCounted

## Regressoes dos especiais novos (pedido de variedade): puxador (lingua que
## prende e puxa), curandeiro (cura e levanta cadaver) e espreitador (quase
## invisivel ate chegar perto e da o bote).
## Uso: await ZombieL4dSpecialsTests.new().run(test_root)

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")
const SCHEDULE_SCRIPT := preload("res://scripts/survival_wave_schedule.gd")
const ZOMBIE_SCRIPT := preload("res://scripts/zombie.gd")
const MAIN_SCRIPT := preload("res://scripts/main.gd")
const TONGUE_SCRIPT := preload("res://scripts/zombie_tongue.gd")
const HEALER_SCRIPT := preload("res://scripts/zombie_healer.gd")
const STALKER_SCRIPT := preload("res://scripts/zombie_stalker.gd")
const COLLECTOR_SCRIPT := preload("res://scripts/zombie_collector.gd")
const ABILITIES_SCRIPT := preload("res://scripts/zombie_variant_abilities.gd")
const NEW_TYPES := ["SMOKER", "HEALER", "STALKER"]


func run(test_root: Node) -> void:
	_test_types_registered_in_mixes(test_root)
	_test_tongue_grab_pull_and_release(test_root)
	await _test_player_forced_move_overrides_input(test_root)
	await _test_healer_heals_nearby_and_picks_corpse(test_root)
	_test_stalker_reveal_and_pounce(test_root)
	_test_collector_absorbs_and_inherits(test_root)
	_test_collector_borrows_dash(test_root)
	_test_collector_borrows_armor(test_root)
	_test_collector_mutation_scream_heals(test_root)
	_test_main_hooks(test_root)


func _test_types_registered_in_mixes(test_root: Node) -> void:
	print("Testando puxador, curandeiro e espreitador registrados e nas ondas...")
	var problems: Array[String] = []
	var mutator_names: Array = ZombieMutator.Type.keys()
	var zombie_names: Array = ZOMBIE_SCRIPT.ZombieType.keys()
	for type_name in NEW_TYPES:
		if not mutator_names.has(type_name):
			problems.append("%s fora do ZombieMutator.Type" % type_name)
	if mutator_names != zombie_names:
		problems.append("enums de tipo divergentes: mutator=%s zumbi=%s" % [mutator_names, zombie_names])
	if ZombieMutator.TYPE_COUNT != mutator_names.size():
		problems.append("TYPE_COUNT=%d, tipos=%d" % [ZombieMutator.TYPE_COUNT, mutator_names.size()])
	var schedule = SCHEDULE_SCRIPT.new()
	for stage in SCHEDULE_SCRIPT.VARIANT_MIXES.size():
		var mix: Dictionary = SCHEDULE_SCRIPT.VARIANT_MIXES[stage]
		var total := 0
		for kind in mix:
			total += int(mix[kind])
		if total != 100:
			problems.append("fase %d soma %d" % [stage, total])
	for type_name in NEW_TYPES:
		var type_value: int = ZombieMutator.Type[type_name]
		# Na hora 1-2 nao apareciam e o jogador nao via a variedade nova.
		if not schedule.variant_mix_for_wave(0).has(type_value) or not schedule.variant_mix_for_wave(2).has(type_value) or not schedule.variant_mix_for_wave(12).has(type_value):
			problems.append("%s fora das ondas desde a hora 1" % type_name)
	if not problems.is_empty():
		_fail(test_root, "Especiais novos: %s." % [problems])
		return
	print("PASS: Especiais novos registrados e na horda desde a hora 1.")


func _test_tongue_grab_pull_and_release(test_root: Node) -> void:
	print("Testando lingua do puxador: prende, puxa e solta...")
	var zombie_pos := Vector3.ZERO
	var target_pos := Vector3(0.0, 0.0, -10.0)
	var tongue = TONGUE_SCRIPT.new()
	var too_close: bool = tongue.can_grab(TONGUE_SCRIPT.MIN_RANGE - 1.0, true)
	var blind: bool = tongue.can_grab(10.0, false)
	var ready: bool = tongue.can_grab(10.0, true)
	tongue.start()
	var pull: Vector3 = tongue.update(0.1, zombie_pos, target_pos, true, 0)
	var pulls_toward := pull.normalized().distance_to(Vector3(0.0, 0.0, 1.0)) < 0.01 and is_equal_approx(pull.length(), TONGUE_SCRIPT.PULL_SPEED)
	var hurt_release: Vector3 = tongue.update(0.1, zombie_pos, target_pos, true, TONGUE_SCRIPT.BREAK_DAMAGE)
	var released_by_damage: bool = hurt_release == Vector3.ZERO and not tongue.is_pulling()
	var cooldown_blocks: bool = not tongue.can_grab(10.0, true)
	var second = TONGUE_SCRIPT.new()
	second.start()
	second.update(0.1, zombie_pos, target_pos, true, 0)
	second.update(0.1, zombie_pos, target_pos, false, 0)
	var released_by_sight: bool = not second.is_pulling()
	var third = TONGUE_SCRIPT.new()
	third.start()
	third.update(0.1, zombie_pos, Vector3(0.0, 0.0, -TONGUE_SCRIPT.RELEASE_DISTANCE + 0.2), true, 0)
	var released_on_arrival: bool = not third.is_pulling()
	if too_close or blind or not ready or not pulls_toward or not released_by_damage or not cooldown_blocks or not released_by_sight or not released_on_arrival:
		_fail(test_root, "Lingua: perto_demais=%s sem_visao=%s pronta=%s puxa=%s (%s) solta_por_dano=%s recarga=%s solta_sem_visao=%s solta_ao_chegar=%s." % [too_close, blind, ready, pulls_toward, pull, released_by_damage, cooldown_blocks, released_by_sight, released_on_arrival])
		return
	print("PASS: Lingua prende de longe, puxa e solta por dano, visao ou chegada.")


func _test_player_forced_move_overrides_input(test_root: Node) -> void:
	print("Testando jogador puxado ignorando o proprio movimento...")
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.set("reads_local_input", false)
	player.position = Vector3(1700.0, 5.0, 1500.0)
	test_root.add_child(player)
	await test_root.get_tree().physics_frame
	player.call("apply_forced_move", Vector3(0.0, 0.0, 3.5), 1.0)
	player.set("move_input", Vector2(0.0, -1.0))
	player.set("remote_input_age", 0.0)
	player.call("_physics_process", 0.1)
	var pulled := player.velocity.z > 3.0
	player.call("apply_forced_move", Vector3.ZERO, 1.5)
	player.set("move_input", Vector2(1.0, 0.0))
	player.set("remote_input_age", 0.0)
	player.call("_physics_process", 0.1)
	var pinned := absf(player.velocity.x) < 0.01 and absf(player.velocity.z) < 0.01
	player.free()
	if not pulled or not pinned:
		_fail(test_root, "Movimento forcado deveria vencer o input: puxado=%s preso=%s." % [pulled, pinned])
		return
	print("PASS: Jogador puxado ou preso ignora o proprio movimento.")


func _test_healer_heals_nearby_and_picks_corpse(test_root: Node) -> void:
	print("Testando curandeiro curando perto e escolhendo cadaver...")
	var origin := Vector3(1750.0, 1.0, 1500.0)
	var healer := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	healer.set("forced_variant", ZombieMutator.Type.WALKER)
	healer.position = origin
	test_root.add_child(healer)
	healer.set_physics_process(false)
	var hurt := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	hurt.set("forced_variant", ZombieMutator.Type.WALKER)
	hurt.position = origin + Vector3(3.0, 0.0, 0.0)
	test_root.add_child(hurt)
	hurt.set_physics_process(false)
	hurt.set("health", 50)
	var far := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	far.set("forced_variant", ZombieMutator.Type.WALKER)
	far.position = origin + Vector3(HEALER_SCRIPT.HEAL_RADIUS + 4.0, 0.0, 0.0)
	test_root.add_child(far)
	far.set_physics_process(false)
	far.set("health", 50)
	var healed: int = HEALER_SCRIPT.heal_nearby(test_root.get_tree(), healer)
	var hurt_health := int(hurt.get("health"))
	var far_health := int(far.get("health"))
	var healer_untouched := int(healer.get("health")) == int(healer.get("max_health"))
	var near_corpse := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	near_corpse.position = origin + Vector3(0.0, 0.0, 2.0)
	test_root.add_child(near_corpse)
	near_corpse.set_physics_process(false)
	near_corpse.set("is_dead", true)
	var distant_corpse := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	distant_corpse.position = origin + Vector3(0.0, 0.0, HEALER_SCRIPT.REVIVE_RADIUS + 5.0)
	test_root.add_child(distant_corpse)
	distant_corpse.set_physics_process(false)
	distant_corpse.set("is_dead", true)
	var picked: Node = HEALER_SCRIPT.pick_corpse(healer.global_position, [distant_corpse, near_corpse])
	var picked_near := picked == near_corpse
	var none_in_range: Node = HEALER_SCRIPT.pick_corpse(healer.global_position, [distant_corpse])
	for node in [healer, hurt, far, near_corpse, distant_corpse]:
		node.free()
	if healed != 1 or hurt_health != 50 + HEALER_SCRIPT.HEAL_AMOUNT or far_health != 50 or not healer_untouched or not picked_near or none_in_range != null:
		_fail(test_root, "Curandeiro: curou=%d ferido=%d longe=%d curandeiro_intacto=%s cadaver_perto=%s nenhum_no_alcance=%s." % [healed, hurt_health, far_health, healer_untouched, picked_near, none_in_range == null])
		return
	print("PASS: Curandeiro cura so os perto e levanta o cadaver mais proximo.")


func _test_stalker_reveal_and_pounce(test_root: Node) -> void:
	print("Testando espreitador invisivel longe e bote perto...")
	var hidden: float = STALKER_SCRIPT.reveal_opacity(STALKER_SCRIPT.REVEAL_DISTANCE + 2.0)
	var shown: float = STALKER_SCRIPT.reveal_opacity(STALKER_SCRIPT.REVEAL_DISTANCE - 1.0)
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.set("reads_local_input", false)
	test_root.add_child(player)
	var stalker = STALKER_SCRIPT.new()
	var far_pounce: bool = stalker.try_pounce(player, STALKER_SCRIPT.POUNCE_RANGE + 1.0, Vector3.FORWARD)
	var near_pounce: bool = stalker.try_pounce(player, STALKER_SCRIPT.POUNCE_RANGE - 0.5, Vector3.FORWARD)
	var health := int(player.get("health"))
	var pinned := float(player.get("forced_move_time")) >= STALKER_SCRIPT.PIN_SECONDS - 0.01
	var cooldown_blocks: bool = not stalker.try_pounce(player, 1.0, Vector3.FORWARD)
	var max_health := int(player.get("max_health"))
	player.free()
	if hidden > 0.2 or shown < 0.99 or far_pounce or not near_pounce or health != max_health - STALKER_SCRIPT.POUNCE_DAMAGE or not pinned or not cooldown_blocks:
		_fail(test_root, "Espreitador: opacidade longe=%.2f perto=%.2f bote_longe=%s bote_perto=%s vida=%d preso=%s recarga=%s." % [hidden, shown, far_pounce, near_pounce, health, pinned, cooldown_blocks])
		return
	print("PASS: Espreitador some longe, aparece perto e da o bote com recarga.")


func _test_collector_absorbs_and_inherits(test_root: Node) -> void:
	print("Testando coletor: absorve pedaco, herda habilidade e recusa o resto...")
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	# forced_variant antes do add_child: _ready le a variante e monta a aparencia.
	zombie.set("forced_variant", ZombieMutator.Type.COLLECTOR)
	test_root.add_child(zombie)
	zombie.set_physics_process(false)
	var collector = zombie.get("collector")
	var starts_clean := not bool(zombie.call("has_ability", ZombieMutator.Type.SPITTER))
	var refuses_passive: bool = not collector.absorb(ZombieMutator.Type.BRUTE, zombie)
	var took_screamer: bool = collector.absorb(ZombieMutator.Type.SCREAMER, zombie)
	var inherited_scream := bool(zombie.call("has_ability", ZombieMutator.Type.SCREAMER))
	var took_spitter: bool = collector.absorb(ZombieMutator.Type.SPITTER, zombie)
	var took_smoker: bool = collector.absorb(ZombieMutator.Type.SMOKER, zombie)
	var full: bool = collector.is_full()
	var refuses_repeat: bool = not collector.absorb(ZombieMutator.Type.SCREAMER, zombie)
	var inherits_smoker := bool(zombie.call("has_ability", ZombieMutator.Type.SMOKER))
	# test_root nao tem consume_zombie_corpse: o coletor nao pode explodir nem
	# absorver sem um main que hospede a lista de cadaveres.
	var no_host: bool = not collector.try_absorb_nearby(zombie, 1.0)
	var pieces: int = int(collector.get("inherited_types").size())
	zombie.free()
	if not starts_clean or not refuses_passive or not took_screamer or not inherited_scream or not took_spitter or not took_smoker or not full or not refuses_repeat or not inherits_smoker or not no_host or pieces != COLLECTOR_SCRIPT.MAX_ABILITIES:
		_fail(test_root, "Coletor: limpo=%s passiva=%s grito=%s sim=%s cuspe=%s lingua=%s cheio=%s repete=%s herdou_lingua=%s sem_host=%s pedacos=%d." % [starts_clean, refuses_passive, took_screamer, inherited_scream, took_spitter, took_smoker, full, refuses_repeat, inherits_smoker, no_host, pieces])
		return
	print("PASS: Coletor herda ate 3 habilidades, recusa passiva/repetida e come so cadaver util.")


func _test_collector_borrows_dash(test_root: Node) -> void:
	print("Testando coletor: pedaco de arrancada vira estado usavel...")
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	zombie.set("forced_variant", ZombieMutator.Type.COLLECTOR)
	test_root.add_child(zombie)
	zombie.set_physics_process(false)
	var collector = zombie.get("collector")
	var no_dash_before: bool = collector.pick_dash_state() == null
	var took_leaper: bool = collector.absorb(ZombieMutator.Type.LEAPER, zombie)
	var leap_state = collector.dash_state_for(ZombieMutator.Type.LEAPER)
	var ready_after: bool = collector.pick_dash_state() != null
	var leap_range_ok := false
	if leap_state != null:
		# Fora do alcance nao arranca; no alcance, sim.
		leap_state.call("update", 0.1, Vector3.ZERO, Vector3.FORWARD, 99.0, true, 22.0)
		var far_leap := bool(leap_state.call("is_leaping"))
		leap_state.call("update", 0.1, Vector3.ZERO, Vector3.FORWARD, 2.0, true, 22.0)
		leap_range_ok = not far_leap and bool(leap_state.call("is_leaping"))
	zombie.free()
	if not no_dash_before or not took_leaper or leap_state == null or not ready_after or not leap_range_ok:
		_fail(test_root, "Coletor arrancada: sem_antes=%s pegou=%s estado=%s pronto=%s alcance=%s." % [no_dash_before, took_leaper, leap_state != null, ready_after, leap_range_ok])
		return
	print("PASS: Coletor usa a arrancada do pedaco (recarga e alcance do original).")


func _test_collector_borrows_armor(test_root: Node) -> void:
	print("Testando coletor: colete do armored (tiro pela metade, faca cheia)...")
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	zombie.set("forced_variant", ZombieMutator.Type.COLLECTOR)
	test_root.add_child(zombie)
	zombie.set_physics_process(false)
	var collector = zombie.get("collector")
	var plain_bullet: int = ABILITIES_SCRIPT.adjust_incoming_damage(ZombieMutator.Type.COLLECTOR, 40, "bullet")
	var took_armored: bool = collector.absorb(ZombieMutator.Type.ARMORED, zombie)
	var has_armor := bool(zombie.call("has_ability", ZombieMutator.Type.ARMORED))
	var armored_bullet: int = ABILITIES_SCRIPT.adjust_incoming_damage(ZombieMutator.Type.COLLECTOR, 40, "bullet", has_armor)
	var armored_knife: int = ABILITIES_SCRIPT.adjust_incoming_damage(ZombieMutator.Type.COLLECTOR, 40, "melee", has_armor)
	zombie.free()
	if plain_bullet != 40 or not took_armored or not has_armor or armored_bullet >= 40 or armored_knife != 40:
		_fail(test_root, "Coletor colete: sem=%d pegou=%s tem=%s tiro=%d faca=%d." % [plain_bullet, took_armored, has_armor, armored_bullet, armored_knife])
		return
	print("PASS: Coletor herda o colete (tiro pela metade, faca cheia).")


func _test_collector_mutation_scream_heals(test_root: Node) -> void:
	print("Testando mutacao do coletor: grito + curandeiro...")
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	zombie.set("forced_variant", ZombieMutator.Type.COLLECTOR)
	test_root.add_child(zombie)
	zombie.set_physics_process(false)
	var collector = zombie.get("collector")
	collector.absorb(ZombieMutator.Type.SCREAMER, zombie)
	var only_scream: bool = not collector.has_mutation(&"grito_que_cura")
	collector.absorb(ZombieMutator.Type.HEALER, zombie)
	var both: bool = collector.has_mutation(&"grito_que_cura")
	zombie.free()
	if not only_scream or not both:
		_fail(test_root, "Mutacao grito: so_grito=%s com_curandeiro=%s." % [only_scream, both])
		return
	print("PASS: Coletor so muta o grito quando junta curandeiro.")


func _test_main_hooks(test_root: Node) -> void:
	print("Testando ganchos do main para lingua e cadaver levantado...")
	var main_world: Node = MAIN_SCRIPT.new()
	var hooks := main_world.has_method("revive_zombie_corpse") and main_world.has_method("show_zombie_tongue") and main_world.has_method("consume_zombie_corpse")
	main_world.free()
	if not hooks:
		_fail(test_root, "Main deveria ter revive_zombie_corpse, show_zombie_tongue e consume_zombie_corpse.")
		return
	print("PASS: Main atende lingua e cadaver levantado.")


func _fail(test_root: Node, message: String) -> void:
	push_error("FALHA: " + message)
	test_root.set_meta("unit_test_failed", true)
