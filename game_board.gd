extends Control

const DEFAULT_PORT = 9999
# Preload manager scripts
const ShopManagerScript = preload("res://shop_manager.gd")
const CombatManagerScript = preload("res://combat_manager.gd")
# dragged_card removed - now tracked by DragDropManager

# Core game state is now managed by GameState singleton
# Access via GameState.current_turn, GameState.current_gold, etc.

signal game_over(winner: String)

# UI Manager reference
@onready var ui_manager = $MainLayout

# Manager instances
var shop_manager
var combat_manager

# Battlecry selection state
var is_selecting_battlecry_target: bool = false
var battlecry_card_being_played: Node = null
var battlecry_card_id: String = ""
var battlecry_board_position: int = -1

# Constants are now in GameState singleton

# Note: Hand/board size tracking and UI constants moved to UIManager

func _ready():
    # Add to game_board group for CardFactory access
    add_to_group("game_board")
    
    # Initialize GameState for the current game mode
    GameState.initialize_game_state()
    
    # Enable input for battlecry handling
    set_process_unhandled_input(true)
    
    # Setup game mode specific features
    setup_game_mode()
    
    # Note: UI setup is now handled by UIManager
    # Connect to GameState signals for game logic updates (UI signals handled by UIManager)
    GameState.game_over.connect(_on_game_over)
    GameState.player_eliminated.connect(_on_player_eliminated)
    GameState.player_victorious.connect(_on_player_victorious)
    
    # Initialize ShopManager
    shop_manager = ShopManagerScript.new(ui_manager.get_shop_container(), ui_manager)

    # Initialize CombatManager with ShopManager reference for auto-refresh
    combat_manager = CombatManagerScript.new(ui_manager, $MainLayout, shop_manager)
    
    # Connect UI signals to game logic
    ui_manager.forward_card_clicked.connect(_on_card_clicked)
    ui_manager.forward_card_drag_started.connect(_on_card_drag_started)
    
    # Connect DragDropManager signals
    DragDropManager.card_drag_ended.connect(_on_card_drag_ended)
    
    # Initialize game systems
    # In SSOT architecture, shops are dealt by host after initialization
    # No local shop refresh needed
    
    # Connect shop manager to player signals for multiplayer updates
    _connect_shop_to_player_signals()

func _connect_shop_to_player_signals():
    """Connect shop manager to player state signals"""
    # In SSOT architecture, no signal connections needed
    # All updates come through NetworkManager._update_local_player_display()
    pass

func setup_game_mode():
    """Setup game mode specific features"""
    print("Setting up game for mode: ", GameModeManager.get_mode_name())
    
    # Add mode-specific UI indicators
    add_mode_indicator()
    
    # Add Return to Menu button for practice mode
    if GameModeManager.is_practice_mode():
        add_return_to_menu_button()
    
    # Set initial combat UI visibility for multiplayer mode
    if GameModeManager.is_in_multiplayer_session():
        # In multiplayer, only host can start combat
        if ui_manager.start_combat_button:
            ui_manager.start_combat_button.visible = GameState.is_host()
        # Hide enemy board selector in multiplayer
        if ui_manager.enemy_board_selector:
            ui_manager.enemy_board_selector.get_parent().visible = false

func add_mode_indicator():
    """Add a mode indicator to show current game mode"""
    # Get the top UI container
    var top_ui = ui_manager.get_node("TopUI")
    if not top_ui:
        print("Could not find TopUI container")
        return
    
    # Create mode indicator label
    var mode_label = Label.new()
    mode_label.name = "ModeIndicator"
    var mode_text = GameModeManager.get_mode_name() + " • " + GameModeManager.get_player_name()
    
    # Add host indicator in multiplayer
    if GameModeManager.is_in_multiplayer_session():
        if GameState.is_host():
            mode_text += " (Host)"
        else:
            mode_text += " (Client)"
    
    mode_label.text = mode_text
    mode_label.size_flags_horizontal = Control.SIZE_SHRINK_END
    
    # Style the label
    ui_manager.apply_font_to_label(mode_label, ui_manager.UI_FONT_SIZE_SMALL)
    
    # Set color based on mode
    if GameModeManager.is_practice_mode():
        mode_label.add_theme_color_override("font_color", Color.CYAN)
    else:
        mode_label.add_theme_color_override("font_color", Color.ORANGE)
    
    # Add to top UI at the beginning
    top_ui.add_child(mode_label)
    top_ui.move_child(mode_label, 0)
    
    print("Mode indicator added: ", mode_label.text)

