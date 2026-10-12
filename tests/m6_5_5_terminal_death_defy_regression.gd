extends SceneTree

const BattleUnitModel := preload("res://scripts/battle/battle_unit.gd")
const JukainCombatStateModel := preload("res://scripts/battle/jukain_combat_state.gd")
const JukainPrescriptStateModel := preload("res://scripts/battle/jukain_prescript_state.gd")
const BATTLE_SCENE_PATH := "res://scenes/battle/battle_sandbox.tscn"
const VN_SCENE_PATH := "res://scenes/vn/vn_prototype.tscn"
const POSTBATTLE_PATH := "res://data/dialogue/m6_training_hall_postbattle.json"
const ENCOUNTER_ID := "m6_training_hall_prototype"
const PRESCRIPT_ID := "prototype_hiruko_hp"
const RETURN_SEQUENCE := "m6_training_hall_postbattle"
const DEATH_FACT := "jukain_died_before_prescript_resolution"
const FALLBACK_TEXT := "[Prototype] No valid post-battle reaction was available."
const TEST_USER_DIR := "Lumencia Academy M6.5.5 Regression"

const DEATH_REACTION_LINES := [
	["Hiruko", "You got yourself knocked out before dealing with that thing."],
	["Jukain", "I was busy being unconscious."],
	["Hiruko", "That's not an excuse."],
	["Jukain", "It was fairly convincing at the time."],
]
const SHARED_LINES := [
	["Jukain", "Can we agree that was more complicated than advertised?"],
	["Hiruko", "We're done. That's enough for me."],
	["Jukain", "Finally, something we agree on."],
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
	await _test_real_death_then_victory_and_story_return()
	await _test_real_death_then_defeat()
	await _test_death_revive_obey_precedence()
	await _test_death_revive_exploit_precedence()
	await _test_death_revive_normal_defy_precedence()
	await _test_death_after_resolved_routes()
	await _test_damage_source_debug_and_reset_boundaries()
	await _test_story_context_distinction_and_malformed_fallback()
	await _test_layout_and_scope()
	game_state.reset_state()

	if failures.is_empty():
		print("M6.5.5 terminal-death Defy regression suite passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	push_error(
		"M6.5.5 regression suite failed: %d failure(s), %d checks."
		% [failures.size(), checks]
	)
	quit(1)


func _test_real_death_then_victory_and_story_return() -> void:
	var battle: Variant = await _new_battle(true, true)
	if battle == null:
		return
	_activate_prescript(battle, "DEATH VICTORY")
	_kill_jukain_with_enemy_attack(battle, "DEATH VICTORY")
	_check(battle.result_facts[DEATH_FACT], "DEATH VICTORY: real defeat did not latch the death fact")
	_check(not battle.jukain_prescript.is_resolved(), "DEATH VICTORY: death resolved the live Prescript")
	_check(battle.jukain_prescript.get_route_label() == "NONE", "DEATH VICTORY: death created a live route")
	_check(battle.jukain_prescript.karma_stacks == 0, "DEATH VICTORY: death granted Karma")
	_check(not battle.result_facts["replacement_requirement_completed"], "DEATH VICTORY: death completed replacement")
	_check(battle.jukain_state.get_state() == JukainCombatStateModel.State.LOCKED, "DEATH VICTORY: death unlocked Jukain")

	_defeat_all_enemies(battle)
	_check(battle._check_battle_result(), "DEATH VICTORY: remaining party Victory was not recognized")
	var result: Dictionary = game_state.get_pending_battle_result()
	_assert_terminal_death_result(result, "VICTORY", "DEATH VICTORY")
	_check(not battle.jukain_prescript.is_resolved(), "DEATH VICTORY: terminal classification mutated live Prescript")
	_check(battle.jukain_state.get_state() == JukainCombatStateModel.State.LOCKED, "DEATH VICTORY: terminal classification unlocked Jukain")

	await process_frame
	await process_frame
	var vn: Variant = current_scene
	_check(vn != null and vn.name == "VNPrototype", "DEATH VICTORY: integrated Victory did not return to VN")
	if vn == null or vn.name != "VNPrototype":
		return
	_check(vn.current_dialogue_path == POSTBATTLE_PATH, "DEATH VICTORY: wrong postbattle sequence loaded")
	_check(vn.current_node_id == "death_defy_01", "DEATH VICTORY: valid death-Defy reached fallback/wrong branch")
	_check(game_state.get_bond("hiruko") == 0, "DEATH VICTORY: death reaction changed Hiruko Bond")
	_check(game_state.get_pending_battle_result().is_empty(), "DEATH VICTORY: committed result was not consumed")
	_check(game_state.get_flag("m6_training_hall_defy_death_applied"), "DEATH VICTORY: death-Defy receipt was not persisted")
	await _assert_death_reaction_and_shared_ending(vn, "DEATH VICTORY")
	await _free_current_scene()


func _test_real_death_then_defeat() -> void:
	var battle: Variant = await _new_battle(true, false)
	if battle == null:
		return
	_activate_prescript(battle, "DEATH DEFEAT")
	_kill_jukain_with_enemy_attack(battle, "DEATH DEFEAT")
	_defeat_remaining_party(battle)
	_check(battle._check_battle_result(), "DEATH DEFEAT: party Defeat was not recognized")
	var result: Dictionary = game_state.get_pending_battle_result()
	_assert_terminal_death_result(result, "DEFEAT", "DEATH DEFEAT")
	_check(battle.battle_result == battle.BattleResult.DEFEAT, "DEATH DEFEAT: outcome changed from Defeat")
	_check(not battle._request_battle_return(), "DEATH DEFEAT: Defeat accepted a VN return")
	_check(game_state.get_pending_battle_context() == _context(), "DEATH DEFEAT: Defeat discarded retry context")
	await _free_current_scene()


func _test_death_revive_obey_precedence() -> void:
	var battle: Variant = await _new_battle(true, false)
	if battle == null:
		return
	_activate_prescript(battle, "REVIVE OBEY")
	_kill_jukain_with_enemy_attack(battle, "REVIVE OBEY")
	_simulate_revive(battle)
	_set_current(battle, battle.jukain_unit)
	_check(
		battle.begin_attack_selection()
		and battle.select_attack_target(&"party_1")
		and battle.confirm_ally_attack(),
		"REVIVE OBEY: revived Jukain did not resolve the real attack"
	)
	_check(battle.jukain_prescript.get_route_label() == "OBEY", "REVIVE OBEY: real route did not resolve")
	_check(battle.result_facts[DEATH_FACT], "REVIVE OBEY: revival erased historical death")
	_check(battle.result_facts["jukain_attacked_hiruko"], "REVIVE OBEY: direct-hit fact was not recorded")
	_check(battle.result_facts["blessing_gained"] == 1, "REVIVE OBEY: Blessing fact is wrong")
	_finish_victory(battle, "REVIVE OBEY")
	var result: Dictionary = game_state.get_pending_battle_result()
	_check(result["prescript_route"] == "OBEY", "REVIVE OBEY: terminal fallback overwrote real Obey")
	_check(result["facts"][DEATH_FACT], "REVIVE OBEY: result lost historical death")
	_check(result["facts"]["blessing_gained"] == 1, "REVIVE OBEY: result lost Blessing")
	await _free_current_scene()


func _test_death_revive_exploit_precedence() -> void:
	var battle: Variant = await _new_battle(true, false)
	if battle == null:
		return
	_activate_prescript(battle, "REVIVE EXPLOIT")
	_kill_jukain_with_enemy_attack(battle, "REVIVE EXPLOIT")
	_simulate_revive(battle)
	_set_current(battle, battle.jukain_unit)
	_check(
		battle.begin_move_selection()
		and battle.select_move_destination(BattleUnitModel.Line.MID),
		"REVIVE EXPLOIT: revived Jukain could not establish exposure"
	)
	var enemy_c := _find(battle, &"enemy_c")
	_set_current(battle, enemy_c)
	var hiruko_hp_before: int = battle.hiruko_unit.current_hp
	_check(battle.resolve_enemy_turn(), "REVIVE EXPLOIT: enemy action failed")
	_check(battle.hiruko_unit.current_hp < hiruko_hp_before, "REVIVE EXPLOIT: enemy did not damage Hiruko")
	_check(battle.jukain_prescript.get_route_label() == "EXPLOIT", "REVIVE EXPLOIT: real route did not resolve")
	_check(battle.result_facts[DEATH_FACT], "REVIVE EXPLOIT: historical death was cleared")
	_finish_victory(battle, "REVIVE EXPLOIT")
	var result: Dictionary = game_state.get_pending_battle_result()
	_check(result["prescript_route"] == "EXPLOIT", "REVIVE EXPLOIT: terminal fallback overwrote real Exploit")
	_check(result["facts"]["hiruko_damaged_by_enemy"], "REVIVE EXPLOIT: enemy-hit fact was lost")
	_check(result["facts"][DEATH_FACT], "REVIVE EXPLOIT: result lost historical death")
	await _free_current_scene()


func _test_death_revive_normal_defy_precedence() -> void:
	var battle: Variant = await _new_battle(true, false)
	if battle == null:
		return
	_activate_prescript(battle, "REVIVE NORMAL DEFY")
	_kill_jukain_with_enemy_attack(battle, "REVIVE NORMAL DEFY")
	_simulate_revive(battle)
	battle.round_number += 1
	_set_current(battle, battle.jukain_unit)
	_check(battle._process_jukain_turn_start() == &"defied", "REVIVE NORMAL DEFY: deadline did not activate replacement")
	_check(battle.jukain_prescript.karma_stacks == 1, "REVIVE NORMAL DEFY: normal deadline did not grant Karma")
	var enemy_a := _find(battle, &"enemy_a")
	_set_current(battle, enemy_a)
	_check(battle.resolve_enemy_turn(), "REVIVE NORMAL DEFY: replacement attack failed")
	_check(battle.jukain_prescript.get_route_label() == "DEFY", "REVIVE NORMAL DEFY: replacement did not resolve")
	_check(battle.result_facts["replacement_requirement_completed"], "REVIVE NORMAL DEFY: completion fact is false")
	_check(battle.result_facts[DEATH_FACT], "REVIVE NORMAL DEFY: historical death was cleared")
	_finish_victory(battle, "REVIVE NORMAL DEFY")
	var result: Dictionary = game_state.get_pending_battle_result()
	_check(result["prescript_route"] == "DEFY", "REVIVE NORMAL DEFY: terminal route is wrong")
	_check(result["facts"]["replacement_requirement_completed"], "REVIVE NORMAL DEFY: result lost replacement completion")
	_check(result["facts"]["karma_gained"] == 1, "REVIVE NORMAL DEFY: result lost normal Karma")
	_check(result["facts"][DEATH_FACT], "REVIVE NORMAL DEFY: result lost historical death")
	await _free_current_scene()


func _test_death_after_resolved_routes() -> void:
	var obey: Variant = await _new_battle(true, false)
	if obey == null:
		return
	_activate_prescript(obey, "POST-OBEY DEATH")
	_set_current(obey, obey.jukain_unit)
	_check(obey.begin_attack_selection() and obey.select_attack_target(&"party_1") and obey.confirm_ally_attack(), "POST-OBEY DEATH: Obey fixture failed")
	_kill_jukain_with_enemy_attack(obey, "POST-OBEY DEATH")
	_check(not obey.result_facts[DEATH_FACT], "POST-OBEY DEATH: resolved death latched as pre-resolution")
	_finish_victory(obey, "POST-OBEY DEATH")
	_check(game_state.get_pending_battle_result()["prescript_route"] == "OBEY", "POST-OBEY DEATH: Obey was overwritten")
	await _free_current_scene()

	var exploit: Variant = await _new_battle(true, false)
	if exploit == null:
		return
	_activate_prescript(exploit, "POST-EXPLOIT DEATH")
	_set_current(exploit, exploit.jukain_unit)
	_check(exploit.begin_move_selection() and exploit.select_move_destination(BattleUnitModel.Line.MID), "POST-EXPLOIT DEATH: exposure move failed")
	var enemy_c := _find(exploit, &"enemy_c")
	_set_current(exploit, enemy_c)
	_check(exploit.resolve_enemy_turn(), "POST-EXPLOIT DEATH: exploit attack failed")
	_check(exploit.jukain_prescript.get_route_label() == "EXPLOIT", "POST-EXPLOIT DEATH: Exploit did not resolve")
	exploit.jukain_unit.current_hp = 2
	_check(exploit._apply_burn(exploit.jukain_unit), "POST-EXPLOIT DEATH: Burn setup failed")
	_check(exploit._process_burn_tick(exploit.jukain_unit), "POST-EXPLOIT DEATH: Burn damage did not run")
	_check(exploit.jukain_unit.defeated, "POST-EXPLOIT DEATH: Burn did not defeat Jukain")
	_check(not exploit.result_facts[DEATH_FACT], "POST-EXPLOIT DEATH: resolved Burn death latched early-death fact")
	_finish_victory(exploit, "POST-EXPLOIT DEATH")
	_check(game_state.get_pending_battle_result()["prescript_route"] == "EXPLOIT", "POST-EXPLOIT DEATH: Exploit was overwritten")
	await _free_current_scene()

	var normal_defy: Variant = await _new_battle(true, false)
	if normal_defy == null:
		return
	_activate_prescript(normal_defy, "POST-NORMAL-DEFY DEATH")
	normal_defy.round_number += 1
	_set_current(normal_defy, normal_defy.jukain_unit)
	_check(normal_defy._process_jukain_turn_start() == &"defied", "POST-NORMAL-DEFY DEATH: deadline fixture failed")
	var enemy_a := _find(normal_defy, &"enemy_a")
	_set_current(normal_defy, enemy_a)
	_check(normal_defy.resolve_enemy_turn(), "POST-NORMAL-DEFY DEATH: replacement attack failed")
	_check(normal_defy.jukain_prescript.get_route_label() == "DEFY", "POST-NORMAL-DEFY DEATH: normal Defy did not resolve")
	normal_defy.jukain_unit.current_hp = 1
	_set_current(normal_defy, enemy_a)
	_check(normal_defy.resolve_enemy_turn(), "POST-NORMAL-DEFY DEATH: lethal follow-up failed")
	_check(normal_defy.jukain_unit.defeated, "POST-NORMAL-DEFY DEATH: Jukain remained living")
	_check(not normal_defy.result_facts[DEATH_FACT], "POST-NORMAL-DEFY DEATH: resolved Defy death latched pre-resolution fact")
	_finish_victory(normal_defy, "POST-NORMAL-DEFY DEATH")
	var defy_result: Dictionary = game_state.get_pending_battle_result()
	_check(defy_result["prescript_route"] == "DEFY", "POST-NORMAL-DEFY DEATH: Defy route changed")
	_check(defy_result["facts"]["replacement_requirement_completed"], "POST-NORMAL-DEFY DEATH: replacement completion was lost")
	_check(defy_result["facts"]["karma_gained"] == 1, "POST-NORMAL-DEFY DEATH: Karma fact changed")
	_check(not defy_result["facts"][DEATH_FACT], "POST-NORMAL-DEFY DEATH: terminal result invented early death")
	await _free_current_scene()


func _test_damage_source_debug_and_reset_boundaries() -> void:
	var burn_battle: Variant = await _new_battle(true, false)
	if burn_battle == null:
		return
	_activate_prescript(burn_battle, "BURN")
	burn_battle.jukain_unit.current_hp = 2
	_check(burn_battle._apply_burn(burn_battle.jukain_unit), "BURN: setup failed")
	_check(burn_battle._process_burn_tick(burn_battle.jukain_unit), "BURN: legitimate HP loss did not run")
	_check(burn_battle.result_facts[DEATH_FACT], "BURN: source-agnostic transition was not latched")
	var context_before: Dictionary = burn_battle.battle_context.duplicate(true)
	burn_battle.restart_battle()
	_check(not burn_battle.result_facts[DEATH_FACT], "RESTART: abandoned death leaked into retry")
	_check(burn_battle.battle_context == context_before, "RESTART: integrated context was not preserved")
	await _free_current_scene()

	var debug_battle: Variant = await _new_battle(true, false)
	if debug_battle == null:
		return
	_activate_prescript(debug_battle, "DEBUG")
	var hp_before: int = debug_battle.jukain_unit.current_hp
	_check(debug_battle._apply_hp_loss(debug_battle.jukain_unit, 1) == 1, "DEBUG: nonlethal HP-loss fixture failed")
	_check(debug_battle.jukain_unit.current_hp == hp_before - 1 and not debug_battle.result_facts[DEATH_FACT], "DEBUG: nonlethal HP loss latched death")
	debug_battle.jukain_unit.current_hp = 0
	debug_battle.jukain_unit.defeated = true
	_check(not debug_battle.result_facts[DEATH_FACT], "DEBUG: direct field mutation masqueraded as a combat event")
	_check(debug_battle._apply_hp_loss(debug_battle.jukain_unit, 1) == 0 and not debug_battle.result_facts[DEATH_FACT], "DEBUG: already-defeated damage latched a new transition")
	debug_battle._reset_battle_result_tracking()
	_check(not debug_battle.result_facts[DEATH_FACT], "DEBUG RESET: full result reset retained death history")
	await _free_current_scene()

	var standalone: Variant = await _new_battle(false, false)
	if standalone == null:
		return
	_activate_prescript(standalone, "STANDALONE")
	_kill_jukain_with_enemy_attack(standalone, "STANDALONE")
	_check(standalone.result_facts[DEATH_FACT], "STANDALONE: local observer did not record real death")
	_finish_victory(standalone, "STANDALONE")
	_check(game_state.get_pending_battle_result().is_empty(), "STANDALONE: published a story result")
	_check(game_state.get_pending_vn_sequence().is_empty(), "STANDALONE: prepared a VN return")
	_check(game_state.get_bond("hiruko") == 0, "STANDALONE: changed Hiruko Bond")
	await _free_current_scene()


func _test_story_context_distinction_and_malformed_fallback() -> void:
	var normal_result := _result("VICTORY", "DEFY", _facts({
		"replacement_requirement_completed": true,
		DEATH_FACT: true,
		"karma_gained": 1,
	}))
	var normal_vn: Variant = await _load_reaction(normal_result)
	if normal_vn != null:
		_check(normal_vn.current_node_id == "defy_01", "STORY NORMAL DEFY: death branch stole replacement branch")
		_check(normal_vn.dialogue_text.text == "You could've used me to clear the first Prescript.", "STORY NORMAL DEFY: retained dialogue changed")
		_check(game_state.get_bond("hiruko") == 1, "STORY NORMAL DEFY: Bond +1 was not retained")
		_check(game_state.get_pending_battle_result().is_empty(), "STORY NORMAL DEFY: committed result was not consumed")
		_check(game_state.get_flag("m6_training_hall_defy_replacement_applied"), "STORY NORMAL DEFY: replacement receipt was not persisted")
		await _free_current_scene()

	var malformed := _result("VICTORY", "DEFY", _facts({}))
	var fallback: Variant = await _load_reaction(malformed)
	if fallback != null:
		_check(fallback.current_node_id == "reaction_fallback", "MALFORMED DEFY: bare route selected a contextual branch")
		_check(fallback.dialogue_text.text == FALLBACK_TEXT, "MALFORMED DEFY: diagnostic fallback text changed")
		_check(game_state.get_bond("hiruko") == 0, "MALFORMED DEFY: fallback changed Bond")
		_check(game_state.get_pending_battle_result() == malformed, "MALFORMED DEFY: fallback mutated result")
		await _free_current_scene()


func _test_layout_and_scope() -> void:
	for viewport_size: Vector2i in [Vector2i(1152, 648), Vector2i(1440, 810)]:
		root.size = viewport_size
		var result := _result("VICTORY", "DEFY", _facts({DEATH_FACT: true}))
		var vn: Variant = await _load_reaction(result)
		if vn == null:
			continue
		vn.set_deferred("size", Vector2(viewport_size))
		await process_frame
		_check(vn.current_node_id == "death_defy_01", "LAYOUT: death branch did not initialize at %s" % viewport_size)
		_check(vn.story_background.get_global_rect().size == Vector2(viewport_size), "LAYOUT: background does not fill %s" % viewport_size)
		_check(_inside_viewport(vn.dialogue_panel, Vector2(viewport_size)), "LAYOUT: dialogue panel clips at %s" % viewport_size)
		_check(_inside_viewport(vn.speaker_name, Vector2(viewport_size)), "LAYOUT: speaker clips at %s" % viewport_size)
		_check(_inside_viewport(vn.dialogue_text, Vector2(viewport_size)), "LAYOUT: dialogue clips at %s" % viewport_size)
		await _free_current_scene()
	_check(ProjectSettings.get_setting("application/run/main_scene") == VN_SCENE_PATH, "SCOPE: main scene changed")
	_check(not FileAccess.file_exists("res://scripts/systems/revival_manager.gd"), "SCOPE: revival system was introduced")
	_check(not FileAccess.file_exists("res://scripts/systems/reaction_manager.gd"), "SCOPE: reaction manager was introduced")


func _new_battle(integrated: bool, automatic_return: bool) -> Variant:
	if current_scene != null:
		await _free_current_scene()
	game_state.reset_state()
	if integrated:
		_check(game_state.prepare_battle_context(ENCOUNTER_ID, RETURN_SEQUENCE), "FIXTURE: battle context preparation failed")
	var packed: PackedScene = load(BATTLE_SCENE_PATH)
	_check(packed != null, "FIXTURE: battle scene did not load")
	if packed == null:
		return null
	var battle := packed.instantiate()
	battle.automatic_enemy_turns_enabled = false
	battle.automatic_vn_return_enabled = automatic_return
	root.add_child(battle)
	current_scene = battle
	await process_frame
	return battle


func _load_reaction(result: Dictionary) -> Variant:
	if current_scene != null:
		await _free_current_scene()
	game_state.reset_state()
	game_state.set_pending_battle_result(result)
	_check(game_state.prepare_pending_vn_sequence(RETURN_SEQUENCE), "FIXTURE: VN handoff failed")
	var packed: PackedScene = load(VN_SCENE_PATH)
	_check(packed != null, "FIXTURE: VN scene did not load")
	if packed == null:
		return null
	var vn := packed.instantiate()
	root.add_child(vn)
	current_scene = vn
	await process_frame
	return vn


func _free_current_scene() -> void:
	if current_scene == null:
		return
	var scene := current_scene
	current_scene = null
	if is_instance_valid(scene):
		scene.queue_free()
	await process_frame


func _activate_prescript(battle: Control, label: String) -> void:
	_set_current(battle, battle.jukain_unit)
	_check(battle._process_jukain_turn_start() == &"activated", "%s: Prescript did not activate" % label)


func _kill_jukain_with_enemy_attack(battle: Control, label: String) -> void:
	battle.jukain_unit.current_hp = 1
	battle.jukain_unit.defeated = false
	var enemy_a := _find(battle, &"enemy_a")
	_set_current(battle, enemy_a)
	_check(battle.resolve_enemy_turn(), "%s: enemy attack did not resolve" % label)
	_check(battle.jukain_unit.current_hp == 0 and battle.jukain_unit.defeated, "%s: enemy attack did not defeat Jukain" % label)


func _simulate_revive(battle: Control) -> void:
	battle.jukain_unit.current_hp = battle.jukain_unit.max_hp
	battle.jukain_unit.defeated = false
	_check(battle._is_living(battle.jukain_unit), "REVIVE FIXTURE: Jukain was not restored to living state")
	_check(battle.result_facts[DEATH_FACT], "REVIVE FIXTURE: revival cleared historical death")


func _finish_victory(battle: Control, label: String) -> void:
	_defeat_all_enemies(battle)
	_check(battle._check_battle_result(), "%s: Victory was not recognized" % label)
	_check(battle.battle_result == battle.BattleResult.VICTORY, "%s: terminal result was not Victory" % label)


func _defeat_all_enemies(battle: Control) -> void:
	for enemy: BattleUnit in battle.enemy_units:
		enemy.current_hp = 0
		enemy.defeated = true


func _defeat_remaining_party(battle: Control) -> void:
	for ally: BattleUnit in battle.party_units:
		ally.current_hp = 0
		ally.defeated = true


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


func _assert_terminal_death_result(result: Dictionary, outcome: String, label: String) -> void:
	_check(result.get("outcome") == outcome, "%s: wrong outcome" % label)
	_check(result.get("encounter_id") == ENCOUNTER_ID, "%s: wrong encounter" % label)
	_check(result.get("prescript_id") == PRESCRIPT_ID, "%s: wrong Prescript identity" % label)
	_check(result.get("prescript_route") == "DEFY", "%s: unresolved death was not classified Defy" % label)
	var facts: Dictionary = result.get("facts", {})
	_check(facts.get(DEATH_FACT) == true, "%s: result lost death fact" % label)
	_check(facts.get("replacement_requirement_completed") == false, "%s: result fabricated replacement completion" % label)
	_check(facts.get("karma_gained") == 0, "%s: result fabricated Karma" % label)
	_check(facts.keys().size() == 6, "%s: result fact schema is not six fields" % label)


func _assert_death_reaction_and_shared_ending(vn: Control, label: String) -> void:
	for expected: Array in DEATH_REACTION_LINES:
		_check(vn.speaker_name.text == expected[0] and vn.dialogue_text.text == expected[1], "%s: death dialogue line changed" % label)
		_check(game_state.get_bond("hiruko") == 0, "%s: death dialogue changed Bond" % label)
		vn._advance_dialogue()
	_check(vn.current_node_id == "shared_01", "%s: death branch did not reconverge" % label)
	for expected: Array in SHARED_LINES:
		_check(vn.speaker_name.text == expected[0] and vn.dialogue_text.text == expected[1], "%s: shared ending line changed" % label)
		vn._advance_dialogue()
	_check(vn.scene_ended, "%s: shared ending did not terminate" % label)


func _result(outcome: String, route: String, facts: Dictionary) -> Dictionary:
	return {
		"outcome": outcome,
		"encounter_id": ENCOUNTER_ID,
		"prescript_id": PRESCRIPT_ID,
		"prescript_route": route,
		"facts": facts,
	}


func _facts(overrides: Dictionary) -> Dictionary:
	var facts := {
		"jukain_attacked_hiruko": false,
		"hiruko_damaged_by_enemy": false,
		"replacement_requirement_completed": false,
		DEATH_FACT: false,
		"blessing_gained": 0,
		"karma_gained": 0,
	}
	for field: Variant in overrides:
		facts[field] = overrides[field]
	return facts


func _context() -> Dictionary:
	return {"encounter_id": ENCOUNTER_ID, "return_sequence": RETURN_SEQUENCE}


func _inside_viewport(control: Control, viewport_size: Vector2) -> bool:
	var rect := control.get_global_rect()
	return (
		rect.position.x >= 0.0
		and rect.position.y >= 0.0
		and rect.end.x <= viewport_size.x
		and rect.end.y <= viewport_size.y
	)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
