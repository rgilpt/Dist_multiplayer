extends Control

@onready var status_lbl: Label = $Content/Status
@onready var btn_container: VBoxContainer = $Content/TeamList
@onready var title_lbl: Label = $Content/Label

const AMMO_COOLDOWN: float = 40.0
var _ammo_cooldown: float = 0.0
var _observer_btn: Button = null
var _is_observer: bool = false

var my_team: int = -1
var team_counts: Dictionary = {}
var nm: Node = null
var _connected: bool = false

var _team_buttons: Dictionary = {}  # team_id -> Button

func _ready():
	await get_tree().process_frame

	nm = get_node("/root/Main/NetworkManager")
	if nm == null:
		printerr("TeamSelect: NetworkManager not found!")
		return

	_build_team_buttons()
	_set_buttons_enabled(false)
	status_lbl.text = "Connecting to server..."

	nm.team_data_updated.connect(_on_team_data_updated)
	nm.game_started.connect(_on_game_started)
	nm.game_mode_updated.connect(update_ui)
	nm.discovery_status.connect(_on_discovery_status)
	multiplayer.connected_to_server.connect(_on_connected_to_server)

	update_ui()

func _process(delta: float) -> void:
	if not _is_observer or _observer_btn == null:
		return
	if _ammo_cooldown > 0.0:
		_ammo_cooldown -= delta
		_observer_btn.disabled = true
		_observer_btn.text = "Drop Ammo (%ds)" % int(ceil(_ammo_cooldown))
	else:
		_ammo_cooldown = 0.0
		_observer_btn.disabled = false
		_observer_btn.text = "Drop Ammo"

func _build_team_buttons() -> void:
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
	if _is_observer:
		return
	var mpt: int = nm.max_per_team if nm else 2
	var mp: int = nm.max_players if nm else 4
	var total: int = 0
	for cnt in team_counts.values():
		total += cnt

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
		btn.disabled = not _connected or is_full or (my_team != -1)
		btn.visible = not (lock_empty and count == 0)
		var c_arr = t.get("color", null)
		if c_arr != null:
			btn.modulate = Color(c_arr[0], c_arr[1], c_arr[2]) if not btn.disabled else Color(0.5, 0.5, 0.5)
		else:
			btn.modulate = Color(1, 1, 1) if not btn.disabled else Color(0.5, 0.5, 0.5)

	if not _connected:
		status_lbl.text = "Connecting to server..."
		status_lbl.add_theme_color_override("font_color", Color.YELLOW)
	elif my_team != -1:
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

func _on_connected_to_server() -> void:
	_connected = true
	update_ui()

func _set_buttons_enabled(enabled: bool) -> void:
	for btn in _team_buttons.values():
		btn.disabled = not enabled

func _on_team_btn_pressed(team_id: int) -> void:
	if multiplayer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	nm.rpc_claim_team.rpc(team_id)

func _on_discovery_status(message: String) -> void:
	status_lbl.text = message
	status_lbl.add_theme_color_override("font_color", Color.YELLOW)
	for btn in _team_buttons.values():
		btn.disabled = true

func _on_game_started() -> void:
	var mpt: int = nm.max_per_team if nm else 2
	var on_full_team: bool = my_team != -1 and team_counts.get(my_team, 0) >= mpt
	if on_full_team:
		queue_free()
		return

	# Observer mode: hide team selection, show ammo drop panel
	_is_observer = true
	title_lbl.text = "Observer Mode"
	btn_container.visible = false

	status_lbl.text = "You're watching!\nDrop ammo onto the map to help out."
	status_lbl.add_theme_color_override("font_color", Color.YELLOW)

	_observer_btn = Button.new()
	_observer_btn.text = "Drop Ammo"
	_observer_btn.custom_minimum_size = Vector2(200, 60)
	_observer_btn.pressed.connect(_on_observer_ammo_pressed)
	$Content.add_child(_observer_btn)

func _on_observer_ammo_pressed() -> void:
	if nm:
		nm.rpc_request_ammo_drop.rpc_id(1)
	_ammo_cooldown = AMMO_COOLDOWN
