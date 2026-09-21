class_name TdmMatch
extends RefCounted

## Mata-mata por times (Team Deathmatch), autoritativo no servidor.
##
## Regra: 2 times, placar CONTINUO de abates, sem rodadas e sem economia. A
## partida acaba quando um time chega em SCORE_LIMIT ou quando MATCH_SECONDS
## estoura (leva quem tem mais abates; empate no mesmo numero).
##
## Trocou o formato antigo estilo CS (melhor de 3, fase de compra com
## freezetime, dinheiro por abate) porque na pratica a sala vivia parada: com
## poucos jogadores a rodada esperava 150 s de relogio, quem morria ficava fora
## ate a rodada seguinte e o freezetime travava o movimento de quem tinha acabado
## de entrar. Aqui morreu, renasce na propria base em RESPAWN_SECONDS, com
## SPAWN_PROTECTION_SECONDS de invulnerabilidade, e volta a jogar FPS normal.
##
## Arma e ESCOLHA, nao compra: o jogador pega a que quiser no menu de loadout e
## renasce com ela (ver LoadoutMenu e PvpServerDirector.choose_loadout).
##
## Uso:
##   var partida := TdmMatch.new()
##   partida.register_player("123:0")
##   partida.register_kill("123:0", "456:0")
##   partida.tick(delta)

const TEAM_COUNT := 2
## Abates que fecham a partida. 50 com 4-8 jogadores da uma partida de ~8 min,
## dentro do MATCH_SECONDS, sem depender do relogio para terminar.
const SCORE_LIMIT := 50
## Teto de duracao (10 min): a partida sempre termina mesmo com a sala parada.
const MATCH_SECONDS := 600.0
## Tempo no chao antes de voltar. Curto de proposito: o ritmo do TDM e a
## reentrada rapida, nao a espera (o formato antigo tirava o jogador ate o fim
## da rodada).
const RESPAWN_SECONDS := 5.0
## Invulnerabilidade ao renascer. As bases ficam em cantos opostos (~165 m),
## entao isso cobre a saida da casa, nao a briga: atirar cancela (ver
## protection_after_attack).
const SPAWN_PROTECTION_SECONDS := 4.0
## Cores dos times (uma por time, so duas no mapa inteiro): azul e vermelho.
## O uniforme do jogador sai daqui em vez do indice de vaga, que pintava cada
## jogador de uma cor e deixava impossivel saber quem era inimigo.
const TEAM_COLORS: Array[Color] = [Color(0.16, 0.34, 0.78), Color(0.78, 0.18, 0.14)]
const TEAM_NAMES := ["Azul", "Vermelho"]

enum Phase { LIVE, MATCH_END }

var phase: Phase = Phase.LIVE
## Segundos restantes da partida.
var time_remaining := MATCH_SECONDS
## Abates de cada time (o placar que decide).
var team_kills: Array[int] = [0, 0]
## chave -> {"kills": int, "deaths": int, "team": int}
var scores: Dictionary = {}


## Entra na partida no time com MENOS gente (empate no 0); quem ja estava nao
## troca de time. Uso: partida.register_player("123:0")
func register_player(key: String) -> void:
	if scores.has(key):
		return
	scores[key] = {"kills": 0, "deaths": 0, "team": smallest_team()}


## Id do time com menos gente registrada (empate devolve 0).
## Uso: var time := partida.smallest_team()
func smallest_team() -> int:
	var counts := team_counts()
	var smallest := 0
	for team in TEAM_COUNT:
		if counts[team] < counts[smallest]:
			smallest = team
	return smallest


## Quantos jogadores registrados por time. Uso: var n := partida.team_counts()
func team_counts() -> Array[int]:
	var counts: Array[int] = []
	counts.resize(TEAM_COUNT)
	counts.fill(0)
	for key in scores:
		var team := int((scores[key] as Dictionary)["team"])
		if team >= 0 and team < TEAM_COUNT:
			counts[team] += 1
	return counts


func remove_player(key: String) -> void:
	scores.erase(key)


func has_player(key: String) -> bool:
	return scores.has(key)


func player_count() -> int:
	return scores.size()


## Time (0/1) do jogador; -1 quando nao esta na partida.
## Uso: var time := partida.team_of("123:0")
func team_of(key: String) -> int:
	return int((scores.get(key, {}) as Dictionary).get("team", -1))


func kills_of(key: String) -> int:
	return int((scores.get(key, {}) as Dictionary).get("kills", 0))


func deaths_of(key: String) -> int:
	return int((scores.get(key, {}) as Dictionary).get("deaths", 0))


## Placar do time (abates validos menos os de fogo amigo).
## Uso: var placar := partida.score_of_team(0)
func score_of_team(team: int) -> int:
	if team < 0 or team >= TEAM_COUNT:
		return 0
	return team_kills[team]


## Cor do uniforme do time. Fora da faixa devolve a do time 0 (o jogador
## sempre tem uniforme, mesmo com estado de rede incompleto).
## Uso: material.albedo_color = TdmMatch.color_for_team(time)
static func color_for_team(team: int) -> Color:
	if team < 0 or team >= TEAM_COLORS.size():
		return TEAM_COLORS[0]
	return TEAM_COLORS[team]


