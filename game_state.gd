# GameState.gd (Autoload Singleton)
extends Node

# Game Mode Enum
enum GameMode { SHOP, COMBAT }

# Multiplayer Game State
var players: Dictionary = {}  # player_id -> PlayerState
var host_player_id: int = 1
var local_player_id: int = 0

# Elimination tracking
var eliminated_players: Array = []  # Array of player IDs in order of elimination
var placement_counter: int = 0  # Counter for determining placement

# Global Game State
var current_turn: int = 1
var current_mode: GameMode = GameMode.SHOP
var shared_card_pool: Dictionary = {}

# Game Limits
var max_hand_size: int = 10
var max_board_size: int = 7

# Matchmaking
var current_matchups: Dictionary = {}  # player_id -> opponent_id
var ghost_player_id: int = -1  # Player fighting ghost this round (-1 if none)
const GHOST_PLAYER_ID = 0  # Special ID for ghost opponent
const MAX_PLAYERS = 4

# Backwards compatibility - delegate to local player
var current_gold: int:
    get: 
        var local_player = get_local_player()
        return local_player.current_gold if local_player else 3
    set(value):
        var local_player = get_local_player()
        if local_player: local_player.current_gold = value

var player_base_gold: int:
    get:
        var local_player = get_local_player()
        return local_player.player_base_gold if local_player else 3
    set(value):
        var local_player = get_local_player()
        if local_player: local_player.player_base_gold = value

var bonus_gold: int:
    get:
        var local_player = get_local_player()
        return local_player.bonus_gold if local_player else 0
    set(value):
        var local_player = get_local_player()
        if local_player: local_player.bonus_gold = value

var shop_tier: int:
    get:
        var local_player = get_local_player()
        return local_player.shop_tier if local_player else 1
    set(value):
        var local_player = get_local_player()
        if local_player: local_player.shop_tier = value

var current_tavern_upgrade_cost: int:
    get:
        var local_player = get_local_player()
        return local_player.current_tavern_upgrade_cost if local_player else 5
    set(value):
        var local_player = get_local_player()
        if local_player: local_player.current_tavern_upgrade_cost = value

var player_health: int:
    get:
        var local_player = get_local_player()
        return local_player.player_health if local_player else 25
    set(value):
        var local_player = get_local_player()
        if local_player: local_player.player_health = value

var enemy_health: int:
    get:
        var opponent = get_opponent_player()
        return opponent.player_health if opponent else 25

# Legacy card_pool reference
var card_pool: Dictionary:
    get: return shared_card_pool
    set(value): shared_card_pool = value

# Constants
const GLOBAL_GOLD_MAX = 255
const TAVERN_UPGRADE_BASE_COSTS = {
    2: 5,   # Tier 1 → 2: base cost 5
    3: 7,   # Tier 2 → 3: base cost 7
    4: 8,   # Tier 3 → 4: base cost 8
    5: 9,   # Tier 4 → 5: base cost 9
    6: 11   # Tier 5 → 6: base cost 11
}
const DEFAULT_COMBAT_DAMAGE = 5

# Signals for state changes
signal turn_changed(new_turn: int)
signal gold_changed(new_gold: int, max_gold: int)
signal shop_tier_changed(new_tier: int)
signal player_health_changed(new_health: int)
signal enemy_health_changed(new_health: int)
signal game_over(winner: String)
signal game_mode_changed(new_mode: GameMode)
signal player_eliminated(player_id: int, placement: int)
signal player_victorious(player_id: int)

func _ready():
    print("GameState singleton initialized")
    # Initialize the card pool when the singleton is ready
    initialize_card_pool()
    
    # Initialize card art cache for better export compatibility
    CardDatabase.initialize_art_cache()
    
    # Don't set up state here - wait for scene to properly initialize

# === INITIALIZATION ===

func initialize_game_state():
    """Initialize game state based on current game mode - call this when scene is ready"""
    print("GameState: Initializing game state")
    
    # Set up state based on game mode
    if GameModeManager.is_in_multiplayer_session():
        setup_multiplayer_state()
    else:
        setup_practice_state()

# === MULTIPLAYER HELPER FUNCTIONS ===

