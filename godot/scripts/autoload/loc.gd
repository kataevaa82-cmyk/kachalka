extends Node
## Game language. Russian source text is the translation key (gettext style):
## scene texts translate automatically, scripts and data go through tr().
## Yandex requirement 2.14: the language comes from ysdk.environment.i18n.lang (see YandexSDK).

signal language_changed(lang: String)

const EN_PATH := "res://data/i18n_en.json"
## Yandex serves these audiences in Russian; everyone else gets English.
const RUSSIAN_LANGS := ["ru", "be", "kk", "uk", "uz"]

var lang: String = ""
var en: Dictionary = {}


func _ready() -> void:
	var f := FileAccess.open(EN_PATH, FileAccess.READ)
	if f:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			en = parsed
	if en.is_empty():
		push_warning("Missing translations: " + EN_PATH)
	var translation := Translation.new()
	translation.locale = "en"
	for source in en:
		translation.add_message(str(source), str(en[source]))
	TranslationServer.add_translation(translation)
	# Best guess until the SDK answers: Yandex passes ?lang= to the game frame, else the browser/OS language.
	set_language(_initial_language())


func set_language(code: String) -> void:
	var base := code.strip_edges().to_lower().substr(0, 2)
	var wanted := "ru" if base in RUSSIAN_LANGS else "en"
	if wanted == lang:
		return
	lang = wanted
	TranslationServer.set_locale(lang)
	language_changed.emit(lang)


func is_english() -> bool:
	return lang == "en"


func _initial_language() -> String:
	if OS.has_feature("web"):
		var guess: Variant = JavaScriptBridge.eval("(new URLSearchParams(location.search).get('lang')) || navigator.language || ''", true)
		if str(guess) != "":
			return str(guess)
	return OS.get_locale_language()
