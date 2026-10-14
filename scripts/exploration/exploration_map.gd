class_name ExplorationMapController
extends Control

const VNPrototypeModel := preload("res://scripts/vn/vn_prototype.gd")
const ItemCatalogModel := preload("res://scripts/systems/item_catalog.gd")
const InventoryStateModel := preload("res://scripts/systems/inventory_state.gd")
const MARKER_SIZE := Vector2(164.0, 64.0)
const VN_SCENE_PATH := "res://scenes/vn/vn_prototype.tscn"
const BATTLE_SCENE_PATH := "res://scenes/battle/battle_sandbox.tscn"
const BATTLE_CONTENT_SCENES := {
	"m7_3_stone_crossing_battle": BATTLE_SCENE_PATH,
}
const RESOURCE_CONTENT_IDS := ["m7_3_ruins_resource"]
const GOLD := Color(0.96, 0.76, 0.30, 1.0)
const PALE_GOLD := Color(1.0, 0.90, 0.62, 1.0)
const VIOLET := Color(0.17, 0.10, 0.24, 0.96)
const VIOLET_HOVER := Color(0.25, 0.15, 0.34, 0.98)
const MUTED := Color(0.18, 0.20, 0.22, 0.94)
const UNAVAILABLE := Color(0.10, 0.11, 0.14, 0.88)
const ROADBLOCK_RED := Color(1.0, 0.35, 0.30, 1.0)
const REUSABLE_TEAL := Color(0.48, 0.92, 0.84, 1.0)

@onready var map_frame: Control = %MapFrame
@onready var map_texture: TextureRect = %MapTexture
@onready var marker_layer: Control = %MarkerLayer
@onready var context_title: Label = %ContextTitle
@onready var current_location_label: Label = %CurrentLocationLabel
@onready var money_label: Label = %MoneyLabel
@onready var time_panel: PanelContainer = %TimePanel
@onready var time_label: Label = %TimeLabel
@onready var time_actions_label: Label = %TimeActionsLabel
@onready var time_feedback_label: Label = %TimeFeedbackLabel
@onready var save_load_panel: PanelContainer = %SaveLoadPanel
@onready var map_save_button: Button = %MapSaveButton
@onready var map_load_button: Button = %MapLoadButton
@onready var save_load_status: Label = %SaveLoadStatus
@onready var inventory_button: Button = %InventoryButton
@onready var inventory_panel: PanelContainer = %InventoryPanel
@onready var inventory_status: Label = %InventoryStatus
@onready var healing_herb_button: Button = %HealingHerbButton
@onready var inventory_target_list: VBoxContainer = %InventoryTargetList
@onready var inventory_back_button: Button = %InventoryBackButton
@onready var primary_action_panel: PanelContainer = %PrimaryActionPanel
@onready var primary_action_status: Label = %PrimaryActionStatus
@onready var primary_action_button: Button = %PrimaryActionButton
@onready var shop_action_button: Button = %ShopActionButton
@onready var shop_panel: PanelContainer = %ShopPanel
@onready var shop_balance_label: Label = %ShopBalanceLabel
@onready var shop_offer_label: Label = %ShopOfferLabel
@onready var shop_status_label: Label = %ShopStatusLabel
@onready var shop_buy_button: Button = %ShopBuyButton
@onready var shop_back_button: Button = %ShopBackButton
@onready var hub_row: HBoxContainer = %HubRow
@onready var camp_rest_button: Button = %CampRestButton
@onready var wait_button: Button = %WaitButton
@onready var warning_preference_panel: PanelContainer = %WarningPreferencePanel
@onready var warning_preference_button: CheckButton = %WarningPreferenceButton
@onready var warning_overlay: ColorRect = %WarningOverlay
@onready var warning_summary_label: Label = %WarningSummaryLabel
@onready var warning_go_back_button: Button = %WarningGoBackButton
@onready var warning_continue_button: Button = %WarningContinueButton
@onready var diagnostic_panel: PanelContainer = %DiagnosticPanel
@onready var diagnostic_label: Label = %DiagnosticLabel

var marker_buttons: Dictionary = {}
var rendered_map_rect := Rect2()
var exploration_state: RefCounted
var interaction_in_progress := false
var last_interaction_feedback := ""
var feedback_node_id := ""
var inventory_item_selected := false
var inventory_feedback := ""
var shop_feedback := "Buy one item at a time."
var shop_purchase_in_progress := false
var shop_opened_at_node_id := ""
var hub_rendered_node_id := ""
var hub_activation_in_progress := false
var hub_feedback := ""
var hub_feedback_node_id := ""
var warning_dialog_open := false
var progression_in_progress := false
var progression_expected_context_id := ""
var progression_expected_node_id := ""
var warning_underlay_buttons: Dictionary = {}


func _ready() -> void:
	exploration_state = GameState.exploration_state
	primary_action_button.pressed.connect(interact_with_current_node)
	inventory_button.pressed.connect(_toggle_inventory_panel)
	healing_herb_button.pressed.connect(_select_healing_herb)
	inventory_back_button.pressed.connect(_back_inventory_panel)
	shop_action_button.pressed.connect(_open_shop)
	shop_buy_button.pressed.connect(_buy_shop_item)
	shop_back_button.pressed.connect(_close_shop)
	camp_rest_button.pressed.connect(_use_camp_rest)
	wait_button.pressed.connect(_wait_at_hub)
	warning_preference_button.toggled.connect(_on_warning_preference_toggled)
	warning_go_back_button.pressed.connect(_on_warning_go_back)
	warning_continue_button.pressed.connect(_on_warning_continue)
	map_save_button.pressed.connect(_on_map_save)
	map_load_button.pressed.connect(_on_map_load)
	save_load_status.text = GameState.persistence_feedback if not GameState.persistence_feedback.is_empty() else "Save / Load"
	resized.connect(_on_resized)
	call_deferred("refresh_map")


