extends RefCounted

## Regressoes de "corpo flutuando": o que o jogador ve tem que encostar no chao,
## nao ficar apoiado numa colisao invisivel maior que o desenho. Cobre o zumbi
## que perdeu as duas pernas (vira rastejante) e o jipe dirigivel.
## Uso: GroundContactTests.new().run(test_root)

const ZOMBIE_SCENE: PackedScene = preload("res://scenes/zombie.tscn")
const DRIVABLE_CAR_SCENE: PackedScene = preload("res://scenes/drivable_car.tscn")
## Folga aceitavel entre o desenho e o chao. O zumbi em pe ja nasce com 0,06 m
## (pe dentro da capsula) e o braco do rastejante balanca mais uns centimetros,
## mais ainda no Tita (escala 2,3). O bug que isto pega era de 0,23 a 0,28 m.
const MAX_FLOAT := 0.15
## Quadros de fisica ate a suspensao do jipe parar de oscilar.
const SETTLE_FRAMES := 120


func run(test_root: Node) -> void:
	await _test_crawler_body_touches_the_floor(test_root)
	await _test_car_body_sits_on_its_wheels(test_root)


## Ponto mais baixo de tudo que esta desenhado, no espaco do proprio corpo.
## Uso: var base := GroundContactTests.visible_bottom(node)
static func visible_bottom(body: Node3D) -> float:
	var lowest := INF
	for node in body.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null or not instance.is_visible_in_tree():
			continue
		var aabb := instance.get_aabb()
		var relative := body.global_transform.affine_inverse() * instance.global_transform
		for corner in 8:
			lowest = minf(lowest, (relative * aabb.get_endpoint(corner)).y)
	return lowest


## Ponto mais baixo das formas de colisao ativas, no espaco do proprio corpo: e
## por onde o chao empurra. Uso: GroundContactTests.collision_bottom(node)
static func collision_bottom(body: Node3D) -> float:
	var lowest := INF
	for node in body.find_children("*", "CollisionShape3D", true, false):
		var collider := node as CollisionShape3D
		if collider.disabled or collider.shape == null:
			continue
		var relative := body.global_transform.affine_inverse() * collider.global_transform
		lowest = minf(lowest, relative.origin.y - _shape_half_height(collider.shape))
	return lowest


static func _shape_half_height(shape: Shape3D) -> float:
	if shape is CapsuleShape3D:
		return (shape as CapsuleShape3D).height * 0.5
	if shape is BoxShape3D:
		return (shape as BoxShape3D).size.y * 0.5
	if shape is SphereShape3D:
		return (shape as SphereShape3D).radius
	if shape is CylinderShape3D:
		return (shape as CylinderShape3D).height * 0.5
	return 0.0


## Chao de teste para largar um corpo de fisica em cima. Uso: interno.
static func _build_floor() -> StaticBody3D:
	var floor_body := StaticBody3D.new()
	floor_body.name = "GroundContactFloor"
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	collider.shape = box
	collider.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(collider)
	return floor_body


## O rastejo tem que valer para qualquer variante: a escala do corpo muda o
## tamanho da pose, e a animacao por frame nao pode puxar o modelo de volta.
func _test_crawler_body_touches_the_floor(test_root: Node) -> void:
	print("Testando zumbi rastejante encostando no chao...")
	for variant in [ZombieMutator.Type.WALKER, ZombieMutator.Type.BRUTE, ZombieMutator.Type.TITAN]:
		var gaps := await _crawler_gaps(test_root, variant)
		if gaps.x > MAX_FLOAT or gaps.y > MAX_FLOAT or gaps.y < 0.0:
			_fail(test_root, "Zumbi rastejante (variante %d, escala %s): folga em pe=%.3f rastejando=%.3f (maximo %.2f)." % [variant, ZombieMutator.body_scale_for(variant), gaps.x, gaps.y, MAX_FLOAT])
			return
		print("   variante %2d: em pe %.3f m, rastejando %.3f m" % [variant, gaps.x, gaps.y])
	print("PASS: Zumbi sem as pernas encosta no chao em toda variante testada.")


## Folga do desenho ate a colisao antes e depois de perder as duas pernas.
## Deixa um frame correr depois da amputacao: e onde a animacao por frame
## desfazia a pose de rastejo. Uso: interno do teste do zumbi.
func _crawler_gaps(test_root: Node, variant: int) -> Vector2:
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody3D
	zombie.set("forced_variant", variant)
	test_root.add_child(zombie)
	await test_root.get_tree().process_frame
	var standing := visible_bottom(zombie) - collision_bottom(zombie)
	zombie.call("_apply_limb_loss_mask", ZombieLimbState.LEFT_LEG | ZombieLimbState.RIGHT_LEG)
	await test_root.get_tree().process_frame
	await test_root.get_tree().physics_frame
	var crawling := visible_bottom(zombie) - collision_bottom(zombie)
	if not bool(zombie.call("is_crawling")):
		crawling = INF
	zombie.queue_free()
	return Vector2(standing, crawling)


## O jipe so assenta com a fisica rodando: a suspensao decide a altura final.
## Medir a geometria parada daria o caso comprimido, que mente a favor.
func _test_car_body_sits_on_its_wheels(test_root: Node) -> void:
	print("Testando jipe assentado no chao...")
	var tree := test_root.get_tree()
	var floor_body := _build_floor()
	test_root.add_child(floor_body)
	var car := DRIVABLE_CAR_SCENE.instantiate() as VehicleBody3D
	test_root.add_child(car)
	car.global_position = Vector3(0.0, 1.2, 0.0)
	for _frame in SETTLE_FRAMES:
		await tree.physics_frame
	var gap := car.global_position.y + visible_bottom(car)
	var resting := car.global_position.y
	car.queue_free()
	floor_body.queue_free()
	if gap > MAX_FLOAT or gap < -MAX_FLOAT:
		_fail(test_root, "Jipe assentado: base do desenho a %.3f m do chao (limite +-%.2f), carro em y=%.3f." % [gap, MAX_FLOAT, resting])
		return
	print("PASS: Jipe assentado com a base a %.3f m do chao." % gap)


func _fail(test_root: Node, message: String) -> void:
	push_error("FALHA: " + message)
	test_root.set_meta("unit_test_failed", true)
