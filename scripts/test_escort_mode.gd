# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
extends RefCounted

## Modo escolta: contrato do familiar (dano, queda), a espera ate o E de um
## jogador, a rota de rua dentro do mapa, o yaw da caminhada e os desfechos.
## Uso: godot --headless --path . -- --unit-test --test-group=escort

const ESCORT_MEMBER_SCRIPT := preload("res://scripts/escort_family_member.gd")
const ESCORT_DIRECTOR_SCRIPT := preload("res://scripts/escort_director.gd")
const ESCORT_SPAWN_PROFILE_SCRIPT := preload("res://scripts/escort_spawn_profile.gd")
const ESCORT_ECONOMY_SCRIPT := preload("res://scripts/escort_economy.gd")
const ESCORT_SHOP_SCRIPT := preload("res://scripts/escort_shop.gd")
const FLOCK_COORDINATOR_SCRIPT := preload("res://scripts/zombie_flock_coordinator.gd")
const PROCEDURAL_CITY_GENERATOR := preload("res://scripts/procedural/generators/city_generator.gd")
const BUILDING_ASSEMBLER := preload("res://scripts/procedural/assemblers/building_assembler.gd")
const ESCORT_ROUTE_SCRIPT := preload("res://scripts/escort_route.gd")
const DESTRUCTIBLE_DOOR_SCRIPT := preload("res://scripts/destructible_door.gd")
const CITY_GENERATOR_SCRIPT := preload("res://scripts/city_generator.gd")
const PLAYER_SCENE := preload("res://scenes/player.tscn")

const DAMAGE_PER_PUNCH := 40
const PUNCHES_TO_FALL := 3
## Quadros de fisica para o corpo andar antes de medir a direcao.
const WALK_FRAMES := 20
## Quanto a familia pode se afastar do centro do lote para entrar na casa. E a
## diagonal esquina -> centro do lote (19,1 m) com folga: ela atravessa o
## terreno para chegar na porta, e isso e a unica saida de rua permitida.
const SHELTER_REACH := 20.0


func run(test_root: Node) -> void:
	_test_member_takes_damage_and_falls(test_root)
	_test_mission_waits_for_player_interact(test_root)
	_test_street_route_stays_inside_the_map(test_root)
	await _test_member_walks_facing_the_route(test_root)
	_test_director_declares_victory_when_all_escape(test_root)
	_test_director_declares_defeat_when_all_fall(test_root)
	_test_horde_sees_the_member_only_after_start(test_root)
	_test_local_play_activates_escort(test_root)
	_test_escort_map_keeps_the_full_city(test_root)
	_test_family_walks_in_formation(test_root)
	_test_checkpoint_indices_follow_the_route(test_root)
	await _test_member_stops_at_checkpoint(test_root)
	await _test_family_shoots_the_nearest_zombie(test_root)
	_test_escort_spawn_profile_scales_up(test_root)
	_test_exit_holds_fire(test_root)
	_test_house_segments_hold_fire(test_root)
	_test_checkpoint_waits_for_second_interact(test_root)
	_test_route_sweeps_the_horizontal_streets(test_root)
	_test_checkpoint_houses_are_spread_out(test_root)
	_test_route_only_leaves_the_street_at_the_houses(test_root)
	_test_shelter_points_follow_the_door_normal(test_root)
	_test_merchant_stays_at_the_door(test_root)
	_test_shelter_takes_the_exterior_door(test_root)
	_test_checkpoint_shuts_the_door_and_the_exit_reopens_it(test_root)
	_test_family_enters_the_house_head_on(test_root)
	_test_no_car_parked_on_the_escort_route(test_root)
	_test_escort_economy_rewards_variants(test_root)
	_test_player_money_add_and_spend(test_root)
	_test_escort_shop_purchase(test_root)
	_test_family_threads_the_doorway_in_single_file(test_root)


## Marca a falha do grupo (mesmo contrato dos outros testes: push_error sozinho
## NAO reprova o grupo, o runner le o meta unit_test_failed).
func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)


## O zumbi chama take_damage(dano, direcao, origem, atacante); apos a barra
## chegar a zero o NPC marca is_eliminated e avisa pelo sinal knocked_down.
func _test_member_takes_damage_and_falls(test_root: Node) -> void:
	var member := _new_member(test_root, "Escolta-Teste-Queda")
	var knocked_down_members: Array[EscortFamilyMember] = []
	member.knocked_down.connect(knocked_down_members.append)
	for _punch in PUNCHES_TO_FALL:
		member.take_damage(DAMAGE_PER_PUNCH, Vector3.FORWARD, "melee", null)
	if not member.is_eliminated:
		_fail(test_root, "familiar deveria cair apos %d golpes de %d" % [PUNCHES_TO_FALL, DAMAGE_PER_PUNCH])
	if knocked_down_members.is_empty():
		_fail(test_root, "queda do familiar deveria emitir knocked_down")
	if member.health != 0:
		_fail(test_root, "health deveria parar em 0, foi %d" % member.health)
	# Sem isso o corpo sobra na arvore e o proximo teste (jipe, no full suite)
	# pousa em cima dele e falha por ordem de execucao.
	member.free()


## Antes do E a familia espera; com um jogador perto apertando E a missao
## comeca e o trio recebe rota e passa a ser alvo da horda.
##
## O E e dirigido pelo caminho REAL do player (apply_network_input + limpeza do
## transiente no fim do tick, como _physics_process faz). Injetar
## interact_pressed na mao escondia o bug: o director le no _process, depois da
## limpeza, e por isso precisa do pedido latente (consume_interact_request).
func _test_mission_waits_for_player_interact(test_root: Node) -> void:
	var director := _new_director(test_root)
	var near := _spawn_interacting_player(test_root, director.point_a)
	_drive_player_tick(near, {})
	director.tick(0.016, test_root.get_tree())
	if director.mission_started:
		_fail(test_root, "missao nao deveria comecar so por ter jogador perto, sem E")
	_drive_player_tick(near, {"interact": true})
	director.tick(0.016, test_root.get_tree())
	if not director.mission_started:
		_fail(test_root, "E de um jogador perto deveria comecar a escolta no tick seguinte ao do player")
	for member in director.members:
		if member.route.is_empty():
			_fail(test_root, "familiar deveria receber rota ao comecar a missao")
		if not member.targetable:
			_fail(test_root, "familiar deveria virar alvo da horda ao comecar a missao")
	near.free()
	director.free()


