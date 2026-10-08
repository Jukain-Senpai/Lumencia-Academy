class_name BattleUnit
extends RefCounted

## Mutable runtime state for the isolated Milestone 3 combat sandbox.
## The numbers loaded into this model are test fixtures, not final balance data.

enum Team {
	PARTY,
	ENEMY,
}

enum Line {
	FRONT,
	MID,
	BACK,
}

const REQUIRED_FIELDS := [
	"id",
	"name",
	"team",
	"current_hp",
	"max_hp",
	"atk",
	"spd",
	"line",
	"defeated",
]

var stable_id: StringName
var display_name: String
var team: Team
var current_hp: int
var max_hp: int
var atk: int
var spd: int
var line: Line
var defeated: bool


static func from_fixture(fixture: Dictionary) -> BattleUnit:
	for field: String in REQUIRED_FIELDS:
		if not fixture.has(field):
			push_error("Battle fixture is missing required field '%s'." % field)
			return null

	if typeof(fixture["id"]) != TYPE_STRING or fixture["id"].strip_edges().is_empty():
		push_error("Battle fixture requires a non-empty string ID.")
		return null
	if typeof(fixture["name"]) != TYPE_STRING or fixture["name"].strip_edges().is_empty():
		push_error("Battle fixture '%s' requires a non-empty name." % fixture["id"])
		return null
	if not fixture["team"] in Team.values():
		push_error("Battle fixture '%s' has invalid team value '%s'." % [fixture["id"], fixture["team"]])
		return null
	if not fixture["line"] in Line.values():
		push_error("Battle fixture '%s' has invalid line value '%s'." % [fixture["id"], fixture["line"]])
		return null

	for field: String in ["current_hp", "max_hp", "atk", "spd"]:
		if typeof(fixture[field]) != TYPE_INT:
			push_error("Battle fixture '%s' field '%s' must be an integer." % [fixture["id"], field])
			return null
	if fixture["max_hp"] <= 0:
		push_error("Battle fixture '%s' max HP must be greater than zero." % fixture["id"])
		return null
	if fixture["current_hp"] < 0 or fixture["current_hp"] > fixture["max_hp"]:
		push_error(
			"Battle fixture '%s' current HP must be between 0 and max HP." % fixture["id"]
		)
		return null
	if fixture["atk"] < 0 or fixture["spd"] < 0:
		push_error("Battle fixture '%s' ATK and SPD cannot be negative." % fixture["id"])
		return null
	if typeof(fixture["defeated"]) != TYPE_BOOL:
		push_error("Battle fixture '%s' defeated state must be a boolean." % fixture["id"])
		return null

	var unit := BattleUnit.new()
	unit.stable_id = StringName(fixture["id"])
	unit.display_name = fixture["name"].strip_edges()
	unit.team = fixture["team"]
	unit.current_hp = fixture["current_hp"]
	unit.max_hp = fixture["max_hp"]
	unit.atk = fixture["atk"]
	unit.spd = fixture["spd"]
	unit.line = fixture["line"]
	unit.defeated = fixture["defeated"]
	return unit


static func team_name(value: Team) -> String:
	return Team.keys()[value].capitalize()


static func line_name(value: Line) -> String:
	return Line.keys()[value].capitalize()