func setup_multiplayer_state():
    """Initialize multiplayer state when entering a multiplayer game"""
    if NetworkManager:
        local_player_id = NetworkManager.local_player_id
        # Find the host player ID (the one marked as host)
        for player_id in NetworkManager.connected_players:
            if NetworkManager.connected_players[player_id].is_host:
                host_player_id = player_id
                break
        
        print("GameState: Setting up multiplayer - local_player_id: ", local_player_id, ", host_player_id: ", host_player_id, ", is_host: ", NetworkManager.is_host)
        
        # Initialize all connected players
        for connected_player_id in NetworkManager.connected_players.keys():
            if not players.has(connected_player_id):
                var network_player = NetworkManager.connected_players[connected_player_id]
                var game_player = PlayerState.new()
                game_player.player_id = connected_player_id
                game_player.player_name = network_player.player_name
                game_player.is_host = (connected_player_id == host_player_id)
                game_player.reset_game_state()
                players[connected_player_id] = game_player
        
        # If host, sync card pool first, then deal initial shop cards
        if local_player_id == host_player_id:
            print("GameState: Host syncing card pool to all clients")
            NetworkManager.sync_card_pool.rpc(shared_card_pool)
            
            print("GameState: Host will deal initial shops")
            # Use call_deferred to ensure everything is initialized
            call_deferred("_deal_initial_shops_for_all_players")
        
        print("GameState: Multiplayer state initialized for ", players.size(), " players")

func setup_practice_state():
    """Initialize practice mode state with a local player"""
    local_player_id = 0  # Practice mode uses ID 0
    
    # Create a local player for practice mode
    var practice_player = PlayerState.new()
    practice_player.player_id = local_player_id
    practice_player.player_name = SettingsManager.get_player_name()
    practice_player.is_host = true  # In practice mode, player is effectively the host
    practice_player.reset_game_state()
    players[local_player_id] = practice_player
    
    print("GameState: Practice mode state initialized for player: ", practice_player.player_name)

func get_local_player() -> PlayerState:
    """Get the local player's state"""
    if players.has(local_player_id):
        return players[local_player_id]
    return null

func get_opponent_player() -> PlayerState:
    """Get the opponent player's state (assumes 2 players)"""
    for player_id in players.keys():
        if player_id != local_player_id:
            return players[player_id]
    return null

func get_host_player() -> PlayerState:
    """Get the host player's state"""
    if players.has(host_player_id):
        return players[host_player_id]
    return null

func is_host() -> bool:
    """Check if local player is the host"""
    return local_player_id == host_player_id

func add_player(player_id: int, player_name: String, is_host_player: bool = false):
    """Add a player to the game state"""
    if not players.has(player_id):
        var new_player = PlayerState.new()
        new_player.player_id = player_id
        new_player.player_name = player_name
        new_player.is_host = is_host_player
        new_player.reset_game_state()
        players[player_id] = new_player
        print("GameState: Added player ", player_id, " (", player_name, ")")

func remove_player(player_id: int):
    """Remove a player from the game state"""
    if players.has(player_id):
        var player_name = players[player_id].player_name
        players.erase(player_id)
        print("GameState: Removed player ", player_id, " (", player_name, ")")

# === ELIMINATION AND VICTORY TRACKING ===

func check_for_eliminations() -> void:
    """Check if any players have been eliminated (0 or less health)"""
    if not GameModeManager.is_in_multiplayer_session():
        return  # Only handle in multiplayer
    
    var newly_eliminated = []
    
    for player_id in players.keys():
        var player = players[player_id]
        if player.player_health <= 0 and player_id not in eliminated_players:
            # Player has been eliminated
            newly_eliminated.append(player_id)
            eliminated_players.append(player_id)
            placement_counter += 1
            
            # Calculate placement (total players - placement_counter + 1)
            var total_players = players.size()
            var placement = total_players - placement_counter + 1
            
            print("Player ", player_id, " (", player.player_name, ") eliminated - ", _get_placement_text(placement))
            
            # Emit elimination signal
            player_eliminated.emit(player_id, placement)
    
    # After processing eliminations, check for victory
    if newly_eliminated.size() > 0:
        _check_for_victory()

