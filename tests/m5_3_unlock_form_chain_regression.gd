extends SceneTree

const BattleUnitModel := preload("res://scripts/battle/battle_unit.gd")
const JukainCombatStateModel := preload("res://scripts/battle/jukain_combat_state.gd")
const JukainPrescriptStateModel := preload("res://scripts/battle/jukain_prescript_state.gd")
const SANDBOX_PATH := "res://scenes/battle/battle_sandbox.tscn"

var failures: Array[String] = []
var checks := 0
var active_scene: Control


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_locked_and_obey_unlock()
	await _test_exploit_and_defy_unlock()
	await _test_debug_and_root_availability()
	await _test_builder_selection_undo_and_cancel()
	await _test_sequential_chain_and_one_action()
	await _test_burn_and_early_target_defeat()
	await _test_victory_and_terminal_guards()
	await _test_basic_attack_no_relock_and_inspector()
	await _test_restart_at_every_chain_stage()
	await _test_hiruko_generic_and_layout()

	if failures.is_empty():
		print("M5.3 unlock and Form Chain regression suite passed (%d checks)." % checks)
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	push_error("M5.3 regression suite failed: %d failure(s), %d checks." % [failures.size(), checks])
	quit(1)


func _test_locked_and_obey_unlock() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_set_current(scene, scene.jukain_unit)
	_check(scene.jukain_state.get_state() == JukainCombatStateModel.State.LOCKED, "Jukain did not start Locked")
	_check(scene.jukain_state.get_effective_atk(scene.jukain_unit.atk) == 1 and scene.jukain_unit.atk == 9, "Locked effective/real ATK fixture is incorrect")
	_check(not scene.get_node("%FormChainButton").visible and "FORM CHAIN: UNAVAILABLE" in _jukain_details(scene), "Locked Form Chain is not unavailable in root UI/inspector")
	var actor_before: BattleUnit = scene.current_unit
	_check(not scene.begin_jukain_form_chain(), "Locked Jukain entered Form Chain")
	_check(scene.current_unit == actor_before and scene.jukain_chain_slots.is_empty(), "Locked chain attempt consumed state")

	_check(scene._process_jukain_turn_start() == &"activated", "Obey fixture did not activate Prescript")
	var hiruko_hp_before: int = scene.hiruko_unit.current_hp
	_check(scene.begin_attack_selection() and scene.select_attack_target(&"party_1"), "Obey ally target did not reach confirmation")
	_check(scene.confirm_ally_attack(), "Obey ally hit did not resolve")
	_check(hiruko_hp_before - scene.hiruko_unit.current_hp == 1, "Obey hit was retroactively increased after unlock")
	_check(scene.hiruko_state.chains_current == 99, "Obey hit bypassed Hiruko's raw-1 Seal pipeline")
	_check(scene.jukain_prescript.phase == JukainPrescriptStateModel.Phase.RESOLVED_OBEY, "Obey route did not remain recorded")
	_check(scene.jukain_state.get_state() == JukainCombatStateModel.State.UNLOCKED, "Obey completion did not unlock Jukain")
	_check(scene.jukain_state.get_effective_atk(scene.jukain_unit.atk) == 9 and scene.jukain_unit.atk == 9, "Obey unlock did not restore derived ATK 9 while preserving real ATK")
	_check(_log_count(scene, "Jukain unlocks after OBEY.") == 1, "Obey unlock transition was not logged exactly once")
	_check(_log_contains(scene, "Effective ATK restored to 9.") and _log_contains(scene, "Replica Form Chain is now available."), "Obey unlock presentation is incomplete")
	for index: int in 4:
		scene._render_battlefield()
		scene._refresh_character_inspector()
	_check(_log_count(scene, "Jukain unlocks after OBEY.") == 1, "Rendering duplicated the Obey unlock event")
	_check("State: UNLOCKED" in _jukain_details(scene) and "FORM CHAIN: AVAILABLE" in _jukain_details(scene), "Inspector did not reflect Obey unlock")
	await _free_scene(scene)


