class_name BuffHelpers
extends RefCounted

## Helper functions for the buff system

static func create_buff_from_data(buff_data: Dictionary) -> Buff:
    """Create a buff instance from dictionary data"""
    var buff_type = buff_data.get("type", "")
    
    match buff_type:
        "stat_modification":
            var buff = StatModificationBuff.new()
            buff.buff_id = "stat_mod_" + str(Time.get_ticks_msec())
            buff.attack_bonus = buff_data.get("attack_bonus", 0)
            buff.health_bonus = buff_data.get("health_bonus", 0)
            buff.max_health_bonus = buff_data.get("max_health_bonus", 0)
            buff.display_name = "+%d/+%d" % [buff.attack_bonus, buff.health_bonus]
            buff.duration = Buff.Duration.PERMANENT  # Default for enemy board buffs
            return buff
        "keyword_ability":
            var buff = KeywordAbilityBuff.new()
            buff.buff_id = "keyword_" + str(Time.get_ticks_msec())
            buff.ability_name = buff_data.get("ability_name", "")
            buff.ability_data = buff_data.get("ability_data", {})
            buff.display_name = buff.ability_name.capitalize()
            buff.duration = Buff.Duration.PERMANENT  # Default for enemy board buffs
            return buff
        _:
            push_error("Unknown buff type: " + str(buff_type))
            return null

static func pick_random(array: Array):
    """Pick a random element from an array"""
    if array.is_empty():
        return null
    return array[randi() % array.size()]

## Global helper function to be used in CombatMinion
static func create_buff_from_data_global(buff_data: Dictionary) -> Buff:
    """Global wrapper for create_buff_from_data for use in CombatMinion"""
    return create_buff_from_data(buff_data)

## Make create_buff_from_data available globally
static func _static_init():
    # This allows the function to be called from anywhere as create_buff_from_data()
    pass 
