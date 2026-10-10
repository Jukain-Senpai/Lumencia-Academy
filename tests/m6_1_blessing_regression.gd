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
	_test_blessing_state_model()
	await _test_obey_timing_grant_and_inspector()
	await _test_exploit_and_defy_boundaries()
	await _test_basic_attack_scaling()
	await _test_replica_final_stage_scaling()
	await _test_blessing_karma_coexistence()
	await _test_unrelated_damage_sources()
	await _test_restart_and_terminal_cleanup()
	await _test_scope_and_layout()

	if failures.is_empty():
		print("M6.1 Blessing regression suite passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	push_error("M6.1 regression suite failed: %d failure(s), %d checks." % [failures.size(), checks])
	quit(1)


func _test_blessing_state_model() -> void:
	var state := JukainCombatStateModel.new()
	_check(state.blessing_stacks == 0, "STATE A: Blessing did not start at 0")
	_check(state.get_blessing_damage_percent() == 0, "STATE A: zero stacks did not report +0%")
	for expected_stacks: int in range(1, 5):
		state.grant_blessing()
		_check(state.blessing_stacks == expected_stacks, "STATE B–E: controlled grant did not reach %d stacks" % expected_stacks)
		_check(state.get_blessing_damage_percent() == expected_stacks * 10, "STATE B–E: stack %d did not add 10%%" % expected_stacks)
	_check(state.apply_blessing_to_resolved_damage(9) == 13, "STATE E: four stacks did not prove uncapped +40% scaling")
	_check(state.get_state() == JukainCombatStateModel.State.LOCKED and state.get_effective_atk(9) == 1, "STATE G: Blessing changed Locked effective ATK")
	state.debug_unlock()
	_check(state.get_effective_atk(9) == 9, "STATE G: Blessing changed Unlocked effective ATK")
	_check(state.apply_blessing_to_resolved_damage(0) == 0 and state.apply_blessing_to_resolved_damage(-5) == 0, "STATE: Blessing did not safely preserve nonpositive damage")
	state.reset()
	_check(state.blessing_stacks == 0 and state.get_state() == JukainCombatStateModel.State.LOCKED, "STATE: reset did not clear Blessing and restore Locked")


func _test_obey_timing_grant_and_inspector() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_set_current(scene, scene.jukain_unit)
	scene.selected_inspector_unit_id = &"party_2"
	scene._refresh_character_inspector()
	_check("Blessing: 0 (+0% Damage)" in _details(scene), "INSPECTOR A: Jukain did not display Blessing 0")
	_check(scene._process_jukain_turn_start() == &"activated", "OBEY A: Prescript did not activate")
	var real_atk_before: int = scene.jukain_unit.atk
	var hiruko_hp_before: int = scene.hiruko_unit.current_hp
	_check(scene.jukain_state.get_effective_atk(real_atk_before) == 1, "OBEY A: resolving hit did not begin at Locked effective ATK 1")
	_check(scene.begin_attack_selection() and scene.select_attack_target(&"party_1") and scene.confirm_ally_attack(), "OBEY: confirmed Jukain-to-Hiruko action failed")
	_check(hiruko_hp_before - scene.hiruko_unit.current_hp == 1, "OBEY B/F: resolving hit was boosted or failed to remove HP")
	_check(scene.hiruko_state.chains_current == 99 and scene.hiruko_state.wrapper_current == 100, "OBEY B: resolving hit bypassed Hiruko resistance/Seal handling")
	_check(scene.jukain_prescript.phase == JukainPrescriptStateModel.Phase.RESOLVED_OBEY, "OBEY C: route did not resolve OBEY")
	_check(scene.jukain_state.blessing_stacks == 1, "OBEY D: authoritative resolution did not grant exactly one Blessing")
	_check(scene.jukain_state.get_state() == JukainCombatStateModel.State.UNLOCKED, "OBEY E: Jukain did not unlock")
	_check(scene.jukain_unit.atk == real_atk_before and scene.jukain_state.get_effective_atk(real_atk_before) == 9, "OBEY: grant mutated real/effective ATK")
	_check("Blessing: 1 (+10% Damage)" in _details(scene), "INSPECTOR B: selected Jukain did not live-refresh to Blessing 1")
	_check(_log_count(scene, "Prescript resolved: OBEY.") == 1, "LOG A: OBEY resolution was not logged once")
	_check(_log_count(scene, "Blessing of the Index +1.") == 1 and _log_count(scene, "Jukain damage +10%.") == 1, "LOG B: Blessing gain announcement was not logged once")
	for index: int in 5:
		scene._render_battlefield()
		scene._refresh_character_inspector()
	_check(scene.jukain_state.blessing_stacks == 1 and _log_count(scene, "Blessing of the Index +1.") == 1, "OBEY H: rendering duplicated the Blessing grant")
	_set_current(scene, scene.jukain_unit)
	var enemy := _find(scene, &"enemy_a")
	var enemy_hp_before: int = enemy.current_hp
	_check(scene.begin_attack_selection() and scene.select_attack_target(enemy.stable_id), "OBEY G: subsequent Basic Attack failed")
	_check(enemy_hp_before - enemy.current_hp == 10, "OBEY G: subsequent ATK-9 Basic Attack did not receive ceiling +10%")
	await _free_scene(scene)


func _test_exploit_and_defy_boundaries() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_start_jukain_turn(scene)
	_check(scene.begin_move_selection() and scene.select_move_destination(BattleUnitModel.Line.MID), "EXPLOIT: setup Move failed")
	_check(scene.current_unit.stable_id == &"enemy_c" and scene.resolve_enemy_turn(), "EXPLOIT: enemy resolution failed")
	_check(scene.jukain_prescript.phase == JukainPrescriptStateModel.Phase.RESOLVED_EXPLOIT, "EXPLOIT: route did not resolve")
	_check(scene.jukain_state.get_state() == JukainCombatStateModel.State.UNLOCKED, "EXPLOIT: Jukain did not unlock")
	_check(scene.jukain_state.blessing_stacks == 0 and scene.jukain_prescript.karma_stacks == 0, "EXPLOIT: route granted Blessing or Karma")
	scene.selected_inspector_unit_id = &"party_2"
	scene._refresh_character_inspector()
	_check("Blessing: 0 (+0% Damage)" in _details(scene), "EXPLOIT: inspector did not remain at Blessing 0")
	_check(_log_count_containing(scene, "Blessing of the Index") == 0, "EXPLOIT: route announced Blessing")
	await _free_scene(scene)

	scene = await _new_scene(false)
	if scene == null:
		return
	_start_jukain_turn(scene)
	scene.round_number += 1
	_check(scene._process_jukain_turn_start() == &"defied", "DEFY: deadline did not activate replacement")
	_check(scene.jukain_prescript.karma_stacks == 1 and scene.jukain_state.blessing_stacks == 0, "DEFY: deadline did not grant only Karma")
	_check(scene.jukain_state.get_state() == JukainCombatStateModel.State.LOCKED, "DEFY: deadline unlocked before replacement")
	var enemy_a := _find(scene, &"enemy_a")
	_set_current(scene, enemy_a)
	_check(scene.resolve_enemy_turn(), "DEFY: enemy could not complete replacement")
	_check(scene.jukain_prescript.phase == JukainPrescriptStateModel.Phase.RESOLVED_DEFY, "DEFY: replacement did not resolve route")
	_check(scene.jukain_state.get_state() == JukainCombatStateModel.State.UNLOCKED, "DEFY: replacement did not unlock Jukain")
	_check(scene.jukain_prescript.karma_stacks == 1 and scene.jukain_state.blessing_stacks == 0, "DEFY: completed route changed Karma or granted Blessing")
	scene.selected_inspector_unit_id = &"party_2"
	scene._refresh_character_inspector()
	_check("Blessing: 0 (+0% Damage)" in _details(scene), "DEFY: inspector did not remain at Blessing 0")
	await _free_scene(scene)


func _test_basic_attack_scaling() -> void:
	for stacks: int in range(0, 4):
		var scene := await _new_scene(false)
		if scene == null:
			return
		_set_current(scene, scene.jukain_unit)
		scene.debug_unlock_jukain()
		for index: int in stacks:
			scene.jukain_state.grant_blessing()
		var enemy := _find(scene, &"enemy_a")
		var hp_before: int = enemy.current_hp
		_check(scene.begin_attack_selection() and scene.select_attack_target(enemy.stable_id), "BASIC: attack fixture failed at %d stacks" % stacks)
		var expected: int = [9, 10, 11, 12][stacks]
		_check(hp_before - enemy.current_hp == expected, "BASIC: %d stacks produced wrong final damage" % stacks)
		_check(scene.jukain_unit.atk == 9 and scene.jukain_state.get_effective_atk(9) == 9, "BASIC: Blessing mutated stored/effective ATK at %d stacks" % stacks)
		await _free_scene(scene)


func _test_replica_final_stage_scaling() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_set_current(scene, scene.jukain_unit)
	scene.debug_unlock_jukain()
	scene.jukain_state.grant_blessing()
	_check(scene._calculate_jukain_replica_damage(scene.JukainReplicaForm.SCYTHE, 0, BattleUnitModel.Line.FRONT, BattleUnitModel.Line.FRONT) == 13, "REPLICA: normal Scythe did not scale resolved 11 to 13")
	_check(scene._calculate_jukain_replica_damage(scene.JukainReplicaForm.SCYTHE, 3, BattleUnitModel.Line.FRONT, BattleUnitModel.Line.FRONT) == 24, "REPLICA: Hit-4 Scythe did not scale resolved finisher 21 to 24")
	_check(scene._calculate_jukain_replica_damage(scene.JukainReplicaForm.SWORD, 0, BattleUnitModel.Line.FRONT, BattleUnitModel.Line.FRONT) == 13, "REPLICA: Sword did not scale after its resolved line formula")
	_check(scene._calculate_jukain_replica_damage(scene.JukainReplicaForm.WHIP, 0, BattleUnitModel.Line.MID, BattleUnitModel.Line.MID) == 10, "REPLICA: Whip did not scale resolved 9 to 10")
	scene.jukain_unit.line = BattleUnitModel.Line.MID
	_prepare_target(scene, &"enemy_a", BattleUnitModel.Line.MID, 200)
	_check(_build_chain(scene, &"enemy_a", [scene.JukainReplicaForm.SWORD, scene.JukainReplicaForm.WHIP, scene.JukainReplicaForm.SCYTHE, scene.JukainReplicaForm.SCYTHE]), "REPLICA: controlled mixed chain could not be built")
	var target := _find(scene, &"enemy_a")
	var hp_before: int = target.current_hp
	_check(scene.execute_jukain_form_chain(), "REPLICA: controlled mixed chain did not execute")
	_check(hp_before - target.current_hp == 57, "REPLICA: per-hit Blessing/order produced wrong mixed-chain total")
	_check(scene.jukain_unit.line == BattleUnitModel.Line.FRONT and target.line == BattleUnitModel.Line.FRONT, "REPLICA: Blessing changed Sword movement or Whip displacement")
	_check(_log_contains(scene, "Hit 1 — Sword: 10 Slash.") and _log_contains(scene, "Hit 2 — Whip: 10 Blunt."), "REPLICA: Sword/Whip final per-hit damage logs are wrong")
	_check(_log_contains(scene, "Hit 4 — Scythe [FINISHER]: 24 Slash.") and _log_count_containing(scene, "Hit ") == 4, "REPLICA: Scythe Hit-4 ordering changed or created a fifth hit")
	await _free_scene(scene)


func _test_blessing_karma_coexistence() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	scene.jukain_state.grant_blessing()
	scene.jukain_prescript.karma_stacks = 1
	_set_current(scene, scene.jukain_unit)
	scene.debug_unlock_jukain()
	_check(scene._calculate_jukain_replica_damage(scene.JukainReplicaForm.SCYTHE, 0, BattleUnitModel.Line.FRONT, BattleUnitModel.Line.FRONT) == 13, "COEXIST: Blessing did not independently scale a Replica hit")
	var enemy := _find(scene, &"enemy_a")
	var enemy_hp_before: int = enemy.current_hp
	_check(scene.begin_attack_selection() and scene.select_attack_target(enemy.stable_id), "COEXIST: Jukain outgoing action failed")
	_check(enemy_hp_before - enemy.current_hp == 10, "COEXIST: Blessing did not independently scale outgoing Basic Attack")
	_set_current(scene, enemy)
	var jukain_hp_before: int = scene.jukain_unit.current_hp
	_check(scene._commit_basic_attack(enemy, scene.jukain_unit), "COEXIST: enemy incoming action failed")
	_check(jukain_hp_before - scene.jukain_unit.current_hp == 11, "COEXIST: Karma did not independently scale enemy damage")
	_check(scene.jukain_state.blessing_stacks == 1 and scene.jukain_prescript.karma_stacks == 1, "COEXIST: one system removed or replaced the other")
	scene.restart_battle()
	_check(scene.jukain_state.blessing_stacks == 0 and scene.jukain_prescript.karma_stacks == 0, "COEXIST: Restart did not clear both systems")
	await _free_scene(scene)


func _test_unrelated_damage_sources() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	for index: int in 3:
		scene.jukain_state.grant_blessing()
	var target := _find(scene, &"enemy_a")
	target.max_hp = 200
	target.current_hp = 200
	target.defeated = false
	var hp_before: int = target.current_hp
	scene._resolve_hiruko_kick(target)
	_check(hp_before - target.current_hp == 10, "UNRELATED: Blessing altered Hiruko Kick")
	target.current_hp = 200
	target.defeated = false
	hp_before = target.current_hp
	scene._resolve_hiruko_gut_stab(target)
	_check(hp_before - target.current_hp == 20, "UNRELATED: Blessing altered sealed Hiruko Gut Stab")
	var party_3 := _find(scene, &"party_3")
	hp_before = party_3.current_hp
	scene._apply_burn(party_3)
	scene._process_burn_tick(party_3)
	_check(hp_before - party_3.current_hp == 5, "UNRELATED: Blessing altered Hiruko/status Burn")
	var party_4 := _find(scene, &"party_4")
	hp_before = party_4.current_hp
	scene._apply_laevatain_aura("controlled")
	scene._process_burn_tick(party_4)
	_check(hp_before - party_4.current_hp == 5, "UNRELATED: Blessing altered Laevatain aura Burn")
	var generic_ally := _find(scene, &"party_4")
	scene._clear_burn(generic_ally)
	_set_current(scene, generic_ally)
	target.current_hp = 200
	hp_before = target.current_hp
	_check(scene._commit_basic_attack(generic_ally, target), "UNRELATED: generic ally action failed")
	_check(hp_before - target.current_hp == generic_ally.atk, "UNRELATED: Blessing altered generic ally damage")
	var generic_enemy := _find(scene, &"enemy_b")
	_set_current(scene, generic_enemy)
	var generic_target: BattleUnit = scene.jukain_unit
	hp_before = generic_target.current_hp
	_check(scene._commit_basic_attack(generic_enemy, generic_target), "UNRELATED: generic enemy action failed")
	_check(hp_before - generic_target.current_hp == generic_enemy.atk, "UNRELATED: Blessing altered generic enemy damage")
	_check(scene.jukain_prescript.get_enemy_damage_to_jukain(9) == 9, "UNRELATED: Blessing altered zero-Karma enemy-to-Jukain calculation")
	await _free_scene(scene)


func _test_restart_and_terminal_cleanup() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	scene.jukain_state.grant_blessing()
	scene.jukain_prescript.karma_stacks = 1
	scene.debug_unlock_jukain()
	_check(scene.debug_reset_jukain() and scene.jukain_state.blessing_stacks == 0, "RESET: Jukain debug reset retained Blessing")
	scene.jukain_state.grant_blessing()
	scene.debug_unlock_jukain()
	scene.restart_battle()
	_check(scene.jukain_state.blessing_stacks == 0 and scene.jukain_prescript.karma_stacks == 0, "RESET A: Restart retained Blessing or Karma")
	_check(scene.jukain_state.get_state() == JukainCombatStateModel.State.LOCKED and scene.jukain_state.get_effective_atk(scene.jukain_unit.atk) == 1 and scene.jukain_unit.atk == 9, "RESET A: Restart did not restore Jukain Locked/ATK state")
	_check(scene.jukain_prescript.phase == JukainPrescriptStateModel.Phase.ORIGINAL_ACTIVE and scene.jukain_chain_slots.is_empty(), "RESET A: Restart retained Prescript/chain state")
	await _free_scene(scene)

	scene = await _new_scene(false)
	if scene == null:
		return
	scene.jukain_state.grant_blessing()
	for enemy: BattleUnit in scene.enemy_units:
		_defeat(enemy)
	_check(scene._check_battle_result() and scene.battle_result == scene.BattleResult.VICTORY, "RESET B: Victory fixture did not end battle")
	_check(scene.jukain_state.blessing_stacks == 0, "RESET B: Victory retained active Blessing")
	await _free_scene(scene)

	scene = await _new_scene(false)
	if scene == null:
		return
	scene.jukain_state.grant_blessing()
	for ally: BattleUnit in scene.party_units:
		_defeat(ally)
	_check(scene._check_battle_result() and scene.battle_result == scene.BattleResult.DEFEAT, "RESET C: Defeat fixture did not end battle")
	_check(scene.jukain_state.blessing_stacks == 0, "RESET C: Defeat retained active Blessing")
	await _free_scene(scene)


func _test_scope_and_layout() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	scene.selected_inspector_unit_id = &"party_3"
	scene._refresh_character_inspector()
	_check("Blessing" not in _details(scene), "INSPECTOR: generic ally exposed Jukain-specific Blessing")
	scene.selected_inspector_unit_id = &"party_1"
	scene._refresh_character_inspector()
	_check("Blessing" not in _details(scene), "INSPECTOR: Hiruko presentation changed to include Blessing")
	root.size = Vector2i(1152, 648)
	scene.selected_inspector_unit_id = &"party_2"
	scene._refresh_character_inspector()
	await process_frame
	_check(_inside_viewport(scene.get_node("%CharacterInspector"), Vector2(1152, 648)), "LAYOUT: Character Inspector is outside 1152×648")
	_check(scene.get_node("Margin/Layout").size.y <= 624.0, "LAYOUT: M6.1 content exceeds safe 1152×648 height")
	root.size = Vector2i(1440, 810)
	await process_frame
	_check(scene.get_node("Margin/Layout").size.y <= 786.0, "LAYOUT: M6.1 content exceeds safe 1440×810 height")
	_check(not FileAccess.file_exists("res://scripts/battle/battle_result_contract.gd"), "SCOPE: M6.1 added a battle result contract")
	_check(not FileAccess.file_exists("res://scenes/vn/academy_training_hall.tscn"), "SCOPE: M6.1 added M6.2 Academy Training Hall VN")
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
	_check(scene._process_jukain_turn_start() == &"activated", "Prescript fixture did not activate")


func _set_current(scene: Control, unit: BattleUnit) -> void:
	scene.current_unit = unit
	scene.turn_index = scene.turn_queue.find(unit)
	scene.action_in_progress = false
	scene._clear_action_selection()
	scene._refresh_turn_ui()


func _prepare_target(scene: Control, target_id: StringName, line: BattleUnit.Line, hp: int) -> void:
	var target := _find(scene, target_id)
	target.line = line
	target.max_hp = hp
	target.current_hp = hp
	target.defeated = false
	for enemy: BattleUnit in scene.enemy_units:
		if enemy != target and enemy.line < line:
			enemy.line = line
	scene._render_battlefield()


func _build_chain(scene: Control, target_id: StringName, forms: Array) -> bool:
	if not scene.begin_jukain_form_chain() or not scene.select_jukain_chain_target(target_id):
		return false
	for form: int in forms:
		if not scene.select_jukain_chain_form(form):
			return false
	return true


func _find(scene: Control, id: StringName) -> BattleUnit:
	for unit: BattleUnit in scene.party_units + scene.enemy_units:
		if unit.stable_id == id:
			return unit
	return null


func _defeat(unit: BattleUnit) -> void:
	unit.current_hp = 0
	unit.defeated = true


func _details(scene: Control) -> String:
	return scene.get_node("%InspectorDetailsLabel").text


func _log_contains(scene: Control, fragment: String) -> bool:
	return _log_count_containing(scene, fragment) > 0


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
