class_name ZombieMutator
extends RefCounted

## Gerenciador e configurador procedural de variantes anatomicas e mutilacoes de zumbis.
## Suporta 15 variantes com anatomia, amputacoes, materiais e gait visual especificos.

enum Type {
	WALKER = 0,
	ONE_ARM = 1,
	CRAWLER = 2,
	LIMPER = 3,
	SPRINTER = 4,
	HALF_ARM = 5,
	ONE_LEG = 6,
	HALF_LEG = 7,
	HALF_HEAD = 8,
	## Tanque: lento, muita vida e golpe forte; corpo maior.
	BRUTE = 9,
	## Grita periodicamente e atrai a horda pela audicao.
	SCREAMER = 10,
	## Inchado e lento: explode ao morrer ferindo quem estiver perto.
	BLOATER = 11,
	## Magro e curvado: da um bote rapido quando chega perto.
	LEAPER = 12,
	## Capacete e colete: tiro causa metade do dano, faca dano cheio.
	ARMORED = 13,
	## Super zumbi (chefe): 10000 de vida, pisao, invocacao e furia.
	TITAN = 14,
	## Cuspidor: para a distancia e cospe uma poca de acido que queima.
	SPITTER = 15,
	## Investida: braco gigante, arranca em linha reta e arremessa o jogador.
	CHARGER = 16,
	## Saltador: pernas longas, pula alto em arco e cai em cima do jogador.
	JUMPER = 17,
	## Puxador: de longe prende o jogador com a lingua e puxa ate a horda.
	SMOKER = 18,
	## Curandeiro: cura os zumbis perto e levanta cadaveres recentes.
	HEALER = 19,
	## Espreitador: quase invisivel ate chegar perto; da o bote e prende.
	STALKER = 20,
	## Coletor: absorve pedacos de cadaveres e usa as habilidades deles
	## (zombie_collector.gd). Fora do sorteio comum: nasce pela onda ou pelo lab.
	COLLECTOR = 21,
	## Aranha (pedido do dono, referencia Dead Space): corpo baixo com quatro
	## membros finos a mais e costelas expostas; rapida e fragil.
	SPIDER = 22,
}

## Quantidade de tipos (snapshot leva ate 127, ZombieSnapshotCodec).
const TYPE_COUNT := 23
## Geometria base do zumbi (zombie.tscn): pes do modelo e capsula de colisao.
const MODEL_FEET_Y := -0.82
const BASE_CAPSULE_RADIUS := 0.56
const BASE_CAPSULE_HEIGHT := 2.2
const CAPSULE_BOTTOM_Y := -0.88
const BASE_HEALTH_LABEL_Y := 1.75
## Capsula de zumbi grande cresce com o corpo, mas cabe em porta de 2 m e sob a
## verga de 2.75 m: o Tita segue entrando em predio (a cabeca atravessa o teto).
const MAX_CAPSULE_RADIUS := 0.95
const MAX_CAPSULE_HEIGHT := 2.6
## Patas extras da aranha (nomeadas SpiderLimb0..3 na montagem).
const SPIDER_LIMB_COUNT := 4
## Aranha: rebaixamento EXTRA do corpo (somado ao ajuste de escala) e inclinacao.
## Sem isso ela ficava de pe com as 4 patas no ar: o ajuste generico de escala
## reescrevia model.position.y (o antigo -0.55 virava -0.12) e a marcha somava ~0.
## Uso: model_y_offset_for / body_rest_y.
const SPIDER_EXTRA_DROP := -0.45
const SPIDER_PITCH_DEG := 58.0
## Camada procedural: balanco vertical da cabeca no ritmo do passo (2x a
## passada). Barato e vale para qualquer variante.
const HEAD_BOB_AMPLITUDE := 0.05
## Altura de repouso da cabeca no zombie.tscn (position y do no Model/Head).
## Constante de proposito: guardar no cache de nos capturava a cabeca ja
## balancando quando o cache era novo, e ela nunca voltava ao repouso.
const HEAD_REST_Y := 1.14
## Inclinacao ao virar (contrapposto): o corpo rola para fora da curva,
## proporcional a taxa de giro, com teto. Vale para qualquer variante.
const TURN_LEAN_FACTOR := 0.06
const TURN_LEAN_MAX := 0.16
## Passada por metro andado: ~2 no walker (2,2 m/s) e ~3 no sprinter (3,1 m/s),
## que e perto das constantes fixas que existiam por tipo (5,5 e 9,0 rad/s).
const STRIDE_RADIANS_PER_METER := 2.6
const STRIDE_MIN_SPEED := 0.5
const BODY_SCALES: Dictionary = {
	Type.BRUTE: Vector3(1.35, 1.25, 1.35),
	Type.TITAN: Vector3(2.3, 2.3, 2.3),
	Type.BLOATER: Vector3(1.1, 1.0, 1.1),
	Type.LEAPER: Vector3(0.85, 1.0, 0.85),
	Type.CHARGER: Vector3(1.2, 1.1, 1.2),
	Type.SMOKER: Vector3(0.9, 1.15, 0.9),
	Type.SPIDER: Vector3(1.2, 0.85, 1.2),
}

const SKIN_PALETTE: Array[Color] = [
	Color(0.28, 0.52, 0.22),
	Color(0.36, 0.44, 0.40),
	Color(0.46, 0.30, 0.26),
	Color(0.22, 0.35, 0.25),
]
const SHIRT_PALETTE: Array[Color] = [
	Color(0.28, 0.16, 0.12),
	Color(0.18, 0.24, 0.32),
	Color(0.48, 0.44, 0.40),
	Color(0.22, 0.26, 0.18),
]
const PANTS_PALETTE: Array[Color] = [
	Color(0.18, 0.20, 0.22),
	Color(0.16, 0.22, 0.30),
	Color(0.32, 0.28, 0.22),
]


