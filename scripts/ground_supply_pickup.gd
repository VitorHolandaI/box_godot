class_name GroundSupplyPickup
extends Area3D

## Item de vida/municao espalhado pelo mapa: coleta por tocar (jogador anda
## por cima). Nasce por onda e expira sozinho; replica por nome via
## GroundWeaponSync. Uso:
##   var item := GroundSupplyPickup.new()
##   item.setup(GroundSupplyPickup.Kind.HEALTH, 35)
##   tree.current_scene.add_child(item)

enum Kind { HEALTH, AMMO, AMMO_SHOTGUN, AMMO_UZI, AMMO_MAGNUM, AMMO_DOUBLE_BARREL, AMMO_CARBINE, AMMO_SAWED_OFF, AMMO_AUTO_SHOTGUN, AMMO_LASER, AMMO_PLASMA, AMMO_RAIL, AMMO_AK47, AMMO_M4, AMMO_AUG, AMMO_BERETTA, AMMO_SNIPER, AMMO_ROCKET, AMMO_BOLT, AMMO_GRENADE, AMMO_GAS, AMMO_NAPALM, EQUIP_GRENADES, EQUIP_KNIVES }

## Item de municacao de classe alimenta a reserva da arma daquela classe.
const KIND_TO_WEAPON: Dictionary = {
	Kind.AMMO_SHOTGUN: WeaponStats.Kind.SHOTGUN,
	Kind.AMMO_UZI: WeaponStats.Kind.UZI,
	Kind.AMMO_MAGNUM: WeaponStats.Kind.MAGNUM,
	Kind.AMMO_DOUBLE_BARREL: WeaponStats.Kind.DOUBLE_BARREL,
	Kind.AMMO_CARBINE: WeaponStats.Kind.CARBINE,
	Kind.AMMO_SAWED_OFF: WeaponStats.Kind.SAWED_OFF,
	Kind.AMMO_AUTO_SHOTGUN: WeaponStats.Kind.AUTO_SHOTGUN,
	Kind.AMMO_LASER: WeaponStats.Kind.LASER_RIFLE,
	Kind.AMMO_PLASMA: WeaponStats.Kind.PLASMA_SMG,
	Kind.AMMO_RAIL: WeaponStats.Kind.RAILGUN,
	Kind.AMMO_AK47: WeaponStats.Kind.AK47,
	Kind.AMMO_M4: WeaponStats.Kind.M4,
	Kind.AMMO_AUG: WeaponStats.Kind.AUG,
	Kind.AMMO_BERETTA: WeaponStats.Kind.BERETTA,
	Kind.AMMO_SNIPER: WeaponStats.Kind.SNIPER,
	Kind.AMMO_ROCKET: WeaponStats.Kind.BAZOOKA,
	Kind.AMMO_BOLT: WeaponStats.Kind.CROSSBOW,
	Kind.AMMO_GRENADE: WeaponStats.Kind.GRENADE_LAUNCHER,
	Kind.AMMO_GAS: WeaponStats.Kind.CHAINSAW,
	Kind.AMMO_NAPALM: WeaponStats.Kind.FLAMETHROWER,
}

