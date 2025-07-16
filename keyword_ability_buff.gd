class_name KeywordAbilityBuff
extends Buff

@export var ability_name: String  # "taunt", "divine_shield", etc.
@export var ability_data: Dictionary = {}  # Additional ability parameters

func _init():
	buff_type = BuffType.KEYWORD_ABILITY

func apply_to_minion(minion) -> void:
	"""Apply keyword ability to a minion"""
	if minion.has_method("add_keyword_ability"):
		minion.add_keyword_ability(ability_name, ability_data)

func remove_from_minion(minion) -> void:
	"""Remove keyword ability from a minion"""
	if minion.has_method("remove_keyword_ability"):
		minion.remove_keyword_ability(ability_name)

func duplicate() -> KeywordAbilityBuff:
	"""Create a deep copy of this buff"""
	var copy = KeywordAbilityBuff.new()
	copy.buff_id = buff_id
	copy.display_name = display_name
	copy.description = description
	copy.duration = duration
	copy.turns_remaining = turns_remaining
	copy.source_id = source_id
	copy.stackable = stackable
	copy.properties = properties.duplicate()
	copy.ability_name = ability_name
	copy.ability_data = ability_data.duplicate()
	return copy 