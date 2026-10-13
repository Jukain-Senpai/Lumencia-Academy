extends SceneTree

const InventoryStateModel := preload("res://scripts/systems/inventory_state.gd")
const ItemCatalogModel := preload("res://scripts/systems/item_catalog.gd")
const ENTRY_SCENE_PATH := "res://scenes/exploration/m7_4_inventory_prototype.tscn"
const MAP_SCENE_PATH := "res://scenes/exploration/exploration_map.tscn"
const BATTLE_SCENE_PATH := "res://scenes/battle/battle_sandbox.tscn"
const DESIGN_PATH := "res://docs/M7_4_INVENTORY_FOUNDATION_DESIGN.md"
const GAME_STATE_PATH := "res://scripts/systems/game_state.gd"
const HERB_ID := "healing_herb"

var failures: Array[String] = []
var checks := 0
var game_state: Node
var exploration_state: Variant


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1152, 648)
	root.content_scale_size = Vector2i(1152, 648)
	game_state = root.get_node("GameState")
	exploration_state = game_state.exploration_state

	_test_definition_inventory_and_contexts()
	_test_party_runtime_and_exploration_use()
	await _test_canonical_overflow_ui_loop()
	await _test_leftover_badge_state_composition()
	await _test_full_inventory_leftover_retry()
	await _test_leftover_transition_survival()
	await _test_battle_item_root_action_availability()
	await _test_battle_item_shared_inventory_and_victory_sync()
	await _test_battle_cancel_invalid_and_restart_semantics()
	_test_save_reset_and_scope_boundaries()

	await _free_current_scene()
	game_state.reset_state()
	if failures.is_empty():
		print("M7.4 inventory foundation regression suite passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	push_error(
		"M7.4 inventory foundation suite failed: %d failure(s), %d checks."
		% [failures.size(), checks]
	)
	quit(1)


func _test_definition_inventory_and_contexts() -> void:
	_check(FileAccess.file_exists(DESIGN_PATH), "DESIGN: M7.4 decision record is missing")
	var herb: Dictionary = ItemCatalogModel.get_definition(HERB_ID)
	_check(herb.get("display_name") == "Healing Herb", "ITEM: Healing Herb display name is wrong")
	_check(herb.get("use_context") == ItemCatalogModel.BOTH, "ITEM: Healing Herb is not BOTH-context")
	_check(herb.get("effect", {}).get("type") == "heal", "ITEM: Healing Herb effect is not heal")
	_check(herb.get("effect", {}).get("amount") == 18, "ITEM: prototype heal amount changed")
	var mutated := herb.duplicate(true)
	mutated["effect"]["amount"] = 999
	_check(ItemCatalogModel.get_definition(HERB_ID)["effect"]["amount"] == 18, "ITEM: definition leaked mutable metadata")

	var inventory := InventoryStateModel.new()
	_check(inventory.get_quantity(HERB_ID) == 0, "INVENTORY: initial Herb quantity is not zero")
	var gain_one: Dictionary = inventory.gain_item(HERB_ID, 1)
	_check(gain_one == {"requested": 1, "accepted": 1, "remaining": 0}, "INVENTORY: gain 1 result is wrong")
	_check(inventory.get_quantity(HERB_ID) == 1, "INVENTORY: gain 1 did not store one")
	var gain_nine: Dictionary = inventory.gain_item(HERB_ID, 9)
	_check(gain_nine["accepted"] == 9 and inventory.get_quantity(HERB_ID) == 10, "INVENTORY: gain to cap failed")
	var overflow: Dictionary = inventory.gain_item(HERB_ID, 1)
	_check(overflow["accepted"] == 0 and overflow["remaining"] == 1, "INVENTORY: cap overflow result is wrong")
	_check(inventory.get_quantity(HERB_ID) == 10, "INVENTORY: stack exceeded 10")
	_check(inventory.consume_item(HERB_ID, 1) and inventory.get_quantity(HERB_ID) == 9, "INVENTORY: consume 1 failed")
	_check(inventory.consume_item(HERB_ID, 9) and inventory.get_quantity(HERB_ID) == 0, "INVENTORY: consume to zero failed")
	_check(not inventory.consume_item(HERB_ID, 1), "INVENTORY: consumed at zero")
	_check(not inventory.consume_item(HERB_ID, 0), "INVENTORY: accepted zero consume")
	_check(not inventory.consume_item("missing", 1), "INVENTORY: consumed unknown item")
	_check(inventory.gain_item("missing", 2)["accepted"] == 0, "INVENTORY: gained unknown item")
	_check(inventory.gain_item(HERB_ID, 0)["accepted"] == 0, "INVENTORY: accepted zero gain")

	var test_definitions := {
		"battle_test": _test_item_definition("battle_test", ItemCatalogModel.BATTLE_ONLY),
		"exploration_test": _test_item_definition("exploration_test", ItemCatalogModel.EXPLORATION_ONLY),
	}
	var restricted_inventory := InventoryStateModel.new(test_definitions)
	restricted_inventory.gain_item("battle_test", 1)
	restricted_inventory.gain_item("exploration_test", 1)
	_check(restricted_inventory.can_use_in_context("battle_test", ItemCatalogModel.BATTLE_ONLY), "CONTEXT: BATTLE_ONLY rejected Battle")
	_check(not restricted_inventory.can_use_in_context("battle_test", ItemCatalogModel.EXPLORATION_ONLY), "CONTEXT: BATTLE_ONLY allowed Exploration")
	_check(restricted_inventory.can_use_in_context("exploration_test", ItemCatalogModel.EXPLORATION_ONLY), "CONTEXT: EXPLORATION_ONLY rejected Exploration")
	_check(not restricted_inventory.can_use_in_context("exploration_test", ItemCatalogModel.BATTLE_ONLY), "CONTEXT: EXPLORATION_ONLY allowed Battle")


