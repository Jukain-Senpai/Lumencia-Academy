extends SceneTree

const BattleUnitModel := preload("res://scripts/battle/battle_unit.gd")
const SANDBOX_PATH := "res://scenes/battle/battle_sandbox.tscn"
const EXPECTED_ORDER: Array[StringName] = [
	&"enemy_a",
	&"party_1",
	&"party_5",
	&"enemy_b",
	&"party_2",
	&"enemy_c",
	&"party_3",
	&"party_4",
	&"enemy_d",
	&"party_6",
]

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := await _new_scene()
	if scene != null:
		_test_initial_round(scene)
		_test_full_round(scene)
		_test_deterministic_tie(scene)
		_test_defeated_skip(scene)
		_test_consecutive_defeated_skip(scene)
		_test_final_queued_defeat_rollover(scene)
		_test_new_round_excludes_defeated(scene)
		await _test_restart(scene)
		scene.queue_free()
		await process_frame

	if failures.is_empty():
		print("M3.2 turn queue regression suite passed (%d checks)." % checks)
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	push_error("M3.2 turn queue regression suite failed: %d failure(s), %d checks." % [failures.size(), checks])
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


func _test_initial_round(scene: Control) -> void:
	_check(scene.round_number == 1, "Battle did not start at Round 1")
	_check(scene.turn_queue.size() == 10, "Round 1 queue must contain ten living units")
	_check(_queue_ids(scene) == EXPECTED_ORDER, "Round 1 queue does not match descending SPD order")
	_check(_unique_id_count(scene.turn_queue) == 10, "Round 1 queue contains duplicate IDs")
	_check(scene.current_unit != null and scene.current_unit.stable_id == &"enemy_a", "Enemy A was not the first current actor")
	_check(scene.combat_log_entries == ["Battle started.", "Round 1 started.", "Enemy A's turn."], "Initial combat log is incorrect")


func _test_full_round(scene: Control) -> void:
	scene.restart_battle()
	var observed: Array[StringName] = []
	for _turn in EXPECTED_ORDER.size():
		observed.append(scene.current_unit.stable_id)
		scene.advance_turn()
	_check(observed == EXPECTED_ORDER, "Full Round 1 traversal order is incorrect")
	_check(scene.round_number == 2, "Finishing Round 1 did not start Round 2")
	_check(scene.current_unit != null and scene.current_unit.stable_id == &"enemy_a", "Round 2 did not return to Enemy A")
	_check(_queue_ids(scene) == EXPECTED_ORDER, "Round 2 queue was not rebuilt in deterministic order")


func _test_deterministic_tie(scene: Control) -> void:
	var alpha := _make_test_unit("alpha", 10)
	var beta := _make_test_unit("beta", 10)
	_check(alpha != null and beta != null, "Synthetic tie fixtures were invalid")
	if alpha == null or beta == null:
		return
	for iteration in 8:
		var input: Array = [beta, alpha] if iteration % 2 == 0 else [alpha, beta]
		var queue: Array[BattleUnit] = scene._build_turn_queue(input)
		_check(_ids(queue) == [&"alpha", &"beta"], "Equal-SPD order changed on tie run %d" % iteration)


func _test_defeated_skip(scene: Control) -> void:
	scene.restart_battle()
	_find_unit(scene, &"party_5").defeated = true
	scene.advance_turn()
	_check(scene.current_unit.stable_id == &"party_1", "Party 1 should follow Enemy A")
	scene.advance_turn()
	_check(scene.current_unit.stable_id == &"enemy_b", "Defeated Party 5 became current or was not skipped")
	_check(scene.combat_log_entries.has("Party 5 is defeated and skips their turn."), "Defeated Party 5 skip was not logged")


func _test_consecutive_defeated_skip(scene: Control) -> void:
	scene.restart_battle()
	_find_unit(scene, &"party_1").defeated = true
	_find_unit(scene, &"party_5").defeated = true
	scene.advance_turn()
	_check(scene.current_unit.stable_id == &"enemy_b", "Consecutive defeated units were not skipped")
	_check(scene.turn_index == 3, "Turn index did not advance past consecutive defeated units")


