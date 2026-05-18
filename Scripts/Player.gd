extends CharacterBody2D

@export var speed : float = 300.0

@onready var sprite : Sprite2D = $Sprite
@onready var collider : CollisionShape2D = $CollisionShape2D
@onready var weapon_holder : Node2D = $WeaponHolder
@onready var flag_area : Area2D = $FlagArea
@onready var home_zone_area : Area2D = $HomeZoneArea
@onready var ammo_ui : Label = $AmmoUI
@onready var score_ui : Label = $ScoreUI
@onready var health_ui : Label = $HealthUI
@onready var flag_indicator : ColorRect = $FlagIndicator
@onready var p_1_zone: ColorRect = $HomeZoneArea/P1Zone
@onready var p_2_zone: ColorRect = $HomeZoneArea/P2Zone
@onready var camera_2d: Camera2D = $Camera2D

var is_player_one : bool = false
var is_local_player: bool = false
var ammo : int = 6
var score : int = 0
var has_flag : bool = false
var carry_flag_texture : Texture2D
var _ready_to_sync: bool = false

var max_health: int = 100
var health: int = 100
var _is_dead: bool = false

func _ready():
	add_to_group("player")

	camera_2d.enabled = is_local_player
	_ready_to_sync = false

	if is_player_one:
		sprite.modulate = Color(0.3, 0.7, 1.0)
		p_1_zone.visible = true
		p_2_zone.visible = false
	else:
		sprite.modulate = Color(1.0, 0.3, 0.3)
		p_1_zone.visible = false
		p_2_zone.visible = true

	update_health_ui()
	flag_area.body_entered.connect(_on_flag_area_body_entered)
	home_zone_area.body_entered.connect(_on_home_zone_entered)

	if is_local_player:
		await get_tree().create_timer(0.5).timeout
		_ready_to_sync = true


func _physics_process(_delta):
	if not is_local_player or _is_dead:
		return

	# Rotate weapon holder to face mouse
	var mouse_pos := get_global_mouse_position()
	var direction := (mouse_pos - global_position).normalized()
	weapon_holder.rotation = direction.angle()

	# Flip sprite based on mouse side
	sprite.flip_h = mouse_pos.x < global_position.x

	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_action_strength("p1_right") - Input.get_action_strength("p1_left")
	input_dir.y = Input.get_action_strength("p1_down") - Input.get_action_strength("p1_up")

	if input_dir != Vector2.ZERO:
		input_dir = input_dir.normalized()

	velocity = input_dir * speed
	move_and_slide()

	if _ready_to_sync:
		rpc("sync_position", global_position, sprite.flip_h, weapon_holder.rotation)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func sync_position(pos: Vector2, flipped: bool, weapon_rot: float) -> void:
	global_position = pos
	sprite.flip_h = flipped
	weapon_holder.rotation = weapon_rot

func _input(event):
	if not is_local_player or _is_dead:
		return
	if event.is_action_pressed("shoot"):
		fire()

func fire():
	if ammo <= 0 or has_flag:
		return

	ammo -= 1
	update_ammo_ui()

	var mouse_pos := get_global_mouse_position()
	var direction := (mouse_pos - global_position).normalized()

	# Spawn bullet locally for visual
	_spawn_bullet(direction)

	# Tell server to spawn bullet for collision detection
	rpc_id(1, "server_spawn_bullet", global_position, direction, 
		"player_one" if is_player_one else "player_two")

@rpc("any_peer", "call_remote", "reliable")
func server_spawn_bullet(pos: Vector2, direction: Vector2, shooter_str: String) -> void:
	if not multiplayer.is_server():
		return
	var bullet_scene: PackedScene = preload("res://Scenes/Weapon.tscn")
	var bullet: Node2D = bullet_scene.instantiate()
	bullet.global_position = pos
	bullet.direction = direction
	bullet.rotation = direction.angle()
	bullet.shooter = shooter_str
	get_tree().root.add_child(bullet)

func _spawn_bullet(direction: Vector2) -> void:
	var bullet_scene: PackedScene = preload("res://Scenes/Weapon.tscn")
	var bullet: Node2D = bullet_scene.instantiate()
	bullet.global_position = global_position
	bullet.direction = direction
	bullet.rotation = direction.angle()
	bullet.shooter = "player_one" if is_player_one else "player_two"
	get_tree().root.add_child(bullet)


# --- Health ---

func update_health_ui() -> void:
	if health_ui:
		health_ui.text = "HP: " + str(health)

func take_damage(amount: int) -> void:
	if not multiplayer.is_server() or _is_dead:
		return
	health -= amount
	health = max(health, 0)
	rpc("rpc_sync_health", health)
	if health <= 0:
		rpc("rpc_die")

@rpc("any_peer", "call_local", "reliable")
func rpc_sync_health(new_health: int) -> void:
	health = new_health
	update_health_ui()
	# Flash red when hit
	var original_color := sprite.modulate
	sprite.modulate = Color(1.0, 0.2, 0.2)
	await get_tree().create_timer(0.15).timeout
	sprite.modulate = original_color

@rpc("any_peer", "call_local", "reliable")
func rpc_die() -> void:
	_is_dead = true
	visible = false
	collider.set_deferred("disabled", true)
	print("Player ", name, " died!")

	# Drop flag if carrying
	if has_flag:
		has_flag = false
		flag_indicator.visible = false
		if multiplayer.is_server():
			get_node("/root/Main/NetworkManager").respawn_flag()

	# Respawn after 3 seconds
	await get_tree().create_timer(3.0).timeout
	_respawn()

func _respawn() -> void:
	health = max_health
	_is_dead = false
	visible = true
	collider.set_deferred("disabled", false)
	update_health_ui()

	# Teleport back to spawn position
	if is_local_player:
		var nm = get_node_or_null("/root/Main/NetworkManager")
		if nm:
			var my_team = nm.peer_teams.get(multiplayer.get_unique_id(), -1)
			var spawn_pos = nm._get_spawn_position(my_team)
			global_position = spawn_pos
			rpc("sync_position", global_position, sprite.flip_h, weapon_holder.rotation)

	if multiplayer.is_server():
		rpc("rpc_sync_health", health)


# --- Ammo ---

func update_ammo_ui():
	if ammo_ui:
		ammo_ui.text = "Ammo: " + str(ammo)


# --- Flag ---

func _on_flag_area_body_entered(body):
	if body.is_in_group("flag") and not has_flag:
		rpc_request_flag()

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_flag():
	if not multiplayer.is_server():
		return
	has_flag = true
	flag_indicator.visible = true
	get_node("/root/Main/NetworkManager").remove_flag()
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
		get_node("/root/Main/NetworkManager").respawn_flag()

@rpc("any_peer", "call_remote", "reliable")
func rpc_release_flag():
	has_flag = false
	flag_indicator.visible = false

@rpc("any_peer", "call_remote", "reliable")
func rpc_sync_score(new_score: int):
	score = new_score
	if score_ui:
		score_ui.text = "Score: " + str(score)
