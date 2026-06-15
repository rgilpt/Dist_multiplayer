extends Area2D
@onready var shine: Sprite2D = $Shine

func _ready() -> void:
	body_entered.connect(_on_body_entered)

	# Rotate forever — TAU = one full turn in radians, as_relative adds it each loop
	var spin := create_tween().set_loops()
	spin.tween_property(shine, "rotation", TAU, 1.5).as_relative()

	# Pulse scale independently
	var pulse := create_tween().set_loops()
	pulse.tween_property(shine, "scale", Vector2(1.3, 1.3), 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(shine, "scale", Vector2(1.0, 1.0), 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _on_body_entered(body: Node2D) -> void:
	if not multiplayer.is_server():
		return
	if not body.is_in_group("player"):
		return
	body.rpc_refill_ammo.rpc()
	var nm := get_node_or_null("/root/Main/NetworkManager")
	if nm:
		nm.remove_ammo_drop(name)
