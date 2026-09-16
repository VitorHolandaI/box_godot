extends RefCounted

## Regressoes da politica de sumico de cadaveres por distancia.
## Uso: CorpseCleanupTests.new().run(test_root)

const POLICY_SCRIPT := preload("res://scripts/corpse_cleanup_policy.gd")
const MAIN_SCRIPT := preload("res://scripts/main.gd")


func run(test_root: Node) -> void:
	_test_nearby_corpses_never_vanish(test_root)
	_test_hard_cap_removes_farthest_first(test_root)
	_test_register_corpse_skips_freed_oldest(test_root)


func _test_nearby_corpses_never_vanish(test_root: Node) -> void:
	print("Testando cadaveres perto do jogador permanecendo no chao...")
	var corpses: Array[Vector3] = []
	for index in 30:
		corpses.append(Vector3(float(index) * 0.5, 0.0, 2.0))
	corpses.append(Vector3(200.0, 0.0, 0.0))
	var players: Array[Vector3] = [Vector3.ZERO]
	var removals: Array[int] = POLICY_SCRIPT.pick_removals(corpses, players, 50.0, 60)
	if removals != [30]:
		_fail(test_root, "Com 30 corpos perto e 1 longe, so o distante (indice 30) deveria sumir; removidos=%s." % [removals])
		return
	var nobody: Array[Vector3] = []
	if not POLICY_SCRIPT.pick_removals(corpses, nobody, 50.0, 60).is_empty():
		_fail(test_root, "Sem jogadores nenhum corpo deveria sumir por distancia.")
		return
	print("PASS: Corpos proximos ficam; so os distantes somem.")


func _test_hard_cap_removes_farthest_first(test_root: Node) -> void:
	print("Testando teto de cadaveres removendo o mais distante primeiro...")
	var corpses: Array[Vector3] = [Vector3(1.0, 0.0, 0.0), Vector3(40.0, 0.0, 0.0), Vector3(10.0, 0.0, 0.0)]
	var players: Array[Vector3] = [Vector3.ZERO]
	var removals: Array[int] = POLICY_SCRIPT.pick_removals(corpses, players, 50.0, 2)
	if removals != [1]:
		_fail(test_root, "Acima do teto deveria sair o corpo mais distante (indice 1); removidos=%s." % [removals])
		return
	print("PASS: Teto de corpos preserva os mais proximos.")


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)


## Horda morrendo em massa: o corpo mais antigo da fila ja estava liberado e
## `var oldest: Node = corpses.pop_front()` dava SCRIPT ERROR (17 na VPS, 0004fbb).
func _test_register_corpse_skips_freed_oldest(test_root: Node) -> void:
	print("Testando fila de corpos com o mais antigo ja liberado...")
	var main_world: Node = MAIN_SCRIPT.new()
	var fresh: Array[Node] = []
	for index in main_world.MAX_CORPSES:
		var corpse := Node.new()
		main_world.corpses.append(corpse)
		fresh.append(corpse)
	fresh[0].free()
	var newest := Node.new()
	main_world.register_corpse(newest)
	var size: int = main_world.corpses.size()
	for index in range(1, fresh.size()):
		fresh[index].free()
	newest.free()
	main_world.free()
	if size != MAIN_SCRIPT.MAX_CORPSES:
		_fail(test_root, "Fila de corpos deveria voltar a %d sem erro ao descartar o liberado; veio %d." % [MAIN_SCRIPT.MAX_CORPSES, size])
		return
	print("PASS: Fila de corpos descarta o liberado sem erro.")
