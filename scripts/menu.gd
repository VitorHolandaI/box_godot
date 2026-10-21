# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
extends Control

## Menu principal. Fluxo: tela inicial (Sozinho/Multiplayer) -> modos (PvP,
## Escolta, Sobrevivencia) -> jogadores -> configuracao -> partida. A tela de
## configuracoes (MenuSettingsScreen) e o navegador de salas (MenuServerBrowser)
## sao componentes a parte.

const MODE_ORDER: Array[String] = ["pvp", "escort", "survival"]
const MODE_TITLES := {
	"pvp": "PVP",
	"escort": "ESCOLTA",
	"survival": "ZUMBI SOBREVIVENCIA",
}
const MODE_DESCRIPTIONS := {
	"pvp": "Mata-mata em equipes. Ate 4 jogadores locais contra 4 bots: quem fizer mais abates vence.",
	"escort": "Atravesse a cidade em serpentina e leve a familia ate a safehouse, segurando a horda em 3 paradas.",
	"survival": "Aguente ondas cada vez maiores de zumbis. Sobreviva o maximo que puder.",
}
const PANEL_SIZES := {
	"main": Vector2(760, 600),
	"modes": Vector2(780, 620),
	"multiplayer": Vector2(640, 500),
	"players": Vector2(640, 560),
	"browser": Vector2(880, 660),
	"setup": Vector2(1080, 680),
	"settings": Vector2(900, 680),
	"paint": Vector2(780, 640),
}
const HOST_JOIN_MAX_ATTEMPTS := 20
const HOST_JOIN_RETRY_SECONDS := 1.0

var selected_play := "single"
## local | server | host
var selected_mode := "local"
var selected_game_mode := "survival"

var _content: VBoxContainer
var _screens: Dictionary = {}
var _active := ""
var _setup: MenuPlayerSetup
var _browser: MenuServerBrowser
var _start_button: Button
var _message: Label
var _modes_subtitle: Label
var _players_subtitle: Label
var _host_join_attempts := 0
var _join_address := ""
var _join_port := -1
var _paint_pickers: Dictionary = {}


func _ready() -> void:
	GameConfig.menu_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if NetworkSession.bot_mode or NetworkSession.autoplay_bot or NetworkSession.is_server():
		return
	NetworkSession.local_host.stop()
	NetworkSession.join_accepted.connect(_on_join_accepted)
	NetworkSession.join_failed.connect(_on_join_failed)
	theme = MenuTheme.build_theme()
	_content = $MenuPanel/Margin/Content
	_build_screens()
	get_viewport().size_changed.connect(_layout_menu)
	_show("main")
	_layout_menu.call_deferred()


## --- montagem das telas ---

func _build_screens() -> void:
	_screens["main"] = _build_main()
	_screens["modes"] = _build_modes()
	_screens["multiplayer"] = _build_multiplayer()
	_screens["players"] = _build_players()
	_screens["browser"] = _build_browser()
	_screens["setup"] = _build_setup()
	_screens["settings"] = _build_settings()
	_screens["paint"] = _build_paint()
	for screen in _screens.values():
		_content.add_child(screen)
		(screen as Control).visible = false


func _screen(center: bool = true) -> VBoxContainer:
	var screen := VBoxContainer.new()
	screen.add_theme_constant_override("separation", 10)
	screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if center:
		screen.alignment = BoxContainer.ALIGNMENT_CENTER
	return screen


func _build_main() -> VBoxContainer:
	var screen := _screen()
	screen.add_child(MenuTheme.title_label("OPERACAO QUARENTENA"))
	screen.add_child(MenuTheme.muted_label("Sobreviva, lute e escolte pela cidade infestada."))
	screen.add_child(_spacer(18))
	screen.add_child(_big_button("JOGAR SOZINHO", _on_solo))
	screen.add_child(_big_button("MULTIPLAYER", _on_multiplayer))
	screen.add_child(_spacer(8))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	var paint := _button("APARENCIA", func() -> void: _show("paint"))
	paint.custom_minimum_size = Vector2(200.0, 46.0)
	var settings := _button("CONFIGURACOES", func() -> void: _show("settings"))
	settings.custom_minimum_size = Vector2(240.0, 46.0)
	var quit := _button("SAIR", _on_quit)
	MenuTheme.style_danger(quit)
	quit.custom_minimum_size = Vector2(150.0, 46.0)
	row.add_child(paint)
	row.add_child(settings)
	row.add_child(quit)
	screen.add_child(row)
	return screen


