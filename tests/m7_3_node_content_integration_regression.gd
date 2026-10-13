extends SceneTree

const ENTRY_SCENE_PATH := "res://scenes/exploration/m7_3_exploration_prototype.tscn"
const MAP_SCENE_PATH := "res://scenes/exploration/exploration_map.tscn"
const VN_SCENE_PATH := "res://scenes/vn/vn_prototype.tscn"
const BATTLE_SCENE_PATH := "res://scenes/battle/battle_sandbox.tscn"
const VN_DATA_PATH := "res://data/dialogue/m7_3_riverside_event.json"
const DESIGN_PATH := "res://docs/M7_3_NODE_CONTENT_INTEGRATION_DESIGN.md"
const GAME_STATE_PATH := "res://scripts/systems/game_state.gd"

const INVALID_CONTENT_CONTEXTS := [
	{
		"id": "m7_3_invalid_type",
		"content": {"type": "shop", "id": "not_supported"},
		"expected": "Unsupported primary content type",
	},
	{
		"id": "m7_3_missing_id",
		"content": {"type": "resource"},
		"expected": "no valid id",
	},
	{
		"id": "m7_3_unknown_vn",
		"content": {"type": "vn_event", "id": "missing_vn"},
		"expected": "cannot be resolved",
	},
	{
		"id": "m7_3_unknown_battle",
		"content": {"type": "battle", "id": "missing_battle"},
		"expected": "cannot be resolved",
	},
]

var failures: Array[String] = []
var checks := 0
var game_state: Node
var state: Variant


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1152, 648)
	root.content_scale_size = Vector2i(1152, 648)
	game_state = root.get_node("GameState")
	state = game_state.exploration_state
	_test_data_and_scope()
	await _test_vn_loop()
	await _test_battle_defeat_restart_victory_loop()
	await _test_standalone_battle()
	await _test_resource_loop()
	await _test_invalid_content()
	await _test_invalid_handoff_and_transient_boundary()

	await _free_current_scene()
	game_state.reset_state()
	if failures.is_empty():
		print("M7.3 node-content integration regression suite passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	push_error(
		"M7.3 node-content integration suite failed: %d failure(s), %d checks."
		% [failures.size(), checks]
	)
	quit(1)


func _test_data_and_scope() -> void:
	_check(FileAccess.file_exists(DESIGN_PATH), "DESIGN: M7.3 decision record is missing")
	_check(FileAccess.file_exists(VN_DATA_PATH), "DATA: Riverside VN sequence is missing")
	_check(ResourceLoader.exists(ENTRY_SCENE_PATH), "SCENE: M7.3 prototype entry is missing")
	_check(ResourceLoader.exists(MAP_SCENE_PATH), "SCENE: reusable map scene is missing")
	var file := FileAccess.open(VN_DATA_PATH, FileAccess.READ)
	_check(file != null, "DATA: Riverside VN sequence could not be opened")
	if file != null:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		_check(typeof(parsed) == TYPE_DICTIONARY, "DATA: Riverside VN root is invalid")
		if typeof(parsed) == TYPE_DICTIONARY:
			var nodes: Array = parsed.get("nodes", [])
			_check(nodes.size() == 4, "DATA: Riverside VN is not the locked three-line event")
			_check(nodes[3].get("type") == "return_to_exploration", "DATA: VN lacks explicit Exploration return")
			_check(nodes[3].get("content_id") == "m7_3_riverside_event", "DATA: VN return targets wrong content")
	_check(_object_has_property(game_state, "inventory_state"), "SCOPE: M7.4 shared InventoryState is missing")
	_check(not _object_has_property(game_state, "time"), "SCOPE: time state was introduced early")


