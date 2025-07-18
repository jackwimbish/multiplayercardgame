# Refactoring Candidates: Part 2

This document builds upon the initial refactoring efforts that separated core logic into dedicated managers. The primary focus here is to address the remaining responsibilities of `game_board.gd`, which continues to act as a "god object" coordinating many aspects of the game.

The goal is to further decouple game logic, UI interaction, and player input handling.

## ✅ Implementation Status

**Refactor Candidate #1: DragDropManager** - **COMPLETED**
- Created `DragDropManager.gd` autoload singleton
- Extracted all drag-and-drop logic from `game_board.gd`
- Implemented visual feedback system for drop zones
- Connected to `UIManager` for zone registration
- Successfully tested and working

**Refactor Candidate #2: UI Decoupling** - **COMPLETED**
- Removed all direct UI node access from `game_board.gd`
- Enhanced `UIManager` with detailed update functions
- Connected GameState signals directly to UIManager for automatic updates
- Abstracted container access through UIManager getter functions
- Replaced `update_ui_displays()` with `UIManager.update_all_game_displays()`
- Successfully tested and working

---

### 1. Extract Drag-and-Drop Logic into a `DragDropManager`

**Problem:** `game_board.gd` contains a significant amount of code dedicated to managing the drag-and-drop functionality for cards. This includes:
- Tracking the `dragged_card`.
- Detecting which UI zone a card is dropped into (`detect_drop_zone`).
- Determining a card's origin zone (`get_card_origin_zone`).
- Managing mouse filters for all cards during a drag operation (`_set_all_cards_mouse_filter`).
- Handling the `_on_card_drag_started` and `_on_card_dropped` (implicitly) logic.

This responsibility is distinct from the core game rules and should be encapsulated.

**Suggestion:** Create a new autoload singleton script called `DragDropManager.gd` to handle all drag-and-drop operations. This manager would be responsible for the entire lifecycle of a drag operation.

**Example `DragDropManager.gd` (New Autoload Script):**
```gdscript
# DragDropManager.gd (Autoload Singleton)
extends Node

var dragged_card = null
var origin_parent = null
var origin_position = Vector2.ZERO

signal card_drag_started(card)
signal card_drag_ended(card, drop_zone)

func start_drag(card_node):
    if dragged_card:
        return # Already dragging something

    dragged_card = card_node
    origin_parent = card_node.get_parent()
    origin_position = card_node.position
    
    # Reparent the card to the main canvas to ensure it draws on top
    get_tree().current_scene.add_child(dragged_card)
    dragged_card.global_position = get_global_mouse_position()
    
    card_drag_started.emit(dragged_card)

func stop_drag():
    if not dragged_card:
        return

    var drop_zone = detect_drop_zone(dragged_card.global_position)
    card_drag_ended.emit(dragged_card, drop_zone)
    
    # Logic to handle the drop will be in the listener (e.g., game_board.gd)
    # For now, just reset state
    dragged_card = null
    origin_parent = null

func _process(delta):
    if dragged_card:
        dragged_card.global_position = get_global_mouse_position()

func detect_drop_zone(global_pos: Vector2) -> String:
    # This logic would be moved from game_board.gd
    # It would need access to the zone rects, which could be registered
    # with this manager by the UIManager at startup.
    # ...
    return "invalid"

func _input(event):
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if not event.is_pressed() and dragged_card:
            stop_drag()
```
`game_board.gd` would then listen to the `card_drag_ended` signal and implement the game logic for what happens when a card is dropped in a specific zone, without needing to know the details of the drag operation itself.

---

### 2. Decouple `game_board.gd` from Direct UI Node Access

**Problem:** The `game_board.gd` script still directly accesses UI nodes using `get_node_or_null` and absolute paths (e.g., `$MainLayout/PlayerHand`). This creates a tight coupling between the game logic and the scene tree's structure. If the UI layout changes, `game_board.gd` will break.

**Suggestion:** All UI node access should be consolidated within the `UIManager`. The `UIManager` should expose higher-level functions and signals that `game_board.gd` can use. Instead of getting a node and setting its text, `game_board.gd` should call a function on `UIManager` to perform the update.

