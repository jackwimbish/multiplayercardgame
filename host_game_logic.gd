# HostGameLogic.gd - Singleton that handles all game logic on the host
# This runs ONLY on the host/server and processes all game actions

extends Node

# Constants
const REFRESH_COST = 1
const MAX_HAND_SIZE = 10
const MAX_BOARD_SIZE = 7

func _ready():
    print("HostGameLogic: Initialized (only active on host)")

func process_game_action(player_id: int, action: String, params: Dictionary) -> Dictionary:
    """
    Main entry point for all game actions
    Returns: {
        "success": bool,
        "error": String (if failed),
        "state_changes": Dictionary (player states that changed),
        "pool_changed": bool (if card pool changed)
    }
    """
    
    # Validate player exists
    if not GameState.players.has(player_id):
        return {"success": false, "error": "Player not found"}
    
    # Check if player is eliminated
    if GameState.is_player_eliminated(player_id):
        return {"success": false, "error": "You have been eliminated"}
    
    # Process action based on type
    match action:
        "purchase_card":
            return _process_purchase(player_id, params)
        "refresh_shop":
            return _process_refresh(player_id, params)
        "toggle_freeze":
            return _process_freeze_toggle(player_id, params)
        "upgrade_shop":
            return _process_upgrade(player_id, params)
        "sell_minion":
            return _process_sell(player_id, params)
        "play_card":
            return _process_play_card(player_id, params)
        "reorder_board":
            return _process_reorder_board(player_id, params)
        _:
            return {"success": false, "error": "Unknown action: " + action}

func _process_purchase(player_id: int, params: Dictionary) -> Dictionary:
    """Process card purchase request"""
    var card_id = params.get("card_id", "")
    var shop_slot = params.get("shop_slot", -1)
    
    var player = GameState.players[player_id]
    
    # Validate shop slot
    if shop_slot < 0 or shop_slot >= player.shop_cards.size():
        return {"success": false, "error": "Invalid shop slot"}
    
    # Validate card matches slot
    if player.shop_cards[shop_slot] != card_id:
        return {"success": false, "error": "Card mismatch at shop slot"}
    
    # Get card data
    var card_data = CardDatabase.get_card_data(card_id)
    if card_data.is_empty():
        return {"success": false, "error": "Invalid card"}
    
    var cost = card_data.get("cost", 3)
    var card_name = card_data.get("name", "Unknown")
    
    # Validate gold
    if player.current_gold < cost:
        return {"success": false, "error": "Not enough gold (%d/%d)" % [player.current_gold, cost]}
    
    # Validate hand space
    if player.hand_cards.size() >= MAX_HAND_SIZE:
        return {"success": false, "error": "Hand is full"}
    
    # Validate card available in pool
    if GameState.shared_card_pool.get(card_id, 0) <= 0:
        return {"success": false, "error": "Card no longer available"}
    
    # Execute purchase
    player.current_gold -= cost
    player.hand_cards.append(card_id)
    player.shop_cards.remove_at(shop_slot)
    
    # Remove from pool
    GameState.shared_card_pool[card_id] -= 1
    
    print("HostGameLogic: Player %d purchased %s for %d gold" % [player_id, card_name, cost])
    
    return {
        "success": true,
        "state_changes": {player_id: true},
        "pool_changed": true
    }

func _process_refresh(player_id: int, params: Dictionary) -> Dictionary:
    """Process shop refresh request"""
    var player = GameState.players[player_id]
    
    # Validate gold
    if player.current_gold < REFRESH_COST:
        return {"success": false, "error": "Not enough gold (%d/%d)" % [player.current_gold, REFRESH_COST]}
    
    # Return current cards to pool (except frozen)
    GameState.return_cards_to_pool(player.shop_cards, player.frozen_card_ids)
    
    # Spend gold
    player.current_gold -= REFRESH_COST
    
    # Deal new cards
    var shop_size = GameState.get_shop_size_for_tier(player.shop_tier)
    GameState.deal_cards_to_shop(player_id, shop_size)
    
    print("HostGameLogic: Player %d refreshed shop for %d gold" % [player_id, REFRESH_COST])
    
    return {
        "success": true,
        "state_changes": {player_id: true},
        "pool_changed": true
    }

func _process_freeze_toggle(player_id: int, params: Dictionary) -> Dictionary:
    """Process freeze toggle request"""
    var player = GameState.players[player_id]
    
    # Check if all cards are currently frozen
    var all_frozen = true
    for card_id in player.shop_cards:
        if not card_id in player.frozen_card_ids:
            all_frozen = false
            break
    
    if all_frozen:
        # Unfreeze all
        player.frozen_card_ids.clear()
        print("HostGameLogic: Player %d unfroze all cards" % player_id)
    else:
        # Freeze all current shop cards
        player.frozen_card_ids = player.shop_cards.duplicate()
        print("HostGameLogic: Player %d froze all cards" % player_id)
    
    return {
        "success": true,
        "state_changes": {player_id: true}
    }

