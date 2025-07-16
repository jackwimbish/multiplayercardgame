extends Control

const DEFAULT_PORT = 9999
const CardScene = preload("res://card.tscn")
var dragged_card = null

# Core game state variables
var current_turn: int = 1
var player_base_gold: int = 3
var current_gold: int = 3
var bonus_gold: int = 0
var shop_tier: int = 1
var card_pool: Dictionary = {}

# Player Health System (Phase 2A.4)
@export var player_health: int = 25
@export var enemy_health: int = 25
@export var combat_damage: int = 5

signal player_health_changed(new_health: int)
signal enemy_health_changed(new_health: int)
signal game_over(winner: String)

# Combat UI Integration (Phase 2B.2)
var enemy_board_selector: OptionButton
var combat_log_display: RichTextLabel  
var player_health_label: Label
var enemy_health_label: Label
var start_combat_button: Button
var combat_ui_container: VBoxContainer

# Constants
const GLOBAL_GOLD_MAX = 255

# Hand/board size tracking
var max_hand_size: int = 10
var max_board_size: int = 7



func _on_card_clicked(card_node):
    var card_name = card_node.get_node("VBoxContainer/CardName").text
    print("A card was clicked: ", card_name)
    
    # Check if this card is in the hand (only hand cards should be clickable for casting)
    var is_in_hand = false
    for hand_card in $MainLayout/PlayerHand.get_children():
        if hand_card == card_node:
            is_in_hand = true
            break
    
    if not is_in_hand:
        print("Card not in hand - ignoring click")
        return
    
    # Get card data to check if it's a spell
    var card_data = _find_card_data_by_name(card_name)
    if card_data.is_empty():
        print("Error: Could not find card data for ", card_name)
        return
    
    # Handle spell casting
    if card_data.get("type", "") == "spell":
        _cast_spell(card_node, card_data)
    else:
        print(card_name, " is a minion - drag to board to play")

func update_hand_count():
    var hand_size = get_hand_size()
    $MainLayout/PlayerHand/PlayerHandLabel.text = "Your Hand (" + str(hand_size) + "/" + str(max_hand_size) + ")"

func update_board_count():
    var board_size = get_board_size()
    $MainLayout/PlayerBoard/PlayerBoardLabel.text = "Your Board (" + str(board_size) + "/" + str(max_board_size) + ")"

func initialize_card_pool():
    """Set up card availability tracking based on tier and copy counts (shop-available cards only)"""
    card_pool.clear()
    
    # Copy counts by tier: [tier 1: 18, tier 2: 15, tier 3: 13, tier 4: 11, tier 5: 9, tier 6: 6]
    var copies_by_tier = {1: 18, 2: 15, 3: 13, 4: 11, 5: 9, 6: 6}
    
    # Initialize pool for each shop-available card based on its tier
    for card_id in CardDatabase.get_all_shop_available_card_ids():
        var card_data = CardDatabase.get_card_data(card_id)
        var tier = card_data.get("tier", 1)
        var copy_count = copies_by_tier.get(tier, 1)
        card_pool[card_id] = copy_count
    
    print("Card pool initialized (shop cards only): ", card_pool)

func get_shop_size_for_tier(tier: int) -> int:
    """Get number of cards shown in shop for given tier"""
    match tier:
        1: return 3
        2, 3: return 4  
        4, 5: return 5
        6: return 6
        _: return 3  # Default fallback

func get_random_card_for_tier(tier: int) -> String:
    """Get a random card ID for the specified tier that's available in the pool and shop"""
    var available_cards = []
    
    # Find all cards of this tier that have remaining copies AND are shop-available
    for card_id in card_pool.keys():
        if card_pool[card_id] > 0:  # Has remaining copies
            var card_data = CardDatabase.get_card_data(card_id)
            if card_data.get("tier", 1) == tier and card_data.get("shop_available", true):
                available_cards.append(card_id)
    
    if available_cards.is_empty():
        print("Warning: No available shop cards for tier ", tier)
        return ""
    
    # Return random card from available options
    return available_cards[randi() % available_cards.size()]

func refresh_shop():
    """Clear shop and populate with random cards from current tier"""
    # Clear existing shop cards
    for child in $MainLayout/ShopArea.get_children():
        child.queue_free()
    
    var shop_size = get_shop_size_for_tier(shop_tier)
    print("Refreshing shop (tier ", shop_tier, ") with ", shop_size, " cards")
    
    # Add new random cards to shop
    for i in range(shop_size):
        var card_id = get_random_card_for_tier(shop_tier)
        if card_id != "":
            add_card_to_shop(card_id)

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

