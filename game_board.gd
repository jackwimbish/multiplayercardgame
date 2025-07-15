extends Control

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

func add_card_to_hand(card_id):
	# Get the specific card's data from our database
	var data = CARD_DATA[card_id]

	var new_card = CardScene.instantiate()
	
	# Call the new setup function on the card
	new_card.setup_card_data(data)

	new_card.card_clicked.connect(_on_card_clicked)
	$PlayerHand.add_child(new_card)

func _ready():
	# Deal a specific starting hand
	add_card_to_hand("fireball")
	add_card_to_hand("novice_engineer")
	add_card_to_hand("fireball")
	add_card_to_hand("frostbolt")
