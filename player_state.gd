# PlayerState.gd
# Class representing a player's state in multiplayer games

class_name PlayerState
extends RefCounted

# No signals in SSOT architecture - all updates through NetworkManager

# Player identification
var player_id: int = 0
var player_name: String = "Player"
var is_host: bool = false

# Lobby state
var is_ready: bool = false
var connection_status: String = "connected"  # connected, disconnected, reconnecting

# Game state
var current_gold: int = 3
var player_base_gold: int = 3
var bonus_gold: int = 0
var player_health: int = 25
var shop_tier: int = 1
var current_tavern_upgrade_cost: int = 5

# Card collections
var hand_cards: Array = []  # Array of card IDs
var board_minions: Array = []  # Array of minion objects with stats {card_id, current_attack, current_health}  
var shop_cards: Array = []  # Array of card IDs in player's shop
var frozen_card_ids: Array = []  # Array of card IDs frozen for next turn

# Turn state
var is_ready_for_next_phase: bool = false
var has_ended_turn: bool = false

# Matchmaking
var current_opponent_id: int = -1  # -1 for no opponent, 0 for ghost
var current_opponent_name: String = ""

# Network timing
var last_ping_time: float = 0.0
var ping_ms: int = 0

func _init(id: int = 0, name: String = "Player"):
    """Initialize player state with basic info"""
    player_id = id
    player_name = name
    is_host = (id == 1)  # Host is always player ID 1

# === LOBBY FUNCTIONS ===

func set_ready(ready: bool):
    """Set player ready status"""
    is_ready = ready

func get_display_name() -> String:
    """Get display name with host indicator"""
    var display = player_name
    if is_host:
        display += " (Host)"
    return display

func get_status_text() -> String:
    """Get current status as displayable text"""
    if connection_status != "connected":
        return connection_status.capitalize()
    elif is_ready:
        return "Ready"
    else:
        return "Not Ready"

# === GAME FUNCTIONS (for future phases) ===

func reset_game_state():
    """Reset game state for new game"""
    current_gold = 3
    player_base_gold = 3
    bonus_gold = 0
    player_health = 25
    shop_tier = 1
    current_tavern_upgrade_cost = 5
    hand_cards.clear()
    board_minions.clear()
    shop_cards.clear()
    frozen_card_ids.clear()
    is_ready_for_next_phase = false
    has_ended_turn = false

func to_dict() -> Dictionary:
    """Convert player state to dictionary for network transmission"""
    return {
        "player_id": player_id,
        "player_name": player_name,
        "is_host": is_host,
        "is_ready": is_ready,
        "connection_status": connection_status,
        "current_gold": current_gold,
        "player_base_gold": player_base_gold,
        "bonus_gold": bonus_gold,
        "player_health": player_health,
        "shop_tier": shop_tier,
        "current_tavern_upgrade_cost": current_tavern_upgrade_cost,
        "hand_cards": hand_cards,
        "board_minions": board_minions,
        "shop_cards": shop_cards,
        "frozen_card_ids": frozen_card_ids,
        "is_ready_for_next_phase": is_ready_for_next_phase,
        "has_ended_turn": has_ended_turn,
        "ping_ms": ping_ms,
        "current_opponent_id": current_opponent_id,
        "current_opponent_name": current_opponent_name
    }

func from_dict(data: Dictionary):
    """Load player state from dictionary"""
    player_id = data.get("player_id", 0)
    player_name = data.get("player_name", "Player")
    is_host = data.get("is_host", false)
    is_ready = data.get("is_ready", false)
    connection_status = data.get("connection_status", "connected")
    
    # Track if gold/shop changed for signals
    var old_gold = current_gold
    var old_shop = shop_cards.duplicate()
    
    current_gold = data.get("current_gold", 3)
    player_base_gold = data.get("player_base_gold", 3)
    bonus_gold = data.get("bonus_gold", 0)
    player_health = data.get("player_health", 25)
    shop_tier = data.get("shop_tier", 1)
    current_tavern_upgrade_cost = data.get("current_tavern_upgrade_cost", 5)
    hand_cards = data.get("hand_cards", [])
    board_minions = data.get("board_minions", [])
    shop_cards = data.get("shop_cards", [])
    frozen_card_ids = data.get("frozen_card_ids", [])
    is_ready_for_next_phase = data.get("is_ready_for_next_phase", false)
    has_ended_turn = data.get("has_ended_turn", false)
    ping_ms = data.get("ping_ms", 0)
    current_opponent_id = data.get("current_opponent_id", -1)
    current_opponent_name = data.get("current_opponent_name", "")
    
    # In SSOT architecture, NetworkManager handles all display updates
    # No signals emitted here

# === MINION HELPER FUNCTIONS ===

func add_minion_to_board(card_id: String, position: int = -1) -> Dictionary:
    """Add a minion to the board with base stats"""
    var card_data = CardDatabase.get_card_data(card_id)
    if card_data.is_empty():
        return {}
    
    var minion = {
        "card_id": card_id,
        "current_attack": card_data.get("attack", 0),
        "current_health": card_data.get("health", 1)
    }
    
    if position >= 0 and position <= board_minions.size():
        board_minions.insert(position, minion)
    else:
        board_minions.append(minion)
    
    return minion

func remove_minion_from_board(index: int) -> Dictionary:
    """Remove a minion from the board by index"""
    if index >= 0 and index < board_minions.size():
        return board_minions.pop_at(index)
    return {}

func get_minion_at_index(index: int) -> Dictionary:
    """Get minion data at specific board index"""
    if index >= 0 and index < board_minions.size():
        return board_minions[index]
    return {}

func apply_buff_to_minion(index: int, attack_buff: int, health_buff: int):
    """Apply stat buffs to a minion at the given index"""
    if index >= 0 and index < board_minions.size():
        board_minions[index]["current_attack"] += attack_buff
        board_minions[index]["current_health"] += health_buff

func get_board_minion_ids() -> Array:
    """Get array of just the card IDs for compatibility"""
    var ids = []
    for minion in board_minions:
        ids.append(minion.get("card_id", ""))
    return ids

# === DEBUG FUNCTIONS ===

func get_debug_info() -> String:
    """Get debug information about this player"""
    return "Player %d: %s | Host: %s | Ready: %s | Status: %s | Ping: %dms" % [
        player_id, player_name, is_host, is_ready, connection_status, ping_ms
    ] 