# MultiplayerLobby.gd
# Full multiplayer lobby implementation with host/join functionality

extends Control

# UI State
enum LobbyState { MENU, HOST_SETUP, JOIN_SETUP, WAITING, CONNECTED }
var current_state: LobbyState = LobbyState.MENU

# UI References - Main containers
@onready var main_container: VBoxContainer = $MainContainer
@onready var title_label: Label = $MainContainer/TitleLabel

# Mode selection
@onready var mode_selection: HBoxContainer = $MainContainer/ModeSelection
@onready var host_button: Button = $MainContainer/ModeSelection/HostButton
@onready var join_button: Button = $MainContainer/ModeSelection/JoinButton

# Connection setup
@onready var connection_container: VBoxContainer = $MainContainer/ConnectionContainer
@onready var connection_title: Label = $MainContainer/ConnectionContainer/ConnectionTitle

# Host setup
@onready var host_container: VBoxContainer = $MainContainer/ConnectionContainer/HostContainer
@onready var port_input: SpinBox = $MainContainer/ConnectionContainer/HostContainer/PortContainer/PortInput
@onready var create_host_button: Button = $MainContainer/ConnectionContainer/HostContainer/CreateHostButton

# Join setup
@onready var join_container: VBoxContainer = $MainContainer/ConnectionContainer/JoinContainer
@onready var ip_input: LineEdit = $MainContainer/ConnectionContainer/JoinContainer/IPContainer/IPInput
@onready var join_port_input: SpinBox = $MainContainer/ConnectionContainer/JoinContainer/JoinPortContainer/JoinPortInput
@onready var connect_button: Button = $MainContainer/ConnectionContainer/JoinContainer/ConnectButton

# Status and players
@onready var status_container: VBoxContainer = $MainContainer/StatusContainer
@onready var status_label: Label = $MainContainer/StatusContainer/StatusLabel
@onready var players_container: VBoxContainer = $MainContainer/PlayersContainer
@onready var players_title: Label = $MainContainer/PlayersContainer/PlayersTitle
@onready var players_list: VBoxContainer = $MainContainer/PlayersContainer/PlayersList

# Game controls
@onready var game_controls: HBoxContainer = $MainContainer/GameControls
@onready var ready_button: Button = $MainContainer/GameControls/ReadyButton
@onready var start_game_button: Button = $MainContainer/GameControls/StartGameButton

# Navigation
@onready var back_container: HBoxContainer = $MainContainer/BackContainer
@onready var disconnect_button: Button = $MainContainer/BackContainer/DisconnectButton
@onready var back_button: Button = $MainContainer/BackContainer/BackButton

# Player UI elements (created dynamically)
var player_ui_elements: Dictionary = {}  # player_id -> UI node

func _ready():
    print("Multiplayer Lobby loaded")
    setup_ui()
    connect_signals()
    load_network_settings()
    set_lobby_state(LobbyState.MENU)

func setup_ui():
    """Initialize UI elements"""
    # Set up default values
    if port_input:
        port_input.value = NetworkManager.DEFAULT_PORT
    if join_port_input:
        join_port_input.value = NetworkManager.DEFAULT_PORT
    
    # Set up IP input with last used or localhost
    if ip_input:
        var last_ip = SettingsManager.get_setting("network", "last_host_ip", "127.0.0.1")
        ip_input.text = last_ip

func connect_signals():
    """Connect all UI signals and NetworkManager signals"""
    # Mode selection buttons
    if host_button:
        host_button.pressed.connect(_on_host_button_pressed)
    if join_button:
        join_button.pressed.connect(_on_join_button_pressed)
    
    # Connection buttons
    if create_host_button:
        create_host_button.pressed.connect(_on_create_host_button_pressed)
    if connect_button:
        connect_button.pressed.connect(_on_connect_button_pressed)
    
    # Game control buttons
    if ready_button:
        ready_button.pressed.connect(_on_ready_button_pressed)
    if start_game_button:
        start_game_button.pressed.connect(_on_start_game_button_pressed)
    
    # Navigation buttons
    if disconnect_button:
        disconnect_button.pressed.connect(_on_disconnect_button_pressed)
    if back_button:
        back_button.pressed.connect(_on_back_button_pressed)
    
    # NetworkManager signals
    NetworkManager.player_joined.connect(_on_player_joined)
    NetworkManager.player_left.connect(_on_player_left)
    NetworkManager.player_ready_changed.connect(_on_player_ready_changed)
    NetworkManager.connection_failed.connect(_on_connection_failed)
    NetworkManager.connection_lost.connect(_on_connection_lost)
    NetworkManager.game_start_requested.connect(_on_game_start_requested)
    NetworkManager.network_error.connect(_on_network_error)

func load_network_settings():
    """Load saved network preferences"""
    var last_port = SettingsManager.get_setting("network", "last_port", NetworkManager.DEFAULT_PORT)
    if port_input:
        port_input.value = last_port
    if join_port_input:
        join_port_input.value = last_port