**Example of Changes:**

**`game_board.gd` (Before):**
```gdscript
func update_ui_displays():
    var turn_label = get_node_or_null("MainLayout/TopUI/TurnLabel")
    if turn_label:
        turn_label.text = "Turn: " + str(GameState.current_turn)
```

**`UIManager.gd` (After - adding a new function):**
```gdscript
# In UIManager.gd
@onready var turn_label = $TopUI/TurnLabel

func update_turn_display(turn_number: int):
    if turn_label:
        turn_label.text = "Turn: " + str(turn_number)
```

**`game_board.gd` (After - calling the new UIManager function):**
```gdscript
# In game_board.gd
func _ready():
    # Connect to GameState signal
    GameState.turn_changed.connect(_on_turn_changed)

func _on_turn_changed(new_turn: int):
    ui_manager.update_turn_display(new_turn)
```
This change inverts the dependency. `game_board.gd` no longer knows about `turn_label`; it only knows that the `UIManager` can update the turn display. This makes the system more modular and robust. The `update_ui_displays` function in `game_board.gd` should be removed entirely in favor of reactive updates based on signals from `GameState`.

---

### 3. Centralize Card Instantiation and Signal Connection

**Problem:** When a card is created (e.g., in `add_card_to_hand_direct`), `game_board.gd` is responsible for connecting its signals (`card_clicked`, `drag_started`) to its own handlers. This logic is duplicated wherever a card is added to the scene.

**Suggestion:** The `CardFactory` should be the only place where card signals are connected. However, instead of hardcoding a single event handler, we should make the system flexible to support different signal targets for different use cases.

**Enhanced `CardFactory.gd` (Flexible Signal Connection):**
```gdscript
# CardFactory.gd (Autoload Singleton)
extends Node

const CardScene = preload("res://card.tscn")
# ...

func create_card(card_data, card_id, signal_handlers: Dictionary = {}):
    var new_card = CardScene.instantiate()
    # ... setup card data ...
    
    # Connect signals based on provided handlers
    if signal_handlers.has("card_clicked") and signal_handlers["card_clicked"].is_valid():
        new_card.card_clicked.connect(signal_handlers["card_clicked"])
    if signal_handlers.has("drag_started") and signal_handlers["drag_started"].is_valid():
        new_card.drag_started.connect(signal_handlers["drag_started"])
    
    return new_card

# Convenience function for common game board cards
func create_interactive_card(card_data, card_id):
    var handlers = {
        "card_clicked": _get_game_board()._on_card_clicked,
        "drag_started": _get_game_board()._on_card_drag_started
    }
    return create_card(card_data, card_id, handlers)

func _get_game_board():
    # Safe way to get the game board instance
    return get_tree().get_first_node_in_group("game_board")
```

**In `game_board.gd`'s `_ready()` function:**
```gdscript
func _ready():
    # Add the game board to a group for easy access
    add_to_group("game_board")
    # ... rest of the setup
```

**Usage Examples:**
```gdscript
# For normal interactive cards (most common case):
var card = CardFactory.create_interactive_card(card_data, card_id)

# For non-interactive cards (e.g., combat results display):
var display_card = CardFactory.create_card(card_data, card_id) # No signals connected

# For cards with custom handlers (e.g., special UI contexts):
var custom_handlers = {"card_clicked": some_other_handler}
var special_card = CardFactory.create_card(card_data, card_id, custom_handlers)
```

**Benefits of This Approach:**
- **Flexibility**: Different contexts can use different signal handlers
- **No Hardcoded Dependencies**: CardFactory doesn't need a direct reference to game_board
- **Backwards Compatible**: Existing non-interactive card creation continues to work
- **Clear Intent**: `create_interactive_card()` vs `create_card()` makes the intent obvious
- **Supports Multiple Use Cases**: Combat display cards, shop cards, hand cards can all have appropriate signal handling

This change ensures that card setup is consistent and centralized while maintaining flexibility for different use cases throughout the game. 