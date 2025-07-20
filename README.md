# OpenBattlefields

A multiplayer auto-battler card game built with Godot 4.4. Battle against other players online by building powerful synergies with beasts, golems, and demons across 6 tiers of cards.

## Game Overview

OpenBattlefields is an auto-battler where players:
- Purchase minions from a shared shop
- Build their board by dragging cards from hand to play area
- Battle automatically against opponents each round
- Upgrade their shop tier to access more powerful minions
- Last player standing wins!

### Features

- **Real-time Multiplayer**: Host or join games with other players
- **3 Minion Types**: 
  - Beasts (balanced stats)
  - Golems (high health)
  - Demons (high attack)
- **6 Tiers**: Progress through tiers to unlock stronger minions
- **Battlecry Abilities**: Some minions have special effects when played
- **Combat Animations**: Watch your minions battle with smooth animations
- **Help System**: Built-in tutorial overlay for new players

## Getting Started

### Prerequisites

- Godot Engine 4.4 or later
- macOS, Windows, or Linux

### Running from Source

1. Clone the repository
2. Open the project in Godot 4.4
3. Run the project (F5 or Play button)

### Playing the Game

1. **Title Screen**: Choose "Host Game" or "Join Game"
2. **Host Game**: Create a lobby and share the code with friends
3. **Join Game**: Enter the lobby code to join an existing game
4. **Shop Phase**: 
   - Drag minions from shop to hand to purchase (3 gold each)
   - Drag minions from hand to board to play them
   - Drag minions from board to shop to sell (get 1 gold back)
   - Click "Upgrade Shop" to increase your tier (costs gold)
5. **Combat Phase**: Watch your minions battle automatically
6. **Win Condition**: Be the last player with health remaining

### Controls

- **Left Click + Drag**: Move cards between shop, hand, and board
- **Right Click**: Cancel pending actions (like battlecry targeting)
- **H Key**: Toggle help overlay
- **Click "Refresh"**: Get new shop options (1 gold)
- **Click "Freeze"**: Keep current shop for next turn (free)

## Project Structure

```
multiplayercardgame/
├── assets/
│   └── images/
│       ├── cards/         # Card artwork organized by tier
│       └── other/         # UI elements and backgrounds
├── *.gd                   # GDScript source files
├── *.tscn                 # Godot scene files
├── project.godot          # Project configuration
└── README.md             # This file
```

### Key Scripts

- `game_board.gd` - Main game board logic and UI
- `network_manager.gd` - Multiplayer networking
- `card_database.gd` - All card definitions
- `combat_manager.gd` - Combat resolution logic
- `host_game_logic.gd` - Server-side game state management
- `drag_drop_manager.gd` - Card dragging system

## Multiplayer Architecture

The game uses a Single Source of Truth (SSOT) architecture:
- Host player runs authoritative game logic
- All game state changes go through the host
- Clients send actions to host for validation
- Host broadcasts state updates to all clients

## Building for Release

### macOS
1. In Godot: Project → Export → Add macOS preset
2. Configure signing if needed
3. Export as .dmg or .app

### Windows
1. In Godot: Project → Export → Add Windows Desktop preset
2. Export as .exe

### Linux
1. In Godot: Project → Export → Add Linux preset
2. Export as executable

## Development

### Adding New Cards

Edit `card_database.gd` to add new cards. Follow the existing format:

```gdscript
"card_id": {
    "type": "minion",
    "name": "Card Name",
    "description": "Card description",
    "attack": 2,
    "health": 3,
    "tier": 1,
    "cost": 3
}
```

### Testing Multiplayer Locally

1. Export the game or run multiple Godot instances
2. One player hosts a game
3. Other players join using the lobby code
4. Use "localhost" as the server address for local testing

## Known Issues

- Practice mode is currently disabled (coming soon)
- Some visual effects may not appear in exported builds

## Credits

Created by Jack Wimbish
