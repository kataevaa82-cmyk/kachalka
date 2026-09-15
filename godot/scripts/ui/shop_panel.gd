extends CanvasLayer

@onready var root: Control = $Root
@onready var list: VBoxContainer = $Root/Panel/List
@onready var cash: Label = $Root/Panel/Cash

var _ad_busy: bool = false


func _ready() -> void:
	root.visible = false
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED


func show_shop() -> void:
	if root.visible:
		return
	root.visible = true
	get_tree().paused = true
	GameState.paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	YandexSDK.gameplay_stop()
	GameState.note_shop()
	_rebuild()


func hide_shop() -> void:
	if not root.visible or _ad_busy or YandexSDK.is_ad_active():
		return
	root.visible = false
	get_tree().paused = false
	GameState.paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	YandexSDK.gameplay_start()


func _rebuild() -> void:
	cash.text = tr("₽ %d") % GameState.money
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	for id in GameState.shop.keys():
		var item: Dictionary = GameState.shop[id]
		var row := Button.new()
		var owned := GameState.has_gear(id)
		var price := int(item.get("price", 0))
		var item_name := tr(str(item.get("name", id)))
		var label := tr("%s — %d₽\n%s") % [item_name, price, tr(str(item.get("desc", "")))]
		if owned and str(item.get("kind")) == "gear":
			label = tr("%s — КУПЛЕНО") % item_name
			row.disabled = true
		row.text = label
		row.custom_minimum_size = Vector2(0, 72)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var captured := str(id)
		row.pressed.connect(func() -> void:
			if GameState.buy(captured):
				_rebuild()
			else:
				cash.text = tr("Не хватает ₽")
		)
		list.add_child(row)
	var ad := Button.new()
	ad.text = tr("Смотреть рекламу: +60 энергии")
	ad.disabled = _ad_busy
	ad.pressed.connect(_ad)
	list.add_child(ad)
	var close := Button.new()
	close.text = tr("Закрыть")
	close.disabled = _ad_busy
	close.pressed.connect(hide_shop)
	list.add_child(close)


func _ad() -> void:
	if _ad_busy:
		return
	_ad_busy = true
	_rebuild()
	YandexSDK.gameplay_stop()
	var ok: bool = await YandexSDK.show_rewarded()
	if ok:
		GameState.rewarded_energy()
	_ad_busy = false
	_rebuild()
