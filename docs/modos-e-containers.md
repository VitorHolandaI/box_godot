<!-- Documentacao detalhada do projeto. O README fica so com o essencial. -->

# Modos de jogo: um container por modo

Cada modo de jogo e um **servico proprio** no `compose.yaml`, com porta,
container e variaveis proprias, escolhido pelo **profile** do compose. Voce
escolhe qual subir — e da para subir mais de um ao mesmo tempo.

Antes havia um servico so (`game-server`) e o modo ia por variavel de ambiente:
trocar de modo **recriava o mesmo container**, entao nunca dava para ter
sobrevivencia e mata-mata no ar juntos, e descobrir o que estava rodando exigia
ler o `command` do container.

| Modo | Profile | Porta | Container | O que e |
|---|---|---|---|---|
| Sobrevivencia | `survival` | 27015 | `box-godot-survival` | cooperativo contra zumbis, com ondas (padrao do jogo) |
| Mata-mata | `tdm` (ou `pvp`) | 27017 | `box-godot-tdm` | Team Deathmatch por times — ver [pvp.md](pvp.md) |
| Classico | `classic` | 27019 | `box-godot-classic` | zumbis sem a progressao de ondas (`--classic-mode`) |

A porta seguinte de cada modo (27016 / 27018 / 27020) e a de **descoberta** na
rede local.

## Subir, parar, ver

```bash
docker compose --profile survival up -d --build
docker compose --profile tdm up -d --build
docker compose --profile survival --profile tdm up -d   # os dois juntos
docker compose ps
```

Sem profile nenhum o `up` **nao sobe nada**, de proposito: o modo e escolha.

Pelo menu (faz o mesmo, sem decorar comando):

```bash
scripts/server_menu.sh              # menu interativo
scripts/server_menu.sh tdm up       # rebuild + sobe o mata-mata
scripts/server_menu.sh survival start   # sobe a sobrevivencia sem rebuild
scripts/server_menu.sh tdm logs     # log de um modo so
scripts/server_menu.sh tdm stop     # derruba so o mata-mata
scripts/server_menu.sh stop         # derruba tudo
scripts/server_menu.sh status       # o que esta no ar
scripts/server_menu.sh self-test    # testa o proprio menu, sem docker
```

## Variaveis por modo

Cada modo le as suas, entao subir um **nao mexe** na configuracao do outro:

| Modo | Variaveis |
|---|---|
| survival | `SURVIVAL_PORT`, `SURVIVAL_DISCOVERY_PORT`, `SURVIVAL_CAR_BOT`, `SURVIVAL_NAME`, `SURVIVAL_WORLD_SEED` |
| tdm | `TDM_PORT`, `TDM_DISCOVERY_PORT`, `TDM_BOTS`, `TDM_NAME`, `TDM_WORLD_SEED` |
| classic | `CLASSIC_PORT`, `CLASSIC_DISCOVERY_PORT`, `CLASSIC_NAME`, `CLASSIC_WORLD_SEED` |

Sem `*_WORLD_SEED` o `scripts/server_entrypoint.sh` gera a seed a partir do
hostname do container: cada container tem a sua cidade, estavel entre reinicios.

## Adicionar um modo novo

1. A flag no `scripts/network_session.gd` (ao lado de `--pvp` / `--classic-mode`).
2. As regras em um arquivo proprio, puro e testavel (espelho de `tdm_match.gd`).
3. Um servico no `compose.yaml` com profile, porta e container proprios.
4. O modo no `canonical_mode` e no menu de `scripts/server_menu.sh`, mais o
   caso no `self-test` dele.
