extends Area2D

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if not multiplayer.is_server():
		return
	if not body.is_in_group("player"):
		return
	body.rpc_refill_ammo.rpc()
	var nm := get_node_or_null("/root/Main/NetworkManager")
	if nm:
		nm.remove_ammo_drop(name)
