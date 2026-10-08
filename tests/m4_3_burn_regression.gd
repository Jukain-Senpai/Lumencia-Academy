extends SceneTree

const BattleUnitModel := preload("res://scripts/battle/battle_unit.gd")
const HirukoCombatStateModel := preload("res://scripts/battle/hiruko_combat_state.gd")
const SANDBOX_PATH := "res://scenes/battle/battle_sandbox.tscn"

var failures: Array[String] = []
var checks := 0
var active_scene: Control


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_sword_burn_application()
	await _test_refresh_lethal_and_terminal_order()
	await _test_completed_action_ticks()
	await _test_burn_defeat_results()
	await _test_natural_activation_order_and_scope()
	await _test_debug_and_turn_start_aura_guard()
	await _test_restart_and_ui()
	await _test_full_battle_flow()

	if failures.is_empty():
		print("M4.3 Burn regression suite passed (%d checks)." % checks)
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	push_error("M4.3 Burn regression suite failed: %d failure(s), %d checks." % [failures.size(), checks])
	quit(1)


func _test_sword_burn_application() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	var enemy_a := _find_unit(scene, &"enemy_a")
	_set_current(scene, scene.hiruko_unit)
	var hp_before: int = enemy_a.current_hp
	_check(_attack(scene, &"enemy_a"), "SEALED Basic Attack did not resolve")
	_check(hp_before - enemy_a.current_hp == 10, "SEALED Basic Attack damage changed from 10")
	_check(scene._get_burn_ticks(enemy_a) == 0, "SEALED Basic Attack applied Burn")
	await _free_scene(scene)

	scene = await _new_scene(false)
	if scene == null:
		return
	enemy_a = _find_unit(scene, &"enemy_a")
	_check(scene.hiruko_state.set_seals(0, 100), "Could not prepare FLAMING SWORD")
	_set_current(scene, scene.hiruko_unit)
	hp_before = enemy_a.current_hp
	_check(_attack(scene, &"enemy_a"), "FLAMING SWORD Basic Attack did not resolve")
	_check(hp_before - enemy_a.current_hp == 12, "FLAMING SWORD Basic Attack damage changed from 12")
	_check(scene._get_burn_ticks(enemy_a) == 2, "FLAMING SWORD did not apply Burn 2")
	_check(enemy_a.current_hp == hp_before - 12, "New Burn ticked immediately on its direct target")
	_check(_log_contains(scene, "Hiruko applies Burn on Enemy A (2 ticks)."), "FLAMING SWORD Burn application was not logged")
	await _free_scene(scene)

	scene = await _new_scene(false)
	if scene == null:
		return
	enemy_a = _find_unit(scene, &"enemy_a")
	_check(scene.hiruko_state.set_seals(0, 0), "Could not prepare LAEVATAIN")
	_set_current(scene, scene.hiruko_unit)
	hp_before = enemy_a.current_hp
	_check(_attack(scene, &"enemy_a"), "LAEVATAIN Basic Attack did not resolve")
	_check(hp_before - enemy_a.current_hp == 14, "LAEVATAIN Basic Attack damage changed from 14")
	_check(scene._get_burn_ticks(enemy_a) == 2, "LAEVATAIN Basic Attack did not apply Burn 2")
	_check(scene.hiruko_unit.atk == 10, "M4.3 mutated Hiruko's stored ATK")
	await _free_scene(scene)


