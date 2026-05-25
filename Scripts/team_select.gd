extends Control

@onready var status_lbl: Label = $Content/Status
@onready var btn_container: VBoxContainer = $Content/TeamList

var my_team: int = -1
var team_counts: Dictionary = {}
var nm: Node = null

# team_id -> Button
var _team_buttons: Dictionary = {}

func _ready():
	# Wait one frame so NetworkManager is fully initialized
	await get_tree().process_frame

	nm = get_node("/root/Main/NetworkManager")
	if nm == null:
		printerr("TeamSelect: NetworkManager not found!")
		return

	_build_team_buttons()

	nm.team_data_updated.connect(_on_team_data_updated)
	nm.game_started.connect(_on_game_started)
	nm.game_mode_updated.connect(update_ui)
	nm.discovery_status.connect(_on_discovery_status)

	update_ui()

func _build_team_buttons() -> void:
	# Clear any leftover children
	for child in btn_container.get_children():
		child.queue_free()
	_team_buttons.clear()

	for t in nm.team_config.get("teams", []):
		var tid: int = t.get("team_id", -1)
		if tid == -1:
			continue
		var tname: String = t.get("team_name", "Team %d" % tid)
		var c_arr = t.get("color", null)

		if _team_buttons.has(tid):
			printerr("teams.json: duplicate team_id %d — skipping '%s'" % [tid, tname])
			continue
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(150, 60)
		btn.text = tname
		if c_arr != null:
			btn.modulate = Color(c_arr[0], c_arr[1], c_arr[2])
		btn.pressed.connect(func(): _on_team_btn_pressed(tid))
		btn_container.add_child(btn)
		_team_buttons[tid] = btn

func _on_team_data_updated(counts: Dictionary, your_team: int) -> void:
	team_counts = counts
	my_team = your_team
	update_ui()

func update_ui() -> void:
	var mpt: int = nm.max_per_team if nm else 2
	var mp: int = nm.max_players if nm else 4
	var total: int = 0
	for cnt in team_counts.values():
		total += cnt

	# Once 2 or more teams have at least 1 player, hide teams with nobody in them
	var teams_active: int = 0
	for tid in _team_buttons:
		if team_counts.get(tid, 0) >= 1:
			teams_active += 1
	var lock_empty := teams_active >= 2

	for tid in _team_buttons:
		var btn: Button = _team_buttons[tid]
		var t = nm._get_team_config(tid)
		var tname: String = t.get("team_name", "Team %d" % tid)
		var count: int = team_counts.get(tid, 0)
		btn.text = "%s\n%d/%d" % [tname, count, mpt]
		var is_full := count >= mpt
		btn.disabled = is_full or (my_team != -1)
		# Hide teams with no players once the match shape is decided
		btn.visible = not (lock_empty and count == 0)
		var c_arr = t.get("color", null)
		if c_arr != null:
			btn.modulate = Color(c_arr[0], c_arr[1], c_arr[2]) if not btn.disabled else Color(0.5, 0.5, 0.5)
		else:
			btn.modulate = Color(1, 1, 1) if not btn.disabled else Color(0.5, 0.5, 0.5)

	if my_team != -1:
		var t = nm._get_team_config(my_team)
		var tname: String = t.get("team_name", "Team %d" % my_team)
		var c_arr = t.get("color", null)
		status_lbl.text = "You are on %s!\nWaiting for others... (%d/%d)" % [tname, total, mp]
		if c_arr != null:
			status_lbl.add_theme_color_override("font_color", Color(c_arr[0], c_arr[1], c_arr[2]))
		else:
			status_lbl.add_theme_color_override("font_color", Color.WHITE)
	else:
		status_lbl.text = "Pick your team!\nPlayers joined: %d/%d" % [total, mp]
		status_lbl.add_theme_color_override("font_color", Color.WHITE)

func _on_team_btn_pressed(team_id: int) -> void:
	nm.rpc_claim_team.rpc(team_id)

func _on_discovery_status(message: String) -> void:
	status_lbl.text = message
	status_lbl.add_theme_color_override("font_color", Color.YELLOW)
	for btn in _team_buttons.values():
		btn.disabled = true

func _on_game_started() -> void:
	queue_free()
