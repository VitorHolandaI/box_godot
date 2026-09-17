extends RefCounted

## Regressoes do buffer de interpolacao dos proxies (o "teleporte" de zumbi e
## jogador com poucos zumbis no VPS): atraso de 2 intervalos, adaptacao ao
## jitter e reinicio em realocacao do servidor.
## Uso: SnapshotInterpBufferTests.new().run(test_root)

const INTERVAL := 100.0


func run(test_root: Node) -> void:
	_test_first_sample_starts_from_node(test_root)
	_test_interpolates_halfway_at_two_intervals(test_root)
	_test_jitter_grows_delay_within_bounds(test_root)
	_test_far_jump_restarts_buffer(test_root)
	_test_starvation_reports_late_packet(test_root)
	_test_rotation_takes_shortest_path(test_root)


func _test_first_sample_starts_from_node(test_root: Node) -> void:
	print("Testando primeira amostra sem teleporte...")
	var buffer := SnapshotInterpBuffer.new()
	buffer.reset(0.0, Vector3.ZERO, 0.0)
	var node_position := Vector3(10.0, 0.0, 0.0)
	var snapped: bool = buffer.push(1000.0, Vector3(11.0, 0.0, 0.0), 0.0, node_position, 0.0)
	buffer.sample(1000.0)
	var distance: float = buffer.position.distance_to(node_position)
	if not snapped or distance > 1.1:
		_fail(test_root, "Primeira amostra deveria comecar da posicao do no (10,0,0); veio %s (snapped=%s)." % [buffer.position, snapped])
		return
	print("PASS: Primeira amostra comeca do no.")


func _test_interpolates_halfway_at_two_intervals(test_root: Node) -> void:
	print("Testando interpolacao no meio de dois snapshots...")
	var buffer := SnapshotInterpBuffer.new()
	buffer.delay_ms = INTERVAL * 2.0
	buffer.reset(0.0, Vector3.ZERO, 0.0)
	buffer.push(INTERVAL, Vector3(1.0, 0.0, 0.0), 0.0, Vector3.ZERO, 0.0)
	buffer.push(INTERVAL * 2.0, Vector3(2.0, 0.0, 0.0), 0.0, Vector3(1.0, 0.0, 0.0), 0.0)
	# Render time = 200 - 200 = 0: ainda na amostra anterior (posicao 1 m).
	buffer.sample(INTERVAL * 2.0)
	var at_start: Vector3 = buffer.position
	# Render time = 150 ms entre as amostras (350 - 200 de atraso): meio do caminho.
	buffer.sample(INTERVAL * 3.5)
	var halfway: Vector3 = buffer.position
	if not is_equal_approx(at_start.x, 1.0) or not is_equal_approx(halfway.x, 1.5):
		_fail(test_root, "Interpolacao esperada 1.0 -> 1.5 m; veio %s -> %s." % [at_start, halfway])
		return
	print("PASS: Interpolacao entre snapshots validada.")


func _test_jitter_grows_delay_within_bounds(test_root: Node) -> void:
	print("Testando atraso adaptativo com jitter...")
	var buffer := SnapshotInterpBuffer.new()
	buffer.reset(0.0, Vector3.ZERO, 0.0)
	var now := 0.0
	for index in 12:
		now += INTERVAL * 2.0
		buffer.push(now, Vector3(float(index), 0.0, 0.0), 0.0, Vector3.ZERO, 0.0)
	var delayed: float = buffer.delay_ms
	var delayed_interval: float = buffer.interval_ms()
	var clean := SnapshotInterpBuffer.new()
	clean.reset(0.0, Vector3.ZERO, 0.0)
	now = 0.0
	for index in 12:
		now += INTERVAL
		clean.push(now, Vector3(float(index), 0.0, 0.0), 0.0, Vector3.ZERO, 0.0)
	if delayed <= clean.delay_ms or delayed > SnapshotInterpBuffer.MAX_DELAY_MS or delayed_interval > SnapshotInterpBuffer.MAX_INTERVAL_MS + 0.001:
		_fail(test_root, "Com pacotes a cada 200 ms o atraso deveria crescer ate no maximo %s ms; veio %s (intervalo %s)." % [SnapshotInterpBuffer.MAX_DELAY_MS, delayed, delayed_interval])
		return
	if not is_equal_approx(clean.delay_ms, SnapshotInterpBuffer.MIN_DELAY_MS) and clean.delay_ms > INTERVAL * 2.0 + 1.0:
		_fail(test_root, "Com pacotes cravados de 100 ms o atraso deveria ficar em 200 ms; veio %s." % clean.delay_ms)
		return
	print("PASS: Atraso adaptativo validado (%s ms com jitter, %s ms cravado)." % [delayed, clean.delay_ms])


func _test_far_jump_restarts_buffer(test_root: Node) -> void:
	print("Testando reinicio em realocacao do servidor...")
	var buffer := SnapshotInterpBuffer.new()
	buffer.reset(0.0, Vector3.ZERO, 0.0)
	buffer.push(INTERVAL, Vector3(1.0, 0.0, 0.0), 0.0, Vector3.ZERO, 0.0)
	var snapped: bool = buffer.push(INTERVAL * 2.0, Vector3(80.0, 0.0, 0.0), 0.0, Vector3(1.0, 0.0, 0.0), 0.0)
	buffer.sample(INTERVAL * 2.0)
	if not snapped or buffer.position.distance_to(Vector3(80.0, 0.0, 0.0)) > 0.01:
		_fail(test_root, "Salto de 80 m deveria reiniciar o buffer em (80,0,0); veio %s (snapped=%s)." % [buffer.position, snapped])
		return
	print("PASS: Reinicio em realocacao validado.")


func _test_starvation_reports_late_packet(test_root: Node) -> void:
	print("Testando deteccao de buffer sem amostra...")
	var buffer := SnapshotInterpBuffer.new()
	buffer.reset(0.0, Vector3.ZERO, 0.0)
	buffer.push(INTERVAL, Vector3(1.0, 0.0, 0.0), 0.0, Vector3.ZERO, 0.0)
	var fresh: float = buffer.starvation_ms(INTERVAL + buffer.delay_ms)
	var starved: float = buffer.starvation_ms(INTERVAL + buffer.delay_ms + 400.0)
	if fresh > 0.0 or starved != 400.0:
		_fail(test_root, "Buffer alimentado deveria reportar 0 ms e sem amostra 400 ms; veio %s e %s." % [fresh, starved])
		return
	print("PASS: Deteccao de buffer sem amostra validada.")


func _test_rotation_takes_shortest_path(test_root: Node) -> void:
	print("Testando rotacao pelo caminho mais curto...")
	var buffer := SnapshotInterpBuffer.new()
	buffer.delay_ms = INTERVAL * 2.0
	buffer.reset(0.0, Vector3.ZERO, deg_to_rad(170.0))
	# prev = 170 graus em 0 ms, next = -170 graus em 100 ms; o caminho curto
	# entre os dois passa por 180 graus, nao por 0.
	buffer.push(INTERVAL, Vector3.ZERO, deg_to_rad(-170.0), Vector3.ZERO, deg_to_rad(170.0))
	buffer.sample(INTERVAL * 2.5)
	if absf(buffer.rotation) < deg_to_rad(175.0):
		_fail(test_root, "Rotacao de 170 para -170 graus deveria passar por 180; veio %s." % rad_to_deg(buffer.rotation))
		return
	print("PASS: Rotacao pelo caminho mais curto validada.")


func _fail(test_root: Node, message: String) -> void:
	push_error("FALHA: " + message)
	test_root.set_meta("unit_test_failed", true)
