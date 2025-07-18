# UIManager.gd
# Manages all UI elements and updates for the game board
extends Control
class_name UIManager

# UI Font sizes (moved from game_board.gd)
const UI_FONT_SIZE_LARGE = 24    # Main labels, important text
const UI_FONT_SIZE_MEDIUM = 20   # Secondary labels, buttons
const UI_FONT_SIZE_SMALL = 16    # Supporting text

# UI Node References (using @onready for direct access)
@onready var gold_label = $TopUI/GoldLabel
@onready var turn_label = $TopUI/TurnLabel
@onready var shop_tier_label = $TopUI/ShopTierLabel
@onready var upgrade_button = $TopUI/UpgradeShopButton
@onready var refresh_button = $TopUI/RefreshShopButton
@onready var freeze_button = $TopUI/FreezeButton
@onready var end_turn_button = $TopUI/EndTurnButton
@onready var shop_area = $ShopArea
@onready var shop_area_label = $ShopArea/ShopAreaLabel
@onready var player_board = $PlayerBoard
@onready var player_board_label = $PlayerBoard/PlayerBoardLabel
@onready var player_hand = $PlayerHand
@onready var player_hand_label = $PlayerHand/PlayerHandLabel

# Combat UI references (will be created dynamically)
var player_health_label: Label
var enemy_health_label: Label
var combat_log_display: RichTextLabel
var enemy_board_selector: OptionButton
var start_combat_button: Button
var combat_ui_container: VBoxContainer
var return_to_shop_button: Button
var combat_view_toggle_button: Button

# Flash message system
var flash_message_overlay: CanvasLayer
var flash_message_container: PanelContainer
var flash_message_label: Label
var flash_message_tween: Tween

# Game limits for UI display
var max_hand_size: int = 10
var max_board_size: int = 7

func _ready():
    print("UIManager initialized")
    setup_ui()
    connect_gamestate_signals()
    register_drag_drop_zones()

func setup_ui():
    """Initialize all UI elements and styling"""
    apply_ui_font_sizing()
    create_combat_ui()
    create_flash_message_system()
    populate_enemy_board_selector()
    connect_combat_ui_signals()
    connect_shop_ui_signals()
    
    # Hide End Turn button - turns now advance automatically after combat
    if end_turn_button:
        end_turn_button.visible = false
    
    update_all_displays()

func connect_gamestate_signals():
    """Connect to GameState signals for automatic UI updates"""
    GameState.turn_changed.connect(update_turn_display)
    GameState.turn_changed.connect(_on_turn_changed)  # Update upgrade cost on turn change
    GameState.gold_changed.connect(_on_gold_changed)  # Use detailed gold update
    GameState.shop_tier_changed.connect(_on_shop_tier_changed)  # Use wrapper for signal compatibility
    GameState.player_health_changed.connect(update_health_displays)
    GameState.enemy_health_changed.connect(update_health_displays)
    GameState.game_over.connect(_on_game_over)

# === UI UPDATE FUNCTIONS ===

func update_all_displays():
    """Update all UI elements to reflect current game state"""
    update_turn_display(GameState.current_turn)
    update_gold_display(GameState.current_gold, GameState.GLOBAL_GOLD_MAX)
    update_shop_tier_display(GameState.shop_tier)
    update_hand_display()
    update_board_display()
    update_health_displays()

func update_all_game_displays():
    """Comprehensive UI update that replaces game_board.update_ui_displays()"""
    update_turn_display(GameState.current_turn)
    update_gold_display_detailed()
    update_shop_tier_display_detailed()
    update_hand_display()
    update_board_display()

func update_turn_display(new_turn: int):
    """Update turn label"""
    if turn_label:
        turn_label.text = "Turn: " + str(new_turn)

func _on_turn_changed(new_turn: int):
    """Handle turn change to update upgrade button cost"""
    # Update the upgrade button cost since it decreases each turn
    if upgrade_button:
        var upgrade_cost = GameState.calculate_tavern_upgrade_cost()
        if upgrade_cost > 0:
            upgrade_button.text = "Upgrade Shop (" + str(upgrade_cost) + " gold)"
        else:
            upgrade_button.text = "Max Tier"

