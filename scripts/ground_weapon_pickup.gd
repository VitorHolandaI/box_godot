class_name GroundWeaponPickup
extends Area3D

## Arma dropada no chao (pelo jogador ou reutilizada pelo airdrop). Pega por
## interacao (tecla interact) dentro de um raio curto; nunca por colisao
## automatica. Replica por nome via GroundWeaponSync.
## Uso:
##   var pickup := GroundWeaponPickup.new()
##   pickup.setup(WeaponStats.Kind.UZI, 22, 80, 95)
##   tree.current_scene.add_child(pickup)


const MODEL_SCALE := 1.8
const DROP_ANIMATION_TIME := 0.7
const DROP_HEIGHT := 1.2
const LABEL_RADIUS := 3.0
const LABEL_CHECK_INTERVAL := 0.15
const BLINK_SECONDS := 10.0
const FLOOR_PROBE_UP := 1.5
const FLOOR_PROBE_DOWN := 6.0
## Passar por cima (sem apertar E) de uma arma do mesmo tipo que o jogador ja
## carrega transfere a municao que cabe na reserva dele.
const AMMO_ABSORB_RADIUS := 1.2
const AMMO_ABSORB_INTERVAL := 0.2

var weapon_kind := WeaponStats.Kind.SHOTGUN
var mag := 0
var reserve := 0
var durability := 0
## Arma no chao fica 10 minutos e some sozinha (autoridade); o cliente recebe o
## tempo restante no sync so para piscar na hora certa.
var lifetime_seconds := 600.0
var lifetime_elapsed := 0.0
var model_root: Node3D
var name_label: Label3D
var elapsed := 0.0
var _snapped_to_floor := false
var _label_check_elapsed := 0.0
var _ammo_absorb_elapsed := 0.0


func setup(kind: int, weapon_mag: int, weapon_reserve: int, weapon_durability: int) -> void:
	weapon_kind = kind
	mag = weapon_mag
	reserve = weapon_reserve
	durability = weapon_durability


func _ready() -> void:
	add_to_group("ground_weapons")
	collision_layer = 0
	collision_mask = 2
	monitoring = false
	monitorable = true
	_build_visuals()
	_build_collision()


func _process(delta: float) -> void:
	elapsed += delta
	lifetime_elapsed += delta
	if not _snapped_to_floor:
		_snap_to_floor()
	if not NetworkSession.is_client() and lifetime_elapsed >= lifetime_seconds:
		GroundWeaponSync.mark_dirty()
		queue_free()
		return
	if not NetworkSession.is_client():
		_ammo_absorb_elapsed += delta
		if _ammo_absorb_elapsed >= AMMO_ABSORB_INTERVAL:
			_ammo_absorb_elapsed = 0.0
			absorb_ammo_from_nearby_players(get_tree())
	_animate_model(delta)
	_update_name_label(delta)


## Tempo que falta para sumir (vai no sync para o cliente piscar junto).
## Uso: var restante := pickup.remaining_lifetime()
func remaining_lifetime() -> float:
	return maxf(lifetime_seconds - lifetime_elapsed, 0.0)


## Coleta por interacao: retorna "granted"/"merged"/"swapped"/"full"; o
## chamador remove o no so quando a arma saiu do chao.
## Uso: var r := pickup.interact_with(player)
func interact_with(player: Node) -> String:
	# Mesma arma na mao: antes o E somava a reserva e sumia com a arma inteira,
	# perdendo o que nao coube. Agora so sai a municao que cabe.
	if bool(player.call("has_crate_weapon", weapon_kind)):
		return "merged" if _give_ammo_to(player) > 0 else "full"
	var result: String = player.call("take_ground_weapon", weapon_kind, mag, reserve, durability)
	if result != "full":
		GroundWeaponSync.mark_dirty()
		queue_free()
	return result


## Autoridade: jogadores vivos a AMMO_ABSORB_RADIUS com a mesma arma levam a
## municao que cabe; a arma some do chao quando esvazia.
## Uso: pickup.absorb_ammo_from_nearby_players(get_tree())
func absorb_ammo_from_nearby_players(tree: SceneTree) -> void:
	for node in tree.get_nodes_in_group("player"):
		if mag + reserve <= 0 or is_queued_for_deletion():
			return
		var player := node as Node3D
		if player == null or int(player.get("health")) <= 0 or bool(player.get("is_eliminated")):
			continue
		if Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length() > AMMO_ABSORB_RADIUS:
			continue
		if bool(player.call("has_crate_weapon", weapon_kind)):
			_give_ammo_to(player)