## Um tick do jogador como o servidor o ve: aplica a entrada e limpa o
## transiente no fim (e o que _physics_process faz com interact_pressed).
func _drive_player_tick(player: CharacterBody3D, state: Dictionary) -> void:
	player.call("apply_network_input", state)
	player.call("_clear_transient_input")


## A rota segue linhas de rua, nunca passa do muro e cada trecho e curto o
## bastante para a sonda de desvio devolver o NPC para a rua.
func _test_street_route_stays_inside_the_map(test_root: Node) -> void:
	var director := _new_director(test_root)
	var route := director._build_zigzag_route(director.point_a, director.point_b)
	if route.is_empty():
		_fail(test_root, "rota de rua nao deveria ser vazia")
		director.free()
		return
	var limit: float = ESCORT_DIRECTOR_SCRIPT.MAP_HALF_EXTENT - ESCORT_DIRECTOR_SCRIPT.MAP_MARGIN
	var previous: Vector3 = director.point_a
	for waypoint in route:
		if absf(waypoint.x) > limit + 0.001 or absf(waypoint.z) > limit + 0.001:
			_fail(test_root, "waypoint fora do muro: %s" % waypoint)
		if previous.distance_to(waypoint) > ESCORT_DIRECTOR_SCRIPT.ROUTE_STEP + 0.001:
			_fail(test_root, "trecho maior que %s: %s -> %s" % [ESCORT_DIRECTOR_SCRIPT.ROUTE_STEP, previous, waypoint])
		previous = waypoint
	if previous.distance_to(director.point_b) > 0.001:
		_fail(test_root, "rota deveria terminar no ponto B, terminou em %s" % previous)
	director.free()


## O civil anda na direcao da FRENTE dele (-Z), nao de costas. Regressao do yaw
## invertido (atan2(x, z) em vez de atan2(-x, -z), a mesma convencao do player).
## Mede contra o waypoint (nao contra a velocidade: colisao pode empurrar).
func _test_member_walks_facing_the_route(test_root: Node) -> void:
	var director := _new_director(test_root)
	director.begin_mission()
	var member := director.members[0]
	var waypoint := member.global_position + Vector3(6.0, 0.0, 0.0)
	member.route = [waypoint] as Array[Vector3]
	member._route_index = 0
	var tree := test_root.get_tree()
	for _frame in WALK_FRAMES:
		await tree.physics_frame
	var forward := -member.global_transform.basis.z
	var to_waypoint := Vector3(waypoint.x - member.global_position.x, 0.0, waypoint.z - member.global_position.z)
	if Vector3(member.velocity.x, 0.0, member.velocity.z).length() < 0.3:
		_fail(test_root, "familiar deveria estar andando; velocidade %s" % member.velocity)
	elif to_waypoint.length() > 0.001 and forward.normalized().dot(to_waypoint.normalized()) < 0.9:
		_fail(test_root, "familiar anda de costas: frente %s contra o waypoint %s" % [forward, to_waypoint])
	director.free()


func _test_director_declares_victory_when_all_escape(test_root: Node) -> void:
	var director := _new_director(test_root)
	var emitted: Array[bool] = []
	director.escort_finished.connect(func(victory: bool) -> void: emitted.append(victory))
	director.begin_mission()
	for member in director.members:
		member.global_position = director.point_b
	director.tick(0.016, test_root.get_tree())
	if not director.finished_victory:
		_fail(test_root, "trio no ponto B deveria declarar vitoria")
	if director.finished_defeat:
		_fail(test_root, "vitoria nao deveria abrir derrota")
	if emitted != [true]:
		_fail(test_root, "vitoria deveria emitir escort_finished(true); veio %s" % emitted)
	director.free()


func _test_director_declares_defeat_when_all_fall(test_root: Node) -> void:
	var director := _new_director(test_root)
	var emitted: Array[bool] = []
	director.escort_finished.connect(func(victory: bool) -> void: emitted.append(victory))
	director.begin_mission()
	for member in director.members:
		# A familia nasce imortal no modo teste (EscortDirector.TEST_INVULNERABLE);
		# a derrota so pode ser testada com o dano valendo de novo.
		member.invulnerable = false
		for _punch in PUNCHES_TO_FALL:
			member.take_damage(DAMAGE_PER_PUNCH, Vector3.FORWARD, "melee", null)
	director.tick(0.016, test_root.get_tree())
	if not director.finished_defeat:
		_fail(test_root, "familia inteira morta deveria declarar derrota")
	if director.living_count() != 0:
		_fail(test_root, "apos a derrota ninguem deveria restar vivo, restaram %d" % director.living_count())
	if emitted != [false]:
		_fail(test_root, "derrota deveria emitir escort_finished(false); veio %s" % emitted)
	director.free()


## A horda so enxerga o familiar depois do inicio (targetable) e para de
## cacar quem ja escapou pelo ponto B.
func _test_horde_sees_the_member_only_after_start(test_root: Node) -> void:
	var tree := test_root.get_tree()
	var member := _new_member(test_root, "Escolta-Horda")
	if FLOCK_COORDINATOR_SCRIPT.get_living_players(tree).has(member):
		_fail(test_root, "familiar em espera nao deveria ser alvo da horda")
	member.targetable = true
	if not FLOCK_COORDINATOR_SCRIPT.get_living_players(tree).has(member):
		_fail(test_root, "familiar com missao iniciada deveria ser alvo da horda")
	member.escaped = true
	if FLOCK_COORDINATOR_SCRIPT.get_living_players(tree).has(member):
		_fail(test_root, "familiar escapado deveria sair da lista da horda")
	member.free()


