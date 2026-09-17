extends CanvasLayer

## Third-party notices shipped with the build. Kenney and WRAD are CC0 and ask for
## nothing; Inter is SIL OFL, which requires the licence to travel with the font.
## One line per entry so each stays a normal translation key.
const CREDITS_LINES := [
	"КАЧАЛКА: ЕЩЁ ОДИН ПОВТОР",
	"",
	"Движок: Godot Engine — MIT",
	"Шрифт: Inter — SIL Open Font License 1.1",
	"Мебель и реквизит: Kenney Furniture Kit и Food Kit — CC0",
	"Руки от первого лица: WRAD FPS arms — CC0",
	"Музыка и звук: синтезируются самой игрой",
	"",
	"Полные тексты лицензий лежат в сборке рядом с ассетами.",
]

@onready var mass_label: Label = $Root/Top/Mass
@onready var money_label: Label = $Root/Top/Money
@onready var energy_bar: ProgressBar = $Root/Top/Energy
@onready var combo_label: Label = $Root/Top/Combo
@onready var fatigue_bar: ProgressBar = $Root/Vitals/Fatigue/Bar
@onready var hygiene_bar: ProgressBar = $Root/Vitals/Hygiene/Bar
@onready var recovery_bar: ProgressBar = $Root/Vitals/Recovery/Bar
@onready var prompt: Label = $Root/Prompt
@onready var quote: Label = $Root/Quote
@onready var pause_panel: Control = $Root/Pause
@onready var joystick: Control = $Root/Joystick
@onready var interact_btn: Button = $Root/InteractBtn
@onready var reticle: Control = $Root/Reticle
@onready var look_pad: Control = $Root/LookPad
@onready var pause_btn: Button = $Root/PauseBtn
@onready var quest_head: Label = $Root/Quests/Box/Head
@onready var quest_labels: Array = [$Root/Quests/Box/Q0, $Root/Quests/Box/Q1, $Root/Quests/Box/Q2]
@onready var sfx_btn: Button = $Root/Pause/Box/Sound/Sfx
@onready var music_btn: Button = $Root/Pause/Box/Sound/Music
@onready var board: Control = $Root/Board
@onready var board_body: Label = $Root/Board/Box/Body
@onready var board_auth: Button = $Root/Board/Box/Auth

var _quote_ttl: float = 0.0
var _ad_busy: bool = false
var _board_open: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.stats_changed.connect(_refresh)
	GameState.energy_changed.connect(_refresh)
	GameState.money_changed.connect(_refresh)
	GameState.vitals_changed.connect(_refresh)
	GameState.quote_emitted.connect(_on_quote)
	GameState.quests_changed.connect(_refresh_quests)
	GameState.quest_completed.connect(_on_quest_done)
	GameState.level_unlocked.connect(_on_level_unlocked)
	Loc.language_changed.connect(func(_lang: String) -> void: _refresh())
	if joystick.has_signal("stick_changed"):
		joystick.connect("stick_changed", _on_stick)
	pause_panel.visible = false
	interact_btn.pressed.connect(_on_interact)
	interact_btn.visible = false
	if pause_btn:
		pause_btn.pressed.connect(_on_pause_btn)
	board.visible = false
	YandexSDK.leaderboard_loaded.connect(_on_board_loaded)
	# deviceInfo lands after the SDK handshake, so the mobile layout has to be
	# able to rebuild itself rather than being decided once at _ready.
	YandexSDK.device_resolved.connect(func(_mobile: bool) -> void: _layout_phone())
	get_viewport().size_changed.connect(_layout_phone)
	_layout_phone()
	_refresh_sound_buttons()
	_refresh()
	_refresh_quests()


func _process(delta: float) -> void:
	if _quote_ttl > 0.0:
		_quote_ttl -= delta
		if _quote_ttl <= 0.0:
			quote.text = ""


