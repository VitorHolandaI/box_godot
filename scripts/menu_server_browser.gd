# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name MenuServerBrowser
extends VBoxContainer

## Lista de salas multiplayer: descobre na LAN, mostra ping/jogadores/missao e
## deixa salvar/editar/remover servidores. Emite server_chosen quando o jogador
## aperta ENTRAR numa sala. Uso: browser.server_chosen.connect(handler)

signal server_chosen(address: String, port: int)

const REFRESH_SECONDS := 5.0

var _list: VBoxContainer
var _message: Label
var _address_input: LineEdit
var _port_input: LineEdit
var _add_button: Button
var _refresh_elapsed := 0.0
var _editing_address := ""
var _editing_port := -1


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_build()
	NetworkSession.server_list_changed.connect(_render)
	_refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_elapsed += delta
	if _refresh_elapsed >= REFRESH_SECONDS:
		_refresh()
		_refresh_elapsed = 0.0


func _build() -> void:
	var header := HBoxContainer.new()
	header.add_child(MenuTheme.section_label("SALAS DISPONIVEIS"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var refresh := Button.new()
	refresh.text = "ATUALIZAR"
	refresh.custom_minimum_size = Vector2(140.0, 34.0)
	refresh.pressed.connect(_refresh)
	header.add_child(refresh)
	add_child(header)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 190.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)

	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 6)
	_address_input = LineEdit.new()
	_address_input.placeholder_text = "IP ou dominio"
	_address_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address_input.custom_minimum_size = Vector2(0.0, 34.0)
	add_row.add_child(_address_input)
	_port_input = LineEdit.new()
	_port_input.text = str(NetworkSession.DEFAULT_PORT)
	_port_input.custom_minimum_size = Vector2(90.0, 34.0)
	add_row.add_child(_port_input)
	_add_button = Button.new()
	_add_button.text = "SALVAR"
	_add_button.custom_minimum_size = Vector2(120.0, 34.0)
	_add_button.pressed.connect(_save)
	add_row.add_child(_add_button)
	add_child(add_row)

	_message = Label.new()
	_message.custom_minimum_size = Vector2(0.0, 28.0)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_color_override("font_color", MenuTheme.WARNING)
	add_child(_message)


func _refresh() -> void:
	_message.text = "Descobrindo servidores na rede local..."
	var error := NetworkSession.refresh_server_list()
	if error != OK:
		_message.text = "Falha ao consultar servidores: %s" % error_string(error)


func _save() -> void:
	var address := _address_input.text.strip_edges()
	var port := NetworkSession.parse_server_port_value(_port_input.text.strip_edges())
	var error := GameConfig.save_server(address, port)
	if error != OK:
		_message.text = "Servidor invalido. Informe IP e porta entre 1024 e 65535."
		return
	if not _editing_address.is_empty() and (_editing_address != address or _editing_port != port):
		GameConfig.remove_saved_server(_editing_address, _editing_port)
	_editing_address = ""
	_editing_port = -1
	_add_button.text = "SALVAR"
	_message.text = "Servidor salvo. Consultando status..."
	_refresh()


## As linhas saem e voltam a partir dos proprios botoes delas (entrar, editar,
## remover): fora da arvore agora, destruidas no fim do frame.
func _render() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var servers := NetworkSession.get_server_list()
	if servers.is_empty():
		var empty := MenuTheme.muted_label("Nenhuma sala encontrada. Adicione um IP abaixo.")
		_list.add_child(empty)
		return
	for server in servers:
		_list.add_child(_server_row(server))


func _server_row(server: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 40.0
	var status := "ONLINE" if bool(server.get("online", false)) else "SEM RESPOSTA"
	var ping := "%d ms" % int(server.get("ping_ms", -1)) if int(server.get("ping_ms", -1)) >= 0 else "--"
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = "%s | %s | %d/%d jogadores | ping %s\n%s" % [
		String(server.get("name", server.get("address", "Servidor"))),
		status,
		int(server.get("active_players", 0)),
		int(server.get("max_players", 4)),
		ping,
		String(server.get("mission", "Desconhecida")),
	]
	row.add_child(label)
	var join := Button.new()
	join.text = "ENTRAR"
	join.disabled = not bool(server.get("online", false)) or int(server.get("active_players", 0)) >= int(server.get("max_players", 4))
	join.pressed.connect(func() -> void: server_chosen.emit(String(server.get("address", "")), int(server.get("port", NetworkSession.DEFAULT_PORT))))
	row.add_child(join)
	if bool(server.get("saved", false)):
		var edit := Button.new()
		edit.text = "EDITAR"
		edit.pressed.connect(_edit.bind(server))
		row.add_child(edit)
		var remove := Button.new()
		remove.text = "REMOVER"
		remove.pressed.connect(_remove.bind(server))
		row.add_child(remove)
	return row


func _edit(server: Dictionary) -> void:
	_editing_address = String(server.get("address", ""))
	_editing_port = int(server.get("port", NetworkSession.DEFAULT_PORT))
	_address_input.text = _editing_address
	_port_input.text = str(_editing_port)
	_add_button.text = "ATUALIZAR"
	_message.text = "Edite o endereco ou a porta e confirme em ATUALIZAR."


func _remove(server: Dictionary) -> void:
	var address := String(server.get("address", ""))
	var port := int(server.get("port", NetworkSession.DEFAULT_PORT))
	var error := GameConfig.remove_saved_server(address, port)
	if error != OK:
		_message.text = "Nao foi possivel remover %s:%d: %s" % [address, port, error_string(error)]
		return
	if _editing_address == address and _editing_port == port:
		_editing_address = ""
		_editing_port = -1
		_add_button.text = "SALVAR"
	_message.text = "Servidor removido: %s:%d" % [address, port]
	_refresh()
