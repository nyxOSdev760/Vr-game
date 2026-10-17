extends Node
## Sound playback: a pool of 2D players for the player's own sounds and a pool of 3D players
## for positional sounds. Autoloaded as `Sfx`.

const DIR := "res://assets/sfx/"
const LOOPING := ["hum_small", "hum_rotor", "hum_heavy"]

var _streams := {}
var _flat: Array[AudioStreamPlayer] = []
var _spatial: Array[AudioStreamPlayer3D] = []
var _fi := 0
var _si := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for f in DirAccess.get_files_at(DIR):
		var fname := f.trim_suffix(".import")
		if not fname.ends_with(".ogg"): continue
		var key := fname.get_basename()
		if _streams.has(key): continue
		var s: AudioStream = load(DIR + fname)
		if s is AudioStreamOggVorbis and key in LOOPING:
			s = s.duplicate()
			(s as AudioStreamOggVorbis).loop = true
		_streams[key] = s
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_flat.append(p)
	for i in 24:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 4.0
		p3.max_distance = 60.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p3)
		_spatial.append(p3)


func stream(key: String) -> AudioStream:
	return _streams.get(key)


## Non-positional sound (guns in hand, UI, player hurt).
func play(key: String, volume_db := 0.0, pitch := 1.0, pitch_jitter := 0.06) -> void:
	var s: AudioStream = _streams.get(key)
	if s == null: return
	var p := _flat[_fi]
	_fi = (_fi + 1) % _flat.size()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
	p.play()


## Positional sound at a world point.
func play_at(key: String, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	var s: AudioStream = _streams.get(key)
	if s == null: return
	var p := _spatial[_si]
	_si = (_si + 1) % _spatial.size()
	p.stream = s
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.play()


## A looping emitter owned by a node (drone engine hum).
func make_loop(key: String, parent: Node3D, volume_db := -12.0, pitch := 1.0) -> AudioStreamPlayer3D:
	var s: AudioStream = _streams.get(key)
	if s == null: return null
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.unit_size = 2.5
	p.max_distance = 35.0
	p.autoplay = true
	parent.add_child(p)
	return p
