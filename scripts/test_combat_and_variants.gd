extends Node3D

## Suite de testes de combate: Fogo Amigo, Animacao de Impacto (Flinch) e 9 Variantes Anatomicas de Zumbi.
## Execucao:
##   godot --headless --path . -- --unit-test

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")
const BULLET_SCENE := preload("res://scenes/bullet.tscn")
const RAGDOLL_SCENE := preload("res://scenes/zombie_ragdoll.tscn")
const FLOCK_COORDINATOR_SCRIPT := preload("res://scripts/zombie_flock_coordinator.gd")
const ZOMBIE_SPAWN_SCHEDULE_SCRIPT := preload("res://scripts/zombie_spawn_schedule.gd")
const GAMEPLAY_REGRESSION_TESTS_SCRIPT := preload("res://scripts/test_gameplay_regressions.gd")
const SURVIVAL_TESTS_SCRIPT := preload("res://scripts/test_survival_mode.gd")
const COLLISION_BOUNDARY_TESTS_SCRIPT := preload("res://scripts/test_collision_boundaries.gd")
const MAIN_SCRIPT := preload("res://scripts/main.gd")
const DESTRUCTIBLE_DOOR_SCRIPT := preload("res://scripts/destructible_door.gd")

var failure_count := 0


func _ready() -> void:
	print("--- INICIANDO TESTES DE COMBATE, FOGO AMIGO E VARIANTES ---")
	_test_friendly_fire_knife()
	_test_friendly_fire_bullet()
	_test_pistol_fixed_trajectory()
	await COLLISION_BOUNDARY_TESTS_SCRIPT.new().run(self)
	GAMEPLAY_REGRESSION_TESTS_SCRIPT.new().run(self)
	SURVIVAL_TESTS_SCRIPT.new().run(self)
	if bool(get_meta("unit_test_failed", false)):
		failure_count += 1
	_test_hit_reaction_flinch()
	_test_zombie_mutilation_variants()
	_test_ragdoll_mutilation_variants()
	_test_player_three_lives_and_elimination()
	_test_player_vision_cone()
	_test_zombie_vision_hides_entire_proxy()
	_test_wave_restores_three_lives()
	await _test_zombie_breaks_blocking_door()
	_test_zombie_finds_nearest_escape_door()
	_test_zombie_only_escapes_indoors()
	_test_player_sonar_pulse()
	_test_network_ragdoll_is_unique_per_zombie()
	_test_safehouse_structure_and_spawns()
	_test_gunshot_sound_echolocation()
	_test_zombie_flock_coordinator()
	_test_global_zombie_spawn_schedule()

	if failure_count > 0:
		push_error("UNIT_TEST_FAIL: %d grupo(s) de teste falharam." % failure_count)
		get_tree().quit(1)
		return
	print("UNIT_TEST_PASS: Todos os testes de combate, trajetoria, vidas, safehouse, som, hordas e populacao passaram!")
	get_tree().quit(0)


func _mark_failure() -> void:
	failure_count += 1


func _test_friendly_fire_knife() -> void:
	print("Testando fogo amigo com faca...")
	var p1 := PLAYER_SCENE.instantiate() as CharacterBody3D
	p1.name = "PlayerP1"
	p1.reads_local_input = false
	p1.position = Vector3(0, 1, 0)
	add_child(p1)

	var p2 := PLAYER_SCENE.instantiate() as CharacterBody3D
	p2.name = "PlayerP2"
	p2.reads_local_input = false
	p2.position = Vector3(0, 1, -1.2) # Na frente do P1 dentro do alcance de 1.7m
	add_child(p2)

	var initial_health: int = p2.health
	p1.call("_attack_with_knife")
	if p2.health >= initial_health:
		push_error("FALHA: Faca de P1 nao causou dano em P2 (fogo amigo desativado).")
		_mark_failure()
		return

	if p2.hit_reaction_time <= 0.0:
		push_error("FALHA: P2 nao iniciou hit_reaction_time ao sofrer dano de faca.")
		_mark_failure()
		return

	p1.queue_free()
	p2.queue_free()
	print("PASS: Fogo amigo com faca funcionou perfeitamente.")


