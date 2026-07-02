extends SceneTree
# Générateur d'effets sonores — synthèse procédurale PCM16 mono 22 050 Hz.
# Lancé en headless : godot --headless --script res://_sfx_gen.gd
# Produit des WAV dans res://assets/sfx/. Même esprit que _assets_gen.gd :
# tout est généré par code, rien n'est vendored.

const SR := 22050
var rng := RandomNumberGenerator.new()

func _init() -> void:
	rng.seed = 2024
	DirAccess.make_dir_recursive_absolute("res://assets/sfx")
	_save_sfx("hit", _wave_hit())
	_save_sfx("crit", _wave_crit())
	_save_sfx("kill", _wave_kill())
	_save_sfx("pickup", _wave_pickup())
	_save_sfx("levelup", _wave_levelup())
	_save_sfx("stairs", _wave_stairs())
	_save_sfx("buy", _wave_buy())
	_save_sfx("heal", _wave_heal())
	_save_sfx("ui", _wave_ui())
	_save_sfx("danger", _wave_danger())
	print("=== SFX GENERATED ===")
	quit()

# --- Recettes (toutes les valeurs sont à régler à l'oreille) -------------------
func _wave_hit() -> PackedFloat32Array:
	var n := _ms(60.0)
	var noise := _apply_env(_white_noise(n), _envelope_decay(n, 6.0))
	var thump := _apply_env(_sine_wave(150.0, n), _envelope_decay(n, 8.0))
	return _mix2(_scale(noise, 0.7), _scale(thump, 0.6))

func _wave_crit() -> PackedFloat32Array:
	var cn := _ms(80.0)
	var chirp := _apply_env(_square_sweep_wave(400.0, 900.0, cn), _envelope_decay(cn, 3.0))
	return _concat([_wave_hit(), _scale(chirp, 0.5)])

func _wave_kill() -> PackedFloat32Array:
	var n := _ms(150.0)
	return _apply_env(_saw_sweep_wave(300.0, 80.0, n), _envelope_decay(n, 4.0))

func _wave_pickup() -> PackedFloat32Array:
	var n := _ms(40.0)
	var b1 := _apply_env(_square_wave(660.0, n), _envelope_decay(n, 6.0))
	var b2 := _apply_env(_square_wave(990.0, n), _envelope_decay(n, 6.0))
	return _concat([b1, b2])

func _wave_levelup() -> PackedFloat32Array:
	var n := _ms(60.0)
	var parts: Array = []
	for f in [523.0, 659.0, 784.0]:
		parts.append(_apply_env(_square_wave(f, n), _envelope_decay(n, 4.0)))
	return _concat(parts)

func _wave_stairs() -> PackedFloat32Array:
	var n := _ms(200.0)
	var noise := _lowpass(_white_noise(n), 0.08)
	return _apply_env(noise, _envelope_swell(n))

func _wave_buy() -> PackedFloat32Array:
	var n := _ms(35.0)
	var pulse := _apply_env(_sine_wave(1320.0, n), _envelope_decay(n, 10.0))
	return _concat([pulse, _silence(_ms(15.0)), pulse])

func _wave_heal() -> PackedFloat32Array:
	var n := _ms(250.0)
	return _apply_env(_sine_sweep_wave(440.0, 660.0, n), _envelope_swell(n))

func _wave_ui() -> PackedFloat32Array:
	var n := _ms(10.0)
	return _apply_env(_square_wave(1200.0, n), _envelope_decay(n, 8.0))

func _wave_danger() -> PackedFloat32Array:
	var n := _ms(90.0)
	var pulse := _apply_env(_square_wave(110.0, n), _envelope_decay(n, 3.0))
	return _concat([pulse, _silence(_ms(60.0)), pulse])

