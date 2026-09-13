class_name ServerPingProbe
extends RefCounted

const CONNECT_TIMEOUT_MS := 750
const POLL_DELAY_MS := 1


func measure(address: String, port: int) -> int:
	var connection := ENetConnection.new()
	var create_error := connection.create_host(1, 1)
	if create_error != OK:
		return -1
	var started_usec := Time.get_ticks_usec()
	var packet_peer := connection.connect_to_host(address, port, 1)
	if packet_peer == null or not _wait_for_connection(connection):
		connection.destroy()
		return -1
	var ping_ms := roundi(float(Time.get_ticks_usec() - started_usec) / 1000.0)
	packet_peer.peer_disconnect_now()
	connection.destroy()
	return ping_ms


func _wait_for_connection(connection: ENetConnection) -> bool:
	var deadline := Time.get_ticks_msec() + CONNECT_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		var event: Array = connection.service(0)
		if event.size() > 0 and int(event[0]) == ENetConnection.EVENT_CONNECT:
			return true
		if event.size() > 0 and int(event[0]) == ENetConnection.EVENT_ERROR:
			return false
		OS.delay_msec(POLL_DELAY_MS)
	return false
