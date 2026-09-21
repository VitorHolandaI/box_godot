extends RefCounted

## Regressoes do mata-mata por times (Team Deathmatch): placar continuo de
## abates, times equilibrados, fogo amigo punido, protecao de respawn e escolha
## livre de arma (sem economia e sem rodadas).
## Uso: TdmMatchTests.new().run(test_root)

const TDMMATCH_SCRIPT := preload("res://scripts/tdm_match.gd")
const WEAPON_SLOTS_SCRIPT := preload("res://scripts/weapon_slots.gd")
const PVP_DIRECTOR_SCRIPT := preload("res://scripts/pvp_server_director.gd")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const A1 := "101:0"
const A2 := "102:0"
const B1 := "201:0"
const B2 := "202:0"


func run(test_root: Node) -> void:
	_test_teams_balanced_without_money(test_root)
	_test_teams_stay_even_on_sequential_joins(test_root)
	_test_kill_scores_the_team_and_counts_death(test_root)
	_test_friendly_fire_subtracts_instead_of_scoring(test_root)
	_test_score_limit_ends_the_match(test_root)
	_test_time_limit_ends_with_the_bigger_score(test_root)
	_test_draw_when_scores_tie(test_root)
	_test_spawn_protection_blocks_damage(test_root)
	_test_friendly_fire_is_blocked_between_teammates(test_root)
	_test_protection_drops_when_the_protected_attacks(test_root)
	_test_only_two_team_colors(test_root)
	_test_every_weapon_is_choosable_for_free(test_root)
	_test_pvp_keeps_reserve_but_still_wears(test_root)
	_test_death_drops_the_held_weapon(test_root)
	_test_respawn_brings_the_chosen_weapon_back_whole(test_root)
	_test_route_leaves_the_base_before_the_next_corner(test_root)
	_test_route_has_no_long_straight_leg(test_root)
	_test_death_signal_connected_once(test_root)


func _match_with_four() -> TdmMatch:
	var match_state := TDMMATCH_SCRIPT.new()
	for key in [A1, B1, A2, B2]:
		match_state.register_player(String(key))
	return match_state


## Entrar na partida so define time: nao ha dinheiro nem fase de compra.
func _test_teams_balanced_without_money(test_root: Node) -> void:
	print("Testando times equilibrados no mata-mata...")
	var match_state := _match_with_four()
	var counts: Array[int] = [0, 0]
	for key in [A1, A2, B1, B2]:
		var team: int = match_state.team_of(String(key))
		if team < 0 or team >= TDMMATCH_SCRIPT.TEAM_COUNT:
			_fail(test_root, "Time invalido (%d) para %s." % [team, key])
			return
		counts[team] += 1
	if counts[0] != 2 or counts[1] != 2:
		_fail(test_root, "Times deveriam ficar 2x2; veio %s." % [counts])
		return
	if match_state.phase != TDMMATCH_SCRIPT.Phase.LIVE:
		_fail(test_root, "O mata-mata comeca jogando (sem fase de compra); veio fase %d." % match_state.phase)
		return
	if match_state.score_of_team(0) != 0 or match_state.score_of_team(1) != 0:
		_fail(test_root, "Placar deveria comecar 0x0; veio %s." % match_state.team_score_text())
		return
	print("PASS: Times 2x2 e placar 0x0 ja em jogo.")


## Entrando um a um (o caso real da sala), a diferenca entre times nunca passa
## de 1 — e ao sair alguem, o proximo entra no time que ficou menor.
func _test_teams_stay_even_on_sequential_joins(test_root: Node) -> void:
	print("Testando distribuicao uniforme na entrada...")
	var match_state := TDMMATCH_SCRIPT.new()
	for index in 9:
		match_state.register_player("%d:0" % (500 + index))
		var counts: Array = match_state.team_counts()
		if absi(int(counts[0]) - int(counts[1])) > 1:
			_fail(test_root, "Com %d jogadores os times ficaram %s (diferenca > 1)." % [index + 1, counts])
			return
	match_state.remove_player("500:0")
	match_state.register_player("900:0")
	var counts_after: Array = match_state.team_counts()
	if int(counts_after[1]) - int(counts_after[0]) > 1:
		_fail(test_root, "Depois de uma saida o proximo deveria entrar no time menor; times=%s." % [counts_after])
		return
	print("PASS: Times sempre equilibrados na entrada (%s)." % [counts_after])