func _test_party_runtime_and_exploration_use() -> void:
	game_state.reset_state()
	var party: Variant = game_state.party_runtime_state
	var heal_amount := _healing_herb_amount()
	_check(party.get_members().size() == 6, "PARTY: runtime does not contain six stable members")
	_check(party.get_member("party_1")["display_name"] == "Hiruko", "PARTY: Hiruko stable identity changed")
	_check(party.get_member("party_2")["display_name"] == "Jukain", "PARTY: Jukain stable identity changed")
	_check(party.set_current_hp("party_1", 20), "PARTY: could not damage living Hiruko")
	game_state.inventory_state.gain_item(HERB_ID, 2)
	var use_result: Dictionary = game_state.use_item_in_exploration(HERB_ID, "party_1")
	_check(use_result["success"] and use_result["healed"] == heal_amount, "EXPLORATION USE: configured fixed heal was not applied")
	_check(party.get_member("party_1")["current_hp"] == 20 + heal_amount, "EXPLORATION USE: authoritative HP is wrong")
	_check(game_state.inventory_state.get_quantity(HERB_ID) == 1, "EXPLORATION USE: quantity did not decrease once")
	var full_hp_result: Dictionary = game_state.use_item_in_exploration(HERB_ID, "party_2")
	_check(full_hp_result["success"] and full_hp_result["healed"] == 0, "EXPLORATION USE: full-HP living target was rejected")
	_check(game_state.inventory_state.get_quantity(HERB_ID) == 0, "EXPLORATION USE: full-HP use did not consume Herb")
	_check(party.set_current_hp("party_1", 0), "PARTY: could not establish defeated target")
	game_state.inventory_state.gain_item(HERB_ID, 1)
	var defeated_result: Dictionary = game_state.use_item_in_exploration(HERB_ID, "party_1")
	_check(not defeated_result["success"], "EXPLORATION USE: defeated target was healed")
	_check(party.get_member("party_1")["current_hp"] == 0, "EXPLORATION USE: Herb revived defeated target")
	_check(game_state.inventory_state.get_quantity(HERB_ID) == 1, "EXPLORATION USE: failed use consumed Herb")
	_check(not game_state.use_item_in_exploration(HERB_ID, "missing")["success"], "EXPLORATION USE: unknown target was accepted")


