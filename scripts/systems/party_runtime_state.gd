class_name PartyRuntimeState
extends RefCounted

const DEFAULT_MEMBERS := [
	{"id": "party_1", "display_name": "Hiruko", "current_hp": 44, "max_hp": 44},
	{"id": "party_2", "display_name": "Jukain", "current_hp": 40, "max_hp": 40},
	{"id": "party_3", "display_name": "Party 3", "current_hp": 36, "max_hp": 36},
	{"id": "party_4", "display_name": "Party 4", "current_hp": 34, "max_hp": 34},
	{"id": "party_5", "display_name": "Party 5", "current_hp": 30, "max_hp": 30},
	{"id": "party_6", "display_name": "Party 6", "current_hp": 32, "max_hp": 32},
]

var _members: Dictionary = {}


func _init() -> void:
	reset()


func reset() -> void:
	_members.clear()
	for definition: Dictionary in DEFAULT_MEMBERS:
		_members[definition["id"]] = definition.duplicate(true)


func has_member(member_id: String) -> bool:
	return _members.has(member_id)


func get_member(member_id: String) -> Dictionary:
	if not has_member(member_id):
		return {}
	return _members[member_id].duplicate(true)


func get_members() -> Array:
	var result: Array = []
	for definition: Dictionary in DEFAULT_MEMBERS:
		result.append(get_member(definition["id"]))
	return result


func get_hp_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for member_id: String in _members:
		var member: Dictionary = _members[member_id]
		snapshot[member_id] = {
			"current_hp": member["current_hp"],
			"max_hp": member["max_hp"],
		}
	return snapshot


func validate_battle_fixtures(fixtures: Array[Dictionary]) -> bool:
	if fixtures.size() != _members.size():
		return false
	for fixture: Dictionary in fixtures:
		var member_id: String = fixture.get("id", "")
		if not has_member(member_id):
			return false
		var member: Dictionary = _members[member_id]
		if (
			fixture.get("name") != member["display_name"]
			or fixture.get("max_hp") != member["max_hp"]
		):
			return false
	return true


func apply_hp_snapshot(snapshot: Dictionary) -> bool:
	if snapshot.size() != _members.size():
		return false
	for member_id: String in _members:
		var raw_hp: Variant = snapshot.get(member_id)
		if typeof(raw_hp) != TYPE_DICTIONARY:
			return false
		var hp: Dictionary = raw_hp
		var max_hp: int = _members[member_id]["max_hp"]
		if (
			typeof(hp.get("current_hp")) != TYPE_INT
			or hp.get("max_hp") != max_hp
			or int(hp["current_hp"]) < 0
			or int(hp["current_hp"]) > max_hp
		):
			return false
	for member_id: String in _members:
		_members[member_id]["current_hp"] = snapshot[member_id]["current_hp"]
	return true


func set_current_hp(member_id: String, current_hp: int) -> bool:
	if not has_member(member_id):
		return false
	var max_hp: int = _members[member_id]["max_hp"]
	if current_hp < 0 or current_hp > max_hp:
		return false
	_members[member_id]["current_hp"] = current_hp
	return true


func heal_member(member_id: String, amount: int) -> Dictionary:
	var result := {"success": false, "healed": 0, "current_hp": 0, "max_hp": 0}
	if amount <= 0 or not has_member(member_id):
		return result
	var member: Dictionary = _members[member_id]
	result["current_hp"] = member["current_hp"]
	result["max_hp"] = member["max_hp"]
	if member["current_hp"] <= 0:
		return result
	var before: int = member["current_hp"]
	member["current_hp"] = mini(member["max_hp"], before + amount)
	result["success"] = true
	result["healed"] = member["current_hp"] - before
	result["current_hp"] = member["current_hp"]
	return result
