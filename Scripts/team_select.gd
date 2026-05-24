extends Control

@onready var status_lbl: Label = $Content/Status
@onready var team_blue_btn: Button = $Content/HBoxContainer/TeamBlue
@onready var team_red_btn: Button = $Content/HBoxContainer/TeamRed

var my_team: int = -1
var team_counts: Array = [0, 0]
var nm: Node = null

func _ready():
	# Wait one frame so NetworkManager is fully initialized
	await get_tree().process_frame

	nm = get_node("/root/Main/NetworkManager")
	if nm == null:
		printerr("TeamSelect: NetworkManager not found!")
		return

	nm.team_data_updated.connect(_on_team_data_updated)
	nm.game_started.connect(_on_game_started)
	nm.game_mode_updated.connect(update_ui)
	nm.discovery_status.connect(_on_discovery_status)

	team_blue_btn.pressed.connect(_on_team_blue_pressed)
	team_red_btn.pressed.connect(_on_team_red_pressed)

	update_ui()
	print("TeamSelect ready. Waiting for team selection...")

func _on_team_data_updated(blue: int, red: int, your_team: int) -> void:
	print("Team data updated: Blue=", blue, " Red=", red, " MyTeam=", your_team)
	team_counts = [blue, red]
	my_team = your_team
	update_ui()

func update_ui() -> void:
	var mpt: int = nm.max_per_team if nm else 2
	var mp: int = nm.max_players if nm else 4
	var total = team_counts[0] + team_counts[1]

	team_blue_btn.text = "Team Blue\n%d/%d" % [team_counts[0], mpt]
	team_red_btn.text = "Team Red\n%d/%d" % [team_counts[1], mpt]

	# Disable button if team is full OR player already picked
	team_blue_btn.disabled = (team_counts[0] >= mpt) or (my_team != -1)
	team_red_btn.disabled = (team_counts[1] >= mpt) or (my_team != -1)

	# Update button colors
	team_blue_btn.modulate = Color(0.4, 0.6, 1.0) if not team_blue_btn.disabled else Color(0.5, 0.5, 0.5)
	team_red_btn.modulate = Color(1.0, 0.4, 0.4) if not team_red_btn.disabled else Color(0.5, 0.5, 0.5)

	if my_team == 1:
		status_lbl.text = "You are on Team Blue!\nWaiting for others... (%d/%d)" % [total, mp]
		status_lbl.add_theme_color_override("font_color", Color.DODGER_BLUE)
	elif my_team == 2:
		status_lbl.text = "You are on Team Red!\nWaiting for others... (%d/%d)" % [total, mp]
		status_lbl.add_theme_color_override("font_color", Color.TOMATO)
	else:
		status_lbl.text = "Pick your team!\nPlayers joined: %d/%d" % [total, mp]
		status_lbl.add_theme_color_override("font_color", Color.WHITE)

func _on_team_blue_pressed() -> void:
	print("Claiming Team Blue...")
	nm.rpc_claim_team.rpc(1)

func _on_team_red_pressed() -> void:
	print("Claiming Team Red...")
	nm.rpc_claim_team.rpc(2)

func _on_discovery_status(message: String) -> void:
	status_lbl.text = message
	status_lbl.add_theme_color_override("font_color", Color.YELLOW)
	# Disable team buttons until actually connected
	team_blue_btn.disabled = true
	team_red_btn.disabled = true

func _on_game_started() -> void:
	print("Game started! Closing TeamSelect.")
	queue_free()
