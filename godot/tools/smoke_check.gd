extends Node
## Project-aware smoke and data-regression checks.

const GltfRuntime := preload("res://scripts/gym/gltf_runtime.gd")
const PROP_IDS := ["cooler", "chair", "toilet", "sink", "tv", "locker", "bag", "coat", "benchrest", "sauna", "shower"]
const QUEST_TYPES := ["sets", "shop", "prop", "combo", "clean_set", "perfects", "reps", "cardio", "both_cardio", "variety", "perfect_in_set", "earn", "mass_gain", "muscle", "buy"]
const MINIGAMES := ["timing", "bounce", "alternate", "climb", "lane", "simon", "rpm", "lockout", "pump", "target", "charge", "cadence", "pause", "mash", "pendulum"]

var _errors: PackedStringArray = []


func _ready() -> void:
	_check_resources()
	_check_font()
	_check_data()
	_check_i18n()
	_check_audio()
	_check_state_regressions()
	_check_level_progression()
	await _check_gym_scene()
	_finish()


func _check_resources() -> void:
	for path in [
		"res://scripts/autoload/game_state.gd",
		"res://scripts/yandex/yandex_sdk.gd",
		"res://scripts/player/player.gd",
		"res://scripts/gym/gym_world.gd",
		"res://scripts/ui/hud.gd",
		"res://scripts/ui/workout_overlay.gd",
		"res://scripts/autoload/audio.gd",
		"res://scripts/ui/shop_panel.gd",
		"res://scripts/ui/title_screen.gd",
		"res://scenes/boot/title.tscn",
		"res://scenes/gym/gym.tscn",
		"res://scenes/player/player.tscn",
		"res://data/levels.json",
	]:
		if not ResourceLoader.exists(path):
			_errors.append("MISSING %s" % path)
			continue
		var resource := load(path)
		if resource == null:
			_errors.append("LOAD_FAIL %s" % path)
		else:
			print("OK ", path, " ", resource.get_class())
	for path in [
		"res://assets/models/gym_env.glb",
		"res://assets/models/gym_stations.glb",
		"res://assets/models/fp_arms.glb",
	]:
		var node := GltfRuntime.load_node(path)
		if node == null:
			_errors.append("GLB_LOAD_FAIL %s" % path)
		else:
			print("OK_GLTF ", path, " ", node.name)
			node.free()


func _check_font() -> void:
	# Missing glyphs render as boxes (the default font had no ₽); every UI symbol must be covered.
	var font_path := str(ProjectSettings.get_setting("gui/theme/custom_font", ""))
	var font := load(font_path) as Font if font_path != "" else null
	if font == null:
		_errors.append("UI_FONT_MISSING %s" % font_path)
		return
	for ch in "₽→►×·«»—ЁёЖжЩщЪъЫы":
		if not font.has_char(ch.unicode_at(0)):
			_errors.append("UI_FONT_NO_GLYPH %s" % ch)


## Every Russian player-facing string needs an English entry with the same %-placeholders.
func _check_i18n() -> void:
	var sources: Dictionary = {}
	var literal := RegEx.create_from_string("\"((?:[^\"\\\\]|\\\\.)*)\"")
	# Cyrillic, or the ruble sign: English uses "$" for in-game cash.
	var cyr := RegEx.create_from_string("[А-Яа-яЁё₽]")
	for dir in ["res://scripts", "res://scenes"]:
		for path in _files_in(dir):
			if not (path.ends_with(".gd") or path.ends_with(".tscn")):
				continue
			var text := FileAccess.get_file_as_string(path)
			for m in literal.search_all(text):
				var s := m.get_string(1).replace("\\n", "\n").replace("\\\"", "\"")
				if cyr.search(s):
					sources[s] = path
	for id in GameState.stations:
		for key in ["name", "hint", "hint_touch"]:
			sources[str(GameState.stations[id].get(key, ""))] = "stations.json"
	for id in GameState.quest_defs:
		for key in ["title", "desc"]:
			sources[str(GameState.quest_defs[id].get(key, ""))] = "quests.json"
	for kind in GameState.quotes:
		for line in GameState.quotes[kind]:
			sources[str(line)] = "quotes.json"
	for id in GameState.levels:
		for key in ["name", "rule"]:
			sources[str(GameState.levels[id].get(key, ""))] = "levels.json"
	for id in GameState.shop:
		for key in ["name", "desc"]:
			sources[str(GameState.shop[id].get(key, ""))] = "shop.json"
	# No space flag: plain text like "+25% forever" must not look like "% f".
	var placeholder := RegEx.create_from_string("%[-+0#]*\\d*(?:\\.\\d+)?[sdfcxXo]")
	var missing: Array = []
	for s in sources:
		if str(s).strip_edges() == "" or not cyr.search(str(s)):
			continue
		if not Loc.en.has(s):
			missing.append(s)
			continue
		var t := str(Loc.en[s])
		if t.strip_edges() == "" or cyr.search(t):
			_errors.append("I18N_BAD_EN %s" % JSON.stringify(s))
		var a := placeholder.search_all(str(s)).map(func(x: RegExMatch) -> String: return x.get_string())
		var b := placeholder.search_all(t).map(func(x: RegExMatch) -> String: return x.get_string())
		if a != b:
			_errors.append("I18N_PLACEHOLDERS %s" % JSON.stringify(s))
	if not missing.is_empty():
		_errors.append("I18N_MISSING %d: %s" % [missing.size(), JSON.stringify(missing)])
	for s in Loc.en:
		if not sources.has(s):
			print("I18N_UNUSED ", JSON.stringify(s))
	# Russian mode must not fall back to the English table.
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("ru")
	if tr("ЖМИ") != "ЖМИ":
		_errors.append("I18N_RU_FALLS_BACK_TO_EN")
	TranslationServer.set_locale("en")
	if tr("ЖМИ") == "ЖМИ":
		_errors.append("I18N_EN_NOT_APPLIED")
	TranslationServer.set_locale(before)