func _check_for_victory() -> void:
    """Check if only one player remains with health > 0"""
    var alive_players = []
    
    for player_id in players.keys():
        var player = players[player_id]
        if player.player_health > 0:
            alive_players.append(player_id)
    
    if alive_players.size() == 1:
        # We have a winner!
        var winner_id = alive_players[0]
        var winner = players[winner_id]
        print("VICTORY! Player ", winner_id, " (", winner.player_name, ") wins!")
        
        # Emit victory signal
        player_victorious.emit(winner_id)

func is_player_eliminated(player_id: int) -> bool:
    """Check if a player has been eliminated"""
    return player_id in eliminated_players

func get_player_placement(player_id: int) -> int:
    """Get a player's placement (1st, 2nd, etc.)"""
    if player_id in eliminated_players:
        # Find their position in the elimination order
        var elimination_index = eliminated_players.find(player_id)
        var total_players = players.size()
        return total_players - elimination_index
    elif players.has(player_id) and players[player_id].player_health > 0:
        # Still alive - check if they're the only one
        var alive_count = 0
        for p_id in players.keys():
            if players[p_id].player_health > 0:
                alive_count += 1
        
        if alive_count == 1:
            return 1  # Winner!
    
    return -1  # Unknown/error

func _get_placement_text(placement: int) -> String:
    """Convert placement number to text"""
    match placement:
        1: return "1st Place"
        2: return "2nd Place"
        3: return "3rd Place"
        _: return str(placement) + "th Place"

# Initialize card pool (migrated from game_board.gd)
func initialize_card_pool():
    """Set up card availability tracking based on tier and copy counts (shop-available cards only)"""
    shared_card_pool.clear()
    
    print("GameState: Initializing card pool...")
    
    # Copy counts by tier: [tier 1: 18, tier 2: 15, tier 3: 13, tier 4: 11, tier 5: 9, tier 6: 6]
    var copies_by_tier = {1: 18, 2: 15, 3: 13, 4: 11, 5: 9, 6: 6}
    
    # Initialize pool for each shop-available card based on its tier
    var available_cards = CardDatabase.get_all_shop_available_card_ids()
    print("GameState: Found ", available_cards.size(), " shop-available cards")
    
    if available_cards.size() == 0:
        print("ERROR: No shop-available cards found in CardDatabase!")
        return
    
    for card_id in available_cards:
        var card_data = CardDatabase.get_card_data(card_id)
        var tier = card_data.get("tier", 1)
        var copy_count = copies_by_tier.get(tier, 1)
        shared_card_pool[card_id] = copy_count
    
    print("Shared card pool initialized with ", shared_card_pool.size(), " unique cards")
    if shared_card_pool.size() > 0:
        print("Sample cards in pool: ", shared_card_pool.keys().slice(0, 5))

# === SHOP SIZE AND TIER LOGIC ===

func get_shop_size_for_tier(tier: int) -> int:
    """Get number of cards shown in shop for given tier"""
    match tier:
        1: return 3
        2, 3: return 4  
        4, 5: return 5
        6: return 6
        _: return 3  # Default fallback

# === SHARED CARD POOL MANAGEMENT ===

func deal_cards_to_shop(player_id: int, num_cards: int) -> Array:
    """Deal cards from shared pool to a player's shop"""
    var player = players.get(player_id)
    if not player:
        print("Error: Player ", player_id, " not found")
        return []
    
    var dealt_cards = []
    
    # First, preserve frozen cards from previous turn
    if player.frozen_card_ids.size() > 0:
        print("Player ", player_id, " has ", player.frozen_card_ids.size(), " frozen cards to preserve: ", player.frozen_card_ids)
        for frozen_card_id in player.frozen_card_ids:
            dealt_cards.append(frozen_card_id)
        
        # Clear frozen cards after placing them (they're unfrozen now)
        player.frozen_card_ids.clear()
    
    # Calculate how many new cards we need
    var new_cards_needed = num_cards - dealt_cards.size()
    print("  Need to deal ", new_cards_needed, " new cards")
    
    if new_cards_needed > 0:
        var available_cards = []
        
        # Get cards available for this player's shop tier
        print("  Looking for tier ", player.shop_tier, " or lower cards in pool")
        for card_id in shared_card_pool.keys():
            var card_data = CardDatabase.get_card_data(card_id)
            var card_tier = card_data.get("tier", 1)
            var available_count = shared_card_pool[card_id]
            
            if card_tier <= player.shop_tier and available_count > 0:
                # Add multiple entries for cards with multiple copies
                for i in available_count:
                    available_cards.append(card_id)
        
        print("  Found ", available_cards.size(), " available cards for tier ", player.shop_tier)
        
        if available_cards.size() == 0:
            print("  ERROR: No available cards found!")
            print("  Shared card pool has ", shared_card_pool.size(), " unique cards")
            return dealt_cards
        
        # Randomly deal new cards from available pool
        available_cards.shuffle()
        for i in range(min(new_cards_needed, available_cards.size())):
            var card_id = available_cards[i]
            dealt_cards.append(card_id)
            
            # Remove from shared pool
            shared_card_pool[card_id] -= 1
    
    # Update player's shop
    player.shop_cards = dealt_cards
    print("Dealt ", dealt_cards.size(), " cards to player ", player_id, ": ", dealt_cards)
    
    # In SSOT architecture, display updates happen through NetworkManager after state sync
    
    return dealt_cards

