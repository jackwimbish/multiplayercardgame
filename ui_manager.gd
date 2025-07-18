# UIManager.gd
# Manages all UI elements and updates for the game board
extends Control
class_name UIManager

# UI Font sizes (moved from game_board.gd)
const UI_FONT_SIZE_LARGE = 24    # Main labels, important text
const UI_FONT_SIZE_MEDIUM = 20   # Secondary labels, buttons
const UI_FONT_SIZE_SMALL = 16    # Supporting text

# UI Node References (using @onready for direct access)
@onready var gold_label = $TopUI/GoldLabel
@onready var turn_label = $TopUI/TurnLabel
@onready var shop_tier_label = $TopUI/ShopTierLabel
@onready var upgrade_button = $TopUI/UpgradeShopButton
@onready var refresh_button = $TopUI/RefreshShopButton
@onready var freeze_button = $TopUI/FreezeButton
@onready var end_turn_button = $TopUI/EndTurnButton
@onready var shop_area = $ShopArea
@onready var shop_area_label = $ShopArea/ShopAreaLabel
@onready var player_board = $PlayerBoard
@onready var player_board_label = $PlayerBoard/PlayerBoardLabel
@onready var player_hand = $PlayerHand
@onready var player_hand_label = $PlayerHand/PlayerHandLabel

# Combat UI references (will be created dynamically)
var player_health_label: Label
var enemy_health_label: Label
var combat_log_display: RichTextLabel
var enemy_board_selector: OptionButton
var start_combat_button: Button
var combat_ui_container: VBoxContainer
var return_to_shop_button: Button
var combat_view_toggle_button: Button

# Game limits for UI display
var max_hand_size: int = 10
var max_board_size: int = 7

func _ready():
    print("UIManager initialized")
    setup_ui()
    connect_gamestate_signals()

func setup_ui():
    """Initialize all UI elements and styling"""
    apply_ui_font_sizing()
    create_combat_ui()
    populate_enemy_board_selector()
    connect_combat_ui_signals()
    connect_shop_ui_signals()
    
    # Hide End Turn button - turns now advance automatically after combat
    if end_turn_button:
        end_turn_button.visible = false
    
    update_all_displays()

func connect_gamestate_signals():
    """Connect to GameState signals for automatic UI updates"""
    GameState.turn_changed.connect(update_turn_display)
    GameState.turn_changed.connect(_on_turn_changed)  # Update upgrade cost on turn change
    GameState.gold_changed.connect(update_gold_display)
    GameState.shop_tier_changed.connect(update_shop_tier_display)
    GameState.player_health_changed.connect(update_health_displays)
    GameState.enemy_health_changed.connect(update_health_displays)
    GameState.game_over.connect(_on_game_over)

# === UI UPDATE FUNCTIONS ===

func update_all_displays():
    """Update all UI elements to reflect current game state"""
    update_turn_display(GameState.current_turn)
    update_gold_display(GameState.current_gold, GameState.GLOBAL_GOLD_MAX)
    update_shop_tier_display(GameState.shop_tier)
    update_hand_display()
    update_board_display()
    update_health_displays()

func update_turn_display(new_turn: int):
    """Update turn label"""
    if turn_label:
        turn_label.text = "Turn: " + str(new_turn)

func _on_turn_changed(new_turn: int):
    """Handle turn change to update upgrade button cost"""
    # Update the upgrade button cost since it decreases each turn
    if upgrade_button:
        var upgrade_cost = GameState.calculate_tavern_upgrade_cost()
        if upgrade_cost > 0:
            upgrade_button.text = "Upgrade Shop (" + str(upgrade_cost) + " gold)"
        else:
            upgrade_button.text = "Max Tier"

func update_gold_display(new_gold: int, max_gold: int):
    """Update gold label with current/base gold and bonus"""
    if gold_label:
        var gold_text = "Gold: " + str(new_gold) + "/" + str(GameState.player_base_gold)
        if GameState.bonus_gold > 0:
            gold_text += " (+" + str(GameState.bonus_gold) + ")"
        gold_label.text = gold_text

func update_shop_tier_display(new_tier: int):
    """Update shop tier label and upgrade button"""
    if shop_tier_label:
        shop_tier_label.text = "Shop Tier: " + str(new_tier)
    
    if upgrade_button:
        var upgrade_cost = GameState.calculate_tavern_upgrade_cost()
        if upgrade_cost > 0:
            upgrade_button.text = "Upgrade Shop (" + str(upgrade_cost) + " gold)"
        else:
            upgrade_button.text = "Max Tier"

