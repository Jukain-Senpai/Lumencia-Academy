extends SceneTree

const BattleUnitModel := preload("res://scripts/battle/battle_unit.gd")
const JukainCombatStateModel := preload("res://scripts/battle/jukain_combat_state.gd")
const JukainPrescriptStateModel := preload("res://scripts/battle/jukain_prescript_state.gd")
const SANDBOX_PATH := "res://scenes/battle/battle_sandbox.tscn"
const ENCOUNTER_ID := "m6_training_hall_prototype"
const RETURN_SEQUENCE := "m6_training_hall_postbattle"

var failures: Array[String] = []
var checks := 0
var game_state: Node
var active_scene: Control


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	game_state = root.get_node("GameState")
	await _test_occupied_depth_and_semantic_lines()
	await _test_basic_hiruko_and_enemy_symmetry()
	await _test_replica_reach_profiles_and_target_selection()
	await _test_projected_chain_recalculation()
	await _test_runtime_sequence_exposure_and_pull()
	await _test_prescript_result_and_restart_compatibility()
	await _test_layout_and_scope()
	game_state.reset_state()

	if failures.is_empty():
		print("M6.3.5 line-blocking reach regression suite passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	push_error("M6.3.5 regression suite failed: %d failure(s), %d checks." % [failures.size(), checks])
	quit(1)


func _test_occupied_depth_and_semantic_lines() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	var enemy_a := _find(scene, &"enemy_a")
	var enemy_b := _find(scene, &"enemy_b")
	var enemy_c := _find(scene, &"enemy_c")
	var enemy_d := _find(scene, &"enemy_d")
	_check(scene._get_occupied_line_depth(BattleUnitModel.Team.ENEMY, BattleUnitModel.Line.FRONT) == 1, "DEPTH A: occupied Front was not depth 1")
	_check(scene._get_occupied_line_depth(BattleUnitModel.Team.ENEMY, BattleUnitModel.Line.MID) == 2, "DEPTH A: occupied Mid was not depth 2")
	_check(scene._get_occupied_line_depth(BattleUnitModel.Team.ENEMY, BattleUnitModel.Line.BACK) == 3, "DEPTH A: occupied Back was not depth 3")
	_check(enemy_a.line == BattleUnitModel.Line.FRONT and enemy_b.line == BattleUnitModel.Line.FRONT, "DEPTH A: same-line units changed semantic line")
	_defeat(enemy_a)
	_check(scene._get_occupied_line_depth(BattleUnitModel.Team.ENEMY, BattleUnitModel.Line.FRONT) == 1, "DEPTH B: one defeated Front unit removed a still-occupied layer")
	_check(scene._get_occupied_line_depth(BattleUnitModel.Team.ENEMY, BattleUnitModel.Line.MID) == 2, "DEPTH B: multiple Front units counted as multiple layers")
	_defeat(enemy_b)
	_check(scene._get_occupied_line_depth(BattleUnitModel.Team.ENEMY, BattleUnitModel.Line.FRONT) == -1, "DEPTH C: defeated Front line still blocked")
	_check(scene._get_occupied_line_depth(BattleUnitModel.Team.ENEMY, BattleUnitModel.Line.MID) == 1, "DEPTH C: Mid did not compress to depth 1")
	_check(scene._get_occupied_line_depth(BattleUnitModel.Team.ENEMY, BattleUnitModel.Line.BACK) == 2, "DEPTH C: Back did not compress to depth 2")
	_check(enemy_c.line == BattleUnitModel.Line.MID and enemy_d.line == BattleUnitModel.Line.BACK, "DEPTH C: compression collapsed semantic lines")
	_defeat(enemy_c)
	_check(scene._get_occupied_line_depth(BattleUnitModel.Team.ENEMY, BattleUnitModel.Line.BACK) == 1, "DEPTH D: lone Back did not become depth 1")
	_check(enemy_d.line == BattleUnitModel.Line.BACK, "DEPTH D: lone Back target stopped being semantically Back")
	_check(scene._get_nearest_occupied_line(BattleUnitModel.Team.ENEMY) == BattleUnitModel.Line.BACK, "DEPTH D: compatibility nearest-line view is wrong")
	await _free_scene(scene)


func _test_basic_hiruko_and_enemy_symmetry() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	var enemy_a := _find(scene, &"enemy_a")
	var enemy_b := _find(scene, &"enemy_b")
	var enemy_c := _find(scene, &"enemy_c")
	var enemy_d := _find(scene, &"enemy_d")
	var targets: Array[BattleUnit] = scene._get_valid_attack_targets(scene.hiruko_unit)
	_check(_has(targets, enemy_a) and _has(targets, enemy_b), "MELEE A: Hiruko could not target living depth-1 Front units")
	_check(not _has(targets, enemy_c) and not _has(targets, enemy_d), "MELEE A: Hiruko reached blocked Mid/Back")
	_defeat(enemy_a)
	targets = scene._get_valid_attack_targets(scene.hiruko_unit)
	_check(_has(targets, enemy_b) and not _has(targets, enemy_c), "MELEE B: one living Front unit did not keep Mid blocked")
	_defeat(enemy_b)
	targets = scene._get_valid_attack_targets(scene.hiruko_unit)
	_check(_has(targets, enemy_c) and not _has(targets, enemy_d), "MELEE C: empty Front did not expose only Mid")
	_check(enemy_c.line == BattleUnitModel.Line.MID, "MELEE C: reachable Mid changed semantic line")
	_set_current(scene, scene.hiruko_unit)
	_check(scene.begin_attack_selection(), "MELEE UI: Basic Attack selection did not open")
	_check(_has(scene.valid_attack_targets, enemy_c) and not _has(scene.valid_attack_targets, enemy_d), "MELEE UI: selectable targets ignored occupied depth")
	scene.cancel_action_selection()
	_check(scene.begin_skill_selection() and scene.select_hiruko_skill(scene.HirukoSkill.KICK), "HIRUKO: Kick selection did not open")
	_check(_has(scene.valid_skill_targets, enemy_c) and not _has(scene.valid_skill_targets, enemy_d), "HIRUKO: Kick target eligibility differs from depth-1 melee")
	scene.cancel_action_selection()
	_defeat(enemy_c)
	targets = scene._get_valid_attack_targets(scene.hiruko_unit)
	_check(_has(targets, enemy_d) and targets.size() == 1, "MELEE D: lone Back was not reachable at depth 1")
	_check(enemy_d.line == BattleUnitModel.Line.BACK, "MELEE D: reachable Back changed semantic line")
	await _free_scene(scene)

	scene = await _new_scene(false)
	if scene == null:
		return
	var front_ally: BattleUnit = scene.jukain_unit
	var mid_ally: BattleUnit = scene.hiruko_unit
	var back_ally := _find(scene, &"party_5")
	for ally: BattleUnit in scene.party_units:
		if ally not in [front_ally, mid_ally, back_ally]:
			_defeat(ally)
	front_ally.line = BattleUnitModel.Line.FRONT
	mid_ally.line = BattleUnitModel.Line.MID
	back_ally.line = BattleUnitModel.Line.BACK
	var enemy_attacker := _find(scene, &"enemy_a")
	targets = scene._get_valid_attack_targets(enemy_attacker)
	_check(targets == [front_ally], "SYMMETRY A: reach-1 enemy did not target only allied Front")
	_defeat(front_ally)
	targets = scene._get_valid_attack_targets(enemy_attacker)
	_check(targets == [mid_ally], "SYMMETRY B: enemy did not expose allied Mid at depth 1")
	_check(mid_ally.line == BattleUnitModel.Line.MID, "SYMMETRY B: allied Mid semantic line collapsed")
	_defeat(mid_ally)
	targets = scene._get_valid_attack_targets(enemy_attacker)
	_check(targets == [back_ally], "SYMMETRY C: enemy did not expose allied Back at depth 1")
	_check(back_ally.line == BattleUnitModel.Line.BACK, "SYMMETRY C: allied Back semantic line collapsed")
	await _free_scene(scene)


func _test_replica_reach_profiles_and_target_selection() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_check(scene._jukain_replica_max_occupied_depth(scene.JukainReplicaForm.SWORD, BattleUnitModel.Line.FRONT) == 1, "SWORD: Front profile is not depth 1")
	_check(scene._jukain_replica_max_occupied_depth(scene.JukainReplicaForm.SWORD, BattleUnitModel.Line.BACK) == 1, "SWORD: Back profile is not depth 1")
	_check(scene._jukain_replica_max_occupied_depth(scene.JukainReplicaForm.WHIP, BattleUnitModel.Line.BACK) == 1, "WHIP: Back profile is not depth 1")
	_check(scene._jukain_replica_max_occupied_depth(scene.JukainReplicaForm.WHIP, BattleUnitModel.Line.MID) == 2, "WHIP: Mid profile is not depth 2")
	_check(scene._jukain_replica_max_occupied_depth(scene.JukainReplicaForm.WHIP, BattleUnitModel.Line.FRONT) == 3, "WHIP: Front profile is not depth 3")
	for line: BattleUnit.Line in [BattleUnitModel.Line.FRONT, BattleUnitModel.Line.MID, BattleUnitModel.Line.BACK]:
		_check(scene._jukain_replica_max_occupied_depth(scene.JukainReplicaForm.SCYTHE, line) == 3, "SCYTHE: profile was not depth 3 from %s" % BattleUnitModel.line_name(line))

	_unlock_for_chain(scene)
	_check(scene.begin_jukain_form_chain(), "CHAIN TARGETS: target selection did not open")
	_check(scene.valid_jukain_chain_targets.size() == 4, "CHAIN TARGETS: Scythe-capable selection did not include every living enemy")
	for enemy: BattleUnit in scene.enemy_units:
		_check(_has(scene.valid_jukain_chain_targets, enemy), "CHAIN TARGETS: %s was omitted" % enemy.display_name)
	scene.cancel_action_selection()

	var front := _find(scene, &"enemy_a")
	var mid := _find(scene, &"enemy_c")
	var back := _find(scene, &"enemy_d")
	scene.jukain_unit.line = BattleUnitModel.Line.MID
	_check(scene._is_target_reachable(scene.jukain_unit, front, 2), "WHIP MID: Front depth 1 was unreachable")
	_check(scene._is_target_reachable(scene.jukain_unit, mid, 2), "WHIP MID: Mid depth 2 was unreachable")
	_check(not scene._is_target_reachable(scene.jukain_unit, back, 2), "WHIP MID: blocked Back depth 3 was reachable")
	_defeat(front)
	_defeat(_find(scene, &"enemy_b"))
	_check(scene._get_occupied_line_depth(BattleUnitModel.Team.ENEMY, BattleUnitModel.Line.MID) == 1, "WHIP MID: Mid did not become depth 1")
	_check(scene._get_occupied_line_depth(BattleUnitModel.Team.ENEMY, BattleUnitModel.Line.BACK) == 2, "WHIP MID: Back did not become depth 2")
	_check(scene._is_target_reachable(scene.jukain_unit, back, 2), "WHIP MID: Back remained blocked after Front emptied")

	scene.restart_battle()
	_unlock_for_chain(scene)
	scene.jukain_unit.line = BattleUnitModel.Line.FRONT
	back = _find(scene, &"enemy_d")
	_check(scene._is_target_reachable(scene.jukain_unit, back, 3), "WHIP FRONT: Back depth 3 was unreachable")
	scene.jukain_unit.line = BattleUnitModel.Line.BACK
	_check(scene._is_target_reachable(scene.jukain_unit, back, scene.FULL_FIELD_MAX_OCCUPIED_DEPTH), "GUN SUPPORT: synthetic depth-3 profile from Back could not reach Back")
	_check(back.line == BattleUnitModel.Line.BACK, "GUN SUPPORT: range profile changed target semantic line")
	await _free_scene(scene)


func _test_projected_chain_recalculation() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_unlock_for_chain(scene)
	scene.jukain_unit.line = BattleUnitModel.Line.BACK
	_check(_open_builder(scene, &"enemy_d"), "PROJECTION A: Back target could not be held for Scythe")
	_check(scene.select_jukain_chain_form(scene.JukainReplicaForm.SCYTHE), "PROJECTION A: Scythe could not reach Back depth 3")
	_check(not scene.select_jukain_chain_form(scene.JukainReplicaForm.SWORD), "PROJECTION A: Sword reached Back depth 3 after Back→Mid advance")
	_check(not scene.select_jukain_chain_form(scene.JukainReplicaForm.WHIP), "PROJECTION A: Back Whip reached Back depth 3")
	_check(scene.jukain_chain_slots == [scene.JukainReplicaForm.SCYTHE], "PROJECTION A: rejected forms changed slots")
	scene.cancel_action_selection()

	scene.jukain_unit.line = BattleUnitModel.Line.BACK
	_check(_open_builder(scene, &"enemy_a"), "PROJECTION SWORD: Front target could not be held")
	_check(scene.select_jukain_chain_form(scene.JukainReplicaForm.SWORD), "PROJECTION SWORD: post-advance depth-1 Sword was rejected")
	var projection: Dictionary = scene._project_jukain_chain_lines()
	_check(projection["jukain_line"] == BattleUnitModel.Line.MID, "PROJECTION SWORD: Back→Mid self-advance was not projected")
	_check(_find(scene, &"enemy_a").line == BattleUnitModel.Line.FRONT, "PROJECTION SWORD: builder mutated live target")
	scene.cancel_action_selection()

	scene.jukain_unit.line = BattleUnitModel.Line.MID
	_check(_open_builder(scene, &"enemy_d"), "PROJECTION B: Back target could not be held")
	_check(not scene.select_jukain_chain_form(scene.JukainReplicaForm.WHIP), "PROJECTION B: Mid Whip reached blocked Back depth 3")
	scene.cancel_action_selection()
	_defeat(_find(scene, &"enemy_a"))
	_defeat(_find(scene, &"enemy_b"))
	_check(_open_builder(scene, &"enemy_d"), "PROJECTION C: compressed Back target could not be held")
	_check(scene.select_jukain_chain_form(scene.JukainReplicaForm.WHIP), "PROJECTION C: Mid Whip did not reach compressed Back depth 2")
	projection = scene._project_jukain_chain_lines()
	_check(projection["target_line"] == BattleUnitModel.Line.MID, "PROJECTION C: surviving Back target was not projected to Mid")
	_check(scene.undo_jukain_chain_form(), "PROJECTION C: Undo failed")
	projection = scene._project_jukain_chain_lines()
	_check(projection["jukain_line"] == BattleUnitModel.Line.MID and projection["target_line"] == BattleUnitModel.Line.BACK, "PROJECTION C: Undo did not recompute from live lines")
	_check(_find(scene, &"enemy_d").line == BattleUnitModel.Line.BACK, "PROJECTION C: projection mutated live Back target")
	await _free_scene(scene)

	scene = await _new_scene(false)
	if scene == null:
		return
	_unlock_for_chain(scene)
	scene.jukain_unit.line = BattleUnitModel.Line.FRONT
	_check(_open_builder(scene, &"enemy_d"), "PROJECTION D: Front Whip Back target could not be held")
	_check(scene.select_jukain_chain_form(scene.JukainReplicaForm.WHIP), "PROJECTION D: Front Whip did not reach Back through three occupied depths")
	await _free_scene(scene)


func _test_runtime_sequence_exposure_and_pull() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_unlock_for_chain(scene)
	scene.jukain_unit.line = BattleUnitModel.Line.FRONT
	var mid := _find(scene, &"enemy_c")
	mid.max_hp = 200
	mid.current_hp = 200
	_check(_build_chain(scene, &"enemy_c", [scene.JukainReplicaForm.WHIP, scene.JukainReplicaForm.SWORD, scene.JukainReplicaForm.SCYTHE, scene.JukainReplicaForm.SCYTHE]), "RUNTIME A: projected Whip→Sword chain was rejected")
	_check(scene.execute_jukain_form_chain(), "RUNTIME A: live sequential chain did not execute")
	_check(mid.current_hp == 148, "RUNTIME A: semantic exposure/order produced wrong 52 damage total")
	_check(mid.line == BattleUnitModel.Line.FRONT, "RUNTIME A: Whip did not pull surviving Mid target to Front")
	_check(_log_before(scene, "Hit 1 — Whip: 9 Blunt.", "Enemy C: Mid → Front."), "RUNTIME A: Whip pulled before Mid-exposure damage")
	_check(_log_before(scene, "Enemy C: Mid → Front.", "Hit 2 — Sword: 11 Slash."), "RUNTIME A: Sword did not use updated live Front state")
	await _free_scene(scene)

	scene = await _new_scene(false)
	if scene == null:
		return
	_unlock_for_chain(scene)
	var back := _find(scene, &"enemy_d")
	for enemy: BattleUnit in scene.enemy_units:
		if enemy != back:
			_defeat(enemy)
	scene.jukain_unit.line = BattleUnitModel.Line.BACK
	back.max_hp = 200
	back.current_hp = 200
	_check(scene._get_occupied_line_depth(BattleUnitModel.Team.ENEMY, BattleUnitModel.Line.BACK) == 1, "EXPOSURE: lone Back was not depth 1")
	_check(scene._target_line_exposure_percent(back.line) == 85, "EXPOSURE: lone Back stopped using 85%")
	_check(_build_chain(scene, &"enemy_d", [scene.JukainReplicaForm.WHIP, scene.JukainReplicaForm.SCYTHE, scene.JukainReplicaForm.SCYTHE, scene.JukainReplicaForm.SCYTHE]), "EXPOSURE: lone-Back chain was rejected")
	_check(scene.execute_jukain_form_chain(), "EXPOSURE: lone-Back chain did not execute")
	_check(back.current_hp == 159, "EXPOSURE: pre-pull Back then later Mid exposure produced wrong total")
	_check(back.line == BattleUnitModel.Line.MID, "EXPOSURE: surviving Back target did not pull to Mid")
	_check(_log_before(scene, "Hit 1 — Whip: 5 Blunt.", "Enemy D: Back → Mid."), "EXPOSURE: Back exposure was not applied before pull")
	_check(_log_contains(scene, "Hit 2 — Scythe: 9 Slash."), "EXPOSURE: later hit did not use Mid exposure")
	await _free_scene(scene)


func _test_prescript_result_and_restart_compatibility() -> void:
	var scene := await _new_scene(true)
	if scene == null:
		return
	_set_current(scene, scene.jukain_unit)
	_check(scene._process_jukain_turn_start() == &"activated", "PRESCRIPT: activation failed")
	_check(scene.begin_move_selection() and scene.select_move_destination(BattleUnitModel.Line.MID), "PRESCRIPT: Exploit setup move failed")
	_check(scene.current_unit.stable_id == &"enemy_c", "PRESCRIPT: controlled enemy turn changed")
	var hiruko_hp_before: int = scene.hiruko_unit.current_hp
	_check(scene.resolve_enemy_turn(), "PRESCRIPT: symmetric enemy attack failed")
	_check(scene.hiruko_unit.current_hp < hiruko_hp_before, "PRESCRIPT: enemy no longer damaged exposed Hiruko")
	_check(scene.jukain_prescript.get_route_label() == "EXPLOIT", "PRESCRIPT: Exploit became impossible")
	_check(scene.result_facts["hiruko_damaged_by_enemy"], "M6.3: enemy-Hiruko fact was not event-latched")
	for enemy: BattleUnit in scene.enemy_units:
		_defeat(enemy)
	_check(scene._check_battle_result(), "M6.3: integrated Victory was not recognized")
	var result: Dictionary = game_state.get_pending_battle_result()
	_check(result.get("outcome") == "VICTORY" and result.get("prescript_route") == "EXPLOIT", "M6.3: result outcome/route changed")
	_check(result.get("facts", {}).get("hiruko_damaged_by_enemy") == true, "M6.3: result lost event-driven fact")
	_check(result.get("facts", {}).get("blessing_gained") == 0 and result.get("facts", {}).get("karma_gained") == 0, "M6.3: reach patch invented rewards")

	scene.restart_battle()
	_check(scene.battle_context == {"encounter_id": ENCOUNTER_ID, "return_sequence": RETURN_SEQUENCE}, "RESTART: integrated context was not preserved")
	_check(game_state.get_pending_battle_result().is_empty(), "RESTART: pending result was not cleared")
	_check(scene._get_occupied_line_depth(BattleUnitModel.Team.ENEMY, BattleUnitModel.Line.FRONT) == 1 and scene._get_occupied_line_depth(BattleUnitModel.Team.ENEMY, BattleUnitModel.Line.MID) == 2 and scene._get_occupied_line_depth(BattleUnitModel.Team.ENEMY, BattleUnitModel.Line.BACK) == 3, "RESTART: original occupied-depth structure was not derived")
	_check(scene.jukain_unit.line == BattleUnitModel.Line.FRONT and _find(scene, &"enemy_c").line == BattleUnitModel.Line.MID and _find(scene, &"enemy_d").line == BattleUnitModel.Line.BACK, "RESTART: original semantic positions were not restored")
	_check(scene.jukain_state.blessing_stacks == 0 and scene.jukain_prescript.karma_stacks == 0, "M6.1: Restart Blessing/Karma boundary changed")
	await _free_scene(scene)


func _test_layout_and_scope() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	for viewport_size: Vector2i in [Vector2i(1152, 648), Vector2i(1440, 810)]:
		root.size = viewport_size
		scene.set_deferred("size", Vector2(viewport_size))
		await process_frame
		_check(_inside_viewport(scene.get_node("Margin/Layout/Battlefield"), Vector2(viewport_size)), "LAYOUT: battlefield clips at %s" % viewport_size)
		_check(_inside_viewport(scene.get_node("%CharacterInspector"), Vector2(viewport_size)), "LAYOUT: inspector clips at %s" % viewport_size)
		_check(_inside_viewport(scene.get_node("%ReplicaFormRow"), Vector2(viewport_size)), "LAYOUT: Form Chain builder clips at %s" % viewport_size)
		_check(_inside_viewport(scene.get_node("%CombatLog"), Vector2(viewport_size)), "LAYOUT: Combat Log clips at %s" % viewport_size)
	var battlefield: Control = scene.get_node("Margin/Layout/Battlefield")
	var stable_height := battlefield.size.y
	for index: int in 5:
		scene.party_units[index].line = BattleUnitModel.Line.MID
	scene.party_units[5].line = BattleUnitModel.Line.BACK
	scene._render_battlefield()
	await process_frame
	_check(scene.get_node("%AllyMidUnits").get_child_count() == 5, "LAYOUT: five-card line did not render")
	_check(is_equal_approx(battlefield.size.y, stable_height), "LAYOUT: five-card line changed battlefield height")
	_check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/vn/vn_prototype.tscn", "SCOPE: main scene changed")
	_check(FileAccess.file_exists("res://data/dialogue/m6_training_hall_postbattle.json"), "M6.4: post-battle data is missing")
	_check(game_state.get_bond("hiruko") == 0, "SCOPE: reach patch changed Hiruko Bond")
	await _free_scene(scene)


func _new_scene(integrated: bool) -> Control:
	game_state.reset_state()
	if integrated:
		_check(game_state.prepare_battle_context(ENCOUNTER_ID, RETURN_SEQUENCE), "FIXTURE: integrated context failed")
	var packed: PackedScene = load(SANDBOX_PATH)
	_check(packed != null, "FIXTURE: battle sandbox did not load")
	if packed == null:
		return null
	var scene: Control = packed.instantiate()
	scene.automatic_enemy_turns_enabled = false
	root.add_child(scene)
	active_scene = scene
	await process_frame
	return scene


func _free_scene(scene: Control) -> void:
	if active_scene == scene:
		active_scene = null
	scene.queue_free()
	await process_frame


func _unlock_for_chain(scene: Control) -> void:
	_set_current(scene, scene.jukain_unit)
	if scene.jukain_state.get_state() == JukainCombatStateModel.State.LOCKED:
		_check(scene.debug_unlock_jukain(), "FIXTURE: Jukain could not unlock")


func _set_current(scene: Control, unit: BattleUnit) -> void:
	scene.current_unit = unit
	scene.turn_index = scene.turn_queue.find(unit)
	scene.action_in_progress = false
	scene._clear_action_selection()
	scene._refresh_turn_ui()


func _open_builder(scene: Control, target_id: StringName) -> bool:
	return scene.begin_jukain_form_chain() and scene.select_jukain_chain_target(target_id)


func _build_chain(scene: Control, target_id: StringName, forms: Array) -> bool:
	if not _open_builder(scene, target_id):
		return false
	for form: int in forms:
		if not scene.select_jukain_chain_form(form):
			return false
	return true


func _find(scene: Control, stable_id: StringName) -> BattleUnit:
	for unit: BattleUnit in scene.party_units + scene.enemy_units:
		if unit.stable_id == stable_id:
			return unit
	return null


func _has(units: Array, target: BattleUnit) -> bool:
	for unit: BattleUnit in units:
		if unit == target:
			return true
	return false


func _defeat(unit: BattleUnit) -> void:
	unit.current_hp = 0
	unit.defeated = true


func _log_contains(scene: Control, fragment: String) -> bool:
	return _log_index(scene, fragment) >= 0


func _log_before(scene: Control, first: String, second: String) -> bool:
	var first_index := _log_index(scene, first)
	var second_index := _log_index(scene, second)
	return first_index >= 0 and second_index >= 0 and first_index < second_index


func _log_index(scene: Control, fragment: String) -> int:
	for index: int in scene.combat_log_entries.size():
		if fragment in scene.combat_log_entries[index]:
			return index
	return -1


func _inside_viewport(control: Control, viewport_size: Vector2) -> bool:
	var rect := control.get_global_rect()
	return rect.position.x >= 0.0 and rect.position.y >= 0.0 and rect.end.x <= viewport_size.x and rect.end.y <= viewport_size.y


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
