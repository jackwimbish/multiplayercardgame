extends Control

const DEFAULT_PORT = 9999
const CardScene = preload("res://card.tscn")
var dragged_card = null



func _on_card_clicked(card_node):
    print("A card was selected: ", card_node.get_node("VBoxContainer/CardName").text)

func update_hand_count():
    var hand_size = $MainLayout/PlayerHand.get_children().size() - 1 # Subtract 1 for the label
    $MainLayout/PlayerHand/PlayerHandLabel.text = "Your Hand (" + str(hand_size) + "/10)"

func update_board_count():
    var board_size = $MainLayout/PlayerBoard.get_children().size() - 1 # Subtract 1 for the label
    $MainLayout/PlayerBoard/PlayerBoardLabel.text = "Your Board (" + str(board_size) + "/7)"
    
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
    # Initialize count displays
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
    print("End turn button pressed - TODO: implement turn progression")