func refresh_map() -> bool:
	if warning_dialog_open:
		return true
	if exploration_state == null:
		return _show_diagnostic("Exploration state is unavailable.")
	if map_texture.texture == null:
		return _show_diagnostic("Exploration map background is missing.")
	if not exploration_state.has_active_context():
		return _show_diagnostic("No active Exploration context.")

	var context_definition: Dictionary = exploration_state.get_active_context_definition()
	var node_definitions: Array = exploration_state.get_active_node_definitions()
	var validation_error := _get_presentation_validation_error(context_definition, node_definitions)
	if not validation_error.is_empty():
		return _show_diagnostic(validation_error)
	if not _update_marker_layer_rect():
		return _show_diagnostic("Exploration map has no drawable area.")

	context_title.text = context_definition["display_name"]
	var current_definition: Dictionary = exploration_state.get_node_definition(exploration_state.current_node_id)
	current_location_label.text = "Current: %s" % current_definition["display_name"]
	money_label.text = "Money: %d" % GameState.get_money()
	_refresh_time_ui()
	_sync_marker_controls(node_definitions)
	_update_marker_positions(node_definitions)
	_refresh_primary_action(current_definition)
	_refresh_hub_action(current_definition)
	_refresh_inventory_ui()
	warning_preference_panel.visible = exploration_state.has_final_progression_node()
	warning_preference_button.set_pressed_no_signal(GameState.is_missable_content_warning_enabled())
	save_load_panel.visible = exploration_state.active_context_id == GameState.PROGRESSION_CONTEXT_ID
	map_load_button.disabled = not GameState.has_save_file()
	marker_layer.visible = true
	diagnostic_panel.visible = false
	return true


func get_marker_button(node_id: String) -> Button:
	return marker_buttons.get(node_id) as Button


func _on_map_save() -> void:
	if GameState.save_exploration_game():
		save_load_status.text = "Saved successfully."
	else:
		save_load_status.text = "Save failed: %s" % GameState.persistence_error
	map_load_button.disabled = not GameState.has_save_file()


func _on_map_load() -> void:
	if GameState.load_saved_game():
		return
	save_load_status.text = "Load failed: %s" % GameState.persistence_error
	map_load_button.disabled = not GameState.has_save_file()


func _on_resized() -> void:
	if is_node_ready():
		call_deferred("refresh_map")


func _on_marker_pressed(node_id: String) -> void:
	if warning_dialog_open or progression_in_progress:
		return
	if not exploration_state.has_active_context():
		refresh_map()
		return
	if not exploration_state.has_node(node_id):
		_show_diagnostic("Map marker references unknown node '%s'." % node_id)
		return
	if exploration_state.move_to_node(node_id):
		last_interaction_feedback = ""
		feedback_node_id = ""
		hub_feedback = ""
		hub_feedback_node_id = ""
		shop_panel.hide()
		shop_opened_at_node_id = ""
	refresh_map()


func interact_with_current_node() -> bool:
	if interaction_in_progress or warning_dialog_open or progression_in_progress or not exploration_state.has_active_context():
		return false
	var node_id: String = exploration_state.current_node_id
	var node_definition: Dictionary = exploration_state.get_node_definition(node_id)
	if node_definition.has("final_progression"):
		return request_story_advance()
	if exploration_state.has_leftover_reward(node_id):
		return _collect_leftover_reward(node_id)
	var validation_error := _get_primary_content_validation_error(node_definition)
	if not validation_error.is_empty():
		return _show_interaction_error(validation_error)
	if not node_definition.has("primary_content"):
		return false
	if exploration_state.is_node_completed(node_id):
		return false
	var primary_content: Dictionary = node_definition["primary_content"]
	var content_type: String = primary_content["type"]
	var content_id: String = primary_content["id"]
	match content_type:
		"vn_event":
			return _launch_vn_content(content_id)
		"battle":
			return _launch_battle_content(content_id)
		"resource":
			return _resolve_resource_content(primary_content)
	return _show_interaction_error("Unsupported primary content type '%s'." % content_type)


func request_story_advance() -> bool:
	if warning_dialog_open or progression_in_progress or not exploration_state.has_active_context():
		return false
	progression_expected_context_id = exploration_state.active_context_id
	progression_expected_node_id = exploration_state.current_node_id
	if not exploration_state.can_advance_from_current_node(
		progression_expected_context_id, progression_expected_node_id
	):
		return false
	var summary: Dictionary = exploration_state.get_missable_content_summary()
	if GameState.is_missable_content_warning_enabled() and summary["total"] > 0:
		_open_warning_dialog(summary)
		return true
	return _commit_story_advance()


