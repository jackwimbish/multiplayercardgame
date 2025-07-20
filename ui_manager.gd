# UIManager.gd
# Manages all UI elements and updates for the game board
extends Control
class_name UIManager

# UI Font sizes (moved from game_board.gd)
const UI_FONT_SIZE_TITLE = 32    # Title text for victory/loss screens
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

# Victory/Loss screen overlays
var game_over_overlay: CanvasLayer
var victory_screen: PanelContainer
var loss_screen: PanelContainer

# Help overlay system
var help_overlay: CanvasLayer
var help_panel: PanelContainer
var help_content: RichTextLabel
var help_scroll: ScrollContainer
var help_toggle_button: Button
var is_help_visible: bool = false

# Game limits for UI display
var max_hand_size: int = 10
var max_board_size: int = 7

func _ready():
    print("UIManager initialized")
    setup_ui()
    connect_gamestate_signals()
    register_drag_drop_zones()
    set_process_unhandled_input(true)

func setup_ui():
    """Initialize all UI elements and styling"""
    apply_ui_font_sizing()
    create_combat_ui()
    create_flash_message_system()
    create_game_over_overlays()
    create_help_overlay()
    populate_enemy_board_selector()
    # Note: Help button is created later by game_board after mode indicator
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
    GameState.game_mode_changed.connect(update_help_visibility)

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
        var local_player = GameState.get_local_player()
        if local_player and local_player.shop_tier >= 6:
            upgrade_button.text = "Max Tier"
        else:
            var upgrade_cost = GameState.calculate_tavern_upgrade_cost()
            if upgrade_cost >= 0:
                upgrade_button.text = "Upgrade Shop (" + str(upgrade_cost) + " gold)"
            else:
                # Fallback for practice mode
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
        if new_tier >= 6:
            upgrade_button.text = "Max Tier"
        else:
            var upgrade_cost = GameState.calculate_tavern_upgrade_cost()
            if upgrade_cost >= 0:
                upgrade_button.text = "Upgrade Shop (" + str(upgrade_cost) + " gold)"
            else:
                # This shouldn't happen, but fallback to Max Tier
                upgrade_button.text = "Max Tier"

func update_shop_tier_display_detailed():
    """Update shop tier and upgrade button with current state - replaces game_board direct access"""
    var local_player = GameState.get_local_player()
    
    if shop_tier_label:
        var tier = local_player.shop_tier if local_player else GameState.shop_tier
        shop_tier_label.text = "Shop Tier: " + str(tier)
    
    if upgrade_button:
        if local_player:
            if local_player.shop_tier >= 6:
                upgrade_button.text = "Max Tier"
            else:
                var upgrade_cost = local_player.current_tavern_upgrade_cost
                upgrade_button.text = "Upgrade Shop (" + str(upgrade_cost) + " gold)"
        else:
            # Fallback for practice mode
            if GameState.shop_tier >= 6:
                upgrade_button.text = "Max Tier"
            else:
                var upgrade_cost = GameState.calculate_tavern_upgrade_cost()
                if upgrade_cost >= 0:
                    upgrade_button.text = "Upgrade Shop (" + str(upgrade_cost) + " gold)"
                else:
                    # This shouldn't happen, but fallback
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
    if GameModeManager.is_in_multiplayer_session():
        # Multiplayer: Show both player names with health
        var local_player = GameState.get_local_player()
        var opponent = GameState.get_opponent_player()
        
        print("UIManager updating health displays - %s: %d, %s: %d" % [
            local_player.player_name if local_player else "Player",
            local_player.player_health if local_player else 0,
            opponent.player_name if opponent else "Opponent", 
            opponent.player_health if opponent else 0
        ])
        
        if player_health_label and local_player:
            player_health_label.text = "%s: %d HP" % [local_player.player_name, local_player.player_health]
            print("Updated player health label to: ", player_health_label.text)
        
        if enemy_health_label and opponent:
            enemy_health_label.text = "%s: %d HP" % [opponent.player_name, opponent.player_health]
            print("Updated enemy health label to: ", enemy_health_label.text)
    else:
        # Practice mode: Show generic labels
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
    """Get current number of cards in hand from game state"""
    var player = GameState.get_local_player()
    if player:
        return player.hand_cards.size()
    return 0