func _test_canonical_overflow_ui_loop() -> void:
	var map: Variant = await _fresh_inventory_map()
	if map == null:
		return
	_check(game_state.inventory_state.get_quantity(HERB_ID) == 9, "OVERFLOW: prototype did not start with Herb ×9")
	_check(game_state.party_runtime_state.get_member("party_1")["current_hp"] == 20, "OVERFLOW: prototype Hiruko is not damaged")
	await _travel_path(map, ["riverside_camp", "stone_crossing", "ruins_approach"])
	_check(not exploration_state.is_node_completed("ruins_approach"), "OVERFLOW: travel consumed resource")
	map.primary_action_button.emit_signal("pressed")
	await process_frame
	_check(game_state.inventory_state.get_quantity(HERB_ID) == 10, "OVERFLOW: Inventory did not cap at 10")
	_check(exploration_state.is_node_completed("ruins_approach"), "OVERFLOW: primary resource did not complete")
	var leftover: Dictionary = exploration_state.get_leftover_reward("ruins_approach")
	_check(leftover == {"item_id": HERB_ID, "quantity": 1}, "OVERFLOW: exact Herb ×1 leftover is wrong")
	_check(exploration_state.current_node_id == "ruins_approach", "OVERFLOW: current location changed")
	_check(map.primary_action_button.text == "Collect Leftover", "OVERFLOW: leftover action is missing")
	var ruins_marker: Button = map.get_marker_button("ruins_approach")
	_check(ruins_marker.get_meta("has_leftover"), "OVERFLOW: marker metadata lacks leftover")
	_check(ruins_marker.get_meta("is_current") and ruins_marker.get_meta("is_completed"), "OVERFLOW: current/completed marker facts do not coexist")
	_check(ruins_marker.get_node("LeftoverBadge").visible, "OVERFLOW: leftover badge is hidden")
	_check(ruins_marker.get_node("LeftoverBadge").text == "ITEM ×1", "OVERFLOW: leftover badge quantity is unreadable")
	await _assert_leftover_badge_geometry(map, "ruins_approach", Vector2i(1152, 648))
	await _assert_leftover_badge_geometry(map, "ruins_approach", Vector2i(1440, 810))
	root.size = Vector2i(1152, 648)
	await process_frame
	await process_frame
	_check(map.refresh_map(), "OVERFLOW: map did not restore the baseline viewport")
	var completion_before: Dictionary = exploration_state.completed_nodes.duplicate(true)
	map.primary_action_button.emit_signal("pressed")
	await process_frame
	_check(game_state.inventory_state.get_quantity(HERB_ID) == 10, "FULL: retry changed full Inventory")
	_check(exploration_state.get_leftover_reward("ruins_approach") == leftover, "FULL: retry destroyed leftover")
	_check(exploration_state.completed_nodes == completion_before, "FULL: retry replayed primary completion")
	_check(map.get_marker_button("ruins_approach").get_node("LeftoverBadge").visible, "FULL: retry hid leftover badge")
	await _assert_leftover_badge_geometry(map, "ruins_approach", Vector2i(1152, 648))

	map.inventory_button.emit_signal("pressed")
	_check(map.inventory_panel.visible, "EXPLORATION UI: Items panel did not open")
	_check(map.healing_herb_button.text == "Healing Herb ×10", "EXPLORATION UI: quantity is not visible")
	map.healing_herb_button.emit_signal("pressed")
	var hiruko_target: Button = map.inventory_target_list.get_node("InventoryTarget_party_1")
	_check(hiruko_target.text.contains("HP 20/44"), "EXPLORATION UI: target HP is not shown")
	hiruko_target.emit_signal("pressed")
	_check(game_state.inventory_state.get_quantity(HERB_ID) == 9, "EXPLORATION UI: Herb use did not consume one")
	var heal_amount := _healing_herb_amount()
	_check(game_state.party_runtime_state.get_member("party_1")["current_hp"] == 20 + heal_amount, "EXPLORATION UI: Hiruko did not receive configured healing")
	_check(map.inventory_status.text.contains("recovered %d HP" % heal_amount), "EXPLORATION UI: healing feedback is unclear")
	await _travel_path(map, ["stone_crossing", "ruins_approach"])
	_check(exploration_state.has_leftover_reward("ruins_approach"), "LEFTOVER: move away/back lost source")
	map.primary_action_button.emit_signal("pressed")
	await process_frame
	_check(game_state.inventory_state.get_quantity(HERB_ID) == 10, "LEFTOVER: later collection did not restore ×10")
	_check(not exploration_state.has_leftover_reward("ruins_approach"), "LEFTOVER: collected source remains")
	_check(not map.get_marker_button("ruins_approach").get_node("LeftoverBadge").visible, "LEFTOVER: badge did not disappear")
	_check(not map.primary_action_button.visible, "LEFTOVER: completed source remains actionable")


