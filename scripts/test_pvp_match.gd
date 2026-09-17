extends RefCounted

## Regressoes do mata-mata por times: economia estilo CS (comeca com $800,
## $300 por abate, teto $16000), times equilibrados, compra so na fase de
## compra e rodadas de melhor de 3.
## Uso: PvpMatchTests.new().run(test_root)

const PVPMATCH_SCRIPT := preload("res://scripts/pvp_match.gd")
const WEAPON_SLOTS_SCRIPT := preload("res://scripts/weapon_slots.gd")
const A1 := "101:0"
const A2 := "102:0"
const B1 := "201:0"
const B2 := "202:0"


func run(test_root: Node) -> void:
	_test_teams_balanced_and_start_money(test_root)
	_test_teams_stay_even_on_sequential_joins(test_root)
	_test_kill_reward_and_deaths(test_root)
	_test_spend_never_goes_negative(test_root)
	_test_buy_only_during_buy_phase(test_root)
	_test_best_of_three_rounds(test_root)
	_test_round_by_time_and_money_cap(test_root)
	_test_prices_are_defined(test_root)
	_test_frozen_input_keeps_only_aim(test_root)
	_test_pvp_gives_huge_reserve_and_no_wear(test_root)
	_test_frozen_input_zeroes_every_action_key(test_root)
	_test_death_signal_connected_once(test_root)
	_test_round_reason_is_recorded(test_root)


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


## Entrando um a um (o caso real da sala), a diferenca entre times nunca passa
## de 1 — e ao sair alguem, o proximo entra no time que ficou menor.
func _test_teams_stay_even_on_sequential_joins(test_root: Node) -> void:
	print("Testando distribuicao uniforme na entrada...")
	var match_state := PVPMATCH_SCRIPT.new()
	for index in 9:
		match_state.register_player("%d:0" % (500 + index))
		var counts: Array = match_state.team_counts()
		if absi(int(counts[0]) - int(counts[1])) > 1:
			_fail(test_root, "Com %d jogadores os times ficaram %s (diferenca > 1)." % [index + 1, counts])
			return
	# Alguem do time 0 sai: o proximo entra no time 0 para reequilibrar.
	match_state.remove_player("500:0")
	match_state.register_player("900:0")
	var counts_after: Array = match_state.team_counts()
	if int(counts_after[1]) - int(counts_after[0]) > 1:
		_fail(test_root, "Depois de uma saida o proximo deveria entrar no time menor; times=%s." % [counts_after])
		return
	print("PASS: Times sempre equilibrados na entrada (%s)." % [counts_after])


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


## Freezetime: so olhar e o slot passam; movimento/tiro/itens ficam zerados.
func _test_frozen_input_keeps_only_aim(test_root: Node) -> void:
	print("Testando entrada congelada do tempo de compra...")
	var raw := {
		"slot": 1, "move": Vector2(1.0, 1.0), "aim": Vector2(0.5, -0.5),
		"jump": true, "sprint": true, "attack": true, "grenade": true, "reload": true,
	}
	var frozen: Dictionary = PVPMATCH_SCRIPT.frozen_input(raw)
	if frozen["move"] != Vector2.ZERO:
		_fail(test_root, "Movimento deveria ser zerado no freezetime; veio %s." % frozen["move"])
		return
	if frozen["aim"] != raw["aim"] or int(frozen["slot"]) != 1:
		_fail(test_root, "Olhar e slot deveriam passar; aim=%s slot=%s." % [frozen["aim"], frozen["slot"]])
		return
	for action in ["jump", "sprint", "attack", "grenade", "reload"]:
		if bool(frozen[action]):
			_fail(test_root, "%s deveria ficar falso no freezetime." % action)
			return
	if raw["move"] != Vector2(1.0, 1.0) or not bool(raw["attack"]):
		_fail(test_root, "A entrada original nao pode ser alterada; veio %s." % raw)
		return
	print("PASS: Freezetime deixa so olhar e slot.")