## Armadilha do fluxo local: leave_session() re-reseta o modo pelos argumentos
## da linha de comando, entao ligar a escolta ANTES dele a apagaria e o "Jogar
## local" cairia na sobrevivencia (foi o bug visto na janela).
func _test_local_play_activates_escort(test_root: Node) -> void:
	var session := NetworkSession
	var saved_escort: bool = session.escort_mode
	var saved_survival: bool = session.survival_mode
	var saved_pvp: bool = session.pvp_mode
	var saved_bots: int = session.pvp_bots_override
	session.activate_local_escort_mode()
	session.leave_session()
	if session.escort_mode:
		_fail(test_root, "leave_session deveria re-resetar o modo: a escolta tem que ser ligada depois dele")
	session.leave_session()
	session.activate_local_escort_mode()
	if not session.escort_mode:
		_fail(test_root, "Jogar local deveria terminar com a escolta ligada")
	if session.survival_mode:
		_fail(test_root, "Jogar local na escolta nao pode continuar na sobrevivencia")
	session.activate_local_pvp_mode(4)
	if not session.pvp_mode or session.escort_mode or session.survival_mode:
		_fail(test_root, "PvP local deveria ligar so o pvp")
	if session.pvp_bots_override != 4:
		_fail(test_root, "PvP local deveria pedir 4 bots, pediu %d" % session.pvp_bots_override)
	session.activate_local_survival_mode()
	if not session.survival_mode or session.pvp_mode or session.escort_mode:
		_fail(test_root, "Sobrevivencia local deveria ligar so o survival")
	session.escort_mode = saved_escort
	session.survival_mode = saved_survival
	session.pvp_mode = saved_pvp
	session.pvp_bots_override = saved_bots


## Mapa do modo: a escolta usa a cidade 3x3 INTEIRA (o zig-zag atravessa o mapa
## todo), mas reserva o lote da safehouse de chegada (EscortRoute.SAFEHOUSE_LOT), no fim da ultima fileira.
func _test_escort_map_keeps_the_full_city(test_root: Node) -> void:
	var escort = PROCEDURAL_CITY_GENERATOR.generate_world(240912, false, false, true)
	var city = PROCEDURAL_CITY_GENERATOR.generate_world(240912)
	if escort.blocks.size() != city.blocks.size():
		_fail(test_root, "escolta deveria usar a cidade inteira (%d quarteiroes), veio %d" % [city.blocks.size(), escort.blocks.size()])
	# O lote da ponta leste (58.5, 10.5) tem que estar reservado (sem predio):
	# e onde a safehouse da escolta e construida.
	var reserved_found := false
	for block in escort.blocks:
		for lot in block.lots:
			if (lot.position as Vector2).distance_to(ESCORT_ROUTE_SCRIPT.SAFEHOUSE_LOT) < 0.5:
				reserved_found = true
				if lot.building != null:
					_fail(test_root, "lote da safehouse deveria estar vazio; tem predio")
	if not reserved_found:
		_fail(test_root, "escolta deveria reservar o lote da safehouse em %s" % ESCORT_ROUTE_SCRIPT.SAFEHOUSE_LOT)


## O trio vai espalhado (deslocamento lateral distinto por vaga) e o offset e
## perpendicular ao rumo, senao continua fila indiana.
func _test_family_walks_in_formation(test_root: Node) -> void:
	var director := _new_director(test_root)
	var offsets: Array[float] = []
	for member in director.members:
		offsets.append(member.formation_offset)
	if offsets.size() != ESCORT_DIRECTOR_SCRIPT.FAMILY_SIZE:
		_fail(test_root, "familia deveria ter %d membros, tem %d" % [ESCORT_DIRECTOR_SCRIPT.FAMILY_SIZE, offsets.size()])
	elif absf(offsets[0] - offsets[1]) < 0.5 or absf(offsets[1] - offsets[2]) < 0.5:
		_fail(test_root, "vagas da formacao deveriam ser distintas; veio %s" % [offsets])
	var member := director.members[2]
	var side := member._lateral_offset(Vector3(1.0, 0.0, 0.0))
	if absf(side.dot(Vector2(1.0, 0.0))) > 0.05:
		_fail(test_root, "offset lateral deveria ser perpendicular ao rumo; veio %s" % side)
	director.free()


## Checkpoints da serpentina: um indice de parada por PONTA de fileira, na ordem
## da rota e dentro dela (a partida, as viradas de subida e a porta da base NAO
## sao checkpoints).
func _test_checkpoint_indices_follow_the_route(test_root: Node) -> void:
	var director := _new_director(test_root)
	var route := director._build_zigzag_route(director.point_a, director.point_b)
	var expected_stops: int = ESCORT_ROUTE_SCRIPT.checkpoint_corners().size()
	if director.checkpoint_indices.size() != expected_stops:
		_fail(test_root, "serpentina deveria ter %d checkpoints (uma casa por ponta de fileira), tem %d" % [expected_stops, director.checkpoint_indices.size()])
	var previous := -1
	for waypoint_index in director.checkpoint_indices:
		if waypoint_index <= previous:
			_fail(test_root, "indices de checkpoint fora de ordem: %s" % director.checkpoint_indices)
		if waypoint_index >= route.size():
			_fail(test_root, "checkpoint %d fora da rota (%d waypoints)" % [waypoint_index, route.size()])
		previous = waypoint_index
	director.free()


## O civil para no waypoint do checkpoint e nao segue ate o proximo trecho.
func _test_member_stops_at_checkpoint(test_root: Node) -> void:
	var member := _new_member(test_root, "Escolta-Para-Checkpoint")
	var start := Vector3(0.0, 1.0, 0.0)
	member.global_position = start
	var corner := start + Vector3(5.0, 0.0, 0.0)
	var beyond := corner + Vector3(50.0, 0.0, 0.0)
	member.route = [corner, beyond] as Array[Vector3]
	member._route_index = 0
	member.halt_route_index = 0
	member.walking = true
	var tree := test_root.get_tree()
	for _frame in WALK_FRAMES * 8:
		await tree.physics_frame
	if not member.has_reached_halt():
		_fail(test_root, "familiar deveria ter chegado no checkpoint; waypoint %d" % member._route_index)
	elif member.global_position.distance_to(beyond) < 30.0:
		_fail(test_root, "familiar passou do checkpoint e foi alem dele")
	member.free()


