extends SceneTree

const BattleUnitModel := preload("res://scripts/battle/battle_unit.gd")
const JukainCombatStateModel := preload("res://scripts/battle/jukain_combat_state.gd")
const JukainPrescriptStateModel := preload("res://scripts/battle/jukain_prescript_state.gd")
const VN_SCENE_PATH := "res://scenes/vn/vn_prototype.tscn"
const M6_ENTRY_PATH := "res://scenes/vn/m6_training_hall_entry.tscn"
const M6_DIALOGUE_PATH := "res://data/dialogue/m6_training_hall_prebattle.json"
const BATTLE_SCENE_PATH := "res://scenes/battle/battle_sandbox.tscn"
const BACKGROUND_PATH := "res://assets/art/backgrounds/academy_training_hall.png"
const EXPECTED_BACKGROUND_SHA256 := "eb942b4339a0fbe595e08a509aeec1d39cf7ebd9e05d5ac18f1561b8af2dca60"
const ENCOUNTER_ID := "m6_training_hall_prototype"
const RETURN_SEQUENCE := "m6_training_hall_postbattle"
const TEST_USER_DIR := "Lumencia Academy M6.2 Regression"
const TEST_SAVE_PATH := "user://lumencia_save.json"

const EXPECTED_LINES := [
	["Hiruko", "neutral", "We're supposed to clear the targets before the exercise ends."],
	["Jukain", "tired", "Straightforward. That's suspicious."],
	["Hiruko", "neutral", "It's training, Jukain."],
	["Jukain", "smirk", "That's usually when something decides to become complicated."],
	["Hiruko", "annoyed", "Just stay focused."],
	["Jukain", "smirk", "I'll treasure those words when this inevitably goes wrong."],
]

var failures: Array[String] = []
var checks := 0
var game_state: Node


func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", TEST_USER_DIR)
	call_deferred("_run")


