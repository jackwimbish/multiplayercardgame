# Multiplayer Implementation Plan for OpenBattlefields

## Current Architecture Analysis

The codebase is already well-positioned for multiplayer with several key design decisions:

**✅ Already Multiplayer-Ready:**
- **GameState singleton**: Centralized state management
- **Event-driven architecture**: Signals for state changes
- **Separation of concerns**: Game logic separate from UI
- **Turn-based structure**: Natural fit for network synchronization
- **Auto-combat system**: Deterministic combat that can be replicated

**🔧 Needs Multiplayer Adaptation:**
- **Single-player state**: Currently assumes one player
- **Local UI**: No opponent representation
- **Direct state modification**: Needs validation/authorization layer

## Multiplayer Implementation Plan

### Phase 1: Network Foundation (Core Infrastructure)

**1. Godot's Built-in Networking**
- Use Godot's `MultiplayerAPI` with ENet backend
- Implement client-server architecture (one player hosts)
- Create `NetworkManager` autoload singleton
- Add connection/disconnection handling

**2. Network State Synchronization**
- Convert `GameState` to support multiple players
- Add `PlayerState` class to track individual player data
- Implement authoritative server validation
- Create network-safe state update methods

**3. Network Message System**
- Design message protocol for game actions
- Implement RPC (Remote Procedure Call) system
- Add message validation and error handling
- Create action queue system for turn management

### Phase 2: Game Logic Adaptation

**1. Multi-Player Game State**
```gdscript
# PlayerState class structure
PlayerState {
  - player_id: String
  - player_name: String
  - current_gold: int
  - player_health: int
  - hand_cards: Array
  - board_minions: Array
  - shop_state: Dictionary
}

# Updated GameState structure
GameState {
  - players: Dictionary[player_id, PlayerState]
  - current_phase: Phase (SHOP, COMBAT, GAME_OVER)
  - turn_number: int
  - host_player_id: String
}
```

**2. Turn Management System**
- Implement simultaneous shop phases (both players shop at same time)
- Add turn timer system (optional)
- Create combat resolution synchronization
- Handle player disconnection gracefully

**3. Shared Card Pool**
- Modify `CardDatabase` to support shared pool between players
- Implement card availability synchronization
- Handle race conditions for limited cards
- Add pool state broadcast system

### Phase 3: Combat System Multiplayer

**1. Combat Matchmaking**
- Remove `enemy_boards.gd` static system
- Implement real opponent board representation
- Add combat pairing logic (1v1 for now)
- Create combat result synchronization

**2. Deterministic Combat**
- Ensure identical combat results on both clients
- Implement shared random seed system
- Add combat replay/verification system
- Handle combat desynchronization recovery

**3. Health & Elimination**
- Track both players' health
- Implement elimination logic
- Add game over conditions
- Create victory/defeat handling

### Phase 4: UI & UX for Multiplayer

**1. Opponent Representation**
- Add opponent board display area
- Show opponent's minion count, health, etc.
- Implement opponent card back representation
- Add opponent action indicators

**2. Lobby System Enhancement**
- Expand current `multiplayer_lobby.tscn`
- Add host/join game functionality
- Implement player list and ready system
- Add game settings configuration

**3. Real-time Updates**
- Add opponent shop tier/gold display
- Show opponent actions in real-time
- Implement spectator mode foundation
- Add connection status indicators

### Phase 5: Network Reliability & Polish

**1. Error Handling**
- Add reconnection system
- Implement state recovery mechanisms
- Handle partial disconnections
- Add timeout management

**2. Security & Validation**
- Server-side action validation
- Prevent cheating/manipulation
- Add rate limiting
- Implement anti-cheat measures

**3. Performance Optimization**
- Minimize network traffic
- Implement delta synchronization
- Add compression for large state updates
- Optimize for mobile networks

## Technical Implementation Strategy

### Network Architecture Choice
**Client-Server Model** (one player hosts):
- **Pros**: Simpler than dedicated server, authoritative validation
- **Cons**: Host advantage, host disconnection issues
- **Rationale**: Best fit for indie game scope and Godot's networking

### Key Autoloads to Add/Modify

