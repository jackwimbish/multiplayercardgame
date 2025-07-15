extends PanelContainer
signal card_clicked
func _gui_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		card_clicked.emit(self)

func setup_card_data(data):
	# "data" is a Dictionary with card info
	$VBoxContainer/CardName.text = data["name"]
	$VBoxContainer/CardDescription.text = data["description"]
	# We'll load the art later, but the setup is here
	# $VBoxContainer/CardArt.texture = load(data["art_path"])
