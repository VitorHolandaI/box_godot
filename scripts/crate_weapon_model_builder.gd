class_name CrateWeaponModelBuilder
extends RefCounted

## Modelos de caixas das armas de crate na mao do jogador, pelo campo "model"
## de WeaponStats. Armado ao longo do Z: -Z e a frente do boneco (senao a arma
## vira uma "tabua" atravessada no corpo). Armas futuristas ganham faixas que
## brilham na cor do tracer.
## Uso: var node := CrateWeaponModelBuilder.build(WeaponStats.Kind.RAILGUN, muzzle_material)

const WOOD_COLOR := Color(0.45, 0.3, 0.16)


## No da arma (invisivel) com as pecas e o "Flash" do cano.
## Uso: holder.add_child(CrateWeaponModelBuilder.build(kind, muzzle_material))
static func build(kind: int, muzzle_material: Material) -> Node3D:
	var weapon_node := Node3D.new()
	weapon_node.name = "CrateWeapon%d" % kind
	weapon_node.visible = false
	var body := StandardMaterial3D.new()
	body.albedo_color = WeaponStats.color_for(kind)
	body.roughness = 0.45
	body.metallic = 0.5
	var wood := StandardMaterial3D.new()
	wood.albedo_color = WOOD_COLOR
	wood.roughness = 0.7
	var glow := StandardMaterial3D.new()
	glow.albedo_color = WeaponStats.tracer_color_for(kind)
	glow.emission_enabled = true
	glow.emission = WeaponStats.tracer_color_for(kind)
	glow.emission_energy_multiplier = 2.5
	_add_parts(weapon_node, String(WeaponStats.stats_for(kind).get("model", "rifle")), body, wood, glow)
	var flash := add_box(weapon_node, Vector3(0.12, 0.08, 0.08), Vector3(0.0, 0.0, -0.55), muzzle_material)
	flash.name = "Flash"
	flash.visible = false
	# Clarao do tamanho da arma: bazuca e escopeta serrada estouram, SMG pisca.
	flash.scale = Vector3.ONE * float(WeaponStats.stats_for(kind).get("flash_scale", 1.0))
	return weapon_node