func _test_kill_scores_the_team_and_counts_death(test_root: Node) -> void:
	print("Testando abate pontuando o time...")
	var match_state := _match_with_four()
	var killer_team := match_state.team_of(A1)
	var victim_key := B1 if match_state.team_of(B1) != killer_team else A2
	match_state.register_kill(A1, victim_key)
	if match_state.kills_of(A1) != 1 or match_state.deaths_of(victim_key) != 1:
		_fail(test_root, "Abate deveria dar 1 kill e 1 death; veio %d/%d." % [match_state.kills_of(A1), match_state.deaths_of(victim_key)])
		return
	if match_state.score_of_team(killer_team) != 1:
		_fail(test_root, "Placar do time do matador deveria ser 1; veio %d." % match_state.score_of_team(killer_team))
		return
	var enemy_team := 1 - killer_team
	if match_state.score_of_team(enemy_team) != 0:
		_fail(test_root, "O time da vitima nao pontua; veio %d." % match_state.score_of_team(enemy_team))
		return
	print("PASS: Abate pontua o time e conta a morte.")


## Matar companheiro (ou a si mesmo) TIRA um do placar, nunca soma. Sem isso o
## time podia farmar placar matando os proprios.
func _test_friendly_fire_subtracts_instead_of_scoring(test_root: Node) -> void:
	print("Testando punicao de fogo amigo no placar...")
	var match_state := _match_with_four()
	var team := match_state.team_of(A1)
	var mate := B1 if match_state.team_of(B1) == team else A2
	var enemy := A2 if match_state.team_of(A2) != team else B1
	match_state.register_kill(A1, enemy)
	match_state.register_kill(A1, mate)
	if match_state.score_of_team(team) != 0:
		_fail(test_root, "1 abate valido + 1 companheiro deveria zerar o placar; veio %d." % match_state.score_of_team(team))
		return
	if match_state.kills_of(A1) != 0:
		_fail(test_root, "O matador deveria perder o abate; veio %d." % match_state.kills_of(A1))
		return
	if match_state.deaths_of(mate) != 1:
		_fail(test_root, "A morte do companheiro conta como morte dele; veio %d." % match_state.deaths_of(mate))
		return
	# Nunca fica negativo: o placar para no 0.
	match_state.register_kill(A1, mate)
	if match_state.score_of_team(team) != 0 or match_state.kills_of(A1) != 0:
		_fail(test_root, "Placar e abates nunca ficam negativos; veio %d/%d." % [match_state.score_of_team(team), match_state.kills_of(A1)])
		return
	print("PASS: Fogo amigo tira do placar e nao fica negativo.")


func _test_score_limit_ends_the_match(test_root: Node) -> void:
	print("Testando fim por limite de abates...")
	var match_state := _match_with_four()
	var team := match_state.team_of(A1)
	var enemy := B1 if match_state.team_of(B1) != team else A2
	for kill in TDMMATCH_SCRIPT.SCORE_LIMIT:
		if match_state.is_over():
			_fail(test_root, "A partida acabou cedo, no abate %d de %d." % [kill, TDMMATCH_SCRIPT.SCORE_LIMIT])
			return
		match_state.register_kill(A1, enemy)
	if not match_state.is_over():
		_fail(test_root, "Com %d abates a partida deveria acabar; placar %s." % [TDMMATCH_SCRIPT.SCORE_LIMIT, match_state.team_score_text()])
		return
	if match_state.winner() != team:
		_fail(test_root, "Vencedor deveria ser o time %d; veio %d." % [team, match_state.winner()])
		return
	print("PASS: %d abates fecham a partida para o time vencedor." % TDMMATCH_SCRIPT.SCORE_LIMIT)


