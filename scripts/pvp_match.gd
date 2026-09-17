class_name PvpMatch
extends RefCounted

## Mata-mata por times, autoritativo no servidor, com rodadas no estilo CS.
##
## Estrutura: 2 times, melhor de ROUNDS (3) com ROUNDS_TO_WIN (2) vitorias por
## rodada. Cada rodada tem FASE DE COMPRA (todo mundo na base pode comprar) e
## FASE DE COMBATE (so tiro); a rodada acaba quando um time inteiro cai ou
## quando o tempo estoura (vence quem tem mais gente viva; empate no 0x0).
##
## Economia: comeca com MONEY_START e so pistola+faca; abate da MONEY_PER_KILL;
## quem morre perde as armas compradas. Nao ha bonus de derrota (simples nesta
## primeira versao).
## Uso:
##   var match := PvpMatch.new()
##   match.register_player("123:0")
##   var erro := match.buy_rejection("123:0", 1200)

const TEAM_COUNT := 2
const ROUNDS := 3
const ROUNDS_TO_WIN := 2
const MONEY_START := 800
const MONEY_PER_KILL := 300
const MONEY_MAX := 16000
const RESPAWN_SECONDS := 3.0
## 90 s por rodada: o mapa e grande e sem pathfinding a rodada arrastava ate o
## limite; o tempo serve de rede de seguranca, nao de ritmo.
const ROUND_SECONDS := 90.0
const BUY_SECONDS := 15.0
const ROUND_END_SECONDS := 6.0

enum Phase { BUY, LIVE, ROUND_END, MATCH_END }

var phase: Phase = Phase.BUY
## Segundos restantes da fase atual.
var phase_left := BUY_SECONDS
var round_index := 1
var round_wins: Array[int] = [0, 0]
## chave -> {"kills": int, "deaths": int, "money": int, "team": int}
var scores: Dictionary = {}


## Entra na partida na fase de compra, com a economia inicial. O time e o que
## tem MENOS gente (empate no 0); quem ja estava nao muda de time. Assim
## entrando um a um os times ficam sempre com diferenca de no maximo 1.
## Uso: match.register_player("123:0")
func register_player(key: String) -> void:
	if scores.has(key):
		return
	scores[key] = {"kills": 0, "deaths": 0, "money": MONEY_START, "team": smallest_team()}


## Id do time com menos gente registrada (empate devolve 0).
## Uso: var time := match.smallest_team()
func smallest_team() -> int:
	var counts := team_counts()
	var smallest := 0
	for team in TEAM_COUNT:
		if counts[team] < counts[smallest]:
			smallest = team
	return smallest


## Quantos jogadores registrados por time. Uso: var n := match.team_counts()
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


## Time (0/1) do jogador; -1 quando nao esta na partida.
## Uso: var time := match.team_of("123:0")
func team_of(key: String) -> int:
	return int((scores.get(key, {}) as Dictionary).get("team", -1))


func money_of(key: String) -> int:
	return int((scores.get(key, {}) as Dictionary).get("money", 0))


func kills_of(key: String) -> int:
	return int((scores.get(key, {}) as Dictionary).get("kills", 0))


func deaths_of(key: String) -> int:
	return int((scores.get(key, {}) as Dictionary).get("deaths", 0))


## Creditos de dinheiro do abate (respeita MONEY_MAX).
## Uso: var total := match.add_money("123:0", PvpMatch.MONEY_PER_KILL)
func add_money(key: String, amount: int) -> int:
	if not scores.has(key):
		return 0
	var entry: Dictionary = scores[key]
	entry["money"] = clampi(int(entry["money"]) + amount, 0, MONEY_MAX)
	return int(entry["money"])


## Debita so se couber; false quando nao tem dinheiro (nao muda nada).
## Uso: if match.spend("123:0", 1200): comprou()
func spend(key: String, amount: int) -> bool:
	if amount <= 0 or not scores.has(key):
		return false
	var entry: Dictionary = scores[key]
	if int(entry["money"]) < amount:
		return false
	entry["money"] = int(entry["money"]) - amount
	return true


## Entrada congelada do freezetime: so olhar (aim) e o slot do jogador passam;
## movimento, pulo, tiro e itens ficam zerados. E o "tempo de compra" do CS:
## o servidor ignora o movimento nessa fase, entao o cliente nao anda mesmo que
## mande input. Funcao pura para testar.
## Uso: var congelado := PvpMatch.frozen_input(estado)
static func frozen_input(state: Dictionary) -> Dictionary:
	var frozen := state.duplicate()
	for action in ["jump", "sprint", "attack", "knife", "pistol", "reload", "interact", "shotgun", "uzi", "magnum", "double_barrel", "carbine", "drop", "cycle", "grenade", "throw_knife", "air_strike", "swat", "buy"]:
		frozen[action] = false
	frozen["move"] = Vector2.ZERO
	return frozen


## Motivo da recusa de uma compra, ou "" quando pode comprar. A posicao (base)
## e checada por quem chama, que conhece o mapa; aqui vale fase/dinheiro/preco.
## Uso: var erro := match.buy_rejection(key, 1200)
func buy_rejection(key: String, price: int) -> String:
	if not scores.has(key):
		return "Jogador fora da partida."
	if phase != Phase.BUY:
		return "So da para comprar na fase de compra (inicio da rodada)."
	if price <= 0:
		return "Arma sem preco definido."
	if money_of(key) < price:
		return "Dinheiro insuficiente: $%d de $%d." % [money_of(key), price]
	return ""


