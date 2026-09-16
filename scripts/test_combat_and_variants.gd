extends Node3D

## Suite de testes de combate: Fogo Amigo, Animacao de Impacto (Flinch) e 9 Variantes Anatomicas de Zumbi.
## Execucao:
##   godot --headless --path . -- --unit-test

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")
const BULLET_SCENE := preload("res://scenes/bullet.tscn")
const BULLET_SCRIPT := preload("res://scripts/bullet.gd")
const RAGDOLL_SCENE := preload("res://scenes/zombie_ragdoll.tscn")
const FLOCK_COORDINATOR_SCRIPT := preload("res://scripts/zombie_flock_coordinator.gd")
const ZOMBIE_SPAWN_SCHEDULE_SCRIPT := preload("res://scripts/zombie_spawn_schedule.gd")
const GAMEPLAY_REGRESSION_TESTS_SCRIPT := preload("res://scripts/test_gameplay_regressions.gd")
const SURVIVAL_TESTS_SCRIPT := preload("res://scripts/test_survival_mode.gd")
const COLLISION_BOUNDARY_TESTS_SCRIPT := preload("res://scripts/test_collision_boundaries.gd")
const BUILDING_NAVIGATION_TESTS_SCRIPT := preload("res://scripts/test_building_navigation.gd")
const DOOR_BREAKING_TESTS_SCRIPT := preload("res://scripts/test_door_breaking.gd")
const SAFEHOUSE_DOOR_TESTS_SCRIPT := preload("res://scripts/test_safehouse_door.gd")
const NETWORK_LAG_PROBE_TESTS_SCRIPT := preload("res://scripts/test_network_lag_probe.gd")
const CITY_PROPS_TESTS_SCRIPT := preload("res://scripts/test_city_props.gd")
const CORPSE_CLEANUP_TESTS_SCRIPT := preload("res://scripts/test_corpse_cleanup.gd")
const ZOMBIE_SNAPSHOT_CODEC_TESTS_SCRIPT := preload("res://scripts/test_zombie_snapshot_codec.gd")
const APARTMENT_LAYOUT_TESTS_SCRIPT := preload("res://scripts/test_apartment_layout.gd")
const ZOMBIE_UNSTUCK_TESTS_SCRIPT := preload("res://scripts/test_zombie_unstuck.gd")
const PLAYER_UNSTUCK_TESTS_SCRIPT := preload("res://scripts/test_player_unstuck.gd")
const NETWORK_JOIN_SYNC_TESTS_SCRIPT := preload("res://scripts/test_network_join_sync.gd")
const AMMO_LOOT_TESTS_SCRIPT := preload("res://scripts/test_ammo_loot.gd")
const ZOMBIE_NEW_VARIANTS_TESTS_SCRIPT := preload("res://scripts/test_zombie_new_variants.gd")
const ZOMBIE_BOSS_TESTS_SCRIPT := preload("res://scripts/test_zombie_boss.gd")
const WEAPON_DAMAGE_TESTS_SCRIPT := preload("res://scripts/test_weapon_damage.gd")
const SHARED_VISION_TESTS_SCRIPT := preload("res://scripts/test_shared_vision.gd")
const SAFEHOUSE_ROOF_TESTS_SCRIPT := preload("res://scripts/test_safehouse_roof.gd")
const ZOMBIE_BODY_SCALE_TESTS_SCRIPT := preload("res://scripts/test_zombie_body_scale.gd")
const WEAPON_ARSENAL_TESTS_SCRIPT := preload("res://scripts/test_weapon_arsenal.gd")
const ZOMBIE_SPECIALS_TESTS_SCRIPT := preload("res://scripts/test_zombie_specials.gd")
const GROUND_WEAPON_PICKUP_TESTS_SCRIPT := preload("res://scripts/test_ground_weapon_pickup.gd")
const FRAME_PERF_PROBE_TESTS_SCRIPT := preload("res://scripts/test_frame_perf_probe.gd")
# Grupos rodaveis sozinhos com `-- --test-group=<nome>` para iterar rapido.
const FOCUSED_TEST_GROUPS := {
	"apartment_layout": APARTMENT_LAYOUT_TESTS_SCRIPT,
	"zombie_unstuck": ZOMBIE_UNSTUCK_TESTS_SCRIPT,
	"player_unstuck": PLAYER_UNSTUCK_TESTS_SCRIPT,
	"network_join_sync": NETWORK_JOIN_SYNC_TESTS_SCRIPT,
	"ammo_loot": AMMO_LOOT_TESTS_SCRIPT,
	"zombie_new_variants": ZOMBIE_NEW_VARIANTS_TESTS_SCRIPT,
	"zombie_boss": ZOMBIE_BOSS_TESTS_SCRIPT,
	"weapon_damage": WEAPON_DAMAGE_TESTS_SCRIPT,
	"shared_vision": SHARED_VISION_TESTS_SCRIPT,
	"safehouse_roof": SAFEHOUSE_ROOF_TESTS_SCRIPT,
	"zombie_body_scale": ZOMBIE_BODY_SCALE_TESTS_SCRIPT,
	"weapon_arsenal": WEAPON_ARSENAL_TESTS_SCRIPT,
	"zombie_specials": ZOMBIE_SPECIALS_TESTS_SCRIPT,
	"ground_weapon_pickup": GROUND_WEAPON_PICKUP_TESTS_SCRIPT,
	"survival_mode": SURVIVAL_TESTS_SCRIPT,
	"zombie_snapshot_codec": ZOMBIE_SNAPSHOT_CODEC_TESTS_SCRIPT,
	"building_navigation": BUILDING_NAVIGATION_TESTS_SCRIPT,
	"door_breaking": DOOR_BREAKING_TESTS_SCRIPT,
	"safehouse_door": SAFEHOUSE_DOOR_TESTS_SCRIPT,
	"city_props": CITY_PROPS_TESTS_SCRIPT,
	"network_lag_probe": NETWORK_LAG_PROBE_TESTS_SCRIPT,
	"frame_perf_probe": FRAME_PERF_PROBE_TESTS_SCRIPT,
}
const MAIN_SCRIPT := preload("res://scripts/main.gd")
const DESTRUCTIBLE_DOOR_SCRIPT := preload("res://scripts/destructible_door.gd")
const SCRIPT_ERROR_COUNTER_SCRIPT := preload("res://scripts/test_script_error_counter.gd")

