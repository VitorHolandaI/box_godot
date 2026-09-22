# Tick de rede a 60 Hz: como foi feito

Registro de como o servidor dedicado saiu de snapshots a 10 Hz com fisica a
30 Hz para **fisica e snapshots a 60 Hz**, e da latencia de interpolacao de
~200 ms para ~33 ms.

## Ponto de partida

| Coisa | Antes | Onde |
|---|---|---|
| snapshots de jogador/zumbi | 10 Hz (100 ms) | `main.gd` `SNAPSHOT_INTERVAL` |
| fisica do servidor dedicado | 30 Hz | `server_tick_policy.gd` `DEDICATED_PHYSICS_TICKS` |
| atraso de interpolacao do jogador | ~200 ms | `snapshot_interp_buffer.gd` |
| atraso do proxy do carro | 120 ms | `drivable_car.gd` `PROXY_INTERP_DELAY` |

O sintoma que expos o problema foi o **passageiro do carro**: carro e jogador
vinham no mesmo pacote, mas eram interpolados com atrasos diferentes (120 ms x
200 ms). A 20 m/s o passageiro era desenhado 1,6 m atras do carro em que
estava sentado. O motorista nunca mostrou porque ja era grudado no banco antes
de chegar na interpolacao.

## As tres alavancas

O atraso do buffer nao e culpa do algoritmo: ele e consequencia da taxa de
snapshot. Para reduzir a latencia sem travar o proxy, as tres precisam andar
juntas.

1. **Taxa de snapshot** (`main.gd` `SNAPSHOT_INTERVAL`): 10 -> 60 Hz.
2. **Tick de fisica dedicada** (`server_tick_policy.gd`
   `DEDICATED_PHYSICS_TICKS`): 30 -> 60 Hz.
3. **Piso do buffer** (`snapshot_interp_buffer.gd` `MIN_DELAY_MS`): 150 ms ->
   1000/30 ms, e `DEFAULT_INTERVAL_MS`: 100 -> 1000/60.

## Valores finais

```gdscript
# main.gd
const INPUT_INTERVAL := 1.0 / 30.0     # input do cliente continua 30 Hz
const SNAPSHOT_INTERVAL := 1.0 / 60.0  # era 1.0 / 10.0

# server_tick_policy.gd
const DEDICATED_PHYSICS_TICKS := 60    # era 30
const DEDICATED_MAX_PHYSICS_STEPS := 2 # inalterado

# snapshot_interp_buffer.gd
const DEFAULT_INTERVAL_MS := 1000.0 / 60.0
const DELAY_INTERVALS := 2.0               # inalterado: 2 intervalos
const MIN_DELAY_MS := 1000.0 / 30.0        # era 150.0
const MAX_DELAY_MS := 450.0                # inalterado
```

Com `DELAY_INTERVALS = 2`, o buffer converge para **~33 ms** a 60 Hz (dois
intervalos de 16,7 ms).

## O acumulador de snapshot usa `fmod`, nao zera

`_tick_server_network` roda dentro do `_physics_process`, ou seja, na taxa de
fisica. A 20 Hz com fisica de 30 Hz, zerar o acumulador fazia o snapshot sair no
divisor inferior (15 Hz) em vez de 20 Hz. A correcao preserva a sobra:

```gdscript
snapshot_elapsed += delta
if snapshot_elapsed < SNAPSHOT_INTERVAL:
	return
# Preserva a sobra: taxas que nao dividem o tick de fisica mantem a media certa.
snapshot_elapsed = fmod(snapshot_elapsed, SNAPSHOT_INTERVAL)
```

Com isso, 20 Hz sobre 30 Hz rende cadencia 33/67 ms com media de 50 ms. A 60 Hz
sobre 60 Hz a cadencia ja sai regular.

## Medicoes

### Docker local (1 vCPU / 512 MB), 1 cliente, sonda `--lag-probe`

| Taxa | Zumbis | Intervalo medio | p95 | Late | Trafego |
|---|---:|---:|---:|---:|---:|
| 20 Hz | 10 | 50,0 ms | 67,1 ms | 0 | 13,5 KB/s |
| 30 Hz | 10 | 33,3 ms | 33,7 ms | 0 | 19,6 KB/s |
| 60 Hz | 210 | 16,7 ms | 17,6 ms | 1 | 236,5 KB/s |
| 120 Hz | 210 | 8,4 ms | 15,2 ms | 1711 | 486,7 KB/s |

