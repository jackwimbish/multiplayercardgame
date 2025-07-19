# OLD SHOP MANAGER - DO NOT USE
# class_name ShopManager  # Commented out to avoid conflict
extends RefCounted

## Shop Manager handles all shop/tavern functionality
## Manages shop inventory, purchasing, rerolling, and tier progression

# References to UI components
var shop_area: Container
var ui_manager: UIManager

# Shop state
var current_shop_cards: Array = []  # Track current shop card IDs (Array of Strings)
var frozen_cards: Array = []  # Track frozen card IDs (Array of Strings)
var _pending_shop_update: Array = []  # Pending shop update for when returning to shop mode

# Constants
const REFRESH_COST: int = 1

signal shop_refreshed()
signal card_purchased(card_id: String, cost: int)
signal shop_upgraded(new_tier: int, cost: int)

func _init(shop_area_ref: Container, ui_manager_ref: UIManager):
    """Initialize ShopManager with required references"""
    shop_area = shop_area_ref
    ui_manager = ui_manager_ref
    
    # Connect to GameState signals
    # Note: No longer auto-refresh on tier change - player controls when to refresh
    
    # Connect to game mode changes to handle pending shop updates
    if GameState:
        GameState.game_mode_changed.connect(_on_game_mode_changed)
    
    # Connect to local player's shop changed signal for multiplayer updates
    _connect_player_signals()
    
    print("ShopManager initialized")

func _connect_player_signals():
    """Connect to the local player's signals"""
    var local_player = GameState.get_local_player()
    if local_player and not local_player.shop_cards_changed.is_connected(_on_player_shop_changed):
        local_player.shop_cards_changed.connect(_on_player_shop_changed)
        print("ShopManager: Connected to local player shop_cards_changed signal")

func _on_player_shop_changed(new_shop_cards: Array):
    """Handle when player's shop cards change (from network sync)"""
    print("ShopManager: Received shop update signal with cards: ", new_shop_cards)
    if GameModeManager.is_in_multiplayer_session():
        # Only update shop display if we're in SHOP mode
        if GameState.current_mode == GameState.GameMode.SHOP:
            print("ShopManager: Updating shop display in multiplayer mode")
            # In multiplayer, update display based on synced data
            _update_shop_display(new_shop_cards)
        else:
            print("ShopManager: Not in SHOP mode, deferring shop update until mode changes")
            # Store the pending shop update for when we return to shop mode
            _pending_shop_update = new_shop_cards
    else:
        print("ShopManager: Not in multiplayer mode, ignoring shop update signal")

func _on_game_mode_changed(new_mode: GameState.GameMode):
    """Handle game mode changes to apply pending shop updates"""
    # Try to connect player signals if not already connected
    _connect_player_signals()
    
    if new_mode == GameState.GameMode.SHOP and _pending_shop_update.size() > 0:
        print("ShopManager: Applying pending shop update after mode change")
        _update_shop_display(_pending_shop_update)
        _pending_shop_update.clear()
        
    # When returning to shop, clear frozen cards as they've been unfrozen
    if new_mode == GameState.GameMode.SHOP:
        frozen_cards.clear()
        _update_freeze_button_text()




# === SHOP SIZE AND TIER LOGIC ===
# Note: get_shop_size_for_tier() moved to GameState for central access

# === CARD SELECTION LOGIC ===

func get_random_card_for_shop(max_tier: int) -> String:
    """Get a random card ID from max_tier and below, weighted by copies in pool"""
    var weighted_cards = []
    
    # Create weighted selection based on pool copies (more copies = higher chance)
    for card_id in GameState.card_pool.keys():
        var copies_available = GameState.card_pool[card_id]
        if copies_available > 0:  # Has remaining copies
            var card_data = CardDatabase.get_card_data(card_id)
            var card_tier = card_data.get("tier", 1)
            
            # Include cards from max_tier and below that are shop-available
            if card_tier <= max_tier and card_data.get("shop_available", true):
                # Add this card_id multiple times based on copies available
                for i in range(copies_available):
                    weighted_cards.append(card_id)
    
    if weighted_cards.is_empty():
        print("Warning: No available shop cards for tier ", max_tier, " and below")
        return ""
    
    # Return random card from weighted options
    return weighted_cards[randi() % weighted_cards.size()]

# === SHOP REFRESH LOGIC ===

func refresh_shop() -> void:
    """Clear and populate the shop with random cards for current tier (respects frozen cards for auto-refresh)"""
    _refresh_shop_with_freeze_logic(false)  # Auto-refresh preserves frozen cards
    shop_refreshed.emit()

func refresh_shop_complete() -> void:
    """Completely refresh shop, unfreezing all cards (manual refresh)"""
    _refresh_shop_with_freeze_logic(true)  # Manual refresh unfreezes all
    shop_refreshed.emit()

func _refresh_shop_with_freeze_logic(unfreeze_all: bool) -> void:
    """Core refresh logic that handles frozen cards"""
    if unfreeze_all:
        # Manual refresh: unfreeze all and completely refresh
        unfreeze_all_cards()
        _clear_shop_cards()
        _populate_shop_with_new_cards()
    else:
        # Auto-refresh: preserve frozen cards, fill unfrozen slots
        _refresh_shop_preserving_frozen()

func _refresh_shop_preserving_frozen() -> void:
    """Refresh shop with preserve→unfreeze→fill algorithm"""
    var preserved_card_ids: Array = []
    
    # Collect frozen cards that are still in the shop
    for card_id in frozen_cards:
        if card_id in current_shop_cards:
            preserved_card_ids.append(card_id)
    
    # Clear shop and frozen state
    _clear_shop_cards()
    frozen_cards.clear()  # All preserved cards will start unfrozen
    
    # Add preserved cards first (leftmost positions, unfrozen)
    for card_id in preserved_card_ids:
        _add_card_to_shop(card_id)
    
    # Fill remaining slots with new random cards
    var shop_size = GameState.get_shop_size_for_tier(GameState.shop_tier)
    var slots_to_fill = shop_size - preserved_card_ids.size()
    
    for i in range(slots_to_fill):
        var card_id = get_random_card_for_shop(GameState.shop_tier)
        if card_id != "":
            _add_card_to_shop(card_id)
    
    print("Auto-refreshed shop with %d preserved cards (now unfrozen)" % preserved_card_ids.size())
    
    # Update button text after refresh
    _update_freeze_button_text()

func _clear_shop_cards() -> void:
    """Clear existing shop cards (except label)"""
    for child in shop_area.get_children():
        if child.name != "ShopAreaLabel":
            child.queue_free()
    current_shop_cards.clear()

func _update_shop_display(shop_card_ids: Array) -> void:
    """Update shop display with specific cards (for multiplayer sync)"""
    print("ShopManager: _update_shop_display called with: ", shop_card_ids)
    
    # Clear existing shop cards
    _clear_shop_cards()
    
    # Update our tracking to match what we're displaying
    current_shop_cards.clear()
    for card_id in shop_card_ids:
        current_shop_cards.append(card_id)
    
    # Create visual cards for each shop card
    for i in range(shop_card_ids.size()):
        var card_id = shop_card_ids[i]
        if card_id != "":
            # Don't use _add_card_to_shop as it appends to current_shop_cards
            # Instead, add the card directly
            var card_data = CardDatabase.get_card_data(card_id)
            var custom_handlers = {"drag_started": _on_shop_card_drag_started}
            var new_card = CardFactory.create_card(card_data, card_id, custom_handlers)
            
            # Store card_id for purchase logic
            new_card.set_meta("card_id", card_id)
            
            # Apply freeze visual if this card is frozen
            _apply_freeze_visual(new_card, is_card_frozen(card_id))
            
            shop_area.add_child(new_card)
    
    print("Shop display updated with %d cards" % shop_card_ids.size())
    print("Current shop cards tracking: ", current_shop_cards)
    shop_refreshed.emit()

func _populate_shop_with_new_cards() -> void:
    """Populate shop with new random cards for current tier"""
    var shop_size = GameState.get_shop_size_for_tier(GameState.shop_tier)
    print("Refreshing shop (tier ", GameState.shop_tier, ") with ", shop_size, " cards")
    
    # Add new random cards to shop
    for i in range(shop_size):
        var card_id = get_random_card_for_shop(GameState.shop_tier)
        if card_id != "":
            _add_card_to_shop(card_id)
    
    # Update button text after populating
    _update_freeze_button_text()

func _add_card_to_shop(card_id: String, update_tracking: bool = true) -> void:
    """Add a card to the shop area"""
    var card_data = CardDatabase.get_card_data(card_id)
    # Shop cards need custom drag handler only
    var custom_handlers = {"drag_started": _on_shop_card_drag_started}
    var new_card = CardFactory.create_card(card_data, card_id, custom_handlers)
    
    # Store card_id for purchase logic
    new_card.set_meta("card_id", card_id)
    
    # Apply freeze visual if this card is frozen
    _apply_freeze_visual(new_card, is_card_frozen(card_id))
    
    shop_area.add_child(new_card)
    
    # Only update tracking if requested (default true for normal adds)
    if update_tracking:
        current_shop_cards.append(card_id)

# Note: Card creation now handled by CardFactory autoload singleton

# === PURCHASE LOGIC ===

func can_purchase_card(card_id: String) -> Dictionary:
    """Check if a card can be purchased, return result with reason"""
    var card_data = CardDatabase.get_card_data(card_id)
    var cost = card_data.get("cost", 3)
    
    # Check affordability (use current gold from appropriate source)
    var current_gold = GameState.current_gold
    if current_gold < cost:
        return {"can_purchase": false, "reason": "insufficient_gold", "cost": cost}
    
    # Check hand space
    if ui_manager.is_hand_full():
        return {"can_purchase": false, "reason": "hand_full", "cost": cost}
    
    # Check card availability in pool (use appropriate pool)
    var available_count = 0
    if GameModeManager.is_in_multiplayer_session():
        available_count = GameState.shared_card_pool.get(card_id, 0)
    else:
        available_count = GameState.card_pool.get(card_id, 0)
    
    if available_count <= 0:
        return {"can_purchase": false, "reason": "not_available", "cost": cost}
    
    return {"can_purchase": true, "reason": "valid", "cost": cost}

func purchase_card(card_id: String) -> bool:
    """Attempt to purchase a card, return success"""
    # Check if player is eliminated
    if GameModeManager.is_in_multiplayer_session() and GameState.is_player_eliminated(GameState.local_player_id):
        print("Cannot purchase - player is eliminated")
        return false
    
    var purchase_check = can_purchase_card(card_id)
    
    if not purchase_check.can_purchase:
        _handle_purchase_failure(card_id, purchase_check)
        return false
    
    var cost = purchase_check.cost
    var card_data = CardDatabase.get_card_data(card_id)
    var card_name = card_data.get("name", "Unknown")
    
    # Route through appropriate system based on game mode
    if GameModeManager.is_in_multiplayer_session():
        # Multiplayer: Use NetworkManager RPC system
        var shop_slot = _find_card_slot_in_shop(card_id)
        if shop_slot >= 0:
            if NetworkManager.is_host:
                # Host executes directly
                print("Host purchasing card directly")
                if NetworkManager.validate_and_execute_purchase(GameState.local_player_id, card_id, shop_slot):
                    NetworkManager.sync_player_state.rpc(GameState.local_player_id, GameState.players[GameState.local_player_id].to_dict())
                    NetworkManager.sync_card_pool.rpc(GameState.shared_card_pool)
                return true
            else:
                # Client sends RPC to host
                var host_id = GameState.host_player_id
                NetworkManager.request_purchase_card.rpc_id(host_id, GameState.local_player_id, card_id, shop_slot)
                print("Client sent purchase request to host")
                return true
    else:
        # Practice mode: Direct GameState execution
        if GameState.spend_gold(cost):
            # Remove from pool
            GameState.card_pool[card_id] -= 1
            
            # Add to hand
            _add_card_to_hand_direct(card_id)
            
            # Remove from shop
            _remove_card_from_shop(card_id)
            
            card_purchased.emit(card_id, cost)
            print("Purchased ", card_name, " for ", cost, " gold - Remaining in pool: ", GameState.card_pool[card_id])
            
            # Show success message
            ui_manager.show_flash_message("Purchased %s for %d gold!" % [card_name, cost], 1.5)
            return true
    
    return false

func _find_card_slot_in_shop(card_id: String) -> int:
    """Find which slot a card is in within the shop"""
    # In multiplayer, use the player state's shop cards for consistency
    var shop_cards_to_check = current_shop_cards
    if GameModeManager.is_in_multiplayer_session():
        var local_player = GameState.get_local_player()
        if local_player:
            shop_cards_to_check = local_player.shop_cards
            print("Using player state shop cards: ", shop_cards_to_check)
    
    # Use the tracked shop cards array instead of visual container
    # This works even when the card is being dragged (removed from container)
    var slot_index = shop_cards_to_check.find(card_id)
    if slot_index >= 0:
        print("Found card ", card_id, " at shop slot ", slot_index)
    else:
        print("Card ", card_id, " not found in shop cards: ", shop_cards_to_check)
    return slot_index

func _handle_purchase_failure(card_id: String, result: Dictionary) -> void:
    """Handle and log purchase failure reasons"""
    var card_data = CardDatabase.get_card_data(card_id)
    var card_name = card_data.get("name", "Unknown")
    
    var flash_message = ""
    match result.reason:
        "insufficient_gold":
            flash_message = "Not enough gold! Need %d gold, have %d" % [result.cost, GameState.current_gold]
            print("Cannot afford ", card_name, " - costs ", result.cost, " gold, have ", GameState.current_gold)
        "hand_full":
            flash_message = "Hand is full! (%d/%d cards)" % [ui_manager.get_hand_size(), ui_manager.max_hand_size]
            print("Cannot purchase ", card_name, " - hand is full (", ui_manager.get_hand_size(), "/", ui_manager.max_hand_size, ")")
        "not_available":
            flash_message = "Card no longer available!"
            print("Card ", card_name, " no longer available in pool")
    
    # Show flash message to player
    if flash_message != "":
        ui_manager.show_flash_message(flash_message)

func _add_card_to_hand_direct(card_id: String) -> void:
    """Add a card directly to hand (used by purchase system)"""
    var card_data = CardDatabase.get_card_data(card_id)
    var new_card = CardFactory.create_interactive_card(card_data, card_id)
    
    # Store card_id for board state sync
    new_card.set_meta("card_id", card_id)
    
    ui_manager.get_hand_container().add_child(new_card)
    ui_manager.update_hand_display()

func _remove_card_from_shop(card_id: String) -> void:
    """Remove a specific card from the shop"""
    for child in shop_area.get_children():
        if child.get_meta("card_id", "") == card_id:
            child.queue_free()
            break
    
    current_shop_cards.erase(card_id)
    
    # Remove from frozen cards if it was frozen
    if card_id in frozen_cards:
        frozen_cards.erase(card_id)
    
    # Update button text after removal
    _update_freeze_button_text()

# === SHOP REFRESH/REROLL ===

func can_refresh_shop() -> bool:
    """Check if shop can be refreshed"""
    return GameState.can_afford(REFRESH_COST)

func refresh_shop_for_cost() -> bool:
    """Refresh shop for the standard cost (unfreezes all cards)"""
    # Check if player is eliminated
    if GameModeManager.is_in_multiplayer_session() and GameState.is_player_eliminated(GameState.local_player_id):
        print("Cannot refresh shop - player is eliminated")
        return false
    
    if not can_refresh_shop():
        print("Cannot afford shop refresh - need %d gold, have %d" % [REFRESH_COST, GameState.current_gold])
        return false
    
    # Route through appropriate system based on game mode
    if GameModeManager.is_in_multiplayer_session():
        # Multiplayer: Host executes directly, clients use RPC
        if NetworkManager.is_host:
            # Host executes directly to avoid RPC context issues
            print("Host refreshing shop directly")
            if NetworkManager.validate_and_execute_refresh(GameState.local_player_id):
                # Sync state to all clients (including self)
                NetworkManager.sync_player_state.rpc(GameState.local_player_id, GameState.players[GameState.local_player_id].to_dict())
                NetworkManager.sync_card_pool.rpc(GameState.shared_card_pool)
            return true
        else:
            # Client sends RPC to host
            var host_id = GameState.host_player_id
            NetworkManager.request_refresh_shop.rpc_id(host_id, GameState.local_player_id)
            print("Client sent refresh shop request to host")
            return true
    else:
        # Practice mode: Direct GameState execution
        if GameState.spend_gold(REFRESH_COST):
            refresh_shop_complete()  # Manual refresh unfreezes all
            print("Shop refreshed for %d gold (unfroze all)" % REFRESH_COST)
            ui_manager.show_flash_message("Shop refreshed for %d gold!" % REFRESH_COST, 1.5)
            return true
    
    return false

# === TAVERN UPGRADE ===

func can_upgrade_tavern() -> bool:
    """Check if tavern can be upgraded"""
    return GameState.can_upgrade_tavern()

func upgrade_tavern() -> bool:
    """Attempt to upgrade tavern tier"""
    # Check if player is eliminated
    if GameModeManager.is_in_multiplayer_session() and GameState.is_player_eliminated(GameState.local_player_id):
        print("Cannot upgrade tavern - player is eliminated")
        return false
    
    if not GameState.can_upgrade_tavern():
        print("Tavern already at maximum tier (%d)" % GameState.shop_tier)
        return false
    
    var upgrade_cost = GameState.calculate_tavern_upgrade_cost()
    
    # Route through appropriate system based on game mode
    if GameModeManager.is_in_multiplayer_session():
        # Multiplayer: Use NetworkManager RPC system
        if GameState.current_gold >= upgrade_cost:
            if NetworkManager.is_host:
                # Host executes directly
                print("Host upgrading shop directly")
                if NetworkManager.validate_and_execute_upgrade(GameState.local_player_id):
                    NetworkManager.sync_player_state.rpc(GameState.local_player_id, GameState.players[GameState.local_player_id].to_dict())
                return true
            else:
                # Client sends RPC to host
                var host_id = GameState.host_player_id
                NetworkManager.request_upgrade_shop.rpc_id(host_id, GameState.local_player_id)
                print("Client sent shop upgrade request to host")
                return true
        else:
            print("Cannot afford tavern upgrade - need %d gold, have %d" % [upgrade_cost, GameState.current_gold])
    else:
        # Practice mode: Direct GameState execution
        if GameState.upgrade_tavern_tier():
            shop_upgraded.emit(GameState.shop_tier, upgrade_cost)
            print("Tavern upgraded to tier %d for %d gold" % [GameState.shop_tier, upgrade_cost])
            # refresh_shop() is automatically called via the shop_tier_changed signal
            return true
        else:
            print("Cannot afford tavern upgrade - need %d gold, have %d" % [upgrade_cost, GameState.current_gold])
    
    return false

# === FREEZE SYSTEM ===

func toggle_card_freeze(card_id: String) -> void:
    """Toggle freeze state of a specific card"""
    if card_id in frozen_cards:
        frozen_cards.erase(card_id)
        print("Unfroze card: ", card_id)
    else:
        frozen_cards.append(card_id)
        print("Froze card: ", card_id)
    _update_card_freeze_visuals()

func is_card_frozen(card_id: String) -> bool:
    """Check if a card is currently frozen"""
    return card_id in frozen_cards

func freeze_all_cards() -> void:
    """Freeze all current shop cards"""
    frozen_cards.clear()
    for card_id in current_shop_cards:
        frozen_cards.append(card_id)
    _update_card_freeze_visuals()
    _update_freeze_button_text()
    print("Froze all shop cards")

func unfreeze_all_cards() -> void:
    """Unfreeze all cards"""
    frozen_cards.clear()
    _update_card_freeze_visuals()
    _update_freeze_button_text()
    print("Unfroze all shop cards")

func are_all_cards_frozen() -> bool:
    """Check if all current shop cards are frozen"""
    if current_shop_cards.is_empty():
        return false
    
    for card_id in current_shop_cards:
        if not is_card_frozen(card_id):
            return false
    return true

func _update_freeze_button_text() -> void:
    """Update freeze button text based on current freeze state"""
    if ui_manager.freeze_button:
        if are_all_cards_frozen():
            ui_manager.freeze_button.text = "Unfreeze"
        else:
            ui_manager.freeze_button.text = "Freeze"

func _update_card_freeze_visuals() -> void:
    """Update visual indicators for frozen cards"""
    for child in shop_area.get_children():
        if child.name != "ShopAreaLabel":
            var card_id = child.get_meta("card_id", "")
            if card_id != "":
                _apply_freeze_visual(child, is_card_frozen(card_id))

func _apply_freeze_visual(card_node: Node, is_frozen: bool) -> void:
    """Apply freeze visual effect to a card"""
    if is_frozen:
        # Apply blue tint to indicate frozen state
        card_node.modulate = Color(0.7, 0.9, 1.0, 1.0)  # Light blue tint
    else:
        # Reset to normal color
        card_node.modulate = Color.WHITE

# === EVENT HANDLERS ===

func _on_shop_card_drag_started(card: Node, offset = Vector2.ZERO) -> void:
    """Handle when a shop card drag starts"""
    # Forward to UI manager for unified drag handling
    ui_manager._on_card_drag_started(card, offset)

# === PUBLIC INTERFACE FOR GAME_BOARD ===

func handle_refresh_button_pressed() -> void:
    """Handle refresh shop button press"""
    refresh_shop_for_cost()

func handle_freeze_button_pressed() -> void:
    """Handle freeze button press - toggle behavior based on current state"""
    if are_all_cards_frozen():
        unfreeze_all_cards()
    else:
        freeze_all_cards()

func handle_upgrade_button_pressed() -> void:
    """Handle upgrade shop button press"""
    upgrade_tavern()

func handle_shop_card_purchase_by_drag(card: Node) -> bool:
    """Handle shop card purchase via drag and drop"""
    var card_id = card.get_meta("card_id", "")
    if card_id == "":
        print("Error: Shop card missing card_id metadata")
        return false
    
    print("\nShopManager: Handling drag purchase for card: ", card_id)
    print("  Current visual shop cards: ", current_shop_cards)
    
    # Also print the player's shop state from GameState
    var local_player = GameState.get_local_player()
    if local_player:
        print("  Player's shop_cards in GameState: ", local_player.shop_cards)
        # Ensure we're using the player state shop cards for slot calculation
        if current_shop_cards != local_player.shop_cards:
            print("  WARNING: Visual shop doesn't match player state! Syncing...")
            current_shop_cards = local_player.shop_cards.duplicate()
    else:
        print("  ERROR: Local player not found in GameState!")
    
    # Check if player is eliminated
    if GameModeManager.is_in_multiplayer_session() and GameState.is_player_eliminated(GameState.local_player_id):
        print("Cannot purchase - player is eliminated")
        return false
    
    # For drag purchases, validate and execute purchase
    var purchase_check = can_purchase_card(card_id)
    
    if not purchase_check.can_purchase:
        _handle_purchase_failure(card_id, purchase_check)
        return false
    
    var cost = purchase_check.cost
    var card_data = CardDatabase.get_card_data(card_id)
    var card_name = card_data.get("name", "Unknown")
    
    # Route through appropriate system based on game mode
    if GameModeManager.is_in_multiplayer_session():
        # Multiplayer: Use NetworkManager RPC system (same as regular purchase)
        var shop_slot = _find_card_slot_in_shop(card_id)
        if shop_slot >= 0:
            if NetworkManager.is_host:
                # Host executes directly
                print("Host purchasing card directly via drag")
                if NetworkManager.validate_and_execute_purchase(GameState.local_player_id, card_id, shop_slot):
                    NetworkManager.sync_player_state.rpc(GameState.local_player_id, GameState.players[GameState.local_player_id].to_dict())
                    NetworkManager.sync_card_pool.rpc(GameState.shared_card_pool)
                    
                    # The dragged card will be cleaned up by game_board
                    # Don't update tracking here - let the state sync handle it
                    return true
            else:
                # Client sends RPC to host
                var host_id = GameState.host_player_id
                NetworkManager.request_purchase_card.rpc_id(host_id, GameState.local_player_id, card_id, shop_slot)
                print("Client sent purchase request to host via drag")
                
                # Don't update tracking here - let the server sync handle it
                # Don't show message yet - wait for server confirmation
                return true
    else:
        # Practice mode: Direct GameState execution
        if GameState.spend_gold(cost):
            # Remove from pool
            GameState.card_pool[card_id] -= 1
            
            # Add to hand
            _add_card_to_hand_direct(card_id)
            
            # Update tracking after successful purchase
            current_shop_cards.erase(card_id)
            if card_id in frozen_cards:
                frozen_cards.erase(card_id)
            
            # Update button text after purchase
            _update_freeze_button_text()
            
            card_purchased.emit(card_id, cost)
            
            print("Purchased ", card_name, " for ", cost, " gold - Remaining in pool: ", GameState.card_pool[card_id])
            
            # Show success message
            ui_manager.show_flash_message("Purchased %s for %d gold!" % [card_name, cost], 1.5)
            return true
    
    return false 

# === PHASE TRANSITION HELPERS ===

func prepare_for_combat_phase() -> void:
    """Prepare shop state for combat phase transition"""
    # Sync frozen cards to player state for cross-turn persistence
    var local_player = GameState.get_local_player()
    if local_player:
        local_player.frozen_card_ids = frozen_cards.duplicate()
        print("ShopManager: Synced ", frozen_cards.size(), " frozen cards to PlayerState for next turn")
        print("ShopManager: Frozen cards being saved: ", frozen_cards)
        
        # In multiplayer, sync the frozen cards to the server
        if GameModeManager.is_in_multiplayer_session() and NetworkManager:
            print("ShopManager: In multiplayer mode, syncing frozen cards to server")
            print("ShopManager: Is host? ", NetworkManager.is_host, ", Local player ID: ", local_player.player_id, ", Host ID: ", GameState.host_player_id)
            
            if NetworkManager.is_host:
                # Host can update directly and sync to all
                print("ShopManager: Host syncing frozen cards directly")
                NetworkManager.sync_player_state.rpc(local_player.player_id, local_player.to_dict())
            else:
                # Client must request the host to update their frozen cards
                print("ShopManager: Client sending frozen cards to host: ", frozen_cards)
                NetworkManager.request_update_frozen_cards.rpc_id(GameState.host_player_id, local_player.player_id, frozen_cards.duplicate())

func restore_from_combat_phase() -> void:
    """Restore shop state when returning from combat"""
    # Frozen cards are now handled by GameState.deal_cards_to_shop
    # which preserves them from the previous turn
    frozen_cards.clear()  # Clear local tracking as cards are unfrozen on new turn
    _update_freeze_button_text()
