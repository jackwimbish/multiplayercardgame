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

# Animation system
var animation_player: CombatAnimationPlayer
var skip_animations: bool = false

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
    
    # Initialize animation player
    animation_player = CombatAnimationPlayer.new()
    
    print("CombatManager initialized")
    
    # Connect to game mode changes for multiplayer sync
    if GameState:
        GameState.game_mode_changed.connect(_on_game_mode_changed)
    
    # Connect to combat signals in multiplayer
    if GameModeManager.is_in_multiplayer_session() and NetworkManager:
        NetworkManager.combat_started.connect(_on_multiplayer_combat_started)
        NetworkManager.combat_results_received.connect(_on_combat_results_received)
        NetworkManager.combat_results_received_v2.connect(_on_combat_results_received_v2)
        NetworkManager.combat_results_received_v3.connect(_on_combat_results_received_v3)

# === PUBLIC INTERFACE FOR GAME_BOARD ===

func start_combat(enemy_board_name: String) -> void:
    """Main entry point to start combat against an enemy board (practice mode)"""
    print("Starting combat against: %s" % enemy_board_name)
    current_enemy_board_name = enemy_board_name

func start_multiplayer_combat() -> void:
    """Start combat in multiplayer mode - uses real opponent boards"""
    if not NetworkManager or not NetworkManager.is_host:
        print("Only host can start multiplayer combat")
        return
    
    print("Starting multiplayer combat")
    
    # Get both players
    var player1 = GameState.get_host_player()
    var player2 = GameState.get_opponent_player()
    
    if not player1 or not player2:
        print("Error: Could not find both players for combat")
        return
    
    print("Player1 ID: ", player1.player_id, " Name: ", player1.player_name)
    print("Player1 board_minions: ", player1.board_minions)
    print("Player2 ID: ", player2.player_id, " Name: ", player2.player_name) 
    print("Player2 board_minions: ", player2.board_minions)
    
    # Check if either player is eliminated - auto-win for the living player
    var player1_eliminated = GameState.is_player_eliminated(player1.player_id)
    var player2_eliminated = GameState.is_player_eliminated(player2.player_id)
    
    if player1_eliminated or player2_eliminated:
        print("Auto-win detected - one player is eliminated")
        _handle_auto_win(player1, player2, player1_eliminated, player2_eliminated)
        return
    
    # Generate deterministic seed for combat
    var combat_seed = Time.get_ticks_msec()
    
    # Prepare shop state for combat phase (save frozen cards)
    if main_layout:
        var game_board = main_layout.get_parent()
        if game_board and game_board.has_method("prepare_shop_for_combat"):
            game_board.prepare_shop_for_combat()
    
    # Change phase to combat
    NetworkManager.change_game_phase(GameState.GameMode.COMBAT)
    
    # Broadcast combat start with both player boards
    NetworkManager.sync_combat_start.rpc(
        player1.player_id,
        player1.board_minions.duplicate(),
        player2.player_id,
        player2.board_minions.duplicate(),
        combat_seed
    )
    
    # Don't call switch_to_combat_mode here - let the phase change handle it
    # The combat display will be handled by _on_multiplayer_combat_started

func _handle_auto_win(player1: PlayerState, player2: PlayerState, player1_eliminated: bool, player2_eliminated: bool) -> void:
    """Handle auto-win when one player is eliminated"""
    var winner_id: int
    var loser_id: int
    var winner_name: String
    var loser_name: String
    
    if player1_eliminated:
        winner_id = player2.player_id
        loser_id = player1.player_id
        winner_name = player2.player_name
        loser_name = player1.player_name
    else:
        winner_id = player1.player_id
        loser_id = player2.player_id
        winner_name = player1.player_name
        loser_name = player2.player_name
    
    print("Auto-win: ", winner_name, " wins against eliminated ", loser_name)
    
    # Create a simple combat log showing auto-win
    var combat_log = [
        {"type": "combat_start", "player_minions": 0, "enemy_minions": 0},
        {"type": "auto_win", "winner": winner_name, "loser": loser_name, "reason": "opponent_eliminated"},
        {"type": "combat_end", "winner": winner_name, "reason": "auto_win"}
    ]
    
    # Change phase to combat to show results
    NetworkManager.change_game_phase(GameState.GameMode.COMBAT)
    
    # Broadcast auto-win results (no damage, just log)
    NetworkManager.sync_combat_results_v3.rpc(
        combat_log,
        player1.player_id,
        0,  # No damage to player1
        [],  # Empty board
        player2.player_id,
        0,  # No damage to player2
        []   # Empty board
    )

