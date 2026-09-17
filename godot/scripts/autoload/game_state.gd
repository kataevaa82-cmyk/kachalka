extends Node
## Persistable gym state. Geometry never lives here.

signal stats_changed
signal energy_changed
signal money_changed
signal vitals_changed
signal quote_emitted(text: String, kind: String)
signal set_finished(station_id: String, perfects: int, misses: int)
signal quests_changed
signal quest_completed(title: String, reward: String)
signal level_unlocked(level: int, title: String, rule: String)

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 3

var stations: Dictionary = {}
var shop: Dictionary = {}
var quotes: Dictionary = {}
var quest_defs: Dictionary = {}
var levels: Dictionary = {}

var chest: float = 0.0
var arms: float = 0.0
var back: float = 0.0
var legs: float = 0.0
var cardio: float = 0.0
var energy: float = 100.0
var fatigue: float = 0.0
var hygiene: float = 100.0
var recovery: float = 80.0
var money: int = 0
var total_reps: int = 0
var combo: int = 0
var combo_best: int = 0
var sets_since_ad: int = 0
var inv: Dictionary = {}

var protein_boost_left: float = 0.0
var preworkout_left: float = 0.0
var _energy_acc: float = 0.0
var in_set: bool = false
var paused: bool = false
var active_quests: Array = []
var quests_done: int = 0
var _quest_seen: Dictionary = {}
var _prop_cd: Dictionary = {}
var last_saved_at: int = 0
var sfx_on: bool = true
var music_on: bool = true
var _local_save_loaded: bool = false
## A cloud save that landed mid-set: applying it would swap the numbers out from
## under the player, so it waits for the set to end.
var _deferred_cloud: Dictionary = {}


func _ready() -> void:
	stations = _load_json("res://data/stations.json")
	shop = _load_json("res://data/shop.json")
	quotes = _load_json("res://data/quotes.json")
	quest_defs = _load_json("res://data/quests.json")
	levels = _load_json("res://data/levels.json")
	load_game()
	_ensure_quests()
	YandexSDK.cloud_loaded.connect(_on_cloud_loaded)


func _process(delta: float) -> void:
	if paused or in_set:
		return
	if protein_boost_left > 0.0:
		protein_boost_left = max(0.0, protein_boost_left - delta)
	if preworkout_left > 0.0:
		preworkout_left = max(0.0, preworkout_left - delta)
	if energy < 100.0:
		_energy_acc += delta
		var regen_every := 8.0
		if recovery > 70.0:
			regen_every = 5.5
		elif fatigue > 70.0:
			regen_every = 11.0
		if hygiene < 25.0:
			regen_every += 3.0
		if _energy_acc >= regen_every:
			_energy_acc = 0.0
			add_energy(1.0)
	# Natural wind-down while walking the hall
	if fatigue > 0.0:
		add_fatigue(-delta * (0.22 + 0.18 * (recovery / 100.0)))
	if recovery < 100.0 and fatigue < 55.0:
		add_recovery(delta * 0.12)
	if hygiene < 100.0 and fatigue < 20.0:
		add_hygiene(delta * 0.05)
	elif fatigue > 50.0:
		add_hygiene(-delta * 0.06)
	for k in _prop_cd.keys():
		_prop_cd[k] = max(0.0, float(_prop_cd[k]) - delta)


## Bodyweight in kg. Starts ~62. Caps near 145 with a full physique.
## Diminishing returns per muscle so 6 gyms (this hall + 5 more) stay meaningful.
## Legs carry more kilos than arms; cardio is density, not bulk.
## Balance bonus if you don't skip a group.
const BASE_KG := 62.0
const MUSCLE_CAP := 160.0
## Next gym unlocks at these kg. Index 0 = this hall. Five more halls after.
const GYM_TIER_KG: Array[float] = [70.0, 82.0, 96.0, 112.0, 128.0]


func _kg_from(stat: float, max_kg: float) -> float:
	return max_kg * (1.0 - exp(-stat / 52.0))