func _test_friendly_fire_bullet() -> void:
	print("Testando fogo amigo com projetil / bala...")
	var p1 := PLAYER_SCENE.instantiate() as CharacterBody3D
	p1.name = "ShooterP1"
	p1.reads_local_input = false
	p1.position = Vector3(10, 1, 0)
	add_child(p1)

	var p2 := PLAYER_SCENE.instantiate() as CharacterBody3D
	p2.name = "TargetP2"
	p2.reads_local_input = false
	p2.position = Vector3(10, 1, -5)
	add_child(p2)

	var bullet := BULLET_SCENE.instantiate() as Node3D
	add_child(bullet)
	bullet.global_position = Vector3(10, 1.5, -0.5)
	bullet.call("setup", Vector3(0, 0, -1), 35, true, p1)

	for _i in range(30):
		bullet.call("_physics_process", 0.03)
		if not is_instance_valid(bullet):
			break

	if p2.health >= 100:
		push_error("FALHA: Bala de P1 nao atingiu P2 (fogo amigo com projetil desativado).")
		_mark_failure()
		return

	if p2.hit_reaction_time <= 0.0 and p2.velocity.z >= 0.0:
		push_error("FALHA: Bala nao aplicou forca de knockback ou reacao em P2.")
		_mark_failure()
		return

	p1.queue_free()
	p2.queue_free()
	print("PASS: Fogo amigo com bala funcionou com dano e knockback.")


func _test_pistol_fixed_trajectory() -> void:
	print("Testando trajetoria fixa da pistola sem teleguiamento...")
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.reads_local_input = false
	player.aim_input = Vector2.RIGHT
	add_child(player)
	var off_axis_target := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	off_axis_target.position = Vector3(8.0, 1.0, -9.0)
	add_child(off_axis_target)

	var fired_bullet: Variant = player.call("_fire_pistol")
	if fired_bullet == null or not fired_bullet is Node3D:
		push_error("FALHA: Disparo deve retornar o projetil criado para validar sua trajetoria.")
		_mark_failure()
		return
	var bullet := fired_bullet as Node3D
	var launch_direction: Vector3 = bullet.get("direction")
	if launch_direction.distance_to(Vector3.RIGHT) > 0.001:
		push_error("FALHA: Bala saiu em %s, mas deveria preservar a mira %s." % [launch_direction, Vector3.RIGHT])
		_mark_failure()
		return
	player.rotation.y = PI
	off_axis_target.position = Vector3(-8.0, 1.0, 9.0)
	bullet.call("_physics_process", 0.01)
	if (bullet.get("direction") as Vector3).distance_to(launch_direction) > 0.001:
		push_error("FALHA: Bala alterou a direcao depois do disparo.")
		_mark_failure()
		return
	bullet.queue_free()
	player.queue_free()
	off_axis_target.queue_free()
	print("PASS: Trajetoria fixa da pistola validada.")


func _test_hit_reaction_flinch() -> void:
	print("Testando animacao de impacto (flinch) em jogador e zumbi...")
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.reads_local_input = false
	add_child(player)
	player.take_damage(20, Vector3(0, 0, 1), "bullet")

	for _i in range(5):
		player.call("_physics_process", 0.02)

	var model := player.get_node("Model") as Node3D
	var head := player.get_node("Model/Head") as Node3D

	if model.rotation.x >= -0.01:
		push_error("FALHA: Modelo do jogador nao inclinou para tras no flinch.")
		_mark_failure()
		return

	if head.rotation.x >= -0.01:
		push_error("FALHA: Cabeca do jogador nao chicoteou para tras no impacto.")
		_mark_failure()
		return

	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	add_child(zombie)
	zombie.take_damage(25, Vector3(0, 0, 1), "bullet")

	for _i in range(5):
		zombie.call("_physics_process", 0.02)

	var z_model := zombie.get_node("Model") as Node3D

	if z_model.rotation.x >= -0.01:
		push_error("FALHA: Modelo do zumbi nao reagiu ao tiro no flinch.")
		_mark_failure()
		return

	player.queue_free()
	zombie.queue_free()
	print("PASS: Animacao de impacto (flinch) verificada com sucesso.")


