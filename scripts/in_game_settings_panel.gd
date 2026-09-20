class_name InGameSettingsPanel
extends PanelContainer

## Configuracoes abertas pelo Esc durante a partida: graficos (resolucao,
## qualidade, tela cheia) e troca de teclas de cada jogador local, valendo na
## hora. Esc durante a captura cancela so a captura.
## Uso:
##   var painel := InGameSettingsPanel.new()
##   painel.closed.connect(voltar_ao_menu)
##   add_child(painel)

signal closed

const PANEL_SIZE := Vector2(820.0, 620.0)
const TITLE_COLOR := Color(0.72, 0.83, 0.59)

var _capture_slot := -1
var _capture_action := ""
var _capture_button: Button = null
var _message: Label
var _resolution: OptionButton
var _quality: OptionButton
var _fullscreen: CheckButton
var _mouse_aim: CheckButton
var _first_person: CheckButton
var _button_styles: Dictionary = {}


## Mesmo visual do menu da partida (moldura e botoes); chamar antes do add_child.
## Uso: painel.apply_styles($MenuPanel.get_theme_stylebox("panel"), {"normal": estilo, "hover": estilo})
func apply_styles(panel_style: StyleBox, button_styles: Dictionary) -> void:
	add_theme_stylebox_override("panel", panel_style)
	_button_styles = button_styles


func _ready() -> void:
	name = "InGameSettingsPanel"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_CENTER)
	_build()
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)


func is_capturing() -> bool:
	return _capture_slot >= 0


func _input(event: InputEvent) -> void:
	if not visible or not is_capturing():
		return
	var config: Dictionary = GameConfig.player_input_configs[_capture_slot]
	if KeybindingEditor.is_cancel(event, config):
		_end_capture("Troca de tecla cancelada.")
		get_viewport().set_input_as_handled()
		return
	var captured := KeybindingEditor.capture_event(event, config)
	if captured == null:
		return
	GameConfig.set_player_binding(_capture_slot, _capture_action, captured)
	_end_capture("Tecla de %s atualizada." % _capture_action)
	get_viewport().set_input_as_handled()


## Recria os botoes (jogadores podem ter mudado desde a ultima abertura).
## Uso: painel.refresh()
func refresh() -> void:
	for child in get_children():
		child.free()
	_build()


func _fit_to_viewport() -> void:
	var available := get_viewport_rect().size - Vector2(32.0, 32.0)
	var panel_size := Vector2(minf(PANEL_SIZE.x, available.x), minf(PANEL_SIZE.y, available.y))
	offset_left = -panel_size.x * 0.5
	offset_top = -panel_size.y * 0.5
	offset_right = panel_size.x * 0.5
	offset_bottom = panel_size.y * 0.5


func _build() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	root.add_child(_title_label("CONFIGURACOES", 26))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	_build_graphics(content)
	_build_gameplay(content)
	for slot in GameConfig.player_input_configs.size():
		_build_player_bindings(content, slot)
	_message = Label.new()
	_message.text = "Clique numa acao e aperte a tecla ou botao novo."
	root.add_child(_message)
	var back := Button.new()
	back.name = "Back"
	back.text = "VOLTAR"
	back.custom_minimum_size = Vector2(0.0, 46.0)
	back.pressed.connect(func() -> void: closed.emit())
	root.add_child(back)
	_style_buttons(self)


func _style_buttons(node: Node) -> void:
	for button in node.find_children("*", "Button", true, false):
		if button is OptionButton or button is CheckButton:
			continue
		for state in _button_styles:
			(button as Button).add_theme_stylebox_override(String(state), _button_styles[state])


func _build_graphics(content: VBoxContainer) -> void:
	content.add_child(_title_label("GRAFICOS", 20))
	var grid := GridContainer.new()
	grid.columns = 2
	content.add_child(grid)
	_resolution = OptionButton.new()
	_resolution.name = "Resolution"
	for resolution in GameConfig.SUPPORTED_RESOLUTIONS:
		_resolution.add_item("%d x %d" % [resolution.x, resolution.y])
		if resolution == GameConfig.graphics_resolution:
			_resolution.select(_resolution.item_count - 1)
	_quality = OptionButton.new()
	_quality.name = "Quality"
	for label in ["Baixo", "Medio", "Alto"]:
		_quality.add_item(label)
	_quality.select(int(GameConfig.graphics_quality))
	_fullscreen = CheckButton.new()
	_fullscreen.name = "Fullscreen"
	_fullscreen.button_pressed = GameConfig.graphics_fullscreen
	for pair in [["Resolucao", _resolution], ["Qualidade", _quality], ["Tela cheia", _fullscreen]]:
		var label := Label.new()
		label.text = pair[0]
		label.custom_minimum_size = Vector2(200.0, 32.0)
		grid.add_child(label)
		grid.add_child(pair[1])
	var apply := Button.new()
	apply.name = "ApplyGraphics"
	apply.text = "APLICAR GRAFICOS"
	apply.pressed.connect(_apply_graphics)
	content.add_child(apply)


