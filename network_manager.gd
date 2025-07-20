# NetworkManager.gd (Autoload Singleton)
# Manages all multiplayer networking functionality

extends Node

# Network configuration
const DEFAULT_PORT = 9999
const MAX_PLAYERS = 8  # For up to 8 player games
const CONNECTION_TIMEOUT = 10.0  # seconds

# Network state
var is_host: bool = false
var is_connected: bool = false
var server_port: int = DEFAULT_PORT
var connected_players: Dictionary = {}  # peer_id -> PlayerState
var local_player_id: int = 0

# State synchronization tracking
# Rate limiting removed - all game actions now go through HostGameLogic

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
signal combat_results_received_v2(combat_log: Array, player1_id: int, player1_damage: int, player2_id: int, player2_damage: int, final_states: Dictionary)
signal combat_results_received_v3(combat_log: Array, player1_id: int, player1_damage: int, player1_final: Array, player2_id: int, player2_damage: int, player2_final: Array)
signal matchups_assigned()

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

@rpc("any_peer", "call_local", "reliable")
func request_game_action(action: String, params: Dictionary):
    """Unified endpoint for all game actions"""
    var sender_id = multiplayer.get_remote_sender_id()
    # If called locally by host, sender_id will be 0, so use local_player_id
    if sender_id == 0:
        sender_id = local_player_id
    
    if not is_host:
        print("ERROR: Non-host received game action request")
        return
    
    print("NetworkManager: Game action requested - Action: ", action, ", Player: ", sender_id, ", Params: ", params)
    
    # Process action through HostGameLogic
    var result = HostGameLogic.process_game_action(sender_id, action, params)
    print("NetworkManager: Action result - Success: ", result.success, ", Error: ", result.get("error", "none"))
    
    if result.success:
        # Sync all affected player states
        for player_id in result.get("state_changes", {}):
            if GameState.players.has(player_id):
                var state_dict = GameState.players[player_id].to_dict()
                print("NetworkManager: Syncing state for player ", player_id, " - shop: ", state_dict.get("shop_cards", []), ", hand: ", state_dict.get("hand_cards", []))
                sync_player_state.rpc(player_id, state_dict)
        
        # For host, immediately update displays after certain actions
        if is_host and sender_id == local_player_id:
            var player = GameState.get_local_player()
            if player:
                match action:
                    "sell_minion":
                        print("NetworkManager: Host sold minion, updating board display")
                        call_deferred("_update_board_display", player)
                    "purchase_card":
                        print("NetworkManager: Host purchased card, updating shop display")
                        call_deferred("_update_local_player_display")
        
        # Sync card pool if it changed
        if result.get("pool_changed", false):
            sync_card_pool.rpc(GameState.shared_card_pool)
    else:
        # Send error to requesting player only
        show_error_message.rpc_id(sender_id, result.get("error", "Unknown error"))

# All game actions now go through request_game_action RPC

@rpc("any_peer", "call_local", "reliable")
func update_board_state(player_id: int, board_minions: Array):
    """Update a player's board state when minions are played/sold/reordered"""
    print("NetworkManager: Board state update - Player: ", player_id, " Minions: ", board_minions)
    
    # Only host processes board updates
    if is_host:
        if GameState.players.has(player_id):
            var player = GameState.players[player_id]
            player.board_minions = board_minions
            # Sync ONLY the board state, not the entire player state
            # This prevents unnecessary shop refreshes
            sync_board_state_only.rpc(player_id, board_minions)
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

@rpc("authority", "call_local", "reliable")
func broadcast_matchups(matchups: Dictionary) -> void:
    """Broadcast matchup assignments to all clients"""
    print("NetworkManager: Broadcasting matchups: ", matchups)
    GameState.current_matchups = matchups
    MatchmakingManager.apply_matchups(matchups)
    
    # Signal UI to update
    matchups_assigned.emit()

# === STATE SYNCHRONIZATION RPCS ===