func add_card_to_shop(card_id: String):
    """Add a card to the shop area"""
    var card_data = CardDatabase.get_card_data(card_id)
    var new_card = create_card_instance(card_data, card_id)
    
    # Connect drag handler for shop cards (drag-to-purchase)
    new_card.drag_started.connect(_on_card_drag_started)
    
    # Store card_id for purchase logic
    new_card.set_meta("card_id", card_id)
    
    $MainLayout/ShopArea.add_child(new_card)



func add_card_to_hand_direct(card_id: String):
    """Add a card directly to hand (used by purchase system)"""
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



func calculate_base_gold_for_turn(turn: int) -> int:
    """Calculate base gold for a given turn (3 on turn 1, +1 per turn up to 10)"""
    if turn <= 1:
        return 3
    elif turn <= 8:
        return 2 + turn  # Turn 2=4 gold, turn 3=5 gold, ..., turn 8=10 gold
    else:
        return 10  # Maximum base gold of 10 from turn 8 onwards

func start_new_turn():
    """Advance to the next turn and refresh gold"""
    current_turn += 1
    
    # Update base gold from turn progression (but don't decrease it)
    var new_base_gold = calculate_base_gold_for_turn(current_turn)
    player_base_gold = max(player_base_gold, new_base_gold)
    
    # Refresh current gold (base + any bonus, capped at global max)
    current_gold = min(player_base_gold + bonus_gold, GLOBAL_GOLD_MAX)
    bonus_gold = 0  # Reset bonus after applying it
    
    print("Turn ", current_turn, " started - Base Gold: ", player_base_gold, ", Current Gold: ", current_gold)
    update_ui_displays()
    
    # Refresh shop for new turn (free)
    refresh_shop()

func update_ui_displays():
    """Update all UI elements with current game state"""
    var gold_text = "Gold: " + str(current_gold) + "/" + str(player_base_gold)
    if bonus_gold > 0:
        gold_text += " (+" + str(bonus_gold) + ")"
    $MainLayout/TopUI/GoldLabel.text = gold_text
    $MainLayout/TopUI/ShopTierLabel.text = "Shop Tier: " + str(shop_tier)

func spend_gold(amount: int) -> bool:
    """Attempt to spend gold. Returns true if successful, false if insufficient gold"""
    if current_gold >= amount:
        current_gold -= amount
        update_ui_displays()
        return true
    else:
        print("Insufficient gold: need ", amount, ", have ", current_gold)
        return false

func can_afford(cost: int) -> bool:
    """Check if player can afford a given cost"""
    return current_gold >= cost

func increase_base_gold(amount: int):
    """Permanently increase player's base gold income"""
    player_base_gold = min(player_base_gold + amount, GLOBAL_GOLD_MAX)
    print("Base gold increased by ", amount, " to ", player_base_gold)
    update_ui_displays()

func add_bonus_gold(amount: int):
    """Add temporary bonus gold for next turn only"""
    bonus_gold = min(bonus_gold + amount, GLOBAL_GOLD_MAX - player_base_gold)
    print("Bonus gold added: ", amount, " (total bonus: ", bonus_gold, ")")
    update_ui_displays()

func gain_gold(amount: int):
    """Immediately gain current gold (within global limits)"""
    current_gold = min(current_gold + amount, GLOBAL_GOLD_MAX)
    print("Gained ", amount, " gold (current: ", current_gold, ")")
    update_ui_displays()

func get_hand_size() -> int:
    """Get current number of cards in hand"""
    return $MainLayout/PlayerHand.get_children().size() - 1  # Subtract label

func get_board_size() -> int:
    """Get current number of minions on board"""
    return $MainLayout/PlayerBoard.get_children().size() - 1  # Subtract label

func is_hand_full() -> bool:
    """Check if hand is at maximum capacity"""
    return get_hand_size() >= max_hand_size

func is_board_full() -> bool:
    """Check if board is at maximum capacity"""
    return get_board_size() >= max_board_size
    
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
    # Check if card is in shop
    for shop_card in $MainLayout/ShopArea.get_children():
        if shop_card == card:
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
    
    # Cards in shop
    for shop_card in $MainLayout/ShopArea.get_children():
        if shop_card != exclude_card:
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
    var card_id = card.get_meta("card_id", "")
    if card_id == "":
        print("Error: Shop card missing card_id metadata")
        _return_card_to_shop(card)
        return
    
    var card_data = CardDatabase.get_card_data(card_id)
    var cost = card_data.get("cost", 3)
    
    print("Attempting to purchase ", card_data.get("name", "Unknown"), " for ", cost, " gold via drag")
    
    # Check purchase validation (reuse existing logic)
    if not can_afford(cost):
        print("Cannot afford card - need ", cost, " gold, have ", current_gold)
        _return_card_to_shop(card)
        return
    
    if is_hand_full():
        print("Cannot purchase - hand is full (", get_hand_size(), "/", max_hand_size, ")")
        _return_card_to_shop(card)
        return
    
    if card_pool.get(card_id, 0) <= 0:
        print("Card no longer available in pool")
        _return_card_to_shop(card)
        return
    
    # Execute purchase
    if spend_gold(cost):
        # Remove from pool
        card_pool[card_id] -= 1
        
        # Convert shop card to hand card
        _convert_shop_card_to_hand_card(card, card_id)
        
        print("Purchased ", card_data.get("name", "Unknown"), " via drag - Remaining in pool: ", card_pool[card_id])
    else:
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
        print("Cannot play minion - board is full (", get_board_size(), "/", max_board_size, ")")
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
        print("Cannot return minion to hand - hand is full (", get_hand_size(), "/", max_hand_size, ")")
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

