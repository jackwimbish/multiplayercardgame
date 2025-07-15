extends PanelContainer
signal card_clicked

signal drag_started(card)
#signal dropped(card)

#var is_dragging = false
var drag_offset = Vector2.ZERO
        
func _gui_input(event):
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        # Calculate the offset and immediately signal that a drag has begun.
        drag_offset = get_global_mouse_position() - global_position
        drag_started.emit(self)

func setup_card_data(data):
    # "data" is a Dictionary with card info
    $VBoxContainer/CardName.text = data["name"]
    $VBoxContainer/CardDescription.text = data["description"]
    # We'll load the art later, but the setup is here
    # $VBoxContainer/CardArt.texture = load(data["art_path"])
