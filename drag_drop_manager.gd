# DragDropManager.gd (Autoload Singleton)
# Manages all drag-and-drop operations for cards
extends Node

var dragged_card = null
var origin_parent = null
var origin_position = Vector2.ZERO
var drag_offset = Vector2.ZERO

# Zone containers - registered by UIManager at startup
var hand_container: Container
var board_container: Container 
var shop_container: Container

signal card_drag_started(card)
signal card_drag_ended(card, origin_zone, drop_zone)

func _ready():
    print("DragDropManager initialized")

func register_ui_zones(hand: Container, board: Container, shop: Container):
    """Register UI zone containers for drop detection"""
    hand_container = hand
    board_container = board
    shop_container = shop
    print("DragDropManager: UI zones registered")

func start_drag(card_node, offset = Vector2.ZERO):
    """Start dragging a card"""
    if dragged_card:
        return # Already dragging something

    dragged_card = card_node
    origin_parent = card_node.get_parent()
    origin_position = card_node.position
    drag_offset = offset
    
    # Store the card's origin zone for drop handling
    var origin_zone = get_card_origin_zone(card_node)
    card_node.set_meta("origin_zone", origin_zone)
    
    # Set up mouse filters for dragging
    card_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _set_all_cards_mouse_filter(Control.MOUSE_FILTER_IGNORE, card_node)
    
    # "Lift" the card by reparenting to main scene
    card_node.reparent(get_tree().current_scene)
    card_node.move_to_front()
    
    print(card_node.name, " started dragging from ", origin_zone)
    card_drag_started.emit(card_node)

func stop_drag():
    """Stop the current drag operation"""
    if not dragged_card:
        return

    var origin_zone = dragged_card.get_meta("origin_zone", "unknown")
    var drop_zone = detect_drop_zone(dragged_card.global_position)
    
    print(dragged_card.name, " dropped from ", origin_zone, " to ", drop_zone)
    
    # Clear visual feedback
    _clear_drop_zone_feedback()
    
    # Restore mouse filters
    dragged_card.mouse_filter = Control.MOUSE_FILTER_STOP
    _set_all_cards_mouse_filter(Control.MOUSE_FILTER_STOP)
    
    # Emit signal for game logic to handle
    card_drag_ended.emit(dragged_card, origin_zone, drop_zone)
    
    # Reset drag state
    dragged_card = null
    origin_parent = null
    drag_offset = Vector2.ZERO

func _unhandled_input(event):
    """Handle mouse input during drag operations"""
    if dragged_card:
        if event is InputEventMouseMotion:
            dragged_card.global_position = event.global_position - drag_offset
            _update_drop_zone_feedback()

        if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
            stop_drag()

func detect_drop_zone(global_pos: Vector2) -> String:
    """Detect which zone a card is being dropped into"""
    if not hand_container or not board_container or not shop_container:
        return "invalid"
    
    # Get container rectangles
    var hand_rect = hand_container.get_global_rect()
    var board_rect = board_container.get_global_rect()
    var shop_rect = shop_container.get_global_rect()
    
    # Expand hand area to make it easier to drop into
    var expanded_hand_rect = Rect2(
        hand_rect.position.x - 30,  # 30 pixels left
        hand_rect.position.y - 100, # 100 pixels up
        hand_rect.size.x + 60,      # 30 pixels on each side
        hand_rect.size.y + 130      # 100 pixels up + 30 pixels down
    )
    
    if expanded_hand_rect.has_point(global_pos):
        return "hand"
    elif board_rect.has_point(global_pos):
        return "board"
    elif shop_rect.has_point(global_pos):
        return "shop"
    else:
        return "invalid"

func get_card_origin_zone(card) -> String:
    """Determine which zone a card originated from"""
    if not hand_container or not board_container or not shop_container:
        return "unknown"
    
    # Check if card is in shop (skip labels)
    for shop_card in shop_container.get_children():
        if shop_card == card and shop_card.name != "ShopAreaLabel":
            return "shop"
    
    # Check if card is in hand
    for hand_card in hand_container.get_children():
        if hand_card == card:
            return "hand"
    
    # Check if card is on board (skip labels)
    for board_card in board_container.get_children():
        if board_card == card and board_card.name != "PlayerBoardLabel":
            return "board"
    
    return "unknown"

func _set_all_cards_mouse_filter(filter_mode: int, exclude_card = null):
    """Set mouse filter for all cards (optionally excluding one card)"""
    if not hand_container or not board_container or not shop_container:
        return
    
    # Cards in hand
    for hand_card in hand_container.get_children():
        if hand_card != exclude_card:
            hand_card.mouse_filter = filter_mode
    
    # Cards on board (skip labels)
    for board_card in board_container.get_children():
        if board_card != exclude_card and board_card.name != "PlayerBoardLabel":
            board_card.mouse_filter = filter_mode
    
    # Cards in shop (skip labels)
    for shop_card in shop_container.get_children():
        if shop_card != exclude_card and shop_card.name != "ShopAreaLabel":
            shop_card.mouse_filter = filter_mode

func _update_drop_zone_feedback():
    """Update visual feedback for valid drop zones during dragging"""
    if not dragged_card:
        return
    
    var origin_zone = dragged_card.get_meta("origin_zone", "unknown")
    var current_drop_zone = detect_drop_zone(dragged_card.global_position)
    
    # Clear all feedback first
    _clear_drop_zone_feedback()
    
    # Show feedback based on origin and current position
    match [origin_zone, current_drop_zone]:
        ["shop", "hand"]:
            _highlight_container(hand_container, Color.GREEN)
        ["hand", "hand"]:
            _highlight_container(hand_container, Color.BLUE)
        ["hand", "board"]:
            if _is_dragged_card_minion():
                _highlight_container(board_container, Color.CYAN)
            else:
                _highlight_container(board_container, Color.RED)
        ["board", "board"]:
            _highlight_container(board_container, Color.CYAN)
        ["board", "hand"]:
            _highlight_container(hand_container, Color.RED)
        ["board", "shop"]:
            # Valid selling zone (only during shop phase)
            if GameState.current_mode == GameState.GameMode.SHOP:
                _highlight_container(shop_container, Color.YELLOW)
            else:
                _highlight_container(shop_container, Color.RED)
        ["shop", "board"], ["shop", "shop"]:
            # Invalid zones for shop cards
            pass

func _clear_drop_zone_feedback():
    """Clear all visual feedback for drop zones"""
    if hand_container:
        _remove_highlight(hand_container)
    if board_container:
        _remove_highlight(board_container)
    if shop_container:
        _remove_highlight(shop_container)

func _highlight_container(container: Container, color: Color):
    """Add visual highlight to a container"""
    if container:
        container.modulate = Color(color.r, color.g, color.b, 0.7)

func _remove_highlight(container: Container):
    """Remove visual highlight from a container"""
    if container:
        container.modulate = Color.WHITE

func _is_dragged_card_minion() -> bool:
    """Check if the currently dragged card is a minion"""
    if not dragged_card:
        return false
    
    var card_name_node = dragged_card.get_node_or_null("VBoxContainer/CardName")
    if not card_name_node:
        return false
        
    var card_name = card_name_node.text
    var card_data = _find_card_data_by_name(card_name)
    return card_data.get("type", "") == "minion"

func _find_card_data_by_name(card_name: String) -> Dictionary:
    """Find card data by card name from the database"""
    for card_id in CardDatabase.get_all_card_ids():
        var card_data = CardDatabase.get_card_data(card_id)
        if card_data.get("name", "") == card_name:
            return card_data
    return {} 