func return_to_shop() -> void:
    """Handle returning to shop mode after combat"""
    print("Returning to shop from combat")
    
    # Check if the local player is eliminated
    var is_eliminated = GameModeManager.is_in_multiplayer_session() and GameState.is_player_eliminated(GameState.local_player_id)
    
    # If eliminated but NOT the host, don't return to shop
    if is_eliminated and not NetworkManager.is_host:
        print("Player is eliminated - staying on defeat screen")
        return
    
    # If eliminated AND host, continue to advance the game for others
    if is_eliminated and NetworkManager.is_host:
        print("Host is eliminated but advancing game for other players")
    
    if GameModeManager.is_in_multiplayer_session():
        # In multiplayer, only host can advance turn and change phase
        if NetworkManager.is_host:
            print("Host advancing turn and returning to shop after combat")
            # Use the combined RPC to advance turn and change phase atomically
            NetworkManager.advance_turn_and_return_to_shop.rpc()
        else:
            # Clients just wait for the turn advancement and phase change from host
            print("Client waiting for host to advance turn and change phase")
    else:
        # Practice mode: advance turn directly then switch
        GameState.start_new_turn()
        
        # Auto-refresh shop for new turn (respecting freeze in Phase 2)
        if shop_manager:
            shop_manager.refresh_shop()
            print("Shop auto-refreshed for turn %d" % GameState.current_turn)
        
        # Now switch to shop mode
        switch_to_shop_mode()

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
        
        # Check if attacker died
        var attacker_died = attacker.current_health <= 0
        
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
        
        # Advance turn - only increment index if attacker didn't die
        # If attacker died, the array shifted left, so next attacker is at current index
        if not attacker_died:
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
    # Use NetworkManager for phase changes in multiplayer
    if NetworkManager and GameModeManager.is_in_multiplayer_session():
        print("CombatManager: Requesting phase change to COMBAT via NetworkManager (is_host: ", NetworkManager.is_host, ")")
        NetworkManager.change_game_phase(GameState.GameMode.COMBAT)
    else:
        print("CombatManager: Changing phase directly (practice mode)")
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
    # Use NetworkManager for phase changes in multiplayer
    if NetworkManager and GameModeManager.is_in_multiplayer_session():
        print("CombatManager: Requesting phase change to SHOP via NetworkManager (is_host: ", NetworkManager.is_host, ")")
        NetworkManager.change_game_phase(GameState.GameMode.SHOP)
    else:
        print("CombatManager: Changing phase directly (practice mode)")
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

func _restore_player_board_appearance() -> void:
    """Clear all combat visuals - board will be rebuilt from state"""
    var board_container = main_layout.get_node("PlayerBoard")
    var children_to_remove = []
    
    print("CombatManager: Clearing all board visuals for complete rebuild")
    
    # Remove ALL cards except the label - we'll rebuild from scratch
    for child in board_container.get_children():
        if child.name != "PlayerBoardLabel":
            children_to_remove.append(child)
    
    print("CombatManager: Removing ", children_to_remove.size(), " cards from board")
    for child in children_to_remove:
        board_container.remove_child(child)
        child.queue_free()

