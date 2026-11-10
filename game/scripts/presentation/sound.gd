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
	var frequencies = {"click":[440.0],"attack":[196.0,246.94],"normal":[440.0,660.0],"impact":[82.4,123.5],"bow":[740.0,988.0],"heal":[523.25,783.99,1046.5],"shield":[329.63,493.88],"fire":[110.0,164.8],"water":[587.33,880.0],"howl":[196.0,294.0],"cast":[523.25,659.25],"victory":[523.25,659.25,783.99]}.get(kind,[440.0])
	var sample_rate = 22050
	var duration = 0.11 if kind=="click" else 0.65 if kind=="howl" else 0.4 if kind in ["heal","water","shield"] else 0.25
	var count = int(sample_rate * duration)
	var pcm = PackedByteArray()
	pcm.resize(count * 2)
	for i in range(count):
		var t = float(i) / sample_rate
		var envelope = sin(PI * t / duration) * exp(-t * 8.0)
		var value = 0.0
		for f in frequencies:
			var sweep = 1.0-t/duration*0.65 if kind in ["bow","impact"] else 1.0+sin(t*8.0)*0.10 if kind=="howl" else 1.0
			value += sin(TAU*f*t*sweep)/frequencies.size()
		if kind in ["fire","impact"]: value = value*0.65+sin(float(i*i%7919))*0.35
		pcm.encode_s16(i * 2, int(value * envelope * 18000))
	var wave = AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = sample_rate
	wave.data = pcm
	return wave
