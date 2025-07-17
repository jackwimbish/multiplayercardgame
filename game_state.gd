# GameState.gd (Autoload Singleton)
extends Node

# Game Mode Enum
enum GameMode { SHOP, COMBAT }

# Core Economy & Turn System
var current_turn: int = 1
var player_base_gold: int = 3
var current_gold: int = 3
var bonus_gold: int = 0

# Tavern System  
var shop_tier: int = 1
var current_tavern_upgrade_cost: int = 5
var card_pool: Dictionary = {}

# Health System
var player_health: int = 25
var enemy_health: int = 25

# Game Limits
var max_hand_size: int = 10
var max_board_size: int = 7

# Game Mode
var current_mode: GameMode = GameMode.SHOP

# Constants
const GLOBAL_GOLD_MAX = 255
const TAVERN_UPGRADE_BASE_COSTS = {
	2: 5,   # Tier 1 → 2: base cost 5
	3: 7,   # Tier 2 → 3: base cost 7
	4: 8,   # Tier 3 → 4: base cost 8
	5: 9,   # Tier 4 → 5: base cost 9
	6: 11   # Tier 5 → 6: base cost 11
}
const DEFAULT_COMBAT_DAMAGE = 5

# Signals for state changes
signal turn_changed(new_turn: int)
signal gold_changed(new_gold: int, max_gold: int)
signal shop_tier_changed(new_tier: int)
signal player_health_changed(new_health: int)
signal enemy_health_changed(new_health: int)
signal game_over(winner: String)
signal game_mode_changed(new_mode: GameMode)

func _ready():
	print("GameState singleton initialized")
	# Initialize the card pool when the singleton is ready
	initialize_card_pool()

# Initialize card pool (migrated from game_board.gd)
func initialize_card_pool():
	card_pool = {
		1: {"Murloc Raider": 18, "Dire Wolf Alpha": 18, "Coin": 18},
		2: {"Kindly Grandmother": 15, "Faerie Dragon": 15, "Annoy-o-Tron": 15},
		3: {"Harvest Golem": 13, "Shattered Sun Cleric": 13, "Spider Tank": 13},
		4: {"Piloted Shredder": 11, "Defender of Argus": 11, "Gnomish Inventor": 11},
		5: {"Stranglethorn Tiger": 9, "Sludge Belcher": 9, "Azure Drake": 9},
		6: {"Boulderfist Ogre": 6, "Sunwalker": 6, "Cairne Bloodhoof": 6}
	}

# Get current state as a dictionary (useful for debugging/save systems later)
func get_state_snapshot() -> Dictionary:
	return {
		"current_turn": current_turn,
		"player_base_gold": player_base_gold,
		"current_gold": current_gold,
		"bonus_gold": bonus_gold,
		"shop_tier": shop_tier,
		"current_tavern_upgrade_cost": current_tavern_upgrade_cost,
		"player_health": player_health,
		"enemy_health": enemy_health,
		"current_mode": current_mode
	}

# === CORE STATE MANAGEMENT FUNCTIONS ===

# Gold Management Functions
func calculate_base_gold_for_turn(turn: int) -> int:
	"""Calculate base gold for a given turn (3 on turn 1, +1 per turn up to 10)"""
	if turn <= 1:
		return 3
	elif turn <= 8:
		return 2 + turn  # Turn 2=4 gold, turn 3=5 gold, ..., turn 8=10 gold
	else:
		return 10  # Maximum base gold of 10 from turn 8 onwards

func spend_gold(amount: int) -> bool:
	"""Attempt to spend gold. Returns true if successful, false if insufficient gold"""
	if current_gold >= amount:
		current_gold -= amount
		gold_changed.emit(current_gold, GLOBAL_GOLD_MAX)
		return true
	else:
		print("Insufficient gold: need ", amount, ", have ", current_gold)
		return false

func can_afford(cost: int) -> bool:
	"""Check if player can afford a given cost"""
	return current_gold >= cost

func increase_base_gold(amount: int):
	"""Permanently increase player's base gold income"""
	player_base_gold = min(player_base_gold + amount, GLOBAL_GOLD_MAX)
	print("Base gold increased by ", amount, " to ", player_base_gold)
	gold_changed.emit(current_gold, GLOBAL_GOLD_MAX)

func add_bonus_gold(amount: int):
	"""Add temporary bonus gold for next turn only"""
	bonus_gold = min(bonus_gold + amount, GLOBAL_GOLD_MAX - player_base_gold)
	print("Bonus gold added: ", amount, " (total bonus: ", bonus_gold, ")")
	gold_changed.emit(current_gold, GLOBAL_GOLD_MAX)

func gain_gold(amount: int):
	"""Immediately gain current gold (within global limits)"""
	current_gold = min(current_gold + amount, GLOBAL_GOLD_MAX)
	print("Gained ", amount, " gold (current: ", current_gold, ")")
	gold_changed.emit(current_gold, GLOBAL_GOLD_MAX)

