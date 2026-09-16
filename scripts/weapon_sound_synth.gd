class_name WeaponSoundSynth
extends RefCounted

## Sons de tiro sintetizados por perfil (sem assets): ruido de polvora com
## corpo grave para armas de fogo, e tons eletronicos para as futuristas. Cada
## arma escolhe o perfil no campo "sound" de WeaponStats.
## Uso: var stream := WeaponSoundSynth.create_stream("shotgun")

const SAMPLE_RATE := 44100
## duracao (s), grave (Hz), estalo (Hz), decaimento, ruido (0..1), volume.
const PROFILES: Dictionary = {
	"pistol": [0.16, 115.0, 2100.0, 30.0, 0.35, 1.25],
	"smg": [0.09, 160.0, 2600.0, 55.0, 0.45, 0.95],
	"rifle": [0.22, 95.0, 1800.0, 22.0, 0.55, 1.35],
	"heavy_rifle": [0.28, 75.0, 1400.0, 17.0, 0.6, 1.5],
	"shotgun": [0.38, 60.0, 900.0, 11.0, 0.85, 1.7],
	"magnum": [0.32, 70.0, 1200.0, 14.0, 0.6, 1.6],
	"sniper": [0.6, 55.0, 3000.0, 7.0, 0.5, 1.8],
	"launcher": [0.75, 40.0, 500.0, 5.0, 0.9, 1.9],
	"laser": [0.3, 0.0, 2400.0, 9.0, 0.0, 1.0],
	"plasma": [0.14, 0.0, 700.0, 25.0, 0.1, 0.9],
	"railgun": [0.7, 45.0, 1600.0, 6.0, 0.2, 1.7],
	"crossbow": [0.22, 0.0, 190.0, 14.0, 0.12, 0.7],
	"grenade": [0.5, 48.0, 320.0, 8.0, 0.55, 1.45],
}


## Stream WAV do perfil (perfil desconhecido cai no da pistola).
## Uso: player.stream = WeaponSoundSynth.create_stream("sniper")
static func create_stream(profile: String) -> AudioStreamWAV:
	var params: Array = PROFILES.get(profile, PROFILES["pistol"])
	var duration := float(params[0])
	var sample_count := int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(profile)
	for index in sample_count:
		var time := float(index) / SAMPLE_RATE
		var value := clampf(_sample(profile, params, time, duration, rng.randf_range(-1.0, 1.0)), -1.0, 1.0)
		data.encode_s16(index * 2, int(value * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = data
	return stream


## Volume linear do perfil (bazuca e sniper mais altos, SMG mais baixa).
static func volume_for(profile: String) -> float:
	return float((PROFILES.get(profile, PROFILES["pistol"]) as Array)[5])


static func _sample(profile: String, params: Array, time: float, duration: float, noise: float) -> float:
	var bass_hz := float(params[1])
	var crack_hz := float(params[2])
	var decay := float(params[3])
	var noise_mix := float(params[4])
	var envelope := exp(-time * decay)
	match profile:
		"laser":
			# Feixe: tom que desce rapido, com leve vibrato.
			var laser_hz := crack_hz * exp(-time * 6.0)
			return sin(time * laser_hz * TAU + sin(time * 90.0) * 0.6) * envelope * 0.8
		"plasma":
			# Plasma: pulso grave modulado, "bolha" eletrica curta.
			return sin(time * crack_hz * TAU) * sin(time * 38.0 * TAU) * envelope * 0.9 + noise * 0.1 * envelope
		"crossbow":
			# Besta: corda vibrando (tom grave curto) e estalo seco da trava.
			var twang := sin(time * crack_hz * TAU) * sin(time * 9.0 * TAU + 1.0) * envelope
			return twang * 0.9 + noise * noise_mix * exp(-time * 80.0)
		"railgun":
			# Railgun: zumbido de carga subindo nos primeiros 40% e estouro grave.
			var charge := clampf(time / (duration * 0.4), 0.0, 1.0)
			var whine := sin(time * crack_hz * (0.5 + charge) * TAU) * 0.35 * (1.0 - charge * 0.5)
			var blast := (sin(time * bass_hz * TAU) * 0.7 + noise * noise_mix) * exp(-maxf(time - duration * 0.4, 0.0) * decay) * charge
			return whine + blast
	# Armas de fogo: estalo agudo curto + ruido de polvora + corpo grave.
	var crack := sin(time * crack_hz * TAU) * exp(-time * decay * 2.2)
	var powder := noise * noise_mix * envelope
	var body := sin(time * bass_hz * TAU) * exp(-time * decay * 0.6)
	return crack * 0.35 + powder * 0.6 + body * 0.45
