class_name CombatManager
extends RefCounted

## Combat Manager handles all combat functionality
## Manages combat simulation, UI mode switching, and result display

# References to required components
var ui_manager: UIManager
var main_layout: Control  # For accessing board containers
var shop_manager  # Reference to ShopManager for auto-refresh

# Combat state
var current_enemy_board_name: String = ""
var final_player_minions: Array = []     # Surviving CombatMinions
var final_enemy_minions: Array = []      # Surviving CombatMinions  
var original_player_count: int = 0       # For dead minion slots
var original_enemy_count: int = 0        # For dead minion slots

# Constants
const DEFAULT_COMBAT_DAMAGE: int = 5

# Signals for communication
signal combat_started(enemy_board_name: String)
signal combat_ended(result: Dictionary)
signal mode_switched(new_mode: String)

func _init(ui_manager_ref: UIManager, main_layout_ref: Control, shop_manager_ref = null):
	"""Initialize CombatManager with required references"""
	ui_manager = ui_manager_ref
	main_layout = main_layout_ref
	shop_manager = shop_manager_ref
	
	print("CombatManager initialized")

# === PUBLIC INTERFACE FOR GAME_BOARD ===

func start_combat(enemy_board_name: String) -> void:
	"""Main entry point to start combat against an enemy board"""
	print("Starting combat against: %s" % enemy_board_name)
	current_enemy_board_name = enemy_board_name
	
	# Switch to combat screen
	switch_to_combat_mode(enemy_board_name)
	
	# Run combat simulation and display results
	var combat_result = simulate_full_combat(enemy_board_name)
	display_combat_log(combat_result)
	
	# Automatically show the combined result view (log + final board states)
	_show_combat_result_with_log()
	
	combat_started.emit(enemy_board_name)

func return_to_shop() -> void:
	"""Handle returning to shop mode after combat"""
	print("Returning to shop from combat")
	
	# Return to shop mode
	switch_to_shop_mode()
	
	# Start next turn after combat (increments turn, refreshes gold)
	GameState.start_new_turn()
	
	# Auto-refresh shop for new turn (respecting freeze in Phase 2)
	if shop_manager:
		shop_manager.refresh_shop()
		print("Shop auto-refreshed for turn %d" % GameState.current_turn)

func handle_enemy_board_selection(index: int) -> void:
	"""Handle enemy board selection from dropdown"""
	if index < 0 or index >= ui_manager.enemy_board_selector.get_item_count():
		return
	
	var selected_board = ui_manager.enemy_board_selector.get_item_text(index)
	current_enemy_board_name = selected_board
	
	# Update enemy health based on selected board
	var board_data = EnemyBoards.create_enemy_board(selected_board)
	GameState.set_enemy_health(board_data.get("health", GameState.enemy_health))
	
	print("Selected enemy board: %s (Health: %d)" % [board_data.get("name", selected_board), board_data.get("health", GameState.enemy_health)])