## Horda progressiva por trecho: teto proporcional 50, 80, 110, 140, 170, 200,
## mix por fase somando 100 e sorteio sempre dentro do mix. O diretor segue o
## checkpoint.
func _test_escort_spawn_profile_scales_up(test_root: Node) -> void:
	var phases: Array = ESCORT_SPAWN_PROFILE_SCRIPT.PHASES
	if phases.size() != 4:
		_fail(test_root, "perfil deveria ter 4 fases de mix/intervalo, tem %d" % phases.size())
		return
	for index in phases.size():
		var phase: Dictionary = phases[index]
		var mix: Dictionary = phase["mix"]
		var total := 0
		for kind in mix:
			total += int(mix[kind])
		if total != 100:
			_fail(test_root, "mix da fase %d deveria somar 100, soma %d" % [index, total])
		# Uma fase por trecho: o trecho N cai na fase N (ver phase_index).
		var cleared := index
		for roll in 100:
			var variant: int = ESCORT_SPAWN_PROFILE_SCRIPT.pick_variant(cleared, roll)
			if not mix.has(variant):
				_fail(test_root, "variante %d fora do mix da fase %d" % [variant, index])
	# Uma fase por trecho: com 3 casas sao 4 trechos e as 4 fases entram todas.
	var legs: int = ESCORT_SPAWN_PROFILE_SCRIPT.leg_count()
	if legs != ESCORT_ROUTE_SCRIPT.checkpoint_corners().size() + 1:
		_fail(test_root, "os trechos tem de acompanhar as casas da rota; veio %d" % legs)
	for cleared in legs:
		if ESCORT_SPAWN_PROFILE_SCRIPT.phase_index(cleared) != mini(cleared, phases.size() - 1):
			_fail(test_root, "trecho %d deveria cair na fase %d" % [cleared, mini(cleared, phases.size() - 1)])
	# Teto proporcional: 50 no primeiro trecho ate 200 no ultimo.
	var expected_caps: Array[int] = [50, 100, 150, 200]
	for leg in expected_caps.size():
		if ESCORT_SPAWN_PROFILE_SCRIPT.cap_for_leg(leg) != expected_caps[leg]:
			_fail(test_root, "trecho %d deveria ter teto %d, veio %d" % [leg + 1, expected_caps[leg], ESCORT_SPAWN_PROFILE_SCRIPT.cap_for_leg(leg)])
	if ESCORT_SPAWN_PROFILE_SCRIPT.cap_for_leg(legs + 2) != 200:
		_fail(test_root, "passado o ultimo trecho o teto deveria continuar 200")
	var director := _new_director(test_root)
	if int(director.spawn_profile()["cap"]) != 50:
		_fail(test_root, "no inicio o teto deveria ser 50, veio %d" % int(director.spawn_profile()["cap"]))
	director.next_checkpoint = legs - 1
	if int(director.spawn_profile()["cap"]) != 200:
		_fail(test_root, "no ultimo trecho o teto deveria ser 200")
	director.free()


## Ao sair da casa o civil segura o tiro por um tempo (so anda) para nao voltar
## pra dentro e atirar de la; na largada ele pode atirar normalmente.
func _test_exit_holds_fire(test_root: Node) -> void:
	var director := _new_director(test_root)
	director.begin_mission()
	var member = director.members[0]
	if member.hold_fire_seconds > 0.0:
		_fail(test_root, "na largada o civil deveria poder atirar")
	director._release_checkpoint()
	if member.hold_fire_seconds <= 0.0:
		_fail(test_root, "sair da casa deveria segurar o tiro por um tempo")
	director.free()


## Com parada em cada checkpoint, o trecho de parada E o de saida ficam sem
## tiro: esperando o civil e passivo e, liberado, a prioridade e sair andando.
func _test_house_segments_hold_fire(test_root: Node) -> void:
	var director := _new_director(test_root)
	var sites: Array[Dictionary] = []
	for corner in director._escort_checkpoint_corners():
		sites.append(director._shelter_geometry(Vector2(corner.x - 12.0, corner.z + 12.0), corner))
	director._shelter_sites = sites
	director.begin_mission()
	var expected_passive := ESCORT_ROUTE_SCRIPT.checkpoint_corners().size() * 3
	if director.no_fire_route_indices.size() != expected_passive:
		_fail(test_root, "cada casa deveria marcar 3 trechos passivos (parada + os dois da saida); veio %d de %d" % [director.no_fire_route_indices.size(), expected_passive])
	for member in director.members:
		if member.no_fire_indices.size() != expected_passive:
			_fail(test_root, "familiar deveria receber os %d indices passivos, tem %d" % [expected_passive, member.no_fire_indices.size()])
	var inside_index: int = director.checkpoint_indices[0]
	if not director.members[0].no_fire_indices.has(inside_index):
		_fail(test_root, "a parada dentro da casa deveria ser passiva")
	if not director.members[0].no_fire_indices.has(inside_index + 1):
		_fail(test_root, "a saida da casa deveria ser passiva")
	director.free()


## Chegou na esquina: para e liga a zona segura; so um NOVO E libera o proximo
## trecho (e o halt avanca para o checkpoint seguinte).
func _test_checkpoint_waits_for_second_interact(test_root: Node) -> void:
	var director := _new_director(test_root)
	director.begin_mission()
	var tree := test_root.get_tree()
	var player := _spawn_interacting_player(test_root, director.point_a)
	for member in director.members:
		member._route_index = member.halt_route_index + 1
	director.tick(0.016, tree)
	if not director.waiting_at_checkpoint:
		_fail(test_root, "todos no checkpoint deveriam parar a familia e abrir a zona segura")
	if director.allows_spawns():
		_fail(test_root, "familia parada no checkpoint nao deveria deixar a horda spawnar")
	for member in director.members:
		if member.walking:
			_fail(test_root, "familiar deveria estar parado no checkpoint")
	var halted: int = director.members[0].halt_route_index
	_drive_player_tick(player, {"interact": true})
	director.tick(0.016, tree)
	if director.waiting_at_checkpoint:
		_fail(test_root, "E do jogador na zona deveria liberar o checkpoint")
	if director.members[0].halt_route_index == halted:
		_fail(test_root, "halt deveria avancar para o checkpoint seguinte")
	if not director.members[0].walking:
		_fail(test_root, "familiar deveria voltar a andar depois do E")
	if not director.allows_spawns():
		_fail(test_root, "andando depois do E a horda deveria poder spawnar de novo")
	player.free()
	director.free()


