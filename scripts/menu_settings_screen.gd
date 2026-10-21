# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name MenuSettingsScreen
extends VBoxContainer

## Tela de configuracoes reutilizavel (menu principal e painel do Esc): graficos,
## audio e jogabilidade. Cada controle aplica e salva na hora, sem botao Aplicar.
## Uso: var tela := MenuSettingsScreen.new(); content.add_child(tela)

signal changed(message: String)

const LABEL_WIDTH := 220.0

var _status: Label
var _fov_value: Label
var _volume_value: Label


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	_build_graphics()
	_build_audio()
	_build_gameplay()
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", MenuTheme.WARNING)
	add_child(_status)


func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	add_child(grid)
	return grid


func _build_graphics() -> void:
	add_child(MenuTheme.section_label("GRAFICOS"))
	var grid := _grid()
	_add_option(grid, "Resolucao", _resolution_labels(), _resolution_index(), _on_resolution).name = "Resolution"
	_add_option(grid, "Modo de janela", _window_labels(), int(GameConfig.graphics_window_mode), _on_window_mode).name = "WindowMode"
	_add_option(grid, "Qualidade", _quality_labels(), int(GameConfig.graphics_quality), _on_quality).name = "Quality"
	_add_option(grid, "Escala de render", _render_scale_labels(), _render_scale_index(), _on_render_scale).name = "RenderScale"
	_add_option(grid, "Limite de FPS", _fps_labels(), _fps_index(), _on_fps).name = "MaxFps"
	_add_check(grid, "Sombras", GameConfig.graphics_shadows, _on_shadows).name = "Shadows"
	_add_check(grid, "Nevoa", GameConfig.graphics_fog, _on_fog).name = "Fog"
	_add_check(grid, "V-Sync", GameConfig.graphics_vsync, _on_vsync).name = "VSync"
	_fov_value = _add_slider(grid, "Campo de visao (FOV)", GameConfig.FOV_MIN, GameConfig.FOV_MAX, GameConfig.graphics_fov, _on_fov)


func _build_audio() -> void:
	add_child(MenuTheme.section_label("AUDIO"))
	var grid := _grid()
	_volume_value = _add_slider(grid, "Volume geral", 0, 100, int(round(GameConfig.audio_master_volume * 100.0)), _on_volume)


func _build_gameplay() -> void:
	add_child(MenuTheme.section_label("JOGABILIDADE"))
	var grid := _grid()
	_add_check(grid, "Mira pelo mouse", GameConfig.mouse_aim_enabled, _on_mouse_aim)
	_add_check(grid, "Primeira pessoa (FPS)", GameConfig.first_person_enabled, _on_first_person)


