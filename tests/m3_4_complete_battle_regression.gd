extends SceneTree

const BattleUnitModel := preload("res://scripts/battle/battle_unit.gd")
const SANDBOX_PATH := "res://scenes/battle/battle_sandbox.tscn"

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_move_destinations()
	await _test_move_commit_cancel_and_invalid()
	await _test_movement_exposure_and_attack()
	await _test_automatic_enemy_turns()
	await _test_victory_and_restart()
	await _test_defeat_and_restart()
	await _test_stale_deferred_restart()
	await _test_full_battle_and_round_rollover()
	await _test_layout()
	await _test_formation_height_capacity()

	if failures.is_empty():
		print("M3.4 complete battle regression suite passed (%d checks)." % checks)
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	push_error("M3.4 complete battle regression suite failed: %d failure(s), %d checks." % [failures.size(), checks])
	quit(1)


func _test_move_destinations() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return

	var party_1 := _find_unit(scene, &"party_1")
	var party_3 := _find_unit(scene, &"party_3")
	var party_5 := _find_unit(scene, &"party_5")
	_check(scene.get_adjacent_lines(party_1.line) == [BattleUnitModel.Line.MID], "Front did not expose only Mid as a Move destination")
	_check(scene.get_adjacent_lines(party_3.line) == [BattleUnitModel.Line.FRONT, BattleUnitModel.Line.BACK], "Mid did not expose Front and Back as Move destinations")
	_check(scene.get_adjacent_lines(party_5.line) == [BattleUnitModel.Line.MID], "Back did not expose only Mid as a Move destination")

	_set_current(scene, party_1)
	_check(scene.begin_move_selection(), "Front party unit could not enter Move selection")
	_check(scene.valid_move_destinations == [BattleUnitModel.Line.MID], "Front Move selection offered an invalid destination")
	_check(scene.get_node("%MoveMidButton").visible and not scene.get_node("%MoveBackButton").visible, "Front Move controls did not show only Mid")
	scene.cancel_action_selection()

	_set_current(scene, party_3)
	_check(scene.begin_move_selection(), "Mid party unit could not enter Move selection")
	_check(scene.get_node("%MoveFrontButton").visible and scene.get_node("%MoveBackButton").visible, "Mid Move controls did not show Front and Back")
	scene.cancel_action_selection()

	_set_current(scene, party_5)
	_check(scene.begin_move_selection(), "Back party unit could not enter Move selection")
	_check(scene.valid_move_destinations == [BattleUnitModel.Line.MID], "Back Move selection offered an invalid destination")
	_check(not scene.get_node("%MoveFrontButton").visible and scene.get_node("%MoveMidButton").visible, "Back Move controls did not show only Mid")
	await _free_scene(scene)


func _test_move_commit_cancel_and_invalid() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	scene.advance_turn()
	var party_1: BattleUnit = scene.current_unit
	var party_5 := _find_unit(scene, &"party_5")
	var hp_before: int = party_1.current_hp
	var log_size: int = scene.combat_log_entries.size()
	_check(scene.begin_move_selection(), "Party 1 could not enter Move selection for Cancel")
	_check(scene.cancel_action_selection(), "Move Cancel was rejected")
	_check(party_1.line == BattleUnitModel.Line.FRONT, "Move Cancel changed the unit line")
	_check(party_1.current_hp == hp_before, "Move Cancel changed HP")
	_check(scene.current_unit == party_1 and scene.turn_index == 1, "Move Cancel consumed the turn")
	_check(scene.combat_log_entries.size() == log_size, "Move Cancel wrote an action log")

	_check(scene.begin_move_selection(), "Party 1 could not re-enter Move selection")
	_check(not scene.select_move_destination(BattleUnitModel.Line.BACK), "Front to Back direct Move was accepted")
	_check(not scene.select_move_destination(BattleUnitModel.Line.FRONT), "Move to the current line was accepted")
	_check(scene.current_unit == party_1 and party_1.line == BattleUnitModel.Line.FRONT, "Invalid Move changed state or consumed the turn")
	_check(scene.select_move_destination(BattleUnitModel.Line.MID), "Valid Front to Mid Move was rejected")
	_check(party_1.line == BattleUnitModel.Line.MID, "Move commit did not update semantic line state")
	_check(scene.current_unit.stable_id == &"party_5" and scene.turn_index == 2, "Move did not advance exactly once")
	_check(scene.combat_log_entries.has("Party 1 moves from Front to Mid."), "Move commit was not logged correctly")
	_check(scene.get_node("%AllyFrontUnits").get_child_count() == 1, "Moved card remained in Ally Front")
	_check(scene.get_node("%AllyMidUnits").get_child_count() == 3, "Moved card did not appear in Ally Mid")
	_check(not scene.select_move_destination(BattleUnitModel.Line.MID), "Duplicate Move activation committed twice")
	_check(party_1.line == BattleUnitModel.Line.MID and scene.turn_index == 2, "Duplicate Move activation changed state")

	_set_current(scene, party_5)
	party_5.defeated = true
	party_5.current_hp = 0
	_check(not scene.begin_move_selection(), "Defeated party unit entered Move selection")
	await _free_scene(scene)