func get_board_size() -> int:
    """Get current number of minions on board from game state"""
    var player = GameState.get_local_player()
    if player:
        return player.board_minions.size()
    return 0

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

# === WAITING INDICATOR SYSTEM ===

var waiting_indicators = {}

func show_waiting_indicator(element_name: String):
    """Show waiting state for UI element"""
    waiting_indicators[element_name] = true
    
    match element_name:
        "refresh_button":
            if refresh_button:
                refresh_button.disabled = true
                refresh_button.text = "Refreshing..."
        "freeze_button":
            if freeze_button:
                freeze_button.disabled = true
                freeze_button.text = "Updating..."
        "upgrade_button":
            if upgrade_button:
                upgrade_button.disabled = true
                upgrade_button.text = "Upgrading..."
        "shop":
            # Could add a shop overlay or disable all shop cards
            pass

func hide_waiting_indicator(element_name: String):
    """Hide waiting state for UI element"""
    waiting_indicators.erase(element_name)
    
    match element_name:
        "refresh_button":
            if refresh_button:
                refresh_button.disabled = false
                update_refresh_button_text()
        "freeze_button":
            if freeze_button:
                freeze_button.disabled = false
                update_freeze_button_text()
        "upgrade_button":
            if upgrade_button:
                upgrade_button.disabled = false
                update_upgrade_button_text()
        "shop":
            # Remove shop overlay if added
            pass

func hide_all_waiting_indicators():
    """Hide all waiting indicators"""
    for element in waiting_indicators:
        hide_waiting_indicator(element)
    waiting_indicators.clear()

func update_refresh_button_text():
    """Update refresh button text based on cost"""
    if refresh_button:
        refresh_button.text = "Refresh (1)"  # REFRESH_COST

func update_freeze_button_text():
    """Update freeze button text based on state"""
    if freeze_button:
        var local_player = GameState.get_local_player()
        if local_player and local_player.shop_cards.size() > 0:
            # Check if all cards are frozen
            var all_frozen = true
            for card_id in local_player.shop_cards:
                if not card_id in local_player.frozen_card_ids:
                    all_frozen = false
                    break
            freeze_button.text = "Unfreeze" if all_frozen else "Freeze"
        else:
            freeze_button.text = "Freeze"

func update_upgrade_button_text():
    """Update upgrade button text based on tier and cost"""
    if upgrade_button:
        var local_player = GameState.get_local_player()
        if local_player:
            if local_player.shop_tier >= 6:
                upgrade_button.text = "Max Tier"
            else:
                var upgrade_cost = local_player.current_tavern_upgrade_cost
                upgrade_button.text = "Upgrade Shop (%d gold)" % upgrade_cost

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