func _row_label(grid: GridContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 34.0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grid.add_child(label)


func _add_option(grid: GridContainer, text: String, labels: Array, selected_index: int, handler: Callable) -> OptionButton:
	_row_label(grid, text)
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(260.0, 34.0)
	for label in labels:
		option.add_item(String(label))
	option.select(clampi(selected_index, 0, maxi(labels.size() - 1, 0)))
	option.item_selected.connect(handler)
	grid.add_child(option)
	return option


func _add_check(grid: GridContainer, text: String, pressed: bool, handler: Callable) -> CheckButton:
	_row_label(grid, text)
	var check := CheckButton.new()
	check.button_pressed = pressed
	check.toggled.connect(handler)
	grid.add_child(check)
	return check


## Slider com o valor atual ao lado; handler recebe o valor inteiro.
func _add_slider(grid: GridContainer, text: String, minimum: int, maximum: int, value: int, handler: Callable) -> Label:
	_row_label(grid, text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 1
	slider.value = value
	slider.custom_minimum_size = Vector2(190.0, 34.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(56.0, 34.0)
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.text = "%d" % value
	slider.value_changed.connect(func(new_value: float) -> void:
		value_label.text = "%d" % int(round(new_value))
		handler.call(int(round(new_value)))
	)
	row.add_child(slider)
	row.add_child(value_label)
	grid.add_child(row)
	return value_label


func _resolution_labels() -> Array[String]:
	var labels: Array[String] = []
	for resolution in GameConfig.SUPPORTED_RESOLUTIONS:
		labels.append("%d x %d" % [resolution.x, resolution.y])
	return labels


func _resolution_index() -> int:
	return maxi(GameConfig.SUPPORTED_RESOLUTIONS.find(GameConfig.graphics_resolution), 0)


func _window_labels() -> Array[String]:
	return ["Janela", "Tela cheia", "Tela cheia exclusiva"]


func _quality_labels() -> Array[String]:
	var labels: Array[String] = []
	for quality in range(GameConfig.GraphicsQuality.size()):
		labels.append(GameConfig.quality_label(quality))
	return labels


func _render_scale_labels() -> Array[String]:
	var labels: Array[String] = []
	for scale in GameConfig.RENDER_SCALE_OPTIONS:
		labels.append(GameConfig.render_scale_label(scale))
	return labels


func _render_scale_index() -> int:
	return maxi(GameConfig.RENDER_SCALE_OPTIONS.find(GameConfig.graphics_render_scale), GameConfig.RENDER_SCALE_OPTIONS.size() - 1)


func _fps_labels() -> Array[String]:
	var labels: Array[String] = []
	for value in GameConfig.FPS_OPTIONS:
		labels.append(GameConfig.fps_label(value))
	return labels


func _fps_index() -> int:
	return maxi(GameConfig.FPS_OPTIONS.find(GameConfig.graphics_max_fps), 0)


func _apply(error: Error, message: String) -> void:
	var text := message if error == OK else "Falha ao salvar: %s" % error_string(error)
	if _status != null:
		_status.text = text
	changed.emit(text)


func _on_resolution(index: int) -> void:
	if index < 0 or index >= GameConfig.SUPPORTED_RESOLUTIONS.size():
		return
	_apply(GameConfig.set_resolution(GameConfig.SUPPORTED_RESOLUTIONS[index]), "Resolucao atualizada.")


func _on_window_mode(index: int) -> void:
	_apply(GameConfig.set_window_mode(index), "Modo de janela: %s." % GameConfig.window_mode_label(index))


func _on_quality(index: int) -> void:
	_apply(GameConfig.set_quality(index), "Qualidade: %s." % GameConfig.quality_label(index))


func _on_render_scale(index: int) -> void:
	if index < 0 or index >= GameConfig.RENDER_SCALE_OPTIONS.size():
		return
	var scale: float = GameConfig.RENDER_SCALE_OPTIONS[index]
	_apply(GameConfig.set_render_scale(scale), "Escala de render: %s." % GameConfig.render_scale_label(scale))


func _on_fps(index: int) -> void:
	if index < 0 or index >= GameConfig.FPS_OPTIONS.size():
		return
	var value: int = GameConfig.FPS_OPTIONS[index]
	_apply(GameConfig.set_max_fps(value), "Limite de FPS: %s." % GameConfig.fps_label(value))


func _on_shadows(pressed: bool) -> void:
	_apply(GameConfig.set_shadows(pressed), "Sombras %s." % ("ligadas" if pressed else "desligadas"))


func _on_fog(pressed: bool) -> void:
	_apply(GameConfig.set_fog(pressed), "Nevoa %s." % ("ligada" if pressed else "desligada"))


func _on_vsync(pressed: bool) -> void:
	_apply(GameConfig.set_vsync(pressed), "V-Sync %s." % ("ligado" if pressed else "desligado"))


func _on_fov(value: int) -> void:
	_apply(GameConfig.set_fov(value), "FOV: %d." % value)


func _on_volume(value: int) -> void:
	_apply(GameConfig.set_master_volume(float(value) / 100.0), "Volume: %d%%." % value)


func _on_mouse_aim(pressed: bool) -> void:
	_apply(GameConfig.set_mouse_aim(pressed), "Mira pelo mouse %s." % ("ligada" if pressed else "desligada"))
	_push_gameplay_to_players()


func _on_first_person(pressed: bool) -> void:
	_apply(GameConfig.set_first_person(pressed), "Primeira pessoa %s." % ("ligada" if pressed else "desligada"))
	_push_gameplay_to_players()


## Aplica mira/1a pessoa nos jogadores locais ja em partida (menu do Esc).
func _push_gameplay_to_players() -> void:
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group("player"):
		if node.get("is_local_controller") != true:
			continue
		node.set("mouse_aim", GameConfig.mouse_aim_enabled)
		node.call("set_first_person", GameConfig.first_person_enabled)
