extends Node
class_name NetworkManager

var _peer: WebSocketMultiplayerPeer

var flag_instances: Dictionary = {}   # flag_team_id -> Node2D (null if carried)
var flags_at_home: Dictionary = {}    # flag_team_id -> bool
var scores: Dictionary = {}           # team_id -> int
var team_counts: Dictionary = {}      # team_id -> int  (populated from teams.json)
var peer_teams: Dictionary = {}
## Maps team_id -> slot index (0 or 1). Assigned at game start from level.json slots.
var team_slot_map: Dictionary = {}

var is_game_active: bool = false
var game_timer: float = 180.0

var server_address: String = "mflxp.pt"
var server_port: int = 9000  # local port; clients connect via wss://mflxp.pt/game
var is_host: bool = false
var max_peers: int = 4

var max_players: int = 4
var max_per_team: int = 2

signal flag_spawned
signal flag_picked_up
signal flag_scored
signal game_over
signal all_players_joined
signal team_data_updated(counts: Dictionary, your_team: int)
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

const CONNECT_TIMEOUT: float = 5.0
const CONNECT_MAX_RETRIES: int = 5
var _is_client_connecting: bool = false
var _connect_elapsed: float = 0.0
var _reconnect_delay: float = 0.0
var _connect_retries: int = 0
var _connect_address_cache: String = ""

var _initialized: bool = false
var player_scene = preload("res://Scenes/Player.tscn")
var team_config: Dictionary = {}

@onready var players: Node2D = $"../Players"
@onready var team_manager = $"../TeamManager"
#@onready var level_builder = $"../LevelBuilder"
var level_builder = null
func _ready():
	if _initialized:
		print("WARNING: _ready() called twice, skipping.")
		return
	_initialized = true
	_load_team_config()
	_init_team_data()

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
		_peer = WebSocketMultiplayerPeer.new()
		_peer.handshake_timeout = 15.0
		var error: Error = _peer.create_server(server_port)
		if error != OK:
			printerr("Server creation failed: ", error)
			return
		multiplayer.multiplayer_peer = _peer
		_peer.peer_connected.connect(_on_peer_connected)
		_peer.peer_disconnected.connect(_on_peer_disconnected)
		print("Host ready on ws://localhost:", server_port)
		_start_discovery_listener()

	else:
		# Default: connect as client (--client flag is optional)
		var addr_index := args.find("--address")
		if addr_index != -1 and addr_index + 1 < args.size():
			# Explicit address given — connect directly
			server_address = args[addr_index + 1]
			_connect_to_server(server_address)
		else:
			# No address: try LAN discovery first, fall back to remote server
			_start_discovery_broadcast()

func _process(delta: float) -> void:
	if is_game_active and multiplayer.is_server():
		game_timer -= delta
		if game_timer <= 0:
			_end_game()

	_process_discovery(delta)

	if _is_client_connecting:
		_connect_elapsed += delta
		if _connect_elapsed >= CONNECT_TIMEOUT:
			_is_client_connecting = false
			_schedule_reconnect()

	if _reconnect_delay > 0.0:
		_reconnect_delay -= delta
		if _reconnect_delay <= 0.0:
			_reconnect_delay = 0.0
			_connect_to_server(_connect_address_cache)

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

func _is_local_address(address: String) -> bool:
	return address == "127.0.0.1" or address == "localhost" \
		or address.begins_with("192.168.") \
		or address.begins_with("10.") \
		or address.begins_with("172.")

func _build_url(address: String) -> String:
	if _is_local_address(address):
		# Connect directly to the Godot WebSocket server, bypassing the TLS proxy
		return "ws://" + address + ":" + str(server_port)
	return "wss://" + address + "/game"

func _connect_to_server(address: String) -> void:
	server_address = address
	_connect_address_cache = address

	# Clean up any previous peer
	if multiplayer.multiplayer_peer != null:
		if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
			multiplayer.connected_to_server.disconnect(_on_connected_to_server)
		if multiplayer.connection_failed.is_connected(_on_connection_failed):
			multiplayer.connection_failed.disconnect(_on_connection_failed)
		multiplayer.multiplayer_peer = null

	_peer = WebSocketMultiplayerPeer.new()
	_peer.handshake_timeout = 15.0
	var url := _build_url(server_address)
	var error: Error = _peer.create_client(url)
	if error != OK:
		printerr("Client connection failed: ", error)
		_schedule_reconnect()
		return
	multiplayer.multiplayer_peer = _peer
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	_is_client_connecting = true
	_connect_elapsed = 0.0
	print("Connecting to %s (attempt %d)" % [url, _connect_retries + 1])

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
			print("Discovery timed out — falling back to remote server: ", server_address)
			_discovering = false
			_discovery_udp.close()
			_discovery_udp = null
			emit_signal("discovery_status", "No local server found. Connecting to remote...")
			_connect_to_server(server_address)

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


