# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name EscortFamilyMember
extends CharacterBody3D

## Um sobrevivente da familia que o grupo escolta pelo mapa. O corpo usa os
## contratos que o zumbi ja usa ao cacar: entra no grupo "escort_human",
## expoe health/is_eliminated (ZombieFlockCoordinator.get_living_players) e
## atende take_damage(dano, direcao, origem, atacante). So a simulacao do
## servidor anda este corpo; nos outros peers e um fantasma posicionado por
## EscortDirector.replicate_state.
##
## O andar e o MESMO do zumbi (decisao do usuario, 2026-09-25): a direcao vai no
## alvo, o ZombieWallDetour contorna predio encostado e o ZombieIndoorRouter acha
## porta/escada quando o destino esta dentro de um predio. A unica diferenca e o
## alvo: um ponto parado da rota em vez de um jogador perseguido.
## Uso: EscortFamilyMember.new_profile(root, "Familiar-0", Color.CRIMSON)

signal knocked_down(member: EscortFamilyMember)

## Modelo identico ao do jogador (player.tscn), so o subtree "Model": boneco
## reconhecivel, com bracos e pernas animaveis, sem script nem colisao do
## PlayerCharacter.
const PLAYER_SCENE := preload("res://scenes/player.tscn")
## Componentes de locomocao compartilhados com o zombie.gd (nao reimplementar:
## a versao caseira ficava presa em quina de lote).
const WALL_DETOUR_SCRIPT: GDScript = preload("res://scripts/zombie_wall_detour.gd")
const PROGRESS_WATCH_SCRIPT: GDScript = preload("res://scripts/zombie_progress_watch.gd")
const INDOOR_ROUTER_SCRIPT: GDScript = preload("res://scripts/zombie_indoor_router.gd")
const BULLET_SCENE := preload("res://scenes/bullet.tscn")
const DEFAULT_WALK_SPEED := 3.0
## Pistola do civil: mesmo modelo da do player, mas ritmo civil de tiro (nao e
## metralhadora — 3 familiares a 4 tiros/s viravam uma parede de bala) e dano
## menor que o do jogador. Municao infinita: nunca recarrega.
const SHOOT_INTERVAL := 0.9
const SHOOT_RANGE := 32.0
const SHOOT_DAMAGE := 12
const MUZZLE_FLASH_SECONDS := 0.06
## Mira igual ao bot do SWAT: gira o corpo na direcao do alvo e so atira com a
## arma ja apontada (dot >= AIM_ALIGNMENT, ~20 graus). Andando, ele mira e
## continua seguindo a rota com o corpo virado para a ameaca.
## Pose de descanso do civil com a arma na mao (braco baixo, na cintura): a
## pistola fica presa na mao, nunca flutuando ao lado do corpo.
const REST_LEFT_ARM := Vector3(0.72, 0.0, 0.46)
const REST_RIGHT_ARM := Vector3(0.62, 0.0, -0.32)
const AIM_TURN_SPEED := 9.0
const AIM_ALIGNMENT := 0.94
## Pose de mira da pistola, copiada do player_animator.gd (cur_weapon == 1):
## os dois bracos sobem e a arma e ancorada na mao direita.
const AIM_LEFT_ARM := Vector3(1.28, 0.0, 0.38)
const AIM_RIGHT_ARM := Vector3(1.28, 0.0, -0.38)
const HAND_ANCHOR_LOCAL := Vector3(0.0, -0.72, -0.12)
## A bala nasce a frente do cano (mesmo offset do _fire_pistol do player).
const FIRE_MUZZLE_OFFSET := 0.12
## Chegada de waypoint: apertado de proposito. Com o raio largo do bot de PVP
## (4 m) o civil trocava de trecho longe da esquina e cortava a diagonal ate a
## porta, batendo na parede ao lado do vao.
const ARRIVE_RADIUS := 2.0
## Distancia do waypoint em que a formacao fecha (vao de porta estreito).
const FORMATION_TIGHTEN_DISTANCE := 5.0
## Chegada no funil da porta: o civil so troca de waypoint quando chega DE
## VERDADE. Com os 2 m do ARRIVE_RADIUS ele dava o ponto por alcancado ainda
## torto e entrava no vao na diagonal, raspando a ombreira.
const FUNNEL_ARRIVE_RADIUS := 0.6
## Sem progresso por este tempo e o civil e resgatado para o waypoint atual.
## A casa e uma caixa fechada: empurrado pela horda para o lado errado, o civil
## nao reencontra a porta (nao ha navmesh) e trava o checkpoint inteiro, que so
## fecha quando TODOS chegam.
const RESCUE_SECONDS := 10.0
## Mesmo FEET_OFFSET do zombie.gd: o roteador interno decide por onde entrar
## pelo ponto no chao, nao pelo centro do corpo.
const FEET_OFFSET := 1.1
## Distancia em que a familia se assusta (so alimenta HUD/diagnostico: o susto
## NAO congela mais o passo — familiar parado no meio da horda morria parado).
const PANIC_RADIUS := 5.0
## Cadencia do passo na animacao (aproxima 8,5 do PlayerAnimator no trote).
const WALK_SWING_SPEED := 7.5
const WALK_SWING_AMPLITUDE := 0.6
## Tom de pele padrao dos civis (o mesmo do jogador).
const SKIN_TONE := Color(0.82, 0.6, 0.45)
## Camada de fisica do civil: cenario 1, jogador 2, zumbi 4, limite 16. A 8
## fica livre para o familiar nao empurrar ninguem.
const COLLISION_LAYER := 8

