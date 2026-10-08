extends SceneTree

const BattleUnitModel := preload("res://scripts/battle/battle_unit.gd")
const SANDBOX_PATH := "res://scenes/battle/battle_sandbox.tscn"

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := await _new_scene()
	if scene != null:
		_test_initial_target_availability(scene)
		_test_exact_damage_and_turn_consumption(scene)
		_test_cancel(scene)
		_test_invalid_target(scene)
		_test_front_exposure(scene)
		_test_defeat_and_queue_skip(scene)
		_test_enemy_targeting(scene)
		_test_enemy_exposure(scene)
		_test_round_behavior(scene)
		await _test_restart(scene)
		_test_empty_side_safety(scene)
		scene.queue_free()
		await process_frame

	if failures.is_empty():
		print("M3.3 basic attack regression suite passed (%d checks)." % checks)
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	push_error("M3.3 basic attack regression suite failed: %d failure(s), %d checks." % [failures.size(), checks])
	quit(1)


func _new_scene() -> Control:
	var packed_scene: PackedScene = load(SANDBOX_PATH)
	_check(packed_scene != null, "Battle sandbox scene did not load")
	if packed_scene == null:
		return null
	var scene: Control = packed_scene.instantiate()
	scene.automatic_enemy_turns_enabled = false
	root.add_child(scene)
	current_scene = scene
	await process_frame
	return scene


func _test_initial_target_availability(scene: Control) -> void:
	var party_1 := _find_unit(scene, &"party_1")
	_check(_ids(scene._get_valid_attack_targets(party_1)) == [&"enemy_a", &"enemy_b"], "Party target list did not contain exactly the living enemy Front")
	_check(scene._get_nearest_occupied_line(BattleUnitModel.Team.ENEMY) == BattleUnitModel.Line.FRONT, "Enemy Front was not the nearest occupied line")
	_check(not scene.get_node("%AttackButton").visible, "Attack was visible during an enemy turn")
	_check(not scene.get_node("%MoveButton").visible, "Move was visible during an enemy turn")


func _test_exact_damage_and_turn_consumption(scene: Control) -> void:
	scene.restart_battle()
	var party_1 := _find_unit(scene, &"party_1")
	var party_2 := _find_unit(scene, &"party_2")
	var enemy_a := _find_unit(scene, &"enemy_a")
	_check(scene.resolve_enemy_turn(), "Enemy A did not resolve its Basic Attack")
	_check(party_2.current_hp == 31, "Enemy A did not damage front-line Jukain by its exact ATK")
	_check(party_1.current_hp == party_1.max_hp and scene.hiruko_state.chains_current == 100, "Protected Mid Hiruko was damaged through Jukain's Front line")
	_check(scene.current_unit == party_1, "Enemy attack did not advance exactly once to Party 1")
	_check(scene.begin_attack_selection(), "Party 1 could not enter target selection")
	_check(scene.selecting_target, "Target-selection state was not set")
	_check(_ids(scene.valid_attack_targets) == [&"enemy_a", &"enemy_b"], "Target-selection list is incorrect")
	_check(scene.select_attack_target(&"enemy_a"), "Party 1 could not attack valid target Enemy A")
	_check(enemy_a.current_hp == 32, "Party 1 did not deal exactly 10 damage to Enemy A")
	_check(scene.current_unit.stable_id == &"party_5", "Party attack did not advance exactly once to Party 5")
	_check(not scene.select_attack_target(&"enemy_a"), "Repeated target activation committed another attack")
	_check(enemy_a.current_hp == 32, "Repeated target activation dealt duplicate damage")
	_check(scene.combat_log_entries.has("Hiruko attacks Enemy A for 10 Blunt damage."), "Hiruko's SEALED attack profile was not logged")
	_check(scene.combat_log_entries.has("Enemy A has 32 HP remaining."), "Remaining enemy HP was not logged")


func _test_cancel(scene: Control) -> void:
	scene.restart_battle()
	scene.advance_turn()
	var current_before: BattleUnit = scene.current_unit
	var hp_before := _hp_snapshot(scene)
	_check(scene.begin_attack_selection(), "Party turn could not enter target selection before Cancel")
	_check(scene.cancel_target_selection(), "Cancel did not exit target selection")
	_check(not scene.selecting_target, "Cancel retained target-selection state")
	_check(scene.current_unit == current_before, "Cancel advanced the turn")
	_check(_hp_snapshot(scene) == hp_before, "Cancel changed combatant HP")
	_check(_defeated_count(scene) == 0, "Cancel changed a defeated state")


