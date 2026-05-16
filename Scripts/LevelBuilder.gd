extends TileMapLayer

var source: TileSetAtlasSource

func _ready():
	tile_set = TileSet.new()
	tile_set.tile_size = Vector2i(32, 32)  # FIX: set size BEFORE adding source

	var texture = load("res://Assets/tilesets/GlitchHouse.png")
	if texture == null:
		printerr("Failed to load tileset!")
		return

	source = TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(32, 32)
	tile_set.add_source(source)

	# FIX: Register every atlas tile you intend to use
	source.create_tile(Vector2i(0, 0))  # floor
	source.create_tile(Vector2i(1, 0))  # wall
	# Add a physics layer to the TileSet
	tile_set.add_physics_layer()  # creates layer index 0
	

	# Give the wall tile a full 32x32 collision square
	var wall_tile = source.get_tile_data(Vector2i(1, 0), 0)
	var collision_shape = [
		Vector2(0, 0),
		Vector2(32, 0),
		Vector2(32, 32),
		Vector2(0, 32)
	]
	wall_tile.add_collision_polygon(0)  # physics layer 0
	wall_tile.set_collision_polygon_points(0, 0, PackedVector2Array(collision_shape))

	var file = FileAccess.open("res://JSON/level.json", FileAccess.READ)
	if file == null:
		printerr("Failed to open level.json")
		return

	var json_result = JSON.parse_string(file.get_as_text())
	file.close()

	if json_result == null or typeof(json_result) != TYPE_DICTIONARY:
		printerr("Failed to parse level.json")
		return

	for room in json_result.get("rooms", []):
		_build_room(room)

	for corridor in json_result.get("corridors", []):
		_build_corridor(json_result, corridor)

	print("Level built successfully!")


func _build_room(room: Dictionary) -> void:
	var pos := Vector2i(room.get("position", {}).get("x", 0), room.get("position", {}).get("y", 0))
	var width: int = room.get("size", {}).get("width", 0)
	var height: int = room.get("size", {}).get("height", 0)
	var thickness: int = room.get("wall_thickness", 32)

	var tile_x := pos.x / 32
	var tile_y := pos.y / 32
	var tile_w := width / 32
	var tile_h := height / 32
	var tile_t := thickness / 32

	# FIX: floor only fills the interior (minus walls on all sides)
	for x in range(tile_t, tile_w - tile_t):
		for y in range(tile_t, tile_h - tile_t):
			set_cell(Vector2i(tile_x + x, tile_y + y), 0, Vector2i(0, 0))

	# Top and bottom walls
	for x in range(tile_w):
		set_cell(Vector2i(tile_x + x, tile_y), 0, Vector2i(1, 0))
		set_cell(Vector2i(tile_x + x, tile_y + tile_h - tile_t), 0, Vector2i(1, 0))

	# Left and right walls
	for y in range(tile_h):
		set_cell(Vector2i(tile_x, tile_y + y), 0, Vector2i(1, 0))
		set_cell(Vector2i(tile_x + tile_w - tile_t, tile_y + y), 0, Vector2i(1, 0))


func _build_corridor(level_data: Dictionary, corridor: Dictionary) -> void:
	var start_room := _find_room(level_data, corridor.get("start_room", ""))
	var end_room   := _find_room(level_data, corridor.get("end_room", ""))
	if start_room.is_empty() or end_room.is_empty():
		return

	var s_pos := Vector2i(start_room["position"]["x"], start_room["position"]["y"])
	var e_pos := Vector2i(end_room["position"]["x"],   end_room["position"]["y"])
	var s_w: int = start_room["size"]["width"]
	var s_h: int = start_room["size"]["height"]
	var corr_w: int = corridor.get("width", 32) / 32

	# FIX: connect room centers with an L-shaped corridor
	var s_center := Vector2i(s_pos.x / 32 + s_w / 64, s_pos.y / 32 + s_h / 64)
	var e_w: int = end_room["size"]["width"]
	var e_h: int = end_room["size"]["height"]
	var e_center := Vector2i(e_pos.x / 32 + e_w / 64, e_pos.y / 32 + e_h / 64)

	# Horizontal segment
	var x_min := mini(s_center.x, e_center.x)
	var x_max := maxi(s_center.x, e_center.x)
	for x in range(x_min, x_max + 1):
		for w in range(corr_w):
			set_cell(Vector2i(x, s_center.y + w), 0, Vector2i(0, 0))

	# Vertical segment
	var y_min := mini(s_center.y, e_center.y)
	var y_max := maxi(s_center.y, e_center.y)
	for y in range(y_min, y_max + 1):
		for w in range(corr_w):
			set_cell(Vector2i(e_center.x + w, y), 0, Vector2i(0, 0))


func _find_room(level_data: Dictionary, name: String) -> Dictionary:
	for room in level_data.get("rooms", []):
		if room.get("name", "") == name:
			return room
	return {}
