class_name BuyMenu
extends CanvasLayer

## Menu de compra do mata-mata (tecla B por padrao): lista as armas de crate
## com preco, mostra o dinheiro e manda a compra para o servidor, que valida
## fase/base/dinheiro. Recusa aparece na propria linha de status.
## Uso:
##   var menu := BuyMenu.new()
##   add_child(menu)
##   menu.setup(player, Callable(self, "request_purchase_local"), Callable(self, "pvp_status_text"))

const PANEL_SIZE := Vector2(380.0, 460.0)
const ROW_HEIGHT := 30

var _panel: PanelContainer
var _money_label: Label
var _phase_label: Label
var _status_label: Label
var _banner: Label
var _rows: VBoxContainer
var _buttons: Dictionary = {}
var _player: Node = null
var _request_purchase: Callable = Callable()
var _status_provider: Callable = Callable()


## `request_purchase` recebe o tipo da arma; `status_provider` devolve a ultima
## mensagem de recusa (string vazia quando nao ha nada).
## Uso: menu.setup(jogador, pedir_compra, ler_status)
func setup(player: Node, request_purchase: Callable, status_provider: Callable) -> void:
	_player = player
	_request_purchase = request_purchase
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
	title.text = "COMPRAR ARMA"
	column.add_child(title)
	_money_label = Label.new()
	column.add_child(_money_label)
	_phase_label = Label.new()
	column.add_child(_phase_label)
	_rows = VBoxContainer.new()
	column.add_child(_rows)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status_label)
	var hint := Label.new()
	hint.text = "B fecha | compre dentro da sua base na fase de compra"
	column.add_child(hint)
	# Aviso de freezetime: fica na tela mesmo com o menu fechado, para o jogador
	# saber que pode comprar e que o movimento esta travado.
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
		_panel.visible = not _panel.visible
	if _panel.visible:
		refresh()
	_refresh_banner()


## Freezetime: contagem na tela enquanto a fase de compra estiver aberta.
func _refresh_banner() -> void:
	if _banner == null:
		return
	var scene := get_tree().current_scene
	var in_buy: bool = scene != null and bool(scene.get("pvp_buy_open"))
	_banner.visible = in_buy
	if not in_buy:
		return
	var seconds := int(ceil(float(scene.get("pvp_buy_seconds_left")))) if scene != null else 0
	_banner.text = "TEMPO DE COMPRA — %ds\nB para comprar na sua base" % maxi(seconds, 0)


## Recria as linhas quando o jogador aparece (setup pode vir antes do _ready).
func _build_rows() -> void:
	if _rows == null or _rows.get_child_count() > 0:
		return
	for kind in WeaponStats.purchasable_kinds():
		var button := Button.new()
		var price := WeaponStats.price_for(kind)
		button.text = "%s — $%d" % [WeaponStats.stats_for(kind).get("label", kind), price]
		button.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
		button.pressed.connect(_on_row_pressed.bind(kind))
		_rows.add_child(button)
		_buttons[kind] = button


## Atualiza dinheiro, fase e disponibilidade das linhas.
func refresh() -> void:
	if _rows == null:
		return
	_build_rows()
	var money := int(_player.get("pvp_money")) if is_instance_valid(_player) else 0
	_money_label.text = "Dinheiro: $%d" % money
	var open: bool = true
	if is_instance_valid(_player):
		var scene := get_tree().current_scene
		if scene != null and scene.get("pvp_mode"):
			open = bool(scene.get("pvp_buy_open"))
	_phase_label.text = "Fase de compra aberta" if open else "Fase de combate (compre no inicio da rodada)"
	for kind in _buttons:
		var button := _buttons[kind] as Button
		button.disabled = money < WeaponStats.price_for(int(kind))
	_status_label.text = ""
	if _status_provider.is_valid():
		_status_label.text = String(_status_provider.call())


func _on_row_pressed(kind: int) -> void:
	if _request_purchase.is_valid():
		_request_purchase.call(kind)
