# MatchmakingManager.gd
# Handles player matchmaking for multi-player games

class_name MatchmakingManager

static func generate_matchups(active_players: Array) -> Dictionary:
    """Generate random matchups for all active players
    Returns: Dictionary of player_id -> opponent_id mappings"""
    var matchups = {}
    var available = active_players.duplicate()
    available.shuffle()
    
    print("MatchmakingManager: Generating matchups for ", available.size(), " players")
    
    # Pair up players
    while available.size() >= 2:
        var player1 = available.pop_back()
        var player2 = available.pop_back()
        matchups[player1] = player2
        matchups[player2] = player1
        print("  Matched: Player ", player1, " vs Player ", player2)
    
    # Handle odd player with ghost
    if available.size() == 1:
        var ghost_player = available[0]
        matchups[ghost_player] = GameState.GHOST_PLAYER_ID
        GameState.ghost_player_id = ghost_player
        print("  Matched: Player ", ghost_player, " vs Ghost")
    else:
        GameState.ghost_player_id = -1
    
    return matchups

static func apply_matchups(matchups: Dictionary) -> void:
    """Apply matchup data to player states"""
    for player_id in matchups:
        if GameState.players.has(player_id):
            var opponent_id = matchups[player_id]
            var player = GameState.players[player_id]
            
            player.current_opponent_id = opponent_id
            
            if opponent_id == GameState.GHOST_PLAYER_ID:
                player.current_opponent_name = "Ghost"
            elif GameState.players.has(opponent_id):
                player.current_opponent_name = GameState.players[opponent_id].player_name
            else:
                player.current_opponent_name = "Unknown"
            
            print("  Player ", player_id, " (", player.player_name, ") will face ", 
                  player.current_opponent_name, " (ID: ", opponent_id, ")")

static func get_opponent_for_player(player_id: int) -> PlayerState:
    """Get the PlayerState for a player's current opponent
    Returns null if no opponent or ghost opponent"""
    if not GameState.players.has(player_id):
        return null
    
    var player = GameState.players[player_id]
    var opponent_id = player.current_opponent_id
    
    # Handle ghost opponent
    if opponent_id == GameState.GHOST_PLAYER_ID:
        # Create a temporary PlayerState for the ghost
        var ghost = PlayerState.new()
        ghost.player_id = GameState.GHOST_PLAYER_ID
        ghost.player_name = "Ghost"
        ghost.board_minions = []  # Empty board
        ghost.player_health = 1  # Doesn't matter, won't deal damage
        return ghost
    
    # Return actual opponent
    if GameState.players.has(opponent_id):
        return GameState.players[opponent_id]
    
    return null

static func clear_matchups() -> void:
    """Clear all matchup data"""
    GameState.current_matchups.clear()
    GameState.ghost_player_id = -1
    
    for player_id in GameState.players:
        var player = GameState.players[player_id]
        player.current_opponent_id = -1
        player.current_opponent_name = ""