extends SceneTree

const CLASSROOM_PATH := "res://data/dialogue/vn_prototype_m1.json"
const HALLWAY_PATH := "res://data/dialogue/vn_hallway_m2_3.json"
const TEST_USER_DIR := "Lumencia Academy M2.4 Regression"
const TEST_SAVE_PATH := "user://lumencia_save.json"

var failures: Array[String] = []
var checks := 0
var save_signal_count := 0
var load_signal_count := 0
var new_run_signal_count := 0
var game_state: Node


func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", TEST_USER_DIR)
	call_deferred("_run")


func _run() -> void:
	game_state = root.get_node("GameState")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://"))
	_remove_test_save()
	await _test_early_save_and_load()
	await _test_choice_controls()
	await _test_load_from_choice()
	await _test_help_path_persistence()
	await _test_refusal_path_persistence()
	await _test_invalid_save_is_transactional()
	await _test_new_run_button_focus()
	_remove_test_save()

	if failures.is_empty():
		print("M2.4 save/load regression suite passed (%d checks)." % checks)
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	push_error("M2.4 save/load regression suite failed: %d failure(s), %d checks." % [failures.size(), checks])
	quit(1)


func _test_early_save_and_load() -> void:
	game_state.reset_state()
	var scene := await _new_scene()
	_check_utility_focus_modes(scene)
	await _advance_with_accept(scene, 2)
	_check(scene.current_node_id == "intro_03", "Test 1: expected intro_03 before Save")

	scene.save_button.pressed.connect(_count_save)
	scene.save_button.pressed.emit()
	_check(save_signal_count == 1, "Test 1: explicit Save should fire exactly once")
	var saved_text := _read_test_save_text()
	var saved_data: Dictionary = game_state.read_save_data()
	_check(saved_data.get("node") == "intro_03", "Test 1: Save did not snapshot intro_03")

	await _advance_with_accept(scene, 5)
	_check(scene.current_node_id == "classroom_choice", "Test 1: keyboard progression did not reach the choice")
	_check(_read_test_save_text() == saved_text, "Test 1: keyboard progression changed the save file")
	_check(save_signal_count == 1, "Test 1: ui_accept reactivated Save")

	scene.load_button.pressed.connect(_count_load)
	scene.load_button.pressed.emit()
	await process_frame
	_check(load_signal_count == 1, "Test 2: explicit Load should fire exactly once")
	_check_loaded_intro_03(scene, "Test 2")
	await process_frame
	await process_frame
	_check(scene.current_node_id == "intro_03", "Test 2: loaded node changed without input")
	await _advance_with_accept(scene, 1)
	_check(scene.current_node_id == "intro_04", "Test 2: first Enter did not reach intro_04")
	_check(scene.dialogue_text.text == "Yes.", "Test 2: first Enter did not show Hiruko's Yes line")
	_check(load_signal_count == 1, "Test 2: ui_accept reactivated Load after first advance")
	await _advance_with_accept(scene, 1)
	_check(scene.current_node_id == "intro_05", "Test 2: second Enter did not reach intro_05")
	_check(scene.dialogue_text.text == "That was thirty minutes ago.", "Test 2: second Enter showed the wrong line")
	_check(load_signal_count == 1, "Test 2: loaded dialogue snapped back")

	scene.load_button.pressed.emit()
	await process_frame
	await _advance_with_mouse(scene, 1)
	_check(scene.current_node_id == "intro_04", "Test 3: one mouse click did not advance exactly once")
	_check(load_signal_count == 2, "Test 3: mouse advancement reactivated Load")
	await _advance_with_mouse(scene, 1)
	_check(scene.current_node_id == "intro_05", "Test 3: second mouse click did not advance exactly once")
	_check(load_signal_count == 2, "Test 3: mouse progression retriggered Load")

	await _advance_to_choice(scene)
	await _select_focused_choice()
	_check(scene.current_node_id == "help_01", "Test 4: Help did not reach help_01")
	await _advance_with_accept(scene, 6)
	_check(scene.current_dialogue_path == HALLWAY_PATH, "Test 4: progression did not transition to hallway")
	_check(_read_test_save_text() == saved_text, "Test 4: choice/transition progression changed the save file")

	scene.save_button.pressed.emit()
	var overwritten_data: Dictionary = game_state.read_save_data()
	_check(save_signal_count == 2, "Test 5: deliberate overwrite should fire Save exactly once")
	_check(overwritten_data.get("sequence") == HALLWAY_PATH, "Test 5: overwrite saved the wrong sequence")
	_check(overwritten_data.get("node") == "hallway_intro", "Test 5: overwrite saved the wrong node")
	var overwritten_text := _read_test_save_text()
	await _advance_with_accept(scene, 1)
	_check(_read_test_save_text() == overwritten_text, "Test 5: progression changed the overwritten save")
	_free_scene(scene)