func _run() -> void:
	game_state = root.get_node("GameState")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://"))
	_remove_test_save()
	await _test_data_assets_and_reused_controller()
	await _test_transient_context_save_boundary()
	await _test_real_vn_to_battle_path_and_double_guard()
	await _test_standalone_battle_fallback()
	await _test_layout_and_scope_boundaries()
	_remove_test_save()
	game_state.reset_state()

	if failures.is_empty():
		print("M6.2 VN-to-battle regression suite passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	push_error("M6.2 regression suite failed: %d failure(s), %d checks." % [failures.size(), checks])
	quit(1)


func _test_data_assets_and_reused_controller() -> void:
	_check(FileAccess.file_exists(M6_DIALOGUE_PATH), "DATA A: M6 dialogue file is missing")
	_check(FileAccess.file_exists(BACKGROUND_PATH), "ASSET A: canonical Training Hall background is missing")
	_check(not FileAccess.file_exists("res://assets/art/New folder/academy_training_hall.png"), "ASSET: temporary Training Hall path still exists")
	_check(_sha256(BACKGROUND_PATH) == EXPECTED_BACKGROUND_SHA256, "ASSET: Training Hall bytes changed during relocation")
	_check(ResourceLoader.exists(BACKGROUND_PATH), "ASSET B: Godot cannot resolve Training Hall background")
	var background: Resource = load(BACKGROUND_PATH)
	_check(background is Texture2D, "ASSET C: Training Hall did not import as Texture2D")

	var file := FileAccess.open(M6_DIALOGUE_PATH, FileAccess.READ)
	_check(file != null, "DATA A: dialogue file could not be opened")
	if file == null:
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	_check(typeof(data) == TYPE_DICTIONARY, "DATA A: dialogue root is not an object")
	if typeof(data) != TYPE_DICTIONARY:
		return
	_check(data.get("background") == BACKGROUND_PATH, "DATA C: dialogue references the wrong background")
	var nodes: Array = data.get("nodes", [])
	var lines: Array[Dictionary] = []
	var choices := 0
	var launch_nodes: Array[Dictionary] = []
	for raw_node: Variant in nodes:
		if typeof(raw_node) != TYPE_DICTIONARY:
			continue
		var node: Dictionary = raw_node
		match node.get("type", ""):
			"line":
				lines.append(node)
			"choice":
				choices += 1
			"start_battle":
				launch_nodes.append(node)
	_check(lines.size() == 6, "DATA B: M6 sequence does not contain exactly six lines")
	for index: int in mini(lines.size(), EXPECTED_LINES.size()):
		var expected: Array = EXPECTED_LINES[index]
		_check(lines[index].get("speaker") == expected[0], "DATA D–I: line %d speaker is wrong" % [index + 1])
		_check(lines[index].get("expression") == expected[1], "DATA D–I: line %d expression is wrong" % [index + 1])
		_check(lines[index].get("text") == expected[2], "DATA D–I: line %d text is wrong" % [index + 1])
	_check(choices == 0, "DATA K: M6 sequence contains a choice")
	_check(launch_nodes.size() == 1, "DATA J: sequence lacks exactly one explicit start_battle action")
	if launch_nodes.size() == 1:
		var launch: Dictionary = launch_nodes[0]
		_check(lines[5].get("next") == launch.get("id"), "DATA J: battle action is not after the final line")
		_check(launch.get("battle_scene") == BATTLE_SCENE_PATH, "DATA J: action targets the wrong battle scene")
		_check(launch.get("encounter_id") == ENCOUNTER_ID, "CONTEXT: action has wrong encounter_id")
		_check(launch.get("return_sequence") == RETURN_SEQUENCE, "CONTEXT: action has wrong return_sequence")
		_check(launch.keys().size() == 5, "CONTEXT: action contains unrelated launch state")

	game_state.reset_state()
	var scene := await _new_vn_scene(M6_ENTRY_PATH)
	if scene == null:
		return
	_check(scene.get_script().resource_path == "res://scripts/vn/vn_prototype.gd", "ENTRY: dedicated scene does not reuse the existing VN controller")
	_check(scene.initial_dialogue_path == M6_DIALOGUE_PATH, "ENTRY: dedicated scene did not configure the M6 sequence")
	_check(scene.dialogue_ready and scene.current_dialogue_path == M6_DIALOGUE_PATH, "DATA A: existing loader did not load M6 sequence")
	_check(scene.current_node_id == "training_01", "DATA A: M6 sequence did not start at training_01")
	_check(scene.sequence_background == background and scene.story_background.texture == background, "ASSET: existing background mechanism did not present Training Hall")
	_check(scene.CHARACTER_TEXTURES["Hiruko"].has("neutral") and scene.CHARACTER_TEXTURES["Hiruko"].has("annoyed"), "EXPRESSIONS: Hiruko mappings are missing")
	_check(scene.CHARACTER_TEXTURES["Jukain"].has("tired") and scene.CHARACTER_TEXTURES["Jukain"].has("smirk"), "EXPRESSIONS: Jukain mappings are missing")
	await _free_scene(scene)


func _test_transient_context_save_boundary() -> void:
	game_state.reset_state()
	_check(game_state.get_pending_battle_context().is_empty(), "CONTEXT A: context was not initially absent")
	_check(game_state.prepare_battle_context(ENCOUNTER_ID, RETURN_SEQUENCE), "CONTEXT B: valid context was not prepared")
	var context: Dictionary = game_state.get_pending_battle_context()
	_check(context == {"encounter_id": ENCOUNTER_ID, "return_sequence": RETURN_SEQUENCE}, "CONTEXT B: prepared context is incorrect")
	_check(context.keys().size() == 2, "CONTEXT: unrelated state was copied into battle context")
	context["encounter_id"] = "mutated_copy"
	_check(game_state.get_pending_battle_context()["encounter_id"] == ENCOUNTER_ID, "CONTEXT: caller mutated authoritative context through returned dictionary")
	_check(not game_state.prepare_battle_context("duplicate", "duplicate"), "DOUBLE: existing context was overwritten by a second preparation")
	_check(game_state.save_game(M6_DIALOGUE_PATH, "training_01"), "SAVE: pre-battle M6 line could not be saved")
	var file := FileAccess.open(TEST_SAVE_PATH, FileAccess.READ)
	_check(file != null, "SAVE: M6 save file could not be read")
	if file != null:
		var saved: Variant = JSON.parse_string(file.get_as_text())
		_check(typeof(saved) == TYPE_DICTIONARY, "SAVE: M6 save JSON is invalid")
		if typeof(saved) == TYPE_DICTIONARY:
			_check(saved.keys().size() == 4, "SAVE: transient context changed the explicit save schema")
			_check(not saved.has("pending_battle_context") and not saved.has("encounter_id") and not saved.has("return_sequence"), "SAVE: transient battle context was serialized")
	game_state.clear_pending_battle_context()
	_check(game_state.get_pending_battle_context().is_empty(), "CONTEXT: explicit clear failed")


func _test_real_vn_to_battle_path_and_double_guard() -> void:
	game_state.reset_state()
	var scene := await _new_vn_scene(M6_ENTRY_PATH)
	if scene == null:
		return
	_check(game_state.get_pending_battle_context().is_empty(), "TRANSITION: context existed before final advance")
	for index: int in 5:
		var expected: Array = EXPECTED_LINES[index]
		_check(scene.speaker_name.text == expected[0] and scene.dialogue_text.text == expected[2], "TRANSITION: visible line %d is wrong" % [index + 1])
		await _advance_with_accept()
	_check(scene.current_node_id == "training_06", "TRANSITION: normal advance did not reach the final line")
	_check(scene.speaker_name.text == EXPECTED_LINES[5][0] and scene.dialogue_text.text == EXPECTED_LINES[5][2], "TRANSITION: final line was not visible before launch")

	var rapid_advance := InputEventMouseButton.new()
	rapid_advance.button_index = MOUSE_BUTTON_LEFT
	rapid_advance.pressed = true
	rapid_advance.position = Vector2(2, 2)
	scene._unhandled_input(rapid_advance)
	var context_after_first: Dictionary = game_state.get_pending_battle_context()
	scene._unhandled_input(rapid_advance)
	_check(scene.battle_launch_committed, "DOUBLE: first final-line activation did not commit launch")
	_check(game_state.get_pending_battle_context() == context_after_first, "DOUBLE: repeated final activation changed context")
	_check(context_after_first == {"encounter_id": ENCOUNTER_ID, "return_sequence": RETURN_SEQUENCE}, "TRANSITION: launch prepared wrong context")
	await process_frame
	await process_frame
	var battle: Control = current_scene
	_check(battle != null and battle.name == "BattleSandbox", "TRANSITION: real VN action did not load existing battle scene")
	if battle == null or battle.name != "BattleSandbox":
		return
	_check(battle.battle_context == context_after_first, "INTEGRATED: battle did not receive launch context")
	_check(battle.party_units.size() == 6 and battle.enemy_units.size() == 4 and battle.turn_queue.size() == 10, "INTEGRATED: proven combat fixture/queue changed")
	_check(battle.jukain_state.get_state() == JukainCombatStateModel.State.LOCKED, "INTEGRATED: Jukain did not start Locked")
	_check(battle.jukain_unit.atk == 9 and battle.jukain_state.get_effective_atk(9) == 1, "INTEGRATED: Jukain real/effective ATK changed")
	_check(battle.jukain_state.blessing_stacks == 0 and battle.jukain_prescript.karma_stacks == 0, "INTEGRATED: Blessing or Karma did not start at 0")
	_check(battle.jukain_prescript.phase == JukainPrescriptStateModel.Phase.ORIGINAL_ACTIVE, "INTEGRATED: Prescript was not fresh")
	_check(battle.jukain_state.get_state() == JukainCombatStateModel.State.LOCKED and battle.jukain_chain_slots.is_empty(), "INTEGRATED: Form Chain was available initially")
	_check(battle.hiruko_unit.current_hp == 44 and battle.hiruko_state.get_state_label() == "SEALED", "INTEGRATED: Hiruko M4 initial state changed")

	battle.restart_battle()
	_check(battle.battle_context == context_after_first and game_state.get_pending_battle_context() == context_after_first, "RESTART: integrated context was not preserved")
	_check(battle.jukain_state.get_state() == JukainCombatStateModel.State.LOCKED and battle.jukain_state.blessing_stacks == 0 and battle.jukain_prescript.karma_stacks == 0, "RESTART: integrated combat state did not reset")
	_check(battle.jukain_prescript.phase == JukainPrescriptStateModel.Phase.ORIGINAL_ACTIVE and battle.jukain_chain_slots.is_empty(), "RESTART: Prescript/chain state did not reset")

	_set_current(battle, battle.jukain_unit)
	_check(battle._process_jukain_turn_start() == &"activated", "M6.1: integrated Prescript did not activate")
	var hiruko_hp_before: int = battle.hiruko_unit.current_hp
	_check(battle.begin_attack_selection() and battle.select_attack_target(&"party_1") and battle.confirm_ally_attack(), "M6.1: integrated Obey action failed")
	_check(hiruko_hp_before - battle.hiruko_unit.current_hp == 1, "M6.1: integrated Obey hit was boosted")
	_check(battle.jukain_prescript.phase == JukainPrescriptStateModel.Phase.RESOLVED_OBEY and battle.jukain_state.blessing_stacks == 1, "M6.1: integrated Obey did not grant Blessing after resolution")

	for enemy: BattleUnit in battle.enemy_units:
		_defeat(enemy)
	_check(battle._check_battle_result() and battle.battle_result == battle.BattleResult.VICTORY, "NO RETURN: integrated Victory did not retain terminal battle behavior")
	await process_frame
	_check(current_scene == battle and current_scene.name == "BattleSandbox", "NO RETURN: Victory incorrectly returned to VN")
	_check(game_state.get_bond("hiruko") == 0, "SCOPE: integrated Victory changed Hiruko Bond")
	await _free_scene(battle)


func _test_standalone_battle_fallback() -> void:
	game_state.reset_state()
	var packed: PackedScene = load(BATTLE_SCENE_PATH)
	_check(packed != null, "STANDALONE: battle scene did not load")
	if packed == null:
		return
	var battle: Control = packed.instantiate()
	battle.automatic_enemy_turns_enabled = false
	root.add_child(battle)
	current_scene = battle
	await process_frame
	_check(battle.battle_context.is_empty(), "STANDALONE: battle unexpectedly required/received context")
	_check(battle.jukain_state.get_state() == JukainCombatStateModel.State.LOCKED and battle.jukain_state.blessing_stacks == 0 and battle.jukain_prescript.karma_stacks == 0, "STANDALONE: initial Jukain state changed")
	_check(battle.jukain_prescript.phase == JukainPrescriptStateModel.Phase.ORIGINAL_ACTIVE and battle.hiruko_state.get_state_label() == "SEALED", "STANDALONE: Prescript/Hiruko initialization changed")
	_check(battle.turn_queue.size() == 10 and battle.current_unit != null, "STANDALONE: combat did not begin normally")
	battle.restart_battle()
	_check(battle.battle_context.is_empty() and game_state.get_pending_battle_context().is_empty(), "STANDALONE: Restart invented context")
	await _free_scene(battle)

	var vn := await _new_vn_scene(VN_SCENE_PATH)
	if vn != null:
		_check(vn.dialogue_ready and vn.current_dialogue_path == vn.INITIAL_DIALOGUE_PATH, "STANDALONE VN: existing prototype now requires battle context")
		_check(game_state.get_pending_battle_context().is_empty(), "STANDALONE VN: controller invented battle context")
		await _free_scene(vn)


func _test_layout_and_scope_boundaries() -> void:
	game_state.reset_state()
	var scene := await _new_vn_scene(M6_ENTRY_PATH)
	if scene == null:
		return
	root.size = Vector2i(1152, 648)
	scene.set_deferred("size", Vector2(root.size))
	await process_frame
	_check(scene.story_background.get_global_rect().size == Vector2(1152, 648), "LAYOUT: Training Hall does not fill 1152×648 viewport")
	_check(_inside_viewport(scene.dialogue_panel, Vector2(1152, 648)), "LAYOUT: dialogue panel clips at 1152×648")
	_check(_inside_viewport(scene.speaker_name, Vector2(1152, 648)) and _inside_viewport(scene.dialogue_text, Vector2(1152, 648)), "LAYOUT: speaker/dialogue is unreadable at 1152×648")
	_check(_inside_viewport(scene.jukain_sprite, Vector2(1152, 648)) and _inside_viewport(scene.hiruko_sprite, Vector2(1152, 648)), "LAYOUT: character presentation clips at 1152×648")
	await _free_scene(scene)
	root.size = Vector2i(1440, 810)
	scene = await _new_vn_scene(M6_ENTRY_PATH)
	if scene == null:
		return
	scene.set_deferred("size", Vector2(root.size))
	await process_frame
	_check(scene.story_background.get_global_rect().size == Vector2(1440, 810), "LAYOUT: Training Hall does not fill 1440×810 viewport")
	_check(_inside_viewport(scene.dialogue_panel, Vector2(1440, 810)), "LAYOUT: dialogue panel clips at 1440×810")
	_check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/vn/vn_prototype.tscn", "SCOPE: M6.2 changed the main project scene")
	_check(not FileAccess.file_exists("res://scripts/battle/battle_result_contract.gd"), "SCOPE: M6.2 created a battle result contract")
	_check(not FileAccess.file_exists("res://data/dialogue/m6_training_hall_postbattle.json"), "SCOPE: M6.2 created post-battle VN data")
	_check(game_state.get_bond("hiruko") == 0, "SCOPE: M6.2 introduced a Bond consequence")
	await _free_scene(scene)


func _new_vn_scene(path: String) -> Control:
	var packed: PackedScene = load(path)
	_check(packed != null, "Could not load VN scene %s" % path)
	if packed == null:
		return null
	var scene: Control = packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	return scene


func _free_scene(scene: Control) -> void:
	if current_scene == scene:
		current_scene = null
	scene.queue_free()
	await process_frame


func _advance_with_accept() -> void:
	var pressed := InputEventAction.new()
	pressed.action = &"ui_accept"
	pressed.pressed = true
	Input.parse_input_event(pressed)
	await process_frame
	var released := InputEventAction.new()
	released.action = &"ui_accept"
	released.pressed = false
	Input.parse_input_event(released)
	await process_frame


func _set_current(scene: Control, unit: BattleUnit) -> void:
	scene.current_unit = unit
	scene.turn_index = scene.turn_queue.find(unit)
	scene.action_in_progress = false
	scene._clear_action_selection()
	scene._refresh_turn_ui()


func _defeat(unit: BattleUnit) -> void:
	unit.current_hp = 0
	unit.defeated = true


func _sha256(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(file.get_buffer(file.get_length()))
	return hashing.finish().hex_encode()


func _inside_viewport(control: Control, viewport_size: Vector2) -> bool:
	var rect := control.get_global_rect()
	return rect.position.x >= 0.0 and rect.position.y >= 0.0 and rect.end.x <= viewport_size.x and rect.end.y <= viewport_size.y


func _remove_test_save() -> void:
	var absolute_path := ProjectSettings.globalize_path(TEST_SAVE_PATH)
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
