extends Control

const DEFAULT_PORT = 9999
const CardScene = preload("res://card.tscn")
const ShopManagerScript = preload("res://shop_manager.gd")
var dragged_card = null

# Core game state is now managed by GameState singleton
# Access via GameState.current_turn, GameState.current_gold, etc.

# Player Health System (Phase 2A.4) - now managed by GameState
@export var combat_damage: int = 5  # Keep this for UI configuration

signal game_over(winner: String)

# UI Manager reference
@onready var ui_manager = $MainLayout

# Shop Manager instance
var shop_manager: ShopManagerScript

# Combat Screen State Management - now using GameState.current_mode
var current_enemy_board_name: String = ""

# Combat Result Toggle System
var combat_view_toggle_button: Button
var current_combat_view: String = "log"  # "log" or "result"
var final_player_minions: Array = []     # Surviving CombatMinions
var final_enemy_minions: Array = []      # Surviving CombatMinions  
var original_player_count: int = 0       # For dead minion slots
var original_enemy_count: int = 0        # For dead minion slots

# Constants are now in GameState singleton

# Note: Hand/board size tracking and UI constants moved to UIManager

func _ready():
    # Note: UI setup is now handled by UIManager
    # Connect to GameState signals for game logic updates (UI signals handled by UIManager)
    GameState.game_over.connect(_on_game_over)
    
    # Initialize ShopManager
    shop_manager = ShopManagerScript.new(ui_manager.get_shop_container(), ui_manager)
    
    # Connect UI signals to game logic
    ui_manager.forward_card_clicked.connect(_on_card_clicked)
    ui_manager.forward_card_drag_started.connect(_on_card_drag_started)
    
    # Initialize game systems
    shop_manager.refresh_shop()

# === SIGNAL HANDLERS FOR GAMESTATE ===
func _on_game_over(winner: String):
    print("Game Over! Winner: ", winner)

func _on_card_clicked(card_node):
    # Don't show card details if we're in combat mode
    if GameState.current_mode == GameState.GameMode.COMBAT:
        return
        
    var shop_area = $MainLayout/ShopArea
    var card_id = card_node.name  # Assuming card_node.name is the card ID
    
    # Check if this is a shop card and if we can afford it
    if card_node.get_parent() == shop_area:
        var card_data = CardDatabase.get_card_data(card_id)
        var cost = card_data.get("cost", 3)
        
        if GameState.can_afford(cost):
            print("Can purchase ", card_id, " for ", cost, " gold")
        else:
            print("Cannot afford ", card_id, " - costs ", cost, " gold, have ", GameState.current_gold)

# Note: UI update functions moved to UIManager

# Convenience functions that delegate to UIManager
func get_hand_size() -> int:
    return ui_manager.get_hand_size()

func get_board_size() -> int:
    return ui_manager.get_board_size()

func is_hand_full() -> bool:
    return ui_manager.is_hand_full()

func is_board_full() -> bool:
    return ui_manager.is_board_full()

func update_hand_count():
    ui_manager.update_hand_display()

func update_board_count():
    ui_manager.update_board_display()

# Note: Most shop functions moved to ShopManager

func create_card_instance(card_data: Dictionary, card_id: String = ""):
    """Create the appropriate card instance based on card type"""
    var new_card = CardScene.instantiate()
    
    # Add card_id to card_data so it's preserved
    var enhanced_card_data = card_data.duplicate()
    if card_id != "":
        enhanced_card_data["id"] = card_id
    
    # If it's a minion, swap to MinionCard script
    if enhanced_card_data.get("type", "") == "minion":
        # Load and apply the MinionCard script dynamically
        var minion_script = load("res://minion_card.gd")
        new_card.set_script(minion_script)
    
    new_card.setup_card_data(enhanced_card_data)
    return new_card

func add_card_to_hand_direct(card_id: String):
    """Add a card directly to hand (delegated to ShopManager for purchase logic)"""
    # For purchases, delegate to ShopManager; for other uses, create card directly
    var card_data = CardDatabase.get_card_data(card_id)
    var new_card = create_card_instance(card_data, card_id)
    
    new_card.card_clicked.connect(_on_card_clicked)
    new_card.drag_started.connect(_on_card_drag_started)
    
    $MainLayout/PlayerHand.add_child(new_card)
    update_hand_count()

func add_generated_card_to_hand(card_id: String) -> bool:
    """Add a generated card (like The Coin) to hand - bypasses shop restrictions"""
    if is_hand_full():
        print("Cannot add generated card - hand is full")
        return false
    
    var card_data = CardDatabase.get_card_data(card_id)
    if card_data.is_empty():
        print("Cannot add generated card - card not found: ", card_id)
        return false
    
    var new_card = create_card_instance(card_data, card_id)
    
    new_card.card_clicked.connect(_on_card_clicked)
    new_card.drag_started.connect(_on_card_drag_started)
    
    $MainLayout/PlayerHand.add_child(new_card)
    update_hand_count()
    
    print("Added generated card to hand: ", card_data.get("name", "Unknown"))
    return true



# calculate_base_gold_for_turn() and start_new_turn() now in GameState singleton

func update_ui_displays():
    """Update all UI elements to reflect current game state"""
    # Update turn and gold displays (with null checks)
    var turn_label = get_node_or_null("MainLayout/TopUI/TurnLabel")
    if turn_label:
        turn_label.text = "Turn: " + str(GameState.current_turn)
    
    var gold_text = "Gold: " + str(GameState.current_gold) + "/" + str(GameState.player_base_gold)
    if GameState.bonus_gold > 0:
        gold_text += " (+" + str(GameState.bonus_gold) + ")"
    
    var gold_label = get_node_or_null("MainLayout/TopUI/GoldLabel")
    if gold_label:
        gold_label.text = gold_text
        
    var shop_tier_label = get_node_or_null("MainLayout/TopUI/ShopTierLabel")
    if shop_tier_label:
        shop_tier_label.text = "Shop Tier: " + str(GameState.shop_tier)
    
    # Update upgrade button text with current cost
    var upgrade_button = get_node_or_null("MainLayout/TopUI/UpgradeShopButton")
    if upgrade_button:
        var upgrade_cost = GameState.calculate_tavern_upgrade_cost()
        if upgrade_cost > 0:
            upgrade_button.text = "Upgrade Shop (" + str(upgrade_cost) + " gold)"
        else:
            upgrade_button.text = "Max Tier"
    
    # Update hand and board counts
    update_hand_count()
    update_board_count()

# All gold and tavern management functions moved to GameState singleton:
# - spend_gold(), can_afford(), increase_base_gold(), add_bonus_gold(), gain_gold()
# - calculate_tavern_upgrade_cost(), can_upgrade_tavern(), upgrade_tavern_tier()

# Note: get_hand_size(), get_board_size(), is_hand_full(), is_board_full() moved to UIManager delegation functions above
    
