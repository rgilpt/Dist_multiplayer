extends Node2D

@onready var team_select: Control = $TeamSelect
@onready var server_view: Control = $ServerView  # new node
@onready var lobby_camera: Camera2D = $LobbyCamera

var _is_server: bool = false
var _panning: bool = false
var _pan_origin: Vector2 = Vector2.ZERO
var _cam_origin: Vector2 = Vector2.ZERO
var _is_observer: bool = false
var _game_over_canvas: CanvasLayer = null
var _game_over_countdown_lbl: Label = null
var _game_over_countdown: float = 0.0

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

	var nm := get_node("NetworkManager")
	nm.game_started.connect(_on_game_started)
	nm.game_over.connect(_on_game_over)
	nm.game_reset.connect(_on_game_reset)

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

func _process(delta: float) -> void:
	if _game_over_countdown > 0.0:
		_game_over_countdown -= delta
		if _game_over_countdown_lbl:
			_game_over_countdown_lbl.text = "New game in %ds..." % max(0, int(ceil(_game_over_countdown)))

func _on_game_over() -> void:
	if _is_server:
		return
	_show_game_over_overlay()

func _show_game_over_overlay() -> void:
	var nm = get_node("NetworkManager")

	_game_over_canvas = CanvasLayer.new()
	_game_over_canvas.layer = 100
	add_child(_game_over_canvas)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.82)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game_over_canvas.add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	bg.add_child(vbox)

	var title := Label.new()
	title.text = "GAME OVER"
	title.add_theme_font_size_override("font_size", 52)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Determine winner
	var max_score := -1
	var winner_name := ""
	var tied := false
	for tid in nm.scores:
		if nm.team_counts.get(tid, 0) == 0:
			continue
		var s: int = nm.scores[tid]
		if s > max_score:
			max_score = s
			winner_name = nm._get_team_config(tid).get("team_name", "Team %d" % tid)
			tied = false
		elif s == max_score and max_score >= 0:
			tied = true

	var result_lbl := Label.new()
	result_lbl.text = "It's a tie!" if tied else "%s wins!" % winner_name
	result_lbl.add_theme_font_size_override("font_size", 30)
	result_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(result_lbl)

	var spacer := Label.new()
	spacer.text = " "
	vbox.add_child(spacer)

	for tid in nm.scores:
		if nm.team_counts.get(tid, 0) == 0:
			continue
		var cfg = nm._get_team_config(tid)
		var tname: String = cfg.get("team_name", "Team %d" % tid)
		var score_lbl := Label.new()
		score_lbl.text = "%s:  %d point(s)" % [tname, nm.scores[tid]]
		score_lbl.add_theme_font_size_override("font_size", 22)
		score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(score_lbl)

	var spacer2 := Label.new()
	spacer2.text = " "
	vbox.add_child(spacer2)

	_game_over_countdown_lbl = Label.new()
	_game_over_countdown_lbl.add_theme_font_size_override("font_size", 16)
	_game_over_countdown_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_game_over_countdown_lbl)
	_game_over_countdown = 8.0

func _on_game_reset() -> void:
	if _is_server:
		return
	_game_over_countdown = 0.0
	_game_over_countdown_lbl = null
	if _game_over_canvas:
		_game_over_canvas.queue_free()
		_game_over_canvas = null
	_is_observer = false
	lobby_camera.enabled = true
	lobby_camera.position = Vector2.ZERO
	lobby_camera.zoom = Vector2(1.0, 1.0)
	if is_instance_valid(team_select):
		team_select.visible = true
		if team_select.has_method("reset"):
			team_select.reset()

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
