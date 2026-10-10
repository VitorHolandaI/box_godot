# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name EscortShopMenu
extends CanvasLayer

## Loja da escolta: aberta com B perto de um EscortMerchant, lista as armas do
## catalogo com preco, mostra o saldo e compra (via EscortShop.purchase). A
## compra em si e delegada a um Callable do main, que decide offline/servidor.
## Uso:
##   var menu := EscortShopMenu.new()
##   add_child(menu)
##   menu.setup(player, Callable(self, "buy_escort_weapon"))

const PANEL_SIZE := Vector2(420.0, 540.0)
const ROW_HEIGHT := 30

var _panel: PanelContainer
var _money_label: Label
var _status_label: Label
var _rows: VBoxContainer
var _buttons: Dictionary = {}
var _player: Node = null
var _buy: Callable = Callable()


## `buy` recebe o tipo da arma e devolve a mensagem (vazia no sucesso).
## Uso: menu.setup(jogador, comprar_arma)
func setup(player: Node, buy: Callable) -> void:
	_player = player
	_buy = buy
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
	title.text = "MERCADOR — COMPRAR ARMA"
	column.add_child(title)
	_money_label = Label.new()
	column.add_child(_money_label)
	_rows = VBoxContainer.new()
	column.add_child(_rows)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(0.0, 40.0)
	column.add_child(_status_label)
	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "Chegue perto do mercador (dentro da casa do checkpoint) e aperte B. B fecha."
	column.add_child(hint)


func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		return
	var prefix := String(_player.get("input_action_prefix"))
	if Input.is_action_just_pressed(prefix + "buy"):
		if is_panel_open():
			set_panel_open(false)
		elif player_near_merchant():
			set_panel_open(true)
	if is_panel_open():
		refresh()


func is_panel_open() -> bool:
	return _panel != null and _panel.visible


## Abre/fecha soltando o cursor junto (mesma licao do LoadoutMenu).
func set_panel_open(open: bool) -> void:
	if _panel == null:
		return
	_panel.visible = open
	GameConfig.set_menu_open(get_tree(), open)
	if open:
		refresh()


## Ha mercador dentro do raio de compra do jogador? Uso: interno do _process.
func player_near_merchant() -> bool:
	if not is_instance_valid(_player):
		return false
	var tree := get_tree()
	if tree == null:
		return false
	var origin := (_player as Node3D).global_position
	for node in tree.get_nodes_in_group("escort_merchant"):
		var merchant := node as Node3D
		if merchant == null or not is_instance_valid(merchant):
			continue
		if origin.distance_to(merchant.global_position) <= EscortMerchant.SHOP_RADIUS:
			return true
	return false


func _build_rows() -> void:
	if _rows == null or _rows.get_child_count() > 0:
		return
	for kind in EscortShop.sellable_kinds():
		var button := Button.new()
		button.text = "%s — $%d" % [
			String(WeaponStats.stats_for(int(kind)).get("label", kind)),
			EscortShop.price_of(int(kind)),
		]
		button.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
		button.pressed.connect(_on_row_pressed.bind(int(kind)))
		_rows.add_child(button)
		_buttons[int(kind)] = button


func refresh() -> void:
	if _buttons.is_empty():
		_build_rows()
	var money := int(_player.get("money")) if is_instance_valid(_player) else 0
	_money_label.text = "Seu dinheiro: $%d" % money
	for kind in _buttons:
		var button := _buttons[kind] as Button
		button.disabled = EscortShop.price_of(int(kind)) > money


func _on_row_pressed(kind: int) -> void:
	if _buy.is_valid():
		var answer: Variant = _buy.call(kind)
		_status_label.text = String(answer) if answer != null else ""
	refresh()


## Mostra a resposta de uma compra de rede (o cliente compra por RPC, entao a
## mensagem chega depois). Uso: main._escort_shop_result.
func show_result(message: String) -> void:
	if _status_label != null:
		_status_label.text = message
	refresh()
