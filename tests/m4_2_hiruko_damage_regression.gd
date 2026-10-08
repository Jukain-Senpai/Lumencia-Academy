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
	_test_profiles_and_rounding()
	await _test_opening_sealed_hit()
	await _test_chain_break_state_at_start_and_no_overflow()
	await _test_flaming_hits_and_wrapper_break()
	await _test_laevatain_incoming_hit()
	await _test_outgoing_basic_attacks()
	await _test_generic_damage_and_sealed_defeat()
	await _test_debug_and_natural_state_share_authority()
	await _test_restart_and_opening_callback()
	await _test_completion_flow()
	await _test_layout()

	if failures.is_empty():
		print("M4.2 Hiruko damage regression suite passed (%d checks)." % checks)
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	push_error("M4.2 Hiruko damage regression suite failed: %d failure(s), %d checks." % [failures.size(), checks])
	quit(1)


func _test_profiles_and_rounding() -> void:
	var state := HirukoCombatStateModel.new()
	var hit: Dictionary = state.prepare_hostile_hit(9)
	_check(hit["state_at_hit_start"] == HirukoCombatStateModel.State.SEALED, "Prepared hit did not capture SEALED")
	_check(hit["resistance_percent"] == 70 and hit["hp_damage"] == 3, "SEALED raw 9 did not ceil-scale to 3 HP damage")
	_check(hit["active_seal"] == HirukoCombatStateModel.ActiveSeal.CHAINS, "SEALED did not select Chains")
	_check(state.get_basic_attack_damage(10) == 10 and state.get_basic_attack_type_label() == "BLUNT", "SEALED Basic profile is incorrect")
	_check(state.set_seals(0, 100), "Could not enter FLAMING SWORD fixture state")
	hit = state.prepare_hostile_hit(9)
	_check(hit["resistance_percent"] == 35 and hit["hp_damage"] == 6, "FLAMING SWORD raw 9 did not ceil-scale to 6 HP damage")
	_check(hit["active_seal"] == HirukoCombatStateModel.ActiveSeal.WRAPPER, "FLAMING SWORD did not select Wrapper")
	_check(state.get_basic_attack_damage(10) == 12 and state.get_basic_attack_type_label() == "SLASH", "FLAMING SWORD Basic profile is incorrect")
	_check(state.set_seals(0, 0), "Could not enter LAEVATAIN fixture state")
	hit = state.prepare_hostile_hit(9)
	_check(hit["resistance_percent"] == 0 and hit["hp_damage"] == 9, "LAEVATAIN raw 9 did not remain full HP damage")
	_check(hit["active_seal"] == HirukoCombatStateModel.ActiveSeal.NONE, "LAEVATAIN unexpectedly selected an active Seal")
	_check(state.get_basic_attack_damage(10) == 14 and state.get_basic_attack_type_label() == "SLASH", "LAEVATAIN Basic profile is incorrect")
	_check(state.get_basic_attack_damage(-5) == 0 and state.prepare_hostile_hit(-5)["hp_damage"] == 0, "Negative damage was not clamped to zero")


func _test_opening_sealed_hit() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_check(scene.resolve_enemy_turn(), "Opening Enemy A hit did not resolve")
	_check(scene.hiruko_unit.current_hp == 41, "Opening raw 9 did not reduce Hiruko HP by exactly 3")
	_check(scene.hiruko_state.chains_current == 91, "Opening raw 9 did not reduce Chains by exactly 9")
	_check(scene.hiruko_state.wrapper_current == 100, "Opening hit incorrectly damaged Wrapper")
	_check(scene.hiruko_state.get_state() == HirukoCombatStateModel.State.SEALED, "Opening hit changed state unexpectedly")
	_check(scene.get_node("%ChainsSealBar").value == 91 and scene.get_node("%ChainsSealValueLabel").text == "91/100", "Opening hit did not immediately update partial Chains UI")
	_check(scene.combat_log_entries.has("Enemy A attacks Hiruko for 9 raw damage."), "Opening raw damage was not logged")
	_check(scene.combat_log_entries.has("Hiruko resists 70% and takes 3 damage."), "Opening resistance was not logged")
	_check(scene.combat_log_entries.has("Seal [Chains]: 100 → 91."), "Opening Seal damage was not logged")
	await _free_scene(scene)


