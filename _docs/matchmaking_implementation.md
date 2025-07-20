# Matchmaking Implementation Design Document

## Overview
This document outlines the design and implementation plan for adding 3-4 player matchmaking support to OpenBattlefields. The system will randomly pair players each round, handle odd player counts with "ghost" opponents, and maintain the host-authoritative architecture.

## Design Decisions

### Core Requirements
- **Max Players**: 4 (designed to scale to 8 later)
- **Min Players**: 2 (maintaining current functionality)
- **Matchmaking**: Random pairing each round, host-controlled
- **Odd Players**: One random player fights a "Ghost" (empty board)
- **Combat Display**: Players only see their own combat
- **Elimination**: Game continues until one player remains
- **Disconnections**: Treated as AFK players (no special handling)

### UI/UX Decisions
1. **Lobby**: Shows all connected players (up to 4)
2. **Shop Phase**: "Next Opponent: [Name]" displayed immediately and persistently
3. **Ghost Opponent**: Displayed as "Next Opponent: Ghost"
4. **Combat Phase**: Players see only their combat, wait for host to advance
5. **Elimination**: Players see defeat screen but game continues

### Technical Decisions
- Host calculates and broadcasts all matchups
- All combats resolve simultaneously 
- Ghost combat plays normally against empty board
- Standings tracked for proper placement (3rd, 2nd, 1st)

## Implementation Plan

### 1. Data Structure Updates

#### player_state.gd
```gdscript
# Add opponent tracking
var current_opponent_id: int = -1  # -1 for no opponent, 0 for ghost
var current_opponent_name: String = ""

# Add to get_state() for network sync
state["current_opponent_id"] = current_opponent_id
state["current_opponent_name"] = current_opponent_name
```

#### game_state.gd
```gdscript
# Add matchmaking data
var current_matchups: Dictionary = {}  # player_id -> opponent_id
var ghost_player_id: int = -1  # Player fighting ghost this round (-1 if none)

# Add constants
const GHOST_PLAYER_ID = 0  # Special ID for ghost opponent
const MAX_PLAYERS = 4
```

### 2. Matchmaking Manager

Create new file: `matchmaking_manager.gd`
```gdscript
class_name MatchmakingManager

static func generate_matchups(active_players: Array) -> Dictionary:
    """Generate random matchups for all active players"""
    var matchups = {}
    var available = active_players.duplicate()
    available.shuffle()
    
    # Pair up players
    while available.size() >= 2:
        var player1 = available.pop_back()
        var player2 = available.pop_back()
        matchups[player1] = player2
        matchups[player2] = player1
    
    # Handle odd player with ghost
    if available.size() == 1:
        var ghost_player = available[0]
        matchups[ghost_player] = GameState.GHOST_PLAYER_ID
    
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
```

### 3. Network Updates

#### network_manager.gd
```gdscript
# Add RPC for matchup broadcast
@rpc("authority", "call_local", "reliable")
func broadcast_matchups(matchups: Dictionary) -> void:
    """Broadcast matchup assignments to all clients"""
    print("Broadcasting matchups: ", matchups)
    GameState.current_matchups = matchups
    MatchmakingManager.apply_matchups(matchups)
    
    # Signal UI to update
    matchups_assigned.emit()

# Add signal
signal matchups_assigned

# Modify advance_turn_and_return_to_shop()
@rpc("authority", "call_local", "reliable") 
func advance_turn_and_return_to_shop() -> void:
    # ... existing turn advancement code ...
    
    # Generate and broadcast matchups for next round
    if GameState.current_mode == GameState.GameMode.SHOP:
        var active_players = []
        for player_id in GameState.players:
            if GameState.players[player_id].player_health > 0:
                active_players.append(player_id)
        
        var matchups = MatchmakingManager.generate_matchups(active_players)
        broadcast_matchups(matchups)
```

### 4. UI Updates

#### ui_manager.gd
```gdscript
# Add opponent display element
var opponent_display_label: Label

func create_shop_ui_elements():
    # ... existing code ...
    
    # Add opponent display
    opponent_display_label = Label.new()
    opponent_display_label.name = "OpponentDisplay"
    opponent_display_label.text = "Next Opponent: Loading..."
    apply_font_to_label(opponent_display_label, UI_FONT_SIZE_LARGE)
    
    # Position below turn counter
    var turn_label_pos = turn_label.position
    opponent_display_label.position = Vector2(turn_label_pos.x, turn_label_pos.y + 40)
    
    top_ui_container.add_child(opponent_display_label)

func update_opponent_display():
    """Update the next opponent display"""
    if not opponent_display_label:
        return
        
    var local_player = GameState.get_local_player()
    if local_player:
        opponent_display_label.text = "Next Opponent: " + local_player.current_opponent_name
        opponent_display_label.visible = (GameState.current_mode == GameState.GameMode.SHOP)
    else:
        opponent_display_label.visible = false
```