@rpc("authority", "call_local", "reliable")
func sync_player_state(player_id: int, player_data: Dictionary):
    """Sync a player's state across all clients"""
    var my_peer_id = multiplayer.get_unique_id()
    print("NetworkManager: Syncing player state for player ", player_id, " to peer ", my_peer_id)
    print("NetworkManager: Player data shop_cards: ", player_data.get("shop_cards", []))
    print("NetworkManager: Player data board_minions: ", player_data.get("board_minions", []))
    
    # Validate the player_id in the data matches the parameter
    var data_player_id = player_data.get("player_id", -1)
    if data_player_id != player_id:
        print("NetworkManager: ERROR - Mismatch between player_id parameter (", player_id, ") and data player_id (", data_player_id, ")")
        return
    
    if GameState.players.has(player_id):
        var player = GameState.players[player_id]
        var old_shop = player.shop_cards.duplicate()
        var old_gold = player.current_gold
        var old_frozen = player.frozen_card_ids.duplicate()
        
        # Log the incoming gold value for debugging
        var new_gold = player_data.get("current_gold", -1)
        print("NetworkManager: Player ", player_id, " gold update: ", old_gold, " -> ", new_gold)
        
        # Store old hand cards to detect changes
        var old_hand = player.hand_cards.duplicate()
        
        player.from_dict(player_data)
        print("NetworkManager: Updated player ", player_id, " shop from ", old_shop, " to ", player.shop_cards)
        print("NetworkManager: Updated player ", player_id, " gold from ", old_gold, " to ", player.current_gold)
        print("NetworkManager: Updated player ", player_id, " frozen cards from ", old_frozen, " to ", player.frozen_card_ids)
        print("NetworkManager: Updated player ", player_id, " hand from ", old_hand, " to ", player.hand_cards)
        print("NetworkManager: Updated player ", player_id, " board from ", player.board_minions)
        
        # Check if hand cards changed (new cards were added)
        if player_id == local_player_id:
            # Find which cards were added
            var new_cards = []
            for card_id in player.hand_cards:
                if not card_id in old_hand:
                    new_cards.append(card_id)
            
            if new_cards.size() > 0:
                print("NetworkManager: Local player gained ", new_cards.size(), " new cards: ", new_cards)
                for card_id in new_cards:
                    print("NetworkManager: Creating visual card in hand: ", card_id)
                    _create_visual_card_in_hand(card_id)
                    
                    # Show purchase success message
                    var card_data = CardDatabase.get_card_data(card_id)
                    var card_name = card_data.get("name", "Unknown")
                    var cost = card_data.get("cost", 3)
                    var game_board = get_tree().get_first_node_in_group("game_board")
                    if game_board and game_board.ui_manager:
                        game_board.ui_manager.show_flash_message("Purchased %s for %d gold!" % [card_name, cost], 1.5)
            
            # Also check if we need to recreate all hand visuals (in case of desync)
            var game_board = get_tree().get_first_node_in_group("game_board")
            if game_board:
                _validate_and_update_hand_visuals(player, game_board)
        
        # If this is the local player, update all displays
        if player_id == local_player_id:
            _update_local_player_display()
            
            # Also update board display in case board state changed
            _update_board_display(player)
            
            # Always update UI counts after state changes
            var game_board = get_tree().get_first_node_in_group("game_board")
            if game_board and game_board.ui_manager:
                # Update counts based on the new PlayerState data
                game_board.ui_manager.update_hand_display()
                game_board.ui_manager.update_board_display()
                print("NetworkManager: Updated UI counts - Hand: ", player.hand_cards.size(), ", Board: ", player.board_minions.size())
    else:
        # Create new player from data
        var new_player = PlayerState.new()
        new_player.from_dict(player_data)
        GameState.players[player_id] = new_player
        print("NetworkManager: Created new player ", player_id, " with shop ", new_player.shop_cards)

