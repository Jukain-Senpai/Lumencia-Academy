extends SceneTree

const ENTRY_SCENE_PATH := "res://scenes/exploration/m7_5_economy_prototype.tscn"
const MAP_SCENE_PATH := "res://scenes/exploration/exploration_map.tscn"
const DESIGN_PATH := "res://docs/M7_5_REUSABLE_HUB_ECONOMY_DESIGN.md"
const HERB_ID := "healing_herb"
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
	_test_authored_shape_and_atomic_api()
	await _test_invalid_shop_presentation()
	await _test_shop_ui_and_economy_loop()
	await _test_vn_and_battle_return()
	await _test_resource_overflow_compatibility()
	await _free_current_scene()
	game_state.reset_state()
	_check(game_state.get_money() == 0, "RESET: money survived GameState reset")
	_check(game_state.inventory_state.get_quantity(HERB_ID) == 0, "RESET: Inventory survived GameState reset")
	_check(not state.has_active_context(), "RESET: Exploration context survived GameState reset")
	if failures.is_empty():
		print("M7.5 reusable hub economy regression suite passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	push_error("M7.5 reusable hub economy suite failed: %d failure(s), %d checks." % [failures.size(), checks])
	quit(1)


func _test_authored_shape_and_atomic_api() -> void:
	_check(FileAccess.file_exists(DESIGN_PATH), "DESIGN: M7.5 decision record is missing")
	_check(ResourceLoader.exists(ENTRY_SCENE_PATH), "SCENE: M7.5 entry is missing")
	game_state.reset_state()
	var prototype_script: Script = load("res://scripts/exploration/exploration_prototype.gd")
	var context: Dictionary = prototype_script.get_script_constant_map()["PROTOTYPE_CONTEXT"].duplicate(true)
	var camp: Dictionary = context["nodes"][1]
	_check(camp["id"] == "riverside_camp" and camp["reusable"], "DATA: Shop owner is not reusable Riverside Camp")
	_check(camp["hub_actions"][0]["catalog"] == [{"item_id": HERB_ID, "price": 4}], "DATA: prototype offer changed")
	_check(camp["primary_content"]["type"] == "vn_event" and camp["initial_roadblock"], "DATA: Shop replaced VN or roadblock")
	_check(camp["reveal_on_complete"] == ["deep_grove"], "DATA: Shop changed authored reveal")
	_check(state.define_context(context), "DATA: prototype context rejected")
	_check(state.activate_context(context["id"]), "DATA: prototype context did not activate")
	var copy: Dictionary = state.get_node_definition("riverside_camp")
	copy["hub_actions"][0]["catalog"][0]["price"] = 99
	_check(state.get_node_definition("riverside_camp")["hub_actions"][0]["catalog"][0]["price"] == 4, "DATA: nested Shop offer leaked mutable metadata")
	_check(game_state.gain_money(12), "MONEY: initial gain failed")
	_check(not game_state.gain_money(0) and not game_state.spend_money(0), "MONEY: zero transaction was accepted")
	_check(not game_state.spend_money(13) and game_state.get_money() == 12, "MONEY: overspend changed balance")
	_check(game_state.gain_money(game_state.MAX_MONEY - 12), "MONEY: maximum balance setup failed")
	_check(not game_state.gain_money(1) and game_state.get_money() == game_state.MAX_MONEY, "MONEY: overflow was accepted")
	_check(game_state.spend_money(game_state.MAX_MONEY - 12) and game_state.get_money() == 12, "MONEY: maximum-balance cleanup failed")
	game_state.inventory_state.gain_item(HERB_ID, 9)
	var original_money: int = game_state.get_money()
	var original_herbs: int = game_state.inventory_state.get_quantity(HERB_ID)
	_check(not game_state.buy_from_current_shop("riverside_camp", SHOP_ID, HERB_ID)["success"], "ATOMIC: remote Shop purchase succeeded")
	_check(state.move_to_node("riverside_camp"), "ATOMIC: travel to Riverside failed")
	_check(not state.is_node_completed("riverside_camp") and not state.is_node_revealed("deep_grove"), "ATOMIC: travel consumed primary content")
	for invalid: Dictionary in [
		{"node": "old_trail", "shop": SHOP_ID, "item": HERB_ID},
		{"node": "riverside_camp", "shop": "missing", "item": HERB_ID},
		{"node": "riverside_camp", "shop": SHOP_ID, "item": "missing"},
	]:
		_check(not game_state.buy_from_current_shop(invalid["node"], invalid["shop"], invalid["item"])["success"], "ATOMIC: invalid purchase succeeded: %s" % invalid)
	_check(game_state.get_money() == original_money and game_state.inventory_state.get_quantity(HERB_ID) == original_herbs, "ATOMIC: rejected purchase mutated balances")
	var invalid_price: Dictionary = context.duplicate(true)
	invalid_price["id"] = "m7_5_invalid_price"
	invalid_price["nodes"][1]["hub_actions"][0]["catalog"][0]["price"] = 0
	_check(not state.define_context(invalid_price), "DATA: zero Shop price was accepted")
	var invalid_owner: Dictionary = context.duplicate(true)
	invalid_owner["id"] = "m7_5_invalid_owner"
	invalid_owner["nodes"][1]["reusable"] = false
	_check(not state.define_context(invalid_owner), "DATA: nonreusable Shop owner was accepted")
	var invalid_duplicate: Dictionary = context.duplicate(true)
	invalid_duplicate["id"] = "m7_5_duplicate_offer"
	invalid_duplicate["nodes"][1]["hub_actions"][0]["catalog"].append({"item_id": HERB_ID, "price": 4})
	_check(not state.define_context(invalid_duplicate), "DATA: duplicate Shop offer was accepted")
	var invalid_item: Dictionary = context.duplicate(true)
	invalid_item["id"] = "m7_5_unknown_item"
	invalid_item["nodes"][1]["hub_actions"][0]["catalog"][0]["item_id"] = "missing"
	_check(state.define_context(invalid_item), "DATA: structurally valid unknown-item fixture was rejected")
	_check(state.activate_context(invalid_item["id"]), "DATA: unknown-item fixture did not activate")
	_check(state.move_to_node("riverside_camp"), "DATA: unknown-item fixture did not reach Shop")
	_check(not game_state.buy_from_current_shop("riverside_camp", SHOP_ID, "missing")["success"], "ATOMIC: unknown item was purchased")
	_check(game_state.get_money() == original_money and game_state.inventory_state.get_quantity(HERB_ID) == original_herbs, "ATOMIC: unknown item changed balances")
	var source := FileAccess.open("res://scripts/systems/game_state.gd", FileAccess.READ)
	var text: String = source.get_as_text()
	var payload: String = text.substr(text.find("var save_data := {"), text.find("var file := FileAccess.open", text.find("var save_data := {")) - text.find("var save_data := {"))
	_check(not payload.contains("money") and not payload.contains("inventory"), "SAVE: M7.5 expanded M2 save payload")
	game_state.reset_state()


func _test_invalid_shop_presentation() -> void:
	game_state.reset_state()
	var prototype_script: Script = load("res://scripts/exploration/exploration_prototype.gd")
	var context: Dictionary = prototype_script.get_script_constant_map()["PROTOTYPE_CONTEXT"].duplicate(true)
	context["id"] = "m7_5_invalid_presentation"
	context["nodes"][1]["hub_actions"][0]["catalog"][0]["item_id"] = "missing"
	_check(state.define_context(context) and state.activate_context(context["id"]), "DIAGNOSTIC: unknown-item context setup failed")
	var map: Variant = await _load_scene(MAP_SCENE_PATH)
	if map == null:
		return
	_check(map.diagnostic_panel.visible, "DIAGNOSTIC: unknown Shop item did not show configuration error")
	_check(not map.shop_panel.visible and not map.shop_action_button.visible, "DIAGNOSTIC: broken Shop remains interactable")
	_check(not map.marker_layer.visible, "DIAGNOSTIC: broken map remains travelable")
	_check(game_state.get_money() == 0 and game_state.inventory_state.get_quantity(HERB_ID) == 0, "DIAGNOSTIC: rendering invalid Shop mutated balances")


func _test_shop_ui_and_economy_loop() -> void:
	var map: Variant = await _fresh_map()
	if map == null:
		return
	_check(game_state.get_money() == 12 and game_state.inventory_state.get_quantity(HERB_ID) == 9, "BOOT: prototype start values are wrong")
	_check(map.money_label.text == "Money: 12" and map.inventory_button.text.contains("×9"), "BOOT: starting balances are not visible")
	_check(not map.shop_action_button.visible and not map.shop_panel.visible, "BOOT: remote Shop is visible")
	_press_marker(map, "riverside_camp")
	await process_frame
	_check(map.shop_action_button.visible and map.primary_action_button.visible, "HUB: Shop and VN Interact are not independent")
	_check(not state.is_node_completed("riverside_camp") and not state.is_node_revealed("deep_grove"), "HUB: travel consumed Riverside content")
	var camp_marker_id: int = map.get_marker_button("riverside_camp").get_instance_id()
	map.shop_action_button.emit_signal("pressed")
	_check(map.shop_panel.visible and not map.inventory_panel.visible, "SHOP: panel did not open exclusively")
	_check(map.shop_balance_label.text == "Money: 12" and map.shop_offer_label.text.contains("Owned 9/10"), "SHOP: balance or quantity is not visible")
	_check(map.shop_offer_label.text.contains("4 money"), "SHOP: authored price is not visible")
	_check(map.shop_buy_button.has_focus(), "FOCUS: Buy did not receive keyboard focus")
	map.shop_buy_button.emit_signal("pressed")
	map.shop_buy_button.emit_signal("pressed")
	_check(game_state.get_money() == 8 and game_state.inventory_state.get_quantity(HERB_ID) == 10, "SHOP: rapid activation did not buy exactly one Herb")
	await process_frame
	_check(map.money_label.text == "Money: 8", "SHOP: header money did not refresh")
	_check(map.shop_buy_button.disabled and map.shop_status_label.text.contains("Purchased"), "SHOP: cap or success feedback is wrong")
	_check(map.get_marker_button("riverside_camp").get_instance_id() == camp_marker_id, "SHOP: purchase rebuilt stable marker")
	var at_cap: Dictionary = game_state.buy_from_current_shop("riverside_camp", SHOP_ID, HERB_ID)
	_check(not at_cap["success"] and at_cap["message"] == "Inventory full.", "SHOP: cap rejection is wrong")
	_check(game_state.get_money() == 8 and game_state.inventory_state.get_quantity(HERB_ID) == 10, "SHOP: cap failure changed balances")
	_check(state.leftover_rewards.is_empty(), "SHOP: failed purchase created leftover reward")
	map.inventory_button.emit_signal("pressed")
	_check(map.inventory_panel.visible and not map.shop_panel.visible, "PANELS: Items did not close Shop")
	map.healing_herb_button.emit_signal("pressed")
	var hiruko: Button = map.inventory_target_list.get_node("InventoryTarget_party_1")
	hiruko.emit_signal("pressed")
	_check(game_state.inventory_state.get_quantity(HERB_ID) == 9, "ITEM: Herb use did not free capacity")
	_check(game_state.party_runtime_state.get_member("party_1")["current_hp"] > 20, "ITEM: Herb use did not heal runtime HP")
	map.shop_action_button.emit_signal("pressed")
	_check(map.shop_panel.visible and not map.inventory_panel.visible, "PANELS: Shop did not close Items")
	map.shop_buy_button.emit_signal("pressed")
	await process_frame
	_check(game_state.get_money() == 4 and game_state.inventory_state.get_quantity(HERB_ID) == 10, "SHOP: rebuy after consumption failed")
	_press_marker(map, "old_trail")
	await process_frame
	_check(not map.shop_panel.visible and not map.shop_action_button.visible, "TRAVEL: Shop stayed open away from Riverside")
	_check(game_state.get_money() == 4 and game_state.inventory_state.get_quantity(HERB_ID) == 10, "TRAVEL: balances reset")
	_press_marker(map, "riverside_camp")
	await process_frame
	_check(map.shop_action_button.visible and not state.is_node_completed("riverside_camp"), "REVISIT: Shop disappeared or VN completed")
	map.shop_action_button.emit_signal("pressed")
	_check(map.shop_panel.visible and map.shop_balance_label.text == "Money: 4", "REVISIT: Shop did not reopen with retained balance")
	map.shop_back_button.emit_signal("pressed")
	_check(not map.shop_panel.visible and map.shop_action_button.has_focus(), "FOCUS: Back did not restore Shop focus")
	map.inventory_button.emit_signal("pressed")
	map.healing_herb_button.emit_signal("pressed")
	map.inventory_target_list.get_node("InventoryTarget_party_1").emit_signal("pressed")
	_check(game_state.inventory_state.get_quantity(HERB_ID) == 9, "ITEM: second Herb use did not free capacity")
	map.shop_action_button.emit_signal("pressed")
	map.shop_buy_button.emit_signal("pressed")
	await process_frame
	_check(game_state.get_money() == 0 and game_state.inventory_state.get_quantity(HERB_ID) == 10, "SHOP: repeated purchases did not stop at zero funds")
	game_state.party_runtime_state.set_current_hp("party_1", 20)
	map.inventory_button.emit_signal("pressed")
	map.healing_herb_button.emit_signal("pressed")
	map.inventory_target_list.get_node("InventoryTarget_party_1").emit_signal("pressed")
	_check(game_state.inventory_state.get_quantity(HERB_ID) == 9, "ITEM: third Herb use did not free capacity")
	_check(not game_state.buy_from_current_shop("riverside_camp", SHOP_ID, HERB_ID)["success"], "SHOP: insufficient funds purchase succeeded")
	_check(game_state.get_money() == 0 and game_state.inventory_state.get_quantity(HERB_ID) == 9, "SHOP: insufficient funds changed balances")
	_check(state.leftover_rewards.is_empty(), "SHOP: insufficient funds created leftover reward")
	_check(map.refresh_map(), "SHOP: refreshed map failed")
	map.shop_action_button.emit_signal("pressed")
	_check(map.shop_buy_button.disabled and map.shop_buy_button.tooltip_text == "Not enough money.", "SHOP: insufficient funds are not explained")
	await _assert_shop_geometry(map, Vector2i(1152, 648))
	await _assert_shop_geometry(map, Vector2i(1440, 810))
	root.size = Vector2i(1152, 648)
	await process_frame
	await process_frame


func _test_vn_and_battle_return() -> void:
	var map: Variant = await _fresh_map()
	if map == null:
		return
	_press_marker(map, "riverside_camp")
	await process_frame
	map.shop_action_button.emit_signal("pressed")
	map.shop_buy_button.emit_signal("pressed")
	await process_frame
	_check(game_state.get_money() == 8 and game_state.inventory_state.get_quantity(HERB_ID) == 10, "RETURN: setup purchase failed")
	_check(map.interact_with_current_node(), "VN: Riverside event did not launch")
	await process_frame
	await process_frame
	var vn: Variant = current_scene
	_check(vn != null and vn.name == "VNPrototype", "VN: expected VN scene did not load")
	if vn == null or vn.name != "VNPrototype":
		return
	_check(game_state.get_money() == 8 and game_state.inventory_state.get_quantity(HERB_ID) == 10, "VN: entry reset balances")
	vn._advance_dialogue()
	vn._advance_dialogue()
	vn._advance_dialogue()
	await process_frame
	await process_frame
	map = _current_map()
	_check(map != null, "VN: map return failed")
	if map == null:
		return
	_check(state.current_node_id == "riverside_camp" and state.is_node_completed("riverside_camp"), "VN: Riverside completion or location was lost")
	_check(state.is_node_revealed("deep_grove") and state.is_node_roadblocked("riverside_camp") and state.is_node_reusable("riverside_camp"), "VN: reveal/roadblock/reusable facts changed")
	_check(map.shop_action_button.visible and not map.primary_action_button.visible, "VN: Shop disappeared or primary replayed")
	_check(game_state.get_money() == 8 and game_state.inventory_state.get_quantity(HERB_ID) == 10, "VN: return reset balances")
	_press_marker(map, "old_trail")
	await process_frame
	_press_marker(map, "riverside_camp")
	await process_frame
	_check(map.shop_action_button.visible and not map.primary_action_button.visible, "REVISIT: completed Riverside lost Shop or replayed VN")
	_press_marker(map, "stone_crossing")
	await process_frame
	_check(not map.shop_action_button.visible, "BATTLE: Shop leaked into Stone Crossing")
	_check(map.interact_with_current_node(), "BATTLE: Stone interaction did not launch")
	await process_frame
	await process_frame
	var battle: Variant = current_scene
	_check(battle != null and battle.name == "BattleSandbox", "BATTLE: real scene did not load")
	if battle == null or battle.name != "BattleSandbox":
		return
	battle.automatic_enemy_turns_enabled = false
	_check(game_state.get_money() == 8 and game_state.inventory_state.get_quantity(HERB_ID) == 10, "BATTLE: entry reset balances")
	for unit: Variant in battle.enemy_units:
		unit.current_hp = 0
		unit.defeated = true
	_check(battle._check_battle_result(), "BATTLE: Victory was not recognized")
	await process_frame
	await process_frame
	map = _current_map()
	_check(map != null, "BATTLE: map return failed")
	_check(game_state.get_money() == 8 and game_state.inventory_state.get_quantity(HERB_ID) == 10, "BATTLE: return reset balances")
	if map != null:
		_press_marker(map, "riverside_camp")
		await process_frame
		_check(map.shop_action_button.visible and not map.primary_action_button.visible, "BATTLE: return/revisit lost Shop or replayed VN")


func _test_resource_overflow_compatibility() -> void:
	var map: Variant = await _fresh_map()
	if map == null:
		return
	_press_marker(map, "riverside_camp")
	await process_frame
	map.shop_action_button.emit_signal("pressed")
	map.shop_buy_button.emit_signal("pressed")
	await process_frame
	_press_marker(map, "stone_crossing")
	await process_frame
	_press_marker(map, "ruins_approach")
	await process_frame
	map.primary_action_button.emit_signal("pressed")
	await process_frame
	_check(game_state.inventory_state.get_quantity(HERB_ID) == 10, "RESOURCE: purchase cap was exceeded by reward")
	_check(state.get_leftover_reward("ruins_approach") == {"item_id": HERB_ID, "quantity": 2}, "RESOURCE: M7.4 overflow remainder changed")
	_check(state.is_node_completed("ruins_approach") and map.primary_action_button.text == "Collect Leftover", "RESOURCE: completion or leftover action changed")
	_check(game_state.get_money() == 8, "RESOURCE: resource interaction changed money")


func _assert_shop_geometry(map: Variant, target_size: Vector2i) -> void:
	root.size = target_size
	await process_frame
	await process_frame
	_check(map.refresh_map(), "LAYOUT %s: map failed to refresh" % target_size)
	var panel: Rect2 = map.shop_panel.get_global_rect()
	var viewport := Rect2(Vector2.ZERO, Vector2(target_size))
	_check(viewport.encloses(panel), "LAYOUT %s: Shop is clipped" % target_size)
	_check(not panel.intersects(map.get_node("HeaderPanel").get_global_rect()), "LAYOUT %s: Shop overlaps header" % target_size)
	_check(not panel.intersects(map.primary_action_panel.get_global_rect()), "LAYOUT %s: Shop overlaps actions" % target_size)
	_check(not panel.intersects(map.get_node("LegendPanel").get_global_rect()), "LAYOUT %s: Shop overlaps legend" % target_size)
	_check(map.shop_buy_button.visible and map.shop_back_button.visible, "LAYOUT %s: Shop controls are hidden" % target_size)


func _fresh_map() -> Variant:
	var scene: Variant = await _load_scene(ENTRY_SCENE_PATH)
	if scene == null:
		return null
	var map: Variant = scene.find_child("ExplorationMap", true, false)
	_check(map != null, "MAP: M7.5 prototype lacks reusable map")
	return map


func _current_map() -> Variant:
	if current_scene == null:
		return null
	if current_scene.has_method("get_marker_button"):
		return current_scene
	return current_scene.find_child("ExplorationMap", true, false)


func _press_marker(map: Variant, node_id: String) -> void:
	var marker: Button = map.get_marker_button(node_id)
	_check(marker != null, "TRAVEL: marker %s is missing" % node_id)
	if marker != null:
		marker.emit_signal("pressed")


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
