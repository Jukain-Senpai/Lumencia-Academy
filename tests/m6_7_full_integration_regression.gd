extends SceneTree

const BattleUnitModel := preload("res://scripts/battle/battle_unit.gd")
const JukainCombatStateModel := preload("res://scripts/battle/jukain_combat_state.gd")
const JukainPrescriptStateModel := preload("res://scripts/battle/jukain_prescript_state.gd")

const VN_SCENE_PATH := "res://scenes/vn/vn_prototype.tscn"
const M6_ENTRY_PATH := "res://scenes/vn/m6_training_hall_entry.tscn"
const BATTLE_SCENE_PATH := "res://scenes/battle/battle_sandbox.tscn"
const M1_DIALOGUE_PATH := "res://data/dialogue/vn_prototype_m1.json"
const PREBATTLE_PATH := "res://data/dialogue/m6_training_hall_prebattle.json"
const POSTBATTLE_PATH := "res://data/dialogue/m6_training_hall_postbattle.json"
const BACKGROUND_PATH := "res://assets/art/backgrounds/academy_training_hall.png"
const DESIGN_PATH := "res://docs/M6_7_FULL_INTEGRATION_REGRESSION_DESIGN.md"
const ENCOUNTER_ID := "m6_training_hall_prototype"
const PRESCRIPT_ID := "prototype_hiruko_hp"
const RETURN_SEQUENCE := "m6_training_hall_postbattle"
const TEST_USER_DIR := "Lumencia Academy M6.7 Regression"
const TEST_SAVE_PATH := "user://lumencia_save.json"

