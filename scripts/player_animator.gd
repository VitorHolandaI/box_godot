class_name PlayerAnimator
extends RefCounted

## Gerenciador procedural de poses, marcha e animacoes de impacto do jogador.
## Uso:
##   PlayerAnimator.animate_pose(player, delta, is_walking)

const KNIFE_ATTACK_DURATION := 0.4
## Duracao da animacao de recarga; espelha PlayerCharacter.RELOAD_ANIM_SECONDS.
const RELOAD_ANIM_SECONDS := 1.0
## Ponta do braco (a mao) no espaco do braco; a arma e presa ali (o -Z avanca a
## arma pra frente da mao). Antes a arma ficava num offset fixo e flutuava.
const HAND_ANCHOR_LOCAL := Vector3(0.0, -0.72, -0.12)
## Ajuste fino por ARMA (achado no tuner do --armas-lab): desloca no referencial
## do Model e gira, somando por cima da ancora da mao. Chave = WeaponStats.Kind.
## Uso: var tuned := WEAPON_HOLD_TUNE.get(kind, {})
const WEAPON_HOLD_TUNE := {
	1: {"pos": Vector3(-0.08, -0.02, 0.0), "rot": Vector3(0.0, 0.0, 0.0)},   # pistol
	6: {"pos": Vector3(0.0, 0.05, -0.05), "rot": Vector3(0.0, -PI, 0.0)},    # carbine (modelo invertido)
	16: {"pos": Vector3(0.0, 0.0, 0.0), "rot": Vector3(0.0, -PI, 0.0)},      # sniper (modelo invertido)
	11: {"pos": Vector3(-0.05, 0.0, 0.0), "rot": Vector3(0.0, 0.0, 0.0)},    # railgun
	14: {"pos": Vector3(-0.05, 0.05, 0.05), "rot": Vector3(0.0, 0.0, 0.0)},  # aug
	17: {"pos": Vector3(0.0, 0.05, 0.05), "rot": Vector3(0.0, 0.0, 0.0)},    # bazooka
	20: {"pos": Vector3(0.0, -0.25, 0.0), "rot": Vector3(0.0, 0.0, 0.0)},    # chainsaw
	21: {"pos": Vector3(-0.05, 0.0, 0.0), "rot": Vector3(0.0, 0.0, 0.0)},    # flamethrower
}