var failure_count := 0
var script_error_counter = SCRIPT_ERROR_COUNTER_SCRIPT.new()


func _ready() -> void:
	OS.add_logger(script_error_counter)
	var focused_group := _focused_test_group()
	if not focused_group.is_empty():
		await _run_focused_group(focused_group)
		return
	print("--- INICIANDO TESTES DE COMBATE, FOGO AMIGO E VARIANTES ---")
	_test_friendly_fire_knife()
	_test_friendly_fire_bullet()
	_test_pistol_fixed_trajectory()
	await COLLISION_BOUNDARY_TESTS_SCRIPT.new().run(self)
	GAMEPLAY_REGRESSION_TESTS_SCRIPT.new().run(self)
	SURVIVAL_TESTS_SCRIPT.new().run(self)
	await BUILDING_NAVIGATION_TESTS_SCRIPT.new().run(self)
	await DOOR_BREAKING_TESTS_SCRIPT.new().run(self)
	await SAFEHOUSE_DOOR_TESTS_SCRIPT.new().run(self)
	await APARTMENT_LAYOUT_TESTS_SCRIPT.new().run(self)
	await ZOMBIE_UNSTUCK_TESTS_SCRIPT.new().run(self)
	await PLAYER_UNSTUCK_TESTS_SCRIPT.new().run(self)
	NETWORK_JOIN_SYNC_TESTS_SCRIPT.new().run(self)
	AMMO_LOOT_TESTS_SCRIPT.new().run(self)
	ZOMBIE_NEW_VARIANTS_TESTS_SCRIPT.new().run(self)
	ZOMBIE_BOSS_TESTS_SCRIPT.new().run(self)
	await WEAPON_DAMAGE_TESTS_SCRIPT.new().run(self)
	SHARED_VISION_TESTS_SCRIPT.new().run(self)
	await SAFEHOUSE_ROOF_TESTS_SCRIPT.new().run(self)
	await ZOMBIE_BODY_SCALE_TESTS_SCRIPT.new().run(self)
	await WEAPON_ARSENAL_TESTS_SCRIPT.new().run(self)
	ZOMBIE_SPECIALS_TESTS_SCRIPT.new().run(self)
	await GROUND_WEAPON_PICKUP_TESTS_SCRIPT.new().run(self)
	NETWORK_LAG_PROBE_TESTS_SCRIPT.new().run(self)
	FRAME_PERF_PROBE_TESTS_SCRIPT.new().run(self)
	CITY_PROPS_TESTS_SCRIPT.new().run(self)
	CORPSE_CLEANUP_TESTS_SCRIPT.new().run(self)
	ZOMBIE_SNAPSHOT_CODEC_TESTS_SCRIPT.new().run(self)
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
	_test_player_sonar_pulse()
	_test_crate_weapon_family()
	_test_corpse_does_not_block_player()
	_test_network_ragdoll_is_unique_per_zombie()
	_test_safehouse_structure_and_spawns()
	_test_gunshot_sound_echolocation()
	_test_zombie_flock_coordinator()
	_test_global_zombie_spawn_schedule()

	if script_error_counter.script_errors > 0:
		push_error("FALHA: %d erro(s) de script durante a suite: %s" % [script_error_counter.script_errors, "\n".join(script_error_counter.messages)])
		failure_count += 1
	if failure_count > 0:
		push_error("UNIT_TEST_FAIL: %d grupo(s) de teste falharam." % failure_count)
		get_tree().quit(1)
		return
	print("UNIT_TEST_PASS: Todos os testes de combate, trajetoria, vidas, safehouse, som, hordas e populacao passaram!")
	get_tree().quit(0)


