# Buff System Design

## Overview

The buff system is designed to handle both persistent effects (that last multiple turns/combats) and temporary effects (that only last during a single combat). The system uses a component-based approach where buffs are separate objects that can be applied to minions.

## Core Architecture

### Separation of Board vs Combat State

- **Board Minions**: The "source of truth" for persistent state between combats
- **Combat Minions**: Temporary copies created for each combat, modified during battle
- **Buff Persistence**: Persistent buffs live on board minions, temporary buffs on combat copies

## Data Structures

### Buff Base Class

```gdscript
class_name Buff
extends Resource

enum BuffType {
    STAT_MODIFICATION,    # +attack, +health, etc.
    KEYWORD_ABILITY,      # taunt, divine shield, etc.
    AURA_EFFECT,         # affects other minions
    TRIGGERED_ABILITY     # on-death, on-attack, etc.
}

enum Duration {
    PERMANENT,           # Lasts until explicitly removed
    COMBAT_ONLY,         # Removed after combat ends
    TURNS,              # Lasts for X turns
    CONDITIONAL         # Lasts until condition met
}

@export var buff_id: String
@export var display_name: String
@export var description: String
@export var buff_type: BuffType
@export var duration: Duration
@export var turns_remaining: int = -1  # -1 for permanent/conditional
@export var source_id: String  # What created this buff (card, ability, etc.)
@export var stackable: bool = false
@export var properties: Dictionary = {}  # Flexible data storage

func apply_to_minion(minion: CombatMinion) -> void:
    # Override in subclasses
    pass

func remove_from_minion(minion: CombatMinion) -> void:
    # Override in subclasses
    pass

func should_expire() -> bool:
    # Check if buff should be removed
    return false
```

### Stat Modification Buff

```gdscript
class_name StatModificationBuff
extends Buff

@export var attack_bonus: int = 0
@export var health_bonus: int = 0
@export var max_health_bonus: int = 0

func _init():
    buff_type = BuffType.STAT_MODIFICATION

func apply_to_minion(minion: CombatMinion) -> void:
    minion.current_attack += attack_bonus
    minion.current_health += health_bonus
    minion.max_health += max_health_bonus

func remove_from_minion(minion: CombatMinion) -> void:
    minion.current_attack -= attack_bonus
    minion.current_health -= health_bonus
    minion.max_health -= max_health_bonus
```

### Keyword Ability Buff

```gdscript
class_name KeywordAbilityBuff
extends Buff

@export var ability_name: String  # "taunt", "divine_shield", etc.
@export var ability_data: Dictionary = {}  # Additional ability parameters

func _init():
    buff_type = BuffType.KEYWORD_ABILITY

func apply_to_minion(minion: CombatMinion) -> void:
    minion.add_keyword_ability(ability_name, ability_data)

func remove_from_minion(minion: CombatMinion) -> void:
    minion.remove_keyword_ability(ability_name)
```

## Minion Data Structures

### Board Minion (Persistent State)

```gdscript
# Existing card.gd structure extended with:

var persistent_buffs: Array[Buff] = []
var base_attack: int  # From card database
var base_health: int  # From card database
var current_health: int  # Can take damage between combats

func add_persistent_buff(buff: Buff) -> void:
    if not buff.stackable:
        remove_buff_by_id(buff.buff_id)
    persistent_buffs.append(buff)

func remove_persistent_buff(buff_id: String) -> void:
    for i in range(persistent_buffs.size() - 1, -1, -1):
        if persistent_buffs[i].buff_id == buff_id:
            persistent_buffs.remove_at(i)

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
```

### Combat Minion (Temporary Combat State)

```gdscript
class_name CombatMinion
extends Resource

@export var source_card: Card  # Reference to original board minion
@export var combat_buffs: Array[Buff] = []

# Combat stats (copied from board + persistent buffs at combat start)
@export var base_attack: int
@export var base_health: int
@export var max_health: int
@export var current_attack: int
@export var current_health: int

# Combat state
@export var has_attacked: bool = false
@export var can_attack: bool = true
@export var position: int = 0

# Keyword abilities
@export var keyword_abilities: Dictionary = {}

static func create_from_board_minion(board_minion: Card) -> CombatMinion:
    var combat_minion = CombatMinion.new()
    combat_minion.source_card = board_minion
    
    # Copy base stats
    combat_minion.base_attack = board_minion.base_attack
    combat_minion.base_health = board_minion.base_health
    combat_minion.current_health = board_minion.current_health
    
    # Apply persistent buffs
    for buff in board_minion.persistent_buffs:
        buff.apply_to_minion(combat_minion)
    
    # Set initial combat stats
    combat_minion.current_attack = combat_minion.base_attack
    combat_minion.max_health = combat_minion.base_health
    
    return combat_minion

func add_combat_buff(buff: Buff) -> void:
    if not buff.stackable:
        remove_combat_buff_by_id(buff.buff_id)
    combat_buffs.append(buff)
    buff.apply_to_minion(self)

func remove_combat_buff_by_id(buff_id: String) -> void:
    for i in range(combat_buffs.size() - 1, -1, -1):
        if combat_buffs[i].buff_id == buff_id:
            var buff = combat_buffs[i]
            buff.remove_from_minion(self)
            combat_buffs.remove_at(i)

func add_keyword_ability(ability_name: String, data: Dictionary = {}) -> void:
    keyword_abilities[ability_name] = data

func remove_keyword_ability(ability_name: String) -> void:
    if keyword_abilities.has(ability_name):
        keyword_abilities.erase(ability_name)

func has_keyword_ability(ability_name: String) -> bool:
    return keyword_abilities.has(ability_name)
```

## Combat Flow Integration

### Combat Start
1. Create `CombatMinion` instances from board minions using `create_from_board_minion()`
2. Persistent buffs are automatically applied during creation
3. Combat-specific temporary buffs can be applied as needed

### During Combat
1. Temporary buffs (spells, auras) are applied as `combat_buffs`
2. All modifications happen to combat copies
3. Original board minions remain unchanged

### Combat End
1. Apply persistent changes back to board minions:
   - Update `current_health` (damage taken)
   - Add any permanent buffs gained during combat
   - Remove dead minions from board
2. Combat copies are discarded

## Example Usage

### Adding a Tavern Upgrade (Persistent)
```gdscript
# Player buys a tavern upgrade that gives +1/+1 to all minions
var buff = StatModificationBuff.new()
buff.buff_id = "tavern_upgrade_1"
buff.display_name = "+1/+1"
buff.attack_bonus = 1
buff.health_bonus = 1
buff.duration = Buff.Duration.PERMANENT

for minion in player_board:
    minion.add_persistent_buff(buff)
```