# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
extends RefCounted

## Regressoes do orcamento de simulacao por zumbi (hordas de 200 a 600):
## longe dos jogadores a IA roda a cada 2/4 ticks com o tempo acumulado, e quem
## ja esta batendo no jogador fica parado sem move_and_slide.
## Uso: ZombieTickBudgetTests.new().run(test_root)

const ZOMBIE_TICK_BUDGET_SCRIPT := preload("res://scripts/zombie_tick_budget.gd")
const FLOCK_COORDINATOR_SCRIPT := preload("res://scripts/zombie_flock_coordinator.gd")
const PROXY_FACTORY_SCRIPT := preload("res://scripts/network_zombie_proxy_factory.gd")
const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const NEAR := 0
const MID := 1
const FAR := 2
const TICK := 1.0 / 30.0


func run(test_root: Node) -> void:
	_test_near_runs_every_tick(test_root)
	_test_far_accumulates_skipped_ticks(test_root)
	_test_phase_spreads_zombies_across_ticks(test_root)
	_test_leap_forces_every_tick(test_root)
	_test_holds_ground_only_when_planted(test_root)
	_test_global_slots_cap_crowd_with_bounded_delay(test_root)
	_test_proxy_is_light_for_the_client(test_root)
	await _test_freed_target_is_dropped_without_errors(test_root)
	await _test_flock_spreads_hordes_across_ticks(test_root)


func _test_near_runs_every_tick(test_root: Node) -> void:
	ZOMBIE_TICK_BUDGET_SCRIPT.reset_frame_slots()
	print("Testando zumbi colado todo tick e NEAR a 20 m a cada 2...")
	var budget = ZOMBIE_TICK_BUDGET_SCRIPT.new(3)
	for tick in 5:
		var simulated: float = budget.consume(TICK, NEAR, 25.0, false, tick)
		if not is_equal_approx(simulated, TICK):
			_fail(test_root, "Zumbi NEAR deveria simular todo tick com delta %s; tick %d veio %s." % [TICK, tick, simulated])
			return
	var near_budget = ZOMBIE_TICK_BUDGET_SCRIPT.new(0)
	var near_runs := 0
	for _tick in 6:
		if near_budget.consume(TICK, NEAR, 400.0, false, _tick) > 0.0:
			near_runs += 1
	if near_runs != 3:
		_fail(test_root, "Zumbi NEAR a 20 m deveria rodar a cada 2 ticks (3 em 6); veio %d." % near_runs)
		return
	print("PASS: Zumbi perto simula todo tick.")


func _test_far_accumulates_skipped_ticks(test_root: Node) -> void:
	ZOMBIE_TICK_BUDGET_SCRIPT.reset_frame_slots()
	print("Testando zumbi longe acumulando os ticks pulados...")
	var far_stride: int = ZOMBIE_TICK_BUDGET_SCRIPT.FAR_TICK_STRIDE
	var budget = ZOMBIE_TICK_BUDGET_SCRIPT.new(0)
	var results: Array[float] = []
	for _tick in far_stride * 2:
		results.append(budget.consume(TICK, FAR, 3600.0, false, _tick))
	var runs := results.filter(func(value: float) -> bool: return value > 0.0)
	var total := 0.0
	for value in results:
		total += value
	if runs.size() != 2 or not is_equal_approx(float(runs[0]), TICK * far_stride) or not is_equal_approx(total, TICK * far_stride * 2):
		_fail(test_root, "Zumbi FAR deveria rodar 2 vezes em %d ticks com %d ticks acumulados cada; veio %s." % [far_stride * 2, far_stride, results])
		return
	var mid_stride: int = ZOMBIE_TICK_BUDGET_SCRIPT.MID_TICK_STRIDE
	var mid = ZOMBIE_TICK_BUDGET_SCRIPT.new(0)
	var mid_runs := 0
	for _tick in mid_stride * 4:
		if mid.consume(TICK, MID, 900.0, false, _tick) > 0.0:
			mid_runs += 1
	if mid_runs != 4:
		_fail(test_root, "Zumbi MID deveria rodar 4 vezes em %d ticks; veio %d." % [mid_stride * 4, mid_runs])
		return
	print("PASS: Zumbi longe acumula os ticks pulados.")


