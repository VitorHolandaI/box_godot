extends RefCounted

## Regressoes do mata-mata PVP: economia estilo CS (comeca com $800, $300 por
## abate, teto de $16000), respawn, fim por abates ou por tempo e as regras de
## compra (dinheiro/tempo de compra).
## Uso: PvpMatchTests.new().run(test_root)

const PVPMATCH_SCRIPT := preload("res://scripts/pvp_match.gd")
const ALFA := "101:0"
const BRAVO := "202:0"


func run(test_root: Node) -> void:
	_test_start_money_and_kill_reward(test_root)
	_test_spend_never_goes_negative(test_root)
	_test_buy_rules(test_root)
	_test_win_by_kills_and_by_time(test_root)
	_test_money_is_capped(test_root)


func _test_start_money_and_kill_reward(test_root: Node) -> void:
	print("Testando dinheiro inicial e premio por abate...")
	var match_state = PVPMATCH_SCRIPT.new()
	match_state.register_player(ALFA)
	match_state.register_player(BRAVO)
	var start_money: int = match_state.money_of(ALFA)
	match_state.register_kill(ALFA, BRAVO)
	var after_kill: int = match_state.money_of(ALFA)
	if start_money != PVPMATCH_SCRIPT.MONEY_START:
		_fail(test_root, "Dinheiro inicial deveria ser %d; veio %d." % [PVPMATCH_SCRIPT.MONEY_START, start_money])
		return
	if after_kill != start_money + PVPMATCH_SCRIPT.MONEY_PER_KILL:
		_fail(test_root, "Abate deveria dar +%d; veio %d (antes %d)." % [PVPMATCH_SCRIPT.MONEY_PER_KILL, after_kill, start_money])
		return
	if match_state.kills_of(ALFA) != 1 or match_state.deaths_of(BRAVO) != 1:
		_fail(test_root, "Placar do abate errado: kills=%d mortes=%d." % [match_state.kills_of(ALFA), match_state.deaths_of(BRAVO)])
		return
	if match_state.money_of(BRAVO) != PVPMATCH_SCRIPT.MONEY_START:
		_fail(test_root, "Morrer nao pode dar dinheiro; vitima ficou com %d." % match_state.money_of(BRAVO))
		return
	print("PASS: Economia inicial e premio por abate.")


func _test_spend_never_goes_negative(test_root: Node) -> void:
	print("Testando gasto sem saldo...")
	var match_state = PVPMATCH_SCRIPT.new()
	match_state.register_player(ALFA)
	var spent_ok: bool = match_state.spend(ALFA, PVPMATCH_SCRIPT.MONEY_START)
	var spent_too_much: bool = match_state.spend(ALFA, 1)
	if not spent_ok or spent_too_much or match_state.money_of(ALFA) != 0:
		_fail(test_root, "Gastar tudo deveria zerar e gastar sem saldo deveria falhar; ok=%s sem-saldo=%s dinheiro=%d." % [spent_ok, spent_too_much, match_state.money_of(ALFA)])
		return
	print("PASS: Gasto nao deixa saldo negativo.")


func _test_buy_rules(test_root: Node) -> void:
	print("Testando regras de compra...")
	var match_state = PVPMATCH_SCRIPT.new()
	match_state.register_player(ALFA)
	var caro := match_state.buy_rejection(ALFA, PVPMATCH_SCRIPT.MONEY_START + 1, PVPMATCH_SCRIPT.BUY_SECONDS)
	var na_janela := match_state.buy_rejection(ALFA, PVPMATCH_SCRIPT.MONEY_START, PVPMATCH_SCRIPT.BUY_SECONDS)
	var fora_da_janela := match_state.buy_rejection(ALFA, 100, 0.0)
	var fora_da_partida := match_state.buy_rejection("999:0", 100, PVPMATCH_SCRIPT.BUY_SECONDS)
	var sem_preco := match_state.buy_rejection(ALFA, 0, PVPMATCH_SCRIPT.BUY_SECONDS)
	if caro.is_empty() or not na_janela.is_empty() or fora_da_janela.is_empty() or fora_da_partida.is_empty() or sem_preco.is_empty():
		_fail(test_root, "Compra: caro recusa=%s, dentro da janela=%s, fora da janela=%s, fora da partida=%s, sem preco=%s." % [caro, na_janela, fora_da_janela, fora_da_partida, sem_preco])
		return
	print("PASS: Regras de compra validadas.")


func _test_win_by_kills_and_by_time(test_root: Node) -> void:
	print("Testando fim de partida por abates e por tempo...")
	var match_state = PVPMATCH_SCRIPT.new()
	match_state.register_player(ALFA)
	match_state.register_player(BRAVO)
	var ended := false
	for _kill in PVPMATCH_SCRIPT.KILLS_TO_WIN:
		ended = match_state.register_kill(ALFA, BRAVO)
	if not ended or match_state.winner_key() != ALFA:
		_fail(test_root, "%d abates deveriam acabar a partida com %s vencendo; fim=%s vencedor=%s." % [PVPMATCH_SCRIPT.KILLS_TO_WIN, ALFA, ended, match_state.winner_key()])
		return
	var timed = PVPMATCH_SCRIPT.new()
	timed.register_player(ALFA)
	timed.tick(PVPMATCH_SCRIPT.MATCH_SECONDS + 1.0)
	if not timed.is_over() or timed.time_left() > 0.0:
		_fail(test_root, "Relogio deveria encerrar a partida em %s s; over=%s faltam=%s." % [PVPMATCH_SCRIPT.MATCH_SECONDS, timed.is_over(), timed.time_left()])
		return
	# Sem abates de ninguem, o fim por tempo nao tem vencedor (empate).
	if not timed.winner_key().is_empty():
		_fail(test_root, "Partida sem abates nao pode ter vencedor; veio '%s'." % timed.winner_key())
		return
	print("PASS: Fim por abates e por tempo.")


func _test_money_is_capped(test_root: Node) -> void:
	print("Testando teto de dinheiro...")
	var match_state = PVPMATCH_SCRIPT.new()
	match_state.register_player(ALFA)
	match_state.add_money(ALFA, PVPMATCH_SCRIPT.MONEY_MAX * 2)
	if match_state.money_of(ALFA) != PVPMATCH_SCRIPT.MONEY_MAX:
		_fail(test_root, "Dinheiro deveria parar em %d; veio %d." % [PVPMATCH_SCRIPT.MONEY_MAX, match_state.money_of(ALFA)])
		return
	print("PASS: Teto de dinheiro respeitado.")


func _fail(test_root: Node, message: String) -> void:
	push_error("FALHA: " + message)
	test_root.set_meta("unit_test_failed", true)
