extends Node2D

@export var speed: float = 800.0
var shooter: String = ""
var direction: Vector2 = Vector2.RIGHT

func _ready():
	if shooter == "player_one":
		$Sprite.modulate = Color(0.3, 0.7, 1.0)
	else:
		$Sprite.modulate = Color(1.0, 0.3, 0.3)

func set_mouse_direction(dir: Vector2) -> void:
	direction = dir
	rotation = dir.angle()

@rpc("any_peer", "call_remote", "reliable")
func rpc_set_shooter(s: String) -> void:
	shooter = s
	if shooter == "player_one":
		$Sprite.modulate = Color(0.3, 0.7, 1.0)
	else:
		$Sprite.modulate = Color(1.0, 0.3, 0.3)

func _physics_process(delta: float) -> void:
	# Always move in the aimed direction
	global_position += direction * speed * delta

	# Destroy after travelling too far
	if global_position.length() > 15000:
		queue_free()

func _get_shooter_id() -> String:
	# Returns the node name of the shooter based on shooter string
	# This is a simplification — ideally pass peer_id directly
	return ""


func _on_area_2d_body_entered(body: Node2D) -> void:
	if not multiplayer.is_server():
		return
	if body.is_in_group("player"):
		# Don't hit the shooter's own player
		# shooter is "player_one" or "player_two", body.is_player_one is a bool
		var body_is_one: bool = body.is_player_one
		var shooter_is_one: bool = (shooter == "player_one")
		if body_is_one == shooter_is_one:
			return  # same team/player, ignore
		body.take_damage(25)
		queue_free()
