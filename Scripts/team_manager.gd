extends Node
class_name TeamManager

# peer_id -> team (0=Blue, 1=Red)
var peer_teams: Dictionary = {}

func get_team(peer_id: int) -> int:
	return peer_teams.get(peer_id, -1)

func is_blue(peer_id: int) -> bool:
	return get_team(peer_id) == 0

func is_red(peer_id: int) -> bool:
	return get_team(peer_id) == 1

func get_team_members(team_id: int) -> Array:
	var members: Array = []
	for peer_id in peer_teams:
		if peer_teams[peer_id] == team_id:
			members.append(peer_id)
	return members

func get_blue_members() -> Array:
	return get_team_members(0)

func get_red_members() -> Array:
	return get_team_members(1)

func are_teams_full() -> bool:
	return get_blue_members().size() >= 2 and get_red_members().size() >= 2
