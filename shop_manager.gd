class_name ShopManager
extends RefCounted

## Shop Manager handles all shop/tavern functionality
## Manages shop inventory, purchasing, rerolling, and tier progression

# References to UI components
var shop_area: Container
var ui_manager: UIManager

# Shop state
var current_shop_cards: Array[String] = []  # Track current shop card IDs

# Constants
const REFRESH_COST: int = 1

signal shop_refreshed()
signal card_purchased(card_id: String, cost: int)
signal shop_upgraded(new_tier: int, cost: int)

func _init(shop_area_ref: Container, ui_manager_ref: UIManager):
	"""Initialize ShopManager with required references"""
	shop_area = shop_area_ref
	ui_manager = ui_manager_ref
	
	# Connect to GameState signals
	GameState.shop_tier_changed.connect(_on_shop_tier_changed)
	
	print("ShopManager initialized")

func _on_shop_tier_changed(new_tier: int) -> void:
	"""Handle shop tier changes from GameState"""
	refresh_shop()

# === SHOP SIZE AND TIER LOGIC ===

func get_shop_size_for_tier(tier: int) -> int:
	"""Get number of cards shown in shop for given tier"""
	match tier:
		1: return 3
		2, 3: return 4  
		4, 5: return 5
		6: return 6
		_: return 3  # Default fallback

# === CARD SELECTION LOGIC ===

func get_random_card_for_shop(max_tier: int) -> String:
	"""Get a random card ID from max_tier and below, weighted by copies in pool"""
	var weighted_cards = []
	
	# Create weighted selection based on pool copies (more copies = higher chance)
	for card_id in GameState.card_pool.keys():
		var copies_available = GameState.card_pool[card_id]
		if copies_available > 0:  # Has remaining copies
			var card_data = CardDatabase.get_card_data(card_id)
			var card_tier = card_data.get("tier", 1)
			
			# Include cards from max_tier and below that are shop-available
			if card_tier <= max_tier and card_data.get("shop_available", true):
				# Add this card_id multiple times based on copies available
				for i in range(copies_available):
					weighted_cards.append(card_id)
	
	if weighted_cards.is_empty():
		print("Warning: No available shop cards for tier ", max_tier, " and below")
		return ""
	
	# Return random card from weighted options
	return weighted_cards[randi() % weighted_cards.size()]

# === SHOP REFRESH LOGIC ===

func refresh_shop() -> void:
	"""Clear and populate the shop with random cards for current tier"""
	_clear_shop_cards()
	_populate_shop_with_new_cards()
	shop_refreshed.emit()

func _clear_shop_cards() -> void:
	"""Clear existing shop cards (except label)"""
	for child in shop_area.get_children():
		if child.name != "ShopAreaLabel":
			child.queue_free()
	current_shop_cards.clear()

func _populate_shop_with_new_cards() -> void:
	"""Populate shop with new random cards for current tier"""
	var shop_size = get_shop_size_for_tier(GameState.shop_tier)
	print("Refreshing shop (tier ", GameState.shop_tier, ") with ", shop_size, " cards")
	
	# Add new random cards to shop
	for i in range(shop_size):
		var card_id = get_random_card_for_shop(GameState.shop_tier)
		if card_id != "":
			_add_card_to_shop(card_id)

func _add_card_to_shop(card_id: String) -> void:
	"""Add a card to the shop area"""
	var card_data = CardDatabase.get_card_data(card_id)
	var new_card = _create_card_instance(card_data, card_id)
	
	# Connect drag handler for shop cards (drag-to-purchase)
	new_card.drag_started.connect(_on_shop_card_drag_started)
	
	# Store card_id for purchase logic
	new_card.set_meta("card_id", card_id)
	
	shop_area.add_child(new_card)
	current_shop_cards.append(card_id)

func _create_card_instance(card_data: Dictionary, card_id: String = "") -> Node:
	"""Create the appropriate card instance based on card type"""
	const CardScene = preload("res://card.tscn")
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

# === PURCHASE LOGIC ===

func can_purchase_card(card_id: String) -> Dictionary:
	"""Check if a card can be purchased, return result with reason"""
	var card_data = CardDatabase.get_card_data(card_id)
	var cost = card_data.get("cost", 3)
	
	# Check affordability
	if not GameState.can_afford(cost):
		return {"can_purchase": false, "reason": "insufficient_gold", "cost": cost}
	
	# Check hand space
	if ui_manager.is_hand_full():
		return {"can_purchase": false, "reason": "hand_full", "cost": cost}
	
	# Check card availability in pool
	if GameState.card_pool.get(card_id, 0) <= 0:
		return {"can_purchase": false, "reason": "not_available", "cost": cost}
	
	return {"can_purchase": true, "reason": "valid", "cost": cost}