func _display_multiplayer_opponent_board(player1_id: int, player1_board: Array, player2_id: int, player2_board: Array) -> void:
    """Display the opponent's board in multiplayer combat"""
    # Determine which board is the opponent's
    var opponent_board: Array
    var opponent_name: String
    
    if player1_id == GameState.local_player_id:
        # We are player1, so show player2's board
        opponent_board = player2_board
        var opponent = GameState.players.get(player2_id)
        opponent_name = opponent.player_name if opponent else "Opponent"
    else:
        # We are player2, so show player1's board
        opponent_board = player1_board
        var opponent = GameState.players.get(player1_id)
        opponent_name = opponent.player_name if opponent else "Opponent"
    
    print("Displaying opponent board for ", opponent_name, " - Minions: ", opponent_board)
    
    # Update the shop area label
    main_layout.get_node("ShopArea/ShopAreaLabel").text = "%s's Board" % opponent_name
    main_layout.get_node("ShopArea/ShopAreaLabel").add_theme_color_override("font_color", Color.RED)
    
    # Clear any existing cards
    _clear_enemy_board_from_shop_area()
    
    # Create visual representations of opponent's minions
    for i in range(opponent_board.size()):
        var minion = opponent_board[i]
        var card_id = minion.get("card_id", "")
        var card_data = CardDatabase.get_card_data(card_id).duplicate()
        
        if card_data.is_empty():
            print("Warning: Could not find card data for ", card_id)
            continue
        
        # Override with current stats to show buffs
        card_data["attack"] = minion.get("current_attack", card_data.get("attack", 0))
        card_data["health"] = minion.get("current_health", card_data.get("health", 1))
        
        # Create enemy card using CardFactory
        var enemy_card = CardFactory.create_card(card_data, card_id)
        enemy_card.name = "EnemyMinion_%d" % i
        
        # Make enemy cards non-interactive
        enemy_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
        
        # Add visual indication this is an enemy
        enemy_card.modulate = Color(1.0, 0.8, 0.8)  # Slight red tint
        
        # Check if minion is buffed and apply green color
        var base_card = CardDatabase.get_card_data(card_id)
        var is_buffed = (minion.get("current_attack", 0) > base_card.get("attack", 0) or 
                         minion.get("current_health", 1) > base_card.get("health", 1))
        if is_buffed and enemy_card.has_node("VBoxContainer/BottomRow/StatsLabel"):
            enemy_card.get_node("VBoxContainer/BottomRow/StatsLabel").modulate = Color.GREEN
        
        main_layout.get_node("ShopArea").add_child(enemy_card)

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
    
    # Only show return to shop button for host in multiplayer
    if GameModeManager.is_in_multiplayer_session():
        ui_manager.return_to_shop_button.visible = GameState.is_host()
        if not GameState.is_host():
            # Add a label for non-host players
            var waiting_label = ui_manager.combat_ui_container.find_child("WaitingForHostLabel", false, false)
            if not waiting_label:
                waiting_label = Label.new()
                waiting_label.name = "WaitingForHostLabel"
                waiting_label.text = "Waiting for host to return to shop..."
                ui_manager.apply_font_to_label(waiting_label, ui_manager.UI_FONT_SIZE_MEDIUM)
                ui_manager.combat_ui_container.add_child(waiting_label)
            waiting_label.visible = true
    else:
        # Practice mode - always show button
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
    var is_multiplayer = GameModeManager.is_in_multiplayer_session()
    var is_host = GameState.is_host()
    
    if ui_manager.start_combat_button:
        # In multiplayer, only host can start combat
        ui_manager.start_combat_button.visible = not is_multiplayer or is_host
    
    if ui_manager.enemy_board_selector:
        # Completely hide enemy board selector in multiplayer
        ui_manager.enemy_board_selector.get_parent().visible = not is_multiplayer
    
    if ui_manager.combat_view_toggle_button:
        ui_manager.combat_view_toggle_button.visible = false
    
    if ui_manager.return_to_shop_button:
        ui_manager.return_to_shop_button.visible = false
    
    # Hide waiting label if it exists
    var waiting_label = ui_manager.combat_ui_container.find_child("WaitingForHostLabel", false, false)
    if waiting_label:
        waiting_label.visible = false
    
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
            # Handle both practice mode (player_minions/enemy_minions) and multiplayer (player1_minions/player2_minions)
            var p1_count = action.get("player_minions", action.get("player1_minions", 0))
            var p2_count = action.get("enemy_minions", action.get("player2_minions", 0))
            return "Combat begins! Player: %d minions vs Enemy: %d minions" % [p1_count, p2_count]
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

func _on_game_mode_changed(new_mode: GameState.GameMode) -> void:
    """Handle game mode changes from network sync"""
    print("CombatManager: Game mode changed to ", GameState.GameMode.keys()[new_mode])
    
    # If player is eliminated AND not the host, don't process mode changes
    var is_eliminated = GameModeManager.is_in_multiplayer_session() and GameState.is_player_eliminated(GameState.local_player_id)
    if is_eliminated and not NetworkManager.is_host:
        print("CombatManager: Player is eliminated and not host - ignoring mode change")
        return
    
    # Update UI based on new mode
    if new_mode == GameState.GameMode.COMBAT:
        # For non-host players, prepare shop state when transitioning to combat
        # (Host already does this in start_multiplayer_combat)
        if GameModeManager.is_in_multiplayer_session() and not NetworkManager.is_host:
            print("CombatManager: Non-host preparing shop for combat phase")
            if main_layout:
                var game_board = main_layout.get_parent()
                if game_board and game_board.has_method("prepare_shop_for_combat"):
                    game_board.prepare_shop_for_combat()
        
        # Hide shop elements
        _hide_shop_elements()
        
        # In multiplayer, the board display will be handled by _on_multiplayer_combat_started
        # In practice mode, show enemy board selector
        if not GameModeManager.is_in_multiplayer_session():
            if current_enemy_board_name == "":
                # Default to first enemy board if none selected
                current_enemy_board_name = "Tier 1 Basic"
            # Show enemy board in shop area
            _display_enemy_board_in_shop_area(current_enemy_board_name)
        
        # Update combat UI for combat mode
        _update_combat_ui_for_combat_mode()
        
        # Hide/minimize hand area
        _minimize_hand_area()
        
        mode_switched.emit("combat")
        
    elif new_mode == GameState.GameMode.SHOP:
        current_enemy_board_name = ""
        
        # Restore original shop area label
        var shop_area_label = main_layout.find_child("ShopAreaLabel", true, false)
        if shop_area_label:
            shop_area_label.text = "Shop"
        
        # Clear enemy cards from shop area BEFORE showing shop elements
        _clear_enemy_board_from_shop_area()
        
        # Restore normal appearance to all player board minions
        _restore_player_board_appearance()
        
        # Show shop elements
        _show_shop_elements()
        
        # Update combat UI for shop mode
        _update_combat_ui_for_shop_mode()
        
        # Restore hand area
        _show_hand_area()
        
        # Force a complete board refresh from state to fix any animation modifications
        # Always refresh the board when returning from combat to ensure correct display
        var local_player = GameState.get_local_player()
        if local_player and NetworkManager:
            print("CombatManager: Forcing board refresh after combat")
            print("CombatManager: Player board minions in state: ", local_player.board_minions)
            # The board was already cleared in _restore_player_board_appearance
            # Now recreate from state
            NetworkManager._update_board_display(local_player)
        
        # Update displays - turn has already advanced so values should be correct
        # Use call_deferred to ensure combat visualization cards are fully removed
        ui_manager.call_deferred("update_all_game_displays")
        
        # In multiplayer, force a shop refresh to ensure cards are displayed
        # Use call_deferred to ensure UI is ready
        if GameModeManager.is_in_multiplayer_session() and shop_manager:
            print("CombatManager: Scheduling shop refresh after returning from combat")
            if local_player:
                print("  Local player shop cards: ", local_player.shop_cards)
                if local_player.shop_cards.size() > 0:
                    # Defer the shop update to next frame to ensure UI is ready
                    shop_manager.call_deferred("_on_player_shop_changed", local_player.shop_cards)
                else:
                    print("  WARNING: Local player has no shop cards after turn advance!")
        
        mode_switched.emit("shop")