func _test_movement_exposure_and_attack() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	var party_1 := _find_unit(scene, &"party_1")
	var party_2 := _find_unit(scene, &"party_2")
	_defeat(party_2)
	_set_current(scene, party_1)
	_check(scene.begin_move_selection(), "Sole living Front unit could not begin Move")
	_check(scene.select_move_destination(BattleUnitModel.Line.MID), "Sole living Front unit could not move to Mid")
	_check(scene._get_nearest_occupied_line(BattleUnitModel.Team.PARTY) == BattleUnitModel.Line.MID, "Emptying party Front did not expose Mid")
	_check(_ids(scene._get_valid_attack_targets(_find_unit(scene, &"enemy_a"))) == [&"party_1", &"party_3", &"party_4"], "Enemy targeting did not immediately reflect movement exposure")

	scene.restart_battle()
	scene.advance_turn()
	var enemy_a := _find_unit(scene, &"enemy_a")
	_check(scene.begin_attack_selection(), "Attack selection stopped working after Move integration")
	_check(_ids(scene.valid_attack_targets) == [&"enemy_a", &"enemy_b"], "Attack nearest-line targets changed after Move integration")
	_check(scene.select_attack_target(&"enemy_a"), "Valid Basic Attack failed after Move integration")
	_check(enemy_a.current_hp == 32, "Basic Attack no longer deals exact ATK damage")
	await _free_scene(scene)


func _test_automatic_enemy_turns() -> void:
	var scene := await _new_scene(true)
	if scene == null:
		return
	var party_1 := _find_unit(scene, &"party_1")
	_check(party_1.current_hp == 35, "Initial automatic Enemy A attack did not deal exactly 9 damage to Party 1")
	_check(scene.current_unit == party_1, "Initial automatic enemy turn did not advance to Party 1")
	_check(scene.get_node_or_null("%ResolveEnemyTurnButton") == null, "Resolve Enemy Turn debug control still exists")
	_check(scene.get_node("%AttackButton").visible and scene.get_node("%MoveButton").visible, "Party action controls were not enabled after automatic enemy resolution")
	_check(scene.combat_log_entries.has("Enemy A attacks Party 1 for 9 damage."), "Automatic enemy attack was not logged")
	await _free_scene(scene)

	var chain_scene := await _new_scene(false)
	if chain_scene == null:
		return
	var enemy_a := _find_unit(chain_scene, &"enemy_a")
	var enemy_b := _find_unit(chain_scene, &"enemy_b")
	party_1 = _find_unit(chain_scene, &"party_1")
	chain_scene.turn_queue.assign([enemy_a, enemy_b, party_1])
	chain_scene.turn_index = -1
	chain_scene.current_unit = null
	chain_scene.automatic_enemy_turns_enabled = true
	chain_scene._activate_next_living_turn()
	_check(not chain_scene.get_node("%AttackButton").visible and not chain_scene.get_node("%MoveButton").visible and not chain_scene.get_node("%CancelButton").visible, "Player input was available during an enemy turn")
	await process_frame
	await process_frame
	_check(party_1.current_hp == 27, "Consecutive enemies did not each attack exactly once")
	_check(chain_scene.current_unit == party_1, "Consecutive enemy processing did not reach the next party actor")
	_check(_log_count(chain_scene, "Enemy A attacks Party 1 for 9 damage.") == 1, "Enemy A resolved more than once in a consecutive chain")
	_check(_log_count(chain_scene, "Enemy B attacks Party 1 for 8 damage.") == 1, "Enemy B resolved more than once in a consecutive chain")
	await _free_scene(chain_scene)