static func _add_parts(node: Node3D, model: String, body: Material, wood: Material, glow: Material) -> void:
	match model:
		"shotgun":
			# Cano longo para frente, bombeamento embaixo e coronha atras.
			add_box(node, Vector3(0.14, 0.14, 0.95), Vector3(0.0, 0.0, 0.12), body)
			add_box(node, Vector3(0.16, 0.1, 0.24), Vector3(0.0, -0.11, 0.18), body)
			add_box(node, Vector3(0.16, 0.18, 0.3), Vector3(0.0, -0.06, -0.42), wood)
			add_box(node, Vector3(0.12, 0.22, 0.14), Vector3(0.0, -0.13, -0.62), wood)
		"smg":
			add_box(node, Vector3(0.16, 0.16, 0.55), Vector3.ZERO, body)
			add_box(node, Vector3(0.12, 0.3, 0.12), Vector3(0.0, -0.2, 0.05), body)
			add_box(node, Vector3(0.08, 0.34, 0.08), Vector3(0.0, 0.22, 0.06), body)
		"revolver":
			add_box(node, Vector3(0.13, 0.15, 0.5), Vector3(0.0, 0.0, 0.1), body)
			add_box(node, Vector3(0.13, 0.24, 0.1), Vector3(0.0, -0.16, -0.14), wood)
			add_box(node, Vector3(0.11, 0.11, 0.11), Vector3(0.0, -0.03, -0.02), body)
		"double_barrel":
			add_box(node, Vector3(0.24, 0.12, 0.85), Vector3(0.0, 0.0, 0.1), body)
			add_box(node, Vector3(0.16, 0.16, 0.28), Vector3(0.0, -0.06, -0.42), wood)
			add_box(node, Vector3(0.12, 0.2, 0.12), Vector3(0.0, -0.14, -0.6), wood)
		"short_shotgun":
			# Serrada: dois canos curtos e cabo de pistola.
			add_box(node, Vector3(0.24, 0.13, 0.5), Vector3(0.0, 0.0, -0.05), body)
			add_box(node, Vector3(0.12, 0.24, 0.12), Vector3(0.0, -0.14, 0.2), wood)
		"auto_shotgun":
			# Automatica: corpo grosso, tambor/pente embaixo e coronha reta.
			add_box(node, Vector3(0.18, 0.18, 0.85), Vector3(0.0, 0.0, 0.05), body)
			add_box(node, Vector3(0.16, 0.26, 0.2), Vector3(0.0, -0.2, 0.0), body)
			add_box(node, Vector3(0.14, 0.16, 0.3), Vector3(0.0, -0.02, 0.55), body)
		"sci_rifle":
			add_box(node, Vector3(0.14, 0.16, 1.05), Vector3(0.0, 0.0, 0.05), body)
			add_box(node, Vector3(0.05, 0.05, 0.9), Vector3(0.0, 0.1, 0.0), glow)
			add_box(node, Vector3(0.18, 0.06, 0.06), Vector3(0.0, 0.0, -0.5), glow)
			add_box(node, Vector3(0.12, 0.22, 0.12), Vector3(0.0, -0.16, 0.25), body)
		"sci_smg":
			add_box(node, Vector3(0.18, 0.16, 0.5), Vector3.ZERO, body)
			add_box(node, Vector3(0.2, 0.2, 0.14), Vector3(0.0, 0.0, 0.02), glow)
			add_box(node, Vector3(0.1, 0.26, 0.1), Vector3(0.0, -0.18, 0.12), body)
		"railgun":
			# Railgun: dois trilhos paralelos com bobinas brilhando entre eles.
			add_box(node, Vector3(0.05, 0.08, 1.2), Vector3(-0.08, 0.0, 0.0), body)
			add_box(node, Vector3(0.05, 0.08, 1.2), Vector3(0.08, 0.0, 0.0), body)
			for coil in 3:
				add_box(node, Vector3(0.2, 0.2, 0.06), Vector3(0.0, 0.0, -0.35 + 0.3 * float(coil)), glow)
			add_box(node, Vector3(0.16, 0.2, 0.3), Vector3(0.0, -0.08, 0.5), body)
		"ak":
			# AK: coronha e guarda-mao de madeira, pente curvo para frente.
			add_box(node, Vector3(0.12, 0.13, 0.95), Vector3(0.0, 0.02, 0.0), body)
			add_box(node, Vector3(0.14, 0.12, 0.3), Vector3(0.0, -0.02, -0.25), wood)
			add_box(node, Vector3(0.1, 0.3, 0.12), Vector3(0.0, -0.2, -0.02), body).rotation.x = deg_to_rad(-20.0)
			add_box(node, Vector3(0.12, 0.18, 0.32), Vector3(0.0, -0.06, 0.55), wood)
		"assault_rifle":
			# M4: corpo preto, alca de mira em cima, coronha telescopica.
			add_box(node, Vector3(0.12, 0.14, 0.9), Vector3(0.0, 0.0, 0.0), body)
			add_box(node, Vector3(0.06, 0.08, 0.3), Vector3(0.0, 0.12, 0.05), body)
			add_box(node, Vector3(0.1, 0.26, 0.1), Vector3(0.0, -0.18, 0.05), body)
			add_box(node, Vector3(0.1, 0.14, 0.26), Vector3(0.0, -0.02, 0.55), body)
		"bullpup":
			# AUG: pente atras do gatilho e luneta integrada.
			add_box(node, Vector3(0.14, 0.18, 0.8), Vector3(0.0, 0.0, 0.0), body)
			add_box(node, Vector3(0.08, 0.08, 0.3), Vector3(0.0, 0.16, -0.05), body)
			add_box(node, Vector3(0.1, 0.24, 0.1), Vector3(0.0, -0.18, 0.25), body)
		"handgun":
			add_box(node, Vector3(0.1, 0.12, 0.34), Vector3(0.0, 0.0, 0.0), body)
			add_box(node, Vector3(0.09, 0.2, 0.1), Vector3(0.0, -0.14, 0.1), body)
		"sniper":
			# Sniper: cano muito longo, luneta grossa e bipe.
			add_box(node, Vector3(0.1, 0.1, 1.35), Vector3(0.0, 0.0, -0.1), body)
			add_box(node, Vector3(0.1, 0.1, 0.4), Vector3(0.0, 0.14, 0.1), body)
			add_box(node, Vector3(0.14, 0.18, 0.35), Vector3(0.0, -0.04, 0.55), wood)
		"launcher":
			# Bazuca: tubo grosso no ombro com ponteira brilhando.
			add_box(node, Vector3(0.24, 0.24, 1.2), Vector3(0.0, 0.08, 0.0), body)
			add_box(node, Vector3(0.28, 0.28, 0.1), Vector3(0.0, 0.08, -0.6), glow)
			add_box(node, Vector3(0.1, 0.22, 0.1), Vector3(0.0, -0.14, 0.1), body)
		_:
			# Rifle/carabina: cano longo, mira em cima e coronha de madeira.
			add_box(node, Vector3(0.12, 0.12, 1.0), Vector3(0.0, 0.02, 0.14), body)
			add_box(node, Vector3(0.14, 0.14, 0.3), Vector3(0.0, -0.05, -0.45), wood)
			add_box(node, Vector3(0.1, 0.14, 0.3), Vector3(0.0, 0.14, -0.1), body)
			add_box(node, Vector3(0.12, 0.22, 0.12), Vector3(0.0, -0.14, -0.66), wood)


static func add_box(parent: Node3D, size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	parent.add_child(instance)
	return instance