@rpc("authority", "call_local", "reliable")
func sync_card_pool(pool_data: Dictionary):
    """Sync shared card pool across all clients"""
    print("NetworkManager: Syncing shared card pool with ", pool_data.size(), " unique cards")
    GameState.shared_card_pool = pool_data
    print("NetworkManager: GameState.shared_card_pool now has ", GameState.shared_card_pool.size(), " cards")
    
    # After card pool is synced, update local player display if we have their state
    if !is_host and GameState.get_local_player():
        print("NetworkManager: Card pool synced on client, updating display")
        _update_local_player_display()

@rpc("authority", "call_remote", "reliable")
func show_error_message(message: String):
    """Show error message to specific client"""
    var game_board = get_tree().get_first_node_in_group("game_board")
    if game_board and game_board.ui_manager:
        game_board.ui_manager.show_flash_message(message, 2.0)

@rpc("authority", "call_local", "reliable")
func show_success_message(message: String):
    """Show success message to all clients"""
    var game_board = get_tree().get_first_node_in_group("game_board")
    if game_board and game_board.ui_manager:
        game_board.ui_manager.show_flash_message(message, 1.5)

@rpc("authority", "call_local", "reliable")
func sync_board_state_only(player_id: int, board_minions: Array):
    """Sync only board state without triggering shop refresh"""
    print("NetworkManager: Syncing board state only for player ", player_id, " - Minions: ", board_minions)
    
    if GameState.players.has(player_id):
        var player = GameState.players[player_id]
        player.board_minions = board_minions
        # Don't call from_dict or emit any signals - just update the board array
    else:
        print("NetworkManager: Player ", player_id, " not found for board sync")

@rpc("authority", "call_local", "reliable")
func advance_turn():
    """Advance to next turn (host authority)"""
    print("NetworkManager: Advancing turn")
    
    if not is_host:
        print("ERROR: Non-host trying to advance turn")
        return
    
    # Use HostGameLogic to handle turn advancement
    var result = HostGameLogic.advance_turn_for_all_players()
    
    if result.success:
        # Sync all affected player states
        for player_id in result.get("state_changes", {}):
            if GameState.players.has(player_id):
                var state_dict = GameState.players[player_id].to_dict()
                sync_player_state.rpc(player_id, state_dict)
        
        # Sync card pool if it changed
        if result.get("pool_changed", false):
            sync_card_pool.rpc(GameState.shared_card_pool)

@rpc("authority", "call_local", "reliable")
func advance_turn_and_return_to_shop():
    """Advance turn and return to shop phase after combat (host authority)"""
    print("NetworkManager: Advancing turn and returning to shop")
    
    if not is_host:
        print("ERROR: Non-host trying to advance turn")
        return
    
    # First advance the turn using HostGameLogic
    var result = HostGameLogic.advance_turn_for_all_players()
    
    if result.success:
        # Sync all affected player states
        for player_id in result.get("state_changes", {}):
            if GameState.players.has(player_id):
                var state_dict = GameState.players[player_id].to_dict()
                sync_player_state.rpc(player_id, state_dict)
        
        # Sync card pool if it changed
        if result.get("pool_changed", false):
            sync_card_pool.rpc(GameState.shared_card_pool)
        
        # Generate and broadcast matchups for next round
        var active_players = []
        for player_id in GameState.players:
            if GameState.players[player_id].player_health > 0:
                active_players.append(player_id)
        
        if active_players.size() >= 2:
            var matchups = MatchmakingManager.generate_matchups(active_players)
            broadcast_matchups.rpc(matchups)
    
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
    
    # Apply damage on all clients using explicit player IDs
    # Remember: player1 is always the host (see start_multiplayer_combat)
    if player1_damage > 0:
        if GameState.players.has(GameState.host_player_id):
            print("NetworkManager: Applying ", player1_damage, " damage to host player (ID: ", GameState.host_player_id, ")")
            GameState.players[GameState.host_player_id].player_health -= player1_damage
    
    # Find the non-host player ID
    var client_player_id = -1
    for player_id in GameState.players.keys():
        if player_id != GameState.host_player_id:
            client_player_id = player_id
            break
    
    if player2_damage > 0 and client_player_id != -1:
        if GameState.players.has(client_player_id):
            print("NetworkManager: Applying ", player2_damage, " damage to client player (ID: ", client_player_id, ")")
            GameState.players[client_player_id].player_health -= player2_damage
    
    # Emit signal for UI update
    combat_results_received.emit(combat_log, player1_damage, player2_damage)