func _test_final_queued_defeat_rollover(scene: Control) -> void:
	scene.restart_battle()
	while scene.current_unit.stable_id != &"enemy_d":
		scene.advance_turn()
	_find_unit(scene, &"party_6").defeated = true
	scene.advance_turn()
	_check(scene.round_number == 2, "Skipping a defeated final queue entry did not start Round 2")
	_check(scene.current_unit.stable_id == &"enemy_a", "Round 2 actor is incorrect after a final-entry skip")
	_check(scene.combat_log_entries.has("Party 6 is defeated and skips their turn."), "Final queued defeat was not logged")


func _test_new_round_excludes_defeated(scene: Control) -> void:
	scene.restart_battle()
	_find_unit(scene, &"party_5").defeated = true
	var safety := 0
	while scene.round_number == 1 and safety < 12:
		scene.advance_turn()
		safety += 1
	_check(scene.round_number == 2, "Round did not roll over after a queued defeat")
	_check(not _queue_ids(scene).has(&"party_5"), "Defeated Party 5 entered the rebuilt Round 2 queue")
	_check(scene.turn_queue.size() == 9, "Round 2 queue should contain only nine living units")
	_check(scene.current_unit.stable_id == &"enemy_a", "Enemy A should begin Round 2")


func _test_restart(scene: Control) -> void:
	scene.advance_turn()
	scene.advance_turn()
	_find_unit(scene, &"party_3").current_hp = 1
	_find_unit(scene, &"party_3").line = BattleUnitModel.Line.BACK
	_find_unit(scene, &"party_3").defeated = true
	scene.restart_battle()
	await process_frame
	_check(scene.round_number == 1, "Restart did not restore Round 1")
	_check(scene.turn_index == 0, "Restart did not restore the first queue position")
	_check(scene.current_unit.stable_id == &"enemy_a", "Restart did not restore Enemy A as current actor")
	_check(_queue_ids(scene) == EXPECTED_ORDER, "Restart did not restore the original queue")
	_check(scene.combat_log_entries == ["Battle started.", "Round 1 started.", "Enemy A's turn."], "Restart retained old combat-log entries")
	_check(scene.party_units.size() == 6 and scene.enemy_units.size() == 4, "Restart did not restore all ten combatants")
	_check(_unique_id_count(scene.turn_queue) == 10, "Restart queue contains duplicate entries")
	for unit: BattleUnit in scene.party_units + scene.enemy_units:
		_check(not unit.defeated, "Restart retained defeated state for '%s'" % unit.stable_id)
		_check(unit.current_hp == unit.max_hp, "Restart did not restore HP for '%s'" % unit.stable_id)
	_check(_find_unit(scene, &"party_3").line == BattleUnitModel.Line.MID, "Restart did not restore Party 3's line")
	_check(scene.get_node("%AllyBackUnits").get_child_count() == 2, "Restart duplicated or lost ally Back cards")
	_check(scene.get_node("%EnemyFrontUnits").get_child_count() == 2, "Restart duplicated or lost enemy Front cards")


func _make_test_unit(id: String, spd: int) -> BattleUnit:
	return BattleUnitModel.from_fixture({
		"id": id,
		"name": id.capitalize(),
		"team": BattleUnitModel.Team.PARTY,
		"current_hp": 25,
		"max_hp": 25,
		"atk": 6,
		"spd": spd,
		"line": BattleUnitModel.Line.FRONT,
		"defeated": false,
	})


func _find_unit(scene: Control, id: StringName) -> BattleUnit:
	for unit: BattleUnit in scene.party_units + scene.enemy_units:
		if unit.stable_id == id:
			return unit
	return null


func _queue_ids(scene: Control) -> Array[StringName]:
	return _ids(scene.turn_queue)


func _ids(units: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	for unit: BattleUnit in units:
		result.append(unit.stable_id)
	return result


func _unique_id_count(units: Array) -> int:
	var ids: Dictionary = {}
	for unit: BattleUnit in units:
		ids[unit.stable_id] = true
	return ids.size()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