func _test_vn_loop() -> void:
	var map: Variant = await _fresh_map()
	if map == null:
		return
	_check(state.current_node_id == "old_trail", "VN: prototype did not start at Old Trail")
	_check(not map.primary_action_panel.visible, "VN: Old Trail incorrectly exposes Interact")
	_press_marker(map, "riverside_camp")
	await process_frame
	_check(state.current_node_id == "riverside_camp", "VN: travel did not reach Riverside Camp")
	_check(not state.is_node_completed("riverside_camp"), "VN: travel consumed Riverside content")
	_check(not state.is_node_revealed("deep_grove"), "VN: travel revealed Deep Grove")
	_check(map.primary_action_panel.visible and map.primary_action_button.visible, "VN: current-node action is missing")
	_check(map.primary_action_button.text == "Interact", "VN: action label changed from the narrow contract")

	var first_launch: bool = map.interact_with_current_node()
	var prepared_handoff: Dictionary = game_state.get_pending_exploration_content()
	var duplicate_launch: bool = map.interact_with_current_node()
	_check(first_launch, "VN: explicit Interact did not request VN")
	_check(not duplicate_launch, "VN: rapid duplicate activation was accepted")
	_check(prepared_handoff == {
		"context_id": "m7_2_prototype_forest",
		"node_id": "riverside_camp",
		"content_type": "vn_event",
		"content_id": "m7_3_riverside_event",
	}, "VN: transient handoff shape is wrong")
	_check(game_state.get_pending_vn_sequence() == "m7_3_riverside_event", "VN: sequence routing was not prepared")
	_check(not state.is_node_completed("riverside_camp"), "VN: launch completed the node early")
	await process_frame
	await process_frame
	var vn: Variant = current_scene
	_check(vn != null and vn.name == "VNPrototype", "VN: real VN scene did not load")
	if vn == null or vn.name != "VNPrototype":
		return
	_check(vn.current_dialogue_path == VN_DATA_PATH, "VN: wrong dialogue sequence loaded")
	_check(vn.current_node_id == "riverside_01", "VN: Riverside sequence started at wrong node")
	_check(not state.is_node_completed("riverside_camp"), "VN: content completed before terminal return")
	vn._advance_dialogue()
	vn._advance_dialogue()
	_check(vn.current_node_id == "riverside_03", "VN: neutral three-line sequence did not progress")
	vn._advance_dialogue()
	_check(state.is_node_completed("riverside_camp"), "VN: successful return did not complete Riverside Camp")
	_check(state.is_node_revealed("deep_grove"), "VN: authored reveal did not reveal Deep Grove")
	_check(game_state.get_pending_exploration_content().is_empty(), "VN: successful return retained handoff")
	await process_frame
	await process_frame
	map = _current_map()
	_check(map != null and current_scene.name == "ExplorationMap", "VN: return did not use reusable map scene")
	_check(state.active_context_id == "m7_2_prototype_forest", "VN: return lost active context")
	_check(state.current_node_id == "riverside_camp", "VN: return lost current location")
	_check(state.is_node_roadblocked("riverside_camp"), "VN: completion cleared roadblock fact")
	_check(state.is_node_reusable("riverside_camp"), "VN: completion cleared authored reusable fact")
	_check(map.get_marker_button("deep_grove") != null, "VN: revealed marker did not render after return")
	_check(not map.primary_action_panel.visible, "VN: completed content remains interactable")

	var completion_before: Dictionary = state.completed_nodes.duplicate(true)
	var reveal_before: Dictionary = state.revealed_nodes.duplicate(true)
	_press_marker(map, "old_trail")
	await process_frame
	_press_marker(map, "riverside_camp")
	await process_frame
	_check(state.current_node_id == "riverside_camp", "VN: completed node is not traversable")
	_check(not map.interact_with_current_node(), "VN: completed primary content replayed")
	_check(state.completed_nodes == completion_before and state.revealed_nodes == reveal_before, "VN: revisit replayed completion effects")


func _test_battle_defeat_restart_victory_loop() -> void:
	var map: Variant = await _fresh_map()
	if map == null:
		return
	await _travel_path(map, ["riverside_camp", "stone_crossing"])
	_check(state.current_node_id == "stone_crossing", "BATTLE: travel did not reach Stone Crossing")
	_check(not state.is_node_completed("stone_crossing"), "BATTLE: travel completed Stone Crossing")
	var first_launch: bool = map.interact_with_current_node()
	var handoff_before: Dictionary = game_state.get_pending_exploration_content()
	_check(first_launch and not map.interact_with_current_node(), "BATTLE: launch guard did not reject duplicate activation")
	_check(handoff_before.get("content_type") == "battle", "BATTLE: exploration handoff has wrong type")
	_check(not state.is_node_completed("stone_crossing"), "BATTLE: launch completed node early")
	await process_frame
	await process_frame
	var battle: Variant = current_scene
	_check(battle != null and battle.name == "BattleSandbox", "BATTLE: real battle scene did not load")
	if battle == null or battle.name != "BattleSandbox":
		return
	battle.automatic_enemy_turns_enabled = false
	_check(battle.battle_context.is_empty(), "BATTLE: Exploration polluted the M6 battle context")
	_check(game_state.get_pending_battle_context().is_empty(), "BATTLE: M6 context was invented")
	_defeat_all_party(battle)
	_check(battle._check_battle_result(), "BATTLE: real Defeat was not recognized")
	await process_frame
	_check(current_scene == battle, "BATTLE: Defeat returned to Exploration")
	_check(not state.is_node_completed("stone_crossing"), "BATTLE: Defeat completed node")
	_check(game_state.get_pending_exploration_content() == handoff_before, "BATTLE: Defeat discarded handoff")
	battle.restart_battle()
	_check(battle.battle_result == battle.BattleResult.NONE, "BATTLE: Restart did not reset terminal result")
	_check(game_state.get_pending_exploration_content() == handoff_before, "BATTLE: Restart discarded handoff")
	_check(battle.party_units.all(func(unit: Variant) -> bool: return unit.current_hp > 0 and not unit.defeated), "BATTLE: Restart did not rebuild party")
	_defeat_all_enemies(battle)
	_check(battle._check_battle_result(), "BATTLE: later real Victory was not recognized")
	_check(state.is_node_completed("stone_crossing"), "BATTLE: Victory did not complete Stone Crossing")
	_check(battle.battle_return_committed, "BATTLE: Victory return guard did not commit")
	_check(game_state.get_pending_exploration_content().is_empty(), "BATTLE: successful return retained handoff")
	await process_frame
	await process_frame
	map = _current_map()
	_check(map != null and current_scene.name == "ExplorationMap", "BATTLE: Victory did not return to reusable map")
	_check(state.active_context_id == "m7_2_prototype_forest", "BATTLE: return lost context")
	_check(state.current_node_id == "stone_crossing", "BATTLE: return lost current location")
	_check(not map.primary_action_panel.visible, "BATTLE: completed node remains interactable")


