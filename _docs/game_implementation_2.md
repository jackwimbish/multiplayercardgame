# Game Implementation Phase 2 - Updated Plans

## Overview

This document updates the original `godot_phase2_doc.md` with refined plans based on recent discussions. The core goal remains the same: implement an automated combat system that generates detailed combat logs. However, we've enhanced the design with better enemy management, a robust buff system, improved combat mechanics, and enhanced UI.

**Note**: Code examples in this document are pseudocode for planning purposes and may require adaptation during actual implementation.

## Implementation Dependencies

This plan assumes the following systems are available or will be implemented:

1. **Buff System Classes**: `Buff`, `StatModificationBuff`, `KeywordAbilityBuff` from `buff_system.md`
2. **Card Database**: `CARD_DATABASE.get_card_data()` function for retrieving card stats
3. **Helper Functions**: `create_buff_from_data()`, `pick_random()` for arrays
4. **UI Structure**: Combat-related UI nodes in the scene tree
5. **Scene References**: Proper node path structure for board and hand containers

## Key Updates from Original Plan

### 1. Enhanced Enemy Board System
- **Manual Enemy Selection**: Instead of hard-coded enemies, implement a dropdown/button system to select from predefined enemy boards for testing
- **Flexible Enemy Configuration**: Use JSON/GD-based enemy board definitions with support for buffs and enchantments
- **Scalable Architecture**: Foundation for future AI enemy generation

### 2. Combat Minion Architecture
- **Separation of Board vs Combat State**: Create temporary `CombatMinion` copies for battles
- **Buff System Integration**: Support for persistent buffs (carry between combats) and temporary buffs (combat-only)
- **Clean State Management**: Original board minions remain unchanged during combat
- **Tavern Phase Buffs**: Board minions store persistent buffs that survive between combats
- **Duplicate Card Handling**: Each board position has unique ID to handle identical cards with different buffs

### 3. Enhanced Combat Mechanics
- **Combat Limits**: 500 attack limit to prevent infinite loops, declare ties when reached
- **No Minions Auto-Loss**: Player with no minions loses when opponent has minions, both no minions = tie
- **Player Health System**: Both players start at 25 health, take damage on combat loss
- **Round-Robin Attacking**: Simplified, deterministic attack order

### 4. Improved UI and Feedback
- **Combat Log Integration**: Display combat actions alongside existing game UI
- **End Turn Button Enhancement**: Combat UI appears alongside end turn functionality
- **Always-Visible Combat**: Combat interface appears even when players have no minions

## Implementation Plan

### Phase 2A: Foundation Systems

#### 1. Enemy Board Management System

**Design Philosophy**: Enemy boards specify only the `card_id` and `buffs`. Base stats come from the card database to avoid duplication and ensure consistency when card balance changes.

Create `enemy_boards.gd` with predefined configurations:

```gdscript
# enemy_boards.gd
class_name EnemyBoards
extends RefCounted

static var test_enemy_boards = {
    "early_game": {
        "name": "Early Game Test",
        "health": 25,
        "minions": [
            {"card_id": "murloc_raider"},  # 2/1 basic minion
            {"card_id": "dire_wolf_alpha"}  # 2/2 with aura effect
        ]
    },
    "mid_game": {
        "name": "Mid Game Test", 
        "health": 20,
        "minions": [
            {"card_id": "harvest_golem"},  # 2/3 with deathrattle
            {"card_id": "kindly_grandmother", "buffs": [
                {"type": "stat_modification", "attack_bonus": 2, "health_bonus": 2}
            ]},  # 1/1 + 2/2 buff = 3/3
            {"card_id": "rockpool_hunter"}  # 2/3 with battlecry
        ]
    },
    "late_game": {
        "name": "Late Game Test",
        "health": 15, 
        "minions": [
            {"card_id": "harvest_golem", "buffs": [
                {"type": "stat_modification", "attack_bonus": 2, "health_bonus": 3}
            ]},  # 2/3 + 2/3 buff = 4/6
            {"card_id": "metaltooth_leaper"},  # 3/3 mech synergy
            {"card_id": "cave_hydra"},  # 2/4 with cleave
            {"card_id": "murloc_raider", "buffs": [
                {"type": "stat_modification", "attack_bonus": 4, "health_bonus": 4}
            ]}  # 2/1 + 4/4 buff = 6/5
        ]
    }
}

static func get_enemy_board_names() -> Array[String]:
    return test_enemy_boards.keys()

static func create_enemy_board(board_name: String) -> Dictionary:
    if not test_enemy_boards.has(board_name):
        push_error("Enemy board not found: " + board_name)
        return {}
    return test_enemy_boards[board_name].duplicate(true)
```