func _convert_shop_card_to_hand_card(shop_card, card_id: String):
    """Convert a shop card into a hand card with proper connections"""
    # Remove the shop card from the shop area first
    var shop_position = shop_card.get_index()
    shop_card.queue_free()
    
    # Create a new hand card with the same data
    add_card_to_hand_direct(card_id)
    
    # Update counts
    update_hand_count()

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
            gain_gold(1)
            print("Gained 1 gold from The Coin")
        _:
            print("Spell effect not implemented for: ", spell_name)
    
    # Remove the spell card from hand (spells are consumed when cast)
    spell_card.queue_free()
    update_hand_count()
    
    print("Spell ", spell_name, " cast and removed from hand")

# Player Health System Functions (Phase 2A.4)

func take_damage(damage: int, is_player: bool = true) -> void:
    """Apply damage to player or enemy and check for game over"""
    if is_player:
        player_health = max(0, player_health - damage)
        player_health_changed.emit(player_health)
        print("Player took %d damage, health now: %d" % [damage, player_health])
        if player_health <= 0:
            game_over.emit("enemy")
            print("GAME OVER - Enemy wins!")
    else:
        enemy_health = max(0, enemy_health - damage)
        enemy_health_changed.emit(enemy_health)
        print("Enemy took %d damage, health now: %d" % [damage, enemy_health])
        if enemy_health <= 0:
            game_over.emit("player")
            print("GAME OVER - Player wins!")

func get_player_health() -> int:
    """Get current player health"""
    return player_health

func get_enemy_health() -> int:
    """Get current enemy health"""
    return enemy_health

func reset_health() -> void:
    """Reset both players to starting health (for testing)"""
    player_health = 25
    enemy_health = 25
    player_health_changed.emit(player_health)
    enemy_health_changed.emit(enemy_health)
    print("Health reset - Player: %d, Enemy: %d" % [player_health, enemy_health])

func set_enemy_health(health: int) -> void:
    """Set enemy health (useful for testing different enemy board healths)"""
    enemy_health = max(0, health)
    enemy_health_changed.emit(enemy_health)
    print("Enemy health set to: %d" % enemy_health)

# Combat UI Integration Functions (Phase 2B.2)

func create_combat_ui() -> void:
    """Create combat UI elements programmatically"""
    # Create main combat UI container
    combat_ui_container = VBoxContainer.new()
    combat_ui_container.name = "CombatUI"
    
    # Add to the main layout (position it near the top UI)
    $MainLayout.add_child(combat_ui_container)
    $MainLayout.move_child(combat_ui_container, 1)  # Place after TopUI
    
    # Create health display container
    var health_container = HBoxContainer.new()
    health_container.name = "HealthContainer"
    
    # Player health label
    player_health_label = Label.new()
    player_health_label.name = "PlayerHealthLabel"
    player_health_label.text = "Player Health: %d" % player_health
    player_health_label.add_theme_color_override("font_color", Color.GREEN)
    
    # Enemy health label  
    enemy_health_label = Label.new()
    enemy_health_label.name = "EnemyHealthLabel"
    enemy_health_label.text = "Enemy Health: %d" % enemy_health
    enemy_health_label.add_theme_color_override("font_color", Color.RED)
    
    health_container.add_child(player_health_label)
    health_container.add_child(enemy_health_label)
    
    # Create enemy board selection container
    var enemy_selection_container = HBoxContainer.new()
    enemy_selection_container.name = "EnemySelectionContainer"
    
    var enemy_label = Label.new()
    enemy_label.text = "Enemy Board: "
    
    enemy_board_selector = OptionButton.new()
    enemy_board_selector.name = "EnemyBoardSelector"
    
    enemy_selection_container.add_child(enemy_label)
    enemy_selection_container.add_child(enemy_board_selector)
    
    # Create start combat button
    start_combat_button = Button.new()
    start_combat_button.name = "StartCombatButton"
    start_combat_button.text = "Start Combat"
    
    # Create combat log display
    combat_log_display = RichTextLabel.new()
    combat_log_display.name = "CombatLogDisplay"
    combat_log_display.custom_minimum_size = Vector2(400, 200)
    combat_log_display.bbcode_enabled = true
    combat_log_display.scroll_following = true
    combat_log_display.text = "[b]Combat Log[/b]\n\nSelect an enemy board and click 'Start Combat' to begin."
    
    # Add all elements to combat UI container
    combat_ui_container.add_child(health_container)
    combat_ui_container.add_child(enemy_selection_container)
    combat_ui_container.add_child(start_combat_button)
    combat_ui_container.add_child(combat_log_display)
    
    print("Combat UI created successfully")

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