# === UI STATE MANAGEMENT ===

func set_lobby_state(state: LobbyState):
    """Set the lobby UI state and show/hide appropriate containers"""
    current_state = state
    
    # Hide all optional containers first
    mode_selection.visible = false
    connection_container.visible = false
    status_container.visible = false
    players_container.visible = false
    game_controls.visible = false
    disconnect_button.visible = false
    
    # Show containers based on state
    match state:
        LobbyState.MENU:
            mode_selection.visible = true
            title_label.text = "Multiplayer Lobby"
            
        LobbyState.HOST_SETUP:
            connection_container.visible = true
            host_container.visible = true
            join_container.visible = false
            connection_title.text = "Host Game Setup"
            title_label.text = "Host Game"
            
        LobbyState.JOIN_SETUP:
            connection_container.visible = true
            host_container.visible = false
            join_container.visible = true
            connection_title.text = "Join Game Setup"
            title_label.text = "Join Game"
            
        LobbyState.WAITING:
            status_container.visible = true
            disconnect_button.visible = true
            title_label.text = "Connecting..."
            
        LobbyState.CONNECTED:
            players_container.visible = true
            game_controls.visible = true
            disconnect_button.visible = true
            title_label.text = "Multiplayer Lobby"
            update_game_controls()

func update_status(message: String, color: Color = Color.WHITE):
    """Update status label with message and color"""
    if status_label:
        status_label.text = "Status: " + message
        status_label.add_theme_color_override("font_color", color)

# === BUTTON HANDLERS ===

func _on_host_button_pressed():
    """Handle host game button press"""
    print("Host game selected")
    set_lobby_state(LobbyState.HOST_SETUP)

func _on_join_button_pressed():
    """Handle join game button press"""
    print("Join game selected")
    set_lobby_state(LobbyState.JOIN_SETUP)

func _on_create_host_button_pressed():
    """Handle create host button press"""
    var port = int(port_input.value)
    print("Creating host on port: ", port)
    
    set_lobby_state(LobbyState.WAITING)
    update_status("Creating host game...", Color.YELLOW)
    
    # Save port preference
    SettingsManager.set_setting("network", "last_port", port)
    
    # Create host game
    var success = NetworkManager.create_host_game(port)
    if success:
        set_lobby_state(LobbyState.CONNECTED)
        update_status("Hosting game on port %d - Waiting for players..." % port, Color.GREEN)
    else:
        set_lobby_state(LobbyState.HOST_SETUP)

func _on_connect_button_pressed():
    """Handle connect button press"""
    var host_ip = ip_input.text.strip_edges()
    var port = int(join_port_input.value)
    print("Connecting to: ", host_ip, ":", port)
    
    if host_ip.is_empty():
        update_status("Please enter a host IP address", Color.RED)
        return
    
    set_lobby_state(LobbyState.WAITING)
    update_status("Connecting to %s:%d..." % [host_ip, port], Color.YELLOW)
    
    # Save connection preferences
    SettingsManager.set_setting("network", "last_host_ip", host_ip)
    SettingsManager.set_setting("network", "last_port", port)
    
    # Attempt to join game
    var success = NetworkManager.join_game(host_ip, port)
    if not success:
        set_lobby_state(LobbyState.JOIN_SETUP)

func _on_ready_button_pressed():
    """Handle ready button press"""
    if NetworkManager.get_local_player():
        var current_ready = NetworkManager.get_local_player().is_ready
        NetworkManager.set_local_player_ready(not current_ready)
        update_game_controls()

func _on_start_game_button_pressed():
    """Handle start game button press (host only)"""
    print("Starting multiplayer game!")
    
    # Start the game locally for the host
    _start_game_locally()
    
    # Tell the client to start too
    NetworkManager.request_game_start.rpc()

func _start_game_locally():
    """Start the game for the local player"""
    print("Starting game locally")
    # Set multiplayer mode in GameModeManager
    GameModeManager.select_multiplayer_mode()
    # Transition to game board
    SceneManager.go_to_game_board()

func _on_disconnect_button_pressed():
    """Handle disconnect button press"""
    print("Disconnecting from multiplayer session")
    
    if NetworkManager.is_host:
        NetworkManager.close_host_game()
    else:
        NetworkManager.disconnect_from_game()
    
    set_lobby_state(LobbyState.MENU)
    clear_players_list()

func _on_back_button_pressed():
    """Handle back to menu button press"""
    # Disconnect if connected
    if current_state == LobbyState.CONNECTED or current_state == LobbyState.WAITING:
        _on_disconnect_button_pressed()
    
    SceneManager.go_to_main_menu()

# === NETWORK EVENT HANDLERS ===

func _on_player_joined(player_id: int, player_name: String):
    """Handle when a player joins the lobby"""
    print("Player joined lobby: ", player_name, " (ID: ", player_id, ")")
    update_players_list()
    
    if current_state == LobbyState.WAITING:
        set_lobby_state(LobbyState.CONNECTED)
    
    update_status("Player joined: %s" % player_name, Color.GREEN)