# --- Team Config ---

func _load_team_config() -> void:
	var file := FileAccess.open("res://JSON/teams.json", FileAccess.READ)
	if file == null:
		printerr("teams.json not found — using default visuals")
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		printerr("teams.json parse error: ", json.get_error_message())
		return
	team_config = json.data
	print("Loaded teams.json: ", team_config.get("teams", []).size(), " teams")

## Populate team_counts, flags_at_home, and scores from the loaded config.
func _init_team_data() -> void:
	team_counts.clear()
	flags_at_home.clear()
	scores.clear()
	for t in team_config.get("teams", []):
		var tid: int = t.get("team_id", -1)
		if tid == -1:
			continue
		team_counts[tid] = 0
		flags_at_home[tid] = true
		scores[tid] = 0
	# Fallback: keep working if teams.json is missing
	if team_counts.is_empty():
		team_counts = {1: 0, 2: 0}
		flags_at_home = {1: true, 2: true}
		scores = {1: 0, 2: 0}

## Returns the config dictionary for team_id, or {} if not found.
func _get_team_config(team_id: int) -> Dictionary:
	for t in team_config.get("teams", []):
		if t.get("team_id", -1) == team_id:
			return t
	return {}

## Assigns the 2 active teams to level slots (sorted team_id order → slot 0, slot 1).
## Must be called after all teams have joined, before _start_game.
func _assign_team_slots() -> void:
	team_slot_map.clear()
	var active: Array = []
	for tid in team_counts:
		if team_counts[tid] > 0:
			active.append(tid)
	active.sort()
	for i in active.size():
		team_slot_map[active[i]] = i
	print("Team slot assignments: ", team_slot_map)

## Returns the level slot config Dictionary for the given team_id, or {}.
func _get_slot_config(team_id: int) -> Dictionary:
	var lb = _get_level_builder()
	if lb == null:
		return {}
	var slot_idx: int = team_slot_map.get(team_id, -1)
	if slot_idx < 0 or slot_idx >= lb.slot_configs.size():
		return {}
	return lb.slot_configs[slot_idx]

## Returns 0 for the first peer on a team, 1 for the second (by sorted peer ID).
func _get_slot_in_team(peer_id: int, team_id: int) -> int:
	var team_peers: Array = []
	for pid in peer_teams:
		if peer_teams[pid] == team_id:
			team_peers.append(pid)
	team_peers.sort()
	var idx := team_peers.find(peer_id)
	return max(idx, 0)

func _apply_player_skin(player: Node, peer_id: int) -> void:
	var team_id: int = peer_teams.get(peer_id, -1)
	if team_id == -1:
		return
	var config := _get_team_config(team_id)
	if config.is_empty():
		return
	var slot := _get_slot_in_team(peer_id, team_id)
	var sprite_key := "player1_sprite" if slot == 0 else "player2_sprite"
	var weapon_key := "player1_weapon" if slot == 0 else "player2_weapon"
	var c_arr = config.get("color", null)
	var team_color := Color(c_arr[0], c_arr[1], c_arr[2]) if c_arr != null else Color.WHITE
	player.apply_team_skin(
		"res://" + config.get(sprite_key, ""),
		"res://" + config.get(weapon_key, ""),
		team_color
	)

func _on_connected_to_server() -> void:
	_is_client_connecting = false
	_connect_retries = 0
	if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.disconnect(_on_connected_to_server)
	if multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.disconnect(_on_connection_failed)
	print("Connected! My ID: ", multiplayer.get_unique_id())

func _on_connection_failed() -> void:
	_is_client_connecting = false
	if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.disconnect(_on_connected_to_server)
	if multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.disconnect(_on_connection_failed)
	print("Connection failed — scheduling retry")
	_schedule_reconnect()

