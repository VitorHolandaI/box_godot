extends RefCounted

## Regressoes da sonda de lag usada contra servidores remotos.
## Uso: NetworkLagProbeTests.new().run(test_root)

const LAG_PROBE_SCRIPT := preload("res://scripts/network_lag_probe.gd")


func run(test_root: Node) -> void:
	_test_argument_parsing(test_root)
	_test_snapshot_intervals(test_root)
	_test_received_traffic_rate(test_root)
	_test_prespawn_option(test_root)


func _test_argument_parsing(test_root: Node) -> void:
	print("Testando leitura de --lag-probe...")
	var enabled = LAG_PROBE_SCRIPT.from_arguments(PackedStringArray(["--bot-player=1.2.3.4", "--lag-probe=12.5"]))
	var disabled = LAG_PROBE_SCRIPT.from_arguments(PackedStringArray(["--lag-probe=abc"]))
	if not enabled.is_enabled() or not is_equal_approx(enabled.duration_seconds, 12.5) or disabled.is_enabled():
		_fail(test_root, "--lag-probe=12.5 deveria ativar por 12.5 s e valor invalido deveria desativar.")
		return
	print("PASS: Argumento da sonda de lag validado.")


func _test_snapshot_intervals(test_root: Node) -> void:
	print("Testando intervalos entre snapshots completos...")
	var probe = LAG_PROBE_SCRIPT.new()
	probe.duration_seconds = 1.0
	# Snapshot 0 chega em dois pacotes; o 1 chega 100 ms depois; o 2 atrasa 400 ms.
	probe.record_zombie_packet(0, 0, 2, 4, 1_000_000)
	probe.record_zombie_packet(0, 1, 2, 3, 1_010_000)
	probe.record_zombie_packet(1, 0, 1, 7, 1_110_000)
	probe.record_zombie_packet(1, 0, 1, 7, 1_120_000)
	probe.record_zombie_packet(2, 0, 1, 7, 1_510_000)
	var finished: bool = probe.tick(1.0, 80.0)
	var report: Dictionary = probe.build_report()
	var intervals_ok := is_equal_approx(float(report["snapshot_interval_ms_max"]), 400.0) and int(report["late_snapshots"]) == 1
	if not finished or not intervals_ok or int(report["zombies_last"]) != 7 or not is_equal_approx(float(report["rtt_ms_avg"]), 80.0):
		_fail(test_root, "Relatorio da sonda inesperado: %s." % report)
		return
	print("PASS: Sonda mede snapshots atrasados e RTT.")


func _test_received_traffic_rate(test_root: Node) -> void:
	print("Testando taxa de trafego recebido da sonda...")
	var probe = LAG_PROBE_SCRIPT.new()
	probe.duration_seconds = 10.0
	probe.tick(2.0, 50.0)
	probe.record_received_traffic(999999, 999)
	probe.tick(2.0, 50.0)
	probe.tick(1.5, 50.0)
	probe.record_received_traffic(1024 * 100, 50)
	var report: Dictionary = probe.build_report()
	# Aquecimento de 3 s: o trafego gravado aos 2 s e ignorado; mede 100 KB e 50 pacotes em 2.5 s.
	if not is_equal_approx(float(report["received_kbps"]), 40.0) or int(report["received_packets_per_second"]) != 20:
		_fail(test_root, "Taxa esperada 40 KB/s e 20 pacotes/s; relatorio=%s." % report)
		return
	print("PASS: Sonda mede KB/s e pacotes/s recebidos.")


func _test_prespawn_option(test_root: Node) -> void:
	print("Testando opcao --prespawn-zombies...")
	var valid := LoadTestOptions.prespawn_zombie_count(PackedStringArray(["--server", "--prespawn-zombies=600"]))
	var invalid := LoadTestOptions.prespawn_zombie_count(PackedStringArray(["--prespawn-zombies=-5"]))
	var absent := LoadTestOptions.prespawn_zombie_count(PackedStringArray(["--server"]))
	if valid != 600 or invalid != 0 or absent != 0:
		_fail(test_root, "Prespawn esperado 600/0/0; veio %d/%d/%d." % [valid, invalid, absent])
		return
	print("PASS: Opcao de prespawn validada.")


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