## Cor e etiqueta por classe: antes toda caixa de municao era igual e ninguem
## sabia que aquela era da uzi ou da escopeta.
const CLASS_COLORS: Dictionary = {
	Kind.AMMO: Color(0.95, 0.78, 0.12),
	Kind.AMMO_SHOTGUN: Color(0.9, 0.35, 0.1),
	Kind.AMMO_UZI: Color(0.2, 0.75, 0.95),
	Kind.AMMO_MAGNUM: Color(0.75, 0.3, 0.9),
	Kind.AMMO_DOUBLE_BARREL: Color(0.95, 0.2, 0.25),
	Kind.AMMO_CARBINE: Color(0.35, 0.9, 0.35),
	Kind.AMMO_SAWED_OFF: Color(0.8, 0.55, 0.3),
	Kind.AMMO_AUTO_SHOTGUN: Color(1.0, 0.55, 0.0),
	Kind.AMMO_LASER: Color(0.2, 0.9, 1.0),
	Kind.AMMO_PLASMA: Color(0.9, 0.25, 1.0),
	Kind.AMMO_RAIL: Color(0.3, 1.0, 0.5),
	Kind.AMMO_AK47: Color(0.85, 0.4, 0.2),
	Kind.AMMO_M4: Color(0.6, 0.65, 0.7),
	Kind.AMMO_AUG: Color(0.55, 0.75, 0.35),
	Kind.AMMO_BERETTA: Color(0.95, 0.95, 0.6),
	Kind.AMMO_SNIPER: Color(0.3, 0.55, 1.0),
	Kind.AMMO_ROCKET: Color(1.0, 0.25, 0.1),
	Kind.AMMO_BOLT: Color(0.7, 0.55, 0.35),
	Kind.AMMO_GRENADE: Color(0.45, 0.85, 0.15),
	Kind.AMMO_GAS: Color(0.95, 0.6, 0.2),
	Kind.AMMO_NAPALM: Color(0.85, 0.15, 0.05),
	Kind.EQUIP_GRENADES: Color(0.35, 0.6, 0.2),
	Kind.EQUIP_KNIVES: Color(0.8, 0.85, 0.9),
}
const CLASS_LABELS: Dictionary = {
	Kind.AMMO: "PISTOLA",
	Kind.AMMO_SHOTGUN: "ESCOPETA",
	Kind.AMMO_UZI: "UZI",
	Kind.AMMO_MAGNUM: "MAGNUM",
	Kind.AMMO_DOUBLE_BARREL: "DUPLA",
	Kind.AMMO_CARBINE: "CARABINA",
	Kind.AMMO_SAWED_OFF: "SERRADA",
	Kind.AMMO_AUTO_SHOTGUN: "AUTO 12GA",
	Kind.AMMO_LASER: "LASER",
	Kind.AMMO_PLASMA: "PLASMA",
	Kind.AMMO_RAIL: "RAIL",
	Kind.AMMO_AK47: "AK-47",
	Kind.AMMO_M4: "M4",
	Kind.AMMO_AUG: "AUG",
	Kind.AMMO_BERETTA: "BERETTA",
	Kind.AMMO_SNIPER: "SNIPER",
	Kind.AMMO_ROCKET: "FOGUETE",
	Kind.AMMO_BOLT: "SETAS",
	Kind.AMMO_GRENADE: "GRANADAS",
	Kind.AMMO_GAS: "GASOLINA",
	Kind.AMMO_NAPALM: "NAPALM",
	Kind.EQUIP_GRENADES: "GRANADAS DE MAO",
	Kind.EQUIP_KNIVES: "FACAS",
}
## Itens de equipamento (nao municao): somam na contagem do PlayerEquipment.
const KIND_TO_EQUIPMENT: Dictionary = {
	Kind.EQUIP_GRENADES: PlayerEquipment.Item.GRENADE,
	Kind.EQUIP_KNIVES: PlayerEquipment.Item.THROWING_KNIFE,
}
const DEFAULT_LIFETIME := 180.0
## Municao de classe tocada por quem nao tem aquela arma vira balas de pistola:
## antes o jogador passava por cima e nada acontecia ("municao nao conta").
const PISTOL_ROUNDS_FROM_FOREIGN_CLASS := 12

var supply_kind := Kind.HEALTH
var amount := 35
## Item some sozinho; contagem roda apenas na autoridade (offline/servidor).
var lifetime_seconds := DEFAULT_LIFETIME
var lifetime_elapsed := 0.0
var model_root: Node3D
var elapsed := 0.0


func setup(kind: int, pickup_amount: int) -> void:
	supply_kind = kind
	amount = pickup_amount


func _ready() -> void:
	add_to_group("ground_supplies")
	collision_layer = 0
	collision_mask = 2
	monitoring = not NetworkSession.is_client()
	body_entered.connect(_on_body_entered)
	_build_visuals()
	_build_collision()


