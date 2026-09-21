<!-- Documentacao detalhada do projeto. O README fica so com o essencial. -->

# Modo mata-mata por times (TDM)

Mata-mata por times (Team Deathmatch): **dois times, placar continuo de abates,
FPS normal**. Nao ha rodadas, nao ha economia e nao ha fase de compra — isso saiu
do modo antigo estilo CS, que na pratica deixava a sala parada (rodada de 150 s,
quem morria ficava fora ate a rodada seguinte, freezetime travando quem tinha
acabado de entrar).

## Regras

| | |
|---|---|
| Times | 2 (**Azul** e **Vermelho**), equilibrados na entrada |
| Cor | **uma cor por time**, no uniforme — nao ha mais cor por jogador |
| Placar | abates do time; **50** fecha a partida |
| Tempo | teto de **10 min**; no fim leva quem tem mais abates (igual = empate) |
| Respawn | **5 s**, na propria base, sozinho |
| Invulnerabilidade | **4 s** ao renascer; o **primeiro tiro cancela** |
| Fogo amigo | nao machuca, e matar companheiro **tira 1** do placar do time |
| Arma | **escolha livre** (tecla **B**), de graca, todo o arsenal |
| Bases | as duas safehouses, em **cantos opostos** do mapa (~165 m) |

A troca de arma vale **na hora** quando voce esta dentro da propria base (ou
ainda protegido do respawn); fora dela ela entra **na proxima vida** — trocar de
fuzil no meio do tiroteio seria arma infinita de graca.

A sala aparece como **Mata-mata PVP** e o HUD nao mostra nada de zumbi (sem
contador de horda, sem sonar).

## Subir o servidor

Cada modo e um **container proprio**, com porta e nome proprios, escolhido pelo
profile do compose — da para deixar sobrevivencia e mata-mata no ar ao mesmo
tempo.

```bash
docker compose --profile tdm up -d --build     # mata-mata, porta 27017
docker compose ps

# atalho: menu que escolhe no ato o modo (com ou sem rebuild) e cuida de
# parar/logs/status:
scripts/server_menu.sh                    # menu interativo
scripts/server_menu.sh tdm up             # mata-mata: rebuild + sobe (sem bots)
PVP_BOTS=4 scripts/server_menu.sh tdm up  # com 4 bots, para testar
scripts/server_menu.sh tdm logs           # so o log do mata-mata
scripts/server_menu.sh tdm stop           # derruba so este modo

# cliente (mesmo build do servidor):
godot --path . -- --join=127.0.0.1 --server-port=27017
```

Variaveis do modo: `TDM_PORT`, `TDM_BOTS`, `TDM_NAME`, `TDM_WORLD_SEED`.
Ver [modos-e-containers.md](modos-e-containers.md) para os outros modos.

## Onde mexer

| Arquivo | Papel |
|---|---|
| `scripts/tdm_match.gd` | as REGRAS (placar, times, tempo, fogo amigo, protecao). Puro, testavel |
| `scripts/pvp_server_director.gd` | o mundo: bases, bots, rota entre as bases, respawn, broadcast |
| `scripts/loadout_menu.gd` | menu de arma do cliente (tecla B) |
| `scripts/test_tdm_match.gd` | regressoes do modo |
| `scripts/main.gd` | so a ponte de RPC (o Godot exige um no na arvore para rotear) |