## Aplica estetica, paleta de cores e deformacoes anatomicas no zumbi.
## Uso:
##   ZombieMutator.apply_appearance(zombie, ZombieMutator.Type.HALF_ARM, hash_val)
static func apply_appearance(zombie: CharacterBody3D, z_type: int, hash_val: int) -> void:
	_apply_materials(zombie, hash_val)
	_apply_anatomy(zombie, z_type)
	apply_body_scale(zombie, z_type)


## Variante do sorteio comum (modo classico) pelo hash do nome; nunca o chefe.
## Uso: var tipo := ZombieMutator.random_variant_for_hash(absi(name.hash()))
static func random_variant_for_hash(hash_val: int) -> int:
	# -2: pula o chefe (nunca no sorteio comum) e o coletor (sem cadaver por
	# perto ele nao vira ameaca, entao nao entra na populacao aleatoria).
	var variant := posmod(hash_val, TYPE_COUNT - 2)
	if variant >= Type.TITAN:
		variant += 1
	if variant >= Type.COLLECTOR:
		variant += 1
	return variant


## Aplica SO a aparencia da variante, sem deixar que ela mude os stats: e o que
## o coletor usa para ficar com o pedaco que comeu (colete, capacete, corcunda,
## corpo do chefe...). As rotinas chamadas foram escritas para rodar uma vez por
## zumbi; o coletor come cada variante no maximo uma vez, entao nao duplica node.
## Uso: ZombieMutator.apply_part_appearance(zombie, ZombieMutator.Type.ARMORED)
static func apply_part_appearance(zombie: CharacterBody3D, z_type: int) -> void:
	var model := zombie.get_node_or_null("Model") as Node3D
	if model == null:
		return
	# Algumas rotinas tambem escrevem speed/health; guarda e devolve no fim.
	var speed_before := float(zombie.get("speed"))
	var health_before := int(zombie.get("max_health"))
	match z_type:
		Type.LEAPER:
			model.rotation.x = deg_to_rad(24.0)
		Type.SCREAMER:
			_setup_screamer(zombie)
		Type.BLOATER:
			_setup_bloater(zombie, model)
		Type.ARMORED:
			_setup_armored(zombie)
		Type.TITAN:
			_setup_titan(zombie, model)
		Type.SPITTER:
			_setup_spitter(zombie)
		Type.CHARGER:
			_setup_charger(zombie)
		Type.JUMPER:
			_setup_jumper(zombie)
		Type.SMOKER:
			_setup_smoker(zombie)
		Type.HEALER:
			_setup_healer(zombie)
		Type.STALKER:
			_setup_stalker(zombie, model)
		_:
			return
	zombie.set("speed", speed_before)
	zombie.set("max_health", health_before)


## Escala do corpo por tipo, usada pelo zumbi vivo e pelo cadaver.
## Uso: var escala := ZombieMutator.body_scale_for(ZombieMutator.Type.TITAN)
static func body_scale_for(z_type: int) -> Vector3:
	return BODY_SCALES.get(z_type, Vector3.ONE)


## Rebaixamento extra do modelo por variante (0 = nenhum). Uso:
## var y := model_y_offset_for(ZombieMutator.Type.SPIDER)
static func model_y_offset_for(z_type: int) -> float:
	return SPIDER_EXTRA_DROP if z_type == Type.SPIDER else 0.0


## Y de repouso do modelo: pes no chao com a escala, mais o rebaixamento da
## variante (aranha). Uso: var y := ZombieMutator.body_rest_y(ZombieMutator.Type.SPIDER)
static func body_rest_y(z_type: int) -> float:
	return MODEL_FEET_Y * (1.0 - body_scale_for(z_type).y) + model_y_offset_for(z_type)


