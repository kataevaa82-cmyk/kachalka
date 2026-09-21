extends Node
## Procedural audio. Every sound is synthesised into an AudioStreamWAV at boot:
## no binary assets, no import step, no third-party licences, ~0 bytes in the pck.
##
## Yandex requirement: the game must be silent while an ad is on screen and while
## the tab is hidden. Both are mute *reasons* here — sound returns only when every
## reason is gone (same pattern as the SDK pause bridge).

const SR := 22050
## The loops are bass-heavy and long; half the rate is inaudible here and halves
## both the synthesis time (a boot hitch on web) and the memory they sit in.
const LOOP_SR := 11025
const SFX_VOICES := 8

## Four bars of four beats. Tails that run past the last beat wrap back to the
## loop head when mixed, so the loop point has no seam.
const MUSIC_BPM := 124.0
const MUSIC_BEATS := 16

## Single source of truth for the two toggles; GameState only serialises them.
## The setters run before _ready when a save is restored, so every one of them
## has to survive a half-built node.
var sfx_on: bool = true:
	set(v):
		sfx_on = v
		_apply_volumes()
var music_on: bool = true:
	set(v):
		music_on = v
		_apply_volumes()
		if _music_player == null:
			return
		if music_on:
			_start_music()
		else:
			_music_player.stop()
			_ambience_player.stop()

var _bank: Dictionary = {}
var _sfx_bus: int = -1
var _music_bus: int = -1
var _voices: Array[AudioStreamPlayer] = []
var _voice_i: int = 0
var _music_player: AudioStreamPlayer
var _ambience_player: AudioStreamPlayer
var _music_wanted: bool = false
var _mute_reasons: Dictionary = {}
var _rng := RandomNumberGenerator.new()
## Sample rate the synthesis primitives are currently writing at. Building is
## single-threaded and strictly sequential, so one field is enough to switch the
## loops to LOOP_SR without threading a rate argument through every helper.
var _rate: int = SR


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 0x5EED_1DEA
	_make_buses()
	_build_sfx_ui()
	for _i in SFX_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_voices.append(p)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music_player)
	_ambience_player = AudioStreamPlayer.new()
	_ambience_player.bus = "Music"
	_ambience_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ambience_player)
	# GameState is an earlier autoload, so its save is already restored here.
	sfx_on = GameState.sfx_on
	music_on = GameState.music_on
	# Everything past the UI beeps is the expensive part of the bank. Build it
	# after the title screen has called LoadingAPI.ready(), one slice per frame,
	# so neither the platform handshake nor a single frame takes the whole cost.
	_build_sfx_reps.call_deferred()
	_apply_volumes()


func _make_buses() -> void:
	# Runtime buses instead of a default_bus_layout.tres: one less binary resource
	# to keep in sync, and the layout is only ever these three.
	AudioServer.add_bus()
	_sfx_bus = AudioServer.bus_count - 1
	AudioServer.set_bus_name(_sfx_bus, "SFX")
	AudioServer.set_bus_send(_sfx_bus, "Master")
	AudioServer.add_bus()
	_music_bus = AudioServer.bus_count - 1
	AudioServer.set_bus_name(_music_bus, "Music")
	AudioServer.set_bus_send(_music_bus, "Master")


# ---------------------------------------------------------------- public API

