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

func apply_to_minion(minion) -> void:
    # Override in subclasses
    pass

func remove_from_minion(minion) -> void:
    # Override in subclasses
    pass

func should_expire() -> bool:
    # Check if buff should be removed
    if duration == Duration.TURNS and turns_remaining <= 0:
        return true
    return false

func advance_turn() -> void:
    """Called at the start of each turn to update turn-based buffs"""
    if duration == Duration.TURNS and turns_remaining > 0:
        turns_remaining -= 1 
