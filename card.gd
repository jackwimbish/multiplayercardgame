extends PanelContainer
signal card_clicked

signal drag_started(card)
#signal dropped(card)

var is_being_dragged: bool = false
var drag_offset = Vector2.ZERO
var mouse_press_position: Vector2
const DRAG_THRESHOLD_DISTANCE = 10.0  # pixels before drag starts

func _ready():
    # Set consistent card sizing automatically
    _set_default_size()

func _set_default_size():
    """Set the standard card size and constraints"""
    # Reset anchors to prevent conflicts with size setting
    set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
    
    # Set consistent size constraints
    custom_minimum_size = Vector2(120, 180)
    size = Vector2(120, 180)
    
    # Prevent expansion in containers
    size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    size_flags_vertical = Control.SIZE_SHRINK_CENTER
        
func _gui_input(event):
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            # Record press position but don't start drag yet
            mouse_press_position = get_global_mouse_position()
            is_being_dragged = false
        else:
            # Mouse released
            if not is_being_dragged:
                # It was a click (no drag occurred)
                card_clicked.emit(self)
            is_being_dragged = false
    
    elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
        # Check if we should start dragging
        if not is_being_dragged:
            var drag_distance = mouse_press_position.distance_to(get_global_mouse_position())
            if drag_distance > DRAG_THRESHOLD_DISTANCE:
                # Start drag
                drag_offset = get_global_mouse_position() - global_position
                drag_started.emit(self)
                is_being_dragged = true

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
