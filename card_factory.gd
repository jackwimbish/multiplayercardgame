# CardFactory.gd (Autoload Singleton)
# Centralized factory for creating card instances with proper typing and setup

extends Node

# Preload required resources
const CardScene = preload("res://card.tscn")
const MinionScript = preload("res://minion_card.gd")

## Create a card instance from card data and optional card ID
## @param card_data: Dictionary containing card properties from CardDatabase
## @param card_id: Optional string identifier to preserve card ID in enhanced data
## @return: Configured card node ready for use, or null if creation fails
func create_card(card_data: Dictionary, card_id: String = "") -> Node:
	"""Create the appropriate card instance based on card type"""
	
	# Validate input data
	if card_data.is_empty():
		push_error("CardFactory: Cannot create card with empty card_data")
		return null
	
	# Create base card instance
	var new_card = CardScene.instantiate()
	if not new_card:
		push_error("CardFactory: Failed to instantiate CardScene")
		return null
	
	# Prepare enhanced card data with preserved ID
	var enhanced_card_data = card_data.duplicate()
	if card_id != "":
		enhanced_card_data["id"] = card_id
	
	# Apply specialized script for minion cards
	if enhanced_card_data.get("type", "") == "minion":
		new_card.set_script(MinionScript)
	
	# Setup card with enhanced data
	new_card.setup_card_data(enhanced_card_data)
	
	return new_card

## Create a card directly from card ID using CardDatabase lookup
## @param card_id: String identifier for the card in CardDatabase
## @return: Configured card node ready for use, or null if card not found
func create_card_from_id(card_id: String) -> Node:
	"""Create a card instance directly from card ID using database lookup"""
	
	if card_id.is_empty():
		push_error("CardFactory: Cannot create card with empty card_id")
		return null
	
	var card_data = CardDatabase.get_card_data(card_id)
	if card_data.is_empty():
		push_error("CardFactory: Card not found in database: " + card_id)
		return null
	
	return create_card(card_data, card_id)

## Validate that a card can be created from the given data
## @param card_data: Dictionary containing card properties
## @return: true if card can be created, false otherwise
func can_create_card(card_data: Dictionary) -> bool:
	"""Check if card data is valid for card creation"""
	return not card_data.is_empty() and card_data.has("name") 