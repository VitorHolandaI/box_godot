# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
extends Node

const SAMPLE_RATE := 44100
const GUNSHOT_DURATION := 0.16
const GROAN_DURATION := 0.62

var _gunshot_stream: AudioStreamWAV
var _groan_stream: AudioStreamWAV
var _weapon_streams: Dictionary = {}


func _ready() -> void:
	_gunshot_stream = _create_gunshot_stream()
	_groan_stream = _create_groan_stream()


## Tiro com o som da arma (perfil em WeaponStats); faca/pistola = "pistol".
## Streams por perfil em cache: gerar o PCM a cada disparo custaria CPU.
## Uso: AudioFeedback.play_gunshot(origem, WeaponStats.Kind.SNIPER)
func play_gunshot(world_position: Vector3, weapon_kind: int = -1) -> void:
	var profile := WeaponStats.sound_for(weapon_kind)
	if not _weapon_streams.has(profile):
		_weapon_streams[profile] = WeaponSoundSynth.create_stream(profile)
	var max_distance := 90.0 if profile == "sniper" or profile == "launcher" else 55.0
	_play_spatial(_weapon_streams[profile], world_position, WeaponSoundSynth.volume_for(profile), max_distance)


func play_zombie_groan(world_position: Vector3) -> void:
	_play_spatial(_groan_stream, world_position, 0.8, 22.0)


func has_audio_streams() -> bool:
	return _gunshot_stream != null and _groan_stream != null


func _play_spatial(stream: AudioStream, world_position: Vector3, volume: float, max_distance: float) -> void:
	if stream == null or DisplayServer.get_name() == "headless" or NetworkSession.is_server():
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = linear_to_db(volume)
	player.max_distance = max_distance
	player.unit_size = 4.0
	add_child(player)
	player.global_position = world_position
	player.finished.connect(player.queue_free)
	player.play()


func _create_gunshot_stream() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = _create_pcm(GUNSHOT_DURATION, func(time: float) -> float:
		var envelope := exp(-time * 30.0)
		var crack := sin(time * 2100.0 * TAU) * envelope
		var body := sin(time * 115.0 * TAU) * exp(-time * 18.0)
		return clampf(crack * 0.72 + body * 0.28, -1.0, 1.0)
	)
	return stream


func _create_groan_stream() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = _create_pcm(GROAN_DURATION, func(time: float) -> float:
		var attack := minf(time * 12.0, 1.0)
		var release := minf((GROAN_DURATION - time) * 4.0, 1.0)
		var envelope := attack * release
		var voice := sin((time * 105.0 + sin(time * 4.0) * 8.0) * TAU)
		var rasp := sin(time * 315.0 * TAU) * 0.22
		return clampf((voice * 0.78 + rasp) * envelope, -1.0, 1.0)
	)
	return stream


func _create_pcm(duration: float, sample_function: Callable) -> PackedByteArray:
	var sample_count := roundi(duration * SAMPLE_RATE)
	var pcm := PackedByteArray()
	pcm.resize(sample_count * 2)
	for index in sample_count:
		var sample := clampi(roundi(float(sample_function.call(float(index) / SAMPLE_RATE)) * 32767.0), -32768, 32767)
		pcm[index * 2] = sample & 0xff
		pcm[index * 2 + 1] = (sample >> 8) & 0xff
	return pcm
