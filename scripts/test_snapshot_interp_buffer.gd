extends RefCounted

## Regressoes do buffer de interpolacao dos proxies. O caso central e o de
## continuidade: com atraso de 2 intervalos e so duas amostras guardadas o
## tempo de render cai antes da amostra mais antiga, o peso trava em 0 e tudo
## que se move passa a saltar a 10 Hz (25 de 29 frames parados, salto de 0,5 m
## num quadro). O teste antigo amostrava um instante so e nao pegava isso.
## Uso: SnapshotInterpBufferTests.new().run(test_root)

const FRAME_MS := 16.0
const SNAPSHOT_MS := 100.0
const TWENTY_HZ_SNAPSHOT_MS := 50.0
const THIRTY_HZ_SNAPSHOT_MS := 1000.0 / 30.0
const SIXTY_HZ_SNAPSHOT_MS := 1000.0 / 60.0
## O servidor anda 0,5 m entre snapshots (2,2 m/s com o passo de 10 Hz).
const STEP_METERS := 0.5


func run(test_root: Node) -> void:
	_test_continuity_across_snapshots(test_root)
	_test_interpolates_between_held_samples(test_root)
	_test_far_jump_restarts_buffer(test_root)
	_test_first_sample_starts_from_node(test_root)
	_test_jitter_grows_delay_within_bounds(test_root)
	_test_rotation_takes_shortest_path(test_root)
	_test_sample_history_is_bounded(test_root)
	_test_twenty_hz_uses_two_interval_delay(test_root)
	_test_thirty_hz_uses_two_interval_delay(test_root)
	_test_sixty_hz_uses_two_interval_delay(test_root)
	_test_fast_snapshots_do_not_freeze(test_root)


## O teste que faltava: acompanha o proxy por varios snapshots e exige que a
## posicao ande em todo frame (sem congelar) e com passo de tamanho constante.
func _test_continuity_across_snapshots(test_root: Node) -> void:
	print("Testando continuidade da interpolacao entre varios snapshots...")
	var buffer := SnapshotInterpBuffer.new()
	buffer.reset(0.0, Vector3.ZERO, 0.0)
	var next_push_ms := SNAPSHOT_MS
	var pushed := 0
	var previous := Vector3.ZERO
	var frozen_frames := 0
	var max_step := 0.0
	# Com o estimador inicializado para o servidor atual (60 Hz), um servidor
	# antigo de 10 Hz precisa de algumas chegadas para elevar o atraso adaptativo.
	var warmup_ms := maxf(buffer.delay_ms + SNAPSHOT_MS, SNAPSHOT_MS * 4.0)
	for frame in 60:
		var now_ms := float(frame) * FRAME_MS
		while now_ms >= next_push_ms:
			pushed += 1
			buffer.push(now_ms, Vector3(STEP_METERS * float(pushed), 0.0, 0.0), 0.0, buffer.position, 0.0)
			next_push_ms += SNAPSHOT_MS
		buffer.sample(now_ms)
		if now_ms >= warmup_ms:
			var step := absf(buffer.position.x - previous.x)
			if step < 0.005:
				frozen_frames += 1
			max_step = maxf(max_step, step)
		previous = buffer.position
	var expected_step := STEP_METERS * FRAME_MS / SNAPSHOT_MS
	if frozen_frames > 1:
		_fail(test_root, "Proxy nao pode congelar depois do aquecimento: %d frames parados de %d (passo esperado %.3f m)." % [frozen_frames, 60, expected_step])
		return
	if max_step > expected_step * 1.8:
		_fail(test_root, "Passo por frame deveria ficar perto de %.3f m; veio %.3f m (salto de snapshot em vez de interpolacao)." % [expected_step, max_step])
		return
	if pushed < 4 or buffer.position.x < STEP_METERS * float(pushed - 3):
		_fail(test_root, "Posicao deveria acompanhar os %d snapshots ate ~%.2f m; veio %.2f m." % [pushed, STEP_METERS * float(pushed), buffer.position.x])
		return
	print("PASS: Proxy anda em todo frame (passo max %.3f m, esperado %.3f m)." % [max_step, expected_step])


