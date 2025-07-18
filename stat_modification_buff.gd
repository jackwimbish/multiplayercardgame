class_name StatModificationBuff
extends Buff

@export var attack_bonus: int = 0
@export var health_bonus: int = 0
@export var max_health_bonus: int = 0

func _init():
    buff_type = BuffType.STAT_MODIFICATION

func apply_to_minion(minion) -> void:
    """Apply stat modifications to a combat minion"""
    # Minion could be CombatMinion or Card depending on context
    if minion.has_method("get_current_attack"):
        # CombatMinion interface
        minion.current_attack += attack_bonus
        minion.current_health += health_bonus
        minion.max_health += max_health_bonus
    elif minion.has_method("get_effective_attack"):
        # Card interface - handled through persistent_buffs array
        # The minion will calculate effective stats by iterating buffs
        pass

func remove_from_minion(minion) -> void:
    """Remove stat modifications from a combat minion"""
    if minion.has_method("get_current_attack"):
        # CombatMinion interface
        minion.current_attack -= attack_bonus
        minion.current_health -= health_bonus
        minion.max_health -= max_health_bonus
    elif minion.has_method("get_effective_attack"):
        # Card interface - handled through persistent_buffs array removal
        pass 