# --- Formes d'onde brutes (amplitude -1..1, sans enveloppe) --------------------
func _sine_wave(freq: float, n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array(); out.resize(n)
	for i in n:
		out[i] = sin(TAU * freq * float(i) / float(SR))
	return out

func _sine_sweep_wave(f0: float, f1: float, n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array(); out.resize(n)
	var phase := 0.0
	for i in n:
		var f: float = lerpf(f0, f1, float(i) / float(maxi(1, n - 1)))
		phase += TAU * f / float(SR)
		out[i] = sin(phase)
	return out

func _square_wave(freq: float, n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array(); out.resize(n)
	for i in n:
		var ph: float = fmod(freq * float(i) / float(SR), 1.0)
		out[i] = 1.0 if ph < 0.5 else -1.0
	return out

func _square_sweep_wave(f0: float, f1: float, n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array(); out.resize(n)
	var phase := 0.0
	for i in n:
		var f: float = lerpf(f0, f1, float(i) / float(maxi(1, n - 1)))
		phase = fmod(phase + f / float(SR), 1.0)
		out[i] = 1.0 if phase < 0.5 else -1.0
	return out

func _saw_sweep_wave(f0: float, f1: float, n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array(); out.resize(n)
	var phase := 0.0
	for i in n:
		var f: float = lerpf(f0, f1, float(i) / float(maxi(1, n - 1)))
		phase = fmod(phase + f / float(SR), 1.0)
		out[i] = 2.0 * phase - 1.0
	return out

func _white_noise(n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array(); out.resize(n)
	for i in n:
		out[i] = rng.randf_range(-1.0, 1.0)
	return out

## Filtre passe-bas 1 pôle très simple (moyenne mobile exponentielle) : donne
## un bruit "étouffé" façon souffle plutôt qu'un blanc pur (recette "stairs").
func _lowpass(x: PackedFloat32Array, alpha: float) -> PackedFloat32Array:
	var out := PackedFloat32Array(); out.resize(x.size())
	var y := 0.0
	for i in x.size():
		y += alpha * (x[i] - y)
		out[i] = y
	return out

# --- Enveloppes ------------------------------------------------------------
func _envelope_decay(n: int, tau_ratio: float = 5.0) -> PackedFloat32Array:
	var env := PackedFloat32Array(); env.resize(n)
	for i in n:
		env[i] = exp(-tau_ratio * float(i) / float(n))
	return env

## Montée-descente douce (0->1->0), pour les sons "swell" (soin, escalier).
func _envelope_swell(n: int) -> PackedFloat32Array:
	var env := PackedFloat32Array(); env.resize(n)
	for i in n:
		env[i] = sin(PI * float(i) / float(maxi(1, n - 1)))
	return env

# --- Assemblage / IO ------------------------------------------------------
func _apply_env(wave: PackedFloat32Array, env: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array(); out.resize(wave.size())
	for i in wave.size():
		out[i] = wave[i] * env[i % env.size()]
	return out

func _scale(arr: PackedFloat32Array, factor: float) -> PackedFloat32Array:
	var out := PackedFloat32Array(); out.resize(arr.size())
	for i in arr.size():
		out[i] = arr[i] * factor
	return out

func _mix2(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var n: int = maxi(a.size(), b.size())
	var out := PackedFloat32Array(); out.resize(n)
	for i in n:
		out[i] = (a[i] if i < a.size() else 0.0) + (b[i] if i < b.size() else 0.0)
	return out

func _concat(parts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p in parts:
		out.append_array(p)
	return out

func _silence(n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array(); out.resize(n)
	return out

func _normalize(samples: PackedFloat32Array, peak_db: float = -6.0) -> PackedFloat32Array:
	var peak: float = 0.0
	for v in samples:
		peak = maxf(peak, absf(v))
	if peak <= 0.0001:
		return samples
	var gain: float = db_to_linear(peak_db) / peak
	return _scale(samples, gain)

func _ms(v: float) -> int:
	return int(round(SR * v / 1000.0))

func _make_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SR
	stream.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var s: int = int(round(clampf(samples[i], -1.0, 1.0) * 32767.0))
		bytes.encode_s16(i * 2, s)
	stream.data = bytes
	return stream

func _save_sfx(id: String, samples: PackedFloat32Array) -> void:
	var stream := _make_stream(_normalize(samples, -6.0))
	stream.save_to_wav("res://assets/sfx/%s.wav" % id)