func _test_leftover_badge_state_composition() -> void:
	var map: Variant = await _fresh_inventory_map()
	if map == null:
		return
	await _travel_path(map, ["riverside_camp"])
	_check(exploration_state.complete_primary_content("riverside_camp"), "BADGE COMPOSITION: node could not complete")
	_check(exploration_state.set_leftover_reward("riverside_camp", HERB_ID, 2), "BADGE COMPOSITION: leftover fixture failed")
	_check(map.refresh_map(), "BADGE COMPOSITION: map refresh failed")
	var marker: Button = map.get_marker_button("riverside_camp")
	_check(marker.get_meta("is_current"), "BADGE COMPOSITION: marker is not current")
	_check(marker.get_meta("is_completed"), "BADGE COMPOSITION: marker is not completed")
	_check(marker.get_meta("is_roadblocked"), "BADGE COMPOSITION: roadblock state disappeared")
	_check(marker.get_meta("is_reusable"), "BADGE COMPOSITION: reusable state disappeared")
	_check(marker.get_node("CurrentTag").visible, "BADGE COMPOSITION: current tag disappeared")
	_check(marker.get_node("CompletedBadge").visible, "BADGE COMPOSITION: completed badge disappeared")
	_check(marker.get_node("RoadblockBadge").visible, "BADGE COMPOSITION: roadblock badge disappeared")
	_check(marker.get_node("ReusableBadge").visible, "BADGE COMPOSITION: reusable badge disappeared")
	_check(marker.get_node("LeftoverBadge").text == "ITEM ×2", "BADGE COMPOSITION: leftover quantity is wrong")
	await _assert_leftover_badge_geometry(map, "riverside_camp", Vector2i(1152, 648))
	await _assert_leftover_badge_geometry(map, "riverside_camp", Vector2i(1440, 810))
	root.size = Vector2i(1152, 648)
	await process_frame
	await process_frame


func _test_full_inventory_leftover_retry() -> void:
	var map: Variant = await _fresh_inventory_map()
	if map == null:
		return
	await _travel_path(map, ["riverside_camp", "stone_crossing", "ruins_approach"])
	map.primary_action_button.emit_signal("pressed")
	await process_frame
	var before: Dictionary = exploration_state.get_leftover_reward("ruins_approach")
	map.primary_action_button.emit_signal("pressed")
	await process_frame
	_check(game_state.inventory_state.get_quantity(HERB_ID) == 10, "FULL RETRY: quantity changed")
	_check(exploration_state.get_leftover_reward("ruins_approach") == before, "FULL RETRY: item was destroyed")
	_check(map.primary_action_status.text.contains("Leftover remains ×1"), "FULL RETRY: feedback is unclear")


