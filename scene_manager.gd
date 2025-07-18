# SceneManager.gd (Autoload Singleton)
# Manages scene transitions with fade effects

extends Node

# Scene paths
const MAIN_MENU_SCENE = "res://main_menu.tscn"
const GAME_BOARD_SCENE = "res://game_board.tscn"
const MULTIPLAYER_LOBBY_SCENE = "res://multiplayer_lobby.tscn"  # Future

# Transition state
var is_transitioning: bool = false
var fade_overlay: ColorRect
var transition_tween: Tween

# Transition settings
const FADE_DURATION = 0.3
const FADE_COLOR = Color.BLACK

signal scene_transition_started(scene_path: String)
signal scene_transition_finished(scene_path: String)

func _ready():
    print("SceneManager initialized")
    create_fade_overlay()
    
    # Connect to GameModeManager signals
    GameModeManager.return_to_menu.connect(_on_return_to_menu_requested)

func create_fade_overlay():
    """Create the fade overlay for scene transitions"""
    # Create overlay that covers the entire screen
    fade_overlay = ColorRect.new()
    fade_overlay.name = "SceneTransitionOverlay"
    fade_overlay.color = FADE_COLOR
    fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    
    # Set to cover full screen
    fade_overlay.anchors_preset = Control.PRESET_FULL_RECT
    fade_overlay.visible = false
    
    # Add to a CanvasLayer so it appears above everything
    var canvas_layer = CanvasLayer.new()
    canvas_layer.name = "SceneTransitionLayer"
    canvas_layer.layer = 1000  # Very high layer to ensure it's on top
    canvas_layer.add_child(fade_overlay)
    
    # Add to current scene tree
    add_child(canvas_layer)
    
    print("Scene transition overlay created")

# === SCENE TRANSITION FUNCTIONS ===

func transition_to(scene_path: String):
    """Transition to a new scene with fade effect"""
    if is_transitioning:
        print("SceneManager: Already transitioning, ignoring request")
        return
    
    print("SceneManager: Transitioning to ", scene_path)
    is_transitioning = true
    scene_transition_started.emit(scene_path)
    
    # Start fade out
    fade_overlay.visible = true
    fade_overlay.modulate.a = 0.0
    
    transition_tween = create_tween()
    transition_tween.tween_property(fade_overlay, "modulate:a", 1.0, FADE_DURATION)
    transition_tween.tween_callback(_change_scene.bind(scene_path))
    transition_tween.tween_property(fade_overlay, "modulate:a", 0.0, FADE_DURATION)
    transition_tween.tween_callback(_finish_transition.bind(scene_path))

func _change_scene(scene_path: String):
    """Change to the new scene (called during fade)"""
    print("SceneManager: Loading scene ", scene_path)
    var error = get_tree().change_scene_to_file(scene_path)
    if error != OK:
        print("SceneManager: Error loading scene ", scene_path, " - Error: ", error)

func _finish_transition(scene_path: String):
    """Finish the transition (called after fade in)"""
    fade_overlay.visible = false
    is_transitioning = false
    scene_transition_finished.emit(scene_path)
    print("SceneManager: Transition to ", scene_path, " completed")

# === CONVENIENCE FUNCTIONS ===

func go_to_main_menu():
    """Transition to main menu"""
    transition_to(MAIN_MENU_SCENE)

func go_to_game_board():
    """Transition to game board"""
    # Log session info for debugging
    if GameModeManager.is_in_multiplayer_session():
        print("SceneManager: Transitioning to multiplayer game - Session: ", GameModeManager.get_session_id())
    else:
        print("SceneManager: Transitioning to practice game")
    
    transition_to(GAME_BOARD_SCENE)

func go_to_multiplayer_lobby():
    """Transition to multiplayer lobby"""
    transition_to(MULTIPLAYER_LOBBY_SCENE)

# === SIGNAL HANDLERS ===

func _on_return_to_menu_requested():
    """Handle return to menu request from GameModeManager"""
    # Clean up multiplayer session if active
    if GameModeManager.is_in_multiplayer_session():
        GameModeManager.end_multiplayer_session()
    go_to_main_menu()

# === UTILITY FUNCTIONS ===

func get_current_scene_name() -> String:
    """Get the name of the current scene"""
    var current_scene = get_tree().current_scene
    if current_scene:
        return current_scene.scene_file_path.get_file().get_basename()
    return "unknown"

func is_in_game() -> bool:
    """Check if currently in a game scene (not menu)"""
    var scene_name = get_current_scene_name()
    return scene_name == "game_board" or scene_name == "multiplayer_lobby" 