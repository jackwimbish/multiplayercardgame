class_name CombatAnimationPlayer
extends RefCounted

## Handles the visual playback of combat animations based on combat log

# Animation timing constants (in seconds)
const ATTACK_MOVE_DURATION: float = 0.3
const ATTACK_STRIKE_DURATION: float = 0.2
const ATTACK_RETURN_DURATION: float = 0.3
const PAUSE_BETWEEN_ATTACKS: float = 0.3
const DEATH_FADE_DURATION: float = 0.5
const DAMAGE_NUMBER_DURATION: float = 1.0
const DAMAGE_NUMBER_RISE: float = 50.0

# Sound trigger callbacks (to be connected by CombatManager)
signal sound_combat_start()
signal sound_attack_impact(attacker_name: String, defender_name: String)
signal sound_minion_death(minion_name: String)
signal sound_combat_end(result: String)

# Animation state
var is_playing: bool = false
var is_skipping: bool = false
var current_action_index: int = 0
var combat_log: Array = []
var animation_speed: float = 1.0

# Visual references
var player_board_container: Control
var enemy_board_container: Control
var ui_manager: UIManager
var combat_visuals: Dictionary = {}  # Maps position -> visual minion data

# Original positions for minions
var original_positions: Dictionary = {}

# Track active tweens for cleanup
var active_tweens: Array = []

# Player name mapping for multiplayer combat
var player_name: String = ""  # The player whose board is on the player side
var enemy_name: String = ""   # The player whose board is on the enemy side

# Unique ID mapping for robust minion identification
var unique_id_to_visual_key: Dictionary = {}  # Maps unique_id -> visual key (e.g., "p1_0" -> "player_0")

func setup(player_board: Control, enemy_board: Control, ui_mgr: UIManager):
    """Initialize the animation player with required references"""
    player_board_container = player_board
    enemy_board_container = enemy_board
    ui_manager = ui_mgr

func play_combat_animation(log: Array, player_minions: Array, enemy_minions: Array) -> void:
    """Start playing combat animations based on the combat log"""
    if is_playing:
        print("CombatAnimationPlayer: WARNING - Animation already in progress, resetting state")
        # Force reset if somehow stuck in playing state
        is_playing = false
        is_skipping = false
        # Kill any lingering tweens
        for tween in active_tweens:
            if tween and is_instance_valid(tween):
                tween.kill()
        active_tweens.clear()
    
    print("CombatAnimationPlayer: Starting animation with ", log.size(), " actions")
    print("  Player minions: ", player_minions.size(), " Enemy minions: ", enemy_minions.size())
    
    combat_log = log
    current_action_index = 0
    is_playing = true
    is_skipping = false
    
    # Reset player name mapping
    player_name = ""
    enemy_name = ""
    
    # Extract player names from the combat log to help with minion identification
    _extract_player_names_from_log(log)
    
    # Setup visual minions
    _setup_combat_visuals(player_minions, enemy_minions)
    
    # Store original positions
    _store_original_positions()
    
    # Start animation sequence
    _play_next_action()

func skip_combat() -> void:
    """Skip all remaining animations and show final state"""
    is_skipping = true
    
    # Kill all active tweens
    for tween in active_tweens:
        if tween and is_instance_valid(tween):
            tween.kill()
    active_tweens.clear()
    
    # Show final state immediately
    _show_final_state()
    
    # Reset playing state
    is_playing = false

