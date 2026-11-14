class_name JourneySound
extends Node
## Original synthesized cues; no downloaded samples or runtime network dependency.
const DAY_CHIME = preload("res://assets/audio/dawn-bronze-bell.wav")
var player: AudioStreamPlayer
var cache: Dictionary = {}
var volume = 0.65
var voices: Array[AudioStreamPlayer] = []
var voice_index = 0

func _ready() -> void:
	player = AudioStreamPlayer.new()
	player.volume_db = -18
	add_child(player)
	voices.append(player)
	for i in range(3):
		var voice = AudioStreamPlayer.new()
		voice.volume_db = -18
		add_child(voice)
		voices.append(voice)
	var settings = ConfigFile.new()
	if settings.load("user://settings.cfg") == OK:
		volume = clampf(float(settings.get_value("audio", "volume", 0.65)), 0.0, 1.0)
	set_volume(volume, false)

func set_volume(value: float, persist: bool = true) -> void:
	volume = clampf(value, 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, volume)))
	if persist:
		var settings = ConfigFile.new()
		settings.set_value("audio", "volume", volume)
		settings.save("user://settings.cfg")

func play(kind: String = "click") -> void:
	if player == null or volume <= 0:
		return
	if not cache.has(kind):
		cache[kind] = DAY_CHIME if kind == "day" else _synthesize(kind)
	var voice = voices[voice_index%voices.size()]
	voice_index += 1
	voice.stop()
	voice.stream = cache[kind]
	voice.play()

func _exit_tree() -> void:
	for voice in voices:
		voice.stop()
		voice.stream = null
	cache.clear()

func _synthesize(kind: String) -> AudioStreamWAV:
	var impact := kind.begins_with("chess_")
	var frequencies = [523.25, 659.25, 783.99] if kind == "victory" else [440.0]
	var sample_rate = 22050
	var duration = 0.13 if impact else 0.11 if kind == "click" else 0.25
	var pitch := 730.0 if kind == "chess_block" else 340.0 if kind == "chess_shot" else 105.0
	var noise := RandomNumberGenerator.new()
	noise.seed = 721
	var count = int(sample_rate * duration)
	var pcm = PackedByteArray()
	pcm.resize(count * 2)
	for i in range(count):
		var t = float(i) / sample_rate
		var envelope = sin(PI * t / duration) * exp(-t * 8.0)
		var value = 0.0
		if impact:
			var tone := sin(TAU * pitch * t * (1.0 - t * 1.8)) * exp(-t * 39.0)
			var snap := noise.randf_range(-1.0, 1.0) * exp(-t * 125.0)
			value = tone * 0.68 + snap * 0.30
			envelope = minf(1.0, t * 1200.0)
		else:
			for f in frequencies:
				value += sin(TAU * f * t) / frequencies.size()
		pcm.encode_s16(i * 2, int(value * envelope * 18000))
	var wave = AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = sample_rate
	wave.data = pcm
	return wave
