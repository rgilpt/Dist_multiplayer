extends Control

@onready var status_lbl: Label = $Panel/VBox/Status
@onready var players_lbl: Label = $Panel/VBox/Players
@onready var teams_lbl: Label = $Panel/VBox/Teams
@onready var scores_lbl: Label = $Panel/VBox/Scores
@onready var timer_lbl: Label = $Panel/VBox/Timer
@onready var start_btn: Button = $Panel/VBox/StartBtn
@onready var ammo_btn: Button = $Panel/VBox/AmmoDrop
@onready var ammo_cooldown_lbl: Label = $Panel/VBox/AmmoCooldown

const AMMO_COOLDOWN: float = 40.0
var _ammo_cooldown: float = 0.0

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
	ammo_btn.pressed.connect(_on_ammo_drop_pressed)
	start_btn.visible = false
	ammo_btn.visible = false
	ammo_cooldown_lbl.visible = false
	scores_lbl.visible = false
	timer_lbl.visible = false

	_update_status("— LOBBY —\nWaiting for 2 full teams...")

func _process(delta: float) -> void:
	if nm == null:
		return

	var peer_count: int = nm.peer_teams.size()
	players_lbl.text = "Players connected: %d/%d" % [peer_count, nm.max_players]

	if nm.is_game_active:
		var mins := int(nm.game_timer) / 60
		var secs := int(nm.game_timer) % 60
		timer_lbl.text = "Time: %02d:%02d" % [mins, secs]

		var parts: Array = []
		for tid in nm.scores:
			if nm.team_counts.get(tid, 0) == 0:
				continue
			var cfg: Dictionary = nm._get_team_config(tid)
			parts.append("%s: %d" % [cfg.get("team_name", "Team %d" % tid), nm.scores[tid]])
		scores_lbl.text = "  |  ".join(parts)

		# Ammo drop cooldown countdown
		if _ammo_cooldown > 0.0:
			_ammo_cooldown -= delta
			ammo_btn.disabled = true
			ammo_btn.text = "Drop Ammo (%ds)" % int(ceil(_ammo_cooldown))
		else:
			_ammo_cooldown = 0.0
			ammo_btn.disabled = false
			ammo_btn.text = "Drop Ammo on Map"

func _on_team_data_updated(counts: Dictionary, _your_team: int) -> void:
	var mpt: int = nm.max_per_team
	var parts: Array = []
	var total: int = 0
	var full_teams: int = 0
	for tid in counts:
		if counts[tid] == 0:
			continue
		var cfg: Dictionary = nm._get_team_config(tid)
		var tname: String = cfg.get("team_name", "Team %d" % tid)
		parts.append("%s: %d/%d" % [tname, counts[tid], mpt])
		total += counts[tid]
		if counts[tid] >= mpt:
			full_teams += 1
	teams_lbl.text = "   ".join(parts)

	if full_teams >= 2:
		_update_status("— LOBBY —\nReady! Starting...")
		start_btn.visible = false
	else:
		var needed: int = 2 - full_teams
		_update_status("— LOBBY —\nNeed %d more full team(s) to start" % needed)
		# Show force-start once at least one player per team exists
		start_btn.visible = parts.size() >= 2

func _on_start_pressed() -> void:
	nm._begin_game_server()

func _on_ammo_drop_pressed() -> void:
	nm.spawn_ammo_drop()
	_ammo_cooldown = AMMO_COOLDOWN

func _on_game_started() -> void:
	_update_status("Game in progress!")
	start_btn.visible = false
	timer_lbl.visible = true
	scores_lbl.visible = true
	ammo_btn.visible = true
	ammo_cooldown_lbl.visible = false  # cooldown shown in button text

func _on_game_over() -> void:
	ammo_btn.visible = false
	var parts: Array = []
	for tid in nm.scores:
		if nm.team_counts.get(tid, 0) == 0:
			continue
		var cfg: Dictionary = nm._get_team_config(tid)
		parts.append("%s: %d" % [cfg.get("team_name", "Team %d" % tid), nm.scores[tid]])
	_update_status("— GAME OVER —\n" + "  |  ".join(parts))
	timer_lbl.visible = false

func _update_status(text: String) -> void:
	if status_lbl:
		status_lbl.text = text
