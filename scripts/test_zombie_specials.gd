extends RefCounted

## Regressoes das especiais estilo Left 4 Dead: cuspidor (poca de acido) e
## investida (charger), tipos acima de 15 no snapshot e especiais ja na hora 1.
## Uso: await ZombieSpecialsTests.new().run(test_root)

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const CODEC_SCRIPT := preload("res://scripts/zombie_snapshot_codec.gd")
const ABILITIES_SCRIPT := preload("res://scripts/zombie_variant_abilities.gd")
const ACID_PUDDLE_SCRIPT := preload("res://scripts/acid_puddle.gd")
const SCHEDULE_SCRIPT := preload("res://scripts/survival_wave_schedule.gd")


func run(test_root: Node) -> void:
	_test_codec_carries_types_above_fifteen(test_root)
	_test_specials_from_first_hour(test_root)
	_test_random_variants_skip_titan(test_root)
	_test_spit_needs_range_line_and_cooldown(test_root)
	_test_acid_puddle_burns_then_expires(test_root)
	_test_charger_dash_range_and_hit(test_root)


func _test_codec_carries_types_above_fifteen(test_root: Node) -> void:
	print("Testando tipos de zumbi acima de 15 no snapshot...")
	var states: Array = []
	for zombie_type in [0, 14, ZombieMutator.Type.SPITTER, ZombieMutator.Type.CHARGER, 100]:
		states.append({"network_id": zombie_type + 1, "position": Vector3.ZERO, "is_dead": zombie_type == 100, "zombie_type": zombie_type})
	var decoded: Array[Dictionary] = CODEC_SCRIPT.decode(CODEC_SCRIPT.encode(states))
	var types: Array[int] = []
	for state in decoded:
		types.append(int(state["zombie_type"]))
	var expected: Array[int] = [0, 14, ZombieMutator.Type.SPITTER, ZombieMutator.Type.CHARGER, 100]
	if types != expected or not bool(decoded[4]["is_dead"]) or bool(decoded[3]["is_dead"]):
		_fail(test_root, "Snapshot deveria levar tipos ate 127 sem mexer na flag de morte; tipos=%s." % [types])
		return
	print("PASS: Snapshot leva tipos de zumbi ate 127.")


func _test_specials_from_first_hour(test_root: Node) -> void:
	print("Testando especiais desde a primeira hora...")
	var schedule = SCHEDULE_SCRIPT.new()
	var first: Dictionary = schedule.variant_mix_for_wave(0)
	var missing: Array[String] = []
	for special in [ZombieMutator.Type.LEAPER, ZombieMutator.Type.SPITTER, ZombieMutator.Type.BLOATER, ZombieMutator.Type.CHARGER]:
		if int(first.get(special, 0)) <= 0:
			missing.append(ZombieMutator.Type.keys()[ZombieMutator.Type.values().find(special)])
	var all_stages_have_specials := true
	for wave_index in [3, 7, 12]:
		var mix: Dictionary = schedule.variant_mix_for_wave(wave_index)
		all_stages_have_specials = all_stages_have_specials and int(mix.get(ZombieMutator.Type.SPITTER, 0)) > 0 and int(mix.get(ZombieMutator.Type.CHARGER, 0)) > 0
	if not missing.is_empty() or first.has(ZombieMutator.Type.ARMORED) or not all_stages_have_specials:
		_fail(test_root, "Hora 1 deveria ter leaper, cuspidor, bloater e investida (armored so depois) e as fases seguintes manter cuspidor/investida; faltando=%s." % [missing])
		return
	print("PASS: Especiais aparecem desde a hora 1.")