func _test_refresh_lethal_and_terminal_order() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	var enemy_a := _find_unit(scene, &"enemy_a")
	scene.hiruko_state.set_seals(0, 100)
	_set_current(scene, scene.hiruko_unit)
	scene.burn_remaining_ticks_by_unit_id[enemy_a.stable_id] = 1
	_check(scene._apply_burn(enemy_a) and scene._get_burn_ticks(enemy_a) == 2, "Burn 1 did not refresh to 2")
	_check(scene._apply_burn(enemy_a) and scene._get_burn_ticks(enemy_a) == 2, "Reapplying Burn at 2 increased its duration")
	_check(_attack(scene, &"enemy_a"), "Burn refresh attack did not resolve")
	_check(scene._get_burn_ticks(enemy_a) == 2, "Burn reapplication added or failed to reset duration to 2")
	_check(_log_contains(scene, "Hiruko refreshes Burn on Enemy A (2 ticks)."), "Burn refresh was not logged")
	var hp_after_attack: int = enemy_a.current_hp
	_set_current(scene, enemy_a)
	_check(scene.resolve_enemy_turn(), "Refreshed enemy did not complete its next action")
	_check(enemy_a.current_hp == hp_after_attack - 5 and scene._get_burn_ticks(enemy_a) == 1, "Refreshed Burn stacked damage or failed to tick exactly 5")
	await _free_scene(scene)

	scene = await _new_scene(false)
	if scene == null:
		return
	enemy_a = _find_unit(scene, &"enemy_a")
	scene.hiruko_state.set_seals(0, 100)
	enemy_a.current_hp = 12
	scene._apply_burn(enemy_a)
	_set_current(scene, scene.hiruko_unit)
	_check(_attack(scene, &"enemy_a"), "Direct lethal sword attack did not resolve")
	_check(enemy_a.defeated and enemy_a.current_hp == 0, "Direct lethal sword attack did not defeat its target")
	_check(scene._get_burn_ticks(enemy_a) == 0, "Defeated direct target retained Burn")
	_check(not _log_contains(scene, "Hiruko refreshes Burn on Enemy A"), "Direct lethal target received a Burn refresh")
	await _free_scene(scene)

	scene = await _new_scene(false)
	if scene == null:
		return
	enemy_a = _find_unit(scene, &"enemy_a")
	for enemy: BattleUnit in scene.enemy_units:
		if enemy != enemy_a:
			_defeat(enemy)
	enemy_a.current_hp = 10
	_set_current(scene, scene.hiruko_unit)
	scene._apply_burn(scene.hiruko_unit)
	var hiruko_hp_before: int = scene.hiruko_unit.current_hp
	_check(_attack(scene, &"enemy_a"), "Terminal direct hit did not resolve")
	_check(scene.battle_result == scene.BattleResult.VICTORY, "Terminal direct hit did not produce Victory")
	_check(scene.hiruko_unit.current_hp == hiruko_hp_before, "Actor took a Burn tick after direct action ended the battle")
	_check(scene._get_burn_ticks(scene.hiruko_unit) == 2, "Terminal direct action consumed the actor's Burn duration")
	await _free_scene(scene)


func _test_completed_action_ticks() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	var enemy_a := _find_unit(scene, &"enemy_a")
	scene._apply_burn(enemy_a)
	_check(scene.resolve_enemy_turn(), "Burned enemy's first action did not resolve")
	_check(enemy_a.current_hp == 37 and scene._get_burn_ticks(enemy_a) == 1, "First completed action did not tick Burn 2 → 1 for 5 HP")
	_set_current(scene, enemy_a)
	_check(scene.resolve_enemy_turn(), "Burned enemy's second action did not resolve")
	_check(enemy_a.current_hp == 32 and scene._get_burn_ticks(enemy_a) == 0, "Second completed action did not tick Burn 1 → expired")
	_check(_log_contains(scene, "Burn expires on Enemy A"), "Burn expiration was not logged")
	await _free_scene(scene)

	scene = await _new_scene(false)
	if scene == null:
		return
	var party_2 := _find_unit(scene, &"party_2")
	_set_current(scene, party_2)
	scene._apply_burn(party_2)
	var hp_before: int = party_2.current_hp
	_check(scene.begin_attack_selection() and scene.cancel_action_selection(), "Attack selection cancellation failed")
	_check(scene.begin_move_selection() and scene.cancel_action_selection(), "Move selection cancellation failed")
	scene._render_battlefield()
	_check(party_2.current_hp == hp_before and scene._get_burn_ticks(party_2) == 2, "Selection, Cancel, or rendering ticked Burn")
	_check(scene.begin_move_selection() and scene.select_move_destination(BattleUnitModel.Line.MID), "Burned unit's Move did not resolve")
	_check(party_2.current_hp == hp_before - 5 and scene._get_burn_ticks(party_2) == 1, "Completed Move did not tick Burn exactly once")
	await _free_scene(scene)

	scene = await _new_scene(false)
	if scene == null:
		return
	_set_current(scene, scene.hiruko_unit)
	scene._apply_burn(scene.hiruko_unit)
	var chains_before: int = scene.hiruko_state.chains_current
	var wrapper_before: int = scene.hiruko_state.wrapper_current
	hp_before = scene.hiruko_unit.current_hp
	_check(scene.begin_move_selection() and scene.select_move_destination(BattleUnitModel.Line.MID), "Burned Hiruko Move did not resolve")
	_check(scene.hiruko_unit.current_hp == hp_before - 5, "Burn did not deal exactly 5 HP-only damage to Hiruko")
	_check(scene.hiruko_state.chains_current == chains_before and scene.hiruko_state.wrapper_current == wrapper_before, "Burn entered Hiruko's hostile-hit/Seal pipeline")
	await _free_scene(scene)


