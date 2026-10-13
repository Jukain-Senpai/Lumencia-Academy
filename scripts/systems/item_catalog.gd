class_name ItemCatalog
extends RefCounted

const BATTLE_ONLY := "BATTLE_ONLY"
const EXPLORATION_ONLY := "EXPLORATION_ONLY"
const BOTH := "BOTH"
const HEALING_HERB_ID := "healing_herb"
const HEALING_HERB_PROTOTYPE_HEAL := 18

const DEFINITIONS := {
	HEALING_HERB_ID: {
		"id": HEALING_HERB_ID,
		"display_name": "Healing Herb",
		"use_context": BOTH,
		"effect": {
			"type": "heal",
			"amount": HEALING_HERB_PROTOTYPE_HEAL,
		},
	},
}


static func get_definition(item_id: String) -> Dictionary:
	if not DEFINITIONS.has(item_id):
		return {}
	return DEFINITIONS[item_id].duplicate(true)


static func get_all_definitions() -> Dictionary:
	return DEFINITIONS.duplicate(true)
