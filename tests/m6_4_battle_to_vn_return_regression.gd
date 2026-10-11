extends SceneTree

const BattleUnitModel := preload("res://scripts/battle/battle_unit.gd")
const JukainPrescriptStateModel := preload("res://scripts/battle/jukain_prescript_state.gd")
const VN_SCENE_PATH := "res://scenes/vn/vn_prototype.tscn"
const M6_ENTRY_PATH := "res://scenes/vn/m6_training_hall_entry.tscn"
const BATTLE_SCENE_PATH := "res://scenes/battle/battle_sandbox.tscn"
const PREBATTLE_PATH := "res://data/dialogue/m6_training_hall_prebattle.json"
const POSTBATTLE_PATH := "res://data/dialogue/m6_training_hall_postbattle.json"
const BACKGROUND_PATH := "res://assets/art/backgrounds/academy_training_hall.png"
const ENCOUNTER_ID := "m6_training_hall_prototype"
const RETURN_SEQUENCE := "m6_training_hall_postbattle"
const TEST_USER_DIR := "Lumencia Academy M6.4 Regression"
const TEST_SAVE_PATH := "user://lumencia_save.json"
const FALLBACK_TEXT := "[Prototype] No valid post-battle reaction was available."
const REACTION_STARTS := {
	"OBEY": "obey_01",
	"EXPLOIT": "exploit_01",
	"DEFY": "defy_01",
}
const REACTION_TEXT := {
	"OBEY": "You really hit me because that thing told you to.",
	"EXPLOIT": "You moved out of the way on purpose.",
	"DEFY": "You could've used me to clear the first Prescript.",
}
const REACTION_BOND := {"OBEY": -1, "EXPLOIT": -1, "DEFY": 1}

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
	await _test_postbattle_data_and_resolver()
	await _test_real_obey_flow_result_order_and_return()
	await _test_exploit_return()
	await _test_defy_return()
	await _test_standalone_victory()
	await _test_integrated_defeat_retry_victory()
	await _test_invalid_and_missing_return_sequences()
	await _test_scene_change_failure()
	await _test_vn_initialization_failure()
	await _test_transient_save_reset_and_layout()
	_remove_test_save()
	game_state.reset_state()

	if failures.is_empty():
		print("M6.4 battle-to-VN return regression suite passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	push_error("M6.4 regression suite failed: %d failure(s), %d checks." % [failures.size(), checks])
	quit(1)


func _test_postbattle_data_and_resolver() -> void:
	_check(FileAccess.file_exists(POSTBATTLE_PATH), "DATA: post-battle dialogue is missing")
	var file := FileAccess.open(POSTBATTLE_PATH, FileAccess.READ)
	_check(file != null, "DATA: post-battle dialogue could not be opened")
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	_check(typeof(parsed) == TYPE_DICTIONARY, "DATA: post-battle dialogue root is not an object")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed
	_check(data.get("background") == BACKGROUND_PATH, "DATA: post-battle sequence uses the wrong background")
	_check(data.get("start") == "check_direct_hit", "DATA: post-battle sequence has the wrong start node")
	var nodes: Array = data.get("nodes", [])
	_check(nodes.size() == 21, "DATA: M6.5 changed the expected post-battle graph size")
	var visible_lines := 0
	var end_nodes := 0
	var result_conditions := 0
	var bond_effects := 0
	for raw_node: Variant in nodes:
		_check(typeof(raw_node) == TYPE_DICTIONARY, "DATA: post-battle node is not an object")
		if typeof(raw_node) != TYPE_DICTIONARY:
			continue
		var node: Dictionary = raw_node
		match node.get("type", ""):
			"line":
				visible_lines += 1
			"condition":
				if node.get("condition", {}).get("type") == "battle_result_matches":
					result_conditions += 1
					bond_effects += node.get("effects", []).size()
			"end":
				end_nodes += 1
			_:
				_check(false, "DATA: post-battle sequence contains an unsupported node type")
	_check(visible_lines == 17 and end_nodes == 1, "DATA: M6.5 dialogue/end structure changed")
	_check(result_conditions == 3 and bond_effects == 3, "DATA: contextual condition/effect count changed")
	_check(not JSON.stringify(data).contains("[Prototype] Returned from battle."), "DATA: M6.4 placeholder remains visible")

	var script: GDScript = load("res://scripts/vn/vn_prototype.gd")
	_check(script != null, "RESOLVER: existing VN controller script did not load")
	if script != null:
		_check(script.resolve_dialogue_sequence_path(RETURN_SEQUENCE) == POSTBATTLE_PATH, "RESOLVER: return identifier did not resolve to post-battle data")
		_check(script.resolve_dialogue_sequence_path("unknown_sequence").is_empty(), "RESOLVER: unknown identifier received a fallback")
	_check(ProjectSettings.get_setting("application/run/main_scene") == VN_SCENE_PATH, "SCOPE: project main scene changed")


func _test_real_obey_flow_result_order_and_return() -> void:
	game_state.reset_state()
	var vn: Variant = await _load_scene(M6_ENTRY_PATH)
	if vn == null:
		return
	_check(vn.current_dialogue_path == PREBATTLE_PATH and vn.current_node_id == "training_01", "OBEY FLOW: dedicated entry did not start the real prebattle sequence")
	for index: int in 6:
		vn._advance_dialogue()
		if index < 5:
			_check(vn.current_node_id == "training_%02d" % [index + 2], "OBEY FLOW: prebattle line progression changed")
	await process_frame
	await process_frame
	var battle: Variant = current_scene
	_check(battle != null and battle.name == "BattleSandbox", "OBEY FLOW: explicit start_battle action did not load combat")
	if battle == null or battle.name != "BattleSandbox":
		return
	battle.automatic_enemy_turns_enabled = false
	_check(battle.battle_context == _context(), "OBEY FLOW: battle did not receive M6.2 context")
	_resolve_obey(battle)
	_check(battle.jukain_prescript.get_route_label() == "OBEY", "OBEY FLOW: route fixture did not resolve Obey")
	_check(battle.result_facts["blessing_gained"] == 1, "OBEY FLOW: Blessing fact was not latched before Victory")
	_defeat_all_enemies(battle)
	_check(battle._check_battle_result(), "OBEY FLOW: real Victory was not recognized")
	var before_return: Dictionary = game_state.get_pending_battle_result()
	_assert_result(before_return, "VICTORY", "OBEY", {
		"jukain_attacked_hiruko": true,
		"hiruko_damaged_by_enemy": false,
		"replacement_requirement_completed": false,
		"blessing_gained": 1,
		"karma_gained": 0,
	}, "OBEY FLOW")
	_check(battle.battle_result_committed, "ORDER: result guard was not committed before return")
	_check(battle.battle_return_committed, "ORDER: valid return did not commit its guard")
	_check(game_state.get_pending_vn_sequence() == RETURN_SEQUENCE, "ORDER: routing handoff was not prepared before scene replacement")
	_check(game_state.get_pending_battle_context().is_empty(), "ORDER: successful return initiation retained active battle context")
	_check(not battle._request_battle_return(), "ONCE: duplicate return request was accepted")
	var generation_before: int = battle.battle_generation
	battle.restart_battle()
	_check(battle.battle_generation == generation_before, "INPUT LOCK: Restart mutated battle after return commitment")
	await _assert_postbattle_arrival(before_return, "OBEY")


func _test_exploit_return() -> void:
	var battle: Variant = await _load_integrated_battle()
	if battle == null:
		return
	_resolve_exploit(battle)
	_check(battle.jukain_prescript.get_route_label() == "EXPLOIT", "EXPLOIT: route fixture did not resolve")
	_defeat_all_enemies(battle)
	_check(battle._check_battle_result(), "EXPLOIT: Victory was not recognized")
	var before_return: Dictionary = game_state.get_pending_battle_result()
	_assert_result(before_return, "VICTORY", "EXPLOIT", {
		"jukain_attacked_hiruko": false,
		"hiruko_damaged_by_enemy": true,
		"replacement_requirement_completed": false,
		"blessing_gained": 0,
		"karma_gained": 0,
	}, "EXPLOIT")
	await _assert_postbattle_arrival(before_return, "EXPLOIT")


func _test_defy_return() -> void:
	var battle: Variant = await _load_integrated_battle()
	if battle == null:
		return
	_resolve_defy(battle)
	_check(battle.jukain_prescript.get_route_label() == "DEFY", "DEFY: replacement fixture did not resolve")
	_check(battle.result_facts["replacement_requirement_completed"], "DEFY: completion fact was not event-latched")
	_defeat_all_enemies(battle)
	_check(battle._check_battle_result(), "DEFY: Victory was not recognized")
	var before_return: Dictionary = game_state.get_pending_battle_result()
	_assert_result(before_return, "VICTORY", "DEFY", {
		"jukain_attacked_hiruko": false,
		"hiruko_damaged_by_enemy": false,
		"replacement_requirement_completed": true,
		"blessing_gained": 0,
		"karma_gained": 1,
	}, "DEFY")
	await _assert_postbattle_arrival(before_return, "DEFY")


func _test_standalone_victory() -> void:
	game_state.reset_state()
	var battle: Variant = await _load_scene(BATTLE_SCENE_PATH)
	if battle == null:
		return
	battle.automatic_enemy_turns_enabled = false
	_defeat_all_enemies(battle)
	_check(battle._check_battle_result(), "STANDALONE: Victory was not recognized")
	await process_frame
	_check(current_scene == battle and battle.battle_result == battle.BattleResult.VICTORY, "STANDALONE: Victory left the battle terminal")
	_check(battle.status_label.text == "All enemies defeated. Restart to play again.", "STANDALONE: Victory terminal copy changed")
	_check(not battle.battle_return_committed, "STANDALONE: return guard committed without context")
	_check(game_state.get_pending_battle_result().is_empty(), "STANDALONE: story result was published")
	_check(game_state.get_pending_battle_context().is_empty() and game_state.get_pending_vn_sequence().is_empty(), "STANDALONE: routing state was invented")
	battle.restart_battle()
	_check(battle.battle_result == battle.BattleResult.NONE, "STANDALONE: Restart stopped working")
	await _free_current_scene()


func _test_integrated_defeat_retry_victory() -> void:
	var battle: Variant = await _load_integrated_battle()
	if battle == null:
		return
	_defeat_all_party(battle)
	_check(battle._check_battle_result(), "DEFEAT: integrated Defeat was not recognized")
	await process_frame
	_check(current_scene == battle and battle.battle_result == battle.BattleResult.DEFEAT, "DEFEAT: battle incorrectly returned to VN")
	_assert_result(game_state.get_pending_battle_result(), "DEFEAT", "UNRESOLVED", _empty_facts(), "DEFEAT")
	_check(game_state.get_pending_battle_context() == _context(), "DEFEAT: retry context was cleared")
	_check(not battle.battle_return_committed and game_state.get_pending_vn_sequence().is_empty(), "DEFEAT: return routing was prepared")
	battle.restart_battle()
	_check(game_state.get_pending_battle_result().is_empty(), "RETRY: abandoned Defeat result survived Restart")
	_check(battle.result_facts == _empty_facts(), "RETRY: abandoned attempt facts survived Restart")
	_check(battle.battle_context == _context() and game_state.get_pending_battle_context() == _context(), "RETRY: context did not survive")
	_check(not battle.battle_result_committed and not battle.battle_return_committed, "RETRY: terminal guards did not reset")
	_resolve_obey(battle)
	_defeat_all_enemies(battle)
	_check(battle._check_battle_result(), "RETRY: later Victory was not recognized")
	var victory: Dictionary = game_state.get_pending_battle_result()
	_check(victory.get("outcome") == "VICTORY" and victory.get("prescript_route") == "OBEY", "RETRY: fresh Victory did not replace Defeat result")
	await _assert_postbattle_arrival(victory, "RETRY VICTORY")


func _test_invalid_and_missing_return_sequences() -> void:
	for fixture: Dictionary in [
		{"label": "INVALID", "context": {"encounter_id": ENCOUNTER_ID, "return_sequence": "not_a_real_sequence"}, "fragment": "cannot be resolved"},
		{"label": "MISSING", "context": {"encounter_id": ENCOUNTER_ID}, "fragment": "missing or empty"},
	]:
		game_state.reset_state()
		game_state.pending_battle_context = fixture["context"].duplicate(true)
		var battle: Variant = await _load_scene(BATTLE_SCENE_PATH)
		if battle == null:
			continue
		battle.automatic_enemy_turns_enabled = false
		_defeat_all_enemies(battle)
		_check(battle._check_battle_result(), "%s: Victory was not recognized" % fixture["label"])
		await process_frame
		var result: Dictionary = game_state.get_pending_battle_result()
		_assert_result(result, "VICTORY", "UNRESOLVED", _empty_facts(), fixture["label"])
		_check(current_scene == battle and battle.battle_result == battle.BattleResult.VICTORY, "%s: invalid routing left Victory terminal" % fixture["label"])
		_check(not battle.battle_return_committed, "%s: failed route left guard committed" % fixture["label"])
		_check(game_state.get_pending_battle_context() == fixture["context"], "%s: failed route cleared context" % fixture["label"])
		_check(game_state.get_pending_battle_result() == result, "%s: failed route changed result" % fixture["label"])
		_check(game_state.get_pending_vn_sequence().is_empty(), "%s: failed route left a VN handoff" % fixture["label"])
		_check(String(battle.last_battle_return_error).contains(fixture["fragment"]), "%s: routing error was not explicit" % fixture["label"])
		battle.restart_battle()
		_check(battle.battle_result == battle.BattleResult.NONE, "%s: Victory terminal was not usable after routing failure" % fixture["label"])
		await _free_current_scene()


func _test_scene_change_failure() -> void:
	var battle: Variant = await _load_integrated_battle()
	if battle == null:
		return
	battle.vn_return_scene_path = "res://scenes/vn/missing_m6_4_scene.tscn"
	_defeat_all_enemies(battle)
	_check(battle._check_battle_result(), "SCENE FAILURE: Victory was not recognized")
	var result: Dictionary = game_state.get_pending_battle_result()
	await process_frame
	_assert_result(result, "VICTORY", "UNRESOLVED", _empty_facts(), "SCENE FAILURE")
	_check(current_scene == battle, "SCENE FAILURE: battle terminal was replaced")
	_check(not battle.battle_return_committed, "SCENE FAILURE: return guard was not released")
	_check(game_state.get_pending_battle_context() == _context(), "SCENE FAILURE: battle context was cleared")
	_check(game_state.get_pending_battle_result() == result, "SCENE FAILURE: result was lost or changed")
	_check(game_state.get_pending_vn_sequence().is_empty(), "SCENE FAILURE: failed handoff was retained")
	_check(String(battle.last_battle_return_error).contains("Could not return to VN scene"), "SCENE FAILURE: clear error was not reported")
	await _free_current_scene()


func _test_vn_initialization_failure() -> void:
	game_state.reset_state()
	var result := {"outcome": "VICTORY", "facts": _empty_facts()}
	game_state.set_pending_battle_result(result)
	game_state.pending_vn_sequence = "missing_sequence"
	var vn: Variant = await _load_scene(VN_SCENE_PATH)
	if vn == null:
		return
	_check(not vn.dialogue_ready, "VN FAILURE: invalid handoff silently loaded default dialogue")
	_check(vn.speaker_name.text == "Dialogue Error", "VN FAILURE: stable error presentation was not shown")
	_check(game_state.get_pending_vn_sequence() == "missing_sequence", "VN FAILURE: unresolved routing instruction was consumed")
	_check(game_state.get_pending_battle_result() == result, "VN FAILURE: combat result was consumed or changed")
	await _free_current_scene()


func _test_transient_save_reset_and_layout() -> void:
	game_state.reset_state()
	_check(game_state.prepare_battle_context(ENCOUNTER_ID, RETURN_SEQUENCE), "SAVE: battle context fixture failed")
	game_state.set_pending_battle_result({"outcome": "VICTORY", "facts": _empty_facts()})
	_check(game_state.prepare_pending_vn_sequence(RETURN_SEQUENCE), "SAVE: VN handoff fixture failed")
	_check(not game_state.prepare_pending_vn_sequence(RETURN_SEQUENCE), "HANDOFF: duplicate pending sequence was accepted")
	_check(game_state.save_game(PREBATTLE_PATH, "training_01"), "SAVE: normal save failed with transient M6 state")
	var file := FileAccess.open(TEST_SAVE_PATH, FileAccess.READ)
	_check(file != null, "SAVE: payload could not be inspected")
	if file != null:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		_check(typeof(parsed) == TYPE_DICTIONARY, "SAVE: payload is not an object")
		if typeof(parsed) == TYPE_DICTIONARY:
			var saved: Dictionary = parsed
			_check(saved.keys().size() == 4, "SAVE: explicit four-field schema changed")
			for field: String in ["pending_battle_context", "pending_battle_result", "pending_vn_sequence", "encounter_id", "return_sequence", "outcome"]:
				_check(not saved.has(field), "SAVE: transient field '%s' was serialized" % field)
	game_state.reset_state()
	_check(game_state.get_pending_battle_context().is_empty(), "RESET: battle context survived full reset")
	_check(game_state.get_pending_battle_result().is_empty(), "RESET: battle result survived full reset")
	_check(game_state.get_pending_vn_sequence().is_empty(), "RESET: VN handoff survived full reset")

	for viewport_size: Vector2i in [Vector2i(1152, 648), Vector2i(1440, 810)]:
		game_state.reset_state()
		game_state.set_pending_battle_result({"outcome": "VICTORY", "facts": _empty_facts()})
		_check(game_state.prepare_pending_vn_sequence(RETURN_SEQUENCE), "LAYOUT: post-battle handoff failed at %s" % viewport_size)
		root.size = viewport_size
		var vn: Variant = await _load_scene(VN_SCENE_PATH)
		if vn == null:
			continue
		vn.set_deferred("size", Vector2(viewport_size))
		await process_frame
		_check(vn.current_dialogue_path == POSTBATTLE_PATH and vn.dialogue_text.text == FALLBACK_TEXT, "LAYOUT: safe post-battle fallback did not initialize at %s" % viewport_size)
		_check(vn.story_background.get_global_rect().size == Vector2(viewport_size), "LAYOUT: Training Hall background does not fill %s" % viewport_size)
		_check(_inside_viewport(vn.dialogue_panel, Vector2(viewport_size)), "LAYOUT: dialogue panel clips at %s" % viewport_size)
		_check(_inside_viewport(vn.speaker_name, Vector2(viewport_size)) and _inside_viewport(vn.dialogue_text, Vector2(viewport_size)), "LAYOUT: post-battle text clips at %s" % viewport_size)
		_check(game_state.get_pending_vn_sequence().is_empty(), "LAYOUT: successful VN initialization did not consume routing")
		_check(not game_state.get_pending_battle_result().is_empty(), "LAYOUT: VN initialization consumed battle result")
		await _free_current_scene()


func _load_integrated_battle() -> Variant:
	game_state.reset_state()
	_check(game_state.prepare_battle_context(ENCOUNTER_ID, RETURN_SEQUENCE), "FIXTURE: integrated context preparation failed")
	var battle: Variant = await _load_scene(BATTLE_SCENE_PATH)
	if battle != null:
		battle.automatic_enemy_turns_enabled = false
	return battle


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


func _assert_postbattle_arrival(before_return: Dictionary, label: String) -> void:
	await process_frame
	await process_frame
	var vn: Variant = current_scene
	_check(vn != null and vn.name == "VNPrototype", "%s: reusable VN scene did not load" % label)
	if vn == null or vn.name != "VNPrototype":
		return
	_check(vn.current_dialogue_path == POSTBATTLE_PATH, "%s: wrong post-battle sequence loaded" % label)
	var route: String = before_return.get("prescript_route", "")
	_check(vn.current_node_id == REACTION_STARTS.get(route, "") and vn.dialogue_text.text == REACTION_TEXT.get(route, ""), "%s: M6.5 reaction landing is wrong" % label)
	_check(vn.sequence_background.resource_path == BACKGROUND_PATH, "%s: Training Hall continuity was lost" % label)
	_check(game_state.get_pending_vn_sequence().is_empty(), "%s: successful VN initialization retained routing handoff" % label)
	_check(game_state.get_pending_battle_context().is_empty(), "%s: completed encounter context was not cleared" % label)
	_check(game_state.get_pending_battle_result() == before_return, "%s: scene return mutated the result" % label)
	_check(game_state.get_bond("hiruko") == REACTION_BOND.get(route, 0), "%s: M6.5 contextual Bond consequence is wrong" % label)
	await _free_current_scene()


func _resolve_obey(battle: Control) -> void:
	_set_current(battle, battle.jukain_unit)
	_check(battle._process_jukain_turn_start() == &"activated", "OBEY FIXTURE: Prescript did not activate")
	_check(battle.begin_attack_selection() and battle.select_attack_target(&"party_1") and battle.confirm_ally_attack(), "OBEY FIXTURE: real attack did not resolve")


func _resolve_exploit(battle: Control) -> void:
	_set_current(battle, battle.jukain_unit)
	_check(battle._process_jukain_turn_start() == &"activated", "EXPLOIT FIXTURE: Prescript did not activate")
	_check(battle.begin_move_selection() and battle.select_move_destination(BattleUnitModel.Line.MID), "EXPLOIT FIXTURE: Jukain move failed")
	var hiruko_hp_before: int = battle.hiruko_unit.current_hp
	_check(battle.resolve_enemy_turn(), "EXPLOIT FIXTURE: enemy action failed")
	_check(battle.hiruko_unit.current_hp < hiruko_hp_before, "EXPLOIT FIXTURE: enemy did not damage Hiruko")


func _resolve_defy(battle: Control) -> void:
	_set_current(battle, battle.jukain_unit)
	_check(battle._process_jukain_turn_start() == &"activated", "DEFY FIXTURE: Prescript did not activate")
	battle.round_number += 1
	_check(battle._process_jukain_turn_start() == &"defied", "DEFY FIXTURE: deadline did not grant Karma")
	var enemy_a := _find(battle, &"enemy_a")
	_set_current(battle, enemy_a)
	var jukain_hp_before: int = battle.jukain_unit.current_hp
	_check(battle.resolve_enemy_turn(), "DEFY FIXTURE: replacement enemy attack failed")
	_check(battle.jukain_unit.current_hp < jukain_hp_before, "DEFY FIXTURE: replacement did not damage Jukain")


func _set_current(battle: Control, unit: BattleUnit) -> void:
	battle.current_unit = unit
	battle.turn_index = battle.turn_queue.find(unit)
	battle.action_in_progress = false
	battle._clear_action_selection()
	battle._refresh_turn_ui()


func _find(battle: Control, stable_id: StringName) -> BattleUnit:
	for unit: BattleUnit in battle.party_units + battle.enemy_units:
		if unit.stable_id == stable_id:
			return unit
	return null


func _defeat_all_enemies(battle: Control) -> void:
	for enemy: BattleUnit in battle.enemy_units:
		enemy.current_hp = 0
		enemy.defeated = true


func _defeat_all_party(battle: Control) -> void:
	for ally: BattleUnit in battle.party_units:
		ally.current_hp = 0
		ally.defeated = true


func _assert_result(result: Dictionary, outcome: String, route: String, facts: Dictionary, label: String) -> void:
	_check(result.keys().size() == 5, "%s: result schema changed" % label)
	_check(result.get("outcome") == outcome, "%s: wrong outcome" % label)
	_check(result.get("encounter_id") == ENCOUNTER_ID, "%s: wrong encounter ID" % label)
	_check(result.get("prescript_id") == JukainPrescriptStateModel.PRESCRIPT_ID, "%s: wrong Prescript ID" % label)
	_check(result.get("prescript_route") == route, "%s: wrong route" % label)
	_check(result.get("facts") == facts, "%s: facts changed: %s" % [label, result.get("facts")])
	_check(not result.has("return_sequence"), "%s: routing leaked into combat result" % label)


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