func _test_interpolates_between_held_samples(test_root: Node) -> void:
	print("Testando interpolacao entre as amostras guardadas...")
	var buffer := SnapshotInterpBuffer.new()
	buffer.delay_ms = SNAPSHOT_MS * 2.0
	buffer.reset(0.0, Vector3.ZERO, 0.0)
	buffer.push(SNAPSHOT_MS, Vector3(STEP_METERS, 0.0, 0.0), 0.0, Vector3.ZERO, 0.0)
	buffer.push(SNAPSHOT_MS * 2.0, Vector3(STEP_METERS * 2.0, 0.0, 0.0), 0.0, Vector3(STEP_METERS, 0.0, 0.0), 0.0)
	buffer.push(SNAPSHOT_MS * 3.0, Vector3(STEP_METERS * 3.0, 0.0, 0.0), 0.0, Vector3(STEP_METERS * 2.0, 0.0, 0.0), 0.0)
	# Este caso testa so a escolha do par de amostras, nao a estimativa adaptativa.
	buffer.delay_ms = SNAPSHOT_MS * 2.0
	# Render time = 150 ms (350 - 200): entre 0,5 m (100 ms) e 1,0 m (200 ms).
	buffer.sample(SNAPSHOT_MS * 3.5)
	var middle := buffer.position.x
	if not is_equal_approx(middle, STEP_METERS * 1.5):
		_fail(test_root, "Interpolacao esperada em %.2f m; veio %.2f m." % [STEP_METERS * 1.5, middle])
		return
	print("PASS: Interpolacao entre amostras guardadas validada.")


func _test_far_jump_restarts_buffer(test_root: Node) -> void:
	print("Testando reinicio em realocacao do servidor...")
	var buffer := SnapshotInterpBuffer.new()
	buffer.reset(0.0, Vector3.ZERO, 0.0)
	buffer.push(SNAPSHOT_MS, Vector3(STEP_METERS, 0.0, 0.0), 0.0, Vector3.ZERO, 0.0)
	var snapped: bool = buffer.push(SNAPSHOT_MS * 2.0, Vector3(80.0, 0.0, 0.0), 0.0, Vector3(STEP_METERS, 0.0, 0.0), 0.0)
	buffer.sample(SNAPSHOT_MS * 2.0)
	if not snapped or buffer.position.distance_to(Vector3(80.0, 0.0, 0.0)) > 0.01:
		_fail(test_root, "Salto de 80 m deveria reiniciar o buffer em (80,0,0); veio %s (snapped=%s)." % [buffer.position, snapped])
		return
	print("PASS: Reinicio em realocacao validado.")


func _test_first_sample_starts_from_node(test_root: Node) -> void:
	print("Testando primeira amostra sem teleporte...")
	var buffer := SnapshotInterpBuffer.new()
	var node_position := Vector3(10.0, 0.0, 0.0)
	var snapped: bool = buffer.push(SNAPSHOT_MS, Vector3(11.0, 0.0, 0.0), 0.0, node_position, 0.0)
	buffer.sample(SNAPSHOT_MS)
	var distance: float = buffer.position.distance_to(node_position)
	if not snapped or distance > 1.1:
		_fail(test_root, "Primeira amostra deveria comecar da posicao do no (10,0,0); veio %s (snapped=%s)." % [buffer.position, snapped])
		return
	print("PASS: Primeira amostra comeca do no.")


func _test_jitter_grows_delay_within_bounds(test_root: Node) -> void:
	print("Testando atraso adaptativo com jitter...")
	var delayed := SnapshotInterpBuffer.new()
	delayed.reset(0.0, Vector3.ZERO, 0.0)
	var now_ms := 0.0
	for index in 12:
		now_ms += SNAPSHOT_MS * 2.0
		delayed.push(now_ms, Vector3(float(index), 0.0, 0.0), 0.0, Vector3.ZERO, 0.0)
	var clean := SnapshotInterpBuffer.new()
	clean.reset(0.0, Vector3.ZERO, 0.0)
	now_ms = 0.0
	for index in 12:
		now_ms += SNAPSHOT_MS
		clean.push(now_ms, Vector3(float(index), 0.0, 0.0), 0.0, Vector3.ZERO, 0.0)
	if delayed.delay_ms <= clean.delay_ms or delayed.delay_ms > SnapshotInterpBuffer.MAX_DELAY_MS:
		_fail(test_root, "Com pacotes a cada 200 ms o atraso deveria crescer ate no maximo %s ms; veio %s ms (cravado: %s ms)." % [SnapshotInterpBuffer.MAX_DELAY_MS, delayed.delay_ms, clean.delay_ms])
		return
	if clean.delay_ms > SNAPSHOT_MS * 2.0 + 1.0:
		_fail(test_root, "Com pacotes cravados de 100 ms o atraso deveria ficar em 200 ms; veio %s ms." % clean.delay_ms)
		return
	if delayed.interval_ms() > SnapshotInterpBuffer.MAX_INTERVAL_MS + 0.001:
		_fail(test_root, "Intervalo estimado nao pode passar de %s ms; veio %s ms." % [SnapshotInterpBuffer.MAX_INTERVAL_MS, delayed.interval_ms()])
		return
	print("PASS: Atraso adaptativo validado (jitter %s ms, cravado %s ms)." % [delayed.delay_ms, clean.delay_ms])


