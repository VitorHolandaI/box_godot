class_name ZombieTickBudget
extends RefCounted

## Orcamento de simulacao de um zumbi perseguindo. Substitui o "active set" que
## congelava todo zumbi alem do 80o (d800358): longe dos jogadores a IA roda a
## cada MID_TICK_STRIDE/FAR_TICK_STRIDE ticks com o tempo acumulado, entao o
## zumbi anda a mesma distancia com 1/3 ou 1/6 do custo. A fase por zumbi
## espalha a horda entre os ticks em vez de todos rodarem no mesmo.
## Uso:
##   var budget := ZombieTickBudget.new(network_id)
##   var sim_delta := budget.consume(delta, lod_level, player_distance_sq, dash_is_leaping, Engine.get_physics_frames())
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
## Teto de ticks completos de IA por tick de fisica, somando todos os zumbis.
## Na VPS a horda inteira convergindo no jogador (tudo a < 22 m) levou a IA a
## 15-21 ms/frame mesmo com os intervalos por distancia (ec6aee7).
const MAX_FULL_TICKS_PER_FRAME := 48
## Sem vaga, o zumbi espera no maximo esses ticks extras e roda mesmo assim.
const MAX_OVERLOAD_EXTRA_TICKS := 3

static var _slot_frame := -1
static var _slots_used := 0
## Vagas reservadas neste tick para quem ficou sem vaga no tick anterior: sem
## isso os primeiros da arvore ganhavam sempre e os ultimos so no limite.
static var _reserved_for_owed := 0
static var _owed_this_frame := 0

var _phase := 0
var _tick_counter := 0
var _accumulated_delta := 0.0
var _ticks_waiting := 0
var _owed := false


## `phase_seed` distribui zumbis entre os ticks (id de rede ou hash do nome).
func _init(phase_seed: int = 0) -> void:
	_phase = posmod(phase_seed, FAR_TICK_STRIDE)


## Tempo a simular neste tick (soma dos ticks pulados) ou 0.0 quando o tick e
## pulado. Em voo (bote/investida) roda sempre: o arco precisa de todo tick.
## `physics_frame` separa as vagas globais de cada tick de fisica.
## Uso: var sim_delta := budget.consume(delta, int(lod_level), player_distance_sq, leaping, Engine.get_physics_frames())
func consume(delta: float, lod_level: int, player_distance_sq: float, leaping: bool, physics_frame: int) -> float:
	_tick_counter += 1
	_ticks_waiting += 1
	_accumulated_delta += maxf(delta, 0.0)
	var stride := stride_for(lod_level, player_distance_sq)
	if not leaping and not _owed and (_tick_counter + _phase) % stride != 0:
		return 0.0
	var forced := leaping or _ticks_waiting >= stride + MAX_OVERLOAD_EXTRA_TICKS
	if not _take_slot(physics_frame, _owed, forced):
		_owed = true
		_owed_this_frame += 1
		return 0.0
	_owed = false
	_ticks_waiting = 0
	var simulated := _accumulated_delta
	_accumulated_delta = 0.0
	return simulated


## Isola testes que simulam varios ticks de fisica com numeros repetidos.
## Uso: ZombieTickBudget.reset_frame_slots()
static func reset_frame_slots() -> void:
	_slot_frame = -1
	_slots_used = 0
	_reserved_for_owed = 0
	_owed_this_frame = 0


static func _take_slot(physics_frame: int, owed: bool, forced: bool) -> bool:
	if physics_frame != _slot_frame:
		_slot_frame = physics_frame
		_slots_used = 0
		_reserved_for_owed = mini(_owed_this_frame, MAX_FULL_TICKS_PER_FRAME)
		_owed_this_frame = 0
	var limit := MAX_FULL_TICKS_PER_FRAME if owed else MAX_FULL_TICKS_PER_FRAME - _reserved_for_owed
	if not forced and _slots_used >= limit:
		return false
	_slots_used += 1
	return true


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
