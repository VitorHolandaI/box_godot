# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
extends RefCounted

## Regressoes do tamanho dos zumbis grandes: pes no chao (modelo ampliado a
## partir do centro afundava ~1 m no Tita), capsula acompanhando o corpo e
## cadaver com o mesmo tamanho do zumbi vivo (antes o gigante virava corpo pequeno).
## Uso: await ZombieBodyScaleTests.new().run(test_root)

const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const RAGDOLL_SCENE := preload("res://scenes/zombie_ragdoll.tscn")
const BIG_TYPES: Array[int] = [ZombieMutator.Type.BRUTE, ZombieMutator.Type.TITAN]


func run(test_root: Node) -> void:
	_test_big_zombies_keep_feet_on_ground(test_root)
	_test_voxel_parts_match_the_boxes(test_root)
	await _test_voxel_player_uses_paint(test_root)
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


## As malhas voxel precisam fechar no tamanho exato das caixas originais, senao
## hitbox/anims desalinham; e a cor tem de vir pelo material (sombreado ligado).
func _test_voxel_parts_match_the_boxes(test_root: Node) -> void:
	print("Testando malhas voxel no tamanho das caixas...")
	var specs := [
		{"size": Vector3(0.54, 0.54, 0.54), "kind": "head", "name": "cabeca"},
		{"size": Vector3(0.78, 0.84, 0.4), "kind": "torso", "name": "torso"},
		{"size": Vector3(0.28, 0.84, 0.34), "kind": "limb", "name": "braco"},
		{"size": Vector3(0.34, 0.84, 0.36), "kind": "leg", "name": "perna"},
	]
	for spec in specs:
		var size: Vector3 = spec["size"]
		var mesh := VoxelCharacterBuilder.part_mesh(size, String(spec["kind"]))
		var aabb := mesh.get_aabb()
		var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var fits := aabb.size.distance_to(size) < 0.02 and aabb.position.distance_to(-size * 0.5) < 0.02
		var sane := vertices.size() >= 36 and vertices.size() < 24000
		if mesh.get_surface_count() != 1 or not fits or not sane:
			_fail(test_root, "Voxel de %s: superficies=%d aabb=%s esperado=%s vertices=%d." % [spec["name"], mesh.get_surface_count(), aabb.size, size, vertices.size()])
			return
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	zombie.name = "VoxelZombie"
	zombie.set("simulation_enabled", false)
	test_root.add_child(zombie)
	var head := zombie.get_node("Model/Head") as MeshInstance3D
	var head_mesh := head.mesh as ArrayMesh
	var head_ok := head_mesh != null and head_mesh.get_surface_count() == 1 \
		and head_mesh.get_aabb().size.distance_to(Vector3(0.56, 0.56, 0.56)) < 0.03
	var material := head.material_override
	var uses_vertex_color := false
	if material is StandardMaterial3D:
		uses_vertex_color = (material as StandardMaterial3D).vertex_color_use_as_albedo
	elif material is ShaderMaterial:
		var shader := (material as ShaderMaterial).shader
		uses_vertex_color = shader != null and shader.code.contains("COLOR.rgb")
	zombie.free()
	if not head_ok or not uses_vertex_color:
		_fail(test_root, "Zumbi: malha_voxel=%s sombreado=%s." % [head_ok, uses_vertex_color])
		return
	print("PASS: Malhas voxel batem com as caixas e o zumbi usa sombreamento por vertice.")


## O jogador precisa usar a malha voxel e a pintura salva (pele/camisa).
func _test_voxel_player_uses_paint(test_root: Node) -> void:
	print("Testando voxel e pintura do jogador...")
	PlayerPaint.load_config()
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	test_root.add_child(player)
	player.set_physics_process(false)
	await test_root.get_tree().process_frame
	var head := player.get_node("Model/Head") as MeshInstance3D
	var torso := player.get_node("Model/Torso") as MeshInstance3D
	var head_mesh := head.mesh as ArrayMesh
	var head_ok := head_mesh != null and head_mesh.get_surface_count() == 1 \
		and head_mesh.get_aabb().size.distance_to(Vector3(0.54, 0.54, 0.54)) < 0.03
	var head_material := head.material_override as StandardMaterial3D
	var torso_material := torso.material_override as StandardMaterial3D
	var painted := head_material != null and head_material.vertex_color_use_as_albedo \
		and head_material.albedo_color.is_equal_approx(PlayerPaint.skin)
	var shirt_ok := torso_material != null and torso_material.albedo_color.is_equal_approx(PlayerPaint.shirt)
	player.queue_free()
	await test_root.get_tree().process_frame
	if not head_ok or not painted or not shirt_ok:
		_fail(test_root, "Jogador voxel: malha=%s pele=%s camisa=%s." % [head_ok, painted, shirt_ok])
		return
	print("PASS: Jogador usa malha voxel e a pintura salva.")
