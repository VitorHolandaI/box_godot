# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name LoadoutMenu
extends CanvasLayer

## Menu de arma do mata-mata (tecla B por padrao): lista TODO o arsenal de
## crate, de graca, e manda a escolha para o servidor. Substituiu o menu de
## compra: o mata-mata nao tem mais economia nem fase de compra (ver TdmMatch),
## entao nao ha preco, dinheiro nem freezetime aqui.
##
## A troca vale na hora quando o jogador esta na propria base; fora dela ela
## entra na proxima vida — quem decide e o servidor
## (PvpServerDirector.choose_loadout), e a resposta aparece na linha de status.
## Uso:
##   var menu := LoadoutMenu.new()
##   add_child(menu)
##   menu.setup(player, Callable(self, "choose_loadout_local"), Callable(self, "pvp_status_text"))

const PANEL_SIZE := Vector2(380.0, 520.0)
const ROW_HEIGHT := 26

var _panel: PanelContainer
var _team_label: Label
var _score_label: Label
var _status_label: Label
var _banner: Label
var _rows: VBoxContainer
var _buttons: Dictionary = {}
var _player: Node = null
var _choose_loadout: Callable = Callable()
var _status_provider: Callable = Callable()


## `choose_loadout` recebe o tipo da arma; `status_provider` devolve a ultima
## resposta do servidor (string vazia quando nao ha nada).
## Uso: menu.setup(jogador, escolher_arma, ler_status)
func setup(player: Node, choose_loadout: Callable, status_provider: Callable) -> void:
	_player = player
	_choose_loadout = choose_loadout
	_status_provider = status_provider
	_build_rows()
	refresh()


func _ready() -> void:
	layer = 8
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.custom_minimum_size = PANEL_SIZE
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.position = Vector2(-PANEL_SIZE.x * 0.5, -PANEL_SIZE.y * 0.5)
	add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var title := Label.new()
	title.text = "ESCOLHER ARMA"
	column.add_child(title)
	_team_label = Label.new()
	column.add_child(_team_label)
	_score_label = Label.new()
	column.add_child(_score_label)
	_rows = VBoxContainer.new()
	column.add_child(_rows)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status_label)
	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "B fecha | na sua base a troca vale na hora, fora dela vale no proximo respawn"
	column.add_child(hint)
	# Aviso de invulnerabilidade: fica na tela mesmo com o menu fechado, para o
	# jogador saber que esta protegido e que o primeiro tiro cancela.
	_banner = Label.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.position = Vector2(-220.0, 60.0)
	_banner.custom_minimum_size = Vector2(440.0, 0.0)
	_banner.add_theme_font_size_override("font_size", 22)
	_banner.visible = false
	add_child(_banner)


func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		return
	if Input.is_action_just_pressed(String(_player.get("input_action_prefix")) + "buy"):
		set_panel_open(not is_panel_open())
	if is_panel_open():
		refresh()
	_refresh_banner()


func is_panel_open() -> bool:
	return _panel != null and _panel.visible


## Abre/fecha o painel SOLTANDO o cursor junto. Em primeira pessoa o mouse fica
## preso (PlayerCharacter._apply_mouse_capture): antes o painel so alternava a
## visibilidade, entao o jogador ficava sem cursor para clicar na arma e o
## mouse-look seguia girando o boneco enquanto ele tentava escolher.
## Uso: menu.set_panel_open(true)
func set_panel_open(open: bool) -> void:
	if _panel == null:
		return
	_panel.visible = open
	GameConfig.set_menu_open(get_tree(), open)
	if open:
		refresh()


## Invulnerabilidade de respawn: contagem na tela enquanto durar.
func _refresh_banner() -> void:
	if _banner == null or not is_instance_valid(_player):
		return
	var protection := float(_player.get("spawn_protection_left"))
	_banner.visible = protection > 0.0
	if not _banner.visible:
		return
	_banner.text = "PROTEGIDO — %ds\nO primeiro tiro cancela a protecao" % maxi(int(ceil(protection)), 0)


## Recria as linhas quando o jogador aparece (setup pode vir antes do _ready).
func _build_rows() -> void:
	if _rows == null or _rows.get_child_count() > 0:
		return
	for kind in WeaponStats.loadout_kinds():
		var button := Button.new()
		button.text = String(WeaponStats.stats_for(kind).get("label", kind))
		button.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
		button.pressed.connect(_on_row_pressed.bind(kind))
		_rows.add_child(button)
		_buttons[kind] = button


## Atualiza time, placar e qual arma esta escolhida.
func refresh() -> void:
	if _rows == null:
		return
	_build_rows()
	var team := int(_player.get("pvp_team")) if is_instance_valid(_player) else -1
	var chosen := int(_player.get("pvp_loadout_kind")) if is_instance_valid(_player) else 0
	_team_label.text = "Seu time: %s" % TdmMatch.name_for_team(team)
	_team_label.add_theme_color_override("font_color", TdmMatch.color_for_team(team))
	# `get()` devolve null quando a cena atual nao tem a propriedade (cena de
	# teste, lab, menu): String(null) estoura em vez de virar texto vazio.
	var state_text: Variant = scene_pvp_state_text(get_tree().current_scene)
	_score_label.text = state_text
	for kind in _buttons:
		var button := _buttons[kind] as Button
		button.text = "%s%s" % [WeaponStats.stats_for(int(kind)).get("label", kind), "  (equipada)" if int(kind) == chosen else ""]
	_status_label.text = ""
	if _status_provider.is_valid():
		var answer: Variant = _status_provider.call()
		_status_label.text = String(answer) if answer != null else ""


## Placar do mata-mata publicado pela cena de jogo, ou vazio quando a cena atual
## nao tem esse estado (cena de teste, lab, menu). Uso: interno do refresh.
static func scene_pvp_state_text(scene: Node) -> String:
	if scene == null:
		return ""
	var state: Variant = scene.get("pvp_state_text")
	return String(state) if state != null else ""


func _on_row_pressed(kind: int) -> void:
	if _choose_loadout.is_valid():
		_choose_loadout.call(kind)
