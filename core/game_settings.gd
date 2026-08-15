extends Node
## Player-facing settings that gameplay systems are allowed to read.
##
## Accessibility lives here rather than inside the tracking system so that
## "make clues easier to see" never means "rewrite tracking".

enum TrackingAssist {
	OFF,     ## You find sign by looking. No markers until discovered.
	SUBTLE,  ## Slightly larger notice radius, discovered sign stays highlighted.
	GUIDED,  ## Generous notice radius, discovered sign gets a visible outline.
}

var tracking_assist: TrackingAssist = TrackingAssist.SUBTLE
var mouse_sensitivity: float = 0.0022
var invert_y: bool = false

## Multiplier applied to how close the player must be to notice sign.
func notice_radius_multiplier() -> float:
	match tracking_assist:
		TrackingAssist.OFF: return 1.0
		TrackingAssist.SUBTLE: return 1.6
		TrackingAssist.GUIDED: return 3.0
	return 1.0

func highlight_discovered_sign() -> bool:
	return tracking_assist == TrackingAssist.GUIDED