func _test_time_limit_ends_with_the_bigger_score(test_root: Node) -> void:
	print("Testando fim por tempo...")
	var match_state := _match_with_four()
	var team := match_state.team_of(A1)
	var enemy := B1 if match_state.team_of(B1) != team else A2
	match_state.register_kill(A1, enemy)
	match_state.tick(TDMMATCH_SCRIPT.MATCH_SECONDS - 1.0)
	if match_state.is_over():
		_fail(test_root, "Faltando 1 s a partida nao pode ter acabado.")
		return
	match_state.tick(2.0)
	if not match_state.is_over() or match_state.winner() != team:
		_fail(test_root, "No fim do tempo deveria vencer o time %d; veio fim=%s vencedor=%d." % [team, match_state.is_over(), match_state.winner()])
		return
	if match_state.time_left() != 0.0:
		_fail(test_root, "Relogio deveria parar no 0; veio %f." % match_state.time_left())
		return
	print("PASS: Tempo esgotado entrega a partida a quem tem mais abates.")


func _test_draw_when_scores_tie(test_root: Node) -> void:
	print("Testando empate no fim do tempo...")
	var match_state := _match_with_four()
	match_state.tick(TDMMATCH_SCRIPT.MATCH_SECONDS + 1.0)
	if not match_state.is_over() or match_state.winner() != -1:
		_fail(test_root, "0x0 no fim do tempo e empate (-1); veio %d." % match_state.winner())
		return
	print("PASS: Placar igual no fim do tempo e empate.")


## Quem acabou de renascer nao leva dano: e a "invulnerabilidade de base" que o
## respawn continuo exige (sem ela da para campear a saida da casa inimiga).
func _test_spawn_protection_blocks_damage(test_root: Node) -> void:
	print("Testando invulnerabilidade de respawn...")
	if not TDMMATCH_SCRIPT.blocks_damage(0, 1, TDMMATCH_SCRIPT.SPAWN_PROTECTION_SECONDS):
		_fail(test_root, "Vitima protegida nao pode levar dano de inimigo.")
		return
	if TDMMATCH_SCRIPT.blocks_damage(0, 1, 0.0):
		_fail(test_root, "Sem protecao, o dano de inimigo tem que passar.")
		return
	if TDMMATCH_SCRIPT.SPAWN_PROTECTION_SECONDS <= 0.0:
		_fail(test_root, "A protecao de respawn precisa durar mais que 0 s.")
		return
	print("PASS: Protecao de respawn segura o dano por %.1f s." % TDMMATCH_SCRIPT.SPAWN_PROTECTION_SECONDS)


func _test_friendly_fire_is_blocked_between_teammates(test_root: Node) -> void:
	print("Testando fogo amigo bloqueado...")
	if not TDMMATCH_SCRIPT.blocks_damage(1, 1, 0.0):
		_fail(test_root, "Companheiro de time nao pode machucar companheiro.")
		return
	if TDMMATCH_SCRIPT.blocks_damage(1, 0, 0.0):
		_fail(test_root, "Times diferentes tem que trocar dano.")
		return
	# Sem time (-1) nao e amigo de ninguem: zumbi/acido/queda seguem machucando.
	if TDMMATCH_SCRIPT.blocks_damage(-1, -1, 0.0):
		_fail(test_root, "Dano sem time (ambiente) nao pode ser tratado como fogo amigo.")
		return
	print("PASS: Fogo amigo bloqueado, inimigo e ambiente passam.")


func _test_protection_drops_when_the_protected_attacks(test_root: Node) -> void:
	print("Testando queda da protecao ao atirar...")
	if TDMMATCH_SCRIPT.protection_after_attack(TDMMATCH_SCRIPT.SPAWN_PROTECTION_SECONDS) != 0.0:
		_fail(test_root, "Atirar tem que cancelar a protecao (senao da para limpar a base de graca).")
		return
	print("PASS: O primeiro tiro cancela a invulnerabilidade.")


