# MainMenu.gd
# Main menu scene controller for game mode selection

extends Control

# UI References (will be set in scene)
@onready var player_name_input: LineEdit = $VBoxContainer/PlayerNameContainer/PlayerNameInput
@onready var create_lobby_button: Button = $VBoxContainer/MenuButtons/CreateLobbyButton
@onready var join_lobby_button: Button = $VBoxContainer/MenuButtons/JoinLobbyButton
@onready var practice_button: Button = $VBoxContainer/MenuButtons/PracticeButton
@onready var quit_button: Button = $VBoxContainer/MenuButtons/QuitButton

# Mode descriptions
const PRACTICE_DESCRIPTION = "[b]Practice Mode[/b]\n\nPlay against AI opponents to learn the game mechanics. Perfect for trying new strategies and getting familiar with the cards.\n\n• Single player\n• AI opponents\n• No time pressure\n• Full access to all features"

const MULTIPLAYER_DESCRIPTION = "[b]Multiplayer Mode[/b]\n\nPlay against other human players online. Test your skills in competitive matches.\n\n• Online play\n• Real opponents\n• Host or join games\n• Ready system for coordination\n\n[color=green]Available Now![/color]"

const DEFAULT_DESCRIPTION = "[b]OpenBattlefields[/b]\n\nChoose your game mode to begin playing. Hover over the buttons to learn more about each mode."

func _ready():
    print("MainMenu scene loaded")
    setup_ui()
    connect_signals()
    setup_animations()

func setup_ui():
    """Initialize UI elements and styling"""
    # Setup player name input
    if player_name_input:
        player_name_input.text = SettingsManager.get_player_name()
        player_name_input.text_changed.connect(_on_player_name_changed)
        player_name_input.text_submitted.connect(_on_player_name_submitted)

func setup_animations():
    """Setup visual animations and effects"""
    # Create fade-in animation for the entire menu
    var fade_tween = create_tween()
    modulate.a = 0.0
    fade_tween.tween_property(self, "modulate:a", 1.0, 0.5)

func connect_signals():
    """Connect button signals and hover events"""
    if create_lobby_button:
        create_lobby_button.pressed.connect(_on_create_lobby_button_pressed)
    
    if join_lobby_button:
        join_lobby_button.pressed.connect(_on_join_lobby_button_pressed)
    
    if practice_button:
        practice_button.pressed.connect(_on_practice_button_pressed)
    
    if quit_button:
        quit_button.pressed.connect(_on_quit_button_pressed)

# === BUTTON SIGNAL HANDLERS ===

func _on_create_lobby_button_pressed():
    """Handle host game button press"""
    print("Host game selected")
    # Go to multiplayer lobby as host
    SceneManager.go_to_multiplayer_lobby()

func _on_join_lobby_button_pressed():
    """Handle join game button press"""
    print("Join game selected")
    # Go to multiplayer lobby to join
    SceneManager.go_to_multiplayer_lobby()

func _on_practice_button_pressed():
    """Handle practice mode button press"""
    print("Practice mode selected")
    GameModeManager.select_practice_mode()
    SceneManager.go_to_game_board()

func _on_quit_button_pressed():
    """Handle quit button press"""
    print("Quit game requested")
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


# === UTILITY FUNCTIONS ===

# === INPUT HANDLERS ===

func _input(event):
    """Handle keyboard input"""
    if event.is_action_pressed("ui_cancel"):
        # ESC key exits the game
        _on_quit_button_pressed()
    elif event.is_action_pressed("ui_accept"):
        # Enter key selects practice mode (default)
        if practice_button and not practice_button.disabled:
            _on_practice_button_pressed() 