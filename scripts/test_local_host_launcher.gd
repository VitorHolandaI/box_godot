# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
extends RefCounted

## Regressoes do "Hospedar partida": o menu sobe o servidor dedicado como
## processo filho e entra nele por 127.0.0.1.
## Uso: LocalHostLauncherTests.new().run(test_root)

const LOCAL_HOST_LAUNCHER_SCRIPT := preload("res://scripts/local_host_launcher.gd")


func run(test_root: Node) -> void:
	_test_exported_server_arguments(test_root)
	_test_editor_server_arguments(test_root)
	_test_idle_exit_argument(test_root)
	_test_idle_exit_clock(test_root)
	_test_lan_address_filter(test_root)
	_test_stop_without_server(test_root)


func _test_exported_server_arguments(test_root: Node) -> void:
	print("Testando argumentos do servidor hospedado no binario exportado...")
	var arguments: PackedStringArray = LOCAL_HOST_LAUNCHER_SCRIPT.build_server_arguments(27015, 42, false, "/projeto")
	var expected := PackedStringArray(["--headless", "--", "--server", "--server-port=27015", "--world-seed=42", "--server-name=Partida hospedada", "--host-idle-exit=60"])
	if arguments != expected:
		_fail(test_root, "Argumentos do servidor hospedado esperados %s; veio %s." % [expected, arguments])
		return
	print("PASS: Argumentos do servidor hospedado validados.")


func _test_editor_server_arguments(test_root: Node) -> void:
	print("Testando argumentos do servidor hospedado rodando pelo editor...")
	var arguments: PackedStringArray = LOCAL_HOST_LAUNCHER_SCRIPT.build_server_arguments(27020, 7, true, "/projeto")
	var separator := arguments.find("--")
	var path_index := arguments.find("--path")
	if path_index < 0 or path_index > separator or arguments[path_index + 1] != "/projeto" or not arguments.has("--server-port=27020"):
		_fail(test_root, "Pelo editor o servidor precisa de --path /projeto antes de '--'; veio %s." % arguments)
		return
	print("PASS: Argumentos pelo editor validados.")


func _test_idle_exit_argument(test_root: Node) -> void:
	print("Testando leitura de --host-idle-exit...")
	var seconds: float = LOCAL_HOST_LAUNCHER_SCRIPT.idle_exit_seconds_from_arguments(PackedStringArray(["--server", "--host-idle-exit=60"]))
	var absent: float = LOCAL_HOST_LAUNCHER_SCRIPT.idle_exit_seconds_from_arguments(PackedStringArray(["--server"]))
	var invalid: float = LOCAL_HOST_LAUNCHER_SCRIPT.idle_exit_seconds_from_arguments(PackedStringArray(["--host-idle-exit=abc"]))
	if not is_equal_approx(seconds, 60.0) or absent != 0.0 or invalid != 0.0:
		_fail(test_root, "--host-idle-exit=60 deveria dar 60 e ausente/invalido 0; veio %s/%s/%s." % [seconds, absent, invalid])
		return
	print("PASS: Argumento de saida ociosa validado.")


func _test_idle_exit_clock(test_root: Node) -> void:
	print("Testando relogio de saida do servidor hospedado sem jogadores...")
	var watch = LOCAL_HOST_LAUNCHER_SCRIPT.new()
	watch.idle_exit_seconds = 10.0
	var early: bool = watch.should_exit_idle(6.0, 0)
	var reset_by_player: bool = watch.should_exit_idle(6.0, 1)
	var still_waiting: bool = watch.should_exit_idle(6.0, 0)
	var expired: bool = watch.should_exit_idle(6.0, 0)
	var disabled = LOCAL_HOST_LAUNCHER_SCRIPT.new()
	if early or reset_by_player or still_waiting or not expired or disabled.should_exit_idle(999.0, 0):
		_fail(test_root, "Servidor hospedado deveria sair so apos 10 s seguidos sem peers; early=%s reset=%s waiting=%s expired=%s." % [early, reset_by_player, still_waiting, expired])
		return
	print("PASS: Relogio de saida ociosa validado.")


func _test_lan_address_filter(test_root: Node) -> void:
	print("Testando IPs da rede local mostrados para o host...")
	var addresses := PackedStringArray(["127.0.0.1", "0:0:0:0:0:0:0:1", "192.168.1.25", "169.254.3.4", "fe80:0:0:0:9f89:23c5:863b:2f4f", "10.0.0.14"])
	var lan: PackedStringArray = LOCAL_HOST_LAUNCHER_SCRIPT.filter_lan_ipv4(addresses)
	if lan != PackedStringArray(["192.168.1.25", "10.0.0.14"]):
		_fail(test_root, "IPs da LAN deveriam ser so IPv4 fora de loopback/link-local; veio %s." % lan)
		return
	print("PASS: IPs da rede local validados.")


func _test_stop_without_server(test_root: Node) -> void:
	print("Testando parar servidor hospedado que nunca subiu...")
	var launcher = LOCAL_HOST_LAUNCHER_SCRIPT.new()
	launcher.stop()
	if launcher.is_running() or launcher.server_pid != -1:
		_fail(test_root, "Launcher sem servidor deveria continuar parado com pid -1; veio pid=%d." % launcher.server_pid)
		return
	print("PASS: Parar sem servidor validado.")


func _fail(test_root: Node, message: String) -> void:
	push_error("FALHA: " + message)
	test_root.set_meta("unit_test_failed", true)
