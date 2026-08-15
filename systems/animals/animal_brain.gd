class_name AnimalBrain
extends RefCounted
## An animal's decision-making. Pure logic — no nodes, no physics, no rendering.
##
## It receives a description of the world and returns an intention. The body
## that carries out that intention can be a capsule, a rigged model, or a unit
## test. Behaviour is driven entirely by BehaviorProfile data, so a new species
## needs no new code here.

enum State { REST, FORAGE, TRAVEL, ALERT, FLEE }

const STATE_NAME := {
	State.REST: "resting",
	State.FORAGE: "foraging",
	State.TRAVEL: "travelling",
	State.ALERT: "alert",
	State.FLEE: "fleeing",
}

var profile: BehaviorProfile
var home := Vector3.ZERO
var state: State = State.FORAGE
var target := Vector3.ZERO
var state_time := 0.0
var alert_level := 0.0        ## 0..1 accumulated suspicion of the human

var _rng := RandomNumberGenerator.new()

func setup(profile_: BehaviorProfile, home_: Vector3, seed_: int) -> void:
	profile = profile_
	home = home_
	target = home_
	_rng.seed = seed_
	_pick_new_target()

## ctx keys: position:Vector3, hour:float, threat_distance:float (INF if none),
##           threat_position:Vector3, threat_visible:bool, threat_speed:float
## Returns:  {target:Vector3, speed:float, state:State, state_changed:bool}
func think(delta: float, ctx: Dictionary) -> Dictionary:
	state_time += delta
	var pos: Vector3 = ctx.get("position", Vector3.ZERO)
	var threat_dist: float = ctx.get("threat_distance", INF)
	var threat_pos: Vector3 = ctx.get("threat_position", Vector3.ZERO)
	var threat_visible: bool = ctx.get("threat_visible", false)
	var threat_speed: float = ctx.get("threat_speed", 0.0)
	var hour: float = ctx.get("hour", 12.0)
	var previous := state

	# --- Threat assessment. Noise and closeness both raise suspicion. --------
	if threat_dist < profile.detect_distance:
		var closeness := 1.0 - clampf(threat_dist / profile.detect_distance, 0.0, 1.0)
		var visibility := 1.0 if threat_visible else 0.35
		var noise := clampf(threat_speed / 5.0, 0.15, 1.0)
		alert_level = clampf(alert_level + closeness * visibility * noise * profile.wariness * delta * 1.6, 0.0, 1.0)
	else:
		alert_level = maxf(0.0, alert_level - delta * 0.12)

	# --- State transitions --------------------------------------------------
	if state == State.FLEE:
		if state_time > profile.flee_duration and threat_dist > profile.flush_distance * 2.0:
			_enter(State.ALERT)
	elif threat_dist < profile.flush_distance or alert_level > 0.85:
		_enter(State.FLEE)
		target = _flee_target(pos, threat_pos)
	elif alert_level > 0.4:
		if state != State.ALERT:
			_enter(State.ALERT)
	elif state == State.ALERT and alert_level < 0.2:
		_enter(State.FORAGE)
	elif state != State.ALERT:
		var active := profile.is_active_at(hour)
		if not active and state != State.REST and state_time > 6.0:
			if _rng.randf() < profile.rest_fraction:
				_enter(State.REST)
		elif active and state == State.REST and state_time > 8.0:
			_enter(State.FORAGE)
		elif state_time > _rng.randf_range(12.0, 30.0):
			_enter(State.TRAVEL if _rng.randf() < 0.35 else State.FORAGE)
			_pick_new_target()

	if state != State.FLEE and pos.distance_to(target) < 1.5:
		_pick_new_target()

	return {
		"target": target,
		"speed": _speed_for_state(),
		"state": state,
		"state_changed": previous != state,
		"alert": alert_level,
	}

func state_name() -> String:
	return STATE_NAME.get(state, "?")

func _enter(s: State) -> void:
	if state == s:
		return
	state = s
	state_time = 0.0

func _speed_for_state() -> float:
	match state:
		State.REST: return 0.0
		State.ALERT: return profile.walk_speed * 0.35
		State.FLEE: return profile.run_speed
		State.TRAVEL: return profile.walk_speed * 1.3
		_: return profile.walk_speed

func _pick_new_target() -> void:
	if profile == null:
		return
	var angle := _rng.randf() * TAU
	var radius := sqrt(_rng.randf()) * profile.home_range_radius
	target = home + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)

## Run away from the threat, but stay inside the home range — a wild animal
## does not abandon its territory, it puts cover between itself and you.
func _flee_target(pos: Vector3, threat_pos: Vector3) -> Vector3:
	var away := (pos - threat_pos)
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3(1, 0, 0)
	away = away.normalized()
	var candidate := pos + away.rotated(Vector3.UP, _rng.randf_range(-0.6, 0.6)) * 45.0
	var from_home := candidate - home
	from_home.y = 0.0
	if from_home.length() > profile.home_range_radius:
		candidate = home + from_home.normalized() * profile.home_range_radius
	return candidate