func _test_exploit_and_defy_unlock() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_start_jukain_turn(scene)
	_check(scene.begin_move_selection() and scene.select_move_destination(BattleUnitModel.Line.MID), "Exploit setup Move failed")
	_check(scene.jukain_prescript.phase == JukainPrescriptStateModel.Phase.ORIGINAL_ACTIVE and scene.jukain_state.get_state() == JukainCombatStateModel.State.LOCKED, "Move alone resolved or unlocked Exploit")
	var hiruko_hp_before: int = scene.hiruko_unit.current_hp
	_check(scene.current_unit.stable_id == &"enemy_c" and scene.resolve_enemy_turn(), "Exploit enemy action did not resolve")
	_check(scene.hiruko_unit.current_hp < hiruko_hp_before, "Exploit enemy action did not damage Hiruko")
	_check(scene.jukain_prescript.phase == JukainPrescriptStateModel.Phase.RESOLVED_EXPLOIT and scene.jukain_state.get_state() == JukainCombatStateModel.State.UNLOCKED, "Exploit did not resolve and unlock")
	_check(scene.jukain_prescript.karma_stacks == 0 and _log_count(scene, "Jukain unlocks after EXPLOIT.") == 1, "Exploit added Karma or duplicated unlock")
	await _free_scene(scene)

	scene = await _new_scene(false)
	if scene == null:
		return
	_start_jukain_turn(scene)
	scene.round_number += 1
	_check(scene._process_jukain_turn_start() == &"defied", "Defy deadline did not activate replacement")
	_check(scene.jukain_prescript.phase == JukainPrescriptStateModel.Phase.DEFY_REPLACEMENT_ACTIVE and scene.jukain_prescript.karma_stacks == 1, "Defy did not preserve replacement/Karma state")
	_check(scene.jukain_state.get_state() == JukainCombatStateModel.State.LOCKED and not scene.begin_jukain_form_chain(), "Defy deadline unlocked Jukain before replacement")
	_check(_log_count_containing(scene, "Jukain unlocks") == 0, "Defy deadline emitted an unlock transition")
	var enemy_a := _find_unit(scene, &"enemy_a")
	_set_current(scene, enemy_a)
	var hp_before: int = scene.jukain_unit.current_hp
	_check(scene.resolve_enemy_turn(), "Defy replacement enemy action failed")
	_check(hp_before - scene.jukain_unit.current_hp == 11, "Defy replacement did not retain Karma ×1.20 ceiling damage")
	_check(scene.jukain_prescript.phase == JukainPrescriptStateModel.Phase.RESOLVED_DEFY, "Defy replacement did not resolve route")
	_check(scene.jukain_state.get_state() == JukainCombatStateModel.State.UNLOCKED and scene.jukain_state.get_effective_atk(scene.jukain_unit.atk) == 9, "Completed Defy replacement did not unlock")
	_check(scene.jukain_prescript.karma_stacks == 1 and _log_count(scene, "Jukain unlocks after DEFY.") == 1, "Karma did not persist or Defy unlock duplicated")
	await _free_scene(scene)


func _test_debug_and_root_availability() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_set_current(scene, scene.jukain_unit)
	var phase_before: int = scene.jukain_prescript.phase
	var karma_before: int = scene.jukain_prescript.karma_stacks
	_check(scene.debug_unlock_jukain(), "DEBUG Unlock failed")
	_check(scene.jukain_state.get_state() == JukainCombatStateModel.State.UNLOCKED and scene.jukain_prescript.phase == phase_before and scene.jukain_prescript.karma_stacks == karma_before, "DEBUG Unlock rewrote Prescript/Karma")
	_check(scene.get_node("%AttackButton").visible and scene.get_node("%FormChainButton").visible and scene.get_node("%MoveButton").visible, "Unlocked Jukain root actions are not Attack/Form Chain/Move")
	_check(not scene.get_node("%SkillButton").visible, "Unlocked Jukain received Hiruko's Skill menu")
	_check(scene.begin_jukain_form_chain(), "DEBUG-unlocked Jukain could not begin Form Chain")
	_check(scene.select_jukain_chain_target(&"enemy_a"), "DEBUG-unlocked chain could not select target")
	_check(scene.select_jukain_chain_form(scene.JukainReplicaForm.SCYTHE), "DEBUG-unlocked chain could not fill a slot")
	_check(scene.debug_reset_jukain(), "DEBUG Reset failed")
	_check(scene.jukain_state.get_state() == JukainCombatStateModel.State.LOCKED and scene.jukain_state.get_effective_atk(scene.jukain_unit.atk) == 1, "DEBUG Reset did not restore Locked effective ATK 1")
	_check(scene.jukain_prescript.phase == phase_before and scene.jukain_prescript.karma_stacks == karma_before, "DEBUG Reset rewrote Prescript/Karma")
	_check(not scene._is_jukain_chain_selection_active() and scene.jukain_chain_slots.is_empty(), "DEBUG Reset retained chain target/slots")
	_check(not scene.get_node("%FormChainButton").visible and "FORM CHAIN: UNAVAILABLE" in _jukain_details(scene), "DEBUG Reset did not remove Form Chain availability")
	await _free_scene(scene)


