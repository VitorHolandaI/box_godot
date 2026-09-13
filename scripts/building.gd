class_name Building
extends SolidVenue


func _init() -> void:
	venue_kind = APARTMENT


## Configures wall color for apartment building instances.
## Usage:
##   building.set_wall_color(Color(0.48, 0.25, 0.18))
func set_wall_color(color: Color) -> void:
	wall_color = color
