# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
extends RefCounted

## Regressoes da animacao de recarga: recarregar preenche o pente e liga o
## temporizador cosmetico (PlayerAnimator le `reload_anim_time`). Uso:
## WeaponReloadTests.new().run(test_root)

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const PLAYER_ANIMATOR: GDScript = preload("res://scripts/player_animator.gd")


func run(test_root: Node) -> void:
	_test_reload_fills_mag_and_starts_animation(test_root)


func _test_reload_fills_mag_and_starts_animation(test_root: Node) -> void:
	print("Testando a recarga da pistola (pente + animacao)...")
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.name = "ReloadTest"
	player.set("reads_local_input", false)
	player.set("simulation_enabled", false)
	player.set("is_local_controller", false)
	player.position = Vector3(1300.0, 1.0, 1300.0)
	test_root.add_child(player)
	player.set("pistol_ammo", 3)
	player.set("reserve_ammo", 30)
	player.call("_reload_pistol")
	var anim_time := float(player.get("reload_anim_time"))
	var ammo_after := int(player.get("pistol_ammo"))
	player.free()
	if ammo_after != 12 or anim_time <= 0.0 or not is_equal_approx(anim_time, PLAYER_ANIMATOR.RELOAD_ANIM_SECONDS):
		_fail(test_root, "Recarga deveria encher o pente (3->12) e ligar a animacao por %.2f s; veio pente=%d anim=%.2f." % [PLAYER_ANIMATOR.RELOAD_ANIM_SECONDS, ammo_after, anim_time])
		return
	print("PASS: Recarga enche o pente e dispara a animacao (%.2f s)." % [anim_time])


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