func _test_choice_controls() -> void:
	game_state.reset_state()
	var help_scene := await _new_scene()
	await _advance_to_choice(help_scene)
	_check(help_scene.save_button.disabled, "Test 6A: Save was enabled at the choice")
	_check(root.gui_get_focus_owner() == help_scene.option_a_button, "Test 6A: Option A did not receive focus")
	await _select_focused_choice()
	_check(help_scene.current_node_id == "help_01", "Test 6A: keyboard selection did not choose Option A")
	_check(game_state.get_flag("helped_hiruko"), "Test 6A: Help flag was not set")
	_check(game_state.get_bond("hiruko") == 1, "Test 6A: Help Bond was not exactly 1")
	_check(root.gui_get_focus_owner() == null, "Test 6A: stale choice focus remained after selection")
	await _advance_with_accept(help_scene, 1)
	_check(game_state.get_bond("hiruko") == 1, "Test 6A: later ui_accept duplicated the choice effect")
	_free_scene(help_scene)

	game_state.reset_state()
	var refusal_scene := await _new_scene()
	await _advance_to_choice(refusal_scene)
	refusal_scene.option_b_button.grab_focus()
	await _select_focused_choice()
	_check(refusal_scene.current_node_id == "support_01", "Test 6B: keyboard selection did not choose Option B")
	_check(not game_state.get_flag("helped_hiruko"), "Test 6B: refusal flag was not false")
	_check(game_state.get_bond("hiruko") == 0, "Test 6B: refusal changed the Bond")
	_check(root.gui_get_focus_owner() == null, "Test 6B: stale choice focus remained after selection")
	_free_scene(refusal_scene)


func _test_load_from_choice() -> void:
	game_state.reset_state()
	var scene := await _new_scene()
	await _advance_with_accept(scene, 2)
	scene.save_button.pressed.emit()
	await _advance_to_choice(scene)
	_check(root.gui_get_focus_owner() == scene.option_a_button, "Test 7: choice focus was not established")
	scene.load_button.pressed.emit()
	await process_frame
	_check_loaded_intro_03(scene, "Test 7")
	_check(not scene.choice_panel.visible, "Test 7: choice UI remained visible after Load")
	_check(not scene.awaiting_choice, "Test 7: awaiting_choice remained true after Load")
	_check(root.gui_get_focus_owner() == null, "Test 7: hidden choice retained keyboard focus")
	await _advance_with_accept(scene, 1)
	_check(scene.current_node_id == "intro_04", "Test 7: keyboard progression failed after loading from choice")
	_check(game_state.get_bond("hiruko") == 0, "Test 7: hidden choice received later ui_accept")
	_free_scene(scene)


func _test_help_path_persistence() -> void:
	game_state.reset_state()
	var scene := await _new_scene()
	await _advance_to_choice(scene)
	await _select_focused_choice()
	scene.save_button.pressed.emit()
	_check(game_state.read_save_data().get("node") == "help_01", "Test 8: help_01 was not saved")
	_free_scene(scene)

	game_state.reset_state()
	var restored_scene := await _new_scene()
	restored_scene.load_button.pressed.emit()
	await process_frame
	_check(restored_scene.current_node_id == "help_01", "Test 8: Load did not restore help_01")
	_check(game_state.get_flag("helped_hiruko"), "Test 8: helped_hiruko was not restored")
	_check(game_state.get_bond("hiruko") == 1, "Test 8: Bond was not restored to 1")
	await _advance_with_accept(restored_scene, 7)
	_check(restored_scene.current_dialogue_path == HALLWAY_PATH, "Test 8: hallway did not appear")
	_check(restored_scene.current_node_id == "helped_reaction", "Test 8: helped hallway response was not selected")
	_check(game_state.get_bond("hiruko") == 1, "Test 8: loading/progression duplicated the Bond effect")
	_free_scene(restored_scene)


func _test_refusal_path_persistence() -> void:
	game_state.reset_state()
	var scene := await _new_scene()
	await _advance_to_choice(scene)
	scene.option_b_button.grab_focus()
	await _select_focused_choice()
	scene.save_button.pressed.emit()
	_check(game_state.read_save_data().get("node") == "support_01", "Test 9: support_01 was not saved")
	_free_scene(scene)

	game_state.reset_state()
	var restored_scene := await _new_scene()
	restored_scene.load_button.pressed.emit()
	await process_frame
	_check(restored_scene.current_node_id == "support_01", "Test 9: Load did not restore support_01")
	_check(not game_state.get_flag("helped_hiruko"), "Test 9: refusal flag was not restored")
	_check(game_state.get_bond("hiruko") == 0, "Test 9: refusal Bond was not restored as 0")
	await _advance_with_accept(restored_scene, 7)
	_check(restored_scene.current_dialogue_path == HALLWAY_PATH, "Test 9: hallway did not appear")
	_check(restored_scene.current_node_id == "not_helped_reaction", "Test 9: refusal hallway response was not selected")
	_check(game_state.get_bond("hiruko") == 0, "Test 9: loading/progression introduced a Bond effect")
	_free_scene(restored_scene)


