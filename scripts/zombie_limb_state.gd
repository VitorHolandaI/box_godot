# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name ZombieLimbState
extends RefCounted

## Bits compartilhados pelo zumbi vivo, snapshot e ragdoll. Uso:
##   if mask & ZombieLimbState.LEFT_ARM != 0: hide_left_arm()

const LEFT_ARM := 1
const RIGHT_ARM := 2
const LEFT_LEG := 4
const RIGHT_LEG := 8
const ALL := LEFT_ARM | RIGHT_ARM | LEFT_LEG | RIGHT_LEG


static func bit_for_name(limb_name: String) -> int:
	match limb_name:
		"left_arm":
			return LEFT_ARM
		"right_arm":
			return RIGHT_ARM
		"left_leg":
			return LEFT_LEG
		"right_leg":
			return RIGHT_LEG
	push_error("Nome de membro invalido '%s'; esperado left_arm/right_arm/left_leg/right_leg." % limb_name)
	return 0
