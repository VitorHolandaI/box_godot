class_name PlayerThrowables
extends RefCounted

## Uso dos itens do jogador na autoridade: granada em arco e faca de arremesso
## silenciosa (hitscan que atravessa 2). Ataque aereo e SWAT pedem a cena
## (call_air_strike / call_swat) quando ela souber atender.
## Uso: PlayerThrowables.handle_input(player)

const ITEM_COOLDOWN := 0.6
const KNIFE_DAMAGE := 75
const KNIFE_PIERCE := 2
const KNIFE_NOISE_RADIUS := 6.0


## Le os botoes de item do tick e usa no maximo um item.
## Uso: chamado por player._handle_equipment_input()
static func handle_input(player: Node3D) -> void:
	if float(player.get("equipment_cooldown")) > 0.0:
		return
	var equipment: PlayerEquipment = player.get("equipment")
	var direction := aim_direction(player)
	var used := false
	if bool(player.get("grenade_pressed")) and equipment.try_consume(PlayerEquipment.Item.GRENADE):
		throw_grenade(player, direction)
		used = true
	elif bool(player.get("throw_knife_pressed")) and equipment.try_consume(PlayerEquipment.Item.THROWING_KNIFE):
		throw_knife(player, direction)
		used = true
	elif bool(player.get("air_strike_pressed")):
		used = _request_call(player, equipment, PlayerEquipment.Item.AIR_STRIKE, "call_air_strike", direction)
	elif bool(player.get("swat_pressed")):
		used = _request_call(player, equipment, PlayerEquipment.Item.SWAT, "call_swat", direction)
	if used:
		player.set("equipment_cooldown", ITEM_COOLDOWN)


## Mira do jogador (analogico/mouse) ou a frente do corpo.
## Uso: var direcao := PlayerThrowables.aim_direction(player)
static func aim_direction(player: Node3D) -> Vector3:
	var aim: Vector2 = player.get("aim_input")
	var direction := Vector3(aim.x, 0.0, aim.y).normalized()
	return direction if not direction.is_zero_approx() else -player.global_transform.basis.z


static func throw_grenade(player: Node3D, direction: Vector3) -> void:
	var scene := player.get_tree().current_scene
	var start := player.global_position + Vector3.UP * 1.1 + direction * 0.5
	var start_velocity := direction * ThrownGrenade.THROW_SPEED + Vector3.UP * ThrownGrenade.THROW_LIFT
	var grenade := ThrownGrenade.new()
	player.get_parent().add_child(grenade)
	grenade.setup(start, start_velocity, true, player)
	if scene != null and scene.has_method("replicate_thrown_grenade"):
		scene.call("replicate_thrown_grenade", start, start_velocity)


static func throw_knife(player: Node3D, direction: Vector3) -> void:
	var origin := player.global_position + Vector3.UP * 0.55
	Bullet.hitscan_damage(origin + direction * 0.12, direction, KNIFE_DAMAGE, player as CollisionObject3D, KNIFE_PIERCE)
	ZombieFlockCoordinator.relay_sound(player.get_tree(), origin, KNIFE_NOISE_RADIUS)
	var scene := player.get_tree().current_scene
	if scene != null and scene.has_method("show_thrown_knife"):
		scene.call("show_thrown_knife", origin, direction)


static func _request_call(player: Node3D, equipment: PlayerEquipment, item: int, scene_method: String, direction: Vector3) -> bool:
	var scene := player.get_tree().current_scene
	if scene == null or not scene.has_method(scene_method) or equipment.count_of(item) <= 0:
		return false
	equipment.try_consume(item)
	scene.call(scene_method, player, direction)
	return true