var tint := Color.WHITE
## Escala do modelo: crianca menor, adulto 1.0 (ver FAMILY_ROLES no director).
var model_scale := 1.0
## Vaga na formacao: deslocamento lateral da rota, para o trio caminhar em
## grupo e nao em fila indiana (ver EscortDirector.FORMATION_OFFSETS).
var formation_offset := 0.0
## Variacao leve de passo por membro: o grupo se estica e encolhe em vez de
## andar colado.
var speed_factor := 1.0
## Empurrao forcado do zumbi (puxador/lingua); mesma semantica do player.
var forced_move_velocity := Vector3.ZERO
var forced_move_time := 0.0
var health := 120
var max_health := 120
## Modo teste: ignora dano (ver EscortDirector.TEST_INVULNERABLE). Desligar
## quando o balanceamento de verdade comecar.
var invulnerable := false
var is_eliminated := false
## Alcancou o ponto B: para de andar e sai da lista de cacadores da horda.
var escaped := false
## Enquanto false, a familia espera o grupo chegar e apertar E; ver director.
var walking := false
## Antes da missao comecar a familia nao entra na lista de cacadores da horda.
var targetable := false
## Rota em waypoints de rua (o director monta e entrega igual para o trio).
var route: Array[Vector3] = []
## Indices da rota onde o civil fica PASSIVO (nao mira/atira): o ponto de parada
## dentro da casa e a saida dela. Vem do director.
var no_fire_indices := {}
## Indices do FUNIL da porta: ali o civil anda em fila (sem vaga lateral) e so
## troca de waypoint ao chegar de verdade. Vem do director.
var funnel_indices := {}
## Tempo restante sem atirar logo apos sair da casa (ver EXIT_HOLD_FIRE_SECONDS):
## nesse intervalo o civil so anda, para nao voltar pra dentro e atirar de la.
var hold_fire_seconds := 0.0
## Indice da rota onde a familia para no checkpoint (-1 = vai ate o fim). O
## director avanca este indice quando o jogador aperta E na zona segura.
var halt_route_index := -1
var walk_speed := DEFAULT_WALK_SPEED
## false no remoto: corpo projetado pelo estado do servidor, nao simula.
var simulates := false
## Cadencia restante do tiro da pistola (dono: servidor).
var shoot_cooldown := 0.0