func update_hand_display():
    """Update hand count display"""
    if player_hand_label:
        var hand_size = get_hand_size()
        player_hand_label.text = "Your Hand (" + str(hand_size) + "/" + str(max_hand_size) + ")"

func update_board_display():
    """Update board count display"""
    if player_board_label:
        var board_size = get_board_size()
        player_board_label.text = "Your Board (" + str(board_size) + "/" + str(max_board_size) + ")"

func update_health_displays(new_health: int = -1):
    """Update health display labels (parameter ignored, we read from GameState)"""
    print("UIManager updating health displays - Player: %d, Enemy: %d" % [GameState.player_health, GameState.enemy_health])
    if player_health_label:
        player_health_label.text = "Player Health: %d" % GameState.player_health
        print("Updated player health label to: ", player_health_label.text)
        
    if enemy_health_label:
        enemy_health_label.text = "Enemy Health: %d" % GameState.enemy_health
        print("Updated enemy health label to: ", enemy_health_label.text)

func _on_game_over(winner: String):
    """Handle game over UI updates"""
    print("Game Over! Winner: ", winner)

# === FONT MANAGEMENT ===

func apply_ui_font_sizing() -> void:
    """Apply consistent font sizing to all UI elements"""
    # Top UI labels
    apply_font_to_label(gold_label, UI_FONT_SIZE_LARGE)
    apply_font_to_label(shop_tier_label, UI_FONT_SIZE_LARGE)
    
    # Top UI buttons
    apply_font_to_button(refresh_button, UI_FONT_SIZE_MEDIUM)
    apply_font_to_button(freeze_button, UI_FONT_SIZE_MEDIUM)
    apply_font_to_button(upgrade_button, UI_FONT_SIZE_MEDIUM)
    apply_font_to_button(end_turn_button, UI_FONT_SIZE_MEDIUM)
    
    # Area labels
    apply_font_to_label(shop_area_label, UI_FONT_SIZE_LARGE)
    apply_font_to_label(player_board_label, UI_FONT_SIZE_LARGE)
    apply_font_to_label(player_hand_label, UI_FONT_SIZE_LARGE)

func apply_font_to_label(label: Label, size: int) -> void:
    """Helper function to apply font size to a label"""
    if label:
        label.add_theme_font_size_override("font_size", size)

func apply_font_to_button(button: Button, size: int) -> void:
    """Helper function to apply font size to a button"""  
    if button:
        button.add_theme_font_size_override("font_size", size)

# === PUBLIC INTERFACE FOR GAME LOGIC ===

func get_hand_size() -> int:
    """Get current number of cards in hand"""
    return player_hand.get_children().size() - 1  # Subtract label

func get_board_size() -> int:
    """Get current number of minions on board"""
    return player_board.get_children().size() - 1  # Subtract label

func is_hand_full() -> bool:
    """Check if hand is at maximum capacity"""
    return get_hand_size() >= max_hand_size

func is_board_full() -> bool:
    """Check if board is at maximum capacity"""
    return get_board_size() >= max_board_size

func add_card_to_shop(card_node: Control):
    """Add a card to the shop area"""
    shop_area.add_child(card_node)

func add_card_to_hand(card_node: Control):
    """Add a card to the player's hand"""
    player_hand.add_child(card_node)
    update_hand_display()

func add_card_to_board(card_node: Control):
    """Add a card to the player's board"""
    player_board.add_child(card_node)
    update_board_display()

func clear_shop():
    """Clear all cards from shop area (keeping the label)"""
    for child in shop_area.get_children():
        if child.name != "ShopAreaLabel":
            child.queue_free()

func get_hand_container() -> Container:
    """Return the hand container for direct access"""
    return player_hand

func get_shop_container() -> Container:
    """Return the shop container for direct access"""
    return shop_area

# === EVENT FORWARDING FOR CARD INTERACTIONS ===

func _on_card_clicked(card_node):
    """Forward card click events to game board"""
    forward_card_clicked.emit(card_node)

func _on_card_drag_started(card_node):
    """Forward card drag events to game board"""
    forward_card_drag_started.emit(card_node)

# Signals for forwarding events to game_board
signal forward_card_clicked(card_node)
signal forward_card_drag_started(card_node)