func add_return_to_menu_button():
    """Add a Return to Menu button to the UI"""
    # Get the top UI container
    var top_ui = ui_manager.get_node("TopUI")
    if not top_ui:
        print("Could not find TopUI container")
        return
    
    # Create return to menu button
    var return_button = Button.new()
    return_button.name = "ReturnToMenuButton"
    return_button.text = "Return to Menu"
    return_button.size_flags_horizontal = Control.SIZE_SHRINK_END
    
    # Style the button
    ui_manager.apply_font_to_button(return_button, ui_manager.UI_FONT_SIZE_SMALL)
    
    # Connect signal
    return_button.pressed.connect(_on_return_to_menu_pressed)
    
    # Add to top UI
    top_ui.add_child(return_button)
    top_ui.move_child(return_button, 0)  # Move to front
    
    print("Return to Menu button added")

func _on_return_to_menu_pressed():
    """Handle return to menu button press"""
    print("Return to menu requested")
    GameModeManager.request_return_to_menu()

# === SIGNAL HANDLERS FOR GAMESTATE ===
func _on_game_over(winner: String):
    print("Game Over! Winner: ", winner)

func _on_player_eliminated(player_id: int, placement: int):
    """Handle when a player is eliminated"""
    print("Player ", player_id, " eliminated at ", placement, " place")
    
    # If it's the local player, show the loss screen
    if player_id == GameState.local_player_id:
        ui_manager.show_loss_screen(placement)

func _on_player_victorious(player_id: int):
    """Handle when a player wins"""
    print("Player ", player_id, " is victorious!")
    
    # If it's the local player, show the victory screen
    if player_id == GameState.local_player_id:
        ui_manager.show_victory_screen(1)

func _on_card_clicked(card_node):
    # Check if we're in battlecry target selection mode
    if is_selecting_battlecry_target:
        # Check if the clicked card is on the board
        if card_node.get_parent() == ui_manager.get_board_container():
            # Find the index of this card on the board
            var board_container = ui_manager.get_board_container()
            var index = 0
            for child in board_container.get_children():
                if child == card_node and child.has_meta("card_id"):
                    _on_battlecry_target_selected(index)
                    return
                elif child.has_meta("card_id"):
                    index += 1
        return
    
    # Don't show card details if we're in combat mode
    if GameState.current_mode == GameState.GameMode.COMBAT:
        return
        
    var card_id = card_node.name  # Assuming card_node.name is the card ID
    
    # Check if this is a shop card and if we can afford it
    if ui_manager.is_card_in_shop(card_node):
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

# Note: Card creation now handled by CardFactory autoload singleton

func add_card_to_hand_direct(card_id: String):
    """Add a card directly to hand (delegated to ShopManager for purchase logic)"""
    # For purchases, delegate to ShopManager; for other uses, create card directly
    var card_data = CardDatabase.get_card_data(card_id)
    var new_card = CardFactory.create_interactive_card(card_data, card_id)
    
    # Store card_id for board state sync
    new_card.set_meta("card_id", card_id)
    
    ui_manager.get_hand_container().add_child(new_card)
    # Count will update when state changes

func add_generated_card_to_hand(card_id: String) -> bool:
    """Add a generated card (like The Coin) to hand - bypasses shop restrictions"""
    if is_hand_full():
        print("Cannot add generated card - hand is full")
        return false
    
    var card_data = CardDatabase.get_card_data(card_id)
    if card_data.is_empty():
        print("Cannot add generated card - card not found: ", card_id)
        return false
    
    var new_card = CardFactory.create_interactive_card(card_data, card_id)
    
    # Store card_id for board state sync
    new_card.set_meta("card_id", card_id)
    
    ui_manager.get_hand_container().add_child(new_card)
    update_hand_count()
    
    print("Added generated card to hand: ", card_data.get("name", "Unknown"))
    return true