@rpc("any_peer", "call_local")
func add_card_to_hand(card_id):
    # The rest of the function is the same as before
    var data = CardDatabase.get_card_data(card_id)
    var new_card = create_card_instance(data, card_id)
    
    new_card.card_clicked.connect(_on_card_clicked)
    new_card.drag_started.connect(_on_card_drag_started) # Add this
    #new_card.dropped.connect(_on_card_dropped)
    $MainLayout/PlayerHand.add_child(new_card)
    update_hand_count() # Update the hand count display

func detect_drop_zone(global_pos: Vector2) -> String:
    """Detect which zone a card is being dropped into"""
    # Get the full container rectangles (including labels and empty space)
    var hand_rect = $MainLayout/PlayerHand.get_global_rect()
    var board_rect = $MainLayout/PlayerBoard.get_global_rect()
    var shop_rect = $MainLayout/ShopArea.get_global_rect()
    
    # Expand hand area to make it easier to drop into, especially upward toward center
    var expanded_hand_rect = Rect2(
        hand_rect.position.x - 30,  # 30 pixels left
        hand_rect.position.y - 100, # 100 pixels up (extends well toward center)
        hand_rect.size.x + 60,      # 30 pixels on each side (left + right)
        hand_rect.size.y + 130      # 100 pixels up + 30 pixels down
    )
    
    if expanded_hand_rect.has_point(global_pos):
        return "hand"
    elif board_rect.has_point(global_pos):
        return "board"
    elif shop_rect.has_point(global_pos):
        return "shop"
    else:
        return "invalid"

func get_card_origin_zone(card) -> String:
    """Determine which zone a card originated from"""
    # Check if card is in shop (skip the ShopAreaLabel)
    for shop_card in $MainLayout/ShopArea.get_children():
        if shop_card == card and shop_card.name != "ShopAreaLabel":
            return "shop"
    
    # Check if card is in hand
    for hand_card in $MainLayout/PlayerHand.get_children():
        if hand_card == card:
            return "hand"
    
    # Check if card is on board
    for board_card in $MainLayout/PlayerBoard.get_children():
        if board_card == card and board_card.name != "PlayerBoardLabel":
            return "board"
    
    return "unknown"

func _set_all_cards_mouse_filter(filter_mode: int, exclude_card = null):
    """Set mouse filter for all cards in hand, board, and shop (optionally excluding one card)"""
    # Cards in hand
    for hand_card in $MainLayout/PlayerHand.get_children():
        if hand_card != exclude_card:
            hand_card.mouse_filter = filter_mode
    
    # Cards on board  
    for board_card in $MainLayout/PlayerBoard.get_children():
        if board_card != exclude_card and board_card.name != "PlayerBoardLabel":
            board_card.mouse_filter = filter_mode
    
    # Cards in shop (skip the ShopAreaLabel)
    for shop_card in $MainLayout/ShopArea.get_children():
        if shop_card != exclude_card and shop_card.name != "ShopAreaLabel":
            shop_card.mouse_filter = filter_mode

func _on_card_drag_started(card):
    dragged_card = card # Keep track of the dragged card
    card.mouse_filter = Control.MOUSE_FILTER_IGNORE
    
    # Store the card's origin zone for drop handling
    var origin_zone = get_card_origin_zone(card)
    card.set_meta("origin_zone", origin_zone)
    print(card.name, " started dragging from ", origin_zone)
    
    # Set all other cards to ignore mouse events during dragging
    _set_all_cards_mouse_filter(Control.MOUSE_FILTER_IGNORE, card)
    
    # "Lift" the card out of the container by making it a child of the main board
    card.reparent(self)
    # Ensure the dragged card renders on top of everything else
    card.move_to_front()

func _on_card_dropped(card):
    var origin_zone = card.get_meta("origin_zone", "unknown")
    var drop_zone = detect_drop_zone(card.global_position)
    
    print(card.name, " dropped from ", origin_zone, " to ", drop_zone, " at position ", card.global_position)
    
    # Debug: print hand area bounds
    var hand_rect = $MainLayout/PlayerHand.get_global_rect()
    var expanded_hand_rect = Rect2(
        hand_rect.position.x - 30,
        hand_rect.position.y - 100,
        hand_rect.size.x + 60,
        hand_rect.size.y + 130
    )
    print("Hand area: ", hand_rect, " (expanded: ", expanded_hand_rect, ")")
    
    # Handle different drop scenarios
    match [origin_zone, drop_zone]:
        ["shop", "hand"]:
            _handle_shop_to_hand_drop(card)
        ["hand", "hand"]:
            _handle_hand_reorder_drop(card)
        ["hand", "board"]:
            _handle_hand_to_board_drop(card)
        ["board", "board"]:
            _handle_board_reorder_drop(card)
        ["board", "hand"]:
            _handle_board_to_hand_drop(card)
        ["shop", "board"], ["shop", "shop"], ["shop", "invalid"]:
            _handle_invalid_shop_drop(card)
        ["hand", "shop"], ["hand", "invalid"]:
            _handle_invalid_hand_drop(card)
        ["board", "shop"], ["board", "invalid"]:
            _handle_invalid_board_drop(card)
        _:
            print("Unhandled drop scenario: ", origin_zone, " -> ", drop_zone)
            _return_card_to_origin(card, origin_zone)
    
    # Restore mouse filters for all cards
    card.mouse_filter = Control.MOUSE_FILTER_STOP
    _set_all_cards_mouse_filter(Control.MOUSE_FILTER_STOP)
    
    dragged_card = null

func _handle_shop_to_hand_drop(card):
    """Handle purchasing a card by dragging from shop to hand"""
    # Delegate to ShopManager for purchase logic
    var success = shop_manager.handle_shop_card_purchase_by_drag(card)
    
    if success:
        # Purchase succeeded - clean up the dragged card node
        card.queue_free()
    else:
        # Return card to shop if purchase failed
        _return_card_to_shop(card)

func _handle_hand_reorder_drop(card):
    """Handle reordering cards within the hand"""
    var cards_in_hand = $MainLayout/PlayerHand.get_children()
    var new_index = -1

    # Find where to place the card based on its X position
    for i in range(cards_in_hand.size()):
        if card.global_position.x < cards_in_hand[i].global_position.x:
            new_index = i
            break

    # Put the card back into the hand container
    card.reparent($MainLayout/PlayerHand)

    # Move it to the calculated position
    if new_index != -1:
        $MainLayout/PlayerHand.move_child(card, new_index)
    else:
        # If it was dropped past the last card, move it to the end
        $MainLayout/PlayerHand.move_child(card, $MainLayout/PlayerHand.get_child_count() - 1)