func _test_builder_selection_undo_and_cancel() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_unlock_for_chain(scene)
	var actor_before: BattleUnit = scene.current_unit
	var enemy_a := _find_unit(scene, &"enemy_a")
	var hp_before: int = enemy_a.current_hp
	var inspector_before: StringName = scene.selected_inspector_unit_id
	_check(scene.begin_jukain_form_chain(), "Form Chain target selection did not open")
	_check(_ids(scene.valid_jukain_chain_targets) == [&"enemy_a", &"enemy_b"], "Form Chain did not use nearest occupied enemy line")
	_check(not scene.select_jukain_chain_target(&"enemy_c"), "Form Chain accepted protected Mid target")
	_check(scene.cancel_target_selection(), "Form Chain target-selection Cancel failed")
	_check(scene.current_unit == actor_before and enemy_a.current_hp == hp_before and not scene._is_jukain_chain_selection_active(), "Target Cancel changed gameplay or retained target state")
	_check(scene.selected_inspector_unit_id == inspector_before, "Target Cancel changed inspector selection")
	_check(scene.begin_jukain_form_chain(), "Card-target precedence fixture did not reopen selection")
	_click_card(scene, &"enemy_a")
	_check(scene.jukain_chain_target_id == &"enemy_a" and not scene.selecting_jukain_chain_target, "Enemy card click did not select the Form Chain target")
	_check(scene.selected_inspector_unit_id == inspector_before, "Form Chain target click changed inspector selection")
	_check(scene.cancel_action_selection(), "Card-target precedence fixture did not cancel builder")

	_check(_open_chain_builder(scene, &"enemy_a"), "Form Chain builder did not open")
	_check(scene.jukain_chain_slots.size() == 0 and _slot_text(scene) == "Hit 1: —  |  Hit 2: —  |  Hit 3: —  |  Hit 4: —", "Builder does not expose four empty slots")
	_check(not scene.execute_jukain_form_chain(), "Zero-slot chain executed")
	for count: int in 3:
		_check(scene.select_jukain_chain_form(scene.JukainReplicaForm.SCYTHE), "Scythe selection %d failed" % [count + 1])
		_check(scene.jukain_chain_slots.size() == count + 1, "One Scythe click did not fill exactly one slot")
		_check(not scene.execute_jukain_form_chain(), "Incomplete %d-slot chain executed" % [count + 1])
		_check(enemy_a.current_hp == hp_before and scene.current_unit == actor_before, "Incomplete chain caused damage or consumed turn")
	_check(scene.undo_jukain_chain_form() and scene.jukain_chain_slots.size() == 2, "Undo did not remove the most recent slot")
	_check(scene.select_jukain_chain_form(scene.JukainReplicaForm.SCYTHE) and scene.select_jukain_chain_form(scene.JukainReplicaForm.SCYTHE), "Repeated Scythe could not fill slots 3 and 4")
	_check(scene.jukain_chain_slots.size() == 4 and _slot_text(scene).count("Scythe") == 4, "Four independent repeated Scythe slots were not preserved")
	_check(not scene.select_jukain_chain_form(scene.JukainReplicaForm.SCYTHE), "A fifth chain slot was accepted")
	_check(not scene.get_node("%ExecuteChainButton").disabled, "Complete chain did not enable Execute")
	_check(scene.cancel_action_selection(), "Complete-unexecuted Chain Cancel failed")
	_check(scene.jukain_chain_target_id == &"" and scene.jukain_chain_slots.is_empty(), "Chain Cancel retained target/slots")
	_check(scene.current_unit == actor_before and enemy_a.current_hp == hp_before, "Chain Cancel consumed turn or dealt damage")
	_check(scene.get_node("%AttackButton").visible and scene.get_node("%FormChainButton").visible and scene.get_node("%MoveButton").visible, "Chain Cancel did not return to Jukain root actions")
	await _free_scene(scene)