func _test_victory_and_restart() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	scene.advance_turn()
	for id: StringName in [&"enemy_a", &"enemy_b", &"enemy_c"]:
		_defeat(_find_unit(scene, id))
	var enemy_d := _find_unit(scene, &"enemy_d")
	enemy_d.current_hp = 5
	_check(scene.begin_attack_selection(), "Final living enemy could not be targeted")
	_check(scene.select_attack_target(&"enemy_d"), "Attack against final enemy failed")
	_check(enemy_d.current_hp == 0 and enemy_d.defeated, "Final enemy did not reach defeated zero-HP state")
	_check(scene.battle_result == scene.BattleResult.VICTORY, "Final enemy defeat did not set VICTORY")
	_check(scene.current_unit == null, "Victory retained a current actor")
	_check(scene.get_node("%ActionModeLabel").text == "VICTORY", "Victory was not visibly displayed")
	_check(scene.combat_log_entries.has("All enemies defeated.") and scene.combat_log_entries.has("Victory!"), "Victory messages were not logged")
	_check(_all_action_controls_hidden(scene), "Player controls remained active after Victory")
	var stopped_round: int = scene.round_number
	var stopped_log_size: int = scene.combat_log_entries.size()
	_check(not scene.begin_attack_selection() and not scene.begin_move_selection(), "A new action began after Victory")
	scene.advance_turn()
	_check(scene.round_number == stopped_round and scene.combat_log_entries.size() == stopped_log_size, "Turn processing continued after Victory")

	scene.automatic_enemy_turns_enabled = true
	scene.restart_battle()
	await process_frame
	_check(scene.battle_result == scene.BattleResult.NONE, "Restart after Victory retained battle result")
	_check(scene.current_unit.stable_id == &"party_1", "Restart after Victory did not resume normal automatic flow")
	_check(_find_unit(scene, &"party_1").current_hp == 35, "Restart after Victory did not produce one clean initial enemy attack")
	_check(_all_units_restored_except_initial_hit(scene), "Restart after Victory did not restore fixture state")
	await _free_scene(scene)


func _test_defeat_and_restart() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	for unit: BattleUnit in scene.party_units:
		_defeat(unit)
	var party_1 := _find_unit(scene, &"party_1")
	party_1.defeated = false
	party_1.current_hp = 5
	scene.automatic_enemy_turns_enabled = true
	scene._schedule_enemy_turn()
	await process_frame
	_check(party_1.current_hp == 0 and party_1.defeated, "Final party member was not defeated by automatic attack")
	_check(scene.battle_result == scene.BattleResult.DEFEAT, "Final party defeat did not set DEFEAT")
	_check(scene.current_unit == null, "Defeat retained a current actor")
	_check(scene.get_node("%ActionModeLabel").text == "DEFEAT", "Defeat was not visibly displayed")
	_check(scene.combat_log_entries.has("All party members defeated.") and scene.combat_log_entries.has("Defeat!"), "Defeat messages were not logged")
	_check(_all_action_controls_hidden(scene), "Player controls remained active after Defeat")
	_check(not scene.resolve_enemy_turn(), "Enemy action resolved after Defeat")

	scene.restart_battle()
	await process_frame
	_check(scene.battle_result == scene.BattleResult.NONE, "Restart after Defeat retained battle result")
	_check(scene.current_unit.stable_id == &"party_1" and _find_unit(scene, &"party_1").current_hp == 35, "Restart after Defeat did not restore normal initial flow")
	_check(_all_units_restored_except_initial_hit(scene), "Restart after Defeat did not restore fixture state")
	await _free_scene(scene)


func _test_stale_deferred_restart() -> void:
	var scene := _instantiate_scene(true)
	if scene == null:
		return
	root.add_child(scene)
	current_scene = scene
	# _ready scheduled the original battle's Enemy A. Restart before that callback runs.
	scene.restart_battle()
	await process_frame
	await process_frame
	var party_1 := _find_unit(scene, &"party_1")
	_check(party_1.current_hp == 35, "A stale deferred enemy action leaked through Restart")
	_check(_log_count(scene, "Enemy A attacks Party 1 for 9 damage.") == 1, "Restart produced duplicate initial enemy actions")
	_check(scene.current_unit == party_1, "Restart with a pending enemy action did not settle on Party 1")
	await _free_scene(scene)