func _test_burn_defeat_results() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	var enemy_a := _find_unit(scene, &"enemy_a")
	enemy_a.current_hp = 4
	scene.burn_remaining_ticks_by_unit_id[enemy_a.stable_id] = 1
	_check(scene.resolve_enemy_turn(), "Burn-lethal nonterminal enemy action did not resolve")
	_check(enemy_a.defeated and enemy_a.current_hp == 0, "Burn did not defeat a 4 HP enemy")
	_check(scene._get_burn_ticks(enemy_a) == 0, "Burn-defeated enemy retained its Burn entry")
	_check(scene.battle_result == scene.BattleResult.NONE, "Nonterminal Burn defeat ended the battle")
	await _free_scene(scene)

	scene = await _new_scene(false)
	if scene == null:
		return
	enemy_a = _find_unit(scene, &"enemy_a")
	for enemy: BattleUnit in scene.enemy_units:
		if enemy != enemy_a:
			_defeat(enemy)
	enemy_a.current_hp = 4
	scene.burn_remaining_ticks_by_unit_id[enemy_a.stable_id] = 1
	_check(scene.resolve_enemy_turn(), "Victory-by-Burn enemy action did not resolve")
	_check(scene.battle_result == scene.BattleResult.VICTORY, "Last enemy's Burn defeat did not use existing Victory logic")
	_check(scene.current_unit == null, "Victory-by-Burn retained a current actor")
	await _free_scene(scene)

	scene = await _new_scene(false)
	if scene == null:
		return
	var party_2 := _find_unit(scene, &"party_2")
	for ally: BattleUnit in scene.party_units:
		if ally != party_2:
			_defeat(ally)
	party_2.current_hp = 4
	scene.burn_remaining_ticks_by_unit_id[party_2.stable_id] = 1
	_set_current(scene, party_2)
	_check(scene.begin_move_selection() and scene.select_move_destination(BattleUnitModel.Line.MID), "Defeat-by-Burn Move did not resolve")
	_check(scene.battle_result == scene.BattleResult.DEFEAT, "Last ally's Burn defeat did not use existing Defeat logic")
	_check(scene.current_unit == null and scene._get_burn_ticks(party_2) == 0, "Defeat-by-Burn retained actor or Burn state")
	await _free_scene(scene)


func _test_natural_activation_order_and_scope() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	var enemy_b := _find_unit(scene, &"enemy_b")
	var enemy_d := _find_unit(scene, &"enemy_d")
	var party_6 := _find_unit(scene, &"party_6")
	_defeat(enemy_d)
	_defeat(party_6)
	_check(scene.hiruko_state.set_seals(0, 5), "Could not prepare natural Wrapper break")
	_set_current(scene, enemy_b)
	_check(scene.resolve_enemy_turn(), "Natural Wrapper-breaking enemy action did not resolve")
	_check(scene.hiruko_unit.current_hp == 38, "Wrapper-breaking hit stopped using hit-start FLAMING SWORD resistance")
	_check(scene.hiruko_state.get_state() == HirukoCombatStateModel.State.LAEVATAIN, "Natural Wrapper break did not enter LAEVATAIN")
	_check(
		enemy_b.current_hp == 33 and scene._get_burn_ticks(enemy_b) == 1,
		"Attacking enemy did not receive activation Burn 2 then immediately tick to 1 (HP %d, Burn %d)" % [
			enemy_b.current_hp,
			scene._get_burn_ticks(enemy_b),
		]
	)
	for unit_id: StringName in [&"party_2", &"party_3", &"party_4", &"party_5", &"enemy_a", &"enemy_c"]:
		_check(scene._get_burn_ticks(_find_unit(scene, unit_id)) == 2, "Activation aura missed living unit %s" % unit_id)
	_check(scene._get_burn_ticks(scene.hiruko_unit) == 0, "Hiruko was affected by her own activation aura")
	_check(scene._get_burn_ticks(party_6) == 0 and scene._get_burn_ticks(enemy_d) == 0, "Activation aura affected a defeated unit")
	var transition_index := _log_index_containing(scene, "Hiruko enters LAEVATAIN.")
	var aura_index := _log_index_containing(scene, "Laevatain activation aura")
	var tick_index := _log_index_containing(scene, "Enemy B takes 5 Burn damage.")
	_check(transition_index >= 0 and transition_index < aura_index and aura_index < tick_index, "Natural activation log/order is not transition → aura → attacker Burn tick")
	_check(_log_contains(scene, "Party 2") and _log_contains(scene, "Enemy C"), "Grouped activation aura log does not identify affected units")
	await _free_scene(scene)


