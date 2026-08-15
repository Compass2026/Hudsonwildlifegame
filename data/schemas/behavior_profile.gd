class_name BehaviorProfile
extends Resource
## Data that drives AnimalBrain. No species-specific code should ever exist:
## a new species' behaviour is a new BehaviorProfile.

@export_group("Movement")
@export var walk_speed := 1.4
@export var run_speed := 7.0
@export var turn_rate := 2.5           ## radians / second
@export var home_range_radius := 70.0

@export_group("Wariness")
@export var detect_distance := 40.0    ## can notice a human this far away
@export var flush_distance := 22.0     ## bolts if a human gets this close
@export var wariness := 0.8            ## 0 = tame, 1 = extremely shy
@export var flee_duration := 8.0

@export_group("Activity")
## Hours of the day this animal is most active. Crepuscular species get two
## windows; a nocturnal species can wrap past midnight (e.g. 20 -> 5).
@export var active_windows: Array[Vector2] = [Vector2(4.0, 9.0), Vector2(17.0, 22.0)]
@export var rest_fraction := 0.55      ## share of inactive time spent bedded down

@export_group("Sign production")
@export var track_interval_m := 0.9    ## distance between recorded footfalls
@export var scat_chance_per_hour := 0.4
@export var hair_chance_per_hour := 0.25

func is_active_at(hour: float) -> bool:
	for w in active_windows:
		if w.x <= w.y:
			if hour >= w.x and hour <= w.y:
				return true
		else: # wraps midnight
			if hour >= w.x or hour <= w.y:
				return true
	return false
