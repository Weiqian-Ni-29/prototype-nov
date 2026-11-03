class_name JourneySound
extends Node
## Original synthesized cues; no downloaded samples or runtime network dependency.
var player: AudioStreamPlayer
var cache: Dictionary = {}
var volume = 0.65

func _ready() -> void:
	player = AudioStreamPlayer.new()
	player.volume_db = -18
	add_child(player)
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
		cache[kind] = _synthesize(kind)
	player.stop()
	player.stream = cache[kind]
	player.play()

func _exit_tree() -> void:
	if is_instance_valid(player):
		player.stop()
		player.stream = null
	cache.clear()

func _synthesize(kind: String) -> AudioStreamWAV:
	var frequencies = {"click": [440.0], "day": [392.0, 493.88], "attack": [196.0, 246.94], "cast": [523.25, 659.25], "victory": [523.25, 659.25, 783.99]}.get(kind, [440.0])
	var sample_rate = 22050
	var duration = 0.11 if kind == "click" else 0.25
	var count = int(sample_rate * duration)
	var pcm = PackedByteArray()
	pcm.resize(count * 2)
	for i in range(count):
		var t = float(i) / sample_rate
		var envelope = sin(PI * t / duration) * exp(-t * 8.0)
		var value = 0.0
		for f in frequencies:
			value += sin(TAU * f * t) / frequencies.size()
		pcm.encode_s16(i * 2, int(value * envelope * 18000))
	var wave = AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = sample_rate
	wave.data = pcm
	return wave
