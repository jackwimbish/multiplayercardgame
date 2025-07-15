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

# Constants
const GLOBAL_GOLD_MAX = 255

# Hand/board size tracking
var max_hand_size: int = 10
var max_board_size: int = 7



func _on_card_clicked(card_node):
    print("A card was selected: ", card_node.get_node("VBoxContainer/CardName").text)

func update_hand_count():
    var hand_size = get_hand_size()
    $MainLayout/PlayerHand/PlayerHandLabel.text = "Your Hand (" + str(hand_size) + "/" + str(max_hand_size) + ")"

func update_board_count():
    var board_size = get_board_size()
    $MainLayout/PlayerBoard/PlayerBoardLabel.text = "Your Board (" + str(board_size) + "/" + str(max_board_size) + ")"

func initialize_card_pool():
    """Set up card availability tracking based on tier and copy counts"""
    card_pool.clear()
    
    # Copy counts by tier: [tier 1: 18, tier 2: 15, tier 3: 13, tier 4: 11, tier 5: 9, tier 6: 6]
    var copies_by_tier = {1: 18, 2: 15, 3: 13, 4: 11, 5: 9, 6: 6}
    
    # Initialize pool for each card based on its tier
    for card_id in CardDatabase.get_all_card_ids():
        var card_data = CardDatabase.get_card_data(card_id)
        var tier = card_data.get("tier", 1)
        var copy_count = copies_by_tier.get(tier, 1)
        card_pool[card_id] = copy_count
    
    print("Card pool initialized: ", card_pool)

func get_shop_size_for_tier(tier: int) -> int:
    """Get number of cards shown in shop for given tier"""
    match tier:
        1: return 3
        2, 3: return 4  
        4, 5: return 5
        6: return 6
        _: return 3  # Default fallback

func get_random_card_for_tier(tier: int) -> String:
    """Get a random card ID for the specified tier that's available in the pool"""
    var available_cards = []
    
    # Find all cards of this tier that have remaining copies
    for card_id in card_pool.keys():
        if card_pool[card_id] > 0:  # Has remaining copies
            var card_data = CardDatabase.get_card_data(card_id)
            if card_data.get("tier", 1) == tier:
                available_cards.append(card_id)
    
    if available_cards.is_empty():
        print("Warning: No available cards for tier ", tier)
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

func add_card_to_shop(card_id: String):
    """Add a card to the shop area"""
    var card_data = CardDatabase.get_card_data(card_id)
    var new_card = CardScene.instantiate()
    new_card.setup_card_data(card_data)
    
    # Connect shop-specific click handler (different from hand cards)
    new_card.card_clicked.connect(_on_shop_card_clicked.bind(card_id))
    
    # Store card_id for purchase logic
    new_card.set_meta("card_id", card_id)
    
    $MainLayout/ShopArea.add_child(new_card)

func _on_shop_card_clicked(card_id: String):
    """Handle clicking a card in the shop to purchase it"""
    var card_data = CardDatabase.get_card_data(card_id)
    var cost = card_data.get("cost", 3)
    
    print("Attempting to purchase ", card_data.get("name", "Unknown"), " for ", cost, " gold")
    
    # Check if player can afford and has hand space
    if not can_afford(cost):
        print("Cannot afford card - need ", cost, " gold, have ", current_gold)
        return
    
    if is_hand_full():
        print("Cannot purchase - hand is full (", get_hand_size(), "/", max_hand_size, ")")
        return
    
    # Check if card is still available in pool
    if card_pool.get(card_id, 0) <= 0:
        print("Card no longer available in pool")
        return
    
    # Execute purchase
    if spend_gold(cost):
        # Remove from pool
        card_pool[card_id] -= 1
        
        # Add to hand 
        add_card_to_hand_direct(card_id)
        
        # Remove from shop
        remove_card_from_shop(card_id)
        
        print("Purchased ", card_data.get("name", "Unknown"), " - Remaining in pool: ", card_pool[card_id])

