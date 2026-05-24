extends Node
class_name NetworkManager

var _peer: ENetMultiplayerPeer

# Classic CTF: two flags, one per team.
# flag_team_id 1 = Blue flag (at Blue HQ), 2 = Red flag (at Red HQ)
const FLAG_HOME_POSITIONS: Dictionary = {
	1: Vector2(384, 224),    # inside Blue HQ, upper area
	2: Vector2(3184, 5344),  # inside Red HQ, lower area
}
var flag_instances: Dictionary = {}        # flag_team_id -> Node2D (null if carried)
var flags_at_home: Dictionary = {1: true, 2: true}  # flag_team_id -> bool

var score_team_a: int = 0
var score_team_b: int = 0

var team_counts: Dictionary = {1: 0, 2: 0}
var peer_teams: Dictionary = {}

var is_game_active: bool = false
var game_timer: float = 180.0

var server_address: String = "127.0.0.1"
var server_port: int = 7777
var is_host: bool = false
var max_peers: int = 4

var max_players: int = 4
var max_per_team: int = 2

signal flag_spawned
signal flag_picked_up
signal flag_scored
signal game_over
signal all_players_joined
signal team_data_updated(blue_count: int, red_count: int, your_team: int)
signal game_started
signal game_mode_updated
signal discovery_status(message: String)

const DISCOVERY_PORT: int = 7778
const DISCOVERY_MSG: String = "DISCOVER_DIST"
const DISCOVERY_RESPONSE: String = "DIST_SERVER"
const DISCOVERY_INTERVAL: float = 1.0
const DISCOVERY_TIMEOUT: float = 10.0

var _discovery_udp: PacketPeerUDP = null
var _discovering: bool = false
var _discovery_timer: float = 0.0
var _discovery_elapsed: float = 0.0

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

	if "--1v1" in args:
		max_players = 2
		max_per_team = 1
		print("Game mode: 1v1")

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
		_start_discovery_listener()
		print("Host ready. Max peers: ", max_peers)

	elif "--client" in args:
		var addr_index := args.find("--address")
		if addr_index != -1 and addr_index + 1 < args.size():
			# Address provided explicitly — connect immediately
			server_address = args[addr_index + 1]
			_connect_to_server(server_address)
		else:
			# No address — discover server on local network
			_start_discovery_broadcast()
	else:
		printerr("No --server or --client argument provided.")

func _process(delta: float) -> void:
	_process_discovery(delta)
	if not is_game_active:
		return
	if not multiplayer.is_server():
		return
	game_timer -= delta
	if game_timer <= 0:
		_end_game()

# --- LAN Discovery ---

func _start_discovery_listener() -> void:
	_discovery_udp = PacketPeerUDP.new()
	var err := _discovery_udp.bind(DISCOVERY_PORT)
	if err != OK:
		printerr("Discovery listener failed to bind port ", DISCOVERY_PORT, ": ", err)
		_discovery_udp = null
		return
	print("Discovery listener active on port ", DISCOVERY_PORT)

func _start_discovery_broadcast() -> void:
	_discovery_udp = PacketPeerUDP.new()
	_discovery_udp.set_broadcast_enabled(true)
	# Bind to a reply port so the server knows where to send the response
	var err := _discovery_udp.bind(DISCOVERY_PORT + 1)
	if err != OK:
		printerr("Discovery broadcast socket failed: ", err, " — falling back to localhost")
		_discovery_udp = null
		_connect_to_server("127.0.0.1")
		return
	_discovering = true
	_discovery_elapsed = 0.0
	_discovery_timer = DISCOVERY_INTERVAL  # fire immediately on first frame
	emit_signal("discovery_status", "Searching for server on local network...")
	print("LAN discovery started")

func _connect_to_server(address: String) -> void:
	server_address = address
	_peer = ENetMultiplayerPeer.new()
	var error: Error = _peer.create_client(server_address, server_port)
	if error != OK:
		printerr("Client connection failed: ", error)
		return
	multiplayer.multiplayer_peer = _peer
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	print("Connecting to ", server_address, ":", server_port)