**New Autoloads:**
- `NetworkManager` - Connection & message handling
- `PlayerManager` - Player-specific logic
- `CombatSynchronizer` - Combat determinism

**Modified Autoloads:**
- `GameState` - Multi-player state management
- `ShopManager` - Add network validation for purchases
- `CombatManager` - Add opponent integration
- `UIManager` - Add opponent UI elements
- `DragDropManager` - Add network action broadcasting
- `SceneManager` - Add lobby ↔ game transitions

### Integration with Existing Systems

**ShopManager Integration:**
- Add network validation for card purchases
- Implement shared shop refresh synchronization
- Handle simultaneous purchase conflicts

**CombatManager Integration:**
- Replace static enemy boards with real opponent data
- Add combat synchronization protocols
- Implement damage/health updates across network

**UIManager Integration:**
- Add opponent information displays
- Implement network status indicators
- Show real-time opponent actions

**DragDropManager Integration:**
- Broadcast drag actions to opponent
- Add network latency compensation
- Implement action confirmation system

### Development Phases Priority

1. **Foundation First**: Get basic 2-player connection working
2. **Core Gameplay**: Implement shop phase multiplayer
3. **Combat Integration**: Add real opponent combat
4. **Polish & Reliability**: Handle edge cases and disconnections
5. **Advanced Features**: Spectating, tournaments, etc.

## Migration Strategy

### Backwards Compatibility
- Keep practice mode fully functional
- Use feature flags to toggle multiplayer features
- Maintain single-player performance
- Gradual rollout of multiplayer components

### Testing Approach
- **Local Network Testing**: Same machine, different ports
- **LAN Testing**: Multiple devices on same network
- **Internet Testing**: Port forwarding and external connections
- **Stress Testing**: Simulated network issues and packet loss

### Implementation Milestones

**Milestone 1: Basic Connection**
- NetworkManager autoload created
- Host/join lobby functionality
- Basic message passing between clients

**Milestone 2: State Synchronization**
- PlayerState class implementation
- Multi-player GameState conversion
- Basic turn synchronization

**Milestone 3: Shop Phase Multiplayer**
- Shared card pool implementation
- Purchase conflict resolution
- Shop state synchronization

**Milestone 4: Combat Integration**
- Real opponent board representation
- Combat result synchronization
- Health/damage network updates

**Milestone 5: Full Feature Parity**
- Complete UI for multiplayer
- Error handling and reconnection
- Performance optimization

## Technical Considerations

### Network Protocol Design
```gdscript
# Example message structure
{
  "type": "PURCHASE_CARD",
  "player_id": "player_123",
  "card_id": "goblin_warrior",
  "timestamp": 1234567890,
  "validation_hash": "abc123"
}
```

### State Validation
- All game actions validated by host
- Rollback mechanism for invalid actions
- Checksums for critical game state
- Regular state synchronization points

### Performance Optimization
- Send only delta changes, not full state
- Compress large data structures
- Batch multiple small updates
- Prioritize critical vs. cosmetic updates

### Security Measures
- Input validation on all network messages
- Rate limiting to prevent spam/DoS
- Action verification against game rules
- Player authentication (simple token system)

## Future Considerations

### Scalability
- Foundation for dedicated server architecture
- Support for larger player counts (4+ players)
- Tournament and matchmaking systems
- Spectator mode and replay system

### Advanced Features
- Cross-platform compatibility
- Mobile network optimization
- Voice chat integration
- Advanced anti-cheat systems

## Risk Assessment

**High Risk:**
- Network desynchronization during combat
- Player disconnection during critical moments
- Race conditions in shared card pool

**Medium Risk:**
- Performance issues with network latency
- Complex state synchronization bugs
- Platform-specific networking issues

**Low Risk:**
- UI layout adjustments for multiplayer
- Backwards compatibility with practice mode
- Basic connection establishment

## Success Metrics

**Technical Success:**
- < 200ms action confirmation time
- < 5% packet loss tolerance
- Successful reconnection in 95% of cases

**Gameplay Success:**
- Smooth simultaneous shop phase
- Identical combat results on all clients
- Intuitive opponent interaction feedback

**User Experience Success:**
- Easy lobby creation and joining
- Clear connection status indicators
- Graceful handling of network issues 