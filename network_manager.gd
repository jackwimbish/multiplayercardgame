# NetworkManager.gd (Autoload Singleton)
# Manages all multiplayer networking functionality

extends Node

# Network configuration
const DEFAULT_PORT = 9999
const MAX_PLAYERS = 2  # For 1v1 games
const CONNECTION_TIMEOUT = 10.0  # seconds

# Network state
var is_host: bool = false
var is_connected: bool = false
var server_port: int = DEFAULT_PORT
var connected_players: Dictionary = {}  # peer_id -> PlayerState
var local_player_id: int = 0

# Network events
signal player_joined(player_id: int, player_name: String)
signal player_left(player_id: int, player_name: String)
signal player_ready_changed(player_id: int, is_ready: bool)
signal connection_failed(reason: String)
signal connection_lost()
signal game_start_requested()
signal network_error(message: String)

# Combat events
signal combat_started(combat_data: Dictionary)
signal combat_results_received(combat_log: Array, player1_damage: int, player2_damage: int)

func _ready():
    print("NetworkManager initialized")
    # Connect multiplayer signals
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)
    multiplayer.connection_failed.connect(_on_connection_failed)
    multiplayer.server_disconnected.connect(_on_server_disconnected)

# === HOST FUNCTIONS ===

func create_host_game(port: int = DEFAULT_PORT) -> bool:
    """Create a host game on the specified port"""
    print("NetworkManager: Creating host game on port ", port)
    
    # Create server peer
    var peer = ENetMultiplayerPeer.new()
    var error = peer.create_server(port, MAX_PLAYERS)
    
    if error != OK:
        print("NetworkManager: Failed to create server - Error: ", error)
        var error_message = "Failed to create server on port %d. Port may be in use." % port
        network_error.emit(error_message)
        return false
    
    # Set the multiplayer peer
    multiplayer.multiplayer_peer = peer
    
    # Set network state
    is_host = true
    is_connected = true
    server_port = port
    local_player_id = multiplayer.get_unique_id()  # Get actual peer ID
    
    print("NetworkManager: Host created - local_player_id: ", local_player_id, ", is_host: ", is_host)
    
    # Add host to connected players
    var host_player = PlayerState.new()
    host_player.player_id = local_player_id
    host_player.player_name = GameModeManager.get_network_player_name()
    host_player.is_ready = false
    host_player.is_host = true
    connected_players[local_player_id] = host_player
    
    print("NetworkManager: Host game created successfully on port ", port)
    player_joined.emit(local_player_id, host_player.player_name)
    return true

func close_host_game():
    """Close the host game and disconnect all players"""
    print("NetworkManager: Closing host game")
    
    if multiplayer.multiplayer_peer:
        multiplayer.multiplayer_peer.close()
        multiplayer.multiplayer_peer = null
    
    _reset_network_state()

# === CLIENT FUNCTIONS ===

func join_game(ip_address: String, port: int = DEFAULT_PORT) -> bool:
    """Join a game at the specified IP and port"""
    print("NetworkManager: Joining game at ", ip_address, ":", port)
    
    # Validate IP address format
    if not _is_valid_ip(ip_address):
        var error_message = "Invalid IP address format: %s" % ip_address
        network_error.emit(error_message)
        return false
    
    # Create client peer
    var peer = ENetMultiplayerPeer.new()
    var error = peer.create_client(ip_address, port)
    
    if error != OK:
        print("NetworkManager: Failed to create client - Error: ", error)
        var error_message = "Failed to connect to %s:%d" % [ip_address, port]
        network_error.emit(error_message)
        return false
    
    # Set the multiplayer peer
    multiplayer.multiplayer_peer = peer
    
    # Set network state
    is_host = false
    is_connected = false  # Will be set to true when connection succeeds
    server_port = port
    local_player_id = 0  # Will be assigned by server
    
    print("NetworkManager: Attempting to connect to ", ip_address, ":", port)
    return true

func disconnect_from_game():
    """Disconnect from the current game"""
    print("NetworkManager: Disconnecting from game")
    
    if multiplayer.multiplayer_peer:
        multiplayer.multiplayer_peer.close()
        multiplayer.multiplayer_peer = null
    
    _reset_network_state()

