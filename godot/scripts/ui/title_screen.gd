extends Control

var _starting: bool = false


func _ready() -> void:
	if GameState.is_touch():
		var controls := $Center/Controls as Label
		controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# Source text on purpose: the Label auto-translates and follows a later SDK language switch.
		controls.text = "Левый стик — ходьба. Свайп справа — взгляд. Кнопки на экране — действия."
	YandexSDK.loading_ready()


func _on_play() -> void:
	if _starting:
		return
	_starting = true
	get_tree().change_scene_to_file("res://scenes/gym/gym.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact") or event.is_action_pressed("rep"):
		_on_play()