## Jogabilidade: mira pelo cursor e primeira pessoa. Aplicam na hora nos
## jogadores locais e ficam salvos em settings.cfg.
func _build_gameplay(content: VBoxContainer) -> void:
	content.add_child(_title_label("JOGABILIDADE", 20))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	content.add_child(grid)
	_mouse_aim = CheckButton.new()
	_mouse_aim.name = "MouseAim"
	_mouse_aim.button_pressed = GameConfig.mouse_aim_enabled
	_first_person = CheckButton.new()
	_first_person.name = "FirstPerson"
	_first_person.button_pressed = GameConfig.first_person_enabled
	for pair in [["Mira pelo mouse", _mouse_aim], ["Primeira pessoa (FPS)", _first_person]]:
		var label := Label.new()
		label.text = pair[0]
		label.custom_minimum_size = Vector2(200.0, 32.0)
		grid.add_child(label)
		grid.add_child(pair[1])
	_mouse_aim.toggled.connect(_apply_gameplay)
	_first_person.toggled.connect(_apply_gameplay)


## Salva e aplica mira/FPS na hora nos jogadores locais. Uso: toggled dos check.
func _apply_gameplay(_pressed: bool = false) -> void:
	GameConfig.set_mouse_aim(_mouse_aim.button_pressed)
	GameConfig.set_first_person(_first_person.button_pressed)
	for node in get_tree().get_nodes_in_group("player"):
		if node.get("is_local_controller") != true:
			continue
		node.set("mouse_aim", _mouse_aim.button_pressed)
		node.call("set_first_person", _first_person.button_pressed)
	if _message != null:
		_message.text = "Mira e camera atualizadas."


func _build_player_bindings(content: VBoxContainer, slot: int) -> void:
	var config: Dictionary = GameConfig.player_input_configs[slot]
	content.add_child(_title_label("CONTROLES DO JOGADOR %d (%s)" % [slot + 1, String(config.get("device_name", "Teclado"))], 20))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	content.add_child(grid)
	for action_data in KeybindingEditor.ACTION_LABELS:
		var action: String = action_data[0]
		var label := Label.new()
		label.text = action_data[1]
		label.custom_minimum_size = Vector2(200.0, 30.0)
		grid.add_child(label)
		var button := Button.new()
		button.name = "Bind_%d_%s" % [slot, action]
		button.custom_minimum_size = Vector2(180.0, 30.0)
		button.text = KeybindingEditor.binding_text(config, action)
		button.disabled = KeybindingEditor.uses_analog(config, action)
		button.pressed.connect(_begin_capture.bind(slot, action, button))
		grid.add_child(button)


func _begin_capture(slot: int, action: String, button: Button) -> void:
	if is_capturing():
		_end_capture("")
	_capture_slot = slot
	_capture_action = action
	_capture_button = button
	button.text = "Aperte agora..."
	_message.text = "Esc cancela a troca."


func _end_capture(text: String) -> void:
	if _capture_button != null and _capture_slot >= 0:
		_capture_button.text = KeybindingEditor.binding_text(GameConfig.player_input_configs[_capture_slot], _capture_action)
	_capture_slot = -1
	_capture_action = ""
	_capture_button = null
	if _message != null and not text.is_empty():
		_message.text = text


func _apply_graphics() -> void:
	var index := _resolution.selected
	if index < 0 or index >= GameConfig.SUPPORTED_RESOLUTIONS.size():
		_message.text = "Resolucao selecionada invalida."
		return
	var error := GameConfig.apply_graphics_settings(GameConfig.SUPPORTED_RESOLUTIONS[index], _quality.selected, _fullscreen.button_pressed)
	_message.text = "Graficos aplicados e salvos." if error == OK else "Falha ao salvar graficos: %s" % error_string(error)


func _title_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TITLE_COLOR)
	return label
