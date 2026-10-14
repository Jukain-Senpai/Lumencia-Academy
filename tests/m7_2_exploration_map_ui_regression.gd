extends SceneTree

const PROTOTYPE_SCENE_PATH := "res://scenes/exploration/m7_2_exploration_prototype.tscn"
const MAP_ASSET_PATH := "res://assets/art/backgrounds/lumencia_forest_exploration_map.png"
const DESIGN_PATH := "res://docs/M7_2_EXPLORATION_MAP_UI_DESIGN.md"
const EXPECTED_MAP_SHA256 := "68a53b944589b1414f1447d6726c2c8864897dacb08360e11a197992cf3681ce"
const MARKER_IDS := ["old_trail", "riverside_camp", "stone_crossing", "ruins_approach", "deep_grove"]

const INVALID_POSITION_CONTEXT := {
	"id": "m7_2_invalid_position",
	"display_name": "Invalid Position",
	"starting_node": "invalid_node",
	"nodes": [
		{
			"id": "invalid_node",
			"display_name": "Invalid Node",
			"map_position": Vector2(INF, 0.5),
			"connections": [],
			"initially_revealed": true,
			"reveal_on_complete": [],
			"reusable": false,
			"initial_roadblock": false,
		},
	],
}

var failures: Array[String] = []
var checks := 0
var state: Variant
var prototype_scene: Control
var map_controller: Variant


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1152, 648)
	root.content_scale_size = Vector2i(1152, 648)
	state = root.get_node("GameState").exploration_state
	state.clear_runtime()
	await _open_prototype_scene()
	if prototype_scene != null:
		_test_asset_and_initial_map()
		_test_defensive_read_boundaries()
		await _test_real_button_travel_and_stability()
		_test_progressive_reveal_and_multi_state()
		await _test_completed_traversal()
		_test_invalid_travel_ui()
		await _test_responsive_layout(Vector2i(1152, 648))
		await _test_responsive_layout(Vector2i(1440, 810))
		_test_invalid_context_handling()
	await _close_scene()
	state.clear_runtime()

	if failures.is_empty():
		print("M7.2 exploration map UI regression suite passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	push_error("M7.2 exploration map UI suite failed: %d failure(s), %d checks." % [failures.size(), checks])
	quit(1)


func _open_prototype_scene() -> void:
	var packed_scene: PackedScene = load(PROTOTYPE_SCENE_PATH)
	_check(packed_scene != null, "SCENE: prototype Exploration scene did not load")
	if packed_scene == null:
		return
	prototype_scene = packed_scene.instantiate()
	root.add_child(prototype_scene)
	await process_frame
	await process_frame
	map_controller = prototype_scene.get_node("ExplorationMap")
	_check(map_controller != null, "SCENE: reusable ExplorationMap is missing")


func _test_asset_and_initial_map() -> void:
	_check(FileAccess.file_exists(DESIGN_PATH), "ASSET: M7.2 design record is missing")
	_check(FileAccess.file_exists(MAP_ASSET_PATH), "ASSET: approved map is missing from final path")
	_check(FileAccess.get_sha256(MAP_ASSET_PATH) == EXPECTED_MAP_SHA256, "ASSET: approved map bytes changed")
	var map_texture: TextureRect = map_controller.get_node("MapFrame/MapTexture")
	_check(map_texture.texture != null, "INITIAL: map background did not load")
	_check(map_texture.texture.get_size() == Vector2(2560, 1440), "INITIAL: map texture dimensions changed")
	_check(state.active_context_id == "m7_2_prototype_forest", "INITIAL: prototype context did not activate")
	_check(state.current_node_id == "old_trail", "INITIAL: Old Trail is not authoritative current location")
	_check(not map_controller.get_node("DiagnosticPanel").visible, "INITIAL: valid map shows diagnostic panel")
	_check(map_controller.get_node("MapFrame/MarkerLayer").visible, "INITIAL: marker layer is hidden")
	_check(map_controller.marker_buttons.size() == 4, "INITIAL: expected four revealed markers")
	for node_id: String in ["old_trail", "riverside_camp", "stone_crossing", "ruins_approach"]:
		var button: Button = _marker(node_id)
		_check(button != null and button.visible, "INITIAL: revealed marker %s is missing" % node_id)
		if button != null:
			var definition: Dictionary = state.get_node_definition(node_id)
			_check(button.text == definition["display_name"], "INITIAL: %s label is not authored data" % node_id)
	_check(_marker("deep_grove") == null, "INITIAL: hidden Deep Grove has a marker")
	_check(_marker("old_trail").get_meta("is_current"), "INITIAL: Old Trail lacks current presentation")
	_check(_marker("old_trail").get_node("CurrentTag").visible, "INITIAL: current tag is hidden")
	_check(_marker("old_trail").disabled, "INITIAL: current node incorrectly invites self-travel")
	_check(not _marker("riverside_camp").disabled, "INITIAL: connected Riverside Camp is not travelable")
	_check(_marker("stone_crossing").visible and _marker("stone_crossing").disabled, "INITIAL: revealed unreachable Stone Crossing presentation is wrong")
	_check(_marker("ruins_approach").visible and _marker("ruins_approach").disabled, "INITIAL: revealed unreachable Ruins Approach presentation is wrong")
	_check(state.completed_nodes.is_empty(), "INITIAL: rendering completed a node")
	_check(not map_controller.warning_preference_panel.visible and not map_controller.warning_overlay.visible, "INITIAL: M7.7 warning controls leaked into M7.2 prototype")
	_check(not map_controller.save_load_panel.visible, "INITIAL: M7.8 Save/Load controls leaked into M7.2 prototype")
	_check(_only_expected_map_buttons_exist(), "INITIAL: unexpected player-facing Button was added")


func _test_defensive_read_boundaries() -> void:
	var context_copy: Dictionary = state.get_active_context_definition()
	context_copy["display_name"] = "Mutated UI Copy"
	context_copy["nodes"][0]["connections"].clear()
	context_copy["nodes"][0]["map_position"] = Vector2.ZERO
	var fresh_context: Dictionary = state.get_active_context_definition()
	_check(fresh_context["display_name"] == "Prototype Forest", "READ API: context display name leaked through copy")
	_check(fresh_context["nodes"][0]["connections"] == ["riverside_camp"], "READ API: nested connections leaked through copy")
	_check(fresh_context["nodes"][0]["map_position"] == Vector2(0.17, 0.70), "READ API: nested position leaked through copy")
	var node_copy: Dictionary = state.get_node_definition("riverside_camp")
	node_copy["connections"].clear()
	_check(state.get_node_definition("riverside_camp")["connections"].size() == 3, "READ API: node definition was not a deep copy")


func _test_real_button_travel_and_stability() -> void:
	var old_button: Button = _marker("old_trail")
	var camp_button: Button = _marker("riverside_camp")
	var old_instance_id := old_button.get_instance_id()
	var camp_instance_id := camp_button.get_instance_id()
	camp_button.grab_focus()
	await process_frame
	_check(camp_button.has_focus(), "CLICK: reachable marker could not receive keyboard focus")
	camp_button.emit_signal("pressed")
	await process_frame
	_check(state.current_node_id == "riverside_camp", "CLICK: Button activation did not travel through ExplorationState")
	_check(_marker("riverside_camp").get_instance_id() == camp_instance_id, "CLICK: destination marker was rebuilt after ordinary travel")
	_check(_marker("old_trail").get_instance_id() == old_instance_id, "CLICK: previous marker was rebuilt after ordinary travel")
	_check(_marker("riverside_camp").get_meta("is_current") and _marker("riverside_camp").get_node("CurrentTag").visible, "CLICK: current presentation did not move to Riverside Camp")
	_check(not _marker("old_trail").get_meta("is_current") and not _marker("old_trail").get_node("CurrentTag").visible, "CLICK: previous node remained visually current")
	_check(not _marker("old_trail").disabled, "CLICK: Old Trail did not become reachable for return travel")
	_check(not _marker("stone_crossing").disabled, "CLICK: Stone Crossing reachability did not refresh")
	_check(_marker("ruins_approach").disabled, "CLICK: disconnected Ruins Approach became travelable")
	_check(not state.is_node_completed("riverside_camp"), "CLICK: travel completed Riverside Camp")


func _test_progressive_reveal_and_multi_state() -> void:
	var stable_instance_ids: Dictionary = {}
	for node_id: String in ["old_trail", "riverside_camp", "stone_crossing", "ruins_approach"]:
		stable_instance_ids[node_id] = _marker(node_id).get_instance_id()
	_check(state.complete_primary_content("riverside_camp"), "REVEAL: M7.1 completion call failed")
	_check(map_controller.refresh_map(), "REVEAL: valid map refresh failed")
	var deep_grove: Button = _marker("deep_grove")
	_check(deep_grove != null and deep_grove.visible, "REVEAL: Deep Grove marker did not appear")
	_check(deep_grove != null and not deep_grove.disabled, "REVEAL: connected Deep Grove did not become travelable")
	for node_id: String in stable_instance_ids:
		_check(_marker(node_id).get_instance_id() == stable_instance_ids[node_id], "REVEAL: unchanged marker %s was rebuilt" % node_id)
	var camp: Button = _marker("riverside_camp")
	_check(camp.get_meta("is_current"), "MULTI-STATE: Riverside Camp lost current presentation")
	_check(camp.get_meta("is_completed") and camp.get_node("CompletedBadge").visible, "MULTI-STATE: completed presentation is missing")
	_check(camp.get_meta("is_roadblocked") and camp.get_node("RoadblockBadge").visible, "MULTI-STATE: roadblock presentation is missing")
	_check(camp.get_meta("is_reusable") and camp.get_node("ReusableBadge").visible, "MULTI-STATE: reusable presentation is missing")
	_check(camp.get_node("CurrentTag").visible, "MULTI-STATE: current layer was overwritten")
	_check(state.is_node_completed("riverside_camp") and state.is_node_roadblocked("riverside_camp") and state.is_node_reusable("riverside_camp"), "MULTI-STATE: UI refresh corrupted authoritative facts")


func _test_completed_traversal() -> void:
	var camp_instance_id := _marker("riverside_camp").get_instance_id()
	_marker("old_trail").emit_signal("pressed")
	await process_frame
	_check(state.current_node_id == "old_trail", "COMPLETED: return to Old Trail failed")
	var completed_camp: Button = _marker("riverside_camp")
	_check(completed_camp.get_meta("is_completed"), "COMPLETED: completed visual did not persist away from node")
	_check(not completed_camp.disabled and completed_camp.get_meta("is_reachable"), "COMPLETED: completed connected node became untravelable")
	var completion_before: Dictionary = state.completed_nodes.duplicate(true)
	var reveal_before: Dictionary = state.revealed_nodes.duplicate(true)
	completed_camp.emit_signal("pressed")
	await process_frame
	_check(state.current_node_id == "riverside_camp", "COMPLETED: travel back to completed node failed")
	_check(state.is_node_completed("riverside_camp"), "COMPLETED: revisit reset completion")
	_check(state.completed_nodes == completion_before and state.revealed_nodes == reveal_before, "COMPLETED: travel replayed completion/reveal content")
	_check(_marker("riverside_camp").get_instance_id() == camp_instance_id, "COMPLETED: revisit rebuilt the marker")


func _test_invalid_travel_ui() -> void:
	var ruins: Button = _marker("ruins_approach")
	var before: String = state.current_node_id
	_check(ruins.visible and ruins.disabled and not ruins.get_meta("is_reachable"), "INVALID: known disconnected marker is not visible-disabled")
	ruins.emit_signal("pressed")
	_check(state.current_node_id == before, "INVALID: disconnected marker teleported the player")
	_check(not map_controller.get_node("DiagnosticPanel").visible, "INVALID: expected travel rejection showed configuration diagnostic")
	map_controller._on_marker_pressed("missing_marker_node")
	_check(state.current_node_id == before, "INVALID: unknown marker changed current location")
	_check(map_controller.get_node("DiagnosticPanel").visible, "INVALID: broken marker invariant did not show diagnostic")
	_check(map_controller.refresh_map(), "INVALID: valid refresh did not recover from diagnostic")
	_check(not map_controller.get_node("DiagnosticPanel").visible, "INVALID: diagnostic did not clear after valid refresh")


func _test_responsive_layout(target_size: Vector2i) -> void:
	root.size = target_size
	root.content_scale_size = target_size
	await process_frame
	await process_frame
	_check(map_controller.refresh_map(), "LAYOUT %s: refresh failed" % target_size)
	var marker_layer: Control = map_controller.get_node("MapFrame/MarkerLayer")
	var map_texture: TextureRect = map_controller.get_node("MapFrame/MapTexture")
	_check(marker_layer.visible and map_texture.visible and map_texture.texture != null, "LAYOUT %s: background or markers are hidden" % target_size)
	_check(
		marker_layer.size.is_equal_approx(Vector2(target_size)),
		"LAYOUT %s: marker layer %s does not match rendered 16:9 map (texture %s, root %s, content scale %s)"
		% [target_size, marker_layer.size, map_texture.size, root.size, root.content_scale_size]
	)
	var layer_bounds := Rect2(Vector2.ZERO, marker_layer.size)
	var buttons: Array[Button] = []
	for node_id: String in MARKER_IDS:
		var button: Button = _marker(node_id)
		_check(button != null and not button.text.is_empty(), "LAYOUT %s: %s label is unreadable/missing" % [target_size, node_id])
		if button == null:
			continue
		buttons.append(button)
		var authored_position: Vector2 = state.get_node_definition(node_id)["map_position"]
		var actual_position := (button.position + button.size * 0.5) / marker_layer.size
		_check(actual_position.distance_to(authored_position) < 0.001, "LAYOUT %s: %s drifted from normalized position" % [target_size, node_id])
		_check(layer_bounds.encloses(button.get_rect()), "LAYOUT %s: %s left the rendered map" % [target_size, node_id])
	var header_rect: Rect2 = map_controller.get_node("HeaderPanel").get_global_rect()
	var legend_rect: Rect2 = map_controller.get_node("LegendPanel").get_global_rect()
	for index: int in buttons.size():
		var marker_rect := buttons[index].get_global_rect()
		_check(not marker_rect.intersects(header_rect), "LAYOUT %s: marker overlaps header" % target_size)
		_check(not marker_rect.intersects(legend_rect), "LAYOUT %s: marker overlaps legend" % target_size)
		for other_index: int in range(index + 1, buttons.size()):
			_check(not marker_rect.intersects(buttons[other_index].get_global_rect()), "LAYOUT %s: markers overlap" % target_size)


func _test_invalid_context_handling() -> void:
	_check(state.define_context(INVALID_POSITION_CONTEXT), "DIAGNOSTIC: structurally valid test context was rejected")
	_check(state.activate_context("m7_2_invalid_position"), "DIAGNOSTIC: invalid-presentation context could not activate at state layer")
	_check(not map_controller.refresh_map(), "DIAGNOSTIC: infinite coordinate was accepted")
	_check(map_controller.get_node("DiagnosticPanel").visible, "DIAGNOSTIC: malformed presentation did not show diagnostic")
	_check("invalid normalized map position" in map_controller.get_node("DiagnosticPanel/Margin/DiagnosticLabel").text, "DIAGNOSTIC: malformed-position message is unclear")
	_check(not map_controller.get_node("MapFrame/MarkerLayer").visible, "DIAGNOSTIC: invalid map remains interactive")
	state.clear_runtime()
	_check(not map_controller.refresh_map(), "DIAGNOSTIC: empty context was accepted")
	_check(map_controller.get_node("DiagnosticPanel").visible, "DIAGNOSTIC: empty context did not show diagnostic")
	_check("No active Exploration context" in map_controller.get_node("DiagnosticPanel/Margin/DiagnosticLabel").text, "DIAGNOSTIC: empty-context message is unclear")


func _only_expected_map_buttons_exist() -> bool:
	var all_buttons: Array[Node] = prototype_scene.find_children("*", "Button", true, false)
	var expected_utility_buttons := [
		map_controller.get_node("PrimaryActionPanel/Margin/Content/ActionRow/PrimaryActionButton"),
		map_controller.get_node("PrimaryActionPanel/Margin/Content/ActionRow/ShopActionButton"),
		map_controller.get_node("PrimaryActionPanel/Margin/Content/HubRow/CampRestButton"),
		map_controller.get_node("PrimaryActionPanel/Margin/Content/HubRow/WaitButton"),
		map_controller.get_node("HeaderPanel/Margin/Header/InventoryButton"),
		map_controller.get_node("InventoryPanel/Margin/Content/HealingHerbButton"),
		map_controller.get_node("InventoryPanel/Margin/Content/InventoryBackButton"),
		map_controller.get_node("ShopPanel/Margin/Content/ShopBuyButton"),
		map_controller.get_node("ShopPanel/Margin/Content/ShopBackButton"),
		map_controller.get_node("WarningPreferencePanel/Margin/WarningPreferenceButton"),
		map_controller.get_node("WarningOverlay/WarningPanel/Margin/Content/Actions/WarningGoBackButton"),
		map_controller.get_node("WarningOverlay/WarningPanel/Margin/Content/Actions/WarningContinueButton"),
		map_controller.get_node("SaveLoadPanel/Margin/Content/Buttons/MapSaveButton"),
		map_controller.get_node("SaveLoadPanel/Margin/Content/Buttons/MapLoadButton"),
	]
	if all_buttons.size() != map_controller.marker_buttons.size() + expected_utility_buttons.size():
		return false
	for node: Node in all_buttons:
		if node in expected_utility_buttons:
			continue
		if not node.has_meta("node_id") or not MARKER_IDS.has(node.get_meta("node_id")):
			return false
	return true


func _marker(node_id: String) -> Button:
	return map_controller.get_marker_button(node_id)


func _close_scene() -> void:
	if prototype_scene == null:
		return
	prototype_scene.queue_free()
	await process_frame
	prototype_scene = null
	map_controller = null


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
