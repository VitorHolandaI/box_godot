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
const LEAP_SPEED := 8.5
const LEAP_UP_SPEED := 3.2
const LEAP_DURATION := 0.35
const LEAP_COOLDOWN := 3.5


## Dano de tiro no armored cai pela metade; faca e golpes batem cheio.
## Uso: var dano := ZombieVariantAbilities.adjust_incoming_damage(ZombieMutator.Type.ARMORED, 40, "bullet")
static func adjust_incoming_damage(zombie_type: int, amount: int, damage_kind: String) -> int:
	if zombie_type == ZombieMutator.Type.ARMORED and damage_kind == "bullet":
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


## Estado do bote do leaper: perto do alvo, no chao e fora da recarga, salta
## para frente. Enquanto salta, a perseguicao nao sobrescreve a velocidade.
## Uso:
##   var boost := leap.update(delta, velocity, direction, distance, is_on_floor())
##   if leap.is_leaping(): velocity = boost
class LeapState extends RefCounted:
	var _cooldown := 0.0
	var _time_left := 0.0
	var _velocity := Vector3.ZERO

	## Velocidade do bote neste tick, ou Vector3.ZERO quando nao salta.
	func update(delta: float, current_velocity: Vector3, direction: Vector3, distance: float, on_floor: bool) -> Vector3:
		var step := maxf(delta, 0.0)
		_cooldown = maxf(_cooldown - step, 0.0)
		if _time_left > 0.0:
			_time_left -= step
			return Vector3(_velocity.x, current_velocity.y, _velocity.z) if _time_left > 0.0 else Vector3.ZERO
		if _cooldown > 0.0 or not on_floor or distance > ZombieVariantAbilities.LEAP_RANGE:
			return Vector3.ZERO
		var flat := Vector3(direction.x, 0.0, direction.z).normalized()
		if flat.is_zero_approx():
			return Vector3.ZERO
		_velocity = flat * ZombieVariantAbilities.LEAP_SPEED + Vector3.UP * ZombieVariantAbilities.LEAP_UP_SPEED
		_time_left = ZombieVariantAbilities.LEAP_DURATION
		_cooldown = ZombieVariantAbilities.LEAP_COOLDOWN
		return _velocity

	func is_leaping() -> bool:
		return _time_left > 0.0
