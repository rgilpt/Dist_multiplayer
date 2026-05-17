extends Node2D
class_name LevelBuilder
@export var tile_map: TileMapLayer
@export var floor_coords: Vector2i = Vector2i(0, 0)
@export var wall_coords: Vector2i = Vector2i(1, 0)
var level_data: Dictionary = {}
var map_size: Vector2i = Vector2i.ZERO
func _ready():
	generate_level()
func generate_level():
	var json_text: String = FileAccess.get_file_as_string("res://level.json")
	var parsed: Variant = JSON.parse_string(json_text)
	
	if parsed == null or not parsed is Dictionary:
		printerr("Invalid JSON data!")
		get_tree().quit()
		
	level_data = parsed
	map_size = parsed.map_size
	
	if tile_map == null or tile_map.tile_set == null:
		printerr("TileMapLayer or TileSet not assigned.")
		return
		
	# Clear existing map to avoid tile overlapping
	tile_map.clear()
	
	# Paint walkable floors
	for rect in level_data.objects.rooms:
		_paint_rect(rect, floor_coords)
		
	for rect in level_data.objects.corridors:
		_paint_rect(rect, floor_coords)
		
	# Paint walls around the entire map (border tiles)
	_paint_rect({"x": 0, "y": 0, "w": map_size.x, "h": 1}, wall_coords)
	_paint_rect({"x": 0, "y": map_size.y - 1, "w": map_size.x, "h": 1}, wall_coords)
	_paint_rect({"x": 0, "y": 0, "w": 1, "h": map_size.y}, wall_vars)
	_paint_rect({"x": map_size.x - 1, "y": 0, "w": 1, "h": map_size.y}, wall_coords)
	
	# Attach spawn/flag data to the map node for NetworkManager to read easily
	tile_map.set_meta("spawns", level_data.objects)
	print("Level generated successfully.")
	print("Blue Spawn: ", level_data.objects.spawn_blue)
	print("Red Spawn: ", level_data.objects.spawn_red)
	print("Flag Spawn: ", level_data.objects.flag_spawn)
func _paint_rect(rect, coords):
	var source_id: int = coords.x
	var atlas_coords: Vector2i = coords.y
	for dx in range(rect.w):
		for dy in range(rect.h):
			tile_map.tile_set.set_tile(Vector2i(rect.x + dx, rect.y + dy), source_id, atlas_coords, [])
