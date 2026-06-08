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
	# Client: disable lobby camera so player camera takes over
	lobby_camera.enabled = false

func _input(event: InputEvent) -> void:
	if not _is_server:
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