func _focused_test_group() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--test-group="):
			return argument.trim_prefix("--test-group=")
	return ""


func _run_focused_group(group_name: String) -> void:
	if not FOCUSED_TEST_GROUPS.has(group_name):
		push_error("UNIT_TEST_FAIL: grupo '%s' desconhecido; esperado um de %s." % [group_name, FOCUSED_TEST_GROUPS.keys()])
		get_tree().quit(1)
		return
	var group_script: GDScript = FOCUSED_TEST_GROUPS[group_name]
	# Script com erro de compilacao nao roda nenhum teste e antes saia PASS.
	if not group_script.can_instantiate():
		push_error("UNIT_TEST_FAIL: grupo '%s' nao compila (%s); rode `godot --headless --path . --import` se criou class_name novo." % [group_name, group_script.resource_path])
		get_tree().quit(1)
		return
	await group_script.new().run(self)
	var failed: bool = bool(get_meta("unit_test_failed", false)) or int(script_error_counter.script_errors) > 0
	if script_error_counter.script_errors > 0:
		push_error("FALHA: %d erro(s) de script: %s" % [script_error_counter.script_errors, "\n".join(script_error_counter.messages)])
	print("UNIT_TEST_%s: grupo %s" % ["FAIL" if failed else "PASS", group_name])
	get_tree().quit(1 if failed else 0)


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

	# 3a morte: vidas caem para 0 e fica CAIDO (visivel, deitado, reanimavel)
	player.take_damage(100, Vector3.FORWARD, "bullet")
	if player.lives != 0 or not player.is_downed or player.is_eliminated or not player.visible:
		push_error("FALHA: Apos perder 3 vidas, jogador deve ficar caido e reanimavel.")
		_mark_failure()
		return

	if not player.get_lives_text().contains("CAIDO"):
		push_error("FALHA: get_lives_text() deve indicar estado caido.")
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