func _files_in(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_files_in(dir.path_join(d)))
	return out


func _check_data() -> void:
	if GameState.stations.is_empty():
		_errors.append("STATIONS_EMPTY")
	for id in GameState.stations:
		var station: Dictionary = GameState.stations[id]
		if str(station.get("id", "")) != str(id):
			_errors.append("STATION_ID_MISMATCH %s" % id)
		if str(station.get("minigame", "")) not in MINIGAMES:
			_errors.append("STATION_BAD_MINIGAME %s" % id)
		for key in ["energy", "reps", "period", "green", "perfect", "gain"]:
			if float(station.get(key, 0.0)) <= 0.0:
				_errors.append("STATION_BAD_%s %s" % [key.to_upper(), id])
		# Yandex mobile: keyboard hints need a touch variant without keys.
		if _mentions_keys(str(station.get("hint", ""))):
			var touch_hint := str(station.get("hint_touch", ""))
			if touch_hint.is_empty() or _mentions_keys(touch_hint):
				_errors.append("STATION_NO_TOUCH_HINT %s" % id)
	for id in GameState.quest_defs:
		var quest: Dictionary = GameState.quest_defs[id]
		var quest_type := str(quest.get("type", ""))
		if quest_type not in QUEST_TYPES:
			_errors.append("QUEST_BAD_TYPE %s" % id)
		if int(quest.get("target", 0)) <= 0:
			_errors.append("QUEST_BAD_TARGET %s" % id)
		var station_id := str(quest.get("station", ""))
		if station_id != "" and not GameState.stations.has(station_id):
			_errors.append("QUEST_BAD_STATION %s=%s" % [id, station_id])
		if quest_type == "prop" and str(quest.get("prop", "")) not in PROP_IDS:
			_errors.append("QUEST_BAD_PROP %s" % id)
	for id in GameState.shop:
		var item: Dictionary = GameState.shop[id]
		if int(item.get("price", -1)) < 0:
			_errors.append("SHOP_BAD_PRICE %s" % id)
		if str(item.get("kind", "")) not in ["gear", "consumable"]:
			_errors.append("SHOP_BAD_KIND %s" % id)
	if GameState.levels.size() != 6:
		_errors.append("LEVEL_COUNT expected=6 actual=%d" % GameState.levels.size())
	var previous_mass := -1.0
	var previous_period := 2.0
	var previous_cash := 0.0
	for level in range(1, 7):
		var data := GameState.level_data(level)
		if data.is_empty() or int(data.get("id", 0)) != level:
			_errors.append("LEVEL_BAD_ID %d" % level)
			continue
		var unlock_mass := float(data.get("unlock_mass", -1.0))
		if unlock_mass <= previous_mass:
			_errors.append("LEVEL_UNLOCK_ORDER %d" % level)
		previous_mass = unlock_mass
		if str(data.get("name", "")).is_empty() or str(data.get("rule", "")).is_empty():
			_errors.append("LEVEL_TEXT_EMPTY %d" % level)
		var period_scale := float(data.get("period_scale", 0.0))
		var cash_scale := float(data.get("cash_scale", 0.0))
		if period_scale <= 0.0 or period_scale > previous_period:
			_errors.append("LEVEL_PERIOD_ORDER %d" % level)
		if cash_scale < previous_cash:
			_errors.append("LEVEL_CASH_ORDER %d" % level)
		if float(data.get("window_scale", 0.0)) <= 0.0 or float(data.get("gain_scale", 0.0)) <= 0.0:
			_errors.append("LEVEL_BAD_SCALE %d" % level)
		var accent := str(data.get("accent", ""))
		if not accent.begins_with("#") or accent.length() != 7:
			_errors.append("LEVEL_BAD_ACCENT %d" % level)
		previous_period = period_scale
		previous_cash = cash_scale
		if level > 1 and not is_equal_approx(unlock_mass, GameState.GYM_TIER_KG[level - 2]):
			_errors.append("LEVEL_THRESHOLD_MISMATCH %d" % level)