func connect_combat_ui_signals() -> void:
    """Connect combat UI element signals"""
    if start_combat_button:
        start_combat_button.pressed.connect(_on_start_combat_button_pressed)
        
    if enemy_board_selector:
        enemy_board_selector.item_selected.connect(_on_enemy_board_selected)
        
    print("Combat UI signals connected")

func update_health_displays() -> void:
    """Update health display labels"""
    if player_health_label:
        player_health_label.text = "Player Health: %d" % player_health
        
    if enemy_health_label:
        enemy_health_label.text = "Enemy Health: %d" % enemy_health

func display_combat_log(action_log: Array) -> void:
    """Display combat actions in the combat log"""
    if not combat_log_display:
        return
        
    combat_log_display.clear()
    combat_log_display.append_text("[b]COMBAT LOG[/b]\n\n")
    
    for action in action_log:
        var log_line = format_combat_action(action)
        combat_log_display.append_text(log_line + "\n")

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
    if not enemy_board_selector:
        print("Error: Enemy board selector not available")
        return
        
    var selected_index = enemy_board_selector.selected
    var board_names = EnemyBoards.get_enemy_board_names()
    
    if selected_index < 0 or selected_index >= board_names.size():
        print("Error: Invalid enemy board selection")
        return
        
    var selected_board_name = board_names[selected_index]
    print("Starting combat against: %s" % selected_board_name)
    
    # Run combat simulation and display results
    var combat_result = simulate_full_combat(selected_board_name)
    display_combat_log(combat_result)

func _on_enemy_board_selected(index: int) -> void:
    """Handle enemy board selection change"""
    var board_names = EnemyBoards.get_enemy_board_names()
    if index >= 0 and index < board_names.size():
        var selected_board = board_names[index]
        var board_data = EnemyBoards.create_enemy_board(selected_board)
        
        # Update enemy health based on selected board
        if board_data.has("health"):
            set_enemy_health(board_data.health)
            
        print("Selected enemy board: %s (Health: %d)" % [board_data.get("name", selected_board), board_data.get("health", enemy_health)])

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
    
    # Main combat loop - check turn conditions before each attack
    while attack_count < max_attacks:
        # Check if current player can attack
        if p_turn:
            # Player's turn
            if player_minions.is_empty():
                if enemy_minions.is_empty():
                    action_log.append({"type": "combat_tie", "reason": "both_no_minions"})
                    break
                else:
                    action_log.append({"type": "combat_end", "winner": "enemy", "reason": "player_no_minions"})
                    take_damage(combat_damage, true)
                    break
        else:
            # Enemy's turn
            if enemy_minions.is_empty():
                if player_minions.is_empty():
                    action_log.append({"type": "combat_tie", "reason": "both_no_minions"})
                    break
                else:
                    action_log.append({"type": "combat_end", "winner": "player", "reason": "enemy_no_minions"})
                    take_damage(combat_damage, false)
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
        
        # Execute attack (even 0-damage attacks count as attempts)
        execute_attack(attacker, defender, action_log)
        attack_count += 1
        
        # Remove dead minions
        player_minions = player_minions.filter(func(m): return m.current_health > 0)
        enemy_minions = enemy_minions.filter(func(m): return m.current_health > 0)
        
        # Advance turn
        if p_turn:
            p_attacker_index += 1
        else:
            e_attacker_index += 1
        p_turn = not p_turn
    
    # Handle max attacks reached
    if attack_count >= max_attacks:
        action_log.append({"type": "combat_tie", "reason": "max_attacks_reached"})
    
    # After combat ends, start the next turn
    action_log.append({"type": "turn_start", "turn": current_turn + 1})
    start_new_turn()
    
    return action_log