# === CORE COMBAT ALGORITHM ===

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
	
	# Check for immediate win conditions (empty armies)
	if player_minions.is_empty() and enemy_minions.is_empty():
		action_log.append({"type": "combat_tie", "reason": "both_no_minions"})
		return action_log
	elif player_minions.is_empty():
		action_log.append({"type": "combat_end", "winner": "enemy", "reason": "player_no_minions"})
		GameState.take_damage(DEFAULT_COMBAT_DAMAGE, true)
		return action_log
	elif enemy_minions.is_empty():
		action_log.append({"type": "combat_end", "winner": "player", "reason": "enemy_no_minions"})
		GameState.take_damage(DEFAULT_COMBAT_DAMAGE, false)
		return action_log
	
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
	
	# Main combat loop
	while attack_count < max_attacks:
		# Check if combat should continue (both sides have minions)
		if player_minions.is_empty() or enemy_minions.is_empty():
			# This should be caught by the post-attack win condition check,
			# but this is a safety check for the first iteration
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
		
		# Check if we have valid attacker and defender before executing attack
		if attacker == null or defender == null:
			action_log.append({"type": "combat_end", "reason": "null_combatant", "winner": "tie"})
			break
		
		# Execute attack (even 0-damage attacks count as attempts)
		execute_attack(attacker, defender, action_log)
		attack_count += 1
		
		# Remove dead minions
		player_minions = player_minions.filter(func(m): return m.current_health > 0)
		enemy_minions = enemy_minions.filter(func(m): return m.current_health > 0)
		
		# Check win conditions after removing dead minions
		if player_minions.is_empty() and enemy_minions.is_empty():
			action_log.append({"type": "combat_tie", "reason": "both_no_minions"})
			break
		elif player_minions.is_empty():
			action_log.append({"type": "combat_end", "winner": "enemy", "reason": "player_no_minions"})
			GameState.take_damage(DEFAULT_COMBAT_DAMAGE, true)
			break
		elif enemy_minions.is_empty():
			action_log.append({"type": "combat_end", "winner": "player", "reason": "enemy_no_minions"})
			GameState.take_damage(DEFAULT_COMBAT_DAMAGE, false)
			break
		
		# Advance turn
		if p_turn:
			p_attacker_index += 1
		else:
			e_attacker_index += 1
		p_turn = not p_turn
	
	# Handle max attacks reached
	if attack_count >= max_attacks:
		action_log.append({"type": "combat_tie", "reason": "max_attacks_reached"})
	
	# Store final combat state for result view
	final_player_minions = player_minions.duplicate(true)
	final_enemy_minions = enemy_minions.duplicate(true)
	
	return action_log

func execute_attack(attacker, defender, action_log: Array) -> void:
	"""Execute a single attack between two minions"""
	var damage_to_defender = attacker.get_effective_attack()
	var damage_to_attacker = defender.get_effective_attack()
	
	# Capture health BEFORE damage for logging
	var attacker_health_before = attacker.current_health
	var defender_health_before = defender.current_health
	
	# Apply damage
	defender.take_damage(damage_to_defender)
	attacker.take_damage(damage_to_attacker)
	
	# Log the attack with health BEFORE damage
	action_log.append({
		"type": "attack",
		"attacker_id": attacker.get_display_name(),
		"defender_id": defender.get_display_name(),
		"attacker_attack": attacker.get_effective_attack(),
		"defender_attack": defender.get_effective_attack(),
		"damage_dealt": damage_to_defender,
		"damage_received": damage_to_attacker,
		"attacker_health": attacker_health_before,
		"defender_health": defender_health_before
	})
	
	# Check for deaths and log them
	if defender.current_health <= 0:
		action_log.append({
			"type": "death",
			"target_id": defender.get_display_name()
		})
	
	if attacker.current_health <= 0:
		action_log.append({
			"type": "death", 
			"target_id": attacker.get_display_name()
		})

func simulate_full_combat(enemy_board_name: String) -> Array:
	"""Simulate a complete combat and return the action log"""
	print("=== COMBAT SIMULATION START ===")
	
	# Create combat armies
	var player_army = create_player_combat_army()
	var enemy_army = create_enemy_combat_army(enemy_board_name)
	
	# Store original counts for result view  
	original_player_count = player_army.size()
	original_enemy_count = enemy_army.size()
	
	print("Player army: %d minions vs Enemy army (%s): %d minions" % [player_army.size(), enemy_board_name, enemy_army.size()])
	
	# Run the actual combat simulation
	var combat_log = run_combat(player_army, enemy_army)
	
	print("=== COMBAT SIMULATION COMPLETE ===")
	return combat_log

# === ARMY CREATION FUNCTIONS ===

func create_player_combat_army() -> Array:
	"""Create CombatMinion array from player's board"""
	var combat_army = []
	var minion_index = 0
	
	for child in main_layout.get_node("PlayerBoard").get_children():
		if child.name != "PlayerBoardLabel" and child.has_method("get_card_data"):
			var card_data = child.get_card_data()
			if card_data.get("type") == "minion":
				var combat_minion = CombatMinion.create_from_board_minion(child, "player_%d" % minion_index)
				combat_minion.position = minion_index  # Set the position for final board display
				combat_army.append(combat_minion)
				minion_index += 1
	
	print("Created player combat army: %d minions" % combat_army.size())
	return combat_army

