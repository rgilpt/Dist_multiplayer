extends Area2D

## The team this zone belongs to. 1 = Blue, 2 = Red.
@export var team_id: int = 1

@onready var visual: Polygon2D = $Visual

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if visual:
		var nm := get_node_or_null("/root/Main/NetworkManager")
		var c_arr = nm._get_team_config(team_id).get("color", null) if nm else null
		if c_arr != null:
			visual.color = Color(c_arr[0], c_arr[1], c_arr[2], 0.35)
		else:
			visual.color = Color(0.2, 0.5, 1.0, 0.35) if team_id == 1 else Color(1.0, 0.2, 0.2, 0.35)

func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	# Poll every frame so we don't miss the entry when position is set directly
	for body in get_overlapping_bodies():
		_try_score(body)

func _on_body_entered(body: Node2D) -> void:
	if not multiplayer.is_server():
		return
	if not body.is_in_group("player"):
		return
	var nm: Node = get_node("/root/Main/NetworkManager")
	var player_team: int = nm.peer_teams.get(int(body.name), -1)
	if player_team == team_id:
		body.rpc_refill_ammo.rpc()
	_try_score(body)

func _try_score(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	var enemy_flag_team: int = body.carried_flag_team
	if enemy_flag_team == -1 or enemy_flag_team == team_id:
		return

	var nm: Node = get_node("/root/Main/NetworkManager")
	var player_team: int = nm.peer_teams.get(int(body.name), -1)
	if player_team != team_id:
		return
	if not nm.flags_at_home.get(team_id, false):
		return

	# Score — clear the flag first so the poll won't double-score
	body.rpc_set_flag.rpc(-1)
	body.score += 1
	body.rpc_sync_score.rpc(body.score)
	nm.score_for_team(team_id)
	nm.respawn_flag(enemy_flag_team)