# === PLAYER MANAGEMENT ===

@rpc("any_peer", "call_remote", "reliable")
func update_player_info(player_id: int, player_name: String):
    """Update player information across the network"""
    print("NetworkManager: Updating player info - ID: ", player_id, " Name: ", player_name)
    
    if not connected_players.has(player_id):
        var new_player = PlayerState.new()
        new_player.player_id = player_id
        new_player.is_host = (player_id == 1)
        new_player.is_ready = false
        connected_players[player_id] = new_player
        
        # Emit player joined signal for new players
        player_joined.emit(player_id, player_name)
    
    # Update player name
    connected_players[player_id].player_name = player_name

@rpc("any_peer", "call_remote", "reliable")
func update_player_ready_state(player_id: int, is_ready: bool):
    """Update player ready state across the network"""
    print("NetworkManager: Player ", player_id, " ready state: ", is_ready)
    
    if connected_players.has(player_id):
        connected_players[player_id].is_ready = is_ready
        player_ready_changed.emit(player_id, is_ready)

@rpc("any_peer", "call_remote", "reliable")
func request_game_start():
    """Host requests game start (sent to all players)"""
    print("NetworkManager: Game start requested")
    game_start_requested.emit()

# === GAME ACTION RPCS ===

@rpc("any_peer", "call_remote", "reliable")
func request_purchase_card(player_id: int, card_id: String, shop_slot: int):
    """Request to purchase a card from shop"""
    print("NetworkManager: Purchase request - Player: ", player_id, " Card: ", card_id)
    
    # Only server validates purchases
    if is_host:
        var success = validate_and_execute_purchase(player_id, card_id, shop_slot)
        sync_player_state.rpc(player_id, GameState.players[player_id].to_dict())
        
        if success:
            # Sync shared card pool state to all players
            sync_card_pool.rpc(GameState.shared_card_pool)

@rpc("any_peer", "call_remote", "reliable") 
func request_refresh_shop(player_id: int):
    """Request to refresh player's shop"""
    var sender_id = multiplayer.get_remote_sender_id()
    var my_id = multiplayer.get_unique_id()
    print("NetworkManager: Refresh shop request - Player: ", player_id, ", Sender: ", sender_id, ", My ID: ", my_id, ", is_host: ", is_host)
    
    # Only process on the server/host - use is_host instead of multiplayer.is_server()
    # because multiplayer.is_server() returns false in RPC context
    if is_host:
        print("NetworkManager: Server executing refresh for player ", player_id)
        validate_and_execute_refresh(player_id)
        print("NetworkManager: About to sync player state for player ", player_id)
        sync_player_state.rpc(player_id, GameState.players[player_id].to_dict())
        sync_card_pool.rpc(GameState.shared_card_pool)
    else:
        print("NetworkManager: Client received refresh request - ignoring (should not happen with proper RPC setup)")

@rpc("any_peer", "call_remote", "reliable")
func request_upgrade_shop(player_id: int):
    """Request to upgrade player's shop tier"""
    print("NetworkManager: Upgrade shop request - Player: ", player_id)
    
    if is_host:
        validate_and_execute_upgrade(player_id)
        sync_player_state.rpc(player_id, GameState.players[player_id].to_dict())

@rpc("any_peer", "call_local", "reliable")
func request_sell_minion(player_id: int, card_id: String):
    """Request to sell a minion back to the pool"""
    print("NetworkManager: Sell minion request - Player: ", player_id, " Card: ", card_id)
    
    if is_host:
        validate_and_execute_sell(player_id, card_id)
        sync_player_state.rpc(player_id, GameState.players[player_id].to_dict())
        sync_card_pool.rpc(GameState.shared_card_pool)

@rpc("any_peer", "call_local", "reliable")
func request_end_turn(player_id: int):
    """Request to end turn for a player"""
    print("NetworkManager: End turn request - Player: ", player_id)
    
    if is_host:
        validate_and_execute_end_turn(player_id)
        # Check if both players have ended turn
        if _all_players_ended_turn():
            advance_turn.rpc()