func mass() -> float:
	var c := _kg_from(chest, 22.0)
	var a := _kg_from(arms, 14.0)
	var b := _kg_from(back, 20.0)
	var l := _kg_from(legs, 30.0)
	var k := _kg_from(cardio, 8.0)
	var avg := (chest + arms + back + legs) * 0.25
	var mn := minf(chest, minf(arms, minf(back, legs)))
	var balance := 1.0
	if avg > 1.0:
		balance = 1.0 + 0.12 * clampf(mn / avg, 0.0, 1.0)
	return BASE_KG + (c + a + b + l + k) * balance


func mass_score() -> int:
	return int(round(mass() * 10.0))


func gym_level() -> int:
	var m := mass()
	var lvl := 1
	for t in GYM_TIER_KG:
		if m + 0.001 >= t:
			lvl += 1
		else:
			break
	return mini(lvl, 1 + GYM_TIER_KG.size())


func next_gym_kg() -> float:
	var i := gym_level() - 1
	if i < 0 or i >= GYM_TIER_KG.size():
		return 0.0
	return GYM_TIER_KG[i]


func muscle_value(key: String) -> float:
	match key:
		"chest":
			return chest
		"arms":
			return arms
		"back":
			return back
		"legs":
			return legs
		"cardio":
			return cardio
		_:
			return 0.0


func add_muscle(key: String, amount: float) -> void:
	var previous_level := gym_level()
	match key:
		"chest":
			chest = clampf(chest + amount, 0.0, MUSCLE_CAP)
		"arms":
			arms = clampf(arms + amount, 0.0, MUSCLE_CAP)
		"back":
			back = clampf(back + amount, 0.0, MUSCLE_CAP)
		"legs":
			legs = clampf(legs + amount, 0.0, MUSCLE_CAP)
		"cardio":
			cardio = clampf(cardio + amount, 0.0, MUSCLE_CAP)
	var current_level := gym_level()
	stats_changed.emit()
	if current_level > previous_level:
		level_unlocked.emit(current_level, level_name(current_level), level_rule(current_level))
		Audio.play("levelup")


func level_data(level: int = -1) -> Dictionary:
	var wanted := gym_level() if level < 1 else level
	var value: Variant = levels.get(str(wanted), {})
	return value if value is Dictionary else {}


func level_name(level: int = -1) -> String:
	return tr(str(level_data(level).get("name", tr("Уровень %d") % (gym_level() if level < 1 else level))))


func level_rule(level: int = -1) -> String:
	return tr(str(level_data(level).get("rule", "Базовый режим")))


func level_period_scale() -> float:
	return clampf(float(level_data().get("period_scale", 1.0)), 0.55, 1.25)


func level_window_scale() -> float:
	return clampf(float(level_data().get("window_scale", 1.0)), 0.55, 1.25)


func level_cash_scale() -> float:
	return clampf(float(level_data().get("cash_scale", 1.0)), 0.5, 4.0)


func level_gain_scale() -> float:
	return clampf(float(level_data().get("gain_scale", 1.0)), 0.5, 2.0)


func level_accent(level: int = -1) -> Color:
	return Color.from_string(str(level_data(level).get("accent", "#26d9ed")), Color(0.15, 0.85, 0.95))


func add_energy(v: float) -> void:
	energy = clampf(energy + v, 0.0, 100.0)
	energy_changed.emit()


func add_fatigue(v: float) -> void:
	var n := clampf(fatigue + v, 0.0, 100.0)
	if is_equal_approx(n, fatigue):
		return
	fatigue = n
	vitals_changed.emit()


func add_hygiene(v: float) -> void:
	var n := clampf(hygiene + v, 0.0, 100.0)
	if is_equal_approx(n, hygiene):
		return
	hygiene = n
	vitals_changed.emit()


func add_recovery(v: float) -> void:
	var n := clampf(recovery + v, 0.0, 100.0)
	if is_equal_approx(n, recovery):
		return
	recovery = n
	vitals_changed.emit()