const RECEIPTS := [
	"m6_training_hall_obey_direct_hit_applied",
	"m6_training_hall_exploit_enemy_hit_applied",
	"m6_training_hall_defy_replacement_applied",
	"m6_training_hall_defy_death_applied",
]
const PREBATTLE_LINES := [
	["training_01", "Hiruko", "We're supposed to clear the targets before the exercise ends."],
	["training_02", "Jukain", "Straightforward. That's suspicious."],
	["training_03", "Hiruko", "It's training, Jukain."],
	["training_04", "Jukain", "That's usually when something decides to become complicated."],
	["training_05", "Hiruko", "Just stay focused."],
	["training_06", "Jukain", "I'll treasure those words when this inevitably goes wrong."],
]
const EMPTY_FACTS := {
	"jukain_attacked_hiruko": false,
	"hiruko_damaged_by_enemy": false,
	"replacement_requirement_completed": false,
	"jukain_died_before_prescript_resolution": false,
	"blessing_gained": 0,
	"karma_gained": 0,
}
const RESULT_FIELDS := ["outcome", "encounter_id", "prescript_id", "prescript_route", "facts"]
const RAW_RESULT_FIELDS := [
	"hp",
	"party_units",
	"enemy_units",
	"line_positions",
	"burn_remaining_ticks",
	"seal_hp",
	"turn_queue",
	"chain_selection",
	"combat_ui",
	"receipt",
	"story_node",
	"return_sequence",
]
const RAW_SAVE_FIELDS := [
	"pending_battle_result",
	"pending_battle_context",
	"pending_vn_sequence",
	"blessing",
	"karma",
	"combat_hp",
	"combat_state",
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
	await _test_design_and_contextual_data_ownership()
	await _test_full_obey_loop()
	await _test_full_exploit_loop()
	await _test_full_normal_defy_loop()
	await _test_full_terminal_death_defy_loop()
	await _test_death_revive_real_route_precedence()
	await _test_defeat_restart_victory()
	await _test_standalone_battle_retention()
	await _test_reusable_vn_retention()
	_remove_test_save()
	game_state.reset_state()

	if failures.is_empty():
		print("M6.7 full integration regression suite passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	push_error("M6.7 full integration suite failed: %d failure(s), %d checks." % [failures.size(), checks])
	quit(1)


func _test_design_and_contextual_data_ownership() -> void:
	_check(FileAccess.file_exists(DESIGN_PATH), "AUDIT: M6.7 design record is missing")
	var file := FileAccess.open(POSTBATTLE_PATH, FileAccess.READ)
	_check(file != null, "AUDIT: postbattle data could not be opened")
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	_check(typeof(parsed) == TYPE_DICTIONARY, "AUDIT: postbattle data is not an object")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var expected := {
		"check_direct_hit": ["OBEY", "jukain_attacked_hiruko", RECEIPTS[0], -1],
		"check_enemy_hit": ["EXPLOIT", "hiruko_damaged_by_enemy", RECEIPTS[1], -1],
		"check_replacement": ["DEFY", "replacement_requirement_completed", RECEIPTS[2], 1],
		"check_terminal_death": ["DEFY", "jukain_died_before_prescript_resolution", RECEIPTS[3], 0],
	}
	var found := 0
	for raw_node: Variant in parsed.get("nodes", []):
		if typeof(raw_node) != TYPE_DICTIONARY:
			continue
		var node: Dictionary = raw_node
		var node_id: String = node.get("id", "")
		if not expected.has(node_id):
			continue
		found += 1
		var rule: Array = expected[node_id]
		var condition: Dictionary = node.get("condition", {})
		var effects: Array = node.get("effects", [])
		_check(condition.get("type") == "battle_result_matches", "%s: reaction stopped using contextual result matching" % node_id)
		_check(condition.get("encounter_id") == ENCOUNTER_ID and condition.get("prescript_id") == PRESCRIPT_ID, "%s: encounter/Prescript context changed" % node_id)
		_check(condition.get("prescript_route") == rule[0] and condition.get("required_fact") == rule[1], "%s: route became detached from its authoritative fact" % node_id)
		_check(condition.get("receipt_flag") == rule[2], "%s: receipt mapping changed" % node_id)
		_check(effects.size() == 1 and effects[0].get("type") == "adjust_bond" and int(effects[0].get("amount")) == int(rule[3]), "%s: contextual Bond effect changed" % node_id)
	_check(found == 4, "AUDIT: expected four contextual reaction nodes")
	_check(not FileAccess.file_exists("res://scripts/systems/reaction_manager.gd"), "AUDIT: generic reaction manager was introduced")
	_check(not FileAccess.file_exists("res://scripts/systems/effect_ledger.gd"), "AUDIT: generic effect ledger was introduced")
	_check(not FileAccess.file_exists("res://scripts/systems/story_event_manager.gd"), "AUDIT: generic story event manager was introduced")


func _test_full_obey_loop() -> void:
	var battle: Variant = await _begin_integrated_scenario("OBEY", Vector2i(1152, 648))
	if battle == null:
		return
	_set_current(battle, battle.jukain_unit)
	_check(battle._process_jukain_turn_start() == &"activated", "OBEY: Prescript did not activate on Jukain's real turn")
	var hiruko_hp_before: int = battle.hiruko_unit.current_hp
	_check(battle.begin_attack_selection(), "OBEY: Jukain could not begin the real ally attack")
	_check(battle.select_attack_target(&"party_1"), "OBEY: Hiruko could not be selected")
	_check(battle.confirm_ally_attack(), "OBEY: confirmed direct attack did not resolve")
	_check(hiruko_hp_before - battle.hiruko_unit.current_hp == 1, "OBEY: resolving Locked hit was boosted or did not cause one HP loss")
	_check(battle.result_facts["jukain_attacked_hiruko"] == true, "OBEY: direct-hit fact was not latched")
	_check(battle.jukain_prescript.get_route_label() == "OBEY", "OBEY: route did not resolve through the real attack")
	_check(battle.jukain_state.blessing_stacks == 1 and battle.jukain_prescript.karma_stacks == 0, "OBEY: Blessing/Karma consequence is wrong")
	_check(battle.jukain_state.get_state() == JukainCombatStateModel.State.UNLOCKED, "OBEY: successful resolution did not unlock Jukain")

	_set_current(battle, battle.jukain_unit)
	var enemy_a: BattleUnit = _find(battle, &"enemy_a")
	var enemy_hp_before: int = enemy_a.current_hp
	_check(battle.begin_attack_selection() and battle.select_attack_target(enemy_a.stable_id), "OBEY: later real Jukain attack failed")
	_check(enemy_hp_before - enemy_a.current_hp == 10, "OBEY: later ATK-9 damage did not receive ceiling +10% Blessing")

	var expected_facts := EMPTY_FACTS.duplicate(true)
	expected_facts["jukain_attacked_hiruko"] = true
	expected_facts["blessing_gained"] = 1
	var result := _finish_victory_and_capture_result(battle, "OBEY", expected_facts, "OBEY")
	await _assert_postbattle_persistence(
		result,
		"obey_01",
		"You really hit me because that thing told you to.",
		RECEIPTS[0],
		-1,
		4,
		"OBEY"
	)


func _test_full_exploit_loop() -> void:
	var battle: Variant = await _begin_integrated_scenario("EXPLOIT", Vector2i(1440, 810))
	if battle == null:
		return
	_set_current(battle, battle.jukain_unit)
	_check(battle._process_jukain_turn_start() == &"activated", "EXPLOIT: Prescript did not activate")
	_check(battle.begin_move_selection(), "EXPLOIT: Jukain could not begin real positioning")
	_check(battle.select_move_destination(BattleUnitModel.Line.MID), "EXPLOIT: Jukain could not move Front → Mid")
	_check(battle.jukain_prescript.exploit_setup, "EXPLOIT: real move did not establish exposure")
	_check(battle.current_unit != null and battle.current_unit.stable_id == &"enemy_c", "EXPLOIT: deterministic enemy turn did not follow movement")
	var hiruko_hp_before: int = battle.hiruko_unit.current_hp
	_check(battle.resolve_enemy_turn(), "EXPLOIT: real enemy action did not resolve")
	_check(battle.hiruko_unit.current_hp < hiruko_hp_before, "EXPLOIT: enemy did not actually damage Hiruko")
	_check(battle.result_facts["jukain_attacked_hiruko"] == false, "EXPLOIT: direct-hit fact was fabricated")
	_check(battle.result_facts["hiruko_damaged_by_enemy"] == true, "EXPLOIT: enemy-hit fact was not latched")
	_check(battle.jukain_prescript.get_route_label() == "EXPLOIT", "EXPLOIT: route did not resolve through enemy damage")
	_check(battle.jukain_state.blessing_stacks == 0 and battle.jukain_prescript.karma_stacks == 0, "EXPLOIT: synthetic route reward was added")
	_check(battle.jukain_state.get_state() == JukainCombatStateModel.State.UNLOCKED, "EXPLOIT: successful resolution did not unlock Jukain")

	var expected_facts := EMPTY_FACTS.duplicate(true)
	expected_facts["hiruko_damaged_by_enemy"] = true
	var result := _finish_victory_and_capture_result(battle, "EXPLOIT", expected_facts, "EXPLOIT")
	await _assert_postbattle_persistence(
		result,
		"exploit_01",
		"You moved out of the way on purpose.",
		RECEIPTS[1],
		-1,
		4,
		"EXPLOIT"
	)


func _test_full_normal_defy_loop() -> void:
	var battle: Variant = await _begin_integrated_scenario("NORMAL DEFY", Vector2i(1152, 648))
	if battle == null:
		return
	_set_current(battle, battle.jukain_unit)
	_check(battle._process_jukain_turn_start() == &"activated", "NORMAL DEFY: Prescript did not activate")
	var hiruko_hp_before: int = battle.hiruko_unit.current_hp
	battle.round_number += 1
	_check(battle._process_jukain_turn_start() == &"defied", "NORMAL DEFY: original deadline did not expire")
	_check(battle.hiruko_unit.current_hp == hiruko_hp_before, "NORMAL DEFY: deadline path changed Hiruko HP")
	_check(battle.jukain_prescript.phase == JukainPrescriptStateModel.Phase.DEFY_REPLACEMENT_ACTIVE, "NORMAL DEFY: replacement requirement did not activate")
	_check(battle.jukain_prescript.karma_stacks == 1 and battle.jukain_state.blessing_stacks == 0, "NORMAL DEFY: Karma/Blessing state is wrong")
	_check(battle.jukain_state.get_state() == JukainCombatStateModel.State.LOCKED, "NORMAL DEFY: deadline granted a free unlock")

	var enemy_a: BattleUnit = _find(battle, &"enemy_a")
	_set_current(battle, enemy_a)
	var jukain_hp_before: int = battle.jukain_unit.current_hp
	_check(battle.resolve_enemy_turn(), "NORMAL DEFY: real enemy replacement attack failed")
	_check(jukain_hp_before - battle.jukain_unit.current_hp == 11, "NORMAL DEFY: Karma +20% enemy damage rule changed")
	_check(battle.result_facts["replacement_requirement_completed"] == true, "NORMAL DEFY: replacement completion fact was not latched")
	_check(battle.result_facts["jukain_died_before_prescript_resolution"] == false, "NORMAL DEFY: controlled living path fabricated death history")
	_check(battle.jukain_prescript.get_route_label() == "DEFY", "NORMAL DEFY: replacement did not resolve the real route")
	_check(battle.jukain_prescript.karma_stacks == 1 and battle.jukain_state.get_state() == JukainCombatStateModel.State.UNLOCKED, "NORMAL DEFY: Karma/unlock did not survive replacement completion")

	var expected_facts := EMPTY_FACTS.duplicate(true)
	expected_facts["replacement_requirement_completed"] = true
	expected_facts["karma_gained"] = 1
	var result := _finish_victory_and_capture_result(battle, "DEFY", expected_facts, "NORMAL DEFY")
	await _assert_postbattle_persistence(
		result,
		"defy_01",
		"You could've used me to clear the first Prescript.",
		RECEIPTS[2],
		1,
		5,
		"NORMAL DEFY"
	)


func _test_full_terminal_death_defy_loop() -> void:
	var battle: Variant = await _begin_integrated_scenario("DEATH DEFY", Vector2i(1440, 810))
	if battle == null:
		return
	_set_current(battle, battle.jukain_unit)
	_check(battle._process_jukain_turn_start() == &"activated", "DEATH DEFY: Prescript did not activate")
	battle.jukain_unit.current_hp = 1
	battle.jukain_unit.defeated = false
	var enemy_a: BattleUnit = _find(battle, &"enemy_a")
	_set_current(battle, enemy_a)
	_check(battle.resolve_enemy_turn(), "DEATH DEFY: legitimate enemy attack did not resolve")
	_check(battle.jukain_unit.current_hp == 0 and battle.jukain_unit.defeated, "DEATH DEFY: Jukain did not transition to defeated")
	_check(battle.result_facts["jukain_died_before_prescript_resolution"] == true, "DEATH DEFY: unresolved death fact was not latched")
	_check(not battle.jukain_prescript.is_resolved() and battle.jukain_prescript.get_route_label() == "NONE", "DEATH DEFY: death mutated the live Prescript into a resolved route")
	_check(battle.jukain_prescript.karma_stacks == 0 and battle.result_facts["replacement_requirement_completed"] == false, "DEATH DEFY: death fabricated Karma/replacement")
	_check(battle.jukain_state.get_state() == JukainCombatStateModel.State.LOCKED and battle.jukain_state.blessing_stacks == 0, "DEATH DEFY: death unlocked or blessed Jukain")

	var expected_facts := EMPTY_FACTS.duplicate(true)
	expected_facts["jukain_died_before_prescript_resolution"] = true
	var result := _finish_victory_and_capture_result(battle, "DEFY", expected_facts, "DEATH DEFY")
	_check(not battle.jukain_prescript.is_resolved(), "DEATH DEFY: terminal classification retroactively resolved live Prescript")
	await _assert_postbattle_persistence(
		result,
		"death_defy_01",
		"You got yourself knocked out before dealing with that thing.",
		RECEIPTS[3],
		0,
		4,
		"DEATH DEFY"
	)


func _test_death_revive_real_route_precedence() -> void:
	var battle: Variant = await _begin_integrated_scenario("REVIVE PRECEDENCE", Vector2i(1152, 648))
	if battle == null:
		return
	_set_current(battle, battle.jukain_unit)
	_check(battle._process_jukain_turn_start() == &"activated", "REVIVE PRECEDENCE: Prescript did not activate")
	battle.jukain_unit.current_hp = 1
	var enemy_a: BattleUnit = _find(battle, &"enemy_a")
	_set_current(battle, enemy_a)
	_check(battle.resolve_enemy_turn(), "REVIVE PRECEDENCE: real unresolved death did not occur")
	_check(battle.result_facts["jukain_died_before_prescript_resolution"], "REVIVE PRECEDENCE: death history was not latched")
	battle.jukain_unit.current_hp = battle.jukain_unit.max_hp
	battle.jukain_unit.defeated = false
	_check(battle._is_living(battle.jukain_unit), "REVIVE PRECEDENCE: established simulated revival did not restore living state")
	_set_current(battle, battle.jukain_unit)
	_check(battle.begin_attack_selection() and battle.select_attack_target(&"party_1") and battle.confirm_ally_attack(), "REVIVE PRECEDENCE: revived Jukain did not perform real OBEY action")
	_check(battle.jukain_prescript.get_route_label() == "OBEY", "REVIVE PRECEDENCE: later real route did not win")
	_check(battle.result_facts["jukain_died_before_prescript_resolution"], "REVIVE PRECEDENCE: real resolution erased historical death")

	var expected_facts := EMPTY_FACTS.duplicate(true)
	expected_facts["jukain_attacked_hiruko"] = true
	expected_facts["jukain_died_before_prescript_resolution"] = true
	expected_facts["blessing_gained"] = 1
	var result := _finish_victory_and_capture_result(battle, "OBEY", expected_facts, "REVIVE PRECEDENCE")
	var vn: Variant = await _wait_for_scene_name("VNPrototype", 12, "REVIVE PRECEDENCE Victory → postbattle VN")
	if vn != null:
		_check(vn.current_node_id == "obey_01", "REVIVE PRECEDENCE: historical death stole the real OBEY branch")
		_check(_active_receipts() == [RECEIPTS[0]], "REVIVE PRECEDENCE: real route did not create only the OBEY receipt")
		_check(game_state.get_bond("hiruko") == -1, "REVIVE PRECEDENCE: real-route Bond is wrong")
		_check(game_state.get_pending_battle_result().is_empty(), "REVIVE PRECEDENCE: result was not consumed")
	await _free_current_scene()
	_check(result.get("prescript_route") == "OBEY", "REVIVE PRECEDENCE: captured result changed after return")


func _test_defeat_restart_victory() -> void:
	var battle: Variant = await _begin_integrated_scenario("DEFEAT RETRY", Vector2i(1440, 810))
	if battle == null:
		return
	for ally: BattleUnit in battle.party_units:
		ally.current_hp = 0
		ally.defeated = true
	_check(battle._check_battle_result(), "DEFEAT RETRY: integrated Defeat was not recognized")
	var defeat_result: Dictionary = game_state.get_pending_battle_result()
	_check(defeat_result.get("outcome") == "DEFEAT", "DEFEAT RETRY: terminal result is not Defeat")
	_check(defeat_result.get("prescript_route") == "UNRESOLVED", "DEFEAT RETRY: unstarted route was reclassified")
	_check(_active_receipts().is_empty() and game_state.get_bond("hiruko") == 0, "DEFEAT RETRY: Defeat created a story consequence")
	await process_frame
	_check(current_scene == battle and battle.battle_result == battle.BattleResult.DEFEAT, "DEFEAT RETRY: Defeat returned to successful postbattle VN")
	_check(game_state.get_pending_battle_context() == _battle_context(), "DEFEAT RETRY: retry context was discarded")

	battle.restart_battle()
	_check(game_state.get_pending_battle_result().is_empty(), "DEFEAT RETRY: abandoned result survived Restart")
	_check(battle.result_facts == EMPTY_FACTS, "DEFEAT RETRY: abandoned facts survived Restart")
	_check(battle.jukain_state.blessing_stacks == 0 and battle.jukain_prescript.karma_stacks == 0, "DEFEAT RETRY: abandoned Blessing/Karma survived Restart")
	_check(battle.result_facts["jukain_died_before_prescript_resolution"] == false, "DEFEAT RETRY: death history survived Restart")
	_check(not battle.battle_result_committed and not battle.battle_return_committed and battle.battle_result == battle.BattleResult.NONE, "DEFEAT RETRY: terminal/return guards survived Restart")
	_check(battle.battle_context == _battle_context() and game_state.get_pending_battle_context() == _battle_context(), "DEFEAT RETRY: integrated context did not survive Restart")

	_set_current(battle, battle.jukain_unit)
	_check(battle._process_jukain_turn_start() == &"activated", "DEFEAT RETRY: retry Prescript did not activate")
	_check(battle.begin_attack_selection() and battle.select_attack_target(&"party_1") and battle.confirm_ally_attack(), "DEFEAT RETRY: fresh OBEY action failed")
	var expected_facts := EMPTY_FACTS.duplicate(true)
	expected_facts["jukain_attacked_hiruko"] = true
	expected_facts["blessing_gained"] = 1
	_finish_victory_and_capture_result(battle, "OBEY", expected_facts, "DEFEAT RETRY")
	var vn: Variant = await _wait_for_scene_name("VNPrototype", 12, "DEFEAT RETRY Victory → postbattle VN")
	if vn != null:
		_check(vn.current_node_id == "obey_01", "DEFEAT RETRY: fresh Victory selected wrong branch")
		_check(_active_receipts() == [RECEIPTS[0]], "DEFEAT RETRY: retry did not create exactly one fresh receipt")
		_check(game_state.get_bond("hiruko") == -1, "DEFEAT RETRY: retry did not create exactly one Bond consequence")
		_check(game_state.get_pending_battle_result().is_empty(), "DEFEAT RETRY: fresh result was not consumed")
	await _free_current_scene()


func _test_standalone_battle_retention() -> void:
	await _reset_scenario(Vector2i(1152, 648))
	var battle: Variant = await _load_scene(BATTLE_SCENE_PATH)
	if battle == null:
		return
	battle.automatic_enemy_turns_enabled = false
	_check(battle.battle_context.is_empty() and game_state.get_pending_battle_context().is_empty(), "STANDALONE: story context leaked into direct battle")
	for enemy: BattleUnit in battle.enemy_units:
		enemy.current_hp = 0
		enemy.defeated = true
	_check(battle._check_battle_result(), "STANDALONE: Victory was not recognized")
	await process_frame
	await process_frame
	_check(current_scene == battle and battle.battle_result == battle.BattleResult.VICTORY, "STANDALONE: Victory left the battle terminal")
	_check(game_state.get_pending_battle_result().is_empty(), "STANDALONE: story result was published")
	_check(game_state.get_pending_vn_sequence().is_empty(), "STANDALONE: VN return was prepared")
	_check(_active_receipts().is_empty() and game_state.get_bond("hiruko") == 0, "STANDALONE: story consequence leaked into combat sandbox")
	_check(not battle.battle_return_committed, "STANDALONE: return guard committed without integration context")
	battle.restart_battle()
	_check(battle.battle_result == battle.BattleResult.NONE, "STANDALONE: Restart no longer works")
	await _free_current_scene()


func _test_reusable_vn_retention() -> void:
	await _reset_scenario(Vector2i(1440, 810))
	var vn: Variant = await _load_scene(VN_SCENE_PATH)
	if vn == null:
		return
	_check(vn.current_dialogue_path == M1_DIALOGUE_PATH and vn.current_node_id == "intro_01", "REUSABLE VN: ordinary M1 sequence did not initialize")
	_check(game_state.get_pending_battle_result().is_empty() and _active_receipts().is_empty(), "REUSABLE VN: absence of M6 state was not safe")
	for index: int in 7:
		vn._advance_dialogue()
	_check(vn.current_node_id == "classroom_choice" and vn.awaiting_choice, "REUSABLE VN: normal choice did not appear")
	vn._on_option_selected(0)
	_check(vn.current_node_id == "help_01", "REUSABLE VN: ordinary choice target changed")
	_check(game_state.get_flag("helped_hiruko") and game_state.get_bond("hiruko") == 1, "REUSABLE VN: ordinary flag/Bond effects failed")
	_check(_active_receipts().is_empty(), "REUSABLE VN: unrelated choice created an M6 receipt")
	_check(game_state.save_game(M1_DIALOGUE_PATH, "help_01"), "REUSABLE VN: ordinary line could not be saved")
	vn._advance_dialogue()
	game_state.reset_state()
	vn._load_game()
	_check(vn.current_dialogue_path == M1_DIALOGUE_PATH and vn.current_node_id == "help_01", "REUSABLE VN: exact ordinary VN position was not restored")
	_check(game_state.get_flag("helped_hiruko") and game_state.get_bond("hiruko") == 1, "REUSABLE VN: ordinary persistent state was not restored")
	_check(_active_receipts().is_empty() and game_state.get_pending_battle_result().is_empty(), "REUSABLE VN: load invented M6 state")
	for index: int in 7:
		vn._advance_dialogue()
	_check(vn.current_node_id == "helped_reaction", "REUSABLE VN: ordinary flag condition no longer routed correctly")
	_check(game_state.get_bond("hiruko") == 1, "REUSABLE VN: ordinary save/load duplicated Bond")
	await _free_current_scene()


func _begin_integrated_scenario(label: String, viewport_size: Vector2i) -> Variant:
	await _reset_scenario(viewport_size)
	_check(game_state.get_pending_battle_context().is_empty(), "%s BEFORE BATTLE: context was not absent" % label)
	_check(game_state.get_pending_battle_result().is_empty(), "%s BEFORE BATTLE: pending result was not absent" % label)
	_check(_active_receipts().is_empty(), "%s BEFORE BATTLE: receipts were not empty" % label)
	var vn: Variant = await _load_scene(M6_ENTRY_PATH)
	if vn == null:
		return null
	_check(vn.current_dialogue_path == PREBATTLE_PATH, "%s: M6 entry loaded the wrong sequence" % label)
	for index: int in PREBATTLE_LINES.size():
		var expected: Array = PREBATTLE_LINES[index]
		_check(vn.current_node_id == expected[0], "%s: prebattle line %d node is wrong" % [label, index + 1])
		_check(vn.speaker_name.text == expected[1] and vn.dialogue_text.text == expected[2], "%s: prebattle line %d content is wrong" % [label, index + 1])
		vn._advance_dialogue()
	_check(game_state.get_pending_battle_context() == _battle_context(), "%s AFTER VN LAUNCH: context is wrong" % label)
	_check(game_state.get_pending_battle_result().is_empty() and _active_receipts().is_empty(), "%s AFTER VN LAUNCH: result/receipt appeared early" % label)
	var battle: Variant = await _wait_for_scene_name("BattleSandbox", 12, "%s VN entry → battle" % label)
	if battle == null:
		return null
	battle.automatic_enemy_turns_enabled = false
	_assert_integrated_initialization(battle, label)
	return battle


func _assert_integrated_initialization(battle: Control, label: String) -> void:
	_check(battle.battle_context == _battle_context(), "%s INIT: battle did not intake integrated context" % label)
	_check(game_state.get_pending_battle_context() == _battle_context(), "%s INIT: authoritative context disappeared before terminal" % label)
	_check(battle.hiruko_unit.stable_id == &"party_1" and battle.jukain_unit.stable_id == &"party_2", "%s INIT: Hiruko/Jukain identities changed" % label)
	_check(battle.jukain_unit.line == BattleUnitModel.Line.FRONT and battle.hiruko_unit.line == BattleUnitModel.Line.MID, "%s INIT: controlled formation changed" % label)
	_check(battle.jukain_prescript.phase == JukainPrescriptStateModel.Phase.ORIGINAL_ACTIVE and not battle.jukain_prescript.is_resolved(), "%s INIT: prototype Prescript did not start unresolved/active" % label)
	_check(battle.jukain_state.get_state() == JukainCombatStateModel.State.LOCKED and battle.jukain_state.get_effective_atk(battle.jukain_unit.atk) == 1, "%s INIT: Jukain did not start Locked at effective ATK 1" % label)
	_check(battle.jukain_state.blessing_stacks == 0 and battle.jukain_prescript.karma_stacks == 0, "%s INIT: Blessing/Karma was not zero" % label)
	_check(battle.result_facts == EMPTY_FACTS, "%s INIT: attempt facts were not clean" % label)
	_check(game_state.get_pending_battle_result().is_empty() and _active_receipts().is_empty(), "%s INIT: stale result/receipt contaminated battle" % label)


func _finish_victory_and_capture_result(
	battle: Control,
	expected_route: String,
	expected_facts: Dictionary,
	label: String
) -> Dictionary:
	_check(battle.jukain_prescript.get_route_label() == expected_route or expected_route == "DEFY" and not battle.jukain_prescript.is_resolved(), "%s VICTORY: route was not established before cleanup" % label)
	for enemy: BattleUnit in battle.enemy_units:
		enemy.current_hp = 0
		enemy.defeated = true
	_check(battle._check_battle_result(), "%s VICTORY: real terminal Victory was not recognized" % label)
	var result: Dictionary = game_state.get_pending_battle_result()
	_assert_result_contract(result, "VICTORY", expected_route, expected_facts, label)
	_check(_active_receipts().is_empty(), "%s VICTORY: story receipt existed before VN consequence" % label)
	_check(battle.battle_result_committed and battle.battle_return_committed, "%s VICTORY: result/return guards were not committed" % label)
	_check(game_state.get_pending_vn_sequence() == RETURN_SEQUENCE, "%s VICTORY: VN handoff was not prepared" % label)
	return result


func _assert_result_contract(
	result: Dictionary,
	expected_outcome: String,
	expected_route: String,
	expected_facts: Dictionary,
	label: String
) -> void:
	_check(result.keys().size() == 5, "%s RESULT: top-level field count changed" % label)
	for field: String in RESULT_FIELDS:
		_check(result.has(field), "%s RESULT: missing top-level field '%s'" % [label, field])
	_check(result.get("outcome") == expected_outcome, "%s RESULT: outcome is wrong" % label)
	_check(result.get("encounter_id") == ENCOUNTER_ID, "%s RESULT: encounter identity is wrong" % label)
	_check(result.get("prescript_id") == PRESCRIPT_ID, "%s RESULT: Prescript identity is wrong" % label)
	_check(result.get("prescript_route") == expected_route, "%s RESULT: route is wrong" % label)
	_check(result.get("facts") == expected_facts, "%s RESULT: authoritative facts are wrong: %s" % [label, result.get("facts")])
	for field: String in RAW_RESULT_FIELDS:
		_check(not result.has(field), "%s RESULT: raw combat/story field '%s' leaked" % [label, field])


func _assert_postbattle_persistence(
	_captured_result: Dictionary,
	branch_start: String,
	first_text: String,
	receipt: String,
	expected_bond: int,
	branch_line_count: int,
	label: String
) -> void:
	var vn: Variant = await _wait_for_scene_name("VNPrototype", 12, "%s Victory → postbattle VN" % label)
	if vn == null:
		return
	_check(vn.current_dialogue_path == POSTBATTLE_PATH and vn.current_node_id == branch_start, "%s STORY: wrong contextual branch" % label)
	_check(vn.dialogue_text.text == first_text, "%s STORY: first contextual line changed" % label)
	_check(vn.dialogue_text.text != "[Prototype] No valid post-battle reaction was available.", "%s STORY: valid route reached fallback" % label)
	_check(game_state.get_pending_battle_result().is_empty(), "%s STORY: committed result was not consumed" % label)
	_check(game_state.get_pending_battle_context().is_empty() and game_state.get_pending_vn_sequence().is_empty(), "%s STORY: transport state remained after arrival" % label)
	_check(_active_receipts() == [receipt], "%s STORY: receipt cardinality/identity is wrong" % label)
	_check(game_state.get_bond("hiruko") == expected_bond, "%s STORY: contextual Bond is wrong" % label)
	await _assert_postbattle_layout(vn, label)

	var bond_after_commit: int = game_state.get_bond("hiruko")
	vn._advance_dialogue()
	var saved_node_id: String = vn.current_node_id
	_check(game_state.get_bond("hiruko") == bond_after_commit, "%s STORY: advancing duplicated consequence" % label)
	_check(game_state.save_game(POSTBATTLE_PATH, saved_node_id), "%s SAVE: postbattle line could not be saved" % label)
	var save_data: Dictionary = game_state.read_save_data()
	_assert_save_payload(save_data, saved_node_id, receipt, expected_bond, label)

	for index: int in branch_line_count - 1:
		vn._advance_dialogue()
		_check(game_state.get_bond("hiruko") == bond_after_commit, "%s STORY: branch advancement duplicated Bond" % label)
	_check(vn.current_node_id == "shared_01", "%s STORY: branch did not reach shared ending" % label)
	for index: int in 3:
		vn._advance_dialogue()
		_check(game_state.get_bond("hiruko") == bond_after_commit, "%s STORY: shared ending duplicated Bond" % label)
	_check(vn.scene_ended, "%s STORY: shared ending did not finish" % label)

	game_state.reset_state()
	vn._load_game()
	_check(vn.current_dialogue_path == POSTBATTLE_PATH and vn.current_node_id == saved_node_id, "%s LOAD: exact VN position was not restored" % label)
	_check(_active_receipts() == [receipt] and game_state.get_bond("hiruko") == expected_bond, "%s LOAD: receipt/Bond was not restored" % label)
	_check(game_state.get_pending_battle_result().is_empty() and game_state.get_pending_battle_context().is_empty() and game_state.get_pending_vn_sequence().is_empty(), "%s LOAD: transient battle transport was recreated" % label)
	vn._advance_dialogue()
	_check(game_state.get_bond("hiruko") == expected_bond, "%s LOAD: continuing from save reapplied consequence" % label)
	await _free_current_scene()

	_check(game_state.prepare_pending_vn_sequence(RETURN_SEQUENCE), "%s REENTRY: receipt-only handoff could not be prepared" % label)
	var reentry: Variant = await _load_scene(VN_SCENE_PATH)
	if reentry != null:
		_check(reentry.current_node_id == branch_start, "%s REENTRY: receipt did not identify the same branch" % label)
		_check(_active_receipts() == [receipt] and game_state.get_bond("hiruko") == expected_bond, "%s REENTRY: receipt-only presentation changed story state" % label)
		_check(game_state.get_pending_battle_result().is_empty(), "%s REENTRY: pending result was required or recreated" % label)
		_check(reentry.executed_reaction_effect_node_ids.is_empty(), "%s REENTRY: presentation was marked as a fresh effect commit" % label)
	await _free_current_scene()
	_remove_test_save()


func _assert_save_payload(
	save_data: Dictionary,
	expected_node: String,
	receipt: String,
	expected_bond: int,
	label: String
) -> void:
	_check(save_data.keys().size() == 4, "%s SAVE: top-level schema is not four fields" % label)
	for field: String in ["sequence", "node", "flags", "bonds"]:
		_check(save_data.has(field), "%s SAVE: missing top-level field '%s'" % [label, field])
	_check(save_data.get("sequence") == POSTBATTLE_PATH and save_data.get("node") == expected_node, "%s SAVE: sequence/node snapshot is wrong" % label)
	var flags: Dictionary = save_data.get("flags", {})
	var bonds: Dictionary = save_data.get("bonds", {})
	_check(flags.get(receipt) == true and _active_receipts() == [receipt], "%s SAVE: receipt was not stored inside flags" % label)
	_check(bonds.get("hiruko") == expected_bond, "%s SAVE: Hiruko Bond is wrong" % label)
	for field: String in RAW_SAVE_FIELDS:
		_check(not save_data.has(field), "%s SAVE: transient/raw field '%s' was serialized" % [label, field])
	var serialized := JSON.stringify(save_data).to_lower()
	_check(not serialized.contains("blessing_stacks") and not serialized.contains("karma_stacks"), "%s SAVE: battle-local Blessing/Karma was serialized" % label)


func _assert_postbattle_layout(vn: Control, label: String) -> void:
	vn.set_deferred("size", Vector2(root.size))
	await process_frame
	var viewport_size := Vector2(root.size)
	_check(vn.sequence_background.resource_path == BACKGROUND_PATH, "%s LAYOUT: Training Hall background changed" % label)
	_check(vn.story_background.get_global_rect().size == viewport_size, "%s LAYOUT: background does not fill viewport" % label)
	_check(_inside_viewport(vn.dialogue_panel, viewport_size), "%s LAYOUT: dialogue panel clips" % label)
	_check(_inside_viewport(vn.speaker_name, viewport_size) and _inside_viewport(vn.dialogue_text, viewport_size), "%s LAYOUT: speaker/dialogue text clips" % label)


func _reset_scenario(viewport_size: Vector2i) -> void:
	if current_scene != null:
		await _free_current_scene()
	game_state.reset_state()
	_remove_test_save()
	root.size = viewport_size


func _load_scene(path: String) -> Variant:
	if current_scene != null:
		await _free_current_scene()
	var packed: PackedScene = load(path)
	_check(packed != null, "SCENE: could not load %s" % path)
	if packed == null:
		return null
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	return scene


func _wait_for_scene_name(expected_name: String, frame_limit: int, transition_label: String) -> Variant:
	for frame_index: int in frame_limit:
		if current_scene != null and current_scene.name == expected_name:
			return current_scene
		await process_frame
	_check(false, "%s did not complete within %d frames; expected scene '%s'" % [transition_label, frame_limit, expected_name])
	return null


func _free_current_scene() -> void:
	if current_scene == null:
		return
	var scene := current_scene
	current_scene = null
	if is_instance_valid(scene):
		scene.queue_free()
	await process_frame


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


func _active_receipts() -> Array[String]:
	var active: Array[String] = []
	for receipt: String in RECEIPTS:
		if game_state.get_flag(receipt):
			active.append(receipt)
	return active


func _battle_context() -> Dictionary:
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
