extends SceneTree

const BattleUnitModel := preload("res://scripts/battle/battle_unit.gd")
const SANDBOX_PATH := "res://scenes/battle/battle_sandbox.tscn"

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_fixture_validation()
	var scene := await _new_scene()
	if scene != null:
		_test_roster(scene)
		_test_formations(scene)
		_test_visual_orientation(scene)
		await _test_restart(scene)
		scene.queue_free()
		await process_frame

	if failures.is_empty():
		print("M3.1 combat sandbox regression suite passed (%d checks)." % checks)
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	push_error("M3.1 combat sandbox regression suite failed: %d failure(s), %d checks." % [failures.size(), checks])
	quit(1)


func _test_fixture_validation() -> void:
	var valid := {
		"id": "fixture", "name": "Fixture", "team": BattleUnitModel.Team.PARTY,
		"current_hp": 25, "max_hp": 25, "atk": 6, "spd": 5,
		"line": BattleUnitModel.Line.FRONT, "defeated": false,
	}
	var unit := BattleUnitModel.from_fixture(valid)
	_check(unit != null, "A valid combatant fixture was rejected")
	if unit != null:
		_check(unit.stable_id == &"fixture", "Stable ID was not retained")
		_check(unit.current_hp == 25 and unit.max_hp == 25, "HP fields were not retained")
		_check(unit.team == BattleUnitModel.Team.PARTY, "Team was not retained")
		_check(unit.line == BattleUnitModel.Line.FRONT, "Semantic line was not retained")
		_check(not unit.defeated, "Defeated state was not retained")


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


func _test_roster(scene: Control) -> void:
	_check(scene.party_units.size() == 6, "Sandbox must contain exactly six party units")
	_check(scene.enemy_units.size() == 4, "Sandbox must contain exactly four enemy units")
	var ids: Dictionary = {}
	for unit: BattleUnit in scene.party_units + scene.enemy_units:
		_check(not ids.has(unit.stable_id), "Duplicate unit ID '%s'" % unit.stable_id)
		ids[unit.stable_id] = true
		_check(not unit.display_name.is_empty(), "Unit '%s' has no display name" % unit.stable_id)
		_check(unit.current_hp == unit.max_hp, "Unit '%s' did not start at full HP" % unit.stable_id)
		_check(unit.atk >= 0 and unit.spd >= 0, "Unit '%s' has invalid temporary stats" % unit.stable_id)
		_check(not unit.defeated, "Unit '%s' started defeated" % unit.stable_id)


func _test_formations(scene: Control) -> void:
	_check(_ids_in_line(scene.party_units, BattleUnitModel.Line.FRONT) == [&"party_2"], "Party Front formation is incorrect")
	_check(_ids_in_line(scene.party_units, BattleUnitModel.Line.MID) == [&"party_1", &"party_3", &"party_4"], "Party Mid formation is incorrect")
	_check(_ids_in_line(scene.party_units, BattleUnitModel.Line.BACK) == [&"party_5", &"party_6"], "Party Back formation is incorrect")
	_check(_ids_in_line(scene.enemy_units, BattleUnitModel.Line.FRONT) == [&"enemy_a", &"enemy_b"], "Enemy Front formation is incorrect")
	_check(_ids_in_line(scene.enemy_units, BattleUnitModel.Line.MID) == [&"enemy_c"], "Enemy Mid formation is incorrect")
	_check(_ids_in_line(scene.enemy_units, BattleUnitModel.Line.BACK) == [&"enemy_d"], "Enemy Back formation is incorrect")


func _test_visual_orientation(scene: Control) -> void:
	var ally_lines := scene.get_node("Margin/Layout/Battlefield/Allies/Layout/Lines")
	var enemy_lines := scene.get_node("Margin/Layout/Battlefield/Enemies/Layout/Lines")
	_check(_child_names(ally_lines) == ["Back", "Mid", "Front"], "Ally visual order must be Back / Mid / Front")
	_check(_child_names(enemy_lines) == ["Front", "Mid", "Back"], "Enemy visual order must be Front / Mid / Back")
	_check(scene.get_node("%AllyFrontUnits").get_child_count() == 1, "Ally Front did not render one card")
	_check(scene.get_node("%EnemyFrontUnits").get_child_count() == 2, "Enemy Front did not render two cards")


func _test_restart(scene: Control) -> void:
	var original: BattleUnit = scene.party_units[0]
	original.current_hp = 1
	original.line = BattleUnitModel.Line.BACK
	original.defeated = true
	scene.restart_battle()
	await process_frame
	var restored: BattleUnit = scene.party_units[0]
	_check(restored.current_hp == restored.max_hp, "Restart did not restore HP")
	_check(restored.line == BattleUnitModel.Line.MID, "Restart did not restore line")
	_check(not restored.defeated, "Restart did not restore defeated=false")
	_check(restored != original, "Restart did not rebuild clean runtime state")


func _ids_in_line(units: Array, line: BattleUnit.Line) -> Array[StringName]:
	var result: Array[StringName] = []
	for unit: BattleUnit in units:
		if unit.line == line:
			result.append(unit.stable_id)
	return result


func _child_names(node: Node) -> Array[String]:
	var result: Array[String] = []
	for child: Node in node.get_children():
		result.append(child.name)
	return result


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
