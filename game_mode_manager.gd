# GameModeManager.gd (Autoload Singleton)
# Manages game mode selection and state for Practice vs Multiplayer

extends Node

# Game Mode Enum
enum GameMode { PRACTICE, MULTIPLAYER }

# Current game mode state
var current_mode: GameMode = GameMode.PRACTICE
var is_host: bool = false
var player_name: String = "Player"

# Signals for mode changes
signal mode_selected(mode: GameMode)
signal game_started()
signal return_to_menu()

func _ready():
    print("GameModeManager initialized")

# === MODE SELECTION FUNCTIONS ===

func select_practice_mode():
    """Select practice mode and emit signal"""
    current_mode = GameMode.PRACTICE
    is_host = false  # Not applicable for practice
    print("Practice mode selected")
    mode_selected.emit(GameMode.PRACTICE)

func select_multiplayer_mode():
    """Select multiplayer mode and emit signal"""
    current_mode = GameMode.MULTIPLAYER
    print("Multiplayer mode selected")
    mode_selected.emit(GameMode.MULTIPLAYER)

func start_game():
    """Signal that the game is starting"""
    print("Game starting in mode: ", GameMode.keys()[current_mode])
    game_started.emit()

func request_return_to_menu():
    """Request return to main menu"""
    print("Returning to main menu")
    return_to_menu.emit()

# === UTILITY FUNCTIONS ===

func is_practice_mode() -> bool:
    """Check if currently in practice mode"""
    return current_mode == GameMode.PRACTICE

func is_multiplayer_mode() -> bool:
    """Check if currently in multiplayer mode"""
    return current_mode == GameMode.MULTIPLAYER

func get_mode_name() -> String:
    """Get human-readable mode name"""
    match current_mode:
        GameMode.PRACTICE:
            return "Practice Mode"
        GameMode.MULTIPLAYER:
            return "Multiplayer Mode"
        _:
            return "Unknown Mode"

# === SETTINGS FUNCTIONS (for future use) ===

func set_player_name(name: String):
    """Set player name"""
    player_name = name.strip_edges()
    if player_name.is_empty():
        player_name = "Player"
    print("Player name set to: ", player_name)

func get_player_name() -> String:
    """Get current player name"""
    return player_name 