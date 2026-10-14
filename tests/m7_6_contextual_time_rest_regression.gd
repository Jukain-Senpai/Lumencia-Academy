extends SceneTree

const TIMED_ENTRY := "res://scenes/exploration/m7_6_time_rest_prototype.tscn"
const NO_TIME_ENTRY := "res://scenes/exploration/m7_5_economy_prototype.tscn"
const MAP_SCENE := "res://scenes/exploration/exploration_map.tscn"
const DESIGN_PATH := "res://docs/M7_6_CONTEXTUAL_TIME_REST_DESIGN.md"
const BASE_SCRIPT := "res://scripts/exploration/exploration_prototype.gd"
const HERB_ID := "healing_herb"
const REST_ID := "prototype_camp_rest"
const WAIT_ID := "prototype_wait"
const SHOP_ID := "prototype_supply_shop"

var failures: Array[String] = []
var checks := 0
var game_state: Node
var state: Variant


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1152, 648)
	root.content_scale_size = Vector2i(1152, 648)
	game_state = root.get_node("GameState")
	state = game_state.exploration_state
	_test_definition_validation()
	await _test_no_time_backwards_compatibility()
	await _test_time_slots_without_night_healing()
	await _test_primary_action_cost_and_idempotence()
	await _test_multiday_clock_and_rest_order()
	await _test_rest_limits_and_scene_survival()
	await _test_vn_boundary()
	await _test_battle_defeat_restart_and_victory_boundary()
	await _test_resource_overflow_and_layout()
	await _free_current_scene()
	game_state.reset_state()
	_check(not state.has_active_context() and state.get_time_snapshot().is_empty(), "RESET: time survived GameState reset")
	_check(state.hub_action_uses.is_empty(), "RESET: Rest uses survived GameState reset")
	if failures.is_empty():
		print("M7.6 contextual time/rest regression suite passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	push_error("M7.6 contextual time/rest suite failed: %d failure(s), %d checks." % [failures.size(), checks])
	quit(1)


func _test_definition_validation() -> void:
	_check(FileAccess.file_exists(DESIGN_PATH), "DESIGN: M7.6 decision record is missing")
	_check(ResourceLoader.exists(TIMED_ENTRY), "SCENE: M7.6 timed entry is missing")
	game_state.reset_state()
	var base := _base_context()
	_check(state.define_context(base) and state.activate_context(base["id"]), "DATA: default context rejected")
	_check(state.get_time_snapshot()["mode"] == "NO_TIME", "DATA: context without time did not default to NO_TIME")
	for malformed: Variant in ["MULTI_DAY", {"mode": "UNKNOWN"}, {"mode": "TIME_SLOTS", "days": 7}, {"mode": 1}]:
		var invalid := _base_context()
		invalid["id"] = "invalid_time_%d" % checks
		invalid["time"] = malformed
		_check(not state.define_context(invalid), "DATA: malformed time was accepted: %s" % malformed)
	var invalid_cost := _base_context()
	invalid_cost["id"] = "invalid_cost"
	invalid_cost["nodes"][1]["primary_content"]["action_cost"] = -1
	_check(not state.define_context(invalid_cost), "DATA: negative action cost was accepted")
	invalid_cost["nodes"][1]["primary_content"]["action_cost"] = "1"
	_check(not state.define_context(invalid_cost), "DATA: noninteger action cost was accepted")
	invalid_cost["nodes"][1]["primary_content"]["action_cost"] = 0
	_check(state.define_context(invalid_cost), "DATA: explicit zero-cost primary content was rejected")
	var invalid_rest := _base_context()
	invalid_rest["id"] = "invalid_rest"
	invalid_rest["nodes"][1]["hub_actions"].append(_rest_action())
	invalid_rest["nodes"][1]["hub_actions"][1]["max_uses"] = 0
	_check(not state.define_context(invalid_rest), "DATA: zero-use Rest was accepted")
	var invalid_wait := _base_context()
	invalid_wait["id"] = "invalid_wait"
	invalid_wait["nodes"][1]["hub_actions"].append(_wait_action())
	_check(not state.define_context(invalid_wait), "DATA: Wait leaked into NO_TIME context")
	var timed := _base_context()
	timed["id"] = "defensive_timed"
	timed["time"] = {"mode": "TIME_SLOTS"}
	timed["nodes"][1]["hub_actions"].append(_rest_action())
	_check(state.define_context(timed) and state.activate_context(timed["id"]), "DATA: valid timed Rest context rejected")
	var copy: Dictionary = state.get_active_context_definition()
	copy["time"]["mode"] = "NO_TIME"
	copy["nodes"][1]["hub_actions"][1]["max_uses"] = 99
	_check(state.get_active_context_definition()["time"]["mode"] == "TIME_SLOTS", "DATA: authored time metadata leaked")
	_check(state.get_node_definition("riverside_camp")["hub_actions"][1]["max_uses"] == 2, "DATA: authored Rest metadata leaked")
	_check(state.get_hub_action_uses_remaining("riverside_camp", REST_ID) == 2, "DATA: fresh activation did not seed Rest uses")
	var time_copy: Dictionary = state.get_time_snapshot()
	time_copy["day"] = 99
	_check(state.get_time_snapshot()["day"] == 1, "DATA: time snapshot leaked mutable runtime state")
	for unused: int in 6:
		_check(state.spend_timed_action()["success"], "DATA: direct clock progression failed")
	_check(state.get_time_snapshot()["transition_pending"] and state.get_time_snapshot()["day"] == 1, "DATA: next day was exposed before transition finished")
	_check(state.get_time_snapshot()["daypart"] == "Night" and state.get_time_snapshot()["actions_spent"] == 2, "DATA: pending boundary lost Night 2/2")
	_check(not state.spend_timed_action()["success"], "DATA: seventh action bypassed pending day boundary")
	_check(state.finish_day_transition() and state.get_time_snapshot()["day"] == 2, "DATA: pending day did not finish")
	_check(state.activate_context(timed["id"]) and state.get_time_snapshot()["total_actions"] == 0, "DATA: fresh activation failed to reset clock")
	game_state.reset_state()


func _test_no_time_backwards_compatibility() -> void:
	var map: Variant = await _fresh_no_time_map()
	if map == null:
		return
	_check(not map.time_panel.visible and not map.camp_rest_button.visible and not map.wait_button.visible, "NO_TIME: time/Rest/Wait UI leaked into M7.5")
	_check(state.get_time_snapshot()["mode"] == "NO_TIME", "NO_TIME: M7.5 mode changed")
	_travel(map, "riverside_camp")
	await process_frame
	_check(_total() == 0, "NO_TIME: travel charged time")
	map.shop_action_button.emit_signal("pressed")
	map.shop_buy_button.emit_signal("pressed")
	await process_frame
	_check(_total() == 0 and game_state.get_money() == 8, "NO_TIME: Shop charged time or failed")
	map.inventory_button.emit_signal("pressed")
	map.healing_herb_button.emit_signal("pressed")
	map.inventory_target_list.get_node("InventoryTarget_party_1").emit_signal("pressed")
	_check(_total() == 0, "NO_TIME: Herb use charged time")
	_check(map.interact_with_current_node(), "NO_TIME: Riverside VN did not launch")
	await process_frame
	await process_frame
	var vn: Variant = current_scene
	_check(vn != null and vn.name == "VNPrototype", "NO_TIME: VN scene missing")
	if vn == null or vn.name != "VNPrototype":
		return
	_check(_total() == 0, "NO_TIME: VN launch charged time")
	_complete_riverside_vn(vn)
	await process_frame
	await process_frame
	map = _current_map()
	_check(_total() == 0 and state.is_node_completed("riverside_camp"), "NO_TIME: VN completion charged time or failed")
	_travel(map, "stone_crossing")
	await process_frame
	_check(map.interact_with_current_node(), "NO_TIME: Stone battle did not launch")
	await process_frame
	await process_frame
	var battle: Variant = current_scene
	_check(battle != null and battle.name == "BattleSandbox", "NO_TIME: Battle scene missing")
	if battle == null or battle.name != "BattleSandbox":
		return
	battle.automatic_enemy_turns_enabled = false
	_defeat_enemies(battle)
	_check(battle._check_battle_result(), "NO_TIME: battle victory failed")
	await process_frame
	await process_frame
	map = _current_map()
	_check(_total() == 0 and state.is_node_completed("stone_crossing"), "NO_TIME: battle completion charged time or failed")
	_travel(map, "ruins_approach")
	await process_frame
	map.primary_action_button.emit_signal("pressed")
	await process_frame
	_check(_total() == 0 and state.is_node_completed("ruins_approach"), "NO_TIME: resource completion charged time or failed")
	_check(state.has_leftover_reward("ruins_approach"), "NO_TIME: resource overflow did not preserve leftover")
	map.primary_action_button.emit_signal("pressed")
	_check(_total() == 0, "NO_TIME: leftover collection charged time")
	var no_time_rest: Variant = await _custom_map("NO_TIME", true, false, false)
	if no_time_rest == null:
		return
	_travel(no_time_rest, "riverside_camp")
	await process_frame
	game_state.party_runtime_state.set_current_hp("party_3", 0)
	var rest: Dictionary = game_state.use_current_camp_rest("riverside_camp", REST_ID)
	_check(rest["success"] and state.get_hub_action_uses_remaining("riverside_camp", REST_ID) == 1, "NO_TIME: Camp Rest did not consume one use")
	_check(game_state.party_runtime_state.get_member("party_3")["current_hp"] == 18, "NO_TIME: Camp Rest did not revive at 50%")
	_check(_total() == 0 and not no_time_rest.time_panel.visible, "NO_TIME: Camp Rest advanced/displayed clock")


func _test_time_slots_without_night_healing() -> void:
	var map: Variant = await _custom_map("TIME_SLOTS", false, true, false)
	if map == null:
		return
	_check(map.time_panel.visible and map.time_label.text == "Day 1 — Morning", "TIME_SLOTS: starting clock is wrong")
	_travel(map, "riverside_camp")
	await process_frame
	game_state.party_runtime_state.set_current_hp("party_1", 11)
	game_state.party_runtime_state.set_current_hp("party_3", 0)
	for action_number: int in 6:
		var result: Dictionary = game_state.wait_at_current_hub("riverside_camp", WAIT_ID)
		_check(result["success"], "TIME_SLOTS: Wait %d failed" % (action_number + 1))
		var snapshot: Dictionary = state.get_time_snapshot()
		if action_number == 0:
			_check(snapshot["day"] == 1 and snapshot["daypart"] == "Morning" and snapshot["actions_spent"] == 1, "TIME_SLOTS: action 1 progression wrong")
		if action_number == 1:
			_check(snapshot["daypart"] == "Afternoon" and snapshot["actions_spent"] == 0, "TIME_SLOTS: action 2 progression wrong")
		if action_number == 3:
			_check(snapshot["daypart"] == "Night" and snapshot["actions_spent"] == 0, "TIME_SLOTS: action 4 progression wrong")
	_check(state.get_time_snapshot()["day"] == 2 and state.get_time_snapshot()["actions_spent"] == 0, "TIME_SLOTS: sixth action did not start Day 2")
	_check(game_state.party_runtime_state.get_member("party_1")["current_hp"] == 11, "TIME_SLOTS: day transition healed living member")
	_check(game_state.party_runtime_state.get_member("party_3")["current_hp"] == 0, "TIME_SLOTS: day transition revived defeated member")
	_check(game_state.wait_at_current_hub("riverside_camp", WAIT_ID)["success"], "TIME_SLOTS: seventh action failed")
	_check(state.get_time_snapshot()["day"] == 2 and state.get_time_snapshot()["actions_spent"] == 1, "TIME_SLOTS: seventh action advanced day twice")
	_check(map.refresh_map() and map.time_label.text == "Day 2 — Morning", "TIME_SLOTS: map time display did not refresh")
	_check(map.time_actions_label.text == "Actions: 1/2", "TIME_SLOTS: map action display is wrong")
	var before: Dictionary = state.get_time_snapshot()
	_check(not game_state.wait_at_current_hub("old_trail", WAIT_ID)["success"], "TIME_SLOTS: stale Wait request succeeded")
	_check(state.get_time_snapshot() == before, "TIME_SLOTS: rejected Wait advanced clock")


func _test_primary_action_cost_and_idempotence() -> void:
	var map: Variant = await _custom_map("TIME_SLOTS", false, true, true)
	if map == null:
		return
	_travel(map, "riverside_camp")
	await process_frame
	_check(game_state.prepare_exploration_content("vn_event", "m7_3_riverside_event"), "COST: zero-cost handoff did not prepare")
	_check(game_state.resolve_pending_exploration_content("vn_event", "m7_3_riverside_event"), "COST: zero-cost completion failed")
	_check(state.is_node_completed("riverside_camp") and _total() == 0, "COST: zero-cost completion charged time")
	_check(game_state.resolve_pending_exploration_content("vn_event", "m7_3_riverside_event"), "COST: zero-cost duplicate resolution failed")
	_check(_total() == 0, "COST: zero-cost duplicate charged time")
	game_state.clear_pending_exploration_content()
	map = await _custom_map("TIME_SLOTS", false, true, false)
	if map == null:
		return
	_travel(map, "riverside_camp")
	await process_frame
	_check(not game_state.resolve_pending_exploration_content("vn_event", "m7_3_riverside_event"), "COST: missing handoff resolved")
	_check(_total() == 0 and not state.is_node_completed("riverside_camp"), "COST: invalid resolution changed time/completion")
	_check(game_state.prepare_exploration_content("vn_event", "m7_3_riverside_event"), "COST: normal handoff did not prepare")
	_check(game_state.resolve_pending_exploration_content("vn_event", "m7_3_riverside_event"), "COST: normal completion failed")
	_check(_total() == 1 and state.is_node_completed("riverside_camp"), "COST: normal completion did not charge once")
	_check(game_state.resolve_pending_exploration_content("vn_event", "m7_3_riverside_event"), "COST: duplicate resolution was not idempotent")
	_check(_total() == 1, "COST: duplicate resolution charged twice")
	game_state.clear_pending_exploration_content()


func _test_multiday_clock_and_rest_order() -> void:
	var map: Variant = await _fresh_timed_map()
	if map == null:
		return
	_check(state.get_time_snapshot()["mode"] == "MULTI_DAY", "MULTI_DAY: timed entry has wrong mode")
	_check(map.time_panel.visible and map.time_actions_label.text == "Actions: 0/2", "MULTI_DAY: starting clock UI is wrong")
	_check(game_state.get_money() == 12 and game_state.inventory_state.get_quantity(HERB_ID) == 9, "MULTI_DAY: M7.5 fixture balances changed")
	_travel(map, "riverside_camp")
	await process_frame
	_check(_total() == 0 and map.camp_rest_button.visible and map.wait_button.visible and map.shop_action_button.visible and map.primary_action_button.visible, "MULTI_DAY: travel charged time or independent actions are missing")
	_check(map.camp_rest_button.text.contains("2 left"), "MULTI_DAY: Rest uses are not visible")
	map.wait_button.grab_focus()
	_check(map.wait_button.has_focus(), "FOCUS: Wait cannot receive keyboard focus")
	for action_number: int in 5:
		map.wait_button.emit_signal("pressed")
		map.wait_button.emit_signal("pressed")
		_check(_total() == action_number + 1, "MULTI_DAY: rapid Wait activated twice")
		await process_frame
	_check(state.get_time_snapshot()["daypart"] == "Night" and state.get_time_snapshot()["actions_spent"] == 1, "MULTI_DAY: five actions did not reach Night 1/2")
	game_state.party_runtime_state.set_current_hp("party_1", 1)
	game_state.party_runtime_state.set_current_hp("party_3", 0)
	map.camp_rest_button.emit_signal("pressed")
	map.camp_rest_button.emit_signal("pressed")
	_check(_total() == 6, "REST BOUNDARY: rapid Rest charged twice")
	_check(state.get_hub_action_uses_remaining("riverside_camp", REST_ID) == 1, "REST BOUNDARY: rapid Rest used two charges")
	_check(game_state.party_runtime_state.get_member("party_1")["current_hp"] == 32, "REST BOUNDARY: 50% then 20% living recovery order is wrong")
	_check(game_state.party_runtime_state.get_member("party_3")["current_hp"] == 26, "REST BOUNDARY: 50% revival then 20% recovery order is wrong")
	_check(state.get_time_snapshot()["day"] == 2 and state.get_time_snapshot()["daypart"] == "Morning" and state.get_time_snapshot()["actions_spent"] == 0, "REST BOUNDARY: sixth action did not start Day 2 Morning")
	_check(state.get_time_snapshot()["feedback"].contains("Night Rest"), "REST BOUNDARY: Night Rest status is missing")
	await process_frame
	_check(map.time_label.text == "Day 2 — Morning" and map.time_feedback_label.visible, "REST BOUNDARY: time panel did not show next-day recovery")
	_check(map.camp_rest_button.text.contains("1 left") and map.shop_action_button.visible, "REST BOUNDARY: Rest count or Shop changed")
	map.wait_button.emit_signal("pressed")
	await process_frame
	_check(_total() == 7 and state.get_time_snapshot()["day"] == 2, "MULTI_DAY: seventh action repeated Night Rest")
	_check(game_state.party_runtime_state.get_member("party_1")["current_hp"] == 32, "MULTI_DAY: seventh action healed again")


func _test_rest_limits_and_scene_survival() -> void:
	var map: Variant = await _fresh_timed_map()
	if map == null:
		return
	_travel(map, "riverside_camp")
	await process_frame
	game_state.party_runtime_state.set_current_hp("party_1", 20)
	game_state.party_runtime_state.set_current_hp("party_3", 0)
	map.camp_rest_button.grab_focus()
	_check(map.camp_rest_button.has_focus(), "FOCUS: Camp Rest cannot receive keyboard focus")
	map.camp_rest_button.emit_signal("pressed")
	await process_frame
	_check(game_state.party_runtime_state.get_member("party_1")["current_hp"] == 42, "REST: living 50% recovery is wrong")
	_check(game_state.party_runtime_state.get_member("party_3")["current_hp"] == 18, "REST: defeated member was not revived to 50%")
	_check(_total() == 1 and state.get_hub_action_uses_remaining("riverside_camp", REST_ID) == 1, "REST: first use/time result wrong")
	var before_failed: Dictionary = game_state.party_runtime_state.get_hp_snapshot()
	_check(not game_state.use_current_camp_rest("old_trail", REST_ID)["success"], "REST: stale location was accepted")
	_check(not game_state.use_current_camp_rest("riverside_camp", "missing")["success"], "REST: unknown action was accepted")
	_check(game_state.party_runtime_state.get_hp_snapshot() == before_failed and _total() == 1, "REST: invalid request changed HP/time")
	_travel(map, "old_trail")
	await process_frame
	_travel(map, "riverside_camp")
	await process_frame
	_check(state.get_hub_action_uses_remaining("riverside_camp", REST_ID) == 1, "REST: travel reset uses")
	map = await _load_scene(MAP_SCENE)
	_check(map != null and map.camp_rest_button.text.contains("1 left"), "REST: map reload reset uses")
	_check(map.interact_with_current_node(), "REST: VN transition did not launch")
	await process_frame
	await process_frame
	var vn: Variant = current_scene
	_check(vn != null and vn.name == "VNPrototype", "REST: VN scene missing")
	if vn == null or vn.name != "VNPrototype":
		return
	_complete_riverside_vn(vn)
	await process_frame
	await process_frame
	map = _current_map()
	_check(state.get_hub_action_uses_remaining("riverside_camp", REST_ID) == 1 and _total() == 2, "REST: VN return reset Rest uses/time")
	_travel(map, "stone_crossing")
	await process_frame
	_check(map.interact_with_current_node(), "REST: Battle transition did not launch")
	await process_frame
	await process_frame
	var battle: Variant = current_scene
	_check(battle != null and battle.name == "BattleSandbox", "REST: Battle scene missing")
	if battle == null or battle.name != "BattleSandbox":
		return
	battle.automatic_enemy_turns_enabled = false
	_defeat_enemies(battle)
	_check(battle._check_battle_result(), "REST: Battle Victory failed")
	await process_frame
	await process_frame
	map = _current_map()
	_check(state.get_hub_action_uses_remaining("riverside_camp", REST_ID) == 1 and _total() == 3, "REST: Battle return reset Rest uses/time")
	_travel(map, "riverside_camp")
	await process_frame
	map.camp_rest_button.emit_signal("pressed")
	await process_frame
	_check(state.get_hub_action_uses_remaining("riverside_camp", REST_ID) == 0 and _total() == 4, "REST: second use failed")
	_check(map.camp_rest_button.disabled and map.shop_action_button.visible, "REST: exhausted Rest did not disable or hid Shop")
	var hp_at_zero: Dictionary = game_state.party_runtime_state.get_hp_snapshot()
	var money_at_zero: int = game_state.get_money()
	var herbs_at_zero: int = game_state.inventory_state.get_quantity(HERB_ID)
	map.camp_rest_button.emit_signal("pressed")
	_check(not game_state.use_current_camp_rest("riverside_camp", REST_ID)["success"], "REST: third use was accepted")
	_check(game_state.party_runtime_state.get_hp_snapshot() == hp_at_zero and _total() == 4, "REST: exhausted use changed HP/time")
	_check(game_state.get_money() == money_at_zero and game_state.inventory_state.get_quantity(HERB_ID) == herbs_at_zero, "REST: failed use changed economy")
	_check(state.is_node_roadblocked("riverside_camp") and state.is_node_completed("riverside_camp") and state.is_node_revealed("deep_grove"), "REST: VN reveal/roadblock facts changed")
	map.shop_action_button.emit_signal("pressed")
	_check(map.shop_panel.visible, "REST: exhausted Rest blocked Shop")
	map.shop_back_button.emit_signal("pressed")
	for unused: int in 2:
		_check(game_state.wait_at_current_hub("riverside_camp", WAIT_ID)["success"], "REST: day-advance Wait failed")
	_check(state.get_time_snapshot()["day"] == 2 and state.get_hub_action_uses_remaining("riverside_camp", REST_ID) == 0, "REST: day transition replenished charges")
	_check(map.refresh_map() and map.camp_rest_button.disabled, "REST: depleted UI did not persist across day")
	_check(state.activate_context(state.active_context_id), "REST: fresh context activation failed")
	_check(state.get_hub_action_uses_remaining("riverside_camp", REST_ID) == 2 and _total() == 0, "REST: fresh context activation did not reset uses/clock")


func _test_vn_boundary() -> void:
	var map: Variant = await _fresh_timed_map()
	if map == null:
		return
	_travel(map, "riverside_camp")
	await process_frame
	for unused: int in 5:
		game_state.wait_at_current_hub("riverside_camp", WAIT_ID)
	_check(_total() == 5, "VN BOUNDARY: setup actions failed")
	game_state.party_runtime_state.set_current_hp("party_1", 20)
	_check(map.interact_with_current_node(), "VN BOUNDARY: Riverside VN did not launch")
	await process_frame
	await process_frame
	var vn: Variant = current_scene
	_check(vn != null and vn.name == "VNPrototype", "VN BOUNDARY: VN scene missing")
	if vn == null or vn.name != "VNPrototype":
		return
	_check(_total() == 5, "VN BOUNDARY: launching dialogue charged time")
	_complete_riverside_vn(vn)
	_check(_total() == 6 and state.get_time_snapshot()["day"] == 2, "VN BOUNDARY: terminal return did not charge sixth action")
	_check(game_state.party_runtime_state.get_member("party_1")["current_hp"] == 29, "VN BOUNDARY: Night Rest healing is wrong")
	await process_frame
	await process_frame
	map = _current_map()
	_check(map != null and map.time_label.text == "Day 2 — Morning", "VN BOUNDARY: map did not show Day 2")
	_check(state.is_node_completed("riverside_camp") and state.is_node_revealed("deep_grove"), "VN BOUNDARY: primary completion/reveal failed")
	_check(state.is_node_roadblocked("riverside_camp") and state.is_node_reusable("riverside_camp"), "VN BOUNDARY: roadblock/reusable changed")
	_check(map.shop_action_button.visible and map.camp_rest_button.visible and not map.primary_action_button.visible, "VN BOUNDARY: independent hub actions or primary replay wrong")
	_travel(map, "old_trail")
	await process_frame
	_travel(map, "riverside_camp")
	await process_frame
	_check(_total() == 6 and not map.interact_with_current_node(), "VN BOUNDARY: revisit replayed or charged completed VN")
	_check(state.get_hub_action_uses_remaining("riverside_camp", REST_ID) == 2, "VN BOUNDARY: VN/day transition consumed Rest uses")


func _test_battle_defeat_restart_and_victory_boundary() -> void:
	var map: Variant = await _fresh_timed_map()
	if map == null:
		return
	_travel(map, "riverside_camp")
	await process_frame
	for unused: int in 5:
		game_state.wait_at_current_hub("riverside_camp", WAIT_ID)
	game_state.party_runtime_state.set_current_hp("party_1", 30)
	game_state.party_runtime_state.set_current_hp("party_3", 10)
	_travel(map, "stone_crossing")
	await process_frame
	_check(_total() == 5 and not state.is_node_completed("stone_crossing"), "BATTLE BOUNDARY: travel completed or charged node")
	_check(map.interact_with_current_node(), "BATTLE BOUNDARY: Stone battle did not launch")
	await process_frame
	await process_frame
	var battle: Variant = current_scene
	_check(battle != null and battle.name == "BattleSandbox", "BATTLE BOUNDARY: Battle scene missing")
	if battle == null or battle.name != "BattleSandbox":
		return
	battle.automatic_enemy_turns_enabled = false
	_check(battle.hiruko_unit.current_hp == 30 and _total() == 5, "BATTLE BOUNDARY: runtime HP hydration/time on entry wrong")
	for unit: Variant in battle.party_units:
		unit.current_hp = 0
		unit.defeated = true
	_check(battle._check_battle_result(), "BATTLE BOUNDARY: Defeat was not recognized")
	_check(_total() == 5 and game_state.party_runtime_state.get_member("party_1")["current_hp"] == 30, "BATTLE BOUNDARY: Defeat charged time or overwrote party HP")
	battle.restart_battle()
	_check(battle.hiruko_unit.current_hp == 30 and _total() == 5, "BATTLE BOUNDARY: Restart lost encounter-entry HP or charged time")
	battle.hiruko_unit.current_hp = 1
	battle.party_units[2].current_hp = 0
	battle.party_units[2].defeated = true
	_defeat_enemies(battle)
	_check(battle._check_battle_result(), "BATTLE BOUNDARY: later Victory was not recognized")
	_check(battle.party_runtime_synced and _total() == 6, "BATTLE BOUNDARY: Victory sync/time did not commit")
	_check(game_state.party_runtime_state.get_member("party_1")["current_hp"] == 10, "BATTLE BOUNDARY: Battle HP was not synced before +20% Night Rest")
	_check(game_state.party_runtime_state.get_member("party_3")["current_hp"] == 8, "BATTLE BOUNDARY: Night Rest did not revive defeated battle member")
	_check(state.get_time_snapshot()["day"] == 2 and state.is_node_completed("stone_crossing"), "BATTLE BOUNDARY: next day or primary completion failed")
	await process_frame
	await process_frame
	map = _current_map()
	_check(map != null and map.time_label.text == "Day 2 — Morning", "BATTLE BOUNDARY: map return lost clock")
	_check(game_state.party_runtime_state.get_member("party_1")["current_hp"] == 10, "BATTLE BOUNDARY: later Battle HP sync overwrote Night Rest")
	_check(not map.interact_with_current_node() and _total() == 6, "BATTLE BOUNDARY: completed battle replayed/charged")


func _test_resource_overflow_and_layout() -> void:
	var map: Variant = await _fresh_timed_map()
	if map == null:
		return
	_travel(map, "riverside_camp")
	await process_frame
	map.shop_action_button.emit_signal("pressed")
	map.shop_buy_button.emit_signal("pressed")
	await process_frame
	_check(_total() == 0 and game_state.get_money() == 8 and game_state.inventory_state.get_quantity(HERB_ID) == 10, "RESOURCE: Shop purchase charged time or failed")
	_check(not game_state.buy_from_current_shop("riverside_camp", SHOP_ID, HERB_ID)["success"] and _total() == 0, "RESOURCE: failed capped Shop purchase charged time")
	_travel(map, "stone_crossing")
	await process_frame
	_travel(map, "ruins_approach")
	await process_frame
	_check(_total() == 0, "RESOURCE: travel charged time")
	map.primary_action_button.emit_signal("pressed")
	await process_frame
	_check(_total() == 1 and state.is_node_completed("ruins_approach"), "RESOURCE: successful primary completion did not charge exactly one")
	_check(state.get_leftover_reward("ruins_approach") == {"item_id": HERB_ID, "quantity": 2}, "RESOURCE: overflow leftover changed")
	_check(map.get_marker_button("ruins_approach").get_node("LeftoverBadge").visible, "RESOURCE: M7.4 leftover badge disappeared")
	for target_size: Vector2i in [Vector2i(1152, 648), Vector2i(1440, 810)]:
		root.size = target_size
		await process_frame
		await process_frame
		_check(map.refresh_map(), "LAYOUT %s: refresh failed" % target_size)
		var viewport := Rect2(Vector2.ZERO, Vector2(target_size))
		var time_rect: Rect2 = map.time_panel.get_global_rect()
		var action_rect: Rect2 = map.primary_action_panel.get_global_rect()
		var old_trail_rect: Rect2 = map.get_marker_button("old_trail").get_global_rect()
		var leftover_rect: Rect2 = map.get_marker_button("ruins_approach").get_node("LeftoverBadge").get_global_rect()
		_check(viewport.encloses(time_rect) and viewport.encloses(action_rect), "LAYOUT %s: clock/actions are clipped" % target_size)
		_check(not time_rect.intersects(map.get_marker_button("riverside_camp").get_global_rect()), "LAYOUT %s: clock covers Riverside marker" % target_size)
		_check(not action_rect.intersects(old_trail_rect), "LAYOUT %s: action panel covers Old Trail" % target_size)
		_check(not leftover_rect.intersects(action_rect) and viewport.encloses(leftover_rect), "LAYOUT %s: leftover badge is obstructed/clipped" % target_size)
		_check(not leftover_rect.intersects(time_rect) and map.get_marker_button("ruins_approach").visible, "LAYOUT %s: clock covers leftover or marker is hidden" % target_size)
		_check(map.time_panel.visible and map.time_actions_label.text == "Actions: 1/2", "LAYOUT %s: clock is hidden or stale" % target_size)
	root.size = Vector2i(1152, 648)
	await process_frame
	map.primary_action_button.emit_signal("pressed")
	_check(_total() == 1 and state.get_leftover_reward("ruins_approach")["quantity"] == 2, "RESOURCE: full-inventory leftover retry charged time or lost reward")
	game_state.inventory_state.consume_item(HERB_ID, 1)
	map.primary_action_button.emit_signal("pressed")
	_check(_total() == 1 and state.get_leftover_reward("ruins_approach")["quantity"] == 1, "RESOURCE: partial leftover collection charged time")
	_check(game_state.get_money() == 8, "RESOURCE: resource/leftover changed money")


func _base_context() -> Dictionary:
	var script: Script = load(BASE_SCRIPT)
	return script.get_script_constant_map()["PROTOTYPE_CONTEXT"].duplicate(true)


func _rest_action() -> Dictionary:
	return {"id": REST_ID, "type": "rest", "display_name": "Camp Rest", "max_uses": 2}


func _wait_action() -> Dictionary:
	return {"id": WAIT_ID, "type": "wait", "display_name": "Wait / Advance Time"}


func _custom_map(mode: String, include_rest: bool, include_wait: bool, zero_cost: bool) -> Variant:
	game_state.reset_state()
	var context := _base_context()
	context["id"] = "m7_6_custom_%s" % mode.to_lower()
	context["time"] = {"mode": mode}
	if include_rest:
		context["nodes"][1]["hub_actions"].append(_rest_action())
	if include_wait:
		context["nodes"][1]["hub_actions"].append(_wait_action())
	if zero_cost:
		context["nodes"][1]["primary_content"]["action_cost"] = 0
	_check(state.define_context(context) and state.activate_context(context["id"]), "CUSTOM: %s context failed" % mode)
	return await _load_scene(MAP_SCENE)


func _fresh_timed_map() -> Variant:
	var entry: Variant = await _load_scene(TIMED_ENTRY)
	if entry == null:
		return null
	var map: Variant = entry.find_child("ExplorationMap", true, false)
	_check(map != null, "MAP: timed entry lacks reusable ExplorationMap")
	return map


func _fresh_no_time_map() -> Variant:
	var entry: Variant = await _load_scene(NO_TIME_ENTRY)
	if entry == null:
		return null
	var map: Variant = entry.find_child("ExplorationMap", true, false)
	_check(map != null, "MAP: M7.5 entry lacks ExplorationMap")
	return map


func _current_map() -> Variant:
	if current_scene == null:
		return null
	if current_scene.has_method("get_marker_button"):
		return current_scene
	return current_scene.find_child("ExplorationMap", true, false)


func _travel(map: Variant, node_id: String) -> void:
	var marker: Button = map.get_marker_button(node_id)
	_check(marker != null, "TRAVEL: marker %s is missing" % node_id)
	if marker != null:
		marker.emit_signal("pressed")


func _complete_riverside_vn(vn: Variant) -> void:
	vn._advance_dialogue()
	vn._advance_dialogue()
	vn._advance_dialogue()


func _defeat_enemies(battle: Variant) -> void:
	for unit: Variant in battle.enemy_units:
		unit.current_hp = 0
		unit.defeated = true


func _total() -> int:
	return state.get_time_snapshot().get("total_actions", -1)


func _load_scene(path: String) -> Variant:
	await _free_current_scene()
	var packed: PackedScene = load(path)
	_check(packed != null, "SCENE: could not load %s" % path)
	if packed == null:
		return null
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	return scene


func _free_current_scene() -> void:
	if current_scene == null:
		return
	var old_scene: Node = current_scene
	current_scene = null
	old_scene.queue_free()
	await process_frame


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