func _handle_hand_to_board_drop(card):
    """Handle playing a minion from hand to board"""
    # Get card data to check if it's a minion
    var card_name = card.get_node("VBoxContainer/CardName").text
    var card_data = _find_card_data_by_name(card_name)
    
    if card_data.is_empty():
        print("Error: Could not find card data for ", card_name)
        _return_card_to_hand(card)
        return
    
    # Only minions can be played to the board
    if card_data.get("type", "") != "minion":
        print(card_name, " is not a minion - returning to hand")
        _return_card_to_hand(card)
        return
    
    # Check if board is full
    if is_board_full():
        print("Cannot play minion - board is full (", get_board_size(), "/", ui_manager.max_board_size, ")")
        _return_card_to_hand(card)
        return
    
    # Play the minion to the board
    _play_minion_to_board(card)
    print("Played ", card_name, " to board")

func _handle_invalid_shop_drop(card):
    """Handle invalid drops for shop cards"""
    print("Invalid drop for shop card - returning to shop")
    _return_card_to_shop(card)

func _handle_invalid_hand_drop(card):
    """Handle invalid drops for hand cards"""
    print("Invalid drop for hand card - returning to hand")
    _return_card_to_hand(card)

func _handle_board_reorder_drop(card):
    """Handle reordering minions within the board"""
    var cards_on_board = $MainLayout/PlayerBoard.get_children()
    var new_index = -1

    # Find where to place the minion based on its X position
    # Skip the label when calculating position
    for i in range(cards_on_board.size()):
        if cards_on_board[i].name == "PlayerBoardLabel":
            continue
        if card.global_position.x < cards_on_board[i].global_position.x:
            new_index = i
            break

    # Put the card back into the board container
    card.reparent($MainLayout/PlayerBoard)

    # Move it to the calculated position
    if new_index != -1:
        $MainLayout/PlayerBoard.move_child(card, new_index)
    else:
        # If it was dropped past the last card, move it to the end
        $MainLayout/PlayerBoard.move_child(card, $MainLayout/PlayerBoard.get_child_count() - 1)

func _handle_board_to_hand_drop(card):
    """Handle returning a minion from board to hand"""
    # Check if hand has space
    if is_hand_full():
        print("Cannot return minion to hand - hand is full (", get_hand_size(), "/", ui_manager.max_hand_size, ")")
        _return_card_to_board(card)
        return
    
    # Move minion back to hand
    card.reparent($MainLayout/PlayerHand)
    
    update_hand_count()
    update_board_count()
    print("Returned minion to hand")

func _handle_invalid_board_drop(card):
    """Handle invalid drops for board cards"""
    print("Invalid drop for board card - returning to board")
    _return_card_to_board(card)

func _return_card_to_origin(card, origin_zone: String):
    """Return card to its original zone"""
    match origin_zone:
        "shop":
            _return_card_to_shop(card)
        "hand":
            _return_card_to_hand(card)
        "board":
            _return_card_to_board(card)
        _:
            print("Cannot return card to unknown origin: ", origin_zone)
            card.queue_free()

func _return_card_to_shop(card):
    """Return a card to the shop area"""
    card.reparent($MainLayout/ShopArea)

func _return_card_to_hand(card):
    """Return a card to the hand area"""
    card.reparent($MainLayout/PlayerHand)

func _return_card_to_board(card):
    """Return a card to the board area"""
    card.reparent($MainLayout/PlayerBoard)

# Note: _convert_shop_card_to_hand_card moved to ShopManager

func _find_card_data_by_name(card_name: String) -> Dictionary:
    """Find card data by card name from the database"""
    for card_id in CardDatabase.get_all_card_ids():
        var card_data = CardDatabase.get_card_data(card_id)
        if card_data.get("name", "") == card_name:
            return card_data
    return {}

func _play_minion_to_board(card):
    """Move a minion card from hand to board with proper positioning"""
    var cards_on_board = $MainLayout/PlayerBoard.get_children()
    var new_index = -1
    
    # Find where to place the minion based on its X position
    # Skip the label when calculating position
    for i in range(cards_on_board.size()):
        if cards_on_board[i].name == "PlayerBoardLabel":
            continue
        if card.global_position.x < cards_on_board[i].global_position.x:
            new_index = i
            break
    
    # Move card to board
    card.reparent($MainLayout/PlayerBoard)
    
    # Position the card appropriately
    if new_index != -1:
        $MainLayout/PlayerBoard.move_child(card, new_index)
    else:
        # If dropped past the last card, move to end (but before label if it exists)
        $MainLayout/PlayerBoard.move_child(card, $MainLayout/PlayerBoard.get_child_count() - 1)
    
    # Update counts
    update_hand_count()
    update_board_count()

func _unhandled_input(event):
    if dragged_card: # This check is now primary
        if event is InputEventMouseMotion:
            dragged_card.global_position = get_global_mouse_position() - dragged_card.drag_offset
            # Update visual feedback during drag
            _update_drop_zone_feedback()

        if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
            # Clear visual feedback before dropping
            _clear_drop_zone_feedback()
            # Manually call the drop function when the mouse is released anywhere
            _on_card_dropped(dragged_card)

func _update_drop_zone_feedback():
    """Update visual feedback for valid drop zones during dragging"""
    if not dragged_card:
        return
    
    var origin_zone = dragged_card.get_meta("origin_zone", "unknown")
    var current_drop_zone = detect_drop_zone(get_global_mouse_position())
    
    # Clear all feedback first
    _clear_drop_zone_feedback()
    
    # Show feedback based on origin and current position
    match [origin_zone, current_drop_zone]:
        ["shop", "hand"]:
            # Valid purchase zone
            _highlight_container($MainLayout/PlayerHand, Color.GREEN)
        ["hand", "hand"]:
            # Valid reorder zone
            _highlight_container($MainLayout/PlayerHand, Color.BLUE)
        ["hand", "board"]:
            # Valid minion play zone (check if it's actually a minion)
            if _is_dragged_card_minion():
                _highlight_container($MainLayout/PlayerBoard, Color.CYAN)
            else:
                _highlight_container($MainLayout/PlayerBoard, Color.RED)
        ["board", "board"]:
            # Valid minion reorder zone
            _highlight_container($MainLayout/PlayerBoard, Color.CYAN)
        ["board", "hand"]:
            # Valid return to hand zone
            if not is_hand_full():
                _highlight_container($MainLayout/PlayerHand, Color.MAGENTA)
            else:
                _highlight_container($MainLayout/PlayerHand, Color.RED)
        ["shop", "board"], ["shop", "shop"]:
            # Invalid zones for shop cards
            _highlight_invalid_zone(current_drop_zone)

func _clear_drop_zone_feedback():
    """Clear all visual feedback for drop zones"""
    _remove_highlight($MainLayout/PlayerHand)
    _remove_highlight($MainLayout/PlayerBoard)
    _remove_highlight($MainLayout/ShopArea)

func _highlight_container(container: Container, color: Color):
    """Add visual highlight to a container"""
    # More visible modulation-based highlight
    container.modulate = Color(color.r, color.g, color.b, 0.7)

func _remove_highlight(container: Container):
    """Remove visual highlight from a container"""
    container.modulate = Color.WHITE

func _highlight_invalid_zone(zone_name: String):
    """Show feedback for invalid drop zones"""
    # For now, just ensure other zones aren't highlighted
    pass

