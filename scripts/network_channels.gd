class_name NetworkChannels
extends RefCounted

## Canais do ENet por tipo de trafego. Com um canal so (padrao do
## ENetMultiplayerPeer) um pacote confiavel reenviado (porta, item, HUD) segura
## os snapshots atras dele — head-of-line blocking. A sonda de lag na VPS
## mediu 128 ms de media e 1,6 s no pior com 10 Hz esperados; no cliente isso
## aparecia como zumbi/jogador teleportando. Cada fluxo quente ganha canal
## proprio para perda e atraso de um nao derrubarem o outro.
## Snapshot de zumbi vai sozinho porque uma wave grande ocupa varios pacotes:
## no mesmo canal, perder um derruba os seguintes (unreliable_ordered).
## Uso:
##   var peer := ENetMultiplayerPeer.new()
##   peer.create_server(porta, max_players, NetworkChannels.COUNT)

const RELIABLE := 0
const SNAPSHOT_ZOMBIES := 1
const SNAPSHOT_PLAYERS := 2
const INPUT := 3
const EFFECTS := 4
## Quantos canais abrir no host ENet (precisa cobrir o maior canal usado).
const COUNT := 5

## Nome de cada canal, na ordem do indice; usado em mensagem de erro e diagnostico.
const NAMES := ["confiavel", "snapshot_zumbis", "snapshot_jogadores", "input", "efeitos"]


## Todos os canais tem nome e ficam abaixo de COUNT; falha cedo se alguem
## adicionar um canal e esquecer de abrir o host para ele.
## Uso: var erro := NetworkChannels.validate()
static func validate() -> String:
	if NAMES.size() != COUNT:
		return "NetworkChannels.NAMES tem %d nomes; esperado %d (um por canal)." % [NAMES.size(), COUNT]
	var seen: Array[int] = [RELIABLE, SNAPSHOT_ZOMBIES, SNAPSHOT_PLAYERS, INPUT, EFFECTS]
	for index in seen.size():
		var channel: int = seen[index]
		if channel < 0 or channel >= COUNT:
			return "Canal %d ('%s') fora de COUNT=%d." % [channel, NAMES[index], COUNT]
		if seen.count(channel) != 1:
			return "Canal %d ('%s') duplicado no plano de canais." % [channel, NAMES[index]]
	return ""