func _test_phase_spreads_zombies_across_ticks(test_root: Node) -> void:
	ZOMBIE_TICK_BUDGET_SCRIPT.reset_frame_slots()
	print("Testando rodizio de fase entre zumbis longe...")
	var far_stride: int = ZOMBIE_TICK_BUDGET_SCRIPT.FAR_TICK_STRIDE
	var runs_per_tick: Array[int] = []
	runs_per_tick.resize(far_stride)
	for phase_seed in far_stride * 2:
		var budget = ZOMBIE_TICK_BUDGET_SCRIPT.new(phase_seed)
		for tick in far_stride:
			if budget.consume(TICK, FAR, 3600.0, false, tick) > 0.0:
				runs_per_tick[tick] += 1
	if runs_per_tick.any(func(runs: int) -> bool: return runs != 2):
		_fail(test_root, "%d zumbis FAR com fases distintas deveriam dividir 2 por tick; veio %s." % [far_stride * 2, runs_per_tick])
		return
	print("PASS: Fases espalham a horda entre os ticks.")


func _test_leap_forces_every_tick(test_root: Node) -> void:
	ZOMBIE_TICK_BUDGET_SCRIPT.reset_frame_slots()
	print("Testando bote/investida sempre simulado todo tick...")
	var budget = ZOMBIE_TICK_BUDGET_SCRIPT.new(1)
	budget.consume(TICK, FAR, 3600.0, false, 0)
	var simulated: float = budget.consume(TICK, FAR, 3600.0, true, 1)
	if not is_equal_approx(simulated, TICK * 2.0):
		_fail(test_root, "Em voo o zumbi roda no tick mesmo longe, com o tempo acumulado; veio %s." % simulated)
		return
	print("PASS: Bote simulado todo tick.")


func _test_holds_ground_only_when_planted(test_root: Node) -> void:
	print("Testando zumbi parado batendo sem move_and_slide...")
	var planted: bool = ZOMBIE_TICK_BUDGET_SCRIPT.holds_ground(true, true, false, false)
	var airborne: bool = ZOMBIE_TICK_BUDGET_SCRIPT.holds_ground(true, false, false, false)
	var leaping: bool = ZOMBIE_TICK_BUDGET_SCRIPT.holds_ground(true, true, true, false)
	var knocked: bool = ZOMBIE_TICK_BUDGET_SCRIPT.holds_ground(true, true, false, true)
	var chasing: bool = ZOMBIE_TICK_BUDGET_SCRIPT.holds_ground(false, true, false, false)
	if not planted or airborne or leaping or knocked or chasing:
		_fail(test_root, "So quem esta no chao, em alcance e sem bote/tranco fica parado; planted=%s air=%s leap=%s knock=%s chase=%s." % [planted, airborne, leaping, knocked, chasing])
		return
	print("PASS: Zumbi batendo fica parado sem deslizar.")


## 60 zumbis colados no jogador no mesmo tick: so MAX_FULL_TICKS_PER_FRAME rodam
## e ninguem espera mais que 1 + MAX_OVERLOAD_EXTRA_TICKS ticks. Na VPS a horda
## inteira convergindo no jogador levou a IA a 15-21 ms/frame (ec6aee7).
func _test_global_slots_cap_crowd_with_bounded_delay(test_root: Node) -> void:
	print("Testando teto global de ticks de zumbi com atraso limitado...")
	ZOMBIE_TICK_BUDGET_SCRIPT.reset_frame_slots()
	var cap: int = ZOMBIE_TICK_BUDGET_SCRIPT.MAX_FULL_TICKS_PER_FRAME
	var max_wait: int = 1 + ZOMBIE_TICK_BUDGET_SCRIPT.MAX_OVERLOAD_EXTRA_TICKS
	var budgets: Array = []
	for index in 60:
		budgets.append(ZOMBIE_TICK_BUDGET_SCRIPT.new(index))
	var runs_first_frame := 0
	var ran: Array[bool] = []
	ran.resize(budgets.size())
	for frame in max_wait:
		for index in budgets.size():
			if budgets[index].consume(TICK, NEAR, 4.0, false, 1000 + frame) > 0.0:
				ran[index] = true
				if frame == 0:
					runs_first_frame += 1
	var everyone_ran := not ran.has(false)
	if runs_first_frame != cap or not everyone_ran:
		_fail(test_root, "Com 60 zumbis colados o 1o tick deveria rodar %d e todos em %d ticks; rodaram %d, todos=%s." % [cap, max_wait, runs_first_frame, everyone_ran])
		return
	print("PASS: Teto global de ticks com atraso limitado.")