func _on_player_left(player_id: int, player_name: String):
    """Handle when a player leaves the lobby"""
    print("Player left lobby: ", player_name, " (ID: ", player_id, ")")
    update_players_list()
    update_game_controls()
    update_status("Player left: %s" % player_name, Color.ORANGE)

func _on_player_ready_changed(player_id: int, is_ready: bool):
    """Handle when a player's ready state changes"""
    print("Player ", player_id, " ready state: ", is_ready)
    update_players_list()
    update_game_controls()

func _on_connection_failed(reason: String):
    """Handle when connection fails"""
    print("Connection failed: ", reason)
    update_status("Connection failed: %s" % reason, Color.RED)
    set_lobby_state(LobbyState.JOIN_SETUP)

func _on_connection_lost():
    """Handle when connection is lost"""
    print("Connection lost")
    update_status("Connection lost", Color.RED)
    set_lobby_state(LobbyState.MENU)
    clear_players_list()

func _on_game_start_requested():
    """Handle when host requests game start"""
    print("Game start requested - transitioning to game")
    # Set multiplayer mode in GameModeManager
    GameModeManager.select_multiplayer_mode()
    # Transition to game board
    SceneManager.go_to_game_board()

func _on_network_error(message: String):
    """Handle network errors"""
    print("Network error: ", message)
    update_status("Error: %s" % message, Color.RED)

# === PLAYER LIST MANAGEMENT ===

func update_players_list():
    """Update the display of connected players"""
    clear_players_list()
    
    var connected_players = NetworkManager.get_connected_players()
    for player in connected_players.values():
        create_player_ui_element(player)

func clear_players_list():
    """Clear all player UI elements"""
    if players_list:
        for child in players_list.get_children():
            child.queue_free()
    player_ui_elements.clear()

func create_player_ui_element(player: PlayerState):
    """Create UI element for a player"""
    var player_container = HBoxContainer.new()
    player_container.name = "Player" + str(player.player_id)
    
    # Player name label
    var name_label = Label.new()
    name_label.text = player.get_display_name()
    name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    name_label.add_theme_font_size_override("font_size", 18)
    
    # Ready status label
    var status_label = Label.new()
    status_label.text = player.get_status_text()
    status_label.add_theme_font_size_override("font_size", 16)
    
    # Color code the status
    if player.is_ready:
        status_label.add_theme_color_override("font_color", Color.GREEN)
    else:
        status_label.add_theme_color_override("font_color", Color.ORANGE)
    
    player_container.add_child(name_label)
    player_container.add_child(status_label)
    
    players_list.add_child(player_container)
    player_ui_elements[player.player_id] = player_container

func update_game_controls():
    """Update ready button and start game button states"""
    if not ready_button or not start_game_button:
        return
    
    var local_player = NetworkManager.get_local_player()
    if local_player:
        # Update ready button text
        if local_player.is_ready:
            ready_button.text = "Not Ready"
            ready_button.add_theme_color_override("font_color", Color.ORANGE)
        else:
            ready_button.text = "Ready"
            ready_button.add_theme_color_override("font_color", Color.GREEN)
    
    # Update start game button (host only)
    if NetworkManager.is_host:
        start_game_button.visible = true
        start_game_button.disabled = not NetworkManager.can_start_game()
        
        if NetworkManager.can_start_game():
            start_game_button.text = "Start Game"
            start_game_button.add_theme_color_override("font_color", Color.GREEN)
        else:
            start_game_button.text = "Waiting for Players..."
            start_game_button.add_theme_color_override("font_color", Color.GRAY)
    else:
        start_game_button.visible = false

# === INPUT HANDLING ===

func _input(event):
    """Handle keyboard input"""
    if event.is_action_pressed("ui_cancel"):
        # ESC key goes back
        _on_back_button_pressed()
    elif event.is_action_pressed("ui_accept"):
        # Enter key shortcuts
        match current_state:
            LobbyState.HOST_SETUP:
                _on_create_host_button_pressed()
            LobbyState.JOIN_SETUP:
                _on_connect_button_pressed()
            LobbyState.CONNECTED:
                if NetworkManager.is_host and NetworkManager.can_start_game():
                    _on_start_game_button_pressed()
                else:
                    _on_ready_button_pressed()

# === UTILITY FUNCTIONS ===

func get_lobby_info() -> String:
    """Get current lobby information for debugging"""
    var info = "Multiplayer Lobby Info:\n"
    info += "  State: %s\n" % LobbyState.keys()[current_state]
    info += "  Connected Players: %d\n" % NetworkManager.get_player_count()
    info += "  Is Host: %s\n" % NetworkManager.is_host
    info += "  Can Start Game: %s\n" % NetworkManager.can_start_game()
    return info 