## O freezetime tem que zerar QUALQUER booleano do estado, inclusive uma acao
## nova: a lista fixa de antes usava `drop`/`cycle` (chaves do input) enquanto o
## GameConfig chama as acoes de `drop_weapon`/`cycle_weapon`, e uma acao nova
## entrava sem ser congelada.
func _test_frozen_input_zeroes_every_action_key(test_root: Node) -> void:
	print("Testando freezetime em qualquer chave booleana...")
	var raw := {
		"slot": 2, "move": Vector2(0.7, -0.2), "aim": Vector2(0.1, 0.4),
		"drop": true, "cycle": true, "swat": true, "buy": true,
		"acao_nova_de_amanha": true, "recarga_segundos": 1.5,
	}
	var frozen: Dictionary = PVPMATCH_SCRIPT.frozen_input(raw)
	for key in ["drop", "cycle", "swat", "buy", "acao_nova_de_amanha"]:
		if bool(frozen[key]):
			_fail(test_root, "Chave booleana '%s' deveria ficar falsa no freezetime." % key)
			return
	if frozen["move"] != Vector2.ZERO:
		_fail(test_root, "Movimento deveria ser zerado; veio %s." % frozen["move"])
		return
	if frozen["aim"] != raw["aim"] or int(frozen["slot"]) != 2 or frozen["recarga_segundos"] != 1.5:
		_fail(test_root, "Olhar/slot/valores nao booleanos devem passar; veio %s." % frozen)
		return
	if not bool(raw["drop"]) or raw["move"] != Vector2(0.7, -0.2):
		_fail(test_root, "A entrada original nao pode ser alterada; veio %s." % raw)
		return
	print("PASS: Freezetime zera toda chave booleana e preserva olhar/slot.")


## O log da rodada nova conta como a anterior fechou: por tempo, por eliminacao
## ou por queda geral (e quem levou). Sem isso so dava para ver o placar.
func _test_round_reason_is_recorded(test_root: Node) -> void:
	print("Testando motivo/vencedor da rodada...")
	var match_state := PVPMATCH_SCRIPT.new()
	match_state.register_player("1:0")
	match_state.register_player("2:0")
	if str(match_state.last_round_report()["motivo"]) != "":
		_fail(test_root, "Sem rodada fechada o motivo deveria ser vazio; veio %s." % match_state.last_round_report())
		return
	match_state.finish_round_by_time([1, 0])
	var report: Dictionary = match_state.last_round_report()
	if str(report["motivo"]) != "tempo" or int(report["vencedor"]) != 0:
		_fail(test_root, "Rodada por tempo deveria marcar motivo 'tempo' e vencedor 0; veio %s." % report)
		return
	match_state.tick(PVPMATCH_SCRIPT.BUY_SECONDS + 1.0)
	match_state.finish_round(-1, "eliminacao")
	report = match_state.last_round_report()
	if str(report["motivo"]) != "eliminacao" or int(report["vencedor"]) != -1:
		_fail(test_root, "Empate por eliminacao deveria marcar 'eliminacao' e -1; veio %s." % report)
		return
	print("PASS: motivo e vencedor da rodada registrados.")


## Regressao: o handler de morte era conectado de novo a cada registro porque a
## checagem usava o Callable SEM bind contra o Callable COM bind conectado
## (is_connected compara os argumentos atados) -> cada morte contava em dobro.
func _test_death_signal_connected_once(test_root: Node) -> void:
	print("Testando conexao unica do sinal de morte...")
	var player := FakePvpPlayer.new()
	var host := FakePvpHost.new()
	if not PvpDeathWiring.connect_once(player, host):
		_fail(test_root, "A primeira conexao deveria acontecer; veio false.")
		player.free()
		return
	if PvpDeathWiring.connect_once(player, host):
		_fail(test_root, "A segunda conexao deveria ser recusada; veio true.")
		player.free()
		return
	var connections: Array = player.pvp_died.get_connections()
	if connections.size() != 1:
		_fail(test_root, "pvp_died deveria ter 1 conexao; tem %d." % connections.size())
		player.free()
		return
	player.pvp_died.emit(player)
	if host.deaths != 1:
		_fail(test_root, "Uma morte deveria chamar o handler 1 vez; chamou %d." % host.deaths)
		player.free()
		return
	player.free()
	print("PASS: sinal de morte conectado uma unica vez.")


