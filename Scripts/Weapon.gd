extends Node2D

@export var speed: float = 800.0
## Team ID of the player who fired this bullet. Set before add_child.
var shooter_team: int = -1
var direction: Vector2 = Vector2.RIGHT

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	if global_position.length() > 15000:
		queue_free()

func _on_area_2d_body_entered(body: Node2D) -> void:
	if not multiplayer.is_server():
		return
	if not body.is_in_group("player"):
		return
	# Ignore friendly fire
	if body.team_id == shooter_team:
		return
	body.take_damage(25)
	queue_free()
