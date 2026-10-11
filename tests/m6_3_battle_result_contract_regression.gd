extends SceneTree

const BattleUnitModel := preload("res://scripts/battle/battle_unit.gd")
const JukainPrescriptStateModel := preload("res://scripts/battle/jukain_prescript_state.gd")
const BATTLE_SCENE_PATH := "res://scenes/battle/battle_sandbox.tscn"
const M6_DIALOGUE_PATH := "res://data/dialogue/m6_training_hall_prebattle.json"
const ENCOUNTER_ID := "m6_training_hall_prototype"
const RETURN_SEQUENCE := "m6_training_hall_postbattle"
const TEST_USER_DIR := "Lumencia Academy M6.3 Regression"
const TEST_SAVE_PATH := "user://lumencia_save.json"

var failures: Array[String] = []
var checks := 0
var game_state: Node
var active_scene: Control


func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", TEST_USER_DIR)
	call_deferred("_run")


func _run() -> void:
	game_state = root.get_node("GameState")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://"))
	_remove_test_save()
	await _test_initial_and_preterminal_state()
	await _test_obey_victory_contract_and_copy_safety()
	await _test_exploit_victory_contract()
	await _test_defy_victory_contract()
	await _test_defeat_contracts_and_event_independence()
	await _test_exactly_once_and_post_commit_immutability()
	await _test_standalone_terminal_boundaries()
	await _test_restart_before_and_after_terminal()
	await _test_stale_result_reset_and_save_exclusion()
	await _test_retained_m6_flow_and_layout()
	_remove_test_save()
	game_state.reset_state()

	if failures.is_empty():
		print("M6.3 battle-result contract regression suite passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	push_error("M6.3 regression suite failed: %d failure(s), %d checks." % [failures.size(), checks])
	quit(1)


func _test_initial_and_preterminal_state() -> void:
	game_state.reset_state()
	_check(game_state.get_pending_battle_result().is_empty(), "INITIAL: pending result was not empty")
	var scene := await _new_battle(true)
	if scene == null:
		return
	_check(game_state.get_pending_battle_result().is_empty(), "INITIAL: integrated battle start created a result")
	_check(scene.result_facts == _empty_facts(), "INITIAL: result facts did not start at defaults")
	_check(not scene.battle_result_committed, "INITIAL: result guard started committed")
	_check(scene.battle_context == _context(), "INITIAL: integrated context was not retained")
	_start_jukain_turn(scene)
	var hiruko_hp_before: int = scene.hiruko_unit.current_hp
	_check(scene.begin_attack_selection(), "PRETERMINAL: Jukain attack selection failed")
	_check(scene.select_attack_target(&"party_1"), "PRETERMINAL: Hiruko selection failed")
	_check(not scene.result_facts["jukain_attacked_hiruko"], "PRETERMINAL: selection alone recorded a hit")
	_check(scene.confirm_ally_attack(), "PRETERMINAL: confirmed ally attack failed")
	_check(hiruko_hp_before > scene.hiruko_unit.current_hp, "PRETERMINAL: confirmed attack did not reduce HP")
	_check(scene.jukain_prescript.get_route_label() == "OBEY", "PRETERMINAL: Obey did not resolve")
	_check(scene.result_facts["jukain_attacked_hiruko"], "PRETERMINAL: real Jukain-to-Hiruko HP loss was not recorded")
	_check(scene.result_facts["blessing_gained"] == 1, "PRETERMINAL: actual Blessing grant was not recorded")
	_check(game_state.get_pending_battle_result().is_empty(), "PRETERMINAL: resolved route published before terminal")
	await _free_scene(scene)


func _test_obey_victory_contract_and_copy_safety() -> void:
	var scene := await _new_battle(true)
	if scene == null:
		return
	_start_jukain_turn(scene)
	_check(scene.begin_attack_selection() and scene.select_attack_target(&"party_1") and scene.confirm_ally_attack(), "OBEY: real route fixture failed")
	_check(scene.jukain_state.blessing_stacks == 1, "OBEY: active Blessing was not granted")
	_check(game_state.get_pending_battle_result().is_empty(), "OBEY: result existed before Victory")
	_finish_victory(scene)
	var expected := {
		"jukain_attacked_hiruko": true,
		"hiruko_damaged_by_enemy": false,
		"replacement_requirement_completed": false,
		"blessing_gained": 1,
		"karma_gained": 0,
	}
	_assert_contract(game_state.get_pending_battle_result(), "VICTORY", "OBEY", expected, "OBEY")
	_check(scene.battle_result_committed, "OBEY: terminal result guard was not committed")
	_check(scene.jukain_state.blessing_stacks == 0, "OBEY: active Blessing did not receive existing terminal cleanup")
	_check(game_state.get_pending_battle_result()["facts"]["blessing_gained"] == 1, "OBEY: terminal cleanup erased the latched gain")
	var caller_copy: Dictionary = game_state.get_pending_battle_result()
	caller_copy["outcome"] = "MUTATED"
	caller_copy["facts"]["blessing_gained"] = 99
	var authoritative: Dictionary = game_state.get_pending_battle_result()
	_check(authoritative["outcome"] == "VICTORY", "COPY: caller changed stored outcome")
	_check(authoritative["facts"]["blessing_gained"] == 1, "COPY: caller changed nested stored facts")
	var source := {"outcome": "SOURCE", "facts": {"value": 1}}
	game_state.set_pending_battle_result(source)
	source["facts"]["value"] = 2
	_check(game_state.get_pending_battle_result()["facts"]["value"] == 1, "COPY: caller changed result after storage")
	await _free_scene(scene)


func _test_exploit_victory_contract() -> void:
	var scene := await _new_battle(true)
	if scene == null:
		return
	_start_jukain_turn(scene)
	_check(scene.begin_move_selection() and scene.select_move_destination(BattleUnitModel.Line.MID), "EXPLOIT: positioning setup failed")
	_check(scene.current_unit.stable_id == &"enemy_c", "EXPLOIT: controlled enemy did not receive the turn")
	var hiruko_hp_before: int = scene.hiruko_unit.current_hp
	_check(scene.resolve_enemy_turn(), "EXPLOIT: enemy attack did not resolve")
	_check(scene.hiruko_unit.current_hp < hiruko_hp_before, "EXPLOIT: enemy did not actually damage Hiruko")
	_check(scene.jukain_prescript.get_route_label() == "EXPLOIT", "EXPLOIT: route did not resolve")
	_check(scene.result_facts["hiruko_damaged_by_enemy"], "EXPLOIT: real enemy-to-Hiruko damage was not latched")
	_check(not scene.result_facts["jukain_attacked_hiruko"], "EXPLOIT: enemy damage was mislabeled as Jukain damage")
	_check(game_state.get_pending_battle_result().is_empty(), "EXPLOIT: result existed before terminal")
	_finish_victory(scene)
	_assert_contract(
		game_state.get_pending_battle_result(),
		"VICTORY",
		"EXPLOIT",
		{
			"jukain_attacked_hiruko": false,
			"hiruko_damaged_by_enemy": true,
			"replacement_requirement_completed": false,
			"blessing_gained": 0,
			"karma_gained": 0,
		},
		"EXPLOIT"
	)
	_check(scene.jukain_state.blessing_stacks == 0 and scene.jukain_prescript.karma_stacks == 0, "EXPLOIT: M6.1 reward boundaries changed")
	await _free_scene(scene)


func _test_defy_victory_contract() -> void:
	var scene := await _new_battle(true)
	if scene == null:
		return
	_start_jukain_turn(scene)
	scene.round_number += 1
	_check(scene._process_jukain_turn_start() == &"defied", "DEFY: deadline did not grant Karma")
	_check(scene.result_facts["karma_gained"] == 1, "DEFY: actual Karma gain was not latched")
	_check(not scene.result_facts["replacement_requirement_completed"], "DEFY: deadline alone completed replacement")
	var enemy_a := _find(scene, &"enemy_a")
	_set_current(scene, enemy_a)
	var jukain_hp_before: int = scene.jukain_unit.current_hp
	_check(scene.resolve_enemy_turn(), "DEFY: replacement enemy attack failed")
	_check(scene.jukain_unit.current_hp < jukain_hp_before, "DEFY: replacement attack caused no HP loss")
	_check(scene.jukain_prescript.get_route_label() == "DEFY", "DEFY: replacement did not resolve route")
	_check(scene.result_facts["replacement_requirement_completed"], "DEFY: authoritative completion was not latched")
	_check(game_state.get_pending_battle_result().is_empty(), "DEFY: result existed before terminal")
	_finish_victory(scene)
	_assert_contract(
		game_state.get_pending_battle_result(),
		"VICTORY",
		"DEFY",
		{
			"jukain_attacked_hiruko": false,
			"hiruko_damaged_by_enemy": false,
			"replacement_requirement_completed": true,
			"blessing_gained": 0,
			"karma_gained": 1,
		},
		"DEFY"
	)
	_check(scene.jukain_prescript.karma_stacks == 1 and scene.jukain_state.blessing_stacks == 0, "DEFY: M6.1 Karma/Blessing behavior changed")
	await _free_scene(scene)


func _test_defeat_contracts_and_event_independence() -> void:
	var scene := await _new_battle(true)
	if scene == null:
		return
	_finish_defeat(scene)
	_assert_contract(game_state.get_pending_battle_result(), "DEFEAT", "UNRESOLVED", _empty_facts(), "UNRESOLVED DEFEAT")
	_check(scene.jukain_prescript.karma_stacks == 0, "UNRESOLVED DEFEAT: terminal synthesized Karma")
	await _free_scene(scene)

	scene = await _new_battle(true)
	if scene == null:
		return
	_start_jukain_turn(scene)
	_check(scene.begin_attack_selection() and scene.select_attack_target(&"party_1") and scene.confirm_ally_attack(), "RESOLVED DEFEAT: Obey fixture failed")
	_finish_defeat(scene)
	_assert_contract(
		game_state.get_pending_battle_result(),
		"DEFEAT",
		"OBEY",
		{
			"jukain_attacked_hiruko": true,
			"hiruko_damaged_by_enemy": false,
			"replacement_requirement_completed": false,
			"blessing_gained": 1,
			"karma_gained": 0,
		},
		"RESOLVED DEFEAT"
	)
	await _free_scene(scene)

	scene = await _new_battle(true)
	if scene == null:
		return
	# Directly setting a resolved route proves terminal construction does not invent facts.
	scene.jukain_prescript.phase = JukainPrescriptStateModel.Phase.RESOLVED_OBEY
	_finish_victory(scene)
	_assert_contract(game_state.get_pending_battle_result(), "VICTORY", "OBEY", _empty_facts(), "EVENT INDEPENDENCE")
	await _free_scene(scene)


func _test_exactly_once_and_post_commit_immutability() -> void:
	var scene := await _new_battle(true)
	if scene == null:
		return
	_finish_victory(scene)
	var committed: Dictionary = game_state.get_pending_battle_result()
	_check(scene.battle_result_committed, "ONCE: guard was not set")
	scene.result_facts["karma_gained"] = 42
	scene._render_battlefield()
	scene._refresh_turn_ui()
	_check(scene._check_battle_result(), "ONCE: repeated result check no longer recognized terminal state")
	_check(not scene._commit_pending_battle_result(scene.BattleResult.VICTORY), "ONCE: direct repeated commit was accepted")
	_check(game_state.get_pending_battle_result() == committed, "ONCE: later render/check/fact mutation changed stored result")
	await _free_scene(scene)


func _test_standalone_terminal_boundaries() -> void:
	var scene := await _new_battle(false)
	if scene == null:
		return
	_finish_victory(scene)
	_check(scene.battle_result == scene.BattleResult.VICTORY, "STANDALONE: Victory behavior failed")
	_check(not scene.battle_result_committed, "STANDALONE: Victory marked a story result committed")
	_check(game_state.get_pending_battle_result().is_empty(), "STANDALONE: Victory published a story result")
	await _free_scene(scene)

	scene = await _new_battle(false)
	if scene == null:
		return
	_finish_defeat(scene)
	_check(scene.battle_result == scene.BattleResult.DEFEAT, "STANDALONE: Defeat behavior failed")
	_check(not scene.battle_result_committed, "STANDALONE: Defeat marked a story result committed")
	_check(game_state.get_pending_battle_result().is_empty(), "STANDALONE: Defeat published a story result")
	await _free_scene(scene)


func _test_restart_before_and_after_terminal() -> void:
	var scene := await _new_battle(true)
	if scene == null:
		return
	_start_jukain_turn(scene)
	_check(scene.begin_attack_selection() and scene.select_attack_target(&"party_1") and scene.confirm_ally_attack(), "RESTART BEFORE: fact fixture failed")
	_check(scene.result_facts["jukain_attacked_hiruko"] and scene.result_facts["blessing_gained"] == 1, "RESTART BEFORE: fixture facts were not present")
	scene.restart_battle()
	_check(scene.battle_context == _context() and game_state.get_pending_battle_context() == _context(), "RESTART BEFORE: integrated context was lost")
	_check(scene.result_facts == _empty_facts(), "RESTART BEFORE: abandoned facts leaked")
	_check(not scene.battle_result_committed and game_state.get_pending_battle_result().is_empty(), "RESTART BEFORE: guard/result were not reset")
	_check(scene.jukain_prescript.get_route_label() == "NONE" and scene.jukain_state.blessing_stacks == 0, "RESTART BEFORE: combat state was not fresh")
	_finish_victory(scene)
	_assert_contract(game_state.get_pending_battle_result(), "VICTORY", "UNRESOLVED", _empty_facts(), "RETRY AFTER PRETERMINAL")
	await _free_scene(scene)

	scene = await _new_battle(true)
	if scene == null:
		return
	_finish_victory(scene)
	_check(not game_state.get_pending_battle_result().is_empty(), "RESTART AFTER: terminal fixture produced no result")
	scene.restart_battle()
	_check(game_state.get_pending_battle_result().is_empty(), "RESTART AFTER: pending result was not cleared")
	_check(scene.result_facts == _empty_facts() and not scene.battle_result_committed, "RESTART AFTER: local result tracking was not reset")
	_check(scene.battle_context == _context(), "RESTART AFTER: context was not preserved")
	_finish_defeat(scene)
	_assert_contract(game_state.get_pending_battle_result(), "DEFEAT", "UNRESOLVED", _empty_facts(), "RETRY AFTER TERMINAL")
	await _free_scene(scene)


func _test_stale_result_reset_and_save_exclusion() -> void:
	game_state.reset_state()
	game_state.set_pending_battle_result({"outcome": "OLD", "facts": {"old": true}})
	_check(game_state.prepare_battle_context("new_encounter", "new_return"), "STALE: new context did not prepare")
	_check(game_state.get_pending_battle_result().is_empty(), "STALE: new integrated preparation retained old result")
	_check(game_state.get_pending_battle_context() == {"encounter_id": "new_encounter", "return_sequence": "new_return"}, "STALE: new context is wrong")
	game_state.set_pending_battle_result({"outcome": "VICTORY", "facts": _empty_facts()})
	_check(game_state.save_game(M6_DIALOGUE_PATH, "training_01"), "SAVE: normal save failed with transient state present")
	var file := FileAccess.open(TEST_SAVE_PATH, FileAccess.READ)
	_check(file != null, "SAVE: save payload could not be inspected")
	if file != null:
		var saved: Variant = JSON.parse_string(file.get_as_text())
		_check(typeof(saved) == TYPE_DICTIONARY, "SAVE: payload was not an object")
		if typeof(saved) == TYPE_DICTIONARY:
			_check(saved.keys().size() == 4, "SAVE: transient state changed the four-field schema")
			_check(not saved.has("pending_battle_context") and not saved.has("pending_battle_result"), "SAVE: transient structures were serialized")
			_check(not saved.has("encounter_id") and not saved.has("return_sequence") and not saved.has("outcome"), "SAVE: transient fields leaked into payload")
	game_state.reset_state()
	_check(game_state.get_pending_battle_context().is_empty() and game_state.get_pending_battle_result().is_empty(), "RESET: full GameState reset retained transient state")


func _test_retained_m6_flow_and_layout() -> void:
	var file := FileAccess.open(M6_DIALOGUE_PATH, FileAccess.READ)
	_check(file != null, "M6.2: Training Hall dialogue is missing")
	if file != null:
		var data: Variant = JSON.parse_string(file.get_as_text())
		_check(typeof(data) == TYPE_DICTIONARY, "M6.2: dialogue data is invalid")
		if typeof(data) == TYPE_DICTIONARY:
			var line_count := 0
			var launch_count := 0
			for raw_node: Variant in data.get("nodes", []):
				if typeof(raw_node) != TYPE_DICTIONARY:
					continue
				if raw_node.get("type") == "line":
					line_count += 1
				elif raw_node.get("type") == "start_battle":
					launch_count += 1
					_check(raw_node.get("encounter_id") == ENCOUNTER_ID and raw_node.get("return_sequence") == RETURN_SEQUENCE, "M6.2: launch context changed")
			_check(line_count == 6 and launch_count == 1, "M6.2: six-line explicit launch flow changed")
	_check(JukainPrescriptStateModel.PRESCRIPT_ID == "prototype_hiruko_hp", "IDENTITY: Prescript ID is not stable")
	_check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/vn/vn_prototype.tscn", "SCOPE: main scene changed")
	_check(FileAccess.file_exists("res://data/dialogue/m6_training_hall_postbattle.json"), "M6.4: post-battle dialogue is missing")
	_check(game_state.get_bond("hiruko") == 0, "SCOPE: M6.3 changed Hiruko Bond")

	var scene := await _new_battle(false)
	if scene == null:
		return
	for viewport_size: Vector2i in [Vector2i(1152, 648), Vector2i(1440, 810)]:
		root.size = viewport_size
		scene.set_deferred("size", Vector2(viewport_size))
		await process_frame
		_check(_inside_viewport(scene.get_node("Margin/Layout/Battlefield"), Vector2(viewport_size)), "LAYOUT: battlefield clips at %s" % viewport_size)
		_check(_inside_viewport(scene.get_node("%CharacterInspector"), Vector2(viewport_size)), "LAYOUT: Character Inspector clips at %s" % viewport_size)
		_check(_inside_viewport(scene.get_node("%ReplicaFormRow"), Vector2(viewport_size)), "LAYOUT: Form Chain builder clips at %s" % viewport_size)
		_check(_inside_viewport(scene.get_node("%CombatLog"), Vector2(viewport_size)), "LAYOUT: Combat Log clips at %s" % viewport_size)
		_check(scene.get_node("%AllyMidUnits").get_child_count() == 3, "LAYOUT: retained five-card line fixture changed")
	await _free_scene(scene)


func _new_battle(integrated: bool) -> Control:
	game_state.reset_state()
	if integrated:
		_check(game_state.prepare_battle_context(ENCOUNTER_ID, RETURN_SEQUENCE), "FIXTURE: integrated context preparation failed")
	var packed: PackedScene = load(BATTLE_SCENE_PATH)
	_check(packed != null, "FIXTURE: battle scene did not load")
	if packed == null:
		return null
	var scene: Control = packed.instantiate()
	scene.automatic_enemy_turns_enabled = false
	# This retained suite isolates the M6.3 contract; M6.4 owns automatic routing coverage.
	scene.automatic_vn_return_enabled = false
	root.add_child(scene)
	current_scene = scene
	active_scene = scene
	await process_frame
	return scene


func _free_scene(scene: Control) -> void:
	if current_scene == scene:
		current_scene = null
	if active_scene == scene:
		active_scene = null
	scene.queue_free()
	await process_frame


func _start_jukain_turn(scene: Control) -> void:
	_set_current(scene, scene.jukain_unit)
	_check(scene._process_jukain_turn_start() == &"activated", "FIXTURE: Prescript did not activate")


func _set_current(scene: Control, unit: BattleUnit) -> void:
	scene.current_unit = unit
	scene.turn_index = scene.turn_queue.find(unit)
	scene.action_in_progress = false
	scene._clear_action_selection()
	scene._refresh_turn_ui()


func _finish_victory(scene: Control) -> void:
	for enemy: BattleUnit in scene.enemy_units:
		_defeat(enemy)
	_check(scene._check_battle_result(), "FIXTURE: Victory was not recognized")
	_check(scene.battle_result == scene.BattleResult.VICTORY, "FIXTURE: terminal result was not Victory")


func _finish_defeat(scene: Control) -> void:
	for ally: BattleUnit in scene.party_units:
		_defeat(ally)
	_check(scene._check_battle_result(), "FIXTURE: Defeat was not recognized")
	_check(scene.battle_result == scene.BattleResult.DEFEAT, "FIXTURE: terminal result was not Defeat")


func _assert_contract(
	contract: Dictionary,
	outcome: String,
	route: String,
	expected_facts: Dictionary,
	label: String
) -> void:
	_check(contract.keys().size() == 5, "%s: contract does not have exactly five top-level fields" % label)
	_check(contract.get("outcome") == outcome, "%s: wrong outcome" % label)
	_check(contract.get("encounter_id") == ENCOUNTER_ID, "%s: wrong encounter ID" % label)
	_check(contract.get("prescript_id") == "prototype_hiruko_hp", "%s: wrong Prescript ID" % label)
	_check(contract.get("prescript_route") == route, "%s: wrong Prescript route" % label)
	_check(not contract.has("return_sequence"), "%s: routing context leaked into result" % label)
	var facts: Dictionary = contract.get("facts", {})
	_check(facts.keys().size() == 5, "%s: facts do not have exactly five fields" % label)
	_check(facts == expected_facts, "%s: factual snapshot is wrong: %s" % [label, facts])


func _empty_facts() -> Dictionary:
	return {
		"jukain_attacked_hiruko": false,
		"hiruko_damaged_by_enemy": false,
		"replacement_requirement_completed": false,
		"blessing_gained": 0,
		"karma_gained": 0,
	}


func _context() -> Dictionary:
	return {"encounter_id": ENCOUNTER_ID, "return_sequence": RETURN_SEQUENCE}


func _find(scene: Control, id: StringName) -> BattleUnit:
	for unit: BattleUnit in scene.party_units + scene.enemy_units:
		if unit.stable_id == id:
			return unit
	return null


func _defeat(unit: BattleUnit) -> void:
	unit.current_hp = 0
	unit.defeated = true


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
