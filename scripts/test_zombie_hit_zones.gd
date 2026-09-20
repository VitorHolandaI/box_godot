extends RefCounted

## Regressoes do dano localizado (item 5): a zona do corpo vem da parte mais
## proxima do ponto de impacto; cabeca dobra o dano, perna derruba a velocidade
## e braco enfraquece o golpe. Sem ponto de impacto (melee/fogo) nada muda.
## Uso: await ZombieHitZoneTests.new().run(test_root)

const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")
const ZOMBIE_SCRIPT: GDScript = preload("res://scripts/zombie.gd")


func run(test_root: Node) -> void:
	_test_body_zone_is_nearest_part(test_root)
	await _test_headshot_doubles_damage(test_root)
	await _test_leg_shot_slows_zombie(test_root)
	await _test_arm_shot_weakens_attack(test_root)
	await _test_hit_without_position_is_torso(test_root)


func _test_body_zone_is_nearest_part(test_root: Node) -> void:
	print("Testando a zona pela parte mais proxima do impacto...")
	var points := {
		"head": [Vector3(0.0, 1.14, 0.0)],
		"torso": [Vector3(0.0, 0.1, 0.0)],
		"arm": [Vector3(0.6, 0.3, 0.0)],
		"leg": [Vector3(0.2, -0.5, 0.0)],
	}
	var head: String = ZOMBIE_SCRIPT.body_zone_for_points(Vector3(0.05, 1.1, 0.0), points)
	var torso: String = ZOMBIE_SCRIPT.body_zone_for_points(Vector3(0.0, 0.05, 0.2), points)
	var arm: String = ZOMBIE_SCRIPT.body_zone_for_points(Vector3(0.62, 0.32, 0.0), points)
	var leg: String = ZOMBIE_SCRIPT.body_zone_for_points(Vector3(0.2, -0.45, 0.0), points)
	if head != "head" or torso != "torso" or arm != "arm" or leg != "leg":
		_fail(test_root, "Zona deveria ser head/torso/arm/leg; veio %s/%s/%s/%s." % [head, torso, arm, leg])
		return
	print("PASS: Zona do corpo e a parte mais proxima do impacto.")


func _test_headshot_doubles_damage(test_root: Node) -> void:
	print("Testando tiro na cabeca dobrando o dano...")
	var zombie := await _spawn_walker(test_root, Vector3(1000.0, 1.0, 1000.0))
	var point := (zombie.get_node("Model/Head") as Node3D).global_position
	zombie.take_damage(10, Vector3.FORWARD, "bullet", null, point)
	var health_after := int(zombie.get("health"))
	var zone := String(zombie.get("last_hit_zone"))
	zombie.free()
	if zone != "head" or health_after != 80:
		_fail(test_root, "Cabeca deveria dar 2x (10->20) e zona 'head'; vida=%d zona=%s." % [health_after, zone])
		return
	print("PASS: Tiro na cabeca dobra o dano.")


func _test_leg_shot_slows_zombie(test_root: Node) -> void:
	print("Testando tiro na perna derrubando a velocidade...")
	var zombie := await _spawn_walker(test_root, Vector3(1010.0, 1.0, 1000.0))
	var base_speed := float(zombie.get("speed"))
	var point := (zombie.get_node("Model/LeftLeg") as Node3D).global_position
	zombie.take_damage(10, Vector3.FORWARD, "bullet", null, point)
	var speed_after := float(zombie.get("speed"))
	var leg_shot := bool(zombie.get("leg_shot"))
	zombie.free()
	if not leg_shot or speed_after >= base_speed or speed_after < 0.6:
		_fail(test_root, "Perna deveria derrubar a velocidade (%.2f -> %.2f) e marcar leg_shot; leg_shot=%s." % [base_speed, speed_after, leg_shot])
		return
	print("PASS: Tiro na perna derruba a velocidade (%.2f -> %.2f)." % [base_speed, speed_after])


func _test_arm_shot_weakens_attack(test_root: Node) -> void:
	print("Testando tiro no braco enfraquecendo o golpe...")
	var zombie := await _spawn_walker(test_root, Vector3(1020.0, 1.0, 1000.0))
	var base_attack := int(zombie.get("attack_damage"))
	var point := (zombie.get_node("Model/LeftArm") as Node3D).global_position
	zombie.take_damage(10, Vector3.FORWARD, "bullet", null, point)
	var attack_after := int(zombie.get("attack_damage"))
	var arm_shot := bool(zombie.get("arm_shot"))
	zombie.free()
	if not arm_shot or attack_after >= base_attack:
		_fail(test_root, "Braco deveria enfraquecer o golpe (%d -> %d) e marcar arm_shot; arm_shot=%s." % [base_attack, attack_after, arm_shot])
		return
	print("PASS: Tiro no braco enfraquece o golpe (%d -> %d)." % [base_attack, attack_after])


## Melee, fogo e explosao nao passam ponto de impacto: dano cheio, zona torso.
func _test_hit_without_position_is_torso(test_root: Node) -> void:
	print("Testando dano sem ponto de impacto (melee/fogo)...")
	var zombie := await _spawn_walker(test_root, Vector3(1030.0, 1.0, 1000.0))
	zombie.take_damage(10, Vector3.FORWARD, "melee", null)
	var health_after := int(zombie.get("health"))
	var zone := String(zombie.get("last_hit_zone"))
	var speed_after := float(zombie.get("speed"))
	zombie.free()
	if health_after != 90 or zone != "torso" or not is_equal_approx(speed_after, 2.2):
		_fail(test_root, "Sem impacto deveria ser torso sem debuff; vida=%d zona=%s velocidade=%.2f." % [health_after, zone, speed_after])
		return
	print("PASS: Dano sem ponto de impacto conta como torso e nao debuffa.")


func _spawn_walker(test_root: Node, position: Vector3) -> CharacterBody3D:
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	zombie.name = "HitZoneTarget"
	zombie.set("forced_variant", ZombieMutator.Type.WALKER)
	zombie.set("gravity", 0.0)
	zombie.position = position
	test_root.add_child(zombie)
	zombie.set_physics_process(false)
	await test_root.get_tree().physics_frame
	return zombie


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
