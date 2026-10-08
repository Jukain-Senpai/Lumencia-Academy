extends Control

## Milestone 3 battle sandbox. Owns fixture, round, and turn state locally.

const BattleUnitModel := preload("res://scripts/battle/battle_unit.gd")

# Temporary sandbox fixtures. These values are intentionally small and non-canonical.
const PARTY_FIXTURES: Array[Dictionary] = [
	{"id": "party_1", "name": "Party 1", "team": BattleUnitModel.Team.PARTY, "current_hp": 44, "max_hp": 44, "atk": 10, "spd": 14, "line": BattleUnitModel.Line.FRONT, "defeated": false},
	{"id": "party_2", "name": "Party 2", "team": BattleUnitModel.Team.PARTY, "current_hp": 40, "max_hp": 40, "atk": 9, "spd": 11, "line": BattleUnitModel.Line.FRONT, "defeated": false},
	{"id": "party_3", "name": "Party 3", "team": BattleUnitModel.Team.PARTY, "current_hp": 36, "max_hp": 36, "atk": 8, "spd": 9, "line": BattleUnitModel.Line.MID, "defeated": false},
	{"id": "party_4", "name": "Party 4", "team": BattleUnitModel.Team.PARTY, "current_hp": 34, "max_hp": 34, "atk": 7, "spd": 7, "line": BattleUnitModel.Line.MID, "defeated": false},
	{"id": "party_5", "name": "Party 5", "team": BattleUnitModel.Team.PARTY, "current_hp": 30, "max_hp": 30, "atk": 11, "spd": 13, "line": BattleUnitModel.Line.BACK, "defeated": false},
	{"id": "party_6", "name": "Party 6", "team": BattleUnitModel.Team.PARTY, "current_hp": 32, "max_hp": 32, "atk": 6, "spd": 5, "line": BattleUnitModel.Line.BACK, "defeated": false},
]

const ENEMY_FIXTURES: Array[Dictionary] = [
	{"id": "enemy_a", "name": "Enemy A", "team": BattleUnitModel.Team.ENEMY, "current_hp": 42, "max_hp": 42, "atk": 9, "spd": 15, "line": BattleUnitModel.Line.FRONT, "defeated": false},
	{"id": "enemy_b", "name": "Enemy B", "team": BattleUnitModel.Team.ENEMY, "current_hp": 38, "max_hp": 38, "atk": 8, "spd": 12, "line": BattleUnitModel.Line.FRONT, "defeated": false},
	{"id": "enemy_c", "name": "Enemy C", "team": BattleUnitModel.Team.ENEMY, "current_hp": 35, "max_hp": 35, "atk": 10, "spd": 10, "line": BattleUnitModel.Line.MID, "defeated": false},
	{"id": "enemy_d", "name": "Enemy D", "team": BattleUnitModel.Team.ENEMY, "current_hp": 46, "max_hp": 46, "atk": 7, "spd": 6, "line": BattleUnitModel.Line.BACK, "defeated": false},
]

@onready var restart_button: Button = %RestartButton
@onready var attack_button: Button = %AttackButton
@onready var cancel_button: Button = %CancelButton
@onready var resolve_enemy_button: Button = %ResolveEnemyTurnButton
@onready var action_mode_label: Label = %ActionModeLabel
@onready var status_label: Label = %StatusLabel
@onready var round_label: Label = %RoundLabel
@onready var current_turn_label: Label = %CurrentTurnLabel
@onready var turn_order_label: Label = %TurnOrderLabel
@onready var combat_log_label: RichTextLabel = %CombatLog

var party_units: Array[BattleUnit] = []
var enemy_units: Array[BattleUnit] = []
var round_number := 0
var turn_queue: Array[BattleUnit] = []
var turn_index := -1
var current_unit: BattleUnit = null
var combat_log_entries: Array[String] = []
var selecting_target := false
var valid_attack_targets: Array[BattleUnit] = []
var action_in_progress := false
var empty_side_guard_active := false


func _ready() -> void:
	restart_button.pressed.connect(restart_battle)
	attack_button.pressed.connect(begin_attack_selection)
	cancel_button.pressed.connect(cancel_target_selection)
	resolve_enemy_button.pressed.connect(resolve_enemy_turn)
	restart_battle()


func restart_battle() -> void:
	var rebuilt_party := _build_units(PARTY_FIXTURES, BattleUnitModel.Team.PARTY)
	var rebuilt_enemies := _build_units(ENEMY_FIXTURES, BattleUnitModel.Team.ENEMY)
	if (
		rebuilt_party.is_empty()
		or rebuilt_enemies.is_empty()
		or not _has_unique_ids(rebuilt_party + rebuilt_enemies)
	):
		status_label.text = "Sandbox fixture error — check the debugger."
		return

	party_units.assign(rebuilt_party)
	enemy_units.assign(rebuilt_enemies)
	_reset_turn_state()
	_render_battlefield()
	_append_combat_log("Battle started.")
	_start_round()
	restart_button.release_focus()
	attack_button.release_focus()
	cancel_button.release_focus()
	resolve_enemy_button.release_focus()


