class_name TrackEmitter
extends Node
## Attached to an animal. Turns movement into physical sign.
##
## Animals do not "spawn evidence for the player". They walk, and the ground
## records it or does not. Everything the tracking system later reads is a
## by-product of an animal having actually been there.

const SIGN_ROLL_HOURS := 0.25

var species: SpeciesData
var animal_uid := 0

## The true footprint dimensions of THIS individual, sampled once. Every track
## it leaves is consistent with it, which is what makes a trail followable.
var individual_truth: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _distance_since_track := 0.0
var _last_pos := Vector3.INF
var _hours_since_scat := 0.0

func setup(species_: SpeciesData, uid: int, seed_: int) -> void:
	species = species_
	animal_uid = uid
	_rng.seed = seed_
	individual_truth = species.track.sample_individual(_rng)

## Call every frame with the animal's world position and how fast it is moving.
func update(pos: Vector3, speed: float, delta: float) -> void:
	if species == null:
		return
	if _last_pos == Vector3.INF:
		_last_pos = pos
		return
	_distance_since_track += _last_pos.distance_to(pos)
	_last_pos = pos

	var interval: float = species.behavior.track_interval_m
	# A running animal takes longer, deeper, more scattered strides.
	if speed > species.behavior.walk_speed * 2.0:
		interval *= 2.4
	if _distance_since_track >= interval:
		_distance_since_track = 0.0
		_leave_track(pos, speed)

	# Rolled in quarter-hour slices rather than whole hours, so sign accumulates
	# smoothly instead of appearing in clumps on the hour.
	_hours_since_scat += delta * GameClock.time_scale / 3600.0
	if _hours_since_scat > SIGN_ROLL_HOURS:
		_hours_since_scat = 0.0
		if _rng.randf() < species.behavior.scat_chance_per_hour * SIGN_ROLL_HOURS:
			_leave_scat(pos)
		if _rng.randf() < species.behavior.hair_chance_per_hour * SIGN_ROLL_HOURS:
			_leave_hair(pos)

func _leave_track(pos: Vector3, speed: float) -> void:
	var ground := EnvironmentSystem.ground_position(pos)
	var sub := EnvironmentSystem.substrate_at(ground)

	# How well this print registered: ground first, then the animal's own foot
	# structure, then weather.
	var condition: float = sub.retention
	condition += species.track.clarity_bias
	condition *= EnvironmentSystem.ground_condition
	if speed > species.behavior.walk_speed * 2.0:
		condition *= 0.75   # running prints are scuffed and partial
	condition = clampf(condition + _rng.randf_range(-0.06, 0.06), 0.0, 1.0)

	if condition < 0.08:
		return  # the ground took nothing; there is genuinely no sign here

	var truth := individual_truth.duplicate()
	# Per-print variation: soft ground spreads a print, hard ground shrinks it.
	var spread: float = 1.0 + (sub.retention - 0.5) * 0.16
	truth["length_cm"] = float(truth["length_cm"]) * spread
	truth["width_cm"] = float(truth["width_cm"]) * spread
	if speed > species.behavior.walk_speed * 2.0:
		truth["stride_cm"] = float(truth["stride_cm"]) * 2.2
		truth["gait"] = "bounding"

	EvidenceSystem.create(EvidenceKind.Type.TRACK, species.id, ground,
		condition, truth, animal_uid, _last_heading)

func _leave_scat(pos: Vector3) -> void:
	var ground := EnvironmentSystem.ground_position(pos)
	EvidenceSystem.create(EvidenceKind.Type.SCAT, species.id, ground,
		_rng.randf_range(0.6, 0.95),
		{"diameter_cm": float(individual_truth.get("width_cm", 4.0)) * 0.28,
		 "contents": "hair and small bones"},
		animal_uid)

## Hair caught on bark or brush where the animal squeezed through. Physically
## small and easy to walk past, but among the strongest sign there is.
func _leave_hair(pos: Vector3) -> void:
	var ground := EnvironmentSystem.ground_position(pos)
	EvidenceSystem.create(EvidenceKind.Type.HAIR, species.id, ground,
		_rng.randf_range(0.55, 0.9),
		{"guard_hair_length_cm": _rng.randf_range(2.5, 6.0)},
		animal_uid)

var _last_heading := 0.0

func set_heading(h: float) -> void:
	_last_heading = h
