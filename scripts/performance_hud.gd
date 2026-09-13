extends Label

const MEGABYTE := 1048576.0


func _ready() -> void:
	add_theme_font_size_override("font_size", 15)
	add_theme_color_override("font_color", Color(0.95, 0.95, 0.85))
	add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	add_theme_constant_override("shadow_offset_x", 2)
	add_theme_constant_override("shadow_offset_y", 2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	text = _build_text()
	var viewport_size := get_viewport_rect().size
	position = Vector2(viewport_size.x - size.x - 12.0, 12.0)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		visible = not visible


func _build_text() -> String:
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	var draw_calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var objects := Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var primitives := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var node_count := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var active_physics := Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)
	var memory_static := Performance.get_monitor(Performance.MEMORY_STATIC)
	return "FPS %d | draw %d | objs %d | prim %d | nodes %d | phys %d | mem %.1f MB" % [
		roundi(fps),
		int(draw_calls),
		int(objects),
		int(primitives),
		int(node_count),
		int(active_physics),
		memory_static / MEGABYTE,
	]
