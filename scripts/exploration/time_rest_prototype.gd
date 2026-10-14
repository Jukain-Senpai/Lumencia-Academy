extends Control

const BASE_PROTOTYPE_SCRIPT := "res://scripts/exploration/exploration_prototype.gd"
const ItemCatalogModel := preload("res://scripts/systems/item_catalog.gd")
const TIMED_CONTEXT_ID := "m7_6_timed_prototype_forest"
const PROTOTYPE_STARTING_MONEY := 12
const PROTOTYPE_STARTING_HERBS := 9
const PROTOTYPE_HIRUKO_HP := 20

var context_ready := false


func _enter_tree() -> void:
	GameState.reset_state()
	GameState.gain_money(PROTOTYPE_STARTING_MONEY)
	GameState.inventory_state.gain_item(ItemCatalogModel.HEALING_HERB_ID, PROTOTYPE_STARTING_HERBS)
	GameState.party_runtime_state.set_current_hp("party_1", PROTOTYPE_HIRUKO_HP)
	var context := build_context()
	context_ready = GameState.exploration_state.define_context(context)
	if context_ready:
		context_ready = GameState.exploration_state.activate_context(TIMED_CONTEXT_ID)
	if not context_ready:
		push_error("M7.6 timed Exploration prototype context is invalid.")


static func build_context() -> Dictionary:
	var base_script: Script = load(BASE_PROTOTYPE_SCRIPT)
	var context: Dictionary = base_script.get_script_constant_map()["PROTOTYPE_CONTEXT"].duplicate(true)
	context["id"] = TIMED_CONTEXT_ID
	context["time"] = {"mode": "MULTI_DAY"}
	for node_definition: Dictionary in context["nodes"]:
		if node_definition["id"] == "riverside_camp":
			node_definition["hub_actions"].append({
				"id": "prototype_camp_rest",
				"type": "rest",
				"display_name": "Camp Rest",
				"max_uses": 2,
			})
			node_definition["hub_actions"].append({
				"id": "prototype_wait",
				"type": "wait",
				"display_name": "Wait / Advance Time",
			})
			break
	return context
