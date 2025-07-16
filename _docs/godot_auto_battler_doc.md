# Godot Auto-Battler Project Documentation

Welcome to the team. This document outlines the goal of our project and your first set of tasks.

## Project Goal

We are creating a 1v1 auto-battler game inspired by Hearthstone's Battlegrounds. The core gameplay loop consists of two phases:

1. **Tavern Phase**: Players buy cards from a shop and place minions on their board.
2. **Combat Phase**: The players' boards of minions fight automatically.

The cycle repeats, with players losing health after a lost combat, until only one player remains.

## Core Architecture: Blueprint vs. Object 📜 / ♟️

It is critical to understand the distinction we make between a card's data and its in-game representation:

**CardData**: This is the "blueprint" for any card in the game (minion, spell, etc.). It is raw data defined in a global dictionary called `CARD_DATABASE`. This data has no visual component; it is the single source of truth for what a card is and what it can do.

**Game Piece (card.tscn)**: This is the visual and interactive "object" that represents a piece of CardData in a specific context (e.g., in the shop or on the player's board). Its job is to display the data it's given and handle player interactions.

## Existing Codebase

- **game_board.gd**: The main script for the game. It manages the game state, networking, the `CARD_DATABASE`, and the logic for creating and interacting with game pieces.
- **card.gd**: The script attached to our universal game piece scene, `card.tscn`. It is responsible for receiving CardData and updating its own visuals, as well as emitting signals for interactions like clicks and drags.
- **card.tscn**: A versatile scene that serves as the visual template for a card in the shop or on the board.

## Phase 1 Goal: Build the Tavern

Your first objective is to implement the Tavern/Shop Phase. This involves creating the UI where a player can see cards available for purchase and manage the minions they've placed on their board.

### 1. Establish the Card Database

Open `game_board.gd` and ensure the global `CARD_DATABASE` is defined as follows. Note the "type" field, which is crucial for distinguishing between card types.

```gdscript
# In game_board.gd
const CARD_DATABASE = {
    "puddlestomper": {
        "type": "minion",
        "name": "Puddlestomper",
        "description": "",
        "attack": 3,
        "health": 2
    },
    "scrappy_mech": {
        "type": "minion",
        "name": "Scrappy Mech",
        "description": "A scrappy little mech.",
        "attack": 1,
        "health": 1
    },
    "coin": {
        "type": "spell",
        "name": "The Coin",
        "description": "Gain 1 Gold."
    }
}
```

### 2. Make the Card Scene Robust

Modify `card.gd` so it can correctly display any card type from the database without errors.

- Ensure `card.tscn` has Label nodes for `CardName`, `CardDescription`, `AttackLabel`, and `HealthLabel`.
- Update the `setup_card_data` function to safely handle data that may or may not have attack and health values.

```gdscript
# In card.gd
func setup_card_data(data):
    $VBoxContainer/CardName.text = data.get("name", "Unnamed")
    $VBoxContainer/CardDescription.text = data.get("description", "")

    # Only show stats if the card data has them.
    if data.has("attack"):
        $VBoxContainer/AttackLabel.text = str(data["attack"])
        $VBoxContainer/AttackLabel.show()
    else:
        $VBoxContainer/AttackLabel.hide()

    if data.has("health"):
        $VBoxContainer/HealthLabel.text = str(data["health"])
        $VBoxContainer/HealthLabel.show()
    else:
        $VBoxContainer/HealthLabel.hide()
```

### 3. Create the Tavern Layout

Modify `game_board.tscn` to have distinct areas for the player's board and the shop.

- **Player's Board**: The existing `PlayerHand` container should be renamed to `PlayerBoard`. This is where owned minions are placed and reordered.
- **The Shop**: Add a new `HBoxContainer` and name it `ShopArea`. Position it above the `PlayerBoard`.
- **Controls**: Add UI elements for a Gold Label and a "Refresh Shop" Button.

### 4. Implement Shop Logic

Add the core functions to `game_board.gd` to make the shop interactive.

- **refresh_shop()**: Create a function that clears the `ShopArea` and then populates it with instances of `card.tscn`, each configured with data for a random card from `CARD_DATABASE`.
- **"Buy" Mechanic**: When a card in the `ShopArea` is clicked, it should be removed from the shop and a new instance added to the `PlayerBoard`. (For now, you can assume all cards are minions). You will need to implement a simple gold system; a cost of 3 gold per card is a good starting point.