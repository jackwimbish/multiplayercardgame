# HostGameLogic.gd
# Singleton that handles all game logic on the host
# This ensures single source of truth - only the host can modify game state

extends Node

# Constants
const REFRESH_COST = 1
const MAX_HAND_SIZE = 10

func _ready():
    print("HostGameLogic singleton initialized")

func process_game_action(player_id: int, action: String, params: Dictionary) -> Dictionary:
    """
    Process any game action. Returns result dictionary:
    {
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
    
    # Execute refresh
    player.current_gold -= REFRESH_COST
    
    # Return old cards to pool (except frozen)
    GameState.return_cards_to_pool(player.shop_cards, player.frozen_card_ids)
    
    # Deal new cards
    var shop_size = GameState.get_shop_size_for_tier(player.shop_tier)
    GameState.deal_cards_to_shop(player_id, shop_size)
    
    # Clear frozen cards (manual refresh unfreezes all)
    player.frozen_card_ids.clear()
    
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
    
    # Update tavern upgrade cost
    if player.shop_tier < 6:
        player.current_tavern_upgrade_cost = max(0, player.current_tavern_upgrade_cost - 1)
    
    print("HostGameLogic: Player %d upgraded to tier %d for %d gold" % [player_id, player.shop_tier, upgrade_cost])
    
    # Auto-refresh shop after upgrade
    GameState.return_cards_to_pool(player.shop_cards, player.frozen_card_ids)
    var shop_size = GameState.get_shop_size_for_tier(player.shop_tier)
    GameState.deal_cards_to_shop(player_id, shop_size)
    
    return {
        "success": true,
        "state_changes": {player_id: true},
        "pool_changed": true
    }

func _process_sell(player_id: int, params: Dictionary) -> Dictionary:
    """Process minion sell request"""
    var card_id = params.get("card_id", "")
    var board_position = params.get("board_position", -1)
    
    var player = GameState.players[player_id]
    
    # Validate board position
    if board_position < 0 or board_position >= player.board_minions.size():
        return {"success": false, "error": "Invalid board position"}
    
    # Validate card matches position
    if player.board_minions[board_position] != card_id:
        return {"success": false, "error": "Card mismatch at board position"}
    
    # Only allow selling during shop phase
    if GameState.current_mode != GameState.GameMode.SHOP:
        return {"success": false, "error": "Can only sell during shop phase"}
    
    # Execute sell
    player.board_minions.remove_at(board_position)
    player.current_gold += 1  # All minions sell for 1 gold
    
    # Note: We don't return cards to pool when selling
    
    print("HostGameLogic: Player %d sold minion for 1 gold" % player_id)
    
    return {
        "success": true,
        "state_changes": {player_id: true}
    }

func advance_turn_for_all_players() -> Dictionary:
    """Called when combat ends and new turn begins"""
    print("HostGameLogic: Advancing turn for all players")
    
    # Update turn counter
    GameState.current_turn += 1
    
    # Update all player states
    var changed_players = {}
    
    for player_id in GameState.players:
        var player = GameState.players[player_id]
        
        # Skip eliminated players
        if GameState.is_player_eliminated(player_id):
            continue
        
        # Calculate new gold for turn
        var base_gold = GameState.calculate_base_gold_for_turn(GameState.current_turn)
        player.player_base_gold = base_gold
        player.current_gold = base_gold + player.bonus_gold
        
        # Return old cards to pool (except frozen)
        GameState.return_cards_to_pool(player.shop_cards, player.frozen_card_ids)
        
        # Deal new cards (preserves frozen cards)
        var shop_size = GameState.get_shop_size_for_tier(player.shop_tier)
        GameState.deal_cards_to_shop(player_id, shop_size)
        
        # Update tavern upgrade cost
        if player.shop_tier < 6 and player.current_tavern_upgrade_cost > 0:
            player.current_tavern_upgrade_cost -= 1
        
        changed_players[player_id] = true
    
    print("HostGameLogic: Turn %d started, all players updated" % GameState.current_turn)
    
    return {
        "success": true,
        "state_changes": changed_players,
        "pool_changed": true
    }