func _on_gold_changed(new_gold: int, max_gold: int):
    """Handle gold changes with detailed display update"""
    update_gold_display_detailed()

func _on_shop_tier_changed(new_tier: int):
    """Handle shop tier changes with detailed display update"""
    update_shop_tier_display_detailed()

func update_gold_display(new_gold: int, max_gold: int):
    """Update gold label with current/base gold and bonus"""
    if gold_label:
        var gold_text = "Gold: " + str(new_gold) + "/" + str(GameState.player_base_gold)
        if GameState.bonus_gold > 0:
            gold_text += " (+" + str(GameState.bonus_gold) + ")"
        gold_label.text = gold_text

func update_gold_display_detailed():
    """Update gold display with full current state - replaces game_board direct access"""
    if gold_label:
        var local_player = GameState.get_local_player()
        if local_player:
            var gold_text = "Gold: " + str(local_player.current_gold) + "/" + str(local_player.player_base_gold)
            if local_player.bonus_gold > 0:
                gold_text += " (+" + str(local_player.bonus_gold) + ")"
            gold_label.text = gold_text
        else:
            # Fallback for practice mode
            var gold_text = "Gold: " + str(GameState.current_gold) + "/" + str(GameState.player_base_gold)
            if GameState.bonus_gold > 0:
                gold_text += " (+" + str(GameState.bonus_gold) + ")"
            gold_label.text = gold_text

func update_shop_tier_display(new_tier: int):
    """Update shop tier label and upgrade button"""
    if shop_tier_label:
        shop_tier_label.text = "Shop Tier: " + str(new_tier)
    
    if upgrade_button:
        var upgrade_cost = GameState.calculate_tavern_upgrade_cost()
        if upgrade_cost > 0:
            upgrade_button.text = "Upgrade Shop (" + str(upgrade_cost) + " gold)"
        else:
            upgrade_button.text = "Max Tier"

func update_shop_tier_display_detailed():
    """Update shop tier and upgrade button with current state - replaces game_board direct access"""
    var local_player = GameState.get_local_player()
    
    if shop_tier_label:
        var tier = local_player.shop_tier if local_player else GameState.shop_tier
        shop_tier_label.text = "Shop Tier: " + str(tier)
    
    if upgrade_button:
        if local_player:
            var upgrade_cost = local_player.current_tavern_upgrade_cost
            if local_player.shop_tier < 6 and upgrade_cost > 0:
                upgrade_button.text = "Upgrade Shop (" + str(upgrade_cost) + " gold)"
            else:
                upgrade_button.text = "Max Tier"
        else:
            # Fallback for practice mode
            var upgrade_cost = GameState.calculate_tavern_upgrade_cost()
            if upgrade_cost > 0:
                upgrade_button.text = "Upgrade Shop (" + str(upgrade_cost) + " gold)"
            else:
                upgrade_button.text = "Max Tier"

func update_hand_display():
    """Update hand count display"""
    if player_hand_label:
        var hand_size = get_hand_size()
        player_hand_label.text = "Your Hand (" + str(hand_size) + "/" + str(max_hand_size) + ")"

func update_board_display():
    """Update board count display"""
    if player_board_label:
        var board_size = get_board_size()
        player_board_label.text = "Your Board (" + str(board_size) + "/" + str(max_board_size) + ")"

func update_health_displays(new_health: int = -1):
    """Update health display labels (parameter ignored, we read from GameState)"""
    print("UIManager updating health displays - Player: %d, Enemy: %d" % [GameState.player_health, GameState.enemy_health])
    if player_health_label:
        player_health_label.text = "Player Health: %d" % GameState.player_health
        print("Updated player health label to: ", player_health_label.text)
        
    if enemy_health_label:
        enemy_health_label.text = "Enemy Health: %d" % GameState.enemy_health
        print("Updated enemy health label to: ", enemy_health_label.text)

