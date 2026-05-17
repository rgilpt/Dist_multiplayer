extends Control
@onready var bg: ColorRect = $Background
@onready var status_lbl: Label = $Content/Status
@onready var team_blue_btn: Button = $Content/HBoxContainer/TeamBlue
@onready var team_red_btn: Button = $Content/HBoxContainer/TeamRed
@export var team_manager: TeamManager = null
@export var network_manager: NetworkManager = null
var my_team: int = -1  # 0=Blue, 1=Red
var team_counts: Array = [0, 0]
func _ready():
	bg.color = Color(0,0,0,0)
	update_ui()
	# Connect to NetworkManager signals
	#network_manager.team_data_updated.connect(_on_team_data_updated)
	#network_manager.game_started.connect(_on_game_started)
func _on_team_data_updated(team_a: int, team_b: int, your_team: int):
	team_counts = [team_a, team_b]
	my_team = your_team
	update_ui()
func update_ui():
	team_blue_btn.text = "Team A: %d/2" % team_counts[0]
	team_red_btn.text = "Team B: %d/2" % team_counts[1]
	
	# Disable buttons if team is full
	team_blue_btn.disabled = (team_counts[0] >= 2)
	team_red_btn.disabled = (team_counts[1] >= 2)
	
	if my_team == 0:
		status_lbl.text = "You are on Team A!"
		status_lbl.set("custom_colors/font_color", Color.DODGER_BLUE)
	elif my_team == 1:
		status_lbl.text = "You are on Team B!"
		status_lbl.set("custom_colors/font_color", Color.RED)
	elif team_counts[0] + team_counts[1] < 4:
		status_lbl.text = "Waiting for more players..."
	else:
		status_lbl.text = "Waiting for game start..."
func _on_team_blue_pressed():
	_network_claim_team(0)
func _on_team_red_pressed():
	_network_claim_team(1)
func _network_claim_team(team_id: int):
	if (my_team != -1): return # Already picked
	get_node("/root/NetworkManager").rpc_claim_team(team_id)
func _on_game_started():
	queue_free()