func _test_leftover_transition_survival() -> void:
	var map: Variant = await _fresh_inventory_map()
	if map == null:
		return
	await _travel_path(map, ["riverside_camp", "stone_crossing", "ruins_approach"])
	map.primary_action_button.emit_signal("pressed")
	await process_frame
	await _travel_path(map, ["stone_crossing"])
	_check(map.interact_with_current_node(), "TRANSITION: Stone battle did not launch")
	await process_frame
	await process_frame
	var battle: Variant = current_scene
	_check(battle != null and battle.name == "BattleSandbox", "TRANSITION: battle scene did not load")
	if battle == null or battle.name != "BattleSandbox":
		return
	battle.automatic_enemy_turns_enabled = false
	_defeat_all_enemies(battle)
	_check(battle._check_battle_result(), "TRANSITION: Victory was not recognized")
	await process_frame
	await process_frame
	map = _current_map()
	_check(map != null and exploration_state.has_leftover_reward("ruins_approach"), "TRANSITION: battle return lost leftover")
	await _travel_path(map, ["riverside_camp"])
	_check(map.interact_with_current_node(), "TRANSITION: Riverside VN did not launch")
	await process_frame
	await process_frame
	var vn: Variant = current_scene
	_check(vn != null and vn.name == "VNPrototype", "TRANSITION: VN scene did not load")
	if vn == null or vn.name != "VNPrototype":
		return
	vn._advance_dialogue()
	vn._advance_dialogue()
	vn._advance_dialogue()
	await process_frame
	await process_frame
	map = _current_map()
	_check(map != null and exploration_state.has_leftover_reward("ruins_approach"), "TRANSITION: VN return lost leftover")
	_check(exploration_state.get_leftover_reward("ruins_approach")["quantity"] == 1, "TRANSITION: leftover quantity changed")


func _test_battle_item_shared_inventory_and_victory_sync() -> void:
	var battle: Variant = await _launch_prototype_battle()
	if battle == null:
		return
	await _ensure_player_turn(battle)
	_check(battle.current_unit != null and battle.current_unit.team == battle.BattleUnitModel.Team.PARTY, "BATTLE ITEM: no player turn")
	_check(battle.hiruko_unit.current_hp <= 20, "BATTLE ITEM: BattleUnit was not hydrated from runtime HP")
	var actor: Variant = battle.current_unit
	actor.current_hp = 10
	battle._apply_burn(actor)
	var turn_index_before: int = battle.turn_index
	battle.item_button.emit_signal("pressed")
	_check(battle.selecting_item and battle.healing_herb_button.visible, "BATTLE ITEM: Item root action did not open list")
	_check(battle.healing_herb_button.text == "Healing Herb ×9", "BATTLE ITEM: shared quantity is wrong")
	battle.healing_herb_button.emit_signal("pressed")
	_check(battle.selected_item_id == HERB_ID, "BATTLE ITEM: Herb selection failed")
	_check(battle._contains_unit(battle.valid_item_targets, actor), "BATTLE ITEM: actor is not a valid target")
	_check(battle.use_battle_item_on_target(actor.stable_id), "BATTLE ITEM: valid use failed")
	_check(game_state.inventory_state.get_quantity(HERB_ID) == 8, "BATTLE ITEM: quantity did not decrease once")
	var heal_amount := _healing_herb_amount()
	_check(actor.current_hp == 10 + heal_amount - battle.BURN_DAMAGE, "BATTLE ITEM: heal and one Burn tick did not resolve exactly once")
	_check(battle._get_burn_ticks(actor) == 1, "BATTLE ITEM: Burn duration did not tick once")
	_check(battle.turn_index != turn_index_before or battle.current_unit != actor, "BATTLE ITEM: actor's turn was not consumed")
	var ally_target: Variant = battle.jukain_unit
	ally_target.current_hp = 10
	var second_actor: Variant = battle.current_unit
	_check(second_actor != null and second_actor != ally_target, "BATTLE ITEM: another player actor was not available")
	_check(battle.begin_item_selection() and battle.select_battle_item(HERB_ID), "BATTLE ITEM: ally-target flow did not open")
	_check(battle.use_battle_item_on_target(ally_target.stable_id), "BATTLE ITEM: another living ally was rejected")
	_check(ally_target.current_hp == 10 + heal_amount, "BATTLE ITEM: another living ally did not receive configured healing")
	_check(game_state.inventory_state.get_quantity(HERB_ID) == 7, "BATTLE ITEM: ally-target use did not consume exactly one")
	var battle_hiruko_hp: int = battle.hiruko_unit.current_hp
	_defeat_all_enemies(battle)
	_check(battle._check_battle_result(), "BATTLE ITEM: Victory was not recognized")
	_check(battle.party_runtime_synced, "BATTLE ITEM: Victory did not commit party runtime sync")
	_check(game_state.party_runtime_state.get_member("party_1")["current_hp"] == battle_hiruko_hp, "BATTLE ITEM: final BattleUnit HP did not sync")
	await process_frame
	await process_frame
	var map: Variant = _current_map()
	_check(map != null, "BATTLE ITEM: Victory did not return to Exploration")
	_check(game_state.inventory_state.get_quantity(HERB_ID) == 7, "SHARED: Exploration did not retain battle consumption")
	_check(map.inventory_button.text.contains("×7"), "SHARED: map UI does not show battle quantity")


