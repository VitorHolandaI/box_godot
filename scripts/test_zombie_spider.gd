# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
extends RefCounted

## Regressoes da aranha: o corpo precisa ficar REBAIXADO e inclinado para as 4
## patas tocarem o chao. Antes so inclinava e a marcha reescrevia o Y para ~0,
## entao ela andava de pe.
## Uso: ZombieSpiderTests.new().run(test_root)

const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")
const SPIDER_TYPE := ZombieMutator.Type.SPIDER


func run(test_root: Node) -> void:
	_test_spider_low_on_four_legs(test_root)


func _test_spider_low_on_four_legs(test_root: Node) -> void:
	print("Testando a aranha rebaixada em 4 patas...")
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	zombie.name = "SpiderTest"
	zombie.set("forced_variant", SPIDER_TYPE)
	zombie.set("gravity", 0.0)
	zombie.position = Vector3(1200.0, 1.0, 1200.0)
	test_root.add_child(zombie)
	zombie.set_physics_process(false)
	var model := zombie.get_node("Model") as Node3D
	var limbs := 0
	for limb_index in ZombieMutator.SPIDER_LIMB_COUNT:
		if zombie.get_node_or_null("Model/SpiderLimb%d" % limb_index) != null:
			limbs += 1
	var body_y := model.position.y
	var pitch := model.rotation.x
	zombie.free()
	var expected_y := ZombieMutator.body_rest_y(SPIDER_TYPE)
	var expected_pitch := deg_to_rad(ZombieMutator.SPIDER_PITCH_DEG)
	if limbs != ZombieMutator.SPIDER_LIMB_COUNT \
			or absf(body_y - expected_y) > 0.01 \
			or absf(pitch - expected_pitch) > 0.01:
		_fail(test_root, "Aranha deveria ter %d patas, corpo em y=%.2f e pitch=%.2f; veio %d patas, y=%.2f pitch=%.2f." % [ZombieMutator.SPIDER_LIMB_COUNT, expected_y, expected_pitch, limbs, body_y, pitch])
		return
	print("PASS: Aranha rebaixada (y=%.2f) e inclinada, com %d patas extras." % [body_y, limbs])


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