func _mentions_keys(text: String) -> bool:
	var low := text.to_lower()
	for word in ["пробел", "q w e r", "a / d", "(a)", "(d)", "wasd"]:
		if word in low:
			return true
	return false


## Every id the game asks for must exist in the synthesised bank, the bank must
## hold real samples, and the ad/tab mute must be reason-counted (Yandex: silence
## while an ad is up, sound back only when every reason is gone).
func _check_audio() -> void:
	var wanted := [
		"click", "back", "deny", "perfect", "good", "miss", "combo", "clank", "plate",
		"rack", "step", "water", "steam", "whoosh", "coin", "quest", "setdone",
		"setfail", "levelup", "lowenergy",
	]
	for id in wanted:
		var stream: Variant = Audio._bank.get(id)
		if stream == null:
			_errors.append("AUDIO_MISSING %s" % id)
			continue
		var wav := stream as AudioStreamWAV
		if wav == null or wav.data.size() < 512:
			_errors.append("AUDIO_EMPTY %s" % id)
	if AudioServer.get_bus_index("SFX") < 0 or AudioServer.get_bus_index("Music") < 0:
		_errors.append("AUDIO_BUSES_MISSING")
	# Two overlapping reasons: the first release must not bring the sound back.
	Audio.hold_mute("ad")
	Audio.hold_mute("hidden")
	Audio.release_mute("ad")
	if not Audio.is_muted():
		_errors.append("AUDIO_MUTE_NOT_REASON_COUNTED")
	Audio.release_mute("hidden")
	if Audio.is_muted():
		_errors.append("AUDIO_MUTE_STUCK")
	if AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")) and Audio.sfx_on:
		_errors.append("AUDIO_BUS_STILL_MUTED")
	# Toggles have to survive a save round trip.
	var sfx_before: bool = Audio.sfx_on
	Audio.toggle_sfx()
	if GameState.sfx_on == sfx_before:
		_errors.append("AUDIO_TOGGLE_NOT_PERSISTED")
	Audio.toggle_sfx()


func _check_state_regressions() -> void:
	var state: Node = (load("res://scripts/autoload/game_state.gd") as GDScript).new()
	state.stations = GameState.stations
	state.shop = {"belt": {"id": "belt", "price": 120, "kind": "gear"}}
	state.quest_defs = GameState.quest_defs
	state.from_dict({
		"v": 1,
		"stats": {"chest": 12.0, "arms": 8.0, "back": 6.0, "legs": 10.0, "cardio": 4.0},
		"active_quests": [{"id": "steam_bath", "type": "prop", "target": 2, "progress": 0}],
	})
	if not is_equal_approx(state.chest, 12.0) or str(state.active_quests[0].get("prop", "")) != "sauna":
		_errors.append("REGRESSION_LEGACY_SAVE_MIGRATION")
	var prop_quest: Dictionary = state._make_quest("steam_bath")
	if str(prop_quest.get("prop", "")) != "sauna":
		_errors.append("REGRESSION_QUEST_PROP_LOST")
	prop_quest["target"] = 2
	state.active_quests = [prop_quest]
	state._quest_on_prop("cooler")
	if int(prop_quest.get("progress", 0)) != 0:
		_errors.append("REGRESSION_WRONG_PROP_COUNTED")
	state._quest_on_prop("sauna")
	if int(prop_quest.get("progress", 0)) != 1:
		_errors.append("REGRESSION_RIGHT_PROP_IGNORED")
	var clean_quest := {"id": "clean2", "type": "clean_set", "station": "", "target": 3, "progress": 1}
	state.active_quests = [clean_quest]
	state.note_set("bench", 0, 1, 3, false)
	if int(clean_quest.get("progress", 0)) != 0:
		_errors.append("REGRESSION_CLEAN_STREAK_NOT_RESET")
	state.active_quests = [
		{"id": "reps30", "title": "Тридцатка", "type": "reps", "station": "", "target": 30, "progress": 0},
		{"id": "bench3", "title": "Жимовая серия", "type": "sets", "station": "bench", "target": 3, "progress": 1},
	]
	# quest_hint_for translates, and the boot locale follows the host machine — pin
	# Russian so this asserts the shadowing rule, not the developer's system language.
	var hint_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("ru")
	var station_hint := str(state.quest_hint_for("bench"))
	TranslationServer.set_locale(hint_locale)
	if not station_hint.begins_with("Жимовая серия"):
		_errors.append("REGRESSION_STATION_QUEST_HINT_SHADOWED")
	state.money = 200
	state.inv = {"belt": true}
	if state.buy("belt") or state.money != 200:
		_errors.append("REGRESSION_GEAR_REPURCHASE")
	state.free()