func create_help_overlay() -> void:
    """Create the help overlay system"""
    # Note: Help button is created separately by create_help_button()
    
    # Create the overlay layer
    help_overlay = CanvasLayer.new()
    help_overlay.name = "HelpOverlay"
    help_overlay.layer = 5  # Above game but below game over screens
    add_child(help_overlay)
    
    # Create semi-transparent panel covering right side
    help_panel = PanelContainer.new()
    help_panel.name = "HelpPanel"
    
    # Position on right side of screen
    help_panel.anchor_left = 0.5  # Start from middle of screen
    help_panel.anchor_top = 0.0
    help_panel.anchor_right = 1.0
    help_panel.anchor_bottom = 1.0
    help_panel.offset_left = 0
    help_panel.offset_top = 0
    help_panel.offset_right = 0
    help_panel.offset_bottom = 0
    
    # Semi-transparent dark background
    var style_box = StyleBoxFlat.new()
    style_box.bg_color = Color(0.1, 0.1, 0.1, 0.85)  # Dark semi-transparent
    style_box.border_width_left = 2
    style_box.border_width_right = 2
    style_box.border_width_top = 2
    style_box.border_width_bottom = 2
    style_box.border_color = Color(0.3, 0.3, 0.3, 0.8)
    style_box.corner_radius_top_left = 5
    style_box.corner_radius_top_right = 5
    style_box.corner_radius_bottom_left = 5
    style_box.corner_radius_bottom_right = 5
    help_panel.add_theme_stylebox_override("panel", style_box)
    
    # Create scroll container
    help_scroll = ScrollContainer.new()
    help_scroll.name = "HelpScroll"
    help_panel.add_child(help_scroll)
    
    # Create content label
    help_content = RichTextLabel.new()
    help_content.name = "HelpContent"
    help_content.bbcode_enabled = true
    help_content.fit_content = true
    help_content.scroll_active = false  # Let ScrollContainer handle scrolling
    help_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    help_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
    help_content.add_theme_font_size_override("normal_font_size", UI_FONT_SIZE_MEDIUM)
    help_content.add_theme_font_size_override("bold_font_size", UI_FONT_SIZE_LARGE)
    help_content.add_theme_color_override("default_color", Color.WHITE)
    help_content.text = _get_help_text()
    
    # Add padding
    var margin_container = MarginContainer.new()
    margin_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    margin_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
    margin_container.add_theme_constant_override("margin_left", 20)
    margin_container.add_theme_constant_override("margin_right", 20)
    margin_container.add_theme_constant_override("margin_top", 20)
    margin_container.add_theme_constant_override("margin_bottom", 20)
    margin_container.add_child(help_content)
    help_scroll.add_child(margin_container)
    
    help_overlay.add_child(help_panel)
    help_panel.visible = false
    
    print("Help overlay created")

func create_game_over_overlays() -> void:
    """Create victory and loss screen overlays"""
    # Create the overlay layer
    game_over_overlay = CanvasLayer.new()
    game_over_overlay.name = "GameOverOverlay"
    game_over_overlay.layer = 10  # Above everything else
    add_child(game_over_overlay)
    
    # Create victory screen
    victory_screen = _create_victory_screen()
    game_over_overlay.add_child(victory_screen)
    victory_screen.visible = false
    
    # Create loss screen
    loss_screen = _create_loss_screen()
    game_over_overlay.add_child(loss_screen)
    loss_screen.visible = false
    
    print("Game over overlays created")

func _create_victory_screen() -> PanelContainer:
    """Create the victory screen overlay"""
    var screen = PanelContainer.new()
    screen.name = "VictoryScreen"
    
    # Full screen
    screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    screen.mouse_filter = Control.MOUSE_FILTER_STOP  # Block input to game
    
    # Dark background
    var style_box = StyleBoxFlat.new()
    style_box.bg_color = Color(0.1, 0.15, 0.1, 0.95)  # Dark green tint
    screen.add_theme_stylebox_override("panel", style_box)
    
    # Content container
    var vbox = VBoxContainer.new()
    vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    vbox.alignment = BoxContainer.ALIGNMENT_CENTER
    screen.add_child(vbox)
    
    # Victory title
    var title = Label.new()
    title.text = "VICTORY!"
    title.add_theme_font_size_override("font_size", UI_FONT_SIZE_TITLE)
    title.add_theme_color_override("font_color", Color.GOLD)
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    vbox.add_child(title)
    
    # Add spacing
    var spacer1 = Control.new()
    spacer1.custom_minimum_size.y = 40
    vbox.add_child(spacer1)
    
    # Placement label
    var placement_label = Label.new()
    placement_label.name = "PlacementLabel"
    placement_label.text = "1st Place"
    placement_label.add_theme_font_size_override("font_size", UI_FONT_SIZE_LARGE)
    placement_label.add_theme_color_override("font_color", Color.WHITE)
    placement_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    vbox.add_child(placement_label)
    
    # Add spacing
    var spacer2 = Control.new()
    spacer2.custom_minimum_size.y = 60
    vbox.add_child(spacer2)
    
    # Return to menu button
    var menu_button = Button.new()
    menu_button.name = "ReturnToMenuButton"
    menu_button.text = "Return to Menu"
    menu_button.custom_minimum_size = Vector2(200, 50)
    apply_font_to_button(menu_button, UI_FONT_SIZE_MEDIUM)
    menu_button.pressed.connect(_on_return_to_menu_pressed)
    vbox.add_child(menu_button)
    
    return screen

