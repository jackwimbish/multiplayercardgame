# SSOT Implementation Plan - Detailed Version

## Architecture Overview

### Core Components

1. **NetworkManager** (All clients)
   - Handles RPC communication only
   - Receives state syncs and triggers display updates
   - Routes action requests to host

2. **HostGameLogic** (Host only - new singleton)
   - Processes all game actions
   - Validates and executes game rules
   - Returns success/failure with state changes
   - Never directly updates UI

3. **GameState** (All clients)
   - Read-only on clients
   - Modified only by HostGameLogic on host
   - Single source of truth for game data

4. **Display Managers** (All clients)
   - ShopManager: Display shop cards only
   - UIManager: Display UI elements only
   - No game logic, no state storage

### Data Flow

```
1. Client Action (button click, drag, etc.)
   ↓
2. NetworkManager.request_game_action.rpc_id(host_id, "action_type", params)
   ↓
3. Host: NetworkManager.request_game_action() 
   ↓
4. Host: HostGameLogic.process_game_action()
   ↓
5. Host: GameState updates
   ↓
6. Host: NetworkManager.sync_player_state.rpc()
   ↓
7. All Clients: Receive sync, update GameState
   ↓
8. All Clients: _update_local_player_display()
```

## Implementation Details

### Phase 1: Create HostGameLogic Singleton

**File: host_game_logic.gd**
```gdscript
# Autoload singleton
extends Node

func process_game_action(player_id: int, action: String, params: Dictionary) -> Dictionary:
    """
    Process any game action. Returns result dictionary:
    {
        "success": bool,
        "error": String (if failed),
        "state_changes": Dictionary (player states that changed)
    }
    """
    
    if not GameState.players.has(player_id):
        return {"success": false, "error": "Player not found"}
    
    match action:
        "purchase_card":
            return _process_purchase(player_id, params)
        "refresh_shop":
            return _process_refresh(player_id, params)
        "toggle_freeze":
            return _process_freeze_toggle(player_id, params)
        "upgrade_shop":
            return _process_upgrade(player_id, params)
        _:
            return {"success": false, "error": "Unknown action: " + action}

func _process_purchase(player_id: int, params: Dictionary) -> Dictionary:
    var card_id = params.get("card_id", "")
    var shop_slot = params.get("shop_slot", -1)
    
    # All validation and execution logic here
    # Returns success/failure with updated states
```

### Phase 2: Refactor NetworkManager

**Changes to network_manager.gd:**

1. **Add unified RPC endpoint:**
```gdscript
@rpc("any_peer", "call_remote", "reliable")
func request_game_action(action: String, params: Dictionary):
    var sender_id = multiplayer.get_remote_sender_id()
    
    if not is_host:
        print("ERROR: Non-host received game action request")
        return
    
    var result = HostGameLogic.process_game_action(sender_id, action, params)
    
    if result.success:
        # Sync all affected player states
        for player_id in result.state_changes:
            var state_dict = GameState.players[player_id].to_dict()
            sync_player_state.rpc(player_id, state_dict)
        
        # Sync card pool if it changed
        if result.get("pool_changed", false):
            sync_card_pool.rpc(GameState.shared_card_pool)
    else:
        # Send error to requesting player only
        show_error_message.rpc_id(sender_id, result.error)
```

2. **Update state sync to trigger display:**
```gdscript
@rpc("authority", "call_local", "reliable")
func sync_player_state(player_id: int, state_data: Dictionary):
    if not GameState.players.has(player_id):
        GameState.players[player_id] = PlayerState.new()
    
    GameState.players[player_id].from_dict(state_data)
    
    # If this is the local player, update all displays
    if player_id == local_player_id:
        _update_local_player_display()

func _update_local_player_display():
    var player = GameState.get_local_player()
    if not player:
        return
    
    # Get full card data for display
    var shop_cards_data = []
    for card_id in player.shop_cards:
        shop_cards_data.append(CardDatabase.get_card_data(card_id))
    
    # Update all displays with explicit calls
    var game_board = get_tree().get_first_node_in_group("game_board")
    if game_board:
        game_board.shop_manager.display_shop(shop_cards_data, player.frozen_card_ids)
        game_board.ui_manager.display_gold(player.current_gold, player.player_base_gold)
        game_board.ui_manager.display_shop_tier(player.shop_tier)
        
        # Update hand display
        var hand_cards_data = []
        for card_id in player.hand_cards:
            hand_cards_data.append(CardDatabase.get_card_data(card_id))
        game_board.ui_manager.display_hand(hand_cards_data)
```

3. **Remove all old individual RPCs:**
- Delete: `request_purchase_card`, `request_refresh_shop`, `request_upgrade_shop`
- Delete: `validate_and_execute_*` functions
- Keep: `sync_player_state`, `sync_card_pool`

### Phase 3: Refactor ShopManager to Display-Only

**New shop_manager.gd structure:**
```gdscript
class_name ShopManager
extends RefCounted

var shop_area: Container
var ui_manager: UIManager

func _init(shop_area_ref: Container, ui_manager_ref: UIManager):
    shop_area = shop_area_ref
    ui_manager = ui_manager_ref

func display_shop(cards_data: Array, frozen_card_ids: Array):
    """Display shop cards with freeze state"""
    # Clear existing display
    for child in shop_area.get_children():
        if child.name != "ShopAreaLabel":
            child.queue_free()
    
    # Create visual cards
    for i in range(cards_data.size()):
        var card_data = cards_data[i]
        var card_id = card_data.get("id", "")
        
        # Create visual card
        var card_visual = CardFactory.create_card(card_data, card_id)
        
        # Apply freeze visual if frozen
        if card_id in frozen_card_ids:
            card_visual.modulate = Color(0.7, 0.9, 1.0, 1.0)
        
        # Store metadata for drag handling
        card_visual.set_meta("shop_slot", i)
        card_visual.set_meta("card_id", card_id)
        
        shop_area.add_child(card_visual)

func handle_card_drag(card_visual: Node) -> Dictionary:
    """Return drag metadata for action request"""
    return {
        "card_id": card_visual.get_meta("card_id", ""),
        "shop_slot": card_visual.get_meta("shop_slot", -1)
    }
```