func _on_game_over(winner: String):
    """Handle game over UI updates"""
    print("Game Over! Winner: ", winner)

# === FONT MANAGEMENT ===

func apply_ui_font_sizing() -> void:
    """Apply consistent font sizing to all UI elements"""
    # Top UI labels
    apply_font_to_label(gold_label, UI_FONT_SIZE_LARGE)
    apply_font_to_label(shop_tier_label, UI_FONT_SIZE_LARGE)
    
    # Top UI buttons
    apply_font_to_button(refresh_button, UI_FONT_SIZE_MEDIUM)
    apply_font_to_button(freeze_button, UI_FONT_SIZE_MEDIUM)
    apply_font_to_button(upgrade_button, UI_FONT_SIZE_MEDIUM)
    apply_font_to_button(end_turn_button, UI_FONT_SIZE_MEDIUM)
    
    # Area labels
    apply_font_to_label(shop_area_label, UI_FONT_SIZE_LARGE)
    apply_font_to_label(player_board_label, UI_FONT_SIZE_LARGE)
    apply_font_to_label(player_hand_label, UI_FONT_SIZE_LARGE)

func apply_font_to_label(label: Label, size: int) -> void:
    """Helper function to apply font size to a label"""
    if label:
        label.add_theme_font_size_override("font_size", size)

func apply_font_to_button(button: Button, size: int) -> void:
    """Helper function to apply font size to a button"""  
    if button:
        button.add_theme_font_size_override("font_size", size)

# === PUBLIC INTERFACE FOR GAME LOGIC ===

func get_hand_size() -> int:
    """Get current number of cards in hand"""
    return player_hand.get_children().size() - 1  # Subtract label

func get_board_size() -> int:
    """Get current number of minions on board"""
    return player_board.get_children().size() - 1  # Subtract label

func is_hand_full() -> bool:
    """Check if hand is at maximum capacity"""
    return get_hand_size() >= max_hand_size

func is_board_full() -> bool:
    """Check if board is at maximum capacity"""
    return get_board_size() >= max_board_size

func add_card_to_shop(card_node: Control):
    """Add a card to the shop area"""
    shop_area.add_child(card_node)

func add_card_to_hand(card_node: Control):
    """Add a card to the player's hand"""
    player_hand.add_child(card_node)
    update_hand_display()

func add_card_to_board(card_node: Control):
    """Add a card to the player's board"""
    player_board.add_child(card_node)
    update_board_display()

func clear_shop():
    """Clear all cards from shop area (keeping the label)"""
    for child in shop_area.get_children():
        if child.name != "ShopAreaLabel":
            child.queue_free()

func get_hand_container() -> Container:
    """Return the hand container for direct access"""
    return player_hand

func get_shop_container() -> Container:
    """Return the shop container for direct access"""
    return shop_area

func get_board_container() -> Container:
    """Return the board container for direct access"""
    return player_board

func is_card_in_shop(card_node: Node) -> bool:
    """Check if a card is in the shop area"""
    return card_node.get_parent() == shop_area

# === FLASH MESSAGE SYSTEM ===

func show_flash_message(message: String, duration: float = 2.5) -> void:
    """Show a temporary toast-style flash message to the player"""
    if not flash_message_container or not flash_message_label:
        print("Flash message system not initialized")
        return
    
    # Stop any existing tween
    if flash_message_tween:
        flash_message_tween.kill()
    
    # Set up the message
    flash_message_label.text = message
    flash_message_container.modulate = Color.WHITE
    flash_message_container.visible = true
    
    # Create and configure tween for fade out
    flash_message_tween = create_tween()
    flash_message_tween.tween_interval(duration - 0.5)  # Show for most of duration
    flash_message_tween.tween_property(flash_message_container, "modulate", Color.TRANSPARENT, 0.5)
    flash_message_tween.tween_callback(func(): flash_message_container.visible = false)
    
    print("Toast message: ", message)

# === EVENT FORWARDING FOR CARD INTERACTIONS ===