func _create_loss_screen() -> PanelContainer:
    """Create the loss screen overlay"""
    var screen = PanelContainer.new()
    screen.name = "LossScreen"
    
    # Full screen
    screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    screen.mouse_filter = Control.MOUSE_FILTER_STOP  # Block input to game
    
    # Dark background
    var style_box = StyleBoxFlat.new()
    style_box.bg_color = Color(0.15, 0.1, 0.1, 0.95)  # Dark red tint
    screen.add_theme_stylebox_override("panel", style_box)
    
    # Content container
    var vbox = VBoxContainer.new()
    vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    vbox.alignment = BoxContainer.ALIGNMENT_CENTER
    screen.add_child(vbox)
    
    # Loss title
    var title = Label.new()
    title.text = "DEFEATED"
    title.add_theme_font_size_override("font_size", UI_FONT_SIZE_TITLE)
    title.add_theme_color_override("font_color", Color.CRIMSON)
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    vbox.add_child(title)
    
    # Add spacing
    var spacer1 = Control.new()
    spacer1.custom_minimum_size.y = 40
    vbox.add_child(spacer1)
    
    # Placement label
    var placement_label = Label.new()
    placement_label.name = "PlacementLabel"
    placement_label.text = "2nd Place"
    placement_label.add_theme_font_size_override("font_size", UI_FONT_SIZE_LARGE)
    placement_label.add_theme_color_override("font_color", Color.WHITE)
    placement_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    vbox.add_child(placement_label)
    
    # Add spacing
    var spacer2 = Control.new()
    spacer2.custom_minimum_size.y = 60
    vbox.add_child(spacer2)
    
    # Return to menu button
    var menu_button = Button.new()
    menu_button.name = "ReturnToMenuButton"
    menu_button.text = "Return to Menu"
    menu_button.custom_minimum_size = Vector2(200, 50)
    apply_font_to_button(menu_button, UI_FONT_SIZE_MEDIUM)
    menu_button.pressed.connect(_on_return_to_menu_pressed)
    vbox.add_child(menu_button)
    
    return screen

func _on_return_to_menu_pressed() -> void:
    """Handle return to menu button press"""
    print("Return to menu pressed from game over screen")
    GameModeManager.request_return_to_menu()

func show_victory_screen(placement: int = 1) -> void:
    """Show the victory screen with placement"""
    if victory_screen:
        var placement_label = victory_screen.find_child("PlacementLabel", true, false)
        if placement_label:
            placement_label.text = _get_placement_text(placement)
        victory_screen.visible = true
        print("Showing victory screen - ", _get_placement_text(placement))

func show_loss_screen(placement: int) -> void:
    """Show the loss screen with placement"""
    if loss_screen:
        var placement_label = loss_screen.find_child("PlacementLabel", true, false)
        if placement_label:
            placement_label.text = _get_placement_text(placement)
        loss_screen.visible = true
        print("Showing loss screen - ", _get_placement_text(placement))

func _get_placement_text(placement: int) -> String:
    """Convert placement number to text"""
    match placement:
        1: return "1st Place"
        2: return "2nd Place"
        3: return "3rd Place"
        _: return str(placement) + "th Place"

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
    style_box.set_content_margin(SIDE_LEFT, 20)
    style_box.set_content_margin(SIDE_RIGHT, 20)
    style_box.set_content_margin(SIDE_TOP, 12)
    style_box.set_content_margin(SIDE_BOTTOM, 12)
    
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

# === HELP OVERLAY FUNCTIONS ===