## Proxy do client so interpola a posicao do servidor: sem mascara de colisao
## (move_and_collide custava ate 4 ms/frame e a fisica do client 8-10 ms), olhos
## sem CSG e sombra so no torso (draw calls iam a ~6000 com a horda na tela).
func _test_proxy_is_light_for_the_client(test_root: Node) -> void:
	print("Testando proxy de zumbi leve no client...")
	var proxy: CharacterBody3D = PROXY_FACTORY_SCRIPT.instantiate_proxy(ZOMBIE_SCENE, "ZombieSpawn77", {"position": Vector3(500.0, 1.0, 500.0), "zombie_type": 0})
	test_root.add_child(proxy)
	var csg_count := proxy.find_children("*", "CSGShape3D", true, false).size()
	var shadow_casters := 0
	for node in proxy.find_children("*", "GeometryInstance3D", true, false):
		if (node as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			shadow_casters += 1
	proxy.call("apply_network_state", {"position": Vector3(502.0, 1.0, 500.0), "rotation": 0.0, "health": 100, "is_dead": false, "zombie_type": 0, "attack_sequence": 0})
	var mask := proxy.collision_mask
	proxy.free()
	if mask != 0 or csg_count != 0 or shadow_casters > 1:
		_fail(test_root, "Proxy leve esperado: mascara 0, sem CSG, no maximo 1 sombra; veio mascara=%d csg=%d sombras=%d." % [mask, csg_count, shadow_casters])
		return
	print("PASS: Proxy de zumbi leve no client.")


## Jogador que desconecta vira objeto liberado em alert_target: cada zumbi
## gerava um SCRIPT ERROR por tick (4158 no teste de carga com 600).
func _test_freed_target_is_dropped_without_errors(test_root: Node) -> void:
	print("Testando zumbi com alvo desconectado (liberado)...")
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	zombie.set("forced_variant", 11)
	test_root.add_child(zombie)
	zombie.global_position = Vector3(900.0, 50.0, 900.0)
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	test_root.add_child(player)
	zombie.set("is_cluster_leader", false)
	zombie.set("alert_target", player)
	player.free()
	zombie.call("_run_physics_tick", TICK)
	var dropped: bool = typeof(zombie.get("alert_target")) == TYPE_NIL
	zombie.free()
	await test_root.get_tree().process_frame
	if not dropped:
		_fail(test_root, "Zumbi deveria soltar o alvo liberado no tick em vez de passar objeto morto adiante.")
		return
	print("PASS: Alvo desconectado solto sem erro.")


## Duas hordas de 50 com teto de 80 zumbis por tick: a segunda so recebe
## cerebro no tick seguinte, sem refazer o agrupamento.
func _test_flock_spreads_hordes_across_ticks(test_root: Node) -> void:
	print("Testando flock aplicando hordas grandes em ticks diferentes...")
	var coordinator := FLOCK_COORDINATOR_SCRIPT.new() as Node
	test_root.add_child(coordinator)
	var first_horde := _spawn_horde(test_root, Vector3(-3000.0, 1.0, 0.0), 50)
	var second_horde := _spawn_horde(test_root, Vector3(3000.0, 1.0, 0.0), 50)
	coordinator._physics_process(0.2)
	var first_tick := [_has_brain(first_horde), _has_brain(second_horde)]
	coordinator._physics_process(0.0)
	var second_tick := [_has_brain(first_horde), _has_brain(second_horde)]
	for zombie in first_horde + second_horde:
		zombie.free()
	coordinator.free()
	await test_root.get_tree().process_frame
	if first_tick.count(true) != 1 or second_tick != [true, true]:
		_fail(test_root, "Flock deveria aplicar 1 horda por tick com teto de 80; tick1=%s tick2=%s." % [first_tick, second_tick])
		return
	print("PASS: Flock espalha hordas grandes entre ticks.")


func _spawn_horde(test_root: Node, center: Vector3, count: int) -> Array[CharacterBody3D]:
	var horde: Array[CharacterBody3D] = []
	for index in count:
		var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
		zombie.position = center + Vector3(float(index % 10), 0.0, float(index / 10))
		test_root.add_child(zombie)
		horde.append(zombie)
	return horde


func _has_brain(horde: Array[CharacterBody3D]) -> bool:
	return horde.all(func(zombie: CharacterBody3D) -> bool: return int(zombie.get("horde_id")) > 0)


func _fail(test_root: Node, message: String) -> void:
	push_error("FALHA: " + message)
	test_root.set_meta("unit_test_failed", true)
