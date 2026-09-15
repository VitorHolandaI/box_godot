extends RefCounted

## Regressoes do arsenal ampliado: toda arma de crate aparece em todo lugar que
## depende do tipo (municao de classe, drop, crate, modelo na mao, cor), o
## railgun atravessa a fila de zumbis e armas futuristas tem tracer proprio.
## Uso: await WeaponArsenalTests.new().run(test_root)

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")
const DIRECTOR_SCRIPT := preload("res://scripts/ammo_loot_director.gd")
const SCHEDULE_SCRIPT := preload("res://scripts/survival_wave_schedule.gd")
const MIN_CRATE_WEAPONS := 16


func run(test_root: Node) -> void:
	_test_player_enum_matches_stats(test_root)
	_test_every_crate_weapon_is_wired(test_root)
	await _test_railgun_pierces_line_of_zombies(test_root)
	_test_futuristic_weapons_have_own_tracer(test_root)


func _test_player_enum_matches_stats(test_root: Node) -> void:
	print("Testando enum de armas do jogador igual a tabela de stats...")
	var player_names: Array = PlayerCharacter.Weapon.keys()
	var stats_names: Array = WeaponStats.Kind.keys()
	if player_names != stats_names:
		_fail(test_root, "PlayerCharacter.Weapon e WeaponStats.Kind devem ter os mesmos tipos na mesma ordem; jogador=%s stats=%s." % [player_names, stats_names])
		return
	print("PASS: Enum de armas do jogador bate com a tabela de stats.")


func _test_every_crate_weapon_is_wired(test_root: Node) -> void:
	print("Testando cada arma de crate ligada em municao, drop, crate e modelo...")
	var kinds: Array[int] = WeaponStats.crate_kinds()
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.set("reads_local_input", false)
	player.set("is_local_controller", false)
	test_root.add_child(player)
	var problems: Array[String] = []
	var schedule = SCHEDULE_SCRIPT.new()
	var crate_kinds_seen: Dictionary = {}
	for seed_value in 400:
		for kind in schedule.crate_kinds_for_wave(30, seed_value):
			crate_kinds_seen[kind] = true
	for kind in kinds:
		var label := String(WeaponStats.stats_for(kind).get("label", ""))
		var ammo_kind := DIRECTOR_SCRIPT.supply_kind_for_weapon(kind)
		if ammo_kind < 0:
			problems.append("%s sem municao de classe" % label)
		elif not DIRECTOR_SCRIPT.RESTOCKED_KINDS.has(ammo_kind) or not GroundSupplyPickup.CLASS_LABELS.has(ammo_kind) or not GroundSupplyPickup.CLASS_COLORS.has(ammo_kind) or not DIRECTOR_SCRIPT.AMOUNT_BY_KIND.has(ammo_kind):
			problems.append("%s com municao sem reposicao/etiqueta/cor/quantidade" % label)
		if not DIRECTOR_SCRIPT.droppable_weapons().has(kind):
			problems.append("%s fora do drop dos zumbis" % label)
		if not crate_kinds_seen.has(kind):
			problems.append("%s nunca sai no crate" % label)
		if player.find_child("CrateWeapon%d" % kind, true, false) == null:
			problems.append("%s sem modelo na mao" % label)
	player.free()
	if kinds.size() < MIN_CRATE_WEAPONS or not problems.is_empty():
		_fail(test_root, "Arsenal com %d armas de crate (minimo %d); problemas=%s." % [kinds.size(), MIN_CRATE_WEAPONS, problems])
		return
	print("PASS: %d armas de crate ligadas em municao, drop, crate e modelo." % kinds.size())


func _test_railgun_pierces_line_of_zombies(test_root: Node) -> void:
	print("Testando railgun atravessando a fila de zumbis...")
	var origin := Vector3(-900.0, 1.0, 900.0)
	var shooter := PLAYER_SCENE.instantiate() as CharacterBody3D
	shooter.set("reads_local_input", false)
	shooter.set("simulation_enabled", false)
	shooter.set("is_local_controller", false)
	shooter.position = origin
	test_root.add_child(shooter)
	var zombies: Array[CharacterBody3D] = []
	for index in 3:
		var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
		zombie.name = "RailTarget%d" % index
		zombie.set("forced_variant", ZombieMutator.Type.WALKER)
		zombie.position = origin + Vector3(0.0, 0.0, -4.0 - float(index) * 2.5)
		test_root.add_child(zombie)
		zombie.set_physics_process(false)
		zombies.append(zombie)
	await test_root.get_tree().physics_frame
	Bullet.hitscan_damage(origin + Vector3.UP * 0.55, Vector3.FORWARD, 30, shooter, int(WeaponStats.stats_for(WeaponStats.Kind.RAILGUN)["pierce"]))
	var railgun_hits := 0
	for zombie in zombies:
		if int(zombie.get("health")) < int(zombie.get("max_health")):
			railgun_hits += 1
		zombie.set("health", int(zombie.get("max_health")))
	Bullet.hitscan_damage(origin + Vector3.UP * 0.55, Vector3.FORWARD, 30, shooter, 1)
	var single_hits := 0
	for zombie in zombies:
		if int(zombie.get("health")) < int(zombie.get("max_health")):
			single_hits += 1
	shooter.free()
	for zombie in zombies:
		zombie.free()
	if railgun_hits != 3 or single_hits != 1:
		_fail(test_root, "Railgun deveria ferir os 3 zumbis da fila e tiro comum so o primeiro; railgun=%d comum=%d." % [railgun_hits, single_hits])
		return
	print("PASS: Railgun atravessa a fila; tiro comum para no primeiro.")


func _test_futuristic_weapons_have_own_tracer(test_root: Node) -> void:
	print("Testando tracer das armas futuristas...")
	var default_color := WeaponStats.tracer_color_for(WeaponStats.Kind.UZI)
	var colors: Dictionary = {}
	for kind in [WeaponStats.Kind.LASER_RIFLE, WeaponStats.Kind.PLASMA_SMG, WeaponStats.Kind.RAILGUN]:
		colors[WeaponStats.tracer_color_for(kind)] = true
	if colors.size() != 3 or colors.has(default_color):
		_fail(test_root, "Laser, plasma e railgun deveriam ter tracers distintos do padrao; cores=%s padrao=%s." % [colors.keys(), default_color])
		return
	print("PASS: Armas futuristas tem tracer proprio.")


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