## `id` must exist in the bank; unknown ids are ignored so callers stay cheap.
func play(id: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if not sfx_on or is_muted():
		return
	var stream: Variant = _bank.get(id)
	if stream == null or _voices.is_empty():
		return
	var p: AudioStreamPlayer = _voices[_voice_i]
	_voice_i = (_voice_i + 1) % _voices.size()
	p.stream = stream
	p.pitch_scale = clampf(pitch, 0.4, 2.4)
	p.volume_db = volume_db
	p.play()


## Rep feedback: combo lifts the pitch so a streak audibly climbs.
func play_rep(grade: String, combo: int) -> void:
	match grade:
		"perfect":
			play("perfect", 1.0 + minf(float(combo), 12.0) * 0.022)
		"good":
			play("good", 1.0 + minf(float(combo), 8.0) * 0.012)
		_:
			play("miss")


func start_music() -> void:
	_music_wanted = true
	_start_music()


func stop_music() -> void:
	_music_wanted = false
	if _music_player:
		_music_player.stop()
	if _ambience_player:
		_ambience_player.stop()


## Reason-counted mute: ads and a hidden tab can overlap.
func hold_mute(reason: String) -> void:
	_mute_reasons[reason] = true
	_apply_volumes()


func release_mute(reason: String) -> void:
	_mute_reasons.erase(reason)
	_apply_volumes()


func is_muted() -> bool:
	return not _mute_reasons.is_empty()


func toggle_sfx() -> void:
	sfx_on = not sfx_on
	GameState.sfx_on = sfx_on
	if sfx_on:
		play("click")


func toggle_music() -> void:
	music_on = not music_on
	GameState.music_on = music_on


func _start_music() -> void:
	if not music_on or not _music_wanted or _music_player == null:
		return
	if _music_player.stream != null and not _music_player.playing:
		_music_player.play()
	if _ambience_player.stream != null and not _ambience_player.playing:
		_ambience_player.volume_db = -14.0
		_ambience_player.play()


func _apply_volumes() -> void:
	if _sfx_bus < 0:
		return
	var muted := is_muted()
	AudioServer.set_bus_mute(_sfx_bus, muted or not sfx_on)
	AudioServer.set_bus_mute(_music_bus, muted or not music_on)
	AudioServer.set_bus_volume_db(_sfx_bus, -4.0)
	AudioServer.set_bus_volume_db(_music_bus, -11.0)


# ------------------------------------------------------------------- the bank

## Only the sounds the title screen can reach. The whole bank used to be built
## here, which cost ~130 ms on desktop and several times that in a phone browser
## — all of it before the first frame was drawn. play() ignores ids that are not
## in the bank yet, so the rest builds a slice at a time once boot is over.
func _build_sfx_ui() -> void:
	_bank["click"] = _wav(_tone(0.055, 900.0, 1240.0, 0.35, 0.004, 3.0, 0.32))
	_bank["back"] = _wav(_tone(0.075, 640.0, 380.0, 0.30, 0.004, 3.0, 0.30))
	_bank["deny"] = _wav(_seq([
		[0.0, _tone(0.09, 230.0, 210.0, 0.55, 0.004, 2.4, 0.34)],
		[0.10, _tone(0.11, 185.0, 150.0, 0.55, 0.004, 2.4, 0.34)],
	]))


func _build_sfx_reps() -> void:
	_bank["perfect"] = _wav(_seq([
		[0.0, _tone(0.09, 880.0, 880.0, 0.22, 0.003, 3.4, 0.34)],
		[0.055, _tone(0.20, 1318.5, 1318.5, 0.18, 0.003, 2.8, 0.30)],
		[0.055, _noise(0.10, 5200.0, 2600.0, 0.002, 4.0, 0.07)],
	]))
	_bank["good"] = _wav(_tone(0.12, 587.3, 587.3, 0.30, 0.004, 3.2, 0.30))
	_bank["miss"] = _wav(_seq([
		[0.0, _tone(0.20, 190.0, 88.0, 0.85, 0.003, 2.2, 0.34)],
		[0.0, _noise(0.09, 900.0, 0.0, 0.002, 3.0, 0.14)],
	]))
	_bank["combo"] = _wav(_tone(0.07, 1046.5, 1568.0, 0.20, 0.003, 3.6, 0.24))
	_build_sfx_world.call_deferred()


func _build_sfx_world() -> void:
	# Iron
	_bank["clank"] = _wav(_metal(0.34, [1180.0, 1867.0, 2530.0, 3310.0], 0.30))
	_bank["plate"] = _wav(_seq([
		[0.0, _metal(0.46, [520.0, 803.0, 1190.0, 1610.0], 0.30)],
		[0.0, _noise(0.10, 1600.0, 240.0, 0.002, 3.4, 0.12)],
	]))
	_bank["rack"] = _wav(_seq([
		[0.0, _metal(0.30, [640.0, 1010.0, 1480.0], 0.26)],
		[0.09, _metal(0.36, [600.0, 950.0, 1390.0], 0.20)],
	]))
	# World
	_bank["step"] = _wav(_norm(_noise(0.085, 720.0, 90.0, 0.002, 4.5, 1.0), 0.32))
	_bank["water"] = _wav(_norm(_noise(0.85, 4200.0, 950.0, 0.10, 1.1, 1.0), 0.30))
	_bank["steam"] = _wav(_norm(_noise(1.10, 2600.0, 500.0, 0.22, 0.9, 1.0), 0.26))
	_bank["whoosh"] = _wav(_norm(_noise(0.26, 2200.0, 380.0, 0.05, 2.6, 1.0), 0.34))
	_build_sfx_progress.call_deferred()


func _build_sfx_progress() -> void:
	# Economy and progress
	_bank["coin"] = _wav(_seq([
		[0.0, _tone(0.07, 1568.0, 1568.0, 0.25, 0.002, 3.6, 0.28)],
		[0.045, _tone(0.16, 2093.0, 2093.0, 0.20, 0.002, 3.0, 0.24)],
	]))
	_bank["quest"] = _wav(_metal(0.90, [1046.5, 1567.9, 2093.0, 3136.0], 0.22))
	_bank["setdone"] = _wav(_arp([523.3, 784.0, 1046.5], 0.11, 0.26, 0.30))
	_bank["setfail"] = _wav(_arp([392.0, 293.7], 0.16, 0.34, 0.30))
	_bank["levelup"] = _wav(_arp([523.3, 659.3, 784.0, 1046.5, 1318.5], 0.10, 0.34, 0.32))
	_bank["lowenergy"] = _wav(_seq([
		[0.0, _tone(0.10, 440.0, 440.0, 0.40, 0.004, 3.0, 0.26)],
		[0.16, _tone(0.14, 370.0, 330.0, 0.40, 0.004, 3.0, 0.26)],
	]))
	_build_music_loop.call_deferred()


func _build_music_loop() -> void:
	_rate = LOOP_SR
	_bank["music"] = _wav(_music(), true)
	_rate = SR
	_music_player.stream = _bank["music"]
	_build_ambience_loop.call_deferred()


func _build_ambience_loop() -> void:
	_rate = LOOP_SR
	_bank["ambience"] = _wav(_seamless(_ambience(), 0.05), true)
	_rate = SR
	_ambience_player.stream = _bank["ambience"]
	_start_music()


# ------------------------------------------------------------------ synthesis

## Sine stack with `harm` of second/third harmonic, exponential decay of `curve`.
func _tone(dur: float, f0: float, f1: float, harm: float, attack: float, curve: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * _rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(_rate)
		var u := float(i) / float(n)
		var f: float = lerpf(f0, f1, u)
		phase += TAU * f / float(_rate)
		var s := sin(phase) + harm * sin(phase * 2.0) + harm * 0.4 * sin(phase * 3.0)
		out[i] = s * vol * _envelope(t, dur, attack, curve)
	return out


## One-pole band-limited noise: LP(hi) minus LP(lo) gives a usable band-pass.
func _noise(dur: float, hi: float, lo: float, attack: float, curve: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * _rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var a_hi := 1.0 - exp(-TAU * hi / float(_rate))
	var a_lo := 1.0 - exp(-TAU * maxf(lo, 1.0) / float(_rate))
	var y_hi := 0.0
	var y_lo := 0.0
	for i in n:
		var t := float(i) / float(_rate)
		var x := _rng.randf_range(-1.0, 1.0)
		y_hi += a_hi * (x - y_hi)
		y_lo += a_lo * (x - y_lo)
		var s := y_hi - (y_lo if lo > 0.0 else 0.0)
		out[i] = s * vol * _envelope(t, dur, attack, curve)
	return out


## Inharmonic partials plus a click transient: reads as struck metal.
func _metal(dur: float, partials: Array, vol: float) -> PackedFloat32Array:
	var n := int(dur * _rate)
	var out := PackedFloat32Array()
	out.resize(n)
	for pi in range(partials.size()):
		var f: float = float(partials[pi])
		var amp: float = vol / (float(pi) * 0.85 + 1.0)
		var decay: float = 3.0 + float(pi) * 1.6
		var phase := 0.0
		for i in n:
			var t := float(i) / float(_rate)
			phase += TAU * f / float(_rate)
			out[i] += sin(phase) * amp * _envelope(t, dur, 0.0015, decay)
	return out


func _arp(notes: Array, step: float, tail: float, vol: float) -> PackedFloat32Array:
	var parts: Array = []
	for i in range(notes.size()):
		var f: float = float(notes[i])
		var dur: float = tail if i == notes.size() - 1 else step * 1.8
		parts.append([float(i) * step, _tone(dur, f, f, 0.28, 0.004, 3.0, vol)])
	return _seq(parts)


## Band-passed noise comes out far quieter than a sine of the same nominal volume
## (the two one-poles cancel most of the energy), and the exact loss moves with the
## cutoffs. Scaling to a target peak keeps those sounds audible whatever the filter.
func _norm(buf: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var top := 0.0
	for v in buf:
		top = maxf(top, absf(v))
	if top < 0.0001:
		return buf
	var k := peak / top
	for i in buf.size():
		buf[i] *= k
	return buf


func _envelope(t: float, dur: float, attack: float, curve: float) -> float:
	if t < attack:
		return t / maxf(attack, 0.0001)
	var u := (t - attack) / maxf(dur - attack, 0.0001)
	return exp(-curve * u) * (1.0 - u)


## Mixes [offset_seconds, buffer] pairs into one buffer.
func _seq(parts: Array) -> PackedFloat32Array:
	var total := 0
	for part in parts:
		var off: int = int(float(part[0]) * _rate)
		var buf: PackedFloat32Array = part[1]
		total = maxi(total, off + buf.size())
	var out := PackedFloat32Array()
	out.resize(total)
	for part in parts:
		var off: int = int(float(part[0]) * _rate)
		var buf: PackedFloat32Array = part[1]
		for i in buf.size():
			out[off + i] += buf[i]
	return out


## Four-on-the-floor gym loop: kick, off-beat hat, a minor bass figure and a pad.
## Peak the whole loop lands on after mixing; anything above this would clip.
const MUSIC_PEAK := 0.62


func _music() -> PackedFloat32Array:
	var beat := 60.0 / MUSIC_BPM
	var n := int(round(beat * float(MUSIC_BEATS) * float(_rate)))
	var out := PackedFloat32Array()
	out.resize(n)
	var bass_notes := [55.0, 55.0, 65.41, 55.0, 49.0, 55.0, 73.42, 65.41]
	var pad_chords := [[110.0, 130.81, 164.81], [98.0, 123.47, 146.83]]
	# Build each voice once and reuse it: sixteen kicks are the same sixteen samples.
	var kick := _kick()
	var hat := _hat()
	var ghost := _norm(_noise(0.16, 7000.0, 3200.0, 0.002, 3.0, 1.0), 0.10)
	for b in MUSIC_BEATS:
		var at := float(b) * beat
		out = _mix_into(out, kick, at)
		out = _mix_into(out, hat, at + beat * 0.5)
		if b % 4 == 2:
			out = _mix_into(out, ghost, at + beat * 0.75)
	for i in range(MUSIC_BEATS * 2):
		var f: float = float(bass_notes[i % bass_notes.size()])
		out = _mix_into(out, _tone(beat * 0.42, f, f, 0.55, 0.006, 2.6, 0.17), float(i) * beat * 0.5)
	for bar in 4:
		var chord: Array = pad_chords[bar % pad_chords.size()]
		for f in chord:
			out = _mix_into(out, _tone(beat * 3.6, float(f), float(f), 0.10, 0.35, 0.9, 0.045), float(bar) * beat * 4.0)
	return _norm(out, MUSIC_PEAK)


func _kick() -> PackedFloat32Array:
	return _seq([
		[0.0, _tone(0.19, 118.0, 44.0, 0.05, 0.002, 3.2, 0.42)],
		[0.0, _noise(0.02, 2400.0, 0.0, 0.001, 4.0, 0.07)],
	])


func _hat() -> PackedFloat32Array:
	return _norm(_noise(0.055, 9000.0, 4200.0, 0.001, 5.0, 1.0), 0.13)


## Quiet room tone under the music: low hum plus a wide noise floor.
func _ambience() -> PackedFloat32Array:
	var dur := 4.0
	var n := int(dur * _rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var a := 1.0 - exp(-TAU * 420.0 / float(_rate))
	var y := 0.0
	for i in n:
		var t := float(i) / float(_rate)
		# Whole cycles over the loop length, so the seam is silent.
		var hum := sin(TAU * 50.0 * t) * 0.05 + sin(TAU * 100.0 * t) * 0.018
		var wobble := 1.0 + 0.25 * sin(TAU * 0.5 * t)
		y += a * (_rng.randf_range(-1.0, 1.0) - y)
		out[i] = hum * wobble + y * 0.055
	return _norm(out, 0.30)


## Crossfades the tail over the head and drops it, so the loop point has no step.
## Tones are written in whole cycles and need this; filtered noise does.
func _seamless(buf: PackedFloat32Array, fade_sec: float) -> PackedFloat32Array:
	var n := buf.size()
	var f := mini(int(fade_sec * float(_rate)), n / 4)
	if f < 2:
		return buf
	for i in f:
		var w := float(i) / float(f)
		buf[i] = buf[i] * w + buf[n - f + i] * (1.0 - w)
	buf.resize(n - f)
	return buf


## Returns the mixed buffer rather than writing through the argument: PackedArrays
## are copy-on-write, so a caller cannot rely on seeing a callee's mutation.
func _mix_into(dst: PackedFloat32Array, src: PackedFloat32Array, at_sec: float) -> PackedFloat32Array:
	var off := int(at_sec * float(_rate))
	var n := dst.size()
	for i in src.size():
		# Wrap so a tail that runs past the last beat lands back at the loop head.
		dst[(off + i) % n] += src[i]
	return dst


func _wav(buf: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var n := buf.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v := int(round(clampf(buf[i], -1.0, 1.0) * 32767.0))
		data.encode_s16(i * 2, v)
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = _rate
	s.stereo = false
	s.data = data
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = n
	return s