func _test_zombie_mutilation_variants() -> void:
	print("Testando todas as 9 variantes anatomicas procedurais de zumbi...")
	var variants: Array[ZombieMutator.Type] = [
		ZombieMutator.Type.WALKER,
		ZombieMutator.Type.ONE_ARM,
		ZombieMutator.Type.CRAWLER,
		ZombieMutator.Type.LIMPER,
		ZombieMutator.Type.SPRINTER,
		ZombieMutator.Type.HALF_ARM,
		ZombieMutator.Type.ONE_LEG,
		ZombieMutator.Type.HALF_LEG,
		ZombieMutator.Type.HALF_HEAD,
	]

	for v in variants:
		var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
		add_child(zombie)
		zombie.zombie_type = v
		ZombieMutator.apply_appearance(zombie, int(v), 12345 + int(v) * 37)

		match v:
			ZombieMutator.Type.ONE_ARM:
				var mesh := zombie.get_node("Model/LeftArm/Mesh") as MeshInstance3D
				if mesh.visible:
					push_error("FALHA: Variante ONE_ARM deve ocultar braco esquerdo.")
					_mark_failure()
					return
			ZombieMutator.Type.HALF_ARM:
				var mesh := zombie.get_node("Model/LeftArm/Mesh") as MeshInstance3D
				if mesh.scale.y > 0.6:
					push_error("FALHA: Variante HALF_ARM deve ter braco esquerdo amputado/encurtado.")
					_mark_failure()
					return
			ZombieMutator.Type.ONE_LEG:
				var mesh := zombie.get_node("Model/LeftLeg/Mesh") as MeshInstance3D
				if mesh.visible:
					push_error("FALHA: Variante ONE_LEG deve ocultar perna esquerda.")
					_mark_failure()
					return
			ZombieMutator.Type.HALF_LEG:
				var mesh := zombie.get_node("Model/RightLeg/Mesh") as MeshInstance3D
				if mesh.scale.y > 0.6:
					push_error("FALHA: Variante HALF_LEG deve ter perna direita encurtada/amputada.")
					_mark_failure()
					return
			ZombieMutator.Type.HALF_HEAD:
				var eye := zombie.get_node("Model/Head/RightEye") as Node3D
				if eye.visible:
					push_error("FALHA: Variante HALF_HEAD deve ocultar o olho da metade rompida.")
					_mark_failure()
					return
			ZombieMutator.Type.CRAWLER:
				if zombie.speed > 1.5:
					push_error("FALHA: CRAWLER deve ter velocidade reduzida.")
					_mark_failure()
					return

		# Executa passo de animacao para garantir que pose funciona sem crash
		ZombieMutator.animate_variant_pose(zombie, int(v), 0.016, true, 0.0, 1.2)
		ZombieMutator.animate_hit_reaction(zombie, 0.016, 0.1, 0.24, Vector3.FORWARD, "bullet", int(v), 0.0)
		zombie.queue_free()

	print("PASS: Todas as 9 variantes anatomicas validadas.")


func _test_ragdoll_mutilation_variants() -> void:
	print("Testando criacao de ragdolls para as variantes mutiladas...")
	for v in range(9):
		var ragdoll := RAGDOLL_SCENE.instantiate() as Node3D
		add_child(ragdoll)
		ragdoll.call("setup", Vector3(0, 1, -2), v)
		ragdoll.queue_free()
	print("PASS: Ragdolls de todas as variantes inicializados com sucesso.")