func _is_dragged_card_minion() -> bool:
    """Check if the currently dragged card is a minion"""
    if not dragged_card:
        return false
    
    var card_name = dragged_card.get_node("VBoxContainer/CardName").text
    var card_data = _find_card_data_by_name(card_name)
    return card_data.get("type", "") == "minion"


func _cast_spell(spell_card, card_data: Dictionary):
    """Cast a spell card and apply its effects"""
    var spell_name = card_data.get("name", "Unknown Spell")
    print("Casting spell: ", spell_name)
    
    # Apply spell effects based on card
    match card_data.get("name", ""):
        "The Coin":
            # Gain 1 gold immediately
            GameState.gain_gold(1)
            print("Gained 1 gold from The Coin")
        _:
            print("Spell effect not implemented for: ", spell_name)
    
    # Remove the spell card from hand (spells are consumed when cast)
    spell_card.queue_free()
    update_hand_count()
    
    print("Spell ", spell_name, " cast and removed from hand")

# All health management functions moved to GameState singleton:
# - take_damage(), get_player_health(), get_enemy_health(), reset_health(), set_enemy_health()

# Combat UI Integration Functions (Phase 2B.2)

# Note: Combat UI functions moved to UIManager

# Combat Screen Mode Management

func switch_to_combat_mode(enemy_board_name: String) -> void:
    """Switch to combat screen view"""
    GameState.current_mode = GameState.GameMode.COMBAT
    current_enemy_board_name = enemy_board_name
    
    # Hide shop elements
    _hide_shop_elements()
    
    # Show enemy board in shop area
    _display_enemy_board_in_shop_area(enemy_board_name)
    
    # Update combat UI for combat mode
    _update_combat_ui_for_combat_mode()
    
    # Hide/minimize hand area
    _minimize_hand_area()
    
    print("Switched to combat mode vs %s" % enemy_board_name)

func switch_to_shop_mode() -> void:
    """Switch back to shop/tavern view"""
    GameState.current_mode = GameState.GameMode.SHOP
    current_enemy_board_name = ""
    
    # Restore original shop area label
    $MainLayout/ShopArea/ShopAreaLabel.text = "Shop"
    $MainLayout/ShopArea/ShopAreaLabel.remove_theme_color_override("font_color")
    
    # Show shop elements
    _show_shop_elements()
    
    # Clear enemy board from shop area
    _clear_enemy_board_from_shop_area()
    
    # Restore original player board (in case we were in result view)
    _restore_original_player_board()
    
    # Reset battle selection display (clear previous combat log)
    if ui_manager.combat_log_display:
        ui_manager.combat_log_display.clear()
        ui_manager.combat_log_display.text = "[b]Next Battle[/b]\n\nSelect an enemy board and click 'Start Combat' to begin."
    
    # Update combat UI for shop mode
    _update_combat_ui_for_shop_mode()
    
    # Show hand area normally
    _show_hand_area()
    
    print("Switched to shop mode")

func _hide_shop_elements() -> void:
    """Hide shop cards and shop-related buttons"""
    # Hide shop cards (but keep the ShopAreaLabel visible)
    for child in $MainLayout/ShopArea.get_children():
        if child.name != "ShopAreaLabel":
            child.visible = false
    
    # Hide shop-related buttons
    $MainLayout/TopUI/RefreshShopButton.visible = false
    $MainLayout/TopUI/UpgradeShopButton.visible = false

func _show_shop_elements() -> void:
    """Show shop cards and shop-related buttons"""
    # Show shop cards (label should already be visible)
    for child in $MainLayout/ShopArea.get_children():
        child.visible = true
    
    # Show shop-related buttons
    $MainLayout/TopUI/RefreshShopButton.visible = true
    $MainLayout/TopUI/UpgradeShopButton.visible = true

func _display_enemy_board_in_shop_area(enemy_board_name: String) -> void:
    """Create and display enemy minions in the shop area"""
    var enemy_board_data = EnemyBoards.create_enemy_board(enemy_board_name)
    if enemy_board_data.is_empty():
        print("Failed to load enemy board: %s" % enemy_board_name)
        return
    
    # Update the existing shop area label to show enemy board
    $MainLayout/ShopArea/ShopAreaLabel.text = "Enemy Board: %s" % enemy_board_data.get("name", enemy_board_name)
    $MainLayout/ShopArea/ShopAreaLabel.add_theme_color_override("font_color", Color.RED)
    
    # Create visual representations of enemy minions
    for i in range(enemy_board_data.get("minions", []).size()):
        var enemy_minion_data = enemy_board_data.minions[i]
        var card_data = CardDatabase.get_card_data(enemy_minion_data.card_id).duplicate()
        
        # Apply any buffs to the card data for display
        for buff_data in enemy_minion_data.get("buffs", []):
            if buff_data.type == "stat_modification":
                card_data.attack += buff_data.get("attack_bonus", 0)
                card_data.health += buff_data.get("health_bonus", 0)
        
        # Create enemy card display
        var enemy_card = create_card_instance(card_data, enemy_minion_data.card_id)
        enemy_card.name = "EnemyMinion_%d" % i
        
        # Make enemy cards non-interactive
        enemy_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
        
        # Add visual indication this is an enemy
        enemy_card.modulate = Color(1.0, 0.8, 0.8)  # Slight red tint
        
        $MainLayout/ShopArea.add_child(enemy_card)

func _clear_enemy_board_from_shop_area() -> void:
    """Remove enemy minions from shop area"""
    var children_to_remove = []
    for child in $MainLayout/ShopArea.get_children():
        if (child.name.begins_with("EnemyMinion_") or 
            child.name.begins_with("EnemyResult_") or
            child.name.begins_with("EnemyDead_")) and child.name != "ShopAreaLabel":
            children_to_remove.append(child)
    
    for child in children_to_remove:
        child.queue_free()

func _minimize_hand_area() -> void:
    """Minimize hand area during combat"""
    $MainLayout/PlayerHand.visible = false

func _show_hand_area() -> void:
    """Show hand area normally during shop phase"""
    $MainLayout/PlayerHand.visible = true

