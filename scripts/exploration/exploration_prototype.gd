extends Control

const PROTOTYPE_CONTEXT := {
	"id": "m7_2_prototype_forest",
	"display_name": "Prototype Forest",
	"starting_node": "old_trail",
	"nodes": [
		{
			"id": "old_trail",
			"display_name": "Old Trail",
			"map_position": Vector2(0.17, 0.70),
			"connections": ["riverside_camp"],
			"initially_revealed": true,
			"reveal_on_complete": [],
			"reusable": false,
			"initial_roadblock": false,
		},
		{
			"id": "riverside_camp",
			"display_name": "Riverside Camp",
			"map_position": Vector2(0.34, 0.19),
			"connections": ["old_trail", "stone_crossing", "deep_grove"],
			"initially_revealed": true,
			"reveal_on_complete": ["deep_grove"],
			"reusable": true,
			"initial_roadblock": true,
			"primary_content": {
				"type": "vn_event",
				"id": "m7_3_riverside_event",
			},
		},
		{
			"id": "stone_crossing",
			"display_name": "Stone Crossing",
			"map_position": Vector2(0.54, 0.43),
			"connections": ["riverside_camp", "ruins_approach"],
			"initially_revealed": true,
			"reveal_on_complete": [],
			"reusable": false,
			"initial_roadblock": false,
			"primary_content": {
				"type": "battle",
				"id": "m7_3_stone_crossing_battle",
			},
		},
		{
			"id": "ruins_approach",
			"display_name": "Ruins Approach",
			"map_position": Vector2(0.79, 0.19),
			"connections": ["stone_crossing"],
			"initially_revealed": true,
			"reveal_on_complete": [],
			"reusable": false,
			"initial_roadblock": false,
			"primary_content": {
				"type": "resource",
				"id": "m7_3_ruins_resource",
				"reward": {
					"type": "item",
					"item_id": "healing_herb",
					"quantity": 2,
				},
			},
		},
		{
			"id": "deep_grove",
			"display_name": "Deep Grove",
			"map_position": Vector2(0.84, 0.77),
			"connections": ["riverside_camp"],
			"initially_revealed": false,
			"reveal_on_complete": [],
			"reusable": false,
			"initial_roadblock": false,
		},
	],
}

var context_ready := false


func _enter_tree() -> void:
	var exploration_state: RefCounted = GameState.exploration_state
	if exploration_state.active_context_id == PROTOTYPE_CONTEXT["id"]:
		context_ready = true
		return
	context_ready = exploration_state.define_context(PROTOTYPE_CONTEXT)
	if context_ready:
		context_ready = exploration_state.activate_context(PROTOTYPE_CONTEXT["id"])