func _test_player_three_lives_and_elimination() -> void:
	print("Testando sistema de 3 vidas e eliminacao...")
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.reads_local_input = false
	player.position = Vector3(-15.2, 0.5, 8.2)
	add_child(player)

	if player.lives != 3 or player.is_eliminated:
		push_error("FALHA: Jogador deve iniciar com 3 vidas e nao eliminado.")
		_mark_failure()
		return

	# 1a morte: vidas caem de 3 para 2 e respawna
	var expected_spawn := player.global_position
	player.global_position = Vector3(4.0, 0.5, 4.0)
	player.take_damage(100, Vector3.FORWARD, "bullet")
	if player.lives != 2 or player.health != 100 or player.is_eliminated or player.global_position.distance_to(expected_spawn) > 0.01:
		push_error("FALHA: Apos 1a morte, jogador deve ter 2 vidas e renascer com 100 de vida.")
		_mark_failure()
		return

	# 2a morte: vidas caem de 2 para 1 e respawna
	player.take_damage(100, Vector3.FORWARD, "bullet")
	if player.lives != 1 or player.health != 100 or player.is_eliminated:
		push_error("FALHA: Apos 2a morte, jogador deve ter 1 vida e renascer com 100 de vida.")
		_mark_failure()
		return

	# 3a morte: vidas caem para 0 e e eliminado
	player.take_damage(100, Vector3.FORWARD, "bullet")
	if player.lives != 0 or not player.is_eliminated or player.visible or player.collision_layer != 0:
		push_error("FALHA: Apos perder 3 vidas, jogador deve ser eliminado e invisivel.")
		_mark_failure()
		return

	if not player.get_lives_text().contains("ELIMINADO"):
		push_error("FALHA: get_lives_text() deve indicar [ELIMINADO].")
		_mark_failure()
		return

	# Dano adicional nao deve afetar jogador eliminado
	player.take_damage(50, Vector3.FORWARD, "bullet")
	if player.health != 0:
		push_error("FALHA: Jogador eliminado nao deve receber dano adicional.")
		_mark_failure()
		return

	player.queue_free()
	print("PASS: Sistema de 3 vidas e eliminacao validado com sucesso.")


func _test_player_vision_cone() -> void:
	print("Testando cone de visao ampliado e overlay translucido...")
	var player := PLAYER_SCENE.instantiate() as PlayerCharacter
	player.reads_local_input = false
	player.position = Vector3.ZERO
	add_child(player)
	var wide_target := Vector3(sin(deg_to_rad(60.0)) * 20.0, 1.0, -cos(deg_to_rad(60.0)) * 20.0)
	if not player.can_see_position(Vector3(0.0, 1.0, -28.0)) or not player.can_see_position(wide_target):
		push_error("FALHA: Jogador deveria enxergar ate 28m e 60 graus do centro.")
		_mark_failure()
		player.queue_free()
		return
	if player.can_see_position(Vector3(0.0, 1.0, 12.0)) or player.can_see_position(Vector3(0.0, 1.0, -33.0)):
		push_error("FALHA: Jogador nao deveria enxergar zumbi atras ou fora do alcance.")
		_mark_failure()
		player.queue_free()
		return
	var overlay := player.get_node_or_null("VisionArc") as MeshInstance3D
	var material := overlay.material_override as StandardMaterial3D if overlay != null else null
	player.configure_vision_overlay(17)
	if overlay == null or overlay.mesh == null or material == null or not overlay.visible or material.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA or material.albedo_color.a >= 0.5:
		push_error("FALHA: Overlay de visao deveria ser branco translucido e manter o mapa legivel.")
		_mark_failure()
		player.queue_free()
		return
	player.queue_free()
	print("PASS: Cone ampliado e overlay branco translucido validados.")