func _test_standalone_battle() -> void:
	game_state.reset_state()
	var battle: Variant = await _load_scene(BATTLE_SCENE_PATH)
	if battle == null:
		return
	battle.automatic_enemy_turns_enabled = false
	_defeat_all_enemies(battle)
	_check(battle._check_battle_result(), "STANDALONE: Victory was not recognized")
	await process_frame
	_check(current_scene == battle, "STANDALONE: battle invented an Exploration return")
	_check(battle.battle_result == battle.BattleResult.VICTORY, "STANDALONE: Victory terminal changed")
	_check(not battle.battle_return_committed, "STANDALONE: return guard committed without handoff")
	_check(game_state.get_pending_exploration_content().is_empty(), "STANDALONE: exploration handoff was invented")


func _test_resource_loop() -> void:
	var map: Variant = await _fresh_map()
	if map == null:
		return
	await _travel_path(map, ["riverside_camp", "stone_crossing", "ruins_approach"])
	_check(state.current_node_id == "ruins_approach", "RESOURCE: travel did not reach Ruins Approach")
	_check(not state.is_node_completed("ruins_approach"), "RESOURCE: travel consumed resource")
	var marker_before: int = map.get_marker_button("ruins_approach").get_instance_id()
	map.primary_action_button.emit_signal("pressed")
	await process_frame
	_check(state.is_node_completed("ruins_approach"), "RESOURCE: explicit interaction did not complete node")
	_check(map.primary_action_panel.visible, "RESOURCE: success feedback panel is missing")
	_check(map.primary_action_status.text == "Healing Herb ×2 collected.", "RESOURCE: success feedback changed")
	_check(not map.primary_action_button.visible, "RESOURCE: completed resource remains actionable")
	_check(map.get_marker_button("ruins_approach").get_instance_id() == marker_before, "RESOURCE: refresh rebuilt stable marker")
	var completed_before: Dictionary = state.completed_nodes.duplicate(true)
	_check(not map.interact_with_current_node(), "RESOURCE: second collection was accepted")
	_check(state.completed_nodes == completed_before, "RESOURCE: second interaction mutated completion")
	_check(game_state.get_pending_exploration_content().is_empty(), "RESOURCE: synchronous resolution retained handoff")
	_check(game_state.inventory_state.get_quantity("healing_herb") == 2, "RESOURCE: M7.4 item reward did not enter shared Inventory")
	_press_marker(map, "stone_crossing")
	await process_frame
	_press_marker(map, "ruins_approach")
	await process_frame
	_check(state.is_node_completed("ruins_approach"), "RESOURCE: revisit reset completion")
	_check(not map.primary_action_panel.visible, "RESOURCE: revisit offers collection again")