func _setup_combat_visuals(player_minions: Array, enemy_minions: Array) -> void:
    """Setup visual tracking for all minions in combat"""
    combat_visuals.clear()
    unique_id_to_visual_key.clear()
    
    # Track player minions
    var player_index = 0
    for child in player_board_container.get_children():
        if child.has_meta("card_id") and player_index < player_minions.size():
            var minion_data = player_minions[player_index]
            # Store original stats to ensure we don't modify game state
            var original_stats = child.get_node_or_null("VBoxContainer/BottomRow/StatsLabel")
            var original_stats_text = ""
            if original_stats:
                original_stats_text = original_stats.text
            
            var visual_key = "player_" + str(player_index)
            combat_visuals[visual_key] = {
                "node": child,
                "side": "player",
                "position": player_index,
                "max_health": minion_data.get("current_health", 1),
                "current_health": minion_data.get("current_health", 1),
                "attack": minion_data.get("current_attack", 1),
                "is_dead": false,
                "card_id": minion_data.get("card_id", ""),
                "original_stats_text": original_stats_text
            }
            
            # Map unique ID to visual key if available
            var unique_id = minion_data.get("unique_id", "")
            if unique_id != "":
                unique_id_to_visual_key[unique_id] = visual_key
                print("    Mapped unique ID ", unique_id, " to ", visual_key)
            
            player_index += 1
    
    print("  Set up ", player_index, " player minions in combat_visuals")
    
    # Track enemy minions
    var enemy_index = 0
    for child in enemy_board_container.get_children():
        if child.name.begins_with("EnemyMinion_") and enemy_index < enemy_minions.size():
            var minion_data = enemy_minions[enemy_index]
            var visual_key = "enemy_" + str(enemy_index)
            combat_visuals[visual_key] = {
                "node": child,
                "side": "enemy",
                "position": enemy_index,
                "max_health": minion_data.get("current_health", 1),
                "current_health": minion_data.get("current_health", 1),
                "attack": minion_data.get("current_attack", 1),
                "is_dead": false,
                "card_id": minion_data.get("card_id", "")
            }
            
            # Map unique ID to visual key if available
            var unique_id = minion_data.get("unique_id", "")
            if unique_id != "":
                unique_id_to_visual_key[unique_id] = visual_key
                print("    Mapped unique ID ", unique_id, " to ", visual_key)
            
            enemy_index += 1
    
    print("  Set up ", enemy_index, " enemy minions in combat_visuals")
    print("  Total combat_visuals: ", combat_visuals.keys())
    print("  Unique ID mappings: ", unique_id_to_visual_key)

func _extract_player_names_from_log(log: Array) -> void:
    """Extract player names from combat log to map to our player/enemy boards"""
    player_name = ""
    enemy_name = ""
    
    # Look for attack actions to extract player names
    for action in log:
        if action.get("type") == "attack":
            var attacker_id = action.get("attacker_id", "")
            var defender_id = action.get("defender_id", "")
            
            # Extract names from format "PlayerName's CardName (pos X)"
            var attacker_owner = _extract_owner_name(attacker_id)
            var defender_owner = _extract_owner_name(defender_id)
            
            # The first time we see different owners, we can map them
            if attacker_owner != "" and defender_owner != "" and attacker_owner != defender_owner:
                # In multiplayer, we need to determine which player is "ours"
                # This is a bit tricky without more context, but we can make educated guesses
                # For now, let's assume the first attacker's owner in an attack between different players
                # maps to whichever board that minion is on
                print("CombatAnimationPlayer: Found player names - ", attacker_owner, " vs ", defender_owner)
                
                # We'll refine this mapping when we process the first attack
                return

func _extract_owner_name(minion_id: String) -> String:
    """Extract owner name from minion ID string like 'PlayerName's CardName (pos X)'"""
    var parts = minion_id.split("'s ")
    if parts.size() >= 2:
        return parts[0]
    return ""

func _store_original_positions() -> void:
    """Store the original positions of all minions"""
    for key in combat_visuals:
        var visual = combat_visuals[key]
        if visual.node and is_instance_valid(visual.node):
            original_positions[key] = visual.node.global_position

func _play_next_action() -> void:
    """Play the next action in the combat log"""
    if is_skipping or not is_playing:
        return
    
    if current_action_index >= combat_log.size():
        _on_combat_animation_complete()
        return
    
    var action = combat_log[current_action_index]
    print("CombatAnimationPlayer: Playing action ", current_action_index, " of ", combat_log.size(), " - Type: ", action.get("type", "unknown"))
    current_action_index += 1
    
    match action.get("type", ""):
        "combat_start":
            _animate_combat_start(action)
        "first_attacker":
            _animate_first_attacker(action)
        "attack":
            _animate_attack(action)
        "death":
            # Deaths are handled as part of attack animations
            _play_next_action()
        "combat_end", "combat_tie":
            _animate_combat_end(action)
        _:
            # Skip unknown actions
            print("  Skipping unknown action type: ", action.get("type", "unknown"))
            _play_next_action()