## Municao que sai da arma do chao para `space` de reserva: primeiro a reserva
## dela, depois o pente. Devolve {taken, mag, reserve} com o que sobra no chao.
## Uso: GroundWeaponPickup.split_ammo(22, 80, 50) -> {taken 50, mag 22, reserve 30}
static func split_ammo(pickup_mag: int, pickup_reserve: int, space: int) -> Dictionary:
	var taken := clampi(space, 0, maxi(pickup_mag, 0) + maxi(pickup_reserve, 0))
	var from_reserve := mini(taken, maxi(pickup_reserve, 0))
	return {
		"taken": taken,
		"reserve": maxi(pickup_reserve, 0) - from_reserve,
		"mag": maxi(pickup_mag, 0) - (taken - from_reserve),
	}


func _give_ammo_to(player: Node) -> int:
	var space := int(player.call("crate_reserve_space", weapon_kind))
	var split := split_ammo(mag, reserve, space)
	var added := int(player.call("absorb_ground_ammo", weapon_kind, int(split["taken"])))
	if added <= 0:
		return 0
	# add_reserve pode aceitar menos que o previsto; recalcula a sobra real.
	var actual := split_ammo(mag, reserve, added)
	mag = int(actual["mag"])
	reserve = int(actual["reserve"])
	GroundWeaponSync.mark_dirty()
	if mag + reserve <= 0:
		queue_free()
	return added


## Assenta no piso de verdade (rua ou andar de predio) no primeiro frame: o
## drop nasce na altura do zumbi/jogador e ficava flutuando ou enterrado.
func _snap_to_floor() -> void:
	_snapped_to_floor = true
	if not is_inside_tree():
		return
	var from := global_position + Vector3.UP * FLOOR_PROBE_UP
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (FLOOR_PROBE_UP + FLOOR_PROBE_DOWN), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position.y = float((hit["position"] as Vector3).y) + 0.02


## Queda com quiques e giro ao aparecer, depois gira devagar; pisca antes de sumir.
func _animate_model(delta: float) -> void:
	if model_root == null:
		return
	var drop_progress := clampf(elapsed / DROP_ANIMATION_TIME, 0.0, 1.0)
	var falling := 1.0 - drop_progress
	var bounce := absf(cos(drop_progress * PI * 2.5)) * DROP_HEIGHT * falling * falling
	model_root.position.y = 0.35 + bounce + sin(elapsed * 2.4) * 0.04 * drop_progress
	model_root.rotation.y += delta * (0.8 + 9.0 * falling)
	model_root.rotation.z = sin(elapsed * 14.0) * 0.5 * falling
	var remaining := remaining_lifetime()
	model_root.visible = remaining > BLINK_SECONDS or fmod(elapsed * 6.0, 1.0) < 0.6


## Nome grande da arma so para jogador local perto (servidor dedicado nao tem).
func _update_name_label(delta: float) -> void:
	_label_check_elapsed += delta
	if name_label == null or _label_check_elapsed < LABEL_CHECK_INTERVAL:
		return
	_label_check_elapsed = 0.0
	var near := false
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		if player == null or player.get("is_local_controller") != true:
			continue
		if Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length() <= LABEL_RADIUS:
			near = true
			break
	name_label.visible = near


func _build_visuals() -> void:
	model_root = Node3D.new()
	model_root.name = "Model"
	model_root.position.y = 0.35
	add_child(model_root)
	var muzzle := StandardMaterial3D.new()
	muzzle.albedo_color = WeaponStats.tracer_color_for(weapon_kind)
	var weapon_model := CrateWeaponModelBuilder.build(weapon_kind, muzzle)
	weapon_model.visible = true
	weapon_model.scale = Vector3.ONE * MODEL_SCALE
	model_root.add_child(weapon_model)
	var light := OmniLight3D.new()
	light.light_color = WeaponStats.tracer_color_for(weapon_kind)
	light.light_energy = 0.7
	light.omni_range = 2.6
	model_root.add_child(light)
	name_label = Label3D.new()
	name_label.name = "NameLabel"
	name_label.text = "%s\n[E] PEGAR" % String(WeaponStats.stats_for(weapon_kind).get("label", "Arma"))
	name_label.font_size = 72
	name_label.outline_size = 14
	name_label.pixel_size = 0.006
	name_label.modulate = Color(1.0, 1.0, 1.0)
	name_label.outline_modulate = Color(WeaponStats.tracer_color_for(weapon_kind).darkened(0.6), 1.0)
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.no_depth_test = true
	name_label.position.y = 1.6
	name_label.visible = false
	add_child(name_label)


func _build_collision() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 1.0, 1.2)
	shape.shape = box
	shape.position.y = 0.4
	add_child(shape)
