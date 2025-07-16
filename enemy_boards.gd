class_name EnemyBoards
extends RefCounted

## Enemy Board Management System
## 
## Design Philosophy: Enemy boards specify only the card_id and buffs. 
## Base stats come from the card database to avoid duplication and ensure 
## consistency when card balance changes.

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
    """Get list of all available enemy board names"""
    var names: Array[String] = []
    names.assign(test_enemy_boards.keys())
    return names

static func create_enemy_board(board_name: String) -> Dictionary:
    """Create an enemy board configuration by name"""
    if not test_enemy_boards.has(board_name):
        push_error("Enemy board not found: " + board_name)
        return {}
    return test_enemy_boards[board_name].duplicate(true)

static func validate_enemy_board(board_data: Dictionary) -> bool:
    """Validate that all cards in an enemy board exist in the database"""
    if not board_data.has("minions"):
        push_error("Enemy board missing 'minions' array")
        return false
    
    var minions = board_data.get("minions", [])
    for minion_data in minions:
        if not minion_data.has("card_id"):
            push_error("Enemy minion missing 'card_id' field")
            return false
        
        var card_id = minion_data.get("card_id", "")
        var card_data = CardDatabase.get_card_data(card_id)
        if card_data.is_empty():
            push_error("Enemy minion references unknown card: " + card_id)
            return false
        
        # Validate that it's a minion (enemy boards should only have minions)
        if card_data.get("type", "") != "minion":
            push_error("Enemy board contains non-minion card: " + card_id)
            return false
    
    return true

static func get_enemy_board_info(board_name: String) -> Dictionary:
    """Get summary information about an enemy board"""
    var board_data = create_enemy_board(board_name)
    if board_data.is_empty():
        return {}
    
    var info = {
        "name": board_data.get("name", "Unknown"),
        "health": board_data.get("health", 25),
        "minion_count": board_data.get("minions", []).size(),
        "minions": []
    }
    
    # Add detailed minion info
    for minion_data in board_data.get("minions", []):
        var card_id = minion_data.get("card_id", "")
        var card_data = CardDatabase.get_card_data(card_id)
        
        var base_attack = card_data.get("attack", 0)
        var base_health = card_data.get("health", 0)
        
        # Calculate effective stats with buffs
        var effective_attack = base_attack
        var effective_health = base_health
        
        for buff_data in minion_data.get("buffs", []):
            if buff_data.get("type", "") == "stat_modification":
                effective_attack += buff_data.get("attack_bonus", 0)
                effective_health += buff_data.get("health_bonus", 0)
        
        info.minions.append({
            "name": card_data.get("name", "Unknown"),
            "base_stats": "%d/%d" % [base_attack, base_health],
            "effective_stats": "%d/%d" % [effective_attack, effective_health],
            "has_buffs": not minion_data.get("buffs", []).is_empty()
        })
    
    return info

static func validate_all_enemy_boards() -> bool:
    """Validate all predefined enemy boards"""
    var all_valid = true
    
    for board_name in get_enemy_board_names():
        print("Validating enemy board: ", board_name)
        var board_data = create_enemy_board(board_name)
        
        if not validate_enemy_board(board_data):
            print("❌ Enemy board validation failed: ", board_name)
            all_valid = false
        else:
            var info = get_enemy_board_info(board_name)
            print("✅ %s: %d minions, %d health" % [info.name, info.minion_count, info.health])
            for minion in info.minions:
                var buff_indicator = " (buffed)" if minion.has_buffs else ""
                print("   - %s: %s → %s%s" % [minion.name, minion.base_stats, minion.effective_stats, buff_indicator])
    
    return all_valid 