## Duas cores no mapa inteiro, uma por time: antes cada jogador saia de uma cor
## (indice de vaga) e nao dava para saber quem era inimigo.
func _test_only_two_team_colors(test_root: Node) -> void:
	print("Testando as duas cores de time...")
	if TDMMATCH_SCRIPT.TEAM_COLORS.size() != TDMMATCH_SCRIPT.TEAM_COUNT:
		_fail(test_root, "Deveria haver 1 cor por time (%d); veio %d." % [TDMMATCH_SCRIPT.TEAM_COUNT, TDMMATCH_SCRIPT.TEAM_COLORS.size()])
		return
	var blue: Color = TDMMATCH_SCRIPT.color_for_team(0)
	var red: Color = TDMMATCH_SCRIPT.color_for_team(1)
	if blue == red:
		_fail(test_root, "As cores dos dois times nao podem ser iguais; veio %s." % blue)
		return
	if blue.b <= blue.r or red.r <= red.b:
		_fail(test_root, "Time 0 deveria ser azul e time 1 vermelho; veio %s e %s." % [blue, red])
		return
	if TDMMATCH_SCRIPT.color_for_team(7) != blue or TDMMATCH_SCRIPT.color_for_team(-1) != blue:
		_fail(test_root, "Time fora da faixa deveria cair na cor do time 0.")
		return
	if TDMMATCH_SCRIPT.name_for_team(0) == TDMMATCH_SCRIPT.name_for_team(1):
		_fail(test_root, "Os times precisam de nomes diferentes no HUD.")
		return
	print("PASS: Duas cores (%s / %s), uma por time." % [TDMMATCH_SCRIPT.name_for_team(0), TDMMATCH_SCRIPT.name_for_team(1)])


## No mata-mata a arma e ESCOLHA, nao compra: todo o arsenal de crate esta
## disponivel de graca no menu de loadout.
func _test_every_weapon_is_choosable_for_free(test_root: Node) -> void:
	print("Testando arsenal livre do loadout...")
	var kinds := WeaponStats.loadout_kinds()
	if kinds.size() < 8:
		_fail(test_root, "O loadout deveria oferecer o arsenal inteiro; veio %d armas." % kinds.size())
		return
	for kind in kinds:
		if not WeaponStats.is_crate_weapon(int(kind)):
			_fail(test_root, "Arma %s do loadout nao e arma de crate." % kind)
			return
		if String(WeaponStats.stats_for(int(kind)).get("label", "")).is_empty():
			_fail(test_root, "Arma %s do loadout precisa de nome para o menu." % kind)
			return
	if kinds.size() != WeaponStats.STATS_BY_KIND.size():
		_fail(test_root, "O loadout deveria ter todas as %d armas de crate; veio %d." % [WeaponStats.STATS_BY_KIND.size(), kinds.size()])
		return
	print("PASS: %d armas escolhiveis de graca no loadout." % kinds.size())


## Mata-mata: a arma vem com reserva multiplicada (municao nao e o recurso
## escasso aqui), MAS desgasta igual ao survival. Escolher a arma de graca nao
## pode virar arma eterna: a durabilidade e o que faz a arma degradar (spread
## dobrado, chance de falha) e obriga a trocar ou pegar a do chao.
func _test_pvp_keeps_reserve_but_still_wears(test_root: Node) -> void:
	print("Testando reserva grande COM desgaste no mata-mata...")
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
	var max_durability := int(stats["max_durability"])
	if pvp_slots.wear(kind) != max_durability - 1:
		_fail(test_root, "No mata-mata o tiro TEM que desgastar 1 ponto; veio %s de %d." % [pvp_slots.state_of(kind)["durability"], max_durability])
		NetworkSession.pvp_mode = pvp_before
		return
	# Desgastando ate o fim: a arma degrada antes de quebrar e quebra no 0.
	var degraded_at := -1
	for shot in max_durability:
		var left := pvp_slots.wear(kind)
		if degraded_at < 0 and pvp_slots.is_degraded(kind):
			degraded_at = left
		if left <= 0:
			break
	if degraded_at <= 0:
		_fail(test_root, "A arma deveria degradar antes de quebrar; degradou em %d." % degraded_at)
		NetworkSession.pvp_mode = pvp_before
		return
	if int(pvp_slots.state_of(kind)["durability"]) != 0:
		_fail(test_root, "Depois de %d tiros a durabilidade deveria zerar; veio %s." % [max_durability, pvp_slots.state_of(kind)["durability"]])
		NetworkSession.pvp_mode = pvp_before
		return
	# Survival continua igual: mesma reserva base e mesmo desgaste.
	NetworkSession.pvp_mode = false
	var survival_slots: WeaponSlots = WEAPON_SLOTS_SCRIPT.new()
	survival_slots.grant(kind)
	if int(survival_slots.state_of(kind)["reserve"]) != base_reserve:
		_fail(test_root, "No survival a reserva deveria continuar %d; veio %s." % [base_reserve, survival_slots.state_of(kind)["reserve"]])
		NetworkSession.pvp_mode = pvp_before
		return
	if survival_slots.wear(kind) != max_durability - 1:
		_fail(test_root, "No survival o tiro deveria desgastar 1 ponto; veio %s." % survival_slots.state_of(kind)["durability"])
		NetworkSession.pvp_mode = pvp_before
		return
	NetworkSession.pvp_mode = pvp_before
	print("PASS: Reserva %d (base %d) e desgaste valendo nos dois modos." % [expected_reserve, base_reserve])