func _process_discovery(delta: float) -> void:
	if _discovery_udp == null:
		return

	if is_host:
		# Server: respond to any discovery broadcast
		while _discovery_udp.get_available_packet_count() > 0:
			var packet := _discovery_udp.get_packet()
			if packet.get_string_from_utf8() == DISCOVERY_MSG:
				var client_ip := _discovery_udp.get_packet_ip()
				var client_port := _discovery_udp.get_packet_port()
				print("Discovery request from ", client_ip, " — responding")
				_discovery_udp.set_dest_address(client_ip, client_port)
				_discovery_udp.put_packet(DISCOVERY_RESPONSE.to_utf8_buffer())
	else:
		# Client: broadcast until server responds or timeout
		if not _discovering:
			return
		_discovery_elapsed += delta
		_discovery_timer += delta

		if _discovery_timer >= DISCOVERY_INTERVAL:
			_discovery_timer = 0.0
			_discovery_udp.set_dest_address("255.255.255.255", DISCOVERY_PORT)
			_discovery_udp.put_packet(DISCOVERY_MSG.to_utf8_buffer())
			print("Broadcasting discovery... (%.0fs)" % _discovery_elapsed)

		while _discovery_udp.get_available_packet_count() > 0:
			var packet := _discovery_udp.get_packet()
			if packet.get_string_from_utf8() == DISCOVERY_RESPONSE:
				var found_ip := _discovery_udp.get_packet_ip()
				print("Server found at ", found_ip)
				_discovering = false
				_discovery_udp.close()
				_discovery_udp = null
				emit_signal("discovery_status", "Found server at " + found_ip)
				_connect_to_server(found_ip)
				return

		if _discovery_elapsed >= DISCOVERY_TIMEOUT:
			print("Discovery timed out — falling back to 127.0.0.1")
			_discovering = false
			_discovery_udp.close()
			_discovery_udp = null
			emit_signal("discovery_status", "No server found. Trying localhost...")
			_connect_to_server("127.0.0.1")

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
	rpc_id(id, "rpc_update_team_counts", team_counts[1], team_counts[2], -1, -1)
	rpc_id(id, "rpc_set_game_mode", max_players, max_per_team)

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: ", id)
	if players.has_node(str(id)):
		players.get_node(str(id)).queue_free()
	if id in peer_teams:
		team_counts[peer_teams[id]] -= 1
		peer_teams.erase(id)
		rpc_update_team_counts.rpc(team_counts[1], team_counts[2], -1, -1)


# --- Spawning ---

func _get_spawn_position(team_id: int, peer_id: int = -1) -> Vector2:
	var lb = _get_level_builder()
	if lb == null:
		return Vector2(300, 300) if team_id == 1 else Vector2(3800, 3800)
	var spawns: Array = lb.blue_spawns if team_id == 1 else lb.red_spawns
	if spawns.is_empty():
		return Vector2(300, 300) if team_id == 1 else Vector2(3800, 3800)

	# Use sorted peer-ID order so the index is deterministic even when all
	# players spawn at the same time (before any node enters the tree).
	var idx := 0
	if peer_id != -1:
		var team_peers: Array = []
		for pid in peer_teams:
			if peer_teams[pid] == team_id:
				team_peers.append(pid)
		team_peers.sort()
		var pos_in_list := team_peers.find(peer_id)
		idx = pos_in_list if pos_in_list != -1 else 0

	var base_pos: Vector2 = spawns[idx % spawns.size()]
	return _find_free_spawn_near(base_pos, lb)

# Search outward from base_pos for a floor tile that no existing player occupies.
func _find_free_spawn_near(base_pos: Vector2, lb: Node) -> Vector2:
	var tile_map = lb.tile_map
	if tile_map == null:
		return base_pos

	# Build candidate offsets: centre first, then expanding rings (shuffled per
	# ring so the fallback direction is random rather than always top-left).
	var candidates: Array[Vector2] = [Vector2.ZERO]
	for ring in range(1, 8):  # search up to 7 tiles (224 px) out
		var ring_offsets: Array[Vector2] = []
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				if abs(dx) == ring or abs(dy) == ring:
					ring_offsets.append(Vector2(dx * 32, dy * 32))
		ring_offsets.shuffle()
		candidates.append_array(ring_offsets)

	for offset in candidates:
		var candidate := base_pos + offset
		if _is_valid_spawn(candidate, tile_map):
			return candidate

	return base_pos  # give up and use original

func _is_valid_spawn(pos: Vector2, tile_map) -> bool:
	# Every tile the player's bounding box overlaps must be a floor tile.
	var half := 28  # slightly smaller than half of the 64 px player hitbox
	for cx in [-half, half]:
		for cy in [-half, half]:
			var tile := Vector2i(int(pos.x + cx) / 32, int(pos.y + cy) / 32)
			if tile_map.get_cell_atlas_coords(tile) != Vector2i(0, 0):
				return false
	# Must not overlap any player already in the scene.
	for child in players.get_children():
		if child.global_position.distance_to(pos) < 60.0:
			return false
	return true

func _spawn_local_player() -> void:
	var my_id := multiplayer.get_unique_id()
	if players.has_node(str(my_id)):
		print("Local player already spawned, skipping.")
		return
	var my_team = peer_teams.get(my_id, -1)
	var spawn_pos := _get_spawn_position(my_team, my_id)
	var player = player_scene.instantiate()
	player.name = str(my_id)
	player.position = spawn_pos
	player.is_player_one = (my_team == 1)
	player.is_local_player = true
	players.add_child(player)
	player.set_multiplayer_authority(my_id)
	print("Spawned local player at: ", spawn_pos, " team: ", my_team)
	spawn_remote_player.rpc(my_id, spawn_pos)

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
	player.is_player_one = (peer_teams.get(peer_id, -1) == 1)
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
	if team_counts.get(team_id, 0) >= max_per_team:
		return
	peer_teams[peer_id] = team_id
	team_counts[team_id] += 1
	print("Peer ", peer_id, " joined team ", "Blue" if team_id == 1 else "Red")
	if team_manager:
		team_manager.peer_teams[peer_id] = team_id
	# Broadcast to ALL peers including sender
	rpc_update_team_counts.rpc(team_counts[1], team_counts[2], peer_id, team_id)
	if peer_teams.size() >= max_players:
		_begin_game_server()