func _build_modes() -> VBoxContainer:
	var screen := _screen()
	screen.add_child(MenuTheme.title_label("ESCOLHA O MODO", 30))
	_modes_subtitle = MenuTheme.muted_label("")
	screen.add_child(_modes_subtitle)
	screen.add_child(_spacer(6))
	for game_mode in MODE_ORDER:
		screen.add_child(_mode_card(game_mode))
	screen.add_child(_spacer(6))
	screen.add_child(_back_button("VOLTAR", func() -> void: _show("main")))
	return screen


func _build_multiplayer() -> VBoxContainer:
	var screen := _screen()
	screen.add_child(MenuTheme.title_label("MULTIPLAYER", 30))
	screen.add_child(MenuTheme.muted_label("Entre numa sala existente ou hospede a sua."))
	screen.add_child(_spacer(14))
	screen.add_child(_big_button("ENTRAR EM SALA", func() -> void: _show("browser")))
	screen.add_child(_big_button("HOSPEDAR PARTIDA", func() -> void: _show_players("host")))
	screen.add_child(_spacer(6))
	screen.add_child(_back_button("VOLTAR", func() -> void: _show("modes")))
	return screen


func _build_players() -> VBoxContainer:
	var screen := _screen()
	screen.add_child(MenuTheme.title_label("QUANTOS JOGADORES?", 28))
	_players_subtitle = MenuTheme.muted_label("")
	screen.add_child(_players_subtitle)
	screen.add_child(_spacer(10))
	for count in range(1, 5):
		screen.add_child(_big_button("%d JOGADOR%s" % [count, "" if count == 1 else "ES"], _on_players_chosen.bind(count)))
	screen.add_child(_spacer(6))
	screen.add_child(_back_button("VOLTAR", func() -> void: _show("modes")))
	return screen


func _build_browser() -> VBoxContainer:
	var screen := _screen(false)
	screen.add_child(MenuTheme.title_label("ENTRAR EM SALA", 28))
	_browser = MenuServerBrowser.new()
	_browser.server_chosen.connect(_on_server_chosen)
	screen.add_child(_browser)
	screen.add_child(_back_button("VOLTAR", func() -> void: _show("multiplayer")))
	return screen


func _build_setup() -> VBoxContainer:
	var screen := _screen(false)
	_setup = MenuPlayerSetup.new()
	screen.add_child(_setup)
	_message = Label.new()
	_message.custom_minimum_size = Vector2(0.0, 26.0)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_color_override("font_color", MenuTheme.WARNING)
	screen.add_child(_message)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	var back := _button("VOLTAR", _on_setup_back)
	back.custom_minimum_size = Vector2(180.0, 48.0)
	_start_button = _button("INICIAR PARTIDA", _on_start_pressed)
	MenuTheme.style_primary(_start_button)
	_start_button.custom_minimum_size = Vector2(300.0, 48.0)
	actions.add_child(back)
	actions.add_child(_start_button)
	screen.add_child(actions)
	return screen


func _build_settings() -> VBoxContainer:
	var screen := _screen(false)
	screen.add_child(MenuTheme.title_label("CONFIGURACOES", 28))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var settings := MenuSettingsScreen.new()
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(settings)
	screen.add_child(scroll)
	screen.add_child(_back_button("VOLTAR", func() -> void: _show("main")))
	return screen