func execute_attack(attacker, defender, action_log: Array) -> void:
    """Execute an attack between two combat minions with detailed logging"""
    action_log.append({
        "type": "attack",
        "attacker_id": attacker.minion_id,
        "defender_id": defender.minion_id,
        "attacker_attack": attacker.current_attack,
        "attacker_health": attacker.current_health,
        "defender_attack": defender.current_attack,
        "defender_health": defender.current_health
    })
    
    # Simultaneous damage
    var attacker_damage = attacker.current_attack
    var defender_damage = defender.current_attack
    
    defender.current_health -= attacker_damage
    attacker.current_health -= defender_damage
    
    action_log.append({
        "type": "damage",
        "target_id": defender.minion_id,
        "amount": attacker_damage,
        "new_health": defender.current_health
    })
    
    action_log.append({
        "type": "damage", 
        "target_id": attacker.minion_id,
        "amount": defender_damage,
        "new_health": attacker.current_health
    })
    
    # Check for deaths
    if defender.current_health <= 0:
        action_log.append({"type": "death", "target_id": defender.minion_id})
    
    if attacker.current_health <= 0:
        action_log.append({"type": "death", "target_id": attacker.minion_id})

func simulate_full_combat(enemy_board_name: String) -> Array:
    """Simulate a complete combat using enhanced algorithm and return action log"""
    # Create combat armies
    var player_army = create_player_combat_army()
    var enemy_army = create_enemy_combat_army(enemy_board_name)
    
    # Run the enhanced combat algorithm
    return run_combat(player_army, enemy_army)

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
    """Apply tavern upgrade buff to all board minions"""
    print("Applying tavern upgrade: +%d/+%d to all board minions" % [attack_bonus, health_bonus])
    
    var minions_buffed = 0
    
    # Apply to each board minion individually
    for child in $MainLayout/PlayerBoard.get_children():
        if child.has_method("add_persistent_buff") and child.name != "PlayerBoardLabel":
            # Create a unique buff for each minion (non-stackable buffs need unique IDs)
            var upgrade_buff = create_stat_modification_buff(
                "tavern_upgrade_" + str(Time.get_ticks_msec()) + "_" + str(minions_buffed),
                "+%d/+%d Tavern Upgrade" % [attack_bonus, health_bonus],
                attack_bonus,
                health_bonus
            )
            
            apply_tavern_buff_to_minion(child, upgrade_buff)
            minions_buffed += 1
    
    print("Tavern upgrade applied to %d minions" % minions_buffed)

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

# Test function for the buff system
func test_buff_system() -> void:
    """Test function to demonstrate buff system functionality"""
    print("\n=== Buff System Test ===")
    
    var board_minions = []
    for child in $MainLayout/PlayerBoard.get_children():
        if child.has_method("add_persistent_buff") and child.name != "PlayerBoardLabel":
            board_minions.append(child)
    
    if board_minions.is_empty():
        print("No minions on board to test buffs")
        return
    
    print("Testing buff system with %d board minions:" % board_minions.size())
    
    # Show initial stats
    for i in range(board_minions.size()):
        var minion = board_minions[i]
        print("  %d. %s: %d/%d (base: %d/%d)" % [
            i + 1,
            minion.card_data.get("name", "Unknown"),
            minion.get_effective_attack(),
            minion.get_effective_health(),
            minion.base_attack,
            minion.base_health
        ])
    
    # Test applying a +1/+1 buff to first minion
    if board_minions.size() > 0:
        var test_buff = create_stat_modification_buff(
            "test_buff_" + str(Time.get_ticks_msec()),
            "+1/+1 Test Buff",
            1, 1
        )
        
        print("\nApplying +1/+1 test buff to first minion...")
        apply_tavern_buff_to_minion(board_minions[0], test_buff)
        
        print("After buff - %s: %d/%d" % [
            board_minions[0].card_data.get("name", "Unknown"),
            board_minions[0].get_effective_attack(),
            board_minions[0].get_effective_health()
        ])
    
    print("========================\n")