func _on_card_clicked(card_node):
    """Forward card click events to game board"""
    forward_card_clicked.emit(card_node)

func _on_card_drag_started(card_node, offset = Vector2.ZERO):
    """Forward card drag events to game board"""
    forward_card_drag_started.emit(card_node, offset)

# Signals for forwarding events to game_board
signal forward_card_clicked(card_node)
signal forward_card_drag_started(card_node)

# === COMBAT UI CREATION ===

func create_combat_ui() -> void:
    """Create combat UI elements programmatically"""
    # Create main combat UI container
    combat_ui_container = VBoxContainer.new()
    combat_ui_container.name = "CombatUI"
    
    # Add to the main layout (position it near the top UI)
    add_child(combat_ui_container)
    move_child(combat_ui_container, 1)  # Place after TopUI
    
    # Create health display container
    var health_container = HBoxContainer.new()
    health_container.name = "HealthContainer"
    
    # Player health label
    player_health_label = Label.new()
    player_health_label.name = "PlayerHealthLabel"
    player_health_label.text = "Player Health: %d" % GameState.player_health
    player_health_label.add_theme_color_override("font_color", Color.GREEN)
    apply_font_to_label(player_health_label, UI_FONT_SIZE_LARGE)
    
    # Enemy health label  
    enemy_health_label = Label.new()
    enemy_health_label.name = "EnemyHealthLabel"
    enemy_health_label.text = "Enemy Health: %d" % GameState.enemy_health
    enemy_health_label.add_theme_color_override("font_color", Color.RED)
    apply_font_to_label(enemy_health_label, UI_FONT_SIZE_LARGE)
    
    health_container.add_child(player_health_label)
    health_container.add_child(enemy_health_label)
    
    # Create enemy board selection container
    var enemy_selection_container = HBoxContainer.new()
    enemy_selection_container.name = "EnemySelectionContainer"
    
    var enemy_label = Label.new()
    enemy_label.text = "Enemy Board: "
    apply_font_to_label(enemy_label, UI_FONT_SIZE_MEDIUM)
    
    enemy_board_selector = OptionButton.new()
    enemy_board_selector.name = "EnemyBoardSelector"
    apply_font_to_button(enemy_board_selector, UI_FONT_SIZE_MEDIUM)
    
    enemy_selection_container.add_child(enemy_label)
    enemy_selection_container.add_child(enemy_board_selector)
    
    # Create start combat button
    start_combat_button = Button.new()
    start_combat_button.name = "StartCombatButton"
    start_combat_button.text = "Start Combat"
    apply_font_to_button(start_combat_button, UI_FONT_SIZE_MEDIUM)
    
    # Create combat log display
    combat_log_display = RichTextLabel.new()
    combat_log_display.name = "CombatLogDisplay"
    combat_log_display.custom_minimum_size = Vector2(400, 200)
    combat_log_display.bbcode_enabled = true
    combat_log_display.scroll_following = true
    combat_log_display.add_theme_font_size_override("normal_font_size", UI_FONT_SIZE_SMALL)
    combat_log_display.add_theme_font_size_override("bold_font_size", UI_FONT_SIZE_MEDIUM)
    combat_log_display.text = "[b]Next Battle[/b]\n\nSelect an enemy board and click 'Start Combat' to begin."
    
    # Add all elements to combat UI container
    combat_ui_container.add_child(health_container)
    combat_ui_container.add_child(enemy_selection_container)
    combat_ui_container.add_child(start_combat_button)
    combat_ui_container.add_child(combat_log_display)
    
    print("Combat UI created successfully")