func _test_zombie_vision_hides_entire_proxy() -> void:
	print("Testando esvaecimento do proxy de zumbi no FOV...")
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	zombie.simulation_enabled = false
	add_child(zombie)
	zombie.set_vision_visible(false)
	zombie.call("_update_visual_fade", 0.3)
	if not zombie.visible or float(zombie.get("visual_opacity")) >= 1.0:
		push_error("FALHA: Ao sair do FOV o zumbi deveria esvaecer em vez de sumir na hora.")
		_mark_failure()
		zombie.queue_free()
		return
	zombie.call("_update_visual_fade", 1.0)
	if zombie.visible or zombie.get_node("Model").visible or zombie.get_node("HealthLabel").visible:
		push_error("FALHA: Fade concluido deveria ocultar proxy, modelo e barra de vida do zumbi.")
		_mark_failure()
		zombie.queue_free()
		return
	zombie.queue_free()
	print("PASS: FOV esvaece e por fim oculta todo o proxy visual do zumbi.")


func _test_wave_restores_three_lives() -> void:
	print("Testando reset de 3 vidas em nova onda...")
	var player := PLAYER_SCENE.instantiate() as PlayerCharacter
	player.reads_local_input = false
	add_child(player)
	player.take_damage(100, Vector3.FORWARD, "bullet")
	player.take_damage(100, Vector3.FORWARD, "bullet")
	player.take_damage(100, Vector3.FORWARD, "bullet")
	if not player.is_eliminated or player.lives != 0:
		push_error("FALHA: Jogador deveria estar eliminado antes da nova onda.")
		_mark_failure()
		player.queue_free()
		return
	player.restore_wave_lives()
	if player.lives != 3 or player.is_eliminated or not player.visible or player.health != player.max_health:
		push_error("FALHA: Nova onda deveria devolver 3 vidas e reanimar o jogador.")
		_mark_failure()
		player.queue_free()
		return
	player.queue_free()
	print("PASS: Nova onda restaura 3 vidas e reanima o jogador.")


func _test_zombie_breaks_blocking_door() -> void:
	print("Testando zumbi quebrando porta que bloqueia o caminho...")
	var door := DESTRUCTIBLE_DOOR_SCRIPT.new() as AnimatableBody3D
	door.position = Vector3(-1.1, 1.0, 0.3)
	add_child(door)
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	zombie.position = Vector3(0.0, 1.0, 1.2)
	zombie.simulation_enabled = false
	add_child(zombie)
	await get_tree().physics_frame
	zombie.call("_try_attack_blocking_door", Vector3(0.0, 0.0, -1.0))
	zombie.call("_try_attack_blocking_door", Vector3(0.0, 0.0, -1.0))
	if int(door.get("health")) >= int(door.get("max_health")):
		push_error("FALHA: Zumbi bloqueado deveria atacar a porta a frente; vida=%d." % int(door.get("health")))
		_mark_failure()
		zombie.queue_free()
		door.queue_free()
		return
	zombie.queue_free()
	door.queue_free()
	await get_tree().process_frame
	print("PASS: Zumbi ataca a porta fechada que bloqueia a passagem.")


func _test_zombie_finds_nearest_escape_door() -> void:
	print("Testando rota de fuga do zumbi pela porta mais proxima...")
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	zombie.position = Vector3(0.0, 1.0, 0.0)
	zombie.simulation_enabled = false
	add_child(zombie)
	var near_door := DESTRUCTIBLE_DOOR_SCRIPT.new() as AnimatableBody3D
	near_door.position = Vector3(0.0, 1.0, 5.0)
	add_child(near_door)
	var far_door := DESTRUCTIBLE_DOOR_SCRIPT.new() as AnimatableBody3D
	far_door.position = Vector3(0.0, 1.0, 20.0)
	add_child(far_door)
	var found: Node3D = zombie.call("_find_nearest_door") as Node3D
	if found != near_door:
		push_error("FALHA: Zumbi preso deveria mirar a porta fechada mais proxima.")
		_mark_failure()
		zombie.queue_free()
		near_door.queue_free()
		far_door.queue_free()
		return
	near_door.set("is_open", true)
	var next_found: Node3D = zombie.call("_find_nearest_door") as Node3D
	if next_found != far_door:
		push_error("FALHA: Porta aberta nao deve servir de rota de fuga.")
		_mark_failure()
		zombie.queue_free()
		near_door.queue_free()
		far_door.queue_free()
		return
	zombie.queue_free()
	near_door.queue_free()
	far_door.queue_free()
	print("PASS: Zumbi preso busca e quebra a porta fechada mais proxima.")


