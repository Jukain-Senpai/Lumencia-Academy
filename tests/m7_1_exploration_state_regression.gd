extends SceneTree

const ExplorationStateModel := preload("res://scripts/systems/exploration_state.gd")
const DESIGN_PATH := "res://docs/M7_1_EXPLORATION_STATE_DESIGN.md"

const PRIMARY_CONTEXT := {
	"id": "m7_1_primary",
	"starting_node": "A",
	"nodes": [
		{
			"id": "A",
			"connections": ["B"],
			"initially_revealed": true,
			"reveal_on_complete": [],
			"reusable": false,
			"initial_roadblock": false,
		},
		{
			"id": "B",
			"connections": ["A", "C"],
			"initially_revealed": true,
			"reveal_on_complete": ["C"],
			"reusable": true,
			"initial_roadblock": true,
		},
		{
			"id": "C",
			"connections": ["B"],
			"initially_revealed": false,
			"reveal_on_complete": [],
			"reusable": false,
			"initial_roadblock": false,
		},
		{
			"id": "ShopLikeName",
			"connections": [],
			"initially_revealed": true,
			"reveal_on_complete": [],
			"reusable": false,
			"initial_roadblock": false,
		},
	],
}

const SECOND_CONTEXT := {
	"id": "m7_1_secondary",
	"starting_node": "X",
	"nodes": [
		{
			"id": "X",
			"connections": ["OddReusableName"],
			"initially_revealed": true,
			"reveal_on_complete": [],
			"reusable": false,
			"initial_roadblock": false,
		},
		{
			"id": "OddReusableName",
			"connections": ["X"],
			"initially_revealed": true,
			"reveal_on_complete": [],
			"reusable": true,
			"initial_roadblock": false,
		},
	],
}

