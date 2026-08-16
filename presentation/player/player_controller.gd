class_name PlayerController
extends CharacterBody3D
## First-person researcher. Movement, looking, and using equipment.
##
## Gameplay results are produced by systems, not here: this script gathers what
## the systems need (where am I, what is in the frame, how fast am I moving) and
## calls them. Replacing this with a different control scheme, or a third-person
## rig, does not touch tracking, evidence or identification.

const WALK_SPEED := 3.4
const SLOW_SPEED := 1.3
const CROUCH_SPEED := 1.0
const ACCEL := 12.0
const GRAVITY := 18.0
const EYE_HEIGHT := 1.7
const CROUCH_EYE_HEIGHT := 1.05

const FOV_WIDE := 70.0
const FOV_TELE := 11.0

var current_speed := 0.0
var crouching := false
var camera_mode := false          ## looking through the field camera
var zoom := 1.0

## What the raised camera can currently see. Read by the viewfinder UI; empty
## when there is nothing identifiable in frame.
var camera_subject: Dictionary = {}

var _subject_timer := 0.0
var _ui_modal_open := false
var _camera: Camera3D
var _pitch := 0.0
var _field_camera := FieldCamera.new()
var _perception: FieldPerception

func _ready() -> void:
	add_to_group(&"player")
	InputActions.ensure()

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)

	_camera = Camera3D.new()
	_camera.name = "EyeCamera"
	_camera.position.y = EYE_HEIGHT
	_camera.fov = FOV_WIDE
	_camera.far = 600.0
	add_child(_camera)
	_camera.current = true

	_perception = FieldPerception.new()
	_perception.name = "FieldPerception"
	_perception.owner_body = self
	add_child(_perception)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	EventBus.ui_modal_changed.connect(func(is_open): _ui_modal_open = is_open)
	EventBus.animal_sighted.connect(_on_first_sighting)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens: float = Settings.mouse_sensitivity / maxf(zoom, 1.0)
		rotate_y(-event.relative.x * sens)
		var dy: float = event.relative.y * sens * (-1.0 if Settings.invert_y else 1.0)
		_pitch = clampf(_pitch - dy, -1.4, 1.4)
		_camera.rotation.x = _pitch

	if event.is_action_pressed("toggle_mouse"):
		Input.mouse_mode = (Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED)

	if event.is_action_pressed("toggle_camera"):
		camera_mode = not camera_mode
		if not camera_mode:
			zoom = 1.0
			_camera.fov = FOV_WIDE

	if event.is_action_pressed("crouch"):
		crouching = not crouching

	if camera_mode:
		if event.is_action_pressed("zoom_in"):
			zoom = clampf(zoom + 0.6, 1.0, 6.0)
		elif event.is_action_pressed("zoom_out"):
			zoom = clampf(zoom - 0.6, 1.0, 6.0)
		elif event.is_action_pressed("shutter"):
			take_photograph()

	if event.is_action_pressed("interact"):
		_examine_nearest()

