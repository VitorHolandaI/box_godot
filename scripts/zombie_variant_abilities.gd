# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name ZombieVariantAbilities
extends RefCounted

## Habilidades das variantes que mudam a jogabilidade (nao so a aparencia):
## armored corta dano de tiro, bloater explode ao morrer e leaper da bote.
## Tudo roda onde o zumbi e simulado (servidor/partida local); o cliente ve o
## resultado pelo snapshot (posicao, vida) e toca o efeito visual pela morte.
## Uso:
##   amount = ZombieVariantAbilities.adjust_incoming_damage(zombie_type, amount, damage_kind)
##   ZombieVariantAbilities.bloater_burst(get_tree(), global_position, self)

const ARMORED_BULLET_FACTOR := 0.5
const BURST_RADIUS := 4.0
const BURST_PLAYER_DAMAGE := 40
const BURST_ZOMBIE_DAMAGE := 70
const BURST_DOOR_DAMAGE := 60
const LEAP_RANGE := 4.5
const LEAP_AIRTIME := 0.55
const LEAP_SPEED_CAP := 12.0
const LEAP_COOLDOWN := 3.5
const JUMP_MIN_RANGE := 4.0
const JUMP_MAX_RANGE := 12.0
const JUMP_AIRTIME := 1.4
const JUMP_SPEED_CAP := 12.0
const JUMP_COOLDOWN := 4.0
## Bloater explode sozinho colado no alvo (kamikaze) e da uma arrancada curta.
const BLOATER_DETONATE_DISTANCE := 1.8
const BLOATER_LUNGE_MAX_RANGE := 6.0
const BLOATER_LUNGE_SPEED := 7.0
const CHARGE_MIN_RANGE := 5.0
const CHARGE_MAX_RANGE := 14.0
const CHARGE_SPEED := 9.0
const CHARGE_DURATION := 1.1
const CHARGE_COOLDOWN := 6.0
const CHARGE_HIT_DAMAGE := 25
const CHARGE_KNOCKBACK := 11.0
const CHARGE_HIT_RADIUS := 1.7
const SPIT_MIN_RANGE := 4.0
const SPIT_MAX_RANGE := 12.0
const SPIT_COOLDOWN := 5.0
## Cuspidor para de andar a esta distancia do alvo para cuspir de longe.
const SPITTER_KEEP_DISTANCE := 8.0


## Dano de tiro no armored cai pela metade; faca e golpes batem cheio.
## extra_armor serve para quem herdou o colete sem ser do tipo ARMORED (coletor).
## Uso: var dano := ZombieVariantAbilities.adjust_incoming_damage(ZombieMutator.Type.ARMORED, 40, "bullet")
static func adjust_incoming_damage(zombie_type: int, amount: int, damage_kind: String, extra_armor: bool = false) -> int:
	if (zombie_type == ZombieMutator.Type.ARMORED or extra_armor) and damage_kind == "bullet":
		return maxi(roundi(float(amount) * ARMORED_BULLET_FACTOR), 1)
	return amount


## Explosao do bloater: fere jogadores, zumbis e portas no raio.
## Uso: ZombieVariantAbilities.bloater_burst(get_tree(), global_position, self)
static func bloater_burst(tree: SceneTree, origin: Vector3, source: Node) -> void:
	area_damage(tree, origin, BURST_RADIUS, BURST_PLAYER_DAMAGE, BURST_ZOMBIE_DAMAGE, BURST_DOOR_DAMAGE, source)


## Dano em area com queda pela distancia (100% no centro, 40% na borda) para
## jogadores, zumbis e portas; dano 0 pula o grupo. `source` nao se atinge.
## Uso: ZombieVariantAbilities.area_damage(get_tree(), pos, 6.0, 30, 0, 80, self)
static func area_damage(tree: SceneTree, origin: Vector3, radius: float, player_damage: int, zombie_damage: int, door_damage: int, source: Node) -> void:
	var damage_by_group := {"player": player_damage, "zombies": zombie_damage, "destructible_door": door_damage}
	for group_name in damage_by_group:
		var base_damage := int(damage_by_group[group_name])
		if base_damage <= 0:
			continue
		for node in tree.get_nodes_in_group(group_name):
			if node == source or not is_instance_valid(node) or not node.has_method("take_damage"):
				continue
			var offset := (node as Node3D).global_position - origin
			var distance := offset.length()
			if distance > radius:
				continue
			var falloff := 1.0 - distance / radius * 0.6
			var direction := offset.normalized() if distance > 0.01 else Vector3.UP
			node.take_damage(roundi(float(base_damage) * falloff), direction, "explosion", source)