func _refresh() -> void:
	var nxt := GameState.next_gym_kg()
	if nxt > 0.0:
		mass_label.text = tr("МАССА %.1f кг  ·  УР.%d/6\n%s  ·  до следующего %.0f кг") % [GameState.mass(), GameState.gym_level(), GameState.level_name().to_upper(), nxt]
	else:
		mass_label.text = tr("МАССА %.1f кг  ·  УР.6/6\n%s  ·  ФИНАЛ") % [GameState.mass(), GameState.level_name().to_upper()]
	mass_label.modulate = GameState.level_accent()
	money_label.text = tr("₽ %d") % GameState.money
	energy_bar.value = GameState.energy
	combo_label.text = tr("КОМБО ×%d") % GameState.combo if GameState.combo > 0 else ""
	if fatigue_bar:
		fatigue_bar.value = GameState.fatigue
		fatigue_bar.modulate = Color(1.0, 0.55, 0.2) if GameState.fatigue < 70.0 else Color(1.0, 0.25, 0.18)
	if hygiene_bar:
		hygiene_bar.value = GameState.hygiene
		hygiene_bar.modulate = Color(0.35, 0.82, 0.95) if GameState.hygiene > 30.0 else Color(0.75, 0.45, 0.2)
	if recovery_bar:
		recovery_bar.value = GameState.recovery
		recovery_bar.modulate = Color(0.35, 0.92, 0.55) if GameState.recovery > 35.0 else Color(0.7, 0.7, 0.35)
	_refresh_quests()


func _refresh_quests() -> void:
	if quest_head:
		var n := GameState.quests_done
		quest_head.text = tr("ЗАДАНИЯ") if n == 0 else tr("ЗАДАНИЯ  ·  %d") % n
	for i in range(quest_labels.size()):
		var lab: Label = quest_labels[i]
		if i >= GameState.active_quests.size():
			lab.text = ""
			continue
		var qv: Variant = GameState.active_quests[i]
		if not qv is Dictionary:
			lab.text = ""
			continue
		var q: Dictionary = qv
		var prog := int(q.get("progress", 0))
		var tgt := int(q.get("target", 1))
		# Quests are saved with Russian source text; translate on display.
		lab.text = tr("%s\n%s   %d/%d   +%d₽") % [
			tr(str(q.get("title", ""))),
			tr(str(q.get("desc", ""))),
			mini(prog, tgt),
			tgt,
			int(q.get("cash", 0)),
		]
		lab.modulate = Color(0.85, 0.95, 0.9) if prog > 0 else Color(0.75, 0.78, 0.82)


func _on_quest_done(title: String, reward: String) -> void:
	quote.text = tr("ЗАЧЁТ  %s  %s") % [title, reward]
	_quote_ttl = 3.2
	quote.modulate = Color(0.3, 1.0, 0.75)


func _on_level_unlocked(level: int, title: String, rule: String) -> void:
	quote.text = tr("НОВЫЙ УРОВЕНЬ %d/6  ·  %s\n%s") % [level, title.to_upper(), rule]
	quote.modulate = GameState.level_accent(level)
	_quote_ttl = 5.0


## `action` is already translated. `can_act` false = info only (locked station), no E / button.
func set_prompt(action: String, can_act: bool = true) -> void:
	var ok := action != "" and can_act
	# No keyboard hints on touch devices: the on-screen button does the action.
	prompt.text = "E — " + action if ok and not GameState.is_touch() else action
	interact_btn.visible = ok
	interact_btn.text = action if ok and action.length() < 16 else "E"


func set_aim(hot: bool) -> void:
	if reticle:
		reticle.visible = not GameState.in_set
		reticle.set("hot", hot and not GameState.in_set)


func set_workout(on: bool) -> void:
	if reticle:
		reticle.visible = not on
	if joystick and joystick.has_method("set_workout"):
		joystick.call("set_workout", on)
	elif joystick:
		joystick.visible = not on and GameState.is_touch()
	if look_pad:
		look_pad.visible = not on and GameState.is_touch()
	if interact_btn and on:
		interact_btn.visible = false


## Re-runs on every resize and whenever deviceInfo changes its mind, so rotating
## a phone or leaving fullscreen relayouts instead of keeping the boot-time guess.
func _layout_phone() -> void:
	var w := get_viewport().get_visible_rect().size.x
	var touch := GameState.is_touch()
	var phone := touch and w < 980.0
	var q: Control = $Root/Quests
	if q:
		q.offset_right = 250.0 if phone else 330.0
		q.offset_bottom = 210.0 if phone else 260.0
		q.modulate.a = 0.82 if phone else 1.0
	if pause_btn:
		pause_btn.visible = touch or OS.has_feature("web")
	if joystick:
		joystick.visible = touch and not GameState.in_set and not GameState.paused
	if look_pad:
		look_pad.visible = touch and not GameState.in_set and not GameState.paused
	# The prompt's keyboard hint depends on the same answer; the proximity scan
	# re-pushes it every frame, so there is nothing to patch up here.