func _test_sequential_chain_and_one_action() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_unlock_for_chain(scene)
	var enemy_a := _find_unit(scene, &"enemy_a")
	enemy_a.max_hp = 100
	enemy_a.current_hp = 100
	var expected_next := _find_unit(scene, &"enemy_c")
	var turn_index_before: int = scene.turn_index
	_check(_build_complete_chain(scene, &"enemy_a"), "Complete four-Scythe chain could not be built")
	_check(scene.execute_jukain_form_chain(), "Complete chain did not execute")
	_check(enemy_a.current_hp == 46 and not enemy_a.defeated, "M5.4 Scythe hits did not apply 11 + 11 + 11 + 21 to the 100 HP fixture")
	for hit_index: int in 3:
		_check(_log_count(scene, "Hit %d — Scythe: 11 Slash." % [hit_index + 1]) == 1, "Hit %d is missing its M5.4 Front-exposure Scythe damage" % [hit_index + 1])
	_check(_log_count(scene, "Hit 4 — Scythe [FINISHER]: 21 Slash.") == 1, "Hit 4 is missing its M5.4 Scythe finisher")
	_check(_log_index(scene, "Hit 1 — Scythe: 11 Slash.") < _log_index(scene, "Hit 2 — Scythe: 11 Slash.") and _log_index(scene, "Hit 2 — Scythe: 11 Slash.") < _log_index(scene, "Hit 3 — Scythe: 11 Slash.") and _log_index(scene, "Hit 3 — Scythe: 11 Slash.") < _log_index(scene, "Hit 4 — Scythe [FINISHER]: 21 Slash."), "Chain hits were not logged in sequential order")
	_check(not _log_contains(scene, "54 Slash"), "Chain damage was collapsed into one opaque 54-damage event")
	_check(scene.current_unit == expected_next and scene.turn_index == turn_index_before + 1, "Complete chain did not advance the queue exactly once")
	_check(not scene.action_in_progress and not scene._is_jukain_chain_selection_active(), "Completed chain retained action/builder state")
	_check(_log_count_containing(scene, "'s turn.") >= 1 and _log_count(scene, "Enemy C's turn.") == 1, "An actor ran between chain hits or next actor did not activate once")
	await _free_scene(scene)


func _test_burn_and_early_target_defeat() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_unlock_for_chain(scene)
	var jukain_hp_before: int = scene.jukain_unit.current_hp
	var burn_target := _find_unit(scene, &"enemy_a")
	burn_target.max_hp = 100
	burn_target.current_hp = 100
	_check(scene._apply_burn(scene.jukain_unit), "Could not prepare Burning Jukain")
	_check(_build_complete_chain(scene, &"enemy_a") and scene.execute_jukain_form_chain(), "Burning Jukain chain failed")
	_check(_log_count_containing(scene, "Hit ") == 4, "Burning chain did not resolve four hits")
	_check(scene.jukain_unit.current_hp == jukain_hp_before - 5 and scene._get_burn_ticks(scene.jukain_unit) == 1, "Jukain Burn did not tick exactly once after the whole chain")
	_check(_log_count(scene, "Jukain takes 5 Burn damage.") == 1 and _log_index(scene, "Hit 4 — Scythe [FINISHER]: 21 Slash.") < _log_index(scene, "Jukain takes 5 Burn damage."), "Burn timing/order is not four hits then one tick")
	await _free_scene(scene)

	scene = await _new_scene(false)
	if scene == null:
		return
	_unlock_for_chain(scene)
	var enemy_a := _find_unit(scene, &"enemy_a")
	var enemy_b := _find_unit(scene, &"enemy_b")
	enemy_a.current_hp = 20
	var enemy_b_hp: int = enemy_b.current_hp
	_check(_build_complete_chain(scene, &"enemy_a") and scene.execute_jukain_form_chain(), "Early-defeat chain failed")
	_check(enemy_a.defeated and enemy_a.current_hp == 0, "Second M5.4 Scythe did not defeat the 20 HP target")
	_check(_log_count_containing(scene, "Hit ") == 2 and not _log_contains(scene, "Hit 3 —"), "Chain did not stop after intermediate target defeat")
	_check(enemy_b.current_hp == enemy_b_hp, "Early target defeat retargeted another enemy")
	_check(scene.battle_result == scene.BattleResult.NONE and scene.current_unit == _find_unit(scene, &"enemy_c"), "Nonterminal early defeat did not complete one normal action")
	await _free_scene(scene)


