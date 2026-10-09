extends SceneTree

const BattleUnitModel := preload("res://scripts/battle/battle_unit.gd")
const JukainCombatStateModel := preload("res://scripts/battle/jukain_combat_state.gd")
const SANDBOX_PATH := "res://scenes/battle/battle_sandbox.tscn"

var failures: Array[String] = []
var checks := 0
var active_scene: Control


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_input_map_and_mapping()
	await _test_hotkey_context_and_single_press()
	await _test_mouse_keyboard_undo_cancel_restart()
	await _test_projection_validation()
	await _test_form_rules_and_rounding()
	await _test_sequential_sword_chain()
	await _test_sequential_whip_chain()
	await _test_mixed_chain_and_one_action()
	await _test_death_victory_and_burn()
	await _test_preserved_state_and_layout()

	if failures.is_empty():
		print("M5.4 Replica forms regression suite passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	push_error("M5.4 regression suite failed: %d failure(s), %d checks." % [failures.size(), checks])
	quit(1)


func _test_input_map_and_mapping() -> void:
	for slot_number: int in range(1, 7):
		var action := StringName("jukain_replica_slot_%d" % slot_number)
		_check(InputMap.has_action(action), "HOTKEY A: missing action %s" % action)
		var events := InputMap.action_get_events(action)
		_check(events.size() == 1 and events[0] is InputEventKey, "HOTKEY B: %s lacks one key binding" % action)
		if events.size() == 1 and events[0] is InputEventKey:
			_check((events[0] as InputEventKey).keycode == KEY_0 + slot_number, "HOTKEY B: %s has wrong default key" % action)

	var scene := await _new_scene(false)
	if scene == null:
		return
	_check(scene.REPLICA_SLOT_MAPPING.size() == 6, "Replica mapping does not contain six slots")
	_check(scene.REPLICA_SLOT_MAPPING[0]["form"] == scene.JukainReplicaForm.SCYTHE, "HOTKEY C: slot 1 is not Scythe")
	_check(scene.REPLICA_SLOT_MAPPING[1]["form"] == scene.JukainReplicaForm.SWORD, "HOTKEY D: slot 2 is not Sword")
	_check(scene.REPLICA_SLOT_MAPPING[2]["form"] == scene.JukainReplicaForm.WHIP, "HOTKEY E: slot 3 is not Whip")
	for index: int in range(3, 6):
		_check(scene.REPLICA_SLOT_MAPPING[index]["form"] == scene.UNASSIGNED_REPLICA_FORM, "HOTKEY F: reserved slot %d is assigned" % [index + 1])
	_check(scene.get_node("%ScytheFormButton").text == "[1] Scythe", "Scythe prompt is not InputMap-derived")
	_check(scene.get_node("%SwordFormButton").text == "[2] Sword", "Sword prompt is not InputMap-derived")
	_check(scene.get_node("%WhipFormButton").text == "[3] Whip", "Whip prompt is not InputMap-derived")
	_check("[4] —" in scene.get_node("%ReplicaReservedLabel").text and "[6] —" in scene.get_node("%ReplicaReservedLabel").text, "Reserved prompt does not expose slots 4–6")
	await _free_scene(scene)


func _test_hotkey_context_and_single_press() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_set_current(scene, scene.jukain_unit)
	_check(not _press_slot(scene, 1) and scene.jukain_chain_slots.is_empty(), "HOTKEY N: Locked Jukain accepted slot 1")
	_unlock_for_chain(scene)
	_check(scene.begin_jukain_form_chain(), "Hotkey target-selection fixture did not open")
	_check(not _press_slot(scene, 1) and scene.jukain_chain_slots.is_empty(), "HOTKEY P: target selection accepted a form hotkey")
	_check(scene.select_jukain_chain_target(&"enemy_a"), "Hotkey fixture could not select target")
	_check(_press_slot(scene, 1) and scene.jukain_chain_slots == [scene.JukainReplicaForm.SCYTHE], "HOTKEY G: 1 did not fill exactly one Scythe")
	_check(not _press_slot(scene, 1, true) and scene.jukain_chain_slots.size() == 1, "HOTKEY L: held/repeat 1 added another slot")
	_check(_press_slot(scene, 2) and scene.jukain_chain_slots[1] == scene.JukainReplicaForm.SWORD, "HOTKEY H: 2 did not append Sword")
	_check(_press_slot(scene, 3) and scene.jukain_chain_slots[2] == scene.JukainReplicaForm.WHIP, "HOTKEY I: 3 did not append Whip")
	_check(_press_slot(scene, 1) and _forms(scene) == [0, 1, 2, 0], "HOTKEY J: 1,2,3,1 representation is wrong")
	_check(not _press_slot(scene, 1) and scene.jukain_chain_slots.size() == 4, "HOTKEY Q: a fifth slot was added")
	await _free_scene(scene)

	scene = await _new_scene(false)
	if scene == null:
		return
	_set_current(scene, scene.hiruko_unit)
	_check(not _press_slot(scene, 1) and scene.jukain_chain_slots.is_empty(), "HOTKEY O: Hiruko turn accepted Replica input")
	scene.debug_unlock_jukain()
	_set_current(scene, scene.jukain_unit)
	_check(not _press_slot(scene, 1) and scene.jukain_chain_slots.is_empty(), "Normal combat root accepted Replica input")
	_check(_open_builder(scene, &"enemy_a"), "Reserved-key fixture could not open builder")
	var actor_before: BattleUnit = scene.current_unit
	for slot_number: int in range(4, 7):
		_check(_press_slot(scene, slot_number), "Reserved slot %d was not recognized safely" % slot_number)
	_check(scene.jukain_chain_slots.is_empty() and scene.current_unit == actor_before, "HOTKEY M: 4/5/6 changed the chain or turn")
	scene.action_in_progress = true
	_check(not _press_slot(scene, 1) and scene.jukain_chain_slots.is_empty(), "Action-in-progress accepted Replica input")
	await _free_scene(scene)

	scene = await _new_scene(false)
	if scene == null:
		return
	_set_current(scene, scene.jukain_unit)
	scene._process_jukain_turn_start()
	_check(scene.begin_attack_selection() and scene.select_attack_target(&"party_1"), "Confirmation-precedence fixture did not open")
	scene.debug_unlock_jukain()
	_check(not _press_slot(scene, 1) and scene.jukain_chain_slots.is_empty(), "Ally attack confirmation did not own numeric input")
	await _free_scene(scene)


func _test_mouse_keyboard_undo_cancel_restart() -> void:
	var keyboard_scene := await _new_scene(false)
	if keyboard_scene == null:
		return
	_unlock_for_chain(keyboard_scene)
	_check(_open_builder(keyboard_scene, &"enemy_a"), "Keyboard parity fixture did not open")
	for slot_number: int in [1, 2, 3, 1]:
		_press_slot(keyboard_scene, slot_number)
	var keyboard_forms := _forms(keyboard_scene)

	var mouse_scene := await _new_scene(false)
	if mouse_scene == null:
		return
	_unlock_for_chain(mouse_scene)
	_check(_open_builder(mouse_scene, &"enemy_a"), "Mouse parity fixture did not open")
	for button_name: String in ["%ScytheFormButton", "%SwordFormButton", "%WhipFormButton", "%ScytheFormButton"]:
		(mouse_scene.get_node(button_name) as Button).pressed.emit()
	_check(_forms(mouse_scene) == keyboard_forms, "HOTKEY K: mouse and keyboard produced different chain state")
	_check(mouse_scene.undo_jukain_chain_form(), "Undo failed after mouse-built chain")
	_check(_press_slot(mouse_scene, 1) and _forms(mouse_scene) == [0, 1, 2, 0], "HOTKEY R: Undo then keyboard selection used the wrong slot")
	_check(mouse_scene.cancel_action_selection() and mouse_scene.jukain_chain_slots.is_empty() and mouse_scene.jukain_chain_target_id == &"", "HOTKEY S: Cancel did not clear keyboard/mouse chain")
	_check(mouse_scene.current_unit == mouse_scene.jukain_unit, "Cancel consumed Jukain's turn")
	_check(_open_builder(mouse_scene, &"enemy_a") and _press_slot(mouse_scene, 1), "Restart fixture could not build a partial chain")
	mouse_scene.restart_battle()
	_check(mouse_scene.jukain_chain_slots.is_empty() and mouse_scene.jukain_chain_target_id == &"" and not mouse_scene._is_jukain_chain_selection_active(), "HOTKEY T: Restart retained chain state")
	_check(mouse_scene.jukain_state.get_state() == JukainCombatStateModel.State.LOCKED and not _press_slot(mouse_scene, 1), "Restart did not suppress Locked Replica shortcuts")
	await _free_scene(keyboard_scene)
	await _free_scene(mouse_scene)


func _test_projection_validation() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_unlock_for_chain(scene)
	scene.jukain_unit.line = BattleUnitModel.Line.BACK
	_prepare_target(scene, &"enemy_a", BattleUnitModel.Line.MID, 300)
	_check(_open_builder(scene, &"enemy_a"), "Projection fixture could not open on Mid target")
	_check(not scene.select_jukain_chain_form(scene.JukainReplicaForm.WHIP), "Back Whip incorrectly reached Mid target")
	_check(scene.jukain_chain_slots.is_empty() and "projected position" in scene.status_label.text, "Rejected Whip changed a slot or lacked feedback")
	_check(scene.select_jukain_chain_form(scene.JukainReplicaForm.SWORD), "Projected Sword was rejected")
	_check(scene.select_jukain_chain_form(scene.JukainReplicaForm.WHIP), "Sword→Whip was not accepted from projected Mid")
	var projection: Dictionary = scene._project_jukain_chain_lines()
	_check(projection["jukain_line"] == BattleUnitModel.Line.MID and projection["target_line"] == BattleUnitModel.Line.FRONT, "Sword/Whip projection did not apply ordered line changes")
	_check(scene.select_jukain_chain_form(scene.JukainReplicaForm.WHIP), "Projected second Whip was rejected against pulled Front target")
	_check(scene.undo_jukain_chain_form(), "Projection Undo failed")
	projection = scene._project_jukain_chain_lines()
	_check(projection["jukain_line"] == BattleUnitModel.Line.MID and projection["target_line"] == BattleUnitModel.Line.FRONT, "Undo did not recompute projection from remaining slots")
	_check(scene.cancel_action_selection() and scene.jukain_chain_slots.is_empty(), "Cancel did not clear projected chain")
	_check(scene.jukain_unit.line == BattleUnitModel.Line.BACK and _find(scene, &"enemy_a").line == BattleUnitModel.Line.MID, "Builder projection mutated live lines")
	await _free_scene(scene)

	scene = await _new_scene(false)
	if scene == null:
		return
	_unlock_for_chain(scene)
	scene.jukain_unit.line = BattleUnitModel.Line.BACK
	_prepare_target(scene, &"enemy_a", BattleUnitModel.Line.FRONT, 300)
	_check(_build_chain(scene, &"enemy_a", [2, 0, 0, 0]), "Runtime-revalidation fixture could not build a valid chain")
	var hp_before: int = _find(scene, &"enemy_a").current_hp
	_find(scene, &"enemy_a").line = BattleUnitModel.Line.MID
	_check(not scene.execute_jukain_form_chain(), "Runtime executed a Whip that live state made unreachable")
	_check(_find(scene, &"enemy_a").current_hp == hp_before and scene.current_unit == scene.jukain_unit and not scene.action_in_progress, "Runtime reach rejection dealt damage or consumed the turn")
	await _free_scene(scene)


func _test_form_rules_and_rounding() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_unlock_for_chain(scene)
	_check(scene._jukain_replica_damage_type(scene.JukainReplicaForm.SCYTHE) == "Slash", "SCYTHE A: damage type is not Slash")
	_check(scene._jukain_replica_damage_type(scene.JukainReplicaForm.SWORD) == "Slash", "SWORD A: damage type is not Slash")
	_check(scene._jukain_replica_damage_type(scene.JukainReplicaForm.WHIP) == "Blunt", "WHIP A: damage type is not Blunt")
	for line: BattleUnit.Line in BattleUnitModel.Line.values():
		_check(scene._jukain_replica_efficiency_percent(scene.JukainReplicaForm.SCYTHE, line) == 100, "SCYTHE B–E: Scythe is not 100%% on line %s" % line)
	_check(scene._jukain_replica_efficiency_percent(scene.JukainReplicaForm.SWORD, BattleUnitModel.Line.FRONT) == 100, "SWORD G: Front efficiency is wrong")
	_check(scene._jukain_replica_efficiency_percent(scene.JukainReplicaForm.SWORD, BattleUnitModel.Line.MID) == 60, "SWORD E: Mid efficiency is wrong")
	_check(scene._jukain_replica_efficiency_percent(scene.JukainReplicaForm.SWORD, BattleUnitModel.Line.BACK) == 35, "Sword Back table value is wrong")
	_check(scene._jukain_replica_efficiency_percent(scene.JukainReplicaForm.WHIP, BattleUnitModel.Line.FRONT) == 100 and scene._jukain_replica_efficiency_percent(scene.JukainReplicaForm.WHIP, BattleUnitModel.Line.MID) == 100 and scene._jukain_replica_efficiency_percent(scene.JukainReplicaForm.WHIP, BattleUnitModel.Line.BACK) == 60, "WHIP B–D: Whip efficiency table is wrong")
	_check(scene._target_line_exposure_percent(BattleUnitModel.Line.FRONT) == 115 and scene._target_line_exposure_percent(BattleUnitModel.Line.MID) == 100 and scene._target_line_exposure_percent(BattleUnitModel.Line.BACK) == 85, "EXPOSURE A–C: Line Exposure table is wrong")
	_check(scene._calculate_jukain_replica_damage(scene.JukainReplicaForm.SCYTHE, 0, BattleUnitModel.Line.BACK, BattleUnitModel.Line.FRONT) == 11, "Scythe Front exposure ceiling is wrong")
	_check(scene._calculate_jukain_replica_damage(scene.JukainReplicaForm.SCYTHE, 1, BattleUnitModel.Line.MID, BattleUnitModel.Line.MID) == 9 and scene._calculate_jukain_replica_damage(scene.JukainReplicaForm.SCYTHE, 2, BattleUnitModel.Line.FRONT, BattleUnitModel.Line.BACK) == 8, "SCYTHE F–H: normal Scythe hit rounding is wrong")
	_check(scene._calculate_jukain_replica_damage(scene.JukainReplicaForm.SCYTHE, 3, BattleUnitModel.Line.FRONT, BattleUnitModel.Line.FRONT) == 21, "SCYTHE I/J: Hit-4 finisher is not one doubled hit")
	_check(scene._calculate_jukain_replica_damage(scene.JukainReplicaForm.SWORD, 3, BattleUnitModel.Line.FRONT, BattleUnitModel.Line.FRONT) == 11, "SCYTHE K: non-Scythe Hit 4 received finisher bonus")
	_check(scene._calculate_jukain_replica_damage(scene.JukainReplicaForm.WHIP, 0, BattleUnitModel.Line.BACK, BattleUnitModel.Line.FRONT) == 7, "WHIP D: Back efficiency did not use one final ceiling")
	_check(scene._advance_line_toward_front(BattleUnitModel.Line.BACK) == BattleUnitModel.Line.MID and scene._advance_line_toward_front(BattleUnitModel.Line.MID) == BattleUnitModel.Line.FRONT and scene._advance_line_toward_front(BattleUnitModel.Line.FRONT) == BattleUnitModel.Line.FRONT, "SWORD B–D: Sword movement table is wrong")
	_check(scene._can_whip_reach(BattleUnitModel.Line.FRONT, BattleUnitModel.Line.MID) and scene._can_whip_reach(BattleUnitModel.Line.MID, BattleUnitModel.Line.FRONT) and scene._can_whip_reach(BattleUnitModel.Line.BACK, BattleUnitModel.Line.FRONT) and not scene._can_whip_reach(BattleUnitModel.Line.BACK, BattleUnitModel.Line.MID), "WHIP E: reach rules are wrong")
	_check(scene._pull_line_toward_front(BattleUnitModel.Line.BACK) == BattleUnitModel.Line.MID and scene._pull_line_toward_front(BattleUnitModel.Line.MID) == BattleUnitModel.Line.FRONT and scene._pull_line_toward_front(BattleUnitModel.Line.FRONT) == BattleUnitModel.Line.FRONT, "WHIP G–I: displacement table is wrong")
	await _free_scene(scene)


func _test_sequential_sword_chain() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_unlock_for_chain(scene)
	scene.jukain_unit.line = BattleUnitModel.Line.BACK
	_prepare_target(scene, &"enemy_a", BattleUnitModel.Line.FRONT, 300)
	_check(_build_chain(scene, &"enemy_a", [1, 1, 0, 0]), "Sword sequence could not be built")
	var hp_before: int = _find(scene, &"enemy_a").current_hp
	_check(scene.execute_jukain_form_chain(), "Sword sequence did not execute")
	_check(scene.jukain_unit.line == BattleUnitModel.Line.FRONT, "SWORD I: two Swords did not move Back→Mid→Front")
	_check(hp_before - _find(scene, &"enemy_a").current_hp == 50, "SWORD E/F/J: sequential Sword chain used stale positions or wrong rounding")
	_check(_log_contains(scene, "Jukain: Back → Mid.") and _log_contains(scene, "Jukain: Mid → Front."), "Sword pre-damage movements were not visible in order")
	_check(_log_contains(scene, "Hit 1 — Sword: 7 Slash.") and _log_contains(scene, "Hit 2 — Sword: 11 Slash."), "Sword did not use its newly advanced line for current damage")
	_check(not _log_contains(scene, "Counter"), "SWORD H: Counter behavior leaked into M5.4")
	await _free_scene(scene)


func _test_sequential_whip_chain() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_unlock_for_chain(scene)
	scene.jukain_unit.line = BattleUnitModel.Line.MID
	_prepare_target(scene, &"enemy_a", BattleUnitModel.Line.MID, 300)
	_check(_build_chain(scene, &"enemy_a", [2, 2, 2, 0]), "Repeated Whip sequence could not be built")
	var hp_before: int = _find(scene, &"enemy_a").current_hp
	_check(scene.execute_jukain_form_chain(), "Repeated Whip sequence did not execute")
	_check(hp_before - _find(scene, &"enemy_a").current_hp == 52, "WHIP F/K/L: pull did not affect later hit exposure")
	_check(_find(scene, &"enemy_a").line == BattleUnitModel.Line.FRONT, "WHIP G/H: surviving target did not finish at Front")
	_check(_log_index(scene, "Hit 1 — Whip: 9 Blunt.") < _log_index(scene, "Enemy A: Mid → Front."), "WHIP F: displacement happened before its own damage")
	_check(_log_contains(scene, "Hit 2 — Whip: 11 Blunt.") and _log_contains(scene, "Enemy A remains Front."), "Repeated Whip did not use/preserve Front state")
	_check(not _log_contains(scene, "Bind"), "WHIP M: Bind behavior leaked into M5.4")
	await _free_scene(scene)

	scene = await _new_scene(false)
	if scene == null:
		return
	_unlock_for_chain(scene)
	scene.jukain_unit.line = BattleUnitModel.Line.MID
	_prepare_target(scene, &"enemy_a", BattleUnitModel.Line.MID, 5)
	_check(_build_chain(scene, &"enemy_a", [2, 0, 0, 0]) and scene.execute_jukain_form_chain(), "Defeated-target Whip fixture failed")
	_check(_find(scene, &"enemy_a").defeated and _find(scene, &"enemy_a").line == BattleUnitModel.Line.MID, "WHIP J: defeated target was displaced")
	await _free_scene(scene)


func _test_mixed_chain_and_one_action() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_unlock_for_chain(scene)
	scene.jukain_unit.line = BattleUnitModel.Line.BACK
	_prepare_target(scene, &"enemy_a", BattleUnitModel.Line.MID, 300)
	var turn_index_before: int = scene.turn_index
	_check(_build_chain(scene, &"enemy_a", [1, 2, 2, 0]), "MIXED H: Sword/Whip/Whip/Scythe could not be built")
	var hp_before: int = _find(scene, &"enemy_a").current_hp
	_check(scene.execute_jukain_form_chain(), "Mixed chain did not execute")
	_check(hp_before - _find(scene, &"enemy_a").current_hp == 47, "MIXED C–H: mixed chain did not compose live line state")
	_check(scene.jukain_unit.line == BattleUnitModel.Line.MID and _find(scene, &"enemy_a").line == BattleUnitModel.Line.FRONT, "Mixed chain ended on wrong lines")
	_check(_log_index(scene, "Hit 1 — Sword: 6 Slash.") < _log_index(scene, "Hit 2 — Whip: 9 Blunt.") and _log_index(scene, "Hit 2 — Whip: 9 Blunt.") < _log_index(scene, "Hit 3 — Whip: 11 Blunt.") and _log_index(scene, "Hit 3 — Whip: 11 Blunt.") < _log_index(scene, "Hit 4 — Scythe [FINISHER]: 21 Slash."), "MIXED A/B: hit order or finisher log is wrong")
	_check(scene.turn_index == turn_index_before + 1 and scene.current_unit == _find(scene, &"enemy_c"), "MIXED I: chain did not consume exactly one action")
	_check(scene.jukain_unit.atk == 9 and _find(scene, &"enemy_a").atk == 9, "EXPOSURE G: form damage mutated stored ATK")
	await _free_scene(scene)


func _test_death_victory_and_burn() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_unlock_for_chain(scene)
	_prepare_target(scene, &"enemy_a", BattleUnitModel.Line.FRONT, 300)
	var jukain_hp_before: int = scene.jukain_unit.current_hp
	scene._apply_burn(scene.jukain_unit)
	_check(_build_chain(scene, &"enemy_a", [0, 1, 2, 0]) and scene.execute_jukain_form_chain(), "Burn mixed-chain fixture failed")
	_check(scene.jukain_unit.current_hp == jukain_hp_before - 5 and scene._get_burn_ticks(scene.jukain_unit) == 1, "MIXED J: Burn did not tick once after the chain")
	_check(_log_count(scene, "Jukain takes 5 Burn damage.") == 1 and _log_index(scene, "Hit 4 — Scythe [FINISHER]") < _log_index(scene, "Jukain takes 5 Burn damage."), "Burn ran before completion or more than once")
	await _free_scene(scene)

	scene = await _new_scene(false)
	if scene == null:
		return
	_unlock_for_chain(scene)
	_prepare_target(scene, &"enemy_a", BattleUnitModel.Line.FRONT, 5)
	var enemy_b_hp: int = _find(scene, &"enemy_b").current_hp
	_check(_build_chain(scene, &"enemy_a", [0, 1, 2, 0]) and scene.execute_jukain_form_chain(), "Early-death mixed-chain fixture failed")
	_check(_log_count_containing(scene, "Hit ") == 1 and _find(scene, &"enemy_b").current_hp == enemy_b_hp, "MIXED K: death did not stop remaining effects/no-retarget")
	_check(scene.jukain_unit.line == BattleUnitModel.Line.FRONT, "Later Sword moved Jukain after target death")
	await _free_scene(scene)

	scene = await _new_scene(false)
	if scene == null:
		return
	_unlock_for_chain(scene)
	var target := _find(scene, &"enemy_a")
	for enemy: BattleUnit in scene.enemy_units:
		if enemy != target:
			_defeat(enemy)
	target.current_hp = 5
	target.max_hp = 5
	jukain_hp_before = scene.jukain_unit.current_hp
	scene._apply_burn(scene.jukain_unit)
	_check(_build_chain(scene, &"enemy_a", [0, 1, 2, 0]) and scene.execute_jukain_form_chain(), "Victory-mid-chain fixture failed")
	_check(scene.battle_result == scene.BattleResult.VICTORY and _log_count_containing(scene, "Hit ") == 1, "MIXED L: Victory did not stop remaining hits")
	_check(scene.jukain_unit.current_hp == jukain_hp_before and scene._get_burn_ticks(scene.jukain_unit) == 2, "Victory processed post-result Burn")
	_check(not _press_slot(scene, 1), "HOTKEY U: Victory accepted Replica shortcut")
	await _free_scene(scene)


func _test_preserved_state_and_layout() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_set_current(scene, scene.jukain_unit)
	_check(scene.jukain_unit.atk == 9 and scene.jukain_state.get_effective_atk(scene.jukain_unit.atk) == 1, "M5.1 Locked/real ATK invariant regressed")
	_check(not scene.begin_jukain_form_chain(), "Locked Form Chain became available")
	_check("REPLICA: 1 Scythe" in _jukain_details(scene) and "3 Whip" in _jukain_details(scene), "Character Inspector lacks compact Replica reference")
	_unlock_for_chain(scene)
	root.size = Vector2i(1152, 648)
	_check(_open_builder(scene, &"enemy_a"), "Layout fixture could not open builder")
	await process_frame
	for node_name: String in ["%ChainSlotsLabel", "%ReplicaReservedLabel", "%ScytheFormButton", "%SwordFormButton", "%WhipFormButton", "%ExecuteChainButton", "%CancelButton"]:
		var control: Control = scene.get_node(node_name)
		_check(_inside_viewport(control, Vector2(1152, 648)), "1152×648: %s is outside viewport at %s" % [node_name, control.get_global_rect()])
	var battlefield: Control = scene.get_node("Margin/Layout/Battlefield")
	var stable_height: float = battlefield.size.y
	for index: int in 5:
		scene.party_units[index].line = BattleUnitModel.Line.MID
	scene.party_units[5].line = BattleUnitModel.Line.BACK
	scene._render_battlefield()
	await process_frame
	_check(scene.get_node("%AllyMidUnits").get_child_count() == 5 and is_equal_approx(battlefield.size.y, stable_height), "Five-card line changed battlefield height")
	root.size = Vector2i(1440, 810)
	await process_frame
	_check(scene.get_node("Margin/Layout").size.y <= 786.0, "1440×810 layout exceeds safe content height")
	await _free_scene(scene)

	scene = await _new_scene(false)
	if scene == null:
		return
	scene.debug_unlock_jukain()
	for ally: BattleUnit in scene.party_units:
		_defeat(ally)
	_check(scene._check_battle_result() and scene.battle_result == scene.BattleResult.DEFEAT and not _press_slot(scene, 1), "HOTKEY U: Defeat accepted Replica shortcut")
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


func _set_current(scene: Control, unit: BattleUnit) -> void:
	scene.current_unit = unit
	scene.turn_index = scene.turn_queue.find(unit)
	scene.action_in_progress = false
	scene._clear_action_selection()
	scene._refresh_turn_ui()


func _unlock_for_chain(scene: Control) -> void:
	_set_current(scene, scene.jukain_unit)
	if scene.jukain_state.get_state() == JukainCombatStateModel.State.LOCKED:
		_check(scene.debug_unlock_jukain(), "Controlled fixture could not unlock Jukain")


func _open_builder(scene: Control, target_id: StringName) -> bool:
	return scene.begin_jukain_form_chain() and scene.select_jukain_chain_target(target_id)


func _build_chain(scene: Control, target_id: StringName, forms: Array) -> bool:
	if not _open_builder(scene, target_id):
		return false
	for form: int in forms:
		if not scene.select_jukain_chain_form(form):
			return false
	return true


func _press_slot(scene: Control, slot_number: int, echo := false) -> bool:
	var event := InputEventKey.new()
	event.keycode = KEY_0 + slot_number
	event.pressed = true
	event.echo = echo
	return scene._handle_jukain_replica_shortcut(event)


func _forms(scene: Control) -> Array[int]:
	var result: Array[int] = []
	for form: int in scene.jukain_chain_slots:
		result.append(form)
	return result


func _prepare_target(scene: Control, target_id: StringName, line: BattleUnit.Line, hp: int) -> void:
	var target := _find(scene, target_id)
	target.line = line
	target.max_hp = hp
	target.current_hp = hp
	target.defeated = false
	for enemy: BattleUnit in scene.enemy_units:
		if enemy == target:
			continue
		if enemy.line < line:
			enemy.line = line
	scene._render_battlefield()


func _find(scene: Control, id: StringName) -> BattleUnit:
	for unit: BattleUnit in scene.party_units + scene.enemy_units:
		if unit.stable_id == id:
			return unit
	return null


func _defeat(unit: BattleUnit) -> void:
	unit.current_hp = 0
	unit.defeated = true


func _jukain_details(scene: Control) -> String:
	scene.selected_inspector_unit_id = &"party_2"
	scene._refresh_character_inspector()
	return scene.get_node("%InspectorDetailsLabel").text


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


func _inside_viewport(control: Control, viewport_size: Vector2) -> bool:
	var rect := control.get_global_rect()
	return rect.position.x >= 0.0 and rect.position.y >= 0.0 and rect.end.x <= viewport_size.x and rect.end.y <= viewport_size.y


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