func add_card_to_hand_direct(card_id: String):
    """Add a card directly to hand (used by purchase system)"""
    var card_data = CardDatabase.get_card_data(card_id)
    var new_card = CardScene.instantiate()
    new_card.setup_card_data(card_data)
    new_card.card_clicked.connect(_on_card_clicked)
    new_card.drag_started.connect(_on_card_drag_started)
    
    $MainLayout/PlayerHand.add_child(new_card)
    update_hand_count()

func remove_card_from_shop(card_id: String):
    """Remove the first instance of a card from the shop"""
    for child in $MainLayout/ShopArea.get_children():
        if child.get_meta("card_id", "") == card_id:
            child.queue_free()
            break

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
    var new_card = CardScene.instantiate()
    new_card.setup_card_data(data)
    new_card.card_clicked.connect(_on_card_clicked)
    new_card.drag_started.connect(_on_card_drag_started) # Add this
    #new_card.dropped.connect(_on_card_dropped)
    $MainLayout/PlayerHand.add_child(new_card)
    update_hand_count() # Update the hand count display

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
    
    # Set all other cards to ignore mouse events during dragging
    _set_all_cards_mouse_filter(Control.MOUSE_FILTER_IGNORE, card)
    
    # "Lift" the card out of the container by making it a child of the main board
    card.reparent(self)
    # Ensure the dragged card renders on top of everything else
    card.move_to_front()
    print(card.name, " started dragging.")

func _on_card_dropped(card):
    print(card.name, " was dropped.")
    var cards_in_hand = $MainLayout/PlayerHand.get_children()
    var new_index = -1

    # Find where to place the card based on its X position
    for i in range(cards_in_hand.size()):
        if card.global_position.x < cards_in_hand[i].global_position.x:
            new_index = i
            break

    # Put the card back into the container
    card.reparent($MainLayout/PlayerHand)

    # Move it to the calculated position
    if new_index != -1:
        $MainLayout/PlayerHand.move_child(card, new_index)
    else:
        # If it was dropped past the last card, move it to the end
        $MainLayout/PlayerHand.move_child(card, $MainLayout/PlayerHand.get_child_count() - 1)
    
    # Restore mouse filters for all cards
    card.mouse_filter = Control.MOUSE_FILTER_STOP
    _set_all_cards_mouse_filter(Control.MOUSE_FILTER_STOP)
    
    dragged_card = null # Forget the card now that it's dropped

func _unhandled_input(event):
    if dragged_card: # This check is now primary
        if event is InputEventMouseMotion:
            dragged_card.global_position = get_global_mouse_position() - dragged_card.drag_offset

        if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
            # Manually call the drop function when the mouse is released anywhere
            _on_card_dropped(dragged_card)

func _ready():
    # Initialize game state
    initialize_card_pool()
    update_ui_displays()
    update_hand_count()
    update_board_count()
    
    # Initialize shop with cards
    refresh_shop()
    
    # Deal a specific starting hand (mix of minions and spells for testing)
    add_card_to_hand("murloc_raider")
    add_card_to_hand("dire_wolf_alpha")
    add_card_to_hand("coin")  # Test spell card (no attack/health)
    add_card_to_hand("kindly_grandmother")


func _on_refresh_shop_button_pressed() -> void:
    var refresh_cost = 1
    if spend_gold(refresh_cost):
        refresh_shop()
        print("Shop refreshed for ", refresh_cost, " gold")
    else:
        print("Cannot refresh shop - need ", refresh_cost, " gold")

func _on_upgrade_shop_button_pressed() -> void:
    # Temporary test: Increase base gold (normally this would upgrade shop tier for 5 gold)
    if spend_gold(2):
        increase_base_gold(1)
        print("TEST: Spent 2 gold to increase base gold by 1")

func _on_end_turn_button_pressed() -> void:
    print("End turn button pressed")
    start_new_turn()