func _on_pause_btn() -> void:
	if GameState.in_set or _ad_busy or YandexSDK.is_ad_active():
		return
	var world := get_parent()
	if GameState.paused:
		if world.has_method("_resume"):
			world._resume()
	else:
		if world.has_method("_pause"):
			world._pause()


func _refresh_sound_buttons() -> void:
	var on := tr("вкл")
	var off := tr("выкл")
	sfx_btn.text = tr("Звук: %s") % (on if Audio.sfx_on else off)
	music_btn.text = tr("Музыка: %s") % (on if Audio.music_on else off)


func _on_sfx_pressed() -> void:
	Audio.toggle_sfx()
	GameState.save_game()
	_refresh_sound_buttons()


func _on_music_pressed() -> void:
	Audio.toggle_music()
	Audio.play("click")
	GameState.save_game()
	_refresh_sound_buttons()


func _on_credits_pressed() -> void:
	Audio.play("click")
	_board_open = true
	board.visible = true
	board_auth.visible = false
	var lines: Array[String] = []
	for line in CREDITS_LINES:
		lines.append(tr(str(line)) if str(line) != "" else "")
	board_body.text = "\n".join(lines)
	$Root/Board/Box/Head.text = tr("ТИТРЫ")


func _on_board_pressed() -> void:
	Audio.play("click")
	_board_open = true
	board.visible = true
	board_auth.visible = false
	$Root/Board/Box/Head.text = tr("ТАБЛИЦА РЕКОРДОВ")
	board_body.text = tr("Загружаем…")
	YandexSDK.load_leaderboard()


func _on_board_loaded(entries: Array, own_rank: int) -> void:
	if not _board_open:
		return
	if entries.is_empty():
		board_body.text = tr("Пока пусто. Закрой сет — и попадёшь в таблицу.\nРекорд сохраняется только для игроков с аккаунтом Яндекса.")
		board_auth.visible = true
		return
	var rows: Array[String] = []
	for e in entries:
		if not e is Dictionary:
			continue
		var row: Dictionary = e
		var who := str(row.get("name", ""))
		if who.strip_edges() == "":
			who = tr("Аноним")
		# The board stores mass × 10 so it can stay an integer leaderboard.
		rows.append(tr("%d.  %s  —  %.1f кг") % [int(row.get("rank", 0)), who, float(row.get("score", 0)) / 10.0])
	if own_rank > 0:
		rows.append("")
		rows.append(tr("Твоё место: %d") % own_rank)
	else:
		board_auth.visible = true
	board_body.text = "\n".join(rows)


func _on_board_auth() -> void:
	Audio.play("click")
	YandexSDK.open_auth_dialog()


func _on_board_close() -> void:
	Audio.play("back")
	_board_open = false
	board.visible = false


func _on_interact() -> void:
	Audio.play("click", 1.0, -6.0)
	var world := get_parent()
	if world.has_method("_try_interact"):
		world._try_interact()


func flash_energy() -> void:
	energy_bar.modulate = Color(1, 0.3, 0.3)
	await get_tree().create_timer(0.25).timeout
	energy_bar.modulate = Color.WHITE


func _on_quote(text: String, _kind: String) -> void:
	quote.text = text
	quote.modulate = Color(0.15, 0.85, 0.95, 1)
	_quote_ttl = 2.2


func _on_stick(v: Vector2) -> void:
	var p: Node = get_tree().get_first_node_in_group("player")
	if p:
		p.set("stick", v)


func show_pause(on: bool) -> void:
	if pause_panel:
		pause_panel.visible = on
		pause_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	if on:
		_refresh_sound_buttons()
	else:
		_on_board_close()


func _on_resume_pressed() -> void:
	if _ad_busy or YandexSDK.is_ad_active():
		return
	if _board_open:
		_on_board_close()
	var world := get_parent()
	if world.has_method("_resume"):
		world._resume()


func _on_ad_pressed() -> void:
	if _ad_busy:
		return
	Audio.play("click")
	_ad_busy = true
	var ad_button: Button = $Root/Pause/Box/AdEnergy
	ad_button.disabled = true
	YandexSDK.gameplay_stop()
	var ok: bool = await YandexSDK.show_rewarded()
	if ok:
		GameState.rewarded_energy()
	_ad_busy = false
	ad_button.disabled = false