#### 2. Combat Minion System

Implement the `CombatMinion` class as documented in `buff_system.md`:

```gdscript
# combat_minion.gd
class_name CombatMinion
extends Resource

@export var source_card_id: String  # Reference to original card
@export var minion_id: String  # Unique combat identifier
@export var combat_buffs: Array[Buff] = []
@export var source_board_minion: Card  # Reference to original board minion

# Combat stats (includes persistent buffs)
@export var base_attack: int
@export var base_health: int  
@export var max_health: int
@export var current_attack: int
@export var current_health: int

# Combat state
@export var has_attacked: bool = false
@export var can_attack: bool = true
@export var position: int = 0
@export var keyword_abilities: Dictionary = {}

static func create_from_board_minion(board_minion: Card, combat_id: String) -> CombatMinion:
    var combat_minion = CombatMinion.new()
    combat_minion.source_card_id = board_minion.card_data.get("id", "unknown")
    combat_minion.minion_id = combat_id
    
    # Copy base stats + apply persistent buffs from tavern phase
    combat_minion.base_attack = board_minion.get_effective_attack()  # Includes tavern buffs
    combat_minion.base_health = board_minion.get_effective_health()   # Includes tavern buffs
    combat_minion.current_health = board_minion.current_health
    combat_minion.current_attack = combat_minion.base_attack
    combat_minion.max_health = combat_minion.base_health
    
    # Store reference to original board minion for post-combat updates
    combat_minion.source_board_minion = board_minion
    
    return combat_minion

static func create_from_enemy_data(enemy_data: Dictionary, combat_id: String) -> CombatMinion:
    var combat_minion = CombatMinion.new()
    combat_minion.source_card_id = enemy_data.get("card_id", "unknown")
    combat_minion.minion_id = combat_id
    
    # Get base stats from card database (no duplication)
    var base_stats = CARD_DATABASE.get_card_data(enemy_data.card_id)
    combat_minion.base_attack = base_stats.attack
    combat_minion.base_health = base_stats.health
    combat_minion.current_attack = combat_minion.base_attack
    combat_minion.current_health = combat_minion.base_health
    combat_minion.max_health = combat_minion.base_health
    
    # Apply any predefined buffs (this handles all stat modifications)
    for buff_data in enemy_data.get("buffs", []):
        var buff = create_buff_from_data(buff_data)  # NOTE: Implement this helper function
        if buff:
            combat_minion.add_combat_buff(buff)
    
    return combat_minion
```

#### 3. Enhanced Board Minion System

Extend `card.gd` to support persistent buffs and unique identification:

```gdscript
# In card.gd - enhanced for buff system
extends PanelContainer

# Existing signals and variables...
var card_data: Dictionary = {}

# NEW: Buff system integration
var persistent_buffs: Array[Buff] = []
var base_attack: int
var base_health: int  
var current_health: int  # Can take damage between combats
var unique_board_id: String  # For handling duplicate cards

func setup_card_data(data: Dictionary):
    # Existing setup...
    card_data = data
    $VBoxContainer/CardName.text = data.get("name", "Unnamed")
    $VBoxContainer/CardDescription.text = data.get("description", "")
    
    # NEW: Initialize base stats and unique ID
    base_attack = data.get("attack", 0)
    base_health = data.get("health", 0)
    current_health = base_health
    unique_board_id = generate_unique_id()
    
    update_display_stats()

func add_persistent_buff(buff: Buff) -> void:
    if not buff.stackable:
        remove_persistent_buff_by_id(buff.buff_id)
    persistent_buffs.append(buff)
    update_display_stats()

func remove_persistent_buff_by_id(buff_id: String) -> void:
    for i in range(persistent_buffs.size() - 1, -1, -1):
        if persistent_buffs[i].buff_id == buff_id:
            persistent_buffs.remove_at(i)
    update_display_stats()

func get_effective_attack() -> int:
    var total = base_attack
    for buff in persistent_buffs:
        if buff is StatModificationBuff:
            total += buff.attack_bonus
    return total

func get_effective_health() -> int:
    var total = base_health
    for buff in persistent_buffs:
        if buff is StatModificationBuff:
            total += buff.health_bonus
    return total

func update_display_stats() -> void:
    # Update visual stats to show effective stats
    if card_data.has("attack") and card_data.has("health"):
        var display_attack = get_effective_attack()
        var display_health = max(current_health, 0)
        $VBoxContainer/BottomRow/StatsLabel.text = str(display_attack) + "/" + str(display_health)
        
        # Visual indication of buffs (green text if buffed)
        if not persistent_buffs.is_empty():
            $VBoxContainer/BottomRow/StatsLabel.modulate = Color.GREEN
        else:
            $VBoxContainer/BottomRow/StatsLabel.modulate = Color.WHITE

func generate_unique_id() -> String:
    # Generate unique ID for this board instance
    return card_data.get("id", "unknown") + "_" + str(Time.get_ticks_msec())
```

#### 4. Player Health System

Add player health tracking to `game_board.gd`:

```gdscript
# In game_board.gd
@export var player_health: int = 25
@export var enemy_health: int = 25
@export var combat_damage: int = 5

signal player_health_changed(new_health: int)
signal enemy_health_changed(new_health: int)
signal game_over(winner: String)

func take_damage(damage: int, is_player: bool = true) -> void:
    if is_player:
        player_health = max(0, player_health - damage)
        player_health_changed.emit(player_health)
        if player_health <= 0:
            game_over.emit("enemy")
    else:
        enemy_health = max(0, enemy_health - damage)
        enemy_health_changed.emit(enemy_health)
        if enemy_health <= 0:
            game_over.emit("player")
```

### Phase 2B: Enhanced Combat System

#### 1. Tavern Phase Buff Application

Add buff management functions to `game_board.gd` for tavern phase mechanics:

```gdscript
# In game_board.gd - tavern phase buff application
func apply_tavern_buff_to_minion(target_minion: Card, buff: Buff) -> void:
    """Apply persistent buff during tavern phase"""
    # Set buff as permanent since it's applied during tavern phase
    buff.duration = Buff.Duration.PERMANENT
    
    # Add to persistent buffs (survives between combats)
    target_minion.add_persistent_buff(buff)
    
    print("Applied %s to %s" % [buff.display_name, target_minion.card_data.get("name", "Unknown")])

func apply_tavern_upgrade_all_minions(attack_bonus: int, health_bonus: int) -> void:
    """Apply tavern upgrade buff to all board minions"""
    var upgrade_buff = StatModificationBuff.new()
    upgrade_buff.buff_id = "tavern_upgrade_" + str(Time.get_ticks_msec())
    upgrade_buff.display_name = "+%d/+%d Tavern Upgrade" % [attack_bonus, health_bonus]
    upgrade_buff.attack_bonus = attack_bonus
    upgrade_buff.health_bonus = health_bonus
    upgrade_buff.duration = Buff.Duration.PERMANENT
    
    # Apply to each board minion individually
    for minion in $MainLayout/PlayerBoard.get_children():
        if minion is Card:
            apply_tavern_buff_to_minion(minion, upgrade_buff.duplicate())

func find_minion_by_unique_id(unique_id: String) -> Card:
    """Find board minion by unique ID to handle duplicates"""
    for minion in $MainLayout/PlayerBoard.get_children():
        if minion is Card and minion.unique_board_id == unique_id:
            return minion
    return null
```

#### 2. Combat UI Integration

Update the UI to include:
- Enemy board selection dropdown
- Combat log display area
- Player/enemy health displays
- Combat button alongside end turn