func _test_invalid_target(scene: Control) -> void:
	scene.restart_battle()
	scene.advance_turn()
	var enemy_c := _find_unit(scene, &"enemy_c")
	_check(scene.begin_attack_selection(), "Could not enter target selection for invalid-target test")
	_check(not scene.select_attack_target(&"enemy_c"), "Protected enemy Mid target was accepted")
	_check(enemy_c.current_hp == 35, "Invalid target attempt changed Enemy C HP")
	_check(scene.current_unit.stable_id == &"party_1", "Invalid target attempt advanced the turn")
	_check(scene.selecting_target, "Invalid target attempt unexpectedly canceled selection")


func _test_front_exposure(scene: Control) -> void:
	scene.restart_battle()
	_defeat(_find_unit(scene, &"enemy_a"))
	_defeat(_find_unit(scene, &"enemy_b"))
	var party_1 := _find_unit(scene, &"party_1")
	_check(_ids(scene._get_valid_attack_targets(party_1)) == [&"enemy_c"], "Enemy Mid was not exposed after Front was defeated")
	_check(scene._get_nearest_occupied_line(BattleUnitModel.Team.ENEMY) == BattleUnitModel.Line.MID, "Nearest enemy line did not advance to Mid")
	_defeat(_find_unit(scene, &"enemy_c"))
	_check(_ids(scene._get_valid_attack_targets(party_1)) == [&"enemy_d"], "Enemy Back was not exposed after Front and Mid were defeated")


func _test_defeat_and_queue_skip(scene: Control) -> void:
	scene.restart_battle()
	scene.advance_turn()
	var enemy_b := _find_unit(scene, &"enemy_b")
	enemy_b.current_hp = 10
	_check(scene.begin_attack_selection(), "Party 1 could not select an attack for defeat test")
	_check(scene.select_attack_target(&"enemy_b"), "Party 1 could not attack Enemy B")
	_check(enemy_b.current_hp == 0, "Lethal damage did not clamp Enemy B HP to zero")
	_check(enemy_b.defeated, "Zero-HP Enemy B was not marked defeated")
	_check(not _ids(scene._get_valid_attack_targets(scene.current_unit)).has(&"enemy_b"), "Defeated Enemy B remained targetable")
	_check(scene._get_nearest_occupied_line(BattleUnitModel.Team.ENEMY) == BattleUnitModel.Line.FRONT, "Living Enemy A should still occupy Front")
	_check(_scene_has_text(scene, "DEFEATED"), "Defeated card was not visibly marked")
	_check(scene.begin_attack_selection(), "Party 5 could not select an attack after Enemy B's defeat")
	_check(scene.select_attack_target(&"enemy_a"), "Party 5 could not attack Enemy A")
	_check(scene.current_unit.stable_id == &"party_2", "Queued defeated Enemy B was not skipped")
	_check(scene.combat_log_entries.has("Enemy B is defeated and skips their turn."), "Queued defeated Enemy B skip was not logged")


func _test_enemy_targeting(scene: Control) -> void:
	scene.restart_battle()
	var party_1 := _find_unit(scene, &"party_1")
	var party_2 := _find_unit(scene, &"party_2")
	_check(_ids(scene._get_valid_attack_targets(scene.current_unit)) == [&"party_2"], "Enemy target list did not contain the sole party Front unit")
	_check(scene.resolve_enemy_turn(), "Enemy A did not resolve its attack")
	_check(party_2.current_hp == 31 and party_1.current_hp == party_1.max_hp, "Enemy A did not deterministically target front-line Jukain")
	_check(scene.current_unit.stable_id == &"party_1", "Enemy attack did not integrate with the existing queue")


