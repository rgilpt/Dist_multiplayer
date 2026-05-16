extends CharacterBody2D

@export var speed : float = 300.0

@onready var sprite : Sprite2D = $Sprite
@onready var collider : CollisionShape2D = $CollisionShape2D
@onready var weapon_holder : Node2D = $WeaponHolder
@onready var flag_area : Area2D = $FlagArea
@onready var home_zone_area : Area2D = $HomeZoneArea
@onready var ammo_ui : Label = $AmmoUI
@onready var score_ui : Label = $ScoreUI
@onready var flag_indicator : ColorRect = $FlagIndicator
@onready var p_1_zone: ColorRect = $HomeZoneArea/P1Zone
@onready var p_2_zone: ColorRect = $HomeZoneArea/P2Zone

var is_player_one : bool = false
var is_local_player: bool = false
var ammo : int = 6
var score : int = 0
var has_flag : bool = false
var carry_flag_texture : Texture2D
@onready var camera_2d: Camera2D = $Camera2D

func _ready():
	add_to_group("player")
	print(is_multiplayer_authority())
	camera_2d.enabled = is_local_player

	if is_player_one:
		sprite.modulate = Color(0.3, 0.7, 1.0)
		p_1_zone.visible = true
		p_2_zone.visible = false
	else:
		sprite.modulate = Color(1.0, 0.3, 0.3)
		p_1_zone.visible = false
		p_2_zone.visible = true

	weapon_holder.visible = false

	flag_area.body_entered.connect(_on_flag_area_body_entered)
	home_zone_area.body_entered.connect(_on_home_zone_entered)

func _physics_process(_delta):
	# Local player: read input and broadcast position
	if is_multiplayer_authority():
		var input_dir := Vector2.ZERO
		input_dir.x = Input.get_action_strength("p1_right") - Input.get_action_strength("p1_left")
		input_dir.y = Input.get_action_strength("p1_down") - Input.get_action_strength("p1_up")

		if input_dir != Vector2.ZERO:
			input_dir = input_dir.normalized()

		velocity = input_dir * speed
		move_and_slide()

		if input_dir.x != 0:
			sprite.flip_h = input_dir.x < 0

		rpc("sync_position", global_position, sprite.flip_h)
	# Remote player: just smoothly follow received position
	else:
		pass  # position is set directly by sync_position RPC

@rpc("any_peer", "call_remote", "unreliable_ordered")
func sync_position(pos: Vector2, flipped: bool) -> void:
	global_position = pos
	sprite.flip_h = flipped

func _input(event):
	if not is_multiplayer_authority():
		return
	if event.is_action_pressed("shoot"):
		fire()

func fire():
	if ammo <= 0 or has_flag:
		return

	ammo -= 1
	update_ammo_ui()

	var bullet_scene : PackedScene = preload("res://Scenes/Weapon.tscn")
	var bullet : Node2D = bullet_scene.instantiate()
	bullet.global_position = global_position + Vector2(10, 10)
	get_tree().root.add_child(bullet)

	if is_player_one:
		bullet.shooter = "player_one"
		bullet.rpc_set_shooter("player_one")
	else:
		bullet.shooter = "player_two"
		bullet.rpc_set_shooter("player_two")

func update_ammo_ui():
	if ammo_ui:
		ammo_ui.text = "Ammo: " + str(ammo)




func _on_flag_area_body_entered(body):
	if body.is_in_group("flag") and not has_flag:
		rpc_request_flag()

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_flag():
	if not multiplayer.is_server():
		return
	has_flag = true
	flag_indicator.visible = true
	get_node("/root/NetworkManager").remove_flag()
	rpc("rpc_set_flag", true)

@rpc("any_peer", "call_remote", "reliable")
func rpc_set_flag(flag: bool):
	has_flag = flag
	flag_indicator.visible = flag

func _on_home_zone_entered(body):
	if has_flag and multiplayer.is_server():
		score += 1
		score_ui.text = "Score: " + str(score)
		rpc("rpc_sync_score", score)
		rpc("rpc_release_flag")
		get_node("/root/NetworkManager").respawn_flag()

@rpc("any_peer", "call_remote", "reliable")
func rpc_release_flag():
	has_flag = false
	flag_indicator.visible = false

@rpc("any_peer", "call_remote", "reliable")
func rpc_sync_score(new_score: int):
	score = new_score
	if score_ui:
		score_ui.text = "Score: " + str(score)