# === MULTIPLAYER COMBAT HANDLERS ===

func _on_multiplayer_combat_started(combat_data: Dictionary) -> void:
    """Handle combat start signal from NetworkManager"""
    print("Multiplayer combat started signal received")
    
    # Extract combat data
    var player1_id = combat_data.get("player1_id")
    var player1_board = combat_data.get("player1_board", [])
    var player2_id = combat_data.get("player2_id") 
    var player2_board = combat_data.get("player2_board", [])
    var random_seed = combat_data.get("random_seed", 0)
    
    # Display opponent's board
    _display_multiplayer_opponent_board(player1_id, player1_board, player2_id, player2_board)
    
    # Set up RNG with the seed
    var rng = RandomNumberGenerator.new()
    rng.seed = random_seed
    
    # Run combat simulation if we're the host
    if NetworkManager.is_host:
        print("Host running combat simulation")
        _run_multiplayer_combat_simulation(player1_id, player1_board, player2_id, player2_board, rng)

func _run_multiplayer_combat_simulation(player1_id: int, player1_board: Array, player2_id: int, player2_board: Array, rng: RandomNumberGenerator) -> void:
    """Run the combat simulation on the host and broadcast results"""
    
    # Get player names
    var player1_name = GameState.players[player1_id].player_name if GameState.players.has(player1_id) else "Player 1"
    var player2_name = GameState.players[player2_id].player_name if GameState.players.has(player2_id) else "Player 2"
    
    # Run combat with player boards
    var combat_result = _simulate_multiplayer_combat(player1_board, player2_board, player1_name, player2_name, rng)
    var combat_log = combat_result["log"]
    var player1_final = combat_result["player1_final"]
    var player2_final = combat_result["player2_final"]
    
    # Determine damage based on combat results
    var player1_damage = 0
    var player2_damage = 0
    
    # Check the last action in the log for winner
    for action in combat_log:
        if action.get("type") == "combat_end":
            var winner = action.get("winner", "")
            if winner == "player1":
                player2_damage = DEFAULT_COMBAT_DAMAGE
            elif winner == "player2":
                player1_damage = DEFAULT_COMBAT_DAMAGE
            # If it's a tie, no damage
    
    print("Combat simulation complete - Player1 (", player1_name, ") takes ", player1_damage, " damage, Player2 (", player2_name, ") takes ", player2_damage, " damage")
    
    # Broadcast results with explicit player IDs and final board states
    NetworkManager.sync_combat_results_v3.rpc(
        combat_log, 
        player1_id, player1_damage, player1_final,
        player2_id, player2_damage, player2_final
    )