func _physics_process(delta: float) -> void:
	elapsed += delta
	if NetworkSession.is_client():
		return
	lifetime_elapsed += delta
	if lifetime_elapsed >= lifetime_seconds:
		GroundWeaponSync.mark_dirty()
		queue_free()
		return
	if model_root != null:
		model_root.position.y = 0.3 + sin(elapsed * 2.6) * 0.05


func _on_body_entered(body: Node3D) -> void:
	if NetworkSession.is_client():
		return
	if not body.is_in_group("player"):
		return
	var received := 0
	if supply_kind == Kind.HEALTH and body.has_method("add_health"):
		received = int(body.call("add_health", amount))
	elif supply_kind == Kind.AMMO and body.has_method("add_ammo"):
		received = int(body.call("add_ammo", amount))
	elif KIND_TO_WEAPON.has(supply_kind) and body.has_method("add_crate_reserve"):
		received = _collect_class_ammo(body)
	elif KIND_TO_EQUIPMENT.has(supply_kind) and body.get("equipment") is PlayerEquipment:
		received = (body.get("equipment") as PlayerEquipment).add(int(KIND_TO_EQUIPMENT[supply_kind]), amount)
	# Reserva cheia / vida cheia deixa o item no chao para quem precisa.
	if received > 0:
		GroundWeaponSync.mark_dirty()
		queue_free()


## Cor de destaque do item (municao por classe); vida usa o branco da cruz.
## Uso: var cor := GroundSupplyPickup.color_for(GroundSupplyPickup.Kind.AMMO_UZI)
static func color_for(kind: int) -> Color:
	return CLASS_COLORS.get(kind, Color(0.96, 0.96, 0.92))


## Classe da arma que o jogador tem: vai para a reserva dela. Sem a arma: vira
## balas de pistola. Reserva cheia retorna 0 e o item fica no chao.
func _collect_class_ammo(player: Node) -> int:
	var weapon_kind := int(KIND_TO_WEAPON[supply_kind])
	var slots: Variant = player.get("weapon_slots")
	if slots is WeaponSlots and (slots as WeaponSlots).has_kind(weapon_kind):
		return int(player.call("add_crate_reserve", weapon_kind, amount))
	if player.has_method("add_ammo"):
		return int(player.call("add_ammo", PISTOL_ROUNDS_FROM_FOREIGN_CLASS))
	return 0


func _build_visuals() -> void:
	model_root = Node3D.new()
	model_root.name = "Model"
	model_root.position.y = 0.3
	add_child(model_root)
	var is_health := supply_kind == Kind.HEALTH
	var primary := StandardMaterial3D.new()
	primary.albedo_color = Color(0.78, 0.12, 0.12) if is_health else Color(0.24, 0.35, 0.18)
	primary.roughness = 0.6
	var bright := StandardMaterial3D.new()
	bright.albedo_color = color_for(supply_kind)
	bright.emission_enabled = true
	bright.emission = bright.albedo_color
	bright.emission_energy_multiplier = 0.4
	_add_box(Vector3(0.4, 0.28, 0.32), Vector3.ZERO, primary)
	if is_health:
		_add_box(Vector3(0.22, 0.06, 0.03), Vector3(0.0, 0.0, -0.17), bright)
		_add_box(Vector3(0.06, 0.2, 0.03), Vector3(0.0, 0.0, -0.17), bright)
	else:
		_add_box(Vector3(0.38, 0.05, 0.3), Vector3(0.0, 0.16, 0.0), bright)
		_add_class_label()
	var light := OmniLight3D.new()
	light.light_color = primary.albedo_color.lightened(0.35) if is_health else bright.albedo_color
	light.light_energy = 0.5
	light.omni_range = 2.2
	model_root.add_child(light)


func _add_class_label() -> void:
	var label := Label3D.new()
	label.name = "ClassLabel"
	label.text = String(CLASS_LABELS.get(supply_kind, "MUNICAO"))
	label.modulate = color_for(supply_kind)
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 40
	label.pixel_size = 0.006
	label.position = Vector3(0.0, 0.55, 0.0)
	model_root.add_child(label)


func _build_collision() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	shape.shape = box
	shape.position.y = 0.4
	add_child(shape)


func _add_box(size: Vector3, position: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	model_root.add_child(instance)