## Amplia modelo e capsula mantendo os pes no chao. Antes o modelo crescia a
## partir do centro: o Tita afundava ~1 m e ficava maior que a colisao, parecendo
## atravessar tudo. Uso: ZombieMutator.apply_body_scale(zombie, ZombieMutator.Type.BRUTE)
static func apply_body_scale(zombie: CharacterBody3D, z_type: int) -> void:
	var body_scale := body_scale_for(z_type)
	if body_scale == Vector3.ONE and is_zero_approx(model_y_offset_for(z_type)):
		return
	var model := zombie.get_node_or_null("Model") as Node3D
	if model != null:
		model.scale = body_scale
		model.position.y = body_rest_y(z_type)
	var collision := zombie.get_node_or_null("CollisionShape") as CollisionShape3D
	if collision != null and collision.shape is CapsuleShape3D:
		# A forma da cena e compartilhada entre todos os zumbis: duplica antes.
		var capsule := (collision.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
		capsule.radius = minf(BASE_CAPSULE_RADIUS * maxf(body_scale.x, body_scale.z), MAX_CAPSULE_RADIUS)
		capsule.height = maxf(minf(BASE_CAPSULE_HEIGHT * body_scale.y, MAX_CAPSULE_HEIGHT), capsule.radius * 2.0)
		collision.shape = capsule
		collision.position.y = CAPSULE_BOTTOM_Y + capsule.height * 0.5
	var label := zombie.get_node_or_null("HealthLabel") as Label3D
	if label != null:
		# Valor absoluto: apply_appearance pode rodar de novo (troca de tipo pela rede).
		label.position.y = BASE_HEALTH_LABEL_Y + 1.6 * (body_scale.y - 1.0)


static func appearance_colors(hash_val: int) -> Array[Color]:
	return [
		SKIN_PALETTE[(hash_val / 5) % SKIN_PALETTE.size()],
		SHIRT_PALETTE[(hash_val / 20) % SHIRT_PALETTE.size()],
		PANTS_PALETTE[(hash_val / 80) % PANTS_PALETTE.size()],
	]


static func _apply_materials(zombie: CharacterBody3D, hash_val: int) -> void:
	var skin_mat := _quick_mat(SKIN_PALETTE[(hash_val / 5) % SKIN_PALETTE.size()], 0.9)
	var shirt_mat := _quick_mat(SHIRT_PALETTE[(hash_val / 20) % SHIRT_PALETTE.size()], 0.95)
	var pants_mat := _quick_mat(PANTS_PALETTE[(hash_val / 80) % PANTS_PALETTE.size()], 0.95)

	var head := zombie.get_node_or_null("Model/Head") as MeshInstance3D
	var torso := zombie.get_node_or_null("Model/Torso") as MeshInstance3D
	var left_arm := zombie.get_node_or_null("Model/LeftArm/Mesh") as MeshInstance3D
	var right_arm := zombie.get_node_or_null("Model/RightArm/Mesh") as MeshInstance3D
	var left_leg := zombie.get_node_or_null("Model/LeftLeg/Mesh") as MeshInstance3D
	var right_leg := zombie.get_node_or_null("Model/RightLeg/Mesh") as MeshInstance3D

	if head != null:
		head.material_override = skin_mat
	if torso != null:
		torso.material_override = shirt_mat
	if left_arm != null:
		left_arm.material_override = skin_mat
	if right_arm != null:
		right_arm.material_override = skin_mat
	if left_leg != null:
		left_leg.material_override = pants_mat
	if right_leg != null:
		right_leg.material_override = pants_mat


static func _apply_anatomy(zombie: CharacterBody3D, z_type: int) -> void:
	var model := zombie.get_node_or_null("Model") as Node3D
	if model == null:
		return

	match z_type:
		Type.ONE_ARM:
			zombie.set("speed", 2.0)
			zombie.set("max_health", 85)
			_hide_node(zombie, "Model/LeftArm/Mesh")
			_create_stump(zombie.get_node_or_null("Model/LeftArm") as Node3D, Vector3(0.0, -0.1, 0.0))
		Type.HALF_ARM:
			zombie.set("speed", 2.1)
			zombie.set("max_health", 90)
			_shorten_limb(zombie, "Model/LeftArm/Mesh")
			_create_stump(zombie.get_node_or_null("Model/LeftArm") as Node3D, Vector3(0.0, -0.42, 0.0))
		Type.CRAWLER:
			_setup_crawler(zombie, model)
		Type.LIMPER:
			zombie.set("speed", 1.65)
			zombie.set("max_health", 90)
			var r_leg := zombie.get_node_or_null("Model/RightLeg") as Node3D
			if r_leg != null:
				r_leg.rotation.z = deg_to_rad(10.0)
			model.rotation.z = deg_to_rad(8.0)
		Type.SPRINTER:
			zombie.set("speed", 3.1)
			zombie.set("max_health", 70)
			model.rotation.x = deg_to_rad(15.0)
		Type.ONE_LEG:
			zombie.set("speed", 1.5)
			zombie.set("max_health", 80)
			_hide_node(zombie, "Model/LeftLeg/Mesh")
			_create_stump(zombie.get_node_or_null("Model/LeftLeg") as Node3D, Vector3(0.0, -0.05, 0.0))
		Type.HALF_LEG:
			zombie.set("speed", 1.6)
			zombie.set("max_health", 85)
			_shorten_limb(zombie, "Model/RightLeg/Mesh")
			_create_stump(zombie.get_node_or_null("Model/RightLeg") as Node3D, Vector3(0.0, -0.42, 0.0))
			model.rotation.z = deg_to_rad(7.0)
		Type.HALF_HEAD:
			zombie.set("speed", 2.3)
			zombie.set("max_health", 95)
			_create_split_head(zombie)
		Type.BRUTE:
			zombie.set("speed", 1.15)
			zombie.set("max_health", 550)
			zombie.set("attack_damage", 26)
			_setup_brute(model)
		Type.SCREAMER:
			zombie.set("speed", 2.4)
			zombie.set("max_health", 85)
			_setup_screamer(zombie)
		Type.BLOATER:
			# Kamikaze: corre e se joga no jogador para explodir colado.
			zombie.set("speed", 3.2)
			zombie.set("max_health", 140)
			_setup_bloater(zombie, model)
		Type.LEAPER:
			zombie.set("speed", 2.6)
			zombie.set("max_health", 70)
			model.rotation.x = deg_to_rad(24.0)
		Type.ARMORED:
			zombie.set("speed", 1.9)
			zombie.set("max_health", 160)
			_setup_armored(zombie)
		Type.SPITTER:
			zombie.set("speed", 2.0)
			zombie.set("max_health", 80)
			_setup_spitter(zombie)
		Type.CHARGER:
			zombie.set("speed", 1.9)
			zombie.set("max_health", 220)
			_setup_charger(zombie)
		Type.JUMPER:
			zombie.set("speed", 2.5)
			zombie.set("max_health", 90)
			_setup_jumper(zombie)
		Type.SMOKER:
			zombie.set("speed", 1.9)
			zombie.set("max_health", 120)
			_setup_smoker(zombie)
		Type.HEALER:
			zombie.set("speed", 1.6)
			zombie.set("max_health", 150)
			_setup_healer(zombie)
		Type.STALKER:
			zombie.set("speed", 3.0)
			zombie.set("max_health", 80)
			_setup_stalker(zombie, model)
		Type.TITAN:
			zombie.set("speed", 1.7)
			zombie.set("max_health", 10000)
			zombie.set("attack_damage", 45)
			_setup_titan(zombie, model)
		Type.COLLECTOR:
			# Lento e bem mais duro: precisa sobreviver ate encostar no cadaver
			# para virar ameaca, senao morre na horda antes de juntar pedaco.
			zombie.set("speed", 2.0)
			zombie.set("max_health", 260)
			_setup_collector(model)
		Type.SPIDER:
			# Aranha: mais rapida que o walker e mais fragil; o susto e o corpo.
			zombie.set("speed", 3.3)
			zombie.set("max_health", 85)
			_setup_spider(zombie, model)
		Type.WALKER:
			zombie.set("speed", 2.2)
			zombie.set("max_health", 100)


## Aranha: corpo baixo e largo, costelas expostas e quatro membros finos a mais.
## O tamanho do corpo vem de BODY_SCALES (padrao das outras variantes); aqui so
## o que e proprio dela. Uso: chamado pelo _apply_anatomy.
static func _setup_spider(zombie: CharacterBody3D, model: Node3D) -> void:
	model.position.y = body_rest_y(Type.SPIDER)
	model.rotation.x = deg_to_rad(SPIDER_PITCH_DEG)
	var head := zombie.get_node_or_null("Model/Head") as Node3D
	if head != null:
		head.rotation.x = deg_to_rad(-45.0)
	var torso := zombie.get_node_or_null("Model/Torso") as MeshInstance3D
	if torso != null:
		torso.material_override = _quick_mat(Color(0.30, 0.34, 0.24), 0.98)
		# Costelas expostas: tres pares claros sobre o torso escuro.
		for rib_index in 3:
			var rib_y := -0.18 + float(rib_index) * 0.18
			_add_box(torso, Vector3(0.62, 0.06, 0.1), Vector3(0.0, 0.12 + rib_y, -0.22), Color(0.78, 0.74, 0.62))
	# Quatro membros extras: duas de cada lado, finos, abertos em diagonal.
	for limb_index in 4:
		var side := -1.0 if limb_index % 2 == 0 else 1.0
		var depth := -0.12 + float(limb_index / 2) * 0.26
		var limb := _add_box(model, Vector3(0.7, 0.09, 0.09), Vector3(side * 0.62, 0.30, depth), Color(0.78, 0.74, 0.62))
		# Nome para a passada achar as patas extras (animate_variant_pose).
		limb.name = "SpiderLimb%d" % limb_index
		limb.rotation.z = deg_to_rad(side * 28.0)
		limb.rotation.y = deg_to_rad(side * 22.0)
	var col_shape := zombie.get_node_or_null("CollisionShape") as CollisionShape3D
	if col_shape != null:
		col_shape.position = Vector3(0.0, -0.28, 0.0)
	var health_lbl := zombie.get_node_or_null("HealthLabel") as Label3D
	if health_lbl != null:
		health_lbl.position.y = 1.05


## Coletor: corcunda para frente, leitura diferente do walker sem arte nova.
static func _setup_collector(model: Node3D) -> void:
	model.rotation.x = deg_to_rad(12.0)


static func _setup_crawler(zombie: CharacterBody3D, model: Node3D) -> void:
	zombie.set("speed", 1.4)
	zombie.set("max_health", 75)
	_apply_crawler_pose(zombie, model)


## Aplica a postura baixa sem alterar os stats iniciais da variante. Uso:
## ZombieMutator.apply_crawler_locomotion(zombie)
static func apply_crawler_locomotion(zombie: CharacterBody3D) -> void:
	if zombie == null:
		return
	var crawler_model := zombie.get_node_or_null("Model") as Node3D
	if crawler_model == null:
		return
	_apply_crawler_pose(zombie, crawler_model)


static func _apply_crawler_pose(zombie: CharacterBody3D, model: Node3D) -> void:
	model.position.y = -0.45
	model.rotation.x = deg_to_rad(65.0)
	var head := zombie.get_node_or_null("Model/Head") as Node3D
	if head != null:
		head.rotation.x = deg_to_rad(-50.0)
	var col_shape := zombie.get_node_or_null("CollisionShape") as CollisionShape3D
	if col_shape != null:
		col_shape.position = Vector3(0.0, -0.3, 0.0)
		if col_shape.shape is CapsuleShape3D:
			var standing_capsule := col_shape.shape as CapsuleShape3D
			var crawler_capsule := standing_capsule.duplicate() as CapsuleShape3D
			crawler_capsule.height = crawler_capsule.radius * 2.0
			col_shape.shape = crawler_capsule
	var health_lbl := zombie.get_node_or_null("HealthLabel") as Label3D
	if health_lbl != null:
		health_lbl.position.y = 0.95


## Brute: corpo maior e ombreiras de paletizado escuro para leitura imediata.
static func _setup_brute(model: Node3D) -> void:
	# Tamanho do corpo vem de apply_body_scale; aqui so a cabeca desproporcional.
	var head := model.get_node_or_null("Head") as Node3D
	if head != null:
		head.scale = Vector3(1.2, 1.15, 1.2)


## Screamer: tronco vermelho vivo e mandibula aberta, para ser reconhecido
## antes do grito. Uso: chamado por apply_appearance no spawn.
static func _setup_screamer(zombie: CharacterBody3D) -> void:
	var torso := zombie.get_node_or_null("Model/Torso") as MeshInstance3D
	if torso != null:
		torso.material_override = _quick_mat(Color(0.55, 0.08, 0.08), 0.9)
	var head := zombie.get_node_or_null("Model/Head") as Node3D
	if head != null:
		head.rotation.x = deg_to_rad(-12.0)
		_add_box(head, Vector3(0.2, 0.12, 0.16), Vector3(0.0, -0.14, -0.24), Color(0.75, 0.72, 0.65))


## Bloater: tronco inchado esverdeado com bolhas, para ser reconhecido de longe
## (matar de perto machuca). Uso: chamado por apply_appearance no spawn.
static func _setup_bloater(zombie: CharacterBody3D, model: Node3D) -> void:
	var torso := zombie.get_node_or_null("Model/Torso") as MeshInstance3D
	if torso != null:
		torso.scale = Vector3(1.55, 1.15, 1.6)
		torso.material_override = _quick_mat(Color(0.42, 0.55, 0.18), 0.7)
		_add_box(torso, Vector3(0.18, 0.18, 0.12), Vector3(0.14, 0.1, -0.24), Color(0.7, 0.82, 0.25))
		_add_box(torso, Vector3(0.12, 0.12, 0.1), Vector3(-0.16, -0.12, -0.24), Color(0.7, 0.82, 0.25))


## Tita: pele vermelho-escura e olhos brilhando; o tamanho (2.3x) e a capsula
## vem de apply_body_scale.
static func _setup_titan(zombie: CharacterBody3D, _model: Node3D) -> void:
	for part in ["Model/Head", "Model/Torso", "Model/LeftArm/Mesh", "Model/RightArm/Mesh"]:
		var mesh := zombie.get_node_or_null(part) as MeshInstance3D
		if mesh != null:
			mesh.material_override = _quick_mat(Color(0.32, 0.08, 0.07), 0.8)
	var head := zombie.get_node_or_null("Model/Head") as Node3D
	if head != null:
		for eye_name in ["LeftEye", "RightEye"]:
			var eye := head.get_node_or_null(eye_name) as GeometryInstance3D
			if eye == null:
				continue
			var glow := _quick_mat(Color(1.0, 0.35, 0.05), 0.3, Color(1.0, 0.35, 0.05), 3.0)
			eye.material_override = glow
	var label := zombie.get_node_or_null("HealthLabel") as Label3D
	if label != null:
		label.modulate = Color(1.0, 0.4, 0.2)


## Cuspidor: pescoco esticado, pele amarelada e bolsa de acido na garganta.
static func _setup_spitter(zombie: CharacterBody3D) -> void:
	var head := zombie.get_node_or_null("Model/Head") as Node3D
	if head != null:
		head.position.y += 0.18
		_add_box(head, Vector3(0.3, 0.18, 0.2), Vector3(0.0, -0.3, -0.12), Color(0.75, 0.85, 0.2))
	var torso := zombie.get_node_or_null("Model/Torso") as MeshInstance3D
	if torso != null:
		torso.material_override = _quick_mat(Color(0.55, 0.58, 0.3), 0.85)


## Investida: braco direito enorme e ombro saltado; o corpo 1.2x vem de apply_body_scale.
static func _setup_charger(zombie: CharacterBody3D) -> void:
	var right_arm := zombie.get_node_or_null("Model/RightArm") as Node3D
	if right_arm != null:
		right_arm.scale = Vector3(1.9, 1.3, 1.9)
	var torso := zombie.get_node_or_null("Model/Torso") as Node3D
	if torso != null:
		_add_box(torso, Vector3(0.36, 0.3, 0.46), Vector3(0.36, 0.3, 0.0), Color(0.45, 0.3, 0.28))


## Puxador: pescoco longo, pele arroxeada e boca brilhando (de onde sai a lingua).
static func _setup_smoker(zombie: CharacterBody3D) -> void:
	var head := zombie.get_node_or_null("Model/Head") as Node3D
	if head != null:
		head.position.y += 0.22
		_add_box(head, Vector3(0.22, 0.08, 0.06), Vector3(0.0, -0.16, -0.29), Color(0.85, 0.2, 0.35))
	var torso := zombie.get_node_or_null("Model/Torso") as MeshInstance3D
	if torso != null:
		torso.material_override = _quick_mat(Color(0.42, 0.36, 0.48), 0.85)
		_add_box(torso, Vector3(0.16, 0.3, 0.16), Vector3(0.0, 0.52, 0.0), Color(0.42, 0.36, 0.48))


## Curandeiro: manto verde e cruz brilhante flutuando sobre a cabeca.
static func _setup_healer(zombie: CharacterBody3D) -> void:
	var torso := zombie.get_node_or_null("Model/Torso") as MeshInstance3D
	if torso != null:
		torso.material_override = _quick_mat(Color(0.18, 0.42, 0.26), 0.9)
	var head := zombie.get_node_or_null("Model/Head") as Node3D
	if head == null:
		return
	_add_box(head, Vector3(0.08, 0.3, 0.08), Vector3(0.0, 0.55, 0.0), Color(0.4, 1.0, 0.5), Color(0.3, 1.0, 0.4))
	_add_box(head, Vector3(0.24, 0.08, 0.08), Vector3(0.0, 0.58, 0.0), Color(0.4, 1.0, 0.5), Color(0.3, 1.0, 0.4))


## Espreitador: pele escura, agachado e bracos compridos.
static func _setup_stalker(zombie: CharacterBody3D, model: Node3D) -> void:
	model.rotation.x = deg_to_rad(20.0)
	for part in ["Model/Head", "Model/Torso", "Model/LeftArm/Mesh", "Model/RightArm/Mesh", "Model/LeftLeg/Mesh", "Model/RightLeg/Mesh"]:
		var mesh := zombie.get_node_or_null(part) as MeshInstance3D
		if mesh != null:
			mesh.material_override = _quick_mat(Color(0.08, 0.09, 0.12), 0.95)
	for arm in ["Model/LeftArm", "Model/RightArm"]:
		var arm_node := zombie.get_node_or_null(arm) as Node3D
		if arm_node != null:
			arm_node.scale = Vector3(0.8, 1.45, 0.8)


## Saltador: pernas esticadas e agachado, com joelheiras claras.
static func _setup_jumper(zombie: CharacterBody3D) -> void:
	for leg_path in ["Model/LeftLeg/Mesh", "Model/RightLeg/Mesh"]:
		var leg := zombie.get_node_or_null(leg_path) as MeshInstance3D
		if leg != null:
			leg.material_override = _quick_mat(Color(0.3, 0.34, 0.2), 0.8)
			_add_box(leg, Vector3(0.38, 0.14, 0.4), Vector3(0.0, 0.05, -0.05), Color(0.75, 0.7, 0.6))
	var model := zombie.get_node_or_null("Model") as Node3D
	if model != null:
		model.rotation.x = deg_to_rad(18.0)


## Armored: capacete e colete de policia escuros com faixa refletiva.
## Uso: chamado por apply_appearance no spawn.
static func _setup_armored(zombie: CharacterBody3D) -> void:
	var head := zombie.get_node_or_null("Model/Head") as Node3D
	if head != null:
		_add_box(head, Vector3(0.56, 0.2, 0.56), Vector3(0.0, 0.24, 0.0), Color(0.1, 0.11, 0.13))
		_add_box(head, Vector3(0.5, 0.12, 0.05), Vector3(0.0, 0.06, -0.29), Color(0.25, 0.3, 0.35))
	var torso := zombie.get_node_or_null("Model/Torso") as Node3D
	if torso != null:
		_add_box(torso, Vector3(0.74, 0.62, 0.46), Vector3.ZERO, Color(0.12, 0.14, 0.18))
		_add_box(torso, Vector3(0.76, 0.06, 0.48), Vector3(0.0, 0.12, 0.0), Color(0.85, 0.8, 0.2))


static func _hide_node(parent: Node, path: String) -> void:
	var node := parent.get_node_or_null(path) as Node3D
	if node != null:
		node.visible = false


static func _shorten_limb(parent: Node, path: String) -> void:
	var mesh := parent.get_node_or_null(path) as MeshInstance3D
	if mesh != null:
		mesh.scale = Vector3(0.9, 0.48, 0.9)
		mesh.position = Vector3(0.0, -0.21, 0.0)


static func _create_stump(parent: Node3D, pos: Vector3) -> void:
	if parent == null:
		return
	_add_box(parent, Vector3(0.28, 0.16, 0.28), pos, Color(0.55, 0.07, 0.08))
	_add_box(parent, Vector3(0.09, 0.16, 0.09), pos + Vector3(0.0, -0.09, 0.0), Color(0.88, 0.86, 0.80))


static func _create_split_head(zombie: CharacterBody3D) -> void:
	var head := zombie.get_node_or_null("Model/Head") as Node3D
	if head == null:
		return
	var right_eye := head.get_node_or_null("RightEye") as Node3D
	if right_eye != null:
		right_eye.visible = false

	# Cerebro exposto e cavidade craniana lacerada
	_add_box(head, Vector3(0.22, 0.36, 0.42), Vector3(0.15, 0.10, -0.02), Color(0.50, 0.05, 0.07))
	_add_box(head, Vector3(0.16, 0.10, 0.36), Vector3(0.16, 0.24, -0.02), Color(0.68, 0.10, 0.12))
	_add_box(head, Vector3(0.04, 0.38, 0.44), Vector3(0.02, 0.10, -0.02), Color(0.84, 0.82, 0.76))


## Frequencia da passada a partir da velocidade REAL, em vez do multiplicador
## fixo por tipo: acelera, freia e empurrao mudam o ritmo do passo junto com o
## deslocamento, que e o que tira a sensacao de pe patinando.
## Uso: walk_time += delta * ZombieMutator.stride_radians_per_second(velocidade)
static func stride_radians_per_second(speed: float) -> float:
	return maxf(speed, STRIDE_MIN_SPEED) * STRIDE_RADIANS_PER_METER


## Inclinacao ao virar: o corpo rola para fora da curva na proporcao da taxa de
## giro (contrapposto). Escreve model.rotation.z, canal que nenhuma pose de
## variante usa na animacao (elas escrevem model.rotation.x). Parado nao inclina.
## Uso: chamado por animate_variant_pose.
static func _apply_turn_lean(model: Node3D, is_walking: bool, turn_rate: float, delta: float) -> void:
	var wanted := 0.0
	if is_walking:
		wanted = clampf(-turn_rate * TURN_LEAN_FACTOR, -TURN_LEAN_MAX, TURN_LEAN_MAX)
	model.rotation.z = lerpf(model.rotation.z, wanted, minf(delta * 8.0, 1.0))


## Balanco secundario da cabeca: sobe e desce no ritmo do passo e volta ao
## repouso quando o zumbi para. Usa a altura de repouso do cenario como base, em
## vez do valor atual, para o offset nao acumular nem depender de estado.
## Uso: chamado por animate_variant_pose.
static func _apply_head_bob(head: Node3D, is_walking: bool, walk_time: float, delta: float) -> void:
	if head == null:
		return
	var bob := sin(walk_time * 2.0) * HEAD_BOB_AMPLITUDE if is_walking else 0.0
	head.position.y = lerpf(head.position.y, HEAD_REST_Y + bob, minf(delta * 12.0, 1.0))


static func _add_box(parent: Node3D, box_size: Vector3, pos: Vector3, color: Color, emission: Color = Color(0.0, 0.0, 0.0, 0.0)) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	mesh.material = _quick_mat(color, 0.85, emission)
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.position = pos
	# Detalhes de variante sem sombra: com 200 zumbis na tela cada peca extra
	# virava mais um draw call em cada cascata da sombra do sol.
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(inst)
	return inst


## Material de runtime compartilhado por (cor, roughness, emissao). Criar um
## material novo por zumbi e usa-lo como override faz o Godot logar
## "Parameter material is null" quando a malha e liberada segurando o RID de um
## material que morre junto (godotengine/godot#85817). Compartilhar resolve o
## spam e ainda corta a alocacao por zumbi (mesmo padrao do ZombieDissolveVisual).
## Uso: mesh.material_override = ZombieMutator._quick_mat(Color.RED, 0.9)
static var _quick_materials: Dictionary = {}

static func _quick_mat(color: Color, roughness: float, emission: Color = Color(0.0, 0.0, 0.0, 0.0), emission_energy: float = 2.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%s|%.1f" % [color.to_html(true), roughness, emission.to_html(true), emission_energy]
	var cached: Variant = _quick_materials.get(key)
	if cached != null:
		return cached as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	if emission.a > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = emission_energy
	_quick_materials[key] = mat
	return mat


## Atualiza as poses e a locomocao de acordo com a variante anatomica.
## Uso:
##   ZombieMutator.animate_variant_pose(zombie, z_type, delta, is_walking, attack_w, walk_time)
static func animate_variant_pose(
	zombie: CharacterBody3D,
	z_type: int,
	delta: float,
	is_walking: bool,
	attack_w: float,
	walk_time: float,
	cached_nodes: Dictionary = {},
	turn_rate: float = 0.0
) -> void:
	var left_arm := _pose_node(zombie, cached_nodes, "Model/LeftArm")
	var right_arm := _pose_node(zombie, cached_nodes, "Model/RightArm")
	var left_leg := _pose_node(zombie, cached_nodes, "Model/LeftLeg")
	var right_leg := _pose_node(zombie, cached_nodes, "Model/RightLeg")
	var model := _pose_node(zombie, cached_nodes, "Model")
	var head := _pose_node(zombie, cached_nodes, "Model/Head")

	if left_arm == null or right_arm == null or left_leg == null or right_leg == null or model == null:
		return

	var swing := sin(walk_time) * 0.52 if is_walking else 0.0

	# Camada procedural somada por cima da pose da variante. Fica aqui, antes do
	# match, porque so mexe em head.position.y - canal que nenhuma pose escreve
	# (elas mexem em rotacao e em model.position.y).
	_apply_head_bob(head, is_walking, walk_time, delta)
	_apply_turn_lean(model, is_walking, turn_rate, delta)

	match z_type:
		Type.CRAWLER:
			var crawl := sin(walk_time) * 0.6 if is_walking else 0.0
			left_arm.rotation.x = lerpf(left_arm.rotation.x, -0.65 + crawl + attack_w * 0.8, minf(delta * 12.0, 1.0))
			right_arm.rotation.x = lerpf(right_arm.rotation.x, -0.65 - crawl + attack_w * 0.8, minf(delta * 12.0, 1.0))
			var leg_drag := 1.45 + (sin(walk_time) * 0.08 if is_walking else 0.0)
			left_leg.rotation.x = lerpf(left_leg.rotation.x, leg_drag, minf(delta * 8.0, 1.0))
			right_leg.rotation.x = lerpf(right_leg.rotation.x, leg_drag + 0.05, minf(delta * 8.0, 1.0))
		Type.SPIDER:
			# Trote de aranha: pares em diagonal (frente-esq com tras-direita) e
			# as quatro patas extras remando no mesmo ritmo, corpo balancando.
			var trot := sin(walk_time) * 0.7 if is_walking else 0.0
			var counter := sin(walk_time + PI) * 0.7 if is_walking else 0.0
			left_leg.rotation.x = lerpf(left_leg.rotation.x, 1.15 + trot, minf(delta * 14.0, 1.0))
			right_leg.rotation.x = lerpf(right_leg.rotation.x, 1.15 + counter, minf(delta * 14.0, 1.0))
			left_arm.rotation.x = lerpf(left_arm.rotation.x, 0.95 + counter + attack_w * 1.1, minf(delta * 14.0, 1.0))
			right_arm.rotation.x = lerpf(right_arm.rotation.x, 0.95 + trot + attack_w * 1.1, minf(delta * 14.0, 1.0))
			model.position.y = lerpf(model.position.y, body_rest_y(z_type) + (sin(walk_time * 2.0) * 0.05 if is_walking else 0.0), minf(delta * 12.0, 1.0))
			for limb_index in SPIDER_LIMB_COUNT:
				var limb := _pose_node(zombie, cached_nodes, "Model/SpiderLimb%d" % limb_index)
				if limb == null:
					continue
				var limb_phase := trot if limb_index % 2 == 0 else counter
				limb.rotation.x = lerpf(limb.rotation.x, limb_phase * 0.5, minf(delta * 16.0, 1.0))
		Type.LIMPER, Type.HALF_LEG:
			var step := -sin(walk_time) * 0.55 if is_walking else 0.0
			left_leg.rotation.x = lerpf(left_leg.rotation.x, step, minf(delta * 10.0, 1.0))
			right_leg.rotation.x = lerpf(right_leg.rotation.x, 0.72 + (sin(walk_time) * 0.12 if is_walking else 0.0), minf(delta * 8.0, 1.0))
			model.position.y = lerpf(model.position.y, sin(walk_time) * -0.12 if is_walking else 0.0, minf(delta * 12.0, 1.0))
			left_arm.rotation.x = lerpf(left_arm.rotation.x, lerpf(step, 1.6, attack_w), minf(delta * 16.0, 1.0))
			right_arm.rotation.x = lerpf(right_arm.rotation.x, 0.18 + attack_w * 1.2, minf(delta * 12.0, 1.0))
		Type.ONE_ARM:
			right_arm.rotation.x = lerpf(right_arm.rotation.x, lerpf(-swing, 1.65, attack_w), minf(delta * 18.0, 1.0))
			left_leg.rotation.x = lerpf(left_leg.rotation.x, -swing, minf(delta * 10.0, 1.0))
			right_leg.rotation.x = lerpf(right_leg.rotation.x, swing, minf(delta * 10.0, 1.0))
		Type.HALF_ARM:
			right_arm.rotation.x = lerpf(right_arm.rotation.x, lerpf(-swing, 1.68, attack_w), minf(delta * 18.0, 1.0))
			var stump_flail := sin(walk_time * 1.8) * 0.35 + 0.3 if is_walking else 0.2
			left_arm.rotation.x = lerpf(left_arm.rotation.x, lerpf(stump_flail, 1.3, attack_w), minf(delta * 18.0, 1.0))
			left_leg.rotation.x = lerpf(left_leg.rotation.x, -swing, minf(delta * 10.0, 1.0))
			right_leg.rotation.x = lerpf(right_leg.rotation.x, swing, minf(delta * 10.0, 1.0))
		Type.ONE_LEG:
			var hop := sin(walk_time * 1.5) * 0.6 if is_walking else 0.0
			right_leg.rotation.x = lerpf(right_leg.rotation.x, hop, minf(delta * 14.0, 1.0))
			var hop_bob := absf(sin(walk_time * 1.5)) * 0.16 - 0.05 if is_walking else 0.0
			model.position.y = lerpf(model.position.y, hop_bob, minf(delta * 14.0, 1.0))
			left_arm.rotation.x = lerpf(left_arm.rotation.x, lerpf(hop * 0.8, 1.5, attack_w), minf(delta * 16.0, 1.0))
			right_arm.rotation.x = lerpf(right_arm.rotation.x, lerpf(-hop * 0.8, 1.5, attack_w), minf(delta * 16.0, 1.0))
		Type.HALF_HEAD:
			left_arm.rotation.x = lerpf(left_arm.rotation.x, lerpf(swing, 1.65, attack_w), minf(delta * 18.0, 1.0))
			right_arm.rotation.x = lerpf(right_arm.rotation.x, lerpf(-swing, 1.65, attack_w), minf(delta * 18.0, 1.0))
			left_leg.rotation.x = lerpf(left_leg.rotation.x, -swing, minf(delta * 10.0, 1.0))
			right_leg.rotation.x = lerpf(right_leg.rotation.x, swing, minf(delta * 10.0, 1.0))
			if head != null:
				var twitch := sin(walk_time * 2.8) * 0.12 if is_walking else 0.0
				head.rotation.z = lerpf(head.rotation.z, deg_to_rad(12.0) + twitch, minf(delta * 15.0, 1.0))
		Type.SPRINTER, Type.LEAPER:
			var run_swing := sin(walk_time) * 0.78 if is_walking else 0.0
			left_arm.rotation.x = lerpf(left_arm.rotation.x, lerpf(run_swing, 1.7, attack_w), minf(delta * 20.0, 1.0))
			right_arm.rotation.x = lerpf(right_arm.rotation.x, lerpf(-run_swing, 1.7, attack_w), minf(delta * 20.0, 1.0))
			left_leg.rotation.x = lerpf(left_leg.rotation.x, -run_swing * 1.1, minf(delta * 14.0, 1.0))
			right_leg.rotation.x = lerpf(right_leg.rotation.x, run_swing * 1.1, minf(delta * 14.0, 1.0))
		_:
			left_arm.rotation.x = lerpf(left_arm.rotation.x, lerpf(swing, 1.65, attack_w), minf(delta * 18.0, 1.0))
			right_arm.rotation.x = lerpf(right_arm.rotation.x, lerpf(-swing, 1.65, attack_w), minf(delta * 18.0, 1.0))
			left_leg.rotation.x = lerpf(left_leg.rotation.x, -swing, minf(delta * 10.0, 1.0))
			right_leg.rotation.x = lerpf(right_leg.rotation.x, swing, minf(delta * 10.0, 1.0))


## Nos de pose em cache: ~288k get_node_or_null/s com 600 zumbis viram
## um lookup no Dictionary por zumbi. Chave = caminho; valor = no (ou null).
static func _pose_node(zombie: Node3D, cache: Dictionary, path: String) -> Node3D:
	var key := "pose_" + path
	if not cache.has(key):
		cache[key] = zombie.get_node_or_null(path) as Node3D
	return cache.get(key, null)


## Aplica animacao de impacto / flinch no zumbi quando recebe dano.
## Uso:
##   ZombieMutator.animate_hit_reaction(zombie, delta, hit_time, 0.24, hit_dir, "bullet", z_type, attack_w)
static func animate_hit_reaction(
	zombie: CharacterBody3D,
	delta: float,
	hit_time: float,
	duration: float,
	hit_dir: Vector3,
	hit_kind: String,
	z_type: int,
	attack_w: float,
	cached_nodes: Dictionary = {}
) -> void:
	var model := _pose_node(zombie, cached_nodes, "Model")
	var head := _pose_node(zombie, cached_nodes, "Model/Head")
	if model == null:
		return

	var hit_weight := sin((1.0 - hit_time / duration) * PI) if hit_time > 0.0 else 0.0
	var target_x := -0.45 * hit_weight if hit_kind == "bullet" else -0.18 * attack_w
	var target_z := -hit_dir.x * 0.42 * hit_weight if hit_kind == "knife" else -hit_dir.x * 0.25 * hit_weight

	if z_type == Type.CRAWLER:
		target_x += deg_to_rad(65.0)
	elif z_type == Type.SPRINTER:
		target_x += deg_to_rad(15.0)
	elif z_type == Type.LIMPER or z_type == Type.HALF_LEG:
		target_z += deg_to_rad(8.0)

	model.rotation.x = lerpf(model.rotation.x, target_x, minf(delta * 20.0, 1.0))
	model.rotation.z = lerpf(model.rotation.z, target_z, minf(delta * 20.0, 1.0))
	model.position.z = lerpf(model.position.z, 0.14 * hit_weight, minf(delta * 20.0, 1.0))

	if head != null:
		var head_x := -0.48 * hit_weight if hit_time > 0.0 else (deg_to_rad(-50.0) if z_type == Type.CRAWLER else 0.0)
		head.rotation.x = lerpf(head.rotation.x, head_x, minf(delta * 22.0, 1.0))