func _simulate_multiplayer_combat(player1_board: Array, player2_board: Array, player1_name: String, player2_name: String, rng: RandomNumberGenerator) -> Dictionary:
    """Simulate combat between two player boards with deterministic RNG"""
    var action_log = []
    
    # Add turn indicator at the start
    action_log.append({
        "type": "turn_start",
        "turn": GameState.current_turn
    })
    
    action_log.append({
        "type": "combat_start", 
        "player1_minions": player1_board.size(),
        "player2_minions": player2_board.size()
    })
    
    # Check for immediate win conditions (empty armies)
    if player1_board.is_empty() and player2_board.is_empty():
        action_log.append({"type": "combat_tie", "reason": "both_no_minions"})
        return {"log": action_log, "player1_final": [], "player2_final": []}
    elif player1_board.is_empty():
        action_log.append({"type": "combat_end", "winner": "player2", "reason": "player1_no_minions"})
        return {"log": action_log, "player1_final": [], "player2_final": _create_final_state(player2_board)}
    elif player2_board.is_empty():
        action_log.append({"type": "combat_end", "winner": "player1", "reason": "player2_no_minions"})
        return {"log": action_log, "player1_final": _create_final_state(player1_board), "player2_final": []}
    
    # Create minion instances from card IDs
    var player1_minions = []
    var player2_minions = []
    
    # Track original counts for final display
    var original_p1_count = player1_board.size()
    var original_p2_count = player2_board.size()
    
    for i in range(player1_board.size()):
        var minion = player1_board[i]
        var card_id = minion.get("card_id", "")
        var card_data = CardDatabase.get_card_data(card_id)
        player1_minions.append({
            "id": card_id,
            "unique_id": "p1_" + str(i),  # Unique identifier for this combat
            "position": i,
            "attack": minion.get("current_attack", card_data.get("attack", 1)),
            "health": minion.get("current_health", card_data.get("health", 1)),
            "max_health": minion.get("current_health", card_data.get("health", 1)),
            "owner": player1_name,
            "is_dead": false  # Track death state instead of removing
        })
    
    for i in range(player2_board.size()):
        var minion = player2_board[i]
        var card_id = minion.get("card_id", "")
        var card_data = CardDatabase.get_card_data(card_id)
        player2_minions.append({
            "id": card_id,
            "unique_id": "p2_" + str(i),  # Unique identifier for this combat
            "position": i,
            "attack": minion.get("current_attack", card_data.get("attack", 1)),
            "health": minion.get("current_health", card_data.get("health", 1)),
            "max_health": minion.get("current_health", card_data.get("health", 1)),
            "owner": player2_name,
            "is_dead": false  # Track death state instead of removing
        })
    
    # Determine who goes first
    var p1_turn: bool
    if player1_minions.size() > player2_minions.size():
        p1_turn = true
        action_log.append({"type": "first_attacker", "attacker": "player1", "reason": "more_minions"})
    elif player2_minions.size() > player1_minions.size():
        p1_turn = false
        action_log.append({"type": "first_attacker", "attacker": "player2", "reason": "more_minions"})
    else:
        p1_turn = rng.randf() < 0.5
        action_log.append({"type": "first_attacker", "attacker": "player1" if p1_turn else "player2", "reason": "random_equal_minions"})
    
    # Combat loop
    var max_attacks = 20
    var attack_count = 0
    var p1_attacker_index = 0
    var p2_attacker_index = 0
    
    # Helper function to check if any minions are alive
    var has_living_p1 = func(): 
        for m in player1_minions:
            if not m.is_dead:
                return true
        return false
    
    var has_living_p2 = func():
        for m in player2_minions:
            if not m.is_dead:
                return true
        return false
    
    # Helper function to get living defenders
    var get_living_defenders = func(minion_list: Array) -> Array:
        var living = []
        for m in minion_list:
            if not m.is_dead:
                living.append(m)
        return living
    
    while has_living_p1.call() and has_living_p2.call() and attack_count < max_attacks:
        var attacker = null
        var defender_list
        
        if p1_turn:
            # Find next living attacker for player 1
            while p1_attacker_index < player1_minions.size():
                if not player1_minions[p1_attacker_index].is_dead:
                    attacker = player1_minions[p1_attacker_index]
                    break
                p1_attacker_index += 1
            
            # If we've gone through all minions, wrap around
            if attacker == null:
                p1_attacker_index = 0
                while p1_attacker_index < player1_minions.size():
                    if not player1_minions[p1_attacker_index].is_dead:
                        attacker = player1_minions[p1_attacker_index]
                        break
                    p1_attacker_index += 1
            
            defender_list = get_living_defenders.call(player2_minions)
        else:
            # Find next living attacker for player 2
            while p2_attacker_index < player2_minions.size():
                if not player2_minions[p2_attacker_index].is_dead:
                    attacker = player2_minions[p2_attacker_index]
                    break
                p2_attacker_index += 1
            
            # If we've gone through all minions, wrap around
            if attacker == null:
                p2_attacker_index = 0
                while p2_attacker_index < player2_minions.size():
                    if not player2_minions[p2_attacker_index].is_dead:
                        attacker = player2_minions[p2_attacker_index]
                        break
                    p2_attacker_index += 1
            
            defender_list = get_living_defenders.call(player1_minions)
        
        # This shouldn't happen if our has_living checks work correctly
        if attacker == null or defender_list.is_empty():
            print("Combat error: No attacker or defenders found")
            break
        
        # Choose random defender from living defenders
        var defender = defender_list[rng.randi() % defender_list.size()]
        
        # Log attack with unique IDs and display names
        action_log.append({
            "type": "attack",
            "attacker_unique_id": attacker.unique_id,
            "defender_unique_id": defender.unique_id,
            "attacker_id": attacker.owner + "'s " + CardDatabase.get_card_data(attacker.id).get("name", "Unknown") + " (pos " + str(attacker.position) + ")",
            "defender_id": defender.owner + "'s " + CardDatabase.get_card_data(defender.id).get("name", "Unknown") + " (pos " + str(defender.position) + ")",
            "attacker_attack": attacker.attack,
            "attacker_health": attacker.health,
            "defender_attack": defender.attack,
            "defender_health": defender.health
        })
        
        # Apply damage
        attacker.health -= defender.attack
        defender.health -= attacker.attack
        
        # Mark deaths but don't remove from arrays
        if attacker.health <= 0 and not attacker.is_dead:
            action_log.append({"type": "death", "target_id": attacker.owner + "'s " + CardDatabase.get_card_data(attacker.id).get("name", "Unknown")})
            attacker.is_dead = true
        
        if defender.health <= 0 and not defender.is_dead:
            action_log.append({"type": "death", "target_id": defender.owner + "'s " + CardDatabase.get_card_data(defender.id).get("name", "Unknown")})
            defender.is_dead = true
        
        # Always advance attacker index
        if p1_turn:
            p1_attacker_index += 1
        else:
            p2_attacker_index += 1
        
        # Switch turns
        p1_turn = not p1_turn
        attack_count += 1
    
    # Determine winner based on living minions
    var p1_alive = has_living_p1.call()
    var p2_alive = has_living_p2.call()
    
    if not p1_alive and not p2_alive:
        action_log.append({"type": "combat_tie", "reason": "both_died"})
    elif not p1_alive:
        action_log.append({"type": "combat_end", "winner": "player2"})
    elif not p2_alive:
        action_log.append({"type": "combat_end", "winner": "player1"})
    else:
        action_log.append({"type": "combat_tie", "reason": "max_attacks_reached"})
    
    # Create final states for all positions (including dead minions)
    var player1_final = []
    var player2_final = []
    
    # Build final states with all original positions
    for i in range(original_p1_count):
        var found = false
        for minion in player1_minions:
            if minion.position == i:
                player1_final.append({
                    "card_id": minion.id,
                    "position": i,
                    "health": minion.health,
                    "max_health": minion.max_health,
                    "attack": minion.attack
                })
                found = true
                break
        if not found:
            # This position had a minion that died
            var minion = player1_board[i]
            var card_id = minion.get("card_id", "")
            var card_data = CardDatabase.get_card_data(card_id)
            player1_final.append({
                "card_id": card_id,
                "position": i,
                "health": 0,
                "max_health": minion.get("current_health", card_data.get("health", 1)),
                "attack": minion.get("current_attack", card_data.get("attack", 1))
            })
    
    # Same for player 2
    for i in range(original_p2_count):
        var found = false
        for minion in player2_minions:
            if minion.position == i:
                player2_final.append({
                    "card_id": minion.id,
                    "position": i,
                    "health": minion.health,
                    "max_health": minion.max_health,
                    "attack": minion.attack
                })
                found = true
                break
        if not found:
            # This position had a minion that died
            var minion = player2_board[i]
            var card_id = minion.get("card_id", "")
            var card_data = CardDatabase.get_card_data(card_id)
            player2_final.append({
                "card_id": card_id,
                "position": i,
                "health": 0,
                "max_health": minion.get("current_health", card_data.get("health", 1)),
                "attack": minion.get("current_attack", card_data.get("attack", 1))
            })
    
    return {"log": action_log, "player1_final": player1_final, "player2_final": player2_final}