func _test_rotation_takes_shortest_path(test_root: Node) -> void:
	print("Testando rotacao pelo caminho mais curto...")
	var buffer := SnapshotInterpBuffer.new()
	buffer.delay_ms = SNAPSHOT_MS * 2.0
	buffer.reset(0.0, Vector3.ZERO, deg_to_rad(170.0))
	buffer.push(SNAPSHOT_MS, Vector3.ZERO, deg_to_rad(-170.0), Vector3.ZERO, deg_to_rad(170.0))
	# Render time = 50 ms: meio caminho entre 170 e -170, que passa por 180.
	buffer.sample(SNAPSHOT_MS * 2.5)
	if absf(buffer.rotation) < deg_to_rad(175.0):
		_fail(test_root, "Rotacao de 170 para -170 graus deveria passar por 180; veio %.1f graus." % rad_to_deg(buffer.rotation))
		return
	print("PASS: Rotacao pelo caminho mais curto validada.")


func _test_sample_history_is_bounded(test_root: Node) -> void:
	print("Testando limite de amostras guardadas...")
	var buffer := SnapshotInterpBuffer.new()
	buffer.reset(0.0, Vector3.ZERO, 0.0)
	for index in 40:
		buffer.push(float(index) * SNAPSHOT_MS, Vector3(float(index), 0.0, 0.0), 0.0, Vector3.ZERO, 0.0)
	if buffer.sample_count() > SnapshotInterpBuffer.MAX_SAMPLES or buffer.sample_count() < 2:
		_fail(test_root, "Historico deveria ficar entre 2 e %d amostras; veio %d." % [SnapshotInterpBuffer.MAX_SAMPLES, buffer.sample_count()])
		return
	print("PASS: Historico de amostras limitado (%d)." % buffer.sample_count())

## A 20 Hz, dois intervalos sao 100 ms. O piso antigo de 150 ms escondia metade
## do ganho do snapshot mais rapido mesmo em uma rede sem jitter.
func _test_twenty_hz_uses_two_interval_delay(test_root: Node) -> void:
	print("Testando atraso de dois intervalos com snapshots a 20 Hz...")
	var buffer := SnapshotInterpBuffer.new()
	buffer.reset(0.0, Vector3.ZERO, 0.0)
	for index in 20:
		var now_ms := TWENTY_HZ_SNAPSHOT_MS * float(index + 1)
		buffer.push(now_ms, Vector3(float(index), 0.0, 0.0), 0.0, Vector3.ZERO, 0.0)
	var expected_delay_ms := TWENTY_HZ_SNAPSHOT_MS * SnapshotInterpBuffer.DELAY_INTERVALS
	if buffer.delay_ms > expected_delay_ms + 15.0:
		_fail(test_root, "Snapshots a 20 Hz deveriam ficar perto de %s ms; veio %s ms." % [expected_delay_ms, buffer.delay_ms])
		return
	print("PASS: Snapshots a 20 Hz usam %s ms de atraso." % buffer.delay_ms)