func create_flash_message_system() -> void:
    """Create toast-style flash message system with rounded background and shadow"""
    # Create independent CanvasLayer for overlay messages
    flash_message_overlay = CanvasLayer.new()
    flash_message_overlay.name = "FlashMessageOverlay"
    flash_message_overlay.layer = 1  # Appear above main UI (layer 0)
    
    # Create container for toast-style background
    flash_message_container = PanelContainer.new()
    flash_message_container.name = "FlashMessageContainer"
    flash_message_container.visible = false
    flash_message_container.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't block clicks
    
    # Style the container with rounded background and shadow
    _create_toast_style_background()
    
    # Position container at bottom center
    flash_message_container.anchors_preset = Control.PRESET_CENTER_BOTTOM
    flash_message_container.anchor_top = 0.85
    flash_message_container.anchor_bottom = 0.85  # Single point anchor
    flash_message_container.anchor_left = 0.5
    flash_message_container.anchor_right = 0.5
    flash_message_container.offset_left = -200  # Half width for centering
    flash_message_container.offset_right = 200   # Half width for centering
    flash_message_container.offset_top = -25     # Height for container
    flash_message_container.offset_bottom = 25
    
    # Create flash message label
    flash_message_label = Label.new()
    flash_message_label.name = "FlashMessageLabel"
    flash_message_label.text = ""
    flash_message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    
    # Style the text
    apply_font_to_label(flash_message_label, UI_FONT_SIZE_MEDIUM)
    flash_message_label.add_theme_color_override("font_color", Color.WHITE)
    flash_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    flash_message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    
    # Add label to container, container to overlay, overlay to scene
    flash_message_container.add_child(flash_message_label)
    flash_message_overlay.add_child(flash_message_container)
    get_tree().current_scene.add_child.call_deferred(flash_message_overlay)
    
    # Tween will be created when needed (Godot 4.4 style)
    flash_message_tween = null
    
    print("Toast-style flash message system created")

func _create_toast_style_background() -> void:
    """Create the styled background for toast messages"""
    # Create a StyleBoxFlat for the rounded background
    var style_box = StyleBoxFlat.new()
    
    # Background color (dark semi-transparent)
    style_box.bg_color = Color(0.1, 0.1, 0.1, 0.9)  # Dark background with transparency
    
    # Rounded corners for toast effect
    style_box.corner_radius_top_left = 12
    style_box.corner_radius_top_right = 12
    style_box.corner_radius_bottom_left = 12
    style_box.corner_radius_bottom_right = 12
    
    # Padding for text breathing room
    style_box.content_margin_left = 20
    style_box.content_margin_right = 20
    style_box.content_margin_top = 12
    style_box.content_margin_bottom = 12
    
    # Shadow effect
    style_box.shadow_color = Color(0, 0, 0, 0.5)  # Semi-transparent black shadow
    style_box.shadow_size = 4
    style_box.shadow_offset = Vector2(2, 2)
    
    # Apply the style to the container
    flash_message_container.add_theme_stylebox_override("panel", style_box)

func populate_enemy_board_selector() -> void:
    """Populate enemy board dropdown with available options"""
    if not enemy_board_selector:
        return
        
    enemy_board_selector.clear()
    
    # Add enemy board options
    for board_name in EnemyBoards.get_enemy_board_names():
        var board_data = EnemyBoards.create_enemy_board(board_name)
        enemy_board_selector.add_item(board_data.get("name", board_name))
        
    print("Enemy board selector populated with %d options" % enemy_board_selector.get_item_count())

func connect_combat_ui_signals():
    """Connect combat UI element signals to game_board functions"""
    if start_combat_button:
        # Connect to the parent's (game_board.gd) signal handler
        start_combat_button.pressed.connect(get_parent()._on_start_combat_button_pressed)
        
    if enemy_board_selector:
        # Connect to the parent's (game_board.gd) signal handler  
        enemy_board_selector.item_selected.connect(get_parent()._on_enemy_board_selected)
        
    print("Combat UI signals connected to game_board handlers")

func connect_shop_ui_signals():
    """Connect shop UI element signals to game_board functions"""
    # Note: Shop button signals are connected in game_board.tscn, not here
    # This function is kept for consistency but no longer connects signals
    print("Shop UI signals connected in scene file")

func register_drag_drop_zones():
    """Register UI zones with the DragDropManager for drag-and-drop operations"""
    DragDropManager.register_ui_zones(player_hand, player_board, shop_area) 