### 5. Combat Manager Updates

#### combat_manager.gd
```gdscript
# Modify get_opponent_for_combat() 
func get_opponent_for_combat() -> PlayerState:
    """Get the assigned opponent for current player"""
    var local_player = GameState.get_local_player()
    if not local_player:
        return null
    
    var opponent_id = local_player.current_opponent_id
    
    # Handle ghost opponent
    if opponent_id == GameState.GHOST_PLAYER_ID:
        # Create empty player state for ghost
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

# Update start_multiplayer_combat()
func start_multiplayer_combat():
    """Start combat using assigned matchups"""
    var opponent = get_opponent_for_combat()
    if not opponent:
        print("ERROR: No opponent assigned for combat!")
        return
    
    # Show opponent's board in enemy area
    _display_multiplayer_board_in_area(
        opponent.board_minions,
        main_layout.get_node("ShopArea"),
        "Enemy Board: " + opponent.player_name,
        false
    )
    
    # ... rest of existing combat code ...
```

### 6. Lobby Updates

#### multiplayer_lobby.gd
```gdscript
# Update UI to show 4 player slots
const MAX_PLAYER_SLOTS = 4

# Modify player list display to show all connected players
func update_player_list():
    # Clear existing
    for child in player_list_container.get_children():
        child.queue_free()
    
    # Add all players (up to MAX_PLAYER_SLOTS)
    var player_count = 0
    for player_id in GameState.players:
        if player_count >= MAX_PLAYER_SLOTS:
            break
            
        var player = GameState.players[player_id]
        var label = Label.new()
        label.text = player.player_name
        if player_id == GameState.host_player_id:
            label.text += " (Host)"
        player_list_container.add_child(label)
        player_count += 1
    
    # Show empty slots
    while player_count < MAX_PLAYER_SLOTS:
        var label = Label.new()
        label.text = "[Empty Slot]"
        label.modulate = Color(0.5, 0.5, 0.5)
        player_list_container.add_child(label)
        player_count += 1
```

### 7. Game Flow Updates

#### host_game_logic.gd
```gdscript
# Add to advance_turn()
func advance_turn():
    # ... existing turn advancement ...
    
    # After dealing new shops, generate matchups
    var active_players = []
    for player_id in GameState.players:
        if GameState.players[player_id].player_health > 0:
            active_players.append(player_id)
    
    if active_players.size() >= 2:
        var matchups = MatchmakingManager.generate_matchups(active_players)
        GameState.current_matchups = matchups
        MatchmakingManager.apply_matchups(matchups)
```

## Implementation Order

1. **Phase 1**: Data structures and matchmaking logic
   - Update player_state.gd and game_state.gd
   - Create matchmaking_manager.gd
   - Add network RPCs

2. **Phase 2**: UI Updates
   - Add opponent display to shop phase
   - Update lobby for 4 players
   - Connect UI to matchup signals

3. **Phase 3**: Combat Integration
   - Update combat manager for assigned opponents
   - Handle ghost opponents
   - Ensure proper damage calculation

4. **Phase 4**: Testing and Polish
   - Test with 2, 3, and 4 players
   - Verify ghost mechanics
   - Ensure elimination handling works correctly

## Edge Cases Handled

1. **Odd number of players**: One random player fights ghost
2. **Player disconnection**: Treated as AFK, no special handling
3. **All but one eliminated**: Game ends, last player wins
4. **Multiple eliminations same round**: Random placement assignment
5. **2 players**: Works exactly as current system

## Future Enhancements

1. **Smarter Matchmaking**: Avoid repeat opponents, balance by health/board strength
2. **Ghost Improvements**: Use eliminated player's last board state
3. **Spectator Mode**: Allow eliminated players to watch ongoing matches
4. **8 Player Support**: Increase MAX_PLAYERS and test scaling
5. **Tournament Brackets**: Show visual bracket for remaining players

## Testing Plan

1. **2 Player**: Verify existing functionality unchanged
2. **3 Players**: Test ghost assignment and rotation
3. **4 Players**: Test full matchmaking with no ghost
4. **Elimination**: Test proper placement tracking
5. **Network**: Verify sync with high latency/packet loss