```gdscript
# Add to game_board.gd UI setup
# NOTE: These UI nodes need to be added to the actual scene structure
@onready var enemy_board_selector: OptionButton = $UI/EnemyBoardSelector
@onready var combat_log_display: RichTextLabel = $UI/CombatLogDisplay
@onready var player_health_label: Label = $UI/PlayerHealthLabel
@onready var enemy_health_label: Label = $UI/EnemyHealthLabel
@onready var start_combat_button: Button = $UI/StartCombatButton

func _ready():
    # Populate enemy board options
    for board_name in EnemyBoards.get_enemy_board_names():
        var board_data = EnemyBoards.create_enemy_board(board_name)
        enemy_board_selector.add_item(board_data.name)
    
    # Connect signals
    player_health_changed.connect(_on_player_health_changed)
    enemy_health_changed.connect(_on_enemy_health_changed)
    start_combat_button.pressed.connect(_on_start_combat_button_pressed)
```

#### 3. Enhanced Combat Algorithm

Update the combat system with new features:

```gdscript
# In game_board.gd
func run_combat(player_minions: Array[CombatMinion], enemy_minions: Array[CombatMinion]) -> Array[Dictionary]:
    var action_log = []
    var p_attacker_index = 0
    var e_attacker_index = 0
    var p_turn = true
    var attack_count = 0
    var max_attacks = 500
    
    action_log.append({"type": "combat_start", "player_minions": player_minions.size(), "enemy_minions": enemy_minions.size()})
    
    # Check for auto-loss/tie conditions
    if player_minions.is_empty() and enemy_minions.is_empty():
        action_log.append({"type": "combat_tie", "reason": "both_no_minions"})
        return action_log
    
    if player_minions.is_empty():
        action_log.append({"type": "auto_loss", "loser": "player", "reason": "no_minions"})
        take_damage(combat_damage, true)
        return action_log
    
    if enemy_minions.is_empty():
        action_log.append({"type": "auto_loss", "loser": "enemy", "reason": "no_minions"})
        take_damage(combat_damage, false)
        return action_log
    
    # Main combat loop
    while not player_minions.is_empty() and not enemy_minions.is_empty() and attack_count < max_attacks:
        var attacker: CombatMinion
        var defender: CombatMinion
        
        # Select attacker and defender based on round-robin
        if p_turn:
            if p_attacker_index >= player_minions.size(): 
                p_attacker_index = 0
            attacker = player_minions[p_attacker_index]
            defender = enemy_minions.pick_random()  # NOTE: Implement pick_random() helper or use enemy_minions[randi() % enemy_minions.size()]
        else:
            if e_attacker_index >= enemy_minions.size(): 
                e_attacker_index = 0
            attacker = enemy_minions[e_attacker_index]
            defender = player_minions.pick_random()  # NOTE: Implement pick_random() helper or use player_minions[randi() % player_minions.size()]
        # Execute attack
        execute_attack(attacker, defender, action_log)
        attack_count += 1
        
        # Remove dead minions
        player_minions = player_minions.filter(func(m): return m.current_health > 0)
        enemy_minions = enemy_minions.filter(func(m): return m.current_health > 0)
        
        # Advance turn
        if p_turn:
            p_attacker_index += 1
        else:
            e_attacker_index += 1
        p_turn = not p_turn
    
    # Determine combat result
    if attack_count >= max_attacks:
        action_log.append({"type": "combat_tie", "reason": "max_attacks_reached"})
    elif player_minions.is_empty():
        action_log.append({"type": "combat_end", "winner": "enemy"})
        take_damage(combat_damage, true)
    elif enemy_minions.is_empty():
        action_log.append({"type": "combat_end", "winner": "player"})
        take_damage(combat_damage, false)
    
    return action_log

func execute_attack(attacker: CombatMinion, defender: CombatMinion, action_log: Array[Dictionary]) -> void:
    action_log.append({
        "type": "attack",
        "attacker_id": attacker.minion_id,
        "defender_id": defender.minion_id,
        "attacker_attack": attacker.current_attack,
        "defender_attack": defender.current_attack
    })
    
    # Simultaneous damage
    var attacker_damage = attacker.current_attack
    var defender_damage = defender.current_attack
    
    defender.current_health -= attacker_damage
    attacker.current_health -= defender_damage
    
    action_log.append({
        "type": "damage",
        "target_id": defender.minion_id,
        "amount": attacker_damage,
        "new_health": defender.current_health
    })
    
    action_log.append({
        "type": "damage", 
        "target_id": attacker.minion_id,
        "amount": defender_damage,
        "new_health": attacker.current_health
    })
    
    # Check for deaths
    if defender.current_health <= 0:
        action_log.append({"type": "death", "target_id": defender.minion_id})
    
    if attacker.current_health <= 0:
        action_log.append({"type": "death", "target_id": attacker.minion_id})
```