func _test_invalid_content() -> void:
	for fixture: Dictionary in INVALID_CONTENT_CONTEXTS:
		game_state.reset_state()
		var context := _single_node_context(fixture["id"], fixture["content"])
		_check(state.define_context(context), "INVALID: test context %s was rejected structurally" % fixture["id"])
		_check(state.activate_context(fixture["id"]), "INVALID: test context %s did not activate" % fixture["id"])
		var map: Variant = await _load_scene(MAP_SCENE_PATH)
		if map == null:
			continue
		var before: String = state.current_node_id
		_check(not map.interact_with_current_node(), "INVALID: %s content launched" % fixture["id"])
		_check(state.current_node_id == before, "INVALID: %s changed location" % fixture["id"])
		_check(not state.is_node_completed(before), "INVALID: %s completed node" % fixture["id"])
		_check(game_state.get_pending_exploration_content().is_empty(), "INVALID: %s retained handoff" % fixture["id"])
		_check(fixture["expected"] in map.primary_action_status.text, "INVALID: %s diagnostic is unclear" % fixture["id"])


func _test_invalid_handoff_and_transient_boundary() -> void:
	var map: Variant = await _fresh_map()
	if map == null:
		return
	_press_marker(map, "riverside_camp")
	await process_frame
	game_state.pending_exploration_content = {
		"context_id": "m7_2_prototype_forest",
		"node_id": "stone_crossing",
		"content_type": "vn_event",
		"content_id": "m7_3_riverside_event",
	}
	_check(not game_state.validate_pending_exploration_content("vn_event", "m7_3_riverside_event"), "HANDOFF: mismatched node validated")
	_check(not game_state.resolve_pending_exploration_content("vn_event", "m7_3_riverside_event"), "HANDOFF: mismatched node resolved")
	_check(not state.is_node_completed("riverside_camp") and not state.is_node_completed("stone_crossing"), "HANDOFF: mismatch completed a node")
	game_state.clear_pending_exploration_content()
	_check(game_state.prepare_exploration_content("vn_event", "m7_3_riverside_event"), "HANDOFF: valid handoff could not prepare")
	var copy: Dictionary = game_state.get_pending_exploration_content()
	copy["node_id"] = "mutated_copy"
	_check(game_state.get_pending_exploration_content().get("node_id") == "riverside_camp", "HANDOFF: getter leaked mutable state")
	var game_state_source := FileAccess.open(GAME_STATE_PATH, FileAccess.READ)
	_check(game_state_source != null, "SAVE: GameState source could not be inspected")
	if game_state_source != null:
		var source_text := game_state_source.get_as_text()
		var save_start := source_text.find("var save_data := {")
		var save_end := source_text.find("var file := FileAccess.open", save_start)
		var save_payload := source_text.substr(save_start, save_end - save_start)
		_check(save_start >= 0 and save_end > save_start, "SAVE: explicit payload boundary changed unexpectedly")
		_check(save_payload.contains("\"sequence\"") and save_payload.contains("\"node\"") and save_payload.contains("\"flags\"") and save_payload.contains("\"bonds\""), "SAVE: original four fields are missing")
		_check(not save_payload.contains("pending_exploration_content"), "SAVE: transient handoff entered save payload")
	game_state.reset_state()
	_check(game_state.get_pending_exploration_content().is_empty(), "RESET: exploration handoff survived reset")
	_check(not state.has_active_context(), "RESET: transient Exploration runtime survived reset")


func _fresh_map() -> Variant:
	game_state.reset_state()
	var scene: Variant = await _load_scene(ENTRY_SCENE_PATH)
	if scene == null:
		return null
	var map: Variant = scene.get_node_or_null("ExplorationMap")
	_check(map != null, "MAP: prototype wrapper lacks reusable map")
	return map


func _current_map() -> Variant:
	if current_scene == null:
		return null
	if current_scene.has_method("get_marker_button"):
		return current_scene
	return current_scene.get_node_or_null("ExplorationMap")


func _travel_path(map: Variant, node_ids: Array) -> void:
	for raw_node_id: Variant in node_ids:
		_press_marker(map, String(raw_node_id))
		await process_frame


func _press_marker(map: Variant, node_id: String) -> void:
	var marker: Button = map.get_marker_button(node_id)
	_check(marker != null, "TRAVEL: marker %s is missing" % node_id)
	if marker != null:
		marker.emit_signal("pressed")


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


func _single_node_context(context_id: String, content: Dictionary) -> Dictionary:
	return {
		"id": context_id,
		"display_name": "Invalid Content Test",
		"starting_node": "test_node",
		"nodes": [
			{
				"id": "test_node",
				"display_name": "Test Node",
				"map_position": Vector2(0.5, 0.5),
				"connections": [],
				"initially_revealed": true,
				"reveal_on_complete": [],
				"reusable": false,
				"initial_roadblock": false,
				"primary_content": content.duplicate(true),
			},
		],
	}


func _object_has_property(object: Object, property_name: String) -> bool:
	for property: Dictionary in object.get_property_list():
		if property.get("name") == property_name:
			return true
	return false


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
