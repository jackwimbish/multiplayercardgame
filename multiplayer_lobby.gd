# MultiplayerLobby.gd
# Placeholder scene for future multiplayer implementation

extends Control

# UI References
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var back_button: Button = $VBoxContainer/BackButton

func _ready():
    print("Multiplayer Lobby loaded (placeholder)")
    setup_ui()

func setup_ui():
    """Setup placeholder UI"""
    if status_label:
        status_label.text = "Multiplayer Lobby\n\n[Coming Soon]\n\nMultiplayer functionality will be implemented in Phase 3."
    
    if back_button:
        back_button.text = "Back to Menu"
        back_button.pressed.connect(_on_back_button_pressed)

func _on_back_button_pressed():
    """Return to main menu"""
    SceneManager.go_to_main_menu()

# Future multiplayer functions will be implemented here:
# - Player lobbies
# - Matchmaking
# - Network synchronization
# - Room management 