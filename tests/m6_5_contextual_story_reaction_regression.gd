extends SceneTree

const VN_SCENE_PATH := "res://scenes/vn/vn_prototype.tscn"
const POSTBATTLE_PATH := "res://data/dialogue/m6_training_hall_postbattle.json"
const BACKGROUND_PATH := "res://assets/art/backgrounds/academy_training_hall.png"
const ENCOUNTER_ID := "m6_training_hall_prototype"
const PRESCRIPT_ID := "prototype_hiruko_hp"
const RETURN_SEQUENCE := "m6_training_hall_postbattle"
const FALLBACK_TEXT := "[Prototype] No valid post-battle reaction was available."
const TEST_USER_DIR := "Lumencia Academy M6.5 Regression"
const TEST_SAVE_PATH := "user://lumencia_save.json"

const SHARED_LINES := [
	["Jukain", "tired", "Can we agree that was more complicated than advertised?"],
	["Hiruko", "neutral", "We're done. That's enough for me."],
	["Jukain", "smirk", "Finally, something we agree on."],
]
const REACTIONS := [
	{
		"route": "OBEY",
		"condition_id": "check_direct_hit",
		"required_fact": "jukain_attacked_hiruko",
		"start": "obey_01",
		"delta": -1,
		"lines": [
			["Hiruko", "annoyed", "You really hit me because that thing told you to."],
			["Jukain", "tired", "In my defense, it was extremely specific."],
			["Hiruko", "annoyed", "That's your defense?"],
			["Jukain", "smirk", "It's not a particularly strong one."],
		],
	},
	{
		"route": "EXPLOIT",
		"condition_id": "check_enemy_hit",
		"required_fact": "hiruko_damaged_by_enemy",
		"start": "exploit_01",
		"delta": -1,
		"lines": [
			["Hiruko", "annoyed", "You moved out of the way on purpose."],
			["Jukain", "smirk", "Technically, I never touched you."],
			["Hiruko", "annoyed", "You used me as a loophole."],
			["Jukain", "tired", "It sounded better in my head."],
		],
	},
	{
		"route": "DEFY",
		"condition_id": "check_replacement",
		"required_fact": "replacement_requirement_completed",
		"start": "defy_01",
		"delta": 1,
		"lines": [
			["Hiruko", "neutral", "You could've used me to clear the first Prescript."],
			["Jukain", "tired", "I noticed."],
			["Hiruko", "neutral", "So you let it punish you instead."],
			["Jukain", "tired", "I disliked its first suggestion."],
			["Hiruko", "faint_smile", "...Idiot."],
		],
	},
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
	await _test_data_graph_and_narrow_schema()
	await _test_valid_reactions_and_shared_reconvergence()
	await _test_multiple_facts_preserve_resolved_route()
	await _test_invalid_result_fallbacks()
	await _test_instance_local_duplicate_protection_and_save_boundary()
	await _test_layout_and_scope()
	_remove_test_save()
	game_state.reset_state()

	if failures.is_empty():
		print("M6.5 contextual story reaction regression suite passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	push_error("M6.5 regression suite failed: %d failure(s), %d checks." % [failures.size(), checks])
	quit(1)


func _test_data_graph_and_narrow_schema() -> void:
	_check(FileAccess.file_exists(POSTBATTLE_PATH), "DATA: post-battle sequence is missing")
	var file := FileAccess.open(POSTBATTLE_PATH, FileAccess.READ)
	_check(file != null, "DATA: post-battle sequence could not be opened")
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	_check(typeof(parsed) == TYPE_DICTIONARY, "DATA: post-battle root is not an object")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed
	_check(data.get("background") == BACKGROUND_PATH, "DATA: Training Hall background changed")
	_check(data.get("start") == "check_direct_hit", "DATA: reaction chain does not start with direct-hit validation")
	var nodes: Array = data.get("nodes", [])
	var nodes_by_id: Dictionary = {}
	for raw_node: Variant in nodes:
		_check(typeof(raw_node) == TYPE_DICTIONARY, "DATA: dialogue node is not an object")
		if typeof(raw_node) == TYPE_DICTIONARY:
			nodes_by_id[raw_node.get("id", "")] = raw_node
	_check(nodes_by_id.size() == 21, "DATA: expected post-battle graph size changed")

	var expected_false_targets := ["check_enemy_hit", "check_replacement", "reaction_fallback"]
	for index: int in REACTIONS.size():
		var reaction: Dictionary = REACTIONS[index]
		var node: Dictionary = nodes_by_id.get(reaction["condition_id"], {})
		_check(not node.is_empty(), "DATA: missing condition %s" % reaction["condition_id"])
		var condition: Dictionary = node.get("condition", {})
		_check(condition.keys().size() == 6, "DATA: condition %s has extra query fields" % reaction["condition_id"])
		_check(condition.get("type") == "battle_result_matches", "DATA: condition does not use the narrow result matcher")
		_check(condition.get("outcome") == "VICTORY", "DATA: condition outcome is not Victory")
		_check(condition.get("encounter_id") == ENCOUNTER_ID, "DATA: condition encounter identity changed")
		_check(condition.get("prescript_id") == PRESCRIPT_ID, "DATA: condition Prescript identity changed")
		_check(condition.get("prescript_route") == reaction["route"], "DATA: condition route is wrong")
		_check(condition.get("required_fact") == reaction["required_fact"], "DATA: condition fact is wrong")
		_check(node.get("true_target") == reaction["start"], "DATA: condition targets the wrong dialogue branch")
		_check(node.get("false_target") == expected_false_targets[index], "DATA: condition chain order changed")
		var effects: Array = node.get("effects", [])
		_check(effects.size() == 1, "DATA: reaction does not own exactly one effect")
		if effects.size() == 1:
			var effect: Dictionary = effects[0]
			_check(effect.get("type") == "adjust_bond" and effect.get("bond") == "hiruko" and int(effect.get("amount")) == int(reaction["delta"]), "DATA: contextual Bond effect is wrong")

	for reaction: Dictionary in REACTIONS:
		var lines: Array = reaction["lines"]
		for index: int in lines.size():
			var node_id := "%s_%02d" % [String(reaction["route"]).to_lower(), index + 1]
			var node: Dictionary = nodes_by_id.get(node_id, {})
			var expected: Array = lines[index]
			_check(node.get("speaker") == expected[0], "DATA: %s speaker is wrong" % node_id)
			_check(node.get("expression") == expected[1], "DATA: %s expression is wrong" % node_id)
			_check(node.get("text") == expected[2], "DATA: %s text is wrong" % node_id)

	for index: int in SHARED_LINES.size():
		var node_id := "shared_%02d" % [index + 1]
		var node: Dictionary = nodes_by_id.get(node_id, {})
		var expected: Array = SHARED_LINES[index]
		_check(node.get("speaker") == expected[0] and node.get("expression") == expected[1] and node.get("text") == expected[2], "DATA: shared line %d is wrong" % [index + 1])
	_check(nodes_by_id.get("obey_04", {}).get("next") == "shared_01", "DATA: Obey does not reconverge")
	_check(nodes_by_id.get("exploit_04", {}).get("next") == "shared_01", "DATA: Exploit does not reconverge")
	_check(nodes_by_id.get("defy_05", {}).get("next") == "shared_01", "DATA: Defy does not reconverge")
	_check(nodes_by_id.get("reaction_fallback", {}).get("text") == FALLBACK_TEXT, "DATA: neutral fallback content changed")
	var serialized := JSON.stringify(data)
	_check(not serialized.contains("[Prototype] Returned from battle."), "DATA: M6.4 placeholder remains")
	_check(not serialized.contains("blessing_gained\":true") and not serialized.contains("karma_gained\":true"), "DATA: reward facts became reaction conditions")

	game_state.reset_state()
	var scene: Variant = await _load_reaction_scene(_valid_result("OBEY", "jukain_attacked_hiruko"), false)
	if scene != null:
		_check(scene.dialogue_ready, "SCHEMA: existing VN loader rejected the contextual graph")
		_check(scene.BATTLE_REACTION_FACTS == ["jukain_attacked_hiruko", "hiruko_damaged_by_enemy", "replacement_requirement_completed"], "SCHEMA: matcher supports fields beyond the approved authoritative facts")
		await _free_current_scene()


func _test_valid_reactions_and_shared_reconvergence() -> void:
	for reaction: Dictionary in REACTIONS:
		game_state.reset_state()
		game_state.adjust_bond("hiruko", 4)
		var result := _valid_result(reaction["route"], reaction["required_fact"])
		var before: Dictionary = result.duplicate(true)
		var scene: Variant = await _load_reaction_scene(result, false)
		if scene == null:
			continue
		var label: String = reaction["route"]
		_check(scene.current_node_id == reaction["start"], "%s: wrong reaction branch selected" % label)
		_check(game_state.get_bond("hiruko") == 4 + int(reaction["delta"]), "%s: contextual Bond delta is wrong" % label)
		_check(scene.executed_reaction_effect_node_ids.keys() == [reaction["condition_id"]], "%s: executed-node guard is wrong" % label)
		_check(game_state.get_pending_battle_result() == before, "%s: branch entry mutated the combat result" % label)
		_check(game_state.get_pending_vn_sequence().is_empty(), "%s: successful VN initialization retained routing" % label)
		var bond_after_entry: int = game_state.get_bond("hiruko")
		scene._show_node(reaction["condition_id"])
		_check(game_state.get_bond("hiruko") == bond_after_entry, "%s: condition redraw duplicated Bond effect" % label)
		_check(scene.current_node_id == reaction["start"], "%s: guarded redraw changed branch" % label)

		var branch_lines: Array = reaction["lines"]
		for index: int in branch_lines.size():
			var expected: Array = branch_lines[index]
			_check(scene.speaker_name.text == expected[0] and scene.dialogue_text.text == expected[2], "%s: visible branch line %d is wrong" % [label, index + 1])
			_check(game_state.get_bond("hiruko") == bond_after_entry, "%s: advancing branch line %d duplicated Bond" % [label, index + 1])
			scene._advance_dialogue()
		_check(scene.current_node_id == "shared_01", "%s: branch did not enter shared ending" % label)
		for index: int in SHARED_LINES.size():
			var expected: Array = SHARED_LINES[index]
			_check(scene.speaker_name.text == expected[0] and scene.dialogue_text.text == expected[2], "%s: shared line %d is wrong" % [label, index + 1])
			_check(game_state.get_bond("hiruko") == bond_after_entry, "%s: shared line %d duplicated Bond" % [label, index + 1])
			scene._advance_dialogue()
		_check(scene.scene_ended, "%s: shared ending did not terminate" % label)
		_check(game_state.get_pending_battle_result() == before, "%s: completed dialogue mutated/consumed result" % label)
		await _free_current_scene()


func _test_multiple_facts_preserve_resolved_route() -> void:
	for reaction: Dictionary in REACTIONS:
		game_state.reset_state()
		var result := _valid_result(reaction["route"], reaction["required_fact"])
		result["facts"]["jukain_attacked_hiruko"] = true
		result["facts"]["hiruko_damaged_by_enemy"] = true
		result["facts"]["replacement_requirement_completed"] = true
		var before: Dictionary = result.duplicate(true)
		var scene: Variant = await _load_reaction_scene(result, false)
		if scene == null:
			continue
		_check(scene.current_node_id == reaction["start"], "%s MULTI: unrelated true facts switched the resolved route" % reaction["route"])
		_check(game_state.get_bond("hiruko") == int(reaction["delta"]), "%s MULTI: wrong contextual delta" % reaction["route"])
		_check(game_state.get_pending_battle_result() == before, "%s MULTI: result was mutated" % reaction["route"])
		await _free_current_scene()


func _test_invalid_result_fallbacks() -> void:
	var invalid_results: Array[Dictionary] = []
	invalid_results.append({})
	invalid_results.append(_result("DEFEAT", ENCOUNTER_ID, PRESCRIPT_ID, "OBEY", _facts({"jukain_attacked_hiruko": true})))
	invalid_results.append(_result("VICTORY", "wrong_encounter", PRESCRIPT_ID, "OBEY", _facts({"jukain_attacked_hiruko": true})))
	invalid_results.append(_result("VICTORY", ENCOUNTER_ID, "wrong_prescript", "OBEY", _facts({"jukain_attacked_hiruko": true})))
	invalid_results.append(_result("VICTORY", ENCOUNTER_ID, PRESCRIPT_ID, "UNRESOLVED", _facts({})))
	invalid_results.append(_result("VICTORY", ENCOUNTER_ID, PRESCRIPT_ID, "OBEY", _facts({"blessing_gained": 1})))
	invalid_results.append(_result("VICTORY", ENCOUNTER_ID, PRESCRIPT_ID, "EXPLOIT", _facts({})))
	invalid_results.append(_result("VICTORY", ENCOUNTER_ID, PRESCRIPT_ID, "DEFY", _facts({"karma_gained": 1})))
	invalid_results.append(_result("VICTORY", ENCOUNTER_ID, PRESCRIPT_ID, "OBEY", {"jukain_attacked_hiruko": 1}))
	invalid_results.append({"outcome": "VICTORY", "encounter_id": ENCOUNTER_ID, "prescript_id": PRESCRIPT_ID, "prescript_route": "OBEY", "facts": []})

	for index: int in invalid_results.size():
		game_state.reset_state()
		game_state.adjust_bond("hiruko", 7)
		var result: Dictionary = invalid_results[index]
		var before: Dictionary = result.duplicate(true)
		var scene: Variant = await _load_reaction_scene(result, false)
		if scene == null:
			continue
		_check(scene.current_node_id == "reaction_fallback", "FALLBACK %d: invalid result selected a route" % index)
		_check(scene.dialogue_text.text == FALLBACK_TEXT, "FALLBACK %d: diagnostic text is wrong" % index)
		_check(game_state.get_bond("hiruko") == 7, "FALLBACK %d: invalid result changed Bond" % index)
		_check(scene.executed_reaction_effect_node_ids.is_empty(), "FALLBACK %d: invalid result marked an effect executed" % index)
		_check(game_state.get_pending_battle_result() == before, "FALLBACK %d: invalid result was mutated or consumed" % index)
		await _free_current_scene()


func _test_instance_local_duplicate_protection_and_save_boundary() -> void:
	game_state.reset_state()
	var result := _valid_result("OBEY", "jukain_attacked_hiruko")
	var before: Dictionary = result.duplicate(true)
	var scene: Variant = await _load_reaction_scene(result, false)
	if scene == null:
		return
	_check(game_state.get_bond("hiruko") == -1, "LOCAL GUARD: first instance did not apply Obey consequence")
	for index: int in 4:
		scene._show_node("check_direct_hit")
		_check(game_state.get_bond("hiruko") == -1, "LOCAL GUARD: repeated traversal %d reapplied Bond" % [index + 1])
	_check(game_state.get_pending_battle_result() == before, "LOCAL GUARD: traversal changed result")
	_check(game_state.save_game(POSTBATTLE_PATH, "obey_01"), "SAVE: reaction line could not use existing save payload")
	var file := FileAccess.open(TEST_SAVE_PATH, FileAccess.READ)
	_check(file != null, "SAVE: reaction save payload could not be read")
	if file != null:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		_check(typeof(parsed) == TYPE_DICTIONARY, "SAVE: payload is not an object")
		if typeof(parsed) == TYPE_DICTIONARY:
			var saved: Dictionary = parsed
			_check(saved.keys().size() == 4, "SAVE: four-field schema changed")
			for field: String in ["pending_battle_result", "pending_vn_sequence", "executed_reaction_effect_node_ids", "consumed", "bond_applied"]:
				_check(not saved.has(field), "SAVE: M6 transient/apply-once field '%s' was serialized" % field)
	await _free_current_scene()

	_check(game_state.prepare_pending_vn_sequence(RETURN_SEQUENCE), "M6.6 BOUNDARY: second-instance handoff failed")
	var second_scene: Variant = await _load_scene(VN_SCENE_PATH)
	if second_scene != null:
		_check(game_state.get_bond("hiruko") == -2, "M6.6 BOUNDARY: new instance did not exhibit documented reapplication limitation")
		_check(game_state.get_pending_battle_result() == before, "M6.6 BOUNDARY: new instance changed result")
		await _free_current_scene()


func _test_layout_and_scope() -> void:
	for viewport_size: Vector2i in [Vector2i(1152, 648), Vector2i(1440, 810)]:
		game_state.reset_state()
		root.size = viewport_size
		var scene: Variant = await _load_reaction_scene(_valid_result("DEFY", "replacement_requirement_completed"), false)
		if scene == null:
			continue
		scene.set_deferred("size", Vector2(viewport_size))
		await process_frame
		_check(scene.current_node_id == "defy_01", "LAYOUT: Defy branch did not initialize at %s" % viewport_size)
		_check(scene.story_background.get_global_rect().size == Vector2(viewport_size), "LAYOUT: Training Hall background does not fill %s" % viewport_size)
		_check(_inside_viewport(scene.dialogue_panel, Vector2(viewport_size)), "LAYOUT: dialogue panel clips at %s" % viewport_size)
		_check(_inside_viewport(scene.speaker_name, Vector2(viewport_size)) and _inside_viewport(scene.dialogue_text, Vector2(viewport_size)), "LAYOUT: reaction text clips at %s" % viewport_size)
		await _free_current_scene()
	_check(ProjectSettings.get_setting("application/run/main_scene") == VN_SCENE_PATH, "SCOPE: main scene changed")
	_check(not FileAccess.file_exists("res://scripts/systems/reaction_manager.gd"), "SCOPE: a reaction manager was introduced")
	_check(not FileAccess.file_exists("res://scripts/systems/relationship_manager.gd"), "SCOPE: a second Bond system was introduced")


func _load_reaction_scene(result: Dictionary, reset_state := true) -> Variant:
	if reset_state:
		game_state.reset_state()
	game_state.set_pending_battle_result(result)
	_check(game_state.prepare_pending_vn_sequence(RETURN_SEQUENCE), "FIXTURE: VN routing handoff failed")
	return await _load_scene(VN_SCENE_PATH)


func _load_scene(path: String) -> Variant:
	if current_scene != null:
		await _free_current_scene()
	var packed: PackedScene = load(path)
	_check(packed != null, "FIXTURE: scene did not load: %s" % path)
	if packed == null:
		return null
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	return scene


func _free_current_scene() -> void:
	if current_scene == null:
		return
	var scene := current_scene
	current_scene = null
	if is_instance_valid(scene):
		scene.queue_free()
	await process_frame


func _valid_result(route: String, required_fact: String) -> Dictionary:
	var facts := _facts({required_fact: true})
	if route == "OBEY":
		facts["blessing_gained"] = 1
	elif route == "DEFY":
		facts["karma_gained"] = 1
	return _result("VICTORY", ENCOUNTER_ID, PRESCRIPT_ID, route, facts)


func _result(
	outcome: String,
	encounter_id: String,
	prescript_id: String,
	route: String,
	facts: Variant
) -> Dictionary:
	return {
		"outcome": outcome,
		"encounter_id": encounter_id,
		"prescript_id": prescript_id,
		"prescript_route": route,
		"facts": facts,
	}


func _facts(overrides: Dictionary) -> Dictionary:
	var facts := {
		"jukain_attacked_hiruko": false,
		"hiruko_damaged_by_enemy": false,
		"replacement_requirement_completed": false,
		"blessing_gained": 0,
		"karma_gained": 0,
	}
	for field: Variant in overrides:
		facts[field] = overrides[field]
	return facts


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
