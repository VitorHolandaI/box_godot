## Testes do desvio de obstaculo dos bots de PVP (funcoes puras).
## Uso: godot --headless --path . -- --unit-test --test-group=pvp_navigation
const PvpNavigationScript := preload("res://scripts/pvp_navigation.gd")

var failures := 0


func run(test_root: Node) -> void:
	print("Testando desvio de obstaculo dos bots de PVP...")
	_test_keeps_desired_when_free(test_root)
	_test_turns_to_first_free_side(test_root)
	_test_prefers_small_deviation(test_root)
	_test_falls_back_to_most_open_direction(test_root)
	_test_empty_desired_is_zero(test_root)
	_test_side_step_alternates_sides(test_root)
	if failures > 0:
		test_root.get_tree().quit(1)
	else:
		print("UNIT_TEST_PASS: grupo pvp_navigation")


## Tudo livre: mantem a direcao desejada.
func _test_keeps_desired_when_free(test_root: Node) -> void:
	var free_probes: Array = [2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0]
	var result: Vector2 = PvpNavigationScript.choose_direction(Vector2.RIGHT, free_probes)
	if not result.is_equal_approx(Vector2.RIGHT):
		_fail(test_root, "Com tudo livre deveria manter a direcao; veio %s." % result)
		return
	print("PASS: mantem a direcao quando esta livre.")


## Reto bloqueado e o desvio de 25 graus livre: vira 25 graus (nao 55/90).
func _test_turns_to_first_free_side(test_root: Node) -> void:
	var probes: Array = [0.4, 2.0, 0.3, 2.0, 0.3, 0.3, 0.3]
	var result: Vector2 = PvpNavigationScript.choose_direction(Vector2.RIGHT, probes)
	var expected := Vector2.RIGHT.rotated(deg_to_rad(25.0))
	if not result.is_equal_approx(expected):
		_fail(test_root, "Deveria virar 25 graus; veio %s (esperado %s)." % [result, expected])
		return
	print("PASS: vira para o desvio pequeno livre.")


## Com o reto e o +25 bloqueados, escolhe o -25 (o outro lado pequeno) antes dos
## desvios grandes.
func _test_prefers_small_deviation(test_root: Node) -> void:
	var probes: Array = [0.2, 0.2, 1.9, 2.0, 0.2, 0.2, 0.2]
	var result: Vector2 = PvpNavigationScript.choose_direction(Vector2.RIGHT, probes)
	var expected := Vector2.RIGHT.rotated(deg_to_rad(-25.0))
	if not result.is_equal_approx(expected):
		_fail(test_root, "Deveria virar -25 graus; veio %s (esperado %s)." % [result, expected])
		return
	print("PASS: prefere desvio pequeno do outro lado.")


## Tudo bloqueado: escolhe a direcao com mais espaco (nao trava parado).
func _test_falls_back_to_most_open_direction(test_root: Node) -> void:
	var probes: Array = [0.2, 0.2, 0.2, 0.4, 0.2, 1.5, 0.3]
	var result: Vector2 = PvpNavigationScript.choose_direction(Vector2.RIGHT, probes)
	var expected := Vector2.RIGHT.rotated(deg_to_rad(90.0))
	if not result.is_equal_approx(expected):
		_fail(test_root, "Com tudo bloqueado deveria ir para o lado com mais espaco (90); veio %s." % result)
		return
	print("PASS: com tudo bloqueado vai para o lado mais aberto.")


## Direcao desejada nula nao pode virar giro de 90 graus.
func _test_empty_desired_is_zero(test_root: Node) -> void:
	var probes: Array = [2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0]
	var result: Vector2 = PvpNavigationScript.choose_direction(Vector2.ZERO, probes)
	if result != Vector2.ZERO:
		_fail(test_root, "Desejado nulo deveria devolver ZERO; veio %s." % result)
		return
	print("PASS: desejado nulo devolve ZERO.")


## Saida de prego sai de lado e alterna o lado por vaga (bots vizinhos nao se
## amontoam no mesmo canto).
func _test_side_step_alternates_sides(test_root: Node) -> void:
	var first: Vector2 = PvpNavigationScript.side_step(Vector2.RIGHT, 0)
	var second: Vector2 = PvpNavigationScript.side_step(Vector2.RIGHT, 1)
	if not first.is_equal_approx(Vector2.DOWN) or not second.is_equal_approx(Vector2.UP):
		_fail(test_root, "Lados deveriam alternar (DOWN, UP); veio %s e %s." % [first, second])
		return
	if PvpNavigationScript.side_step(Vector2.ZERO, 0) != Vector2.ZERO:
		_fail(test_root, "Side step de direcao nula deveria ser ZERO.")
		return
	print("PASS: saida de prego alterna os lados.")


func _fail(test_root: Node, message: String) -> void:
	failures += 1
	print("FALHA: %s" % message)
	test_root.get_tree().quit(1)