func create_enemy_combat_army(enemy_board_name: String) -> Array:
	"""Create CombatMinion array from enemy board definition"""
	var enemy_board_data = EnemyBoards.create_enemy_board(enemy_board_name)
	var combat_army = []
	var minion_index = 0
	
	for minion_data in enemy_board_data.get("minions", []):
		var combat_minion = CombatMinion.create_from_enemy_data(minion_data, "enemy_%d" % minion_index)
		combat_minion.position = minion_index  # Set the position for final board display
		combat_army.append(combat_minion)
		minion_index += 1
	
	print("Created enemy combat army: %d minions" % combat_army.size())
	return combat_army

# === MODE SWITCHING FUNCTIONS ===

func switch_to_combat_mode(enemy_board_name: String) -> void:
	"""Switch to combat screen view"""
	GameState.current_mode = GameState.GameMode.COMBAT
	current_enemy_board_name = enemy_board_name
	
	# Hide shop elements
	_hide_shop_elements()
	
	# Show enemy board in shop area
	_display_enemy_board_in_shop_area(enemy_board_name)
	
	# Update combat UI for combat mode
	_update_combat_ui_for_combat_mode()
	
	# Hide/minimize hand area
	_minimize_hand_area()
	
	print("Switched to combat mode vs %s" % enemy_board_name)
	mode_switched.emit("combat")

func switch_to_shop_mode() -> void:
	"""Switch back to shop/tavern view"""
	GameState.current_mode = GameState.GameMode.SHOP
	current_enemy_board_name = ""
	
	# Restore original shop area label
	main_layout.get_node("ShopArea/ShopAreaLabel").text = "Shop"
	main_layout.get_node("ShopArea/ShopAreaLabel").remove_theme_color_override("font_color")
	
	# Show shop elements
	_show_shop_elements()
	
	# Clear enemy board from shop area
	_clear_enemy_board_from_shop_area()
	
	# Restore original player board (in case we were in result view)
	_restore_original_player_board()
	
	# Reset battle selection display (clear previous combat log)
	if ui_manager.combat_log_display:
		ui_manager.combat_log_display.clear()
		ui_manager.combat_log_display.text = "[b]Next Battle[/b]\n\nSelect an enemy board and click 'Start Combat' to begin."
	
	# Update combat UI for shop mode
	_update_combat_ui_for_shop_mode()
	
	# Show hand area normally
	_show_hand_area()
	
	print("Switched to shop mode")
	mode_switched.emit("shop")

func _hide_shop_elements() -> void:
	"""Hide shop cards and shop-related buttons"""
	# Hide shop cards (but keep the ShopAreaLabel visible)
	for child in main_layout.get_node("ShopArea").get_children():
		if child.name != "ShopAreaLabel":
			child.visible = false
	
	# Hide shop-related buttons
	main_layout.get_node("TopUI/RefreshShopButton").visible = false
	main_layout.get_node("TopUI/FreezeButton").visible = false
	main_layout.get_node("TopUI/UpgradeShopButton").visible = false

func _show_shop_elements() -> void:
	"""Show shop cards and shop-related buttons"""
	# Show shop cards (label should already be visible)
	for child in main_layout.get_node("ShopArea").get_children():
		child.visible = true
	
	# Show shop-related buttons
	main_layout.get_node("TopUI/RefreshShopButton").visible = true
	main_layout.get_node("TopUI/FreezeButton").visible = true
	main_layout.get_node("TopUI/UpgradeShopButton").visible = true