func _open_warning_dialog(summary: Dictionary) -> void:
	var details: Array[String] = []
	if summary["optional_primary_count"] > 0:
		details.append("Optional events: %d" % summary["optional_primary_count"])
	if summary["leftover_reward_count"] > 0:
		details.append("Uncollected rewards: %d" % summary["leftover_reward_count"])
	if summary["optional_roadblock_count"] > 0:
		details.append("Optional roadblocks: %d" % summary["optional_roadblock_count"])
	warning_summary_label.text = "  •  ".join(details)
	warning_dialog_open = true
	warning_overlay.show()
	warning_underlay_buttons.clear()
	for raw_node: Node in find_children("*", "BaseButton", true, false):
		var button := raw_node as BaseButton
		if button == null or warning_overlay.is_ancestor_of(button):
			continue
		warning_underlay_buttons[button] = {
			"disabled": button.disabled,
			"focus_mode": button.focus_mode,
		}
		button.disabled = true
		button.focus_mode = Control.FOCUS_NONE
	warning_go_back_button.disabled = false
	warning_continue_button.disabled = false
	warning_go_back_button.grab_focus()


func _on_warning_go_back() -> void:
	if not warning_dialog_open or progression_in_progress:
		return
	_close_warning_dialog()
	primary_action_button.grab_focus()


func _close_warning_dialog() -> void:
	warning_dialog_open = false
	warning_overlay.hide()
	for raw_button: Variant in warning_underlay_buttons:
		var button := raw_button as BaseButton
		if not is_instance_valid(button):
			continue
		button.disabled = warning_underlay_buttons[raw_button]["disabled"]
		button.focus_mode = warning_underlay_buttons[raw_button]["focus_mode"]
	warning_underlay_buttons.clear()
	refresh_map()


func _on_warning_continue() -> void:
	if not warning_dialog_open or progression_in_progress:
		return
	_commit_story_advance()


func _commit_story_advance() -> bool:
	if progression_in_progress:
		return false
	progression_in_progress = true
	warning_continue_button.disabled = true
	warning_go_back_button.disabled = true
	var result: Dictionary = GameState.advance_story_from_exploration(
		progression_expected_context_id, progression_expected_node_id
	)
	if result["success"]:
		return true
	progression_in_progress = false
	warning_continue_button.disabled = false
	warning_go_back_button.disabled = false
	if warning_dialog_open:
		_close_warning_dialog()
	last_interaction_feedback = result["message"]
	feedback_node_id = exploration_state.current_node_id
	refresh_map()
	return false


func _on_warning_preference_toggled(enabled: bool) -> void:
	GameState.set_missable_content_warning_enabled(enabled)


func _unhandled_input(event: InputEvent) -> void:
	if warning_dialog_open and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_warning_go_back()


func _launch_vn_content(content_id: String) -> bool:
	if VNPrototypeModel.resolve_dialogue_sequence_path(content_id).is_empty():
		return _show_interaction_error("VN content '%s' cannot be resolved." % content_id)
	if not GameState.prepare_exploration_content("vn_event", content_id):
		return _show_interaction_error("VN interaction handoff could not be prepared.")
	if not GameState.prepare_pending_vn_sequence(content_id):
		GameState.clear_pending_exploration_content()
		return _show_interaction_error("VN routing is already occupied.")
	interaction_in_progress = true
	primary_action_button.disabled = true
	var change_error := get_tree().change_scene_to_file(VN_SCENE_PATH)
	if change_error != OK:
		GameState.clear_pending_vn_sequence()
		GameState.clear_pending_exploration_content()
		interaction_in_progress = false
		return _show_interaction_error(
			"Could not launch VN content: %s" % error_string(change_error)
		)
	return true


func _launch_battle_content(content_id: String) -> bool:
	if not BATTLE_CONTENT_SCENES.has(content_id):
		return _show_interaction_error("Battle content '%s' cannot be resolved." % content_id)
	var battle_scene: String = BATTLE_CONTENT_SCENES[content_id]
	if not ResourceLoader.exists(battle_scene):
		return _show_interaction_error("Battle scene is missing for '%s'." % content_id)
	if not GameState.prepare_exploration_content("battle", content_id):
		return _show_interaction_error("Battle interaction handoff could not be prepared.")
	interaction_in_progress = true
	primary_action_button.disabled = true
	var change_error := get_tree().change_scene_to_file(battle_scene)
	if change_error != OK:
		GameState.clear_pending_exploration_content()
		interaction_in_progress = false
		return _show_interaction_error(
			"Could not launch battle content: %s" % error_string(change_error)
		)
	return true


func _resolve_resource_content(primary_content: Dictionary) -> bool:
	var content_id: String = primary_content["id"]
	if not RESOURCE_CONTENT_IDS.has(content_id):
		return _show_interaction_error("Resource content '%s' cannot be resolved." % content_id)
	var reward: Dictionary = primary_content["reward"]
	var item_id: String = reward["item_id"]
	var requested_quantity: int = reward["quantity"]
	var item_definition: Dictionary = GameState.inventory_state.get_item_definition(item_id)
	if item_definition.is_empty():
		return _show_interaction_error("Resource reward item '%s' is unknown." % item_id)
	if not GameState.prepare_exploration_content("resource", content_id):
		return _show_interaction_error("Resource interaction handoff could not be prepared.")
	interaction_in_progress = true
	if not GameState.resolve_pending_exploration_content("resource", content_id):
		GameState.clear_pending_exploration_content()
		interaction_in_progress = false
		return _show_interaction_error("Resource interaction handoff became invalid.")
	var gain_result: Dictionary = GameState.inventory_state.gain_item(item_id, requested_quantity)
	var remaining: int = gain_result["remaining"]
	if remaining > 0:
		exploration_state.set_leftover_reward(
			exploration_state.current_node_id,
			item_id,
			remaining
		)
	GameState.clear_pending_exploration_content()
	interaction_in_progress = false
	last_interaction_feedback = "%s ×%d collected." % [
		item_definition["display_name"],
		gain_result["accepted"],
	]
	if remaining > 0:
		last_interaction_feedback += " Leftover ×%d remains." % remaining
	feedback_node_id = exploration_state.current_node_id
	return refresh_map()


