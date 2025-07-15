extends Control

const DEFAULT_PORT = 9999
const CardScene = preload("res://card.tscn")

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
	$PlayerHand.add_child(new_card)

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
