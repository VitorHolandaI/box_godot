extends RefCounted

## Regressoes do mata-mata por times: economia estilo CS (comeca com $800,
## $300 por abate, teto $16000), times equilibrados, compra so na fase de
## compra e rodadas de melhor de 3.
## Uso: PvpMatchTests.new().run(test_root)

const PVPMATCH_SCRIPT := preload("res://scripts/pvp_match.gd")
const A1 := "101:0"
const A2 := "102:0"
const B1 := "201:0"
const B2 := "202:0"


func run(test_root: Node) -> void:
	_test_teams_balanced_and_start_money(test_root)
	_test_kill_reward_and_deaths(test_root)
	_test_spend_never_goes_negative(test_root)
	_test_buy_only_during_buy_phase(test_root)
	_test_best_of_three_rounds(test_root)
	_test_round_by_time_and_money_cap(test_root)
	_test_prices_are_defined(test_root)


func _match_with_four() -> PvpMatch:
	var match_state := PVPMATCH_SCRIPT.new()
	for key in [A1, B1, A2, B2]:
		match_state.register_player(String(key))
	return match_state


func _test_teams_balanced_and_start_money(test_root: Node) -> void:
	print("Testando times equilibrados e dinheiro inicial...")
	var match_state := _match_with_four()
	var counts: Array[int] = [0, 0]
	for key in [A1, A2, B1, B2]:
		var team: int = match_state.team_of(String(key))
		if team < 0 or team >= PVPMATCH_SCRIPT.TEAM_COUNT:
			_fail(test_root, "Time invalido (%d) para %s." % [team, key])
			return
		counts[team] += 1
	var money: int = match_state.money_of(A1)
	if counts[0] != 2 or counts[1] != 2:
		_fail(test_root, "Times deveriam ficar 2x2; veio %s." % [counts])
		return
	if money != PVPMATCH_SCRIPT.MONEY_START:
		_fail(test_root, "Dinheiro inicial deveria ser %d; veio %d." % [PVPMATCH_SCRIPT.MONEY_START, money])
		return
	print("PASS: Times 2x2 e $%d inicial." % money)


func _test_kill_reward_and_deaths(test_root: Node) -> void:
	print("Testando premio por abate e contagem de mortes...")
	var match_state := _match_with_four()
	match_state.register_kill(A1, B1)
	var money: int = match_state.money_of(A1)
	if match_state.kills_of(A1) != 1 or match_state.deaths_of(B1) != 1:
		_fail(test_root, "Placar do abate errado: kills=%d mortes=%d." % [match_state.kills_of(A1), match_state.deaths_of(B1)])
		return
	if money != PVPMATCH_SCRIPT.MONEY_START + PVPMATCH_SCRIPT.MONEY_PER_KILL:
		_fail(test_root, "Abate deveria dar +%d; veio %d." % [PVPMATCH_SCRIPT.MONEY_PER_KILL, money])
		return
	if match_state.money_of(B1) != PVPMATCH_SCRIPT.MONEY_START:
		_fail(test_root, "Morrer nao pode dar dinheiro; vitima ficou com %d." % match_state.money_of(B1))
		return
	# Abate em si mesmo nao credita ninguem.
	match_state.register_kill(A2, A2)
	if match_state.kills_of(A2) != 0:
		_fail(test_root, "Suicidio nao pode contar abate; veio %d." % match_state.kills_of(A2))
		return
	print("PASS: Premio por abate e mortes.")


func _test_spend_never_goes_negative(test_root: Node) -> void:
	print("Testando gasto sem saldo...")
	var match_state := _match_with_four()
	var spent_ok: bool = match_state.spend(A1, PVPMATCH_SCRIPT.MONEY_START)
	var spent_too_much: bool = match_state.spend(A1, 1)
	if not spent_ok or spent_too_much or match_state.money_of(A1) != 0:
		_fail(test_root, "Gastar tudo deveria zerar e gastar sem saldo falhar; ok=%s sem-saldo=%s dinheiro=%d." % [spent_ok, spent_too_much, match_state.money_of(A1)])
		return
	print("PASS: Gasto nao deixa saldo negativo.")


func _test_buy_only_during_buy_phase(test_root: Node) -> void:
	print("Testando compra so na fase de compra...")
	var match_state := _match_with_four()
	var na_compra := match_state.buy_rejection(A1, PVPMATCH_SCRIPT.MONEY_START)
	var caro := match_state.buy_rejection(A1, PVPMATCH_SCRIPT.MONEY_START + 1)
	var sem_preco := match_state.buy_rejection(A1, 0)
	# Avanca a compra: 15 s de fase de compra viram combate.
	match_state.tick(PVPMATCH_SCRIPT.BUY_SECONDS + 1.0)
	var no_combate := match_state.buy_rejection(A1, 100)
	if not na_compra.is_empty() or caro.is_empty() or sem_preco.is_empty() or no_combate.is_empty():
		_fail(test_root, "Compra: na fase de compra=%s, caro=%s, sem preco=%s, no combate=%s." % [na_compra, caro, sem_preco, no_combate])
		return
	if match_state.phase != PVPMATCH_SCRIPT.Phase.LIVE:
		_fail(test_root, "Depois de %s s a fase deveria ser combate; veio %d." % [PVPMATCH_SCRIPT.BUY_SECONDS, match_state.phase])
		return
	print("PASS: Compra liberada so na fase de compra.")