### Phase 2C: Combat Log Display and Testing

#### 1. Combat Log Formatting

Create a readable combat log display:

```gdscript
func display_combat_log(action_log: Array[Dictionary]) -> void:
    combat_log_display.clear()
    combat_log_display.append_text("[b]COMBAT LOG[/b]\n\n")
    
    for action in action_log:
        var log_line = format_combat_action(action)
        combat_log_display.append_text(log_line + "\n")

func format_combat_action(action: Dictionary) -> String:
    match action.type:
        "combat_start":
            return "Combat begins! Player: %d minions vs Enemy: %d minions" % [action.player_minions, action.enemy_minions]
        "attack":
            return "%s attacks %s (%d vs %d)" % [action.attacker_id, action.defender_id, action.attacker_attack, action.defender_attack]
        "damage":
            return "%s takes %d damage (health: %d)" % [action.target_id, action.amount, action.new_health]
        "death":
            return "%s dies!" % action.target_id
        "combat_end":
            return "Combat ends! Winner: %s" % action.winner
        "combat_tie":
            match action.reason:
                "both_no_minions":
                    return "Combat tied! Neither player has minions"
                _:
                    return "Combat tied! (%s)" % action.reason
        "auto_loss":
            return "%s loses automatically (%s)" % [action.loser, action.reason]
        _:
            return "Unknown action: %s" % str(action)
```

## Testing Strategy

### 1. Tavern Phase Buff Testing
- Test buff application to individual minions during tavern phase
- Verify persistent buffs survive between combat rounds
- Test duplicate card handling (same card type, different buffs)
- Validate visual feedback for buffed minions (green stats display)
- Test tavern upgrade mechanics affecting all board minions

### 2. Enemy Board Progression
- Test with each predefined enemy board (early/mid/late game)
- Verify buff applications work correctly
- Test edge cases (no minions, single minion, etc.)

### 3. Combat Mechanics Validation
- Verify round-robin attack order
- Test combat limits and tie conditions
- Validate damage calculations and health tracking
- Test auto-loss scenarios

### 4. UI Integration Testing
- Test enemy board selection
- Verify combat log display formatting
- Test health display updates
- Ensure combat works alongside existing tavern phase

## Future Expansion Points

### 1. Advanced Buff System
- Implement full buff system from `buff_system.md`
- Add keyword abilities (taunt, divine shield, etc.)
- Create aura effects and triggered abilities

### 2. Enhanced Enemy AI
- Random enemy board generation
- Difficulty scaling based on player progress
- Dynamic enemy compositions

### 3. Combat Animation Preparation
- Structured action log format ready for animation system
- Timing and sequence data for smooth replays
- Visual effect hooks in combat actions

### 4. Multiplayer Foundation
- Combat system designed to work with networked opponents
- Deterministic combat resolution for sync
- Replay data format compatible with multiplayer validation

## Implementation Priority

1. **Phase 2A**: Enemy boards, combat minions, player health (Foundation)
2. **Phase 2B**: Enhanced combat algorithm, UI integration (Core Features)
3. **Phase 2C**: Combat log display, testing framework (Polish & Testing)

This updated plan maintains the original goal of creating a robust combat log system while incorporating our refined understanding of the game's needs and architecture. 