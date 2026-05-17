extends Node

class_name NetworkManager

# NetworkManager - Handles multiplayer setup and game state for 2v2
var _peer: ENetMultiplayerPeer
var has_flag: bool = false
var flag_instance: Node2D = null
var flag_position: Vector2 = Vector2.ZERO

# Team scores (Team A vs Team B)
var score_team_a: int = 0
var score_team_b: int = 0

# Player team assignments: peer_id -> team (0 = A, 1 = B)
var player_team: Dictionary = {}
# Team members per team
var team_a_members: Array[int] = []
var team_b_members: Array[int] = []

var is_game_active: bool = false
var game_timer: float = 180.0  # 3 minutes per game

# Connection settings
var server_address: String = "127.0.0.1"
var server_port: int = 7777
var is_host: bool = false
var max_peers: int = 4

signal flag_spawned
signal flag_picked_up
signal flag_scored
signal game_over
signal all_players_joined
signal connected_as_team(assigned_team: int)

var _initialized: bool = false
var player_scene = preload("res://Scenes/Player.tscn")
@onready var players: Node2D = $"../Players"

func _ready():
	if _initialized:
		print("WARNING: _ready() called twice, skipping.")
		return
	_initialized = true
	var args := OS.get_cmdline_args()
	
	#args.append("--client")
	#args.append("127.0.0.1")
	args.append("--server")
	
	 


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
		call_deferred("_spawn_local_player")

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

func _on_connected_to_server() -> void:
	# Disconnect immediately so this can never fire twice
	multiplayer.connected_to_server.disconnect(_on_connected_to_server)
	print("Connected! My ID: ", multiplayer.get_unique_id())
	call_deferred("_spawn_local_player")

func _spawn_local_player(my_id=null, spawn_pos=Vector2(250,250)) -> void:
	if my_id == null:
		my_id = multiplayer.get_unique_id()
	# Guard: don't spawn if already exists
	if has_node(str(my_id)):
		print("Local player already spawned, skipping.")
		return
	var player = player_scene.instantiate()
	player.name = str(my_id)
	player.position = spawn_pos
	player.is_player_one = (my_id == 1)
	player.is_local_player = true
	
	players.add_child(player)
	player.set_multiplayer_authority(my_id)
	print("Spawned local player with id: ", my_id)
	rpc("spawn_remote_player", my_id)

@rpc("any_peer", "call_remote", "reliable")
func spawn_remote_player(peer_id: int) -> void:
	# Never spawn a remote copy of our own local player
	if peer_id == multiplayer.get_unique_id():
		return
	# Don't spawn if already exists
	if has_node(str(peer_id)):
		return
	print("Spawning remote copy of peer: ", peer_id)
	var player = player_scene.instantiate()
	player.name = str(peer_id)
	player.is_player_one = (peer_id == 1)
	add_child(player)
	player.set_multiplayer_authority(peer_id)

func _on_peer_connected(id: int) -> void:
	print("Peer connected: ", id)
	# Tell the newly connected peer about OUR player (not theirs — they spawn themselves)
	rpc_id(id, "spawn_remote_player", multiplayer.get_unique_id())

	# Also tell them about any OTHER players already in the game
	for existing_id in player_team.keys():
		if existing_id != id:
			rpc_id(id, "spawn_remote_player", existing_id)

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: ", id)
	# Remove their player from our scene
	if has_node(str(id)):
		get_node(str(id)).queue_free()

func _start_game():
	is_game_active = true
	game_timer = 180.0
	score_team_a = 0
	score_team_b = 0
	spawn_flag_to_position(Vector2(0, 0))
	rpc("rpc_update_scores", 0, 0)

func _end_game():
	is_game_active = false
	rpc("rpc_show_game_over")
	print("Game Over! Team A: ", score_team_a, " Team B: ", score_team_b)

func spawn_flag_to_position(pos: Vector2):
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

func remove_flag():
	if flag_instance:
		flag_instance.queue_free()
		flag_instance = null
	has_flag = false
	rpc("rpc_remove_flag")

func respawn_flag():
	spawn_flag_to_position(Vector2(0, 0))
	rpc("rpc_respawn_flag")

# --- RPC Functions ---

@rpc("authority", "call_remote", "reliable")
func _rpc_assign_team(team: int) -> void:
	print("Client assigned to team: ", "A" if team == 0 else "B")
	rpc("rpc_update_team_state", player_team, team_a_members, team_b_members)
	# Emit to all clients
	emit_signal("connected_as_team", team)

@rpc("any_peer", "call_remote", "reliable")
func rpc_assign_team(team: int) -> void:
	# This should not be called directly; used by _rpc_assign_team
	pass

@rpc("any_peer", "call_remote", "reliable")
func rpc_update_team_state(team_map: Dictionary, team_a: Array, team_b: Array) -> void:
	player_team = team_map
	team_a_members = team_a
	team_b_members = team_b
	print("Updated teams: A=", team_a, " B=", team_b)

@rpc("any_peer", "call_remote", "reliable")
func rpc_update_scores(s_a: int, s_b: int) -> void:
	score_team_a = s_a
	score_team_b = s_b

@rpc("any_peer", "call_remote", "reliable")
func rpc_start_game() -> void:
	is_game_active = true
	game_timer = 180.0
	score_team_a = 0
	score_team_b = 0
	spawn_flag_to_position(Vector2(0, 0))

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
	remove_flag()

@rpc("any_peer", "call_remote", "reliable")
func rpc_respawn_flag() -> void:
	spawn_flag_to_position(Vector2(0, 0))

@rpc("any_peer", "call_remote", "reliable")
func rpc_show_game_over() -> void:
	print("Game Over!")
	emit_signal("game_over")