func _test_battle_item_root_action_availability() -> void:
	var battle: Variant = await _launch_prototype_battle()
	if battle == null:
		return
	var cases: Array = [
		{"label": "Hiruko", "unit": battle.hiruko_unit},
		{"label": "Jukain Locked", "unit": battle.jukain_unit},
		{"label": "Generic party", "unit": battle.party_units[2]},
	]
	for item_case: Dictionary in cases:
		_set_current_battle_unit(battle, item_case["unit"])
		_check(battle.item_button.visible, "ROOT ACTION: Item is hidden for %s" % item_case["label"])
		_check(battle.begin_item_selection(), "ROOT ACTION: Item did not open for %s" % item_case["label"])
		_check(battle.back_from_item_menu(), "ROOT ACTION: Item Back failed for %s" % item_case["label"])
	_check(battle.jukain_state.unlock(), "ROOT ACTION: Jukain could not enter Unlocked fixture")
	_set_current_battle_unit(battle, battle.jukain_unit)
	_check(battle.item_button.visible, "ROOT ACTION: Item is hidden for Jukain Unlocked")
	_check(battle.begin_item_selection(), "ROOT ACTION: Item did not open for Jukain Unlocked")
	_check(battle.back_from_item_menu(), "ROOT ACTION: Item Back failed for Jukain Unlocked")
	_check(game_state.inventory_state.get_quantity(HERB_ID) == 9, "ROOT ACTION: menu checks consumed Inventory")


func _test_battle_cancel_invalid_and_restart_semantics() -> void:
	var battle: Variant = await _launch_prototype_battle()
	if battle == null:
		return
	await _ensure_player_turn(battle)
	var actor: Variant = battle.current_unit
	var quantity_before: int = game_state.inventory_state.get_quantity(HERB_ID)
	var hp_before: int = actor.current_hp
	var turn_before: int = battle.turn_index
	_check(battle.begin_item_selection(), "CANCEL: could not open Item list")
	_check(battle.back_from_item_menu(), "CANCEL: Item-list Back failed")
	_check(game_state.inventory_state.get_quantity(HERB_ID) == quantity_before, "CANCEL: list Back consumed item")
	_check(actor.current_hp == hp_before and battle.turn_index == turn_before, "CANCEL: list Back changed HP/turn")
	_check(battle.begin_item_selection() and battle.select_battle_item(HERB_ID), "CANCEL: target menu could not open")
	_check(battle.back_from_item_menu(), "CANCEL: target Back failed")
	_check(battle.selecting_item and battle.selected_item_id.is_empty(), "CANCEL: target Back did not return to item list")
	_check(game_state.inventory_state.get_quantity(HERB_ID) == quantity_before, "CANCEL: target Back consumed item")
	_check(actor.current_hp == hp_before and battle.turn_index == turn_before, "CANCEL: target Back changed HP/turn")
	battle.back_from_item_menu()

	var defeated_target: Variant = battle.party_units[1]
	defeated_target.current_hp = 0
	defeated_target.defeated = true
	_check(battle.begin_item_selection() and battle.select_battle_item(HERB_ID), "INVALID TARGET: item target mode failed")
	_check(not battle.use_battle_item_on_target(defeated_target.stable_id), "INVALID TARGET: defeated ally accepted")
	_check(game_state.inventory_state.get_quantity(HERB_ID) == quantity_before, "INVALID TARGET: defeated ally consumed item")
	_check(defeated_target.current_hp == 0 and battle.turn_index == turn_before, "INVALID TARGET: defeated ally revived/consumed turn")
	var enemy: Variant = battle.enemy_units[0]
	_check(not battle.use_battle_item_on_target(enemy.stable_id), "INVALID TARGET: enemy accepted Herb")
	battle.back_from_item_menu()
	battle.back_from_item_menu()

	await _ensure_player_turn(battle)
	actor = battle.current_unit
	var entry_hp: int = battle.battle_entry_hp_snapshot[String(actor.stable_id)]["current_hp"]
	actor.current_hp = maxi(1, entry_hp - 10)
	_check(battle.begin_item_selection() and battle.select_battle_item(HERB_ID), "RESTART: item flow did not open")
	_check(battle.use_battle_item_on_target(actor.stable_id), "RESTART: valid Herb use failed")
	var quantity_after_use: int = game_state.inventory_state.get_quantity(HERB_ID)
	_defeat_all_party(battle)
	_check(battle._check_battle_result(), "RESTART: Defeat was not recognized")
	_check(game_state.party_runtime_state.get_member(String(actor.stable_id))["current_hp"] == entry_hp, "RESTART: Defeat overwrote party runtime")
	battle.restart_battle()
	var restored: Variant = battle._find_unit_by_id(actor.stable_id)
	_check(restored.current_hp == entry_hp, "RESTART: encounter-entry HP snapshot was not restored")
	_check(game_state.inventory_state.get_quantity(HERB_ID) == quantity_after_use, "RESTART: consumed Herb was refunded")
	_check(not battle.party_runtime_synced, "RESTART: restart incorrectly published party HP")


