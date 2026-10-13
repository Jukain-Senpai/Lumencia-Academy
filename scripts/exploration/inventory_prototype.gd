extends Control

const ItemCatalogModel := preload("res://scripts/systems/item_catalog.gd")
const DAMAGED_MEMBER_ID := "party_1"
const PROTOTYPE_HERB_QUANTITY := 9
const PROTOTYPE_HIRUKO_HP := 20


func _enter_tree() -> void:
	GameState.reset_state()
	GameState.inventory_state.gain_item(
		ItemCatalogModel.HEALING_HERB_ID,
		PROTOTYPE_HERB_QUANTITY
	)
	GameState.party_runtime_state.set_current_hp(DAMAGED_MEMBER_ID, PROTOTYPE_HIRUKO_HP)
