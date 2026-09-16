extends RefCounted

## Regressoes da sonda de custo por frame (micro travadas com a horda grande).
## Uso: FramePerfProbeTests.new().run(test_root)

const FRAME_PERF_PROBE_SCRIPT := preload("res://scripts/frame_perf_probe.gd")


func run(test_root: Node) -> void:
	_test_argument_parsing(test_root)
	_test_hitch_line_breaks_down_sections(test_root)
	_test_window_report_counts_budget_misses(test_root)


func _test_argument_parsing(test_root: Node) -> void:
	print("Testando leitura de --perf-probe...")
	var default_probe = FRAME_PERF_PROBE_SCRIPT.from_arguments(PackedStringArray(["--server"]))
	var off_probe = FRAME_PERF_PROBE_SCRIPT.from_arguments(PackedStringArray(["--perf-probe=off"]))
	if not default_probe.enabled or off_probe.enabled:
		_fail(test_root, "Sonda deveria ligar por padrao e desligar com --perf-probe=off; default=%s off=%s." % [default_probe.enabled, off_probe.enabled])
		return
	print("PASS: Argumento da sonda de frame validado.")


func _test_hitch_line_breaks_down_sections(test_root: Node) -> void:
	print("Testando linha de frame travado com quebra por secao...")
	var probe = FRAME_PERF_PROBE_SCRIPT.new()
	probe.record_section("zombie_ai", 12_000)
	probe.record_section("zombie_ai", 8_000)
	probe.record_section("flock", 5_000)
	probe.record_section("sub:zombie_move", 7_000)
	probe.record_physics_step()
	probe.record_physics_step()
	var lines: Array[Dictionary] = probe.finish_frame(40.0, 10_000, {"role": "server"})
	var hitch: Dictionary = lines[0] if lines.size() == 1 else {}
	var sections: Dictionary = hitch.get("sections_ms", {})
	var hitch_ok: bool = hitch.get("event", "") == "perf_hitch" and is_equal_approx(float(sections.get("zombie_ai", 0.0)), 20.0) and is_equal_approx(float(sections.get("flock", 0.0)), 5.0)
	var rest_ok: bool = is_equal_approx(float(hitch.get("unaccounted_ms", 0.0)), 15.0) and int(hitch.get("physics_steps", 0)) == 2 and hitch.get("role", "") == "server"
	if not hitch_ok or not rest_ok:
		_fail(test_root, "Linha de hitch esperada com zombie_ai=20 flock=5 resto=15 e 2 passos; veio %s." % [lines])
		return
	# Segundo hitch em menos de 1 s nao vira outra linha (evita inundar o log).
	var throttled: Array[Dictionary] = probe.finish_frame(50.0, 10_500, {})
	var after_cooldown: Array[Dictionary] = probe.finish_frame(50.0, 11_200, {})
	if not throttled.is_empty() or after_cooldown.size() != 1:
		_fail(test_root, "Hitch deveria respeitar 1 s de intervalo; throttled=%s depois=%s." % [throttled, after_cooldown])
		return
	print("PASS: Linha de frame travado validada.")


func _test_window_report_counts_budget_misses(test_root: Node) -> void:
	print("Testando relatorio periodico da sonda de frame...")
	var probe = FRAME_PERF_PROBE_SCRIPT.new()
	var report: Dictionary = {}
	for frame_index in 296:
		var frame_ms := 34.0 if frame_index >= 280 else 16.0
		probe.record_section("zombie_ai", 9_000 if frame_index == 5 else 2_000)
		if frame_index == 7:
			probe.record_physics_step()
			probe.record_physics_step()
		for line in probe.finish_frame(frame_ms, frame_index * 17, {"zombies": 200}):
			if line.get("event", "") == "perf_report":
				report = line
	var section: Dictionary = report.get("sections_ms", {}).get("zombie_ai", {})
	var frames_ok := int(report.get("frames", 0)) == 296 and int(report.get("frames_over_budget", 0)) == 16 and int(report.get("frames_over_33ms", 0)) == 16
	var physics_ok := int(report.get("multi_physics_frames", 0)) == 1 and int(report.get("physics_steps_max", 0)) == 2
	var section_ok := is_equal_approx(float(section.get("max", 0.0)), 9.0) and absf(float(section.get("avg", 0.0)) - 2.02) < 0.01
	if not frames_ok or not physics_ok or not section_ok or int(report.get("zombies", 0)) != 200 or is_equal_approx(float(report.get("frame_ms_max", 0.0)), 34.0) == false:
		_fail(test_root, "Relatorio esperado com 296 frames, 16 acima do orcamento, zombie_ai avg~2.02 max 9; veio %s." % report)
		return
	print("PASS: Relatorio periodico da sonda de frame validado.")


func _fail(test_root: Node, message: String) -> void:
	push_error("FALHA: " + message)
	test_root.set_meta("unit_test_failed", true)