var failures: Array[String] = []
var checks := 0
var state: RefCounted


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	state = root.get_node("GameState").exploration_state
	state.clear_runtime()
	_test_definition_validation_and_activation()
	_test_invalid_travel()
	_test_core_flow_and_independent_facts()
	_test_roadblock_lifecycle()
	_test_reveal_idempotence()
	_test_reusable_metadata()
	_test_context_reset()
	_test_game_state_reset_ownership()

	if failures.is_empty():
		print("M7.1 exploration state regression suite passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	push_error("M7.1 exploration state suite failed: %d failure(s), %d checks." % [failures.size(), checks])
	quit(1)


func _test_definition_validation_and_activation() -> void:
	_check(FileAccess.file_exists(DESIGN_PATH), "DESIGN: M7.1 design record is missing")
	_check(not state.has_active_context(), "ACTIVATE: exploration unexpectedly began active")
	_check(not state.activate_context("unknown"), "ACTIVATE: unknown context was accepted")
	_check(state.active_context_id.is_empty() and state.current_node_id.is_empty(), "ACTIVATE: unknown context corrupted inactive state")
	_check(not state.define_context({}), "DEFINE: empty context was accepted")
	var invalid_start: Dictionary = PRIMARY_CONTEXT.duplicate(true)
	invalid_start["starting_node"] = "missing"
	_check(not state.define_context(invalid_start), "DEFINE: missing starting node was accepted")
	var invalid_connection: Dictionary = PRIMARY_CONTEXT.duplicate(true)
	invalid_connection["nodes"][0]["connections"] = ["missing"]
	_check(not state.define_context(invalid_connection), "DEFINE: unknown connection target was accepted")
	_check(state.define_context(PRIMARY_CONTEXT), "DEFINE: valid primary context was rejected")
	_check(state.define_context(SECOND_CONTEXT), "DEFINE: valid secondary context was rejected")
	_check(state.activate_context("m7_1_primary"), "ACTIVATE: valid primary context was rejected")
	_check(state.active_context_id == "m7_1_primary", "ACTIVATE: active context ID is wrong")
	_check(state.current_node_id == "A", "ACTIVATE: starting location is not A")
	_check(state.is_node_revealed("A") and state.is_node_revealed("B"), "ACTIVATE: initial A/B reveal state is wrong")
	_check(not state.is_node_revealed("C"), "ACTIVATE: C did not begin hidden")
	_check(state.is_node_roadblocked("B"), "ACTIVATE: B did not receive its initial roadblock")


func _test_invalid_travel() -> void:
	var before := _snapshot()
	_check(not state.move_to_node("C"), "TRAVEL: hidden C was accepted")
	_check(_snapshot() == before, "TRAVEL: hidden destination corrupted state")
	_check(not state.move_to_node("ShopLikeName"), "TRAVEL: disconnected revealed destination was accepted")
	_check(_snapshot() == before, "TRAVEL: disconnected destination corrupted state")
	_check(not state.move_to_node("unknown"), "TRAVEL: unknown destination was accepted")
	_check(_snapshot() == before, "TRAVEL: unknown destination corrupted state")
	state.clear_runtime()
	_check(not state.move_to_node("A"), "TRAVEL: move without active context was accepted")
	_check(state.current_node_id.is_empty(), "TRAVEL: failed inactive move assigned a location")
	_check(state.activate_context("m7_1_primary"), "TRAVEL: primary context could not be restored")


func _test_core_flow_and_independent_facts() -> void:
	_check(state.can_travel_to("B"), "CORE: revealed connected B was not available")
	_check(state.move_to_node("B"), "CORE: A to B travel failed")
	_check(state.current_node_id == "B", "CORE: B did not become current")
	_check(not state.is_node_completed("B"), "CORE: travel automatically completed B")
	_check(state.is_node_roadblocked("B"), "CORE: travel cleared B's roadblock")
	_check(state.is_node_reusable("B"), "CORE: authored reusable metadata was lost")
	_check(state.complete_primary_content("B"), "CORE: completing B failed")
	_check(state.current_node_id == "B", "CORE: completion changed current location")
	_check(state.is_node_completed("B"), "CORE: B was not marked completed")
	_check(state.is_node_revealed("C"), "CORE: completing B did not reveal C")
	_check(state.is_node_roadblocked("B"), "CORE: completion cleared B's independent roadblock")
	_check(state.is_node_reusable("B"), "CORE: completion changed reusable metadata")
	_check(state.move_to_node("A"), "CORE: B to A return failed")
	_check(state.current_node_id == "A", "CORE: A did not become current on return")
	_check(state.is_node_completed("B") and state.is_node_revealed("C"), "CORE: completion or reveal did not persist away from B")
	_check(state.move_to_node("B"), "CORE: completed B was not traversable")
	_check(state.current_node_id == "B" and state.is_node_completed("B"), "CORE: second arrival reset B completion")
	_check(state.is_node_roadblocked("B") and state.is_node_reusable("B"), "MULTI-STATE: B did not remain current/completed/roadblocked/reusable")
	var before_duplicate := _snapshot()
	_check(state.complete_primary_content("B"), "CORE: duplicate completion was not idempotently accepted")
	_check(_snapshot() == before_duplicate, "CORE: duplicate completion changed established state")
	_check(not state.complete_primary_content("unknown"), "COMPLETE: unknown node was accepted")
	_check(_snapshot() == before_duplicate, "COMPLETE: unknown node corrupted state")


func _test_roadblock_lifecycle() -> void:
	_check(state.is_node_roadblocked("B"), "ROADBLOCK: B did not retain initial roadblock")
	_check(state.move_to_node("A") and state.move_to_node("B"), "ROADBLOCK: travel away/back failed")
	_check(state.is_node_roadblocked("B"), "ROADBLOCK: roadblock did not persist through travel")
	_check(state.set_node_roadblocked("B", false), "ROADBLOCK: explicit clear failed")
	_check(not state.is_node_roadblocked("B"), "ROADBLOCK: explicit clear left B roadblocked")
	_check(state.is_node_completed("B"), "ROADBLOCK: clearing roadblock erased completion")
	_check(state.set_node_roadblocked("B", false), "ROADBLOCK: duplicate clear was not idempotent")
	_check(state.set_node_roadblocked("B", true), "ROADBLOCK: explicit set failed")
	_check(state.is_node_roadblocked("B") and state.is_node_completed("B"), "ROADBLOCK: set could not coexist with completion")
	var before := _snapshot()
	_check(not state.set_node_roadblocked("unknown", true), "ROADBLOCK: unknown node was accepted")
	_check(_snapshot() == before, "ROADBLOCK: unknown mutation corrupted state")


func _test_reveal_idempotence() -> void:
	var before := _snapshot()
	_check(state.reveal_node("C"), "REVEAL: duplicate reveal was rejected")
	_check(_snapshot() == before, "REVEAL: duplicate reveal changed established state")
	_check(not state.reveal_node("unknown"), "REVEAL: unknown node was accepted")
	_check(_snapshot() == before, "REVEAL: unknown node corrupted state")


func _test_reusable_metadata() -> void:
	_check(state.is_node_reusable("B"), "REUSABLE: B's authored true value was not returned")
	_check(not state.is_node_reusable("ShopLikeName"), "REUSABLE: shop-like name overrode authored false value")
	_check(not state.is_node_reusable("unknown"), "REUSABLE: unknown node reported reusable")


func _test_context_reset() -> void:
	_check(state.activate_context("m7_1_secondary"), "RESET: secondary context activation failed")
	_check(state.active_context_id == "m7_1_secondary" and state.current_node_id == "X", "RESET: secondary identity/start is wrong")
	_check(state.is_node_revealed("X") and state.is_node_revealed("OddReusableName"), "RESET: secondary reveal state is wrong")
	_check(not state.has_node("A") and not state.is_node_completed("B"), "RESET: primary nodes or completion leaked")
	_check(not state.is_node_roadblocked("B"), "RESET: primary roadblock leaked")
	_check(state.is_node_reusable("OddReusableName"), "REUSABLE: strangely named node lost authored true value")
	_check(state.move_to_node("OddReusableName"), "RESET: secondary context travel failed")
	_check(state.current_node_id == "OddReusableName" and not state.is_node_completed("OddReusableName"), "RESET: secondary travel consumed content")


func _test_game_state_reset_ownership() -> void:
	var game_state: Node = root.get_node("GameState")
	game_state.reset_state()
	_check(game_state.exploration_state == state, "OWNERSHIP: GameState replaced the ExplorationState owner")
	_check(not state.has_active_context() and state.current_node_id.is_empty(), "OWNERSHIP: GameState reset retained active exploration runtime")
	_check(state.revealed_nodes.is_empty() and state.completed_nodes.is_empty() and state.roadblocked_nodes.is_empty(), "OWNERSHIP: GameState reset retained node runtime facts")
	_check(state.activate_context("m7_1_primary"), "OWNERSHIP: static context definitions were lost during runtime reset")
	_check(state.current_node_id == "A" and not state.is_node_completed("B"), "OWNERSHIP: fresh activation did not restore authored initial state")
	state.clear_runtime()


func _snapshot() -> Dictionary:
	return {
		"context": state.active_context_id,
		"current": state.current_node_id,
		"revealed": state.revealed_nodes.duplicate(true),
		"completed": state.completed_nodes.duplicate(true),
		"roadblocked": state.roadblocked_nodes.duplicate(true),
	}


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