func _test_chain_break_state_at_start_and_no_overflow() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_check(scene.hiruko_state.set_seals(5, 100), "Could not prepare partial Chains fixture")
	scene._render_battlefield()
	_check(scene.resolve_enemy_turn(), "Chain-breaking hit did not resolve")
	_check(scene.hiruko_unit.current_hp == 41, "Chain-breaking hit did not use SEALED resistance captured at hit start")
	_check(scene.hiruko_state.chains_current == 0, "Chain-breaking hit did not clamp Chains to zero")
	_check(scene.hiruko_state.wrapper_current == 100, "Chain damage overflowed into Wrapper")
	_check(scene.hiruko_state.get_state() == HirukoCombatStateModel.State.FLAMING_SWORD, "Chain break did not derive FLAMING SWORD")
	_check(scene.get_node("%HirukoStateLabel").text == "FLAMING SWORD", "Natural Chain break left stale state UI")
	_check(scene.get_node("%ChainsSealValueLabel").text == "BROKEN", "Natural Chain break did not show BROKEN")
	_check(scene.get_node("%HirukoProfileLabel").text == "DR 35%  •  Basic SLASH ×1.2", "Natural Chain break did not update the combat profile")
	_check(scene.combat_log_entries.has("Seal [Chains] is broken.") and scene.combat_log_entries.has("Hiruko enters FLAMING SWORD."), "Natural Chain transition feedback is incomplete")
	await _free_scene(scene)


func _test_flaming_hits_and_wrapper_break() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_check(scene.hiruko_state.set_seals(0, 100), "Could not prepare FLAMING SWORD fixture")
	_check(scene.resolve_enemy_turn(), "FLAMING SWORD hit did not resolve")
	_check(scene.hiruko_unit.current_hp == 38, "FLAMING SWORD raw 9 did not deal exactly 6 HP damage")
	_check(scene.hiruko_state.wrapper_current == 91 and scene.hiruko_state.chains_current == 0, "FLAMING SWORD hit did not damage only Wrapper by raw 9")
	_check(scene.hiruko_state.get_state() == HirukoCombatStateModel.State.FLAMING_SWORD, "Non-breaking Wrapper hit changed state")
	await _free_scene(scene)

	scene = await _new_scene(false)
	if scene == null:
		return
	_check(scene.hiruko_state.set_seals(0, 5), "Could not prepare partial Wrapper fixture")
	_check(scene.resolve_enemy_turn(), "Wrapper-breaking hit did not resolve")
	_check(scene.hiruko_unit.current_hp == 38, "Wrapper-breaking hit did not use FLAMING SWORD resistance captured at hit start")
	_check(scene.hiruko_state.wrapper_current == 0 and scene.hiruko_state.chains_current == 0, "Wrapper-breaking hit did not clamp only Wrapper")
	_check(scene.hiruko_state.get_state() == HirukoCombatStateModel.State.LAEVATAIN, "Wrapper break did not derive LAEVATAIN")
	_check(scene.get_node("%HirukoStateLabel").text == "LAEVATAIN" and scene.get_node("%WrapperSealValueLabel").text == "BROKEN", "Natural Wrapper break left stale UI")
	_check(scene.get_node("%HirukoProfileLabel").text == "DR 0%  •  Basic SLASH ×1.4", "Natural Wrapper break did not update the combat profile")
	_check(scene.combat_log_entries.has("Seal [Wrapper] is broken.") and scene.combat_log_entries.has("Hiruko enters LAEVATAIN."), "Natural Wrapper transition feedback is incomplete")
	await _free_scene(scene)


func _test_laevatain_incoming_hit() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	scene.hiruko_state.set_seals(0, 0)
	_check(scene.resolve_enemy_turn(), "LAEVATAIN incoming hit did not resolve")
	_check(scene.hiruko_unit.current_hp == 35, "LAEVATAIN did not take full raw 9 HP damage")
	_check(scene.hiruko_state.chains_current == 0 and scene.hiruko_state.wrapper_current == 0, "LAEVATAIN hit changed broken Seal values")
	_check(scene.combat_log_entries.has("Hiruko resists 0% and takes 9 damage."), "LAEVATAIN full damage was not logged")
	await _free_scene(scene)