func _update_combat_ui_for_combat_mode() -> void:
    """Update combat UI elements for combat mode"""
    if ui_manager.start_combat_button:
        ui_manager.start_combat_button.visible = false
    
    if ui_manager.enemy_board_selector:
        ui_manager.enemy_board_selector.get_parent().visible = false
    
    # Create return to shop button if it doesn't exist
    if not ui_manager.return_to_shop_button:
        ui_manager.return_to_shop_button = Button.new()
        ui_manager.return_to_shop_button.name = "ReturnToShopButton"
        ui_manager.return_to_shop_button.text = "Return to Shop"
        ui_manager.apply_font_to_button(ui_manager.return_to_shop_button, ui_manager.UI_FONT_SIZE_MEDIUM)
        ui_manager.combat_ui_container.add_child(ui_manager.return_to_shop_button)
        ui_manager.return_to_shop_button.pressed.connect(_on_return_to_shop_button_pressed)
    
    # Hide toggle button (no longer needed)
    if ui_manager.combat_view_toggle_button:
        ui_manager.combat_view_toggle_button.visible = false
    
    ui_manager.return_to_shop_button.visible = true
    
    # Make combat UI and log prominent and always visible
    if ui_manager.combat_ui_container:
        ui_manager.combat_ui_container.visible = true
        
    if ui_manager.combat_log_display:
        ui_manager.combat_log_display.custom_minimum_size = Vector2(600, 300)
        ui_manager.combat_log_display.add_theme_font_size_override("normal_font_size", ui_manager.UI_FONT_SIZE_MEDIUM)
        ui_manager.combat_log_display.add_theme_font_size_override("bold_font_size", ui_manager.UI_FONT_SIZE_LARGE)
        ui_manager.combat_log_display.visible = true

func _update_combat_ui_for_shop_mode() -> void:
    """Update combat UI elements for shop mode"""
    if ui_manager.start_combat_button:
        ui_manager.start_combat_button.visible = true
    
    if ui_manager.enemy_board_selector:
        ui_manager.enemy_board_selector.get_parent().visible = true
    
    if ui_manager.combat_view_toggle_button:
        ui_manager.combat_view_toggle_button.visible = false
    
    if ui_manager.return_to_shop_button:
        ui_manager.return_to_shop_button.visible = false
    
    # Keep combat UI container visible but minimize combat log during shop mode
    if ui_manager.combat_ui_container:
        ui_manager.combat_ui_container.visible = true
        
    if ui_manager.combat_log_display:
        ui_manager.combat_log_display.custom_minimum_size = Vector2(400, 200)
        ui_manager.combat_log_display.visible = true  # Keep visible for "Next Battle" display

# Combat Result Toggle View Functions

func _show_combat_result_view() -> void:
    """Show the final combat result with surviving minions and tombstones"""
    # Hide combat log
    if ui_manager.combat_log_display:
        ui_manager.combat_log_display.visible = false
    
    # Clear current enemy board display
    _clear_enemy_board_from_shop_area()
    
    # Show final board states
    _display_final_player_board()
    _display_final_enemy_board()
    
    print("Showing combat result view")

func _show_combat_log_view() -> void:
    """Show the combat log view (default)"""
    # Show combat log
    if ui_manager.combat_log_display:
        ui_manager.combat_log_display.visible = true
    
    # Clear result view
    _clear_enemy_board_from_shop_area()
    
    # Restore original player board (in case we were in result view)
    _restore_original_player_board()
    
    # Show original enemy board preview
    _display_enemy_board_in_shop_area(current_enemy_board_name)
    
    print("Showing combat log view")

func _show_combat_result_with_log() -> void:
    """Show the combined combat result view with both log and final board states"""
    # Combat log is already visible and populated
    
    # Clear current enemy board display
    _clear_enemy_board_from_shop_area()
    
    # Show final board states
    _display_final_player_board_with_dead()
    _display_final_enemy_board_with_dead()
    
    print("Showing combined combat result with log")

func _display_final_player_board_with_dead() -> void:
    """Update player board to show final combat state with dead minions visible"""
    # Hide original minions instead of removing them
    for child in $MainLayout/PlayerBoard.get_children():
        if child.name != "PlayerBoardLabel":
            child.visible = false
    
    # Show surviving minions with updated health
    for i in range(original_player_count):
        var surviving_minion = null
        
        # Find surviving minion at this position
        for minion in final_player_minions:
            if minion.position == i:
                surviving_minion = minion
                break
        
        if surviving_minion:
            # Create card showing final state
            var card_data = CardDatabase.get_card_data(surviving_minion.source_card_id).duplicate()
            card_data.attack = surviving_minion.current_attack
            card_data.health = surviving_minion.current_health
            var result_card = create_card_instance(card_data, surviving_minion.source_card_id)
            
            # Apply health color (orange for damaged, red for dead)
            _apply_health_color_to_card_enhanced(result_card, surviving_minion.current_health, surviving_minion.max_health)
            
            # Mark as result card for cleanup
            result_card.name = "PlayerResult_%d" % i
            $MainLayout/PlayerBoard.add_child(result_card)
        else:
            # Create dead minion display (greyed out with red health)
            var dead_minion = _create_dead_minion_card(i, true)
            dead_minion.name = "PlayerDead_%d" % i
            $MainLayout/PlayerBoard.add_child(dead_minion)

func _display_final_enemy_board_with_dead() -> void:
    """Display final enemy board state in shop area with dead minions visible"""
    # Update the existing shop area label to show final state
    $MainLayout/ShopArea/ShopAreaLabel.text = "Enemy Final State"
    $MainLayout/ShopArea/ShopAreaLabel.add_theme_color_override("font_color", Color.RED)
    
    # Show surviving enemy minions with dead minions
    for i in range(original_enemy_count):
        var surviving_minion = null
        
        # Find surviving minion at this position
        for minion in final_enemy_minions:
            if minion.position == i:
                surviving_minion = minion
                break
        
        if surviving_minion:
            # Create card showing final state
            var card_data = CardDatabase.get_card_data(surviving_minion.source_card_id).duplicate()
            card_data.attack = surviving_minion.current_attack
            card_data.health = surviving_minion.current_health
            var result_card = create_card_instance(card_data, surviving_minion.source_card_id)
            
            # Apply enemy visual style and health color
            result_card.modulate = Color(1.0, 0.8, 0.8)  # Red tint
            result_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
            _apply_health_color_to_card_enhanced(result_card, surviving_minion.current_health, surviving_minion.max_health)
            
            result_card.name = "EnemyResult_%d" % i
            $MainLayout/ShopArea.add_child(result_card)
        else:
            # Create dead enemy minion display (greyed out with red health)
            var dead_minion = _create_dead_minion_card(i, false)
            dead_minion.name = "EnemyDead_%d" % i
            $MainLayout/ShopArea.add_child(dead_minion)

func _display_final_player_board() -> void:
    """Update player board to show final combat state"""
    # Hide original minions instead of removing them
    for child in $MainLayout/PlayerBoard.get_children():
        if child.name != "PlayerBoardLabel":
            child.visible = false
    
    # Show surviving minions with updated health
    for i in range(original_player_count):
        var surviving_minion = null
        
        # Find surviving minion at this position
        for minion in final_player_minions:
            if minion.position == i:
                surviving_minion = minion
                break
        
        if surviving_minion:
            # Create card showing final state
            var card_data = CardDatabase.get_card_data(surviving_minion.source_card_id).duplicate()
            card_data.attack = surviving_minion.current_attack
            card_data.health = surviving_minion.current_health
            var result_card = create_card_instance(card_data, surviving_minion.source_card_id)
            
            # Apply health color (orange for damaged)
            _apply_health_color_to_card(result_card, surviving_minion.current_health, surviving_minion.max_health)
            
            # Mark as result card for cleanup
            result_card.name = "PlayerResult_%d" % i
            $MainLayout/PlayerBoard.add_child(result_card)
        else:
            # Create dead minion display (greyed out with red health)
            var dead_minion = _create_dead_minion_card(i, true)
            dead_minion.name = "PlayerDead_%d" % i
            $MainLayout/PlayerBoard.add_child(dead_minion)

