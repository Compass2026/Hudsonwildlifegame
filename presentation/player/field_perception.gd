class_name FieldPerception
extends Node
## Decides what the player notices.
##
## Sign is not revealed by walking over a trigger. It is noticed when you are
## close enough, moving slowly enough, and the print is good enough to catch
## your eye. Rushing past a trail is a real way to fail.
##
## Accessibility scales the radius through Settings; the rule itself never changes.

const BASE_RADIUS := 2.2
const SCAN_INTERVAL := 0.25
const MAX_SPEED_TO_NOTICE := 2.6   ## m/s — above this you are moving too fast

var owner_body: Node3D
var _timer := 0.0
var _sighted: Dictionary = {}      ## animal uid -> true

func _process(delta: float) -> void:
	if owner_body == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = SCAN_INTERVAL
	_scan_sign()
	_scan_animals()

func _scan_sign() -> void:
	var speed: float = owner_body.get("current_speed")
	if typeof(speed) != TYPE_FLOAT:
		speed = 0.0
	if speed > MAX_SPEED_TO_NOTICE:
		return

	var radius := BASE_RADIUS * Settings.notice_radius_multiplier()
	# Moving slowly and crouching buys you a wider sweep.
	radius *= lerpf(1.35, 0.8, clampf(speed / MAX_SPEED_TO_NOTICE, 0.0, 1.0))

	for r in EvidenceSystem.records_near(owner_body.global_position, radius, true):
		# A faint print in leaf litter has to be almost underfoot.
		var needed := lerpf(radius * 0.35, radius, r.effective_quality())
		if owner_body.global_position.distance_to(r.position) <= needed:
			EvidenceSystem.discover(r)
			EventBus.notice.emit(_first_impression(r), "clue")

func _first_impression(r: EvidenceRecord) -> String:
	# Never name the species. The player looks, then decides.
	match r.kind:
		EvidenceKind.Type.TRACK:
			var q := r.effective_quality()
			if q > 0.7:
				return "A clear print in the %s." % r.substrate_label
			if q > 0.35:
				return "Something disturbed the %s here." % r.substrate_label
			return "A faint depression. Might be nothing."
		EvidenceKind.Type.SCAT:
			return "Droppings on the trail."
		EvidenceKind.Type.HAIR:
			return "Hair caught on the bark here. Something squeezed past."
	return "Sign of some kind here."

## Direct visual contact, logged once per animal.
##
## A sighting has to be a real observation, not something that drifted through
## the edge of the frame at distance: the animal must be near the centre of
## where you are looking, close enough to see properly, and in daylight enough
## to be worth anything. Optics will extend this range when binoculars land.
const SIGHT_RANGE := 45.0
const SIGHT_CONE_DOT := 0.93   ## roughly a 21-degree cone around your gaze

func _scan_animals() -> void:
	var cam := owner_body.get_viewport().get_camera_3d()
	if cam == null:
		return
	for node in get_tree().get_nodes_in_group(&"animal"):
		var a := node as AnimalController
		if a == null or _sighted.has(a.animal_uid):
			continue
		var point := a.sight_point()
		var range_limit := SIGHT_RANGE * lerpf(0.4, 1.0, GameClock.light_level())
		if owner_body.global_position.distance_to(point) > range_limit:
			continue
		if not cam.is_position_in_frustum(point):
			continue
		var to_animal := (point - cam.global_position).normalized()
		if (-cam.global_transform.basis.z).dot(to_animal) < SIGHT_CONE_DOT:
			continue
		if _occluded(cam.global_position, point, a):
			continue
		_sighted[a.animal_uid] = true

		# Your own trained observation is evidence — good evidence, but not
		# proof, and worth less the further away and darker it was.
		var distance := owner_body.global_position.distance_to(point)
		var condition := clampf(1.0 - distance / SIGHT_RANGE, 0.15, 1.0) * lerpf(0.35, 1.0, GameClock.light_level())
		var record := EvidenceSystem.create(EvidenceKind.Type.DIRECT_SIGHTING,
			a.species.id, point, condition,
			{"distance_m": snappedf(distance, 0.5)}, a.animal_uid)
		record.discovered = true
		record.examined = true
		record.collected = true
		record.notes = "Observed at %.0f m in %d%% light." % [distance, GameClock.light_level() * 100.0]

		EventBus.evidence_recorded.emit(record)
		EventBus.animal_sighted.emit(a.species.id, a.animal_uid)
		EventBus.notice.emit("Movement — an animal, in the open. Sighting logged.", "clue")

func _occluded(from: Vector3, to: Vector3, ignore: Node3D) -> bool:
	var space := owner_body.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [owner_body.get_rid(), ignore.get_rid()]
	return not space.intersect_ray(q).is_empty()
