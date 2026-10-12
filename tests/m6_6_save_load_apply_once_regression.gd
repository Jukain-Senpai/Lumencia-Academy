extends SceneTree

const VN_SCENE_PATH := "res://scenes/vn/vn_prototype.tscn"
const POSTBATTLE_PATH := "res://data/dialogue/m6_training_hall_postbattle.json"
const DESIGN_PATH := "res://docs/M6_6_SAVE_LOAD_APPLY_ONCE_DESIGN.md"
const ENCOUNTER_ID := "m6_training_hall_prototype"
const PRESCRIPT_ID := "prototype_hiruko_hp"
const RETURN_SEQUENCE := "m6_training_hall_postbattle"
const FALLBACK_TEXT := "[Prototype] No valid post-battle reaction was available."
const TEST_USER_DIR := "Lumencia Academy M6.6 Regression"
const TEST_SAVE_PATH := "user://lumencia_save.json"

const RECEIPTS := [
	"m6_training_hall_obey_direct_hit_applied",
	"m6_training_hall_exploit_enemy_hit_applied",
	"m6_training_hall_defy_replacement_applied",
	"m6_training_hall_defy_death_applied",
]
const REACTIONS := [
	{
		"route": "OBEY",
		"fact": "jukain_attacked_hiruko",
		"receipt": "m6_training_hall_obey_direct_hit_applied",
		"condition": "check_direct_hit",
		"start": "obey_01",
		"delta": -1,
	},
	{
		"route": "EXPLOIT",
		"fact": "hiruko_damaged_by_enemy",
		"receipt": "m6_training_hall_exploit_enemy_hit_applied",
		"condition": "check_enemy_hit",
		"start": "exploit_01",
		"delta": -1,
	},
	{
		"route": "DEFY",
		"fact": "replacement_requirement_completed",
		"receipt": "m6_training_hall_defy_replacement_applied",
		"condition": "check_replacement",
		"start": "defy_01",
		"delta": 1,
	},
	{
		"route": "DEFY",
		"fact": "jukain_died_before_prescript_resolution",
		"receipt": "m6_training_hall_defy_death_applied",
		"condition": "check_terminal_death",
		"start": "death_defy_01",
		"delta": 0,
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
	await _test_design_data_and_narrow_schema()
	await _test_fresh_commit_and_same_instance_guard()
	await _test_persisted_reentry_without_result()
	await _test_matching_stale_result_cleanup()
	await _test_conflicting_result_preservation()
	await _test_multiple_receipts_and_invalid_results()
	await _test_save_load_and_old_save_compatibility()
	await _test_death_defy_overlap_and_reset()
	_remove_test_save()
	game_state.reset_state()

	if failures.is_empty():
		print("M6.6 save/load apply-once regression suite passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	push_error("M6.6 regression suite failed: %d failure(s), %d checks." % [failures.size(), checks])
	quit(1)


func _test_design_data_and_narrow_schema() -> void:
	_check(FileAccess.file_exists(DESIGN_PATH), "DESIGN: M6.6 design record is missing")
	_check(FileAccess.file_exists(POSTBATTLE_PATH), "DATA: post-battle sequence is missing")
	var file := FileAccess.open(POSTBATTLE_PATH, FileAccess.READ)
	_check(file != null, "DATA: post-battle sequence could not be opened")
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	_check(typeof(parsed) == TYPE_DICTIONARY, "DATA: post-battle root is not an object")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var nodes_by_id: Dictionary = {}
	for raw_node: Variant in parsed.get("nodes", []):
		if typeof(raw_node) == TYPE_DICTIONARY:
			nodes_by_id[raw_node.get("id", "")] = raw_node
	_check(nodes_by_id.size() == 26, "DATA: dialogue graph was duplicated or resized")
	for reaction: Dictionary in REACTIONS:
		var node: Dictionary = nodes_by_id.get(reaction["condition"], {})
		var condition: Dictionary = node.get("condition", {})
		_check(condition.get("type") == "battle_result_matches", "DATA: reaction stopped using existing condition flow")
		_check(condition.get("receipt_flag") == reaction["receipt"], "DATA: reaction receipt mapping is wrong")
		_check(condition.get("required_fact") == reaction["fact"], "DATA: authoritative fact mapping changed")
		_check(node.get("true_target") == reaction["start"], "DATA: existing dialogue branch was not reused")
		if reaction["condition"] == "check_terminal_death":
			_check(condition.keys().size() == 8, "DATA: death-Defy condition is not narrowly extended")
			_check(condition.get("required_false_fact") == "replacement_requirement_completed", "DATA: death-Defy false fact is wrong")
		else:
			_check(condition.keys().size() == 7, "DATA: non-death condition gained extra query fields")
			_check(not condition.has("required_false_fact"), "DATA: false-fact support escaped death-Defy")

	game_state.reset_state()
	var scene: Variant = await _enter_postbattle(_valid_result("OBEY", "jukain_attacked_hiruko"))
	if scene != null:
		_check(scene.TRAINING_HALL_REACTION_RECEIPTS == RECEIPTS, "SCHEMA: controller receipt allowlist changed")
		_check(scene.DEATH_DEFY_REQUIRED_FALSE_FACT == "replacement_requirement_completed", "SCHEMA: controller false-fact scope changed")
		await _free_current_scene()


func _test_fresh_commit_and_same_instance_guard() -> void:
	for reaction: Dictionary in REACTIONS:
		game_state.reset_state()
		game_state.adjust_bond("hiruko", 5)
		var scene: Variant = await _enter_postbattle(_valid_result(reaction["route"], reaction["fact"]), false)
		if scene == null:
			continue
		var label: String = reaction["receipt"]
		_check(scene.current_node_id == reaction["start"], "%s FRESH: wrong branch" % label)
		_check(game_state.get_bond("hiruko") == 5 + int(reaction["delta"]), "%s FRESH: Bond delta is wrong" % label)
		_check(game_state.get_flag(reaction["receipt"]), "%s FRESH: receipt was not set" % label)
		_check(_active_receipts() == [reaction["receipt"]], "%s FRESH: receipt cardinality is not one" % label)
		_check(game_state.get_pending_battle_result().is_empty(), "%s FRESH: result was not cleared" % label)
		_check(scene.executed_reaction_effect_node_ids.keys() == [reaction["condition"]], "%s FRESH: local guard was not marked" % label)
		var bond_after_commit: int = game_state.get_bond("hiruko")
		for redraw: int in 3:
			scene._show_node(reaction["condition"])
			_check(scene.current_node_id == reaction["start"], "%s REDRAW %d: branch changed" % [label, redraw])
			_check(game_state.get_bond("hiruko") == bond_after_commit, "%s REDRAW %d: Bond reapplied" % [label, redraw])
			_check(_active_receipts() == [reaction["receipt"]], "%s REDRAW %d: receipt set changed" % [label, redraw])
		await _free_current_scene()


func _test_persisted_reentry_without_result() -> void:
	for reaction: Dictionary in REACTIONS:
		game_state.reset_state()
		game_state.adjust_bond("hiruko", 3)
		game_state.set_flag(reaction["receipt"], true)
		var scene: Variant = await _enter_postbattle({}, false)
		if scene == null:
			continue
		_check(scene.current_node_id == reaction["start"], "%s REENTRY: receipt did not restore branch" % reaction["receipt"])
		_check(game_state.get_bond("hiruko") == 3, "%s REENTRY: presentation reapplied Bond" % reaction["receipt"])
		_check(game_state.get_pending_battle_result().is_empty(), "%s REENTRY: pending result was invented" % reaction["receipt"])
		_check(scene.executed_reaction_effect_node_ids.is_empty(), "%s REENTRY: presentation marked a fresh commit" % reaction["receipt"])
		await _free_current_scene()


func _test_matching_stale_result_cleanup() -> void:
	for reaction: Dictionary in REACTIONS:
		game_state.reset_state()
		game_state.adjust_bond("hiruko", 8)
		game_state.set_flag(reaction["receipt"], true)
		var scene: Variant = await _enter_postbattle(_valid_result(reaction["route"], reaction["fact"]), false)
		if scene == null:
			continue
		_check(scene.current_node_id == reaction["start"], "%s STALE: equivalent result did not route" % reaction["receipt"])
		_check(game_state.get_bond("hiruko") == 8, "%s STALE: Bond reapplied" % reaction["receipt"])
		_check(game_state.get_pending_battle_result().is_empty(), "%s STALE: redundant result was not cleared" % reaction["receipt"])
		_check(_active_receipts() == [reaction["receipt"]], "%s STALE: receipts changed" % reaction["receipt"])
		await _free_current_scene()


func _test_conflicting_result_preservation() -> void:
	game_state.reset_state()
	game_state.adjust_bond("hiruko", 11)
	game_state.set_flag(RECEIPTS[0], true)
	var conflict := _valid_result("EXPLOIT", "hiruko_damaged_by_enemy")
	var scene: Variant = await _enter_postbattle(conflict, false)
	if scene != null:
		_check(scene.current_node_id == "reaction_fallback", "CONFLICT: receipt-first entry hid conflicting result")
		_check(scene.dialogue_text.text == FALLBACK_TEXT, "CONFLICT: diagnostic fallback text changed")
		_check(game_state.get_bond("hiruko") == 11, "CONFLICT: Bond changed")
		_check(_active_receipts() == [RECEIPTS[0]], "CONFLICT: receipt changed")
		_check(game_state.get_pending_battle_result() == conflict, "CONFLICT: evidence was consumed or mutated")
		_check(scene.executed_reaction_effect_node_ids.is_empty(), "CONFLICT: effect guard was marked")
		await _free_current_scene()


func _test_multiple_receipts_and_invalid_results() -> void:
	game_state.reset_state()
	game_state.adjust_bond("hiruko", 6)
	game_state.set_flag(RECEIPTS[0], true)
	game_state.set_flag(RECEIPTS[2], true)
	var valid_pending := _valid_result("OBEY", "jukain_attacked_hiruko")
	var multiple: Variant = await _enter_postbattle(valid_pending, false)
	if multiple != null:
		_check(multiple.current_node_id == "reaction_fallback", "CARDINALITY: multiple receipts selected a branch")
		_check(game_state.get_bond("hiruko") == 6, "CARDINALITY: multiple receipts changed Bond")
		_check(_active_receipts().size() == 2, "CARDINALITY: invalid state was rewritten")
		_check(game_state.get_pending_battle_result() == valid_pending, "CARDINALITY: pending evidence was consumed")
		await _free_current_scene()

	for fixture: Dictionary in [
		{"label": "DEFEAT", "result": _result("DEFEAT", "OBEY", _facts({"jukain_attacked_hiruko": true}))},
		{"label": "WRONG ENCOUNTER", "result": _result("VICTORY", "OBEY", _facts({"jukain_attacked_hiruko": true}), "wrong_encounter")},
		{"label": "MISSING FACT", "result": _result("VICTORY", "EXPLOIT", _facts({}))},
	]:
		game_state.reset_state()
		game_state.adjust_bond("hiruko", 2)
		var result: Dictionary = fixture["result"]
		var invalid: Variant = await _enter_postbattle(result, false)
		if invalid == null:
			continue
		_check(invalid.current_node_id == "reaction_fallback", "%s: invalid result selected a branch" % fixture["label"])
		_check(game_state.get_bond("hiruko") == 2, "%s: invalid result changed Bond" % fixture["label"])
		_check(_active_receipts().is_empty(), "%s: invalid result created a receipt" % fixture["label"])
		_check(game_state.get_pending_battle_result() == result, "%s: invalid result was consumed" % fixture["label"])
		await _free_current_scene()


func _test_save_load_and_old_save_compatibility() -> void:
	for reaction: Dictionary in REACTIONS:
		_remove_test_save()
		game_state.reset_state()
		var scene: Variant = await _enter_postbattle(
			_valid_result(reaction["route"], reaction["fact"]),
			false
		)
		if scene == null:
			continue
		scene._advance_dialogue()
		var saved_node_id: String = scene.current_node_id
		_check(game_state.save_game(POSTBATTLE_PATH, saved_node_id), "%s SAVE: committed line could not be saved" % reaction["receipt"])
		var file := FileAccess.open(TEST_SAVE_PATH, FileAccess.READ)
		_check(file != null, "%s SAVE: payload could not be opened" % reaction["receipt"])
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			_check(typeof(parsed) == TYPE_DICTIONARY, "%s SAVE: payload root is not an object" % reaction["receipt"])
			if typeof(parsed) == TYPE_DICTIONARY:
				var saved: Dictionary = parsed
				_check(saved.keys().size() == 4, "%s SAVE: top-level cardinality changed" % reaction["receipt"])
				for field: String in ["sequence", "node", "flags", "bonds"]:
					_check(saved.has(field), "%s SAVE: required field '%s' is missing" % [reaction["receipt"], field])
				_check(saved["flags"].get(reaction["receipt"]) == true, "%s SAVE: receipt is not inside flags" % reaction["receipt"])
				_check(saved["bonds"].get("hiruko") == int(reaction["delta"]), "%s SAVE: committed Bond is wrong" % reaction["receipt"])
				for forbidden: String in ["pending_battle_result", "receipt", "consumed", "bond_applied"]:
					_check(not saved.has(forbidden), "%s SAVE: transient/fifth field '%s' was added" % [reaction["receipt"], forbidden])

		game_state.reset_state()
		_check(game_state.get_bond("hiruko") == 0 and _active_receipts().is_empty(), "%s LOAD: reset fixture failed" % reaction["receipt"])
		scene._load_game()
		_check(scene.current_node_id == saved_node_id, "%s LOAD: exact saved post-battle line was not restored" % reaction["receipt"])
		_check(game_state.get_bond("hiruko") == int(reaction["delta"]), "%s LOAD: committed Bond was not restored" % reaction["receipt"])
		_check(_active_receipts() == [reaction["receipt"]], "%s LOAD: committed receipt was not restored" % reaction["receipt"])
		_check(game_state.get_pending_battle_result().is_empty(), "%s LOAD: transient result was synthesized" % reaction["receipt"])
		await _free_current_scene()

		_check(game_state.prepare_pending_vn_sequence(RETURN_SEQUENCE), "%s LOAD REENTRY: routing fixture failed" % reaction["receipt"])
		var reentry: Variant = await _load_scene(VN_SCENE_PATH)
		if reentry != null:
			_check(reentry.current_node_id == reaction["start"], "%s LOAD REENTRY: receipt did not restore branch" % reaction["receipt"])
			_check(game_state.get_bond("hiruko") == int(reaction["delta"]), "%s LOAD REENTRY: restored consequence reapplied" % reaction["receipt"])
			await _free_current_scene()

	game_state.reset_state()
	_check(game_state.save_game("res://data/dialogue/vn_prototype_m1.json", "start"), "OLD SAVE: receipt-free payload could not be created")
	var old_data: Dictionary = game_state.read_save_data()
	_check(not old_data.is_empty(), "OLD SAVE: receipt-free payload could not be read")
	for receipt: String in RECEIPTS:
		_check(not old_data["flags"].has(receipt), "OLD SAVE: missing receipt was invented")
	game_state.restore_from_save_data(old_data)
	for receipt: String in RECEIPTS:
		_check(not game_state.get_flag(receipt), "OLD SAVE: absent receipt did not default false")
	var fresh_after_old: Variant = await _enter_postbattle(_valid_result("EXPLOIT", "hiruko_damaged_by_enemy"), false)
	if fresh_after_old != null:
		_check(fresh_after_old.current_node_id == "exploit_01", "OLD SAVE: fresh result did not commit")
		_check(game_state.get_bond("hiruko") == -1, "OLD SAVE: fresh Bond consequence is wrong")
		_check(_active_receipts() == [RECEIPTS[1]], "OLD SAVE: fresh receipt was not created")
		await _free_current_scene()


func _test_death_defy_overlap_and_reset() -> void:
	game_state.reset_state()
	game_state.set_flag(RECEIPTS[3], true)
	var conflicting_normal_defy := _valid_result("DEFY", "replacement_requirement_completed")
	conflicting_normal_defy["facts"]["jukain_died_before_prescript_resolution"] = true
	var scene: Variant = await _enter_postbattle(conflicting_normal_defy, false)
	if scene != null:
		_check(scene.current_node_id == "reaction_fallback", "DEATH FALSE FACT: normal Defy matched death receipt")
		_check(game_state.get_bond("hiruko") == 0, "DEATH FALSE FACT: conflict changed Bond")
		_check(game_state.get_pending_battle_result() == conflicting_normal_defy, "DEATH FALSE FACT: conflict was consumed")
		await _free_current_scene()

	game_state.reset_state()
	for receipt: String in RECEIPTS:
		_check(not game_state.get_flag(receipt), "RESET: receipt '%s' survived full reset" % receipt)
	_check(game_state.get_bond("hiruko") == 0, "RESET: Bond survived full reset")
	_check(game_state.get_pending_battle_result().is_empty(), "RESET: pending result survived full reset")


func _enter_postbattle(result: Dictionary, reset_state := true) -> Variant:
	if reset_state:
		game_state.reset_state()
	if not result.is_empty():
		game_state.set_pending_battle_result(result)
	_check(game_state.prepare_pending_vn_sequence(RETURN_SEQUENCE), "FIXTURE: post-battle handoff failed")
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


func _active_receipts() -> Array[String]:
	var active: Array[String] = []
	for receipt: String in RECEIPTS:
		if game_state.get_flag(receipt):
			active.append(receipt)
	return active


func _valid_result(route: String, required_fact: String) -> Dictionary:
	var facts := _facts({required_fact: true})
	if route == "OBEY":
		facts["blessing_gained"] = 1
	elif route == "DEFY" and required_fact == "replacement_requirement_completed":
		facts["karma_gained"] = 1
	return _result("VICTORY", route, facts)


func _result(
	outcome: String,
	route: String,
	facts: Variant,
	encounter_id := ENCOUNTER_ID,
	prescript_id := PRESCRIPT_ID
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
		"jukain_died_before_prescript_resolution": false,
		"blessing_gained": 0,
		"karma_gained": 0,
	}
	for field: Variant in overrides:
		facts[field] = overrides[field]
	return facts


func _remove_test_save() -> void:
	var absolute_path := ProjectSettings.globalize_path(TEST_SAVE_PATH)
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
