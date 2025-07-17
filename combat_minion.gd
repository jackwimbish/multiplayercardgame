class_name CombatMinion
extends Resource

@export var source_card_id: String  # Reference to original card
@export var minion_id: String  # Unique combat identifier
@export var combat_buffs: Array = []  # Array[Buff] - untyped to avoid linter issues
@export var source_board_minion = null  # Card - untyped to avoid linter issues

# Combat stats (includes persistent buffs)
@export var base_attack: int
@export var base_health: int  
@export var max_health: int
@export var current_attack: int
@export var current_health: int

# Combat state
@export var has_attacked: bool = false
@export var can_attack: bool = true
@export var position: int = 0
@export var keyword_abilities: Dictionary = {}

static func create_from_board_minion(board_minion, combat_id: String) -> CombatMinion:  # board_minion: Card
	"""Create a combat minion from a board minion card"""
	var combat_minion = CombatMinion.new()
	combat_minion.source_card_id = board_minion.card_data.get("id", "unknown")
	combat_minion.minion_id = combat_id
	
	# Copy base stats + apply persistent buffs from tavern phase
	combat_minion.base_attack = board_minion.get_effective_attack()  # Includes tavern buffs
	combat_minion.base_health = board_minion.get_effective_health()   # Includes tavern buffs
	combat_minion.current_health = board_minion.current_health
	combat_minion.current_attack = combat_minion.base_attack
	combat_minion.max_health = combat_minion.base_health
	
	# Store reference to original board minion for post-combat updates
	combat_minion.source_board_minion = board_minion
	
	return combat_minion

static func create_from_enemy_data(enemy_data: Dictionary, combat_id: String) -> CombatMinion:
	"""Create a combat minion from enemy board data"""
	var combat_minion = CombatMinion.new()
	combat_minion.source_card_id = enemy_data.get("card_id", "unknown")
	combat_minion.minion_id = combat_id
	
	# Get base stats from card database (no duplication)
	var base_stats = CardDatabase.get_card_data(enemy_data.card_id)
	combat_minion.base_attack = base_stats.attack
	combat_minion.base_health = base_stats.health
	combat_minion.current_attack = combat_minion.base_attack
	combat_minion.current_health = combat_minion.base_health
	combat_minion.max_health = combat_minion.base_health
	
	# Apply any predefined buffs (this handles all stat modifications)
	for buff_data in enemy_data.get("buffs", []):
		var buff = BuffHelpers.create_buff_from_data(buff_data)
		if buff:
			combat_minion.add_combat_buff(buff)
	
	return combat_minion

func add_combat_buff(buff) -> void:  # buff: Buff
	"""Add a temporary combat buff to this minion"""
	if not buff.stackable:
		remove_combat_buff_by_id(buff.buff_id)
	combat_buffs.append(buff)
	buff.apply_to_minion(self)

func remove_combat_buff_by_id(buff_id: String) -> void:
	"""Remove a combat buff by its ID"""
	for i in range(combat_buffs.size() - 1, -1, -1):
		if combat_buffs[i].buff_id == buff_id:
			var buff = combat_buffs[i]
			buff.remove_from_minion(self)
			combat_buffs.remove_at(i)

func add_keyword_ability(ability_name: String, data: Dictionary = {}) -> void:
	"""Add a keyword ability to this combat minion"""
	keyword_abilities[ability_name] = data

func remove_keyword_ability(ability_name: String) -> void:
	"""Remove a keyword ability from this combat minion"""
	if keyword_abilities.has(ability_name):
		keyword_abilities.erase(ability_name)

func has_keyword_ability(ability_name: String) -> bool:
	"""Check if this minion has a specific keyword ability"""
	return keyword_abilities.has(ability_name)

func get_current_attack() -> int:
	"""Get current attack value (for buff system compatibility)"""
	return current_attack

func get_current_health() -> int:
	"""Get current health value (for buff system compatibility)"""
	return current_health

func get_effective_attack() -> int:
	"""Get effective attack value (alias for get_current_attack for combat compatibility)"""
	return current_attack

func take_damage(amount: int) -> void:
	"""Apply damage to this combat minion"""
	current_health = max(0, current_health - amount)

func get_display_name() -> String:
	"""Get display name for combat logging"""
	var card_name = "Unknown"
	
	# Try to get name from CardDatabase if we have the card ID
	if source_card_id != "" and source_card_id != "unknown":
		var card_data = CardDatabase.get_card_data(source_card_id)
		if not card_data.is_empty():
			card_name = card_data.get("name", "Unknown")
	
	# Extract owner and position from minion_id (format: "player_0" or "enemy_1")
	var display_name = card_name
	if minion_id != "":
		var parts = minion_id.split("_")
		if parts.size() >= 2:
			var owner = parts[0].capitalize()  # "player" -> "Player", "enemy" -> "Enemy"
			var position = parts[1]
			display_name = "%s %s %s" % [owner, card_name, position]
		else:
			display_name = "%s (%s)" % [card_name, minion_id]
	
	return display_name 