## A familia anda armada (pistola do player, municao infinita): com um zumbi na
## frente e linha livre, o alvo toma dano de tiro.
func _test_family_shoots_the_nearest_zombie(test_root: Node) -> void:
	var member := _new_member(test_root, "Escolta-Atira")
	member.global_position = Vector3(0.0, 1.0, 0.0)
	# Andando (com rota vazia, fica parado) e sem trecho passivo: pode engajar.
	member.walking = true
	var target := _FakeZombieTarget.new()
	target.add_to_group("zombies")
	target.collision_layer = 4
	target.collision_mask = 0
	target.position = Vector3(6.0, 1.0, 0.0)
	test_root.add_child(target)
	var tree := test_root.get_tree()
	for _frame in WALK_FRAMES * 2:
		await tree.physics_frame
	if target.damage_taken < ESCORT_MEMBER_SCRIPT.SHOOT_DAMAGE:
		_fail(test_root, "familiar armado deveria ter atirado no zumbi a frente; dano %d" % target.damage_taken)
	target.free()
	member.free()


## Zumbi de mentira para a regressao do tiro: so o contrato que o hitscan usa
## (CollisionObject3D na camada de zumbi + take_damage).
class _FakeZombieTarget extends StaticBody3D:
	var health := 100
	var is_dead := false
	var damage_taken := 0

	func _init() -> void:
		var collision := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.4
		capsule.height = 1.6
		collision.shape = capsule
		collision.position = Vector3(0.0, 0.8, 0.0)
		add_child(collision)

	func take_damage(amount: int, _direction: Vector3, _kind: String = "bullet", _source: Node = null, _hit_position: Vector3 = Vector3.INF) -> void:
		damage_taken += amount
		health = maxi(health - amount, 0)
		if health <= 0:
			is_dead = true


## Zigue-zague HORIZONTAL: a familia anda uma rua horizontal inteira, sobe uma
## rua e volta pela horizontal seguinte. Entao toda perna segue uma rua e as
## QUATRO horizontais sao andadas de ponta a ponta.
func _test_route_sweeps_the_horizontal_streets(test_root: Node) -> void:
	var stops: Array[Vector3] = [ESCORT_DIRECTOR_SCRIPT.ESCORT_START]
	stops.append_array(ESCORT_ROUTE_SCRIPT.route_corners())
	# A ultima fileira termina na base, que se entra pela rua de cima (porta +Z).
	stops.append_array(ESCORT_DIRECTOR_SCRIPT.final_street_approach(
		stops[stops.size() - 1], Vector3(-58.5, 1.0, 67.25), Vector3.BACK
	))
	var walked := {}
	for index in range(1, stops.size()):
		var street := _street_of_leg(stops[index - 1], stops[index])
		if street.is_empty():
			_fail(test_root, "perna %s -> %s nao anda por nenhuma rua" % [stops[index - 1], stops[index]])
			continue
		walked[street] = true
	for line in ESCORT_ROUTE_SCRIPT.ROAD_LINES:
		var street := "z=%s" % line
		if not walked.has(street):
			_fail(test_root, "a fileira %s nunca e andada; a rota cobriu %s" % [street, walked.keys()])


## O que o usuario reclamou em 2026-09-28: "eles entram em 2 casas quase na
## mesma esquina". A serpentina vertical punha duas paradas na mesma rua
## horizontal, a 48 m uma da outra. Uma casa por PONTA de fileira, e pronto.
func _test_checkpoint_houses_are_spread_out(test_root: Node) -> void:
	var corners := ESCORT_ROUTE_SCRIPT.checkpoint_corners()
	for index in range(1, corners.size()):
		var gap: float = (corners[index] as Vector3).distance_to(corners[index - 1])
		if gap < 100.0:
			_fail(test_root, "casas %d e %d ficam a %.0f m uma da outra (%s e %s); tem de ser uma por ponta de fileira" % [index, index + 1, gap, corners[index - 1], corners[index]])


## Nome da rua que uma perna percorre ("x=24"), ou "" se ela nao segue rua
## nenhuma (perna na diagonal ou por cima dos lotes). Uso: interno dos testes.
func _street_of_leg(from: Vector3, to: Vector3) -> String:
	var lines: Array = ESCORT_ROUTE_SCRIPT.ROAD_LINES
	if is_equal_approx(from.x, to.x) and not is_equal_approx(from.z, to.z):
		for line in lines:
			if absf(from.x - float(line)) < 0.01:
				return "x=%s" % line
	if is_equal_approx(from.z, to.z) and not is_equal_approx(from.x, to.x):
		for line in lines:
			if absf(from.z - float(line)) < 0.01:
				return "z=%s" % line
	return ""


## A rota so pode sair do asfalto para entrar na casa do checkpoint. Regressao:
## a rota antiga saia da casa direto para a esquina seguinte e cortava metade do
## mapa por cima dos lotes (493 m dos 860 m fora de rua, medido em 2026-09-28).
func _test_route_only_leaves_the_street_at_the_houses(test_root: Node) -> void:
	var director := _new_director(test_root)
	director._shelter_sites = _fake_shelter_sites()
	director._route_via = Vector3(58.5, 1.0, 19.25)
	director.point_b = Vector3(58.5, 1.0, 12.25)
	var route := director._build_zigzag_route(ESCORT_DIRECTOR_SCRIPT.ESCORT_START, director.point_b)
	var previous: Vector3 = ESCORT_DIRECTOR_SCRIPT.ESCORT_START
	var worst := 0.0
	var worst_point := Vector3.ZERO
	for waypoint in route:
		var samples := maxi(1, int(previous.distance_to(waypoint)))
		for step in samples + 1:
			var point := previous.lerp(waypoint, float(step) / float(samples))
			var slack := _distance_off_street(point)
			if slack > worst:
				worst = slack
				worst_point = point
		previous = waypoint
	if worst > 0.01:
		_fail(test_root, "rota anda %.1f m fora da rua e longe das casas (pior ponto %s)" % [worst, worst_point])
	director.free()