func _on_combat_animations_complete() -> void:
    """Called when combat animations are complete"""
    print("Combat animations complete")
    # Final boards are already displayed by animation system
    # Just ensure UI is updated
    ui_manager.update_health_displays()
    
    # When animations complete, we need to ensure the board is refreshed when returning to shop
    # The actual refresh will happen in _on_game_mode_changed when switching to SHOP mode

func skip_all_combat_animations() -> void:
    """Skip all combat animations and show final state immediately"""
    skip_animations = true
    if animation_player and animation_player.is_playing:
        animation_player.skip_combat()

func _create_final_state(board: Array) -> Array:
    """Create final state for a board with no combat (all minions at full health)"""
    var final_state = []
    for i in range(board.size()):
        var minion = board[i]
        var card_id = minion.get("card_id", "")
        var card_data = CardDatabase.get_card_data(card_id)
        final_state.append({
            "card_id": card_id,
            "position": i,
            "health": minion.get("current_health", card_data.get("health", 1)),
            "max_health": minion.get("current_health", card_data.get("health", 1)),
            "attack": minion.get("current_attack", card_data.get("attack", 1))
        })
    return final_state

func _on_combat_results_received(combat_log: Array, player1_damage: int, player2_damage: int) -> void:
    """Handle combat results broadcast from host"""
    print("Combat results received - P1 damage: ", player1_damage, ", P2 damage: ", player2_damage)
    
    # Display the combat log
    _show_multiplayer_combat_log(combat_log)
    
    # Apply damage is already done in NetworkManager, just update UI
    ui_manager.update_health_displays()