func move_scale() -> float:
	return 1.0 - 0.25 * clampf((fatigue - 48.0) / 52.0, 0.0, 1.0)


func too_tired() -> bool:
	return fatigue >= 90.0


func too_filthy() -> bool:
	return hygiene < 14.0


func add_money(v: int) -> void:
	money = max(0, money + v)
	money_changed.emit()


func has_gear(id: String) -> bool:
	return bool(inv.get(id, false))


func can_unlock(station_id: String) -> bool:
	var st: Dictionary = stations.get(station_id, {})
	return mass() + 0.001 >= float(st.get("unlock_mass", 0))


func green_window_scale() -> float:
	var g := 1.35 if preworkout_left > 0.0 else 1.0
	g *= 1.0 - 0.30 * clampf((fatigue - 55.0) / 45.0, 0.0, 1.0)
	if recovery > 75.0:
		g *= 1.08
	g *= level_window_scale()
	return g


func gain_scale(station_id: String) -> float:
	var g := 1.0
	if protein_boost_left > 0.0:
		g *= 1.1
	if station_id == "squat" and has_gear("belt"):
		g *= 1.25
	g *= 1.0 - 0.40 * clampf((fatigue - 50.0) / 50.0, 0.0, 1.0)
	g *= 1.0 + 0.14 * clampf((recovery - 55.0) / 45.0, 0.0, 1.0)
	if hygiene < 22.0:
		g *= 0.88
	g *= level_gain_scale()
	return maxf(g, 0.35)


## Touch devices get touch controls and must not see keyboard hints (Yandex mobile
## requirements). The answer comes from ysdk.deviceInfo, not from a touchscreen
## probe: a touch-capable laptop is still a desktop player who needs mouse look.
func is_touch() -> bool:
	return YandexSDK.is_mobile_device()


func emit_quote(kind: String) -> void:
	var pool: Array = quotes.get(kind, [])
	if pool.is_empty():
		return
	quote_emitted.emit(tr(str(pool[randi() % pool.size()])), kind)


## Russian source text; translated here so callers stay readable.
func say(text: String) -> void:
	quote_emitted.emit(tr(text), "prop")


func use_prop(id: String) -> void:
	if float(_prop_cd.get(id, 0.0)) > 0.05:
		Audio.play("deny", 1.0, -6.0)
		say("Подожди секунду.")
		return
	match id:
		"cooler":
			add_energy(16.0)
			add_recovery(4.0)
			_prop_cd[id] = 14.0
			Audio.play("water", 1.35)
			say("Глоток из кулера. Живой.")
		"chair", "benchrest":
			if too_filthy():
				_prop_cd[id] = 6.0
				say("Сесть? Сначала душ. Рядом уже морщатся.")
				return
			add_energy(10.0)
			add_fatigue(-16.0)
			add_recovery(18.0)
			_prop_cd[id] = 12.0
			Audio.play("back")
			say("Сел. Спина сказала спасибо.")
		"toilet":
			add_energy(6.0)
			add_hygiene(6.0)
			_prop_cd[id] = 28.0
			Audio.play("water", 0.8)
			say("Дела качалочные тоже бывают срочными.")
		"sink":
			add_hygiene(18.0)
			_prop_cd[id] = 8.0
			Audio.play("water", 1.1)
			say("Умылся. Грифель с лица смыл.")
		"shower":
			add_hygiene(42.0)
			add_fatigue(-8.0)
			add_recovery(6.0)
			_prop_cd[id] = 16.0
			Audio.play("water")
			say("Смыл подход. Человек, не гриф.")
		"tv":
			add_energy(8.0)
			add_fatigue(-10.0)
			add_recovery(12.0)
			_prop_cd[id] = 16.0
			Audio.play("click", 0.85)
			say("Серия про качков. Мотивация +1.")
		"locker":
			add_money(2)
			_prop_cd[id] = 18.0
			Audio.play("coin")
			say("В шкафчике нашёл двушку. Сегодня твой день.")
		"bag":
			if energy < 4.0:
				emit_quote("empty")
				return
			if too_tired():
				say("Руки не поднимаются. Иди парись.")
				return
			add_energy(-3.0)
			add_fatigue(3.0)
			add_hygiene(-2.0)
			add_recovery(-2.0)
			add_muscle("arms", 0.18)
			add_money(2)
			_prop_cd[id] = 0.45
			Audio.play("whoosh")
			say("Бах. Груша не обиделась.")
		"coat":
			_prop_cd[id] = 10.0
			Audio.play("back")
			say("Куртку повесил. Теперь ты качок, не гость.")
		"sauna":
			add_energy(18.0)
			add_fatigue(-32.0)
			add_recovery(34.0)
			add_hygiene(-8.0)
			_prop_cd[id] = 36.0
			Audio.play("steam")
			say("Распарился. Как огурчик. Теперь в душ.")
		_:
			say("Ага.")
			_prop_cd[id] = 4.0
	_quest_on_prop(id)