func _collect_leftover_reward(node_id: String) -> bool:
	var leftover: Dictionary = exploration_state.get_leftover_reward(node_id)
	if leftover.is_empty():
		return false
	var item_definition: Dictionary = GameState.inventory_state.get_item_definition(
		leftover["item_id"]
	)
	if item_definition.is_empty():
		return _show_interaction_error("Leftover reward references an unknown item.")
	var gain_result: Dictionary = GameState.inventory_state.gain_item(
		leftover["item_id"],
		leftover["quantity"]
	)
	var accepted: int = gain_result["accepted"]
	if accepted > 0:
		exploration_state.reduce_leftover_reward(node_id, accepted)
		last_interaction_feedback = "%s ×%d collected." % [
			item_definition["display_name"],
			accepted,
		]
	else:
		last_interaction_feedback = "Inventory full. Leftover remains ×%d." % leftover["quantity"]
	feedback_node_id = node_id
	return refresh_map()


func _refresh_primary_action(node_definition: Dictionary) -> void:
	var node_id: String = node_definition.get("id", "")
	if node_definition.has("final_progression"):
		primary_action_panel.show()
		primary_action_status.text = "Select Advance Story to leave this exploration phase."
		primary_action_button.text = "Advance Story"
		primary_action_button.visible = true
		primary_action_button.disabled = progression_in_progress or exploration_state.is_node_roadblocked(node_id)
		return
	var validation_error := _get_primary_content_validation_error(node_definition)
	if not validation_error.is_empty():
		_show_interaction_error(validation_error)
		return
	if exploration_state.has_leftover_reward(node_id):
		var leftover: Dictionary = exploration_state.get_leftover_reward(node_id)
		var definition: Dictionary = GameState.inventory_state.get_item_definition(
			leftover["item_id"]
		)
		primary_action_panel.visible = true
		primary_action_status.text = (
			last_interaction_feedback
			if feedback_node_id == node_id and not last_interaction_feedback.is_empty()
			else "%s ×%d remains here." % [
				definition.get("display_name", leftover["item_id"]),
				leftover["quantity"],
			]
		)
		primary_action_button.text = "Collect Leftover"
		primary_action_button.visible = true
		primary_action_button.disabled = false
		return
	if exploration_state.is_node_completed(node_id) or not node_definition.has("primary_content"):
		primary_action_panel.visible = (
			node_id == feedback_node_id and not last_interaction_feedback.is_empty()
		)
		primary_action_status.text = last_interaction_feedback
		primary_action_button.visible = false
		primary_action_button.disabled = true
		return
	primary_action_panel.visible = true
	primary_action_status.text = "Location interaction available."
	primary_action_button.text = "Interact"
	primary_action_button.visible = true
	primary_action_button.disabled = interaction_in_progress


func _get_primary_content_validation_error(node_definition: Dictionary) -> String:
	if not node_definition.has("primary_content"):
		return ""
	var raw_content: Variant = node_definition["primary_content"]
	if typeof(raw_content) != TYPE_DICTIONARY:
		return "Current node has malformed primary content."
	var primary_content: Dictionary = raw_content
	if typeof(primary_content.get("type")) != TYPE_STRING or primary_content["type"].is_empty():
		return "Current node primary content has no valid type."
	if typeof(primary_content.get("id")) != TYPE_STRING or primary_content["id"].is_empty():
		return "Current node primary content has no valid id."
	if not ["vn_event", "battle", "resource"].has(primary_content["type"]):
		return "Unsupported primary content type '%s'." % primary_content["type"]
	var has_action_cost := primary_content.has("action_cost")
	var has_optional := primary_content.has("optional")
	if has_action_cost and (typeof(primary_content["action_cost"]) != TYPE_INT or not [0, 1].has(primary_content["action_cost"])):
		return "Current node primary content has an invalid action cost."
	if has_optional and typeof(primary_content["optional"]) != TYPE_BOOL:
		return "Current node primary content has an invalid optional flag."
	if primary_content["type"] != "resource":
		if primary_content.keys().size() != 2 + int(has_action_cost) + int(has_optional):
			return "Current node primary content has unexpected fields."
		return ""
	if primary_content.keys().size() != 3 + int(has_action_cost) + int(has_optional):
		return "Resource primary content requires one item reward."
	var raw_reward: Variant = primary_content.get("reward")
	if typeof(raw_reward) != TYPE_DICTIONARY:
		return "Resource primary content has a malformed reward."
	var reward: Dictionary = raw_reward
	if (
		reward.keys().size() != 3
		or reward.get("type") != "item"
		or typeof(reward.get("item_id")) != TYPE_STRING
		or String(reward.get("item_id")).is_empty()
		or typeof(reward.get("quantity")) != TYPE_INT
		or int(reward.get("quantity")) <= 0
	):
		return "Resource primary content has an invalid item reward."
	return ""