func _test_victory_and_terminal_guards() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_unlock_for_chain(scene)
	var enemy_a := _find_unit(scene, &"enemy_a")
	for enemy: BattleUnit in scene.enemy_units:
		if enemy != enemy_a:
			_defeat(enemy)
	enemy_a.current_hp = 20
	var jukain_hp_before: int = scene.jukain_unit.current_hp
	scene._apply_burn(scene.jukain_unit)
	_check(_build_complete_chain(scene, &"enemy_a") and scene.execute_jukain_form_chain(), "Victory-mid-chain execution failed")
	_check(scene.battle_result == scene.BattleResult.VICTORY and scene.current_unit == null, "Final enemy death did not produce immediate Victory")
	_check(_log_count_containing(scene, "Hit ") == 2 and not _log_contains(scene, "Hit 3 —"), "Victory did not stop remaining chain hits")
	_check(scene.jukain_unit.current_hp == jukain_hp_before and scene._get_burn_ticks(scene.jukain_unit) == 2, "Victory chain processed post-Victory Burn")
	_check(not scene.get_node("%FormChainButton").visible and not scene.begin_jukain_form_chain() and not scene.execute_jukain_form_chain(), "Victory allowed Form Chain controls or stale execution")
	await _free_scene(scene)

	scene = await _new_scene(false)
	if scene == null:
		return
	scene.debug_unlock_jukain()
	for ally: BattleUnit in scene.party_units:
		_defeat(ally)
	_check(scene._check_battle_result() and scene.battle_result == scene.BattleResult.DEFEAT, "Controlled Defeat did not resolve")
	_check(not scene.get_node("%FormChainButton").visible and not scene.begin_jukain_form_chain(), "Defeat allowed Form Chain")
	await _free_scene(scene)


func _test_basic_attack_no_relock_and_inspector() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_start_jukain_turn(scene)
	_check(scene.begin_attack_selection() and scene.select_attack_target(&"party_1") and scene.confirm_ally_attack(), "Natural Obey unlock fixture failed")
	_check(scene.jukain_state.get_state() == JukainCombatStateModel.State.UNLOCKED, "Natural unlock fixture did not unlock")
	_check("RESOLVED: OBEY" in _jukain_details(scene) and "FORM CHAIN: AVAILABLE" in _jukain_details(scene), "Inspector lost Prescript route or Form Chain availability")
	_set_current(scene, scene.jukain_unit)
	var enemy_a := _find_unit(scene, &"enemy_a")
	var hp_before: int = enemy_a.current_hp
	_check(scene.begin_attack_selection() and scene.select_attack_target(&"enemy_a"), "Unlocked Basic Attack no longer resolves")
	_check(hp_before - enemy_a.current_hp == 10, "Post-Obey Basic Attack did not apply M6.1 Blessing after effective ATK 9")
	_check(scene.jukain_unit.atk == 9, "Unlocked Basic Attack mutated real ATK")
	_set_current(scene, scene.jukain_unit)
	for step: int in 3:
		scene.round_number += 1
		scene.turn_index = step
		scene._process_jukain_turn_start()
		scene._render_battlefield()
	_check(scene.jukain_state.get_state() == JukainCombatStateModel.State.UNLOCKED and scene.jukain_prescript.phase == JukainPrescriptStateModel.Phase.RESOLVED_OBEY, "Natural unlock re-locked or reactivated Prescript across later turns")
	_check(_log_count(scene, "Jukain unlocks after OBEY.") == 1 and scene.jukain_prescript.karma_stacks == 0, "Later turns duplicated unlock or Karma")
	scene.restart_battle()
	_check(scene.jukain_state.get_state() == JukainCombatStateModel.State.LOCKED and scene.jukain_state.get_effective_atk(scene.jukain_unit.atk) == 1, "Restart from natural Unlocked state did not re-lock Jukain")
	_check(scene.jukain_prescript.phase == JukainPrescriptStateModel.Phase.ORIGINAL_ACTIVE and scene.jukain_prescript.karma_stacks == 0, "Restart from natural Unlocked state did not reset Prescript/Karma")
	await _free_scene(scene)

	scene = await _new_scene(false)
	if scene == null:
		return
	scene.select_inspector_unit(&"party_2")
	_set_current(scene, scene.jukain_unit)
	_check("State: LOCKED" in _details(scene) and "Effective ATK 1" in _details(scene) and "FORM CHAIN: UNAVAILABLE" in _details(scene), "Selected Jukain inspector lacks Locked state")
	_check(scene.debug_unlock_jukain(), "Inspector live-refresh DEBUG Unlock failed")
	_check("State: UNLOCKED" in _details(scene) and "Effective ATK 9" in _details(scene) and "FORM CHAIN: AVAILABLE" in _details(scene), "Inspector did not live-refresh Locked → Unlocked")
	await _free_scene(scene)


