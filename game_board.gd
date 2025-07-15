extends Control

const DEFAULT_PORT = 9999
const CardScene = preload("res://card.tscn")
var dragged_card = null

# Our simple card database
const CARD_DATA = {
    "fireball": {
        "name": "Fireball",
        "description": "Deal 6 damage.",
        "cost": 4
    },
    "frostbolt": {
        "name": "Frostbolt",
        "description": "Deal 2 damage and Freeze a character.",
        "cost": 2
    },
    "novice_engineer": {
        "name": "Novice Engineer",
        "description": "Battlecry: Draw a card.",
        "cost": 2
    }
}

func _on_card_clicked(card_node):
    print("A card was selected: ", card_node.get_node("VBoxContainer/CardName").text)
    
@rpc("any_peer", "call_local")
func add_card_to_hand(card_id):
    # The rest of the function is the same as before
    var data = CARD_DATA[card_id]
    var new_card = CardScene.instantiate()
    new_card.setup_card_data(data)
    new_card.card_clicked.connect(_on_card_clicked)
    new_card.drag_started.connect(_on_card_drag_started) # Add this
    #new_card.dropped.connect(_on_card_dropped)
    $PlayerHand.add_child(new_card)

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
    var cards_in_hand = $PlayerHand.get_children()
    var new_index = -1

    # Find where to place the card based on its X position
    for i in range(cards_in_hand.size()):
        if card.global_position.x < cards_in_hand[i].global_position.x:
            new_index = i
            break

    # Put the card back into the container
    card.reparent($PlayerHand)

    # Move it to the calculated position
    if new_index != -1:
        $PlayerHand.move_child(card, new_index)
    else:
        # If it was dropped past the last card, move it to the end
        $PlayerHand.move_child(card, $PlayerHand.get_child_count() - 1)
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
    # Deal a specific starting hand
    add_card_to_hand("fireball")
    add_card_to_hand("novice_engineer")
    add_card_to_hand("fireball")
    add_card_to_hand("frostbolt")


func _on_host_button_pressed() -> void:
    var peer = ENetMultiplayerPeer.new()
    peer.create_server(DEFAULT_PORT)
    multiplayer.multiplayer_peer = peer
    print("Server started. Waiting for players.")


func _on_join_button_pressed() -> void:
    var ip = $NetworkUI/IPAddressField.text
    if ip == "":
        ip = "127.0.0.1" # Default to localhost for easy testing
    
    var peer = ENetMultiplayerPeer.new()
    peer.create_client(ip, DEFAULT_PORT)
    multiplayer.multiplayer_peer = peer
    print("Joining server at ", ip)


func _on_draw_button_pressed() -> void:
    # Instead of calling the function directly, we call the RPC
    add_card_to_hand.rpc("fireball")