func _show_interaction_error(message: String) -> bool:
	last_interaction_feedback = message
	feedback_node_id = exploration_state.current_node_id if exploration_state != null else ""
	primary_action_panel.visible = true
	primary_action_status.text = message
	primary_action_button.visible = false
	primary_action_button.disabled = true
	push_error("Exploration interaction error: %s" % message)
	return false


func _toggle_inventory_panel() -> void:
	inventory_panel.visible = not inventory_panel.visible
	if inventory_panel.visible:
		shop_panel.hide()
		shop_opened_at_node_id = ""
		inventory_item_selected = false
		inventory_feedback = "Choose an item."
	_refresh_inventory_ui()


func _select_healing_herb() -> void:
	if GameState.inventory_state.get_quantity(ItemCatalogModel.HEALING_HERB_ID) <= 0:
		inventory_feedback = "No Healing Herbs available."
		_refresh_inventory_ui()
		return
	inventory_item_selected = true
	inventory_feedback = "Choose a living current-party member."
	_refresh_inventory_ui()


func _back_inventory_panel() -> void:
	if inventory_item_selected:
		inventory_item_selected = false
		inventory_feedback = "Choose an item."
	else:
		inventory_panel.hide()
	_refresh_inventory_ui()


func _refresh_inventory_ui() -> void:
	var quantity: int = GameState.inventory_state.get_quantity(
		ItemCatalogModel.HEALING_HERB_ID
	)
	inventory_button.text = "Items · Healing Herb ×%d" % quantity
	healing_herb_button.text = "Healing Herb ×%d" % quantity
	healing_herb_button.disabled = quantity <= 0
	if not inventory_panel.visible:
		return
	inventory_status.text = inventory_feedback
	healing_herb_button.visible = not inventory_item_selected
	inventory_target_list.visible = inventory_item_selected
	if inventory_item_selected:
		_rebuild_inventory_targets()


func _rebuild_inventory_targets() -> void:
	for child: Node in inventory_target_list.get_children():
		inventory_target_list.remove_child(child)
		child.queue_free()
	for member: Dictionary in GameState.party_runtime_state.get_members():
		var target_button := Button.new()
		target_button.name = "InventoryTarget_%s" % member["id"]
		target_button.text = "%s · HP %d/%d" % [
			member["display_name"],
			member["current_hp"],
			member["max_hp"],
		]
		target_button.disabled = member["current_hp"] <= 0
		if target_button.disabled:
			target_button.text += " · DEFEATED"
		target_button.pressed.connect(_use_healing_herb_in_exploration.bind(member["id"]))
		inventory_target_list.add_child(target_button)


func _use_healing_herb_in_exploration(member_id: String) -> bool:
	var member_before: Dictionary = GameState.party_runtime_state.get_member(member_id)
	var result: Dictionary = GameState.use_item_in_exploration(
		ItemCatalogModel.HEALING_HERB_ID,
		member_id
	)
	if not result["success"]:
		inventory_feedback = "Healing Herb use was rejected; nothing was consumed."
		_refresh_inventory_ui()
		return false
	inventory_feedback = "%s recovered %d HP · %d/%d HP." % [
		member_before["display_name"],
		result["healed"],
		result["current_hp"],
		result["max_hp"],
	]
	_refresh_inventory_ui()
	return true


func _refresh_hub_action(node_definition: Dictionary) -> void:
	var shop_action := _get_shop_action(node_definition)
	var rest_action := _get_hub_action(node_definition, "rest")
	var wait_action := _get_hub_action(node_definition, "wait")
	hub_rendered_node_id = node_definition.get("id", "")
	shop_action_button.visible = not shop_action.is_empty()
	shop_action_button.disabled = shop_action.is_empty()
	if shop_action.is_empty():
		shop_panel.hide()
		shop_opened_at_node_id = ""
	else:
		shop_action_button.text = shop_action.get("display_name", "Shop")
	camp_rest_button.visible = not rest_action.is_empty()
	wait_button.visible = not wait_action.is_empty()
	hub_row.visible = camp_rest_button.visible or wait_button.visible
	if camp_rest_button.visible:
		var remaining: int = exploration_state.get_hub_action_uses_remaining(
			hub_rendered_node_id, rest_action["id"]
		)
		camp_rest_button.text = "%s · %d left" % [rest_action["display_name"], remaining]
		camp_rest_button.disabled = remaining <= 0 or hub_activation_in_progress
		camp_rest_button.tooltip_text = (
			"Rest uses exhausted." if remaining <= 0 else "Restore 50% Max HP to the party."
		)
	if wait_button.visible:
		wait_button.text = wait_action["display_name"]
		wait_button.disabled = hub_activation_in_progress
	if not shop_action.is_empty() or hub_row.visible:
		primary_action_panel.show()
		if not primary_action_button.visible:
			primary_action_status.text = "Location actions available."
	if hub_feedback_node_id == hub_rendered_node_id and not hub_feedback.is_empty():
		primary_action_status.text = hub_feedback
	if shop_panel.visible:
		if shop_opened_at_node_id != exploration_state.current_node_id:
			shop_panel.hide()
			shop_opened_at_node_id = ""
		else:
			_refresh_shop_ui(shop_action)


func _get_shop_action(node_definition: Dictionary) -> Dictionary:
	return _get_hub_action(node_definition, "shop")