func _test_save_reset_and_scope_boundaries() -> void:
	var source_file := FileAccess.open(GAME_STATE_PATH, FileAccess.READ)
	_check(source_file != null, "SAVE: GameState source could not be inspected")
	if source_file != null:
		var source := source_file.get_as_text()
		var save_start := source.find("var save_data := {")
		var save_end := source.find("var file := FileAccess.open", save_start)
		var payload := source.substr(save_start, save_end - save_start)
		_check(payload.contains("\"sequence\"") and payload.contains("\"node\"") and payload.contains("\"flags\"") and payload.contains("\"bonds\""), "SAVE: original keys are missing")
		_check(not payload.contains("inventory") and not payload.contains("party") and not payload.contains("leftover"), "SAVE: M7.4 runtime entered save schema")
	game_state.inventory_state.gain_item(HERB_ID, 4)
	game_state.party_runtime_state.set_current_hp("party_1", 7)
	game_state.reset_state()
	_check(game_state.inventory_state.get_quantity(HERB_ID) == 0, "RESET: Inventory survived GameState reset")
	_check(game_state.party_runtime_state.get_member("party_1")["current_hp"] == 44, "RESET: party HP did not reset")
	_check(not exploration_state.has_active_context() and exploration_state.leftover_rewards.is_empty(), "RESET: Exploration leftovers survived reset")
	var project_text := FileAccess.open("res://project.godot", FileAccess.READ).get_as_text()
	_check(not project_text.contains("money") and not project_text.contains("ActionClock"), "SCOPE: money/time system was added")


func _fresh_inventory_map() -> Variant:
	var scene: Variant = await _load_scene(ENTRY_SCENE_PATH)
	if scene == null:
		return null
	var map: Variant = scene.find_child("ExplorationMap", true, false)
	_check(map != null, "MAP: M7.4 prototype lacks reusable map")
	return map


func _launch_prototype_battle() -> Variant:
	var map: Variant = await _fresh_inventory_map()
	if map == null:
		return null
	await _travel_path(map, ["riverside_camp", "stone_crossing"])
	_check(map.interact_with_current_node(), "BATTLE: Stone Crossing interaction failed")
	await process_frame
	await process_frame
	var battle: Variant = current_scene
	_check(battle != null and battle.name == "BattleSandbox", "BATTLE: real BattleSandbox did not load")
	if battle != null and battle.name == "BattleSandbox":
		battle.automatic_enemy_turns_enabled = false
		return battle
	return null