## Quanto um ponto esta fora do asfalto E longe da casa de algum checkpoint;
## zero quando ele esta na rua ou dentro do raio da parada. Uso: interno.
func _distance_off_street(point: Vector3) -> float:
	for line in ESCORT_ROUTE_SCRIPT.ROAD_LINES:
		if absf(point.x - float(line)) <= ESCORT_ROUTE_SCRIPT.ROAD_HALF_WIDTH:
			return 0.0
		if absf(point.z - float(line)) <= ESCORT_ROUTE_SCRIPT.ROAD_HALF_WIDTH:
			return 0.0
	var closest := INF
	var houses: Array[Vector2] = ESCORT_ROUTE_SCRIPT.checkpoint_lot_centers()
	# A safehouse de chegada conta como casa: a ultima perna entra nela.
	houses.append(ESCORT_ROUTE_SCRIPT.SAFEHOUSE_LOT)
	for center in houses:
		closest = minf(closest, Vector2(point.x - center.x, point.z - center.y).length())
	return maxf(0.0, closest - SHELTER_REACH)


## Paradas falsas: uma por checkpoint, com a porta no centro do lote virada para
## a esquina. Dispensa a cidade montada (o teste roda sem cena).
func _fake_shelter_sites() -> Array[Dictionary]:
	var sites: Array[Dictionary] = []
	var corners := ESCORT_ROUTE_SCRIPT.checkpoint_corners()
	var centers := ESCORT_ROUTE_SCRIPT.checkpoint_lot_centers()
	for index in corners.size():
		var center := Vector3(centers[index].x, 1.0, centers[index].y)
		var to_corner := corners[index] - center
		# Porta de predio procedural e sempre no eixo da parede, nunca diagonal.
		var normal := Vector3(signf(to_corner.x), 0.0, 0.0) if absf(to_corner.x) >= absf(to_corner.z) else Vector3(0.0, 0.0, signf(to_corner.z))
		sites.append(ESCORT_DIRECTOR_SCRIPT.shelter_points(center, normal, corners[index]))
	return sites


## A frente da casa sai da NORMAL DA PAREDE da porta, nao da direcao porta ->
## esquina: com a porta de lado a direcao antiga jogava o "approach" na parede.
func _test_shelter_points_follow_the_door_normal(test_root: Node) -> void:
	var door := Vector3(58.5, 1.0, -49.0)
	var corner := Vector3(72.0, 1.0, -24.0)
	var site := ESCORT_DIRECTOR_SCRIPT.shelter_points(door, Vector3.BACK, corner)
	var approach: Vector3 = site["approach"]
	var inside: Vector3 = site["inside"]
	if not is_equal_approx(approach.x, door.x) or approach.z <= door.z:
		_fail(test_root, "approach deveria sair pela normal (+Z) da porta %s, veio %s" % [door, approach])
	if not is_equal_approx(inside.x, door.x) or inside.z >= door.z:
		_fail(test_root, "inside deveria entrar contra a normal da porta, veio %s" % inside)
	# Normal apontando para dentro: a funcao vira ela para o lado da esquina.
	var flipped := ESCORT_DIRECTOR_SCRIPT.shelter_points(door, Vector3.FORWARD, corner)
	if (flipped["approach"] as Vector3).z <= door.z:
		_fail(test_root, "normal ao contrario deveria ser virada para a esquina, veio %s" % flipped["approach"])


## O mercador fica na calcada em frente a porta, deslocado de lado: visivel e
## alcancavel de fora. Regressao de "mercador dentro da casa".
func _test_merchant_stays_at_the_door(test_root: Node) -> void:
	var door := Vector3(0.0, 1.0, 0.0)
	var corner := Vector3(0.0, 1.0, 24.0)
	var site := ESCORT_DIRECTOR_SCRIPT.shelter_points(door, Vector3.BACK, corner)
	var spot := ESCORT_DIRECTOR_SCRIPT.merchant_spot(site)
	var approach: Vector3 = site["approach"]
	var outward: Vector3 = site["door_direction"]
	var lateral := Vector3(-outward.z, 0.0, outward.x)
	var in_front := (spot - door).dot(outward) > 0.0
	var beside_door := absf((spot - approach).dot(lateral)) > 1.0
	var not_blocking := absf((spot - approach).dot(outward)) < 0.01
	if not in_front or not beside_door or not not_blocking:
		_fail(test_root, "mercador deveria ficar na calcada ao lado da porta; spot=%s approach=%s" % [spot, approach])


## A parada usa a porta DA RUA. O predio procedural cria porta destrutivel para
## todo vao da planta, inclusive quarto e estoque, e a porta interna fica mais
## perto do centro do lote: sem filtrar, a familia era mandada para dentro de um
## comodo (medido em 2026-09-28: 6 de 6 checkpoints pegaram porta interna).
func _test_shelter_takes_the_exterior_door(test_root: Node) -> void:
	var building := StaticBody3D.new()
	building.name = "PredioDoCheckpoint"
	test_root.add_child(building)
	var lot := Vector3(58.5, 0.0, -58.5)
	var corner := Vector3(72.0, 1.0, -72.0)
	# Interna bem no centro do lote; externa na fachada, mais longe do centro.
	BUILDING_ASSEMBLER._add_door(building, {"room_a": "sala", "room_b": "quarto", "axis": "horizontal", "center": Vector2(0.0, 0.0), "width": 1.4}, "horizontal", 0.0, 0.0, Vector2(lot.x, lot.z), 0.0, null, "Door_interna")
	BUILDING_ASSEMBLER._add_door(building, {"room_a": "sala", "room_b": "outside", "axis": "horizontal", "center": Vector2(0.0, 0.0), "width": 1.6}, "horizontal", -6.0, 0.0, Vector2(lot.x, lot.z), 0.0, null, "Door_rua")
	var director := _new_director(test_root)
	var found := director._nearest_shelter_door(test_root.get_tree(), lot, ESCORT_DIRECTOR_SCRIPT.SHELTER_FIND_RADIUS, corner)
	if found == null:
		_fail(test_root, "deveria achar a porta da rua do predio do checkpoint")
	elif String(found.name) != "Door_rua":
		_fail(test_root, "parada deveria usar a porta da rua, usou %s" % found.name)
	director.free()
	building.free()


