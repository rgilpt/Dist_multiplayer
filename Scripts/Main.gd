extends Node2D

@onready var team_select: Control = $TeamSelect
@onready var server_view: Control = $ServerView  # new node
@onready var lobby_camera: Camera2D = $LobbyCamera

var _is_server: bool = false
var _panning: bool = false
var _pan_origin: Vector2 = Vector2.ZERO
var _cam_origin: Vector2 = Vector2.ZERO

const ZOOM_MIN := Vector2(0.1, 0.1)
const ZOOM_MAX := Vector2(3.0, 3.0)
const ZOOM_STEP := 0.1

func _ready():
	await get_tree().process_frame
	lobby_camera.enabled = true

	var args := OS.get_cmdline_args()
	_is_server = "--server" in args
	if _is_server:
		team_select.visible = false
		server_view.visible = true
	else:
		team_select.visible = true
		server_view.visible = false

	get_node("NetworkManager").game_started.connect(_on_game_started)

func _on_game_started() -> void:
	if _is_server:
		return  # server keeps lobby camera

	var nm = get_node("NetworkManager")
	var my_id := multiplayer.get_unique_id()
	var my_team: int = nm.peer_teams.get(my_id, -1)
	var is_player = my_team != -1 and nm.team_counts.get(my_team, 0) >= nm.max_per_team

	if is_player:
		lobby_camera.enabled = false  # player's own Camera2D takes over
		return

	# Observer: keep lobby camera, center it between the two team bases
	_is_observer = true
	lobby_camera.enabled = true
	var lb = nm.level_builder
	if lb and lb.slot_configs.size() >= 2:
		var s0 = lb.slot_configs[0].get("flag_position", {"x": 384, "y": 224})
		var s1 = lb.slot_configs[1].get("flag_position", {"x": 3184, "y": 5344})
		lobby_camera.position = Vector2((s0.x + s1.x) * 0.5, (s0.y + s1.y) * 0.5)
	lobby_camera.zoom = Vector2(0.5, 0.5)

var _is_observer: bool = false

func _input(event: InputEvent) -> void:
	if not _is_server and not _is_observer:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			lobby_camera.zoom = (lobby_camera.zoom + Vector2(ZOOM_STEP, ZOOM_STEP)).clamp(ZOOM_MIN, ZOOM_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			lobby_camera.zoom = (lobby_camera.zoom - Vector2(ZOOM_STEP, ZOOM_STEP)).clamp(ZOOM_MIN, ZOOM_MAX)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_panning = event.pressed
			if _panning:
				_pan_origin = event.position
				_cam_origin = lobby_camera.position

	elif event is InputEventMouseMotion and _panning:
		var delta = (event.position - _pan_origin) / lobby_camera.zoom
		lobby_camera.position = _cam_origin - delta