func _get_hub_action(node_definition: Dictionary, action_type: String) -> Dictionary:
	var raw_actions: Variant = node_definition.get("hub_actions", [])
	if typeof(raw_actions) != TYPE_ARRAY:
		return {}
	for raw_action: Variant in raw_actions:
		if typeof(raw_action) == TYPE_DICTIONARY and raw_action.get("type") == action_type:
			return raw_action
	return {}


func _refresh_time_ui() -> void:
	var snapshot: Dictionary = exploration_state.get_time_snapshot()
	time_panel.visible = snapshot.get("mode") != "NO_TIME"
	if not time_panel.visible:
		return
	time_label.text = "Day %d — %s" % [snapshot["day"], snapshot["daypart"]]
	time_actions_label.text = "Actions: %d/2" % snapshot["actions_spent"]
	time_feedback_label.text = snapshot["feedback"]
	time_feedback_label.visible = not snapshot["feedback"].is_empty()


func _use_camp_rest() -> void:
	if hub_activation_in_progress or not camp_rest_button.visible or camp_rest_button.disabled:
		return
	hub_activation_in_progress = true
	call_deferred("_clear_hub_activation_guard")
	var node_definition: Dictionary = exploration_state.get_node_definition(hub_rendered_node_id)
	var rest_action := _get_hub_action(node_definition, "rest")
	var result: Dictionary = GameState.use_current_camp_rest(
		hub_rendered_node_id, rest_action.get("id", "")
	)
	hub_feedback = result["message"]
	hub_feedback_node_id = hub_rendered_node_id
	refresh_map()


func _wait_at_hub() -> void:
	if hub_activation_in_progress or not wait_button.visible or wait_button.disabled:
		return
	hub_activation_in_progress = true
	call_deferred("_clear_hub_activation_guard")
	var node_definition: Dictionary = exploration_state.get_node_definition(hub_rendered_node_id)
	var wait_action := _get_hub_action(node_definition, "wait")
	var result: Dictionary = GameState.wait_at_current_hub(
		hub_rendered_node_id, wait_action.get("id", "")
	)
	hub_feedback = result["message"]
	hub_feedback_node_id = hub_rendered_node_id
	refresh_map()


func _clear_hub_activation_guard() -> void:
	hub_activation_in_progress = false
	if is_node_ready():
		refresh_map()


func _open_shop() -> void:
	if not exploration_state.has_active_context():
		return
	var node_definition: Dictionary = exploration_state.get_node_definition(
		exploration_state.current_node_id
	)
	var shop_action := _get_shop_action(node_definition)
	if shop_action.is_empty():
		refresh_map()
		return
	inventory_panel.hide()
	shop_opened_at_node_id = exploration_state.current_node_id
	shop_feedback = "Buy one item at a time."
	shop_panel.show()
	_refresh_shop_ui(shop_action)
	shop_buy_button.grab_focus()


func _buy_shop_item() -> void:
	if shop_purchase_in_progress or not shop_panel.visible:
		return
	shop_purchase_in_progress = true
	call_deferred("_clear_shop_purchase_guard")
	var node_definition: Dictionary = exploration_state.get_node_definition(
		shop_opened_at_node_id
	)
	var shop_action := _get_shop_action(node_definition)
	var catalog: Array = shop_action.get("catalog", [])
	if catalog.is_empty():
		shop_feedback = "Shop offer is unavailable."
		refresh_map()
		return
	var item_id: String = catalog[0].get("item_id", "")
	var result: Dictionary = GameState.buy_from_current_shop(
		shop_opened_at_node_id,
		shop_action.get("id", ""),
		item_id
	)
	shop_feedback = result["message"]
	refresh_map()


func _clear_shop_purchase_guard() -> void:
	shop_purchase_in_progress = false
	if shop_panel.visible:
		refresh_map()


func _close_shop() -> void:
	shop_panel.hide()
	shop_opened_at_node_id = ""
	shop_action_button.grab_focus()


func _refresh_shop_ui(shop_action: Dictionary) -> void:
	var catalog: Array = shop_action.get("catalog", [])
	if catalog.is_empty():
		shop_panel.hide()
		_show_diagnostic("Shop has no authored offer.")
		return
	var offer: Dictionary = catalog[0]
	var item_id: String = offer.get("item_id", "")
	var item_definition: Dictionary = GameState.inventory_state.get_item_definition(item_id)
	if item_definition.is_empty():
		shop_panel.hide()
		_show_diagnostic("Shop references unknown item '%s'." % item_id)
		return
	var quantity: int = GameState.inventory_state.get_quantity(item_id)
	var price: int = offer.get("price", 0)
	shop_balance_label.text = "Money: %d" % GameState.get_money()
	shop_offer_label.text = "%s · %d money · Owned %d/%d" % [
		item_definition["display_name"], price, quantity, InventoryStateModel.STACK_CAP,
	]
	shop_status_label.text = shop_feedback
	shop_buy_button.text = "Buy %s" % item_definition["display_name"]
	shop_buy_button.disabled = (
		quantity >= InventoryStateModel.STACK_CAP
		or GameState.get_money() < price
		or shop_purchase_in_progress
	)
	if quantity >= InventoryStateModel.STACK_CAP:
		shop_buy_button.tooltip_text = "Inventory full."
	elif GameState.get_money() < price:
		shop_buy_button.tooltip_text = "Not enough money."
	else:
		shop_buy_button.tooltip_text = "Buy one %s for %d money." % [item_definition["display_name"], price]


