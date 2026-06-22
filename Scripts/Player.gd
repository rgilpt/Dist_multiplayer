extends CharacterBody2D

@export var speed : float = 600.0

@onready var sprite : Sprite2D = $Sprite
@onready var collider : CollisionShape2D = $CollisionShape2D
@onready var weapon_holder : Node2D = $WeaponHolder
@onready var flag_area : Area2D = $FlagArea
@onready var home_zone_area : Area2D = $HomeZoneArea
@onready var ammo_ui : Label = $AmmoUI
@onready var score_ui : Label = $ScoreUI
@onready var health_ui : Label = $HealthUI
@onready var flag_indicator : ColorRect = $FlagIndicator
@onready var flag_holder : Node2D = $FlagHolder
@onready var flag_sprite : Sprite2D = $FlagHolder/FlagSprite
@onready var p_1_zone: ColorRect = $HomeZoneArea/P1Zone
@onready var p_2_zone: ColorRect = $HomeZoneArea/P2Zone
@onready var camera_2d: Camera2D = $Camera2D

var is_player_one : bool = false
var team_id: int = -1
var is_local_player: bool = false
var _nm: Node = null
var ammo : int = 6          # gun clip
var reserve_ammo : int = 8  # unloaded reserve
const MAX_CLIP : int = 6
const MAX_RESERVE : int = 14 # 6 + 14 = 20 total max
var score : int = 0
## Which team's flag this player is carrying. -1 = none.
var carried_flag_team: int = -1
var has_flag: bool:
	get: return carried_flag_team != -1
var _ready_to_sync: bool = false

var max_health: int = 100
var health: int = 100
var _is_dead: bool = false
var _bounce_velocity: Vector2 = Vector2.ZERO
const BOUNCE_FORCE: float = 500.0
const BOUNCE_DECAY: float = 8.0
var _is_reloading: bool = false
const RELOAD_TIME: float = 1.5

func _ready():
	add_to_group("player")

	camera_2d.enabled = is_local_player
	_ready_to_sync = false

	# Zone visibility (cosmetic only — real home zone logic is in HomeZone.gd)
	p_1_zone.visible = is_player_one
	p_2_zone.visible = not is_player_one

	update_health_ui()
	#flag_area.body_entered.connect(_on_flag_area_body_entered)

	if is_local_player:
		_nm = get_node_or_null("/root/Main/NetworkManager")
		await get_tree().create_timer(0.5).timeout
		_ready_to_sync = true


func _physics_process(delta):
	if not is_local_player or _is_dead:
		return
	if _nm and not _nm.is_game_active:
		velocity = Vector2.ZERO
		return

	# Rotate weapon holder to face mouse
	var mouse_pos := get_global_mouse_position()
	var direction := (mouse_pos - global_position).normalized()
	weapon_holder.rotation = direction.angle()

	# Flip sprite based on mouse side
	sprite.flip_h = mouse_pos.x < global_position.x

	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("p1_left"):
		input_dir.x = -1
	elif Input.is_action_pressed("p1_right"):
		input_dir.x = 1
	else:
		input_dir.x = 0
		
	if Input.is_action_pressed("p1_up"):
		input_dir.y = -1
	elif Input.is_action_pressed("p1_down"):
		input_dir.y = 1
	else:
		input_dir.y = 0
	if input_dir != Vector2.ZERO:
		input_dir = input_dir.normalized()

	_bounce_velocity = _bounce_velocity.lerp(Vector2.ZERO, BOUNCE_DECAY * delta)
	velocity = input_dir * speed + _bounce_velocity
	move_and_slide()

	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var other := col.get_collider()
		if other and other.is_in_group("player") and other != self:
			var push_dir = (global_position - other.global_position)
			if push_dir == Vector2.ZERO:
				push_dir = Vector2.RIGHT
			_bounce_velocity = push_dir.normalized() * BOUNCE_FORCE

	if _ready_to_sync:
		sync_position.rpc(global_position, sprite.flip_h, weapon_holder.rotation)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func sync_position(pos: Vector2, flipped: bool, weapon_rot: float) -> void:
	global_position = pos
	sprite.flip_h = flipped
	weapon_holder.rotation = weapon_rot