@rpc("any_peer", "call_local", "reliable")
func rpc_update_team_counts(blue: int, red: int, joining_peer: int, joining_team: int) -> void:
	team_counts[1] = blue
	team_counts[2] = red
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
	_rpc_begin_game_client.rpc()
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
	_spawn_home_zones()
	if multiplayer.is_server():
		spawn_flag(1)
		spawn_flag(2)
		rpc_update_scores.rpc(0, 0)

func _end_game() -> void:
	is_game_active = false
	rpc_show_game_over.rpc()
	print("Game Over! Blue: ", score_team_a, " Red: ", score_team_b)

func _create_flag_at(flag_team_id: int, pos: Vector2) -> void:
	if flag_instances.get(flag_team_id) != null:
		flag_instances[flag_team_id].queue_free()
	var flag_scene := preload("res://Scenes/Flag.tscn")
	var flag := flag_scene.instantiate()
	flag.flag_team_id = flag_team_id
	flag.global_position = pos
	add_child(flag)
	flag_instances[flag_team_id] = flag

func spawn_flag(flag_team_id: int) -> void:
	var pos: Vector2 = FLAG_HOME_POSITIONS[flag_team_id]
	flags_at_home[flag_team_id] = true
	_create_flag_at(flag_team_id, pos)
	rpc_spawn_flag.rpc(flag_team_id, pos)

func remove_flag(flag_team_id: int) -> void:
	flags_at_home[flag_team_id] = false
	if flag_instances.get(flag_team_id) != null:
		flag_instances[flag_team_id].queue_free()
		flag_instances[flag_team_id] = null
	rpc_remove_flag.rpc(flag_team_id)

func respawn_flag(flag_team_id: int) -> void:
	spawn_flag(flag_team_id)

func drop_flag(flag_team_id: int, drop_pos: Vector2) -> void:
	flags_at_home[flag_team_id] = false
	_create_flag_at(flag_team_id, drop_pos)
	rpc_drop_flag.rpc(flag_team_id, drop_pos)


# --- RPCs ---

@rpc("any_peer", "call_local", "reliable")
func rpc_update_scores(s_a: int, s_b: int) -> void:
	score_team_a = s_a
	score_team_b = s_b

func score_for_team(team_id: int) -> void:
	if team_id == 1:
		score_team_a += 1
	else:
		score_team_b += 1
	rpc_update_scores.rpc(score_team_a, score_team_b)
	print("Score — Blue: ", score_team_a, " Red: ", score_team_b)

func _spawn_home_zones() -> void:
	# Remove any existing home zones first (e.g. on game restart)
	for child in get_parent().get_children():
		if child.is_in_group("home_zone"):
			child.queue_free()
	var hz_scene: PackedScene = preload("res://Scenes/HomeZone.tscn")
	# Blue HQ center: position (128,128) + half of 512x512
	var blue_zone: Node = hz_scene.instantiate()
	blue_zone.team_id = 1
	blue_zone.position = Vector2(384, 384)
	blue_zone.add_to_group("home_zone")
	get_parent().add_child(blue_zone)
	# Red HQ center: position (2928,4928) + half of 512x512
	var red_zone: Node = hz_scene.instantiate()
	red_zone.team_id = 2
	red_zone.position = Vector2(3184, 5184)
	red_zone.add_to_group("home_zone")
	get_parent().add_child(red_zone)

@rpc("any_peer", "call_remote", "reliable")
func rpc_spawn_flag(flag_team_id: int, pos: Vector2) -> void:
	flags_at_home[flag_team_id] = true
	_create_flag_at(flag_team_id, pos)

@rpc("any_peer", "call_remote", "reliable")
func rpc_remove_flag(flag_team_id: int) -> void:
	flags_at_home[flag_team_id] = false
	if flag_instances.get(flag_team_id) != null:
		flag_instances[flag_team_id].queue_free()
		flag_instances[flag_team_id] = null

@rpc("any_peer", "call_remote", "reliable")
func rpc_drop_flag(flag_team_id: int, drop_pos: Vector2) -> void:
	flags_at_home[flag_team_id] = false
	_create_flag_at(flag_team_id, drop_pos)

@rpc("any_peer", "call_remote", "reliable")
func rpc_show_game_over() -> void:
	print("Game Over!")
	emit_signal("game_over")

@rpc("authority", "call_remote", "reliable")
func rpc_set_game_mode(p_max_players: int, p_max_per_team: int) -> void:
	max_players = p_max_players
	max_per_team = p_max_per_team
	emit_signal("game_mode_updated")