static func animate_pose(player: Node3D, delta: float, is_walking: bool) -> void:
	var target_swing: float = 0.0
	var is_sprint: bool = bool(player.get("is_sprinting"))
	if is_walking:
		var current_walk: float = float(player.get("walk_time")) + delta * (13.5 if is_sprint else 8.5)
		player.set("walk_time", current_walk)
		target_swing = sin(current_walk) * (0.9 if is_sprint else 0.65)

	var cur_weapon: int = int(player.get("current_weapon"))
	var left_arm := player.get_node_or_null("Model/LeftArm") as Node3D
	var right_arm := player.get_node_or_null("Model/RightArm") as Node3D
	var knife_model := player.get_node_or_null("Model/RightArm/Knife") as Node3D
	var weapon_holder := player.get_node_or_null("Model/Weapons") as Node3D
	var left_leg := player.get_node_or_null("Model/LeftLeg") as Node3D
	var right_leg := player.get_node_or_null("Model/RightLeg") as Node3D
	var model := player.get_node_or_null("Model") as Node3D

	if cur_weapon == 0: # Weapon.KNIFE
		var strike_weight: float = 0.0
		var knife_t: float = float(player.get("knife_attack_time"))
		if knife_t > 0.0:
			var strike_progress: float = 1.0 - knife_t / KNIFE_ATTACK_DURATION
			strike_weight = sin(strike_progress * PI)
		var left_pose := Vector3(0.58, 0.0, 0.34).lerp(Vector3(0.9, 0.0, 0.42), strike_weight)
		var right_pose := Vector3(0.58, 0.0, -0.34).lerp(Vector3(1.45, 0.0, -0.12), strike_weight)
		if left_arm != null:
			_set_arm_pose(left_arm, left_pose, delta)
		if right_arm != null:
			_set_arm_pose(right_arm, right_pose, delta)
		if knife_model != null:
			knife_model.rotation.x = lerpf(knife_model.rotation.x, -right_pose.x, minf(delta * 20.0, 1.0))
	elif cur_weapon == 1 and float(player.get("pistol_stance_time")) > 0.0:
		if left_arm != null:
			_set_arm_pose(left_arm, Vector3(1.28, 0.0, 0.38), delta)
		if right_arm != null:
			_set_arm_pose(right_arm, Vector3(1.28, 0.0, -0.38), delta)
		var recoil: float = 0.12 if float(player.get("pistol_recoil_time")) > 0.0 else 0.0
		_anchor_weapon_to_hand(right_arm, weapon_holder, recoil, delta)
	elif cur_weapon >= 2 and float(player.get("crate_weapon_stance_time")) > 0.0:
		# Arma de crate: armas longas (fuzil, escopeta, sniper...) vao com as
		# DUAS maos na arma (a esquerda alcanca o guarda-mao); pistola/revolver/
		# serrada seguem de uma mao so.
		var two_hands := WeaponStats.uses_two_hands(cur_weapon)
		if left_arm != null:
			_set_arm_pose(left_arm, Vector3(1.45, 0.0, 0.52) if two_hands else Vector3(0.72, 0.0, 0.4), delta)
		if right_arm != null:
			_set_arm_pose(right_arm, Vector3(1.35, 0.0, -0.3), delta)
		# Recuo proprio de cada arma, dirigido pelo clarao do cano (que ja viaja
		# no snapshot): a arma segue a mao e o coice entra no offset (cano sobe).
		var kick := clampf(float(player.get("muzzle_flash_time")) / 0.08, 0.0, 1.0)
		var recoil := WeaponStats.recoil_for(cur_weapon) * kick
		var settle := 40.0 if kick > 0.0 else 16.0
		_anchor_weapon_to_hand(right_arm, weapon_holder, recoil.x, delta, settle)
		if weapon_holder != null:
			weapon_holder.rotation.x = lerpf(weapon_holder.rotation.x, recoil.y, minf(delta * settle, 1.0))
	else:
		if left_arm != null:
			_set_arm_pose(left_arm, Vector3(0.72, 0.0, 0.46), delta)
		if right_arm != null:
			_set_arm_pose(right_arm, Vector3(0.62, 0.0, -0.32), delta)
		if weapon_holder != null:
			weapon_holder.position = weapon_holder.position.lerp(Vector3(0.24, 0.45, -0.42), minf(delta * 10.0, 1.0))

	if left_leg != null:
		left_leg.rotation.x = lerpf(left_leg.rotation.x, -target_swing, minf(delta * 12.0, 1.0))
	if right_leg != null:
		right_leg.rotation.x = lerpf(right_leg.rotation.x, target_swing, minf(delta * 12.0, 1.0))
	if model != null:
		model.rotation.x = lerpf(model.rotation.x, -0.14 if is_sprint else 0.0, minf(delta * 10.0, 1.0))

	_apply_reload_pose(player, delta)
	_animate_hit_reaction(player, delta)
	_apply_hold_tuning(player)


## Pose de ajuste por arma vinda do tuner (--armas-lab): desloca na mao e gira,
## para achar o grip certo sem recompilar. Uso: lido de player.weapon_holds.
static func _apply_hold_tuning(player: Node3D) -> void:
	var kind := int(player.get("current_weapon"))
	var offset := Vector3.ZERO
	var rot := Vector3.ZERO
	var tuned: Dictionary = WEAPON_HOLD_TUNE.get(kind, {})
	offset += tuned.get("pos", Vector3.ZERO)
	rot += tuned.get("rot", Vector3.ZERO)
	# O tuner do --armas-lab soma por cima do ajuste fixo (permite continuar
	# refinando sem recompilar).
	var table: Variant = player.get("weapon_holds")
	if table is Dictionary and (table as Dictionary).has(kind):
		var hold: Dictionary = (table as Dictionary)[kind]
		offset += hold.get("pos", Vector3.ZERO)
		rot += hold.get("rot", Vector3.ZERO)
	if offset.is_zero_approx() and rot.is_zero_approx():
		return
	var weapon_holder := player.get_node_or_null("Model/Weapons") as Node3D
	var model := player.get_node_or_null("Model") as Node3D
	if weapon_holder == null:
		return
	# Offset no referencial do MODEL (cima/lados/frente intuitivos), nao no
	# referencial do braco (que fica girado na mira).
	if model != null and not offset.is_zero_approx():
		weapon_holder.global_position += model.global_transform.basis * offset
	weapon_holder.rotation = rot