var _model: Node3D = null
var _left_arm: Node3D = null
var _right_arm: Node3D = null
var _left_leg: Node3D = null
var _right_leg: Node3D = null
var _walk_time := 0.0
var _muzzle_flash: Node3D = null
var _muzzle_flash_time := 0.0
## Poses: dono da arma pra ancorar a pistola na mao (mira e descanso).
var _weapon_holder: Node3D = null
## Alvo que o civil esta mirando neste tick; enquanto valer, o yaw e da mira
## (nao da rota). Ver _defend/_walk_along_route.
var _aim_target: Node3D = null
## Diagnostico (--escort-debug): ultimo collider encostado no move_and_slide.
var _debug_touch := ""
## Waypoint atual da rota, monotonico (mesma licao do bot de PVP: voltar a
## recalcular "o proximo" fazia o NPC ir e voltar no limite de chegada).
var _route_index := 0
var _wall_detour = WALL_DETOUR_SCRIPT.new()
var _progress_watch = PROGRESS_WATCH_SCRIPT.new()
var _indoor_router = INDOOR_ROUTER_SCRIPT.new()


## Cria um CIVIL: mesma malha base do jogador, mas sem kit militar (capacete,
## colete, mochila, cinto, arma, faca) e repintado (blusa, calca, pele, sapato).
## Uso: EscortFamilyMember.new_civilian(root, "Familiar-Mae", Color(0.85,0.35,0.45), 0.96)
static func new_civilian(scene_root: Node, role_name: String, tint: Color, model_scale: float) -> EscortFamilyMember:
	var member := EscortFamilyMember.new()
	member.name = role_name
	member.simulates = true
	member.tint = tint
	member.model_scale = model_scale
	member.add_child(_make_body_shape())
	member.add_child(_make_civilian_model(tint, model_scale))
	# Nome legivel e o casamento do estado no cliente; os auto-renames
	# @CharacterBody3D@N quebrariam o matching por nome.
	scene_root.add_child(member, true)
	return member


static func _make_body_shape() -> CollisionShape3D:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.4
	var node := CollisionShape3D.new()
	node.shape = capsule
	node.name = "FamiliarShape"
	node.position = Vector3(0.0, 0.7, 0.0)
	return node


## Extrai o "Model" do player.tscn sem instanciar o jogador de verdade (a
## template nunca entra na arvore, entao o PlayerCharacter nao roda _ready nem
## registra input/colisao) e o transforma em civil.
static func _make_civilian_model(tint: Color, model_scale: float) -> Node3D:
	var template := PLAYER_SCENE.instantiate()
	var model := template.get_node_or_null("Model") as Node3D
	if model == null:
		template.free()
		var fallback := MeshInstance3D.new()
		fallback.name = "Model"
		fallback.mesh = CapsuleMesh.new()
		return fallback
	template.remove_child(model)
	template.free()
	model.name = "Model"
	_strip_military_kit(model)
	_paint_civilian(model, tint)
	# No player.tscn a Pistol nasce `visible = false` (o PlayerCharacter liga ao
	# equipar). O civil nao e PlayerCharacter: sem isto ele atira com a arma
	# invisivel na mao.
	var pistol := model.get_node_or_null("Weapons/Pistol") as Node3D
	if pistol != null:
		pistol.visible = true
	model.scale = Vector3.ONE * model_scale
	return model


## Tira o que faz o jogador parecer soldado: capacete, viseira, colete, cinto,
## mochila e faca. A pistola (Model/Weapons) fica: a familia agora anda armada.
static func _strip_military_kit(model: Node3D) -> void:
	for path in ["Head/Helmet", "Head/HelmetRim", "Vest", "Belt", "Backpack", "RightArm/Knife"]:
		var part := model.get_node_or_null(path) as Node3D
		if part == null:
			continue
		part.get_parent().remove_child(part)
		part.free()