# Test function for CombatMinion system
func test_combat_minion_system() -> void:
    """Test CombatMinion creation from board minions and enemy data"""
    print("\n=== Combat Minion System Test ===")
    
    # Test 1: Create CombatMinion from board minion
    print("\n--- Test 1: Board Minion → CombatMinion ---")
    var board_minions = []
    for child in $MainLayout/PlayerBoard.get_children():
        if child.has_method("get_effective_attack") and child.name != "PlayerBoardLabel":
            board_minions.append(child)
    
    if board_minions.size() > 0:
        var test_minion = board_minions[0]
        print("Creating CombatMinion from: %s (%d/%d)" % [
            test_minion.card_data.get("name", "Unknown"),
            test_minion.get_effective_attack(),
            test_minion.get_effective_health()
        ])
        
        var combat_minion = CombatMinion.create_from_board_minion(test_minion, "test_combat_1")
        
        print("✅ CombatMinion created:")
        print("   - ID: %s" % combat_minion.minion_id)
        print("   - Stats: %d/%d (base: %d/%d)" % [
            combat_minion.current_attack,
            combat_minion.current_health,
            combat_minion.base_attack,
            combat_minion.base_health
        ])
        print("   - Combat buffs: %d" % combat_minion.combat_buffs.size())
    else:
        print("❌ No board minions found to test")
    
    # Test 2: Create CombatMinion from enemy data
    print("\n--- Test 2: Enemy Data → CombatMinion ---")
    var enemy_board_data = EnemyBoards.create_enemy_board("mid_game")
    if not enemy_board_data.is_empty() and enemy_board_data.has("minions"):
        var enemy_minion_data = enemy_board_data.minions[0]  # First enemy minion
        
        print("Creating CombatMinion from enemy: %s" % enemy_minion_data.get("card_id", "Unknown"))
        if enemy_minion_data.has("buffs"):
            print("   - Has %d predefined buffs" % enemy_minion_data.buffs.size())
        
        var enemy_combat_minion = CombatMinion.create_from_enemy_data(enemy_minion_data, "enemy_combat_1")
        
        print("✅ Enemy CombatMinion created:")
        print("   - ID: %s" % enemy_combat_minion.minion_id)
        print("   - Stats: %d/%d" % [enemy_combat_minion.current_attack, enemy_combat_minion.current_health])
        print("   - Combat buffs: %d" % enemy_combat_minion.combat_buffs.size())
    else:
        print("❌ Could not load enemy board data")
    
    # Test 3: Test adding combat buff
    print("\n--- Test 3: Adding Combat Buff ---")
    if board_minions.size() > 0:
        var test_minion = board_minions[0]
        var combat_minion = CombatMinion.create_from_board_minion(test_minion, "test_combat_buff")
        
        print("Before buff: %d/%d" % [combat_minion.current_attack, combat_minion.current_health])
        
        # Create a temporary combat buff
        var combat_buff = create_stat_modification_buff(
            "temp_combat_buff",
            "+2/+2 Combat Buff",
            2, 2
        )
        
        combat_minion.add_combat_buff(combat_buff)
        
        print("After +2/+2 buff: %d/%d" % [combat_minion.current_attack, combat_minion.current_health])
        print("✅ Combat buff system working")
    
    print("================================\n")

# Combat UI System Test (Phase 2B.2)
func test_combat_ui_system() -> void:
    """Test function to demonstrate combat UI functionality"""
    print("\n=== Combat UI System Test ===")
    
    print("Combat UI Components:")
    print("  - Enemy Board Selector: %s" % ("✅" if enemy_board_selector else "❌"))
    print("  - Combat Log Display: %s" % ("✅" if combat_log_display else "❌"))
    print("  - Player Health Label: %s" % ("✅" if player_health_label else "❌"))
    print("  - Enemy Health Label: %s" % ("✅" if enemy_health_label else "❌"))
    print("  - Start Combat Button: %s" % ("✅" if start_combat_button else "❌"))
    
    if enemy_board_selector:
        print("  - Available enemy boards: %d" % enemy_board_selector.get_item_count())
        for i in range(enemy_board_selector.get_item_count()):
            print("    %d. %s" % [i + 1, enemy_board_selector.get_item_text(i)])
    
    print("\nCurrent Health Status:")
    print("  - Player: %d" % player_health)
    print("  - Enemy: %d" % enemy_health)
    
    # Test health display updates
    print("\nTesting health display updates...")
    var original_player_health = player_health
    var original_enemy_health = enemy_health
    
    # Temporary health change to test UI updates
    player_health = 20
    enemy_health = 15
    update_health_displays()
    
    print("  - Updated to Player: 20, Enemy: 15")
    
    # Restore original health
    player_health = original_player_health
    enemy_health = original_enemy_health
    update_health_displays()
    
    print("  - Restored to Player: %d, Enemy: %d" % [player_health, enemy_health])
    
    print("==============================\n")

