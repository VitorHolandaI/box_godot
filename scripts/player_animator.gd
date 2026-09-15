class_name PlayerAnimator
extends RefCounted

## Gerenciador procedural de poses, marcha e animacoes de impacto do jogador.
## Uso:
##   PlayerAnimator.animate_pose(player, delta, is_walking)

const KNIFE_ATTACK_DURATION := 0.4


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
		if weapon_holder != null:
			weapon_holder.position = weapon_holder.position.lerp(Vector3(0.0, 0.68, -0.9 + recoil), minf(delta * 16.0, 1.0))
	elif cur_weapon >= 2 and float(player.get("crate_weapon_stance_time")) > 0.0:
		# Arma de crate: mira com as DUAS maos esticadas na arma (nao fica
		# na postura tatica da pistola).
		if left_arm != null:
			_set_arm_pose(left_arm, Vector3(1.35, 0.0, 0.3), delta)
		if right_arm != null:
			_set_arm_pose(right_arm, Vector3(1.35, 0.0, -0.3), delta)
		if weapon_holder != null:
			# Recuo proprio de cada arma, dirigido pelo clarao do cano (que ja
			# viaja no snapshot): coice para tras e cano subindo, e volta rapido.
			var kick := clampf(float(player.get("muzzle_flash_time")) / 0.08, 0.0, 1.0)
			var recoil := WeaponStats.recoil_for(cur_weapon) * kick
			var settle := 40.0 if kick > 0.0 else 16.0
			weapon_holder.position = weapon_holder.position.lerp(Vector3(0.0, 0.62, -1.0 + recoil.x), minf(delta * settle, 1.0))
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

	_animate_hit_reaction(player, delta)


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
