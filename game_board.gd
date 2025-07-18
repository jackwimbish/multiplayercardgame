extends Control

const DEFAULT_PORT = 9999
const ShopManagerScript = preload("res://shop_manager.gd")
const CombatManagerScript = preload("res://combat_manager.gd")
# dragged_card removed - now tracked by DragDropManager

# Core game state is now managed by GameState singleton
# Access via GameState.current_turn, GameState.current_gold, etc.

signal game_over(winner: String)

# UI Manager reference
@onready var ui_manager = $MainLayout

# Manager instances
var shop_manager: ShopManagerScript
var combat_manager: CombatManagerScript

# Constants are now in GameState singleton

# Note: Hand/board size tracking and UI constants moved to UIManager

func _ready():
    # Add to game_board group for CardFactory access
    add_to_group("game_board")
    
    # Initialize GameState for the current game mode
    GameState.initialize_game_state()
    
    # Setup game mode specific features
    setup_game_mode()
    
    # Note: UI setup is now handled by UIManager
    # Connect to GameState signals for game logic updates (UI signals handled by UIManager)
    GameState.game_over.connect(_on_game_over)
    
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
    shop_manager.refresh_shop()
    
    # Connect shop manager to player signals for multiplayer updates
    _connect_shop_to_player_signals()

func _connect_shop_to_player_signals():
    """Connect shop manager to player state signals"""
    if GameModeManager.is_in_multiplayer_session():
        var local_player = GameState.get_local_player()
        if local_player:
            local_player.shop_cards_changed.connect(shop_manager._on_player_shop_changed)
            # Create wrapper for gold_changed signal (PlayerState emits 1 param, UI expects 2)
            local_player.gold_changed.connect(func(new_gold): ui_manager._on_gold_changed(new_gold, GameState.GLOBAL_GOLD_MAX))
            print("Connected shop manager to player shop_cards_changed signal")
            print("Connected UI manager to player gold_changed signal")

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

func _on_card_clicked(card_node):
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
    
    # Play the minion to the board
    _play_minion_to_board(card)
    print("Played ", card_name, " to board")
    
    # Sync board state in multiplayer
    if GameModeManager.is_in_multiplayer_session():
        _sync_board_state_to_network()

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

    # Put the card back into the board container
    card.reparent(board_container)

    # Move it to the calculated position
    if new_index != -1:
        board_container.move_child(card, new_index)
    else:
        # If it was dropped past the last card, move it to the end
        board_container.move_child(card, board_container.get_child_count() - 1)
    
    # Sync board state in multiplayer (position changed)
    if GameModeManager.is_in_multiplayer_session():
        _sync_board_state_to_network()

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
    
    # Get card info for feedback
    var card_name = card.get_node("VBoxContainer/CardName").text
    var card_data = _find_card_data_by_name(card_name)
    
    if card_data.is_empty():
        print("Error: Could not find card data for ", card_name)
        _return_card_to_board(card)
        return
    
    # Only minions can be sold (should always be true since it's from board)
    if card_data.get("type", "") != "minion":
        print("Error: Non-minion on board - cannot sell")
        _return_card_to_board(card)
        return
    
    # Execute the sale
    GameState.gain_gold(1)
    card.queue_free()  # Remove the minion card
    
    # Update displays
    update_board_count()
    ui_manager.update_gold_display_detailed()  # Update gold display
    
    print("Sold ", card_name, " for 1 gold (Current gold: ", GameState.current_gold, ")")
    
    # Sync board state in multiplayer (minion sold)
    if GameModeManager.is_in_multiplayer_session():
        _sync_board_state_to_network()

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
    
    # Update counts
    update_hand_count()
    update_board_count()

# _unhandled_input removed - now handled by DragDropManager

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
    shop_manager.handle_refresh_button_pressed()

func _on_freeze_button_pressed() -> void:
    """Handle freeze button press"""
    shop_manager.handle_freeze_button_pressed()

func _on_upgrade_shop_button_pressed() -> void:
    """Handle upgrade shop button press"""
    shop_manager.handle_upgrade_button_pressed()

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