func _animate_combat_start(action: Dictionary) -> void:
    """Animate the combat start"""
    sound_combat_start.emit()
    
    # Could add visual flourish here
    await player_board_container.get_tree().create_timer(0.5).timeout
    _play_next_action()

func _animate_first_attacker(action: Dictionary) -> void:
    """Animate showing who attacks first"""
    # Could add visual indicator here
    _play_next_action()

func _animate_attack(action: Dictionary) -> void:
    """Animate a minion attack"""
    print("CombatAnimationPlayer: Animating attack - ", action.get("attacker_id", ""), " vs ", action.get("defender_id", ""))
    
    # First try to use unique IDs if available
    var attacker_unique_id = action.get("attacker_unique_id", "")
    var defender_unique_id = action.get("defender_unique_id", "")
    
    var attacker_id = ""
    var defender_id = ""
    
    if attacker_unique_id != "" and defender_unique_id != "":
        # Use unique ID mapping
        attacker_id = unique_id_to_visual_key.get(attacker_unique_id, "")
        defender_id = unique_id_to_visual_key.get(defender_unique_id, "")
        print("  Using unique IDs - attacker: ", attacker_unique_id, " -> ", attacker_id, ", defender: ", defender_unique_id, " -> ", defender_id)
    
    # Fall back to name-based search if unique IDs not available or not found
    if attacker_id == "" or defender_id == "":
        print("  Falling back to name-based search")
        attacker_id = _find_minion_by_name(action.get("attacker_id", ""))
        defender_id = _find_minion_by_name(action.get("defender_id", ""))
    
    print("  Found attacker: ", attacker_id, " defender: ", defender_id)
    
    if not attacker_id or not defender_id:
        print("  Could not find attacker or defender - skipping")
        print("    attacker_id: ", attacker_id, " defender_id: ", defender_id)
        _play_next_action()
        return
    
    var attacker = combat_visuals.get(attacker_id)
    var defender = combat_visuals.get(defender_id)
    
    if not attacker or not defender:
        print("  Attacker or defender not found in combat_visuals")
        _play_next_action()
        return
        
    if attacker.is_dead or defender.is_dead:
        print("  Skipping attack - attacker dead: ", attacker.is_dead, " defender dead: ", defender.is_dead)
        _play_next_action()
        return
    
    # Get attack values
    var damage_to_defender = action.get("damage_dealt", attacker.attack)
    var damage_to_attacker = action.get("damage_received", defender.attack)
    
    # Create attack animation
    await _perform_melee_attack(attacker, defender, damage_to_attacker, damage_to_defender)
    
    # Apply damage
    attacker.current_health -= damage_to_attacker
    defender.current_health -= damage_to_defender
    
    print("  After attack - Attacker health: ", attacker.current_health, " Defender health: ", defender.current_health)
    
    # Check for deaths
    var has_deaths = false
    if attacker.current_health <= 0 and not attacker.is_dead:
        attacker.is_dead = true
        _animate_minion_death(attacker)
        has_deaths = true
    
    if defender.current_health <= 0 and not defender.is_dead:
        defender.is_dead = true
        _animate_minion_death(defender)
        has_deaths = true
    
    # Wait for death animations if any
    if has_deaths:
        await player_board_container.get_tree().create_timer(DEATH_FADE_DURATION).timeout
    
    # Pause before next action
    await player_board_container.get_tree().create_timer(PAUSE_BETWEEN_ATTACKS).timeout
    
    print("  Attack animation complete, playing next action")
    _play_next_action()

