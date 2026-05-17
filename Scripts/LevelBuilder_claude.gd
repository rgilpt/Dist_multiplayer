extends Node
class_name LevelBuilderClaude
var source: TileSetAtlasSource
@export var tile_map: TileMapLayer
var tile_set
func _ready():
	tile_set = TileSet.new()
	tile_set.tile_size = Vector2i(32, 32)  # FIX: set size BEFORE adding source
	tile_map.tile_set = tile_set
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
		Vector2(-16, -16),
		Vector2(16, -16),
		Vector2(16, 16),
		Vector2(-16, 16)
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
			tile_map.set_cell(Vector2i(tile_x + x, tile_y + y), 0, Vector2i(0, 0))

	# Top and bottom walls
	for x in range(tile_w):
		tile_map.set_cell(Vector2i(tile_x + x, tile_y), 0, Vector2i(1, 0))
		tile_map.set_cell(Vector2i(tile_x + x, tile_y + tile_h - tile_t), 0, Vector2i(1, 0))

	# Left and right walls
	for y in range(tile_h):
		tile_map.set_cell(Vector2i(tile_x, tile_y + y), 0, Vector2i(1, 0))
		tile_map.set_cell(Vector2i(tile_x + tile_w - tile_t, tile_y + y), 0, Vector2i(1, 0))


func _is_inside_floor(tile_pos: Vector2i, level_data: Dictionary) -> bool:
	# Check rooms
	for room in level_data.get("rooms", []):
		var rx = room["position"]["x"] / 32
		var ry = room["position"]["y"] / 32
		var rw = room["size"]["width"] / 32
		var rh = room["size"]["height"] / 32
		if tile_pos.x >= rx and tile_pos.x < rx + rw \
		and tile_pos.y >= ry and tile_pos.y < ry + rh:
			return true

	# Check corridors
	for corridor in level_data.get("corridors", []):
		var sr := _find_room(level_data, corridor.get("start_room", ""))
		var er := _find_room(level_data, corridor.get("end_room", ""))
		if sr.is_empty() or er.is_empty():
			continue
		var sw: int = sr["size"]["width"]
		var sh: int = sr["size"]["height"]
		var ew: int = er["size"]["width"]
		var eh: int = er["size"]["height"]
		var corr_w: int = corridor.get("width", 64) / 32
		var sc := Vector2i(sr["position"]["x"] / 32 + sw / 64, sr["position"]["y"] / 32 + sh / 64)
		var ec := Vector2i(er["position"]["x"] / 32 + ew / 64, er["position"]["y"] / 32 + eh / 64)

		# Horizontal segment floor area
		var x_min := mini(sc.x, ec.x)
		var x_max := maxi(sc.x, ec.x)
		if tile_pos.x >= x_min and tile_pos.x <= x_max \
		and tile_pos.y >= sc.y and tile_pos.y < sc.y + corr_w:
			return true

		# Vertical segment floor area
		var y_min := mini(sc.y, ec.y)
		var y_max := maxi(sc.y, ec.y)
		if tile_pos.x >= ec.x and tile_pos.x < ec.x + corr_w \
		and tile_pos.y >= y_min and tile_pos.y <= y_max:
			return true

	return false

func _build_corridor(level_data: Dictionary, corridor: Dictionary) -> void:
	var start_room := _find_room(level_data, corridor.get("start_room", ""))
	var end_room   := _find_room(level_data, corridor.get("end_room", ""))
	if start_room.is_empty() or end_room.is_empty():
		return

	var s_w: int = start_room["size"]["width"]
	var s_h: int = start_room["size"]["height"]
	var e_w: int = end_room["size"]["width"]
	var e_h: int = end_room["size"]["height"]
	var corr_w: int = corridor.get("width", 64) / 32

	var s_center := Vector2i(start_room["position"]["x"] / 32 + s_w / 64, start_room["position"]["y"] / 32 + s_h / 64)
	var e_center := Vector2i(end_room["position"]["x"] / 32 + e_w / 64, end_room["position"]["y"] / 32 + e_h / 64)

	# Horizontal segment
	var x_min := mini(s_center.x, e_center.x)
	var x_max := maxi(s_center.x, e_center.x)
	for x in range(x_min, x_max + 1):
		# Floor
		for w in range(corr_w):
			tile_map.set_cell(Vector2i(x, s_center.y + w), 0, Vector2i(0, 0))
		# Walls above and below
		var wall_top := Vector2i(x, s_center.y - 1)
		var wall_bot := Vector2i(x, s_center.y + corr_w)
		if not _is_inside_floor(wall_top, level_data):
			tile_map.set_cell(wall_top, 0, Vector2i(1, 0))
		if not _is_inside_floor(wall_bot, level_data):
			tile_map.set_cell(wall_bot, 0, Vector2i(1, 0))

	# Vertical segment
	var y_min := mini(s_center.y, e_center.y)
	var y_max := maxi(s_center.y, e_center.y)
	for y in range(y_min, y_max + 1):
		# Floor
		for w in range(corr_w):
			tile_map.set_cell(Vector2i(e_center.x + w, y), 0, Vector2i(0, 0))
		# Walls left and right
		var wall_left  := Vector2i(e_center.x - 1, y)
		var wall_right := Vector2i(e_center.x + corr_w, y)
		if not _is_inside_floor(wall_left, level_data):
			tile_map.set_cell(wall_left, 0, Vector2i(1, 0))
		if not _is_inside_floor(wall_right, level_data):
			tile_map.set_cell(wall_right, 0, Vector2i(1, 0))

func _find_room(level_data: Dictionary, name: String) -> Dictionary:
	for room in level_data.get("rooms", []):
		if room.get("name", "") == name:
			return room
	return {}
