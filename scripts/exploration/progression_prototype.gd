extends Control

const TimedPrototypeModel := preload("res://scripts/exploration/time_rest_prototype.gd")
const ItemCatalogModel := preload("res://scripts/systems/item_catalog.gd")
const PROGRESSION_CONTEXT_ID := "m7_7_progression_prototype_forest"
const FINAL_NODE_ID := "forest_boundary"

var context_ready := false


func _enter_tree() -> void:
	var state: ExplorationState = GameState.exploration_state
	if state.is_context_closed(PROGRESSION_CONTEXT_ID):
		push_error("M7.7 Exploration context is closed and cannot be reopened.")
		return
	if state.active_context_id == PROGRESSION_CONTEXT_ID:
		context_ready = true
		return
	if state.has_active_context():
		push_error("Another Exploration context is already active.")
		return
	GameState.reset_state()
	GameState.gain_money(TimedPrototypeModel.PROTOTYPE_STARTING_MONEY)
	GameState.inventory_state.gain_item(
		ItemCatalogModel.HEALING_HERB_ID,
		TimedPrototypeModel.PROTOTYPE_STARTING_HERBS
	)
	GameState.party_runtime_state.set_current_hp("party_1", TimedPrototypeModel.PROTOTYPE_HIRUKO_HP)
	var context := build_context()
	context_ready = state.define_context(context)
	if context_ready:
		context_ready = state.activate_context(PROGRESSION_CONTEXT_ID)
	if not context_ready:
		push_error("M7.7 progression Exploration prototype context is invalid.")


static func build_context() -> Dictionary:
	var context: Dictionary = TimedPrototypeModel.build_context()
	context["id"] = PROGRESSION_CONTEXT_ID
	context["display_name"] = "Prototype Forest — Story Exit"
	for node_definition: Dictionary in context["nodes"]:
		match node_definition["id"]:
			"old_trail":
				node_definition["connections"].append(FINAL_NODE_ID)
			"riverside_camp", "stone_crossing", "ruins_approach":
				node_definition["primary_content"]["optional"] = true
	context["nodes"].append({
		"id": FINAL_NODE_ID,
		"display_name": "Forest Boundary",
		"map_position": Vector2(0.54, 0.72),
		"connections": ["old_trail"],
		"initially_revealed": true,
		"reveal_on_complete": [],
		"reusable": false,
		"initial_roadblock": false,
		"final_progression": {
			"destination": ExplorationState.PROTOTYPE_FINAL_DESTINATION,
		},
	})
	return context
