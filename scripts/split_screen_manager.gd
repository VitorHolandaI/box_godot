extends Control

const LOCAL_CAMERA_SCRIPT := preload("res://scripts/local_camera.gd")
const VISION_OVERLAY_LAYER_START := 17
const MINIMAP_SIZE := 150.0
const MINIMAP_WORLD_EXTENT := 160.0
# Fim de onda: com poucos zumbis vivos o minimapa mostra todos, para ninguem
# ficar cacando o ultimo escondido atras de um predio.
const STRAGGLER_REVEAL_COUNT := 5
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
	var tracked_zombies: Array = []
	var tracked_crates: Array = []
	var tracked_loot: Array = []
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
		for zombie_node in tracked_zombies:
			var zombie := zombie_node as Node3D
			if zombie == null or not is_instance_valid(zombie):
				continue
			# Zumbi fora do alcance do mapa fica preso na borda, apontando a direcao.
			var zombie_point := (center + Vector2(zombie.global_position.x, zombie.global_position.z) * scale_value).clamp(Vector2.ONE * 6.0, size - Vector2.ONE * 6.0)
			draw_circle(zombie_point, 5.0, Color(1.0, 0.12, 0.08, 0.95))
			draw_arc(zombie_point, 8.0, 0.0, TAU, 16, Color(1.0, 0.55, 0.1, 0.8), 2.0)
		for crate_node in tracked_crates:
			var crate := crate_node as Node3D
			if crate == null or not is_instance_valid(crate):
				continue
			_draw_crate_widget(crate.global_position, center, scale_value)
		for loot_node in tracked_loot:
			var loot := loot_node as Node3D
			if loot == null or not is_instance_valid(loot):
				continue
			var loot_point := (center + Vector2(loot.global_position.x, loot.global_position.z) * scale_value).clamp(Vector2.ONE * 8.0, size - Vector2.ONE * 8.0)
			draw_rect(Rect2(loot_point - Vector2(3.0, 3.0), Vector2(6.0, 6.0)), Color(0.95, 0.8, 0.2, 0.9), true)



	## Widget do crate no minimapa: icone de paraquedas e, quando o crate esta
	## fora do alcance do mapa, seta presa na borda apontando a direcao.
	func _draw_crate_widget(crate_position: Vector3, center: Vector2, scale_value: float) -> void:
		var raw_point := center + Vector2(crate_position.x, crate_position.z) * scale_value
		var edge_rect := Rect2(Vector2.ONE * 8.0, size - Vector2.ONE * 16.0)
		var outside := not edge_rect.has_point(raw_point)
		var point := raw_point.clamp(edge_rect.position, edge_rect.end)
		var pulse := 0.7 + 0.3 * absf(sin(Time.get_ticks_msec() / 220.0))
		draw_circle(point, 7.0, Color(1.0, 0.85, 0.1, 0.95))
		draw_rect(Rect2(point - Vector2(4.0, 4.0), Vector2(8.0, 8.0)), Color(0.35, 0.22, 0.08), true)
		draw_circle(point, 4.5, Color(0.95, 0.2, 0.15))
		if outside:
			var direction := (raw_point - point).normalized()
			if direction.length_squared() < 0.001:
				direction = (point - center).normalized()
			var tip := point + direction * 9.0
			var left := point + direction.rotated(2.4) * 7.0
			var right := point + direction.rotated(-2.4) * 7.0
			var arrow_color := Color(1.0, 0.85, 0.1, 0.7 + 0.3 * pulse)
			draw_line(left, tip, arrow_color, 2.0)
			draw_line(right, tip, arrow_color, 2.0)
			draw_line(left, right, arrow_color, 2.0)

var players: Array[Node] = []
var view_panels: Array[Control] = []
var viewports: Array[SubViewport] = []
var hud_labels: Array[Label] = []
var minimaps: Array[Control] = []
var straggler_reveal_count := STRAGGLER_REVEAL_COUNT


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
	var all_zombies := get_tree().get_nodes_in_group("zombies")
	var all_crates: Array = []
	var all_loot: Array = []
	for node in get_tree().get_nodes_in_group("ground_weapons"):
		if node is AirSupplyPickup:
			all_crates.append(node)
		elif node is GroundWeaponPickup:
			all_loot.append(node)
	for index in minimaps.size():
		var view_player: Node = players[index] if index < players.size() else null
		var reveal_zombies: Array = stragglers_to_reveal(all_zombies, straggler_reveal_count)
		if reveal_zombies.is_empty() and view_player != null and is_instance_valid(view_player) and view_player.has_method("is_sonar_active") and view_player.is_sonar_active():
			reveal_zombies = _zombies_near(view_player as Node3D, all_zombies, float(view_player.get_sonar_reveal_radius()))
		minimaps[index].tracked_players = all_players
		minimaps[index].tracked_zombies = reveal_zombies
		minimaps[index].tracked_crates = all_crates
		minimaps[index].tracked_loot = all_loot
		minimaps[index].queue_redraw()
	for index in players.size():
		var player := players[index]
		if not is_instance_valid(player):
			continue
		hud_labels[index].text = "P%d | %s\n%s\nVida: %d/%d\n%s\n%s | %s\n%s\nZumbis: %d | Abates: %d\n%s\n%s" % [
			index + 1,
			player.input_device_name,
			player.get_lives_text(),
			player.health,
			player.max_health,
			player.get_stamina_text(),
			player.get_weapon_name(),
			player.get_ammo_text(),
			player.get_weapon_slots_text(),
			alive_zombies,
			player.zombie_kills,
			player.get_sonar_text(),
			get_tree().current_scene.get_survival_hud_text() if get_tree().current_scene.has_method("get_survival_hud_text") else "",
		]


## Todos os zumbis vivos quando restam no maximo `max_count`; senao, nenhum.
## Uso: var revelados := preload("res://scripts/split_screen_manager.gd").stragglers_to_reveal(zumbis, 5)
static func stragglers_to_reveal(zombies: Array, max_count: int) -> Array:
	var alive: Array = []
	for zombie_node in zombies:
		if is_instance_valid(zombie_node) and zombie_node.get("is_dead") != true:
			alive.append(zombie_node)
	return alive if alive.size() <= max_count else []


## Filtra os zumbis dentro do raio de revelacao do pulso sonar.
## Uso: var revelados := _zombies_near(player, todos, 45.0)
func _zombies_near(origin: Node3D, zombies: Array, radius: float) -> Array:
	var found: Array = []
	if origin == null or not is_instance_valid(origin):
		return found
	var radius_squared := radius * radius
	for zombie_node in zombies:
		var zombie := zombie_node as Node3D
		if zombie == null or not is_instance_valid(zombie):
			continue
		if origin.global_position.distance_squared_to(zombie.global_position) <= radius_squared:
			found.append(zombie)
	return found


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