func _physics_process(delta: float) -> void:
	# While a panel is up you are reading, not walking. Gated on the UI's own
	# announcement rather than on the cursor state, so freeing the cursor for
	# any other reason never leaves you unable to move.
	var input := Vector2.ZERO
	if not _ui_modal_open:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input.x, 0.0, input.y))
	dir.y = 0.0
	if dir.length() > 0.01:
		dir = dir.normalized()

	var target_speed := WALK_SPEED
	if crouching:
		target_speed = CROUCH_SPEED
	elif Input.is_action_pressed("move_slow"):
		target_speed = SLOW_SPEED
	if camera_mode:
		target_speed = minf(target_speed, SLOW_SPEED)

	velocity.x = move_toward(velocity.x, dir.x * target_speed, ACCEL * delta)
	velocity.z = move_toward(velocity.z, dir.z * target_speed, ACCEL * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	move_and_slide()

	current_speed = Vector2(velocity.x, velocity.z).length()

	var eye := CROUCH_EYE_HEIGHT if crouching else EYE_HEIGHT
	_camera.position.y = lerpf(_camera.position.y, eye, delta * 8.0)
	_camera.fov = lerpf(_camera.fov, lerpf(FOV_WIDE, FOV_TELE, (zoom - 1.0) / 5.0), delta * 10.0)

	InvestigationSystem.report_player_position(global_position)

	# While the camera is up, keep a cheap read on what is actually in frame so
	# the viewfinder can tell the player what the shot is worth BEFORE they take
	# it. Throttled, because it casts rays.
	if camera_mode:
		_subject_timer -= delta
		if _subject_timer <= 0.0:
			_subject_timer = 0.2
			camera_subject = _best_subject_in_frame()
	elif not camera_subject.is_empty():
		camera_subject = {}

var _camera_prompted := false

## A sighting is worth nothing undocumented, and the camera is no use if the
## player never finds out it is there.
func _on_first_sighting(_species_id: StringName, _uid: int) -> void:
	if _camera_prompted:
		return
	_camera_prompted = true
	EventBus.notice.emit("Press F to raise your camera, then left click to shoot.", "info")

# --- Equipment ------------------------------------------------------------

## Find the discovered sign nearest the crosshair and study it.
func _examine_nearest() -> void:
	var best: EvidenceRecord = null
	var best_score := -1.0
	var forward := -_camera.global_transform.basis.z
	for r in EvidenceSystem.records_near(global_position, 3.5):
		if not r.discovered or r.examined:
			continue
		var to_r := (r.position - _camera.global_position).normalized()
		var score := forward.dot(to_r)
		if score > 0.4 and score > best_score:
			best_score = score
			best = r
	if best == null:
		EventBus.notice.emit("Nothing within reach to examine.", "info")
		return
	EventBus.request_examine.emit(best)

func take_photograph() -> void:
	var subject := _best_subject_in_frame()
	var has_subject := not subject.is_empty()
	var ctx := {
		"subject_visible": has_subject,
		"light_level": GameClock.light_level(),
		"camera_motion": current_speed + (0.35 if not crouching else 0.12),
		"zoom": zoom,
		"distance": 0.0,
		"screen_fraction": 0.0,
		"occlusion": 0.0,
		"subject_motion": 0.0,
	}
	var species_id := &""
	if has_subject:
		var a: AnimalController = subject["animal"]
		species_id = a.species.id
		ctx["distance"] = subject["distance"]
		ctx["screen_fraction"] = subject["screen_fraction"]
		ctx["occlusion"] = subject["occlusion"]
		ctx["subject_motion"] = Vector2(a.velocity.x, a.velocity.z).length()

	var result := _field_camera.evaluate(ctx)
	var record := _field_camera.make_record(species_id, global_position, result, ctx)
	EvidenceSystem.add(record)
	EventBus.photo_taken.emit(record, result["critique"])
	EventBus.notice.emit("Photograph: %d%% — %s" % [
		int(result["quality"] * 100.0), result["critique"][result["critique"].size() - 1]],
		"success" if result["quality"] >= 0.45 else "warn")

## Work out what is in the frame and how well it is framed. This is the only
## place that touches screen space; FieldCamera receives plain numbers.
func _best_subject_in_frame() -> Dictionary:
	var best := {}
	var best_fraction := 0.0
	var vp_size := get_viewport().get_visible_rect().size
	for node in get_tree().get_nodes_in_group(&"animal"):
		var a := node as AnimalController
		if a == null:
			continue
		var centre := a.sight_point()
		if not _camera.is_position_in_frustum(centre):
			continue
		var distance := _camera.global_position.distance_to(centre)
		if distance > 200.0:
			continue

		var top := centre + Vector3.UP * a.species.shoulder_height_m * 0.5
		var p_centre := _camera.unproject_position(centre)
		var p_top := _camera.unproject_position(top)
		var pixel_height := absf(p_centre.y - p_top.y) * 2.0
		var fraction := clampf(pixel_height / maxf(vp_size.y, 1.0), 0.0, 1.0)

		var occlusion := _sample_occlusion(centre, a)
		if occlusion >= 1.0:
			continue
		if fraction > best_fraction:
			best_fraction = fraction
			best = {"animal": a, "distance": distance,
				"screen_fraction": fraction, "occlusion": occlusion}
	return best if not best.is_empty() else {}

## Three rays across the subject: fully blocked, half blocked, or clear.
func _sample_occlusion(centre: Vector3, a: AnimalController) -> float:
	var space := get_world_3d().direct_space_state
	var blocked := 0
	var offsets := [Vector3.ZERO, Vector3.UP * 0.3, Vector3.UP * -0.25]
	for o in offsets:
		var q := PhysicsRayQueryParameters3D.create(_camera.global_position, centre + o)
		q.exclude = [get_rid(), a.get_rid()]
		if not space.intersect_ray(q).is_empty():
			blocked += 1
	return float(blocked) / float(offsets.size())
