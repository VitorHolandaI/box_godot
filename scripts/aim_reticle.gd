# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
extends Control

## Retículo de mira desenhado por cima do quadro do jogador (filho do painel do
## split). FPS: cruz pequena no centro da tela, que e para onde o tiro vai.
## 3a pessoa: linha fina do boneco ate o cursor e um ponto no cursor, no estilo
## Foxhole. O cursor e o do mouse, ou o virtual do analogico direito quando o
## jogador esta no controle. Nao intercepta mouse nem input.
## Uso (split_screen_manager):
##   var reticle := AIM_RETICLE_SCRIPT.new()
##   panel.add_child(reticle)
##   reticle.setup(player, camera)

const CROSS_COLOR := Color(0.96, 0.96, 0.9, 0.9)
const CROSS_SIZE := 7.0
const CROSS_GAP := 3.0
const LINE_COLOR := Color(1.0, 1.0, 1.0, 0.35)
const CURSOR_COLOR := Color(1.0, 0.9, 0.4, 0.9)
## Altura do peito do boneco de onde a linha de mira sai na 3a pessoa.
const AIM_LINE_HEIGHT := 1.1

var player: Node3D
var camera: Camera3D


## Liga o retículo ao jogador e a camera do quadro.
## Uso: reticle.setup(player, camera)
func setup(new_player: Node3D, new_camera: Camera3D) -> void:
	player = new_player
	camera = new_camera
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if player == null or not is_instance_valid(player):
		return
	if bool(player.get("first_person")):
		_draw_crosshair(size * 0.5)
		return
	# So quem tem cursor desenha: o dono do mouse, ou quem joga no controle (esse
	# tem o cursor virtual do analogico direito).
	if not bool(player.get("mouse_owner")) and not bool(player.call("uses_gamepad")):
		return
	if camera == null or not is_instance_valid(camera):
		return
	var from := camera.unproject_position(player.global_position + Vector3.UP * AIM_LINE_HEIGHT)
	var to: Vector2 = player.call("aim_cursor_position")
	if from.distance_squared_to(to) < 1.0:
		return
	draw_line(from, to, LINE_COLOR, 1.0)
	draw_circle(to, 3.0, CURSOR_COLOR)


## Cruz de mira centrada (FPS). Uso: interno do _draw.
func _draw_crosshair(center: Vector2) -> void:
	var inner := CROSS_GAP
	var outer := CROSS_GAP + CROSS_SIZE
	draw_line(center + Vector2(-outer, 0.0), center + Vector2(-inner, 0.0), CROSS_COLOR, 1.5)
	draw_line(center + Vector2(inner, 0.0), center + Vector2(outer, 0.0), CROSS_COLOR, 1.5)
	draw_line(center + Vector2(0.0, -outer), center + Vector2(0.0, -inner), CROSS_COLOR, 1.5)
	draw_line(center + Vector2(0.0, inner), center + Vector2(0.0, outer), CROSS_COLOR, 1.5)
	draw_circle(center, 1.2, CROSS_COLOR)