func create_help_button() -> void:
    """Create the help toggle button at the beginning of TopUI"""
    # Get the TopUI container
    var top_ui = get_node_or_null("TopUI")
    if not top_ui:
        print("Could not find TopUI container for help button")
        return
    
    # Create the help button
    help_toggle_button = Button.new()
    help_toggle_button.name = "HelpToggleButton"
    help_toggle_button.text = "How to Play"
    help_toggle_button.add_theme_font_size_override("font_size", UI_FONT_SIZE_MEDIUM)
    
    # Style the button to match other TopUI buttons
    help_toggle_button.flat = false
    help_toggle_button.custom_minimum_size = Vector2(120, 40)
    
    # Add to TopUI container at the beginning
    top_ui.add_child(help_toggle_button)
    top_ui.move_child(help_toggle_button, 0)  # Put at the very beginning
    
    # Add a separator after the help button for right margin
    var separator = VSeparator.new()
    separator.custom_minimum_size.x = 20  # Add 20 pixels of spacing to the right
    top_ui.add_child(separator)
    top_ui.move_child(separator, 1)  # Put right after the help button
    
    # Connect signal
    help_toggle_button.pressed.connect(_on_help_toggle_pressed)
    
    # Initially visible only during shop phase
    help_toggle_button.visible = GameState.current_mode == GameState.GameMode.SHOP

func _on_help_toggle_pressed() -> void:
    """Toggle the help overlay visibility"""
    is_help_visible = !is_help_visible
    
    if help_panel:
        help_panel.visible = is_help_visible
        
    # Update button text
    if help_toggle_button:
        help_toggle_button.text = "Close Help Window" if is_help_visible else "How to Play"

func _get_help_text() -> String:
    """Return the help content as BBCode formatted text"""
    return """[b][u]How to Play OpenBattlefields[/u][/b]

[b]Game Basics:[/b]
OpenBattlefields is an auto-battler where you build a team of minions to fight against opponents. The last player standing wins!

[b]Card Stats:[/b]
The numbers on the bottom left of each card show [color=yellow]Attack/Health[/color]
• [b]Attack:[/b] Damage dealt when attacking
• [b]Health:[/b] Damage needed to destroy the minion

[b]Turn Structure:[/b]
Each turn consists of two phases:
• [b]Shop Phase:[/b] Buy minions, arrange your board, and prepare for combat
• [b]Combat Phase:[/b] Your minions automatically battle an opponent

[b]Shopping:[/b]
• Minions cost [color=yellow]3 gold[/color] each
• Drag a minion from the shop to your hand to buy it
• Drag a minion from your hand to the board to play it
• Drag a minion from your board to the shop to sell it for [color=yellow]1 gold[/color]
• You can have up to 10 cards in hand and 7 minions on board
• [b]Refresh Shop:[/b] Get new minions for [color=yellow]1 gold[/color]
• [b]Freeze Shop:[/b] Keep current minions for next turn (free)
• [b]Upgrade Shop:[/b] Unlock higher tier minions (cost decreases each turn)

[b]Economy:[/b]
• You start with [color=yellow]3 gold[/color]
• Gold increases by 1 each turn (max [color=yellow]10 gold[/color])
• Selling minions gives you [color=yellow]1 gold[/color] back

[b]Combat:[/b]
• Minions attack from left to right
• Each minion attacks a random enemy minion
• Both minions deal damage simultaneously
• Combat continues until one side has no minions left
• The loser takes damage to their health
• When your health reaches 0, you're eliminated

[b]Controls:[/b]
• [b]Drag & Drop:[/b] Move cards between shop, hand, and board
• [b]Right Click:[/b] Cancel pending action (e.g., battlecry targeting)
• [b]H Key:[/b] Toggle this help window

[b]Tips:[/b]
• Position matters! Minions attack from left to right
• Save gold to upgrade your shop tier for stronger minions
• Build synergies between minions for powerful combos
• Watch your opponent's board to counter their strategy"""

func update_help_visibility(mode: GameState.GameMode) -> void:
    """Update help button visibility based on game mode"""
    if help_toggle_button:
        # Only show during shop mode
        help_toggle_button.visible = (mode == GameState.GameMode.SHOP)
        
        # Hide overlay if button is hidden
        if not help_toggle_button.visible and is_help_visible:
            is_help_visible = false
            if help_panel:
                help_panel.visible = false
            help_toggle_button.text = "How to Play"

func _unhandled_input(event: InputEvent) -> void:
    """Handle keyboard input for help overlay"""
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_H:
            # Only toggle if button is visible (shop phase)
            if help_toggle_button and help_toggle_button.visible:
                _on_help_toggle_pressed()
                get_viewport().set_input_as_handled() 
