## Autoload : lecture des effets sonores générés par code (_sfx_gen.gd ->
## assets/sfx/*.wav). Pool de lecteurs en tourniquet, flux chargés à la
## demande (et mis en cache). Sûr en headless : sans périphérique audio,
## AudioStreamPlayer.play() ne fait rien de nuisible (pas de crash).
extends Node

const POOL_SIZE := 8

var _players: Array = []
var _streams: Dictionary = {}   # id -> AudioStreamWAV (cache)
var _next: int = 0

func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)

## Joue l'effet `id` (assets/sfx/<id>.wav) sur le prochain lecteur du
## tourniquet, à `vol_db` dB au-dessus du volume maître SFX des réglages.
func play(id: String, vol_db: float = 0.0) -> void:
	var stream = _load(id)
	if stream == null or _players.is_empty():
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.volume_db = vol_db + _sfx_vol_db()
	p.play()

func _load(id: String):
	if _streams.has(id):
		return _streams[id]
	var path := "res://assets/sfx/%s.wav" % id
	if not ResourceLoader.exists(path):
		return null
	var s = load(path)
	_streams[id] = s
	return s

func _sfx_vol_db() -> float:
	var lin: float = clampf(float(GameState.settings.get("sfx_vol", 0.8)), 0.0, 1.0)
	if lin <= 0.0001:
		return -80.0
	return linear_to_db(lin)