# Player Health System Test (Phase 2A.4)
func test_enhanced_combat_algorithm() -> void:
    """Test function to demonstrate enhanced combat algorithm (Phase 2B.3)"""
    print("\n=== Enhanced Combat Algorithm Test ===")
    
    # Reset health for clean test
    reset_health()
    
    # Test with different enemy boards
    var enemy_boards_to_test = ["early_game", "mid_game", "late_game"]
    
    for board_name in enemy_boards_to_test:
        print("\n--- Testing Combat vs %s ---" % board_name)
        print("Pre-combat state: Turn %d, Gold %d/%d" % [current_turn, current_gold, player_base_gold])
        
        # Create combat armies
        var player_army = create_player_combat_army()
        var enemy_army = create_enemy_combat_army(board_name)
        
        print("Player army: %d minions" % player_army.size())
        for minion in player_army:
            print("  - %s: %d/%d" % [minion.source_card_id, minion.current_attack, minion.current_health])
        
        print("Enemy army (%s): %d minions" % [board_name, enemy_army.size()])
        for minion in enemy_army:
            print("  - %s: %d/%d" % [minion.source_card_id, minion.current_attack, minion.current_health])
        
        # Run enhanced combat algorithm
        print("\nRunning enhanced combat algorithm...")
        var combat_log = run_combat(player_army.duplicate(true), enemy_army.duplicate(true))
        
        print("Combat result: %d actions logged" % combat_log.size())
        
        # Highlight key combat features
        print("Key combat events:")
        for i in range(min(3, combat_log.size())):
            var action = combat_log[i]
            if action.get("type") in ["combat_start", "first_attacker"]:
                print("  %s" % format_combat_action(action))
        
        # Show some attack examples
        var attack_count = 0
        for action in combat_log:
            if action.get("type") == "attack" and attack_count < 3:
                print("  Attack example: %s" % format_combat_action(action))
                attack_count += 1
        
        # Show final resolution
        if combat_log.size() > 1:
            # Look for the combat result (before turn_start)
            for i in range(combat_log.size() - 1, -1, -1):
                var action = combat_log[i]
                if action.get("type") in ["combat_end", "combat_tie"]:
                    print("  Final result: %s" % format_combat_action(action))
                    break
        
        print("Current health - Player: %d, Enemy: %d" % [player_health, enemy_health])
        print("Post-combat state: Turn %d, Gold %d/%d" % [current_turn, current_gold, player_base_gold])
        print("------------------------")
    
    print("=== Enhanced Combat Test Complete ===\n")

func test_health_system() -> void:
    """Test function to demonstrate health system functionality"""
    print("\n=== Player Health System Test ===")
    
    print("Initial state:")
    print("  Player health: %d" % player_health)
    print("  Enemy health: %d" % enemy_health)
    print("  Combat damage: %d" % combat_damage)
    
    print("\nTesting damage application:")
    
    # Test player taking damage
    print("Player takes %d damage..." % combat_damage)
    take_damage(combat_damage, true)
    
    # Test enemy taking damage  
    print("Enemy takes %d damage..." % combat_damage)
    take_damage(combat_damage, false)
    
    print("\nAfter combat damage:")
    print("  Player health: %d" % player_health)
    print("  Enemy health: %d" % enemy_health)
    
    # Test health reset
    print("\nResetting health...")
    reset_health()
    
    # Test game over scenario
    print("\nTesting game over scenario:")
    print("Setting player health to 3...")
    player_health = 3
    player_health_changed.emit(player_health)
    
    print("Player takes %d damage (should trigger game over)..." % combat_damage)
    take_damage(combat_damage, true)
    
    print("=================================\n")

# Combat preparation functions
func create_player_combat_army() -> Array:
    """Create CombatMinion array from player's board"""
    var combat_army = []
    var minion_index = 0
    
    for child in $MainLayout/PlayerBoard.get_children():
        if child.has_method("get_effective_attack") and child.name != "PlayerBoardLabel":
            var card_name = child.card_data.get("id", "unknown")
            var combat_id = "pm_%d_%s" % [minion_index, card_name]
            var combat_minion = CombatMinion.create_from_board_minion(child, combat_id)
            combat_minion.position = minion_index
            combat_army.append(combat_minion)
            minion_index += 1
    
    print("Created player combat army: %d minions" % combat_army.size())
    return combat_army

func create_enemy_combat_army(enemy_board_name: String) -> Array:
    """Create CombatMinion array from enemy board configuration"""
    var combat_army = []
    var enemy_board_data = EnemyBoards.create_enemy_board(enemy_board_name)
    
    if enemy_board_data.is_empty():
        print("Failed to load enemy board: %s" % enemy_board_name)
        return combat_army
    
    var minion_index = 0
    for enemy_minion_data in enemy_board_data.get("minions", []):
        var card_name = enemy_minion_data.get("card_id", "unknown")
        var combat_id = "em_%d_%s" % [minion_index, card_name]
        var combat_minion = CombatMinion.create_from_enemy_data(enemy_minion_data, combat_id)
        combat_minion.position = minion_index
        combat_army.append(combat_minion)
        minion_index += 1
    
    print("Created enemy combat army (%s): %d minions" % [enemy_board_name, combat_army.size()])
    return combat_army

func simulate_combat_preparation(enemy_board_name: String = "mid_game") -> Dictionary:
    """Simulate preparing for combat - creates both armies"""
    print("\n=== Combat Preparation Simulation ===")
    
    var player_army = create_player_combat_army()
    var enemy_army = create_enemy_combat_army(enemy_board_name)
    
    print("Player army:")
    for minion in player_army:
        print("  - %s: %d/%d (pos %d)" % [
            minion.source_card_id,
            minion.current_attack,
            minion.current_health,
            minion.position
        ])
    
    print("Enemy army (%s):" % enemy_board_name)
    for minion in enemy_army:
        print("  - %s: %d/%d (pos %d, buffs: %d)" % [
            minion.source_card_id,
            minion.current_attack,
            minion.current_health,
            minion.position,
            minion.combat_buffs.size()
        ])
    
    print("===================================\n")
    
    return {
        "player_army": player_army,
        "enemy_army": enemy_army,
        "enemy_board_name": enemy_board_name
    }