func _display_final_enemy_board() -> void:
    """Display final enemy board state in shop area"""
    # Update the existing shop area label to show final state
    $MainLayout/ShopArea/ShopAreaLabel.text = "Enemy Final State"
    $MainLayout/ShopArea/ShopAreaLabel.add_theme_color_override("font_color", Color.RED)
    
    # Show surviving enemy minions with tombstones
    for i in range(original_enemy_count):
        var surviving_minion = null
        
        # Find surviving minion at this position
        for minion in final_enemy_minions:
            if minion.position == i:
                surviving_minion = minion
                break
        
        if surviving_minion:
            # Create card showing final state
            var card_data = CardDatabase.get_card_data(surviving_minion.source_card_id).duplicate()
            card_data.attack = surviving_minion.current_attack
            card_data.health = surviving_minion.current_health
            var result_card = create_card_instance(card_data, surviving_minion.source_card_id)
            
            # Apply enemy visual style and health color
            result_card.modulate = Color(1.0, 0.8, 0.8)  # Red tint
            result_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
            _apply_health_color_to_card(result_card, surviving_minion.current_health, surviving_minion.max_health)
            
            result_card.name = "EnemyResult_%d" % i
            $MainLayout/ShopArea.add_child(result_card)
        else:
            # Create dead enemy minion display (greyed out with red health)
            var dead_minion = _create_dead_minion_card(i, false)
            dead_minion.name = "EnemyDead_%d" % i
            $MainLayout/ShopArea.add_child(dead_minion)

func _create_dead_minion_card(position: int, is_player: bool) -> Control:
    """Create a card showing a dead minion (greyed out with red health)"""
    # Find the original minion data at this position
    var original_card_data = {}
    var original_minions = []
    
    # Get original minion data from current board before combat
    if is_player:
        for child in $MainLayout/PlayerBoard.get_children():
            if child.has_method("get_effective_attack") and child.name != "PlayerBoardLabel":
                original_minions.append(child.card_data.duplicate())
    else:
        # For enemy, we need to reconstruct from the enemy board name
        var enemy_board_data = EnemyBoards.create_enemy_board(current_enemy_board_name)
        for enemy_minion_data in enemy_board_data.get("minions", []):
            var card_data = CardDatabase.get_card_data(enemy_minion_data.card_id).duplicate()
            # Apply buffs
            for buff_data in enemy_minion_data.get("buffs", []):
                if buff_data.type == "stat_modification":
                    card_data.attack += buff_data.get("attack_bonus", 0)
                    card_data.health += buff_data.get("health_bonus", 0)
            original_minions.append(card_data)
    
    # Get card data for this position
    if position < original_minions.size():
        original_card_data = original_minions[position].duplicate()
    else:
        # Fallback if position is out of range
        original_card_data = {
            "name": "Unknown Minion",
            "description": "",
            "attack": 0,
            "health": 0,
            "id": "unknown"
        }
    
    # Set health to 0 for dead minion display
    original_card_data.health = 0
    
    var dead_card = create_card_instance(original_card_data, original_card_data.get("id", "unknown"))
    
    # Apply greyed-out visual style
    dead_card.modulate = Color(0.6, 0.6, 0.6, 0.8)
    dead_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
    
    # Make health text red for dead minions
    var stats_label = dead_card.get_node_or_null("VBoxContainer/BottomRow/StatsLabel")
    if stats_label:
        stats_label.add_theme_color_override("font_color", Color.RED)
    
    return dead_card

func _apply_health_color_to_card(card: Control, current_health: int, max_health: int) -> void:
    """Apply orange color to health text if minion is damaged"""
    var stats_label = card.get_node_or_null("VBoxContainer/BottomRow/StatsLabel")
    if stats_label and current_health < max_health:
        # Damaged minion - make health orange
        stats_label.add_theme_color_override("font_color", Color.ORANGE)
    elif stats_label:
        # Full health - normal color
        stats_label.add_theme_color_override("font_color", Color.WHITE)

func _apply_health_color_to_card_enhanced(card: Control, current_health: int, max_health: int) -> void:
    """Apply color to health text: red for dead (<=0), orange for damaged, white for full"""
    var stats_label = card.get_node_or_null("VBoxContainer/BottomRow/StatsLabel")
    if stats_label:
        if current_health <= 0:
            # Dead minion - make health red
            stats_label.add_theme_color_override("font_color", Color.RED)
        elif current_health < max_health:
            # Damaged minion - make health orange
            stats_label.add_theme_color_override("font_color", Color.ORANGE)
        else:
            # Full health - normal color
            stats_label.add_theme_color_override("font_color", Color.WHITE)

func _restore_original_player_board() -> void:
    """Restore the player board to its original state (before combat result view)"""
    var children_to_remove = []
    
    for child in $MainLayout/PlayerBoard.get_children():
        if child.name != "PlayerBoardLabel":
            # Remove result cards and dead minion cards
            if (child.name.begins_with("PlayerResult_") or 
                child.name.begins_with("PlayerDead_")):
                children_to_remove.append(child)
            else:
                # Show original minions that were hidden
                child.visible = true
                
                # Reset any color overrides that might have been applied
                var stats_label = child.get_node_or_null("VBoxContainer/BottomRow/StatsLabel")
                if stats_label:
                    stats_label.remove_theme_color_override("font_color")
                
                # Reset modulation
                child.modulate = Color.WHITE
    
    # Remove result cards and tombstones
    for child in children_to_remove:
        child.queue_free()

func display_combat_log(action_log: Array) -> void:
    """Display combat actions in the combat log"""
    if not ui_manager.combat_log_display:
        return
        
    ui_manager.combat_log_display.clear()
    ui_manager.combat_log_display.append_text("[b]BATTLE LOG[/b]\n\n")
    
    for action in action_log:
        var log_line = format_combat_action(action)
        ui_manager.combat_log_display.append_text(log_line + "\n")

