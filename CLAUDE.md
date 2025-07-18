# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OpenBattlefields is a multiplayer auto-battler card game built with Godot 4.4, inspired by Hearthstone's Battlegrounds. The game follows a two-phase loop: Tavern Phase (buying/placing cards) and Combat Phase (automatic battles).

## Running the Project

### Development Commands
```bash
# Run the game in Godot editor
godot --editor

# Run the game directly
godot

# Run a specific scene
godot res://main_menu.tscn
```

### Working with Godot
- Main scene: `main_menu.tscn`
- Project settings: `project.godot`
- All game logic in GDScript (`.gd` files)
- Scene files (`.tscn`) define UI and game objects

## Architecture Overview

### Core Design Pattern: Blueprint vs Object
- **CardData**: Raw data defining cards in `CARD_DATABASE` (no visuals)
- **Game Piece** (`card.tscn`): Visual representation that displays CardData

### Autoloaded Singletons (Global Scripts)
- `GameState`: Central game state management
- `CardFactory`: Card creation utilities
- `DragDropManager`: Drag and drop functionality
- `GameModeManager`: Game mode management
- `SceneManager`: Scene transitions
- `SettingsManager`: Game settings
- `NetworkManager`: Multiplayer networking (new)

### Key Systems
1. **Card System**: Database-driven with factory pattern
2. **Combat System**: Deterministic auto-battler logic
3. **Shop System**: Card purchasing during tavern phase
4. **Buff System**: Stat modifications and abilities
5. **Network System**: Multiplayer support (in development)

## Code Style Requirements

### Naming Conventions (from .cursorrules)
- **Files**: `snake_case.gd`, `snake_case.tscn`
- **Classes**: `class_name PascalCase`
- **Variables/Functions**: `snake_case`
- **Constants**: `ALL_CAPS_SNAKE_CASE`
- **Nodes**: `PascalCase` in scene tree
- **Signals**: `snake_case` past tense (e.g., `card_played`)

### Best Practices
- Use strict typing for all variables and functions
- Use `@onready` for node references
- Prefer composition over inheritance
- Use signals for loose coupling
- Keep methods under 30 lines
- Implement proper cleanup in `_exit_tree()`

### Performance Guidelines
- Use object pooling for frequently spawned objects
- Prefer packed arrays over regular arrays
- Minimize scene tree depth
- Use physics layers efficiently

## Current Development Focus

The project is actively implementing multiplayer functionality:
- Network manager implementation
- Player state system for multiple players
- Converting single-player logic to multiplayer
- UI updates for opponent representation

## Important Files to Know

### Game Logic
- `game_state.gd`: Central game state and phase management
- `card_factory.gd`: Card creation and initialization
- `combat_manager.gd`: Auto-battle resolution
- `shop_manager.gd`: Tavern phase shop logic

### UI/Scenes
- `main_menu.tscn/gd`: Entry point
- `multiplayer_lobby.tscn/gd`: Multiplayer setup
- `game_board.tscn/gd`: Main game scene
- `card.tscn/gd`: Universal card representation

### Data
- `CARD_DATABASE` in various files: Card definitions
- `buff_system.gd`: Buff/debuff implementations

## Testing Approach

Currently no automated tests. Manual testing through:
1. Run game with `godot`
2. Test single-player flow first
3. Test multiplayer with multiple instances

## Documentation

Comprehensive documentation in `_docs/` directory:
- `godot_auto_battler_doc.md`: Core game design
- `multiplayer_implementation.md`: Network architecture plan
- `buff_system.md`: Buff system details
- `game_implementation_*.md`: Development phases