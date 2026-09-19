class_name ZombieCollector
extends RefCounted

## Coletor (variante COLLECTOR): passa por cima do cadaver e absorve o pedaco,
## herdando a habilidade da variante morta. Roda so onde ha simulacao, como o
## resto da IA (servidor/offline).
##
## Decisoes desta primeira fatia:
## - absorve ao ENCOSTAR, em raio curto: o cadaver perde a colisao ao morrer
##   (zombie.gd desabilita o CollisionShape), entao Area3D nao resolve.
## - no maximo MAX_ABILITIES pedacos, sem repetir a mesma variante.
## - o cadaver consumido sai do `corpses` do main: o healer nao revive mais.
## - so entram as habilidades com despacho proprio e sem estado de arrancada
##   (grito, cuspe e lingua). Bote, pulo e investida dependem do `_dash_for_type`
##   e ficam para a proxima fatia, com teste proprio.

const ABSORB_RADIUS := 1.7
const ABSORB_INTERVAL := 0.25
const MAX_ABILITIES := 3
const PART_MARKER_SIZE := Vector3(0.34, 0.22, 0.30)
const PART_MARKER_BASE := Vector3(-0.18, 0.72, 0.28)
const PART_MARKER_STEP := 0.18

## Variantes cujo pedaco da uma habilidade ativa que o coletor sabe usar.
## As arrancadas (leaper/charger/jumper) e as passivas ficam de fora por ora.
const ABSORBABLE_TYPES: Array[int] = [
	ZombieMutator.Type.SCREAMER,
	ZombieMutator.Type.SPITTER,
	ZombieMutator.Type.SMOKER,
]

var inherited_types: Array[int] = []
var _absorb_timer := 0.0


## O coletor tem esta habilidade? (o despacho em zombie.gd pergunta por aqui)
## Uso: if collector.has_ability(ZombieMutator.Type.SMOKER): ...
func has_ability(zombie_type: int) -> bool:
	return inherited_types.has(zombie_type)


func is_full() -> bool:
	return inherited_types.size() >= MAX_ABILITIES


## Guarda o pedaco e marca no corpo. Recusa variante nao absorvivel, repetida ou
## com a mochila cheia, sem consumir o cadaver nesses casos.
## Uso: var pegou := collector.absorb(ZombieMutator.Type.SPITTER, zombie)
func absorb(zombie_type: int, owner: Node3D) -> bool:
	if is_full() or has_ability(zombie_type) or not ABSORBABLE_TYPES.has(zombie_type):
		return false
	inherited_types.append(zombie_type)
	_add_part_marker(owner, inherited_types.size() - 1)
	return true


## Ve se tem cadaver util encostado e absorve (checa a cada ABSORB_INTERVAL).
## Uso: collector.try_absorb_nearby(zombie, delta)
func try_absorb_nearby(owner: Node3D, delta: float) -> bool:
	if is_full() or not owner.is_inside_tree():
		return false
	_absorb_timer = maxf(_absorb_timer - delta, 0.0)
	if _absorb_timer > 0.0:
		return false
	_absorb_timer = ABSORB_INTERVAL
	var scene := owner.get_tree().current_scene
	if scene == null or not scene.has_method("consume_zombie_corpse"):
		return false
	var corpse := _nearest_absorbable_corpse(scene, owner.global_position)
	if corpse == null:
		return false
	if not absorb(int(corpse.get("zombie_type")), owner):
		return false
	scene.call("consume_zombie_corpse", corpse)
	return true


## Cadaver mais proximo dentro do raio que ainda da um pedaco util.
func _nearest_absorbable_corpse(scene: Node, from: Vector3) -> Node:
	var raw_corpses: Variant = scene.get("corpses")
	if not (raw_corpses is Array):
		return null
	var corpse_list: Array = raw_corpses as Array
	var nearest: Node = null
	var nearest_distance := ABSORB_RADIUS
	for corpse in corpse_list:
		var corpse_node := corpse as Node3D
		if corpse_node == null or not is_instance_valid(corpse_node):
			continue
		var kind := int(corpse_node.get("zombie_type"))
		if not ABSORBABLE_TYPES.has(kind) or has_ability(kind):
			continue
		var distance := from.distance_to(corpse_node.global_position)
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest = corpse_node
	return nearest


## Bloco escuro nas costas por pedaco: da para ver o coletor "crescendo" sem
## precisar de arte nova.
func _add_part_marker(owner: Node3D, index: int) -> void:
	if not is_instance_valid(owner):
		return
	var model := owner.get_node_or_null("Model") as Node3D
	if model == null:
		return
	var marker := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = PART_MARKER_SIZE
	marker.mesh = box
	marker.position = PART_MARKER_BASE + Vector3(PART_MARKER_STEP * float(index), 0.0, 0.0)
	model.add_child(marker)
