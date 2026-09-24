# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
extends RefCounted

## Regressao da porta da safehouse: E deve abrir/fechar a porta pelo raycast
## do jogador, e a interacao manual deve sobreviver ao ciclo de auto-close.
## Uso: await SafehouseDoorTests.new().run(test_root)

const SAFEHOUSE_BUILDER := preload("res://scripts/safehouse_builder.gd")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const MAIN_SCENE := preload("res://scenes/main.tscn")


func run(test_root: Node) -> void:
	await _test_interact_toggles_and_auto_reopens(test_root)
	await _test_main_finds_door_of_staged_city(test_root)


## Regressao: desde a cidade em etapas (f7785c7) a safehouse nasce com
## call_deferred, depois do @onready do main. A referencia ficava null, o
## snapshot sempre dizia "fechada" e o client nunca abria a porta na tela.
func _test_main_finds_door_of_staged_city(test_root: Node) -> void:
	print("Testando main achando a porta da safehouse na cidade em etapas...")
	var previous_city := NetworkSession.procedural_city_enabled
	NetworkSession.procedural_city_enabled = true
	var main_world := MAIN_SCENE.instantiate() as Node3D
	main_world.set_process(false)
	main_world.set_physics_process(false)
	test_root.add_child(main_world)
	await test_root.get_tree().process_frame
	await test_root.get_tree().physics_frame
	var door := main_world.get_node_or_null("GeneratedCity/CentralSafehouse/SafehouseDoor")
	# A busca agora e pelo GRUPO, nao por um caminho fixo: o mata-mata tem porta
	# em cada base e todas precisam entrar na mascara do snapshot.
	var listed: Array = SafehouseDoorSync.ordered_doors(test_root.get_tree())
	var found := door != null and listed.has(door)
	main_world.free()
	NetworkSession.procedural_city_enabled = previous_city
	if not found:
		_fail(test_root, "A porta criada depois do _ready deveria entrar na lista do SafehouseDoorSync; porta_na_cena=%s listadas=%d." % [door, listed.size()])
		return
	print("PASS: Porta da cidade em etapas entra na lista replicada (%d porta(s))." % listed.size())


## Player em frente a porta aperta E: raycast deve achar o painel e o toggle
## deve mover o painel ate o angulo aberto; novo E fecha.
func _test_interact_toggles_and_auto_reopens(test_root: Node) -> void:
	print("Testando porta da safehouse respondendo ao E...")
	var house := SAFEHOUSE_BUILDER.build_safehouse() as StaticBody3D
	test_root.add_child(house)
	house.position = Vector3(-300.0, 0.12, -300.0)
	var door := house.get_node("SafehouseDoor") as Node3D
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.set("reads_local_input", false)
	test_root.add_child(player)
	# De frente para o painel: porta em z=-6.25 do centro; olhando -Z o player
	# fica DENTRO da casa em z=-304 (porta 2.25 m a frente, olhando pra ela).
	player.position = Vector3(-300.0, 1.2, -304.0)
	await test_root.get_tree().physics_frame
	await test_root.get_tree().physics_frame
	var ray_start: Vector3 = player.get("head").global_position
	var ray_end: Vector3 = ray_start - player.global_transform.basis.z * 2.5
	var probe := PhysicsRayQueryParameters3D.create(ray_start, ray_end, 1, [player])
	var probe_hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(probe)
	print("DEBUG ray hit=", not probe_hit.is_empty(), " col=", str(probe_hit.get("collider")), " start=", ray_start, " end=", ray_end)
	var sphere := SphereShape3D.new()
	sphere.radius = 0.8
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = sphere
	shape_query.transform = Transform3D(Basis.IDENTITY, Vector3(-300.0, 1.0, -306.25))
	shape_query.collision_mask = 1
	var shape_hits := player.get_world_3d().direct_space_state.intersect_shape(shape_query, 8)
	for shape_hit in shape_hits:
		print("DEBUG shape hit col=", str(shape_hit.get("collider")), " rid=", str(shape_hit.get("rid")))
	player.set("interact_pressed", true)
	player.call("_handle_interaction_input")
	if not bool(door.call("is_open_requested")):
		_fail(test_root, "E deveria abrir a porta da safehouse pelo raycast; toggle=%s." % [door.call("is_open_requested")])
		player.queue_free()
		house.queue_free()
		return
	var panel := door.get_node("Panel") as AnimatableBody3D
	door.call("_physics_process", 0.5)
	var opened_panel: bool = panel.rotation.y < -0.5
	# Com a porta aberta o painel desliga o colisor (para de bloquear); o
	# fechamento e automatico: sem ator perto por CLOSE_HOLD_TIME ela fecha.
	player.queue_free()
	await test_root.get_tree().physics_frame
	await test_root.get_tree().physics_frame
	door.call("_physics_process", 2.1)
	door.call("_physics_process", 2.1)
	var closed_again: bool = not bool(door.call("is_open_requested")) and panel.rotation.y > -0.05 and panel.collision_layer == 1
	house.queue_free()
	if not opened_panel or not closed_again:
		_fail(test_root, "Porta deveria abrir pelo E (angulo=%s), desligar colisao e fechar sozinha sem ator perto; fechada=%s." % [panel.rotation.y, closed_again])
		return
	print("PASS: Porta da safehouse abre pelo E e fecha sozinha ao sair.")


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
