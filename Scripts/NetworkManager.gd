extends Node
class_name NetworkManager

var _peer: ENetMultiplayerPeer
var has_flag: bool = false
var flag_instance: Node2D = null
var flag_position: Vector2 = Vector2.ZERO

var score_team_a: int = 0
var score_team_b: int = 0

var team_counts: Dictionary = {0: 0, 1: 0}
var peer_teams: Dictionary = {}

var is_game_active: bool = false
var game_timer: float = 180.0

var server_address: String = "127.0.0.1"
var server_port: int = 7777
var is_host: bool = false
var max_peers: int = 4

signal flag_spawned
signal flag_picked_up
signal flag_scored
signal game_over
signal all_players_joined
signal team_data_updated(blue_count: int, red_count: int, your_team: int)
signal game_started

var _initialized: bool = false
var player_scene = preload("res://Scenes/Player.tscn")

@onready var players: Node2D = $"../Players"
@onready var team_manager = $"../TeamManager"
#@onready var level_builder = $"../LevelBuilder"
var level_builder = null
func _ready():
	if _initialized:
		print("WARNING: _ready() called twice, skipping.")
		return
	_initialized = true

	# Debug: print full tree to find level_builder
	print("NetworkManager parent: ", get_parent().name)
	print("level_builder onready: ", level_builder)
	for child in get_parent().get_children():
		print("  sibling: ", child.name, " (", child.get_class(), ")")
		for grandchild in child.get_children():
			print("    child: ", grandchild.name, " script: ", grandchild.get_script())

	var args := OS.get_cmdline_args()

	if "--server" in args:
		print("Initializing as SERVER...")
		is_host = true
		_peer = ENetMultiplayerPeer.new()
		var error: Error = _peer.create_server(server_port, max_peers)
		if error != OK:
			printerr("Server creation failed: ", error)
			return
		multiplayer.multiplayer_peer = _peer
		_peer.peer_connected.connect(_on_peer_connected)
		_peer.peer_disconnected.connect(_on_peer_disconnected)
		print("Host ready. Max peers: ", max_peers)

	elif "--client" in args:
		var addr_index := args.find("--address")
		if addr_index != -1 and addr_index + 1 < args.size():
			server_address = args[addr_index + 1]
		_peer = ENetMultiplayerPeer.new()
		var error: Error = _peer.create_client(server_address, server_port)
		if error != OK:
			printerr("Client connection failed: ", error)
			return
		multiplayer.multiplayer_peer = _peer
		multiplayer.connected_to_server.connect(_on_connected_to_server)
		print("Connecting to ", server_address, ":", server_port)
	else:
		printerr("No --server or --client argument provided.")

func _process(delta: float) -> void:
	if not is_game_active:
		return
	if not multiplayer.is_server():
		return
	game_timer -= delta
	if game_timer <= 0:
		_end_game()

func _get_level_builder():
	if level_builder == null:
		# Walk the whole tree looking for LevelBuilderClaude
		level_builder = _find_node_by_script(get_parent(), "LevelBuilderClaude")
		if level_builder == null:
			printerr("LevelBuilderClaude not found anywhere!")
	return level_builder

func _find_node_by_script(node: Node, class_name_str: String) -> Node:
	if node.get_script() and node.get_script().get_global_name() == class_name_str:
		return node
	for child in node.get_children():
		var result = _find_node_by_script(child, class_name_str)
		if result:
			return result
	return null


func _on_connected_to_server() -> void:
	multiplayer.connected_to_server.disconnect(_on_connected_to_server)
	print("Connected! My ID: ", multiplayer.get_unique_id())

func _on_peer_connected(id: int) -> void:
	print("Peer connected: ", id)
	for child in players.get_children():
		var existing_id := int(child.name)
		if existing_id != id:
			rpc_id(id, "spawn_remote_player", existing_id, child.position)
	rpc_id(id, "rpc_update_team_counts", team_counts[0], team_counts[1], -1, -1)

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: ", id)
	if players.has_node(str(id)):
		players.get_node(str(id)).queue_free()
	if id in peer_teams:
		team_counts[peer_teams[id]] -= 1
		peer_teams.erase(id)
		rpc("rpc_update_team_counts", team_counts[0], team_counts[1], -1, -1)


# --- Spawning ---

func _get_spawn_position(team_id: int) -> Vector2:
	print("level_builder: ", level_builder)
	print("blue_spawns size: ", level_builder.blue_spawns.size() if level_builder else "NULL")
	print("red_spawns size: ", level_builder.red_spawns.size() if level_builder else "NULL")
	
	var lb = _get_level_builder()
	print("level_builder: ", lb)
	if lb == null:
		return Vector2(300, 300) if team_id == 0 else Vector2(3800, 3800)
	var spawns: Array = lb.blue_spawns if team_id == 0 else lb.red_spawns
	print("spawns for team ", team_id, ": ", spawns)
	if spawns.is_empty():
		return Vector2(300, 300) if team_id == 0 else Vector2(3800, 3800)
	var idx := _count_team_players(team_id)
	return spawns[idx % spawns.size()]

func _count_team_players(team_id: int) -> int:
	var count := 0
	for pid in peer_teams:
		if peer_teams[pid] == team_id and players.has_node(str(pid)):
			count += 1
	return count

