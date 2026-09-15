class_name NetworkZombieProxyFactory
extends RefCounted

## Cria o zumbi "proxy" do cliente a partir de um estado do snapshot. A variante
## vem do servidor (sorteada pela onda) e e aplicada ANTES do _ready: derivar so
## do nome dava outro tipo e outra aparencia no cliente.
## Uso:
##   var zombie := NetworkZombieProxyFactory.instantiate_proxy(ZOMBIE_SCENE, "ZombieSpawn7", state)
##   zombies.add_child(zombie, true)


## Zumbi sem simulacao, com nome, tipo e posicao inicial do estado recebido.
## Uso: var zombie := NetworkZombieProxyFactory.instantiate_proxy(scene, "ZombieSpawn7", {"position": Vector3.ZERO, "zombie_type": 5})
static func instantiate_proxy(zombie_scene: PackedScene, zombie_name: String, state: Dictionary) -> CharacterBody3D:
	var zombie := zombie_scene.instantiate() as CharacterBody3D
	zombie.name = zombie_name
	zombie.set("simulation_enabled", false)
	var zombie_type := int(state.get("zombie_type", -1))
	if zombie_type >= 0:
		zombie.set("forced_variant", zombie_type)
	var initial_position: Variant = state.get("position")
	if initial_position is Vector3:
		zombie.position = initial_position
	return zombie