func _ensure_player_turn(battle: Variant) -> void:
	for iteration: int in 12:
		if (
			battle.current_unit != null
			and battle.current_unit.team == battle.BattleUnitModel.Team.PARTY
		):
			return
		if battle.current_unit == null or battle.battle_result != battle.BattleResult.NONE:
			return
		battle.resolve_enemy_turn()
		await process_frame


func _set_current_battle_unit(battle: Variant, unit: Variant) -> void:
	battle.current_unit = unit
	battle.turn_index = battle.turn_queue.find(unit)
	battle.action_in_progress = false
	battle._clear_action_selection()
	battle._refresh_turn_ui()


func _current_map() -> Variant:
	if current_scene == null:
		return null
	if current_scene.has_method("get_marker_button"):
		return current_scene
	return current_scene.find_child("ExplorationMap", true, false)


func _travel_path(map: Variant, node_ids: Array) -> void:
	for raw_node_id: Variant in node_ids:
		var marker: Button = map.get_marker_button(String(raw_node_id))
		_check(marker != null, "TRAVEL: marker %s is missing" % raw_node_id)
		if marker != null:
			marker.emit_signal("pressed")
			await process_frame


func _assert_leftover_badge_geometry(
	map: Variant,
	node_id: String,
	target_size: Vector2i
) -> void:
	root.size = target_size
	await process_frame
	await process_frame
	_check(map.refresh_map(), "BADGE %s: refresh failed for %s" % [target_size, node_id])
	await process_frame
	var marker: Button = map.get_marker_button(node_id)
	var badge: Label = marker.get_node("LeftoverBadge")
	var badge_rect := badge.get_global_rect()
	var marker_rect := marker.get_global_rect()
	var header_rect: Rect2 = map.get_node("HeaderPanel").get_global_rect()
	var map_rect: Rect2 = map.marker_layer.get_global_rect()
	_check(badge.visible and badge.text.begins_with("ITEM ×"), "BADGE %s: leftover is unreadable for %s" % [target_size, node_id])
	_check(map_rect.encloses(badge_rect), "BADGE %s: leftover left the rendered map for %s" % [target_size, node_id])
	_check(not badge_rect.intersects(header_rect), "BADGE %s: leftover overlaps HeaderPanel for %s" % [target_size, node_id])
	_check(badge_rect.position.y >= marker_rect.end.y - 0.5, "BADGE %s: leftover is not below its marker for %s" % [target_size, node_id])
	_check(absf(badge_rect.get_center().x - marker_rect.get_center().x) <= 1.0, "BADGE %s: leftover detached horizontally from %s" % [target_size, node_id])
	_check(badge_rect.size.x <= marker_rect.size.x and badge_rect.size.y >= 22.0, "BADGE %s: leftover pill geometry is invalid for %s" % [target_size, node_id])
	_check(badge.get_theme_font_size("font_size") >= 14, "BADGE %s: leftover type is too small for %s" % [target_size, node_id])
	_check(badge.get_theme_stylebox("normal") != null, "BADGE %s: leftover has no contrast pill for %s" % [target_size, node_id])
	_check(badge.mouse_filter == Control.MOUSE_FILTER_IGNORE, "BADGE %s: leftover intercepts marker input for %s" % [target_size, node_id])


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
	return scene


func _free_current_scene() -> void:
	if current_scene == null:
		return
	var old_scene: Node = current_scene
	current_scene = null
	old_scene.queue_free()
	await process_frame


func _defeat_all_enemies(battle: Variant) -> void:
	for unit: Variant in battle.enemy_units:
		unit.current_hp = 0
		unit.defeated = true


func _defeat_all_party(battle: Variant) -> void:
	for unit: Variant in battle.party_units:
		unit.current_hp = 0
		unit.defeated = true


func _test_item_definition(item_id: String, use_context: String) -> Dictionary:
	return {
		"id": item_id,
		"display_name": item_id.capitalize(),
		"use_context": use_context,
		"effect": {"type": "heal", "amount": 1},
	}


func _healing_herb_amount() -> int:
	return ItemCatalogModel.get_definition(HERB_ID)["effect"]["amount"]


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