func _perform_melee_attack(attacker: Dictionary, defender: Dictionary, damage_to_attacker: int, damage_to_defender: int) -> void:
    """Perform the melee attack animation"""
    if not attacker.node or not defender.node:
        return
    
    var attacker_node = attacker.node
    var defender_node = defender.node
    
    # Calculate attack position (move 80% of the way to the target)
    var start_pos = attacker_node.global_position
    var target_pos = defender_node.global_position
    var attack_pos = start_pos.lerp(target_pos, 0.8)
    
    # Move to attack position
    var move_tween = player_board_container.get_tree().create_tween()
    active_tweens.append(move_tween)
    move_tween.tween_property(attacker_node, "global_position", attack_pos, ATTACK_MOVE_DURATION)
    
    await move_tween.finished
    
    # Strike animation and damage numbers
    sound_attack_impact.emit(
        CardDatabase.get_card_data(attacker.card_id).get("name", "Unknown"),
        CardDatabase.get_card_data(defender.card_id).get("name", "Unknown")
    )
    
    # Show damage numbers simultaneously
    if damage_to_attacker > 0:
        _show_damage_number(attacker_node, damage_to_attacker)
    if damage_to_defender > 0:
        _show_damage_number(defender_node, damage_to_defender)
    
    # Small shake on defender
    _shake_minion(defender_node)
    
    await player_board_container.get_tree().create_timer(ATTACK_STRIKE_DURATION).timeout
    
    # Return to position
    var return_tween = player_board_container.get_tree().create_tween()
    active_tweens.append(return_tween)
    return_tween.tween_property(attacker_node, "global_position", start_pos, ATTACK_RETURN_DURATION)
    
    await return_tween.finished

func _show_damage_number(target_node: Node, damage: int) -> void:
    """Show floating damage number above a minion"""
    var damage_label = Label.new()
    damage_label.text = "-" + str(damage)
    damage_label.add_theme_color_override("font_color", Color.RED)
    damage_label.add_theme_font_size_override("font_size", 24)
    damage_label.z_index = 100
    
    # Position above the card
    target_node.add_child(damage_label)
    damage_label.position = Vector2(target_node.size.x / 2 - 20, -20)
    
    # Animate floating up and fading
    var tween = player_board_container.get_tree().create_tween()
    active_tweens.append(tween)
    tween.set_parallel(true)
    tween.tween_property(damage_label, "position:y", damage_label.position.y - DAMAGE_NUMBER_RISE, DAMAGE_NUMBER_DURATION)
    tween.tween_property(damage_label, "modulate:a", 0.0, DAMAGE_NUMBER_DURATION)
    
    # Remove after animation
    tween.finished.connect(func(): damage_label.queue_free())

func _shake_minion(minion_node: Node) -> void:
    """Apply a small shake effect to a minion when hit"""
    var original_pos = minion_node.position
    var shake_amount = 5.0
    
    var shake_tween = player_board_container.get_tree().create_tween()
    active_tweens.append(shake_tween)
    shake_tween.tween_property(minion_node, "position:x", original_pos.x + shake_amount, 0.05)
    shake_tween.tween_property(minion_node, "position:x", original_pos.x - shake_amount, 0.05)
    shake_tween.tween_property(minion_node, "position:x", original_pos.x, 0.05)

func _animate_minion_death(minion: Dictionary) -> void:
    """Animate a minion dying"""
    if not minion.node or not is_instance_valid(minion.node):
        return
    
    sound_minion_death.emit(CardDatabase.get_card_data(minion.card_id).get("name", "Unknown"))
    
    # Fade to grey
    var death_tween = player_board_container.get_tree().create_tween()
    active_tweens.append(death_tween)
    death_tween.tween_property(minion.node, "modulate", Color(0.5, 0.5, 0.5, 0.7), DEATH_FADE_DURATION)
    
    # Update health display to 0 (visual only during combat)
    var stats_label = minion.node.get_node_or_null("VBoxContainer/BottomRow/StatsLabel")
    if stats_label:
        var attack = minion.attack
        stats_label.text = str(attack) + "/0"
        stats_label.add_theme_color_override("font_color", Color.RED)

func _animate_combat_end(action: Dictionary) -> void:
    """Animate the combat ending"""
    var result = action.get("winner", "tie")
    sound_combat_end.emit(result)
    
    # Could add victory/defeat animation here
    await player_board_container.get_tree().create_timer(0.5).timeout
    
    _on_combat_animation_complete()