## Quem morre DEIXA a arma no chao, com a municao e o desgaste que ela tinha:
## o abate vira despojo e quem passa pode pegar. Antes a arma sumia com o morto.
func _test_death_drops_the_held_weapon(test_root: Node) -> void:
	print("Testando arma caindo no chao na morte...")
	var pvp_before: bool = NetworkSession.pvp_mode
	NetworkSession.pvp_mode = true
	var player := PLAYER_SCENE.instantiate() as PlayerCharacter
	player.name = "PlayerQueMorre"
	player.reads_local_input = false
	test_root.add_child(player)
	var dropped: Array = []
	player.crate_weapon_dropped.connect(func(kind: int, mag: int, reserve: int, durability: int) -> void:
		dropped.append({"kind": kind, "mag": mag, "reserve": reserve, "durability": durability})
	)
	var kind := WeaponStats.Kind.AK47
	player.choose_pvp_loadout(kind)
	player.equip_crate_weapon(kind)
	# Gasta um pouco: o que cai no chao tem que ser o estado REAL, nao o de fabrica.
	player.weapon_slots.wear(kind)
	player.weapon_slots.consume_mag(kind)
	var mag_before := int(player.weapon_slots.state_of(kind)["mag"])
	var durability_before := int(player.weapon_slots.state_of(kind)["durability"])
	player.take_damage(player.max_health * 10, Vector3.FORWARD, "bullet", null)
	if not bool(player.get("is_eliminated")):
		_fail(test_root, "O jogador deveria ter morrido com dano acima da vida.")
		_cleanup(player, pvp_before)
		return
	if dropped.size() != 1:
		_fail(test_root, "A morte deveria soltar exatamente 1 arma; soltou %d." % dropped.size())
		_cleanup(player, pvp_before)
		return
	var loot: Dictionary = dropped[0]
	if int(loot["kind"]) != kind:
		_fail(test_root, "A arma no chao deveria ser a que estava na mao (%d); veio %s." % [kind, loot["kind"]])
		_cleanup(player, pvp_before)
		return
	if int(loot["mag"]) != mag_before or int(loot["durability"]) != durability_before:
		_fail(test_root, "A arma deveria cair com o estado de uso (mag %d, durabilidade %d); veio mag %s, durabilidade %s." % [mag_before, durability_before, loot["mag"], loot["durability"]])
		_cleanup(player, pvp_before)
		return
	if player.weapon_slots.has_kind(kind):
		_fail(test_root, "Quem morreu nao pode continuar com a arma no slot.")
		_cleanup(player, pvp_before)
		return
	_cleanup(player, pvp_before)
	print("PASS: A arma cai no chao com mag %d e durabilidade %d." % [mag_before, durability_before])


## Renascer devolve a arma ESCOLHIDA no loadout, nova: quem morreu perde o
## desgaste da vida anterior (a arma gasta ficou no chao para os outros).
func _test_respawn_brings_the_chosen_weapon_back_whole(test_root: Node) -> void:
	print("Testando respawn com a arma escolhida inteira...")
	var pvp_before: bool = NetworkSession.pvp_mode
	NetworkSession.pvp_mode = true
	var player := PLAYER_SCENE.instantiate() as PlayerCharacter
	player.name = "PlayerQueRenasce"
	player.reads_local_input = false
	test_root.add_child(player)
	var kind := WeaponStats.Kind.UZI
	player.choose_pvp_loadout(kind)
	player.equip_crate_weapon(kind)
	player.weapon_slots.wear(kind)
	player.take_damage(player.max_health * 10, Vector3.FORWARD, "bullet", null)
	player.pvp_respawn_at(Vector3(5.0, 1.0, 5.0))
	if not player.weapon_slots.has_kind(kind):
		_fail(test_root, "Renascer deveria devolver a arma escolhida (%d)." % kind)
		_cleanup(player, pvp_before)
		return
	var max_durability := int(WeaponStats.stats_for(kind)["max_durability"])
	if int(player.weapon_slots.state_of(kind)["durability"]) != max_durability:
		_fail(test_root, "A arma do respawn vem nova (%d de durabilidade); veio %s." % [max_durability, player.weapon_slots.state_of(kind)["durability"]])
		_cleanup(player, pvp_before)
		return
	if player.spawn_protection_left <= 0.0:
		_fail(test_root, "Renascer tem que ligar a invulnerabilidade; veio %f." % player.spawn_protection_left)
		_cleanup(player, pvp_before)
		return
	_cleanup(player, pvp_before)
	print("PASS: Respawn devolve a arma escolhida nova, com protecao.")