func _test_random_variants_skip_titan(test_root: Node) -> void:
	print("Testando sorteio comum com especiais novas e sem Tita...")
	var seen: Dictionary = {}
	for hash_value in 3000:
		var variant := ZombieMutator.random_variant_for_hash(hash_value)
		if variant == ZombieMutator.Type.TITAN:
			_fail(test_root, "Sorteio comum gerou Tita no hash %d." % hash_value)
			return
		seen[variant] = true
	if seen.size() != ZombieMutator.TYPE_COUNT - 1:
		_fail(test_root, "Sorteio comum deveria cobrir todos os %d tipos menos o Tita; cobriu %d." % [ZombieMutator.TYPE_COUNT - 1, seen.size()])
		return
	print("PASS: Sorteio comum cobre as especiais e nunca gera Tita.")


func _test_spit_needs_range_line_and_cooldown(test_root: Node) -> void:
	print("Testando cuspe do cuspidor...")
	var spit = ABILITIES_SCRIPT.SpitState.new()
	var too_close: bool = spit.update(0.1, 2.0, true)
	var blocked: bool = spit.update(0.1, 8.0, false)
	var fires: bool = spit.update(0.1, 8.0, true)
	var cooling: bool = spit.update(0.1, 8.0, true)
	var again: bool = spit.update(ABILITIES_SCRIPT.SPIT_COOLDOWN, 8.0, true)
	if too_close or blocked or not fires or cooling or not again:
		_fail(test_root, "Cuspe: perto demais nao, sem visao nao, no alcance sim, na recarga nao, depois sim; %s/%s/%s/%s/%s." % [too_close, blocked, fires, cooling, again])
		return
	print("PASS: Cuspidor cospe no alcance, com visao e com recarga.")


func _test_acid_puddle_burns_then_expires(test_root: Node) -> void:
	print("Testando poca de acido...")
	var origin := Vector3(-960.0, 1.0, -960.0)
	var inside := _add_player(test_root, origin + Vector3(1.0, 0.0, 0.0))
	var outside := _add_player(test_root, origin + Vector3(6.0, 0.0, 0.0))
	var puddle = ACID_PUDDLE_SCRIPT.new()
	puddle.damages = true
	test_root.add_child(puddle)
	puddle.global_position = origin
	puddle.call("_physics_process", 1.0)
	var burned := int(inside.get("health")) < int(inside.get("max_health"))
	var spared := int(outside.get("health")) == int(outside.get("max_health"))
	puddle.call("_physics_process", ACID_PUDDLE_SCRIPT.LIFETIME)
	var expired: bool = puddle.is_queued_for_deletion()
	inside.free()
	outside.free()
	puddle.free()
	if not burned or not spared or not expired:
		_fail(test_root, "Poca queima quem esta dentro, poupa quem esta fora e some; queimou=%s poupou=%s sumiu=%s." % [burned, spared, expired])
		return
	print("PASS: Poca de acido queima dentro do raio e some.")


func _test_charger_dash_range_and_hit(test_root: Node) -> void:
	print("Testando investida do charger...")
	var charge = ABILITIES_SCRIPT.ChargeState.new()
	var toward := Vector3(1.0, 0.0, 0.0)
	var close: Vector3 = charge.update(0.1, Vector3.ZERO, toward, 2.0, true)
	var start: Vector3 = charge.update(0.1, Vector3.ZERO, toward, 9.0, true)
	var charging: bool = charge.is_leaping()
	var player := _add_player(test_root, Vector3(-940.0, 1.0, -960.0))
	var before := int(player.get("health"))
	ABILITIES_SCRIPT.charge_impact(player, toward)
	var hit := int(player.get("health")) < before and player.velocity.x > 1.0
	player.free()
	if close != Vector3.ZERO or start.x < ABILITIES_SCRIPT.CHARGE_SPEED - 0.01 or not charging or not hit:
		_fail(test_root, "Investida: nao arranca colado, arranca a 9 m e arremessa o jogador; colado=%s arrancada=%s correndo=%s acerto=%s." % [close, start, charging, hit])
		return
	print("PASS: Charger arranca de longe e arremessa o jogador.")


func _add_player(test_root: Node, position: Vector3) -> CharacterBody3D:
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.set("reads_local_input", false)
	player.set("simulation_enabled", false)
	player.set("is_local_controller", false)
	player.position = position
	test_root.add_child(player)
	return player


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