@rpc("authority", "call_local", "reliable")
func sync_combat_results_v2(combat_log: Array, player1_id: int, player1_damage: int, player2_id: int, player2_damage: int):
    """Broadcast combat results with explicit player IDs to avoid confusion"""
    print("NetworkManager: Combat results v2 - Player ", player1_id, " takes ", player1_damage, " damage, Player ", player2_id, " takes ", player2_damage, " damage")
    
    # Apply damage to specific players
    if player1_damage > 0 and GameState.players.has(player1_id):
        print("NetworkManager: Applying ", player1_damage, " damage to player ", player1_id, " (", GameState.players[player1_id].player_name, ")")
        GameState.players[player1_id].player_health -= player1_damage
    
    if player2_damage > 0 and GameState.players.has(player2_id):
        print("NetworkManager: Applying ", player2_damage, " damage to player ", player2_id, " (", GameState.players[player2_id].player_name, ")")
        GameState.players[player2_id].player_health -= player2_damage
    
    # Emit signal for UI update - now the UI will need to determine which damage belongs to which player
    combat_results_received.emit(combat_log, player1_damage, player2_damage)

@rpc("authority", "call_local", "reliable")
func sync_combat_results_v3(combat_log: Array, player1_id: int, player1_damage: int, player1_final: Array, player2_id: int, player2_damage: int, player2_final: Array):
    """Broadcast combat results with final board states for visualization"""
    print("NetworkManager: Combat results v3 - Player ", player1_id, " takes ", player1_damage, " damage, Player ", player2_id, " takes ", player2_damage, " damage")
    
    # Apply damage to specific players
    if player1_damage > 0 and GameState.players.has(player1_id):
        print("NetworkManager: Applying ", player1_damage, " damage to player ", player1_id, " (", GameState.players[player1_id].player_name, ")")
        GameState.players[player1_id].player_health -= player1_damage
    
    if player2_damage > 0 and GameState.players.has(player2_id):
        print("NetworkManager: Applying ", player2_damage, " damage to player ", player2_id, " (", GameState.players[player2_id].player_name, ")")
        GameState.players[player2_id].player_health -= player2_damage
    
    # Store final board states for visualization
    var final_states = {
        "player1_id": player1_id,
        "player1_final": player1_final,
        "player2_id": player2_id,
        "player2_final": player2_final
    }
    
    # Only emit v3 signal for animation system (v2 is deprecated)
    combat_results_received_v3.emit(combat_log, player1_id, player1_damage, player1_final, player2_id, player2_damage, player2_final)
    
    # Check for eliminations after damage is applied
    GameState.check_for_eliminations()

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

# === LEGACY VALIDATION FUNCTIONS REMOVED ===
# All game action validation now handled by HostGameLogic singleton