func _find_minion_by_name(name: String) -> String:
    """Find a minion in combat_visuals by its display name"""
    # The name comes in format like "PlayerName's CardName (pos X)"
    print("  Looking for minion: ", name)
    
    # Extract the owner name from the minion ID
    var owner = _extract_owner_name(name)
    
    # Extract position number
    var pos_str = ""
    var pos_index = name.find("(pos ")
    if pos_index >= 0:
        var end_index = name.find(")", pos_index)
        if end_index > pos_index:
            pos_str = name.substr(pos_index + 5, end_index - pos_index - 5)
    
    var position = pos_str.to_int() if pos_str != "" else -1
    
    print("    Owner: ", owner, " Position: ", position)
    
    # Build a list of all matches
    var matches = []
    
    for key in combat_visuals:
        var visual = combat_visuals[key]
        var card_name = CardDatabase.get_card_data(visual.card_id).get("name", "Unknown")
        
        # Check if this minion's name and position match
        if name.contains(card_name) and visual.position == position:
            matches.append({
                "key": key,
                "side": "player" if key.begins_with("player_") else "enemy"
            })
            print("    Potential match: ", key, " (", card_name, " pos ", visual.position, ")")
    
    # If we only found one match, use it
    if matches.size() == 1:
        print("    Single match found: ", matches[0].key)
        # Establish owner mapping if needed
        if owner != "" and matches[0].side == "player" and player_name == "":
            player_name = owner
            print("    Established player name: ", player_name)
        elif owner != "" and matches[0].side == "enemy" and enemy_name == "":
            enemy_name = owner
            print("    Established enemy name: ", enemy_name)
        return matches[0].key
    
    # If we found multiple matches, use owner info to disambiguate
    if matches.size() > 1:
        print("    Multiple matches found, using owner info")
        for match in matches:
            # If we haven't established names yet, return the first match and establish
            if player_name == "" or enemy_name == "":
                if match.side == "player" and player_name == "":
                    player_name = owner
                    print("    Established player name: ", player_name)
                elif match.side == "enemy" and enemy_name == "":
                    enemy_name = owner
                    print("    Established enemy name: ", enemy_name)
                return match.key
            
            # We have names, match based on owner
            if (owner == player_name and match.side == "player") or (owner == enemy_name and match.side == "enemy"):
                print("    Owner match found: ", match.key)
                return match.key
    
    print("    No match found in combat_visuals")
    return ""

func _show_final_state() -> void:
    """Show the final state of combat"""
    print("CombatAnimationPlayer: Showing final state")
    
    # Reset all positions
    for key in original_positions:
        if combat_visuals.has(key) and combat_visuals[key].node and is_instance_valid(combat_visuals[key].node):
            combat_visuals[key].node.global_position = original_positions[key]
    
    # Apply final visual states
    for key in combat_visuals:
        var visual = combat_visuals[key]
        if visual.node and is_instance_valid(visual.node):
            if visual.is_dead:
                print("  Minion ", key, " is dead - applying death visuals")
                visual.node.modulate = Color(0.5, 0.5, 0.5, 0.7)
                var stats_label = visual.node.get_node_or_null("VBoxContainer/BottomRow/StatsLabel")
                if stats_label:
                    stats_label.text = str(visual.attack) + "/0"
                    stats_label.add_theme_color_override("font_color", Color.RED)

func _on_combat_animation_complete() -> void:
    """Called when all combat animations are complete"""
    is_playing = false
    active_tweens.clear()
    _show_final_state()
    
    # Restore original stats text to prevent persistence of combat damage
    _restore_original_stats()
    
    # Notify CombatManager that animations are done
    if ui_manager and ui_manager.combat_ui_container:
        var combat_manager = ui_manager.combat_ui_container.get_parent()
        if combat_manager and combat_manager.has_method("_on_combat_animations_complete"):
            combat_manager._on_combat_animations_complete()

func _restore_original_stats() -> void:
    """Restore original stats text to all player minions"""
    for key in combat_visuals:
        var visual = combat_visuals[key]
        if visual.side == "player" and visual.node and is_instance_valid(visual.node):
            var original_text = visual.get("original_stats_text", "")
            if original_text != "":
                var stats_label = visual.node.get_node_or_null("VBoxContainer/BottomRow/StatsLabel")
                if stats_label:
                    stats_label.text = original_text
                    stats_label.remove_theme_color_override("font_color")