func _show_multiplayer_combat_log(combat_log: Array) -> void:
    """Display the multiplayer combat log"""
    var formatted_log = "[b][color=yellow]Turn %d Combat Results[/color][/b]\n\n" % GameState.current_turn
    
    for action in combat_log:
        formatted_log += format_combat_action(action) + "\n"
    
    # Add damage summary
    formatted_log += "\n[b][color=cyan]Combat Complete![/color][/b]\n"
    
    # Show in combat log display
    if ui_manager.combat_log_display:
        ui_manager.combat_log_display.clear()
        ui_manager.combat_log_display.append_text(formatted_log)
        ui_manager.combat_log_display.visible = true

func _on_combat_results_received_v2(combat_log: Array, player1_id: int, player1_damage: int, player2_id: int, player2_damage: int, final_states: Dictionary) -> void:
    """Handle combat results with final board states for visualization"""
    print("Combat results v2 received - P1 (", player1_id, ") damage: ", player1_damage, ", P2 (", player2_id, ") damage: ", player2_damage)
    
    # Display the combat log
    _show_multiplayer_combat_log(combat_log)
    
    # Update health displays
    ui_manager.update_health_displays()
    
    # Display the final board states
    _display_multiplayer_final_boards(final_states)

func _on_combat_results_received_v3(combat_log: Array, player1_id: int, player1_damage: int, player1_final: Array, player2_id: int, player2_damage: int, player2_final: Array) -> void:
    """Handle combat results with animations"""
    print("Combat results v3 received - Starting combat animations")
    print("Player1 final: ", player1_final)
    print("Player2 final: ", player2_final)
    print("Combat log size: ", combat_log.size())
    
    # Reset skip flag in case it was left on from previous combat
    skip_animations = false
    
    # Display the combat log text first
    _show_multiplayer_combat_log(combat_log)
    
    # Setup animation player
    var player_board = main_layout.get_node("PlayerBoard")
    var enemy_board = main_layout.get_node("ShopArea")
    animation_player.setup(player_board, enemy_board, ui_manager)
    
    # Connect sound signals (optional - for future use)
    # animation_player.sound_combat_start.connect(_play_combat_start_sound)
    # animation_player.sound_attack_impact.connect(_play_attack_sound)
    # animation_player.sound_minion_death.connect(_play_death_sound)
    # animation_player.sound_combat_end.connect(_play_combat_end_sound)
    
    # We need to get the initial board states for animation
    # The final states have dead minions with 0 health which breaks the animation
    # Get the board states from our stored combat data or reconstruct from final states
    var our_initial: Array = []
    var opponent_initial: Array = []
    
    # Reconstruct initial states from final states (all minions start at full health)
    if player1_id == GameState.local_player_id:
        for i in range(player1_final.size()):
            var minion = player1_final[i]
            our_initial.append({
                "card_id": minion.get("card_id", ""),
                "current_attack": minion.get("attack", 1),
                "current_health": minion.get("max_health", 1),  # Use max_health for initial state
                "unique_id": "p1_" + str(i)  # Consistent with combat simulation
            })
        for i in range(player2_final.size()):
            var minion = player2_final[i]
            opponent_initial.append({
                "card_id": minion.get("card_id", ""),
                "current_attack": minion.get("attack", 1),
                "current_health": minion.get("max_health", 1),  # Use max_health for initial state
                "unique_id": "p2_" + str(i)  # Consistent with combat simulation
            })
    else:
        for i in range(player2_final.size()):
            var minion = player2_final[i]
            our_initial.append({
                "card_id": minion.get("card_id", ""),
                "current_attack": minion.get("attack", 1),
                "current_health": minion.get("max_health", 1),  # Use max_health for initial state
                "unique_id": "p2_" + str(i)  # Consistent with combat simulation
            })
        for i in range(player1_final.size()):
            var minion = player1_final[i]
            opponent_initial.append({
                "card_id": minion.get("card_id", ""),
                "current_attack": minion.get("attack", 1),
                "current_health": minion.get("max_health", 1),  # Use max_health for initial state
                "unique_id": "p1_" + str(i)  # Consistent with combat simulation
            })
    
    # Start animations with initial states
    if not skip_animations:
        animation_player.play_combat_animation(combat_log, our_initial, opponent_initial)
    else:
        # Skip directly to final state
        _on_combat_animations_complete()
        # Reset skip flag for next combat
        skip_animations = false
        
    # Update health displays will happen after animations complete
    ui_manager.update_health_displays()