## Devolve o modo anterior e libera o jogador do teste.
func _cleanup(player: Node, pvp_before: bool) -> void:
	NetworkSession.pvp_mode = pvp_before
	player.queue_free()


## Regressao: o bot nascia no quintal a 5,9 m da primeira esquina, e o raio de
## chegada era 6,0 m — ele ja considerava a esquina alcancada, pulava para a
## seguinte (no outro canto do mapa) e cortava o quarteirao na diagonal, travando
## num predio sem nunca sair de casa (medido: 120 s parado em (-44,5, -58,0)).
func _test_route_leaves_the_base_before_the_next_corner(test_root: Node) -> void:
	print("Testando saida da base antes da proxima esquina...")
	var director := PVP_DIRECTOR_SCRIPT
	var yard_distance: float = director.BOT_YARD_DISTANCE
	var first_corner: Vector3 = director.ROUTE_CORNERS[0]
	var base: Vector3 = director.TEAM_BASE_FALLBACK[0]
	# O quintal do time 0 fica em -Z; a primeira esquina e a rua de baixo.
	var yard := Vector3(base.x, base.y + 1.0, base.z - yard_distance)
	var to_corner := Vector2(yard.x - first_corner.x, yard.z - first_corner.z).length()
	if director.WAYPOINT_ARRIVE_RADIUS >= to_corner:
		_fail(test_root, "O raio de chegada (%.1f m) precisa ser MENOR que a distancia do quintal ate a primeira esquina (%.1f m), senao o bot pula a rua." % [director.WAYPOINT_ARRIVE_RADIUS, to_corner])
		return
	print("PASS: Raio de chegada %.1f m < %.1f m ate a rua." % [director.WAYPOINT_ARRIVE_RADIUS, to_corner])


## O bot anda em linha reta para o waypoint (nao ha navmesh). Trecho longo
## demais acumula desvio de obstaculo ate ele sair da rua e encostar num predio
## (medido: o time 1 travado em x=-28,9 por 80 s num trecho de 144 m).
func _test_route_has_no_long_straight_leg(test_root: Node) -> void:
	print("Testando rota picotada em trechos curtos...")
	var route: Array = PVP_DIRECTOR_SCRIPT.paved_route()
	if route.size() < PVP_DIRECTOR_SCRIPT.ROUTE_CORNERS.size():
		_fail(test_root, "A rota picotada nao pode ter menos pontos que as esquinas; veio %d." % route.size())
		return
	for index in range(1, route.size()):
		var leg: float = (route[index] as Vector3).distance_to(route[index - 1])
		if leg > PVP_DIRECTOR_SCRIPT.ROUTE_STEP + 0.01:
			_fail(test_root, "Trecho %d da rota tem %.1f m (maximo %.1f m)." % [index, leg, PVP_DIRECTOR_SCRIPT.ROUTE_STEP])
			return
	# As esquinas originais continuam na rota: picotar nao pode cortar caminho.
	for corner in PVP_DIRECTOR_SCRIPT.ROUTE_CORNERS:
		var found := false
		for point in route:
			if (point as Vector3).distance_to(corner) < 0.01:
				found = true
				break
		if not found:
			_fail(test_root, "A esquina %s sumiu da rota picotada." % corner)
			return
	print("PASS: Rota com %d pontos, nenhum trecho acima de %.0f m." % [route.size(), PVP_DIRECTOR_SCRIPT.ROUTE_STEP])


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