## Com a familia toda dentro, a casa vira abrigo de verdade: a porta FECHA, e
## so o E que libera o checkpoint reabre. A reabertura tem de acontecer na mesma
## chamada que manda andar: se o civil sair andando contra a folha fechada, o
## vigia de progresso estoura em RESCUE_SECONDS e ele e teleportado (relato de
## 2026-09-28: "ficam presos e depois teleportavam").
func _test_checkpoint_shuts_the_door_and_the_exit_reopens_it(test_root: Node) -> void:
	var director := _new_director(test_root)
	var sites: Array[Dictionary] = []
	for corner in director._escort_checkpoint_corners():
		sites.append(director._shelter_geometry(Vector2(corner.x - 12.0, corner.z + 12.0), corner))
	var door := _new_shelter_door(test_root, sites[0]["approach"])
	sites[0]["door"] = door
	director._shelter_sites = sites
	director.begin_mission()
	var tree := test_root.get_tree()
	var player := _spawn_interacting_player(test_root, director.point_a)
	for member in director.members:
		member._route_index = member.halt_route_index + 1
	director.tick(0.016, tree)
	if not director.waiting_at_checkpoint:
		_fail(test_root, "a familia inteira na parada deveria abrir a zona segura")
	if door.is_open:
		_fail(test_root, "porta da casa deveria fechar com a familia toda dentro")
	_drive_player_tick(player, {"interact": true})
	director.tick(0.016, tree)
	if not door.is_open:
		_fail(test_root, "o E da saida deveria reabrir a porta da casa")
	for member in director.members:
		if not member.walking:
			_fail(test_root, "familiar deveria sair andando junto com a porta aberta")
	# Porta arrombada pela horda nao volta a fechar nem trava a parada.
	var broken := _new_shelter_door(test_root, sites[1]["approach"])
	broken.is_destroyed = true
	broken.is_open = true
	broken.close_for()
	if not broken.is_open:
		_fail(test_root, "porta arrombada nao deveria fechar (o vao ja nao existe)")
	director.free()
	door.free()
	broken.free()
	player.free()


## Porta de verdade para a parada de um checkpoint, ja aberta como fica quando a
## familia entra. Uso: var porta := _new_shelter_door(test_root, ponto)
func _new_shelter_door(parent: Node, at: Vector3) -> DestructibleDoor:
	var door := DESTRUCTIBLE_DOOR_SCRIPT.new() as DestructibleDoor
	door.name = "PortaDaParada%d" % parent.get_child_count()
	door.configure(Vector3(1.6, 2.1, 0.2), null)
	parent.add_child(door)
	door.global_position = at
	door.is_open = true
	return door


## A familia entra de frente no vao: o ponto de rua, a calcada e o ponto de
## espera ficam na MESMA reta, a normal da porta, e a ultima perna e reta.
## Regressao medida em 2026-09-28 no checkpoint 2: com a perna final na diagonal
## o civil raspava a fachada ao lado do vao, o desvio de parede o levava
## rodeando o predio por 9 s e o resgate acabava teleportando ele para dentro.
func _test_family_enters_the_house_head_on(test_root: Node) -> void:
	var door := Vector3(-30.5, 1.0, 55.3)
	var site := ESCORT_DIRECTOR_SCRIPT.shelter_points(door, Vector3.RIGHT, Vector3(-24.0, 1.0, 72.0))
	var far: Vector3 = site["approach_far"]
	var near: Vector3 = site["approach"]
	var inside: Vector3 = site["inside"]
	for point in [far, near, inside]:
		if absf((point as Vector3).z - door.z) > 0.01:
			_fail(test_root, "ponto da parada saiu da reta da porta: %s" % point)
	if not (far.x > near.x and near.x > door.x and inside.x < door.x):
		_fail(test_root, "ordem deveria ser rua -> calcada -> porta -> dentro: %s %s %s" % [far, near, inside])
	if far.distance_to(near) < 3.0:
		_fail(test_root, "o ponto de rua tem de ficar longe da fachada para a perna final ser reta; veio %.1f m" % far.distance_to(near))
	var director := _new_director(test_root)
	director._shelter_sites = _fake_shelter_sites()
	var route := director._build_zigzag_route(ESCORT_DIRECTOR_SCRIPT.ESCORT_START, director.point_b)
	var halt: int = director.checkpoint_indices[0]
	var entry := route[halt] - route[halt - 1]
	if absf(entry.x) > 0.01 and absf(entry.z) > 0.01:
		_fail(test_root, "a entrada no vao deveria ser reta no eixo da porta, veio %s" % entry)
	director.free()


## Carro nenhum pode ficar parado no corredor que a familia anda: o civil encosta
## no RigidBody, o desvio de parede o manda rodear e ele volta pela rota (medido
## em 2026-09-28: carro em (-24, 18) travou os tres e os tres teleportaram).
## O resto do mapa continua com carro, que e o que o jogador dirige.
func _test_no_car_parked_on_the_escort_route(test_root: Node) -> void:
	var parked: Array[Vector3] = []
	parked.append_array(CITY_GENERATOR_SCRIPT.car_spots_for_escort(CITY_GENERATOR_SCRIPT.ABANDONED_CAR_SPOTS))
	parked.append_array(CITY_GENERATOR_SCRIPT.car_spots_for_escort(CITY_GENERATOR_SCRIPT.ESCORT_DRIVABLE_CAR_SPOTS))
	if parked.size() < 6:
		_fail(test_root, "a escolta deveria manter carro no mapa fora do corredor; sobraram %d" % parked.size())
	for spot in parked:
		var gap: float = ESCORT_ROUTE_SCRIPT.distance_to_street_spine(spot)
		if gap < ESCORT_ROUTE_SCRIPT.CAR_CLEARANCE:
			_fail(test_root, "carro em %s fica a %.1f m da rota (minimo %s)" % [spot, gap, ESCORT_ROUTE_SCRIPT.CAR_CLEARANCE])
	# E o carro dirigivel da escolta tem de continuar perto de onde o grupo nasce.
	var start: Vector3 = ESCORT_DIRECTOR_SCRIPT.ESCORT_START
	var closest := INF
	for spot in CITY_GENERATOR_SCRIPT.ESCORT_DRIVABLE_CAR_SPOTS:
		closest = minf(closest, (spot as Vector3).distance_to(start))
	if closest > 40.0:
		_fail(test_root, "carro dirigivel da escolta ficou a %.0f m do nascimento; longe demais para servir" % closest)