func _test_restart_at_every_chain_stage() -> void:
	for filled_slots: int in [-1, 0, 1, 3, 4]:
		var scene := await _new_scene(false)
		if scene == null:
			return
		_unlock_for_chain(scene)
		_check(scene.begin_jukain_form_chain(), "Restart stage %d could not open target selection" % filled_slots)
		if filled_slots >= 0:
			_check(scene.select_jukain_chain_target(&"enemy_a"), "Restart stage %d could not select target" % filled_slots)
			for index: int in filled_slots:
				_check(scene.select_jukain_chain_form(scene.JukainReplicaForm.SCYTHE), "Restart stage %d could not fill slot %d" % [filled_slots, index + 1])
		scene.select_inspector_unit(&"party_2")
		scene.restart_battle()
		_check(scene.jukain_state.get_state() == JukainCombatStateModel.State.LOCKED and scene.jukain_state.get_effective_atk(scene.jukain_unit.atk) == 1 and scene.jukain_unit.atk == 9, "Restart stage %d did not restore Locked/real ATK" % filled_slots)
		_check(scene.jukain_prescript.phase == JukainPrescriptStateModel.Phase.ORIGINAL_ACTIVE and scene.jukain_prescript.karma_stacks == 0, "Restart stage %d retained Prescript/Karma" % filled_slots)
		_check(not scene._is_jukain_chain_selection_active() and scene.jukain_chain_target_id == &"" and scene.jukain_chain_slots.is_empty(), "Restart stage %d retained chain state" % filled_slots)
		_check(scene.selected_inspector_unit_id == &"party_1" and not scene.get_node("%FormChainButton").visible, "Restart stage %d retained inspector/Form Chain UI" % filled_slots)
		_check(not scene.execute_jukain_form_chain(), "Restart stage %d executed a stale chain" % filled_slots)
		await _free_scene(scene)


func _test_hiruko_generic_and_layout() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_check(scene.debug_break_chains() and scene.debug_break_wrapper(), "Hiruko M4 debug state transitions regressed")
	_check(scene.hiruko_state.get_state_label() == "LAEVATAIN", "Hiruko M4 state did not reach LAEVATAIN")
	var party_3 := _find_unit(scene, &"party_3")
	_set_current(scene, party_3)
	var enemy_a := _find_unit(scene, &"enemy_a")
	var hp_before: int = enemy_a.current_hp
	_check(scene.begin_attack_selection() and scene.select_attack_target(&"enemy_a"), "Generic M3 Basic Attack regressed")
	_check(hp_before - enemy_a.current_hp == party_3.atk, "Generic M3 damage changed")
	await _free_scene(scene)

	root.size = Vector2i(1152, 648)
	scene = await _new_scene(false)
	if scene == null:
		return
	_unlock_for_chain(scene)
	await process_frame
	_check(scene.get_node("Margin/Layout").size.y <= 624.0, "M5.3 root exceeds safe 1152×648 height")
	_check(_inside_viewport(scene.get_node("%AttackButton")) and _inside_viewport(scene.get_node("%FormChainButton")) and _inside_viewport(scene.get_node("%MoveButton")), "Unlocked Jukain root actions are outside 1152×648")
	_check(_open_chain_builder(scene, &"enemy_a"), "Layout fixture could not open chain builder")
	_fill_scythes(scene, 4)
	await process_frame
	_check(_inside_viewport(scene.get_node("%ChainSlotsLabel")) and _inside_viewport(scene.get_node("%ScytheFormButton")) and _inside_viewport(scene.get_node("%ExecuteChainButton")) and _inside_viewport(scene.get_node("%CancelButton")), "Chain builder is outside 1152×648")
	var battlefield: Control = scene.get_node("Margin/Layout/Battlefield")
	var stable_height: float = battlefield.size.y
	for index: int in 5:
		scene.party_units[index].line = BattleUnitModel.Line.MID
	scene.party_units[5].line = BattleUnitModel.Line.BACK
	scene._render_battlefield()
	await process_frame
	_check(scene.get_node("%AllyMidUnits").get_child_count() == 5 and is_equal_approx(battlefield.size.y, stable_height), "Five-card line changed height under Form Chain UI")
	root.size = Vector2i(1440, 810)
	await process_frame
	_check(scene.get_node("Margin/Layout").size.y <= 786.0, "M5.3 content exceeds safe 1440×810 height")
	await _free_scene(scene)