@rpc("any_peer", "call_local", "reliable")
func update_board_state(player_id: int, board_minions: Array):
    """Update a player's board state when minions are played/sold/reordered"""
    print("NetworkManager: Board state update - Player: ", player_id, " Minions: ", board_minions)
    
    # Only host processes board updates
    if is_host:
        if GameState.players.has(player_id):
            var player = GameState.players[player_id]
            player.board_minions = board_minions
            # Sync the updated state to all clients
            sync_player_state.rpc(player_id, player.to_dict())
        else:
            print("NetworkManager: Player ", player_id, " not found for board update")

# === PHASE CONTROL RPCS (HOST ONLY) ===

@rpc("any_peer", "call_remote", "reliable")
func request_phase_change(new_phase: GameState.GameMode):
    """Request a phase change - only host can execute this"""
    var sender_id = multiplayer.get_remote_sender_id()
    print("NetworkManager: Phase change requested to ", GameState.GameMode.keys()[new_phase], " from peer ", sender_id)
    
    # Only server can change phases
    if is_host:
        print("NetworkManager: Server processing phase change request")
        # Broadcast phase change to all players (including host)
        sync_phase_change.rpc(new_phase)
    else:
        print("NetworkManager: Client received phase change request - ignoring")

@rpc("authority", "call_local", "reliable")
func sync_phase_change(new_phase: GameState.GameMode):
    """Sync phase change across all clients (host authority)"""
    print("NetworkManager: Syncing phase change to ", GameState.GameMode.keys()[new_phase])
    
    # Update the game state mode
    GameState.current_mode = new_phase
    
    # Emit signal so UI can update accordingly
    GameState.game_mode_changed.emit(new_phase)

# === STATE SYNCHRONIZATION RPCS ===

@rpc("authority", "call_local", "reliable")
func sync_player_state(player_id: int, player_data: Dictionary):
    """Sync a player's state across all clients"""
    print("NetworkManager: Syncing player state for player ", player_id, " to peer ", multiplayer.get_unique_id())
    
    if GameState.players.has(player_id):
        var player = GameState.players[player_id]
        var old_shop = player.shop_cards.duplicate()
        var old_gold = player.current_gold
        player.from_dict(player_data)
        print("NetworkManager: Updated player ", player_id, " shop from ", old_shop, " to ", player.shop_cards)
        print("NetworkManager: Updated player ", player_id, " gold from ", old_gold, " to ", player.current_gold)
        
        # If this is the local player, force UI update for gold and shop tier
        # This ensures the display updates even if the signal connection isn't working
        if player_id == local_player_id:
            var game_board = get_tree().get_first_node_in_group("game_board")
            if game_board and game_board.ui_manager:
                if old_gold != player.current_gold:
                    print("NetworkManager: Local player gold changed, forcing UI update")
                    game_board.ui_manager.update_gold_display_detailed()
                # Also update shop tier display in case upgrade cost changed
                game_board.ui_manager.update_shop_tier_display_detailed()
    else:
        # Create new player from data
        var new_player = PlayerState.new()
        new_player.from_dict(player_data)
        GameState.players[player_id] = new_player
        print("NetworkManager: Created new player ", player_id, " with shop ", new_player.shop_cards)

@rpc("authority", "call_local", "reliable")
func sync_card_pool(pool_data: Dictionary):
    """Sync shared card pool across all clients"""
    print("NetworkManager: Syncing shared card pool")
    GameState.shared_card_pool = pool_data

@rpc("authority", "call_local", "reliable")
func advance_turn():
    """Advance to next turn (host authority)"""
    print("NetworkManager: Advancing turn")
    
    # Use GameState's turn progression system
    GameState.start_new_turn()
    
    # Reset all players' end turn status
    for player in GameState.players.values():
        player.has_ended_turn = false
    
    # Deal new shop cards for all players
    _deal_new_shops_for_all_players()

