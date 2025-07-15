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

func setup_card_data(data: Dictionary):
    # "data" is a Dictionary with card info
    # Safely handle card data that may or may not have all fields
    $VBoxContainer/CardName.text = data.get("name", "Unnamed")
    $VBoxContainer/CardDescription.text = data.get("description", "")
    
    # Show attack/health stats at bottom left for minions (with forward slash)
    if data.has("attack") and data.has("health"):
        $VBoxContainer/BottomRow/StatsLabel.text = str(data["attack"]) + "/" + str(data["health"])
        $VBoxContainer/BottomRow/StatsLabel.show()
    else:
        # Hide stats for spells or cards without both attack and health
        $VBoxContainer/BottomRow/StatsLabel.hide()
    
    # We'll load the art later, but the setup is here
    # $VBoxContainer/CardArt.texture = load(data["art_path"])