func _test_outgoing_basic_attacks() -> void:
	await _check_hiruko_basic_attack(100, 100, 10, "Blunt", "SEALED")
	await _check_hiruko_basic_attack(0, 100, 12, "Slash", "FLAMING SWORD")
	await _check_hiruko_basic_attack(0, 0, 14, "Slash", "LAEVATAIN")


func _check_hiruko_basic_attack(chains: int, wrapper: int, expected_damage: int, type_label: String, state_label: String) -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_check(scene.hiruko_state.set_seals(chains, wrapper), "Could not prepare %s outgoing fixture" % state_label)
	scene.advance_turn()
	var enemy_a := _find_unit(scene, &"enemy_a")
	var hp_before: int = enemy_a.current_hp
	_check(scene.begin_attack_selection() and scene.select_attack_target(&"enemy_a"), "%s Basic Attack did not resolve" % state_label)
	_check(hp_before - enemy_a.current_hp == expected_damage, "%s Basic Attack dealt incorrect damage" % state_label)
	_check(scene.hiruko_unit.atk == 10, "%s transition mutated Hiruko's stored ATK" % state_label)
	_check(scene.combat_log_entries.has("Hiruko attacks Enemy A for %d %s damage." % [expected_damage, type_label]), "%s damage type was not logged" % state_label)
	_check(not _log_contains(scene, "Burn"), "%s Basic Attack introduced Burn during M4.2" % state_label)
	await _free_scene(scene)


func _test_generic_damage_and_sealed_defeat() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	var party_2 := _find_unit(scene, &"party_2")
	var enemy_a := _find_unit(scene, &"enemy_a")
	_set_current(scene, party_2)
	var hp_before: int = enemy_a.current_hp
	_check(scene.begin_attack_selection() and scene.select_attack_target(&"enemy_a"), "Generic Party 2 attack did not resolve")
	_check(hp_before - enemy_a.current_hp == party_2.atk and party_2.atk == 9, "Generic Basic Attack no longer deals exactly ATK")
	await _free_scene(scene)

	scene = await _new_scene(false)
	if scene == null:
		return
	scene.hiruko_unit.current_hp = 3
	_check(scene.resolve_enemy_turn(), "Lethal SEALED hit did not resolve")
	_check(scene.hiruko_unit.current_hp == 0 and scene.hiruko_unit.defeated, "Seals prevented normal HP defeat")
	_check(scene.hiruko_state.chains_current == 91 and scene.hiruko_state.wrapper_current == 100, "Lethal hit did not still damage the active Seal")
	await _free_scene(scene)


func _test_debug_and_natural_state_share_authority() -> void:
	var scene := await _new_scene(false)
	if scene == null:
		return
	_check(scene.debug_break_chains(), "M4.1 Break Chains debug path stopped working")
	_check(scene.resolve_enemy_turn(), "Natural hit after debug transition did not resolve")
	_check(scene.hiruko_unit.current_hp == 38 and scene.hiruko_state.wrapper_current == 91, "Natural hit did not use debug-created FLAMING SWORD authority")
	_check(scene.debug_reset_hiruko(), "M4.1 Reset Hiruko debug path stopped working")
	_check(scene.hiruko_unit.current_hp == 38, "Reset Hiruko debug path incorrectly healed HP")
	_check(scene.hiruko_state.chains_current == 100 and scene.hiruko_state.wrapper_current == 100, "Reset Hiruko did not restore only Seal state")
	await _free_scene(scene)