func advance_turn() -> void:
	# Kept for the M3.2 regression harness. No visible M3.3 control calls this directly.
	if current_unit == null:
		push_error("Cannot advance the sandbox turn without a current actor.")
		return
	_clear_target_selection()
	_activate_next_living_turn()


func begin_attack_selection() -> bool:
	if (
		action_in_progress
		or empty_side_guard_active
		or current_unit == null
		or current_unit.team != BattleUnitModel.Team.PARTY
		or not _is_living(current_unit)
	):
		return false

	valid_attack_targets = _get_valid_attack_targets(current_unit)
	if valid_attack_targets.is_empty():
		_activate_empty_side_guard(current_unit.team)
		return false

	selecting_target = true
	_render_battlefield()
	_refresh_action_ui()
	return true


func cancel_target_selection() -> bool:
	if not selecting_target or action_in_progress:
		return false
	_clear_target_selection()
	_render_battlefield()
	_refresh_action_ui()
	return true


func select_attack_target(target_id: StringName) -> bool:
	if not selecting_target or action_in_progress or current_unit == null:
		return false
	var target := _find_unit_by_id(target_id)
	if target == null:
		return false
	return _commit_basic_attack(current_unit, target)


func resolve_enemy_turn() -> bool:
	if (
		action_in_progress
		or selecting_target
		or empty_side_guard_active
		or current_unit == null
		or current_unit.team != BattleUnitModel.Team.ENEMY
		or not _is_living(current_unit)
	):
		return false

	var targets := _get_valid_attack_targets(current_unit)
	if targets.is_empty():
		_activate_empty_side_guard(current_unit.team)
		return false
	return _commit_basic_attack(current_unit, targets[0])


func _reset_turn_state() -> void:
	round_number = 0
	turn_queue.clear()
	turn_index = -1
	current_unit = null
	combat_log_entries.clear()
	selecting_target = false
	valid_attack_targets.clear()
	action_in_progress = false
	empty_side_guard_active = false
	combat_log_label.clear()
	_refresh_turn_ui()


func _start_round() -> void:
	round_number += 1
	turn_queue = _build_turn_queue(party_units + enemy_units)
	turn_index = -1
	current_unit = null

	if turn_queue.is_empty():
		push_error("Cannot start Round %d: the living-unit turn queue is empty." % round_number)
		status_label.text = "Turn queue error — check the debugger."
		_refresh_turn_ui()
		return

	_append_combat_log("Round %d started." % round_number)
	_activate_next_living_turn()


func _build_turn_queue(units: Array) -> Array[BattleUnit]:
	var queue: Array[BattleUnit] = []
	for unit: BattleUnit in units:
		if _is_living(unit):
			queue.append(unit)

	# Temporary M3 tie-break: ascending stable ID after descending SPD.
	queue.sort_custom(
		func(first: BattleUnit, second: BattleUnit) -> bool:
			if first.spd == second.spd:
				return String(first.stable_id) < String(second.stable_id)
			return first.spd > second.spd
	)

	if not _has_unique_ids(queue):
		push_error("A round queue cannot contain duplicate unit references or IDs.")
		return []
	return queue


func _activate_next_living_turn() -> void:
	_clear_target_selection()
	current_unit = null
	while turn_index + 1 < turn_queue.size():
		turn_index += 1
		var candidate := turn_queue[turn_index]
		if not _is_living(candidate):
			_append_combat_log("%s is defeated and skips their turn." % candidate.display_name)
			continue

		current_unit = candidate
		_append_combat_log("%s's turn." % current_unit.display_name)
		_refresh_turn_ui()
		return

	_start_round()


func _is_living(unit: BattleUnit) -> bool:
	return not unit.defeated and unit.current_hp > 0


func _get_nearest_occupied_line(team: BattleUnit.Team) -> int:
	var units := party_units if team == BattleUnitModel.Team.PARTY else enemy_units
	for line: BattleUnit.Line in [
		BattleUnitModel.Line.FRONT,
		BattleUnitModel.Line.MID,
		BattleUnitModel.Line.BACK,
	]:
		for unit: BattleUnit in units:
			if unit.line == line and _is_living(unit):
				return line
	return -1