@rpc("authority", "call_local", "reliable")
func advance_turn_and_return_to_shop():
    """Advance turn and return to shop phase after combat (host authority)"""
    print("NetworkManager: Advancing turn and returning to shop")
    
    # First advance the turn
    GameState.start_new_turn()
    
    # Reset all players' end turn status
    for player in GameState.players.values():
        player.has_ended_turn = false
    
    # Deal new shop cards for all players
    _deal_new_shops_for_all_players()
    
    # Then change phase to shop
    sync_phase_change.rpc(GameState.GameMode.SHOP)

# === COMBAT SYNCHRONIZATION RPCS ===

@rpc("authority", "call_local", "reliable")
func sync_combat_start(player1_id: int, player1_board: Array, player2_id: int, player2_board: Array, random_seed: int):
    """Broadcast combat start with both player boards and deterministic seed"""
    print("NetworkManager: Combat starting - Player ", player1_id, " vs Player ", player2_id, " with seed ", random_seed)
    
    # Store combat data for clients to use
    var combat_data = {
        "player1_id": player1_id,
        "player1_board": player1_board,
        "player2_id": player2_id, 
        "player2_board": player2_board,
        "random_seed": random_seed
    }
    
    # Emit signal so CombatManager can handle the combat
    # We'll create this signal next
    combat_started.emit(combat_data)

@rpc("authority", "call_local", "reliable")
func sync_combat_results(combat_log: Array, player1_damage: int, player2_damage: int):
    """Broadcast combat results to all players"""
    print("NetworkManager: Combat results - P1 damage: ", player1_damage, ", P2 damage: ", player2_damage)
    
    # Apply damage on all clients
    if player1_damage > 0:
        if GameState.players.has(GameState.host_player_id):
            GameState.players[GameState.host_player_id].player_health -= player1_damage
    
    if player2_damage > 0:
        var opponent = GameState.get_opponent_player()
        if opponent:
            opponent.player_health -= player2_damage
    
    # Emit signal for UI update
    combat_results_received.emit(combat_log, player1_damage, player2_damage)

# === UTILITY FUNCTIONS ===

func get_player_count() -> int:
    """Get the number of connected players"""
    return connected_players.size()

func get_connected_players() -> Dictionary:
    """Get dictionary of all connected players"""
    return connected_players

func get_local_player() -> PlayerState:
    """Get the local player's state"""
    if connected_players.has(local_player_id):
        return connected_players[local_player_id]
    return null

func are_all_players_ready() -> bool:
    """Check if all connected players are ready"""
    if connected_players.size() < 2:
        return false  # Need at least 2 players
    
    for player in connected_players.values():
        if not player.is_ready:
            return false
    
    return true

func set_local_player_ready(is_ready: bool):
    """Set the local player's ready state"""
    if connected_players.has(local_player_id):
        # Update locally
        connected_players[local_player_id].is_ready = is_ready
        player_ready_changed.emit(local_player_id, is_ready)
        
        # Send to other players
        update_player_ready_state.rpc(local_player_id, is_ready)

func can_start_game() -> bool:
    """Check if the game can be started (host only, all players ready)"""
    return is_host and are_all_players_ready()

func change_game_phase(new_phase: GameState.GameMode):
    """Change the game phase (multiplayer-aware)"""
    print("NetworkManager: change_game_phase called with ", GameState.GameMode.keys()[new_phase])
    if GameModeManager.is_in_multiplayer_session():
        print("NetworkManager: In multiplayer mode, is_host = ", is_host, ", local_player_id = ", local_player_id)
        # In multiplayer, check if we're host
        if is_host:
            print("NetworkManager: Host changing phase directly")
            # Host can change directly and sync to others
            sync_phase_change.rpc(new_phase)
        else:
            print("NetworkManager: Client requesting phase change from host")
            # Client must request from host
            request_phase_change.rpc_id(GameState.host_player_id, new_phase)
    else:
        print("NetworkManager: Practice mode - changing phase directly")
        # In practice mode, change directly
        GameState.current_mode = new_phase
        GameState.game_mode_changed.emit(new_phase)

# === NETWORK EVENT HANDLERS ===