func apply_rep(station_id: String, grade: String) -> Dictionary:
	var st: Dictionary = stations[station_id]
	var muscle := str(st.get("muscle", "chest"))
	var base := float(st.get("gain", 1.0)) * gain_scale(station_id)
	var cash := 0
	var gains := 0.0
	match grade:
		"perfect":
			combo += 1
			gains = base * 2.0
			cash = int(round(float(st.get("cash_perfect", 8)) * level_cash_scale()))
			emit_quote("perfect")
		"good":
			combo += 1
			gains = base
			cash = int(round(float(st.get("cash_perfect", 8)) * 0.5 * level_cash_scale()))
			emit_quote("good")
		_:
			combo = 0
			gains = base * 0.25
			emit_quote("miss")
	combo_best = max(combo_best, combo)
	total_reps += 1
	add_muscle(muscle, gains)
	add_money(cash)
	_quest_on_rep(station_id, grade, cash, muscle, gains)
	return {"gains": gains, "cash": cash, "combo": combo}


func note_effort(cost: float) -> void:
	add_fatigue(cost * 0.95)
	add_hygiene(-cost * 0.58)
	add_recovery(-cost * 0.42)


func finish_set() -> void:
	in_set = false
	sets_since_ad += 1
	if fatigue >= 72.0:
		emit_quote("tired")
	elif hygiene <= 32.0:
		emit_quote("dirty")
	elif recovery >= 78.0:
		emit_quote("fresh")
	save_game()
	# After the save, so the just-finished set carries the newer timestamp and wins.
	_flush_deferred_cloud()
	YandexSDK.submit_score(mass_score())


## The local session has just written a newer save, so the merge keeps local
## progress and pushes it up — but the remote copy is no longer silently dropped.
func _flush_deferred_cloud() -> void:
	if _deferred_cloud.is_empty():
		return
	var data := _deferred_cloud
	_deferred_cloud = {}
	_merge_cloud(data)


func buy(item_id: String) -> bool:
	var item: Dictionary = shop.get(item_id, {})
	if item.is_empty():
		return false
	var kind := str(item.get("kind", "consumable"))
	if kind == "gear" and has_gear(item_id):
		return false
	var price := int(item.get("price", 0))
	if money < price:
		return false
	add_money(-price)
	Audio.play("coin")
	if kind == "gear":
		inv[item_id] = true
	elif item_id == "protein":
		add_energy(45.0)
		add_recovery(10.0)
		protein_boost_left = 60.0
	elif item_id == "preworkout":
		preworkout_left = 90.0
	_quest_on_buy(item_id)
	save_game()
	return true


func rewarded_energy() -> void:
	Audio.play("coin", 1.15)
	add_energy(60.0)
	add_recovery(12.0)
	add_fatigue(-10.0)
	save_game()