func purchase_card(card_id: String) -> bool:
	"""Attempt to purchase a card, return success"""
	var purchase_check = can_purchase_card(card_id)
	
	if not purchase_check.can_purchase:
		_handle_purchase_failure(card_id, purchase_check)
		return false
	
	var cost = purchase_check.cost
	
	# Execute purchase
	if GameState.spend_gold(cost):
		# Remove from pool
		GameState.card_pool[card_id] -= 1
		
		# Add to hand
		_add_card_to_hand_direct(card_id)
		
		# Remove from shop
		_remove_card_from_shop(card_id)
		
		card_purchased.emit(card_id, cost)
		
		var card_data = CardDatabase.get_card_data(card_id)
		print("Purchased ", card_data.get("name", "Unknown"), " for ", cost, " gold - Remaining in pool: ", GameState.card_pool[card_id])
		return true
	
	return false

func _handle_purchase_failure(card_id: String, result: Dictionary) -> void:
	"""Handle and log purchase failure reasons"""
	var card_data = CardDatabase.get_card_data(card_id)
	var card_name = card_data.get("name", "Unknown")
	
	match result.reason:
		"insufficient_gold":
			print("Cannot afford ", card_name, " - costs ", result.cost, " gold, have ", GameState.current_gold)
		"hand_full":
			print("Cannot purchase ", card_name, " - hand is full (", ui_manager.get_hand_size(), "/", ui_manager.max_hand_size, ")")
		"not_available":
			print("Card ", card_name, " no longer available in pool")

func _add_card_to_hand_direct(card_id: String) -> void:
	"""Add a card directly to hand (used by purchase system)"""
	var card_data = CardDatabase.get_card_data(card_id)
	var new_card = _create_card_instance(card_data, card_id)
	
	new_card.card_clicked.connect(ui_manager._on_card_clicked)
	new_card.drag_started.connect(ui_manager._on_card_drag_started)
	
	ui_manager.get_hand_container().add_child(new_card)
	ui_manager.update_hand_display()

func _remove_card_from_shop(card_id: String) -> void:
	"""Remove a specific card from the shop"""
	for child in shop_area.get_children():
		if child.get_meta("card_id", "") == card_id:
			child.queue_free()
			break
	
	current_shop_cards.erase(card_id)

# === SHOP REFRESH/REROLL ===

func can_refresh_shop() -> bool:
	"""Check if shop can be refreshed"""
	return GameState.can_afford(REFRESH_COST)

func refresh_shop_for_cost() -> bool:
	"""Refresh shop for the standard cost"""
	if can_refresh_shop():
		if GameState.spend_gold(REFRESH_COST):
			refresh_shop()
			print("Shop refreshed for %d gold" % REFRESH_COST)
			return true
	else:
		print("Cannot afford shop refresh - need %d gold, have %d" % [REFRESH_COST, GameState.current_gold])
	return false

# === TAVERN UPGRADE ===

func can_upgrade_tavern() -> bool:
	"""Check if tavern can be upgraded"""
	return GameState.can_upgrade_tavern()

func upgrade_tavern() -> bool:
	"""Attempt to upgrade tavern tier"""
	if GameState.can_upgrade_tavern():
		var upgrade_cost = GameState.calculate_tavern_upgrade_cost()
		if GameState.upgrade_tavern_tier():
			shop_upgraded.emit(GameState.shop_tier, upgrade_cost)
			print("Tavern upgraded to tier %d for %d gold" % [GameState.shop_tier, upgrade_cost])
			# refresh_shop() is automatically called via the shop_tier_changed signal
			return true
		else:
			print("Cannot afford tavern upgrade - need %d gold, have %d" % [upgrade_cost, GameState.current_gold])
	else:
		print("Tavern already at maximum tier (%d)" % GameState.shop_tier)
	return false

# === EVENT HANDLERS ===

func _on_shop_card_drag_started(card: Node) -> void:
	"""Handle when a shop card drag starts"""
	# Forward to UI manager for unified drag handling
	ui_manager._on_card_drag_started(card)

# === PUBLIC INTERFACE FOR GAME_BOARD ===

func handle_refresh_button_pressed() -> void:
	"""Handle refresh shop button press"""
	refresh_shop_for_cost()

func handle_upgrade_button_pressed() -> void:
	"""Handle upgrade shop button press"""
	upgrade_tavern()

func handle_shop_card_purchase_by_drag(card: Node) -> bool:
	"""Handle shop card purchase via drag and drop"""
	var card_id = card.get_meta("card_id", "")
	if card_id == "":
		print("Error: Shop card missing card_id metadata")
		return false
	
	# For drag purchases, validate and execute purchase without removing from shop
	# (the dragged card IS the shop card and will be cleaned up by game_board)
	var purchase_check = can_purchase_card(card_id)
	
	if not purchase_check.can_purchase:
		_handle_purchase_failure(card_id, purchase_check)
		return false
	
	var cost = purchase_check.cost
	
	# Execute purchase
	if GameState.spend_gold(cost):
		# Remove from pool
		GameState.card_pool[card_id] -= 1
		
		# Add to hand
		_add_card_to_hand_direct(card_id)
		
		# Remove one instance from tracking (erase removes first occurrence)
		current_shop_cards.erase(card_id)
		
		card_purchased.emit(card_id, cost)
		
		var card_data = CardDatabase.get_card_data(card_id)
		print("Purchased ", card_data.get("name", "Unknown"), " for ", cost, " gold - Remaining in pool: ", GameState.card_pool[card_id])
		return true
	
	return false 