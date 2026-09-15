extends RefCounted

## Regressoes do tamanho dos zumbis grandes: pes no chao (modelo ampliado a
## partir do centro afundava ~1 m no Tita), capsula acompanhando o corpo e
## cadaver com o mesmo tamanho do zumbi vivo (antes o gigante virava corpo pequeno).
## Uso: await ZombieBodyScaleTests.new().run(test_root)

const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")
const RAGDOLL_SCENE := preload("res://scenes/zombie_ragdoll.tscn")
const BIG_TYPES: Array[int] = [ZombieMutator.Type.BRUTE, ZombieMutator.Type.TITAN]


func run(test_root: Node) -> void:
	_test_big_zombies_keep_feet_on_ground(test_root)
	await _test_ragdoll_matches_body_scale(test_root)


func _test_big_zombies_keep_feet_on_ground(test_root: Node) -> void:
	print("Testando pes no chao e capsula dos zumbis grandes...")
	for zombie_type in BIG_TYPES:
		var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
		zombie.name = "BodyScale%d" % zombie_type
		zombie.set("forced_variant", zombie_type)
		zombie.set("simulation_enabled", false)
		test_root.add_child(zombie)
		var model := zombie.get_node("Model") as Node3D
		var feet_y := model.position.y + ZombieMutator.MODEL_FEET_Y * model.scale.y
		var collision := zombie.get_node("CollisionShape") as CollisionShape3D
		var capsule := collision.shape as CapsuleShape3D
		var capsule_bottom := collision.position.y - capsule.height * 0.5
		var scale := ZombieMutator.body_scale_for(zombie_type)
		var expected_radius := minf(ZombieMutator.BASE_CAPSULE_RADIUS * maxf(scale.x, scale.z), ZombieMutator.MAX_CAPSULE_RADIUS)
		var report := "tipo=%d pes=%.2f base_capsula=%.2f raio=%.2f" % [zombie_type, feet_y, capsule_bottom, capsule.radius]
		zombie.free()
		if absf(feet_y - ZombieMutator.MODEL_FEET_Y) > 0.01 or absf(capsule_bottom - ZombieMutator.CAPSULE_BOTTOM_Y) > 0.01 or not is_equal_approx(capsule.radius, expected_radius):
			_fail(test_root, "Zumbi grande com pes em %.2f, base da capsula em %.2f e raio %.2f; %s." % [ZombieMutator.MODEL_FEET_Y, ZombieMutator.CAPSULE_BOTTOM_Y, expected_radius, report])
			return
	print("PASS: Brute e Tita pisam no chao com capsula do tamanho do corpo.")


func _test_ragdoll_matches_body_scale(test_root: Node) -> void:
	print("Testando cadaver do Tita no tamanho do zumbi...")
	var normal := RAGDOLL_SCENE.instantiate()
	normal.position = Vector3(990.0, 5.0, 990.0)
	test_root.add_child(normal)
	var titan := RAGDOLL_SCENE.instantiate()
	titan.set("body_scale", ZombieMutator.body_scale_for(ZombieMutator.Type.TITAN))
	titan.position = Vector3(995.0, 5.0, 990.0)
	test_root.add_child(titan)
	await test_root.get_tree().physics_frame
	var normal_size := ((normal.get_node("Torso/Mesh") as MeshInstance3D).mesh as BoxMesh).size
	var titan_size := ((titan.get_node("Torso/Mesh") as MeshInstance3D).mesh as BoxMesh).size
	var titan_shape := ((titan.get_node("Torso/Collision") as CollisionShape3D).shape as BoxShape3D).size
	normal.free()
	titan.free()
	var ratio := titan_size.y / normal_size.y
	if absf(ratio - 2.3) > 0.01 or not titan_shape.is_equal_approx(titan_size):
		_fail(test_root, "Cadaver do Tita deveria ser 2.3x com colisao igual a malha; proporcao=%.2f malha=%s colisao=%s." % [ratio, titan_size, titan_shape])
		return
	print("PASS: Cadaver do Tita tem o mesmo tamanho do zumbi vivo.")


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