func _test_best_of_three_rounds(test_root: Node) -> void:
	print("Testando melhor de 3 rodadas...")
	var match_state := _match_with_four()
	match_state.tick(PVPMATCH_SCRIPT.BUY_SECONDS + 1.0)  # entra no combate da rodada 1
	match_state.finish_round(match_state.team_of(A1))
	if match_state.phase != PVPMATCH_SCRIPT.Phase.ROUND_END:
		_fail(test_root, "Fim de rodada deveria entrar em ROUND_END; veio %d." % match_state.phase)
		return
	# Passa o fim de rodada: comeca a rodada 2 com compra aberta de novo.
	match_state.tick(PVPMATCH_SCRIPT.ROUND_END_SECONDS + 0.1)
	var round_two := match_state.round_index == 2 and match_state.phase == PVPMATCH_SCRIPT.Phase.BUY
	match_state.tick(PVPMATCH_SCRIPT.BUY_SECONDS + 1.0)
	match_state.finish_round(match_state.team_of(B1))
	if not round_two:
		_fail(test_root, "Depois do fim de rodada deveria comecar a rodada 2 em compra; rodada=%d fase=%d." % [match_state.round_index, match_state.phase])
		return
	if match_state.team_score_text() != "Time A 1 x 1 Time B":
		_fail(test_root, "Placar de times deveria estar 1x1; veio '%s'." % match_state.team_score_text())
		return
	match_state.tick(PVPMATCH_SCRIPT.ROUND_END_SECONDS + 0.1)
	match_state.tick(PVPMATCH_SCRIPT.BUY_SECONDS + 1.0)
	match_state.finish_round(match_state.team_of(A1))
	# 2 vitorias de 3: a partida fecha sem precisar da terceira rodada decidida.
	match_state.tick(PVPMATCH_SCRIPT.ROUND_END_SECONDS + 0.1)
	if not match_state.is_over() or match_state.match_winner() != 0:
		_fail(test_root, "Com 2 vitorias o time A deveria fechar a partida; over=%s vencedor=%d placar=%s." % [match_state.is_over(), match_state.match_winner(), match_state.team_score_text()])
		return
	print("PASS: Melhor de 3 rodadas (2 vitorias fecha).")


func _test_round_by_time_and_money_cap(test_root: Node) -> void:
	print("Testando rodada por tempo e teto de dinheiro...")
	var match_state := _match_with_four()
	match_state.tick(PVPMATCH_SCRIPT.BUY_SECONDS + 1.0)
	# 2 vivos no time A contra 1 no B: A leva a rodada pelo tempo.
	match_state.finish_round_by_time([2, 1])
	var team_a_win: bool = match_state.round_wins[0] == 1
	var empate := PVPMATCH_SCRIPT.new()
	empate.register_player(A1)
	empate.finish_round_by_time([1, 1])
	# Empate nao soma vitoria para ninguem.
	var empate_sem_vitoria: bool = empate.round_wins[0] == 0 and empate.round_wins[1] == 0
	match_state.add_money(A1, PVPMATCH_SCRIPT.MONEY_MAX * 2)
	var capped: bool = match_state.money_of(A1) == PVPMATCH_SCRIPT.MONEY_MAX
	if not team_a_win or not empate_sem_vitoria or not capped:
		_fail(test_root, "Rodada por tempo=%s, empate sem vitoria=%s, teto de dinheiro=%s (dinheiro=%d)." % [team_a_win, empate_sem_vitoria, capped, match_state.money_of(A1)])
		return
	print("PASS: Rodada por tempo, empate e teto de dinheiro.")


func _test_prices_are_defined(test_root: Node) -> void:
	print("Testando precos das armas compraveis...")
	var kinds: Array[int] = WeaponStats.purchasable_kinds()
	var sem_preco: Array[int] = []
	for kind in kinds:
		if WeaponStats.price_for(kind) <= 0:
			sem_preco.append(kind)
	if kinds.is_empty() or not sem_preco.is_empty():
		_fail(test_root, "Toda arma compravel precisa de preco > 0; sem preco=%s (catalogo=%d)." % [sem_preco, kinds.size()])
		return
	var caras: Array[int] = []
	for kind in kinds:
		if not WeaponStats.is_crate_weapon(kind):
			caras.append(kind)
	if not caras.is_empty():
		_fail(test_root, "Preco definido para arma que nao e de crate: %s." % [caras])
		return
	print("PASS: %d armas compraveis com preco." % kinds.size())


func _fail(test_root: Node, message: String) -> void:
	push_error("FALHA: " + message)
	test_root.set_meta("unit_test_failed", true)
