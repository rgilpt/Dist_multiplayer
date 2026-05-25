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
		var parts: Array = []
		for tid in nm.scores:
			if nm.team_counts.get(tid, 0) == 0:
				continue
			var cfg: Dictionary = nm._get_team_config(tid)
			var tname: String = cfg.get("team_name", "Team %d" % tid)
			parts.append("%s: %d" % [tname, nm.scores[tid]])
		scores_lbl.text = "  |  ".join(parts)
	# Update connected players
	var peer_count = nm.peer_teams.size()
	players_lbl.text = "Players connected: %d/%d" % [peer_count, nm.max_players]

func _on_team_data_updated(counts: Dictionary, _your_team: int) -> void:
	var mpt: int = nm.max_per_team
	var parts: Array = []
	var total: int = 0
	var teams_with_players: int = 0
	for tid in counts:
		if counts[tid] == 0:
			continue
		var cfg: Dictionary = nm._get_team_config(tid)
		var tname: String = cfg.get("team_name", "Team %d" % tid)
		parts.append("%s: %d/%d" % [tname, counts[tid], mpt])
		total += counts[tid]
		teams_with_players += 1
	teams_lbl.text = "   ".join(parts)
	_update_status("Team selection in progress... (%d/%d picked)" % [total, nm.max_players])
	start_btn.visible = teams_with_players >= 2

func _on_start_pressed() -> void:
	# Force start even if not all players have picked a team
	print("Server force-starting game...")
	nm._begin_game_server()

func _on_game_started() -> void:
	_update_status("Game in progress!")
	start_btn.visible = false
	timer_lbl.visible = true
	scores_lbl.visible = true

func _on_game_over() -> void:
	var parts: Array = []
	for tid in nm.scores:
		if nm.team_counts.get(tid, 0) == 0:
			continue
		var cfg: Dictionary = nm._get_team_config(tid)
		var tname: String = cfg.get("team_name", "Team %d" % tid)
		parts.append("%s: %d" % [tname, nm.scores[tid]])
	_update_status("Game Over!\n" + "  |  ".join(parts))
	timer_lbl.visible = false

func _update_status(text: String) -> void:
	if status_lbl:
		status_lbl.text = text
