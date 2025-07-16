class_name Card
extends PanelContainer
signal card_clicked

signal drag_started(card)
#signal dropped(card)

var is_being_dragged: bool = false
var drag_offset = Vector2.ZERO
var mouse_press_position: Vector2
const DRAG_THRESHOLD_DISTANCE = 10.0  # pixels before drag starts

# Card data storage
var card_data: Dictionary = {}

func _ready():
    # Set consistent card sizing automatically
    _set_default_size()

func _set_default_size():
    """Set the standard card size and constraints"""
    # Reset anchors to prevent conflicts with size setting
    set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
    
    # Set consistent size constraints
    custom_minimum_size = Vector2(180, 270)
    size = Vector2(180, 270)
    
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
    # Store card data for future reference
    card_data = data
    
    # Set up UI elements
    $VBoxContainer/CardName.text = data.get("name", "Unnamed")
    
    # Make card name larger
    $VBoxContainer/CardName.add_theme_font_size_override("font_size", 18)
    
    # Set description with dynamic font sizing
    var description = data.get("description", "")
    $VBoxContainer/CardDescription.text = description
    _adjust_description_font_size(description)
    
    # Show/hide stats based on card type - base implementation for spells
    if data.has("attack") and data.has("health"):
        # This will be overridden in MinionCard
        $VBoxContainer/BottomRow/StatsLabel.text = str(data.get("attack", 0)) + "/" + str(data.get("health", 0))
        $VBoxContainer/BottomRow/StatsLabel.add_theme_font_size_override("font_size", 20)
        $VBoxContainer/BottomRow/StatsLabel.show()
    else:
        # Hide stats for spells or cards without both attack and health
        $VBoxContainer/BottomRow/StatsLabel.hide()
    
    # Load card art using the database helper function
    var card_id = data.get("id", "")
    if card_id != "":
        var art_path = CardDatabase.get_card_art_path(card_id)
        var art_texture = load(art_path)
        if art_texture:
            $VBoxContainer/CardArt.texture = art_texture
        else:
            print("Warning: Could not load card art from: ", art_path)

func _adjust_description_font_size(description: String) -> void:
    """Adjust font size based on description length"""
    var description_label = $VBoxContainer/CardDescription
    
    # Get current theme or create a new one
    var theme_override = description_label.get_theme_stylebox("normal")
    
    # Determine font size based on text length
    var font_size: int
    if description.length() <= 30:
        font_size = 20  # Normal size for short descriptions
    elif description.length() <= 60:
        font_size = 18  # Smaller for medium descriptions  
    else:
        font_size = 16  # Smallest for long descriptions
    
    # Apply the font size
    description_label.add_theme_font_size_override("font_size", font_size)