# calculate_base_gold_for_turn() and start_new_turn() now in GameState singleton

# update_ui_displays removed - now handled by UIManager.update_all_game_displays()

# All gold and tavern management functions moved to GameState singleton:
# - spend_gold(), can_afford(), increase_base_gold(), add_bonus_gold(), gain_gold()
# - calculate_tavern_upgrade_cost(), can_upgrade_tavern(), upgrade_tavern_tier()

# Note: get_hand_size(), get_board_size(), is_hand_full(), is_board_full() moved to UIManager delegation functions above
    
@rpc("any_peer", "call_local")
func add_card_to_hand(card_id):
    # The rest of the function is the same as before
    var data = CardDatabase.get_card_data(card_id)
    var new_card = CardFactory.create_interactive_card(data, card_id)
    
    # Store card_id for board state sync
    new_card.set_meta("card_id", card_id)
    
    #new_card.dropped.connect(_on_card_dropped)
    ui_manager.get_hand_container().add_child(new_card)
    update_hand_count() # Update the hand count display

# detect_drop_zone, get_card_origin_zone, _set_all_cards_mouse_filter moved to DragDropManager

func _on_card_drag_started(card, offset = Vector2.ZERO):
    # Delegate to DragDropManager
    DragDropManager.start_drag(card, offset)

func _on_card_drag_ended(card, origin_zone: String, drop_zone: String):
    """Handle card drop events from DragDropManager"""
    print(card.name, " dropped from ", origin_zone, " to ", drop_zone, " at position ", card.global_position)
    
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
            _handle_board_to_hand_drop(card)  # Now handles this as invalid
        ["board", "shop"]:
            _handle_board_to_shop_drop(card)  # Sell minion for gold
        ["shop", "board"], ["shop", "shop"], ["shop", "invalid"]:
            _handle_invalid_shop_drop(card)
        ["hand", "shop"], ["hand", "invalid"]:
            _handle_invalid_hand_drop(card)
        ["board", "invalid"]:
            _handle_invalid_board_drop(card)
        _:
            print("Unhandled drop scenario: ", origin_zone, " -> ", drop_zone)
            _return_card_to_origin(card, origin_zone)

func _handle_shop_to_hand_drop(card):
    """Handle purchasing a card by dragging from shop to hand"""
    if GameModeManager.is_in_multiplayer_session():
        var drag_data = shop_manager.get_card_drag_data(card)
        
        # Send purchase request
        NetworkManager.request_game_action.rpc_id(
            GameState.host_player_id,
            "purchase_card",
            drag_data
        )
        
        # Return card to shop - visual state will update when host responds
        _return_card_to_shop(card)
        
        # Show subtle feedback that action was registered
        ui_manager.show_flash_message("Purchasing...", 0.5)
    else:
        print("Practice mode not implemented in SSOT architecture")
        _return_card_to_shop(card)

