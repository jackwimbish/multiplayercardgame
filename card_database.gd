# Card Database for Auto-Battler Game
# Contains all card definitions organized by tier

class_name CardDatabase

# Cache for validated card art paths
static var _card_art_cache: Dictionary = {}

# Card database for auto-battler
const CARDS = {
    # Tier 1 Cards (18 copies each)
    "rockpool_hunter": {
        "type": "minion",
        "name": "Rockpool Hunter",
        "description": "Battlecry: Give another friendly minion +1/+1.",
        "attack": 2,
        "health": 1,
        "tier": 1,
        "cost": 3,
        "abilities": [
            {
                "type": "battlecry",
                "target": "other_friendly_minion",
                "effect": {
                    "type": "buff",
                    "attack": 1,
                    "health": 1
                }
            }
        ]
    },
    "feral_prowler": {
        "type": "minion",
        "name": "Feral Prowler",
        "description": "A tier 1 beast creature",
        "attack": 2,
        "health": 2,
        "tier": 1,
        "cost": 3
    },
    "wild_stalker": {
        "type": "minion",
        "name": "Wild Stalker",
        "description": "A tier 1 beast creature",
        "attack": 2,
        "health": 3,
        "tier": 1,
        "cost": 3
    },
    "stone_sentinel": {
        "type": "minion",
        "name": "Stone Sentinel",
        "description": "A tier 1 golem creature",
        "attack": 1,
        "health": 3,
        "tier": 1,
        "cost": 3
    },
    "clay_guardian": {
        "type": "minion",
        "name": "Clay Guardian",
        "description": "A tier 1 golem creature",
        "attack": 1,
        "health": 4,
        "tier": 1,
        "cost": 3
    },
    "shadow_imp": {
        "type": "minion",
        "name": "Shadow Imp",
        "description": "A tier 1 demon creature",
        "attack": 3,
        "health": 1,
        "tier": 1,
        "cost": 3
    },
    "chaos_spawn": {
        "type": "minion",
        "name": "Chaos Spawn",
        "description": "A tier 1 demon creature",
        "attack": 3,
        "health": 2,
        "tier": 1,
        "cost": 3
    },
    
    # Tier 2 Cards (15 copies each)
    "savage_hunter": {
        "type": "minion",
        "name": "Savage Hunter",
        "description": "A tier 2 beast creature",
        "attack": 3,
        "health": 4,
        "tier": 2,
        "cost": 3
    },
    "pack_ravager": {
        "type": "minion",
        "name": "Pack Ravager",
        "description": "A tier 2 beast creature",
        "attack": 4,
        "health": 3,
        "tier": 2,
        "cost": 3
    },
    "granite_protector": {
        "type": "minion",
        "name": "Granite Protector",
        "description": "A tier 2 golem creature",
        "attack": 2,
        "health": 5,
        "tier": 2,
        "cost": 3
    },
    "crystal_colossus": {
        "type": "minion",
        "name": "Crystal Colossus",
        "description": "A tier 2 golem creature",
        "attack": 2,
        "health": 6,
        "tier": 2,
        "cost": 3
    },
    "void_stalker": {
        "type": "minion",
        "name": "Void Stalker",
        "description": "A tier 2 demon creature",
        "attack": 5,
        "health": 2,
        "tier": 2,
        "cost": 3
    },
    "doom_caller": {
        "type": "minion",
        "name": "Doom Caller",
        "description": "A tier 2 demon creature",
        "attack": 4,
        "health": 3,
        "tier": 2,
        "cost": 3
    },
    
    # Tier 3 Cards (13 copies each)
    "alpha_predator": {
        "type": "minion",
        "name": "Alpha Predator",
        "description": "A tier 3 beast creature",
        "attack": 5,
        "health": 4,
        "tier": 3,
        "cost": 3
    },
    "primal_striker": {
        "type": "minion",
        "name": "Primal Striker",
        "description": "A tier 3 beast creature",
        "attack": 4,
        "health": 5,
        "tier": 3,
        "cost": 3
    },
    "obsidian_hulk": {
        "type": "minion",
        "name": "Obsidian Hulk",
        "description": "A tier 3 golem creature",
        "attack": 3,
        "health": 6,
        "tier": 3,
        "cost": 3
    },
    "ancient_watcher": {
        "type": "minion",
        "name": "Ancient Watcher",
        "description": "A tier 3 golem creature",
        "attack": 3,
        "health": 7,
        "tier": 3,
        "cost": 3
    },
    "abyss_walker": {
        "type": "minion",
        "name": "Abyss Walker",
        "description": "A tier 3 demon creature",
        "attack": 6,
        "health": 3,
        "tier": 3,
        "cost": 3
    },
    "terror_bringer": {
        "type": "minion",
        "name": "Terror Bringer",
        "description": "A tier 3 demon creature",
        "attack": 7,
        "health": 2,
        "tier": 3,
        "cost": 3
    },
    
    # Tier 4 Cards (11 copies each)
    "apex_hunter": {
        "type": "minion",
        "name": "Apex Hunter",
        "description": "A tier 4 beast creature",
        "attack": 6,
        "health": 6,
        "tier": 4,
        "cost": 3
    },
    "ancient_prowler": {
        "type": "minion",
        "name": "Ancient Prowler",
        "description": "A tier 4 beast creature",
        "attack": 6,
        "health": 7,
        "tier": 4,
        "cost": 3
    },
    "diamond_defender": {
        "type": "minion",
        "name": "Diamond Defender",
        "description": "A tier 4 golem creature",
        "attack": 4,
        "health": 8,
        "tier": 4,
        "cost": 3
    },
    "fortress_guardian": {
        "type": "minion",
        "name": "Fortress Guardian",
        "description": "A tier 4 golem creature",
        "attack": 4,
        "health": 9,
        "tier": 4,
        "cost": 3
    },
    "nightmare_herald": {
        "type": "minion",
        "name": "Nightmare Herald",
        "description": "A tier 4 demon creature",
        "attack": 8,
        "health": 4,
        "tier": 4,
        "cost": 3
    },
    "void_reaver": {
        "type": "minion",
        "name": "Void Reaver",
        "description": "A tier 4 demon creature",
        "attack": 9,
        "health": 3,
        "tier": 4,
        "cost": 3
    },
    
    # Tier 5 Cards (9 copies each)
    "elder_beast": {
        "type": "minion",
        "name": "Elder Beast",
        "description": "A tier 5 beast creature",
        "attack": 8,
        "health": 7,
        "tier": 5,
        "cost": 3
    },
    "legendary_stalker": {
        "type": "minion",
        "name": "Legendary Stalker",
        "description": "A tier 5 beast creature",
        "attack": 7,
        "health": 8,
        "tier": 5,
        "cost": 3
    },
    "titan_construct": {
        "type": "minion",
        "name": "Titan Construct",
        "description": "A tier 5 golem creature",
        "attack": 5,
        "health": 10,
        "tier": 5,
        "cost": 3
    },
    "eternal_sentinel": {
        "type": "minion",
        "name": "Eternal Sentinel",
        "description": "A tier 5 golem creature",
        "attack": 5,
        "health": 11,
        "tier": 5,
        "cost": 3
    },
    "chaos_lord": {
        "type": "minion",
        "name": "Chaos Lord",
        "description": "A tier 5 demon creature",
        "attack": 10,
        "health": 5,
        "tier": 5,
        "cost": 3
    },
    "destruction_incarnate": {
        "type": "minion",
        "name": "Destruction Incarnate",
        "description": "A tier 5 demon creature",
        "attack": 11,
        "health": 4,
        "tier": 5,
        "cost": 3
    },
    
    # Tier 6 Cards (6 copies each)
    "mythic_predator": {
        "type": "minion",
        "name": "Mythic Predator",
        "description": "A tier 6 beast creature",
        "attack": 9,
        "health": 9,
        "tier": 6,
        "cost": 3
    },
    "eternal_hunter": {
        "type": "minion",
        "name": "Eternal Hunter",
        "description": "A tier 6 beast creature",
        "attack": 10,
        "health": 10,
        "tier": 6,
        "cost": 3
    },
    "colossal_ancient": {
        "type": "minion",
        "name": "Colossal Ancient",
        "description": "A tier 6 golem creature",
        "attack": 6,
        "health": 13,
        "tier": 6,
        "cost": 3
    },
    "worldbreaker_golem": {
        "type": "minion",
        "name": "Worldbreaker Golem",
        "description": "A tier 6 golem creature",
        "attack": 7,
        "health": 14,
        "tier": 6,
        "cost": 3
    },
    "void_tyrant": {
        "type": "minion",
        "name": "Void Tyrant",
        "description": "A tier 6 demon creature",
        "attack": 13,
        "health": 6,
        "tier": 6,
        "cost": 3
    },
    "annihilation_engine": {
        "type": "minion",
        "name": "Annihilation Engine",
        "description": "A tier 6 demon creature",
        "attack": 14,
        "health": 6,
        "tier": 6,
        "cost": 3
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

static func get_shop_available_cards_by_tier(tier: int) -> Array:
    """Get card IDs for a specific tier that are available in the shop"""
    var cards_in_tier = []
    for card_id in CARDS.keys():
        var card_data = CARDS[card_id]
        if card_data.get("tier", 0) == tier and card_data.get("shop_available", true):
            cards_in_tier.append(card_id)
    return cards_in_tier

static func get_all_shop_available_card_ids() -> Array:
    """Get all card IDs that can appear in the shop"""
    var shop_cards = []
    for card_id in CARDS.keys():
        if CARDS[card_id].get("shop_available", true):
            shop_cards.append(card_id)
    return shop_cards

static func is_card_shop_available(card_id: String) -> bool:
    """Check if a specific card can appear in the shop"""
    var card_data = get_card_data(card_id)
    return card_data.get("shop_available", true)

static func initialize_art_cache() -> void:
    """Pre-cache all card art paths - call this at game startup"""
    _card_art_cache.clear()
    print("CardDatabase: Initializing art cache...")
    
    for card_id in CARDS.keys():
        get_card_art_path(card_id)  # This will cache the path
    
    print("CardDatabase: Art cache initialized with ", _card_art_cache.size(), " entries")

static func get_card_art_path(card_id: String) -> String:
    """Get the art path for a card, with fallback to default art"""
    var default_path = "res://assets/images/cards/default/default_card_art.png"
    
    # Check cache first
    if _card_art_cache.has(card_id):
        return _card_art_cache[card_id]
    
    # Get card data to determine type and tier
    var card_data = get_card_data(card_id)
    if card_data.is_empty():
        _card_art_cache[card_id] = default_path
        return default_path
    
    var card_type = card_data.get("type", "minion")
    var specific_path = ""
    
    # Check for specific card art based on type
    match card_type:
        "spell":
            specific_path = "res://assets/images/cards/spells/%s.png" % card_id
        "minion":
            var tier = card_data.get("tier", 1)
            specific_path = "res://assets/images/cards/tier%d/%s.png" % [tier, card_id]
        _:
            # Unknown type, try default minion path
            var tier = card_data.get("tier", 1)
            specific_path = "res://assets/images/cards/tier%d/%s.png" % [tier, card_id]
    
    # Try multiple methods to check if resource exists
    var final_path = default_path
    
    # Method 1: ResourceLoader.exists (works better in exports)
    if ResourceLoader.exists(specific_path):
        final_path = specific_path
    # Method 2: Try to load the resource directly
    elif ResourceLoader.load(specific_path) != null:
        final_path = specific_path
    # Method 3: Check with FileAccess as fallback (for editor)
    elif FileAccess.file_exists(specific_path):
        final_path = specific_path
    
    # Cache the result
    _card_art_cache[card_id] = final_path
    return final_path