func _display_enemy_board_in_shop_area(enemy_board_name: String) -> void:
	"""Create and display enemy minions in the shop area"""
	var enemy_board_data = EnemyBoards.create_enemy_board(enemy_board_name)
	if enemy_board_data.is_empty():
		print("Failed to load enemy board: %s" % enemy_board_name)
		return
	
	# Update the existing shop area label to show enemy board
	main_layout.get_node("ShopArea/ShopAreaLabel").text = "Enemy Board: %s" % enemy_board_data.get("name", enemy_board_name)
	main_layout.get_node("ShopArea/ShopAreaLabel").add_theme_color_override("font_color", Color.RED)
	
	# Create visual representations of enemy minions
	for i in range(enemy_board_data.get("minions", []).size()):
		var enemy_minion_data = enemy_board_data.minions[i]
		var card_data = CardDatabase.get_card_data(enemy_minion_data.card_id).duplicate()
		
		# Apply any buffs to the card data for display
		for buff_data in enemy_minion_data.get("buffs", []):
			if buff_data.type == "stat_modification":
				card_data.attack += buff_data.get("attack_bonus", 0)
				card_data.health += buff_data.get("health_bonus", 0)
		
		# Create enemy card using CardFactory
		var enemy_card = _create_enemy_card_placeholder(card_data, enemy_minion_data.card_id, i)
		main_layout.get_node("ShopArea").add_child(enemy_card)

func _create_enemy_card_placeholder(card_data: Dictionary, card_id: String, index: int) -> Control:
	"""Create enemy card display using CardFactory"""
	var enemy_card = CardFactory.create_card(card_data, card_id)
	enemy_card.name = "EnemyMinion_%d" % index
	
	# Make enemy cards non-interactive
	enemy_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Add visual indication this is an enemy
	enemy_card.modulate = Color(1.0, 0.8, 0.8)  # Slight red tint
	
	return enemy_card

func _clear_enemy_board_from_shop_area() -> void:
	"""Remove enemy minions from shop area"""
	var children_to_remove = []
	for child in main_layout.get_node("ShopArea").get_children():
		if (child.name.begins_with("EnemyMinion_") or 
			child.name.begins_with("EnemyResult_") or
			child.name.begins_with("EnemyDead_")) and child.name != "ShopAreaLabel":
			children_to_remove.append(child)
	
	for child in children_to_remove:
		child.queue_free()

func _minimize_hand_area() -> void:
	"""Minimize hand area during combat"""
	main_layout.get_node("PlayerHand").visible = false

func _show_hand_area() -> void:
	"""Show hand area normally during shop phase"""
	main_layout.get_node("PlayerHand").visible = true

func _update_combat_ui_for_combat_mode() -> void:
	"""Update combat UI elements for combat mode"""
	if ui_manager.start_combat_button:
		ui_manager.start_combat_button.visible = false
	
	if ui_manager.enemy_board_selector:
		ui_manager.enemy_board_selector.get_parent().visible = false
	
	# Create return to shop button if it doesn't exist
	if not ui_manager.return_to_shop_button:
		ui_manager.return_to_shop_button = Button.new()
		ui_manager.return_to_shop_button.name = "ReturnToShopButton"
		ui_manager.return_to_shop_button.text = "Return to Shop"
		ui_manager.apply_font_to_button(ui_manager.return_to_shop_button, ui_manager.UI_FONT_SIZE_MEDIUM)
		ui_manager.combat_ui_container.add_child(ui_manager.return_to_shop_button)
		ui_manager.return_to_shop_button.pressed.connect(return_to_shop)
	
	# Hide toggle button (no longer needed)
	if ui_manager.combat_view_toggle_button:
		ui_manager.combat_view_toggle_button.visible = false
	
	ui_manager.return_to_shop_button.visible = true
	
	# Make combat UI and log prominent and always visible
	if ui_manager.combat_ui_container:
		ui_manager.combat_ui_container.visible = true
		
	if ui_manager.combat_log_display:
		ui_manager.combat_log_display.custom_minimum_size = Vector2(600, 300)
		ui_manager.combat_log_display.add_theme_font_size_override("normal_font_size", ui_manager.UI_FONT_SIZE_MEDIUM)
		ui_manager.combat_log_display.add_theme_font_size_override("bold_font_size", ui_manager.UI_FONT_SIZE_LARGE)
		ui_manager.combat_log_display.visible = true

