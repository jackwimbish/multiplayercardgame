# MainMenu.gd
# Main menu scene controller for game mode selection

extends Control

# UI References (will be set in scene)
@onready var game_title: Label = $VBoxContainer/TitleContainer/GameTitle
@onready var player_name_input: LineEdit = $VBoxContainer/PlayerNameContainer/PlayerNameInput
@onready var practice_button: Button = $VBoxContainer/ModeSelection/PracticeButton
@onready var multiplayer_button: Button = $VBoxContainer/ModeSelection/MultiplayerButton
@onready var exit_button: Button = $VBoxContainer/ModeSelection/ExitButton
@onready var mode_description: RichTextLabel = $VBoxContainer/InfoPanel/ModeDescription

# Mode descriptions
const PRACTICE_DESCRIPTION = "[b]Practice Mode[/b]\n\nPlay against AI opponents to learn the game mechanics. Perfect for trying new strategies and getting familiar with the cards.\n\n• Single player\n• AI opponents\n• No time pressure\n• Full access to all features"

const MULTIPLAYER_DESCRIPTION = "[b]Multiplayer Mode[/b]\n\nPlay against other human players online. Test your skills in competitive matches.\n\n• Online play\n• Real opponents\n• Host or join games\n• Ready system for coordination\n\n[color=green]Available Now![/color]"

const DEFAULT_DESCRIPTION = "[b]OpenBattlefields[/b]\n\nChoose your game mode to begin playing. Hover over the buttons to learn more about each mode."

func _ready():
    print("MainMenu scene loaded")
    setup_ui()
    connect_signals()
    setup_animations()
    
    # Set initial description
    if mode_description:
        mode_description.text = DEFAULT_DESCRIPTION

func setup_ui():
    """Initialize UI elements and styling"""
    # Set game title
    if game_title:
        game_title.text = "OpenBattlefields"
    
    # Setup player name input
    if player_name_input:
        player_name_input.text = SettingsManager.get_player_name()
        player_name_input.text_changed.connect(_on_player_name_changed)
        player_name_input.text_submitted.connect(_on_player_name_submitted)
    
    # Configure buttons
    if practice_button:
        practice_button.text = "Practice Mode"
    
    if multiplayer_button:
        multiplayer_button.text = "Multiplayer Mode"
        # Enable multiplayer - Phase 1 implementation ready
        multiplayer_button.disabled = false
        multiplayer_button.tooltip_text = "Play against other players online!"
    
    if exit_button:
        exit_button.text = "Exit Game"

func setup_animations():
    """Setup visual animations and effects"""
    # Create fade-in animation for the entire menu
    var fade_tween = create_tween()
    modulate.a = 0.0
    fade_tween.tween_property(self, "modulate:a", 1.0, 0.5)
    
    # Animate title with a slight bounce
    if game_title:
        var title_tween = create_tween()
        game_title.scale = Vector2(0.8, 0.8)
        title_tween.tween_property(game_title, "scale", Vector2(1.0, 1.0), 0.6)
        title_tween.set_ease(Tween.EASE_OUT)
        title_tween.set_trans(Tween.TRANS_BACK)

func connect_signals():
    """Connect button signals and hover events"""
    if practice_button:
        practice_button.pressed.connect(_on_practice_button_pressed)
        practice_button.mouse_entered.connect(_on_practice_button_hover)
        practice_button.mouse_exited.connect(_on_button_hover_exit)
    
    if multiplayer_button:
        multiplayer_button.pressed.connect(_on_multiplayer_button_pressed)
        multiplayer_button.mouse_entered.connect(_on_multiplayer_button_hover)
        multiplayer_button.mouse_exited.connect(_on_button_hover_exit)
    
    if exit_button:
        exit_button.pressed.connect(_on_exit_button_pressed)
        exit_button.mouse_entered.connect(_on_exit_button_hover)
        exit_button.mouse_exited.connect(_on_button_hover_exit)

# === BUTTON SIGNAL HANDLERS ===

func _on_practice_button_pressed():
    """Handle practice mode button press"""
    print("Practice mode selected")
    GameModeManager.select_practice_mode()
    SceneManager.go_to_game_board()

func _on_multiplayer_button_pressed():
    """Handle multiplayer mode button press"""
    print("Multiplayer mode selected")
    # Go directly to multiplayer lobby
    SceneManager.go_to_multiplayer_lobby()

func _on_exit_button_pressed():
    """Handle exit button press"""
    print("Exit game requested")
    get_tree().quit()

# === PLAYER NAME HANDLERS ===

func _on_player_name_changed(new_text: String):
    """Handle player name text changes"""
    # Update SettingsManager with new name (persisted to file)
    SettingsManager.set_player_name(new_text)
    # Also update GameModeManager for current session
    GameModeManager.set_player_name(new_text)

func _on_player_name_submitted(text: String):
    """Handle when player presses Enter in name field"""
    # Automatically start practice mode when name is submitted
    if practice_button and not practice_button.disabled:
        _on_practice_button_pressed()

# === HOVER HANDLERS ===

func _on_practice_button_hover():
    """Show practice mode description on hover"""
    _animate_button_hover(practice_button, true)
    if mode_description:
        mode_description.text = PRACTICE_DESCRIPTION

func _on_multiplayer_button_hover():
    """Show multiplayer mode description on hover"""
    _animate_button_hover(multiplayer_button, true)
    if mode_description:
        mode_description.text = MULTIPLAYER_DESCRIPTION

func _on_exit_button_hover():
    """Show exit description on hover"""
    _animate_button_hover(exit_button, true)
    if mode_description:
        mode_description.text = "[b]Exit Game[/b]\n\nClose the application and return to your desktop."

func _on_button_hover_exit():
    """Reset description when mouse leaves buttons"""
    # Animate all buttons back to normal
    if practice_button:
        _animate_button_hover(practice_button, false)
    if multiplayer_button:
        _animate_button_hover(multiplayer_button, false)
    if exit_button:
        _animate_button_hover(exit_button, false)
    
    if mode_description:
        mode_description.text = DEFAULT_DESCRIPTION

func _animate_button_hover(button: Button, is_hovered: bool):
    """Animate button on hover/unhover"""
    if not button:
        return
    
    var target_scale = Vector2(1.05, 1.05) if is_hovered else Vector2(1.0, 1.0)
    var target_modulate = Color(1.2, 1.2, 1.2, 1.0) if is_hovered else Color.WHITE
    
    var tween = create_tween()
    tween.set_parallel(true)
    tween.tween_property(button, "scale", target_scale, 0.1)
    tween.tween_property(button, "modulate", target_modulate, 0.1)

# === UTILITY FUNCTIONS ===

func show_welcome_message():
    """Show a welcome message (can be called from other scenes)"""
    if mode_description:
        mode_description.text = "[b]Welcome back![/b]\n\nChoose your preferred game mode to continue playing."

# === INPUT HANDLERS ===

func _input(event):
    """Handle keyboard input"""
    if event.is_action_pressed("ui_cancel"):
        # ESC key exits the game
        _on_exit_button_pressed()
    elif event.is_action_pressed("ui_accept"):
        # Enter key selects practice mode (default)
        if practice_button and not practice_button.disabled:
            _on_practice_button_pressed() 