## A 30 Hz, dois intervalos sao ~66,7 ms. O piso precisa deixar o atraso cair
## ate esse valor para que a taxa maior reduza a latencia percebida.
func _test_thirty_hz_uses_two_interval_delay(test_root: Node) -> void:
	print("Testando atraso de dois intervalos com snapshots a 30 Hz...")
	var buffer := SnapshotInterpBuffer.new()
	buffer.reset(0.0, Vector3.ZERO, 0.0)
	for index in 30:
		var now_ms := THIRTY_HZ_SNAPSHOT_MS * float(index + 1)
		buffer.push(now_ms, Vector3(float(index), 0.0, 0.0), 0.0, Vector3.ZERO, 0.0)
	var expected_delay_ms := THIRTY_HZ_SNAPSHOT_MS * SnapshotInterpBuffer.DELAY_INTERVALS
	if buffer.delay_ms > expected_delay_ms + 3.0:
		_fail(test_root, "Snapshots a 30 Hz deveriam ficar perto de %s ms; veio %s ms." % [expected_delay_ms, buffer.delay_ms])
		return
	print("PASS: Snapshots a 30 Hz usam %s ms de atraso." % buffer.delay_ms)


## A 60 Hz, dois intervalos sao ~33,3 ms. Se o piso ficar acima disso, dobrar
## a taxa de servidor nao reduz a latencia percebida do proxy.
func _test_sixty_hz_uses_two_interval_delay(test_root: Node) -> void:
	print("Testando atraso de dois intervalos com snapshots a 60 Hz...")
	var buffer := SnapshotInterpBuffer.new()
	buffer.reset(0.0, Vector3.ZERO, 0.0)
	for index in 60:
		var now_ms := SIXTY_HZ_SNAPSHOT_MS * float(index + 1)
		buffer.push(now_ms, Vector3(float(index), 0.0, 0.0), 0.0, Vector3.ZERO, 0.0)
	var expected_delay_ms := SIXTY_HZ_SNAPSHOT_MS * SnapshotInterpBuffer.DELAY_INTERVALS
	if buffer.delay_ms > expected_delay_ms + 2.0:
		_fail(test_root, "Snapshots a 60 Hz deveriam ficar perto de %s ms; veio %s ms." % [expected_delay_ms, buffer.delay_ms])
		return
	print("PASS: Snapshots a 60 Hz usam %s ms de atraso." % buffer.delay_ms)


## Servidor mais rapido (15-30 Hz) nao pode reintroduzir o congelamento: o
## atraso tem que caber no historico guardado, senao o render time cai antes da
## amostra mais antiga e o peso trava em 0 de novo.
func _test_fast_snapshots_do_not_freeze(test_root: Node) -> void:
	print("Testando snapshots rapidos (30 Hz) sem congelar...")
	var buffer := SnapshotInterpBuffer.new()
	# 20 ms (servidor a 50 Hz): e onde o piso de MIN_DELAY_MS estourava o
	# historico SEM o teto por amostras guardadas.
	var snapshot_ms := 20.0
	buffer.reset(0.0, Vector3.ZERO, 0.0)
	var next_push_ms := snapshot_ms
	var pushed := 0
	var previous := Vector3.ZERO
	var frozen_frames := 0
	for frame in 90:
		var now_ms := float(frame) * FRAME_MS
		while now_ms >= next_push_ms:
			pushed += 1
			buffer.push(now_ms, Vector3(0.25 * float(pushed), 0.0, 0.0), 0.0, buffer.position, 0.0)
			next_push_ms += snapshot_ms
		buffer.sample(now_ms)
		if now_ms >= 400.0:
			if absf(buffer.position.x - previous.x) < 0.002:
				frozen_frames += 1
		previous = buffer.position
	if buffer.delay_ms > float(SnapshotInterpBuffer.MAX_SAMPLES - 2) * buffer.interval_ms() + 0.001:
		_fail(test_root, "Atraso (%s ms) passou do historico (%s amostras x %s ms)." % [buffer.delay_ms, SnapshotInterpBuffer.MAX_SAMPLES, buffer.interval_ms()])
		return
	if frozen_frames > 2:
		_fail(test_root, "Com snapshots de 33 ms o proxy congelou em %d frames; atraso=%s ms intervalo=%s ms." % [frozen_frames, buffer.delay_ms, buffer.interval_ms()])
		return
	print("PASS: Snapshots rapidos interpolam sem congelar (atraso %s ms)." % buffer.delay_ms)


func _fail(test_root: Node, message: String) -> void:
	push_error("FALHA: " + message)
	test_root.set_meta("unit_test_failed", true)
