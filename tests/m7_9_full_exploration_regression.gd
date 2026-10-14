extends SceneTree

const ENTRY := "res://scenes/exploration/m7_7_progression_prototype.tscn"
const VN := "res://scenes/vn/vn_prototype.tscn"
const SAVE_PATH := "user://lumencia_save.json"
const CONTEXT_ID := "m7_7_progression_prototype_forest"
const HERB_ID := "healing_herb"
const SHOP_ID := "prototype_supply_shop"
const REST_ID := "prototype_camp_rest"

var failures: Array[String] = []
var checks := 0
var game_state: Node


func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name",
		"Lumencia Academy M7.9 Regression %d" % Time.get_ticks_usec())
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1152, 648)
	root.content_scale_size = Vector2i(1152, 648)
	game_state = root.get_node("GameState")
	await _complete_journey()
	await _early_progression()
	await _free_current_scene()
	game_state.reset_state()
	var isolated_save: String = ProjectSettings.globalize_path(SAVE_PATH)
	if FileAccess.file_exists(isolated_save):
		DirAccess.remove_absolute(isolated_save)
	if failures.is_empty():
		print("M7.9 full exploration regression suite passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	push_error("M7.9 full exploration suite failed: %d failure(s), %d checks." % [failures.size(), checks])
	quit(1)


func _complete_journey() -> void:
	game_state.reset_state()
	var entry: Node = await _load_scene(ENTRY)
	if entry == null:
		return
	var map: Variant = _current_map()
	var state: ExplorationState = game_state.exploration_state
	_check(entry.context_ready and map != null and state.active_context_id == CONTEXT_ID, "START: trusted Forest context/map did not initialize")
	if map == null:
		return
	_check(state.current_node_id == "old_trail" and state.is_node_revealed("riverside_camp") and not state.is_node_revealed("deep_grove"), "START: starting position/reveal state is wrong")
	_check(map.get_marker_button("riverside_camp") != null and map.get_marker_button("deep_grove") == null and map.map_texture.texture != null, "START: real map, visible marker, or hidden marker is wrong")
	_check(game_state.inventory_state.get_quantity(HERB_ID) == 9 and game_state.get_money() == 12 and game_state.party_runtime_state.get_member("party_1")["current_hp"] == 20, "START: inventory, money, or party HP seed is wrong")
	_check(_total() == 0 and state.get_time_snapshot()["mode"] == ExplorationState.MULTI_DAY and _handoffs_clear(), "START: clock or pending handoffs are wrong")
	_travel(map, "riverside_camp")
	_check(state.current_node_id == "riverside_camp" and _total() == 0 and not state.is_node_completed("riverside_camp"), "TRAVEL: Riverside travel charged time or consumed VN")
	_check(map.shop_action_button.visible and map.camp_rest_button.visible and map.wait_button.visible and map.primary_action_button.visible, "HUB: independent actions are missing before VN")
	_check(state.get_hub_action_uses_remaining("riverside_camp", REST_ID) == 2, "HUB: initial Rest uses are wrong")
	map.shop_action_button.pressed.emit()
	map.shop_buy_button.pressed.emit()
	_check(game_state.get_money() == 8 and game_state.inventory_state.get_quantity(HERB_ID) == 10 and _total() == 0, "SHOP: UI purchase failed or charged time")
	map.shop_back_button.pressed.emit()
	_check(map.interact_with_current_node(), "VN: Riverside interaction did not launch")
	await _wait_for_scene("VNPrototype")
	var vn: Variant = current_scene
	_check(vn != null and vn.name == "VNPrototype" and vn.current_node_id == "riverside_01", "VN: real Riverside scene/line did not load")
	if vn == null or vn.name != "VNPrototype":
		return
	_check(game_state.get_pending_exploration_content().get("content_type") == "vn_event" and _total() == 0, "VN: handoff missing or launch charged time")
	for step: int in 3:
		vn._advance_dialogue()
	await _wait_for_scene("ExplorationMap")
	map = _current_map()
	_check(map != null and current_scene.name == "ExplorationMap", "VN: legitimate return did not reach map")
	if map == null:
		return
	_check(state.is_node_completed("riverside_camp") and state.is_node_revealed("deep_grove") and state.is_node_roadblocked("riverside_camp") and state.is_node_reusable("riverside_camp"), "VN: completion/reveal/roadblock/reusable facts changed")
	_check(_total() == 1 and _handoffs_clear() and not map.interact_with_current_node(), "VN: return did not charge once or primary content replayed")
	_check(map.shop_action_button.visible and map.camp_rest_button.visible and state.get_hub_action_uses_remaining("riverside_camp", REST_ID) == 2, "VN: independent Shop/Rest or uses were lost")
	_travel(map, "stone_crossing")
	_check(_total() == 1 and not state.is_node_completed("stone_crossing"), "BATTLE: travel charged time or completed content")
	_check(map.interact_with_current_node(), "BATTLE: Stone Crossing did not launch")
	await _wait_for_scene("BattleSandbox")
	var battle: Variant = current_scene
	_check(battle != null and battle.name == "BattleSandbox", "BATTLE: real Battle scene did not load")
	if battle == null or battle.name != "BattleSandbox":
		return
	battle.automatic_enemy_turns_enabled = false
	_check(battle.hiruko_unit.current_hp == 20 and game_state.get_pending_exploration_content().get("content_type") == "battle", "BATTLE: runtime HP hydration or handoff failed")
	battle.party_units[0].current_hp = 15
	battle.party_units[1].current_hp = 10
	battle.party_units[2].current_hp = 0
	battle.party_units[2].defeated = true
	for enemy: Variant in battle.enemy_units:
		enemy.current_hp = 0
		enemy.defeated = true
	_check(battle._check_battle_result(), "BATTLE: deterministic Victory was not recognized")
	await _wait_for_scene("ExplorationMap")
	map = _current_map()
	_check(map != null and current_scene.name == "ExplorationMap", "BATTLE: Victory did not return to map")
	if map == null:
		return
	_check(state.is_node_completed("stone_crossing") and _total() == 2 and _handoffs_clear() and not map.interact_with_current_node(), "BATTLE: completion/time/handoff or replay is wrong")
	_check(game_state.party_runtime_state.get_member("party_1")["current_hp"] == 15 and game_state.party_runtime_state.get_member("party_2")["current_hp"] == 10 and game_state.party_runtime_state.get_member("party_3")["current_hp"] == 0, "BATTLE: Victory did not synchronize party HP")
	_travel(map, "ruins_approach")
	_check(_total() == 2 and not state.is_node_completed("ruins_approach"), "RESOURCE: travel consumed resource or time")
	map.primary_action_button.pressed.emit()
	_check(state.is_node_completed("ruins_approach") and _total() == 3 and game_state.inventory_state.get_quantity(HERB_ID) == 10, "RESOURCE: primary completion/reward/time is wrong")
	_check(state.get_leftover_reward("ruins_approach") == {"item_id": HERB_ID, "quantity": 2} and map.get_marker_button("ruins_approach").get_node("LeftoverBadge").visible, "RESOURCE: overflow or ITEM indicator is missing")
	var resource_before: Dictionary = state.get_save_snapshot()
	map.primary_action_button.pressed.emit()
	_check(state.get_save_snapshot() == resource_before and _total() == 3, "RESOURCE: full-inventory retry mutated state")
	_travel(map, "stone_crossing")
	_travel(map, "riverside_camp")
	_check(_total() == 3 and map.shop_action_button.visible and map.camp_rest_button.visible, "HUB: travel or scene returns reset hub actions")
	map.camp_rest_button.pressed.emit()
	await process_frame
	_check(_total() == 4 and state.get_hub_action_uses_remaining("riverside_camp", REST_ID) == 1 and game_state.party_runtime_state.get_member("party_3")["current_hp"] == 18, "REST: first use did not revive/charge exactly once")
	map.wait_button.pressed.emit()
	await process_frame
	_check(_total() == 5 and state.get_time_snapshot()["day"] == 1 and state.get_time_snapshot()["daypart"] == "Night", "TIME: Wait did not reach Day 1 Night action 2")
	_check(game_state.party_runtime_state.set_current_hp("party_1", 0), "REST: deterministic sixth-action injury setup failed")
	map.camp_rest_button.pressed.emit()
	await process_frame
	_check(_total() == 6 and state.get_time_snapshot()["day"] == 2 and state.get_time_snapshot()["daypart"] == "Morning" and state.get_time_snapshot()["actions_spent"] == 0, "TIME: sixth-action Rest did not enter Day 2 Morning 0/2")
	_check(state.get_hub_action_uses_remaining("riverside_camp", REST_ID) == 0 and game_state.party_runtime_state.get_member("party_1")["current_hp"] == 31, "REST: sixth-action 50% recovery then 20% Night Rest is wrong")
	_check(not game_state.use_current_camp_rest("riverside_camp", REST_ID)["success"] and _total() == 6 and map.shop_action_button.visible, "REST: exhausted third use succeeded or Shop vanished")
	game_state.set_flag("m6_training_hall_obey_direct_hit_applied", true)
	game_state.adjust_bond("hiruko", 2)
	map.warning_preference_button.button_pressed = false
	_check(not game_state.is_missable_content_warning_enabled(), "SAVE: warning preference did not switch OFF")
	map.map_save_button.pressed.emit()
	_check(FileAccess.file_exists(SAVE_PATH) and map.save_load_status.text == "Saved successfully.", "SAVE: stable map UI did not write checkpoint")
	var save_data: Dictionary = game_state.read_save_data()
	var expected_state: Dictionary = state.get_save_snapshot()
	var expected_inventory: Array = game_state.inventory_state.get_save_snapshot()
	var expected_hp: Array = game_state.party_runtime_state.get_save_snapshot()
	_check(save_data.get("schema_version") == 2 and save_data.get("kind") == "exploration" and save_data.get("exploration", {}).get("leftover_rewards", []).size() == 1, "SAVE: versioned checkpoint omitted representative leftovers")
	game_state.reset_state()
	vn = await _load_scene(VN)
	if vn == null:
		return
	vn.load_button.pressed.emit()
	await _wait_for_scene("M7_7ProgressionPrototype")
	map = _current_map()
	state = game_state.exploration_state
	_check(map != null and current_scene.name == "M7_7ProgressionPrototype", "LOAD: cold VN Load did not route to progression map")
	if map == null:
		return
	_check(state.get_save_snapshot() == expected_state and game_state.inventory_state.get_save_snapshot() == expected_inventory and game_state.party_runtime_state.get_save_snapshot() == expected_hp, "LOAD: map/inventory/party state did not restore exactly")
	_check(game_state.get_money() == 8 and game_state.get_flag("m6_training_hall_obey_direct_hit_applied") and game_state.get_bond("hiruko") == 2 and not game_state.is_missable_content_warning_enabled(), "LOAD: money/receipt/Bond/preference did not restore")
	_check(_handoffs_clear() and _total() == 6 and state.get_hub_action_uses_remaining("riverside_camp", REST_ID) == 0 and state.is_node_roadblocked("riverside_camp"), "LOAD: handoff/clock/Rest/roadblock restored incorrectly")
	_check(not map.primary_action_button.visible and map.shop_action_button.visible and map.camp_rest_button.disabled, "LOAD: completed VN replay or exhausted hub reset")
	_travel(map, "stone_crossing")
	_check(not map.interact_with_current_node() and _total() == 6, "RESUME: completed battle replayed")
	_travel(map, "ruins_approach")
	_check(state.has_leftover_reward("ruins_approach") and map.primary_action_button.text == "Collect Leftover", "RESUME: leftover source was not actionable")
	_check(game_state.party_runtime_state.set_current_hp("party_1", 1) and game_state.party_runtime_state.set_current_hp("party_2", 1), "RESUME: deterministic item-target setup failed")
	map.inventory_button.pressed.emit()
	map.healing_herb_button.pressed.emit()
	map.inventory_target_list.get_node("InventoryTarget_party_1").pressed.emit()
	map.healing_herb_button.pressed.emit()
	map.inventory_target_list.get_node("InventoryTarget_party_2").pressed.emit()
	_check(game_state.inventory_state.get_quantity(HERB_ID) == 8 and _total() == 6, "RESUME: two Exploration Herbs did not free space without time")
	map.primary_action_button.pressed.emit()
	_check(game_state.inventory_state.get_quantity(HERB_ID) == 10 and not state.has_leftover_reward("ruins_approach") and _total() == 6, "RESUME: leftover collection duplicated reward or charged time")
	_check(not map.get_marker_button("ruins_approach").get_node("LeftoverBadge").visible and not map.interact_with_current_node(), "RESUME: leftover marker persisted or resource replayed")
	_travel(map, "stone_crossing")
	_travel(map, "riverside_camp")
	map.inventory_button.pressed.emit()
	map.healing_herb_button.pressed.emit()
	map.inventory_target_list.get_node("InventoryTarget_party_1").pressed.emit()
	map.shop_action_button.pressed.emit()
	map.shop_buy_button.pressed.emit()
	_check(game_state.get_money() == 4 and game_state.inventory_state.get_quantity(HERB_ID) == 10 and _total() == 6 and map.camp_rest_button.disabled, "RESUME: Shop after exhausted Rest replayed state or charged time")
	map.shop_back_button.pressed.emit()
	map.warning_preference_button.button_pressed = true
	_travel(map, "old_trail")
	_travel(map, "forest_boundary")
	_check(state.get_missable_content_summary()["total"] == 0 and _total() == 6, "PROGRESS: completed optional content or travel counted as missable/time")
	map.primary_action_button.pressed.emit()
	_check(not map.warning_dialog_open, "PROGRESS: unnecessary warning appeared with no unfinished content")
	await _wait_for_scene("M7_7ProgressionResult")
	_check(current_scene != null and current_scene.name == "M7_7ProgressionResult" and state.is_context_closed(CONTEXT_ID), "PROGRESS: completed journey did not close to result")
	if current_scene == null or current_scene.name != "M7_7ProgressionResult":
		return
	_check(not state.activate_context(CONTEXT_ID) and not game_state.advance_story_from_exploration(CONTEXT_ID, "forest_boundary")["success"], "PROGRESS: closed context reopened or advanced twice")
	current_scene.save_button.pressed.emit()
	_check(game_state.read_save_data().get("kind") == "result", "RESULT: UI save did not persist result kind")
	game_state.reset_state()
	vn = await _load_scene(VN)
	vn.load_button.pressed.emit()
	await _wait_for_scene("M7_7ProgressionResult")
	_check(current_scene != null and current_scene.name == "M7_7ProgressionResult" and game_state.exploration_state.is_context_closed(CONTEXT_ID), "RESULT: cold result load reopened Forest")
	_check(not game_state.exploration_state.has_active_context() and game_state.get_money() == 4 and game_state.inventory_state.get_quantity(HERB_ID) == 10, "RESULT: loaded global player state changed")
	_check(not game_state.exploration_state.activate_context(CONTEXT_ID) and not game_state.prepare_exploration_content("vn_event", "m7_3_riverside_event"), "RESULT: closed Forest permitted ordinary activation or event replay")
	game_state.reset_state()
	entry = await _load_scene(ENTRY)
	_check(entry != null and entry.context_ready and game_state.exploration_state.current_node_id == "old_trail", "RESULT: explicit fresh reset did not start new Forest")


func _early_progression() -> void:
	game_state.reset_state()
	var entry: Node = await _load_scene(ENTRY)
	if entry == null:
		return
	var map: Variant = _current_map()
	var state: ExplorationState = game_state.exploration_state
	if map == null:
		_check(false, "EARLY: map missing")
		return
	_travel(map, "forest_boundary")
	_check(state.current_node_id == "forest_boundary" and _total() == 0 and not state.is_node_completed("forest_boundary"), "EARLY: final travel advanced story or time")
	var before: Dictionary = _session_snapshot()
	map.primary_action_button.pressed.emit()
	_check(map.warning_dialog_open and map.warning_summary_label.text.contains("Optional events: 3"), "EARLY: warning did not count unfinished optional content")
	_check(not map.warning_summary_label.text.contains("Riverside") and not map.warning_summary_label.text.contains("Stone") and map.get_marker_button("old_trail").disabled, "EARLY: warning spoiled details or exposed travel")
	map.warning_go_back_button.pressed.emit()
	_check(not map.warning_dialog_open and _session_snapshot() == before and map.primary_action_button.has_focus(), "EARLY: Go Back mutated state or lost focus")
	map.primary_action_button.pressed.emit()
	_check(map.warning_dialog_open, "EARLY: second Advance Story did not warn")
	map.warning_continue_button.pressed.emit()
	await _wait_for_scene("M7_7ProgressionResult")
	_check(current_scene != null and current_scene.name == "M7_7ProgressionResult" and state.is_context_closed(CONTEXT_ID), "EARLY: Continue did not reach result/close context")
	_check(not state.has_active_context() and game_state.get_money() == before["money"] and game_state.inventory_state.get_save_snapshot() == before["inventory"] and game_state.party_runtime_state.get_save_snapshot() == before["party_hp"], "EARLY: optional content became mandatory or Continue changed resources")
	_check(not state.activate_context(CONTEXT_ID), "EARLY: closed context reactivated")


func _session_snapshot() -> Dictionary:
	return {"exploration": game_state.exploration_state.get_save_snapshot(),
		"inventory": game_state.inventory_state.get_save_snapshot(),
		"party_hp": game_state.party_runtime_state.get_save_snapshot(),
		"money": game_state.get_money(), "flags": game_state.flags.duplicate(true),
		"bonds": game_state.bonds.duplicate(true),
		"warning": game_state.is_missable_content_warning_enabled()}


func _handoffs_clear() -> bool:
	return game_state.get_pending_exploration_content().is_empty() and game_state.get_pending_vn_sequence().is_empty() and game_state.get_pending_battle_context().is_empty() and game_state.get_pending_battle_result().is_empty()


func _total() -> int:
	return int(game_state.exploration_state.get_time_snapshot().get("total_actions", -1))


func _travel(map: Variant, node_id: String) -> void:
	var marker: Button = map.get_marker_button(node_id)
	_check(marker != null and not marker.disabled, "TRAVEL: %s marker is missing/unreachable" % node_id)
	if marker != null and not marker.disabled:
		marker.pressed.emit()


func _current_map() -> Variant:
	if current_scene == null:
		return null
	if current_scene.has_method("get_marker_button"):
		return current_scene
	return current_scene.find_child("ExplorationMap", true, false)


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
	return scene


func _wait_for_scene(expected_name: String) -> Node:
	for frame: int in 30:
		if current_scene != null and current_scene.name == expected_name and current_scene.is_node_ready():
			if expected_name != "ExplorationMap" and expected_name != "M7_7ProgressionPrototype":
				return current_scene
			var map: Variant = _current_map()
			if map != null and map.get_marker_button("old_trail") != null:
				return current_scene
		await process_frame
	return null


func _free_current_scene() -> void:
	if current_scene == null:
		return
	var old: Node = current_scene
	current_scene = null
	old.queue_free()
	await process_frame


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
