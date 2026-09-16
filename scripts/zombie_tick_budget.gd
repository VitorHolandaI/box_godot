class_name ZombieTickBudget
extends RefCounted

## Orcamento de simulacao de um zumbi perseguindo. Substitui o "active set" que
## congelava todo zumbi alem do 80o (d800358): longe dos jogadores a IA roda a
## cada MID_TICK_STRIDE/FAR_TICK_STRIDE ticks com o tempo acumulado, entao o
## zumbi anda a mesma distancia com 1/3 ou 1/6 do custo. A fase por zumbi
## espalha a horda entre os ticks em vez de todos rodarem no mesmo.
## Uso:
##   var budget := ZombieTickBudget.new(network_id)
##   var sim_delta := budget.consume(delta, lod_level, player_distance_sq, dash_is_leaping)
##   if sim_delta > 0.0: simular(sim_delta)

const CLOSE_TICK_STRIDE := 1
## NEAR alem de CLOSE_DISTANCE_SQ (10-22 m) roda a 15 Hz: ainda acima dos
## snapshots de 10 Hz; na horda chegando no jogador era o grosso do custo.
const NEAR_TICK_STRIDE := 2
const CLOSE_DISTANCE_SQ := 100.0
# A 30 Hz: MID (22-50 m) roda a 10 Hz, igual aos snapshots que o client ve;
# FAR (> 50 m, fora do raio de visao de 35 m) a 5 Hz. Com 2/4 e ~400 zumbis
# ativos a IA ainda custava 10-11 ms/frame local (move_and_slide 7-8 ms).
const MID_TICK_STRIDE := 3
const FAR_TICK_STRIDE := 6
const LOD_MID := 1
const LOD_FAR := 2

var _phase := 0
var _tick_counter := 0
var _accumulated_delta := 0.0


## `phase_seed` distribui zumbis entre os ticks (id de rede ou hash do nome).
func _init(phase_seed: int = 0) -> void:
	_phase = posmod(phase_seed, FAR_TICK_STRIDE)


## Tempo a simular neste tick (soma dos ticks pulados) ou 0.0 quando o tick e
## pulado. Em voo (bote/investida) roda sempre: o arco precisa de todo tick.
## Uso: var sim_delta := budget.consume(delta, int(lod_level), player_distance_sq, leaping)
func consume(delta: float, lod_level: int, player_distance_sq: float, leaping: bool) -> float:
	_tick_counter += 1
	_accumulated_delta += maxf(delta, 0.0)
	if not leaping and (_tick_counter + _phase) % stride_for(lod_level, player_distance_sq) != 0:
		return 0.0
	var simulated := _accumulated_delta
	_accumulated_delta = 0.0
	return simulated


## `player_distance_sq` vem do flock (0 quando desconhecida = todo tick).
## Uso: ZombieTickBudget.stride_for(2, 3600.0) -> FAR_TICK_STRIDE
static func stride_for(lod_level: int, player_distance_sq: float) -> int:
	if lod_level == LOD_FAR:
		return FAR_TICK_STRIDE
	if lod_level == LOD_MID:
		return MID_TICK_STRIDE
	if player_distance_sq > CLOSE_DISTANCE_SQ:
		return NEAR_TICK_STRIDE
	return CLOSE_TICK_STRIDE


## Zumbi ja colado no alvo, no chao, sem bote nem tranco de golpe fica parado
## batendo: sem flock push e sem move_and_slide. Na horda amontoada no jogador
## esse deslize era o pico medido na VPS (move_and_slide ate 32 ms/frame).
## Uso: if ZombieTickBudget.holds_ground(in_range, is_on_floor(), leaping, hit_reaction_time > 0.0): ...
static func holds_ground(in_melee_range: bool, on_floor: bool, leaping: bool, hit_reacting: bool) -> bool:
	return in_melee_range and on_floor and not leaping and not hit_reacting