func _test_enemy_exposure(scene: Control) -> void:
	scene.restart_battle()
	_defeat(_find_unit(scene, &"party_1"))
	var party_2 := _find_unit(scene, &"party_2")
	_check(scene.resolve_enemy_turn(), "Enemy A could not attack remaining party Front")
	_check(party_2.current_hp == 31, "Enemy A did not choose Party 2 after Party 1 was defeated")

	scene.restart_battle()
	_defeat(_find_unit(scene, &"party_1"))
	_defeat(_find_unit(scene, &"party_2"))
	var party_3 := _find_unit(scene, &"party_3")
	_check(scene.resolve_enemy_turn(), "Enemy A could not attack exposed party Mid")
	_check(party_3.current_hp == 27, "Enemy A did not choose first stable-ID party Mid target")


func _test_round_behavior(scene: Control) -> void:
	scene.restart_battle()
	var safety := 0
	while scene.round_number == 1 and safety < 12:
		if scene.current_unit.team == BattleUnitModel.Team.ENEMY:
			scene.resolve_enemy_turn()
		else:
			scene.begin_attack_selection()
			var targets: Array[BattleUnit] = scene.valid_attack_targets
			scene.select_attack_target(targets[0].stable_id)
		safety += 1
	_check(scene.round_number == 2, "Resolved Basic Attacks did not roll the battle into Round 2")
	_check(scene.current_unit.stable_id == &"party_1", "Round 2 did not start with the fastest living unit")
	_check(not _ids(scene.turn_queue).has(&"enemy_a"), "Defeated Enemy A entered the rebuilt Round 2 queue")


func _test_restart(scene: Control) -> void:
	scene.restart_battle()
	scene.resolve_enemy_turn()
	scene.begin_attack_selection()
	scene.select_attack_target(&"enemy_a")
	scene.begin_attack_selection()
	_defeat(_find_unit(scene, &"enemy_b"))
	scene.restart_battle()
	await process_frame
	_check(scene.round_number == 1, "Restart did not restore Round 1")
	_check(scene.current_unit.stable_id == &"enemy_a", "Restart did not restore Enemy A as current actor")
	_check(not scene.selecting_target and scene.valid_attack_targets.is_empty(), "Restart retained target-selection state")
	_check(scene.battle_result == scene.BattleResult.NONE, "Restart retained terminal battle state")
	_check(scene.combat_log_entries == ["Battle started.", "Round 1 started.", "Enemy A's turn."], "Restart did not restore a clean M3.3 log")
	_check(not scene.get_node("%AttackButton").visible and not scene.get_node("%MoveButton").visible and not scene.get_node("%CancelButton").visible, "Restart retained player action controls")
	for unit: BattleUnit in scene.party_units + scene.enemy_units:
		_check(unit.current_hp == unit.max_hp and not unit.defeated, "Restart did not restore '%s'" % unit.stable_id)


func _test_empty_side_safety(scene: Control) -> void:
	scene.restart_battle()
	scene.advance_turn()
	_defeat(_find_unit(scene, &"enemy_a"))
	_defeat(_find_unit(scene, &"enemy_b"))
	_defeat(_find_unit(scene, &"enemy_c"))
	var enemy_d := _find_unit(scene, &"enemy_d")
	enemy_d.current_hp = 5
	_check(scene.begin_attack_selection(), "Last living enemy could not be targeted")
	_check(_ids(scene.valid_attack_targets) == [&"enemy_d"], "Last living enemy was not the sole valid target")
	_check(scene.select_attack_target(&"enemy_d"), "Attack against final living enemy failed")
	_check(scene.battle_result == scene.BattleResult.VICTORY, "Final enemy defeat did not produce victory")
	_check(scene.current_unit == null, "Victory retained an unsafe current actor")
	_check(scene.combat_log_entries.has("Victory!"), "Victory was not logged")
	_check(not scene.get_node("%AttackButton").visible and not scene.get_node("%MoveButton").visible, "Action controls remained active after victory")


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


func _hp_snapshot(scene: Control) -> Dictionary:
	var result: Dictionary = {}
	for unit: BattleUnit in scene.party_units + scene.enemy_units:
		result[unit.stable_id] = unit.current_hp
	return result


func _defeated_count(scene: Control) -> int:
	var count := 0
	for unit: BattleUnit in scene.party_units + scene.enemy_units:
		if unit.defeated:
			count += 1
	return count


func _scene_has_text(node: Node, expected: String) -> bool:
	if node is Label and node.text == expected:
		return true
	for child: Node in node.get_children():
		if _scene_has_text(child, expected):
			return true
	return false


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
