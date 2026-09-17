extends Control

var _starting: bool = false


func _ready() -> void:
	if GameState.is_touch():
		_apply_touch_hint()
	# deviceInfo arrives after the SDK handshake, which can land after this scene.
	YandexSDK.device_resolved.connect(_on_device_resolved)
	# Requirement 1.19.4 applies to the menu too, not just the gym.
	YandexSDK.pause_requested.connect(_on_platform_pause)
	YandexSDK.resume_requested.connect(_on_platform_resume)
	YandexSDK.loading_ready()


func _apply_touch_hint() -> void:
	var controls := $Center/Controls as Label
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Source text on purpose: the Label auto-translates and follows a later SDK language switch.
	controls.text = "Левый стик — ходьба. Свайп справа — взгляд. Кнопки на экране — действия."


func _on_device_resolved(mobile: bool) -> void:
	if mobile:
		_apply_touch_hint()


func _on_platform_pause() -> void:
	Audio.hold_mute("hidden")
	get_tree().paused = true


func _on_platform_resume() -> void:
	Audio.release_mute("hidden")
	get_tree().paused = false


func _on_play() -> void:
	if _starting:
		return
	_starting = true
	Audio.play("click")
	get_tree().change_scene_to_file("res://scenes/gym/gym.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact") or event.is_action_pressed("rep"):
		_on_play()