func to_dict() -> Dictionary:
	return {
		"v": SAVE_VERSION,
		"chest": chest,
		"arms": arms,
		"back": back,
		"legs": legs,
		"cardio": cardio,
		"energy": energy,
		"fatigue": fatigue,
		"hygiene": hygiene,
		"recovery": recovery,
		"money": money,
		"total_reps": total_reps,
		"combo_best": combo_best,
		"sets_since_ad": sets_since_ad,
		"inv": inv,
		"active_quests": active_quests,
		"quests_done": quests_done,
		"quest_seen": _quest_seen,
		"sfx_on": sfx_on,
		"music_on": music_on,
		"saved_at": last_saved_at,
	}


func from_dict(d: Dictionary) -> void:
	if int(d.get("v", 0)) < 1:
		return
	var legacy_stats: Dictionary = {}
	var legacy_stats_v: Variant = d.get("stats", {})
	if legacy_stats_v is Dictionary:
		legacy_stats = legacy_stats_v
	chest = clampf(float(d.get("chest", legacy_stats.get("chest", 0))), 0.0, MUSCLE_CAP)
	arms = clampf(float(d.get("arms", legacy_stats.get("arms", 0))), 0.0, MUSCLE_CAP)
	back = clampf(float(d.get("back", legacy_stats.get("back", 0))), 0.0, MUSCLE_CAP)
	legs = clampf(float(d.get("legs", legacy_stats.get("legs", 0))), 0.0, MUSCLE_CAP)
	cardio = clampf(float(d.get("cardio", legacy_stats.get("cardio", 0))), 0.0, MUSCLE_CAP)
	energy = clampf(float(d.get("energy", 100)), 0.0, 100.0)
	fatigue = clampf(float(d.get("fatigue", 0)), 0.0, 100.0)
	hygiene = clampf(float(d.get("hygiene", 100)), 0.0, 100.0)
	recovery = clampf(float(d.get("recovery", 80)), 0.0, 100.0)
	money = maxi(0, int(d.get("money", 0)))
	total_reps = maxi(0, int(d.get("total_reps", 0)))
	combo_best = maxi(0, int(d.get("combo_best", 0)))
	sets_since_ad = maxi(0, int(d.get("sets_since_ad", 0)))
	var inv_v: Variant = d.get("inv", {})
	inv = inv_v if inv_v is Dictionary else {}
	var quests_v: Variant = d.get("active_quests", [])
	active_quests = quests_v if quests_v is Array else []
	_migrate_active_quests()
	quests_done = maxi(0, int(d.get("quests_done", 0)))
	var seen_v: Variant = d.get("quest_seen", {})
	_quest_seen = seen_v if seen_v is Dictionary else {}
	sfx_on = bool(d.get("sfx_on", true))
	music_on = bool(d.get("music_on", true))
	Audio.sfx_on = sfx_on
	Audio.music_on = music_on
	# Audio owns the live flags; these fields exist only so the save carries them.
	last_saved_at = maxi(0, int(d.get("saved_at", 0)))
	stats_changed.emit()
	energy_changed.emit()
	money_changed.emit()
	vitals_changed.emit()
	quests_changed.emit()


func _migrate_active_quests() -> void:
	for index in range(active_quests.size()):
		var quest_v: Variant = active_quests[index]
		if not quest_v is Dictionary:
			continue
		var quest: Dictionary = quest_v
		var definition_v: Variant = quest_defs.get(str(quest.get("id", "")), {})
		if definition_v is Dictionary:
			var definition: Dictionary = definition_v
			if not quest.has("prop"):
				quest["prop"] = str(definition.get("prop", ""))
		active_quests[index] = quest


func save_game() -> void:
	last_saved_at = int(Time.get_unix_time_from_system())
	var data := to_dict()
	_write_local(data)
	YandexSDK.cloud_save(data)


func load_game() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				from_dict(parsed)
				_local_save_loaded = true


func _write_local(data: Dictionary) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func _on_cloud_loaded(data: Dictionary) -> void:
	if in_set:
		_deferred_cloud = data.duplicate(true)
		return
	_merge_cloud(data)


