class_name MinionCard
extends Card

## MinionCard - Specialized card class for minions with buff/combat functionality

# Minion-specific buff system integration
var persistent_buffs: Array = []  # Array[Buff] - using untyped for now to avoid linter issues
var base_attack: int = 0
var base_health: int = 0
var current_health: int = 0  # Can take damage between combats
var unique_board_id: String = ""  # For handling duplicate cards with different buffs

func setup_card_data(data: Dictionary):
    # Call parent setup first
    super.setup_card_data(data)
    
    # Initialize minion-specific data
    if data.has("attack") and data.has("health"):
        base_attack = data.get("attack", 0)
        base_health = data.get("health", 0)
        current_health = base_health
        unique_board_id = generate_unique_id()
        
        # Update display with initial stats (override parent's simple display)
        update_display_stats()

func generate_unique_id() -> String:
    """Generate unique ID for this board instance"""
    return card_data.get("id", "unknown") + "_" + str(Time.get_ticks_msec())

func add_persistent_buff(buff) -> void:  # buff: Buff - untyped to avoid linter issues
    """Add a persistent buff that survives between combats"""
    if buff != null and buff.has_method("apply_to_minion"):
        # Remove existing buff if not stackable
        if not buff.stackable:
            remove_persistent_buff_by_id(buff.buff_id)
        
        persistent_buffs.append(buff)
        update_display_stats()
        print("Added persistent buff to %s: %s" % [card_data.get("name", "Unknown"), buff.display_name])

func remove_persistent_buff_by_id(buff_id: String) -> void:
    """Remove a persistent buff by its ID"""
    for i in range(persistent_buffs.size() - 1, -1, -1):
        if persistent_buffs[i].buff_id == buff_id:
            var removed_buff = persistent_buffs[i]
            persistent_buffs.remove_at(i)
            print("Removed persistent buff from %s: %s" % [card_data.get("name", "Unknown"), removed_buff.display_name])
    update_display_stats()

func get_effective_attack() -> int:
    """Get attack including all persistent buff modifications"""
    var total = base_attack
    for buff in persistent_buffs:
        # Check if it's a StatModificationBuff (using duck typing)
        if buff.has_method("apply_to_minion") and buff.buff_type == Buff.BuffType.STAT_MODIFICATION:
            total += buff.attack_bonus
    return total

func get_effective_health() -> int:
    """Get health including all persistent buff modifications"""
    var total = base_health
    for buff in persistent_buffs:
        # Check if it's a StatModificationBuff (using duck typing)
        if buff.has_method("apply_to_minion") and buff.buff_type == Buff.BuffType.STAT_MODIFICATION:
            total += buff.health_bonus
    return total

func update_display_stats() -> void:
    """Update visual stats to show effective stats with buff indicators"""
    # Only update if this is a minion card
    if card_data.has("attack") and card_data.has("health"):
        var display_attack = get_effective_attack()
        var display_health = max(current_health + get_health_buff_bonus(), 0)
        $VBoxContainer/BottomRow/StatsLabel.text = str(display_attack) + "/" + str(display_health)
        
        # Visual indication of buffs (green text if buffed)
        if not persistent_buffs.is_empty():
            $VBoxContainer/BottomRow/StatsLabel.modulate = Color.GREEN
        else:
            $VBoxContainer/BottomRow/StatsLabel.modulate = Color.WHITE

func get_health_buff_bonus() -> int:
    """Get total health bonus from all persistent buffs"""
    var bonus = 0
    for buff in persistent_buffs:
        if buff.has_method("apply_to_minion") and buff.buff_type == Buff.BuffType.STAT_MODIFICATION:  # STAT_MODIFICATION = 0
            bonus += buff.health_bonus
    return bonus

func take_damage(amount: int) -> void:
    """Apply damage to this minion between combats"""
    current_health = max(0, current_health - amount)
    update_display_stats()
    print("%s took %d damage, health now: %d" % [card_data.get("name", "Unknown"), amount, current_health])

func heal_damage(amount: int) -> void:
    """Heal damage on this minion"""
    var max_possible_health = get_effective_health()
    current_health = min(max_possible_health, current_health + amount)
    update_display_stats()
    print("%s healed for %d, health now: %d/%d" % [card_data.get("name", "Unknown"), amount, current_health, max_possible_health])

func is_dead() -> bool:
    """Check if this minion has died"""
    return current_health <= 0 