func _schedule_reconnect() -> void:
	_connect_retries += 1
	if _connect_retries > CONNECT_MAX_RETRIES:
		printerr("Max connection retries reached. Giving up.")
		emit_signal("discovery_status", "Could not connect. Check server is running.")
		return
	# Random jitter so multiple clients don't all retry at the same instant
	_reconnect_delay = randf_range(1.0, 3.0)
	var attempt := _connect_retries
	emit_signal("discovery_status", "Retrying... (attempt %d/%d)" % [attempt, CONNECT_MAX_RETRIES])
	print("Retry %d in %.1fs" % [attempt, _reconnect_delay])

func _on_peer_connected(id: int) -> void:
	print("Peer connected: ", id)
	for child in players.get_children():
		var existing_id := int(child.name)
		if existing_id != id:
			spawn_remote_player.rpc_id(id, existing_id, child.position)
	rpc_update_team_counts.rpc_id(id, team_counts, -1, -1)
	rpc_set_game_mode.rpc_id(id, max_players, max_per_team)

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: ", id)
	if players.has_node(str(id)):
		players.get_node(str(id)).queue_free()
	if id in peer_teams:
		team_counts[peer_teams[id]] -= 1
		peer_teams.erase(id)
		rpc_update_team_counts.rpc(team_counts, -1, -1)


# --- Spawning ---

func _get_spawn_position(team_id: int, peer_id: int = -1) -> Vector2:
	var lb = _get_level_builder()
	if lb == null:
		var slot_idx: int = team_slot_map.get(team_id, 0)
		return Vector2(300, 300) if slot_idx == 0 else Vector2(3800, 3800)
	var slot_idx: int = team_slot_map.get(team_id, 0)
	var spawns: Array = lb.slot_spawns[slot_idx] if lb.slot_spawns.size() > slot_idx else []
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
	player.team_id = my_team
	player.is_local_player = true
	players.add_child(player)
	player.set_multiplayer_authority(my_id)
	_apply_player_skin(player, my_id)
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
	player.team_id = peer_teams.get(peer_id, -1)
	player.is_local_player = false
	players.add_child(player)
	player.set_multiplayer_authority(peer_id)
	_apply_player_skin(player, peer_id)

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
	# Only allow joining a new (empty) team if fewer than 2 teams are already active
	var active_teams := 0
	for t in team_counts:
		if team_counts[t] > 0:
			active_teams += 1
	if active_teams >= 2 and team_counts.get(team_id, 0) == 0:
		return
	if team_counts.get(team_id, 0) >= max_per_team:
		return
	peer_teams[peer_id] = team_id
	team_counts[team_id] += 1
	print("Peer ", peer_id, " joined team ", "Blue" if team_id == 1 else "Red")
	if team_manager:
		team_manager.peer_teams[peer_id] = team_id
	# Broadcast to ALL peers including sender
	rpc_update_team_counts.rpc(team_counts, peer_id, team_id)
	# Auto-start once at least 2 teams each have max_per_team players
	var full_teams := 0
	for t in team_counts:
		if team_counts[t] >= max_per_team:
			full_teams += 1
	if full_teams >= 2:
		_begin_game_server()

@rpc("any_peer", "call_local", "reliable")
func rpc_update_team_counts(counts: Dictionary, joining_peer: int, joining_team: int) -> void:
	for tid in counts:
		team_counts[tid] = counts[tid]
	if joining_peer != -1:
		peer_teams[joining_peer] = joining_team
		if team_manager:
			team_manager.peer_teams[joining_peer] = joining_team
	var my_team = peer_teams.get(multiplayer.get_unique_id(), -1)
	emit_signal("team_data_updated", team_counts, my_team)

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
	_assign_team_slots()  # runs on all peers — team_counts is already synced
	for tid in scores:
		scores[tid] = 0
	_spawn_home_zones()
	if multiplayer.is_server():
		for tid in team_counts:
			if team_counts[tid] > 0:  # only spawn flags for teams that have players
				spawn_flag(tid)
		rpc_update_scores.rpc(scores)

func _end_game() -> void:
	is_game_active = false
	rpc_show_game_over.rpc()
	print("Game Over! Scores: ", scores)