func _test_zombie_only_escapes_indoors() -> void:
	print("Testando fuga de zumbi apenas dentro de construcoes...")
	var building := StaticBody3D.new()
	building.add_to_group("visibility_building")
	building.set_meta("visibility_min", Vector3(-5.0, 0.0, -5.0))
	building.set_meta("visibility_max", Vector3(5.0, 4.0, 5.0))
	add_child(building)
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	zombie.simulation_enabled = false
	zombie.position = Vector3(0.0, 1.0, 0.0)
	add_child(zombie)
	if not bool(zombie.call("_is_inside_building")):
		push_error("FALHA: Zumbi dentro dos limites deveria ser considerado dentro da casa.")
		_mark_failure()
		zombie.queue_free()
		building.queue_free()
		return
	zombie.position = Vector3(20.0, 1.0, 20.0)
	if bool(zombie.call("_is_inside_building")):
		push_error("FALHA: Zumbi na rua nao deveria acionar a rota de fuga interna.")
		_mark_failure()
		zombie.queue_free()
		building.queue_free()
		return
	zombie.queue_free()
	building.queue_free()
	print("PASS: Rota de fuga vale somente dentro de construcoes.")


func _test_player_sonar_pulse() -> void:
	print("Testando pulso sonar que revela zumbis...")
	var player := PLAYER_SCENE.instantiate() as PlayerCharacter
	player.reads_local_input = false
	add_child(player)
	if player.is_sonar_active() or player.get_sonar_text() != "Sonar: pronto":
		push_error("FALHA: Sonar deveria iniciar inativo e pronto.")
		_mark_failure()
		player.queue_free()
		return
	player.trigger_sonar()
	if not player.is_sonar_active() or player.get_sonar_text() != "Sonar: ativo":
		push_error("FALHA: Sonar deveria ativar ao ser disparado.")
		_mark_failure()
		player.queue_free()
		return
	player.set("sonar_pulse_time", 0.0)
	player.trigger_sonar()
	if player.is_sonar_active():
		push_error("FALHA: Cooldown deveria impedir um novo pulso imediato.")
		_mark_failure()
		player.queue_free()
		return
	player.queue_free()
	print("PASS: Sonar ativa, revela e respeita cooldown.")


func _test_network_ragdoll_is_unique_per_zombie() -> void:
	print("Testando ragdoll unico por zumbi de rede...")
	var main := MAIN_SCRIPT.new()
	main.call("spawn_zombie_ragdoll", Vector3.ZERO, 0.0, Vector3.ZERO, 0, 123, "ZombieSnapshot1")
	main.call("spawn_zombie_ragdoll", Vector3.ZERO, 0.0, Vector3.ZERO, 0, 123, "ZombieSnapshot1")
	var spawned_ragdolls: Array = main.get("ragdolls")
	if spawned_ragdolls.size() != 1:
		push_error("FALHA: Um zumbi de rede deveria gerar um corpo; gerou %d." % spawned_ragdolls.size())
		_mark_failure()
		main.free()
		return
	main.free()
	print("PASS: Snapshot repetido mantem somente um ragdoll por zumbi.")


