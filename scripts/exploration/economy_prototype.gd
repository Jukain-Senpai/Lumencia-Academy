extends Control

const ItemCatalogModel := preload("res://scripts/systems/item_catalog.gd")
const PROTOTYPE_STARTING_MONEY := 12
const PROTOTYPE_STARTING_HERBS := 9
const PROTOTYPE_HIRUKO_HP := 20


func _enter_tree() -> void:
	# This entry scene starts a fresh test session. Returning to the map never uses it.
	GameState.reset_state()
	GameState.gain_money(PROTOTYPE_STARTING_MONEY)
	GameState.inventory_state.gain_item(
		ItemCatalogModel.HEALING_HERB_ID,
		PROTOTYPE_STARTING_HERBS
	)
	GameState.party_runtime_state.set_current_hp("party_1", PROTOTYPE_HIRUKO_HP)