## Nome do time para HUD/log. Uso: var nome := TdmMatch.name_for_team(1)
static func name_for_team(team: int) -> String:
	if team < 0 or team >= TEAM_NAMES.size():
		return "Sem time"
	return TEAM_NAMES[team]


## Verdadeiro quando o dano NAO deve ser aplicado: fogo amigo (mesmo time) ou
## vitima ainda protegida pelo respawn. Funcao pura para o player.take_damage
## decidir sem conhecer a partida. Time -1 (fora da partida) nunca e amigo.
## Uso: if TdmMatch.blocks_damage(atacante_time, vitima_time, protecao): return
static func blocks_damage(attacker_team: int, victim_team: int, victim_protection_left: float) -> bool:
	if victim_protection_left > 0.0:
		return true
	return attacker_team >= 0 and attacker_team == victim_team


## Protecao que sobra depois de o protegido atacar: zero. Sem isso da para
## nascer invulneravel e limpar a base inimiga de graca; e a regra classica de
## FPS (a protecao cai no primeiro tiro).
## Uso: player.spawn_protection_left = TdmMatch.protection_after_attack(p)
static func protection_after_attack(_current: float) -> float:
	return 0.0


## Registra um abate: conta a morte da vitima e pontua o time do matador. Abate
## de companheiro (ou de si mesmo) TIRA um do proprio placar em vez de somar.
## Uso: partida.register_kill(chave_matador, chave_vitima)
func register_kill(killer_key: String, victim_key: String) -> void:
	if scores.has(victim_key):
		var victim_entry: Dictionary = scores[victim_key]
		victim_entry["deaths"] = int(victim_entry["deaths"]) + 1
	if killer_key.is_empty() or not scores.has(killer_key):
		return
	var killer_team := team_of(killer_key)
	if killer_team < 0 or killer_team >= TEAM_COUNT:
		return
	if killer_key == victim_key or team_of(victim_key) == killer_team:
		_score_own_goal(killer_key, killer_team)
		return
	var killer_entry: Dictionary = scores[killer_key]
	killer_entry["kills"] = int(killer_entry["kills"]) + 1
	team_kills[killer_team] += 1
	_finish_when_limit_reached()


## Penalidade de fogo amigo: -1 no jogador e no time, sem deixar negativo.
func _score_own_goal(killer_key: String, killer_team: int) -> void:
	var killer_entry: Dictionary = scores[killer_key]
	killer_entry["kills"] = maxi(int(killer_entry["kills"]) - 1, 0)
	team_kills[killer_team] = maxi(team_kills[killer_team] - 1, 0)


func _finish_when_limit_reached() -> void:
	if team_kills[0] < SCORE_LIMIT and team_kills[1] < SCORE_LIMIT:
		return
	phase = Phase.MATCH_END
	time_remaining = 0.0


## Time vencedor, ou -1 (em andamento ou empate).
## Uso: var campeao := partida.winner()
func winner() -> int:
	if phase != Phase.MATCH_END or team_kills[0] == team_kills[1]:
		return -1
	return 0 if team_kills[0] > team_kills[1] else 1


func is_over() -> bool:
	return phase == Phase.MATCH_END


func time_left() -> float:
	return time_remaining


## Avanca o relogio da partida e fecha no tempo. Quem chama (o diretor) so
## deve ticar com a sala ocupada: servidor vazio e sala esperando jogador, nao
## partida rolando (ver PvpServerDirector.tick e o mesmo cuidado em
## SurvivalWaveController.everyone_is_down).
## Uso: partida.tick(delta)
func tick(delta: float) -> void:
	if phase == Phase.MATCH_END:
		return
	time_remaining = maxf(time_remaining - maxf(delta, 0.0), 0.0)
	if time_remaining <= 0.0:
		phase = Phase.MATCH_END


## Placar por jogador, ordenado por abates (HUD/log de fim de partida).
## Uso: for linha in partida.standings(): ...
func standings() -> Array:
	var rows: Array = []
	for key in scores:
		var entry: Dictionary = scores[key]
		rows.append({
			"key": String(key),
			"kills": int(entry["kills"]),
			"deaths": int(entry["deaths"]),
			"team": int(entry["team"]),
		})
	rows.sort_custom(func(first: Dictionary, second: Dictionary) -> bool: return int(first["kills"]) > int(second["kills"]))
	return rows


## Placar dos times em uma linha. Uso: var texto := partida.team_score_text()
func team_score_text() -> String:
	return "%s %d x %d %s" % [TEAM_NAMES[0], team_kills[0], team_kills[1], TEAM_NAMES[1]]


## Linha unica do HUD: relogio + placar, ou o vencedor no fim.
## Uso: var texto := partida.hud_text()
func hud_text() -> String:
	if phase == Phase.MATCH_END:
		var champion := winner()
		var label := "empate" if champion < 0 else "Time %s" % name_for_team(champion)
		return "FIM | vencedor: %s | %s" % [label, team_score_text()]
	var clock := "%02d:%02d" % [int(time_remaining) / 60, int(time_remaining) % 60]
	return "MATA-MATA %s | %s | ate %d" % [clock, team_score_text(), SCORE_LIMIT]