func _check_level_progression() -> void:
	var state: Node = (load("res://scripts/autoload/game_state.gd") as GDScript).new()
	state.stations = GameState.stations
	state.levels = GameState.levels
	state.quest_defs = {}
	state.chest = 0.0
	state.arms = 0.0
	state.back = 0.0
	state.legs = 0.0
	state.cardio = 0.0
	state.energy = 100.0
	state.fatigue = 0.0
	state.hygiene = 100.0
	state.recovery = 80.0
	var visited: Array[int] = [state.gym_level()]
	var repetitions := 0
	while state.gym_level() < 6 and repetitions < 5000:
		var picked := ""
		var lowest := INF
		for id in state.stations:
			if not state.can_unlock(str(id)):
				continue
			var muscle := str(state.stations[id].get("muscle", ""))
			var value: float = float(state.muscle_value(muscle))
			if value < lowest:
				lowest = value
				picked = str(id)
		if picked.is_empty():
			break
		state.apply_rep(picked, "perfect")
		repetitions += 1
		var level: int = state.gym_level()
		if level != visited[-1]:
			visited.append(level)
	if state.gym_level() != 6:
		_errors.append("LEVEL_6_UNREACHABLE mass=%.2f reps=%d" % [state.mass(), repetitions])
	if visited != [1, 2, 3, 4, 5, 6]:
		_errors.append("LEVEL_SEQUENCE_BAD %s" % str(visited))
	else:
		print("OK_LEVEL_PLAYTHROUGH reps=", repetitions, " mass=", snappedf(state.mass(), 0.01), " levels=", visited)
	state.free()


func _check_gym_scene() -> void:
	var packed := load("res://scenes/gym/gym.tscn") as PackedScene
	if packed == null:
		_errors.append("GYM_SCENE_NULL")
		return
	var gym := packed.instantiate()
	add_child(gym)
	for _frame in 8:
		await get_tree().physics_frame
	var player := gym.get_node_or_null("Player") as CharacterBody3D
	if player == null:
		_errors.append("PLAYER_MISSING")
	elif not player.is_on_floor():
		_errors.append("PLAYER_NOT_ON_FLOOR")
	var station_nodes: Array[Node3D] = []
	_collect_named(gym.get_node_or_null("StationsMount"), "EMP_Station", station_nodes)
	if station_nodes.size() != GameState.stations.size() + 1:
		_errors.append("STATION_COUNT scene=%d data_plus_shop=%d" % [station_nodes.size(), GameState.stations.size() + 1])
	for node in station_nodes:
		var id := str(node.get_meta("station_id", ""))
		if id != "shop" and not GameState.stations.has(id):
			_errors.append("SCENE_BAD_STATION %s=%s" % [node.name, id])
	var workout := gym.get_node_or_null("Workout")
	get_tree().paused = true
	if player and player.can_process():
		_errors.append("REGRESSION_PLAYER_RUNS_WHILE_PAUSED")
	if workout and workout.can_process():
		_errors.append("REGRESSION_WORKOUT_RUNS_WHILE_PAUSED")
	var hud := gym.get_node_or_null("HUD")
	if hud and not hud.can_process():
		_errors.append("REGRESSION_HUD_FROZEN_WHILE_PAUSED")
	get_tree().paused = false
	if workout:
		var old_inv: Dictionary = GameState.inv.duplicate(true)
		GameState.inv["gloves"] = true
		workout.set("_sid", "dumbbell")
		workout.set("_gloves_used", false)
		if str(workout.call("_grade_after_gear", "miss")) != "good":
			_errors.append("REGRESSION_GLOVES_FIRST_MISS")
		if str(workout.call("_grade_after_gear", "miss")) != "miss":
			_errors.append("REGRESSION_GLOVES_SECOND_MISS")
		GameState.inv = old_inv
	else:
		_errors.append("WORKOUT_MISSING")
	gym.queue_free()
	await get_tree().process_frame


func _collect_named(node: Node, prefix: String, output: Array[Node3D]) -> void:
	if node == null:
		return
	if node is Node3D and node.name.begins_with(prefix):
		output.append(node)
	for child in node.get_children():
		_collect_named(child, prefix, output)


func _finish() -> void:
	var file := FileAccess.open("res://tools/smoke_result.txt", FileAccess.WRITE)
	if not _errors.is_empty():
		for error in _errors:
			push_error(error)
			if file:
				file.store_line(error)
		if file:
			file.store_line("SMOKE_FAIL")
		get_tree().quit(1)
		return
	print("SMOKE_PASS")
	if file:
		file.store_line("SMOKE_PASS")
	get_tree().quit(0)
