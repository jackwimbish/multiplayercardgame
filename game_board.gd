extends Control

const DEFAULT_PORT = 9999
const CardScene = preload("res://card.tscn")
var dragged_card = null

# Core game state variables
var current_turn: int = 1
var current_gold: int = 3
var max_gold: int = 3
var shop_tier: int = 1
var card_pool: Dictionary = {}

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

func calculate_max_gold_for_turn(turn: int) -> int:
    """Calculate maximum gold for a given turn (3 on turn 1, +1 per turn up to 10)"""
    if turn <= 1:
        return 3
    elif turn <= 8:
        return 2 + turn  # Turn 2=4 gold, turn 3=5 gold, ..., turn 8=10 gold
    else:
        return 10  # Maximum of 10 gold from turn 8 onwards

func start_new_turn():
    """Advance to the next turn and refresh gold"""
    current_turn += 1
    max_gold = calculate_max_gold_for_turn(current_turn)
    current_gold = max_gold  # Refresh to full gold
    
    print("Turn ", current_turn, " started - Gold: ", current_gold, "/", max_gold)
    update_ui_displays()

func update_ui_displays():
    """Update all UI elements with current game state"""
    $MainLayout/TopUI/GoldLabel.text = "Gold: " + str(current_gold) + "/" + str(max_gold)
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

func _on_card_drag_started(card):
    dragged_card = card # Keep track of the dragged card
    card.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
    card.mouse_filter = Control.MOUSE_FILTER_STOP
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
    
    # Deal a specific starting hand (mix of minions and spells for testing)
    add_card_to_hand("murloc_raider")
    add_card_to_hand("dire_wolf_alpha")
    add_card_to_hand("coin")  # Test spell card (no attack/health)
    add_card_to_hand("kindly_grandmother")


func _on_refresh_shop_button_pressed() -> void:
    print("Refresh shop button pressed - TODO: implement shop refresh")

func _on_upgrade_shop_button_pressed() -> void:
    print("Upgrade shop button pressed - TODO: implement shop tier upgrade")

func _on_end_turn_button_pressed() -> void:
    print("End turn button pressed")
    start_new_turn()