func _create_flag_at(flag_team_id: int, pos: Vector2) -> void:
	if flag_instances.get(flag_team_id) != null:
		flag_instances[flag_team_id].queue_free()
	var flag_scene := preload("res://Scenes/Flag.tscn")
	var flag := flag_scene.instantiate()
	flag.flag_team_id = flag_team_id
	flag.global_position = pos
	add_child(flag)
	flag_instances[flag_team_id] = flag
	var flag_config := _get_team_config(flag_team_id)
	var flag_img: String = flag_config.get("flag_image", "")
	if flag_img != "":
		flag.apply_skin("res://" + flag_img)

func spawn_flag(flag_team_id: int) -> void:
	var slot := _get_slot_config(flag_team_id)
	var fp = slot.get("flag_position", null)
	var pos: Vector2
	if fp != null:
		pos = Vector2(fp["x"], fp["y"])
	else:
		var slot_idx: int = team_slot_map.get(flag_team_id, 0)
		pos = Vector2(384, 224) if slot_idx == 0 else Vector2(3184, 5344)
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
func rpc_update_scores(new_scores: Dictionary) -> void:
	for tid in new_scores:
		scores[tid] = new_scores[tid]

func score_for_team(team_id: int) -> void:
	scores[team_id] = scores.get(team_id, 0) + 1
	rpc_update_scores.rpc(scores)
	print("Score: ", scores)

func _spawn_home_zones() -> void:
	for child in get_parent().get_children():
		if child.is_in_group("home_zone"):
			child.queue_free()
	var hz_scene: PackedScene = preload("res://Scenes/HomeZone.tscn")
	for tid in team_slot_map:
		var slot := _get_slot_config(tid)
		var hp = slot.get("home_zone_position", null)
		if hp == null:
			continue
		var zone: Node = hz_scene.instantiate()
		zone.team_id = tid
		zone.position = Vector2(hp["x"], hp["y"])
		zone.add_to_group("home_zone")
		get_parent().add_child(zone)

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

# --- Ammo Drops ---

var _ammo_drop_counter: int = 0

func spawn_ammo_drop() -> void:
	if not multiplayer.is_server():
		return
	var positions := _get_drop_positions()
	if positions.is_empty():
		return
	_ammo_drop_counter += 1
	var drop_name := "AmmoDrop%d" % _ammo_drop_counter
	var pos: Vector2 = positions[randi() % positions.size()]
	_create_ammo_drop(drop_name, pos)
	rpc_create_ammo_drop.rpc(drop_name, pos)

func _get_drop_positions() -> Array:
	var file := FileAccess.open("res://JSON/level.json", FileAccess.READ)
	if file == null:
		return [Vector2(1752, 1552)]
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	var positions: Array = []
	for room in data.get("rooms", []):
		if room.get("name", "").begins_with("hq"):
			continue  # skip team bases
		var cx: float = room["position"]["x"] + room["size"]["width"] / 2.0
		var cy: float = room["position"]["y"] + room["size"]["height"] / 2.0
		positions.append(Vector2(cx, cy))
	return positions

func _create_ammo_drop(drop_name: String, pos: Vector2) -> void:
	var scene: PackedScene = preload("res://Scenes/AmmoDrop.tscn")
	var drop := scene.instantiate()
	drop.name = drop_name
	drop.global_position = pos
	get_parent().add_child(drop)

func remove_ammo_drop(drop_name: String) -> void:
	var node := get_parent().get_node_or_null(drop_name)
	if node:
		node.queue_free()
	rpc_remove_ammo_drop.rpc(drop_name)

@rpc("authority", "call_remote", "reliable")
func rpc_create_ammo_drop(drop_name: String, pos: Vector2) -> void:
	_create_ammo_drop(drop_name, pos)

@rpc("authority", "call_remote", "reliable")
func rpc_remove_ammo_drop(drop_name: String) -> void:
	var node := get_parent().get_node_or_null(drop_name)
	if node:
		node.queue_free()

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_ammo_drop() -> void:
	if not multiplayer.is_server():
		return
	spawn_ammo_drop()

@rpc("any_peer", "call_remote", "reliable")
func rpc_show_game_over() -> void:
	print("Game Over!")
	emit_signal("game_over")

@rpc("authority", "call_remote", "reliable")
func rpc_set_game_mode(p_max_players: int, p_max_per_team: int) -> void:
	max_players = p_max_players
	max_per_team = p_max_per_team
	emit_signal("game_mode_updated")
