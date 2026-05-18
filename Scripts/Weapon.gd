extends Node2D

@export var speed : float = 500.0
var shooter : String = ""
var velocity : Vector2 = Vector2.ZERO
var _mouse_direction : Vector2 = Vector2.RIGHT

@rpc("authority", "call_remote", "reliable")
func set_mouse_direction(dir: Vector2) -> void:
	_mouse_direction = dir

func _ready():
	# Set bullet size based on shooter
	if shooter == "player_one":
		$Sprite.modulate = Color(0.3, 0.7, 1.0)  # Blue for P1
	else:
		$Sprite.modulate = Color(1.0, 0.3, 0.3)  # Red for P2
	rpc_set_shooter(shooter)

@rpc("authority", "call_remote", "reliable")
func rpc_set_shooter(s):
	shooter = s

func _physics_process(delta):
	# Move in the direction of the shooter's facing direction
	if shooter == "player_one":
		velocity = Vector2(speed, 0)
	else:
		velocity = Vector2(-speed, 0)
	
	global_position += velocity * delta
	
	# Remove if out of bounds
	if abs(global_position.x) > 800 or abs(global_position.y) > 450:
		queue_free()

func _on_body_entered(body):
	if not multiplayer.is_server():
		return
	
	if shooter == "player_one" and body.is_in_group("player_two"):
		rpc_damage_player(body)
		queue_free()
	elif shooter == "player_two" and body.is_in_group("player_one"):
		rpc_damage_player(body)
		queue_free()

@rpc("authority", "call_remote", "reliable")
func rpc_damage_player(target):
	if target.ammo > 0:
		target.ammo = 0
		target.score_ui.text = "Score: " + str(target.score)