## Recarga (cosmetica): a mao esquerda desce ate a arma e o cano baixa, com pico
## no meio da animacao; sempre volta a zero (inclusive quando nao recarrega).
## Uso: chamado dentro de animate_pose apos as posturas.
static func _apply_reload_pose(player: Node3D, delta: float) -> void:
	var weapon_holder := player.get_node_or_null("Model/Weapons") as Node3D
	var reload_t: float = float(player.get("reload_anim_time"))
	var weight: float = 0.0
	if reload_t > 0.0 and int(player.get("current_weapon")) >= 1:
		var progress: float = 1.0 - reload_t / RELOAD_ANIM_SECONDS
		weight = sin(clampf(progress, 0.0, 1.0) * PI)
		var left_arm := player.get_node_or_null("Model/LeftArm") as Node3D
		if left_arm != null:
			_set_arm_pose(left_arm, Vector3(0.72, 0.0, 0.55).lerp(Vector3(0.95, 0.0, 0.7), weight), delta)
	if weapon_holder != null:
		weapon_holder.rotation.z = lerpf(weapon_holder.rotation.z, 0.5 * weight, minf(delta * 12.0, 1.0))


static func _animate_hit_reaction(player: Node3D, delta: float) -> void:
	var hit_t: float = float(player.get("hit_reaction_time"))
	var hit_weight: float = sin((1.0 - hit_t / 0.35) * PI) if hit_t > 0.0 else 0.0
	var model := player.get_node_or_null("Model") as Node3D
	var head := player.get_node_or_null("Model/Head") as Node3D
	var left_arm := player.get_node_or_null("Model/LeftArm") as Node3D
	var right_arm := player.get_node_or_null("Model/RightArm") as Node3D
	var torso := player.get_node_or_null("Model/Torso") as MeshInstance3D
	var hit_dir_val: Variant = player.get("hit_direction")
	var hit_dir: Vector3 = hit_dir_val if hit_dir_val is Vector3 else Vector3.ZERO

	if hit_weight > 0.001:
		if model != null:
			model.rotation.x = lerpf(model.rotation.x, -0.42 * hit_weight, minf(delta * 22.0, 1.0))
			model.rotation.z = lerpf(model.rotation.z, -hit_dir.x * 0.35 * hit_weight, minf(delta * 22.0, 1.0))
			model.position.y = lerpf(model.position.y, 0.15 * hit_weight, minf(delta * 18.0, 1.0))
			model.position.z = lerpf(model.position.z, 0.14 * hit_weight, minf(delta * 18.0, 1.0))
		if head != null:
			head.rotation.x = lerpf(head.rotation.x, -0.52 * hit_weight, minf(delta * 25.0, 1.0))
			head.rotation.z = lerpf(head.rotation.z, hit_dir.x * 0.28 * hit_weight, minf(delta * 25.0, 1.0))
		if left_arm != null:
			left_arm.rotation.x = lerpf(left_arm.rotation.x, left_arm.rotation.x - 0.7 * hit_weight, minf(delta * 20.0, 1.0))
		if right_arm != null:
			right_arm.rotation.x = lerpf(right_arm.rotation.x, right_arm.rotation.x - 0.7 * hit_weight, minf(delta * 20.0, 1.0))
	else:
		if head != null:
			head.rotation.x = lerpf(head.rotation.x, 0.0, minf(delta * 12.0, 1.0))
			head.rotation.z = lerpf(head.rotation.z, 0.0, minf(delta * 12.0, 1.0))
		if model != null:
			model.position.z = lerpf(model.position.z, 0.0, minf(delta * 12.0, 1.0))

	if torso != null and torso.material_override is StandardMaterial3D:
		var uniform_mat := torso.material_override as StandardMaterial3D
		uniform_mat.emission_enabled = hit_weight > 0.05
		uniform_mat.emission = Color(0.85, 0.08, 0.08) * hit_weight


static func _set_arm_pose(arm: Node3D, target_rotation: Vector3, delta: float) -> void:
	arm.rotation = arm.rotation.lerp(target_rotation, minf(delta * 12.0, 1.0))


## Prende a arma na ponta do braco direito (a mao); o coice empurra pra tras no
## eixo do braco. Uso: _anchor_weapon_to_hand(right_arm, weapon_holder, coice, delta)
static func _anchor_weapon_to_hand(arm: Node3D, weapon_holder: Node3D, recoil_back: float, delta: float, rate: float = 18.0) -> void:
	if arm == null or weapon_holder == null or not arm.is_inside_tree() or not weapon_holder.is_inside_tree():
		return
	var arm_basis := arm.global_transform.basis
	var target := arm.global_position + arm_basis * (HAND_ANCHOR_LOCAL + Vector3(0.0, 0.0, recoil_back))
	weapon_holder.global_position = weapon_holder.global_position.lerp(target, minf(delta * rate, 1.0))