func _update_combat_ui_for_shop_mode() -> void:
	"""Update combat UI elements for shop mode"""
	if ui_manager.start_combat_button:
		ui_manager.start_combat_button.visible = true
	
	if ui_manager.enemy_board_selector:
		ui_manager.enemy_board_selector.get_parent().visible = true
	
	if ui_manager.combat_view_toggle_button:
		ui_manager.combat_view_toggle_button.visible = false
	
	if ui_manager.return_to_shop_button:
		ui_manager.return_to_shop_button.visible = false
	
	# Keep combat UI container visible but minimize combat log during shop mode
	if ui_manager.combat_ui_container:
		ui_manager.combat_ui_container.visible = true
		
	if ui_manager.combat_log_display:
		ui_manager.combat_log_display.custom_minimum_size = Vector2(400, 200)
		ui_manager.combat_log_display.visible = true  # Keep visible for "Next Battle" display

# === COMBAT DISPLAY FUNCTIONS ===

func display_combat_log(action_log: Array) -> void:
	"""Display combat actions in the combat log"""
	if not ui_manager.combat_log_display:
		return
		
	ui_manager.combat_log_display.clear()
	ui_manager.combat_log_display.append_text("[b]BATTLE LOG[/b]\n\n")
	
	for action in action_log:
		var log_line = format_combat_action(action)
		ui_manager.combat_log_display.append_text(log_line + "\n")

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

func _show_combat_result_with_log() -> void:
	"""Show the combined combat result view with both log and final board states"""
	# Combat log is already visible and populated
	
	# Clear current enemy board display
	_clear_enemy_board_from_shop_area()
	
	# Show final board states
	_display_final_player_board_with_dead()
	_display_final_enemy_board_with_dead()
	
	print("Showing combined combat result with log")

func _display_final_player_board_with_dead() -> void:
	"""Update player board to show final combat state with dead minions visible"""
	# Hide original minions instead of removing them
	for child in main_layout.get_node("PlayerBoard").get_children():
		if child.name != "PlayerBoardLabel":
			child.visible = false
	
	# Show surviving minions with updated health
	for i in range(original_player_count):
		var surviving_minion = null
		
		# Find surviving minion at this position
		for minion in final_player_minions:
			if minion.position == i:
				surviving_minion = minion
				break
		
		if surviving_minion:
			# Create card showing final state - will need delegation to game_board
			var result_card = _create_result_card_placeholder(surviving_minion, i, true)
			main_layout.get_node("PlayerBoard").add_child(result_card)
		else:
			# Create dead minion display
			var dead_minion = _create_dead_minion_card(i, true)
			dead_minion.name = "PlayerDead_%d" % i
			main_layout.get_node("PlayerBoard").add_child(dead_minion)

func _display_final_enemy_board_with_dead() -> void:
	"""Display final enemy board state in shop area with dead minions visible"""
	# Update the existing shop area label to show final state
	main_layout.get_node("ShopArea/ShopAreaLabel").text = "Enemy Final State"
	main_layout.get_node("ShopArea/ShopAreaLabel").add_theme_color_override("font_color", Color.RED)
	
	# Show surviving enemy minions with dead minions
	for i in range(original_enemy_count):
		var surviving_minion = null
		
		# Find surviving minion at this position
		for minion in final_enemy_minions:
			if minion.position == i:
				surviving_minion = minion
				break
		
		if surviving_minion:
			# Create card showing final state - will need delegation to game_board
			var result_card = _create_result_card_placeholder(surviving_minion, i, false)
			main_layout.get_node("ShopArea").add_child(result_card)
		else:
			# Create dead enemy minion display
			var dead_minion = _create_dead_minion_card(i, false)
			dead_minion.name = "EnemyDead_%d" % i
			main_layout.get_node("ShopArea").add_child(dead_minion)