func _process_upgrade(player_id: int, params: Dictionary) -> Dictionary:
    """Process shop tier upgrade request"""
    var player = GameState.players[player_id]
    
    # Check if already max tier
    if player.shop_tier >= 6:
        return {"success": false, "error": "Already at maximum tier"}
    
    # Calculate upgrade cost
    var upgrade_cost = GameState.calculate_tavern_upgrade_cost_for_player(player)
    
    # Validate gold
    if player.current_gold < upgrade_cost:
        return {"success": false, "error": "Not enough gold (%d/%d)" % [player.current_gold, upgrade_cost]}
    
    # Execute upgrade
    player.current_gold -= upgrade_cost
    player.shop_tier += 1
    
    # Update tavern upgrade cost for next tier
    var next_tier = player.shop_tier + 1
    if next_tier <= 6:
        player.current_tavern_upgrade_cost = GameState.TAVERN_UPGRADE_BASE_COSTS.get(next_tier, 999)
    
    print("HostGameLogic: Player %d upgraded to tier %d for %d gold" % [player_id, player.shop_tier, upgrade_cost])
    
    return {
        "success": true,
        "state_changes": {player_id: true}
    }

func _process_sell(player_id: int, params: Dictionary) -> Dictionary:
    """Process minion sell request"""
    var card_id = params.get("card_id", "")
    var board_index = params.get("board_index", -1)
    
    var player = GameState.players[player_id]
    
    # Validate board index
    if board_index < 0 or board_index >= player.board_minions.size():
        return {"success": false, "error": "Invalid board index"}
    
    # Validate card matches position
    if player.board_minions[board_index] != card_id:
        return {"success": false, "error": "Card mismatch at board position"}
    
    # Get card data
    var card_data = CardDatabase.get_card_data(card_id)
    var card_name = card_data.get("name", "Unknown")
    
    # Execute sell
    player.board_minions.remove_at(board_index)
    player.current_gold += 1
    
    # Return card to pool
    GameState.add_card_to_pool(card_id)
    
    print("HostGameLogic: Player %d sold %s for 1 gold" % [player_id, card_name])
    
    return {
        "success": true,
        "state_changes": {player_id: true},
        "pool_changed": true
    }

func advance_turn_for_all_players() -> Dictionary:
    """Advance the turn and deal new shops for all players"""
    
    # Start new turn (updates gold)
    GameState.start_new_turn()
    
    var state_changes = {}
    var pool_changed = false
    
    # Deal new shops for each player
    for player_id in GameState.players.keys():
        var player = GameState.players[player_id]
        
        # Reset turn flags
        player.has_ended_turn = false
        player.is_ready_for_next_phase = false
        
        # Return old shop cards to pool (except frozen)
        GameState.return_cards_to_pool(player.shop_cards, player.frozen_card_ids)
        pool_changed = true
        
        # Deal new shop
        var shop_size = GameState.get_shop_size_for_tier(player.shop_tier)
        GameState.deal_cards_to_shop(player_id, shop_size)
        
        state_changes[player_id] = true
    
    print("HostGameLogic: Advanced to turn %d" % GameState.current_turn)
    
    return {
        "success": true,
        "state_changes": state_changes,
        "pool_changed": pool_changed
    }

func check_ready_for_combat() -> bool:
    """Check if all players are ready for combat phase"""
    for player in GameState.players.values():
        if not player.is_ready_for_next_phase:
            return false
    return true

func reset_combat_ready_flags():
    """Reset all players' combat ready flags"""
    for player in GameState.players.values():
        player.is_ready_for_next_phase = false

func _process_play_card(player_id: int, params: Dictionary) -> Dictionary:
    """Process playing a card from hand to board"""
    var card_id = params.get("card_id", "")
    var hand_index = params.get("hand_index", -1)
    var board_position = params.get("board_position", -1)
    
    var player = GameState.players[player_id]
    
    # If hand_index not provided, find the card
    if hand_index < 0:
        hand_index = player.hand_cards.find(card_id)
        if hand_index < 0:
            return {"success": false, "error": "Card not found in hand"}
    
    # Validate the card is in hand
    if hand_index >= player.hand_cards.size():
        return {"success": false, "error": "Invalid hand index"}
    
    if player.hand_cards[hand_index] != card_id:
        return {"success": false, "error": "Card mismatch at hand index"}
    
    # Validate it's a minion
    var card_data = CardDatabase.get_card_data(card_id)
    if card_data.get("type", "") != "minion":
        return {"success": false, "error": "Only minions can be played to board"}
    
    # Validate board space
    if player.board_minions.size() >= MAX_BOARD_SIZE:
        return {"success": false, "error": "Board is full"}
    
    # Remove from hand
    player.hand_cards.remove_at(hand_index)
    
    # Add to board at specified position
    if board_position < 0 or board_position > player.board_minions.size():
        # Add to end if position invalid
        player.board_minions.append(card_id)
    else:
        player.board_minions.insert(board_position, card_id)
    
    print("HostGameLogic: Player %d played %s to board" % [player_id, card_data.get("name", "Unknown")])
    
    return {
        "success": true,
        "state_changes": {player_id: true}
    }

func _process_reorder_board(player_id: int, params: Dictionary) -> Dictionary:
    """Process reordering minions on the board"""
    var new_board_order = params.get("board_minions", [])
    
    var player = GameState.players[player_id]
    
    # Validate the new order contains the same minions
    if new_board_order.size() != player.board_minions.size():
        return {"success": false, "error": "Board size mismatch"}
    
    # Simple validation - just check sizes match
    # Could do more thorough validation if needed
    
    player.board_minions = new_board_order
    
    print("HostGameLogic: Player %d reordered board" % player_id)
    
    return {
        "success": true,
        "state_changes": {player_id: true}
    }