func _get_valid_attack_targets(attacker: BattleUnit) -> Array[BattleUnit]:
	var targets: Array[BattleUnit] = []
	if attacker == null or not _is_living(attacker):
		return targets

	var opposing_team: BattleUnit.Team = (
		BattleUnitModel.Team.ENEMY
		if attacker.team == BattleUnitModel.Team.PARTY
		else BattleUnitModel.Team.PARTY
	)
	var nearest_line := _get_nearest_occupied_line(opposing_team)
	if nearest_line < 0:
		return targets

	var opposing_units := enemy_units if opposing_team == BattleUnitModel.Team.ENEMY else party_units
	for unit: BattleUnit in opposing_units:
		if unit.line == nearest_line and _is_living(unit):
			targets.append(unit)
	targets.sort_custom(
		func(first: BattleUnit, second: BattleUnit) -> bool:
			return String(first.stable_id) < String(second.stable_id)
	)
	return targets


func _commit_basic_attack(attacker: BattleUnit, target: BattleUnit) -> bool:
	if action_in_progress or attacker == null or target == null:
		return false
	if attacker != current_unit or not _is_living(attacker):
		return false
	if not _contains_unit(_get_valid_attack_targets(attacker), target):
		return false

	action_in_progress = true
	target.current_hp = maxi(0, target.current_hp - attacker.atk)
	if target.current_hp == 0:
		target.defeated = true

	_append_combat_log(
		"%s attacks %s for %d damage." % [attacker.display_name, target.display_name, attacker.atk]
	)
	if target.defeated:
		_append_combat_log("%s is defeated." % target.display_name)
	else:
		_append_combat_log("%s has %d HP remaining." % [target.display_name, target.current_hp])

	_clear_target_selection()
	if _living_units_for_team(_opposing_team(attacker.team)).is_empty():
		action_in_progress = false
		_activate_empty_side_guard(attacker.team)
		return true

	_render_battlefield()
	action_in_progress = false
	_activate_next_living_turn()
	return true


func _activate_empty_side_guard(acting_team: BattleUnit.Team) -> void:
	empty_side_guard_active = true
	_clear_target_selection()
	current_unit = null
	var message := (
		"No valid enemies remain. Battle result handling is deferred to M3.4."
		if acting_team == BattleUnitModel.Team.PARTY
		else "No valid party members remain. Battle result handling is deferred to M3.4."
	)
	_append_combat_log(message)
	_render_battlefield()
	_refresh_turn_ui()


func _opposing_team(team: BattleUnit.Team) -> BattleUnit.Team:
	return (
		BattleUnitModel.Team.ENEMY
		if team == BattleUnitModel.Team.PARTY
		else BattleUnitModel.Team.PARTY
	)


func _living_units_for_team(team: BattleUnit.Team) -> Array[BattleUnit]:
	var result: Array[BattleUnit] = []
	var units := party_units if team == BattleUnitModel.Team.PARTY else enemy_units
	for unit: BattleUnit in units:
		if _is_living(unit):
			result.append(unit)
	return result


func _contains_unit(units: Array[BattleUnit], target: BattleUnit) -> bool:
	for unit: BattleUnit in units:
		if unit == target:
			return true
	return false


func _find_unit_by_id(target_id: StringName) -> BattleUnit:
	for unit: BattleUnit in party_units + enemy_units:
		if unit.stable_id == target_id:
			return unit
	return null


func _clear_target_selection() -> void:
	selecting_target = false
	valid_attack_targets.clear()


func _append_combat_log(message: String) -> void:
	combat_log_entries.append(message)
	combat_log_label.text = "\n".join(combat_log_entries)
	combat_log_label.scroll_to_line(maxi(0, combat_log_label.get_line_count() - 1))


func _refresh_turn_ui() -> void:
	round_label.text = "Round %d" % round_number if round_number > 0 else "Round —"
	current_turn_label.text = current_unit.display_name if current_unit != null else "—"
	var order_names: PackedStringArray = []
	for unit: BattleUnit in turn_queue:
		order_names.append(unit.display_name)
	turn_order_label.text = " → ".join(order_names) if not order_names.is_empty() else "—"
	_refresh_action_ui()


func _refresh_action_ui() -> void:
	attack_button.hide()
	cancel_button.hide()
	resolve_enemy_button.hide()
	if empty_side_guard_active:
		action_mode_label.text = "Battle result handling is deferred to M3.4."
		status_label.text = "No opposing targets remain."
	elif current_unit == null:
		action_mode_label.text = "No current actor"
		status_label.text = "Turn engine paused."
	elif selecting_target:
		action_mode_label.text = "Attack — Select Target"
		cancel_button.show()
		status_label.text = "Choose a marked target or cancel."
	elif current_unit.team == BattleUnitModel.Team.PARTY:
		action_mode_label.text = "Choose action"
		attack_button.show()
		status_label.text = "Party turn — Basic Attack is required."
	else:
		action_mode_label.text = "Enemy turn"
		resolve_enemy_button.show()
		status_label.text = "Resolve one deterministic enemy attack."