## Cone aposentado: o jogador ve em qualquer direcao ate VIEW_RADIUS.
func _test_player_vision_cone() -> void:
	print("Testando visao por raio em todas as direcoes (sem cone)...")
	var player := PLAYER_SCENE.instantiate() as PlayerCharacter
	player.reads_local_input = false
	player.is_local_controller = false
	player.position = Vector3(0.0, 0.0, 400.0)
	add_child(player)
	var radius := PlayerCharacter.VIEW_RADIUS
	var behind_inside := player.can_see_position(player.position + Vector3(0.0, 1.0, radius - 1.0))
	var side_inside := player.can_see_position(player.position + Vector3(radius - 1.0, 1.0, 0.0))
	var outside := player.can_see_position(player.position + Vector3(0.0, 1.0, -(radius + 1.0)))
	var no_overlay := player.get_node_or_null("VisionArc") == null
	player.queue_free()
	if not behind_inside or not side_inside or outside or not no_overlay:
		push_error("FALHA: Visao deveria cobrir %.0f m em volta sem cone nem overlay; atras=%s lado=%s fora=%s sem_overlay=%s." % [radius, behind_inside, side_inside, outside, no_overlay])
		_mark_failure()
		return
	print("PASS: Jogador ve zumbis a ate %.0f m em qualquer direcao, sem cone." % radius)


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
	var torso := zombie.get_node("Model/Torso") as GeometryInstance3D
	var torso_material := torso.material_override as ShaderMaterial
	var dissolve := float(torso_material.get_shader_parameter(&"dissolve_amount")) if torso_material != null else 0.0
	var dust := zombie.get_node_or_null("DissolveDust") as CPUParticles3D
	# Regressao: instance uniform estourava o limite de 4096 instancias do renderer Compatibility.
	var shader_code := (load("res://shaders/zombie_dissolve.gdshader") as Shader).code
	if shader_code.contains("instance uniform"):
		push_error("FALHA: Shader de dissolucao nao pode usar instance uniform (limite de 4096 no Compatibility).")
		_mark_failure()
		zombie.queue_free()
		return
	if torso_material == null or dissolve <= 0.0 or dissolve >= 1.0 or dust == null:
		push_error("FALHA: Saida do FOV deveria desintegrar em po (shader dissolve=%.2f, po=%s)." % [dissolve, dust])
		_mark_failure()
		zombie.queue_free()
		return
	var sharing_while_fading := torso.material_override == ZombieDissolveVisual.material_for_color(torso_material.get_shader_parameter("albedo_color"))
	zombie.set_vision_visible(true)
	zombie.call("_update_visual_fade", 1.0)
	var shares_when_whole := torso.material_override == ZombieDissolveVisual.material_for_color(torso_material.get_shader_parameter("albedo_color"))
	if sharing_while_fading or not shares_when_whole:
		push_error("FALHA: Zumbi inteiro deveria usar material compartilhado e so o zumbi sumindo usar copia propria.")
		_mark_failure()
		zombie.queue_free()
		return
	zombie.set_vision_visible(false)
	zombie.call("_update_visual_fade", float(zombie.get("DISSOLVE_OUT_TIME")))
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
	# Fim das vidas agora deixa CAIDO (reanimavel), nao eliminado.
	if not player.is_downed or player.is_eliminated or player.lives != 0 or not player.visible:
		push_error("FALHA: Jogador deveria estar caido antes da nova onda.")
		_mark_failure()
		player.queue_free()
		return
	player.restore_wave_lives()
	if player.lives != 3 or player.is_downed or player.is_eliminated or not player.visible or player.health != player.max_health:
		push_error("FALHA: Nova onda deveria devolver 3 vidas e levantar o caido.")
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


