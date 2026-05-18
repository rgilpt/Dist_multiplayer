extends Control

@onready var status_lbl: Label = $Panel/VBox/Status
@onready var players_lbl: Label = $Panel/VBox/Players
@onready var teams_lbl: Label = $Panel/VBox/Teams
@onready var scores_lbl: Label = $Panel/VBox/Scores
@onready var timer_lbl: Label = $Panel/VBox/Timer
@onready var start_btn: Button = $Panel/VBox/StartBtn

var nm: Node = null

func _ready():
	await get_tree().process_frame
	nm = get_node("/root/Main/NetworkManager")
	if nm == null:
		printerr("ServerView: NetworkManager not found!")
		return

	nm.team_data_updated.connect(_on_team_data_updated)
	nm.game_started.connect(_on_game_started)
	nm.game_over.connect(_on_game_over)

	start_btn.pressed.connect(_on_start_pressed)
	start_btn.visible = false  # only show if server wants to force start

	_update_status("Waiting for players to connect...")

func _process(_delta: float) -> void:
	if nm == null:
		return
	# Update timer display
	if nm.is_game_active:
		var mins := int(nm.game_timer) / 60
		var secs := int(nm.game_timer) % 60
		timer_lbl.text = "Time: %02d:%02d" % [mins, secs]
		scores_lbl.text = "Blue: %d  |  Red: %d" % [nm.score_team_a, nm.score_team_b]
	# Update connected players
	var peer_count = nm.peer_teams.size()
	players_lbl.text = "Players connected: %d/4" % peer_count

func _on_team_data_updated(blue: int, red: int, _your_team: int) -> void:
	teams_lbl.text = "Blue Team: %d/2   Red Team: %d/2" % [blue, red]
	var total := blue + red
	_update_status("Team selection in progress... (%d/4 picked)" % total)
	# Show force start button once at least 2 players have picked
	start_btn.visible = (total >= 2)

func _on_start_pressed() -> void:
	# Force start even if not all 4 players picked
	print("Server force-starting game...")
	nm.rpc_begin_game.rpc()

func _on_game_started() -> void:
	_update_status("Game in progress!")
	start_btn.visible = false
	timer_lbl.visible = true
	scores_lbl.visible = true

func _on_game_over() -> void:
	_update_status("Game Over!\nBlue: %d  |  Red: %d" % [nm.score_team_a, nm.score_team_b])
	timer_lbl.visible = false

func _update_status(text: String) -> void:
	if status_lbl:
		status_lbl.text = text