func _deal_new_shops_for_all_players():
    """Deal new shop cards for all players at turn start"""
    print("NetworkManager: Dealing new shops for all players")
    print("NetworkManager: Current turn: ", GameState.current_turn)
    
    for player_id in GameState.players.keys():
        var player = GameState.players[player_id]
        
        print("  Dealing shop for player ", player_id, " (", player.player_name, ")")
        print("    Current shop cards: ", player.shop_cards)
        print("    Frozen cards: ", player.frozen_card_ids)
        print("    Shop tier: ", player.shop_tier)
        
        # Return current shop cards to pool (excluding frozen cards)
        GameState.return_cards_to_pool(player.shop_cards, player.frozen_card_ids)
        
        # Deal new cards (GameState.deal_cards_to_shop handles frozen cards)
        var shop_size = GameState.get_shop_size_for_tier(player.shop_tier)
        GameState.deal_cards_to_shop(player_id, shop_size)
        
        print("    New shop cards: ", player.shop_cards)
        print("    Frozen cards preserved: ", player.frozen_card_ids.size())
        
        # Gold is already updated by GameState.start_new_turn() called in advance_turn()
        # Just ensure the player state has the correct gold value
        print("    Player gold after turn advance: ", player.current_gold)
    
    print("NetworkManager: Syncing all player states after shop deal")
    # Sync all player states
    for player_id in GameState.players.keys():
        var player_dict = GameState.players[player_id].to_dict()
        print("  Syncing player ", player_id, " with frozen cards: ", player_dict.get("frozen_card_ids", []))
        sync_player_state.rpc(player_id, player_dict)
    
    sync_card_pool.rpc(GameState.shared_card_pool)

func _create_visual_card_in_hand(card_id: String):
    """Create a visual card in the local player's hand"""
    # Get the game board to access UI
    var game_board = get_tree().get_first_node_in_group("game_board")
    if game_board:
        # Use the existing function to add card to hand
        game_board.add_card_to_hand_direct(card_id)
        print("NetworkManager: Added visual card ", card_id, " to hand")
    else:
        print("NetworkManager: ERROR - Could not find game_board to add card to hand")

func _update_local_player_display():
    """Update all displays for the local player"""
    var player = GameState.get_local_player()
    if not player:
        print("NetworkManager: No local player found for display update")
        return
    
    var game_board = get_tree().get_first_node_in_group("game_board")
    if not game_board:
        print("NetworkManager: No game board found for display update")
        return
    
    # Check if card pool is initialized
    if GameState.shared_card_pool.is_empty():
        print("NetworkManager: Card pool not yet initialized, skipping shop display update")
        return
    
    # Get full card data for shop display
    var shop_cards_data = []
    for card_id in player.shop_cards:
        var card_data = CardDatabase.get_card_data(card_id).duplicate()  # Make a copy to avoid modifying the original
        if card_data.is_empty():
            print("NetworkManager: Warning - card data not found for: ", card_id)
            continue
        # Add the card ID to the data dictionary
        card_data["id"] = card_id
        shop_cards_data.append(card_data)
    
    print("NetworkManager: Updating shop display with ", shop_cards_data.size(), " cards")
    
    # Update shop display
    if game_board.shop_manager:
        game_board.shop_manager.display_shop(shop_cards_data, player.frozen_card_ids)
    else:
        print("NetworkManager: ERROR - shop_manager not found")
    
    # Update UI displays
    if game_board.ui_manager:
        game_board.ui_manager.update_gold_display_detailed()
        game_board.ui_manager.update_shop_tier_display_detailed()
        
        # Update hand count (visual cards should already exist)
        game_board.ui_manager.update_hand_display()
    
    # Update board display
    _update_board_display(player)