func _test_crate_weapon_family() -> void:
	print("Testando familia de armas de crate com slot, desgaste, falha e quebra...")
	GameConfig.configure_local_players([GameConfig.create_keyboard_config(0)])
	if not InputMap.has_action("player_1_shotgun") or not InputMap.has_action("player_1_uzi") or not InputMap.has_action("player_1_magnum") or not InputMap.has_action("player_1_drop_weapon"):
		push_error("FALHA: Acoes das armas de crate deveriam estar mapeadas para o jogador 1.")
		_mark_failure()
		return
	var player := PLAYER_SCENE.instantiate() as PlayerCharacter
	player.name = "PlayerCrate"
	player.reads_local_input = false
	add_child(player)

	var dropped_kinds: Array[int] = []
	player.crate_weapon_dropped.connect(func(kind: int, _mag: int, _reserve: int, _durability: int) -> void:
		dropped_kinds.append(kind)
	)

	if WeaponStats.stats_for(WeaponStats.Kind.DOUBLE_BARREL).is_empty() or WeaponStats.stats_for(WeaponStats.Kind.CARBINE).is_empty():
		push_error("FALHA: Escopeta dupla e carabina deveriam ter stats na tabela.")
		_mark_failure()
		player.queue_free()
		return
	if int(WeaponStats.stats_for(WeaponStats.Kind.DOUBLE_BARREL)["pellets"]) != 12 or int(WeaponStats.stats_for(WeaponStats.Kind.CARBINE)["pellets"]) != 1:
		push_error("FALHA: Escopeta dupla deveria ter 12 pellets e carabina tiro unico.")
		_mark_failure()
		player.queue_free()
		return
	if player.take_crate_weapon(WeaponStats.Kind.SHOTGUN) != "granted":
		push_error("FALHA: Escopeta deveria entrar no slot livre do jogador.")
		_mark_failure()
		player.queue_free()
		return

	# Disparo de escopeta: 8 pellets, gasta 1 bala e 1 de durabilidade.
	player.current_weapon = PlayerCharacter.Weapon.SHOTGUN
	var pellets_before := _count_bullets()
	player.call("_fire_crate_weapon")
	var pellets_after := _count_bullets()
	if pellets_after - pellets_before != 8:
		push_error("FALHA: Escopeta deveria disparar 8 pellets; saiu %d." % (pellets_after - pellets_before))
		_mark_failure()
		player.queue_free()
		return
	var shot_state: Dictionary = player.weapon_slots.state_of(WeaponStats.Kind.SHOTGUN)
	var max_durability := int(WeaponStats.stats_for(WeaponStats.Kind.SHOTGUN)["max_durability"])
	if int(shot_state.get("mag", 0)) != 5 or int(shot_state.get("durability", 0)) != max_durability - 1:
		push_error("FALHA: Disparo deveria gastar 1 bala e 1 durabilidade; estado=%s." % shot_state)
		_mark_failure()
		player.queue_free()
		return

	# Arma degradada: abaixo do limiar a falha de disparo segue o seed fixo.
	var degraded_state: Dictionary = player.weapon_slots.state_of(WeaponStats.Kind.SHOTGUN)
	degraded_state["durability"] = int(WeaponStats.stats_for(WeaponStats.Kind.SHOTGUN)["degraded_below"]) - 1
	var jam_seed := _find_seed_for_roll(0.15)
	var reference := RandomNumberGenerator.new()
	reference.seed = jam_seed
	player.crate_weapon_rng.seed = jam_seed
	var degraded_before := _count_bullets()
	player.call("_fire_crate_weapon")
	var fired_pellets := _count_bullets() - degraded_before
	if reference.randf() < 0.15:
		if player.attack_cooldown <= 0.0 or fired_pellets != 0:
			push_error("FALHA: Falha de disparo deveria gastar cooldown e nao soltar pellets; pellets=%d." % fired_pellets)
			_mark_failure()
			player.queue_free()
			return
	else:
		if fired_pellets != 8:
			push_error("FALHA: Escopeta degradada sem falha deveria disparar 8 pellets; saiu %d." % fired_pellets)
			_mark_failure()
			player.queue_free()
			return

	# Quebra em 0: sai do slot, cai para a faca e solta pedacos voxel no chao.
	var final_state: Dictionary = player.weapon_slots.state_of(WeaponStats.Kind.SHOTGUN)
	final_state["durability"] = 1
	final_state["mag"] = 2
	player.crate_weapon_rng.seed = _find_seed_not_below_roll(0.15)
	player.call("_fire_crate_weapon")
	if player.weapon_slots.has_kind(WeaponStats.Kind.SHOTGUN) or player.current_weapon != PlayerCharacter.Weapon.KNIFE:
		push_error("FALHA: Arma em durabilidade 0 deveria quebrar e voltar para a faca.")
		_mark_failure()
		player.queue_free()
		return
	if _count_group_nodes("weapon_debris") == 0:
		push_error("FALHA: Quebra deveria spawnar pedacos voxel no grupo weapon_debris.")
		_mark_failure()
		player.queue_free()
		return

	# Drop manual: sinal carrega o estado e o slot esvazia.
	if player.take_crate_weapon(WeaponStats.Kind.UZI) != "granted":
		push_error("FALHA: Uzi deveria entrar no slot livre apos a quebra.")
		_mark_failure()
		player.queue_free()
		return
	player.current_weapon = PlayerCharacter.Weapon.UZI
	player.call("_drop_current_crate_weapon")
	if dropped_kinds != [WeaponStats.Kind.UZI] or player.weapon_slots.has_kind(WeaponStats.Kind.UZI):
		push_error("FALHA: Drop deveria emitir o estado e esvaziar o slot; dropados=%s." % dropped_kinds)
		_mark_failure()
		player.queue_free()
		return

	# Slot cheio: coletar outra arma troca (a antiga cai no chao).
	if player.take_ground_weapon(WeaponStats.Kind.MAGNUM, 6, 12, 30) != "granted":
		push_error("FALHA: Magnum deveria entrar no slot livre.")
		_mark_failure()
		player.queue_free()
		return
	var swapped := player.take_ground_weapon(WeaponStats.Kind.UZI, 20, 90, 100)
	if swapped != "swapped" or dropped_kinds != [WeaponStats.Kind.UZI, WeaponStats.Kind.MAGNUM]:
		push_error("FALHA: Pegar Uzi com slot cheio deveria trocar; resultado=%s dropados=%s." % [swapped, dropped_kinds])
		_mark_failure()
		player.queue_free()
		return

	# Estado de arma sincroniza no snapshot (server -> cliente).
	var sync_state: Dictionary = player.get_network_state()
	var client_player := PLAYER_SCENE.instantiate() as PlayerCharacter
	client_player.reads_local_input = false
	add_child(client_player)
	client_player.apply_network_state(sync_state)
	if not client_player.weapon_slots.has_kind(WeaponStats.Kind.UZI):
		push_error("FALHA: Inventario de armas deveria sincronizar pelo snapshot.")
		_mark_failure()
		player.queue_free()
		client_player.queue_free()
		return
	var client_state: Dictionary = client_player.weapon_slots.state_of(WeaponStats.Kind.UZI)
	var server_state: Dictionary = player.weapon_slots.state_of(WeaponStats.Kind.UZI)
	if int(client_state.get("reserve", -1)) != int(server_state.get("reserve", -2)):
		push_error("FALHA: Reserva sincronizada diverge: cliente=%s servidor=%s." % [client_state, server_state])
		_mark_failure()
		player.queue_free()
		client_player.queue_free()
		return

	player.queue_free()
	client_player.queue_free()
	print("PASS: Familia de armas de crate validada (coleta, pellets, falha, quebra, drop e sync).")