# === COMBAT UI CREATION ===

func create_combat_ui() -> void:
    """Create combat UI elements programmatically"""
    # Create main combat UI container
    combat_ui_container = VBoxContainer.new()
    combat_ui_container.name = "CombatUI"
    
    # Add to the main layout (position it near the top UI)
    add_child(combat_ui_container)
    move_child(combat_ui_container, 1)  # Place after TopUI
    
    # Create health display container
    var health_container = HBoxContainer.new()
    health_container.name = "HealthContainer"
    
    # Player health label
    player_health_label = Label.new()
    player_health_label.name = "PlayerHealthLabel"
    player_health_label.text = "Player Health: %d" % GameState.player_health
    player_health_label.add_theme_color_override("font_color", Color.GREEN)
    apply_font_to_label(player_health_label, UI_FONT_SIZE_LARGE)
    
    # Enemy health label  
    enemy_health_label = Label.new()
    enemy_health_label.name = "EnemyHealthLabel"
    enemy_health_label.text = "Enemy Health: %d" % GameState.enemy_health
    enemy_health_label.add_theme_color_override("font_color", Color.RED)
    apply_font_to_label(enemy_health_label, UI_FONT_SIZE_LARGE)
    
    health_container.add_child(player_health_label)
    health_container.add_child(enemy_health_label)
    
    # Create enemy board selection container
    var enemy_selection_container = HBoxContainer.new()
    enemy_selection_container.name = "EnemySelectionContainer"
    
    var enemy_label = Label.new()
    enemy_label.text = "Enemy Board: "
    apply_font_to_label(enemy_label, UI_FONT_SIZE_MEDIUM)
    
    enemy_board_selector = OptionButton.new()
    enemy_board_selector.name = "EnemyBoardSelector"
    apply_font_to_button(enemy_board_selector, UI_FONT_SIZE_MEDIUM)
    
    enemy_selection_container.add_child(enemy_label)
    enemy_selection_container.add_child(enemy_board_selector)
    
    # Create start combat button
    start_combat_button = Button.new()
    start_combat_button.name = "StartCombatButton"
    start_combat_button.text = "Start Combat"
    apply_font_to_button(start_combat_button, UI_FONT_SIZE_MEDIUM)
    
    # Create combat log display
    combat_log_display = RichTextLabel.new()
    combat_log_display.name = "CombatLogDisplay"
    combat_log_display.custom_minimum_size = Vector2(400, 200)
    combat_log_display.bbcode_enabled = true
    combat_log_display.scroll_following = true
    combat_log_display.add_theme_font_size_override("normal_font_size", UI_FONT_SIZE_SMALL)
    combat_log_display.add_theme_font_size_override("bold_font_size", UI_FONT_SIZE_MEDIUM)
    combat_log_display.text = "[b]Next Battle[/b]\n\nSelect an enemy board and click 'Start Combat' to begin."
    
    # Add all elements to combat UI container
    combat_ui_container.add_child(health_container)
    combat_ui_container.add_child(enemy_selection_container)
    combat_ui_container.add_child(start_combat_button)
    combat_ui_container.add_child(combat_log_display)
    
    print("Combat UI created successfully")

func populate_enemy_board_selector() -> void:
    """Populate enemy board dropdown with available options"""
    if not enemy_board_selector:
        return
        
    enemy_board_selector.clear()
    
    # Add enemy board options
    for board_name in EnemyBoards.get_enemy_board_names():
        var board_data = EnemyBoards.create_enemy_board(board_name)
        enemy_board_selector.add_item(board_data.get("name", board_name))
        
    print("Enemy board selector populated with %d options" % enemy_board_selector.get_item_count())

func connect_combat_ui_signals():
    """Connect combat UI element signals to game_board functions"""
    if start_combat_button:
        # Connect to the parent's (game_board.gd) signal handler
        start_combat_button.pressed.connect(get_parent()._on_start_combat_button_pressed)
        
    if enemy_board_selector:
        # Connect to the parent's (game_board.gd) signal handler  
        enemy_board_selector.item_selected.connect(get_parent()._on_enemy_board_selected)
        
    print("Combat UI signals connected to game_board handlers")

func connect_shop_ui_signals():
    """Connect shop UI element signals to game_board functions"""
    # Note: Shop button signals are connected in game_board.tscn, not here
    # This function is kept for consistency but no longer connects signals
    print("Shop UI signals connected in scene file") 