func _new_scene(automatic_enemies: bool) -> Control:
	var packed_scene: PackedScene = load(SANDBOX_PATH)
	_check(packed_scene != null, "Battle sandbox scene did not load")
	if packed_scene == null:
		return null
	var scene: Control = packed_scene.instantiate()
	scene.automatic_enemy_turns_enabled = automatic_enemies
	root.add_child(scene)
	active_scene = scene
	await process_frame
	return scene


func _free_scene(scene: Control) -> void:
	if active_scene == scene:
		active_scene = null
	scene.queue_free()
	await process_frame


func _start_jukain_turn(scene: Control) -> void:
	_set_current(scene, scene.jukain_unit)
	_check(scene._process_jukain_turn_start() == &"activated", "Jukain's first real turn did not activate Prescript")


func _set_current(scene: Control, unit: BattleUnit) -> void:
	scene.current_unit = unit
	scene.turn_index = scene.turn_queue.find(unit)
	scene.action_in_progress = false
	scene._clear_action_selection()
	scene._refresh_turn_ui()


func _click_card(scene: Control, unit_id: StringName) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	scene._on_unit_card_input(event, unit_id)


func _unlock_for_chain(scene: Control) -> void:
	_set_current(scene, scene.jukain_unit)
	if scene.jukain_state.get_state() == JukainCombatStateModel.State.LOCKED:
		_check(scene.debug_unlock_jukain(), "Controlled chain fixture could not unlock Jukain")


func _open_chain_builder(scene: Control, target_id: StringName) -> bool:
	return scene.begin_jukain_form_chain() and scene.select_jukain_chain_target(target_id)


func _build_complete_chain(scene: Control, target_id: StringName) -> bool:
	if not _open_chain_builder(scene, target_id):
		return false
	return _fill_scythes(scene, 4)


func _fill_scythes(scene: Control, count: int) -> bool:
	for index: int in count:
		if not scene.select_jukain_chain_form(scene.JukainReplicaForm.SCYTHE):
			return false
	return true


func _find_unit(scene: Control, id: StringName) -> BattleUnit:
	for unit: BattleUnit in scene.party_units + scene.enemy_units:
		if unit.stable_id == id:
			return unit
	return null


func _defeat(unit: BattleUnit) -> void:
	unit.current_hp = 0
	unit.defeated = true


func _ids(units: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	for unit: BattleUnit in units:
		result.append(unit.stable_id)
	return result


func _details(scene: Control) -> String:
	return scene.get_node("%InspectorDetailsLabel").text


func _jukain_details(scene: Control) -> String:
	scene.selected_inspector_unit_id = &"party_2"
	scene._refresh_character_inspector()
	return _details(scene)


func _slot_text(scene: Control) -> String:
	return scene.get_node("%ChainSlotsLabel").text


func _log_contains(scene: Control, fragment: String) -> bool:
	return _log_index(scene, fragment) >= 0


func _log_index(scene: Control, fragment: String) -> int:
	for index: int in scene.combat_log_entries.size():
		if fragment in scene.combat_log_entries[index]:
			return index
	return -1


func _log_count(scene: Control, exact_entry: String) -> int:
	var count := 0
	for entry: String in scene.combat_log_entries:
		if entry == exact_entry:
			count += 1
	return count


func _log_count_containing(scene: Control, fragment: String) -> int:
	var count := 0
	for entry: String in scene.combat_log_entries:
		if fragment in entry:
			count += 1
	return count


func _inside_viewport(control: Control) -> bool:
	var rect := control.get_global_rect()
	return rect.position.x >= 0.0 and rect.position.y >= 0.0 and rect.end.x <= 1152.0 and rect.end.y <= 648.0


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
