# Card Database for Auto-Battler Game
# Contains all card definitions organized by tier

class_name CardDatabase

# Card database for auto-battler
const CARDS = {
    # Tier 1 Cards (18 copies each)
    "murloc_raider": {
        "type": "minion",
        "name": "Murloc Raider",
        "description": "A basic murloc warrior.",
        "attack": 2,
        "health": 1,
        "tier": 1,
        "cost": 3
    },
    "dire_wolf_alpha": {
        "type": "minion",
        "name": "Dire Wolf Alpha",
        "description": "Adjacent minions have +1 Attack.",
        "attack": 2,
        "health": 2,
        "tier": 1,
        "cost": 3
    },
    "rockpool_hunter": {
        "type": "minion",
        "name": "Rockpool Hunter",
        "description": "Battlecry: Give a friendly Murloc +1/+1.",
        "attack": 2,
        "health": 3,
        "tier": 1,
        "cost": 3
    },
    
    # Tier 2 Cards (15 copies each)
    "kindly_grandmother": {
        "type": "minion",
        "name": "Kindly Grandmother",
        "description": "Deathrattle: Summon a 1/1 Big Bad Wolf.",
        "attack": 1,
        "health": 1,
        "tier": 2,
        "cost": 3
    },
    "harvest_golem": {
        "type": "minion",
        "name": "Harvest Golem",
        "description": "Deathrattle: Summon a 2/1 Damaged Golem.",
        "attack": 2,
        "health": 3,
        "tier": 2,
        "cost": 3
    },
    "metaltooth_leaper": {
        "type": "minion",
        "name": "Metaltooth Leaper",
        "description": "Battlecry: Give your other Mechs +2 Attack.",
        "attack": 3,
        "health": 3,
        "tier": 2,
        "cost": 3
    },
    
    # Tier 3 Cards (13 copies each)
    "rat_pack": {
        "type": "minion",
        "name": "Rat Pack",
        "description": "Deathrattle: Summon a number of 1/1 Rats equal to this minion's Attack.",
        "attack": 2,
        "health": 2,
        "tier": 3,
        "cost": 3
    },
    "shifter_zerus": {
        "type": "minion",
        "name": "Shifter Zerus",
        "description": "Each turn this is in your hand, transform it into a random minion.",
        "attack": 1,
        "health": 1,
        "tier": 3,
        "cost": 3
    },
    
    # Tier 4 Cards (11 copies each)
    "savannah_highmane": {
        "type": "minion",
        "name": "Savannah Highmane",
        "description": "Deathrattle: Summon two 2/2 Hyenas.",
        "attack": 6,
        "health": 5,
        "tier": 4,
        "cost": 3
    },
    "cave_hydra": {
        "type": "minion",
        "name": "Cave Hydra",
        "description": "Also damages the minions next to whomever this attacks.",
        "attack": 2,
        "health": 4,
        "tier": 4,
        "cost": 3
    },
    
    # Tier 5 Cards (9 copies each)
    "baron_geddon": {
        "type": "minion",
        "name": "Baron Geddon",
        "description": "At the end of your turn, deal 2 damage to ALL other characters.",
        "attack": 7,
        "health": 5,
        "tier": 5,
        "cost": 3
    },
    "lightfang_enforcer": {
        "type": "minion",
        "name": "Lightfang Enforcer",
        "description": "At the end of your turn, give a friendly minion of each minion type +2/+2.",
        "attack": 2,
        "health": 2,
        "tier": 5,
        "cost": 3
    },
    
    # Tier 6 Cards (6 copies each)
    "kalecgos": {
        "type": "minion",
        "name": "Kalecgos",
        "description": "Your first Battlecry each turn triggers twice.",
        "attack": 4,
        "health": 12,
        "tier": 6,
        "cost": 3
    },
    "zapp_slywick": {
        "type": "minion",
        "name": "Zapp Slywick",
        "description": "Always attacks the enemy with the lowest Attack.",
        "attack": 7,
        "health": 10,
        "tier": 6,
        "cost": 3
    },
    
    # Example Spell (for testing different card types)
    "coin": {
        "type": "spell",
        "name": "The Coin",
        "description": "Gain 1 Gold.",
        "tier": 1,
        "cost": 0
    }
}

# Helper functions for working with the card database
static func get_card_data(card_id: String) -> Dictionary:
    """Get card data by ID, returns empty dict if not found"""
    return CARDS.get(card_id, {})

static func get_cards_by_tier(tier: int) -> Array:
    """Get all card IDs for a specific tier"""
    var cards_in_tier = []
    for card_id in CARDS.keys():
        if CARDS[card_id].get("tier", 0) == tier:
            cards_in_tier.append(card_id)
    return cards_in_tier

static func get_all_card_ids() -> Array:
    """Get all card IDs in the database"""
    return CARDS.keys() 