func _handle_hand_reorder_drop(card):
    """Handle reordering cards within the hand"""
    var hand_container = ui_manager.get_hand_container()
    var cards_in_hand = hand_container.get_children()
    var new_index = -1

    # Find where to place the card based on its X position
    for i in range(cards_in_hand.size()):
        if card.global_position.x < cards_in_hand[i].global_position.x:
            new_index = i
            break

    # Put the card back into the hand container
    card.reparent(hand_container)

    # Move it to the calculated position
    if new_index != -1:
        hand_container.move_child(card, new_index)
    else:
        # If it was dropped past the last card, move it to the end
        hand_container.move_child(card, hand_container.get_child_count() - 1)

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
    
    # In multiplayer, use the new play_card action
    if GameModeManager.is_in_multiplayer_session():
        var card_id = card.get_meta("card_id", "")
        if card_id == "":
            # Try to find by name if no ID meta
            for id in CardDatabase.get_all_card_ids():
                if CardDatabase.get_card_data(id).get("name", "") == card_name:
                    card_id = id
                    break
        
        if card_id != "":
            # Check if card has battlecry
            var abilities = card_data.get("abilities", [])
            var has_targetable_battlecry = false
            
            for ability in abilities:
                if ability.get("type") == "battlecry" and ability.get("target") == "other_friendly_minion":
                    has_targetable_battlecry = true
                    break
            
            # Calculate board position
            var board_container = ui_manager.get_board_container()
            var board_position = _calculate_board_drop_position(card, board_container)
            
            # If has battlecry and there are valid targets, enter selection mode
            if has_targetable_battlecry and get_board_size() > 0:
                # Store card info for later
                battlecry_card_being_played = card
                battlecry_card_id = card_id
                battlecry_board_position = board_position
                
                # Return card to hand during selection
                _return_card_to_hand(card)
                
                # Enter target selection mode
                _enter_battlecry_target_mode()
            else:
                # No battlecry or no valid targets - play normally
                _complete_play_card(card, card_id, board_position, -1)
        else:
            print("Error: Could not find card ID for ", card_name)
            _return_card_to_hand(card)
    else:
        # Practice mode - just move visually
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
    if GameModeManager.is_in_multiplayer_session():
        # Build new board order
        var board_container = ui_manager.get_board_container()
        var new_board_order = []
        
        # Get all cards except the one being moved
        for child in board_container.get_children():
            if child.has_meta("card_id") and child != card:
                new_board_order.append(child.get_meta("card_id"))
        
        # Find where to insert the moved card
        var insert_position = _calculate_board_drop_position(card, board_container)
        var card_id = card.get_meta("card_id", "")
        
        if insert_position >= new_board_order.size():
            new_board_order.append(card_id)
        else:
            new_board_order.insert(insert_position, card_id)
        
        # Request reorder action
        NetworkManager.request_game_action.rpc_id(
            GameState.host_player_id,
            "reorder_board",
            {"board_minions": new_board_order}
        )
        
        # Return card to original position (will be updated when state syncs)
        _return_card_to_board(card)
        
        # Show subtle feedback
        ui_manager.show_flash_message("Reordering...", 0.3)
    else:
        # Practice mode - just reorder visually
        var board_container = ui_manager.get_board_container()
        var cards_on_board = board_container.get_children()
        var new_index = -1

        # Find where to place the minion based on its X position
        for i in range(cards_on_board.size()):
            if cards_on_board[i].name == "PlayerBoardLabel":
                continue
            if card.global_position.x < cards_on_board[i].global_position.x:
                new_index = i
                break

        # Put the card back into the board container
        card.reparent(board_container)

        # Move it to the calculated position
        if new_index != -1:
            board_container.move_child(card, new_index)
        else:
            board_container.move_child(card, board_container.get_child_count() - 1)

func _handle_board_to_hand_drop(card):
    """Handle invalid attempt to return a minion from board to hand"""
    print("Cannot return minions from board to hand - this is not allowed")
    _return_card_to_board(card)

func _handle_board_to_shop_drop(card):
    """Handle selling a minion by dragging from board to shop"""
    # Only allow selling during shop phase
    if GameState.current_mode != GameState.GameMode.SHOP:
        print("Cannot sell minions during combat phase")
        _return_card_to_board(card)
        return
    
    # Get card info
    var card_id = card.get_meta("card_id", "")
    if card_id == "":
        print("Error: No card_id metadata on board card")
        _return_card_to_board(card)
        return
    
    if GameModeManager.is_in_multiplayer_session():
        # Get the player's current board state from data
        var player = GameState.get_local_player()
        if not player:
            print("Error: Could not find local player")
            _return_card_to_board(card)
            return
        
        # Find the index of this card in the player's board_minions array
        var board_index = -1
        for i in range(player.board_minions.size()):
            var minion = player.board_minions[i]
            if minion.get("card_id", "") == card_id:
                board_index = i
                break
        
        print("Sell minion - card_id: ", card_id, ", board_index: ", board_index, ", board data: ", player.board_minions)
        
        if board_index >= 0:
            # Request sell action
            NetworkManager.request_game_action.rpc_id(
                GameState.host_player_id,
                "sell_minion",
                {
                    "card_id": card_id,
                    "board_index": board_index
                }
            )
            
            # Return card to board - visual state will update when host responds
            _return_card_to_board(card)
            
            # Show subtle feedback
            ui_manager.show_flash_message("Selling minion...", 0.5)
        else:
            print("Error: Could not find board index for card")
            _return_card_to_board(card)
    else:
        # Practice mode
        var card_name = card.get_node("VBoxContainer/CardName").text
        
        # Execute the sale locally
        GameState.gain_gold(1)
        card.queue_free()
        
        # Update displays
        update_board_count()
        ui_manager.update_gold_display_detailed()
        
        print("Sold ", card_name, " for 1 gold (Current gold: ", GameState.current_gold, ")")

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
    card.reparent(ui_manager.get_shop_container())

