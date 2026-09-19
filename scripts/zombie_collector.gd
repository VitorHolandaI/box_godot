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

const VARIANT_ABILITIES_SCRIPT := preload("res://scripts/zombie_variant_abilities.gd")
const ABSORB_RADIUS := 1.7
const ABSORB_INTERVAL := 0.25
const MAX_ABILITIES := 3
const PART_MARKER_SIZE := Vector3(0.34, 0.22, 0.30)
const PART_MARKER_BASE := Vector3(-0.18, 0.72, 0.28)
const PART_MARKER_STEP := 0.18
## O corpo cresce um pouco a cada pedaco: leitura de "esta maior" sem arte nova.
const PART_GROWTH := 1.08
const PART_MARKER_FALLBACK_COLOR := Color(0.25, 0.25, 0.28)
## Espreitador: o coletor fica translucido, mas menos que o original (que some
## a 6 m). transparency e por instancia, entao nao mexe no material dos outros.
const STALKER_TRANSPARENCY := 0.55

## Cor do bloco de cada habilidade, para dar para ler o que ele ja comeu.
const PART_COLORS: Dictionary = {
	ZombieMutator.Type.SCREAMER: Color(0.85, 0.75, 0.20),
	ZombieMutator.Type.LEAPER: Color(0.30, 0.70, 0.35),
	ZombieMutator.Type.SPITTER: Color(0.45, 0.80, 0.25),
	ZombieMutator.Type.CHARGER: Color(0.80, 0.35, 0.20),
	ZombieMutator.Type.JUMPER: Color(0.35, 0.55, 0.85),
	ZombieMutator.Type.SMOKER: Color(0.55, 0.40, 0.75),
	ZombieMutator.Type.BLOATER: Color(0.60, 0.75, 0.20),
	ZombieMutator.Type.ARMORED: Color(0.55, 0.55, 0.60),
	ZombieMutator.Type.TITAN: Color(0.85, 0.25, 0.25),
	ZombieMutator.Type.HEALER: Color(0.30, 0.80, 0.75),
	ZombieMutator.Type.STALKER: Color(0.20, 0.20, 0.45),
}

## Todas as 11 variantes com habilidade de verdade. As outras (walker, amputados,
## brute e sprinter) so tem estatistica e anatomia, entao nao ha o que herdar.
## O kamikaze do bloater NAO e herdado de proposito: o coletor se mataria ao
## encostar; o que ele herda e a explosao da morte.
const ABSORBABLE_TYPES: Array[int] = [
	ZombieMutator.Type.SCREAMER,
	ZombieMutator.Type.BLOATER,
	ZombieMutator.Type.LEAPER,
	ZombieMutator.Type.ARMORED,
	ZombieMutator.Type.TITAN,
	ZombieMutator.Type.SPITTER,
	ZombieMutator.Type.CHARGER,
	ZombieMutator.Type.JUMPER,
	ZombieMutator.Type.SMOKER,
	ZombieMutator.Type.HEALER,
	ZombieMutator.Type.STALKER,
]

var inherited_types: Array[int] = []
## Arrancada por pedaco (leaper/charger/jumper), criada no absorb.
var dash_states: Dictionary = {}
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
	_install_dash_state(zombie_type)
	_change_appearance(owner, zombie_type, inherited_types.size() - 1)
	return true


## Arrancada do pedaco: a mesma classe que a variante original usa em zombie.gd,
## instanciada igual (os _init das subclasses nao pedem parametro).
func _install_dash_state(zombie_type: int) -> void:
	match zombie_type:
		ZombieMutator.Type.LEAPER:
			dash_states[zombie_type] = VARIANT_ABILITIES_SCRIPT.LeapState.new()
		ZombieMutator.Type.CHARGER:
			dash_states[zombie_type] = VARIANT_ABILITIES_SCRIPT.ChargeState.new()
		ZombieMutator.Type.JUMPER:
			dash_states[zombie_type] = VARIANT_ABILITIES_SCRIPT.HighJumpState.new()


## Estado de arrancada de um pedaco (null quando aquele pedaco nao tem uma).
## Uso: var charge := collector.dash_state_for(ZombieMutator.Type.CHARGER)
func dash_state_for(zombie_type: int) -> RefCounted:
	var state: Variant = dash_states.get(zombie_type)
	return state as RefCounted


## Qual arrancada usar agora: a que ja esta no ar, senao a primeira fora de
## recarga (o update decide depois se o alcance permite).
## Uso: chamado por zombie.gd/_dash_for_type.
func pick_dash_state() -> RefCounted:
	var ready_state: RefCounted = null
	for state_value in dash_states.values():
		var state := state_value as RefCounted
		if state == null:
			continue
		if bool(state.call("is_leaping")):
			return state
		if ready_state == null and bool(state.call("is_ready")):
			ready_state = state
	return ready_state


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


## Cada pedaco muda o corpo: o modelo cresce um pouco e ganha um bloco na cor
## da habilidade. Sem arte nova, e o que da leitura imediata de quem ele comeu.
func _change_appearance(owner: Node3D, zombie_type: int, index: int) -> void:
	if not is_instance_valid(owner):
		return
	var model := owner.get_node_or_null("Model") as Node3D
	if model == null:
		return
	model.scale *= PART_GROWTH
	_add_part_marker(model, PART_COLORS.get(zombie_type, PART_MARKER_FALLBACK_COLOR) as Color, index)
	if zombie_type == ZombieMutator.Type.STALKER:
		_apply_stalker_transparency(model)


## Deixa o corpo translucido sem tocar no material compartilhado das outras
## variantes: transparency e do no, nao do material.
func _apply_stalker_transparency(model: Node3D) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh != null:
			mesh.transparency = STALKER_TRANSPARENCY


func _add_part_marker(model: Node3D, color: Color, index: int) -> void:
	var marker := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = PART_MARKER_SIZE
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	box.material = material
	marker.mesh = box
	marker.position = PART_MARKER_BASE + Vector3(PART_MARKER_STEP * float(index), 0.0, 0.0)
	model.add_child(marker)
