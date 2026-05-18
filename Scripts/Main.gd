extends Node2D

@onready var team_select: Control = $TeamSelect
@onready var server_view: Control = $ServerView  # new node
@onready var lobby_camera: Camera2D = $LobbyCamera

func _ready():
	await get_tree().process_frame
	lobby_camera.enabled = true

	var args := OS.get_cmdline_args()
	if "--server" in args:
		team_select.visible = false
		server_view.visible = true
	else:
		team_select.visible = true
		server_view.visible = false

	get_node("NetworkManager").game_started.connect(_on_game_started)

func _on_game_started() -> void:
	var args := OS.get_cmdline_args()
	if "--server" in args:
		return  # server keeps lobby camera
	# Client: disable lobby camera so player camera takes over
	lobby_camera.enabled = false