func _return_card_to_hand(card):
    """Return a card to the hand area"""
    card.reparent(ui_manager.get_hand_container())

func _return_card_to_board(card):
    """Return a card to the board area"""
    card.reparent(ui_manager.get_board_container())

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
    var board_container = ui_manager.get_board_container()
    var cards_on_board = board_container.get_children()
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
    card.reparent(board_container)
    
    # Position the card appropriately
    if new_index != -1:
        board_container.move_child(card, new_index)
    else:
        # If dropped past the last card, move to end (but before label if it exists)
        board_container.move_child(card, board_container.get_child_count() - 1)
    
    # In practice mode, we need to update the player state first
    # For now, just update visual - counts will update when state changes
    # TODO: Update practice mode to use proper state management

func _calculate_board_drop_position(card: Node, board_container: Container) -> int:
    """Calculate where a card should be inserted on the board based on drop position"""
    var cards_on_board = board_container.get_children()
    var position = 0
    
    # Find insertion position based on X coordinate
    for i in range(cards_on_board.size()):
        if cards_on_board[i].name == "PlayerBoardLabel":
            continue
        if not cards_on_board[i].has_meta("card_id"):
            continue
        if card.global_position.x < cards_on_board[i].global_position.x:
            return position
        position += 1
    
    # If we get here, add to end
    return position

func _unhandled_input(event):
    # Check for right-click to cancel battlecry selection
    if is_selecting_battlecry_target and event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
            # Cancel battlecry selection and return card to hand
            _return_card_to_hand(battlecry_card_being_played)
            _exit_battlecry_target_mode()
            ui_manager.show_flash_message("Battlecry cancelled", 1.0)
            get_viewport().set_input_as_handled()
    
    # Check for click to skip combat animations
    if GameState.current_mode == GameState.GameMode.COMBAT and event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            if combat_manager and combat_manager.has_method("skip_all_combat_animations"):
                combat_manager.skip_all_combat_animations()
                get_viewport().set_input_as_handled()

# Visual feedback functions moved to DragDropManager


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

# Combat functions moved to CombatManager

# Combat helper functions moved to CombatManager

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

# Combat display functions moved to CombatManager

# _display_final_player_board_with_dead moved to CombatManager

# _display_final_enemy_board_with_dead moved to CombatManager

# All combat display functions moved to CombatManager:
# _display_final_player_board, _display_final_enemy_board, _create_dead_minion_card,
# _apply_health_color_to_card, _apply_health_color_to_card_enhanced, _restore_original_player_board,
# display_combat_log

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
        "auto_win":
            return "%s wins automatically (opponent eliminated)" % action.get("winner", "?")
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
    """Handle start combat button press - delegate to CombatManager"""
    if GameModeManager.is_in_multiplayer_session():
        # Multiplayer combat - no enemy selection needed
        combat_manager.start_multiplayer_combat()
    else:
        # Practice mode - use enemy board selector
        if not ui_manager.enemy_board_selector:
            print("Error: Enemy board selector not available")
            return
            
        var selected_index = ui_manager.enemy_board_selector.selected
        var board_names = EnemyBoards.get_enemy_board_names()
        
        if selected_index < 0 or selected_index >= board_names.size():
            print("Error: Invalid enemy board selection")
            return
            
        var selected_board_name = board_names[selected_index]
        combat_manager.start_combat(selected_board_name)