func return_cards_to_pool(card_ids: Array, frozen_card_ids: Array = []):
    """Return cards from shops back to shared pool (excluding frozen cards)"""
    var returned_count = 0
    for card_id in card_ids:
        # Don't return frozen cards to the pool
        if card_id not in frozen_card_ids:
            if shared_card_pool.has(card_id):
                shared_card_pool[card_id] += 1
            else:
                # This shouldn't happen, but handle gracefully
                shared_card_pool[card_id] = 1
            returned_count += 1
    
    print("Returned ", returned_count, " cards to shared pool (excluded ", frozen_card_ids.size(), " frozen cards)")

func remove_card_from_pool(card_id: String):
    """Permanently remove a card from the pool (when purchased)"""
    if shared_card_pool.has(card_id) and shared_card_pool[card_id] > 0:
        shared_card_pool[card_id] -= 1
        print("Removed ", card_id, " from shared pool (purchased)")
        return true
    return false

func add_card_to_pool(card_id: String):
    """Add a card back to the pool (when sold)"""
    if shared_card_pool.has(card_id):
        shared_card_pool[card_id] += 1
    else:
        shared_card_pool[card_id] = 1
    print("Added ", card_id, " back to shared pool (sold)")

func get_available_card_count(card_id: String) -> int:
    """Get how many copies of a card are available in the shared pool"""
    return shared_card_pool.get(card_id, 0)

func _deal_initial_shops_for_all_players():
    """Deal initial shop cards for all players at game start"""
    print("GameState: _deal_initial_shops_for_all_players called")
    print("GameState: Number of players: ", players.size())
    
    for player_id in players.keys():
        var player = players[player_id]
        print("GameState: Dealing shop for player ", player_id, " (", player.player_name, ")")
        var shop_size = get_shop_size_for_tier(player.shop_tier)
        print("GameState: Shop size for tier ", player.shop_tier, ": ", shop_size)
        var dealt_cards = deal_cards_to_shop(player_id, shop_size)
        print("GameState: Dealt cards to player ", player_id, ": ", dealt_cards)
    
    print("GameState: Initial shops dealt for all players")
    
    # Sync all player states to clients after dealing initial shops
    if NetworkManager and is_host():
        print("GameState: Host syncing initial shop states to all clients")
        
        for player_id in players.keys():
            var player_dict = players[player_id].to_dict()
            NetworkManager.sync_player_state.rpc(player_id, player_dict)
        
        # Generate and broadcast initial matchups
        print("GameState: Generating initial matchups")
        var active_players = []
        for pid in players.keys():
            active_players.append(pid)
        
        if active_players.size() >= 2:
            var matchups = MatchmakingManager.generate_matchups(active_players)
            NetworkManager.broadcast_matchups.rpc(matchups)
        
        # Also update local host display
        if NetworkManager.has_method("_update_local_player_display"):
            NetworkManager.call_deferred("_update_local_player_display")