## Repinta o civil: blusa na cor da familia, calca escura, pele e sapato.
static func _paint_civilian(model: Node3D, tint: Color) -> void:
	var shirt := _flat_material(tint)
	var pants := _flat_material(tint.darkened(0.55))
	var skin := _flat_material(SKIN_TONE)
	var shoes := _flat_material(Color(0.16, 0.13, 0.11))
	for path in ["Head", "Torso", "LeftArm/Mesh", "RightArm/Mesh", "LeftLeg/Mesh", "RightLeg/Mesh", "LeftBoot", "RightBoot"]:
		var part := model.get_node_or_null(path)
		if part == null:
			continue
		var material := shirt
		if path.begins_with("Head"):
			material = skin
		elif path.begins_with("LeftArm") or path.begins_with("RightArm"):
			material = skin
		elif path.begins_with("LeftLeg") or path.begins_with("RightLeg"):
			material = pants
		elif path.ends_with("Boot"):
			material = shoes
		part.set("material_override", material)


static func _flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material


func _ready() -> void:
	add_to_group("escort_human")
	# Camada propria (8): o civil e barrado pelo cenario (mascara 1), mas nao
	# colide com jogador, zumbi nem com os outros familiares. Dois corpos na
	# camada 1 se empurravam e o trio andava torto.
	collision_layer = COLLISION_LAYER
	collision_mask = 1
	_bind_player_model_limbs()
	_refresh_visibility()


func _physics_process(delta: float) -> void:
	if not simulates or is_eliminated or escaped:
		velocity = Vector3.ZERO
		_animate_walk(delta, false)
		return
	# Atira enquanto anda E enquanto espera (no checkpoint, pela porta/vao).
	_defend(delta)
	if _apply_forced_move(delta):
		return
	if not walking:
		_stop(delta)
		return
	if has_reached_halt():
		_stop(delta)
		return
	_walk_along_route(delta)


## Defesa com a pistola (municao infinita), no estilo do bot do SWAT: escolhe o
## zumbi vivo mais proximo com linha livre, GIRA o corpo e o bracos para ele
## (pose de mira do player_animator) e so atira com a arma apontada, soltando
## uma bala de verdade do cano. Roda so na simulacao (servidor).
func _defend(delta: float) -> void:
	shoot_cooldown = maxf(shoot_cooldown - delta, 0.0)
	hold_fire_seconds = maxf(hold_fire_seconds - delta, 0.0)
	_update_muzzle_flash(delta)
	# Passivo esperando na casa (parado), no trecho de saida e durante o
	# hold-fire pos-saida: prioridade e andar e se afastar, nao travar mirando o
	# vao com a horda em volta (podem voltar pra dentro e atirar de la).
	if not walking or hold_fire_seconds > 0.0 or no_fire_indices.has(_route_index):
		_aim_target = null
		_apply_rest_pose(delta)
		return
	var target := _nearest_zombie_in_sight()
	if target == null:
		_aim_target = null
		_apply_rest_pose(delta)
		return
	_aim_target = target
	_apply_pistol_aim_pose(delta)
	var origin := _muzzle_origin()
	var aim := target.global_position + Vector3.UP * 1.0 - origin
	aim.y = 0.0
	if aim.length_squared() < 0.0001:
		return
	var aim_direction := aim.normalized()
	rotation.y = lerp_angle(rotation.y, atan2(-aim_direction.x, -aim_direction.z), minf(delta * AIM_TURN_SPEED, 1.0))
	if shoot_cooldown > 0.0:
		return
	if (-global_transform.basis.z).dot(aim_direction) < AIM_ALIGNMENT:
		return
	_fire_bullet(origin, aim_direction)
	shoot_cooldown = SHOOT_INTERVAL
	_muzzle_flash_time = MUZZLE_FLASH_SECONDS


