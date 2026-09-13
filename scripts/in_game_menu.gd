extends Control

@onready var title: Label = $MenuPanel/Content/Title
@onready var status: Label = $MenuPanel/Content/Status

var is_open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if is_open:
		close_menu()
	else:
		open_menu()
	get_viewport().set_input_as_handled()


func open_menu() -> void:
	is_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if NetworkSession.is_offline():
		title.text = "JOGO PAUSADO"
		status.text = "A partida local esta parada."
		get_tree().paused = true
	else:
		title.text = "MENU DA PARTIDA"
		status.text = "A partida online continua acontecendo."


func close_menu() -> void:
	get_tree().paused = false
	is_open = false
	visible = false


func _on_continue_pressed() -> void:
	close_menu()


func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	NetworkSession.leave_session()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _on_quit_pressed() -> void:
	get_tree().paused = false
	NetworkSession.leave_session()
	get_tree().quit()
