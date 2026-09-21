class_name KeybindingEditor
extends RefCounted

## Troca de teclas compartilhada pelo menu principal e pelo menu do Esc na
## partida: rotulo de cada acao, captura do evento conforme o dispositivo do
## jogador (teclado/mouse ou o controle dele) e texto do botao.
## Uso:
##   if KeybindingEditor.is_cancel(event, config): cancelar()
##   var novo := KeybindingEditor.capture_event(event, config)

## Ordem de exibicao; cada acao de GameConfig.ACTIONS precisa de um rotulo.
const ACTION_LABELS := [
	["up", "Mover para cima"],
	["down", "Mover para baixo"],
	["left", "Mover para esquerda"],
	["right", "Mover para direita"],
	["jump", "Pular"],
	["sprint", "Correr"],
	["attack", "Atirar / atacar"],
	["knife", "Equipar faca"],
	["pistol", "Equipar pistola"],
	["reload", "Recarregar"],
	["interact", "Interagir / pegar arma"],
	["sonar", "Sonar"],
	["shotgun", "Equipar escopeta"],
	["uzi", "Equipar Uzi"],
	["magnum", "Equipar magnum"],
	["double_barrel", "Equipar escopeta dupla"],
	["carbine", "Equipar carabina"],
	["cycle_weapon", "Trocar de arma (ciclo)"],
	["drop_weapon", "Dropar arma da mao"],
	["grenade", "Arremessar granada"],
	["throw_knife", "Arremessar faca"],
	["air_strike", "Chamar ataque aereo"],
	["swat", "Chamar SWAT"],
	["buy", "Escolher arma (mata-mata)"],
	["view", "Primeira pessoa / 3a pessoa"],
]


## Esc no teclado cancela a captura em andamento.
## Uso: if KeybindingEditor.is_cancel(event, config): cancelar()
static func is_cancel(event: InputEvent, config: Dictionary) -> bool:
	return String(config.get("device_type", "keyboard")) == "keyboard" and event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE


## Evento limpo para guardar como binding, ou null quando o evento nao serve
## (tecla solta, Esc, controle de outro jogador, tecla num jogador de controle).
## Uso: var novo := KeybindingEditor.capture_event(event, config)
static func capture_event(event: InputEvent, config: Dictionary) -> InputEvent:
	if String(config.get("device_type", "keyboard")) == "keyboard":
		if event is InputEventKey and event.pressed and not event.echo:
			if is_cancel(event, config):
				return null
			var key_event := InputEventKey.new()
			var source := event as InputEventKey
			key_event.physical_keycode = source.physical_keycode if source.physical_keycode != 0 else source.keycode
			return key_event
		if event is InputEventMouseButton and event.pressed:
			var mouse_event := InputEventMouseButton.new()
			mouse_event.button_index = (event as InputEventMouseButton).button_index
			return mouse_event
		return null
	if event is InputEventJoypadButton and event.pressed and event.device == int(config.get("device_id", -1)):
		var joy_event := InputEventJoypadButton.new()
		joy_event.device = event.device
		joy_event.button_index = (event as InputEventJoypadButton).button_index
		return joy_event
	return null


## Movimento no controle usa o analogico e nao e remapeavel.
static func uses_analog(config: Dictionary, action: String) -> bool:
	return String(config.get("device_type", "keyboard")) == "gamepad" and action in ["up", "down", "left", "right"]


## Texto do botao da acao para o jogador.
## Uso: botao.text = KeybindingEditor.binding_text(config, "grenade")
static func binding_text(config: Dictionary, action: String) -> String:
	if uses_analog(config, action):
		return "Analogico esquerdo"
	var binding := (config.get("bindings", {}) as Dictionary).get(action) as InputEvent
	return event_text(binding)


## Nome curto da tecla ("W", nao "W - Physical").
## Uso: botao.text = KeybindingEditor.event_text(evento)
static func event_text(binding: InputEvent) -> String:
	if binding == null:
		return "Nao definido"
	if binding is InputEventKey:
		var key := binding as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
		return OS.get_keycode_string(code)
	return binding.as_text()