# Get current state as a dictionary (useful for debugging/save systems later)
func get_state_snapshot() -> Dictionary:
    return {
        "current_turn": current_turn,
        "player_base_gold": player_base_gold,
        "current_gold": current_gold,
        "bonus_gold": bonus_gold,
        "shop_tier": shop_tier,
        "current_tavern_upgrade_cost": current_tavern_upgrade_cost,
        "player_health": player_health,
        "enemy_health": enemy_health,
        "current_mode": current_mode
    }

# === CORE STATE MANAGEMENT FUNCTIONS ===

# Gold Management Functions
func calculate_base_gold_for_turn(turn: int) -> int:
    """Calculate base gold for a given turn (3 on turn 1, +1 per turn up to 10)"""
    if turn <= 1:
        return 3
    elif turn <= 8:
        return 2 + turn  # Turn 2=4 gold, turn 3=5 gold, ..., turn 8=10 gold
    else:
        return 10  # Maximum base gold of 10 from turn 8 onwards

func spend_gold(amount: int) -> bool:
    """Attempt to spend gold. Returns true if successful, false if insufficient gold"""
    if current_gold >= amount:
        current_gold -= amount
        gold_changed.emit(current_gold, GLOBAL_GOLD_MAX)
        return true
    else:
        print("Insufficient gold: need ", amount, ", have ", current_gold)
        return false

func can_afford(cost: int) -> bool:
    """Check if player can afford a given cost"""
    return current_gold >= cost

func increase_base_gold(amount: int):
    """Permanently increase player's base gold income"""
    player_base_gold = min(player_base_gold + amount, GLOBAL_GOLD_MAX)
    print("Base gold increased by ", amount, " to ", player_base_gold)
    gold_changed.emit(current_gold, GLOBAL_GOLD_MAX)

func add_bonus_gold(amount: int):
    """Add temporary bonus gold for next turn only"""
    bonus_gold = min(bonus_gold + amount, GLOBAL_GOLD_MAX - player_base_gold)
    print("Bonus gold added: ", amount, " (total bonus: ", bonus_gold, ")")
    gold_changed.emit(current_gold, GLOBAL_GOLD_MAX)

func gain_gold(amount: int):
    """Immediately gain current gold (within global limits)"""
    current_gold = min(current_gold + amount, GLOBAL_GOLD_MAX)
    print("Gained ", amount, " gold (current: ", current_gold, ")")
    gold_changed.emit(current_gold, GLOBAL_GOLD_MAX)

# Turn Management
func start_new_turn():
    """Advance to the next turn and refresh gold"""
    current_turn += 1
    
    if GameModeManager.is_in_multiplayer_session():
        # Multiplayer: Update all players (should only be called by host via NetworkManager)
        for player in players.values():
            _update_player_for_new_turn(player)
    else:
        # Practice mode: Update local player using compatibility properties
        var new_base_gold = calculate_base_gold_for_turn(current_turn)
        player_base_gold = max(player_base_gold, new_base_gold)
        
        # Refresh current gold (base + any bonus, capped at global max)
        current_gold = min(player_base_gold + bonus_gold, GLOBAL_GOLD_MAX)
        bonus_gold = 0  # Reset bonus after applying it
        
        # Decrease tavern upgrade cost by 1 each turn (minimum 0)
        current_tavern_upgrade_cost = max(current_tavern_upgrade_cost - 1, 0)
        
        print("Turn ", current_turn, " started - Base Gold: ", player_base_gold, ", Current Gold: ", current_gold)
        print("Tavern upgrade cost decreased to: ", current_tavern_upgrade_cost)
    
    # Emit signals for state changes
    turn_changed.emit(current_turn)
    if not GameModeManager.is_in_multiplayer_session():
        gold_changed.emit(current_gold, GLOBAL_GOLD_MAX)

func _update_player_for_new_turn(player: PlayerState):
    """Update a player's state for a new turn (multiplayer)"""
    # Update base gold from turn progression (but don't decrease it)
    var new_base_gold = calculate_base_gold_for_turn(current_turn)
    player.player_base_gold = max(player.player_base_gold, new_base_gold)
    
    # Refresh current gold (base + any bonus, capped at global max)
    player.current_gold = min(player.player_base_gold + player.bonus_gold, GLOBAL_GOLD_MAX)
    player.bonus_gold = 0  # Reset bonus after applying it
    
    # Decrease tavern upgrade cost by 1 each turn (minimum 0)
    player.current_tavern_upgrade_cost = max(player.current_tavern_upgrade_cost - 1, 0)
    
    print("Player ", player.player_id, " - Turn ", current_turn, " started - Base Gold: ", player.player_base_gold, ", Current Gold: ", player.current_gold)

