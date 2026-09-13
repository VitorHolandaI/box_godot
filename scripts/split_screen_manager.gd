extends Control

const LOCAL_CAMERA_SCRIPT := preload("res://scripts/local_camera.gd")

var players: Array[Node] = []
var view_panels: Array[Control] = []
var viewports: Array[SubViewport] = []
var hud_labels: Array[Label] = []


func configure(local_players: Array[Node]) -> void:
	players = local_players
	for child in get_children():
		child.free()
	view_panels.clear()
	viewports.clear()
	hud_labels.clear()

	for index in players.size():
		_create_player_view(index)
	call_deferred("_layout_views")


func _process(_delta: float) -> void:
	var alive_zombies := get_tree().get_nodes_in_group("zombies").size()
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