func _display_multiplayer_final_boards(final_states: Dictionary) -> void:
    """Display final board states for both players after multiplayer combat"""
    var player1_id = final_states.get("player1_id")
    var player1_final = final_states.get("player1_final", [])
    var player2_id = final_states.get("player2_id") 
    var player2_final = final_states.get("player2_final", [])
    
    # Determine which board is ours and which is the opponent's
    var our_final: Array
    var opponent_final: Array
    var opponent_name: String
    
    if player1_id == GameState.local_player_id:
        our_final = player1_final
        opponent_final = player2_final
        var opponent = GameState.players.get(player2_id)
        opponent_name = opponent.player_name if opponent else "Opponent"
    else:
        our_final = player2_final
        opponent_final = player1_final
        var opponent = GameState.players.get(player1_id)
        opponent_name = opponent.player_name if opponent else "Opponent"
    
    # Display our board in PlayerBoard area
    _display_final_player_board_multiplayer(our_final)
    
    # Display opponent's board in ShopArea
    _display_final_opponent_board_multiplayer(opponent_final, opponent_name)

func _display_final_player_board_multiplayer(final_minions: Array) -> void:
    """Display our final board state with damaged/dead minions"""
    # Hide original minions
    for child in main_layout.get_node("PlayerBoard").get_children():
        if child.name != "PlayerBoardLabel":
            child.visible = false
    
    # Show final state for each position
    for minion_state in final_minions:
        var result_card = _create_multiplayer_result_card(minion_state, true)
        main_layout.get_node("PlayerBoard").add_child(result_card)

func _display_final_opponent_board_multiplayer(final_minions: Array, opponent_name: String) -> void:
    """Display opponent's final board state with damaged/dead minions"""
    # Update shop area label
    main_layout.get_node("ShopArea/ShopAreaLabel").text = "%s's Final Board State" % opponent_name
    main_layout.get_node("ShopArea/ShopAreaLabel").add_theme_color_override("font_color", Color.RED)
    
    # Clear any existing cards
    _clear_enemy_board_from_shop_area()
    
    # Show final state for each position
    for minion_state in final_minions:
        var result_card = _create_multiplayer_result_card(minion_state, false)
        main_layout.get_node("ShopArea").add_child(result_card)

func _create_multiplayer_result_card(minion_state: Dictionary, is_player: bool) -> Control:
    """Create a card showing the final state of a minion"""
    var card_id = minion_state.get("card_id", "")
    var position = minion_state.get("position", 0)
    var health = minion_state.get("health", 0)
    var max_health = minion_state.get("max_health", 1)
    var attack = minion_state.get("attack", 1)
    
    # Get base card data
    var card_data = CardDatabase.get_card_data(card_id).duplicate()
    if card_data.is_empty():
        print("Warning: Could not find card data for ", card_id)
        return Control.new()
    
    # Update stats to show final combat state
    card_data["attack"] = attack
    card_data["health"] = health
    
    # Create card visual
    var result_card = CardFactory.create_card(card_data, card_id)
    var owner_prefix = "Player" if is_player else "Enemy"
    result_card.name = "%sResult_%d" % [owner_prefix, position]
    
    # Make card non-interactive
    result_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
    
    # Apply visual state based on health
    if health <= 0:
        # Dead minion - grey with red health
        result_card.modulate = Color(0.4, 0.4, 0.4, 0.8)
        # Make health text red
        var stats_label = result_card.get_node_or_null("VBoxContainer/BottomRow/StatsLabel")
        if stats_label:
            stats_label.add_theme_color_override("font_color", Color.RED)
    elif health < max_health:
        # Damaged minion - yellow/orange tint
        result_card.modulate = Color(1.0, 0.8, 0.4, 1.0)
    else:
        # Undamaged minion - normal appearance
        result_card.modulate = Color.WHITE
    
    # Add enemy tint if not player's card
    if not is_player:
        result_card.modulate = result_card.modulate * Color(1.0, 0.85, 0.85, 1.0)
    
    return result_card