func format_combat_action(action: Dictionary) -> String:
    """Format a combat action for display"""
    match action.get("type", ""):
        "combat_start":
            return "Combat begins! Player: %d minions vs Enemy: %d minions" % [action.get("player_minions", 0), action.get("enemy_minions", 0)]
        "attack":
            return "%s attacks %s (%d/%d vs %d/%d)" % [
                action.get("attacker_id", "?"), 
                action.get("defender_id", "?"), 
                action.get("attacker_attack", 0),
                action.get("attacker_health", 0),
                action.get("defender_attack", 0),
                action.get("defender_health", 0)
            ]
        "damage":
            return "%s takes %d damage (health: %d)" % [action.get("target_id", "?"), action.get("amount", 0), action.get("new_health", 0)]
        "death":
            return "%s dies!" % action.get("target_id", "?")
        "combat_end":
            return "Combat ends! Winner: %s" % action.get("winner", "?")
        "combat_tie":
            var reason = action.get("reason", "unknown")
            match reason:
                "both_no_minions":
                    return "Combat tied! Neither player has minions"
                _:
                    return "Combat tied! (%s)" % reason
        "auto_loss":
            return "%s loses automatically (%s)" % [action.get("loser", "?"), action.get("reason", "?")]
        "turn_start":
            return "[b][color=cyan]Turn %d begins![/color][/b] Gold and shop refreshed." % action.get("turn", 0)
        "first_attacker":
            var attacker = action.get("attacker", "unknown")
            var reason = action.get("reason", "unknown")
            match reason:
                "more_minions":
                    return "[b]%s attacks first (more minions)[/b]" % attacker.capitalize()
                "random_equal_minions":
                    return "[b]%s attacks first (equal minions, random choice)[/b]" % attacker.capitalize()
                _:
                    return "[b]%s attacks first (%s)[/b]" % [attacker.capitalize(), reason]
        _:
            return "Unknown action: %s" % str(action)

# Combat UI Event Handlers (Phase 2B.2)

func _on_start_combat_button_pressed() -> void:
    """Handle start combat button press"""
    if not ui_manager.enemy_board_selector:
        print("Error: Enemy board selector not available")
        return
        
    var selected_index = ui_manager.enemy_board_selector.selected
    var board_names = EnemyBoards.get_enemy_board_names()
    
    if selected_index < 0 or selected_index >= board_names.size():
        print("Error: Invalid enemy board selection")
        return
        
    var selected_board_name = board_names[selected_index]
    print("Starting combat against: %s" % selected_board_name)
    
    # Switch to combat screen
    switch_to_combat_mode(selected_board_name)
    
    # Run combat simulation and display results
    var combat_result = simulate_full_combat(selected_board_name)
    display_combat_log(combat_result)
    
    # Automatically show the combined result view (log + final board states)
    _show_combat_result_with_log()

# Combat view toggle function removed - now showing combined result view only

func _on_return_to_shop_button_pressed() -> void:
    """Handle return to shop button press"""
    print("Return to shop button pressed")
    
    # Return to shop mode
    switch_to_shop_mode()
    
    # Start next turn after combat
    GameState.start_new_turn()

func _on_refresh_shop_button_pressed() -> void:
    """Handle refresh shop button press"""
    shop_manager.handle_refresh_button_pressed()

func _on_upgrade_shop_button_pressed() -> void:
    """Handle upgrade shop button press"""
    shop_manager.handle_upgrade_button_pressed()

func _on_end_turn_button_pressed() -> void:
    """Handle end turn button press"""
    print("End turn button pressed")
    GameState.start_new_turn()
    print("Started turn %d" % GameState.current_turn)

func _on_enemy_board_selected(index: int) -> void:
    """Handle enemy board selection from dropdown"""
    if index < 0 or index >= ui_manager.enemy_board_selector.get_item_count():
        return
    
    var selected_board = ui_manager.enemy_board_selector.get_item_text(index)
    current_enemy_board_name = selected_board
    
    # Update enemy health based on selected board
    var board_data = EnemyBoards.create_enemy_board(selected_board)
    GameState.set_enemy_health(board_data.get("health", GameState.enemy_health))
    
    print("Selected enemy board: %s (Health: %d)" % [board_data.get("name", selected_board), board_data.get("health", GameState.enemy_health)])
    
    # Update health displays (handled by UIManager automatically via signals)

# Enhanced Combat Algorithm (Phase 2B.3)

func pick_random_from_array(array: Array):
    """Helper function to pick a random element from an array"""
    if array.is_empty():
        return null
    return array[randi() % array.size()]

func run_combat(player_minions: Array, enemy_minions: Array) -> Array:
    """Enhanced combat algorithm with improved turn-based logic"""
    var action_log = []
    var p_attacker_index = 0
    var e_attacker_index = 0
    var attack_count = 0
    var max_attacks = 500
    
    action_log.append({
        "type": "combat_start", 
        "player_minions": player_minions.size(), 
        "enemy_minions": enemy_minions.size()
    })
    
    # Check for immediate win conditions (empty armies)
    if player_minions.is_empty() and enemy_minions.is_empty():
        action_log.append({"type": "combat_tie", "reason": "both_no_minions"})
        return action_log
    elif player_minions.is_empty():
        action_log.append({"type": "combat_end", "winner": "enemy", "reason": "player_no_minions"})
        GameState.take_damage(combat_damage, true)
        return action_log
    elif enemy_minions.is_empty():
        action_log.append({"type": "combat_end", "winner": "player", "reason": "enemy_no_minions"})
        GameState.take_damage(combat_damage, false)
        return action_log
    
    # Determine who goes first: more minions = first attack, equal count = random
    var p_turn: bool
    if player_minions.size() > enemy_minions.size():
        p_turn = true
        action_log.append({"type": "first_attacker", "attacker": "player", "reason": "more_minions"})
    elif enemy_minions.size() > player_minions.size():
        p_turn = false
        action_log.append({"type": "first_attacker", "attacker": "enemy", "reason": "more_minions"})
    else:
        # Equal minions - random first attacker
        p_turn = randi() % 2 == 0
        var first_attacker = "player" if p_turn else "enemy"
        action_log.append({"type": "first_attacker", "attacker": first_attacker, "reason": "random_equal_minions"})
    
    # Main combat loop
    while attack_count < max_attacks:
        # Check if combat should continue (both sides have minions)
        if player_minions.is_empty() or enemy_minions.is_empty():
            # This should be caught by the post-attack win condition check,
            # but this is a safety check for the first iteration
            break
        
        # Current player has minions - select attacker and defender
        var attacker
        var defender
        
        if p_turn:
            # Player attacks
            if p_attacker_index >= player_minions.size(): 
                p_attacker_index = 0
            attacker = player_minions[p_attacker_index]
            defender = pick_random_from_array(enemy_minions)
        else:
            # Enemy attacks
            if e_attacker_index >= enemy_minions.size(): 
                e_attacker_index = 0
            attacker = enemy_minions[e_attacker_index]
            defender = pick_random_from_array(player_minions)
        
        # Check if we have valid attacker and defender before executing attack
        if attacker == null or defender == null:
            action_log.append({"type": "combat_end", "reason": "null_combatant", "winner": "tie"})
            break
        
        # Execute attack (even 0-damage attacks count as attempts)
        execute_attack(attacker, defender, action_log)
        attack_count += 1
        
        # Remove dead minions
        player_minions = player_minions.filter(func(m): return m.current_health > 0)
        enemy_minions = enemy_minions.filter(func(m): return m.current_health > 0)
        
        # Check win conditions after removing dead minions
        if player_minions.is_empty() and enemy_minions.is_empty():
            action_log.append({"type": "combat_tie", "reason": "both_no_minions"})
            break
        elif player_minions.is_empty():
            action_log.append({"type": "combat_end", "winner": "enemy", "reason": "player_no_minions"})
            GameState.take_damage(combat_damage, true)
            break
        elif enemy_minions.is_empty():
            action_log.append({"type": "combat_end", "winner": "player", "reason": "enemy_no_minions"})
            GameState.take_damage(combat_damage, false)
            break
        
        # Advance turn
        if p_turn:
            p_attacker_index += 1
        else:
            e_attacker_index += 1
        p_turn = not p_turn
    
    # Handle max attacks reached
    if attack_count >= max_attacks:
        action_log.append({"type": "combat_tie", "reason": "max_attacks_reached"})
    
    # Store final combat state for result view
    final_player_minions = player_minions.duplicate(true)
    final_enemy_minions = enemy_minions.duplicate(true)
    
    # Don't auto-advance turn - player uses "Return to Shop" button to advance turn
    
    return action_log

