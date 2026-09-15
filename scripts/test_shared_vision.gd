extends RefCounted

## Regressoes da visao compartilhada: zumbi visto por um aliado aparece para
## todos; parede (linha bloqueada) e ninguem olhando mantem oculto.
## Uso: SharedVisionTests.new().run(test_root)

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")
const SHARED_VISION_SCRIPT := preload("res://scripts/shared_vision.gd")


func run(test_root: Node) -> void:
	_test_ally_reveals_zombie(test_root)


func _test_ally_reveals_zombie(test_root: Node) -> void:
	print("Testando zumbi visto pelo aliado aparecendo para todos...")
	var origin := Vector3(930.0, 1.0, -930.0)
	# Eu olho para -z; o zumbi esta 12 m atras de mim (+z), fora do meu cone.
	var me := _add_player(test_root, origin, 0.0)
	var zombie := ZOMBIE_SCENE.instantiate() as Node3D
	zombie.name = "SharedVisionTarget"
	zombie.position = origin + Vector3(0.0, 0.0, 12.0)
	test_root.add_child(zombie)
	var clear := func(_player: Node, _target: Node) -> bool: return true
	var blocked := func(_player: Node, _target: Node) -> bool: return false
	var alone: Array[CharacterBody3D] = [me]
	var alone_sees: bool = SHARED_VISION_SCRIPT.is_seen_by_any(alone, zombie, false, true, clear)
	# Aliado a 6 m do zumbi olhando para ele (+z = rotacao PI).
	var ally := _add_player(test_root, origin + Vector3(0.0, 0.0, 6.0), PI)
	var together: Array[CharacterBody3D] = [me, ally]
	var shared_sees: bool = SHARED_VISION_SCRIPT.is_seen_by_any(together, zombie, false, true, clear)
	var wall_blocks: bool = SHARED_VISION_SCRIPT.is_seen_by_any(together, zombie, false, true, blocked)
	me.free()
	ally.free()
	zombie.free()
	if alone_sees or not shared_sees or wall_blocks:
		_fail(test_root, "Sozinho de costas nao ve; com aliado olhando ve; parede bloqueia; sozinho=%s aliado=%s parede=%s." % [alone_sees, shared_sees, wall_blocks])
		return
	print("PASS: Zumbi visto pelo aliado aparece para todos, parede continua bloqueando.")


func _add_player(test_root: Node, position: Vector3, facing: float) -> CharacterBody3D:
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.set("reads_local_input", false)
	player.set("simulation_enabled", false)
	player.set("is_local_controller", false)
	player.position = position
	player.rotation.y = facing
	test_root.add_child(player)
	return player


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
