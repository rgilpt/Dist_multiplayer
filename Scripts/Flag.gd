extends StaticBody2D

## Team this flag belongs to. 1 = Blue, 2 = Red.
@export var flag_team_id: int = 1

func _ready() -> void:
	add_to_group("flag")
	var sprite := $Sprite2D
	if sprite == null:
		return
	var nm := get_node_or_null("/root/Main/NetworkManager")
	if nm:
		var config: Dictionary = nm._get_team_config(flag_team_id)
		var c_arr = config.get("color", null)
		if c_arr != null:
			sprite.modulate = Color(c_arr[0], c_arr[1], c_arr[2])
			return
	# Fallback if NM or config not available
	sprite.modulate = Color(0.3, 0.7, 1.0) if flag_team_id == 1 else Color(1.0, 0.3, 0.3)

## Replace the flag texture with a custom image loaded from a res:// path.
func apply_skin(texture_path: String) -> void:
	var tex = load(texture_path)
	if tex:
		$Sprite2D.texture = tex