func _test_invalid_save_is_transactional() -> void:
	game_state.reset_state()
	game_state.set_flag("sentinel", true)
	game_state.adjust_bond("hiruko", 7)
	var scene := await _new_scene()
	await _advance_with_accept(scene, 1)
	var before_path: String = scene.current_dialogue_path
	var before_node: String = scene.current_node_id
	var before_text: String = scene.dialogue_text.text
	var file := FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	file.store_string("{ malformed")
	file.close()
	scene.load_button.pressed.emit()
	await process_frame
	_check(scene.current_dialogue_path == before_path, "Invalid save changed the active sequence")
	_check(scene.current_node_id == before_node, "Invalid save changed the current node")
	_check(scene.dialogue_text.text == before_text, "Invalid save changed visible dialogue")
	_check(game_state.get_flag("sentinel"), "Invalid save changed flags")
	_check(game_state.get_bond("hiruko") == 7, "Invalid save changed Bonds")
	_check(scene.save_status_label.text.begins_with("Load failed:"), "Invalid save did not show a visible error")
	_free_scene(scene)


func _test_new_run_button_focus() -> void:
	game_state.reset_state()
	var scene := await _new_scene()
	var callback := Callable(scene, "_start_new_run")
	if scene.new_run_button.pressed.is_connected(callback):
		scene.new_run_button.pressed.disconnect(callback)
	scene.new_run_button.pressed.connect(_count_new_run)
	scene.new_run_button.pressed.emit()
	_check(new_run_signal_count == 1, "New Run explicit activation should fire exactly once")
	await _advance_with_accept(scene, 1)
	_check(scene.current_node_id == "intro_02", "ui_accept did not advance after New Run utility activation")
	_check(new_run_signal_count == 1, "Later ui_accept reactivated New Run")
	_free_scene(scene)


func _new_scene() -> Control:
	var packed_scene: PackedScene = load("res://scenes/vn/vn_prototype.tscn")
	var scene: Control = packed_scene.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	return scene


func _free_scene(scene: Control) -> void:
	if current_scene == scene:
		current_scene = null
	scene.queue_free()
	await process_frame


func _advance_to_choice(scene: Control) -> void:
	while scene.current_node_id != "classroom_choice" and not scene.awaiting_choice:
		await _advance_with_accept(scene, 1)
	_check(scene.current_node_id == "classroom_choice", "Expected to reach classroom_choice")


func _advance_with_accept(_scene: Control, count: int) -> void:
	for _index in count:
		await _send_action("ui_accept", true)
		await _send_action("ui_accept", false)


func _select_focused_choice() -> void:
	await _send_action("ui_accept", true)
	await _send_action("ui_accept", false)


func _send_action(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame


func _advance_with_mouse(scene: Control, count: int) -> void:
	for _index in count:
		var pressed := InputEventMouseButton.new()
		pressed.button_index = MOUSE_BUTTON_LEFT
		pressed.pressed = true
		pressed.position = Vector2(2, 2)
		scene._unhandled_input(pressed)
		await process_frame
		var released := InputEventMouseButton.new()
		released.button_index = MOUSE_BUTTON_LEFT
		released.pressed = false
		released.position = Vector2(2, 2)
		scene._unhandled_input(released)
		await process_frame


func _check_loaded_intro_03(scene: Control, label: String) -> void:
	_check(scene.current_dialogue_path == CLASSROOM_PATH, "%s: wrong restored sequence" % label)
	_check(scene.current_node_id == "intro_03", "%s: wrong restored node" % label)
	_check(scene.speaker_name.text == "Jukain", "%s: wrong restored speaker" % label)
	_check(scene.dialogue_text.text == "She also said, \"I'll be back in five minutes.\"", "%s: wrong restored text" % label)
	_check(scene.jukain_sprite.texture == scene.CHARACTER_TEXTURES["Jukain"]["tired"], "%s: wrong restored expression" % label)
	_check(scene.story_background.texture == scene.sequence_background, "%s: wrong restored background" % label)
	_check(not scene.awaiting_choice, "%s: awaiting_choice was not cleared" % label)
	_check(not scene.choice_panel.visible, "%s: choice UI was not hidden" % label)


func _check_utility_focus_modes(scene: Control) -> void:
	_check(scene.save_button.focus_mode == Control.FOCUS_NONE, "Save utility button accepts keyboard focus")
	_check(scene.load_button.focus_mode == Control.FOCUS_NONE, "Load utility button accepts keyboard focus")
	_check(scene.new_run_button.focus_mode == Control.FOCUS_NONE, "New Run utility button accepts keyboard focus")


func _count_save() -> void:
	save_signal_count += 1


func _count_load() -> void:
	load_signal_count += 1


func _count_new_run() -> void:
	new_run_signal_count += 1


func _read_test_save_text() -> String:
	var file := FileAccess.open(TEST_SAVE_PATH, FileAccess.READ)
	return "" if file == null else file.get_as_text()


func _remove_test_save() -> void:
	var absolute_path := ProjectSettings.globalize_path(TEST_SAVE_PATH)
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