# Turn Management
func start_new_turn():
	"""Advance to the next turn and refresh gold"""
	current_turn += 1
	
	# Update base gold from turn progression (but don't decrease it)
	var new_base_gold = calculate_base_gold_for_turn(current_turn)
	player_base_gold = max(player_base_gold, new_base_gold)
	
	# Refresh current gold (base + any bonus, capped at global max)
	current_gold = min(player_base_gold + bonus_gold, GLOBAL_GOLD_MAX)
	bonus_gold = 0  # Reset bonus after applying it
	
	# Decrease tavern upgrade cost by 1 each turn (minimum 0)
	current_tavern_upgrade_cost = max(current_tavern_upgrade_cost - 1, 0)
	
	print("Turn ", current_turn, " started - Base Gold: ", player_base_gold, ", Current Gold: ", current_gold)
	print("Tavern upgrade cost decreased to: ", current_tavern_upgrade_cost)
	
	# Emit signals for state changes
	turn_changed.emit(current_turn)
	gold_changed.emit(current_gold, GLOBAL_GOLD_MAX)

# Tavern Management Functions
func calculate_tavern_upgrade_cost() -> int:
	"""Get current cost to upgrade tavern tier"""
	if not can_upgrade_tavern():
		return -1  # Cannot upgrade past tier 6
	return current_tavern_upgrade_cost

func can_upgrade_tavern() -> bool:
	"""Check if tavern can be upgraded (not at max tier)"""
	return shop_tier < 6

func upgrade_tavern_tier() -> bool:
	"""Attempt to upgrade tavern tier. Returns true if successful."""
	if not can_upgrade_tavern():
		print("Cannot upgrade - already at max tier (", shop_tier, ")")
		return false
	
	var upgrade_cost = calculate_tavern_upgrade_cost()
	
	if not can_afford(upgrade_cost):
		print("Cannot afford tavern upgrade - need ", upgrade_cost, " gold, have ", current_gold)
		return false
	
	if spend_gold(upgrade_cost):
		shop_tier += 1
		
		# Reset tavern upgrade cost to base cost for next tier
		var next_tier_after_upgrade = shop_tier + 1
		if next_tier_after_upgrade <= 6:
			current_tavern_upgrade_cost = TAVERN_UPGRADE_BASE_COSTS.get(next_tier_after_upgrade, 0)
			print("Upgraded tavern to tier ", shop_tier, " for ", upgrade_cost, " gold. Next upgrade costs ", current_tavern_upgrade_cost)
		else:
			print("Upgraded tavern to tier ", shop_tier, " for ", upgrade_cost, " gold. Max tier reached!")
		
		# Emit signals for state changes
		shop_tier_changed.emit(shop_tier)
		return true
	
	return false

# Health Management Functions
func take_damage(damage: int, is_player: bool = true) -> void:
	"""Apply damage to player or enemy and check for game over"""
	if is_player:
		player_health = max(0, player_health - damage)
		player_health_changed.emit(player_health)
		print("Player took %d damage, health now: %d" % [damage, player_health])
		if player_health <= 0:
			game_over.emit("enemy")
			print("GAME OVER - Enemy wins!")
	else:
		enemy_health = max(0, enemy_health - damage)
		enemy_health_changed.emit(enemy_health)
		print("Enemy took %d damage, health now: %d" % [damage, enemy_health])
		if enemy_health <= 0:
			game_over.emit("player")
			print("GAME OVER - Player wins!")

func get_player_health() -> int:
	"""Get current player health"""
	return player_health

func get_enemy_health() -> int:
	"""Get current enemy health"""
	return enemy_health

func reset_health() -> void:
	"""Reset both players to starting health (for testing)"""
	player_health = 25
	enemy_health = 25
	player_health_changed.emit(player_health)
	enemy_health_changed.emit(enemy_health)
	print("Health reset - Player: %d, Enemy: %d" % [player_health, enemy_health])

func set_enemy_health(health: int) -> void:
	"""Set enemy health (useful for testing different enemy board healths)"""
	enemy_health = max(0, health)
	enemy_health_changed.emit(enemy_health)
	print("Enemy health set to: %d" % enemy_health)

# Print current state for debugging
func debug_print_state():
	print("=== GameState Debug ===")
	print("Turn: ", current_turn)
	print("Gold: ", current_gold, "/", GLOBAL_GOLD_MAX, " (Base: ", player_base_gold, ", Bonus: ", bonus_gold, ")")
	print("Shop Tier: ", shop_tier, " (Upgrade Cost: ", current_tavern_upgrade_cost, ")")
	print("Health - Player: ", player_health, ", Enemy: ", enemy_health)
	print("Mode: ", GameMode.keys()[current_mode])
	print("======================") 