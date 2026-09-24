# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name LocalHostLauncher
extends RefCounted

## "Hospedar partida" do menu: sobe o MESMO servidor dedicado da VPS como
## processo filho headless e o jogo entra nele por 127.0.0.1. Servidor com
## jogador local no mesmo processo exigiria mexer em dezenas de checagens
## is_server() do main.gd; o processo separado reaproveita o caminho testado.
## Amigos entram pelo IP do host (porta UDP liberada no roteador).
##
## O filho nao consegue vigiar o pai (OS.is_process_running no Linux so vale
## para filhos), entao ele sai sozinho apos HOST_IDLE_EXIT_SECONDS sem peers:
## se o jogo do host cair, nao sobra servidor rodando para sempre.
## Uso:
##   var launcher := LocalHostLauncher.new()
##   if launcher.launch(27015) == OK: NetworkSession.join_server("127.0.0.1", 1, 27015)
##   launcher.stop()

const HOST_IDLE_EXIT_ARGUMENT := "--host-idle-exit="
const HOST_IDLE_EXIT_SECONDS := 60
const HOSTED_SERVER_NAME := "Partida hospedada"
const LOOPBACK_ADDRESS := "127.0.0.1"

var server_pid := -1
## Servidor filho: segundos sem nenhum peer antes de encerrar (0 = nunca).
var idle_exit_seconds := 0.0
var _idle_elapsed := 0.0


## Argumentos do processo servidor. Pelo editor o executavel e o proprio Godot
## e precisa de --path para achar o projeto; no binario exportado nao.
## Uso: LocalHostLauncher.build_server_arguments(27015, 42, OS.has_feature("editor"), ProjectSettings.globalize_path("res://"))
static func build_server_arguments(port: int, world_seed: int, running_from_editor: bool, project_path: String) -> PackedStringArray:
	var arguments := PackedStringArray(["--headless"])
	if running_from_editor:
		arguments.append_array(["--path", project_path])
	arguments.append_array([
		"--",
		"--server",
		"--server-port=%d" % port,
		"--world-seed=%d" % world_seed,
		"--server-name=%s" % HOSTED_SERVER_NAME,
		"%s%d" % [HOST_IDLE_EXIT_ARGUMENT, HOST_IDLE_EXIT_SECONDS],
	])
	return arguments


## Uso: LocalHostLauncher.idle_exit_seconds_from_arguments(OS.get_cmdline_user_args())
static func idle_exit_seconds_from_arguments(arguments: PackedStringArray) -> float:
	for argument in arguments:
		if not argument.begins_with(HOST_IDLE_EXIT_ARGUMENT):
			continue
		var raw_value := argument.trim_prefix(HOST_IDLE_EXIT_ARGUMENT)
		if not raw_value.is_valid_float() or float(raw_value) <= 0.0:
			push_error("Valor invalido para %s'%s'; esperado numero de segundos > 0." % [HOST_IDLE_EXIT_ARGUMENT, raw_value])
			return 0.0
		return float(raw_value)
	return 0.0


## IPv4 que amigos na mesma rede podem usar (sem loopback nem link-local).
## Uso: LocalHostLauncher.filter_lan_ipv4(IP.get_local_addresses())
static func filter_lan_ipv4(addresses: PackedStringArray) -> PackedStringArray:
	var lan := PackedStringArray()
	for address in addresses:
		if not address.is_valid_ip_address() or address.contains(":"):
			continue
		if address.begins_with("127.") or address.begins_with("169.254."):
			continue
		lan.append(address)
	return lan


## Sobe o servidor filho; ERR_CANT_CREATE se o SO recusar o processo.
## Uso: var error := launcher.launch(27015)
func launch(port: int) -> Error:
	stop()
	var arguments := build_server_arguments(port, randi(), OS.has_feature("editor"), ProjectSettings.globalize_path("res://"))
	var pid := OS.create_process(OS.get_executable_path(), arguments)
	if pid <= 0:
		push_error("Nao foi possivel iniciar o servidor hospedado: executavel=%s argumentos=%s pid=%d." % [OS.get_executable_path(), arguments, pid])
		return ERR_CANT_CREATE
	server_pid = pid
	print(JSON.stringify({"event": "hosted_server_started", "pid": pid, "port": port}))
	return OK


func is_running() -> bool:
	return server_pid > 0 and OS.is_process_running(server_pid)


## Encerra o servidor filho (menu, saida do jogo); sem servidor nao faz nada.
## Uso: launcher.stop()
func stop() -> void:
	if server_pid <= 0:
		return
	if OS.is_process_running(server_pid):
		var error := OS.kill(server_pid)
		if error != OK:
			push_error("Falha ao encerrar servidor hospedado pid=%d: %s." % [server_pid, error_string(error)])
	server_pid = -1


## Lado do servidor filho: true quando ficou idle_exit_seconds seguidos sem peers.
## Uso: if watch.should_exit_idle(delta, multiplayer.get_peers().size()): get_tree().quit()
func should_exit_idle(delta: float, peer_count: int) -> bool:
	if idle_exit_seconds <= 0.0:
		return false
	if peer_count > 0:
		_idle_elapsed = 0.0
		return false
	_idle_elapsed += delta
	return _idle_elapsed >= idle_exit_seconds
