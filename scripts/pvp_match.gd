class_name PvpMatch
extends RefCounted

## Mata-mata estilo CS, autoritativo no servidor. Guarda economia e placar por
## jogador (chave "peer:slot"), valida compras e decide o fim da partida.
##
## Regras desta primeira versao:
## - todo mundo comeca com MONEY_START e so pistola+faca (loadout resetado ao
##   morrer, como no CS: quem morre perde as armas compradas);
## - abate da MONEY_PER_KILL para quem matou; morte nao da dinheiro;
## - respawn em RESPAWN_SECONDS num ponto longe dos vivos;
## - compra liberada nos primeiros BUY_SECONDS depois de (re)nascer;
## - fim: KILLS_TO_WIN abates de alguem ou MATCH_SECONDS de partida.
## Uso:
##   var match := PvpMatch.new()
##   match.register_player("123:0")
##   var erro := match.buy_rejection("123:0", 1200, false)

const MONEY_START := 800
const MONEY_PER_KILL := 300
const MONEY_MAX := 16000
const RESPAWN_SECONDS := 3.0
const BUY_SECONDS := 15.0
const KILLS_TO_WIN := 20
const MATCH_SECONDS := 600.0

var elapsed := 0.0
var over := false
## chave -> {"kills": int, "deaths": int, "money": int}
var scores: Dictionary = {}


## Entra na partida com a economia inicial (quem ja estava nao perde nada).
## Uso: match.register_player("123:0")
func register_player(key: String) -> void:
	if scores.has(key):
		return
	scores[key] = {"kills": 0, "deaths": 0, "money": MONEY_START}


func remove_player(key: String) -> void:
	scores.erase(key)


func has_player(key: String) -> bool:
	return scores.has(key)


func money_of(key: String) -> int:
	return int((scores.get(key, {}) as Dictionary).get("money", 0))


func kills_of(key: String) -> int:
	return int((scores.get(key, {}) as Dictionary).get("kills", 0))


func deaths_of(key: String) -> int:
	return int((scores.get(key, {}) as Dictionary).get("deaths", 0))


## Credita (respeitando MONEY_MAX) e devolve o total depois do credito.
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


## Motivo da recusa de uma compra, ou "" quando pode comprar. Puro para testar
## as regras sem cena: o chamador passa o preco da arma e o tempo de compra.
## Uso: var erro := match.buy_rejection(key, 1200, tem_arma)
func buy_rejection(key: String, price: int, buy_seconds_left: float) -> String:
	if not scores.has(key):
		return "Jogador fora da partida."
	if over:
		return "A partida acabou."
	if buy_seconds_left <= 0.0:
		return "Fora do tempo de compra."
	if price <= 0:
		return "Arma sem preco definido."
	if money_of(key) < price:
		return "Dinheiro insuficiente: $%d de $%d." % [money_of(key), price]
	return ""


## Registra um abate: credita o matador e conta a morte da vitima. Sem matador
## (morte por queda, suicidio) so conta a morte. Devolve true quando a partida
## terminou com esse abate.
## Uso: if match.register_kill(killer_key, victim_key): anunciar_fim()
func register_kill(killer_key: String, victim_key: String) -> bool:
	if scores.has(victim_key):
		var victim_entry: Dictionary = scores[victim_key]
		victim_entry["deaths"] = int(victim_entry["deaths"]) + 1
	if not killer_key.is_empty() and killer_key != victim_key and scores.has(killer_key):
		var killer_entry: Dictionary = scores[killer_key]
		killer_entry["kills"] = int(killer_entry["kills"]) + 1
		add_money(killer_key, MONEY_PER_KILL)
		if int(killer_entry["kills"]) >= KILLS_TO_WIN:
			over = true
	return over


## Chave de quem venceu, ou "" (partida em andamento / empate no tempo).
## Uso: var vencedor := match.winner_key()
func winner_key() -> String:
	var best_key := ""
	var best_kills := 0
	for key in scores:
		var kills := kills_of(String(key))
		if kills > best_kills:
			best_kills = kills
			best_key = String(key)
	return best_key if over and best_kills > 0 else ""


## Partida encerrada (por abates ou por tempo).
## Uso: if match.is_over(): mostrar_fim()
func is_over() -> bool:
	return over


## Segundos restantes de partida (0 quando ja era).
## Uso: var faltam := match.time_left()
func time_left() -> float:
	return maxf(MATCH_SECONDS - elapsed, 0.0)


## Avanca o relogio; a partida acaba ao bater MATCH_SECONDS.
## Uso: match.tick(delta)
func tick(delta: float) -> void:
	if over:
		return
	elapsed += maxf(delta, 0.0)
	if elapsed >= MATCH_SECONDS:
		over = true


## Placar ordenado por abates, para HUD/placar. Uso:
##   for linha in match.standings(): print(linha["key"], linha["kills"])
func standings() -> Array:
	var rows: Array = []
	for key in scores:
		var entry: Dictionary = scores[key]
		rows.append({"key": String(key), "kills": int(entry["kills"]), "deaths": int(entry["deaths"]), "money": int(entry["money"])})
	rows.sort_custom(func(first: Dictionary, second: Dictionary) -> bool: return int(first["kills"]) > int(second["kills"]))
	return rows


## Linha unica de HUD: tempo, lider e fim de partida.
## Uso: var texto := match.hud_text()
func hud_text() -> String:
	if over:
		var winner := winner_key()
		return "FIM | vencedor: %s | %s" % [winner if not winner.is_empty() else "empate", _score_line()]
	return "%02d:%02d | %s" % [int(time_left()) / 60, int(time_left()) % 60, _score_line()]


func _score_line() -> String:
	var parts: Array[String] = []
	for row in standings():
		parts.append("%s %d/%d" % [row["key"], int(row["kills"]), int(row["deaths"])])
	return " | ".join(parts)