## Registra um abate: credita o matador e conta a morte. Nao decide rodada
## (quem decide e o time sem vivos, reportado pelo main).
## Uso: match.register_kill(killer_key, victim_key)
func register_kill(killer_key: String, victim_key: String) -> void:
	if scores.has(victim_key):
		var victim_entry: Dictionary = scores[victim_key]
		victim_entry["deaths"] = int(victim_entry["deaths"]) + 1
	if killer_key.is_empty() or killer_key == victim_key or not scores.has(killer_key):
		return
	var killer_entry: Dictionary = scores[killer_key]
	killer_entry["kills"] = int(killer_entry["kills"]) + 1
	add_money(killer_key, MONEY_PER_KILL)


## Fecha a rodada para `winner_team` (ou empate com -1), soma a vitoria e
## entra na fase de fim de rodada.
## Uso: match.finish_round(1)
func finish_round(winner_team: int) -> void:
	if phase != Phase.LIVE and phase != Phase.BUY:
		return
	if winner_team >= 0 and winner_team < TEAM_COUNT:
		round_wins[winner_team] += 1
	phase = Phase.ROUND_END
	phase_left = ROUND_END_SECONDS


## Time com mais gente viva vale a rodada quando o tempo estoura; empate quando
## os dois lados tem o mesmo numero. Uso: match.finish_round_by_time(alive_a, alive_b)
func finish_round_by_time(alive_per_team: Array) -> void:
	var first := int(alive_per_team[0]) if alive_per_team.size() > 0 else 0
	var second := int(alive_per_team[1]) if alive_per_team.size() > 1 else 0
	if first == second:
		finish_round(-1)
		return
	finish_round(0 if first > second else 1)


## Time vencedor da partida, ou -1 (em andamento / empate).
## Uso: var campeao := match.match_winner()
func match_winner() -> int:
	if phase != Phase.MATCH_END:
		return -1
	for team in TEAM_COUNT:
		if round_wins[team] >= ROUNDS_TO_WIN:
			return team
	return -1


## Placar da partida por time, para o HUD. Uso: match.team_score_text()
func team_score_text() -> String:
	return "Time A %d x %d Time B" % [round_wins[0], round_wins[1]]


## Rodada atual do total. Uso: var texto := match.round_text()
func round_text() -> String:
	return "Rodada %d/%d" % [round_index, ROUNDS]


func is_over() -> bool:
	return phase == Phase.MATCH_END


func time_left() -> float:
	return phase_left if phase != Phase.MATCH_END else 0.0


## Avanca a maquina de fases: compra -> combate (o fim da rodada vem do main,
## que conta os vivos) -> fim de rodada -> proxima rodada ou fim da partida.
## Uso: match.tick(delta)
func tick(delta: float) -> void:
	if phase == Phase.MATCH_END:
		return
	phase_left = maxf(phase_left - maxf(delta, 0.0), 0.0)
	match phase:
		Phase.BUY:
			if phase_left <= 0.0:
				phase = Phase.LIVE
				phase_left = ROUND_SECONDS
		Phase.LIVE:
			if phase_left <= 0.0:
				phase = Phase.ROUND_END
				phase_left = ROUND_END_SECONDS
		Phase.ROUND_END:
			if phase_left > 0.0:
				return
			if round_wins[0] >= ROUNDS_TO_WIN or round_wins[1] >= ROUNDS_TO_WIN or round_index >= ROUNDS:
				phase = Phase.MATCH_END
				phase_left = 0.0
				return
			round_index += 1
			phase = Phase.BUY
			phase_left = BUY_SECONDS


## Placar ordenado por abates (para placar/HUD). Uso: for linha in match.standings()
func standings() -> Array:
	var rows: Array = []
	for key in scores:
		var entry: Dictionary = scores[key]
		rows.append({
			"key": String(key),
			"kills": int(entry["kills"]),
			"deaths": int(entry["deaths"]),
			"money": int(entry["money"]),
			"team": int(entry["team"]),
		})
	rows.sort_custom(func(first: Dictionary, second: Dictionary) -> bool: return int(first["kills"]) > int(second["kills"]))
	return rows


## Linha unica de HUD: fase/relogio + placar dos times.
## Uso: var texto := match.hud_text()
func hud_text() -> String:
	var clock := "%02d:%02d" % [int(phase_left) / 60, int(phase_left) % 60]
	match phase:
		Phase.BUY:
			return "COMPRA %s | %s | %s" % [clock, round_text(), team_score_text()]
		Phase.LIVE:
			return "%s | %s | %s" % [clock, round_text(), team_score_text()]
		Phase.ROUND_END:
			return "FIM DA RODADA | %s | %s" % [round_text(), team_score_text()]
		_:
			var winner := match_winner()
			return "FIM | vencedor: %s | %s" % ["Time A" if winner == 0 else ("Time B" if winner == 1 else "empate"), team_score_text()]