func _sync_marker_controls(node_definitions: Array) -> void:
	var visible_node_definitions: Dictionary = {}
	for raw_definition: Variant in node_definitions:
		var node_definition: Dictionary = raw_definition
		var node_id: String = node_definition["id"]
		if exploration_state.is_node_revealed(node_id):
			visible_node_definitions[node_id] = node_definition

	for raw_existing_id: Variant in marker_buttons.keys():
		var existing_id: String = raw_existing_id
		if visible_node_definitions.has(existing_id):
			continue
		var old_button: Button = marker_buttons[existing_id]
		old_button.visible = false
		old_button.disabled = true
		marker_buttons.erase(existing_id)
		old_button.queue_free()

	for raw_node_id: Variant in visible_node_definitions:
		var node_id: String = raw_node_id
		var node_definition: Dictionary = visible_node_definitions[node_id]
		if not marker_buttons.has(node_id):
			marker_buttons[node_id] = _create_marker_button(node_id, node_definition["display_name"])
		_update_marker_visuals(node_id, node_definition)


func _create_marker_button(node_id: String, display_name: String) -> Button:
	var button := Button.new()
	button.name = "Marker_%s" % node_id
	button.text = display_name
	button.custom_minimum_size = MARKER_SIZE
	button.size = MARKER_SIZE
	button.clip_text = true
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.set_meta("node_id", node_id)
	button.pressed.connect(_on_marker_pressed.bind(node_id))
	marker_layer.add_child(button)

	_add_indicator(button, "CompletedBadge", "✓", HORIZONTAL_ALIGNMENT_LEFT, Color(0.72, 0.90, 0.72, 1.0))
	_add_indicator(button, "RoadblockBadge", "!", HORIZONTAL_ALIGNMENT_RIGHT, ROADBLOCK_RED)
	_add_indicator(button, "ReusableBadge", "↻", HORIZONTAL_ALIGNMENT_RIGHT, REUSABLE_TEAL, true)
	_add_indicator(button, "FinalBadge", "STORY EXIT", HORIZONTAL_ALIGNMENT_CENTER, PALE_GOLD)
	var leftover_badge := _add_indicator(button, "LeftoverBadge", "ITEM", HORIZONTAL_ALIGNMENT_CENTER, GOLD)
	leftover_badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	leftover_badge.offset_left = 20.0
	leftover_badge.offset_top = 4.0
	leftover_badge.offset_right = -20.0
	leftover_badge.offset_bottom = 30.0
	leftover_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	leftover_badge.add_theme_font_size_override("font_size", 14)
	leftover_badge.add_theme_constant_override("outline_size", 2)
	leftover_badge.add_theme_stylebox_override("normal", _make_leftover_badge_style())
	var current_tag := _add_indicator(button, "CurrentTag", "CURRENT", HORIZONTAL_ALIGNMENT_CENTER, PALE_GOLD, true)
	current_tag.offset_right = -22.0
	return button


func _add_indicator(
	button: Button,
	indicator_name: String,
	indicator_text: String,
	alignment: HorizontalAlignment,
	color: Color,
	bottom: bool = false
) -> Label:
	var label := Label.new()
	label.name = indicator_name
	label.text = indicator_text
	label.horizontal_alignment = alignment
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.04, 0.025, 0.06, 1.0))
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_font_size_override("font_size", 13 if indicator_name == "CurrentTag" else 18)
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE if bottom else Control.PRESET_TOP_WIDE)
	if bottom:
		label.offset_top = -22.0
	else:
		label.offset_bottom = 24.0
	label.visible = false
	button.add_child(label)
	return label


func _update_marker_visuals(node_id: String, node_definition: Dictionary) -> void:
	var button: Button = marker_buttons[node_id]
	var is_current: bool = exploration_state.current_node_id == node_id
	var is_completed: bool = exploration_state.is_node_completed(node_id)
	var is_roadblocked: bool = exploration_state.is_node_roadblocked(node_id)
	var is_reusable: bool = exploration_state.is_node_reusable(node_id)
	var has_leftover: bool = exploration_state.has_leftover_reward(node_id)
	var is_final: bool = node_definition.has("final_progression")
	var is_reachable: bool = not is_current and exploration_state.can_travel_to(node_id)

	button.text = node_definition["display_name"]
	button.disabled = not is_reachable
	button.focus_mode = Control.FOCUS_ALL if is_reachable else Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if is_reachable else Control.CURSOR_ARROW
	button.set_meta("map_position", node_definition["map_position"])
	button.set_meta("is_current", is_current)
	button.set_meta("is_completed", is_completed)
	button.set_meta("is_roadblocked", is_roadblocked)
	button.set_meta("is_reusable", is_reusable)
	button.set_meta("has_leftover", has_leftover)
	button.set_meta("is_reachable", is_reachable)
	button.set_meta("is_final_progression", is_final)

	button.get_node("CompletedBadge").visible = is_completed
	button.get_node("CurrentTag").visible = is_current
	button.get_node("RoadblockBadge").visible = is_roadblocked
	button.get_node("ReusableBadge").visible = is_reusable
	button.get_node("FinalBadge").visible = is_final and not is_current
	var leftover_badge: Label = button.get_node("LeftoverBadge")
	leftover_badge.visible = has_leftover
	if has_leftover:
		leftover_badge.text = "ITEM ×%d" % exploration_state.get_leftover_reward(node_id)["quantity"]

	var background := MUTED if is_completed else (VIOLET if is_reachable or is_current else UNAVAILABLE)
	if is_final and (is_reachable or is_current):
		background = Color(0.24, 0.15, 0.18, 0.97)
	var border := GOLD if is_current else (Color(0.76, 0.62, 0.32, 0.95) if is_reachable else Color(0.42, 0.43, 0.46, 0.85))
	if is_final:
		border = PALE_GOLD
	var border_width := 4 if is_current or is_final else 2
	var normal_style := _make_marker_style(background, border, border_width)
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("disabled", normal_style)
	button.add_theme_stylebox_override("hover", _make_marker_style(VIOLET_HOVER, GOLD, 3))
	button.add_theme_stylebox_override("pressed", _make_marker_style(Color(0.32, 0.20, 0.40, 1.0), PALE_GOLD, 3))
	button.add_theme_stylebox_override("focus", _make_marker_style(Color(0.0, 0.0, 0.0, 0.0), PALE_GOLD, 3))
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", PALE_GOLD)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", PALE_GOLD if is_current else Color(0.72, 0.72, 0.74, 1.0))
	button.add_theme_font_size_override("font_size", 17)

	var tooltip_parts: Array[String] = [node_definition["display_name"]]
	if is_current:
		tooltip_parts.append("Current location")
	elif is_reachable:
		tooltip_parts.append("Available destination")
	else:
		tooltip_parts.append("Not reachable from here")
	if is_completed:
		tooltip_parts.append("Completed")
	if is_roadblocked:
		tooltip_parts.append("Roadblock present")
	if is_reusable:
		tooltip_parts.append("Reusable location")
	if has_leftover:
		tooltip_parts.append("Uncollected item remains")
	if is_final:
		tooltip_parts.append("Story exit — use Advance Story here")
	button.tooltip_text = " • ".join(tooltip_parts)


