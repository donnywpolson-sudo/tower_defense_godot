extends Node

const ASSET_ROOT := "res://assets/"

var stream_cache: Dictionary = {}
var sound_enabled: bool = true
var sfx_enabled: bool = true


func load_sound(relative_path: String) -> AudioStream:
	if stream_cache.has(relative_path):
		return stream_cache[relative_path]
	var path := ASSET_ROOT + relative_path
	if not ResourceLoader.exists(path):
		stream_cache[relative_path] = null
		return null
	var loaded: Resource = load(path)
	if loaded is AudioStream:
		stream_cache[relative_path] = loaded
		return loaded
	stream_cache[relative_path] = null
	return null


func load_sound_any(paths: Array) -> AudioStream:
	for relative_path in paths:
		var stream := load_sound(str(relative_path))
		if stream != null:
			return stream
	return null


func load_game_sound(relative_path: String) -> AudioStream:
	if relative_path.ends_with(".wav"):
		return load_sound_any([relative_path, relative_path.trim_suffix(".wav") + ".ogg"])
	return load_sound(relative_path)


func sound_status(relative_path: String, fallback_frequency: float = 440.0, duration: float = 0.08, volume: float = 0.2) -> Dictionary:
	var stream := load_game_sound(relative_path)
	var fallback := false
	if stream == null:
		stream = make_tone(fallback_frequency, duration, volume)
		fallback = true
	return {
		"requested": relative_path,
		"loaded": not fallback,
		"fallback": fallback,
		"stream": stream,
	}


func play_sound(relative_path: String, fallback_frequency: float = 440.0, volume_db: float = -12.0) -> bool:
	if not sound_enabled or not sfx_enabled:
		return false
	var status := sound_status(relative_path, fallback_frequency)
	var stream: AudioStream = status["stream"]
	if stream == null:
		return false
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	return true


func make_tone(frequency: float, duration: float = 0.08, volume: float = 0.25) -> AudioStreamWAV:
	var sample_rate := 22050
	var sample_count := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var amplitude := int(32767.0 * volume)
	for index in range(sample_count):
		var fade: float = 1.0 - float(index) / max(1.0, float(sample_count))
		var value: int = int(amplitude * fade * sin(TAU * frequency * float(index) / float(sample_rate)))
		if value < 0:
			value = 65536 + value
		data[index * 2] = value & 0xff
		data[index * 2 + 1] = (value >> 8) & 0xff
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream
