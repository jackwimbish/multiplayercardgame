# ShopManager.gd - Display-only shop manager
# This class ONLY handles displaying shop cards
# All game logic is handled by HostGameLogic

class_name ShopManager
extends RefCounted

# UI References
var shop_area: Container
var ui_manager: UIManager

func _init(shop_area_ref: Container, ui_manager_ref: UIManager):
    """Initialize ShopManager with UI references only"""
    shop_area = shop_area_ref
    ui_manager = ui_manager_ref
    print("ShopManager: Display-only shop manager initialized")

func display_shop(cards_data: Array, frozen_card_ids: Array):
    """Display shop cards with freeze state"""
    print("ShopManager: Displaying ", cards_data.size(), " cards, ", frozen_card_ids.size(), " frozen")
    
    # Clear existing display
    # Use immediate removal to prevent visual duplicates for host
    var cards_to_remove = []
    for child in shop_area.get_children():
        if child.name != "ShopAreaLabel":
            cards_to_remove.append(child)
    
    for card in cards_to_remove:
        shop_area.remove_child(card)
        card.queue_free()
    
    # Create visual cards
    for i in range(cards_data.size()):
        var card_data = cards_data[i]
        var card_id = card_data.get("id", "")
        
        if card_id == "":
            print("ShopManager: Warning - card data missing ID")
            continue
        
        # Create visual card with drag handler
        var custom_handlers = {"drag_started": _on_shop_card_drag_started}
        var card_visual = CardFactory.create_card(card_data, card_id, custom_handlers)
        
        # Apply freeze visual if frozen
        if card_id in frozen_card_ids:
            card_visual.modulate = Color(0.7, 0.9, 1.0, 1.0)  # Light blue tint
        
        # Store metadata for drag handling
        card_visual.set_meta("shop_slot", i)
        card_visual.set_meta("card_id", card_id)
        card_visual.set_meta("is_shop_card", true)
        
        shop_area.add_child(card_visual)

func _on_shop_card_drag_started(card: Node, offset = Vector2.ZERO) -> void:
    """Handle when a shop card drag starts"""
    # Forward to UI manager for unified drag handling
    ui_manager._on_card_drag_started(card, offset)

func get_card_drag_data(card_visual: Node) -> Dictionary:
    """Return drag metadata for action request"""
    return {
        "card_id": card_visual.get_meta("card_id", ""),
        "shop_slot": card_visual.get_meta("shop_slot", -1)
    }

func clear_shop():
    """Clear all cards from shop display"""
    for child in shop_area.get_children():
        if child.name != "ShopAreaLabel":
            child.queue_free()
