# Game Implementation Plan - Phase 1: Tavern System

## Game Design Overview

We are building a 1v1 auto-battler inspired by Hearthstone Battlegrounds. This document outlines the design and implementation plan for Phase 1: the Tavern/Shop system.

### Core Game Loop (Phase 1 Focus)
1. **Tavern Phase**: Players use gold to buy minions from a shop and arrange them on their board
2. **Combat Phase**: Boards fight automatically (to be implemented in Phase 2)

### Architecture Philosophy
- **CardData**: Static data blueprints stored in `CARD_DATABASE` 
- **Game Pieces**: Visual representations (`card.tscn`) that display CardData and handle interactions
- Clear separation between data and presentation

## Game Systems Design

### Gold System
- **Starting Gold**: 3 gold on turn 1
- **Gold Progression**: Max gold increases by 1 each turn from turns 2-8
  - Turn 1: 3 gold
  - Turn 2: 4 gold  
  - Turn 3: 5 gold
  - ...
  - Turn 8+: 10 gold (maximum)
- **Gold Refresh**: Full gold restored at start of each turn
- **Card Cost**: 3 gold per card (standard)

### Shop System
- **Shop Tiers**: 6 tiers total, upgradeable by player
- **Shop Sizes by Tier**:
  - Tier 1: 3 cards
  - Tiers 2-3: 4 cards  
  - Tiers 4-5: 5 cards
  - Tier 6: 6 cards
- **Card Pool Distribution**:
  - Tier 1: 18 copies per card
  - Tier 2: 15 copies per card
  - Tier 3: 13 copies per card
  - Tier 4: 11 copies per card
  - Tier 5: 9 copies per card
  - Tier 6: 6 copies per card

### Card Database Structure
```gdscript
const CARD_DATABASE = {
    "card_id": {
        "type": "minion",        # minion, spell, etc.
        "name": "Card Name",
        "description": "Card description",
        "attack": 3,             # minions only
        "health": 2,             # minions only
        "tier": 1,               # shop tier (1-6)
        "cost": 3                # gold cost
    }
}
```

## Implementation Plan

### Step 1: Update Card Database
- Replace existing `CARD_DATA` with comprehensive `CARD_DATABASE`
- Add tier information to all cards
- Include sample cards for each tier (2-3 cards per tier for testing)
- Add cost field (defaulting to 3 for minions)

### Step 2: Enhance Card Scene (`card.tscn`/`card.gd`)
- Add UI elements: `AttackLabel`, `HealthLabel` 
- Update `setup_card_data()` to handle different card types
- Add safe handling for missing attack/health values (spells)
- Ensure proper visual hierarchy and layout

### Step 3: Restructure Game Board Layout (`game_board.tscn`)
- Rename `PlayerHand` → `PlayerBoard`
- Add `ShopArea` container above PlayerBoard
- Add UI elements:
  - `GoldLabel` (display current/max gold)
  - `ShopTierLabel` (display current shop tier)
  - `RefreshShopButton`
  - `UpgradeShopButton`
  - `EndTurnButton` (if not already present)

### Step 4: Implement Core Game State (`game_board.gd`)
- Add game state variables:
  - `current_turn: int`
  - `current_gold: int`
  - `max_gold: int`
  - `shop_tier: int = 1`
  - `card_pool: Dictionary` (tracks remaining cards)
- Add turn management system
- Add gold calculation logic

### Step 5: Implement Shop Logic
- `refresh_shop()`: Clear shop, populate with random cards from current tier
- `initialize_card_pool()`: Set up card availability tracking
- `get_random_card_for_tier(tier: int)`: Return random card data respecting pool limits
- Card purchase logic: validate gold, move card from shop to board, deduct gold

### Step 6: Implement Player Actions
- Connect UI buttons to functions:
  - Refresh shop (costs gold - typically 1)
  - Upgrade shop tier (costs gold - typically 5)
  - End turn (advance turn, refresh gold, refresh shop)
- Handle card clicking in shop vs. board differently

### Step 7: Game Flow Integration
- `start_new_turn()`: Increment turn, calculate max gold, refresh current gold
- Update UI displays when state changes
- Basic turn progression loop

## Technical Considerations

### Card Pool Management
- Track remaining copies of each card globally
- When card is purchased, decrement pool count
- When card is sold/destroyed, increment pool count  
- Prevent showing cards with 0 remaining copies

### UI State Management
- Update gold display whenever gold changes
- Update shop tier display when tier changes
- Disable buttons when actions aren't available (insufficient gold, etc.)
- Visual feedback for purchased/unavailable cards

### Single Player Focus
- Remove/disable multiplayer networking for Phase 1
- Focus on local state management
- Prepare structure for future multiplayer integration

## Testing Strategy

### Phase 1 Testing Goals
- Verify gold progression (turns 1-10+)
- Test shop refresh with different tiers
- Validate card pool depletion (buy many of same card)
- Test shop tier upgrades
- Verify card purchase/board management

### Sample Cards for Testing
- Include at least 2 cards per tier
- Mix of different attack/health values
- Include at least one spell for testing non-minion cards

## Future Phase Integration Points

### Combat System Hooks (Phase 2)
- Player board state easily accessible
- Card positioning matters for combat
- Health tracking for player characters

### Advanced Features (Later Phases)
- Card effects and abilities
- Card synergies and tribes
- Advanced shop mechanics (freeze, etc.)
- Multiplayer synchronization

This implementation plan provides a solid foundation for the auto-battler while maintaining clean architecture for future expansion. 