func _on_peer_connected(peer_id: int):
    """Handle when a peer connects to the server"""
    print("NetworkManager: Peer connected - ID: ", peer_id)
    
    if is_host:
        # Host: A new client connected
        # Send current player info to new player
        var host_player = connected_players[local_player_id]
        update_player_info.rpc_id(peer_id, local_player_id, host_player.player_name)
        
        # Request player info from new player
        request_player_info.rpc_id(peer_id)
    else:
        # Client: We successfully connected to the host
        # Only handle this if it's the host we're connecting to (peer_id should be 1)
        if peer_id == 1:
            # We are now connected as a client
            local_player_id = multiplayer.get_unique_id()  # Get our own unique ID
            is_connected = true
            
            # Add ourselves to our local connected_players dictionary
            var client_player = PlayerState.new()
            client_player.player_id = local_player_id
            client_player.player_name = GameModeManager.get_network_player_name()
            client_player.is_ready = false
            client_player.is_host = false
            connected_players[local_player_id] = client_player
            
            # Emit signal for UI update
            player_joined.emit(local_player_id, client_player.player_name)
            
            # Send our player info to host
            update_player_info.rpc_id(1, local_player_id, client_player.player_name)

@rpc("any_peer", "call_remote", "reliable")
func request_player_info():
    """Request player info from a peer"""
    var player_name = GameModeManager.get_network_player_name()
    update_player_info.rpc_id(multiplayer.get_remote_sender_id(), local_player_id, player_name)

func _on_peer_disconnected(peer_id: int):
    """Handle when a peer disconnects"""
    print("NetworkManager: Peer disconnected - ID: ", peer_id)
    
    if connected_players.has(peer_id):
        var player_name = connected_players[peer_id].player_name
        connected_players.erase(peer_id)
        player_left.emit(peer_id, player_name)

func _on_connection_failed():
    """Handle when connection to server fails"""
    print("NetworkManager: Connection failed")
    connection_failed.emit("Failed to connect to server")
    _reset_network_state()

func _on_server_disconnected():
    """Handle when server disconnects"""
    print("NetworkManager: Server disconnected")
    connection_lost.emit()
    _reset_network_state()

# === PRIVATE FUNCTIONS ===

func _reset_network_state():
    """Reset all network state variables"""
    is_host = false
    is_connected = false
    server_port = DEFAULT_PORT
    local_player_id = 0
    connected_players.clear()

func _is_valid_ip(ip_address: String) -> bool:
    """Validate IP address format"""
    if ip_address == "localhost" or ip_address == "127.0.0.1":
        return true
    
    # Basic IPv4 validation
    var parts = ip_address.split(".")
    if parts.size() != 4:
        return false
    
    for part in parts:
        if not part.is_valid_int():
            return false
        var num = part.to_int()
        if num < 0 or num > 255:
            return false
    
    return true

# === DEBUG FUNCTIONS ===

func get_network_status() -> String:
    """Get current network status for debugging"""
    var status = "NetworkManager Status:\n"
    status += "  Is Host: %s\n" % is_host
    status += "  Is Connected: %s\n" % is_connected
    status += "  Local Player ID: %d\n" % local_player_id
    status += "  Connected Players: %d\n" % connected_players.size()
    
    for player in connected_players.values():
        status += "    Player %d: %s (Ready: %s)\n" % [player.player_id, player.player_name, player.is_ready]
    
    return status

# === GAME ACTION VALIDATION (HOST ONLY) ===

func validate_and_execute_purchase(player_id: int, card_id: String, shop_slot: int) -> bool:
    """Validate and execute a card purchase (host authority)"""
    var player = GameState.players.get(player_id)
    if not player:
        return false
    
    # Check if card is in player's shop at the specified slot
    if shop_slot >= player.shop_cards.size() or player.shop_cards[shop_slot] != card_id:
        print("Purchase validation failed: Card not in shop slot")
        return false
    
    # Check if player can afford the card
    var card_data = CardDatabase.get_card_data(card_id)
    var cost = card_data.get("cost", 3)
    if player.current_gold < cost:
        print("Purchase validation failed: Insufficient gold")
        return false
    
    # Check hand space
    if player.hand_cards.size() >= GameState.max_hand_size:
        print("Purchase validation failed: Hand full")
        return false
    
    # Execute purchase
    player.current_gold -= cost
    player.hand_cards.append(card_id)
    player.shop_cards.remove_at(shop_slot)
    
    # Notify UI of changes if this is the local player
    if player_id == local_player_id:
        player.notify_gold_changed()
        player.notify_shop_changed()
    
    # Remove card from shared pool permanently
    GameState.remove_card_from_pool(card_id)
    
    print("Purchase successful: Player ", player_id, " bought ", card_id, " for ", cost, " gold")
    return true