A comparacao de trafego vale entre 60 e 120 Hz (mesmos 210 zumbis): **dobra**.
Em 60 Hz a fisica do servidor ficou entre 6,5 e 8,8 ms, sem frames acima de
33 ms.

### VPS real (`<ip-da-vps>:27015`), 60 Hz, 10 zumbis

```json
{"complete_snapshots":1763,"snapshot_interval_ms_avg":16.7,
 "snapshot_interval_ms_p95":17.7,"snapshot_interval_ms_max":32.2,
 "late_snapshots":8,"rtt_ms_avg":91.5,"received_kbps":45.3,
 "received_packets_per_second":187,"frame_ms_avg":16.67}
```

## Por que 120 Hz foi descartado

O cliente renderiza a 60 FPS, entao snapshots a 120 Hz chegam **dois por
frame** e sao consumidos em bloco. A sonda marcou 1711 intervalos tardios em 30 s
(contra 1 a 60 Hz) e o trafego dobrou, sem ganho visual proporcional. O teto
util deste cliente e 60 Hz.

## Armadilhas

### 1. O piso do buffer come o ganho
- **Sintoma:** subir a taxa de snapshot nao muda a latencia percebida.
- **Causa:** `MIN_DELAY_MS = 150` forca o atraso para 150 ms mesmo quando
  `intervalo * 2` da menos.
- **Regra:** ao subir a taxa, baixe o piso junto. Hoje `MIN_DELAY_MS` e
  `1000.0 / 30.0` (dois ticks a 60 Hz), com teste em
  `test_snapshot_interp_buffer.gd` para 20, 30 e 60 Hz.

### 2. Taxa nominal limitada pelo tick de fisica
- **Sintoma:** pedir 20 Hz e medir 15 Hz.
- **Causa:** o agendador roda no `_physics_process`; zerar o acumulador prende a
  taxa aos divisores do tick de fisica.
- **Regra:** use `fmod` para preservar a sobra; e lembre que acima do tick de
  fisica o snapshot so repete a mesma simulacao.

### 3. Atraso diferente em coisas que andam juntas
- **Sintoma:** passageiro desenhado atras do carro em que esta sentado.
- **Causa:** dois buffers com atrasos diferentes (carro 120 ms x jogador
  200 ms) para corpos que dividem o mesmo pacote.
- **Regra:** quem esta sentado no veiculo deve ser grudado ao banco, nao
  interpolado por conta propria. Ver `docs/gotchas.md` item 9.

## Como medir de novo

```bash
# servidor local (docker) e relatorio de custo
scripts/server_menu.sh survival start
docker compose logs --since 60s survival | grep perf_report | tail -2

# sonda de rede contra um servidor remoto (RTT + espacamento real de snapshots)
timeout 55 godot --headless --path . -- \
  --bot-player=<ip-da-vps> --server-port=27015 --lag-probe=30

# carga com horda: container isolado, porta propria
docker run --detach --name box-godot-survival-stress --cpus=1.0 --memory=512m \
  --read-only --tmpfs /tmp:size=64m,mode=1777 \
  --tmpfs /home/godot/.local/share/godot:size=64m,uid=10001,gid=10001,mode=0700 \
  --publish 27025:27015/udp box-godot-server:local \
  --server --server-port=27015 --production --procedural-city --survival \
  --prespawn-zombies=200
```

`--prespawn-zombies=N` sozinho nao mede: sem jogador os zumbis sao descartados
por FOV e o relatorio sai com `zombies:0`.

## Onde ficam os numeros

- `scripts/main.gd`: `SNAPSHOT_INTERVAL`, `INPUT_INTERVAL`, `_tick_server_network`.
- `scripts/server_tick_policy.gd`: `DEDICATED_PHYSICS_TICKS`, `DEDICATED_MAX_PHYSICS_STEPS`.
- `scripts/snapshot_interp_buffer.gd`: `DEFAULT_INTERVAL_MS`, `MIN_DELAY_MS`, `DELAY_INTERVALS`, `MAX_SAMPLES`.
- `scripts/network_lag_probe.gd`: `EXPECTED_SNAPSHOT_INTERVAL_MS`.
- `scripts/test_snapshot_interp_buffer.gd`: testes de atraso a 20/30/60 Hz.
- `scripts/test_server_tick_policy.gd`: teste do tick dedicado a 60 Hz.

Commits: `3086250` (20 Hz sem subir a fisica) e `97f9b49` (fisica e snapshots
em 60 Hz).