func _test_debug_and_turn_start_aura_guard() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	var actor_before: BattleUnit = scene.current_unit
	var turn_index_before: int = scene.turn_index
	var hiruko_hp_before: int = scene.hiruko_unit.current_hp
	_check(scene.debug_break_chains() and scene.debug_break_wrapper(), "Debug controls did not enter LAEVATAIN")
	_check(_total_burn_entries(scene) == 0, "Debug Wrapper break caused an immediate aura")
	_check(_log_count_containing(scene, " aura") == 0, "Debug Wrapper break logged an aura")
	_check(scene.current_unit == actor_before and scene.turn_index == turn_index_before and scene.hiruko_unit.current_hp == hiruko_hp_before, "Debug Seal controls changed HP or consumed a turn")
	var enemy_a := _find_unit(scene, &"enemy_a")
	var enemy_hp_before: int = enemy_a.current_hp
	scene.advance_turn()
	_check(scene.current_unit == scene.hiruko_unit, "Raw advance did not reach Hiruko's first real turn")
	_check(scene._get_burn_ticks(enemy_a) == 2 and enemy_a.current_hp == enemy_hp_before, "Turn-start aura did not apply Burn 2 without immediate damage")
	_check(scene._get_burn_ticks(scene.hiruko_unit) == 0, "Turn-start aura affected Hiruko")
	_check(_log_count_containing(scene, "Laevatain turn-start aura") == 1, "First Hiruko turn did not trigger exactly one turn-start aura")
	_check(scene.begin_attack_selection() and scene.cancel_action_selection(), "Hiruko Attack Cancel failed during aura guard test")
	_check(scene.begin_move_selection() and scene.cancel_action_selection(), "Hiruko Move Cancel failed during aura guard test")
	scene._render_battlefield()
	scene._try_apply_hiruko_turn_start_aura()
	_check(_log_count_containing(scene, "Laevatain turn-start aura") == 1, "Cancel, rerender, or guard re-entry retriggered the aura")
	scene.burn_remaining_ticks_by_unit_id[enemy_a.stable_id] = 1
	var safety := 0
	while (scene.round_number < 2 or scene.current_unit != scene.hiruko_unit) and safety < 20:
		scene.advance_turn()
		safety += 1
	_check(safety < 20, "Could not reach Hiruko's next real turn")
	_check(_log_count_containing(scene, "Laevatain turn-start aura") == 2, "Next real Hiruko turn did not trigger one new aura")
	_check(scene._get_burn_ticks(enemy_a) == 2, "Next turn-start aura did not refresh Burn to 2")
	await _free_scene(scene)