func _update_board_display(player: PlayerState):
    """Update the visual board to match player's board_minions data"""
    var game_board = get_tree().get_first_node_in_group("game_board")
    if not game_board or not game_board.ui_manager:
        return
    
    var board_container = game_board.ui_manager.get_board_container()
    
    # Get current visual cards on board
    var current_visuals = []
    for child in board_container.get_children():
        if child.has_meta("card_id"):
            current_visuals.append(child.get_meta("card_id"))
    
    print("NetworkManager: _update_board_display - Visual cards: ", current_visuals, ", Data cards: ", player.board_minions)
    
    # Always recreate if there's any mismatch (order or content)
    var needs_recreation = false
    if current_visuals.size() != player.board_minions.size():
        needs_recreation = true
    else:
        for i in range(current_visuals.size()):
            var minion = player.board_minions[i]
            var minion_card_id = minion.get("card_id", "") if minion is Dictionary else minion
            if current_visuals[i] != minion_card_id:
                needs_recreation = true
                break
    
    # Compare with data
    if needs_recreation:
        print("NetworkManager: Board visual mismatch! Visuals: ", current_visuals, ", Data: ", player.board_minions)
        print("NetworkManager: Recreating board visuals...")
        
        # Clear only visual cards from board, not the label
        # Use immediate removal for host to prevent duplicates
        var cards_to_remove = []
        for child in board_container.get_children():
            if child.has_meta("card_id"):
                cards_to_remove.append(child)
        
        for card in cards_to_remove:
            board_container.remove_child(card)
            card.queue_free()
        
        # Create new visual cards for each minion
        for minion in player.board_minions:
            var card_id = minion.get("card_id", "")
            var card_data = CardDatabase.get_card_data(card_id).duplicate()
            card_data["id"] = card_id
            
            # Override base stats with current stats
            card_data["attack"] = minion.get("current_attack", card_data.get("attack", 0))
            card_data["health"] = minion.get("current_health", card_data.get("health", 1))
            
            print("NetworkManager: Creating visual for ", card_id)
            print("  Minion data: ", minion)
            print("  Card data attack: ", card_data["attack"], " health: ", card_data["health"])
            
            # Create visual card with drag and click handlers
            var custom_handlers = {
                "drag_started": game_board._on_card_drag_started,
                "card_clicked": game_board._on_card_clicked
            }
            var card_visual = CardFactory.create_card(card_data, card_id, custom_handlers)
            
            # Set metadata
            card_visual.set_meta("card_id", card_id)
            card_visual.set_meta("is_board_card", true)
            
            # Check if stats are buffed and set visual indicator
            var base_data = CardDatabase.get_card_data(card_id)
            var is_buffed = (minion.get("current_attack", 0) > base_data.get("attack", 0) or 
                            minion.get("current_health", 1) > base_data.get("health", 1))
            
            if is_buffed and card_visual.has_node("VBoxContainer/BottomRow/StatsLabel"):
                card_visual.get_node("VBoxContainer/BottomRow/StatsLabel").modulate = Color.GREEN
            
            board_container.add_child(card_visual)
        
        print("NetworkManager: Board visuals recreated with ", player.board_minions.size(), " minions")
        # Count display will be updated by the calling function after state sync

func _validate_and_update_hand_visuals(player: PlayerState, game_board: Node):
    """Validate hand visuals match data and recreate if needed"""
    var hand_container = game_board.ui_manager.get_hand_container()
    
    # Get current visual cards in hand
    var current_visuals = []
    for child in hand_container.get_children():
        if child.has_meta("card_id"):
            current_visuals.append(child.get_meta("card_id"))
    
    # Check if visual state matches data state
    var needs_recreation = false
    if current_visuals.size() != player.hand_cards.size():
        needs_recreation = true
    else:
        # Check if all cards match in order
        for i in range(current_visuals.size()):
            if current_visuals[i] != player.hand_cards[i]:
                needs_recreation = true
                break
    
    if needs_recreation:
        print("NetworkManager: Hand visual mismatch! Visual cards: ", current_visuals, ", Data cards: ", player.hand_cards)
        print("NetworkManager: Recreating all hand visuals...")
        
        # Clear only card visuals, not the label
        # Use immediate removal for host to prevent duplicates
        var cards_to_remove = []
        for child in hand_container.get_children():
            if child.has_meta("card_id"):
                cards_to_remove.append(child)
        
        for card in cards_to_remove:
            hand_container.remove_child(card)
            card.queue_free()
        
        # Recreate all hand cards in correct order
        for card_id in player.hand_cards:
            _create_visual_card_in_hand(card_id)