## Bala real saindo do cano (mesmo BULLET_SCENE do player), com o visual
## replicado para os clientes no servidor. Uso: interno de _defend.
func _fire_bullet(origin: Vector3, direction: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		# Runner de teste/headless sem current_scene: usa a raiz da arvore.
		scene = get_tree().root
	if scene == null:
		return
	var bullet := BULLET_SCENE.instantiate() as Node3D
	scene.add_child(bullet)
	bullet.global_position = origin + direction * FIRE_MUZZLE_OFFSET
	bullet.setup(direction, SHOOT_DAMAGE, true, self)
	if NetworkSession.is_server() and scene.has_method("replicate_bullet_visual"):
		scene.call("replicate_bullet_visual", bullet.global_position, direction)


## Pose de mira da pistola (player_animator: bracos sobem e a arma gruda na mao
## direita). Uso: interno de _defend.
func _apply_pistol_aim_pose(delta: float) -> void:
	if _left_arm != null:
		_left_arm.rotation = _left_arm.rotation.lerp(AIM_LEFT_ARM, minf(delta * 12.0, 1.0))
	if _right_arm != null:
		_right_arm.rotation = _right_arm.rotation.lerp(AIM_RIGHT_ARM, minf(delta * 12.0, 1.0))
	_anchor_weapon_to_hand(delta)


## Prende a pistola na ponta do braco direito, como o player com a arma na mao.
func _anchor_weapon_to_hand(delta: float) -> void:
	if _right_arm == null or _weapon_holder == null or not _weapon_holder.is_inside_tree():
		return
	var hand := _right_arm.global_position + _right_arm.global_transform.basis * HAND_ANCHOR_LOCAL
	_weapon_holder.global_position = _weapon_holder.global_position.lerp(hand, minf(delta * 18.0, 1.0))


## Sem alvo: bracos na pose de descanso (arma baixa, na mao) e a pistola
## continua ancorada na mao — nunca solta/flutuando ao lado do corpo.
func _apply_rest_pose(delta: float) -> void:
	if _left_arm != null:
		_left_arm.rotation = _left_arm.rotation.lerp(REST_LEFT_ARM, minf(delta * 10.0, 1.0))
	if _right_arm != null:
		_right_arm.rotation = _right_arm.rotation.lerp(REST_RIGHT_ARM, minf(delta * 10.0, 1.0))
	_anchor_weapon_to_hand(delta)


func _nearest_zombie_in_sight() -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	var best: Node3D = null
	var best_distance := SHOOT_RANGE
	for node in tree.get_nodes_in_group("zombies"):
		var zombie := node as Node3D
		if zombie == null or not is_instance_valid(zombie):
			continue
		if bool(zombie.get("is_dead")) or int(zombie.get("health")) <= 0:
			continue
		var distance := global_position.distance_to(zombie.global_position)
		if distance > best_distance or not _has_line_of_sight_to(zombie):
			continue
		best = zombie
		best_distance = distance
	return best


## Linha de tiro livre ate o zumbi (so cenario estatico bloqueia; os corpos sao
## ignorados para o civil nao deixar de atirar por causa de outro bicho).
func _has_line_of_sight_to(target: Node3D) -> bool:
	var world := get_world_3d()
	if world == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(_muzzle_origin(), target.global_position + Vector3.UP * 1.0, 1)
	query.exclude = [get_rid()]
	return world.direct_space_state.intersect_ray(query).is_empty()


func _muzzle_origin() -> Vector3:
	if _muzzle_flash != null:
		return _muzzle_flash.global_position
	return global_position + Vector3.UP * 1.2


func _update_muzzle_flash(delta: float) -> void:
	_muzzle_flash_time = maxf(_muzzle_flash_time - delta, 0.0)
	if _muzzle_flash != null:
		_muzzle_flash.visible = _muzzle_flash_time > 0.0


## Chegou no waypoint do checkpoint e parou. Uso: diretor espera isto de todos
## os vivos antes de abrir a zona segura.
func has_reached_halt() -> bool:
	return halt_route_index >= 0 and _route_index > halt_route_index


## Leitura pura do susto (HUD/diagnostico). Uso: member.is_panicked()
func is_panicked() -> bool:
	return _living_zombie_within_panic_radius()


## Zumbi arrastando: enquanto durar o empurrao, ele manda no movimento (mesmo
## tratamento do PlayerCharacter: x/z forcados, y da fisica). Devolve true
## quando consumiu o tick. Uso: if _apply_forced_move(delta): return
func _apply_forced_move(delta: float) -> bool:
	if forced_move_time <= 0.0:
		return false
	forced_move_time = maxf(forced_move_time - delta, 0.0)
	velocity = Vector3(forced_move_velocity.x, velocity.y, forced_move_velocity.z)
	move_and_slide()
	_animate_walk(delta, false)
	return true


func take_damage(amount: int, _direction: Vector3, _source_kind: String, attacker: Variant = null) -> void:
	if invulnerable:
		# Modo teste (EscortDirector.TEST_INVULNERABLE): a familia nao morre
		# enquanto a safe zone/checkpoints nao existem, senao a escolta acaba
		# no primeiro bolsao de zumbi e nao da para testar a rota.
		return
	if is_eliminated or escaped or amount <= 0:
		return
	health = maxi(health - amount, 0)
	if health > 0:
		return
	is_eliminated = true
	knocked_down.emit(self)


## Contrato de alvo do zumbi (puxador/lingua arrastam a vitima): o civil tem
## que aceitar o mesmo empurrao forcado que o PlayerCharacter, senao o zumbi
## estoura "nonexistent function apply_forced_move" ao cacar um familiar.
## Uso: target.apply_forced_move(pull, 0.2)
func apply_forced_move(forced_velocity: Vector3, seconds: float) -> void:
	forced_move_velocity = Vector3(forced_velocity.x, 0.0, forced_velocity.z)
	forced_move_time = maxf(seconds, 0.0)


## Estado copiado do servidor: posicao/vida dos fantasmas em cada cliente.
## Uso: member.replicate_state(diretor.state_for_network())
func replicate_state(state: Dictionary) -> void:
	global_position = Vector3(float(state.get("x", global_position.x)), float(state.get("y", global_position.y)), float(state.get("z", global_position.z)))
	health = int(state.get("health", health))
	escaped = bool(state.get("escaped", escaped))
	walking = bool(state.get("walking", walking))
	var server_eliminated := bool(state.get("eliminated", is_eliminated))
	if server_eliminated != is_eliminated:
		is_eliminated = server_eliminated
	_refresh_visibility()


## Anda ate o waypoint atual com a locomotiva do zumbi: direcao no alvo,
## desvio de muro do ZombieWallDetour e porta/escada do ZombieIndoorRouter
## (o ultimo trecho da rota entra na base).
func _walk_along_route(delta: float) -> void:
	var target: Variant = _current_waypoint()
	if target == null:
		_stop(delta)
		return
	var goal := target as Vector3
	var planar := goal - global_position
	planar.y = 0.0
	if planar.length() <= _arrive_radius():
		_advance_waypoint()
		target = _current_waypoint()
		if target == null:
			_stop(delta)
			return
		goal = target as Vector3
		planar = goal - global_position
		planar.y = 0.0
	var lateral := _lateral_offset(Vector3(planar.x, 0.0, planar.z)) * _formation_scale()
	var desired := Vector3(planar.x + lateral.x, 0.0, planar.z + lateral.y)
	_progress_watch.update(delta, global_position, goal)
	if _progress_watch.no_progress_seconds >= RESCUE_SECONDS:
		global_position = Vector3(goal.x, global_position.y, goal.z)
		_progress_watch.reset()
		_wall_detour.reset()
		_indoor_router.invalidate()
		return
	var feet := global_position - Vector3.UP * FEET_OFFSET
	var direction := desired.normalized() if desired.length_squared() > 0.0001 else Vector3.ZERO
	var indoor_route := false
	if _should_use_indoor_router():
		# So no trecho final: o roteador projeta o alvo no navmesh do predio e,
		# com o civil longe, devolveria a entrada da base como primeiro ponto
		# (o trio cortaria a cidade em diagonal, por dentro dos lotes).
		var target_feet := goal - Vector3.UP * FEET_OFFSET
		var router_waypoint: Vector3 = _indoor_router.next_waypoint(get_tree(), feet, target_feet, delta)
		indoor_route = _indoor_router.has_route
		if indoor_route:
			direction = _chase_direction(feet, router_waypoint, desired)
	if not indoor_route:
		var line_clear: bool = _wall_detour.is_active() and _has_line_to(goal)
		var wall_normal := get_wall_normal() if is_on_wall() else Vector3.ZERO
		direction = _wall_detour.steer(delta, global_position, direction, _progress_watch.blocked_seconds, wall_normal, line_clear)
	direction.y = 0.0
	direction = direction.normalized()
	velocity = direction * walk_speed * speed_factor
	move_and_slide()
	_track_touch()
	_animate_walk(delta, true)
	# Godot usa -Z como frente; mesma convencao do PlayerCharacter
	# (player.gd: atan2(-direction.x, -direction.z)). Com atan2(x, z) o civil
	# andava de costas. Com alvo na mira o yaw e da mira (_defend), nao da rota:
	# ele anda de lado atirando, como o bot do SWAT.
	if _aim_target == null or not is_instance_valid(_aim_target):
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(delta * 8.0, 1.0))