func _test_restart_and_ui() -> void:
	root.size = Vector2i(1152, 648)
	var scene := await _new_scene(false)
	if scene == null:
		return
	var battlefield: Control = scene.get_node("Margin/Layout/Battlefield")
	var stable_height := battlefield.size.y
	var party_2 := _find_unit(scene, &"party_2")
	scene._apply_burn(party_2)
	scene._apply_burn(scene.hiruko_unit)
	scene._render_battlefield()
	await process_frame
	_check(_count_labels_containing(scene, "[BURN 2]") >= 2, "Unit cards do not expose compact [BURN 2] status")
	_check(is_equal_approx(battlefield.size.y, stable_height), "Burn card status changed the fixed battlefield height")
	_check(scene.get_node("Margin/Layout").size.y <= 624.0, "M4.3 content exceeds safe 1152×648 height")
	scene.hiruko_state.set_seals(0, 0)
	scene._render_battlefield()
	_check("Aura ACTIVE" in scene.get_node("%HirukoProfileLabel").text, "LAEVATAIN profile does not expose Aura ACTIVE")
	for index: int in 5:
		scene.party_units[index].line = BattleUnitModel.Line.MID
	scene.party_units[5].line = BattleUnitModel.Line.BACK
	scene._render_battlefield()
	await process_frame
	_check(scene.get_node("%AllyMidUnits").get_child_count() == 5, "Five-card line did not render with Burn UI")
	_check(is_equal_approx(battlefield.size.y, stable_height), "Five-card Burn layout grew battlefield height")
	root.size = Vector2i(1440, 810)
	await process_frame
	_check(scene.get_node("Margin/Layout").size.y <= 786.0, "M4.3 content exceeds safe 1440×810 height")
	_check(_count_labels_containing(scene, "[BURN 2]") >= 2, "Burn badges disappeared at 1440×810")
	scene.laevatain_aura_turn_token = "fixture-token"
	scene.automatic_enemy_turns_enabled = true
	scene.restart_battle()
	_check(_total_burn_entries(scene) == 0, "Restart did not clear all Burn state")
	_check(scene.laevatain_aura_turn_token.is_empty(), "Restart did not clear the aura turn token")
	_check(scene.hiruko_state.get_state() == HirukoCombatStateModel.State.SEALED, "Restart did not restore SEALED state")
	await process_frame
	await process_frame
	_check(scene.hiruko_unit.current_hp == 41 and scene.hiruko_state.chains_current == 91, "Restart did not produce the one normal SEALED opening hit")
	_check(_log_count_containing(scene, "Enemy A attacks Hiruko for 9 raw damage.") == 1, "Restart produced duplicate opening enemy hits")
	_check(_total_burn_entries(scene) == 0 and not _log_contains(scene, "Burn"), "Restart opening hit retained or created Burn")
	await _free_scene(scene)


func _test_full_battle_flow() -> void:
	var scene := await _new_scene(true)
	if scene == null:
		return
	scene.debug_break_chains()
	scene.debug_break_wrapper()
	var safety := 0
	while scene.battle_result == scene.BattleResult.NONE and safety < 120:
		if scene.current_unit == null or scene.current_unit.team == BattleUnitModel.Team.ENEMY:
			await process_frame
		else:
			if not scene.begin_attack_selection() or scene.valid_attack_targets.is_empty():
				break
			scene.select_attack_target(scene.valid_attack_targets[0].stable_id)
			await process_frame
		safety += 1
	_check(safety < 120 and scene.battle_result != scene.BattleResult.NONE, "Full M4.3 battle did not reach Victory or Defeat")
	_check(scene.current_unit == null and not scene.action_in_progress, "Completed M4.3 battle retained active turn state")
	await _free_scene(scene)


func _attack(scene: Control, target_id: StringName) -> bool:
	return scene.begin_attack_selection() and scene.select_attack_target(target_id)


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


func _find_unit(scene: Control, id: StringName) -> BattleUnit:
	for unit: BattleUnit in scene.party_units + scene.enemy_units:
		if unit.stable_id == id:
			return unit
	return null


func _defeat(unit: BattleUnit) -> void:
	unit.current_hp = 0
	unit.defeated = true


func _total_burn_entries(scene: Control) -> int:
	return scene.burn_remaining_ticks_by_unit_id.size()


func _log_contains(scene: Control, fragment: String) -> bool:
	return _log_index_containing(scene, fragment) >= 0


func _log_index_containing(scene: Control, fragment: String) -> int:
	for index: int in scene.combat_log_entries.size():
		if fragment in scene.combat_log_entries[index]:
			return index
	return -1


func _log_count_containing(scene: Control, fragment: String) -> int:
	var count := 0
	for entry: String in scene.combat_log_entries:
		if fragment in entry:
			count += 1
	return count


func _count_labels_containing(node: Node, fragment: String) -> int:
	var count := 0
	if node is Label and fragment in (node as Label).text:
		count += 1
	for child: Node in node.get_children():
		count += _count_labels_containing(child, fragment)
	return count


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
