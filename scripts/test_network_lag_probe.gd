extends RefCounted

## Regressoes da sonda de lag usada contra servidores remotos.
## Uso: NetworkLagProbeTests.new().run(test_root)

const LAG_PROBE_SCRIPT := preload("res://scripts/network_lag_probe.gd")


func run(test_root: Node) -> void:
	_test_argument_parsing(test_root)
	_test_snapshot_intervals(test_root)


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


func _fail(test_root: Node, message: String) -> void:
	test_root.set_meta("unit_test_failed", true)
	push_error("FALHA: " + message)
