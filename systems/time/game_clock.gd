extends Node
## Authoritative game time. Everything that cares about time of day — animal
## activity, evidence decay, light level, weather later — reads from here.
##
## The sky/lighting is a listener. Time does not know that graphics exist.

signal ticked(day: int, hour: float)

const HOURS_PER_DAY := 24.0

var day := 1
var hour := 6.5                 ## 0..24
var time_scale := 90.0          ## game seconds per real second (1 real sec ~ 1.5 game min)
var paused := false

var _last_int_hour := -1

func _process(delta: float) -> void:
	if paused:
		return
	advance(delta * time_scale / 3600.0)

## Advance the clock by a number of game hours.
## `silent` skips signals — used when fast-forwarding world history at startup,
## where thousands of ticks would otherwise spam every listener.
func advance(hours: float, silent := false) -> void:
	hour += hours
	while hour >= HOURS_PER_DAY:
		hour -= HOURS_PER_DAY
		day += 1
	if silent:
		return
	ticked.emit(day, hour)
	EventBus.time_changed.emit(day, hour)
	var h := int(hour)
	if h != _last_int_hour:
		_last_int_hour = h
		EventBus.hour_elapsed.emit(day, h)

## Monotonic timestamp used for ageing evidence.
func absolute_hours() -> float:
	return float(day) * HOURS_PER_DAY + hour

## 0.0 = full dark, 1.0 = full daylight. Used by photo quality and by the sky.
func light_level() -> float:
	if hour < 4.5 or hour > 21.0:
		return 0.04
	if hour < 6.5:
		return remap(hour, 4.5, 6.5, 0.04, 0.9)
	if hour > 19.0:
		return remap(hour, 19.0, 21.0, 0.9, 0.04)
	return 1.0

func clock_string() -> String:
	var h := int(hour)
	var m := int((hour - float(h)) * 60.0)
	return "Day %d  %02d:%02d" % [day, h, m]