func validate_and_execute_refresh(player_id: int) -> bool:
    """Validate and execute shop refresh (host authority)"""
    var player = GameState.players.get(player_id)
    if not player:
        return false
    
    var refresh_cost = 1
    if player.current_gold < refresh_cost:
        print("Refresh validation failed: Insufficient gold")
        return false
    
    # Return current shop cards to pool
    GameState.return_cards_to_pool(player.shop_cards)
    
    # Deduct cost
    player.current_gold -= refresh_cost
    player.notify_gold_changed()  # Trigger signal for UI update
    
    # Deal new shop cards
    var shop_size = 3 + player.shop_tier  # Basic shop size + tier bonus
    GameState.deal_cards_to_shop(player_id, shop_size)
    player.notify_shop_changed()  # Trigger signal for UI update
    
    print("Shop refresh successful for player ", player_id)
    return true

func validate_and_execute_upgrade(player_id: int) -> bool:
    """Validate and execute shop tier upgrade (host authority)"""
    var player = GameState.players.get(player_id)
    if not player:
        return false
    
    if player.shop_tier >= 6:
        print("Upgrade validation failed: Already max tier")
        return false
    
    var upgrade_cost = player.current_tavern_upgrade_cost
    if player.current_gold < upgrade_cost:
        print("Upgrade validation failed: Insufficient gold")
        return false
    
    # Execute upgrade
    player.current_gold -= upgrade_cost
    player.shop_tier += 1
    player.current_tavern_upgrade_cost = GameState.TAVERN_UPGRADE_BASE_COSTS.get(player.shop_tier + 1, 999)
    
    # Notify UI of changes if this is the local player
    if player_id == local_player_id:
        player.notify_gold_changed()
    
    print("Shop upgrade successful: Player ", player_id, " now tier ", player.shop_tier)
    return true

func validate_and_execute_sell(player_id: int, card_id: String) -> bool:
    """Validate and execute minion sell (host authority)"""
    var player = GameState.players.get(player_id)
    if not player:
        return false
    
    # Check if player has the minion
    if not player.board_minions.has(card_id):
        print("Sell validation failed: Player doesn't have minion")
        return false
    
    # Execute sell
    player.board_minions.erase(card_id)
    player.current_gold += 1  # Standard sell value
    
    # Return card to shared pool
    GameState.add_card_to_pool(card_id)
    
    print("Sell successful: Player ", player_id, " sold ", card_id, " for 1 gold")
    return true

func validate_and_execute_end_turn(player_id: int) -> bool:
    """Validate and execute end turn (host authority)"""
    var player = GameState.players.get(player_id)
    if not player:
        return false
    
    player.has_ended_turn = true
    print("Player ", player_id, " has ended their turn")
    return true

func _all_players_ended_turn() -> bool:
    """Check if all players have ended their turn"""
    for player in GameState.players.values():
        if not player.has_ended_turn:
            return false
    return true

func _deal_new_shops_for_all_players():
    """Deal new shop cards for all players at turn start"""
    for player_id in GameState.players.keys():
        var player = GameState.players[player_id]
        
        # Return current shop cards to pool
        GameState.return_cards_to_pool(player.shop_cards)
        
        # Deal new cards
        var shop_size = 3 + player.shop_tier
        GameState.deal_cards_to_shop(player_id, shop_size)
        
        # Gold is already updated by GameState.start_new_turn() called in advance_turn()
        # Just ensure the player state has the correct gold value
        print("Player ", player_id, " gold after turn advance: ", player.current_gold)
    
    # Sync all player states
    for player_id in GameState.players.keys():
        sync_player_state.rpc(player_id, GameState.players[player_id].to_dict())
    
    sync_card_pool.rpc(GameState.shared_card_pool) 
