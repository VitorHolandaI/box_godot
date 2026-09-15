extends RefCounted

## Regressoes do super zumbi (Tita): stats de chefe, onda de chefe a cada 10
## horas, habilidades (pisao, invocacao, furia) e onda que so acaba com ele morto.
## Uso: ZombieBossTests.new().run(test_root)

const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const BRAIN_SCRIPT := preload("res://scripts/zombie_boss_brain.gd")
const SCHEDULE_SCRIPT := preload("res://scripts/survival_wave_schedule.gd")
const WAVE_CONTROLLER_SCRIPT := preload("res://scripts/survival_wave_controller.gd")
const ABILITIES_SCRIPT := preload("res://scripts/zombie_variant_abilities.gd")


func run(test_root: Node) -> void:
	_test_titan_stats(test_root)
	_test_random_variants_never_titan(test_root)
	_test_boss_every_ten_hours(test_root)
	_test_slam_needs_player_in_range_and_cooldown(test_root)
	_test_summon_and_rage_fire_once(test_root)
	_test_slam_damages_players_in_radius(test_root)
	_test_wave_waits_for_boss(test_root)
	_test_health_label_only_on_boss(test_root)


func _test_titan_stats(test_root: Node) -> void:
	print("Testando stats do Tita...")
	var titan := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	titan.name = "BossTitanStats"
	titan.set("forced_variant", ZombieMutator.Type.TITAN)
	titan.position = Vector3(970.0, 1.0, -970.0)
	test_root.add_child(titan)
	var shape := (titan.get_node("CollisionShape") as CollisionShape3D).shape as CapsuleShape3D
	var scene_shape := (ZOMBIE_SCENE.instantiate() as Node)
	var default_radius := ((scene_shape.get_node("CollisionShape") as CollisionShape3D).shape as CapsuleShape3D).radius
	scene_shape.free()
	var health := int(titan.get("max_health"))
	var knockback_before := titan.velocity
	titan.take_damage(10, Vector3.FORWARD, "bullet", null)
	var knockback := titan.velocity.distance_to(knockback_before)
	var radius := shape.radius
	titan.free()
	if health != 10000 or radius <= default_radius or knockback > 0.01:
		_fail(test_root, "Tita: 10000 de vida, capsula maior, sem recuo de tiro; vida=%d raio=%.2f padrao=%.2f recuo=%.2f." % [health, radius, default_radius, knockback])
		return
	print("PASS: Tita nasce com 10000 de vida, corpo maior e sem recuo.")


func _test_random_variants_never_titan(test_root: Node) -> void:
	print("Testando sorteio aleatorio sem Tita...")
	for hash_value in 2000:
		if ZombieMutator.random_variant_for_hash(hash_value * 7919) == ZombieMutator.Type.TITAN:
			_fail(test_root, "Sorteio pelo hash %d gerou Tita; chefe so nasce na onda de chefe." % (hash_value * 7919))
			return
	print("PASS: Tita nunca sai no sorteio comum.")


func _test_boss_every_ten_hours(test_root: Node) -> void:
	print("Testando onda de chefe a cada 10 horas...")
	var schedule = SCHEDULE_SCRIPT.new()
	var boss_hours: Array[int] = []
	for wave_index in schedule.wave_count():
		if schedule.is_boss_wave(wave_index):
			boss_hours.append(wave_index + 1)
	if boss_hours.is_empty() or boss_hours[0] != 10 or boss_hours.any(func(hour: int) -> bool: return hour % 10 != 0):
		_fail(test_root, "Chefe deveria nascer nas horas multiplas de 10; horas=%s." % [boss_hours])
		return
	print("PASS: Chefe nas horas %s." % [boss_hours])


func _test_slam_needs_player_in_range_and_cooldown(test_root: Node) -> void:
	print("Testando pisao do Tita...")
	var brain = BRAIN_SCRIPT.new()
	var far: Array[String] = brain.tick(0.1, 1.0, BRAIN_SCRIPT.SLAM_RANGE + 3.0)
	var near: Array[String] = brain.tick(0.1, 1.0, 2.0)
	var cooling: Array[String] = brain.tick(0.1, 1.0, 2.0)
	var ready: Array[String] = brain.tick(BRAIN_SCRIPT.SLAM_COOLDOWN, 1.0, 2.0)
	if far.has("slam") or not near.has("slam") or cooling.has("slam") or not ready.has("slam"):
		_fail(test_root, "Pisao: longe nao, perto sim, na recarga nao, depois sim; %s/%s/%s/%s." % [far, near, cooling, ready])
		return
	print("PASS: Pisao so com jogador perto e respeita a recarga.")


