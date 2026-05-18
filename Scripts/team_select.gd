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
	team_blue_btn.text = "Team Blue\n%d/2" % team_counts[0]
	team_red_btn.text = "Team Red\n%d/2" % team_counts[1]

	# Disable button if team is full OR player already picked
	team_blue_btn.disabled = (team_counts[0] >= 2) or (my_team != -1)
	team_red_btn.disabled = (team_counts[1] >= 2) or (my_team != -1)

	# Update button colors
	team_blue_btn.modulate = Color(0.4, 0.6, 1.0) if not team_blue_btn.disabled else Color(0.5, 0.5, 0.5)
	team_red_btn.modulate = Color(1.0, 0.4, 0.4) if not team_red_btn.disabled else Color(0.5, 0.5, 0.5)

	if my_team == 0:
		status_lbl.text = "You are on Team Blue!\nWaiting for others... (%d/4)" % (team_counts[0] + team_counts[1])
		status_lbl.add_theme_color_override("font_color", Color.DODGER_BLUE)
	elif my_team == 1:
		status_lbl.text = "You are on Team Red!\nWaiting for others... (%d/4)" % (team_counts[0] + team_counts[1])
		status_lbl.add_theme_color_override("font_color", Color.TOMATO)
	else:
		status_lbl.text = "Pick your team!\nPlayers joined: %d/4" % (team_counts[0] + team_counts[1])
		status_lbl.add_theme_color_override("font_color", Color.WHITE)

func _on_team_blue_pressed() -> void:
	print("Claiming Team Blue...")
	nm.rpc_claim_team.rpc(0)

func _on_team_red_pressed() -> void:
	print("Claiming Team Red...")
	nm.rpc_claim_team.rpc(1)

func _on_game_started() -> void:
	print("Game started! Closing TeamSelect.")
	queue_free()