func _test_safehouse_structure_and_spawns() -> void:
	print("Testando Safehouse de 2 andares e geracao de estacoes de respawn...")
	var safehouse := SafehouseBuilder.build_safehouse()
	if safehouse == null or not (safehouse is StaticBody3D):
		push_error("FALHA: SafehouseBuilder deve retornar uma instancia valida de StaticBody3D.")
		_mark_failure()
		return
	add_child(safehouse)

	if not safehouse.has_node("GroundFloorMesh") or not safehouse.has_node("Floor2EastMesh"):
		push_error("FALHA: Safehouse deve possuir malhas de terreo e 2o andar.")
		_mark_failure()
		return

	if not safehouse.has_node("SanctuaryGroundLight") or not safehouse.has_node("SanctuaryUpperLight"):
		push_error("FALHA: Safehouse deve possuir iluminacao de refugio no terreo e 2o andar.")
		_mark_failure()
		return

	if not safehouse.has_node("ExteriorDefensiveSpotlight"):
		push_error("FALHA: Safehouse deve possuir holofote defensivo frontal.")
		_mark_failure()
		return
	for child in safehouse.get_children():
		if child is CollisionShape3D and child.position.z < -6.0 and absf(child.position.x) < 2.1 and child.position.y < 3.1:
			push_error("FALHA: Portal da Safehouse possui um lintel baixo que bloqueia a saida.")
			_mark_failure()
			return
	for spawn_index in 4:
		var marker := safehouse.get_node_or_null("PlayerSpawn%d" % (spawn_index + 1)) as Marker3D
		if marker == null or marker.position.y < 1.0:
			push_error("FALHA: Spawn %d deve existir acima do piso da Safehouse." % (spawn_index + 1))
			_mark_failure()
			return
	var door := safehouse.get_node_or_null("SafehouseDoor")
	if door == null:
		push_error("FALHA: Safehouse deve possuir porta automatica no portal.")
		_mark_failure()
		return
	door.call("update_for_actor_presence", true, 0.1)
	if not bool(door.call("is_open_requested")) or int(door.get_node("Panel").collision_layer) != 0:
		push_error("FALHA: Porta deve abrir e liberar colisao ao detectar jogador ou zumbi.")
		_mark_failure()
		return
	door.call("update_for_actor_presence", false, 1.0)
	var door_still_open := bool(door.call("is_open_requested"))
	var closed_collision_layer := int(door.get_node("Panel").collision_layer)
	if door_still_open or closed_collision_layer != 1:
		push_error("FALHA: Porta vazia esperava aberta=false/camada=1, recebeu aberta=%s/camada=%d." % [door_still_open, closed_collision_layer])
		_mark_failure()
		return

	safehouse.queue_free()
	print("PASS: Safehouse, spawns e porta automatica validados com sucesso.")


func _test_gunshot_sound_echolocation() -> void:
	print("Testando propagacao de som de tiro, atenuacao e ecolocalizacao dos zumbis...")
	var zombie_near := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	zombie_near.position = Vector3(0, 1, 20) # 20 metros de distancia
	add_child(zombie_near)

	var zombie_far := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	zombie_far.position = Vector3(0, 1, 100) # 100 metros (fora do raio de 65m)
	add_child(zombie_far)

	var shot_pos := Vector3(0, 1, 0)
	# Dispara som de tiro
	zombie_near.call("hear_gunshot", shot_pos, 65.0)
	zombie_far.call("hear_gunshot", shot_pos, 65.0)

	if not bool(zombie_near.get("is_investigating_sound")):
		push_error("FALHA: Zumbi a 20m deveria ecolocalizar o som do tiro.")
		_mark_failure()
		return

	if bool(zombie_far.get("is_investigating_sound")):
		push_error("FALHA: Zumbi a 100m nao deveria ouvir tiro fora do raio de 65m.")
		_mark_failure()
		return

	# Executa passo de fisica para verificar que o zumbi se move na direcao do som
	zombie_near.call("_physics_process", 0.1)
	if zombie_near.velocity.z >= 0.0:
		push_error("FALHA: Zumbi deve se locomover devagar em direcao ao som (-Z).")
		_mark_failure()
		return

	zombie_near.queue_free()
	zombie_far.queue_free()
	print("PASS: Propagacao de som de tiro e ecolocalizacao validadas com sucesso.")