func _input(event):
	if not is_local_player or _is_dead:
		return
	if _nm and not _nm.is_game_active:
		return
	if event.is_action_pressed("shoot"):
		fire()
	if event.is_action_pressed("reload"):
		_start_reload()

func _start_reload() -> void:
	if _is_reloading or ammo >= MAX_CLIP or reserve_ammo <= 0:
		return
	_is_reloading = true
	var gun: Sprite2D = $WeaponHolder/Sprite2D
	var original_color := gun.modulate

	var tween := create_tween()
	tween.tween_property(gun, "modulate", Color(1.0, 0.5, 0.0), 0.2)
	tween.tween_property(gun, "modulate", Color(1.0, 1.0, 0.3), 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.set_loops(int(RELOAD_TIME / 0.4))
	await get_tree().create_timer(RELOAD_TIME).timeout

	_is_reloading = false
	tween.kill()

	# Draw from reserve to fill the clip
	var needed := MAX_CLIP - ammo
	var drawn := mini(needed, reserve_ammo)
	ammo += drawn
	reserve_ammo -= drawn
	update_ammo_ui()

	# Green flash to confirm reload complete
	var finish_tween := create_tween()
	finish_tween.tween_property(gun, "modulate", Color(0.3, 1.0, 0.3), 0.1)
	finish_tween.tween_property(gun, "modulate", original_color, 0.3)

func fire():
	if ammo <= 0 or has_flag or _is_reloading:
		return

	ammo -= 1
	update_ammo_ui()

	var mouse_pos := get_global_mouse_position()
	var direction := (mouse_pos - global_position).normalized()

	# Spawn bullet locally for visual
	_spawn_bullet(direction)

	# Tell server to spawn bullet for collision detection
	server_spawn_bullet.rpc_id(1, global_position, direction, team_id)

@rpc("any_peer", "call_remote", "reliable")
func server_spawn_bullet(pos: Vector2, direction: Vector2, shooter_team: int) -> void:
	if not multiplayer.is_server():
		return
	var bullet_scene: PackedScene = preload("res://Scenes/Weapon.tscn")
	var bullet: Node2D = bullet_scene.instantiate()
	bullet.global_position = pos
	bullet.direction = direction
	bullet.rotation = direction.angle()
	bullet.shooter_team = shooter_team
	bullet.add_to_group("bullet")
	get_tree().root.add_child(bullet)

func _spawn_bullet(direction: Vector2) -> void:
	var bullet_scene: PackedScene = preload("res://Scenes/Weapon.tscn")
	var bullet: Node2D = bullet_scene.instantiate()
	bullet.global_position = global_position
	bullet.direction = direction
	bullet.rotation = direction.angle()
	bullet.shooter_team = team_id
	bullet.add_to_group("bullet")
	var nm := get_node_or_null("/root/Main/NetworkManager")
	if nm:
		var cfg: Dictionary = nm._get_team_config(team_id)
		var c_arr = cfg.get("color", null)
		if c_arr != null:
			bullet.modulate = Color(c_arr[0], c_arr[1], c_arr[2])
	get_tree().root.add_child(bullet)


# --- Health ---

func update_health_ui() -> void:
	if health_ui:
		health_ui.text = "HP: " + str(health)

func take_damage(amount: int) -> void:
	if not multiplayer.is_server() or _is_dead:
		return
	if _nm and not _nm.is_game_active:
		return
	health -= amount
	health = max(health, 0)
	rpc_sync_health.rpc(health)
	if health <= 0:
		rpc_die.rpc()

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

	# Drop flag at death position — teammates can return it
	if has_flag and multiplayer.is_server():
		var drop_team := carried_flag_team
		rpc_set_flag.rpc(-1)  # clear from player on all peers
		get_node("/root/Main/NetworkManager").drop_flag(drop_team, global_position)

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
			var my_id := multiplayer.get_unique_id()
			var my_team = nm.peer_teams.get(my_id, -1)
			var spawn_pos = nm._get_spawn_position(my_team, my_id)
			global_position = spawn_pos
			sync_position.rpc(global_position, sprite.flip_h, weapon_holder.rotation)

	if multiplayer.is_server():
		rpc_sync_health.rpc(health)


# --- Ammo ---

func update_ammo_ui():
	if ammo_ui:
		ammo_ui.text = "%d(%d)" % [ammo, reserve_ammo]

@rpc("any_peer", "call_local", "reliable")
func rpc_refill_ammo() -> void:
	if not is_local_player:
		return
	reserve_ammo = MAX_RESERVE
	update_ammo_ui()


# --- Flag ---

func _on_flag_area_body_entered(body: Node2D) -> void:
	if not is_local_player:
		return
	if not body.is_in_group("flag"):
		return
	var flag_team: int = body.get("flag_team_id") if body.get("flag_team_id") != null else -1
	if flag_team == -1:
		return
	var nm := get_node_or_null("/root/Main/NetworkManager")
	if nm == null:
		return
	var my_team: int = nm.peer_teams.get(multiplayer.get_unique_id(), -1)
	if flag_team != my_team and carried_flag_team == -1:
		# Enemy flag — pick it up
		rpc_request_flag.rpc_id(1, flag_team)
	elif flag_team == my_team and not nm.flags_at_home.get(my_team, true):
		# Own dropped flag — return it to base
		rpc_return_flag.rpc_id(1, flag_team)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_flag(flag_team: int) -> void:
	if not multiplayer.is_server():
		return
	var nm := get_node("/root/Main/NetworkManager")
	var player_team: int = nm.peer_teams.get(int(name), -1)
	if flag_team == player_team or carried_flag_team != -1:
		return  # own flag or already carrying
	nm.remove_flag(flag_team)
	rpc_set_flag.rpc(flag_team)

@rpc("any_peer", "call_remote", "reliable")
func rpc_return_flag(flag_team: int) -> void:
	if not multiplayer.is_server():
		return
	get_node("/root/Main/NetworkManager").respawn_flag(flag_team)

# call_local so server + all clients update the carried flag state.
# Pass -1 to clear (flag dropped or scored).
@rpc("any_peer", "call_local", "reliable")
func rpc_set_flag(flag_team: int) -> void:
	carried_flag_team = flag_team
	var carrying := (flag_team != -1)
	flag_indicator.visible = carrying
	flag_holder.visible = carrying
	if flag_team == 1:
		flag_sprite.modulate = Color(0.3, 0.7, 1.0)
		flag_indicator.color = Color(0.3, 0.7, 1.0, 0.7)
	elif flag_team == 2:
		flag_sprite.modulate = Color(1.0, 0.3, 0.3)
		flag_indicator.color = Color(1.0, 0.3, 0.3, 0.7)
	# Apply team's custom flag image if available
	if carrying:
		var nm = get_node_or_null("/root/Main/NetworkManager")
		if nm:
			var config: Dictionary = nm._get_team_config(flag_team)
			var img_path: String = config.get("flag_image", "")
			if img_path != "":
				var tex = load("res://" + img_path)
				if tex:
					flag_sprite.texture = tex

## Apply custom player and weapon textures loaded from res:// paths.
func apply_team_skin(sprite_path: String, weapon_path: String, team_color: Color = Color.WHITE) -> void:
	sprite.modulate = team_color
	if sprite_path != "res://":
		var tex = load(sprite_path)
		if tex:
			sprite.texture = tex
	if weapon_path != "res://":
		var tex = load(weapon_path)
		if tex:
			$WeaponHolder/Sprite2D.texture = tex

@rpc("any_peer", "call_local", "reliable")
func rpc_sync_score(new_score: int) -> void:
	score = new_score
	if score_ui:
		score_ui.text = "Score: " + str(score)
