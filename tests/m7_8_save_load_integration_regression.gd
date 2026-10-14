extends SceneTree

const ENTRY := "res://scenes/exploration/m7_7_progression_prototype.tscn"
const RESULT := "res://scenes/exploration/m7_7_progression_result.tscn"
const MAP := "res://scenes/exploration/exploration_map.tscn"
const VN := "res://scenes/vn/vn_prototype.tscn"
const CONTEXT_SCRIPT := "res://scripts/exploration/progression_prototype.gd"
const SAVE_PATH := "user://lumencia_save.json"
const CONTEXT_ID := "m7_7_progression_prototype_forest"
const RECEIPT := "m6_training_hall_obey_direct_hit_applied"

var failures: Array[String] = []
var checks := 0
var game_state: Node


func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name",
		"Lumencia Academy M7.8 Regression %d" % Time.get_ticks_usec())
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1152, 648)
	root.content_scale_size = Vector2i(1152, 648)
	game_state = root.get_node("GameState")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://"))
	await _test_state_snapshots()
	await _test_map_save_load_and_cold_start()
	await _test_partial_roundtrip_and_rejection()
	await _test_day_two_resume()
	await _test_result_and_legacy_routing()
	await _test_riverside_load_lifecycle()
	await _free_current_scene()
	game_state.reset_state()
	if failures.is_empty():
		print("M7.8 save/load integration regression suite passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	push_error("M7.8 save/load integration suite failed: %d failure(s), %d checks." % [failures.size(), checks])
	quit(1)


func _test_state_snapshots() -> void:
	var context: Dictionary = load(CONTEXT_SCRIPT).call("build_context")
	var original := ExplorationState.new()
	_check(original.define_context(context) and original.activate_context(CONTEXT_ID), "SNAPSHOT: trusted context did not activate")
	_check(original.move_to_node("riverside_camp"), "SNAPSHOT: could not travel to Riverside Camp")
	_check(original.complete_primary_content("riverside_camp"), "SNAPSHOT: could not complete Riverside event")
	_check(original.is_node_revealed("deep_grove"), "SNAPSHOT: Deep Grove did not reveal")
	_check(original.consume_hub_action_use("riverside_camp", "prototype_camp_rest"), "SNAPSHOT: Camp Rest use failed")
	_check(original.spend_timed_action()["success"], "SNAPSHOT: time action failed")
	_check(original.move_to_node("stone_crossing") and original.move_to_node("ruins_approach"), "SNAPSHOT: Ruins travel failed")
	_check(original.complete_primary_content("ruins_approach"), "SNAPSHOT: resource completion failed")
	_check(original.set_leftover_reward("ruins_approach", "healing_herb", 1), "SNAPSHOT: leftover setup failed")
	var snapshot: Dictionary = original.get_save_snapshot()
	var parsed: Variant = JSON.parse_string(JSON.stringify(snapshot))
	var restored := ExplorationState.new()
	_check(restored.define_context(context) and restored.apply_save_snapshot(parsed), "SNAPSHOT: JSON Exploration roundtrip rejected")
	_check(restored.get_save_snapshot() == snapshot, "SNAPSHOT: Exploration values changed on roundtrip")
	_check(restored.is_node_completed("riverside_camp") and restored.is_node_revealed("deep_grove"), "SNAPSHOT: reveal/completion changed")
	_check(restored.is_node_roadblocked("riverside_camp") and restored.get_hub_action_uses_remaining("riverside_camp", "prototype_camp_rest") == 1, "SNAPSHOT: roadblock or Rest use changed")
	_check(restored.get_leftover_reward("ruins_approach")["quantity"] == 1, "SNAPSHOT: leftover changed")
	var bad: Dictionary = parsed.duplicate(true)
	bad["revealed_nodes"].append("fabricated_node")
	var before: Dictionary = restored.get_save_snapshot()
	_check(not restored.apply_save_snapshot(bad) and restored.get_save_snapshot() == before, "SNAPSHOT: bad node partially changed state")
	bad = parsed.duplicate(true)
	bad["time"]["actions_spent"] = 2
	_check(not restored.apply_save_snapshot(bad) and restored.get_save_snapshot() == before, "SNAPSHOT: pending daypart accepted")
	bad = parsed.duplicate(true)
	bad["leftover_rewards"][0]["item_id"] = "fabricated_item"
	_check(not restored.apply_save_snapshot(bad), "SNAPSHOT: fabricated resource reward accepted")
	bad = parsed.duplicate(true)
	bad["hub_action_uses"][0]["remaining"] = 3
	_check(not restored.apply_save_snapshot(bad), "SNAPSHOT: excessive Camp Rest use accepted")
	for mode: String in [ExplorationState.NO_TIME, ExplorationState.TIME_SLOTS, ExplorationState.MULTI_DAY]:
		var mode_context: Dictionary = context.duplicate(true)
		mode_context["id"] = "test_%s" % mode
		mode_context["time"] = {"mode": mode}
		if mode == ExplorationState.NO_TIME:
			for node_definition: Dictionary in mode_context["nodes"]:
				if node_definition["id"] == "riverside_camp":
					node_definition["hub_actions"] = node_definition["hub_actions"].filter(
						func(action: Dictionary) -> bool: return action["type"] != "wait")
		var state := ExplorationState.new()
		_check(state.define_context(mode_context) and state.activate_context(mode_context["id"]), "TIME: %s context failed" % mode)
		for action: int in range(6):
			var spent: Dictionary = state.spend_timed_action()
			_check(spent["success"], "TIME: %s action %d failed" % [mode, action])
			if spent["day_boundary"]:
				_check(state.finish_day_transition(), "TIME: %s day transition failed" % mode)
		var copy := ExplorationState.new()
		_check(copy.define_context(mode_context) and copy.apply_save_snapshot(JSON.parse_string(JSON.stringify(state.get_save_snapshot()))), "TIME: %s stable clock did not restore" % mode)
		_check(copy.get_save_snapshot() == state.get_save_snapshot(), "TIME: %s clock changed" % mode)
	var inventory := InventoryState.new()
	_check(inventory.gain_item("healing_herb", 10)["accepted"] == 10, "INVENTORY: setup failed")
	_check(inventory.apply_save_snapshot(JSON.parse_string(JSON.stringify([{"item_id": "healing_herb", "quantity": 0}]))), "INVENTORY: empty restore failed")
	_check(inventory.get_quantity("healing_herb") == 0, "INVENTORY: empty restore kept Herbs")
	_check(not inventory.apply_save_snapshot([{"item_id": "healing_herb", "quantity": 2}, {"item_id": "healing_herb", "quantity": 3}]), "INVENTORY: duplicate item accepted")
	_check(inventory.get_quantity("healing_herb") == 0, "INVENTORY: failed restore mutated quantity")
	_check(not inventory.apply_save_snapshot([{"item_id": "healing_herb", "quantity": 11}]), "INVENTORY: over-cap quantity accepted")
	var party := PartyRuntimeState.new()
	var hp: Array = party.get_save_snapshot()
	hp[0]["current_hp"] = 0
	_check(party.apply_save_snapshot(JSON.parse_string(JSON.stringify(hp))), "PARTY: zero HP restore failed")
	_check(party.get_member("party_1")["current_hp"] == 0, "PARTY: zero HP was revived")
	hp.append(hp[0].duplicate(true))
	_check(not party.apply_save_snapshot(hp), "PARTY: duplicate member accepted")
	_check(party.get_member("party_1")["current_hp"] == 0, "PARTY: bad restore mutated HP")


func _test_map_save_load_and_cold_start() -> void:
	var entry: Node = await _load_scene(ENTRY)
	if entry == null:
		return
	var map: Variant = entry.find_child("ExplorationMap", true, false)
	_check(entry.context_ready and map != null, "MAP: fresh context did not bootstrap")
	if map == null:
		return
	_check(game_state.get_money() == 12 and game_state.inventory_state.get_quantity("healing_herb") == 9, "MAP: fresh prototype seed is wrong")
	_check(map.map_save_button.focus_mode != Control.FOCUS_NONE and map.map_load_button.focus_mode != Control.FOCUS_NONE, "MAP: Save/Load not focusable")
	map.map_save_button.grab_focus()
	_check(map.map_save_button.has_focus(), "MAP: Save did not receive keyboard focus")
	await _send_action("ui_accept")
	_check(FileAccess.file_exists(SAVE_PATH), "MAP: keyboard Save did not write a file")
	var saved: Dictionary = game_state.read_save_data()
	_check(saved.get("schema_version") == 2 and saved.get("kind") == "exploration", "MAP: versioned envelope is wrong")
	_check(saved.get("exploration", {}).get("current_node_id") == "old_trail", "MAP: wrong starting node saved")
	_check(saved.keys().size() == 9, "MAP: exploration envelope cardinality changed")
	var stable_bytes: String = _read_save_text()
	game_state.prepare_pending_vn_sequence("m7_3_riverside_event")
	_check(not game_state.save_exploration_game() and _read_save_text() == stable_bytes, "SAVE: pending handoff overwrote prior save")
	game_state.clear_pending_vn_sequence()
	map.get_marker_button("riverside_camp").pressed.emit()
	_check(game_state.exploration_state.current_node_id == "riverside_camp", "MAP: travel setup failed")
	_check(game_state.load_saved_game(), "MAP: versioned load failed: %s" % game_state.persistence_error)
	await process_frame
	_check(current_scene != null and current_scene.name == "M7_7ProgressionPrototype", "MAP: route did not restore map scene")
	_check(game_state.exploration_state.current_node_id == "old_trail" and game_state.get_money() == 12, "MAP: saved state did not replace live state")
	_check(game_state.is_missable_content_warning_enabled(), "MAP: saved warning ON did not restore")
	_check(game_state.inventory_state.get_quantity("healing_herb") == 9 and game_state.party_runtime_state.get_member("party_1")["current_hp"] == 20, "MAP: seed values did not restore exactly")
	var loaded_map: Variant = current_scene.find_child("ExplorationMap", true, false)
	_check(loaded_map.save_load_status.text == "Loaded successfully.", "MAP: load feedback missing")
	for size: Vector2i in [Vector2i(1152, 648), Vector2i(1440, 810)]:
		root.size = size
		root.content_scale_size = size
		await process_frame
		var viewport_rect := Rect2(Vector2.ZERO, Vector2(size))
		_check(viewport_rect.encloses(loaded_map.save_load_panel.get_global_rect()), "LAYOUT: save panel clipped at %s" % size)
		_check(loaded_map.save_load_panel.get_global_rect().encloses(loaded_map.map_save_button.get_global_rect()) and loaded_map.save_load_panel.get_global_rect().encloses(loaded_map.map_load_button.get_global_rect()), "LAYOUT: buttons escaped panel at %s" % size)
	root.size = Vector2i(1152, 648)
	root.content_scale_size = Vector2i(1152, 648)
	game_state.reset_state()
	var vn: Node = await _load_scene(VN)
	_check(vn != null, "COLD: initial VN did not open")
	if vn == null:
		return
	_check(vn.load_button.tooltip_text.contains("Ctrl+L"), "COLD: keyboard Load shortcut is not discoverable")
	await _send_load_shortcut()
	await process_frame
	_check(current_scene != null and current_scene.name == "M7_7ProgressionPrototype", "COLD: VN Load did not route to map")
	_check(game_state.exploration_state.current_node_id == "old_trail" and game_state.get_money() == 12, "COLD: bootstrap erased restored values")
	var original_scene: Node = current_scene
	var original_state: ExplorationState = game_state.exploration_state
	var corrupt: String = "{not-json"
	_write_test_save(corrupt)
	_check(not game_state.load_saved_game(), "INVALID: malformed file loaded")
	_check(current_scene == original_scene and game_state.exploration_state == original_state, "INVALID: malformed load mutated scene or state owner")
	_write_test_save(stable_bytes)
	var bad: Dictionary = game_state.read_save_data()
	bad["schema_version"] = 99
	_write_test_save(JSON.stringify(bad))
	_check(not game_state.load_saved_game() and current_scene == original_scene, "INVALID: future schema replaced live scene")
	_write_test_save(stable_bytes)
	bad = game_state.read_save_data()
	bad["exploration"]["current_node_id"] = "unknown_node"
	_write_test_save(JSON.stringify(bad))
	_check(not game_state.load_saved_game() and game_state.exploration_state == original_state, "INVALID: unknown node replaced live state")
	_write_test_save(stable_bytes)
	bad = game_state.read_save_data()
	bad["money"] = -1
	_write_test_save(JSON.stringify(bad))
	_check(not game_state.load_saved_game() and game_state.get_money() == 12, "INVALID: negative money changed live balance")
	_write_test_save(stable_bytes)


func _test_partial_roundtrip_and_rejection() -> void:
	var state: ExplorationState = game_state.exploration_state
	_check(state.move_to_node("riverside_camp") and state.complete_primary_content("riverside_camp"), "PARTIAL: Riverside completion failed")
	_check(state.is_node_revealed("deep_grove") and state.is_node_roadblocked("riverside_camp"), "PARTIAL: reveal/roadblock setup wrong")
	var rest: Dictionary = game_state.use_current_camp_rest("riverside_camp", "prototype_camp_rest")
	_check(rest["success"] and rest["uses_remaining"] == 1, "PARTIAL: Camp Rest did not consume one charge")
	var purchase: Dictionary = game_state.buy_from_current_shop("riverside_camp", "prototype_supply_shop", "healing_herb")
	_check(purchase["success"] and game_state.get_money() == 8 and game_state.inventory_state.get_quantity("healing_herb") == 10, "PARTIAL: Shop purchase setup failed")
	_check(game_state.party_runtime_state.set_current_hp("party_1", 7) and game_state.party_runtime_state.set_current_hp("party_2", 0), "PARTIAL: HP setup failed")
	game_state.set_missable_content_warning_enabled(false)
	game_state.adjust_bond("hiruko", 2)
	_check(state.move_to_node("stone_crossing") and state.move_to_node("ruins_approach"), "PARTIAL: Ruins travel failed")
	_check(state.complete_primary_content("ruins_approach") and state.set_leftover_reward("ruins_approach", "healing_herb", 2), "PARTIAL: completed resource/leftover setup failed")
	_check(state.spend_timed_action()["success"] and state.get_time_snapshot()["total_actions"] == 2, "PARTIAL: timed completion setup failed")
	var standalone: Node = await _load_scene(MAP)
	var map: Variant = standalone
	_check(map != null and map.refresh_map(), "PARTIAL: standalone return map failed")
	if map == null:
		return
	map.map_save_button.pressed.emit()
	_check(map.save_load_status.text == "Saved successfully.", "PARTIAL: standalone map Save failed: %s" % game_state.persistence_error)
	var saved: Dictionary = game_state.read_save_data()
	var saved_bytes: String = _read_save_text()
	_check(saved["exploration"]["current_node_id"] == "ruins_approach" and saved["exploration"]["leftover_rewards"].size() == 1, "PARTIAL: location/leftover not saved")
	_check(saved["exploration"]["hub_action_uses"][0]["remaining"] == 1 and saved["exploration"]["time"]["total_actions"] == 2, "PARTIAL: Rest/time not saved")
	_check(saved["inventory"][0]["quantity"] == 10 and saved["money"] == 8 and saved["party_hp"][1]["current_hp"] == 0, "PARTIAL: inventory/money/zero HP not saved")
	_check(saved["bonds"]["hiruko"] == 2 and not saved["preferences"]["missable_content_warning_enabled"], "PARTIAL: Bond/preference not saved")
	_check(game_state.inventory_state.consume_item("healing_herb", 1) and game_state.spend_money(4), "PARTIAL: mutation setup failed")
	_check(game_state.party_runtime_state.set_current_hp("party_1", 30) and state.reduce_leftover_reward("ruins_approach", 1), "PARTIAL: HP/leftover mutation failed")
	map.map_load_button.pressed.emit()
	await process_frame
	state = game_state.exploration_state
	_check(current_scene != null and current_scene.name == "M7_7ProgressionPrototype", "PARTIAL: UI Load did not route to entry")
	_check(state.current_node_id == "ruins_approach" and state.is_node_completed("riverside_camp") and state.is_node_completed("ruins_approach") and state.is_node_revealed("deep_grove"), "PARTIAL: node progression not restored")
	_check(state.is_node_roadblocked("riverside_camp") and state.get_leftover_reward("ruins_approach")["quantity"] == 2, "PARTIAL: roadblock/leftover not restored")
	_check(state.get_hub_action_uses_remaining("riverside_camp", "prototype_camp_rest") == 1 and state.get_time_snapshot()["total_actions"] == 2, "PARTIAL: Rest/time not restored")
	_check(game_state.get_money() == 8 and game_state.inventory_state.get_quantity("healing_herb") == 10, "PARTIAL: money/inventory not restored")
	_check(game_state.party_runtime_state.get_member("party_1")["current_hp"] == 7 and game_state.party_runtime_state.get_member("party_2")["current_hp"] == 0, "PARTIAL: HP did not restore exactly")
	_check(not game_state.is_missable_content_warning_enabled() and game_state.get_bond("hiruko") == 2, "PARTIAL: preference/Bond not restored")
	var restored_map: Variant = current_scene.find_child("ExplorationMap", true, false)
	_check(restored_map.interact_with_current_node() and state.get_leftover_reward("ruins_approach")["quantity"] == 2, "LEFTOVER: full inventory collected reward")
	_check(game_state.inventory_state.consume_item("healing_herb", 1), "LEFTOVER: Herb consumption failed")
	_check(restored_map.interact_with_current_node() and state.get_leftover_reward("ruins_approach")["quantity"] == 1 and game_state.inventory_state.get_quantity("healing_herb") == 10, "LEFTOVER: first pickup was not partial")
	_check(game_state.inventory_state.consume_item("healing_herb", 1), "LEFTOVER: second Herb consumption failed")
	_check(restored_map.interact_with_current_node() and not state.has_leftover_reward("ruins_approach") and game_state.inventory_state.get_quantity("healing_herb") == 10, "LEFTOVER: second pickup did not clear reward")
	_check(not restored_map.interact_with_current_node() and game_state.inventory_state.get_quantity("healing_herb") == 10, "LEFTOVER: completed resource farmed again")
	_check(game_state.load_saved_game(), "LEFTOVER: saved partial state could not reload")
	await process_frame
	state = game_state.exploration_state
	var live_scene: Node = current_scene
	var bad: Dictionary = saved.duplicate(true)
	var invalid_cases: Array[Dictionary] = []
	bad["inventory"].append({"item_id": "healing_herb", "quantity": 1})
	invalid_cases.append(bad)
	bad = saved.duplicate(true)
	bad["inventory"][0]["quantity"] = 11
	invalid_cases.append(bad)
	bad = saved.duplicate(true)
	bad["inventory"][0]["item_id"] = "unknown_item"
	invalid_cases.append(bad)
	bad = saved.duplicate(true)
	bad["party_hp"].remove_at(0)
	invalid_cases.append(bad)
	bad = saved.duplicate(true)
	bad["party_hp"][0]["current_hp"] = 999
	invalid_cases.append(bad)
	bad = saved.duplicate(true)
	bad["party_hp"][0]["max_hp"] = 999
	invalid_cases.append(bad)
	bad = saved.duplicate(true)
	bad["exploration"]["time"]["mode"] = "NO_TIME"
	invalid_cases.append(bad)
	bad = saved.duplicate(true)
	bad["exploration"]["hub_action_uses"][0]["remaining"] = -1
	invalid_cases.append(bad)
	bad = saved.duplicate(true)
	bad["exploration"]["closed_context_ids"] = [CONTEXT_ID]
	invalid_cases.append(bad)
	bad = saved.duplicate(true)
	bad["exploration"]["closed_context_ids"] = [CONTEXT_ID, CONTEXT_ID]
	invalid_cases.append(bad)
	bad = saved.duplicate(true)
	bad["exploration"]["leftover_rewards"][0]["item_id"] = "unknown_item"
	invalid_cases.append(bad)
	bad = saved.duplicate(true)
	bad["exploration"]["active_context_id"] = "unknown_context"
	invalid_cases.append(bad)
	bad = saved.duplicate(true)
	bad["money"] = 9007199254740992
	invalid_cases.append(bad)
	for index: int in range(invalid_cases.size()):
		_check(not game_state.load_versioned_save_data(invalid_cases[index]), "INVALID %d: malformed candidate loaded" % index)
		_check(current_scene == live_scene and game_state.exploration_state == state and game_state.get_money() == 8, "INVALID %d: failed candidate changed live session" % index)
	_check(_read_save_text() == saved_bytes, "INVALID: rejected candidate overwrote save file")
	var route_candidate: Dictionary = game_state._prepare_versioned_candidate(saved)
	var wrong_context: Dictionary = load("res://scripts/exploration/time_rest_prototype.gd").call("build_context")
	var wrong_state := ExplorationState.new()
	_check(wrong_state.define_context(wrong_context) and wrong_state.activate_context(wrong_context["id"]), "ROUTE: rejected-context fixture failed")
	route_candidate["exploration_state"] = wrong_state
	var original_scene_name: String = live_scene.name
	_check(not game_state._route_loaded_candidate(route_candidate, GameState.PROGRESSION_ENTRY_SCENE_PATH), "ROUTE: incompatible destination initialized")
	_check(current_scene == live_scene and live_scene.name == original_scene_name and game_state.exploration_state == state and game_state.get_money() == 8, "ROUTE: failed initialization did not roll back scene and session")
	await process_frame
	var backup_path: String = ProjectSettings.globalize_path(SAVE_PATH) + ".bak"
	var backup: FileAccess = FileAccess.open(backup_path, FileAccess.WRITE)
	_check(backup != null, "WRITE: could not create isolated backup fixture")
	if backup != null:
		backup.store_string("prior backup")
		backup.close()
		_check(not game_state.save_exploration_game() and _read_save_text() == saved_bytes, "WRITE: blocked replacement changed prior save")
		DirAccess.remove_absolute(backup_path)
	_check(game_state.load_saved_game(), "PARTIAL: final reload failed")
	await process_frame


func _test_day_two_resume() -> void:
	var partial_bytes: String = _read_save_text()
	var state: ExplorationState = game_state.exploration_state
	_check(state.move_to_node("stone_crossing") and state.move_to_node("riverside_camp"), "DAY 2: could not return to Camp")
	for action: int in range(4):
		_check(game_state.wait_at_current_hub("riverside_camp", "prototype_wait")["success"], "DAY 2: Wait action %d failed" % action)
	var time_before: Dictionary = state.get_time_snapshot()
	var hp_before: Dictionary = game_state.party_runtime_state.get_hp_snapshot()
	_check(time_before["day"] == 2 and time_before["daypart"] == "Morning" and time_before["total_actions"] == 6, "DAY 2: stable morning setup failed")
	_check(hp_before["party_1"]["current_hp"] == 16 and hp_before["party_2"]["current_hp"] == 8, "DAY 2: one Night Rest recovery setup failed")
	_check(game_state.save_exploration_game(), "DAY 2: stable checkpoint Save failed: %s" % game_state.persistence_error)
	game_state.reset_state()
	var vn: Node = await _load_scene(VN)
	_check(vn != null, "DAY 2: cold VN entry failed")
	if vn == null:
		return
	await _send_load_shortcut()
	await process_frame
	state = game_state.exploration_state
	_check(current_scene != null and current_scene.name == "M7_7ProgressionPrototype", "DAY 2: cold route missed map")
	_check(state.get_time_snapshot()["day"] == 2 and state.get_time_snapshot()["total_actions"] == 6, "DAY 2: stable clock changed on Load")
	_check(game_state.party_runtime_state.get_hp_snapshot() == hp_before, "DAY 2: loading reapplied Night Rest")
	_check(game_state.wait_at_current_hub("riverside_camp", "prototype_wait")["success"], "DAY 2: next action failed")
	_check(state.get_time_snapshot()["day"] == 2 and state.get_time_snapshot()["total_actions"] == 7 and state.get_time_snapshot()["actions_spent"] == 1, "DAY 2: next action did not advance normally")
	_check(game_state.party_runtime_state.get_hp_snapshot() == hp_before, "DAY 2: next action applied extra recovery")
	_write_test_save(partial_bytes)
	_check(game_state.load_saved_game(), "DAY 2: partial fixture could not restore")
	await process_frame


func _test_result_and_legacy_routing() -> void:
	var map: Variant = current_scene.find_child("ExplorationMap", true, false)
	_check(map != null, "RESULT: map missing")
	if map == null:
		return
	for node_id: String in ["stone_crossing", "riverside_camp", "old_trail", "forest_boundary"]:
		map.get_marker_button(node_id).pressed.emit()
	_check(game_state.exploration_state.current_node_id == "forest_boundary", "RESULT: final node travel failed")
	game_state.set_missable_content_warning_enabled(true)
	_check(map.request_story_advance() and map.warning_dialog_open, "RESULT: warning setup did not open")
	_check(not game_state.save_exploration_game(), "RESULT: warning overlay allowed unstable Save")
	map.warning_go_back_button.pressed.emit()
	_check(not map.warning_dialog_open and game_state.exploration_state.has_active_context(), "RESULT: Go Back did not preserve map")
	game_state.set_missable_content_warning_enabled(false)
	game_state.set_flag(RECEIPT, true)
	_check(game_state.advance_story_from_exploration(CONTEXT_ID, "forest_boundary")["success"], "RESULT: progression failed")
	await process_frame
	_check(current_scene != null and current_scene.name == "M7_7ProgressionResult", "RESULT: result scene missing")
	_check(game_state.exploration_state.is_context_closed(CONTEXT_ID), "RESULT: context did not close")
	var result_scene: Node = current_scene
	result_scene.get_node("ResultPanel/Margin/Content/SaveLoadButtons/ResultSaveButton").pressed.emit()
	var result_data: Dictionary = game_state.read_save_data()
	_check(result_data.get("kind") == "result" and result_data.get("destination") == ExplorationState.PROTOTYPE_FINAL_DESTINATION, "RESULT: save kind/destination wrong")
	_check(result_data.get("preferences", {}).get("missable_content_warning_enabled") == false, "RESULT: warning preference not saved")
	_check(result_data.get("flags", {}).get(RECEIPT) == true, "RESULT: M6 receipt flag not saved")
	var invalid_result: Dictionary = result_data.duplicate(true)
	invalid_result["destination"] = "res://untrusted_scene.tscn"
	var result_owner: ExplorationState = game_state.exploration_state
	_check(not game_state.load_versioned_save_data(invalid_result) and current_scene == result_scene and game_state.exploration_state == result_owner, "RESULT: arbitrary destination changed live state")
	for size: Vector2i in [Vector2i(1152, 648), Vector2i(1440, 810)]:
		root.size = size
		root.content_scale_size = size
		await process_frame
		var save_button: Button = result_scene.get_node("ResultPanel/Margin/Content/SaveLoadButtons/ResultSaveButton")
		var load_button: Button = result_scene.get_node("ResultPanel/Margin/Content/SaveLoadButtons/ResultLoadButton")
		_check(save_button.focus_mode != Control.FOCUS_NONE and load_button.focus_mode != Control.FOCUS_NONE, "RESULT: buttons not keyboard operable")
		_check(Rect2(Vector2.ZERO, Vector2(size)).encloses(save_button.get_global_rect()) and Rect2(Vector2.ZERO, Vector2(size)).encloses(load_button.get_global_rect()), "RESULT: Save/Load clipped at %s" % size)
	root.size = Vector2i(1152, 648)
	root.content_scale_size = Vector2i(1152, 648)
	game_state.reset_state()
	var vn: Node = await _load_scene(VN)
	_check(vn != null, "RESULT: cold VN missing")
	if vn == null:
		return
	vn.load_button.pressed.emit()
	await process_frame
	_check(current_scene != null and current_scene.name == "M7_7ProgressionResult", "RESULT: cold Load did not route to result")
	_check(game_state.exploration_state.is_context_closed(CONTEXT_ID) and not game_state.exploration_state.has_active_context(), "RESULT: closure not restored")
	_check(not game_state.is_missable_content_warning_enabled() and game_state.get_flag(RECEIPT), "RESULT: preferences/receipt not restored")
	var blocked: Node = await _load_scene(ENTRY)
	_check(blocked != null and not blocked.context_ready and game_state.exploration_state.is_context_closed(CONTEXT_ID), "RESULT: closed context reopened normally")
	await _load_scene(VN)
	game_state.set_flag(RECEIPT, true)
	game_state.set_flag("legacy_story_flag", true)
	game_state.adjust_bond("hiruko", -game_state.get_bond("hiruko") - 1)
	_check(game_state.save_game("res://data/dialogue/vn_prototype_m1.json", "intro_03"), "LEGACY: four-field save failed")
	var legacy_data: Dictionary = game_state.read_save_data()
	_check(legacy_data.keys().size() == 4 and not legacy_data.has("schema_version"), "LEGACY: format gained M7 fields")
	game_state.gain_money(9)
	game_state.inventory_state.gain_item("healing_herb", 2)
	game_state.exploration_state.define_context(load(CONTEXT_SCRIPT).call("build_context"))
	game_state.exploration_state.activate_context(CONTEXT_ID)
	_check(game_state.load_saved_game(), "LEGACY: central routing failed: %s" % game_state.persistence_error)
	await process_frame
	_check(current_scene != null and current_scene.name == "VNPrototype", "LEGACY: did not route to VN")
	_check(current_scene.current_node_id == "intro_03", "LEGACY: normal line not restored")
	_check(game_state.get_flag(RECEIPT) and game_state.get_bond("hiruko") == -1, "LEGACY: flags/Bonds lost")
	_check(game_state.get_money() == 0 and game_state.inventory_state.get_quantity("healing_herb") == 0 and not game_state.exploration_state.has_active_context(), "LEGACY: stale M7 runtime leaked")
	_check(not game_state.exploration_state.is_context_closed(CONTEXT_ID) and game_state.is_missable_content_warning_enabled(), "LEGACY: stale closure/preference leaked")


func _test_riverside_load_lifecycle() -> void:
	game_state.reset_state()
	var entry: Node = await _load_scene(ENTRY)
	var map: Variant = entry.find_child("ExplorationMap", true, false)
	game_state.adjust_bond("hiruko", 3)
	_check(game_state.save_exploration_game(), "RIVERSIDE: stable checkpoint save failed")
	var saved: Dictionary = game_state.read_save_data()
	var checkpoint: String = _read_save_text()
	_check(saved.get("schema_version") == 2 and saved.get("kind") == "exploration", "RIVERSIDE: wrong checkpoint schema/kind")
	map.get_marker_button("riverside_camp").pressed.emit()
	_check(map.interact_with_current_node(), "RIVERSIDE: VN launch failed")
	await process_frame
	var vn: Node = current_scene
	_check(vn.name == "VNPrototype" and vn.current_node_id == "riverside_01", "RIVERSIDE: VN did not start on expected line")
	_check(game_state.exploration_state.active_context_id == CONTEXT_ID and game_state.get_pending_exploration_content().get("content_id") == "m7_3_riverside_event" and game_state.get_pending_vn_sequence().is_empty(), "RIVERSIDE: active handoff was not prepared/consumed correctly")
	_check(vn.save_button.disabled, "RIVERSIDE: mid-event legacy Save button remains enabled")
	vn._save_game()
	_check(_read_save_text() == checkpoint and vn.save_status_label.text.contains("Exploration map"), "RIVERSIDE: direct VN Save overwrote map checkpoint")
	await _send_load_shortcut()
	_check(current_scene.name == "M7_7ProgressionPrototype", "RIVERSIDE: Ctrl+L did not route to map")
	_check(game_state.exploration_state.current_node_id == "old_trail" and not game_state.exploration_state.is_node_completed("riverside_camp"), "RIVERSIDE: map state changed during VN load")
	_check(not is_instance_valid(vn) and game_state.get_pending_exploration_content().is_empty() and game_state.get_pending_vn_sequence().is_empty(), "RIVERSIDE: old VN or handoffs survived load")
	_check(game_state.exploration_state.get_time_snapshot()["total_actions"] == 0 and game_state.get_bond("hiruko") == 3 and not game_state.exploration_state.is_node_revealed("deep_grove"), "RIVERSIDE: abandoned VN charged time, changed Bond, or revealed content")
	var loaded_owner: ExplorationState = game_state.exploration_state
	await process_frame
	_check(game_state.exploration_state == loaded_owner, "RIVERSIDE: Ctrl+L release activated Load twice")
	_write_test_save(checkpoint)
	var loaded_map: Variant = current_scene.find_child("ExplorationMap", true, false)
	loaded_map.get_marker_button("riverside_camp").pressed.emit()
	_check(loaded_map.interact_with_current_node(), "RIVERSIDE: second VN launch failed")
	await process_frame
	vn = current_scene
	vn._advance_dialogue()
	vn._advance_dialogue()
	_check(vn.current_node_id == "riverside_03", "RIVERSIDE: late-callback setup failed")
	vn._load_game()
	_check(current_scene.name == "M7_7ProgressionPrototype", "RIVERSIDE: direct Load did not route")
	_check(not vn.dialogue_ready, "RIVERSIDE: abandoned VN remains dialogue-ready before deferred free")
	loaded_owner = game_state.exploration_state
	var late_input := InputEventAction.new()
	late_input.action = "ui_accept"
	late_input.pressed = true
	vn._unhandled_input(late_input)
	_check(vn.last_dialogue_error.is_empty(), "RIVERSIDE: old VN processed late input after map load")
	vn._load_game()
	_check(game_state.exploration_state == loaded_owner and not game_state.exploration_state.is_node_completed("riverside_camp"), "RIVERSIDE: abandoned VN reloaded or completed content")
	await process_frame
	loaded_map = current_scene.find_child("ExplorationMap", true, false)
	loaded_map.get_marker_button("riverside_camp").pressed.emit()
	_check(loaded_map.interact_with_current_node(), "RIVERSIDE: third VN launch failed")
	await process_frame
	vn = current_scene
	var legacy: Dictionary = {"sequence": "res://data/dialogue/m7_3_riverside_event.json", "node": "riverside_01", "flags": {}, "bonds": {}}
	_write_test_save(JSON.stringify(legacy))
	var pending_before: Dictionary = game_state.get_pending_exploration_content()
	var owner_before: ExplorationState = game_state.exploration_state
	var time_before: Dictionary = owner_before.get_time_snapshot()
	await _send_load_shortcut()
	_check(current_scene == vn and game_state.exploration_state == owner_before and game_state.get_pending_exploration_content() == pending_before, "RIVERSIDE: unsupported legacy load destroyed active return handoff")
	_check(vn.save_status_label.text.contains("Exploration return handoff") and vn.current_node_id == "riverside_01", "RIVERSIDE: unsupported legacy checkpoint did not fail clearly")
	_check(owner_before.get_time_snapshot() == time_before and game_state.get_bond("hiruko") == 3, "RIVERSIDE: rejected legacy load mutated time or Bonds")
	_check(not game_state.load_saved_game() and game_state.persistence_error.contains("Exploration return handoff") and current_scene == vn and game_state.get_pending_exploration_content() == pending_before, "RIVERSIDE: central legacy loader accepted unsupported checkpoint")
	_write_test_save("{corrupt")
	await _send_load_shortcut()
	_check(current_scene == vn and game_state.exploration_state == owner_before and game_state.get_pending_exploration_content() == pending_before and vn.current_node_id == "riverside_01", "RIVERSIDE: corrupt save changed live VN or handoff")
	_check(vn.save_status_label.text.begins_with("Load failed:"), "RIVERSIDE: corrupt save did not show failure")
	_write_test_save(checkpoint)
	var candidate: Dictionary = game_state._prepare_versioned_candidate(saved)
	_check(not candidate.is_empty(), "RIVERSIDE: valid route candidate was rejected")
	_check(not game_state._route_loaded_candidate(candidate, "res://scenes/exploration/missing_map.tscn") and current_scene == vn and game_state.exploration_state == owner_before and game_state.get_pending_exploration_content() == pending_before, "RIVERSIDE: failed route altered active session")
	vn._advance_dialogue()
	vn._advance_dialogue()
	vn._advance_dialogue()
	await process_frame
	_check(current_scene.name == "ExplorationMap", "RIVERSIDE: failed loads broke valid VN return")
	_check(game_state.exploration_state.is_node_completed("riverside_camp") and game_state.exploration_state.get_time_snapshot()["total_actions"] == 1, "RIVERSIDE: valid return after failed load did not complete exactly once")
	game_state.reset_state()
	entry = await _load_scene(ENTRY)
	map = entry.find_child("ExplorationMap", true, false)
	map.get_marker_button("riverside_camp").pressed.emit()
	_check(map.interact_with_current_node(), "RIVERSIDE: legacy standalone launch setup failed")
	await process_frame
	vn = current_scene
	var standalone_legacy: Dictionary = {"sequence": "res://data/dialogue/vn_prototype_m1.json", "node": "intro_03", "flags": {"legacy_test": true}, "bonds": {"hiruko": -2}}
	_write_test_save(JSON.stringify(standalone_legacy))
	await _send_load_shortcut()
	_check(current_scene == vn and vn.current_node_id == "intro_03" and vn.dialogue_ready, "RIVERSIDE: valid standalone legacy VN did not load")
	_check(game_state.get_pending_exploration_content().is_empty() and not game_state.exploration_state.has_active_context() and game_state.get_money() == 0 and game_state.inventory_state.get_quantity("healing_herb") == 0, "RIVERSIDE: standalone legacy load retained M7 world")
	_check(game_state.get_flag("legacy_test") and game_state.get_bond("hiruko") == -2 and not vn.save_button.disabled, "RIVERSIDE: standalone legacy VN flags/Bonds/Save changed")
	vn._save_game()
	_check(game_state.read_save_data().keys().size() == 4, "RIVERSIDE: standalone legacy Save schema changed")
	_write_test_save(JSON.stringify(legacy))
	_check(not game_state.load_saved_game() and current_scene == vn and vn.current_node_id == "intro_03", "RIVERSIDE: unsupported legacy save loaded from standalone VN")
	_write_test_save(checkpoint)
	game_state.reset_state()
	vn = await _load_scene(VN)
	await _send_load_shortcut()
	_check(current_scene.name == "M7_7ProgressionPrototype" and game_state.exploration_state.current_node_id == "old_trail" and game_state.get_bond("hiruko") == 3, "RIVERSIDE: cold-session versioned load did not restore checkpoint")


func _load_scene(path: String) -> Node:
	await _free_current_scene()
	var packed: PackedScene = load(path)
	_check(packed != null, "SCENE: missing %s" % path)
	if packed == null:
		return null
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	return scene


func _free_current_scene() -> void:
	if current_scene == null:
		return
	var old: Node = current_scene
	current_scene = null
	old.queue_free()
	await process_frame


func _read_save_text() -> String:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	return file.get_as_text() if file != null else ""


func _write_test_save(contents: String) -> void:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(contents)
		file.close()


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


func _send_load_shortcut() -> void:
	var pressed := InputEventKey.new()
	pressed.keycode = KEY_L
	pressed.ctrl_pressed = true
	pressed.pressed = true
	Input.parse_input_event(pressed)
	await process_frame
	var released := InputEventKey.new()
	released.keycode = KEY_L
	released.ctrl_pressed = true
	released.pressed = false
	Input.parse_input_event(released)
	await process_frame


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