func execute_attack(attacker, defender, action_log: Array) -> void:
    """Execute a single attack between two minions"""
    var damage_to_defender = attacker.get_effective_attack()
    var damage_to_attacker = defender.get_effective_attack()
    
    # Capture health BEFORE damage for logging
    var attacker_health_before = attacker.current_health
    var defender_health_before = defender.current_health
    
    # Apply damage
    defender.take_damage(damage_to_defender)
    attacker.take_damage(damage_to_attacker)
    
    # Log the attack with health BEFORE damage
    action_log.append({
        "type": "attack",
        "attacker_id": attacker.get_display_name(),
        "defender_id": defender.get_display_name(),
        "attacker_attack": attacker.get_effective_attack(),
        "defender_attack": defender.get_effective_attack(),
        "damage_dealt": damage_to_defender,
        "damage_received": damage_to_attacker,
        "attacker_health": attacker_health_before,
        "defender_health": defender_health_before
    })
    
    # Check for deaths and log them
    if defender.current_health <= 0:
        action_log.append({
            "type": "death",
            "target_id": defender.get_display_name()
        })
    
    if attacker.current_health <= 0:
        action_log.append({
            "type": "death", 
            "target_id": attacker.get_display_name()
        })

func simulate_full_combat(enemy_board_name: String) -> Array:
    """Simulate a complete combat and return the action log"""
    print("=== COMBAT SIMULATION START ===")
    
    # Create combat armies
    var player_army = create_player_combat_army()
    var enemy_army = create_enemy_combat_army(enemy_board_name)
    
    # Store original counts for result view  
    original_player_count = player_army.size()
    original_enemy_count = enemy_army.size()
    
    print("Player army: %d minions vs Enemy army (%s): %d minions" % [player_army.size(), enemy_board_name, enemy_army.size()])
    
    # Run the actual combat simulation
    var combat_log = run_combat(player_army, enemy_army)
    
    print("=== COMBAT SIMULATION COMPLETE ===")
    return combat_log

# NEW: Tavern Phase Buff Application Functions

func apply_tavern_buff_to_minion(target_minion, buff) -> void:  # target_minion: MinionCard
    """Apply persistent buff during tavern phase"""
    if target_minion == null or buff == null:
        print("Invalid target minion or buff")
        return
    
    # Verify this is a minion that can receive buffs
    if not target_minion.has_method("add_persistent_buff"):
        print("Target is not a minion card - cannot apply buff")
        return
    
    # Set buff as permanent since it's applied during tavern phase
    buff.duration = Buff.Duration.PERMANENT
    
    # Add to persistent buffs (survives between combats)
    target_minion.add_persistent_buff(buff)
    
    print("Applied %s to %s during tavern phase" % [buff.display_name, target_minion.card_data.get("name", "Unknown")])

func apply_tavern_upgrade_all_minions(attack_bonus: int, health_bonus: int) -> void:
    """Apply tavern upgrade buff to all player minions on board"""
    print("Applying tavern upgrade buff: +%d/+%d to all minions" % [attack_bonus, health_bonus])
    
    var minion_count = 0
    for child in $MainLayout/PlayerBoard.get_children():
        if child.name != "PlayerBoardLabel" and child.has_method("get_card_data"):
            var card_data = child.get_card_data()
            if card_data.get("type") == "minion":
                # Apply the buff
                var current_attack = card_data.get("attack", 0)
                var current_health = card_data.get("health", 1)
                
                card_data["attack"] = current_attack + attack_bonus
                card_data["health"] = current_health + health_bonus
                
                # Update the card display
                child.setup_card_data(card_data)
                minion_count += 1
    
    print("Applied tavern upgrade to %d minions" % minion_count)

func find_minion_by_unique_id(unique_id: String):  # -> Card
    """Find board minion by unique ID to handle duplicates"""
    for child in $MainLayout/PlayerBoard.get_children():
        if child.has_method("add_persistent_buff") and child.unique_board_id == unique_id:
            return child
    return null

func create_stat_modification_buff(buff_id: String, display_name: String, attack_bonus: int, health_bonus: int) -> StatModificationBuff:
    """Create a stat modification buff using the proper buff class"""
    var buff = StatModificationBuff.new()
    buff.buff_id = buff_id
    buff.display_name = display_name
    buff.attack_bonus = attack_bonus
    buff.health_bonus = health_bonus
    buff.max_health_bonus = health_bonus  # Health bonus also increases max health
    buff.duration = Buff.Duration.PERMANENT  # Use proper enum value
    buff.stackable = false
    return buff

# === Test functions removed for GameState migration completion ===
# Will implement proper testing system later

# Combat preparation functions
func create_player_combat_army() -> Array:
    """Create CombatMinion array from player's board"""
    var combat_army = []
    var minion_index = 0
    
    for child in $MainLayout/PlayerBoard.get_children():
        if child.name != "PlayerBoardLabel" and child.has_method("get_card_data"):
            var card_data = child.get_card_data()
            if card_data.get("type") == "minion":
                var combat_minion = CombatMinion.create_from_board_minion(child, "player_%d" % minion_index)
                combat_army.append(combat_minion)
                minion_index += 1
    
    print("Created player combat army: %d minions" % combat_army.size())
    return combat_army

func create_enemy_combat_army(enemy_board_name: String) -> Array:
    """Create CombatMinion array from enemy board definition"""
    var enemy_board_data = EnemyBoards.create_enemy_board(enemy_board_name)
    var combat_army = []
    var minion_index = 0
    
    for minion_data in enemy_board_data.get("minions", []):
        var combat_minion = CombatMinion.create_from_enemy_data(minion_data, "enemy_%d" % minion_index)
        combat_army.append(combat_minion)
        minion_index += 1
    
    print("Created enemy combat army: %d minions" % combat_army.size())
    return combat_army

# Duplicate test_combat_minion_system function removed - original exists earlier in file

# simulate_combat_preparation test function removed