func _test_full_battle_and_round_rollover() -> void:
	var scene := await _new_scene(true)
	if scene == null:
		return
	var safety := 0
	while scene.battle_result == scene.BattleResult.NONE and safety < 100:
		if scene.current_unit == null or scene.current_unit.team == BattleUnitModel.Team.ENEMY:
			await process_frame
		else:
			var began: bool = scene.begin_attack_selection()
			_check(began, "Full battle could not begin a required party Attack")
			if not began or scene.valid_attack_targets.is_empty():
				break
			var target: BattleUnit = scene.valid_attack_targets[0]
			_check(scene.select_attack_target(target.stable_id), "Full battle party Attack failed")
			await process_frame
		safety += 1
	_check(safety < 100, "Full battle did not terminate reliably")
	_check(scene.battle_result != scene.BattleResult.NONE, "Full battle ended without Victory or Defeat")
	_check(scene.current_unit == null, "Completed full battle retained a current actor")
	_check(scene.round_number >= 2, "Full battle did not exercise round rollover")
	await _free_scene(scene)

	var round_scene := await _new_scene(false)
	if round_scene == null:
		return
	var safety_round := 0
	while round_scene.round_number == 1 and safety_round < 12:
		round_scene.advance_turn()
		safety_round += 1
	_check(round_scene.round_number == 2, "Surviving units did not roll into Round 2")
	_check(round_scene.turn_queue.size() == 10, "Round rollover did not preserve all living units")
	_check(round_scene.current_unit.stable_id == &"enemy_a", "Round 2 did not begin in deterministic SPD order")
	await _free_scene(round_scene)


func _test_layout() -> void:
	root.size = Vector2i(1152, 648)
	var scene := await _new_scene(false)
	if scene == null:
		return
	scene.advance_turn()
	await process_frame
	_check(scene.size.x >= 1152.0 and scene.size.y >= 648.0, "Sandbox did not fill the 1152x648 viewport")
	_check(scene.get_node("Margin/Layout").size.y <= 624.0, "Sandbox content exceeds the safe 1152x648 height (%s px)" % scene.get_node("Margin/Layout").size.y)
	_check(_inside_viewport(scene.get_node("%RestartButton")), "Restart is outside the 1152x648 viewport")
	_check(_inside_viewport(scene.get_node("%AttackButton")) and _inside_viewport(scene.get_node("%MoveButton")), "Party action controls are outside the 1152x648 viewport")
	_check(_inside_viewport(scene.get_node("%CombatLog")), "Combat log is outside the 1152x648 viewport")
	_check(scene.get_node("%RoundLabel").is_visible_in_tree() and scene.get_node("%CurrentTurnLabel").is_visible_in_tree() and scene.get_node("%TurnOrderLabel").is_visible_in_tree(), "Round/current/order information is not visible")
	root.size = Vector2i(1440, 810)
	await process_frame
	_check(scene.get_node("Margin/Layout").size.y <= 786.0, "Sandbox does not expand reasonably at a larger viewport")
	await _free_scene(scene)