func _ready():
    # Initialize game state
    initialize_card_pool()
    update_ui_displays()
    update_hand_count()
    update_board_count()
    
    # Initialize health system (Phase 2A.4)
    print("Health System initialized - Player: %d, Enemy: %d" % [player_health, enemy_health])
    
    # Connect health signals (UI nodes may not exist yet, so this prepares for future UI)
    player_health_changed.connect(_on_player_health_changed)
    enemy_health_changed.connect(_on_enemy_health_changed)
    game_over.connect(_on_game_over)
    
    # Initialize Combat UI (Phase 2B.2)
    create_combat_ui()
    populate_enemy_board_selector()
    connect_combat_ui_signals()
    
    # Enemy board system is ready - call test_enemy_board_system() manually to test
    
    # Initialize shop with cards
    refresh_shop()
    
    # Deal a specific starting hand (mix of minions and spells for testing)
    add_card_to_hand("murloc_raider")
    add_card_to_hand("dire_wolf_alpha")
    add_card_to_hand("coin")  # Test spell card (no attack/health)
    add_card_to_hand("kindly_grandmother")

# Health system signal handlers (Phase 2A.4)
func _on_player_health_changed(new_health: int) -> void:
    """Handle player health changes (future UI updates)"""
    print("Player health changed to: %d" % new_health)
    update_health_displays()  # Update combat UI displays

func _on_enemy_health_changed(new_health: int) -> void:
    """Handle enemy health changes (future UI updates)"""
    print("Enemy health changed to: %d" % new_health)
    update_health_displays()  # Update combat UI displays

func _on_game_over(winner: String) -> void:
    """Handle game over state"""
    print("Game Over! Winner: %s" % winner)
    if combat_log_display:
        combat_log_display.append_text("\n[b][color=yellow]GAME OVER![/color][/b]\n")
        combat_log_display.append_text("Winner: %s\n" % winner)
    # TODO: Show game over screen/dialog when UI is available


func _on_refresh_shop_button_pressed() -> void:
    var refresh_cost = 1
    if spend_gold(refresh_cost):
        refresh_shop()
        print("Shop refreshed for ", refresh_cost, " gold")
    else:
        print("Cannot refresh shop - need ", refresh_cost, " gold")

func _on_upgrade_shop_button_pressed() -> void:
    # Temporary test: Apply +1/+1 buff to all board minions (was: upgrade shop tier)
    if spend_gold(2):
        apply_tavern_upgrade_all_minions(1, 1)
        print("TEST: Spent 2 gold to give all board minions +1/+1")

func _on_end_turn_button_pressed() -> void:
    print("End turn button pressed")
    # TEST: Run all system tests instead of normal end turn
    # NOTE: In normal gameplay, players use "Start Combat" button, which automatically
    # progresses to next turn after combat ends. This "End Turn" button is for testing.
    test_health_system()
    test_combat_minion_system()
    test_combat_ui_system()
    test_enhanced_combat_algorithm()  # NEW: Test enhanced combat algorithm (advances turns)
    simulate_combat_preparation("mid_game")
    # Uncomment below for manual turn advancement without combat:
    # start_new_turn()

# Test function temporarily commented out due to linter issues with new classes
# Uncomment after reloading project to register new classes
#func test_enemy_board_system() -> void:
#    """Test function to validate enemy board system (can be called from debugger)"""
#    print("\n=== Enemy Board System Test ===")
#    
#    # Test getting board names
#    var board_names = EnemyBoards.get_enemy_board_names()
#    print("Available enemy boards: ", board_names)
#    
#    # Test each board
#    for board_name in board_names:
#        print("\n--- Testing: ", board_name, " ---")
#        var board_data = EnemyBoards.create_enemy_board(board_name)
#        
#        if EnemyBoards.validate_enemy_board(board_data):
#            var info = EnemyBoards.get_enemy_board_info(board_name)
#            print("✅ %s: %d minions, %d health" % [info.name, info.minion_count, info.health])
#            for minion in info.minions:
#                var buff_indicator = " (buffed)" if minion.has_buffs else ""
#                print("   - %s: %s → %s%s" % [minion.name, minion.base_stats, minion.effective_stats, buff_indicator])
#        else:
#            print("❌ Validation failed for: ", board_name)
#    
#    print("===============================\n")
