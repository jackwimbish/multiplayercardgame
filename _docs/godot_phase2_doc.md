# Phase 2 Goal: Implement an Automated Combat Log Generator

Your objective is to implement the automated combat phase. The primary output of this phase will not be visuals, but a structured Combat Log that details every action in the fight. This log will be used in a later phase to animate the combat replay.

We will develop and test this logic in a Player vs. Environment (PvE) context to keep it isolated from networking.

## Implementation Plan

### 1. Create the "Start Combat" Trigger ⚔️

We need a manual trigger to begin the combat simulation.

- In your `game_board.tscn` scene, ensure you have a Button named `StartCombatButton` with the text "Start Combat".
- Connect its `pressed()` signal to a function in `game_board.gd` named `_on_start_combat_button_pressed`.

### 2. Prepare Data for Combat

The combat algorithm needs clean data arrays to work with. This step involves gathering data from your UI, assigning unique IDs for tracking, and creating a test opponent.

**Ensure Minion Data is Stored**: In your `card.gd` script, make sure you have a variable to hold the minion's data.

```gdscript
# In card.gd
var card_data = {}

func setup_minion_data(data):
    # ... your existing setup logic ...
    self.card_data = data
```

**Gather and ID the Data**: In `game_board.gd`, the `_on_start_combat_button_pressed` function will gather the data and call the combat simulation.

```gdscript
# In game_board.gd
func _on_start_combat_button_pressed():
    # Get player's board data and assign unique IDs
    var player_minions = []
    for i in range($PlayerBoard.get_child_count()):
        var minion_node = $PlayerBoard.get_child(i)
        var minion_data = minion_node.card_data.duplicate()
        minion_data["id"] = "p_" + str(i) # Assign ID like "p_0", "p_1"
        player_minions.append(minion_data)

    # Create a hard-coded enemy board with unique IDs
    var enemy_minions = []
    var enemy_templates = [CARD_DATABASE["puddlestomper"], CARD_DATABASE["scrappy_mech"]]
    for i in range(enemy_templates.size()):
        var minion_data = enemy_templates[i].duplicate()
        minion_data["id"] = "e_" + str(i) # Assign ID like "e_0", "e_1"
        enemy_minions.append(minion_data)

    # Run the simulation and get the log
    var combat_log = run_combat(player_minions, enemy_minions)

    # For now, print the entire log to verify it works
    print("--- COMBAT LOG ---")
    for action in combat_log:
        print(action)
```

### 3. Implement the Combat Log Algorithm 🤖

This is the core of Phase 2. The `run_combat` function will simulate the fight and generate the action log based on the "round-robin" attack order. Add this function to `game_board.gd`.

```gdscript
# In game_board.gd
func run_combat(p_board, e_board):
    var action_log = []
    var p_attacker_index = 0
    var e_attacker_index = 0
    var p_turn = true

    while not p_board.is_empty() and not e_board.is_empty():
        var attacker
        var defender

        # Select the correct attacker based on whose turn it is
        if p_turn:
            if p_attacker_index >= p_board.size(): p_attacker_index = 0
            attacker = p_board[p_attacker_index]
            defender = e_board.pick_random()
        else:
            if e_attacker_index >= e_board.size(): e_attacker_index = 0
            attacker = e_board[e_attacker_index]
            defender = p_board.pick_random()

        # Log the attack
        action_log.append({"type": "attack", "attacker_id": attacker.id, "defender_id": defender.id})

        # --- Damage Exchange & Logging ---
        defender.health -= attacker.attack
        action_log.append({"type": "damage", "target_id": defender.id, "amount": attacker.attack})
        
        attacker.health -= defender.attack
        action_log.append({"type": "damage", "target_id": attacker.id, "amount": defender.attack})
        
        # --- Death Check & Logging ---
        var dead_minions = []
        for minion in p_board + e_board:
            if minion.health <= 0 and not minion.id in dead_minions:
                dead_minions.append(minion.id)
                action_log.append({"type": "death", "target_id": minion.id})

        # Filter out dead minions from the boards
        if not dead_minions.is_empty():
            p_board = p_board.filter(func(m): return not m.id in dead_minions)
            e_board = e_board.filter(func(m): return not m.id in dead_minions)

        # --- Advance Turn & Indices ---
        if p_turn:
            p_attacker_index += 1
        else:
            e_attacker_index += 1
        
        p_turn = not p_turn
    
    return action_log
```