func _spawn_local_player() -> void:
	var my_id := multiplayer.get_unique_id()
	if players.has_node(str(my_id)):
		print("Local player already spawned, skipping.")
		return
	var my_team = peer_teams.get(my_id, -1)
	var spawn_pos := _get_spawn_position(my_team)
	var player = player_scene.instantiate()
	player.name = str(my_id)
	player.position = spawn_pos
	player.is_player_one = (my_id == 1)
	player.is_local_player = true
	players.add_child(player)
	player.set_multiplayer_authority(my_id)
	print("Spawned local player at: ", spawn_pos, " team: ", my_team)
	rpc("spawn_remote_player", my_id, spawn_pos)

@rpc("any_peer", "call_remote", "reliable")
func spawn_remote_player(peer_id: int, spawn_pos: Vector2 = Vector2(300, 300)) -> void:
	if peer_id == multiplayer.get_unique_id():
		return
	if players.has_node(str(peer_id)):
		return
	print("Spawning remote copy of peer: ", peer_id, " at ", spawn_pos)
	var player = player_scene.instantiate()
	player.name = str(peer_id)
	player.position = spawn_pos
	player.is_player_one = (peer_id == 1)
	player.is_local_player = false
	players.add_child(player)
	player.set_multiplayer_authority(peer_id)

# Called on clients by server to trigger their own spawn
@rpc("authority", "call_remote", "reliable")
func _rpc_request_spawn() -> void:
	print("Server requested spawn for me")
	call_deferred("_spawn_local_player")


# --- Team Selection ---

@rpc("any_peer", "call_local", "reliable")
func rpc_claim_team(team_id: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = multiplayer.get_unique_id()
	if peer_id in peer_teams:
		return
	if team_counts.get(team_id, 0) >= 2:
		return
	peer_teams[peer_id] = team_id
	team_counts[team_id] += 1
	print("Peer ", peer_id, " joined team ", "Blue" if team_id == 0 else "Red")
	if team_manager:
		team_manager.peer_teams[peer_id] = team_id
	# Broadcast to ALL peers including sender
	rpc("rpc_update_team_counts", team_counts[0], team_counts[1], peer_id, team_id)
	if peer_teams.size() >= 4:
		# Use call_remote so server doesn't run rpc_begin_game twice
		# Server calls _begin_game locally, clients receive via RPC
		_begin_game_server()

@rpc("any_peer", "call_local", "reliable")
func rpc_update_team_counts(blue: int, red: int, joining_peer: int, joining_team: int) -> void:
	team_counts[0] = blue
	team_counts[1] = red
	if joining_peer != -1:
		peer_teams[joining_peer] = joining_team
		if team_manager:
			team_manager.peer_teams[joining_peer] = joining_team
	var my_team = peer_teams.get(multiplayer.get_unique_id(), -1)
	emit_signal("team_data_updated", blue, red, my_team)

# Server-only: starts the game and tells clients
func _begin_game_server() -> void:
	if not multiplayer.is_server():
		return
	print("Server starting game...")
	_start_game()
	emit_signal("game_started")
	# Tell each client to start game and spawn
	rpc("_rpc_begin_game_client")
	# Server has no player to spawn

@rpc("authority", "call_remote", "reliable")
func _rpc_begin_game_client() -> void:
	print("Client received game start")
	emit_signal("game_started")
	_start_game()
	call_deferred("_spawn_local_player")


# --- Game Logic ---

func _start_game() -> void:
	is_game_active = true
	game_timer = 180.0
	score_team_a = 0
	score_team_b = 0
	if multiplayer.is_server():
		spawn_flag_to_position(Vector2(2048, 2048))
		rpc("rpc_update_scores", 0, 0)

func _end_game() -> void:
	is_game_active = false
	rpc("rpc_show_game_over")
	print("Game Over! Blue: ", score_team_a, " Red: ", score_team_b)

func spawn_flag_to_position(pos: Vector2) -> void:
	flag_position = pos
	has_flag = false
	var flag_scene = preload("res://Scenes/Flag.tscn")
	if flag_instance:
		flag_instance.queue_free()
	flag_instance = flag_scene.instantiate()
	flag_instance.global_position = pos
	add_child(flag_instance)
	flag_instance.add_to_group("flag")
	rpc("rpc_spawn_flag", pos)

func remove_flag() -> void:
	if flag_instance:
		flag_instance.queue_free()
		flag_instance = null
	has_flag = false
	rpc("rpc_remove_flag")

func respawn_flag() -> void:
	spawn_flag_to_position(flag_position)
	rpc("rpc_respawn_flag", flag_position)


# --- RPCs ---

@rpc("any_peer", "call_remote", "reliable")
func rpc_update_scores(s_a: int, s_b: int) -> void:
	score_team_a = s_a
	score_team_b = s_b

@rpc("any_peer", "call_remote", "reliable")
func rpc_spawn_flag(pos: Vector2) -> void:
	if not flag_instance:
		var flag_scene = preload("res://Scenes/Flag.tscn")
		flag_instance = flag_scene.instantiate()
		flag_instance.global_position = pos
		add_child(flag_instance)
		flag_instance.add_to_group("flag")
	else:
		flag_instance.global_position = pos

@rpc("any_peer", "call_remote", "reliable")
func rpc_remove_flag() -> void:
	if flag_instance:
		flag_instance.queue_free()
		flag_instance = null
	has_flag = false

@rpc("any_peer", "call_remote", "reliable")
func rpc_respawn_flag(pos: Vector2) -> void:
	spawn_flag_to_position(pos)

@rpc("any_peer", "call_remote", "reliable")
func rpc_show_game_over() -> void:
	print("Game Over!")
	emit_signal("game_over")