## Mata-mata: arma comprada vem com reserva multiplicada e o tiro NAO desgasta.
## Tambem garante que o survival continua desgastando normalmente.
func _test_pvp_gives_huge_reserve_and_no_wear(test_root: Node) -> void:
	print("Testando reserva grande e sem durabilidade no PVP...")
	var kind := WeaponStats.Kind.AK47
	var stats := WeaponStats.stats_for(kind)
	var base_reserve := int(stats["grant_reserve"])
	var pvp_before: bool = NetworkSession.pvp_mode
	NetworkSession.pvp_mode = true
	var pvp_slots: WeaponSlots = WEAPON_SLOTS_SCRIPT.new()
	pvp_slots.grant(kind)
	var pvp_state: Dictionary = pvp_slots.state_of(kind)
	var expected_reserve: int = mini(base_reserve * WEAPON_SLOTS_SCRIPT.PVP_RESERVE_MULTIPLIER, WEAPON_SLOTS_SCRIPT.PVP_RESERVE_CAP)
	if int(pvp_state["reserve"]) != expected_reserve or expected_reserve <= base_reserve:
		_fail(test_root, "Reserva do PVP deveria ser %d (base %d); veio %s." % [expected_reserve, base_reserve, pvp_state["reserve"]])
		NetworkSession.pvp_mode = pvp_before
		return
	var durability_before := int(pvp_state["durability"])
	for shot in 200:
		pvp_slots.wear(kind)
	if int(pvp_slots.state_of(kind)["durability"]) != durability_before:
		_fail(test_root, "No PVP a durabilidade nao pode cair; foi de %d para %s." % [durability_before, pvp_slots.state_of(kind)["durability"]])
		NetworkSession.pvp_mode = pvp_before
		return
	if pvp_slots.is_degraded(kind):
		_fail(test_root, "Arma do PVP nunca fica degradada.")
		NetworkSession.pvp_mode = pvp_before
		return
	# Survival continua igual: desgasta e degrada.
	NetworkSession.pvp_mode = false
	var survival_slots: WeaponSlots = WEAPON_SLOTS_SCRIPT.new()
	survival_slots.grant(kind)
	if int(survival_slots.state_of(kind)["reserve"]) != base_reserve:
		_fail(test_root, "No survival a reserva deveria continuar %d; veio %s." % [base_reserve, survival_slots.state_of(kind)["reserve"]])
		NetworkSession.pvp_mode = pvp_before
		return
	survival_slots.wear(kind)
	if int(survival_slots.state_of(kind)["durability"]) != durability_before - 1:
		_fail(test_root, "No survival o tiro deveria desgastar 1 ponto; veio %s." % survival_slots.state_of(kind)["durability"])
		NetworkSession.pvp_mode = pvp_before
		return
	NetworkSession.pvp_mode = pvp_before
	print("PASS: PVP com reserva %d (base %d) e sem desgaste." % [expected_reserve, base_reserve])


## Falsos do teste de conexao do sinal: o jogador so precisa do sinal, o host do
## metodo com a assinatura de `_on_pvp_died`.
class FakePvpPlayer:
	extends Node
	signal pvp_died(killer: Node)


class FakePvpHost:
	extends RefCounted
	var deaths := 0
	func _on_pvp_died(_killer: Node, _victim: Node) -> void:
		deaths += 1


func _fail(test_root: Node, message: String) -> void:
	push_error("FALHA: " + message)
	test_root.set_meta("unit_test_failed", true)