## Arrancada generica: perto do alvo (entre min e max), no chao e fora da
## recarga, dispara para frente; enquanto dura, a perseguicao nao sobrescreve a
## velocidade. Leaper e charger sao arrancadas com parametros diferentes.
## Uso:
##   var boost := dash.update(delta, velocity, direction, distance, is_on_floor())
##   if dash.is_leaping(): velocity = boost
class DashState extends RefCounted:
	var min_range := 0.0
	var max_range := 4.5
	var dash_speed := 8.5
	var up_speed := 3.2
	var duration := 0.35
	var cooldown := 3.5
	var _cooldown_left := 0.0
	var _time_left := 0.0
	var _velocity := Vector3.ZERO

	func _init(range_min: float = 0.0, range_max: float = 4.5, speed: float = 8.5, up: float = 3.2, dash_duration: float = 0.35, dash_cooldown: float = 3.5) -> void:
		min_range = range_min
		max_range = range_max
		dash_speed = speed
		up_speed = up
		duration = dash_duration
		cooldown = dash_cooldown

	## Velocidade da arrancada neste tick, ou Vector3.ZERO quando nao arranca.
	## _gravity e may_launch existem para o bote balistico compartilhar a
	## chamada; a arrancada e rente ao chao e ignora a gravidade.
	func update(delta: float, current_velocity: Vector3, direction: Vector3, distance: float, on_floor: bool, _gravity: float = 22.0, may_launch: bool = true) -> Vector3:
		var step := maxf(delta, 0.0)
		_cooldown_left = maxf(_cooldown_left - step, 0.0)
		if _time_left > 0.0:
			_time_left -= step
			return Vector3(_velocity.x, current_velocity.y, _velocity.z) if _time_left > 0.0 else Vector3.ZERO
		if _cooldown_left > 0.0 or not on_floor or not may_launch or distance > max_range or distance < min_range:
			return Vector3.ZERO
		var flat := Vector3(direction.x, 0.0, direction.z).normalized()
		if flat.is_zero_approx():
			return Vector3.ZERO
		_velocity = flat * dash_speed + Vector3.UP * up_speed
		_time_left = duration
		_cooldown_left = cooldown
		return _velocity

	func is_leaping() -> bool:
		return _time_left > 0.0

	## Fora de recarga e parada: quem empresta a arrancada para outro tipo usa
	## isto para escolher entre varias. Uso: if state.is_ready(): ...
	func is_ready() -> bool:
		return not is_leaping() and _cooldown_left <= 0.0


## Bote/salto balistico: resolve o arco ate o alvo e mantem o voo ate
## aterrissar. A velocidade horizontal e distancia/tempo_de_voo (alveja onde
## o player esta) e o impulso vertical g*t/2 fecha o arco de volta ao chao,
## entao o zumbi nunca fica pendurado no ar com velocidade zerada.
## Uso: velocity = leap.update(delta, velocity, dir, dist, on_floor, gravity)
class ArcLeapState extends RefCounted:
	const MAX_FLIGHT_TIME := 1.6
	var min_range: float
	var max_range: float
	var airtime: float
	var speed_cap: float
	var cooldown: float
	var _cooldown_left := 0.0
	var _flying := false
	var _flight_time := 0.0
	var _launch := Vector3.ZERO

	func _init(range_min: float, range_max: float, jump_airtime: float, jump_speed_cap: float, dash_cooldown: float) -> void:
		min_range = range_min
		max_range = range_max
		airtime = jump_airtime
		speed_cap = jump_speed_cap
		cooldown = dash_cooldown

	## Velocidade deste tick: ZERO fora do bote; no lancamento, o impulso do
	## arco; em voo, horizontal preservada com o Y em queda livre (o caller
	## aplica a gravidade antes). may_launch=false bloqueia um novo bote
	## (alvo em outro nivel) sem abortar um voo em progresso.
	func update(delta: float, current_velocity: Vector3, direction: Vector3, distance: float, on_floor: bool, gravity: float = 22.0, may_launch: bool = true) -> Vector3:
		var step := maxf(delta, 0.0)
		_cooldown_left = maxf(_cooldown_left - step, 0.0)
		if _flying:
			_flight_time += step
			if (on_floor and _flight_time > 0.05) or _flight_time > MAX_FLIGHT_TIME:
				_flying = false
				return Vector3.ZERO
			return Vector3(_launch.x, current_velocity.y, _launch.z)
		if _cooldown_left > 0.0 or not on_floor or not may_launch or distance > max_range or distance < min_range:
			return Vector3.ZERO
		var flat := Vector3(direction.x, 0.0, direction.z).normalized()
		if flat.is_zero_approx():
			return Vector3.ZERO
		# Arco balistico: vh = d/t alcaca a posicao do alvo; vy = g*t/2
		# devolve o zumbi ao chao no mesmo instante. Cap evita vh absurdo
		# quando o bote dispara de muito perto.
		var flight := airtime
		var horizontal: float = minf(distance / flight, speed_cap)
		flight = maxf(distance / horizontal, 0.2)
		_launch = flat * horizontal + Vector3.UP * (gravity * flight * 0.5)
		_flying = true
		_flight_time = 0.0
		_cooldown_left = cooldown
		return _launch

	func is_leaping() -> bool:
		return _flying

	## Fora de recarga e parada (mesmo contrato do DashState.is_ready).
	func is_ready() -> bool:
		return not is_leaping() and _cooldown_left <= 0.0


