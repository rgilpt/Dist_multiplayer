extends Node
class_name TeamManager

var my_id: int = -1
var current_counts = {0: 0, 1: 0}
signal team_selected(team_id, peer_id)
func set_peer_id(id):
	my_id = id
func update_team_data(counts):
	current_counts = counts
	update_ui()
func update_ui():
	var blue_btn: Button = $Content/HBox/TeamBlue
	var red_btn: Button = $Content/HBox/TeamRed
	
	# Disable buttons if team is full
	blue_btn.disabled = current_counts[0] >= 2
	red_btn.disabled = current_counts[1] >= 2
func _on_team_blue_pressed():
	emit_signal("team_selected", 0, my_id)
	$Content/Status.text = "Joined: Blue"
	$Content/Status.set("custom_colors/font_color", Color(0.3, 0.7, 1.0))
func _on_team_red_pressed():
	emit_signal("team_selected", 1, my_id)
	$Content/Status.text = "Joined: Red"
	$Content/Status.set("custom_colors/font_color", Color(1.0, 0.3, 0.3))
