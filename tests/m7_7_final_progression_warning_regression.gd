extends SceneTree

const ENTRY := "res://scenes/exploration/m7_7_progression_prototype.tscn"
const RESULT := "res://scenes/exploration/m7_7_progression_result.tscn"
const MAP_SCENE := "res://scenes/exploration/exploration_map.tscn"
const DESIGN := "res://docs/M7_7_FINAL_PROGRESSION_WARNING_DESIGN.md"
const PROGRESSION_SCRIPT := "res://scripts/exploration/progression_prototype.gd"
const TIMED_SCRIPT := "res://scripts/exploration/time_rest_prototype.gd"
const BASE_SCRIPT := "res://scripts/exploration/exploration_prototype.gd"
const CONTEXT_ID := "m7_7_progression_prototype_forest"
const FINAL_ID := "forest_boundary"

var failures: Array[String] = []
var checks := 0
var game_state: Node
var state: ExplorationState


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1152, 648)
	root.content_scale_size = Vector2i(1152, 648)
	game_state = root.get_node("GameState")
	state = game_state.exploration_state
	_test_data_validation()
	_test_missable_detection()
	await _test_warning_cancel_and_state_preservation()
	await _test_preference_and_early_exit()
	await _test_preference_scene_transitions()
	await _test_no_warning_and_leftover()
	await _test_failure_safety()
	await _test_real_control_input()
	await _test_responsive_layout()
	await _free_current_scene()
	game_state.reset_state()
	_check(not state.is_context_closed(CONTEXT_ID), "RESET: fresh session retained closed context")
	_check(game_state.is_missable_content_warning_enabled(), "RESET: warning preference did not restore ON")
	if failures.is_empty():
		print("M7.7 final progression/warning regression suite passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	push_error("M7.7 final progression/warning suite failed: %d failure(s), %d checks." % [failures.size(), checks])
	quit(1)


func _test_data_validation() -> void:
	_check(FileAccess.file_exists(DESIGN), "DATA: M7.7 design document missing")
	_check(ResourceLoader.exists(ENTRY) and ResourceLoader.exists(RESULT), "DATA: progression scenes missing")
	game_state.reset_state()
	var context: Dictionary = _progression_context()
	_check(context["id"] == CONTEXT_ID and context["time"]["mode"] == "MULTI_DAY", "DATA: M7.7 context did not derive timed prototype")
	_check(context["nodes"].size() == 6, "DATA: prototype does not have five prior nodes plus final node")
	var base: Dictionary = _timed_context()
	for base_node: Dictionary in base["nodes"]:
		var matching: Dictionary = _find_node(context, base_node["id"])
		_check(not matching.is_empty(), "DATA: existing node disappeared: %s" % base_node["id"])
		_check(matching.get("map_position") == base_node.get("map_position"), "DATA: existing map coordinate moved: %s" % base_node["id"])
		_check(matching.get("initial_roadblock") == base_node.get("initial_roadblock") and matching.get("reveal_on_complete") == base_node.get("reveal_on_complete"), "DATA: existing reveal/roadblock changed: %s" % base_node["id"])
	_check(_find_node(context, "old_trail")["connections"].has(FINAL_ID), "DATA: Old Trail does not connect to Forest Boundary")
	_check(_find_node(context, FINAL_ID)["connections"].has("old_trail"), "DATA: Forest Boundary lacks return connection")
	_check(_find_node(context, FINAL_ID)["final_progression"]["destination"] == ExplorationState.PROTOTYPE_FINAL_DESTINATION, "DATA: final destination metadata wrong")
	_check(_find_node(context, FINAL_ID)["map_position"] == Vector2(0.54, 0.72), "DATA: final map placement changed")
	for node_id: String in ["riverside_camp", "stone_crossing", "ruins_approach"]:
		_check(_find_node(context, node_id)["primary_content"].get("optional") == true, "DATA: primary content not authored optional: %s" % node_id)
	_check(not _find_node(context, "deep_grove").has("primary_content"), "DATA: empty Deep Grove gained content")
	_check(state.define_context(context) and state.activate_context(CONTEXT_ID), "DATA: valid final context rejected")
	_check(state.has_final_progression_node() and state.get_node_definition(FINAL_ID).has("final_progression"), "DATA: final node not exposed")
	_check(state.can_travel_to(FINAL_ID) and state.move_to_node(FINAL_ID), "DATA: final node not reachable through normal travel")
	_check(state.current_node_id == FINAL_ID and not state.is_node_completed(FINAL_ID), "DATA: travel consumed final content")
	_check(state.get_missable_content_summary()["total"] == 3, "DATA: early exit did not see three optional events")
	var copied: Dictionary = state.get_node_definition(FINAL_ID)
	copied["final_progression"]["destination"] = "tampered"
	_check(state.get_node_definition(FINAL_ID)["final_progression"]["destination"] == ExplorationState.PROTOTYPE_FINAL_DESTINATION, "DATA: final metadata copy leaked")
	for field: String in ["destination", "unsupported"]:
		var bad: Dictionary = context.duplicate(true)
		bad["id"] = "invalid_final_%s" % field
		if field == "destination":
			_find_node(bad, FINAL_ID)["final_progression"]["destination"] = "unknown_destination"
		else:
			_find_node(bad, FINAL_ID)["final_progression"]["unsupported"] = true
		_check(not state.define_context(bad), "DATA: malformed/unsupported final metadata accepted: %s" % field)
	var duplicate: Dictionary = context.duplicate(true)
	duplicate["id"] = "duplicate_final"
	_find_node(duplicate, "deep_grove")["final_progression"] = {"destination": ExplorationState.PROTOTYPE_FINAL_DESTINATION}
	_check(not state.define_context(duplicate), "DATA: duplicate final nodes accepted")
	var mixed: Dictionary = context.duplicate(true)
	mixed["id"] = "mixed_final"
	_find_node(mixed, FINAL_ID)["primary_content"] = {"type": "battle", "id": "invalid"}
	_check(not state.define_context(mixed), "DATA: final battle/content combination accepted")
	var bad_optional: Dictionary = context.duplicate(true)
	bad_optional["id"] = "bad_optional"
	_find_node(bad_optional, "riverside_camp")["primary_content"]["optional"] = "yes"
	_check(not state.define_context(bad_optional), "DATA: nonboolean optional primary metadata accepted")
	var bad_roadblock: Dictionary = context.duplicate(true)
	bad_roadblock["id"] = "bad_roadblock"
	_find_node(bad_roadblock, "riverside_camp")["optional_missable_roadblock"] = 1
	_check(not state.define_context(bad_roadblock), "DATA: nonboolean optional roadblock metadata accepted")
	var base_script: Script = load(BASE_SCRIPT)
	_check(not base_script.get_script_constant_map()["PROTOTYPE_CONTEXT"]["nodes"].any(func(node: Dictionary) -> bool: return node.has("final_progression")), "DATA: old prototype gained final node")
	_check(not _timed_context()["nodes"].any(func(node: Dictionary) -> bool: return node.has("final_progression")), "DATA: M7.6 prototype gained final node")
	var save_shape: Dictionary = game_state._normalize_save_data({"sequence": "fixture", "node": "fixture", "flags": {}, "bonds": {}})
	_check(save_shape.keys().size() == 4 and save_shape.has_all(["sequence", "node", "flags", "bonds"]), "DATA: M2 save schema expanded")
	game_state.reset_state()


func _test_missable_detection() -> void:
	var context: Dictionary = _progression_context()
	context["id"] = "m7_7_detection_fixture"
	_find_node(context, "stone_crossing")["initially_revealed"] = false
	_find_node(context, "riverside_camp")["optional_missable_roadblock"] = true
	_check(state.define_context(context) and state.activate_context(context["id"]), "MISSABLE: detection fixture invalid")
	var summary: Dictionary = state.get_missable_content_summary()
	_check(summary["optional_primary_count"] == 3 and summary["leftover_reward_count"] == 0, "MISSABLE: optional VN/Battle/Resource count wrong")
	_check(not state.is_node_revealed("stone_crossing") and summary["total"] == 4, "MISSABLE: hidden event or authored roadblock not counted")
	_check(summary["optional_roadblock_count"] == 1, "MISSABLE: authored active roadblock missing")
	summary["optional_primary_count"] = 99
	_check(state.get_missable_content_summary()["optional_primary_count"] == 3, "MISSABLE: returned summary mutates runtime")
	_check(state.complete_primary_content("riverside_camp"), "MISSABLE: Riverside completion failed")
	_check(state.get_missable_content_summary()["optional_primary_count"] == 2, "MISSABLE: completed VN still counted")
	_check(state.complete_primary_content("stone_crossing"), "MISSABLE: hidden Stone completion failed")
	_check(state.get_missable_content_summary()["optional_primary_count"] == 1, "MISSABLE: completed Battle still counted")
	_check(state.complete_primary_content("ruins_approach"), "MISSABLE: Ruins completion failed")
	_check(state.get_missable_content_summary()["optional_primary_count"] == 0, "MISSABLE: completed Resource still counted")
	_check(state.set_leftover_reward("ruins_approach", "healing_herb", 2), "MISSABLE: leftover setup failed")
	_check(state.get_missable_content_summary()["leftover_reward_count"] == 1, "MISSABLE: completed Resource leftover not counted")
	_check(state.reduce_leftover_reward("ruins_approach", 2), "MISSABLE: leftover collection failed")
	_check(state.get_missable_content_summary()["leftover_reward_count"] == 0, "MISSABLE: collected reward still counted")
	_check(state.set_node_roadblocked("riverside_camp", false), "MISSABLE: roadblock clear failed")
	_check(state.get_missable_content_summary()["total"] == 0, "MISSABLE: fully resolved content still counted")
	_check(state.set_leftover_reward(FINAL_ID, "healing_herb", 1), "MISSABLE: final-node exclusion setup failed")
	_check(state.get_missable_content_summary()["total"] == 0, "MISSABLE: final node itself was counted")
	_check(state.is_node_reusable("riverside_camp") and state.get_hub_action_uses_remaining("riverside_camp", "prototype_camp_rest") == 2, "MISSABLE: reusable Shop/Rest fixture changed")
	game_state.reset_state()
	var ordinary: Dictionary = _progression_context()
	_check(state.define_context(ordinary) and state.activate_context(CONTEXT_ID), "MISSABLE: ordinary fixture invalid")
	for node_id: String in ["riverside_camp", "stone_crossing", "ruins_approach"]:
		state.complete_primary_content(node_id)
	_check(state.is_node_roadblocked("riverside_camp") and state.get_missable_content_summary()["total"] == 0, "MISSABLE: ordinary Riverside roadblock was counted")
	game_state.reset_state()


func _test_warning_cancel_and_state_preservation() -> void:
	var map: Variant = await _fresh_map()
	if map == null:
		return
	_check(game_state.is_missable_content_warning_enabled() and map.warning_preference_button.button_pressed, "WARNING: default is not ON")
	_check(map.warning_preference_panel.visible and map.time_panel.visible, "WARNING: toggle/time panel not visible")
	_check(not map.get_marker_button(FINAL_ID).disabled and map.get_marker_button(FINAL_ID).get_meta("is_final_progression"), "WARNING: final marker unavailable")
	_check(map.get_marker_button(FINAL_ID).get_node("FinalBadge").visible, "WARNING: final marker lacks story-exit badge")
	_travel(map, FINAL_ID)
	await process_frame
	_check(state.current_node_id == FINAL_ID and not state.is_node_completed(FINAL_ID), "WARNING: final travel consumed content")
	_check(map.primary_action_button.text == "Advance Story", "WARNING: explicit Advance Story action missing")
	game_state.set_flag("m7_7_test_flag", true)
	game_state.adjust_bond("m7_7_test_bond", 2)
	var before: Dictionary = _session_snapshot()
	map.primary_action_button.emit_signal("pressed")
	_check(map.warning_dialog_open and map.warning_overlay.visible, "WARNING: unfinished content did not open warning")
	_check(map.warning_summary_label.text.contains("Optional events: 3"), "WARNING: summary count missing")
	_check(not map.warning_summary_label.text.contains("Stone") and not map.warning_summary_label.text.contains("Riverside"), "WARNING: summary spoiled location identities")
	_check(map.warning_go_back_button.has_focus(), "WARNING: Go Back is not default focus")
	_check(map.primary_action_button.disabled and map.inventory_button.disabled and map.warning_preference_button.disabled, "WARNING: underlying actions remain enabled")
	_check(map.get_marker_button("old_trail").disabled, "WARNING: underlying travel remains enabled")
	map._on_marker_pressed("old_trail")
	_check(state.current_node_id == FINAL_ID, "WARNING: marker activated beneath dialog")
	map.warning_go_back_button.emit_signal("pressed")
	_check(not map.warning_dialog_open and not map.warning_overlay.visible, "GO BACK: warning stayed open")
	_check(_session_snapshot() == before, "GO BACK: cancellation changed session state")
	_check(map.primary_action_button.has_focus(), "GO BACK: Advance Story focus not restored")
	_check(not map.primary_action_button.disabled and not map.inventory_button.disabled, "GO BACK: controls not restored")
	map.primary_action_button.emit_signal("pressed")
	_check(map.warning_dialog_open, "GO BACK: second attempt did not warn")
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	map._unhandled_input(cancel)
	_check(not map.warning_dialog_open and _session_snapshot() == before, "GO BACK: Cancel/Back changed state")
	_travel(map, "old_trail")
	_check(state.current_node_id == "old_trail", "GO BACK: normal navigation did not resume")
	_check(state.get_time_snapshot()["total_actions"] == 0, "GO BACK: travel/cancel spent time")
	_travel(map, FINAL_ID)
	_check(state.current_node_id == FINAL_ID, "GO BACK: final node cannot be revisited")


func _test_preference_and_early_exit() -> void:
	var map: Variant = await _fresh_map()
	if map == null:
		return
	_check(not game_state.set_missable_content_warning_enabled("off"), "PREFERENCE: nonboolean setter accepted")
	_check(game_state.is_missable_content_warning_enabled(), "PREFERENCE: invalid setter changed preference")
	map.warning_preference_button.button_pressed = false
	_check(not game_state.is_missable_content_warning_enabled(), "PREFERENCE: OFF toggle did not update GameState")
	map = await _load_scene(MAP_SCENE)
	_check(map != null and not map.warning_preference_button.button_pressed, "PREFERENCE: map reload reset OFF")
	if map == null:
		return
	var alternate: Dictionary = _timed_context()
	_check(state.define_context(alternate) and state.activate_context(alternate["id"]), "PREFERENCE: context switch setup failed")
	_check(not game_state.is_missable_content_warning_enabled(), "PREFERENCE: context switch reset OFF")
	_check(state.activate_context(CONTEXT_ID), "PREFERENCE: return to active context failed")
	_check(map.refresh_map() and not map.warning_preference_button.button_pressed, "PREFERENCE: returned map lost OFF")
	map.warning_preference_button.button_pressed = true
	_check(game_state.is_missable_content_warning_enabled(), "PREFERENCE: OFF→ON did not restore")
	map.warning_preference_button.button_pressed = false
	_travel(map, FINAL_ID)
	var before: Dictionary = _session_snapshot()
	map.primary_action_button.emit_signal("pressed")
	_check(not map.warning_dialog_open, "CONTINUE: warning appeared while OFF")
	await process_frame
	await process_frame
	_check(current_scene != null and current_scene.name == "M7_7ProgressionResult", "CONTINUE: warning OFF did not reach result scene")
	_check(state.is_context_closed(CONTEXT_ID) and not state.has_active_context(), "CONTINUE: context was not closed")
	_check(not state.activate_context(CONTEXT_ID), "CLOSED: ordinary reactivation succeeded")
	_check(not game_state.advance_story_from_exploration(CONTEXT_ID, FINAL_ID)["success"], "CLOSED: duplicate Continue succeeded")
	_check(game_state.get_money() == before["money"] and game_state.inventory_state.get_quantity("healing_herb") == before["herbs"], "CONTINUE: economy changed")
	_check(game_state.party_runtime_state.get_hp_snapshot() == before["hp"], "CONTINUE: global HP changed")
	_check(game_state.get_flag("m7_7_test_flag") == before["flag"] and game_state.get_bond("m7_7_test_bond") == before["bond"], "CONTINUE: flags or Bonds changed")
	_check(not state.can_travel_to("old_trail") and not game_state.buy_from_current_shop("riverside_camp", "prototype_supply_shop", "healing_herb")["success"], "CLOSED: old traversal/Shop remained active")
	_check(not game_state.use_current_camp_rest("riverside_camp", "prototype_camp_rest")["success"], "CLOSED: old Camp Rest remained active")
	_check(not game_state.prepare_exploration_content("vn_event", "m7_3_riverside_event"), "CLOSED: old primary handoff remained active")
	_check(state.get_missable_content_summary()["total"] == 0, "CLOSED: old missable summary remained active")
	_check(not state.is_context_closed("m7_6_timed_prototype_forest"), "CLOSED: unrelated context was closed")
	game_state.reset_state()
	_check(not state.is_context_closed(CONTEXT_ID) and state.activate_context(CONTEXT_ID), "RESET: fresh session did not reopen context")
	_check(state.current_node_id == "old_trail" and game_state.is_missable_content_warning_enabled(), "RESET: fresh state did not restore starting node/preference")
	game_state.reset_state()


func _test_preference_scene_transitions() -> void:
	var map: Variant = await _fresh_map()
	if map == null:
		return
	map.warning_preference_button.button_pressed = false
	_travel(map, "riverside_camp")
	_check(map.interact_with_current_node(), "PREFERENCE TRANSITIONS: VN did not launch")
	await process_frame
	await process_frame
	var vn: Variant = current_scene
	_check(vn != null and vn.name == "VNPrototype", "PREFERENCE TRANSITIONS: VN scene missing")
	if vn == null or vn.name != "VNPrototype":
		return
	_check(not game_state.is_missable_content_warning_enabled(), "PREFERENCE TRANSITIONS: VN entry reset OFF")
	vn._advance_dialogue()
	vn._advance_dialogue()
	vn._advance_dialogue()
	await process_frame
	await process_frame
	map = _current_map()
	_check(map != null and not game_state.is_missable_content_warning_enabled(), "PREFERENCE TRANSITIONS: VN return reset OFF")
	if map == null:
		return
	_travel(map, "stone_crossing")
	_check(map.interact_with_current_node(), "PREFERENCE TRANSITIONS: Battle did not launch")
	await process_frame
	await process_frame
	var battle: Variant = current_scene
	_check(battle != null and battle.name == "BattleSandbox", "PREFERENCE TRANSITIONS: Battle scene missing")
	if battle == null or battle.name != "BattleSandbox":
		return
	_check(not game_state.is_missable_content_warning_enabled(), "PREFERENCE TRANSITIONS: Battle entry reset OFF")
	battle.automatic_enemy_turns_enabled = false
	for unit: Variant in battle.enemy_units:
		unit.current_hp = 0
		unit.defeated = true
	_check(battle._check_battle_result(), "PREFERENCE TRANSITIONS: Battle Victory failed")
	await process_frame
	await process_frame
	map = _current_map()
	_check(map != null and not game_state.is_missable_content_warning_enabled(), "PREFERENCE TRANSITIONS: Battle return reset OFF")
	_check(state.is_node_completed("riverside_camp") and state.is_node_completed("stone_crossing"), "PREFERENCE TRANSITIONS: VN/Battle content did not complete")
	game_state.reset_state()


func _test_no_warning_and_leftover() -> void:
	var map: Variant = await _fresh_map()
	if map == null:
		return
	for node_id: String in ["riverside_camp", "stone_crossing", "ruins_approach"]:
		_check(state.complete_primary_content(node_id), "NO WARNING: optional completion failed: %s" % node_id)
	_check(state.get_missable_content_summary()["total"] == 0, "NO WARNING: completed optional events still counted")
	_travel(map, FINAL_ID)
	_check(map.refresh_map(), "NO WARNING: map refresh failed")
	map.primary_action_button.emit_signal("pressed")
	_check(not map.warning_dialog_open, "NO WARNING: empty summary opened dialog")
	await process_frame
	await process_frame
	_check(current_scene != null and current_scene.name == "M7_7ProgressionResult", "NO WARNING: complete optional content did not advance")
	map = await _fresh_map()
	if map == null:
		return
	_check(game_state.inventory_state.gain_item("healing_herb", 1)["accepted"] == 1, "LEFTOVER: could not fill inventory")
	for node_id: String in ["riverside_camp", "stone_crossing"]:
		state.complete_primary_content(node_id)
	_travel(map, "riverside_camp")
	_travel(map, "stone_crossing")
	_travel(map, "ruins_approach")
	_check(map.interact_with_current_node(), "LEFTOVER: resource content failed")
	_check(state.is_node_completed("ruins_approach") and state.has_leftover_reward("ruins_approach"), "LEFTOVER: completed resource did not retain overflow")
	_check(state.get_missable_content_summary()["optional_primary_count"] == 0 and state.get_missable_content_summary()["leftover_reward_count"] == 1, "LEFTOVER: completed resource was not counted solely as leftover")
	_travel(map, "stone_crossing")
	_travel(map, "riverside_camp")
	_travel(map, "old_trail")
	_travel(map, FINAL_ID)
	map.primary_action_button.emit_signal("pressed")
	_check(map.warning_dialog_open and map.warning_summary_label.text.contains("Uncollected rewards: 1"), "LEFTOVER: warning did not count leftover")
	_check(not map.warning_summary_label.text.contains("Ruins"), "LEFTOVER: warning spoiled reward location")
	map.warning_go_back_button.emit_signal("pressed")
	_check(state.has_leftover_reward("ruins_approach"), "LEFTOVER: Go Back removed reward")
	_check(state.get_time_snapshot()["total_actions"] == 1, "LEFTOVER: warning/Go Back charged time")


func _test_failure_safety() -> void:
	var map: Variant = await _fresh_map()
	if map == null:
		return
	var before: Dictionary = _session_snapshot()
	_check(not game_state.advance_story_from_exploration(CONTEXT_ID, "old_trail")["success"], "FAILURE: non-final node advanced")
	_check(not game_state.advance_story_from_exploration("wrong_context", FINAL_ID)["success"], "FAILURE: wrong context advanced")
	_check(not game_state.advance_story_from_exploration(CONTEXT_ID, FINAL_ID)["success"], "FAILURE: non-current final node advanced")
	_check(_session_snapshot() == before, "FAILURE: rejected requests mutated session")
	_travel(map, FINAL_ID)
	before = _session_snapshot()
	_check(not game_state.advance_story_from_exploration(CONTEXT_ID, "stale_node")["success"], "FAILURE: stale node advanced")
	_check(game_state.prepare_pending_vn_sequence("m7_3_riverside_event"), "FAILURE: pending VN setup failed")
	_check(not game_state.advance_story_from_exploration(CONTEXT_ID, FINAL_ID)["success"], "FAILURE: pending VN did not block")
	game_state.clear_pending_vn_sequence()
	_check(game_state.prepare_exploration_content("resource", "m7_3_ruins_resource") == false, "FAILURE: invalid pending content setup unexpectedly succeeded")
	game_state.pending_exploration_content = {"context_id": CONTEXT_ID}
	_check(not game_state.advance_story_from_exploration(CONTEXT_ID, FINAL_ID)["success"], "FAILURE: pending exploration handoff did not block")
	game_state.clear_pending_exploration_content()
	_check(game_state.prepare_battle_context("prototype", "return"), "FAILURE: pending battle setup failed")
	_check(not game_state.advance_story_from_exploration(CONTEXT_ID, FINAL_ID)["success"], "FAILURE: pending Battle did not block")
	game_state.clear_pending_battle_context()
	state._active_nodes[FINAL_ID]["final_progression"]["destination"] = "unregistered"
	_check(not game_state.advance_story_from_exploration(CONTEXT_ID, FINAL_ID)["success"], "FAILURE: unsupported destination advanced")
	state._active_nodes[FINAL_ID]["final_progression"]["destination"] = ExplorationState.PROTOTYPE_FINAL_DESTINATION
	_check(state.set_node_roadblocked(FINAL_ID, true), "FAILURE: final roadblock setup failed")
	_check(not game_state.advance_story_from_exploration(CONTEXT_ID, FINAL_ID)["success"], "FAILURE: blocked final node advanced")
	state.set_node_roadblocked(FINAL_ID, false)
	var source_scene: Node = current_scene
	current_scene = null
	_check(not game_state.advance_story_from_exploration(CONTEXT_ID, FINAL_ID)["success"], "FAILURE: missing current scene advanced")
	var unrelated_scene := Control.new()
	root.add_child(unrelated_scene)
	current_scene = unrelated_scene
	_check(not game_state.advance_story_from_exploration(CONTEXT_ID, FINAL_ID)["success"], "FAILURE: unrelated scene advanced Exploration")
	current_scene = source_scene
	unrelated_scene.queue_free()
	_check(_session_snapshot() == before and not state.is_context_closed(CONTEXT_ID), "FAILURE: rejected routing closed/corrupted context")
	_check(map.refresh_map() and map.primary_action_button.text == "Advance Story", "FAILURE: map did not recover after rejection")
	_check(game_state.advance_story_from_exploration(CONTEXT_ID, FINAL_ID)["success"], "FAILURE: valid retry after rejection failed")
	await process_frame
	_check(current_scene != null and current_scene.name == "M7_7ProgressionResult", "FAILURE: valid retry did not reach result")


func _test_real_control_input() -> void:
	var map: Variant = await _fresh_map()
	if map == null:
		return
	_travel(map, FINAL_ID)
	await process_frame
	await _mouse_click(map.primary_action_button)
	_check(map.warning_dialog_open, "INPUT: mouse Advance Story did not open warning")
	_check(map.warning_go_back_button.has_focus(), "INPUT: warning did not focus Go Back")
	await _mouse_click(map.get_marker_button("old_trail"))
	_check(map.warning_dialog_open and state.current_node_id == FINAL_ID, "INPUT: underlying mouse travel escaped warning overlay")
	await _send_action("ui_accept")
	_check(not map.warning_dialog_open and state.has_active_context(), "INPUT: keyboard Go Back did not cancel safely")
	_check(map.primary_action_button.has_focus(), "INPUT: keyboard Go Back did not restore focus")
	await _mouse_click(map.primary_action_button)
	_check(map.warning_dialog_open, "INPUT: second mouse Advance Story did not open warning")
	await _mouse_click(map.warning_go_back_button)
	_check(not map.warning_dialog_open and state.has_active_context(), "INPUT: mouse Go Back did not cancel safely")
	await _mouse_click(map.primary_action_button)
	_check(map.warning_dialog_open, "INPUT: third Advance Story attempt failed")
	map.warning_continue_button.grab_focus()
	_check(map.warning_continue_button.has_focus(), "INPUT: Continue cannot receive keyboard focus")
	await _send_action("ui_accept")
	_check(current_scene != null and current_scene.name == "M7_7ProgressionResult", "INPUT: keyboard Continue did not advance")
	_check(state.is_context_closed(CONTEXT_ID), "INPUT: keyboard Continue did not close context")
	map = await _fresh_map()
	if map == null:
		return
	_travel(map, FINAL_ID)
	await process_frame
	await _mouse_click(map.primary_action_button)
	_check(map.warning_dialog_open, "INPUT: mouse Continue setup failed")
	await _mouse_click(map.warning_continue_button)
	_check(current_scene != null and current_scene.name == "M7_7ProgressionResult", "INPUT: mouse Continue did not reach result")
	_check(state.is_context_closed(CONTEXT_ID), "INPUT: mouse Continue did not close context")


func _test_responsive_layout() -> void:
	var map: Variant = await _fresh_map()
	if map == null:
		return
	for size: Vector2i in [Vector2i(1152, 648), Vector2i(1440, 810)]:
		root.size = size
		root.content_scale_size = size
		await process_frame
		_check(map.refresh_map(), "LAYOUT: map failed at %s" % size)
		var marker: Button = map.get_marker_button(FINAL_ID)
		_check(marker != null and map.rendered_map_rect.has_point(marker.get_global_rect().get_center()), "LAYOUT: final marker left rendered map at %s" % size)
		_check(not marker.get_global_rect().intersects(map.time_panel.get_global_rect()), "LAYOUT: final marker overlaps TimePanel at %s" % size)
		_check(not marker.get_global_rect().intersects(map.primary_action_panel.get_global_rect()), "LAYOUT: final marker overlaps action panel at %s" % size)
		_check(not map.warning_preference_panel.get_global_rect().intersects(map.primary_action_panel.get_global_rect()), "LAYOUT: warning toggle overlaps action panel at %s" % size)
		_check(not map.warning_preference_panel.get_global_rect().intersects(map.get_node("LegendPanel").get_global_rect()), "LAYOUT: warning toggle overlaps legend at %s" % size)
		_travel(map, FINAL_ID)
		map.primary_action_button.emit_signal("pressed")
		await process_frame
		_check(map.warning_overlay.visible, "LAYOUT: warning hidden at %s" % size)
		var panel: Control = map.get_node("WarningOverlay/WarningPanel")
		_check(Rect2(Vector2.ZERO, size).encloses(panel.get_global_rect()), "LAYOUT: warning panel clipped at %s: %s" % [size, panel.get_global_rect()])
		_check(panel.get_global_rect().encloses(map.warning_go_back_button.get_global_rect()) and panel.get_global_rect().encloses(map.warning_continue_button.get_global_rect()), "LAYOUT: warning buttons outside panel at %s" % size)
		map.warning_go_back_button.emit_signal("pressed")
		_travel(map, "old_trail")
	root.size = Vector2i(1152, 648)
	root.content_scale_size = Vector2i(1152, 648)


func _session_snapshot() -> Dictionary:
	return {
		"context": state.active_context_id,
		"current": state.current_node_id,
		"revealed": state.revealed_nodes.duplicate(true),
		"completed": state.completed_nodes.duplicate(true),
		"roadblocked": state.roadblocked_nodes.duplicate(true),
		"leftovers": state.leftover_rewards.duplicate(true),
		"uses": state.hub_action_uses.duplicate(true),
		"time": state.get_time_snapshot(),
		"money": game_state.get_money(),
		"herbs": game_state.inventory_state.get_quantity("healing_herb"),
		"hp": game_state.party_runtime_state.get_hp_snapshot(),
		"flag": game_state.get_flag("m7_7_test_flag"),
		"bond": game_state.get_bond("m7_7_test_bond"),
	}


func _find_node(context: Dictionary, node_id: String) -> Dictionary:
	for node_definition: Dictionary in context["nodes"]:
		if node_definition["id"] == node_id:
			return node_definition
	return {}


func _progression_context() -> Dictionary:
	var script: Script = load(PROGRESSION_SCRIPT)
	return script.call("build_context")


func _timed_context() -> Dictionary:
	var script: Script = load(TIMED_SCRIPT)
	return script.call("build_context")


func _fresh_map() -> Variant:
	await _free_current_scene()
	game_state.reset_state()
	return await _load_scene(ENTRY)


func _load_scene(path: String) -> Variant:
	await _free_current_scene()
	var packed: PackedScene = load(path)
	_check(packed != null, "SCENE: could not load %s" % path)
	if packed == null:
		return null
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	if scene.has_method("get_marker_button"):
		return scene
	return scene.find_child("ExplorationMap", true, false)


func _current_map() -> Variant:
	if current_scene == null:
		return null
	if current_scene.has_method("get_marker_button"):
		return current_scene
	return current_scene.find_child("ExplorationMap", true, false)


func _free_current_scene() -> void:
	if current_scene == null:
		return
	var old_scene: Node = current_scene
	current_scene = null
	old_scene.queue_free()
	await process_frame


func _travel(map: Variant, node_id: String) -> void:
	var marker: Button = map.get_marker_button(node_id)
	_check(marker != null, "TRAVEL: marker missing: %s" % node_id)
	if marker != null:
		marker.emit_signal("pressed")


func _send_action(action: StringName) -> void:
	var pressed := InputEventAction.new()
	pressed.action = action
	pressed.pressed = true
	Input.parse_input_event(pressed)
	await process_frame
	var released := InputEventAction.new()
	released.action = action
	released.pressed = false
	Input.parse_input_event(released)
	await process_frame


func _mouse_click(button: BaseButton) -> void:
	var center: Vector2 = button.get_global_rect().get_center()
	var pressed := InputEventMouseButton.new()
	pressed.button_index = MOUSE_BUTTON_LEFT
	pressed.pressed = true
	pressed.position = center
	pressed.global_position = center
	Input.parse_input_event(pressed)
	await process_frame
	var released := InputEventMouseButton.new()
	released.button_index = MOUSE_BUTTON_LEFT
	released.pressed = false
	released.position = center
	released.global_position = center
	Input.parse_input_event(released)
	await process_frame


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