## Seed cujo primeiro randf() fica abaixo do limite (disparo com falha).
## Uso: var seed := _find_seed_for_roll(0.15)
func _find_seed_for_roll(roll_target: float) -> int:
	for seed in range(1, 400):
		var probe := RandomNumberGenerator.new()
		probe.seed = seed
		if probe.randf() < roll_target:
			return seed
	return 0


## Seed cujo primeiro randf() fica no ou acima do limite (disparo normal).
## Uso: var seed := _find_seed_not_below_roll(0.15)
func _find_seed_not_below_roll(roll_target: float) -> int:
	for seed in range(1, 400):
		var probe := RandomNumberGenerator.new()
		probe.seed = seed
		if probe.randf() >= roll_target:
			return seed
	return 0


## Conta nos com um dado script em um grupo. Uso: _count_group_nodes("weapon_debris")
func _count_group_nodes(group_name: String) -> int:
	var total := 0
	for node in get_tree().get_nodes_in_group(group_name):
		total += 1
	return total


## Conta balas ativas na cena (script bullet.gd). Uso: var n := _count_bullets()
func _count_bullets() -> int:
	var bullet_script: Script = BULLET_SCRIPT
	var total := 0
	for child in get_tree().current_scene.get_children():
		if child.get_script() == bullet_script:
			total += 1
	return total