# Tavern Management Functions
func calculate_tavern_upgrade_cost() -> int:
    """Get current cost to upgrade tavern tier"""
    if not can_upgrade_tavern():
        return -1  # Cannot upgrade past tier 6
    return current_tavern_upgrade_cost

func calculate_tavern_upgrade_cost_for_player(player: PlayerState) -> int:
    """Get tavern upgrade cost for a specific player"""
    if player.shop_tier >= 6:
        return -1  # Cannot upgrade past tier 6
    return player.current_tavern_upgrade_cost

func can_upgrade_tavern() -> bool:
    """Check if tavern can be upgraded (not at max tier)"""
    return shop_tier < 6

func upgrade_tavern_tier() -> bool:
    """Attempt to upgrade tavern tier. Returns true if successful."""
    if not can_upgrade_tavern():
        print("Cannot upgrade - already at max tier (", shop_tier, ")")
        return false
    
    var upgrade_cost = calculate_tavern_upgrade_cost()
    
    if not can_afford(upgrade_cost):
        print("Cannot afford tavern upgrade - need ", upgrade_cost, " gold, have ", current_gold)
        return false
    
    if spend_gold(upgrade_cost):
        shop_tier += 1
        
        # Reset tavern upgrade cost to base cost for next tier
        var next_tier_after_upgrade = shop_tier + 1
        if next_tier_after_upgrade <= 6:
            current_tavern_upgrade_cost = TAVERN_UPGRADE_BASE_COSTS.get(next_tier_after_upgrade, 0)
            print("Upgraded tavern to tier ", shop_tier, " for ", upgrade_cost, " gold. Next upgrade costs ", current_tavern_upgrade_cost)
        else:
            print("Upgraded tavern to tier ", shop_tier, " for ", upgrade_cost, " gold. Max tier reached!")
        
        # Emit signals for state changes
        shop_tier_changed.emit(shop_tier)
        return true
    
    return false

# Health Management Functions
func take_damage(damage: int, is_player: bool = true) -> void:
    """Apply damage to player or enemy and check for game over"""
    if is_player:
        player_health = max(0, player_health - damage)
        player_health_changed.emit(player_health)
        print("Player took %d damage, health now: %d" % [damage, player_health])
        if player_health <= 0:
            game_over.emit("enemy")
            print("GAME OVER - Enemy wins!")
    else:
        enemy_health = max(0, enemy_health - damage)
        enemy_health_changed.emit(enemy_health)
        print("Enemy took %d damage, health now: %d" % [damage, enemy_health])
        if enemy_health <= 0:
            game_over.emit("player")
            print("GAME OVER - Player wins!")

func get_player_health() -> int:
    """Get current player health"""
    return player_health

func get_enemy_health() -> int:
    """Get current enemy health"""
    return enemy_health

func reset_health() -> void:
    """Reset both players to starting health (for testing)"""
    player_health = 25
    enemy_health = 25
    player_health_changed.emit(player_health)
    enemy_health_changed.emit(enemy_health)
    print("Health reset - Player: %d, Enemy: %d" % [player_health, enemy_health])

func set_enemy_health(health: int) -> void:
    """Set enemy health (useful for testing different enemy board healths)"""
    enemy_health = max(0, health)
    enemy_health_changed.emit(enemy_health)
    print("Enemy health set to: %d" % enemy_health)

# Print current state for debugging
func debug_print_state():
    print("=== GameState Debug ===")
    print("Turn: ", current_turn)
    print("Gold: ", current_gold, "/", GLOBAL_GOLD_MAX, " (Base: ", player_base_gold, ", Bonus: ", bonus_gold, ")")
    print("Shop Tier: ", shop_tier, " (Upgrade Cost: ", current_tavern_upgrade_cost, ")")
    print("Health - Player: ", player_health, ", Enemy: ", enemy_health)
    print("Mode: ", GameMode.keys()[current_mode])
    print("======================") 