func _merge_cloud(data: Dictionary) -> void:
	if int(data.get("v", 0)) < 1:
		if _local_save_loaded:
			YandexSDK.cloud_save(to_dict())
		return
	var remote_saved_at := maxi(0, int(data.get("saved_at", 0)))
	var use_remote := not _local_save_loaded
	if _local_save_loaded:
		if remote_saved_at > 0 or last_saved_at > 0:
			use_remote = remote_saved_at > last_saved_at
		else:
			use_remote = _progress_rank(data) > _progress_rank(to_dict())
	if not use_remote:
		YandexSDK.cloud_save(to_dict())
		return
	from_dict(data)
	_local_save_loaded = true
	_ensure_quests()
	_write_local(to_dict())
	YandexSDK.cloud_save(to_dict())


func _progress_rank(data: Dictionary) -> float:
	var muscles := 0.0
	for key in ["chest", "arms", "back", "legs", "cardio"]:
		muscles += maxf(0.0, float(data.get(key, 0.0)))
	return float(maxi(0, int(data.get("total_reps", 0)))) * 1000.0 \
		+ float(maxi(0, int(data.get("quests_done", 0)))) * 100.0 \
		+ muscles


func note_shop() -> void:
	for q in active_quests:
		if str(q.get("type", "")) == "shop":
			q["progress"] = 1
	_resolve_quests()


func note_set(sid: String, perfects: int, misses: int, _reps: int, completed: bool) -> void:
	for q in active_quests:
		var t := str(q.get("type", ""))
		var st := str(q.get("station", ""))
		if t == "sets" and completed and _station_match(st, sid):
			q["progress"] = int(q.get("progress", 0)) + 1
		elif t == "clean_set" and _station_match(st, sid):
			if completed and misses == 0:
				q["progress"] = int(q.get("progress", 0)) + 1
			else:
				q["progress"] = 0
		elif t == "perfect_in_set" and completed and perfects >= int(q.get("target", 5)) and _station_match(st, sid):
			q["progress"] = int(q.get("target", 1))
		elif t == "variety" and completed:
			var used := {}
			var used_v: Variant = q.get("used", {})
			if used_v is Dictionary:
				used = used_v
			used[sid] = true
			q["used"] = used
			q["progress"] = used.size()
		elif t == "cardio" and completed and sid in ["treadmill", "bike"]:
			q["progress"] = int(q.get("progress", 0)) + 1
		elif t == "both_cardio" and completed and sid in ["treadmill", "bike"]:
			var flags := {}
			var flags_v: Variant = q.get("flags", {})
			if flags_v is Dictionary:
				flags = flags_v
			flags[sid] = true
			q["flags"] = flags
			q["progress"] = flags.size()
	_resolve_quests()


func quest_hint_for(sid: String) -> String:
	# A quest tied to this station wins over a generic one listed before it.
	var generic := ""
	for q in active_quests:
		var st := str(q.get("station", ""))
		var t := str(q.get("type", ""))
		if st == sid or (t == "cardio" and sid in ["treadmill", "bike"]) or (t == "both_cardio" and sid in ["treadmill", "bike"]):
			var left: int = maxi(0, int(q.get("target", 1)) - int(q.get("progress", 0)))
			return tr("%s  ещё %d") % [tr(str(q.get("title", ""))), left]
		if generic == "" and t in ["perfects", "combo", "clean_set", "perfect_in_set", "variety", "reps", "sets"] and st == "":
			generic = tr(str(q.get("title", "")))
	return generic


func _quest_on_rep(sid: String, grade: String, cash: int, muscle: String, gains: float) -> void:
	for q in active_quests:
		var t := str(q.get("type", ""))
		var st := str(q.get("station", ""))
		if t == "perfects" and grade == "perfect" and _station_match(st, sid):
			q["progress"] = int(q.get("progress", 0)) + 1
		elif t == "combo":
			q["progress"] = maxi(int(q.get("progress", 0)), combo)
		elif t == "reps" and _station_match(st, sid):
			q["progress"] = int(q.get("progress", 0)) + 1
		elif t == "earn":
			q["progress"] = int(q.get("progress", 0)) + cash
		elif t == "mass_gain":
			q["progress"] = int(floor(mass() - float(q.get("mark", 0.0))))
		elif t == "muscle" and str(q.get("muscle", "")) == muscle:
			q["progress"] = float(q.get("progress", 0.0)) + gains
	_resolve_quests()


