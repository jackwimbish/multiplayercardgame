# Refactoring Candidates for Godot Auto-Battler

This document outlines potential areas for refactoring in the project's codebase. The primary goal of these suggestions is to improve code organization, reduce complexity, and increase maintainability by breaking down large, monolithic scripts into smaller, more focused components.

The main file targeted for refactoring is `game_board.gd`, which has grown into a "god object" managing too many responsibilities.

---

### 1. Separate Game State Management

**Problem:** `game_board.gd` currently mixes core game state variables (like `current_turn`, `current_gold`, `shop_tier`), UI node references, and combat-specific state at the top level of the script. This makes the state of the game hard to track and reason about.

**Suggestion:** Create a dedicated autoload singleton for managing the game's state. This singleton would act as the single source of truth for the game's core data.

**Example `GameState.gd` (New Autoload Script):**
```gdscript
# GameState.gd (Autoload Singleton)
extends Node

# Core Game State
var current_turn: int = 1
var player_base_gold: int = 3
var current_gold: int = 3
var shop_tier: int = 1
var player_health: int = 25
var enemy_health: int = 25

# Signals for state changes
signal turn_changed(new_turn: int)
signal gold_changed(new_gold: int)
signal health_changed(player_hp: int, enemy_hp: int)

func start_new_turn():
    current_turn += 1
    # ... logic to update gold, etc.
    turn_changed.emit(current_turn)

func update_gold(amount: int):
    current_gold += amount
    gold_changed.emit(current_gold)

# ... other state management functions
```

`game_board.gd` would then access this data via the singleton (e.g., `GameState.current_gold`) instead of holding it directly.

---

### 2. Create a Dedicated UI Manager

**Problem:** UI-related logic, such as getting node references, applying font sizes, and updating labels, is scattered throughout `game_board.gd`. This mixes presentation logic with game logic.

**Suggestion:** Create a `UIManager.gd` script, attached to a main UI control node, to handle all UI updates. It would listen to signals from `GameState` or other managers and update the UI accordingly.

**Example `UIManager.gd`:**
```gdscript
# UIManager.gd
extends Control

# UI Node References
@onready var gold_label = $MainLayout/TopUI/GoldLabel
@onready var turn_label = $MainLayout/TopUI/TurnLabel
# ... other UI nodes

func _ready():
    # Connect to signals from the GameState singleton
    GameState.gold_changed.connect(update_gold_label)
    GameState.turn_changed.connect(update_turn_label)
    
    # Initial UI setup
    update_gold_label(GameState.current_gold)
    update_turn_label(GameState.current_turn)

func update_gold_label(new_gold: int):
    gold_label.text = "Gold: " + str(new_gold)

func update_turn_label(new_turn: int):
    turn_label.text = "Turn: " + str(new_turn)

# ... other UI update functions
```

---

### 3. Extract Shop Logic into a `ShopManager`

**Problem:** All the logic for managing the shop—refreshing, populating, managing the card pool, and handling costs—is inside `game_board.gd`. This is a distinct subsystem.

**Suggestion:** Create a `ShopManager.gd` node. This script would manage the `card_pool`, handle shop refreshes, and calculate costs. `game_board.gd` would call high-level functions on the `ShopManager` (e.g., `ShopManager.refresh_shop()`).

**Example `ShopManager.gd`:**
```gdscript
# ShopManager.gd
extends Node

var card_pool: Dictionary = {}
@onready var shop_area = get_parent().get_node("MainLayout/ShopArea") # Example path

func _ready():
    initialize_card_pool()

func initialize_card_pool():
    # Logic from game_board.gd to set up the card pool
    # ...

func refresh_shop():
    # Clear and populate the shop_area container
    # ...

func purchase_card(card_id: String) -> bool:
    var cost = CardDatabase.get_card_data(card_id).get("cost", 3)
    if GameState.current_gold >= cost:
        GameState.update_gold(-cost)
        # ... logic to add card to hand
        return true
    return false
```

---

### 4. Isolate Combat Logic in a `CombatManager`

**Problem:** Even though combat is a Phase 2 feature, its setup (state enums, UI nodes, enemy board selection) is already cluttering `game_board.gd`.

**Suggestion:** Create a `CombatManager.gd` to handle the entire combat sequence. This manager would be responsible for creating `CombatMinion` instances, running the battle simulation, and reporting the results.

**Example `CombatManager.gd`:**
```gdscript
# CombatManager.gd
extends Node

signal combat_started
signal combat_ended(result: Dictionary)

func start_combat(player_board: Array, enemy_board: Array):
    combat_started.emit()
    
    # 1. Create CombatMinion instances for all minions
    # 2. Run the attack sequence loop
    # 3. Determine winner and calculate damage
    # 4. Emit combat_ended with results
    
    var result = { "winner": "player", "damage": 5 }
    combat_ended.emit(result)
```

---

### 5. Create a `CardFactory` for Card Instantiation

**Problem:** The `create_card_instance` function in `game_board.gd` has special logic to dynamically change the script of a card scene if it's a minion. This is a factory pattern hidden inside the main game script.

**Suggestion:** Create a `CardFactory.gd` autoload singleton to centralize the creation of card game objects. This makes the creation process reusable and separates this concern from game logic.

**Example `CardFactory.gd`:**
```gdscript
# CardFactory.gd (Autoload Singleton)
extends Node

const CardScene = preload("res://card.tscn")
const MinionScript = load("res://minion_card.gd")

func create_card(card_id: String):
    var card_data = CardDatabase.get_card_data(card_id)
    if card_data.is_empty():
        return null

    var new_card = CardScene.instantiate()
    
    var enhanced_card_data = card_data.duplicate()
    enhanced_card_data["id"] = card_id

    if enhanced_card_data.get("type") == "minion":
        new_card.set_script(MinionScript)

    new_card.setup_card_data(enhanced_card_data)
    return new_card
```

By breaking down `game_board.gd` into these smaller, more focused managers and singletons, the project will be much easier to develop, debug, and expand in the future. 