# Combat view toggle function removed - now showing combined result view only

func _on_return_to_shop_button_pressed() -> void:
    """Handle return to shop button press - delegate to CombatManager"""
    combat_manager.return_to_shop()

func _on_refresh_shop_button_pressed() -> void:
    """Handle refresh shop button press"""
    if GameModeManager.is_in_multiplayer_session():
        NetworkManager.request_game_action.rpc_id(
            GameState.host_player_id,
            "refresh_shop",
            {}
        )
        ui_manager.show_flash_message("Refreshing shop...", 0.5)
    else:
        print("Practice mode not implemented in SSOT architecture")

func _on_freeze_button_pressed() -> void:
    """Handle freeze button press"""
    if GameModeManager.is_in_multiplayer_session():
        NetworkManager.request_game_action.rpc_id(
            GameState.host_player_id,
            "toggle_freeze",
            {}
        )
        ui_manager.show_flash_message("Toggling freeze...", 0.3)
    else:
        print("Practice mode not implemented in SSOT architecture")

func _on_upgrade_shop_button_pressed() -> void:
    """Handle upgrade shop button press"""
    if GameModeManager.is_in_multiplayer_session():
        NetworkManager.request_game_action.rpc_id(
            GameState.host_player_id,
            "upgrade_shop",
            {}
        )
        ui_manager.show_flash_message("Upgrading shop...", 0.5)
    else:
        print("Practice mode not implemented in SSOT architecture")

func prepare_shop_for_combat() -> void:
    """Prepare shop state before transitioning to combat"""
    # In SSOT architecture, nothing to do here - state is managed by host
    pass

# Note: End turn button removed - turns now advance automatically after combat
# func _on_end_turn_button_pressed() -> void:
#     """Handle end turn button press"""
#     print("End turn button pressed")
#     GameState.start_new_turn()
#     print("Started turn %d" % GameState.current_turn)

func _on_enemy_board_selected(index: int) -> void:
    """Handle enemy board selection from dropdown - delegate to CombatManager"""
    combat_manager.handle_enemy_board_selection(index)

# Enhanced Combat Algorithm (Phase 2B.3)

# pick_random_from_array moved to CombatManager

# run_combat moved to CombatManager

# execute_attack, simulate_full_combat moved to CombatManager

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

func _sync_board_state_to_network():
    """Sync the current board state to the network"""
    var board_container = ui_manager.get_board_container()
    var board_minions = []
    
    print("_sync_board_state_to_network called - checking board children:")
    # Get all minions on the board in order
    for child in board_container.get_children():
        print("  Child: ", child.name, " has_meta('card_id'): ", child.has_meta("card_id"))
        if child.name != "PlayerBoardLabel" and child.has_meta("card_id"):
            var card_id = child.get_meta("card_id")
            board_minions.append(card_id)
            print("    Added card_id: ", card_id)
    
    print("Board minions to sync: ", board_minions)
    
    # Send board state to host
    if NetworkManager.is_host:
        # Host updates directly
        print("Host updating board state directly")
        NetworkManager.update_board_state(GameState.local_player_id, board_minions)
    else:
        # Client sends to host
        print("Client sending board state to host")
        NetworkManager.update_board_state.rpc_id(GameState.host_player_id, GameState.local_player_id, board_minions)
    
    print("Synced board state: ", board_minions)

# === Test functions removed for GameState migration completion ===
# Will implement proper testing system later

# Combat preparation functions moved to CombatManager
# === BATTLECRY FUNCTIONS ===