func _test_zombie_flock_coordinator() -> void:
	print("Testando ZombieFlockCoordinator (LOD, Lider-Seguidor e separacao suave)...")
	var coordinator = FLOCK_COORDINATOR_SCRIPT.new()
	add_child(coordinator)

	var p := PLAYER_SCENE.instantiate() as CharacterBody3D
	p.position = Vector3(0, 1, 0)
	p.reads_local_input = false
	add_child(p)

	var z1 := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	z1.position = Vector3(2, 1, 2)
	add_child(z1)

	var z2 := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	z2.position = Vector3(2.5, 1, 2)
	add_child(z2)

	var z_far := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	z_far.position = Vector3(90, 1, 90)
	z_far.simulation_enabled = false
	add_child(z_far)

	# Executa atualizacao do coordenador
	coordinator._physics_process(0.2)

	var leaders := int(bool(z1.get("is_cluster_leader"))) + int(bool(z2.get("is_cluster_leader")))
	if leaders != 1:
		push_error("FALHA: Cluster deveria possuir exatamente um lider; lideres=%d." % leaders)
		_mark_failure()
		return
	var leader := z1 if bool(z1.get("is_cluster_leader")) else z2
	var follower := z2 if leader == z1 else z1

	if int(z1.get("lod_level")) != 0 or int(z_far.get("lod_level")) != 2:
		push_error("FALHA: LOD de distancia incorreto: z1=%s, z_far=%s" % [z1.get("lod_level"), z_far.get("lod_level")])
		_mark_failure()
		return
	z_far._physics_process(0.2)
	z_far.call("_update_visual_fade", 1.0)
	if (z_far.get_node("Model") as Node3D).visible or (z_far.get_node("HealthLabel") as Label3D).visible:
		push_error("FALHA: Proxy distante deveria esvaecer e ocultar modelo e etiqueta no cliente.")
		_mark_failure()
		return

	# Alerta o lider e valida replicacao para seguidor
	leader.set("alert_target", p)
	coordinator._physics_process(0.2)
	if follower.get("alert_target") != p:
		push_error("FALHA: Seguidor do cluster deveria receber o alvo do lider.")
		_mark_failure()
		return

	var sep: Vector3 = leader.get("flock_separation_vector") as Vector3
	if sep.length_squared() < 0.0001:
		push_error("FALHA: Vetor de separacao suave deveria ser diferente de zero entre z1 e z2.")
		_mark_failure()
		return

	coordinator.queue_free()
	p.queue_free()
	z1.queue_free()
	z2.queue_free()
	z_far.queue_free()
	print("PASS: ZombieFlockCoordinator validado com sucesso.")


func _test_global_zombie_spawn_schedule() -> void:
	print("Testando limite global e reposicao gradual de 600 zumbis...")
	var schedule = ZOMBIE_SPAWN_SCHEDULE_SCRIPT.new(600, 1.0)
	if schedule.is_spawn_due(0.99) or not schedule.is_spawn_due(0.01):
		push_error("FALHA: Spawn inicial deve aguardar um intervalo completo de 1 segundo.")
		_mark_failure()
		return
	if not schedule.has_capacity(599) or schedule.has_capacity(600):
		push_error("FALHA: Limite global deve permitir 599 e bloquear 600 zumbis ativos.")
		_mark_failure()
		return

	var active_zombies := 598
	for _player_kill_slot in 2:
		if schedule.is_spawn_due(1.0) and schedule.has_capacity(active_zombies):
			active_zombies += 1
	if active_zombies != 600:
		push_error("FALHA: Duas mortes devem ser repostas em dois ticks globais; ativos=%d." % active_zombies)
		_mark_failure()
		return
	print("PASS: Limite global e reposicao gradual de zumbis validados.")
