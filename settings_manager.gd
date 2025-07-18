# SettingsManager.gd (Autoload Singleton)
# Manages game settings persistence and player preferences

extends Node

# Settings file path
const SETTINGS_FILE = "user://game_settings.cfg"

# Default settings
const DEFAULT_PLAYER_NAME = "Player"
const DEFAULT_PREFERRED_MODE = GameModeManager.GameMode.PRACTICE

# Current settings
var settings_data: Dictionary = {}

signal settings_loaded()
signal settings_saved()

func _ready():
    print("SettingsManager initialized")
    load_settings()

# === SETTINGS PERSISTENCE ===

func load_settings():
    """Load settings from file"""
    var config = ConfigFile.new()
    var error = config.load(SETTINGS_FILE)
    
    if error == OK:
        # Load existing settings
        settings_data = {
            "player_name": config.get_value("player", "name", DEFAULT_PLAYER_NAME),
            "preferred_mode": config.get_value("game", "preferred_mode", DEFAULT_PREFERRED_MODE),
            "window_fullscreen": config.get_value("display", "fullscreen", false),
            "master_volume": config.get_value("audio", "master_volume", 1.0),
            "music_volume": config.get_value("audio", "music_volume", 0.7),
            "sfx_volume": config.get_value("audio", "sfx_volume", 0.8)
        }
        print("Settings loaded from file")
    else:
        # Use default settings
        settings_data = {
            "player_name": DEFAULT_PLAYER_NAME,
            "preferred_mode": DEFAULT_PREFERRED_MODE,
            "window_fullscreen": false,
            "master_volume": 1.0,
            "music_volume": 0.7,
            "sfx_volume": 0.8
        }
        print("Using default settings (file not found or corrupted)")
    
    # Apply loaded settings
    apply_settings()
    settings_loaded.emit()

func save_settings():
    """Save current settings to file"""
    var config = ConfigFile.new()
    
    # Save player settings
    config.set_value("player", "name", settings_data.get("player_name", DEFAULT_PLAYER_NAME))
    
    # Save game settings
    config.set_value("game", "preferred_mode", settings_data.get("preferred_mode", DEFAULT_PREFERRED_MODE))
    
    # Save display settings
    config.set_value("display", "fullscreen", settings_data.get("window_fullscreen", false))
    
    # Save audio settings
    config.set_value("audio", "master_volume", settings_data.get("master_volume", 1.0))
    config.set_value("audio", "music_volume", settings_data.get("music_volume", 0.7))
    config.set_value("audio", "sfx_volume", settings_data.get("sfx_volume", 0.8))
    
    # Write to file
    var error = config.save(SETTINGS_FILE)
    if error == OK:
        print("Settings saved successfully")
        settings_saved.emit()
    else:
        print("Error saving settings: ", error)

func apply_settings():
    """Apply current settings to the game"""
    # Apply player name to GameModeManager
    var player_name = settings_data.get("player_name", DEFAULT_PLAYER_NAME)
    GameModeManager.set_player_name(player_name)
    
    # Apply display settings
    var fullscreen = settings_data.get("window_fullscreen", false)
    if fullscreen:
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
    else:
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
    
    print("Settings applied")

# === GETTERS AND SETTERS ===

func get_player_name() -> String:
    """Get saved player name"""
    return settings_data.get("player_name", DEFAULT_PLAYER_NAME)

func set_player_name(name: String):
    """Set and save player name"""
    settings_data["player_name"] = name.strip_edges()
    if settings_data["player_name"].is_empty():
        settings_data["player_name"] = DEFAULT_PLAYER_NAME
    save_settings()

func get_preferred_mode() -> GameModeManager.GameMode:
    """Get saved preferred game mode"""
    return settings_data.get("preferred_mode", DEFAULT_PREFERRED_MODE)

func set_preferred_mode(mode: GameModeManager.GameMode):
    """Set and save preferred game mode"""
    settings_data["preferred_mode"] = mode
    save_settings()

func get_master_volume() -> float:
    """Get master volume setting"""
    return settings_data.get("master_volume", 1.0)

func set_master_volume(volume: float):
    """Set and save master volume"""
    settings_data["master_volume"] = clamp(volume, 0.0, 1.0)
    # Apply to audio system
    AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(settings_data["master_volume"]))
    save_settings()

func get_music_volume() -> float:
    """Get music volume setting"""
    return settings_data.get("music_volume", 0.7)

func set_music_volume(volume: float):
    """Set and save music volume"""
    settings_data["music_volume"] = clamp(volume, 0.0, 1.0)
    # Apply to music bus (if it exists)
    var music_bus = AudioServer.get_bus_index("Music")
    if music_bus != -1:
        AudioServer.set_bus_volume_db(music_bus, linear_to_db(settings_data["music_volume"]))
    save_settings()

func get_sfx_volume() -> float:
    """Get SFX volume setting"""
    return settings_data.get("sfx_volume", 0.8)

func set_sfx_volume(volume: float):
    """Set and save SFX volume"""
    settings_data["sfx_volume"] = clamp(volume, 0.0, 1.0)
    # Apply to SFX bus (if it exists)
    var sfx_bus = AudioServer.get_bus_index("SFX")
    if sfx_bus != -1:
        AudioServer.set_bus_volume_db(sfx_bus, linear_to_db(settings_data["sfx_volume"]))
    save_settings()

func is_fullscreen() -> bool:
    """Check if fullscreen is enabled"""
    return settings_data.get("window_fullscreen", false)

func set_fullscreen(enabled: bool):
    """Set and save fullscreen setting"""
    settings_data["window_fullscreen"] = enabled
    if enabled:
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
    else:
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
    save_settings()

# === UTILITY FUNCTIONS ===

func reset_to_defaults():
    """Reset all settings to default values"""
    settings_data = {
        "player_name": DEFAULT_PLAYER_NAME,
        "preferred_mode": DEFAULT_PREFERRED_MODE,
        "window_fullscreen": false,
        "master_volume": 1.0,
        "music_volume": 0.7,
        "sfx_volume": 0.8
    }
    apply_settings()
    save_settings()
    print("Settings reset to defaults")

func get_settings_summary() -> String:
    """Get a summary of current settings for debugging"""
    return "Player: %s | Mode: %s | Fullscreen: %s | Audio: %0.1f/%0.1f/%0.1f" % [
        get_player_name(),
        GameModeManager.GameMode.keys()[get_preferred_mode()],
        is_fullscreen(),
        get_master_volume(),
        get_music_volume(),
        get_sfx_volume()
    ] 