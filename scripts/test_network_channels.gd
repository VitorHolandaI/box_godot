extends RefCounted

## Regressoes do plano de canais do ENet: sem eles tudo ia no canal 0 e um
## pacote confiavel reenviado segurava os snapshots atras dele (a sonda de lag
## mediu 128 ms de media e 1,6 s no pior na VPS, com 10 Hz esperados).
## O teste de ponta a ponta dos canais e o smoke dedicado
## (`scripts/test_dedicated.sh`): o bot so passa se receber snapshot de jogador
## (canal 2), snapshot de zumbi (canal 1), enviar input (canal 3) e ver a bala
## (canal 4) — cada fluxo em um canal diferente.
## Uso: NetworkChannelsTests.new().run(test_root)

const CHANNELS_SCRIPT := preload("res://scripts/network_channels.gd")
const NETWORK_SESSION_SCRIPT := preload("res://scripts/network_session.gd")


func run(test_root: Node) -> void:
	_test_plan_is_consistent(test_root)
	_test_hot_streams_have_own_channels(test_root)
	_test_count_covers_every_channel(test_root)


func _test_plan_is_consistent(test_root: Node) -> void:
	print("Testando plano de canais do ENet...")
	var error: String = CHANNELS_SCRIPT.validate()
	if not error.is_empty():
		_fail(test_root, "Plano de canais invalido: %s" % error)
		return
	if CHANNELS_SCRIPT.COUNT < 2:
		_fail(test_root, "Plano de canais deveria abrir mais de um canal; veio COUNT=%d." % CHANNELS_SCRIPT.COUNT)
		return
	print("PASS: Plano de canais consistente (%d canais)." % CHANNELS_SCRIPT.COUNT)


func _test_hot_streams_have_own_channels(test_root: Node) -> void:
	print("Testando canais separados para snapshot, input e efeitos...")
	var streams := {
		"confiavel": CHANNELS_SCRIPT.RELIABLE,
		"snapshot_zumbis": CHANNELS_SCRIPT.SNAPSHOT_ZOMBIES,
		"snapshot_jogadores": CHANNELS_SCRIPT.SNAPSHOT_PLAYERS,
		"input": CHANNELS_SCRIPT.INPUT,
		"efeitos": CHANNELS_SCRIPT.EFFECTS,
	}
	for name_value in streams.keys():
		var channel: int = streams[name_value]
		if channel < 0 or channel >= CHANNELS_SCRIPT.COUNT:
			_fail(test_root, "Canal de '%s' (%d) fora de COUNT=%d." % [name_value, channel, CHANNELS_SCRIPT.COUNT])
			return
	for name_value in streams.keys():
		var channel: int = streams[name_value]
		for other_value in streams.keys():
			if other_value == name_value:
				continue
			if int(streams[other_value]) == channel:
				_fail(test_root, "Canais de '%s' e '%s' sao o mesmo (%d); um fluxo seguraria o outro." % [name_value, other_value, channel])
				return
	print("PASS: Fluxos quentes em canais separados.")


func _test_count_covers_every_channel(test_root: Node) -> void:
	print("Testando que COUNT cobre todos os canais e NAMES bate com o plano...")
	var highest := CHANNELS_SCRIPT.RELIABLE
	for channel in [CHANNELS_SCRIPT.SNAPSHOT_ZOMBIES, CHANNELS_SCRIPT.SNAPSHOT_PLAYERS, CHANNELS_SCRIPT.INPUT, CHANNELS_SCRIPT.EFFECTS]:
		highest = maxi(highest, int(channel))
	if CHANNELS_SCRIPT.COUNT != highest + 1:
		_fail(test_root, "COUNT deveria ser %d (maior canal + 1); veio %d. Sobra canal aberto ou falta o ultimo." % [highest + 1, CHANNELS_SCRIPT.COUNT])
		return
	if CHANNELS_SCRIPT.NAMES.size() != CHANNELS_SCRIPT.COUNT:
		_fail(test_root, "NAMES tem %d nomes para %d canais." % [CHANNELS_SCRIPT.NAMES.size(), CHANNELS_SCRIPT.COUNT])
		return
	print("PASS: COUNT e NAMES cobrem o plano de canais.")


func _fail(test_root: Node, message: String) -> void:
	push_error("FALHA: " + message)
	test_root.set_meta("unit_test_failed", true)
