# Single Source of Truth Architecture Implementation Plan

## Overview
This document outlines the implementation plan to refactor the multiplayer card game from its current mixed-authority architecture to a clean host-authoritative Single Source of Truth (SSOT) architecture.

## Goal Architecture

### Core Principles
1. **Host Authority**: Only the host can modify game state
2. **Client Display**: Clients only display state, never modify it
3. **Request-Response Flow**: All client actions are requests to the host
4. **One-Way State Flow**: State flows from Host → Clients → UI

### Data Flow
```
Client Action → RPC Request → Host Validation → Host Execution → State Update → Sync to All Clients → UI Update
```

## Current Architecture Problems

### 1. Mixed Authority
- Clients can generate shop cards locally
- Clients modify local state before validation
- Both host and client code paths exist for the same actions

### 2. Multiple Sources of Truth
- `ShopManager.current_shop_cards` vs `PlayerState.shop_cards`
- `ShopManager.frozen_cards` vs `PlayerState.frozen_card_ids`
- Local UI state vs network-synced state

### 3. Race Conditions
- Shop updates from multiple sources
- Optimistic UI updates before host validation
- Signal connections causing cascading updates

## Implementation Plan

### Phase 1: Establish Clear Separation of Concerns

#### 1.1 Create Display-Only Managers
**Task**: Refactor ShopManager to be display-only
- Remove all state tracking (`current_shop_cards`, `frozen_cards`)
- Remove all game logic (card generation, validation)
- Keep only display functions:
  ```gdscript
  func display_shop(card_ids: Array)
  func display_freeze_state(frozen_card_ids: Array)
  ```

#### 1.2 Create Host-Only Game Logic
**Task**: Move all game logic to host-only functions
- Create `HostGameLogic` class or namespace in GameState
- Move shop generation, purchase validation, etc.
- Ensure these functions only run on host

#### 1.3 Standardize Client Actions
**Task**: Create unified action request system
- All client actions go through a single RPC endpoint
- Example: `request_game_action(action_type: String, params: Dictionary)`
- Remove all direct game state modifications on clients

### Phase 2: Unify State Management

#### 2.1 Single State Location
**Task**: Ensure all game state lives in PlayerState/GameState only
- Remove duplicate state tracking in UI managers
- PlayerState is the ONLY source of truth for player data
- GameState is the ONLY source of truth for game data

#### 2.2 Remove Local State Modifications
**Task**: Audit and remove all client-side state changes
- Find all places where clients modify GameState
- Replace with RPC requests to host
- Remove optimistic updates

#### 2.3 Implement State Sync Protocol
**Task**: Create reliable state synchronization
- Host pushes full player state after any change
- Clients never modify received state
- Add versioning to prevent out-of-order updates

### Phase 3: Refactor Game Actions

#### 3.1 Purchase System
**Current Flow (Broken)**:
```
Client: Drag card → Validate locally → Update UI → Send RPC → Host validates → Sync
```

**New Flow**:
```
Client: Drag card → Send purchase request → Wait
Host: Receive request → Validate → Execute → Sync new state
Client: Receive state → Update display
```

**Implementation**:
- Remove `can_purchase_card()` from client execution path
- Remove `_add_card_to_hand_direct()` on clients
- Host handles all validation and execution
- Client only updates display from synced state

#### 3.2 Shop Refresh System
**Current Flow (Broken)**:
```
Client: Click refresh → Generate random cards → Update display → Send RPC
```

**New Flow**:
```
Client: Click refresh → Send refresh request → Wait
Host: Receive request → Return cards to pool → Generate new cards → Sync
Client: Receive state → Display new shop
```

**Implementation**:
- Remove all card generation on clients
- Remove `refresh_shop()` client execution
- Host handles all pool management
- Client displays whatever is in PlayerState.shop_cards

#### 3.3 Freeze System
**Implementation**:
- Client sends freeze toggle request
- Host updates PlayerState.frozen_card_ids
- State sync triggers display update
- Remove local freeze tracking

### Phase 4: Simplify UI Updates

#### 4.1 Remove Signal Cascades
**Task**: Simplify UI update flow
- Remove shop_cards_changed signal connections
- UI updates only from explicit display calls
- No automatic updates from state changes

#### 4.2 Centralized UI Update
**Task**: Single point of UI update
```gdscript
func update_player_display(player_state: PlayerState):
    shop_manager.display_shop(player_state.shop_cards)
    shop_manager.display_freeze_state(player_state.frozen_card_ids)
    ui_manager.update_gold_display(player_state.current_gold)
    ui_manager.update_hand_display(player_state.hand_cards)
```

### Phase 5: Testing and Validation

#### 5.1 Remove Practice Mode Divergence
**Task**: Ensure multiplayer and practice use same code paths
- Practice mode uses same request/response system
- Host logic runs locally in practice mode
- No separate code paths

#### 5.2 Add State Validation
**Task**: Add checksums and validation
- Validate state consistency across clients
- Log any divergence
- Add recovery mechanisms

## Implementation Order

1. **Start with Shop Display** (Phase 1.1)
   - Highest impact, most problematic currently
   - Clear separation makes other changes easier

2. **Refactor Purchase Flow** (Phase 3.1)
   - Most user-facing feature
   - Good test case for new architecture

3. **Unify State Management** (Phase 2)
   - Foundation for all other changes
   - Must be solid before proceeding

4. **Refactor Remaining Actions** (Phase 3.2, 3.3)
   - Apply learned patterns
   - Should be straightforward after purchase

5. **Cleanup and Testing** (Phase 4, 5)
   - Remove old code
   - Ensure consistency

## Code Examples

### Before (Mixed Authority)
```gdscript
# In ShopManager (runs on all clients)
func refresh_shop():
    var new_cards = []
    for i in range(shop_size):
        var card = get_random_card()  # BAD: Client generates state
        new_cards.append(card)
    current_shop_cards = new_cards  # BAD: Local state
    display_cards(new_cards)
```

### After (Host Authority)
```gdscript
# In ShopManager (display only)
func display_shop(card_ids: Array):
    clear_display()
    for card_id in card_ids:
        create_card_visual(card_id)

# In NetworkManager (client side)
func request_refresh_shop():
    rpc_id(host_id, "handle_refresh_request", local_player_id)

# In NetworkManager (host side)
func handle_refresh_request(player_id: int):
    if not is_host: return
    
    # Validate request
    var player = GameState.players[player_id]
    if player.current_gold < REFRESH_COST:
        return
    
    # Execute on host
    player.current_gold -= REFRESH_COST
    var new_cards = GameState.generate_shop_cards(player.shop_tier)
    player.shop_cards = new_cards
    
    # Sync to all
    sync_player_state.rpc(player_id, player.to_dict())
```

## Success Criteria

1. **No Client-Side State Generation**: Clients never create game objects
2. **Single Update Path**: UI updates only from state sync
3. **Predictable Flow**: Every action follows request → validate → execute → sync
4. **No Race Conditions**: State changes are atomic and ordered
5. **Clean Separation**: Display code contains no game logic

## Risks and Mitigation

### Risk: Large Refactor Breaking Existing Features
**Mitigation**: Implement incrementally, test each phase

### Risk: Network Latency Making Game Feel Sluggish
**Mitigation**: 
- Add loading indicators for actions
- Consider predictive display (show likely outcome, correct if needed)
- Optimize network messages

### Risk: Increased Complexity
**Mitigation**: 
- Document clear patterns
- Create helper functions for common operations
- Maintain strict architectural boundaries