## Pintura do personagem (pele/camisa/calca/botas), salva no PC do jogador.
func _build_paint() -> VBoxContainer:
	var screen := _screen(false)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	screen.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)
	content.add_child(MenuTheme.title_label("APARENCIA", 30))
	content.add_child(MenuTheme.muted_label("Pinte o seu personagem. As cores ficam salvas neste PC."))
	PlayerPaint.load_config()
	content.add_child(MenuTheme.section_label("PRESETS"))
	var presets := HFlowContainer.new()
	presets.add_theme_constant_override("h_separation", 8)
	presets.add_theme_constant_override("v_separation", 8)
	content.add_child(presets)
	for index in PlayerPaint.PRESETS.size():
		var preset_button := _button(PlayerPaint.preset_name(index), _on_paint_preset.bind(index))
		preset_button.custom_minimum_size = Vector2(160.0, 38.0)
		presets.add_child(preset_button)
	content.add_child(MenuTheme.section_label("CORES"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 10)
	content.add_child(grid)
	_add_paint_row(grid, "Pele", "skin", PlayerPaint.skin)
	_add_paint_row(grid, "Camisa", "shirt", PlayerPaint.shirt)
	_add_paint_row(grid, "Calca", "pants", PlayerPaint.pants)
	_add_paint_row(grid, "Botas", "boots", PlayerPaint.boots)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	actions.add_child(_button("RESTAURAR PADRAO", _on_paint_reset))
	actions.add_child(_button("VOLTAR", func() -> void: _show("main")))
	screen.add_child(actions)
	return screen


func _add_paint_row(grid: GridContainer, text: String, key: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(160.0, 40.0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grid.add_child(label)
	var picker := ColorPickerButton.new()
	picker.color = color
	picker.edit_alpha = false
	picker.custom_minimum_size = Vector2(240.0, 40.0)
	picker.color_changed.connect(_on_paint_color.bind(key))
	grid.add_child(picker)
	_paint_pickers[key] = picker


func _on_paint_color(color: Color, key: String) -> void:
	match key:
		"skin":
			PlayerPaint.skin = color
		"shirt":
			PlayerPaint.shirt = color
		"pants":
			PlayerPaint.pants = color
		"boots":
			PlayerPaint.boots = color
	PlayerPaint.save_config()


func _on_paint_reset() -> void:
	PlayerPaint.reset_defaults()
	for key in _paint_pickers:
		(_paint_pickers[key] as ColorPickerButton).color = _paint_value(String(key))


func _on_paint_preset(index: int) -> void:
	PlayerPaint.apply_preset(index)
	for key in _paint_pickers:
		(_paint_pickers[key] as ColorPickerButton).color = _paint_value(String(key))


func _paint_value(key: String) -> Color:
	match key:
		"skin":
			return PlayerPaint.skin
		"shirt":
			return PlayerPaint.shirt
		"pants":
			return PlayerPaint.pants
		_:
			return PlayerPaint.boots


## --- widgets ---

func _button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 44.0)
	button.pressed.connect(handler)
	return button


func _big_button(text: String, handler: Callable) -> Button:
	var button := _button(text, handler)
	button.custom_minimum_size = Vector2(0.0, 52.0)
	button.add_theme_font_size_override("font_size", 20)
	return button


func _back_button(text: String, handler: Callable) -> Button:
	var button := _button(text, handler)
	button.custom_minimum_size = Vector2(220.0, 42.0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return button


func _spacer(height: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, float(height))
	return spacer


## Cartao clicavel de modo: titulo em acento e descricao em texto mudo.
func _mode_card(game_mode: String) -> Control:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel", MenuTheme.box(MenuTheme.ACCENT_DEEP, MenuTheme.ACCENT_DIM, 1, 8, 14, 18))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var title := Label.new()
	title.text = MODE_TITLES[game_mode]
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", MenuTheme.ACCENT)
	box.add_child(title)
	var desc := Label.new()
	desc.text = MODE_DESCRIPTIONS[game_mode]
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", MenuTheme.TEXT_MUTED)
	box.add_child(desc)
	wrap.add_child(box)
	var click := Button.new()
	click.flat = true
	click.focus_mode = Control.FOCUS_NONE
	click.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	click.pressed.connect(_on_mode_chosen.bind(game_mode))
	wrap.add_child(click)
	return wrap


## --- fluxo ---

func _show(screen_name: String) -> void:
	for name in _screens:
		(_screens[name] as Control).visible = name == screen_name
	_active = screen_name
	_layout_menu()


func _on_solo() -> void:
	selected_play = "single"
	selected_mode = "local"
	_modes_subtitle.text = "Escolha o modo para jogar sozinho."
	_show("modes")


func _on_multiplayer() -> void:
	selected_play = "multiplayer"
	_modes_subtitle.text = "Escolha o modo para hospedar; entrar em sala usa o modo do servidor."
	_show("modes")


func _on_mode_chosen(game_mode: String) -> void:
	selected_game_mode = game_mode
	if selected_play == "single":
		_show_players("local")
	else:
		_show("multiplayer")


func _show_players(mode: String) -> void:
	selected_mode = mode
	_players_subtitle.text = "Jogadores locais nesta maquina."
	_show("players")


func _on_players_chosen(count: int) -> void:
	_setup.configure(count)
	_start_button.text = "INICIAR PARTIDA" if selected_mode == "local" else "ENTRAR NA SALA"
	_start_button.disabled = false
	_message.text = "Confira os comandos e inicie a partida."
	_show("setup")


func _on_server_chosen(address: String, port: int) -> void:
	selected_mode = "server"
	_join_address = address
	_join_port = port
	_setup.configure(1)
	_start_button.text = "ENTRAR NA SALA"
	_start_button.disabled = false
	_message.text = "Conectando a %s:%d..." % [address, port]
	_show("setup")


func _on_setup_back() -> void:
	if selected_mode == "server":
		_show("browser")
	elif selected_mode == "host":
		_show("players")
	else:
		_show("players")


## --- inicio de partida ---

func _mode_server_arguments() -> PackedStringArray:
	if selected_game_mode == "pvp":
		return PackedStringArray(["--pvp", "--pvp-bots=4"])
	if selected_game_mode == "escort":
		return PackedStringArray(["--escort"])
	return PackedStringArray()


func _activate_local_mode() -> void:
	if selected_game_mode == "pvp":
		NetworkSession.activate_local_pvp_mode(4)
	elif selected_game_mode == "escort":
		NetworkSession.activate_local_escort_mode()
	else:
		NetworkSession.activate_local_survival_mode()


func _on_start_pressed() -> void:
	if _setup.is_capturing():
		_message.text = "Termine ou cancele o remapeamento atual."
		return
	GameConfig.configure_local_players(_setup.configs())
	if selected_mode == "local":
		NetworkSession.leave_session()
		_activate_local_mode()
		get_tree().change_scene_to_file("res://scenes/main.tscn")
		return
	if selected_mode == "host":
		_start_hosted_game()
		return
	_start_join()


func _start_join() -> void:
	_start_button.disabled = true
	_message.text = "Conectando ao servidor..."
	var error: Error = NetworkSession.join_server(_join_address.strip_edges(), _setup.configs().size(), _join_port)
	if error != OK:
		_start_button.disabled = false
		_message.text = "Endereco invalido ou falha ao iniciar conexao: %s" % error_string(error)


func _start_hosted_game() -> void:
	_start_button.disabled = true
	var error := NetworkSession.local_host.launch(NetworkSession.DEFAULT_PORT, _mode_server_arguments())
	if error != OK:
		_start_button.disabled = false
		_message.text = "Nao foi possivel iniciar o servidor local: %s" % error_string(error)
		return
	_host_join_attempts = 0
	_join_hosted_server()


func _join_hosted_server() -> void:
	_host_join_attempts += 1
	_message.text = "Subindo servidor local (tentativa %d de %d)..." % [_host_join_attempts, HOST_JOIN_MAX_ATTEMPTS]
	var error := NetworkSession.join_server(LocalHostLauncher.LOOPBACK_ADDRESS, _setup.configs().size(), NetworkSession.DEFAULT_PORT)
	if error != OK:
		_on_join_failed("Falha ao conectar no servidor local: %s" % error_string(error))


func _on_join_accepted() -> void:
	return


func _on_join_failed(error_message: String) -> void:
	if selected_mode == "host" and _host_join_attempts < HOST_JOIN_MAX_ATTEMPTS and NetworkSession.local_host.is_running():
		get_tree().create_timer(HOST_JOIN_RETRY_SECONDS).timeout.connect(_join_hosted_server)
		return
	if selected_mode == "host":
		NetworkSession.local_host.stop()
	_start_button.disabled = false
	_message.text = error_message


func _on_quit() -> void:
	get_tree().quit()


## --- layout ---

func _layout_menu() -> void:
	if not is_inside_tree():
		return
	var desired: Vector2 = PANEL_SIZES.get(_active, Vector2(760.0, 620.0))
	var available := get_viewport_rect().size - Vector2(48.0, 48.0)
	var panel_size := Vector2(minf(desired.x, available.x), minf(desired.y, available.y))
	var panel: PanelContainer = $MenuPanel
	panel.offset_left = -panel_size.x * 0.5
	panel.offset_top = -panel_size.y * 0.5
	panel.offset_right = panel_size.x * 0.5
	panel.offset_bottom = panel_size.y * 0.5
