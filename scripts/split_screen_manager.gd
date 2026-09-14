extends Control

const LOCAL_CAMERA_SCRIPT := preload("res://scripts/local_camera.gd")
const VISION_OVERLAY_LAYER_START := 17
const MINIMAP_SIZE := 150.0
const MINIMAP_WORLD_EXTENT := 160.0
const MINIMAP_PLAYER_COLORS := [
	Color(0.4, 1.0, 0.4),
	Color(1.0, 0.85, 0.2),
	Color(0.4, 0.85, 1.0),
	Color(1.0, 0.4, 0.85),
]


## Desenha um minimapa com o jogador local e todos os aliados do quadro.
## O mapa e centrado na origem do mundo, cobrindo cidade e floresta.
class MinimapView extends Control:
	var tracked_players: Array = []
	var own_player: Node = null
	var world_extent := 160.0
	var colors: Array = []

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		draw_rect(rect, Color(0.05, 0.06, 0.08, 0.6))
		draw_rect(rect, Color(0.9, 0.9, 0.9, 0.5), false, 1.0)
		var center := size * 0.5
		var scale_value := (minf(size.x, size.y) * 0.5) / world_extent
		for index in tracked_players.size():
			var node := tracked_players[index] as Node3D
			if node == null or not is_instance_valid(node):
				continue
			var point := center + Vector2(node.global_position.x, node.global_position.z) * scale_value
			var color: Color = colors[index % colors.size()] if not colors.is_empty() else Color.WHITE
			if node == own_player:
				draw_circle(point, 6.0, Color(1, 1, 1, 0.95))
			draw_circle(point, 4.0, color)

var players: Array[Node] = []
var view_panels: Array[Control] = []
var viewports: Array[SubViewport] = []
var hud_labels: Array[Label] = []
var minimaps: Array[Control] = []


func configure(local_players: Array[Node]) -> void:
	players = local_players
	for child in get_children():
		child.free()
	view_panels.clear()
	viewports.clear()
	hud_labels.clear()
	minimaps.clear()

	for index in players.size():
		_create_player_view(index)
	call_deferred("_layout_views")


func _process(_delta: float) -> void:
	var alive_zombies := get_tree().get_nodes_in_group("zombies").size()
	var all_players := get_tree().get_nodes_in_group("player")
	for index in minimaps.size():
		minimaps[index].tracked_players = all_players
		minimaps[index].queue_redraw()
	for index in players.size():
		var player := players[index]
		if not is_instance_valid(player):
			continue
		hud_labels[index].text = "P%d | %s\n%s\nVida: %d/%d\n%s\n%s | %s\nZumbis: %d | Abates: %d\n%s" % [
			index + 1,
			player.input_device_name,
			player.get_lives_text(),
			player.health,
			player.max_health,
			player.get_stamina_text(),
			player.get_weapon_name(),
			player.get_ammo_text(),
			alive_zombies,
			player.zombie_kills,
			get_tree().current_scene.get_survival_hud_text() if get_tree().current_scene.has_method("get_survival_hud_text") else "",
		]


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and not view_panels.is_empty():
		_layout_views()


func _create_player_view(index: int) -> void:
	var panel := Control.new()
	panel.clip_contents = true
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	view_panels.append(panel)

	var container := SubViewportContainer.new()
	container.stretch = false
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(container)

	var viewport := SubViewport.new()
	viewport.world_3d = get_viewport().world_3d
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.audio_listener_enable_3d = true
	viewport.msaa_3d = GameConfig.get_msaa_3d()
	viewport.gui_disable_input = true
	container.add_child(viewport)
	viewports.append(viewport)

	var camera := Camera3D.new()
	camera.set_script(LOCAL_CAMERA_SCRIPT)
	viewport.add_child(camera)
	camera.set("target", players[index])
	camera.make_current()
	for layer in range(VISION_OVERLAY_LAYER_START, VISION_OVERLAY_LAYER_START + 4):
		camera.set_cull_mask_value(layer, layer == VISION_OVERLAY_LAYER_START + index)
	if players[index].has_method("configure_vision_overlay"):
		players[index].configure_vision_overlay(VISION_OVERLAY_LAYER_START + index)

	var hud := Label.new()
	hud.position = Vector2(14, 12)
	hud.add_theme_font_size_override("font_size", 16)
	hud.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
	hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	hud.add_theme_constant_override("shadow_offset_x", 2)
	hud.add_theme_constant_override("shadow_offset_y", 2)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hud)
	hud_labels.append(hud)

	var minimap := MinimapView.new()
	minimap.own_player = players[index]
	minimap.world_extent = MINIMAP_WORLD_EXTENT
	minimap.colors = MINIMAP_PLAYER_COLORS
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.anchor_left = 1.0
	minimap.anchor_top = 1.0
	minimap.anchor_right = 1.0
	minimap.anchor_bottom = 1.0
	minimap.offset_left = -MINIMAP_SIZE - 12.0
	minimap.offset_top = -MINIMAP_SIZE - 12.0
	minimap.offset_right = -12.0
	minimap.offset_bottom = -12.0
	panel.add_child(minimap)
	minimaps.append(minimap)


func _layout_views() -> void:
	var count := view_panels.size()
	if count == 0:
		return

	var columns := 1 if count == 1 else 2
	var rows := 1 if count <= 2 else 2
	var cell_size := Vector2(size.x / columns, size.y / rows)
	for index in count:
		var column := index % columns
		var row := index / columns
		view_panels[index].position = Vector2(column, row) * cell_size
		view_panels[index].size = cell_size
		viewports[index].size = Vector2i(maxi(roundi(cell_size.x), 1), maxi(roundi(cell_size.y), 1))