func _create_result_card_placeholder(minion: CombatMinion, index: int, is_player: bool) -> Control:
	"""Create actual card visual showing final combat state"""
	var card_data = CardDatabase.get_card_data(minion.source_card_id).duplicate()
	
	# Update card data with final combat stats
	card_data["attack"] = minion.current_attack
	card_data["health"] = minion.current_health
	
	# Create actual card using CardFactory
	var result_card = CardFactory.create_card(card_data, minion.source_card_id)
	var owner_prefix = "Player" if is_player else "Enemy"
	result_card.name = "%sResult_%d" % [owner_prefix, index]
	
	# Make card non-interactive
	result_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Visual styling based on health status
	if minion.current_health <= 0:
		result_card.modulate = Color(1.0, 0.3, 0.3, 0.8)  # Red tint for dead
	elif minion.current_health < minion.max_health:
		result_card.modulate = Color(1.0, 0.8, 0.4, 1.0)  # Orange tint for damaged
	else:
		result_card.modulate = Color(0.8, 1.0, 0.8, 1.0)  # Green tint for undamaged
	
	# Add owner indication
	if not is_player:
		# Additional red tint for enemy cards
		result_card.modulate = result_card.modulate * Color(1.0, 0.7, 0.7, 1.0)
	
	return result_card

func _create_dead_minion_card(position: int, is_player: bool) -> Control:
	"""Create an actual card showing a dead minion (greyed out with 0 health)"""
	# Find the original minion data at this position
	var original_card_data = {}
	var original_minions = []
	
	# Get original minion data from current board before combat
	if is_player:
		for child in main_layout.get_node("PlayerBoard").get_children():
			if child.has_method("get_effective_attack") and child.name != "PlayerBoardLabel":
				original_minions.append(child.card_data.duplicate())
	else:
		# For enemy, we need to reconstruct from the enemy board name
		var enemy_board_data = EnemyBoards.create_enemy_board(current_enemy_board_name)
		for enemy_minion_data in enemy_board_data.get("minions", []):
			var card_data = CardDatabase.get_card_data(enemy_minion_data.card_id).duplicate()
			# Apply buffs
			for buff_data in enemy_minion_data.get("buffs", []):
				if buff_data.type == "stat_modification":
					card_data.attack += buff_data.get("attack_bonus", 0)
					card_data.health += buff_data.get("health_bonus", 0)
			original_minions.append(card_data)
	
	# Get card data for this position
	if position < original_minions.size():
		original_card_data = original_minions[position].duplicate()
	else:
		# Fallback if position is out of range
		original_card_data = {
			"name": "Unknown Minion",
			"description": "",
			"attack": 0,
			"health": 0,
			"id": "unknown"
		}
	
	# Set health to 0 to show it's dead
	original_card_data["health"] = 0
	
	# Create actual card using CardFactory
	var dead_card = CardFactory.create_card(original_card_data, original_card_data.get("id", "unknown"))
	
	# Make card non-interactive
	dead_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Apply death visual effects
	dead_card.modulate = Color(0.4, 0.4, 0.4, 0.7)  # Dark greyed out
	
	# Add "DEAD" overlay styling by modifying the health display color
	var stats_label = dead_card.get_node_or_null("VBoxContainer/BottomRow/StatsLabel")
	if stats_label:
		stats_label.add_theme_color_override("font_color", Color.RED)
	
	# Add enemy indication if needed
	if not is_player:
		dead_card.modulate = dead_card.modulate * Color(1.0, 0.6, 0.6, 1.0)  # Additional red tint for enemy
	
	return dead_card

func _restore_original_player_board() -> void:
	"""Restore the player board to its original state (before combat result view)"""
	var children_to_remove = []
	
	for child in main_layout.get_node("PlayerBoard").get_children():
		if child.name != "PlayerBoardLabel":
			# Remove result cards and dead minion cards
			if (child.name.begins_with("PlayerResult_") or 
				child.name.begins_with("PlayerDead_")):
				children_to_remove.append(child)
			else:
				# Show original minions that were hidden
				child.visible = true
				
				# Reset any color overrides that might have been applied
				var stats_label = child.get_node_or_null("VBoxContainer/BottomRow/StatsLabel")
				if stats_label:
					stats_label.remove_theme_color_override("font_color")
				
				# Reset modulation
				child.modulate = Color.WHITE
	
	# Remove result cards and tombstones
	for child in children_to_remove:
		child.queue_free()

# === HELPER FUNCTIONS ===

func pick_random_from_array(array: Array):
	"""Helper function to pick a random element from an array"""
	if array.is_empty():
		return null
	return array[randi() % array.size()] 