func _update_marker_positions(node_definitions: Array) -> void:
	for raw_definition: Variant in node_definitions:
		var node_definition: Dictionary = raw_definition
		var node_id: String = node_definition["id"]
		if not marker_buttons.has(node_id):
			continue
		var button: Button = marker_buttons[node_id]
		var normalized_position: Vector2 = node_definition["map_position"]
		button.size = MARKER_SIZE
		button.position = normalized_position * marker_layer.size - MARKER_SIZE * 0.5


func _update_marker_layer_rect() -> bool:
	var available_size := map_texture.size
	var texture_size := Vector2(map_texture.texture.get_size())
	if available_size.x <= 0.0 or available_size.y <= 0.0 or texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return false
	var image_scale: float = minf(available_size.x / texture_size.x, available_size.y / texture_size.y)
	var rendered_size: Vector2 = texture_size * image_scale
	var rendered_offset: Vector2 = (available_size - rendered_size) * 0.5
	rendered_map_rect = Rect2(map_texture.position + rendered_offset, rendered_size)
	marker_layer.position = rendered_map_rect.position
	marker_layer.size = rendered_map_rect.size
	return true


func _get_presentation_validation_error(context_definition: Dictionary, node_definitions: Array) -> String:
	if typeof(context_definition.get("display_name")) != TYPE_STRING or context_definition["display_name"].is_empty():
		return "Active Exploration context has no display name."
	if node_definitions.is_empty():
		return "Active Exploration context has no map nodes."
	for raw_definition: Variant in node_definitions:
		if typeof(raw_definition) != TYPE_DICTIONARY:
			return "Exploration map contains malformed node data."
		var node_definition: Dictionary = raw_definition
		var node_id: Variant = node_definition.get("id")
		if typeof(node_id) != TYPE_STRING or node_id.is_empty() or not exploration_state.has_node(node_id):
			return "Exploration map contains an unknown node."
		if typeof(node_definition.get("display_name")) != TYPE_STRING or node_definition["display_name"].is_empty():
			return "Exploration node '%s' has no display name." % node_id
		if typeof(node_definition.get("map_position")) != TYPE_VECTOR2:
			return "Exploration node '%s' has no normalized map position." % node_id
		var map_position: Vector2 = node_definition["map_position"]
		if (
			is_nan(map_position.x)
			or is_inf(map_position.x)
			or is_nan(map_position.y)
			or is_inf(map_position.y)
			or map_position.x < 0.0
			or map_position.x > 1.0
			or map_position.y < 0.0
			or map_position.y > 1.0
		):
			return "Exploration node '%s' has an invalid normalized map position." % node_id
		var shop_action := _get_shop_action(node_definition)
		if not shop_action.is_empty():
			var catalog: Array = shop_action.get("catalog", [])
			for raw_offer: Variant in catalog:
				if GameState.inventory_state.get_item_definition(raw_offer.get("item_id", "")).is_empty():
					return "Exploration node '%s' has an unknown Shop item." % node_id
	return ""


func _show_diagnostic(message: String) -> bool:
	marker_layer.visible = false
	warning_preference_panel.hide()
	shop_panel.hide()
	shop_action_button.hide()
	hub_row.hide()
	time_panel.hide()
	diagnostic_label.text = message
	diagnostic_panel.visible = true
	return false


func _make_marker_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(18)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 16.0
	style.shadow_color = Color(0.02, 0.015, 0.03, 0.72)
	style.shadow_size = 7
	return style


func _make_leftover_badge_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.065, 0.16, 0.98)
	style.border_color = GOLD
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	style.shadow_color = Color(0.02, 0.01, 0.03, 0.72)
	style.shadow_size = 4
	return style
