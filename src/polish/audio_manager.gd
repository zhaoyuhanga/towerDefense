class_name AudioManager
extends Node
## AudioManager — Programmatic sound effects using AudioStreamGenerator.
## No external .ogg files needed. Pure signal consumer per ADR-0001.

var _master_vol: float = 0.8
var _sfx_vol: float = 1.0
var _players: Array[AudioStreamPlayer] = []
var _player_index: int = 0
const MAX_PLAYERS: int = 8


func _ready() -> void:
	# Pre-create audio player pool
	for i in range(MAX_PLAYERS):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)

	if has_node("/root/SignalBus"):
		SignalBus.monster_died.connect(func(_id, _pos, _r): _play(_tone(0.15, 400, 100, 0.3)))
		SignalBus.wave_started.connect(func(_w): _play(_tone(0.3, 200, 500, 0.4)))
		SignalBus.merge_completed.connect(func(_f, _t, _p): _play(_tone(0.15, 300, 700, 0.5)))
		SignalBus.merge_failed.connect(func(_r): _play(_tone(0.1, 200, 200, 0.2, true)))
		SignalBus.cell_state_changed.connect(func(_c, _r, _o, n): _play(_click(0.03, 800, 0.3) if n == 1 else _click(0.03, 400, 0.2)))
		SignalBus.wave_ended.connect(func(_w, _k, _b): _play(_tone(0.3, 500, 200, 0.3)))


func _play(stream: AudioStream) -> void:
	var player := _players[_player_index]
	_player_index = (_player_index + 1) % MAX_PLAYERS
	player.stop()
	player.stream = stream
	player.volume_db = linear_to_db(_master_vol * _sfx_vol)
	player.play()


## Generate a frequency-sweeping tone
func _tone(duration: float, freq_start: float, freq_end: float, volume: float, square: bool = false) -> AudioStream:
	var sample_rate := 44100.0
	var samples := int(duration * sample_rate)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = sample_rate
	gen.buffer_length = 0.05

	var buffer := PackedVector2Array()
	buffer.resize(samples)
	for i in range(samples):
		var t := float(i) / samples
		var freq := lerpf(freq_start, freq_end, t)
		var phase := 2.0 * PI * freq * float(i) / sample_rate
		var amp := volume * (1.0 - t * t)  # Envelope fade
		var val: float
		if square:
			val = 1.0 if sin(phase) > 0.0 else -1.0
		else:
			val = sin(phase)
		buffer[i] = Vector2(val * amp, val * amp)
	_push_frames(gen, buffer)
	return gen


## Short click/pop sound
func _click(duration: float, freq: float, volume: float) -> AudioStream:
	return _tone(duration, freq, freq * 0.5, volume)


## Push frames into the generator (internal Godot 4 API)
func _push_frames(gen: AudioStreamGenerator, frames: PackedVector2Array) -> void:
	var pb := gen.get_playback() as AudioStreamGeneratorPlayback
	if pb:
		pb.push_buffer(frames)