func _test_formation_height_capacity() -> void:
	root.size = Vector2i(1152, 648)
	var scene := await _new_scene(false)
	if scene == null:
		return
	var battlefield: Control = scene.get_node("Margin/Layout/Battlefield")

	# One, three, then five occupants in party Mid must use the same formation height.
	_set_line_distribution(scene.party_units, [
		BattleUnitModel.Line.MID,
		BattleUnitModel.Line.FRONT,
		BattleUnitModel.Line.FRONT,
		BattleUnitModel.Line.BACK,
		BattleUnitModel.Line.BACK,
		BattleUnitModel.Line.BACK,
	])
	scene._render_battlefield()
	await process_frame
	var stable_height: float = battlefield.size.y
	_check(scene.get_node("%AllyMidUnits").get_child_count() == 1, "One-unit formation fixture did not render correctly")

	_set_line_distribution(scene.party_units, [
		BattleUnitModel.Line.MID,
		BattleUnitModel.Line.MID,
		BattleUnitModel.Line.MID,
		BattleUnitModel.Line.FRONT,
		BattleUnitModel.Line.BACK,
		BattleUnitModel.Line.BACK,
	])
	scene._render_battlefield()
	await process_frame
	_check(scene.get_node("%AllyMidUnits").get_child_count() == 3, "Three-unit formation fixture did not render correctly")
	_check(is_equal_approx(battlefield.size.y, stable_height), "Three occupants changed battlefield height")

	_set_line_distribution(scene.party_units, [
		BattleUnitModel.Line.MID,
		BattleUnitModel.Line.MID,
		BattleUnitModel.Line.MID,
		BattleUnitModel.Line.MID,
		BattleUnitModel.Line.MID,
		BattleUnitModel.Line.BACK,
	])
	_defeat(scene.party_units[2])
	scene._render_battlefield()
	await process_frame
	_check(scene.get_node("%AllyMidUnits").get_child_count() == 5, "Five-unit party formation did not render all cards")
	_check(is_equal_approx(battlefield.size.y, stable_height), "Five party occupants changed battlefield height")
	_check(scene.get_node("Margin/Layout").size.y <= 624.0, "Five party occupants pushed the sandbox below 1152x648 (%s px)" % scene.get_node("Margin/Layout").size.y)
	for destination: BattleUnit.Line in [
		BattleUnitModel.Line.FRONT,
		BattleUnitModel.Line.BACK,
		BattleUnitModel.Line.MID,
		BattleUnitModel.Line.FRONT,
	]:
		for index: int in 5:
			scene.party_units[index].line = destination
		scene.party_units[5].line = (
			BattleUnitModel.Line.BACK
			if destination != BattleUnitModel.Line.BACK
			else BattleUnitModel.Line.FRONT
		)
		scene._render_battlefield()
		await process_frame
		_check(scene._line_container_for(BattleUnitModel.Team.PARTY, destination).get_child_count() == 5, "Repeated party redistribution did not render five cards in %s" % BattleUnitModel.line_name(destination))
		_check(is_equal_approx(battlefield.size.y, stable_height), "Repeated party redistribution changed battlefield height")

	# Mirror the same structural pressure on the enemy side.
	var duplicate_enemy: BattleUnit = BattleUnitModel.from_fixture({
		"id": "enemy_layout_only", "name": "Enemy Slot", "team": BattleUnitModel.Team.ENEMY,
		"current_hp": 1, "max_hp": 1, "atk": 1, "spd": 1,
		"line": BattleUnitModel.Line.FRONT, "defeated": false,
	})
	scene.enemy_units.append(duplicate_enemy)
	for destination: BattleUnit.Line in [
		BattleUnitModel.Line.FRONT,
		BattleUnitModel.Line.MID,
		BattleUnitModel.Line.BACK,
	]:
		for unit: BattleUnit in scene.enemy_units:
			unit.line = destination
		scene._render_battlefield()
		await process_frame
		_check(scene._line_container_for(BattleUnitModel.Team.ENEMY, destination).get_child_count() == 5, "Five-unit enemy formation did not render all cards in %s" % BattleUnitModel.line_name(destination))
		_check(is_equal_approx(battlefield.size.y, stable_height), "Five enemy occupants changed battlefield height")
	_check(_inside_viewport(scene.get_node("%CombatLog")), "Five-unit formation pushed the combat log outside the viewport")
	await _free_scene(scene)


func _instantiate_scene(automatic_enemies: bool) -> Control:
	var packed_scene: PackedScene = load(SANDBOX_PATH)
	_check(packed_scene != null, "Battle sandbox scene did not load")
	if packed_scene == null:
		return null
	var scene: Control = packed_scene.instantiate()
	scene.automatic_enemy_turns_enabled = automatic_enemies
	return scene


func _new_scene(automatic_enemies: bool) -> Control:
	var scene := _instantiate_scene(automatic_enemies)
	if scene == null:
		return null
	root.add_child(scene)
	current_scene = scene
	await process_frame
	return scene


func _free_scene(scene: Control) -> void:
	if current_scene == scene:
		current_scene = null
	scene.queue_free()
	await process_frame


func _set_current(scene: Control, unit: BattleUnit) -> void:
	scene.current_unit = unit
	scene.turn_index = scene.turn_queue.find(unit)
	scene._clear_action_selection()
	scene._refresh_turn_ui()


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


func _set_line_distribution(units: Array[BattleUnit], lines: Array) -> void:
	for index: int in mini(units.size(), lines.size()):
		units[index].line = lines[index]


func _log_count(scene: Control, entry: String) -> int:
	var count := 0
	for logged: String in scene.combat_log_entries:
		if logged == entry:
			count += 1
	return count


func _all_action_controls_hidden(scene: Control) -> bool:
	return (
		not scene.get_node("%AttackButton").visible
		and not scene.get_node("%MoveButton").visible
		and not scene.get_node("%CancelButton").visible
		and not scene.get_node("%MoveFrontButton").visible
		and not scene.get_node("%MoveMidButton").visible
		and not scene.get_node("%MoveBackButton").visible
	)


func _all_units_restored_except_initial_hit(scene: Control) -> bool:
	for unit: BattleUnit in scene.party_units + scene.enemy_units:
		if unit.defeated:
			return false
		var expected_hp: int = unit.max_hp
		if unit.stable_id == &"party_1":
			expected_hp -= 9
		if unit.current_hp != expected_hp:
			return false
	return true


func _inside_viewport(control: Control) -> bool:
	var rect := control.get_global_rect()
	return rect.position.x >= 0.0 and rect.position.y >= 0.0 and rect.end.x <= 1152.0 and rect.end.y <= 648.0


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
