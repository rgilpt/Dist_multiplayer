extends Area2D

## The team this zone belongs to. 1 = Blue, 2 = Red.
@export var team_id: int = 1

@onready var visual: Polygon2D = $Visual

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if visual:
		visual.color = Color(0.2, 0.5, 1.0, 0.35) if team_id == 1 else Color(1.0, 0.2, 0.2, 0.35)

func _on_body_entered(body: Node2D) -> void:
	if not multiplayer.is_server():
		return
	if not body.is_in_group("player"):
		return

	var nm: Node = get_node("/root/Main/NetworkManager")
	var player_team: int = nm.peer_teams.get(int(body.name), -1)

	# Player must be on this team's side
	if player_team != team_id:
		return

	# Classic CTF scoring rules:
	# 1. Player must be carrying the enemy's flag
	var enemy_flag_team: int = body.carried_flag_team
	if enemy_flag_team == -1 or enemy_flag_team == team_id:
		return

	# 2. Own flag must currently be at home (not stolen)
	if not nm.flags_at_home.get(team_id, false):
		return

	# All checks passed — score!
	body.rpc_set_flag.rpc(-1)           # remove flag from player on all peers
	body.score += 1
	body.rpc_sync_score.rpc(body.score)
	nm.score_for_team(team_id)
	nm.respawn_flag(enemy_flag_team)    # return the captured flag to enemy base
