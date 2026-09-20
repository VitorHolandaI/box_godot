extends RefCounted

## Regressoes da ancora da arma: na postura de tiro a arma fica na ponta do
## braco direito (a mao), nao num offset fixo que flutuava longe dela.
## Uso: WeaponAnchorTests.new().run(test_root)

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const PLAYER_ANIMATOR: GDScript = preload("res://scripts/player_animator.gd")
const PISTOL := 1
const FRAMES := 40
## Folga: a tabela WEAPON_HOLD_TUNE desloca a arma de propósito perto da mao.
const MAX_DISTANCE := 0.4


func run(test_root: Node) -> void:
	_test_weapon_follows_the_hand(test_root)


func _test_weapon_follows_the_hand(test_root: Node) -> void:
	print("Testando a arma presa na mao na postura de tiro...")
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.name = "WeaponAnchorTest"
	player.set("reads_local_input", false)
	player.set("simulation_enabled", false)
	player.set("is_local_controller", false)
	player.position = Vector3(1400.0, 1.0, 1400.0)
	test_root.add_child(player)
	player.set("current_weapon", PISTOL)
	player.set("pistol_stance_time", 5.0)
	for _frame in FRAMES:
		PLAYER_ANIMATOR.animate_pose(player, 1.0 / 60.0, false)
	var right_arm := player.get_node("Model/RightArm") as Node3D
	var weapon_holder := player.get_node("Model/Weapons") as Node3D
	var hand := right_arm.global_position + right_arm.global_transform.basis * PLAYER_ANIMATOR.HAND_ANCHOR_LOCAL
	var distance := weapon_holder.global_position.distance_to(hand)
	player.free()
	if distance > MAX_DISTANCE:
		_fail(test_root, "Arma deveria ficar na mao (distancia <= %.2f); veio %.2f m." % [MAX_DISTANCE, distance])
		return
	print("PASS: Arma fica na mao (distancia %.2f m)." % [distance])


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
