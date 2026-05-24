extends StaticBody2D

## Team this flag belongs to. 1 = Blue, 2 = Red.
@export var flag_team_id: int = 1

func _ready() -> void:
	add_to_group("flag")
	var sprite := $Sprite2D
	if sprite:
		sprite.modulate = Color(0.3, 0.7, 1.0) if flag_team_id == 1 else Color(1.0, 0.3, 0.3)
