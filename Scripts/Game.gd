extends Node2D

func _ready():
	get_tree().paused = false
	
	$Map.queue_free()
	var builder := LevelBuilder.new()
	add_child(builder)
	builder.position = Vector2(320, 240)