func _build_units(fixtures: Array[Dictionary], expected_team: BattleUnit.Team) -> Array[BattleUnit]:
	var result: Array[BattleUnit] = []
	var ids: Dictionary = {}
	for fixture: Dictionary in fixtures:
		var unit := BattleUnitModel.from_fixture(fixture)
		if unit == null:
			return []
		if unit.team != expected_team:
			push_error(
				"Battle fixture '%s' is in the wrong fixture collection." % unit.stable_id
			)
			return []
		if ids.has(unit.stable_id):
			push_error("Duplicate battle unit ID '%s'." % unit.stable_id)
			return []
		ids[unit.stable_id] = true
		result.append(unit)
	return result


func _has_unique_ids(units: Array[BattleUnit]) -> bool:
	var ids: Dictionary = {}
	for unit: BattleUnit in units:
		if ids.has(unit.stable_id):
			push_error("Duplicate battle unit ID '%s'." % unit.stable_id)
			return false
		ids[unit.stable_id] = true
	return true


func _render_battlefield() -> void:
	for container: VBoxContainer in _all_line_containers():
		for child: Node in container.get_children():
			container.remove_child(child)
			child.queue_free()

	for unit: BattleUnit in party_units + enemy_units:
		_line_container_for(unit.team, unit.line).add_child(_create_unit_card(unit))


func _all_line_containers() -> Array[VBoxContainer]:
	return [
		%AllyBackUnits,
		%AllyMidUnits,
		%AllyFrontUnits,
		%EnemyFrontUnits,
		%EnemyMidUnits,
		%EnemyBackUnits,
	]


func _line_container_for(team: BattleUnit.Team, line: BattleUnit.Line) -> VBoxContainer:
	if team == BattleUnitModel.Team.PARTY:
		match line:
			BattleUnitModel.Line.FRONT:
				return %AllyFrontUnits
			BattleUnitModel.Line.MID:
				return %AllyMidUnits
			BattleUnitModel.Line.BACK:
				return %AllyBackUnits
	else:
		match line:
			BattleUnitModel.Line.FRONT:
				return %EnemyFrontUnits
			BattleUnitModel.Line.MID:
				return %EnemyMidUnits
			BattleUnitModel.Line.BACK:
				return %EnemyBackUnits

	push_error("No visual container for team '%s', line '%s'." % [team, line])
	return %AllyBackUnits


func _create_unit_card(unit: BattleUnit) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(132, 96)
	card.tooltip_text = "Stable ID: %s" % unit.stable_id

	var style := StyleBoxFlat.new()
	style.bg_color = Color("243b53") if unit.team == BattleUnitModel.Team.PARTY else Color("4a2837")
	style.border_color = Color("78b7d0") if unit.team == BattleUnitModel.Team.PARTY else Color("d4858f")
	style.set_border_width_all(2)
	if unit.defeated:
		style.bg_color = Color("242832")
		style.border_color = Color("5c626d")
	elif selecting_target and _contains_unit(valid_attack_targets, unit):
		style.border_color = Color("f2c879")
		style.set_border_width_all(4)
	style.set_corner_radius_all(8)
	style.content_margin_left = 8.0
	style.content_margin_top = 8.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 8.0
	card.add_theme_stylebox_override("panel", style)

	var details := VBoxContainer.new()
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.add_theme_constant_override("separation", 3)
	card.add_child(details)

	var identity_row := HBoxContainer.new()
	identity_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.add_child(identity_row)

	var name_label := Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text = unit.display_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 18)
	identity_row.add_child(name_label)

	var line_label := Label.new()
	line_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line_label.text = BattleUnitModel.line_name(unit.line).to_upper()
	line_label.add_theme_color_override("font_color", Color("f2c879"))
	identity_row.add_child(line_label)

	var hp_label := Label.new()
	hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_label.text = "HP  %d / %d" % [unit.current_hp, unit.max_hp]
	details.add_child(hp_label)

	var stats_label := Label.new()
	stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if unit.defeated:
		stats_label.text = "DEFEATED"
		stats_label.add_theme_color_override("font_color", Color("d4858f"))
	elif selecting_target and _contains_unit(valid_attack_targets, unit):
		stats_label.text = "SELECT TARGET"
		stats_label.add_theme_color_override("font_color", Color("f2c879"))
		card.tooltip_text = "Click to attack %s" % unit.display_name
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.gui_input.connect(_on_target_card_input.bind(unit.stable_id))
	else:
		stats_label.text = "ATK %d     SPD %d" % [unit.atk, unit.spd]
		stats_label.add_theme_color_override("font_color", Color("c9d6e2"))
	details.add_child(stats_label)
	return card


func _on_target_card_input(event: InputEvent, target_id: StringName) -> void:
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
	):
		get_viewport().set_input_as_handled()
		select_attack_target(target_id)