## O roteador interno (porta/escada) so vale no trecho final, quando o alvo e o
## ponto dentro da base. Uso: interno de _walk_along_route.
func _should_use_indoor_router() -> bool:
	return not route.is_empty() and _route_index >= maxi(route.size() - 1, 0)


## Direcao horizontal deste tick: na rua e a direcao desejada (ja com a vaga da
## formacao); com o roteador interno valendo, vai no waypoint que ele devolve
## (saida de comodo, escada, vao de porta). Uso: interno de _walk_along_route.
func _chase_direction(feet: Vector3, router_waypoint: Vector3, desired: Vector3) -> Vector3:
	var fallback := desired.normalized() if desired.length_squared() > 0.0001 else Vector3.ZERO
	if not _indoor_router.has_route:
		return fallback
	var to_waypoint := router_waypoint - feet
	to_waypoint.y = 0.0
	if to_waypoint.length_squared() < 0.0001:
		return fallback
	return to_waypoint.normalized()


## Troca de waypoint: zera medidores e rota interna (o desvio e o "preso" sao
## do trecho antigo; carregar isso para o novo fazia o civil desviar do nada).
func _advance_waypoint() -> void:
	var next_index := mini(_route_index + 1, route.size())
	if next_index == _route_index:
		return
	_route_index = next_index
	_progress_watch.reset()
	_wall_detour.reset()
	_indoor_router.invalidate()


