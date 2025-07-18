# CardFactory.gd (Autoload Singleton)
# Centralized factory for creating card instances with proper typing and setup

extends Node

# Preload required resources
const CardScene = preload("res://card.tscn")
const MinionScript = preload("res://minion_card.gd")

## Create a card instance from card data with optional signal handlers
## @param card_data: Dictionary containing card properties from CardDatabase
## @param card_id: Optional string identifier to preserve card ID in enhanced data
## @param signal_handlers: Optional dictionary of signal connections
## @return: Configured card node ready for use, or null if creation fails
func create_card(card_data: Dictionary, card_id: String = "", signal_handlers: Dictionary = {}) -> Node:
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
	
	# Connect signals based on provided handlers
	_connect_card_signals(new_card, signal_handlers)
	
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

## Create an interactive card with standard drag-and-drop signal connections
## @param card_data: Dictionary containing card properties from CardDatabase  
## @param card_id: Optional string identifier to preserve card ID in enhanced data
## @return: Configured card node with interactive signals connected
func create_interactive_card(card_data: Dictionary, card_id: String = "") -> Node:
	"""Create a card with standard interactive signal handlers for game board use"""
	var handlers = {
		"card_clicked": _get_game_board()._on_card_clicked if _get_game_board() else null,
		"drag_started": _get_drag_handler() if _get_drag_handler() else null
	}
	return create_card(card_data, card_id, handlers)

## Connect signals for a card based on provided handlers
## @param card: The card node to connect signals for
## @param signal_handlers: Dictionary mapping signal names to callable handlers
func _connect_card_signals(card: Node, signal_handlers: Dictionary):
	"""Connect card signals based on provided handlers"""
	if signal_handlers.has("card_clicked") and signal_handlers["card_clicked"] != null:
		if card.has_signal("card_clicked"):
			card.card_clicked.connect(signal_handlers["card_clicked"])
	
	if signal_handlers.has("drag_started") and signal_handlers["drag_started"] != null:
		if card.has_signal("drag_started"):
			card.drag_started.connect(signal_handlers["drag_started"])

## Get reference to the game board for signal connections
## @return: Game board node or null if not found
func _get_game_board():
	"""Safe way to get the game board instance"""
	var game_board = get_tree().get_first_node_in_group("game_board")
	if not game_board:
		push_warning("CardFactory: No game_board found in scene tree")
	return game_board

## Get the appropriate drag handler (DragDropManager or game board fallback)
## @return: Callable for drag handling or null
func _get_drag_handler():
	"""Get the drag handler, preferring DragDropManager over game board"""
	# Try DragDropManager first (it should exist as an autoload)
	if has_node("/root/DragDropManager"):
		return get_node("/root/DragDropManager").start_drag
	
	# Fallback to game board's drag handler
	var game_board = _get_game_board()
	if game_board and game_board.has_method("_on_card_drag_started"):
		return game_board._on_card_drag_started
	
	return null

## Validate that a card can be created from the given data
## @param card_data: Dictionary containing card properties
## @return: true if card can be created, false otherwise
func can_create_card(card_data: Dictionary) -> bool:
	"""Check if card data is valid for card creation"""
	return not card_data.is_empty() and card_data.has("name") 