# PlayerState.gd
# Class representing a player's state in multiplayer games

class_name PlayerState
extends RefCounted

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
var board_minions: Array = []  # Array of card IDs  
var shop_cards: Array = []  # Array of card IDs in player's shop

# Turn state
var is_ready_for_next_phase: bool = false
var has_ended_turn: bool = false

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
        "is_ready_for_next_phase": is_ready_for_next_phase,
        "has_ended_turn": has_ended_turn,
        "ping_ms": ping_ms
    }

func from_dict(data: Dictionary):
    """Load player state from dictionary"""
    player_id = data.get("player_id", 0)
    player_name = data.get("player_name", "Player")
    is_host = data.get("is_host", false)
    is_ready = data.get("is_ready", false)
    connection_status = data.get("connection_status", "connected")
    current_gold = data.get("current_gold", 3)
    player_base_gold = data.get("player_base_gold", 3)
    bonus_gold = data.get("bonus_gold", 0)
    player_health = data.get("player_health", 25)
    shop_tier = data.get("shop_tier", 1)
    current_tavern_upgrade_cost = data.get("current_tavern_upgrade_cost", 5)
    hand_cards = data.get("hand_cards", [])
    board_minions = data.get("board_minions", [])
    shop_cards = data.get("shop_cards", [])
    is_ready_for_next_phase = data.get("is_ready_for_next_phase", false)
    has_ended_turn = data.get("has_ended_turn", false)
    ping_ms = data.get("ping_ms", 0)

# === DEBUG FUNCTIONS ===

func get_debug_info() -> String:
    """Get debug information about this player"""
    return "Player %d: %s | Host: %s | Ready: %s | Status: %s | Ping: %dms" % [
        player_id, player_name, is_host, is_ready, connection_status, ping_ms
    ] 