func _stop(delta: float) -> void:
	velocity = Vector3.ZERO
	move_and_slide()
	_animate_walk(delta, false)


## Linha livre de cenario estatico ate um ponto (mesma sonda do zombie.gd; o
## ZombieWallDetour so solta o desvio quando ela fica livre).
func _has_line_to(point: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 1.2
	var query := PhysicsRayQueryParameters3D.create(from, point + Vector3.UP * 1.0, 1)
	query.exclude = [get_rid()]
	return space.intersect_ray(query).is_empty()


func _track_touch() -> void:
	_debug_touch = ""
	for collision_index in get_slide_collision_count():
		var collider := get_slide_collision(collision_index).get_collider()
		if collider is Node:
			_debug_touch = String((collider as Node).name)


## Waypoint atual da rota. Rota esgotada devolve o ULTIMO ponto (nao null):
## o raio de avanco (4 m) e maior que o raio de chegada do diretor (2,5 m),
## entao parar no fim deixava o civil a 4 m da porta sem nunca "chegar".
func _current_waypoint() -> Variant:
	if route.is_empty():
		return null
	if _route_index >= route.size():
		return route[route.size() - 1]
	return route[_route_index]


## Deslocamento lateral da formacao, perpendicular ao rumo do waypoint. Mantem
## o trio lado a lado em vez de um atras do outro.
func _lateral_offset(planar: Vector3) -> Vector2:
	if is_zero_approx(formation_offset) or planar.length_squared() < 0.0001:
		return Vector2.ZERO
	var side := Vector2(-planar.z, planar.x).normalized()
	return side * formation_offset


## Fecha a formacao perto do waypoint atual: o vao da porta da casinha tem
## ~2,6 m e dois corpos com 1,2 m de vaga batiam na ombreira em vez de passar.
## Tambem vale para a ultima perna da base (mesma geometria de vao).
func _formation_scale() -> float:
	if route.is_empty():
		return 1.0
	# No funil da porta a fila e obrigatoria, mesmo longe do ponto.
	if funnel_indices.has(_route_index):
		return 0.0
	if _route_index >= maxi(route.size() - 2, 0):
		return 0.0
	var target: Variant = _current_waypoint()
	if target == null:
		return 1.0
	var goal := target as Vector3
	var distance := Vector2(goal.x - global_position.x, goal.z - global_position.z).length()
	return 0.0 if distance <= FORMATION_TIGHTEN_DISTANCE else 1.0


## Raio de chegada do waypoint atual: apertado dentro do funil da porta, normal
## na rua. Uso: if planar.length() <= _arrive_radius(): _advance_waypoint()
func _arrive_radius() -> float:
	return FUNNEL_ARRIVE_RADIUS if funnel_indices.has(_route_index) else ARRIVE_RADIUS


## Susto com zumbi vivo perto (medo). Uso: member.is_panicked()
func _living_zombie_within_panic_radius() -> bool:
	if not simulates:
		return false
	var tree := get_tree()
	if tree == null:
		return false
	for zombie in tree.get_nodes_in_group("zombies"):
		var zombie_body := zombie as Node3D
		if zombie_body == null or not is_instance_valid(zombie_body):
			continue
		if global_position.distance_to(zombie_body.global_position) <= PANIC_RADIUS:
			return true
	return false


## Passo balancando bracos e pernas no ritmo do andar (o jogador usa
## PlayerAnimator; aqui uma versao minima evita depender dos campos dele).
func _animate_walk(delta: float, is_walking: bool) -> void:
	if _model == null:
		return
	if is_walking:
		_walk_time += delta * WALK_SWING_SPEED
	else:
		_walk_time = lerpf(_walk_time, roundf(_walk_time / PI) * PI, minf(delta * 6.0, 1.0))
	var swing := sin(_walk_time) * WALK_SWING_AMPLITUDE if is_walking else 0.0
	if _left_leg != null:
		_left_leg.rotation.x = swing
	if _right_leg != null:
		_right_leg.rotation.x = -swing
	# Bracos NAO balancam: quem manda neles e a pose de mira/descanso do _defend,
	# senao o swing tirava a pistola da mao (arma flutuando na cintura).


func _bind_player_model_limbs() -> void:
	_model = get_node_or_null("Model") as Node3D
	if _model == null:
		return
	_left_arm = _model.get_node_or_null("LeftArm") as Node3D
	_right_arm = _model.get_node_or_null("RightArm") as Node3D
	_left_leg = _model.get_node_or_null("LeftLeg") as Node3D
	_right_leg = _model.get_node_or_null("RightLeg") as Node3D
	_muzzle_flash = _model.get_node_or_null("Weapons/Pistol/MuzzleFlash") as Node3D
	if _muzzle_flash != null:
		_muzzle_flash.visible = false
	_weapon_holder = _model.get_node_or_null("Weapons") as Node3D
	if _weapon_holder != null:
		# Nasce com a arma ja na mao (o cenario nasce flutuando na cintura).
		_anchor_weapon_to_hand(1.0)


func _refresh_visibility() -> void:
	if _model != null:
		_model.visible = not is_eliminated
