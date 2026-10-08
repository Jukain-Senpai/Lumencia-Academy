extends Control

## M3.1-only battle sandbox. Owns its fixture state and presentation locally.

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
@onready var status_label: Label = %StatusLabel

var party_units: Array[BattleUnit] = []
var enemy_units: Array[BattleUnit] = []


func _ready() -> void:
	restart_button.pressed.connect(restart_battle)
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
	_render_battlefield()
	status_label.text = "Formation ready — combat actions begin in M3.2."
	restart_button.release_focus()


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
	card.custom_minimum_size = Vector2(132, 112)
	card.tooltip_text = "Stable ID: %s" % unit.stable_id

	var style := StyleBoxFlat.new()
	style.bg_color = Color("243b53") if unit.team == BattleUnitModel.Team.PARTY else Color("4a2837")
	style.border_color = Color("78b7d0") if unit.team == BattleUnitModel.Team.PARTY else Color("d4858f")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12.0
	style.content_margin_top = 10.0
	style.content_margin_right = 12.0
	style.content_margin_bottom = 10.0
	card.add_theme_stylebox_override("panel", style)

	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 3)
	card.add_child(details)

	var name_label := Label.new()
	name_label.text = unit.display_name
	name_label.add_theme_font_size_override("font_size", 18)
	details.add_child(name_label)

	var hp_label := Label.new()
	hp_label.text = "HP  %d / %d" % [unit.current_hp, unit.max_hp]
	details.add_child(hp_label)

	var stats_label := Label.new()
	stats_label.text = "ATK %d     SPD %d" % [unit.atk, unit.spd]
	stats_label.add_theme_color_override("font_color", Color("c9d6e2"))
	details.add_child(stats_label)

	var line_label := Label.new()
	line_label.text = BattleUnitModel.line_name(unit.line).to_upper()
	line_label.add_theme_color_override("font_color", Color("f2c879"))
	details.add_child(line_label)
	return card