func _test_summon_and_rage_fire_once(test_root: Node) -> void:
	print("Testando invocacao e furia do Tita...")
	var brain = BRAIN_SCRIPT.new()
	var fired: Array[String] = []
	for health_fraction in [0.9, 0.6, 0.55, 0.3, 0.28, 0.2, 0.1]:
		fired.append_array(brain.tick(0.1, health_fraction, 99.0))
	if fired.count("summon") != 2 or fired.count("rage") != 1:
		_fail(test_root, "Invocacao em 66%% e 33%% (2x) e furia abaixo de 25%% (1x); disparos=%s." % [fired])
		return
	print("PASS: Tita invoca duas vezes e entra em furia uma vez.")


func _test_slam_damages_players_in_radius(test_root: Node) -> void:
	print("Testando dano em area do pisao...")
	var origin := Vector3(975.0, 1.0, 975.0)
	var near := PLAYER_SCENE.instantiate() as CharacterBody3D
	near.set("reads_local_input", false)
	near.position = origin + Vector3(3.0, 0.0, 0.0)
	test_root.add_child(near)
	var far := PLAYER_SCENE.instantiate() as CharacterBody3D
	far.set("reads_local_input", false)
	far.position = origin + Vector3(15.0, 0.0, 0.0)
	test_root.add_child(far)
	ABILITIES_SCRIPT.area_damage(test_root.get_tree(), origin, BRAIN_SCRIPT.SLAM_RANGE, BRAIN_SCRIPT.SLAM_PLAYER_DAMAGE, 0, 0, null)
	var near_hit := int(near.get("health")) < int(near.get("max_health"))
	var far_safe := int(far.get("health")) == int(far.get("max_health"))
	near.free()
	far.free()
	if not near_hit or not far_safe:
		_fail(test_root, "Pisao deveria ferir quem esta a 3 m e poupar quem esta a 15 m; perto=%s longe_ileso=%s." % [near_hit, far_safe])
		return
	print("PASS: Pisao fere so quem esta no raio.")


func _test_wave_waits_for_boss(test_root: Node) -> void:
	print("Testando onda esperando o chefe morrer...")
	var controller = WAVE_CONTROLLER_SCRIPT.new(func() -> bool: return true)
	var target: int = controller.schedule.target_for(0)
	for _index in target:
		controller.tick(WAVE_CONTROLLER_SCRIPT.SPAWN_INTERVAL + 0.01)
	controller.register_extra_spawn()
	for _index in target:
		controller.register_death()
	controller.tick(0.1)
	var still_first_wave: bool = controller.wave_index == 0
	controller.register_death()
	controller.tick(0.1)
	if not still_first_wave or controller.wave_index != 1:
		_fail(test_root, "Onda so avanca depois do chefe morrer; antes=%s onda_depois=%d." % [still_first_wave, controller.wave_index])
		return
	print("PASS: Onda so termina com o chefe morto.")


## Vida flutuante so no chefe: 600 Label3D reescritos por snapshot davam lag.
func _test_health_label_only_on_boss(test_root: Node) -> void:
	print("Testando vida flutuante so no Tita...")
	var walker := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	walker.name = "LabelWalker"
	walker.set("forced_variant", ZombieMutator.Type.WALKER)
	walker.set("simulation_enabled", false)
	test_root.add_child(walker)
	var walker_label := walker.get_node("HealthLabel") as Label3D
	var default_text := walker_label.text
	walker.apply_network_state({"health": 37})
	walker.set_vision_visible(true)
	walker.call("_update_visual_fade", 1.0)
	var walker_hidden := not walker_label.visible and walker_label.text == default_text
	var titan := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	titan.name = "LabelTitan"
	titan.set("forced_variant", ZombieMutator.Type.TITAN)
	titan.set("simulation_enabled", false)
	test_root.add_child(titan)
	titan.apply_network_state({"health": 9000})
	titan.set_vision_visible(true)
	titan.call("_update_visual_fade", 1.0)
	var titan_label := titan.get_node("HealthLabel") as Label3D
	var titan_shown := titan_label.visible and titan_label.text == "9000/10000"
	walker.free()
	titan.free()
	if not walker_hidden or not titan_shown:
		_fail(test_root, "Vida flutuante: zumbi comum oculto e sem reescrever texto, Tita visivel; comum_oculto=%s tita=%s." % [walker_hidden, titan_shown])
		return
	print("PASS: So o Tita mostra a vida flutuante.")


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