## No funil da porta (os 5 pontos da parada) o civil anda em FILA e so troca de
## waypoint quando chega de verdade. Regressao medida em 2026-09-28: com a vaga
## lateral de 1,2 m e a chegada larga de 2 m, o civil dava o waypoint por
## alcancado ainda torto, entrava no vao na diagonal, raspava a ombreira e
## acabava teleportado pelo resgate.
func _test_family_threads_the_doorway_in_single_file(test_root: Node) -> void:
	var director := _new_director(test_root)
	director._shelter_sites = _fake_shelter_sites()
	director.begin_mission()
	var expected := ESCORT_ROUTE_SCRIPT.checkpoint_corners().size() * 5
	if director.funnel_route_indices.size() != expected:
		_fail(test_root, "cada casa deveria marcar 5 pontos de funil; veio %d de %d" % [director.funnel_route_indices.size(), expected])
	var member := director.members[0]
	if member.funnel_indices.size() != expected:
		_fail(test_root, "familiar deveria receber os %d indices de funil, tem %d" % [expected, member.funnel_indices.size()])
	member._route_index = director.checkpoint_indices[0]
	if not is_zero_approx(member._formation_scale()):
		_fail(test_root, "no funil o trio deveria andar em fila (formacao 0), veio %s" % member._formation_scale())
	if member._arrive_radius() >= ESCORT_MEMBER_SCRIPT.ARRIVE_RADIUS:
		_fail(test_root, "no funil a chegada deveria ser apertada, veio %s" % member._arrive_radius())
	member._route_index = 0
	if not is_equal_approx(member._arrive_radius(), ESCORT_MEMBER_SCRIPT.ARRIVE_RADIUS):
		_fail(test_root, "na rua a chegada deveria ser a normal, veio %s" % member._arrive_radius())
	if not is_equal_approx(member._formation_scale(), 1.0):
		_fail(test_root, "na rua o trio anda lado a lado, veio %s" % member._formation_scale())
	director.free()


func _new_director(parent: Node) -> EscortDirector:
	var director := ESCORT_DIRECTOR_SCRIPT.new()
	director.point_a = Vector3(24.0, 1.0, -24.0)
	director.point_b = Vector3(-10.5, 1.0, 0.5)
	director._spawn_family(parent)
	return director


func _new_member(parent: Node, member_name: String) -> EscortFamilyMember:
	return ESCORT_MEMBER_SCRIPT.new_civilian(parent, member_name, Color.CRIMSON, 1.0)


## Jogador de verdade (mesma cena) so para o gancho do E; input desligado.
func _spawn_interacting_player(parent: Node, near: Vector3) -> CharacterBody3D:
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.reads_local_input = false
	player.position = near + Vector3(1.0, 0.0, 1.0)
	parent.add_child(player)
	return player


## Economia: tanque rende mais que fraco e variante desconhecida paga o piso.
func _test_escort_economy_rewards_variants(test_root: Node) -> void:
	var weak := ESCORT_ECONOMY_SCRIPT.reward_for_variant(ZombieMutator.Type.WALKER)
	var tank := ESCORT_ECONOMY_SCRIPT.reward_for_variant(ZombieMutator.Type.BRUTE)
	var unknown := ESCORT_ECONOMY_SCRIPT.reward_for_variant(-123)
	if weak <= 0 or tank <= weak:
		_fail(test_root, "tanque deveria render mais que fraco; fraco=%d tanque=%d" % [weak, tank])
	if unknown != ESCORT_ECONOMY_SCRIPT.DEFAULT_REWARD:
		_fail(test_root, "variante desconhecida deveria pagar o piso %d; veio %d" % [ESCORT_ECONOMY_SCRIPT.DEFAULT_REWARD, unknown])
	if ESCORT_ECONOMY_SCRIPT.checkpoint_reward() <= 0:
		_fail(test_root, "bonus de checkpoint deveria ser positivo; veio %d" % ESCORT_ECONOMY_SCRIPT.checkpoint_reward())


## Saldo do jogador: credita, gasta e recusa quando falta grana.
func _test_player_money_add_and_spend(test_root: Node) -> void:
	var player := _spawn_interacting_player(test_root, Vector3.ZERO)
	var added: int = player.call("add_money", 50)
	if added != 50 or int(player.get("money")) != 50:
		_fail(test_root, "add_money(50) deveria deixar 50; veio %d" % added)
	if not bool(player.call("spend_money", 30)) or int(player.get("money")) != 20:
		_fail(test_root, "spend_money(30) deveria deixar 20; veio %d" % int(player.get("money")))
	if bool(player.call("spend_money", 1000)):
		_fail(test_root, "spend_money sem saldo deveria falhar")
	player.free()


## Loja: recusa sem saldo, entrega e desconta com saldo, recusa arma repetida.
func _test_escort_shop_purchase(test_root: Node) -> void:
	var player := _spawn_interacting_player(test_root, Vector3.ZERO)
	var kind := WeaponStats.Kind.UZI
	var price := ESCORT_SHOP_SCRIPT.price_of(kind)
	if price <= 0:
		_fail(test_root, "uzi deveria ter preco no catalogo")
		player.free()
		return
	if String(ESCORT_SHOP_SCRIPT.purchase(player, kind)).is_empty():
		_fail(test_root, "compra sem saldo deveria falhar")
	var address: int = player.call("add_money", price)
	if address != price:
		_fail(test_root, "add_money deveria creditar %d; veio %d" % [price, address])
	if not String(ESCORT_SHOP_SCRIPT.purchase(player, kind)).is_empty():
		_fail(test_root, "compra com saldo deveria passar")
	if int(player.get("money")) != 0:
		_fail(test_root, "compra deveria zerar o saldo; sobrou %d" % int(player.get("money")))
	if not bool(player.call("has_crate_weapon", kind)):
		_fail(test_root, "compra deveria entregar a arma")
	if String(ESCORT_SHOP_SCRIPT.purchase(player, kind)).is_empty():
		_fail(test_root, "comprar a mesma arma de novo deveria recusar")
	player.free()