**Remove from ShopManager:**
- All state tracking (current_shop_cards, frozen_cards)
- All game logic (refresh_shop, purchase_card, etc.)
- All RPC communication
- All signal connections

### Phase 4: Update UI Action Handlers

**In game_board.gd:**
```gdscript
func _on_refresh_shop_button_pressed():
    if GameModeManager.is_in_multiplayer_session():
        ui_manager.show_waiting_indicator("refresh_button")
        NetworkManager.request_game_action.rpc_id(
            GameState.host_player_id,
            "refresh_shop",
            {}
        )
    else:
        # Practice mode - direct execution
        _handle_practice_mode_refresh()

func _handle_shop_to_hand_drop(card):
    if GameModeManager.is_in_multiplayer_session():
        var drag_data = shop_manager.handle_card_drag(card)
        ui_manager.show_waiting_indicator("shop")
        NetworkManager.request_game_action.rpc_id(
            GameState.host_player_id,
            "purchase_card",
            drag_data
        )
        # Remove the dragged card visual
        card.queue_free()
    else:
        # Practice mode
        _handle_practice_mode_purchase(card)
```

### Phase 5: Remove All Signals

**Changes to PlayerState:**
```gdscript
class_name PlayerState
extends RefCounted

# Remove all signals
# signal shop_cards_changed(new_shop_cards: Array)
# signal gold_changed(new_gold: int)

# Remove notify functions
# func notify_shop_changed()
# func notify_gold_changed()

# Keep only data and from_dict/to_dict functions
```

### Phase 6: Add Error Handling and Feedback

**Add to NetworkManager:**
```gdscript
@rpc("authority", "call_remote", "reliable")
func show_error_message(message: String):
    var game_board = get_tree().get_first_node_in_group("game_board")
    if game_board and game_board.ui_manager:
        game_board.ui_manager.show_flash_message(message, 2.0, "error")

@rpc("authority", "call_local", "reliable")
func show_success_message(message: String):
    var game_board = get_tree().get_first_node_in_group("game_board")
    if game_board and game_board.ui_manager:
        game_board.ui_manager.show_flash_message(message, 1.5, "success")
```

**Add to UIManager:**
```gdscript
var waiting_indicators = {}

func show_waiting_indicator(element_name: String):
    # Show spinner or disable button
    if element_name == "refresh_button" and refresh_button:
        refresh_button.disabled = true
        refresh_button.text = "Refreshing..."
    waiting_indicators[element_name] = true

func hide_waiting_indicator(element_name: String):
    # Hide spinner or enable button
    if element_name == "refresh_button" and refresh_button:
        refresh_button.disabled = false
        refresh_button.text = "Refresh (1)"
    waiting_indicators.erase(element_name)

func hide_all_waiting_indicators():
    for element in waiting_indicators:
        hide_waiting_indicator(element)
    waiting_indicators.clear()
```

### Phase 7: Handle Combat and Turn Transitions

**In HostGameLogic:**
```gdscript
func advance_turn_for_all_players():
    """Called when combat ends and new turn begins"""
    # Update all player states
    var changed_players = {}
    
    for player_id in GameState.players:
        var player = GameState.players[player_id]
        
        # Update gold
        player.current_gold = player.player_base_gold + player.bonus_gold
        
        # Return old cards to pool (except frozen)
        GameState.return_cards_to_pool(player.shop_cards, player.frozen_card_ids)
        
        # Deal new cards
        var shop_size = GameState.get_shop_size_for_tier(player.shop_tier)
        GameState.deal_cards_to_shop(player_id, shop_size)
        
        changed_players[player_id] = true
    
    # Return result for NetworkManager to sync
    return {
        "success": true,
        "state_changes": changed_players,
        "pool_changed": true
    }
```

## Key Differences from Original Plan

1. **Unified RPC**: Single `request_game_action` instead of multiple RPCs
2. **HostGameLogic Singleton**: Cleaner separation than embedding in NetworkManager
3. **Display Functions**: Pass full card data, not just IDs
4. **Explicit Display Updates**: Single update function after state sync
5. **No Signals**: Complete removal for predictable data flow
6. **Waiting Indicators**: Visual feedback during network operations

## Migration Checklist

- [ ] Create HostGameLogic singleton and add to autoload
- [ ] Refactor NetworkManager to unified RPC model
- [ ] Strip ShopManager down to display-only
- [ ] Update all UI action handlers to use new request system
- [ ] Remove all signals from PlayerState
- [ ] Add error handling and waiting indicators
- [ ] Test all actions in multiplayer
- [ ] Remove old code and practice mode
- [ ] Update documentation

## Success Metrics

1. **No Desync**: Host and clients always show same state
2. **Clear Errors**: Users understand why actions fail
3. **Responsive UI**: Waiting indicators for all network operations
4. **Single Code Path**: No special cases for host vs client
5. **Maintainable**: Clear separation of concerns