## Bote do leaper: arco baixo e rapido de perto, pousando no alvo.
class LeapState extends ArcLeapState:
	func _init() -> void:
		super(0.0, ZombieVariantAbilities.LEAP_RANGE, ZombieVariantAbilities.LEAP_AIRTIME, ZombieVariantAbilities.LEAP_SPEED_CAP, ZombieVariantAbilities.LEAP_COOLDOWN)


## Pulo alto do saltador: arco de ~5 m de altura de 4 a 12 m do alvo.
class HighJumpState extends ArcLeapState:
	func _init() -> void:
		super(ZombieVariantAbilities.JUMP_MIN_RANGE, ZombieVariantAbilities.JUMP_MAX_RANGE, ZombieVariantAbilities.JUMP_AIRTIME, ZombieVariantAbilities.JUMP_SPEED_CAP, ZombieVariantAbilities.JUMP_COOLDOWN)


## Arrancada do bloater kamikaze: curta e baixa, para se jogar no jogador.
class BloaterLungeState extends DashState:
	func _init() -> void:
		super(ZombieVariantAbilities.BLOATER_DETONATE_DISTANCE, ZombieVariantAbilities.BLOATER_LUNGE_MAX_RANGE, ZombieVariantAbilities.BLOATER_LUNGE_SPEED, 2.0, 0.5, 3.0)


## Investida do charger: arranca de longe, rente ao chao, por mais tempo.
class ChargeState extends DashState:
	func _init() -> void:
		super(ZombieVariantAbilities.CHARGE_MIN_RANGE, ZombieVariantAbilities.CHARGE_MAX_RANGE, ZombieVariantAbilities.CHARGE_SPEED, 0.0, ZombieVariantAbilities.CHARGE_DURATION, ZombieVariantAbilities.CHARGE_COOLDOWN)


## Cuspe do cuspidor: dispara no alcance, com linha de visao e fora da recarga.
## Uso: if spit.update(delta, distance, _has_line_of_sight(target)): cuspir()
class SpitState extends RefCounted:
	var _cooldown_left := 0.0

	func update(delta: float, distance: float, has_line_of_sight: bool) -> bool:
		_cooldown_left = maxf(_cooldown_left - maxf(delta, 0.0), 0.0)
		if _cooldown_left > 0.0 or not has_line_of_sight:
			return false
		if distance < ZombieVariantAbilities.SPIT_MIN_RANGE or distance > ZombieVariantAbilities.SPIT_MAX_RANGE:
			return false
		_cooldown_left = ZombieVariantAbilities.SPIT_COOLDOWN
		return true


## Charger acertou o jogador: dano e arremesso na direcao da corrida.
## Uso: ZombieVariantAbilities.charge_impact(player, direction)
static func charge_impact(player: Node, direction: Vector3) -> void:
	if not is_instance_valid(player) or not player.has_method("take_damage"):
		return
	var flat := Vector3(direction.x, 0.0, direction.z).normalized()
	player.take_damage(CHARGE_HIT_DAMAGE, flat, "melee", null)
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity += flat * CHARGE_KNOCKBACK + Vector3.UP * 4.0