func _test_player_sonar_pulse() -> void:
	print("Testando pulso sonar que revela zumbis...")
	GameConfig.configure_local_players([GameConfig.create_keyboard_config(0)])
	if not InputMap.has_action("player_1_sonar") or InputMap.action_get_events("player_1_sonar").is_empty():
		push_error("FALHA: A acao de sonar deveria estar mapeada para o jogador 1.")
		_mark_failure()
		return
	GameConfig.configure_local_players([{"device_type": "keyboard", "device_id": -1, "device_name": "Antigo", "bindings": {}}])
	if InputMap.action_get_events("player_1_sonar").is_empty():
		push_error("FALHA: Config antigo sem sonar deveria receber a tecla padrao.")
		_mark_failure()
		return
	GameConfig.configure_local_players([GameConfig.create_keyboard_config(0)])
	var client_player := PLAYER_SCENE.instantiate() as PlayerCharacter
	client_player.reads_local_input = false
	client_player.is_local_controller = true
	client_player.simulation_enabled = false
	client_player.input_action_prefix = "player_1_"
	add_child(client_player)
	Input.action_press("player_1_sonar")
	client_player.call("_poll_local_sonar")
	Input.action_release("player_1_sonar")
	if not client_player.is_sonar_active():
		push_error("FALHA: Sonar deveria funcionar no cliente mesmo sem leitura de movimento.")
		_mark_failure()
		client_player.queue_free()
		return
	client_player.queue_free()
	var player := PLAYER_SCENE.instantiate() as PlayerCharacter
	player.reads_local_input = false
	add_child(player)
	if player.is_sonar_active() or not player.get_sonar_text().begins_with("Sonar: "):
		push_error("FALHA: Sonar deveria iniciar inativo com contagem para o proximo pulso.")
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
	player.set("sonar_interval_timer", 0.01)
	player.call("_physics_process", 0.05)
	if not player.is_sonar_active():
		push_error("FALHA: Pulso passivo deveria disparar sozinho apos o intervalo.")
		_mark_failure()
		player.queue_free()
		return
	player.queue_free()
	print("PASS: Sonar dispara passivamente a cada intervalo e tambem manual.")


func _test_corpse_does_not_block_player() -> void:
	print("Testando cadaver que nao prende o jogador e some ao ser atingido...")
	var ragdoll := RAGDOLL_SCENE.instantiate() as Node3D
	add_child(ragdoll)
	ragdoll.call("setup", Vector3.ZERO, 0, 12345)
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.reads_local_input = false
	add_child(player)
	var torso := ragdoll.get_node("Torso") as RigidBody3D
	if torso.collision_layer != 32:
		push_error("FALHA: Cadaver deveria usar camada exclusiva 32; camada=%d." % torso.collision_layer)
		_mark_failure()
		ragdoll.queue_free()
		player.queue_free()
		return
	if torso.collision_layer & player.collision_mask != 0:
		push_error("FALHA: Cadaver nao deveria colidir com o jogador; mascara do jogador=%d." % player.collision_mask)
		_mark_failure()
		ragdoll.queue_free()
		player.queue_free()
		return
	ragdoll.call("take_damage", 35, Vector3.FORWARD, "bullet")
	if not ragdoll.is_queued_for_deletion():
		push_error("FALHA: Tiro no cadaver deveria remover o corpo do chao.")
		_mark_failure()
		ragdoll.queue_free()
		player.queue_free()
		return
	player.queue_free()
	print("PASS: Cadaver nao bloqueia o jogador e e removido a tiro.")


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
	z_far.call("_update_visual_fade", float(z_far.get("DISSOLVE_OUT_TIME")))
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