func _enter_battlecry_target_mode():
    """Enter battlecry target selection mode"""
    is_selecting_battlecry_target = true
    print("Entering battlecry target selection mode")
    
    # Highlight valid targets
    var board_container = ui_manager.get_board_container()
    var valid_targets = 0
    for child in board_container.get_children():
        if child.has_meta("card_id"):
            # Add glowing outline to valid targets
            _add_battlecry_target_highlight(child)
            valid_targets += 1
    
    print("Found ", valid_targets, " valid battlecry targets")
    
    # Show instruction message
    ui_manager.show_flash_message("Click a minion to buff +1/+1 (Right-click to cancel)", 0)

func _add_battlecry_target_highlight(card: Node):
    """Add visual highlight to a valid battlecry target"""
    # Create a glowing outline effect
    var outline = ReferenceRect.new()
    outline.name = "BattlecryTargetOutline"
    outline.border_color = Color(1.0, 0.843, 0.0, 1.0)  # Gold color
    outline.border_width = 5  # Thicker border for visibility
    outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
    
    # Match the card's size
    outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    
    card.add_child(outline)
    
    # Add pulsing animation
    var tween = create_tween()
    tween.set_loops()
    tween.tween_property(outline, "modulate:a", 0.3, 0.5)
    tween.tween_property(outline, "modulate:a", 1.0, 0.5)
    # Store tween reference on the outline so we can kill it later
    outline.set_meta("tween", tween)
    
    # Also add a slight scale animation to the card
    var card_tween = create_tween()
    card_tween.set_loops()
    card_tween.tween_property(card, "scale", Vector2(1.05, 1.05), 0.5)
    card_tween.tween_property(card, "scale", Vector2(1.0, 1.0), 0.5)
    # Store tween reference on the card so we can kill it later
    card.set_meta("battlecry_scale_tween", card_tween)

func _remove_all_battlecry_highlights():
    """Remove all battlecry target highlights"""
    var board_container = ui_manager.get_board_container()
    for child in board_container.get_children():
        if child.has_meta("card_id"):
            # Kill the scale tween if it exists
            if child.has_meta("battlecry_scale_tween"):
                var scale_tween = child.get_meta("battlecry_scale_tween")
                if scale_tween and is_instance_valid(scale_tween):
                    scale_tween.kill()
                child.remove_meta("battlecry_scale_tween")
            
            # Remove the outline and kill its tween
            var outline = child.get_node_or_null("BattlecryTargetOutline")
            if outline:
                if outline.has_meta("tween"):
                    var outline_tween = outline.get_meta("tween")
                    if outline_tween and is_instance_valid(outline_tween):
                        outline_tween.kill()
                outline.queue_free()
            
            # Reset scale
            child.scale = Vector2(1.0, 1.0)

func _exit_battlecry_target_mode():
    """Exit battlecry target selection mode"""
    is_selecting_battlecry_target = false
    _remove_all_battlecry_highlights()
    
    # Clear stored data
    battlecry_card_being_played = null
    battlecry_card_id = ""
    battlecry_board_position = -1

func _on_battlecry_target_selected(target_index: int):
    """Handle battlecry target selection"""
    if not is_selecting_battlecry_target:
        return
    
    # Complete the play with the selected target
    # Note: battlecry_card_being_played is already in hand, so we pass null to avoid double-handling
    _complete_play_card(null, battlecry_card_id, battlecry_board_position, target_index)
    
    # Exit selection mode
    _exit_battlecry_target_mode()

func _complete_play_card(card: Node, card_id: String, board_position: int, battlecry_target: int):
    """Complete playing a card with optional battlecry target"""
    # Request play card action with battlecry target
    var params = {
        "card_id": card_id,
        "board_position": board_position
    }
    
    if battlecry_target >= 0:
        params["battlecry_target"] = battlecry_target
    
    NetworkManager.request_game_action.rpc_id(
        GameState.host_player_id,
        "play_card",
        params
    )
    
    # For battlecry cards, the card is already in hand, so just remove it
    # For non-battlecry cards, return to hand for non-host players
    if card and is_instance_valid(card):
        if !GameState.is_host():
            _return_card_to_hand(card)
        else:
            # For host, remove the card from hand immediately since state will update
            card.queue_free()
    
    # Show subtle feedback
    ui_manager.show_flash_message("Playing minion...", 0.5)
