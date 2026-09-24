# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
extends RefCounted

## Regressoes do carro dirigivel do MVP: montagem da cena, entrar/sair e o dano
## de atropelamento. Uso: DrivableCarTests.new().run(test_root)

const CAR_SCRIPT := preload("res://scripts/drivable_car.gd")
const CAR_SCENE := preload("res://scenes/drivable_car.tscn")
const CAR_BOT_SCRIPT := preload("res://scripts/car_bot_driver.gd")
const CARRO_LAB_SCENE := preload("res://labs/carro_lab.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const RUN_OVER_TARGET_SCRIPT := preload("res://scripts/test_run_over_target.gd")


func run(test_root: Node) -> void:
	_ensure_local_actions()
	_test_scene_has_wheels_and_run_over_area(test_root)
	await _test_enter_and_exit(test_root)
	await _test_exit_with_interact(test_root)
	_test_driving_input_mapping(test_root)
	_test_run_over_damage_is_speed_gated(test_root)
	_test_apply_run_over_hits_actors_not_passengers(test_root)
	_test_car_health_and_destruction(test_root)
	_test_fuel_burn_and_refuel(test_root)
	_test_team_car_never_dies_or_runs_dry(test_root)
	await _test_bot_drives_and_advances_waypoint(test_root)
	await _test_car_lab_has_bot_driving(test_root)
	_test_client_proxy_follows_snapshot(test_root)
	_test_client_proxy_ignores_bad_snapshot(test_root)
	_test_passenger_proxy_rides_the_seat(test_root)


## A vida cai com take_damage; em 0 o carro fica destruido e nao aceita motorista.
func _test_car_health_and_destruction(test_root: Node) -> void:
	print("Testando vida e destruicao do carro...")
	var car: Node = CAR_SCENE.instantiate()
	test_root.add_child(car)
	var full := int(car.get("health"))
	car.call("take_damage", 100)
	var wounded := int(car.get("health"))
	car.call("take_damage", full * 4)
	var destroyed := bool(car.get("is_destroyed"))
	var hud: String = car.call("get_car_hud_text")
	var refused := not bool(car.call("enter", test_root))
	car.free()
	if full <= 0 or wounded >= full or not destroyed or not hud.contains("DESTRUIDO") or not refused:
		_fail(test_root, "Carro deveria perder vida, destruir em 0, mostrar DESTRUIDO e recusar motorista; cheio=%d ferido=%d destruido=%s hud=%s recusou=%s." % [full, wounded, destroyed, hud, refused])
		return
	print("PASS: Carro perde vida, destroi em 0 e recusa motorista.")


## Gasolina: esvazia no HUD, nao passa do tanque e refuel respeita o teto.
func _test_fuel_burn_and_refuel(test_root: Node) -> void:
	print("Testando gasolina e reabastecimento...")
	var car: Node = CAR_SCENE.instantiate()
	test_root.add_child(car)
	car.set("fuel", 0.0)
	var empty_hud: String = car.call("get_car_hud_text")
	car.call("refuel", 40.0)
	var refilled := float(car.get("fuel"))
	car.call("refuel", 99999.0)
	var capped := float(car.get("fuel"))
	var max_fuel := float(car.get("max_fuel"))
	car.free()
	if not empty_hud.contains("Gas: 0%") or not is_equal_approx(refilled, 40.0) or not is_equal_approx(capped, max_fuel):
		_fail(test_root, "Gasolina deveria ir a 0%%, reabastecer 40 e respeitar o teto %.1f; hud=%s refilled=%.1f capped=%.1f." % [max_fuel, empty_hud, refilled, capped])
		return
	print("PASS: Gasolina esvazia, reabastece e respeita o teto do tanque.")


## Carro de base do mata-mata: lataria blindada e tanque infinito. E equipamento
## do time — perder o carro para sempre no primeiro minuto, ou ficar a pe porque
## a gasolina acabou, tirava a base do jogo sem ninguem ter decidido isso.
func _test_team_car_never_dies_or_runs_dry(test_root: Node) -> void:
	print("Testando o carro de base do mata-mata (blindado, tanque infinito)...")
	var car: Node = CAR_SCENE.instantiate()
	car.set("unlimited_fuel", true)
	car.set("indestructible", true)
	test_root.add_child(car)
	var full := int(car.get("health"))
	car.call("take_damage", full * 10)
	var health_after := int(car.get("health"))
	var destroyed := bool(car.get("is_destroyed"))
	var hud: String = car.call("get_car_hud_text")
	car.free()
	if health_after != full or destroyed:
		_fail(test_root, "Carro de base nao pode tomar dano; vida %d de %d, destruido=%s." % [health_after, full, destroyed])
		return
	if not hud.contains("blindado"):
		_fail(test_root, "O HUD do carro de base deveria dizer blindado; veio %s." % hud)
		return
	# Tanque seco nao corta o motor quando a gasolina e infinita (o carro comum corta).
	if CAR_SCRIPT.engine_is_cut(false, 1.0, 0.0, true):
		_fail(test_root, "Com tanque infinito o motor nao pode morrer com gasolina 0.")
		return
	if not CAR_SCRIPT.engine_is_cut(false, 1.0, 0.0, false):
		_fail(test_root, "O carro comum ainda tem que morrer com o tanque seco.")
		return
	if not CAR_SCRIPT.engine_is_cut(true, 1.0, 50.0, true) or not CAR_SCRIPT.engine_is_cut(false, 0.0, 50.0, true):
		_fail(test_root, "Freio e acelerador solto continuam cortando o motor, mesmo no carro de base.")
		return
	print("PASS: Carro de base ignora dano, avisa no HUD e nunca fica sem gasolina.")


## Os players de teste leem input e cobram as acoes `player_1_*` no InputMap.
## Registra uma config de teclado quando o harness ainda nao registrou.
## Uso: primeiro passo de run()
func _ensure_local_actions() -> void:
	if not InputMap.has_action("player_1_interact"):
		GameConfig.configure_local_players([{
			"device_type": "keyboard",
			"device_id": -1,
			"device_name": "Teste",
			"bindings": {},
		}])


## D tem que virar a direita e W acelerar; o Godot usa steering positivo como
## esquerda, entao o mapeamento do jogador inverte o eixo.
## Uso: registrado em run()
func _test_driving_input_mapping(test_root: Node) -> void:
	print("Testando o mapeamento das teclas de direcao...")
	var player = PLAYER_SCENE.instantiate()
	# `get_vehicle_input` so le o Input local com `reads_local_input` (o remoto usa
	# o `vehicle_input` que chegou pela rede): o teste pressiona teclas locais.
	player.set("reads_local_input", true)
	test_root.add_child(player)
	var forward := _press_axis(player, "up")
	var back := _press_axis(player, "down")
	var right := _press_axis(player, "right")
	var left := _press_axis(player, "left")
	player.free()
	var ok := float(right["steer"]) < 0.0 and float(left["steer"]) > 0.0 \
		and float(forward["throttle"]) > 0.0 and float(back["throttle"]) < 0.0
	if not ok:
		_fail(test_root, "Direcoes invertidas; D=%s A=%s W=%s S=%s." % [right, left, forward, back])
		return
	print("PASS: D vira a direita, A a esquerda, W acelera e S da re.")


## Le get_vehicle_input com uma tecla segurada. Uso: interno do teste de direcao
func _press_axis(player, action: String) -> Dictionary:
	var full := StringName(String(player.input_action_prefix) + action)
	if not InputMap.has_action(full):
		InputMap.add_action(full)
	Input.action_press(full)
	var entrada: Dictionary = player.call("get_vehicle_input")
	Input.action_release(full)
	return entrada


## Dirigindo, o tick normal retorna cedo; o E de descer e lido no handler do
## modo carro. Sem isso o jogador ficava preso no veiculo.
## Uso: registrado em run()
func _test_exit_with_interact(test_root: Node) -> void:
	print("Testando descer do carro com E...")
	var holder := Node3D.new()
	test_root.add_child(holder)
	var player = PLAYER_SCENE.instantiate()
	holder.add_child(player)
	var car: Node = CAR_SCENE.instantiate()
	holder.add_child(car)
	await test_root.get_tree().physics_frame
	player.set("reads_local_input", true)
	car.call("enter", player)
	var action := StringName(String(player.input_action_prefix) + "interact")
	Input.action_press(action)
	await test_root.get_tree().physics_frame
	Input.action_release(action)
	await test_root.get_tree().physics_frame
	var left: bool = not bool(player.call("is_driving")) and not bool(car.call("is_occupied"))
	holder.free()
	if not left:
		_fail(test_root, "E dirigindo deveria descer do carro; dirigindo=%s ocupado=%s." % [player.call("is_driving"), car.call("is_occupied")])
		return
	print("PASS: E desce do carro enquanto dirige.")


func _test_scene_has_wheels_and_run_over_area(test_root: Node) -> void:
	print("Testando a montagem do carro dirigivel...")
	var car: Node3D = CAR_SCENE.instantiate()
	var wheels := car.find_children("*", "VehicleWheel3D", true, false)
	var area := car.get_node_or_null("RunOverArea") as Area3D
	var has_seat := car.has_node("Seat")
	var has_exit := car.has_node("ExitPoint")
	# Extrai tudo antes do free: objeto liberado passa a comparar `== null`.
	var wheel_count := wheels.size()
	var has_area := area != null
	var area_mask := area.collision_mask if has_area else 0
	car.free()
	if wheel_count != 4 or not has_area or not has_seat or not has_exit:
		_fail(test_root, "Carro deveria ter 4 rodas, RunOverArea, Seat e ExitPoint; rodas=%d area=%s assento=%s saida=%s." % [wheel_count, has_area, has_seat, has_exit])
		return
	if area_mask & 4 == 0:
		_fail(test_root, "RunOverArea deveria enxergar a camada de zumbi (4); mask=%d." % area_mask)
		return
	print("PASS: Carro com 4 rodas, assento, saida e area de atropelamento.")


func _test_enter_and_exit(test_root: Node) -> void:
	print("Testando entrar e sair do carro...")
	var holder := Node3D.new()
	test_root.add_child(holder)
	var player = PLAYER_SCENE.instantiate()
	player.set("reads_local_input", false)
	holder.add_child(player)
	var car: Node3D = CAR_SCENE.instantiate()
	holder.add_child(car)
	await test_root.get_tree().physics_frame
	var entered: bool = car.call("enter", player)
	var occupied: bool = car.call("is_occupied")
	var driving: bool = player.call("is_driving")
	var seated := _seated_leg_angle(player) > 0.5
	if not entered or not occupied or not driving or not seated or not player.visible:
		_fail(test_root, "Entrar deveria ocupar o carro, sentar o boneco e mante-lo visivel; entrou=%s ocupado=%s dirigindo=%s sentado=%s visivel=%s." % [entered, occupied, driving, seated, player.visible])
		holder.free()
		return
	car.call("exit_car")
	await test_root.get_tree().physics_frame
	if car.call("is_occupied") or player.call("is_driving") or not player.visible or _seated_leg_angle(player) > 0.05:
		_fail(test_root, "Sair deveria liberar o carro e voltar o boneco a pose de pe; ocupado=%s dirigindo=%s visivel=%s perna=%.2f." % [car.call("is_occupied"), player.call("is_driving"), player.visible, _seated_leg_angle(player)])
		holder.free()
		return
	holder.free()
	print("PASS: Entrar senta o boneco visivel no assento e sair devolve ele a pose de pe.")


## Angulo da perna esquerda: positivo so na pose sentada.
## Uso: interno de _test_enter_and_exit
func _seated_leg_angle(player) -> float:
	var leg := player.get_node_or_null("Model/LeftLeg") as Node3D
	return absf(leg.rotation.x) if leg != null else 0.0


func _test_run_over_damage_is_speed_gated(test_root: Node) -> void:
	print("Testando o dano de atropelamento por velocidade...")
	var parado: int = CAR_SCRIPT.run_over_damage(0.0)
	var lento: int = CAR_SCRIPT.run_over_damage(CAR_SCRIPT.RUN_OVER_MIN_SPEED + 0.5)
	var rapido: int = CAR_SCRIPT.run_over_damage(60.0)
	if parado != 0 or lento <= 0 or rapido <= lento or rapido > CAR_SCRIPT.RUN_OVER_MAX_DAMAGE:
		_fail(test_root, "Atropelamento deveria ser 0 parado, positivo acima do corte e crescer com a velocidade; parado=%d lento=%d rapido=%d max=%d." % [parado, lento, rapido, CAR_SCRIPT.RUN_OVER_MAX_DAMAGE])
		return
	print("PASS: Atropelamento para a %.0f km/h e cresce ate %d." % [CAR_SCRIPT.RUN_OVER_MIN_SPEED, rapido])


## Atropelar vale para zumbi E para jogador (antes o carro passava por cima de
## gente sem nada acontecer), mas nunca para quem esta a bordo do proprio carro
## nem para cenario.
func _test_apply_run_over_hits_actors_not_passengers(test_root: Node) -> void:
	print("Testando atropelar zumbi e jogador, poupando passageiro e cenario...")
	var holder := Node3D.new()
	test_root.add_child(holder)
	var car: VehicleBody3D = CAR_SCENE.instantiate()
	holder.add_child(car)
	var zumbi: Node = RUN_OVER_TARGET_SCRIPT.new()
	holder.add_child(zumbi)
	var jogador: Node = RUN_OVER_TARGET_SCRIPT.new()
	jogador.set("target_group", "player")
	holder.add_child(jogador)
	var passageiro: Node = RUN_OVER_TARGET_SCRIPT.new()
	passageiro.set("target_group", "player")
	passageiro.set("riding_car", car)
	holder.add_child(passageiro)
	var parede := StaticBody3D.new()
	holder.add_child(parede)
	car.linear_velocity = Vector3(0.0, 0.0, 20.0)
	var dano_zumbi: int = car.call("apply_run_over", zumbi)
	var dano_jogador: int = car.call("apply_run_over", jogador)
	var dano_passageiro: int = car.call("apply_run_over", passageiro)
	var dano_parede: int = car.call("apply_run_over", parede)
	car.linear_velocity = Vector3.ZERO
	var dano_parado: int = car.call("apply_run_over", zumbi)
	var recebido := int(zumbi.damage_taken)
	holder.free()
	if dano_zumbi <= 0 or dano_jogador <= 0:
		_fail(test_root, "Atropelar deveria machucar zumbi e jogador em movimento; zumbi=%d jogador=%d." % [dano_zumbi, dano_jogador])
		return
	if dano_passageiro != 0:
		_fail(test_root, "Quem esta a bordo do proprio carro nao pode ser atropelado por ele; levou %d." % dano_passageiro)
		return
	if dano_parede != 0 or dano_parado != 0 or recebido != dano_zumbi:
		_fail(test_root, "Atropelar deveria ignorar cenario e carro parado; parede=%d parado=%d recebido=%d." % [dano_parede, dano_parado, recebido])
		return
	print("PASS: Atropelamento pega zumbi (%d) e jogador (%d), poupa passageiro, parede e carro parado." % [dano_zumbi, dano_jogador])


## O bot segue a rota circular: avanca o ponto ao alcancar e entrega
## volante/acelerador dentro da faixa que o carro espera.
func _test_bot_drives_and_advances_waypoint(test_root: Node) -> void:
	print("Testando o bot motorista...")
	var holder := Node3D.new()
	test_root.add_child(holder)
	var car: DrivableCar = CAR_SCENE.instantiate()
	holder.add_child(car)
	var bot: Node = CAR_BOT_SCRIPT.new()
	bot.set("car", car)
	holder.add_child(bot)
	await test_root.get_tree().physics_frame
	car.global_position = Vector3(float(bot.get("waypoint_radius")), 0.3, 0.0)
	bot.call("_physics_process", 0.016)
	var index_after := int(bot.get("_index"))
	car.global_position = Vector3.ZERO
	car.rotation.y = 0.0
	bot.call("_physics_process", 0.016)
	var entrada: Dictionary = bot.call("get_vehicle_input")
	var steer := float(entrada.get("steer", 9.0))
	var throttle := float(entrada.get("throttle", -1.0))
	holder.free()
	if index_after != 1:
		_fail(test_root, "Bot deveria avancar para o proximo ponto ao alcancar o primeiro; indice=%d." % index_after)
		return
	if steer < -1.0 or steer > 1.0 or throttle <= 0.0 or throttle > 1.0:
		_fail(test_root, "Bot deveria entregar steer em [-1,1] e throttle positivo; steer=%.2f throttle=%.2f." % [steer, throttle])
		return
	print("PASS: Bot avanca a rota e entrega volante/acelerador validos.")


## O laboratorio monta o carro ja ocupado por um bot, com a camera isometrica.
func _test_car_lab_has_bot_driving(test_root: Node) -> void:
	print("Testando o laboratorio do carro com bot...")
	var lab: Node3D = CARRO_LAB_SCENE.instantiate()
	test_root.add_child(lab)
	await test_root.get_tree().physics_frame
	var car: DrivableCar = lab.get("_car")
	var bot: Node = lab.get("_bot")
	var ocupado: bool = car != null and bool(car.call("is_occupied"))
	var dirige: bool = bot != null and car.get("driver") == bot
	lab.free()
	if not ocupado or not dirige:
		_fail(test_root, "Lab do carro deveria ter o carro ocupado pelo bot; ocupado=%s dirige=%s." % [ocupado, dirige])
		return
	print("PASS: Lab do carro monta o carro com o bot dirigindo.")


## No cliente o carro e proxy: congela a fisica e segue o transform do snapshot
## (interpolado). Regressao de "o carro sumiu no online": o proxy tem que sair do
## spawn e chegar na posicao enviada pelo servidor, mantendo o modelo visual.
## Uso: registrado em run()
func _test_client_proxy_follows_snapshot(test_root: Node) -> void:
	print("Testando o proxy do cliente seguindo o snapshot...")
	var car: DrivableCar = CAR_SCENE.instantiate()
	test_root.add_child(car)
	car.set("network_proxy", true)
	var target := Vector3(40.0, 0.0, -12.0)
	car.call("apply_network_state", {
		"position": target,
		"basis": Basis.IDENTITY,
		"health": 500,
		"fuel": 100.0,
		"destroyed": false,
	})
	car.call("apply_network_state", {
		"position": target + Vector3(0.0, 0.0, 2.0),
		"basis": Basis.IDENTITY,
	})
	car.call("_physics_process", 0.1)
	var moved: Vector3 = car.global_position
	var visual := car.get_node_or_null("Visual")
	var tem_visual: bool = visual != null and visual.get_child_count() > 0
	car.free()
	if moved.distance_to(target) > 4.0:
		_fail(test_root, "Proxy deveria seguir o snapshot (alvo %s); posicao=%s." % [target, moved])
		return
	if not tem_visual:
		_fail(test_root, "Proxy do carro deveria manter o modelo visual montado; Visual vazio.")
		return
	print("PASS: Proxy do cliente segue o snapshot e mantem o visual.")


## Regressao do "passageiro solto do carro": no cliente o proxy do passageiro
## seguia o SNAPSHOT DELE, interpolado com atraso proprio, enquanto o carro
## seguia o snapshot DELE com outro atraso (120 ms no carro contra 200 ms no
## jogador). Os dois atrasos nao batem, entao em velocidade o passageiro ficava
## metros atras do carro — quanto mais rapido, maior a sobra. O motorista nunca
## mostrou isso porque ele ja era grudado no banco antes de interpolar.
## Uso: registrado em run()
func _test_passenger_proxy_rides_the_seat(test_root: Node) -> void:
	print("Testando passageiro grudado no banco no cliente...")
	var car: DrivableCar = CAR_SCENE.instantiate()
	test_root.add_child(car)
	car.set("network_proxy", true)
	car.global_position = Vector3.ZERO
	var passenger := PLAYER_SCENE.instantiate() as CharacterBody3D
	passenger.reads_local_input = false
	passenger.is_local_controller = false
	# Proxy: e o cliente que nao simula este jogador.
	passenger.simulation_enabled = false
	test_root.add_child(passenger)
	car.call("enter_gunner", passenger)
	if not bool(passenger.call("is_riding")):
		_fail(test_root, "O jogador deveria entrar como passageiro do carro.")
		passenger.free()
		car.free()
		return
	# O carro anda 30 m; o snapshot do passageiro fica para tras de proposito,
	# como acontece de verdade quando os dois atrasos de interpolacao diferem.
	car.global_position = Vector3(30.0, 0.0, 0.0)
	passenger.call("apply_network_state", {
		"position": Vector3(24.0, 0.0, 0.0),
		"rotation": 0.0,
		"health": 100,
	})
	passenger.call("_physics_process", 0.016)
	var seat: Vector3 = car.call("gunner_seat_position")
	# A posicao e lida ANTES do free: montar a mensagem de falha depois do free
	# acessa um no liberado, e a falha vira um erro de script ilegivel em vez do
	# motivo (foi o que aconteceu ao validar este teste contra o codigo antigo).
	var landed: Vector3 = passenger.global_position
	var gap := landed.distance_to(seat)
	passenger.free()
	car.free()
	if gap > 0.05:
		_fail(test_root, "Passageiro deveria ficar no banco (%s); ficou a %.2f m dele, em %s." % [seat, gap, landed])
		return
	print("PASS: Passageiro do cliente fica no banco mesmo com o snapshot dele atrasado.")


## Snapshot corrompido (NaN/infinito ou basis degenerada) nao pode sumir com o
## proxy: vale o ultimo transform bom. Uso: registrado em run()
func _test_client_proxy_ignores_bad_snapshot(test_root: Node) -> void:
	print("Testando que o proxy ignora snapshot corrompido...")
	var car: DrivableCar = CAR_SCENE.instantiate()
	test_root.add_child(car)
	car.set("network_proxy", true)
	car.call("apply_network_state", {"position": Vector3(10.0, 0.0, 0.0), "basis": Basis.IDENTITY})
	car.call("_physics_process", 0.1)
	var good: Vector3 = car.global_position
	car.call("apply_network_state", {"position": Vector3(NAN, NAN, NAN), "basis": Basis.IDENTITY})
	car.call("apply_network_state", {"position": Vector3(9999.0, 0.0, 0.0), "basis": Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)})
	car.call("_physics_process", 0.1)
	var after: Vector3 = car.global_position
	car.free()
	if after.distance_to(good) > 1.0:
		_fail(test_root, "Snapshot corrompido deveria ser ignorado; antes=%s depois=%s." % [good, after])
		return
	print("PASS: Proxy ignora snapshot corrompido e mantem o ultimo bom.")


func _fail(test_root: Node, message: String) -> void:
	push_error("FALHA: " + message)
	test_root.set_meta("unit_test_failed", true)