func _test_restart_and_opening_callback() -> void:
	var scene := _instantiate_scene(true)
	if scene == null:
		return
	root.add_child(scene)
	active_scene = scene
	_check(scene.hiruko_unit.current_hp == 44 and scene.hiruko_state.chains_current == 100, "Fresh Restart fixture was not built before deferred enemy processing")
	await process_frame
	await process_frame
	_check(scene.hiruko_unit.current_hp == 41 and scene.hiruko_state.chains_current == 91, "Automatic opening hit did not produce HP 41 / Chains 91")
	_check(scene.hiruko_state.wrapper_current == 100 and scene.hiruko_state.get_state() == HirukoCombatStateModel.State.SEALED, "Automatic opening hit changed Wrapper or state")

	scene.hiruko_unit.current_hp = 1
	scene.hiruko_unit.line = BattleUnitModel.Line.MID
	scene.hiruko_unit.defeated = true
	scene.hiruko_state.set_seals(0, 0)
	scene.restart_battle()
	await process_frame
	await process_frame
	_check(scene.hiruko_unit.current_hp == 41 and scene.hiruko_unit.line == BattleUnitModel.Line.FRONT and not scene.hiruko_unit.defeated, "Restart did not restore fixture then apply one opening hit")
	_check(scene.hiruko_state.chains_current == 91 and scene.hiruko_state.wrapper_current == 100, "Restart did not restore Seals then apply one opening hit")
	_check(_log_count(scene, "Enemy A attacks Hiruko for 9 raw damage.") == 1, "Restart produced duplicate opening enemy hits")
	await _free_scene(scene)


func _test_completion_flow() -> void:
	var scene := await _new_scene(true)
	if scene == null:
		return
	scene.debug_break_chains()
	scene.debug_break_wrapper()
	var safety := 0
	while scene.battle_result == scene.BattleResult.NONE and safety < 100:
		if scene.current_unit == null or scene.current_unit.team == BattleUnitModel.Team.ENEMY:
			await process_frame
		else:
			if not scene.begin_attack_selection() or scene.valid_attack_targets.is_empty():
				break
			scene.select_attack_target(scene.valid_attack_targets[0].stable_id)
			await process_frame
		safety += 1
	_check(safety < 100 and scene.battle_result != scene.BattleResult.NONE, "Battle with M4.2 mechanics did not reach Victory or Defeat")
	_check(scene.current_unit == null, "Completed M4.2 battle retained a current actor")
	await _free_scene(scene)


func _test_layout() -> void:
	root.size = Vector2i(1152, 648)
	var scene := await _new_scene(false)
	if scene == null:
		return
	scene.hiruko_state.set_seals(50, 100)
	scene._render_battlefield()
	await process_frame
	_check(scene.get_node("Margin/Layout").size.y <= 624.0, "M4.2 content exceeds safe 1152x648 height (%s px)" % scene.get_node("Margin/Layout").size.y)
	_check(_inside_viewport(scene.get_node("%HirukoProfileLabel")) and _inside_viewport(scene.get_node("%ResetHirukoButton")), "M4.2 profile/debug controls are outside 1152x648")
	_check(scene.get_node("%ChainsSealValueLabel").text == "50/100", "Partial Seal presentation did not survive M4.2 UI changes")
	var battlefield: Control = scene.get_node("Margin/Layout/Battlefield")
	var stable_height := battlefield.size.y
	for index: int in 5:
		scene.party_units[index].line = BattleUnitModel.Line.MID
	scene.party_units[5].line = BattleUnitModel.Line.BACK
	scene._render_battlefield()
	await process_frame
	_check(scene.get_node("%AllyMidUnits").get_child_count() == 5, "Five-card M4.2 line did not render all cards")
	_check(is_equal_approx(battlefield.size.y, stable_height), "Five-card M4.2 line changed battlefield height")
	_check(scene.get_node("Margin/Layout").size.y <= 624.0, "Five-card M4.2 line exceeded safe height")
	root.size = Vector2i(1440, 810)
	await process_frame
	_check(scene.get_node("Margin/Layout").size.y <= 786.0, "M4.2 content exceeds safe 1440x810 height")
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
	scene._clear_action_selection()
	scene._refresh_turn_ui()


func _find_unit(scene: Control, id: StringName) -> BattleUnit:
	for unit: BattleUnit in scene.party_units + scene.enemy_units:
		if unit.stable_id == id:
			return unit
	return null


func _log_contains(scene: Control, fragment: String) -> bool:
	for entry: String in scene.combat_log_entries:
		if fragment in entry:
			return true
	return false


func _log_count(scene: Control, entry: String) -> int:
	var count := 0
	for logged: String in scene.combat_log_entries:
		if logged == entry:
			count += 1
	return count


func _inside_viewport(control: Control) -> bool:
	var rect := control.get_global_rect()
	return rect.position.x >= 0.0 and rect.position.y >= 0.0 and rect.end.x <= 1152.0 and rect.end.y <= 648.0


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