func _quest_on_buy(_item_id: String) -> void:
	for q in active_quests:
		if str(q.get("type", "")) == "buy":
			q["progress"] = 1
	_resolve_quests()


func _quest_on_prop(prop_id: String) -> void:
	for q in active_quests:
		if str(q.get("type", "")) != "prop":
			continue
		var need := str(q.get("prop", q.get("station", "")))
		if need == "" or need == prop_id:
			q["progress"] = int(q.get("progress", 0)) + 1
	_resolve_quests()


func _station_match(need: String, sid: String) -> bool:
	return need == "" or need == sid


func _ensure_quests() -> void:
	var dirty := false
	while active_quests.size() < 3:
		var q := _roll_quest()
		if q.is_empty():
			break
		active_quests.append(q)
		dirty = true
	if dirty:
		quests_changed.emit()


func _roll_quest() -> Dictionary:
	var taken: Dictionary = {}
	for q in active_quests:
		taken[str(q.get("id", ""))] = true
	var pool: Array = []
	for id in quest_defs.keys():
		if taken.has(id):
			continue
		var def := {}
		var def_v: Variant = quest_defs[id]
		if def_v is Dictionary:
			def = def_v
		else:
			continue
		if mass() + 0.001 < float(def.get("min_mass", 0)):
			continue
		var st := str(def.get("station", ""))
		if st != "" and not can_unlock(st):
			continue
		if str(def.get("type", "")) in ["cardio", "both_cardio"]:
			if not can_unlock("treadmill") and not can_unlock("bike"):
				continue
		var w := int(def.get("weight", 1))
		if quests_done == 0 and str(id) in ["first_bench", "visit_bar", "combo4"]:
			w += 20
		for i in range(maxi(w, 1)):
			pool.append(id)
	if pool.is_empty():
		return {}
	var pick := str(pool[randi() % pool.size()])
	return _make_quest(pick)


func _make_quest(id: String) -> Dictionary:
	var def := {}
	var def_v: Variant = quest_defs.get(id, {})
	if def_v is Dictionary:
		def = def_v
	if def.is_empty():
		return {}
	return {
		"id": id,
		"title": str(def.get("title", id)),
		"desc": str(def.get("desc", "")),
		"type": str(def.get("type", "sets")),
		"station": str(def.get("station", "")),
		"prop": str(def.get("prop", "")),
		"muscle": str(def.get("muscle", "")),
		"target": int(def.get("target", 1)),
		"progress": 0,
		"cash": int(def.get("cash", 20)),
		"energy": int(def.get("energy", 8)),
		"mark": mass(),
		"used": {},
		"flags": {},
	}


func _resolve_quests() -> void:
	var kept: Array = []
	var completed: Array = []
	for q in active_quests:
		if float(q.get("progress", 0)) + 0.0001 >= float(q.get("target", 1)):
			completed.append(q)
		else:
			kept.append(q)
	active_quests = kept
	for q in completed:
		var cash := int(q.get("cash", 0))
		var en := int(q.get("energy", 0))
		add_money(cash)
		add_energy(float(en))
		quests_done += 1
		_quest_seen[str(q.get("id", ""))] = true
		var reward := tr("+%d₽  +%d эн.") % [cash, en]
		if quests_done > 0 and quests_done % 5 == 0:
			add_money(80)
			add_energy(20.0)
			reward += tr("  ·  герой дня +80₽")
		quest_completed.emit(tr(str(q.get("title", "Задание"))), reward)
		Audio.play("quest")
		emit_quote("quest")
	if not completed.is_empty():
		_ensure_quests()
		save_game()
		quests_changed.emit()
	else:
		quests_changed.emit()


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("Missing data: " + path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}
