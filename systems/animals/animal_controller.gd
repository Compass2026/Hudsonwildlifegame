class_name AnimalController
extends CharacterBody3D
## The physical body of one animal.
##
## This is an adapter, deliberately thin: it gathers perception into a plain
## Dictionary, hands it to AnimalBrain, and carries out whatever the brain
## decided. It also drives a TrackEmitter so the animal's movement leaves real
## sign behind.
##
## Swapping the placeholder capsule for a rigged model is a change to
## `_build_view()` and nothing else.

const GRAVITY := 18.0

## Injected by the presentation layer at startup:
##     AnimalController.view_provider = PlaceholderFactory.build_animal
## Gameplay runs correctly with no provider at all — the animal is simply
## invisible, which is exactly what the headless tests rely on.
static var view_provider: Callable = Callable()

var species: SpeciesData
var animal_uid := 0

var brain: AnimalBrain
var emitter: TrackEmitter

var _view: Node3D
var _perception_timer := 0.0
var _threat_distance := INF
var _threat_position := Vector3.ZERO
var _threat_visible := false
var _threat_speed := 0.0

func setup(species_: SpeciesData, uid: int, spawn_position: Vector3, seed_: int) -> void:
	species = species_
	animal_uid = uid
	global_position = spawn_position
	add_to_group(&"animal")

	brain = AnimalBrain.new()
	brain.setup(species.behavior, spawn_position, seed_)

	emitter = TrackEmitter.new()
	emitter.name = "TrackEmitter"
	add_child(emitter)
	emitter.setup(species, uid, seed_ + 7919)

	_build_collision()
	_build_view()

func _build_collision() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = maxf(0.15, species.body_length_m * 0.22)
	capsule.height = maxf(0.4, species.shoulder_height_m * 1.4)
	shape.shape = capsule
	shape.position.y = capsule.height * 0.5
	add_child(shape)

## Art comes from data (a real model) or from an injected factory (placeholder).
## This system never names a concrete visual class.
func _build_view() -> void:
	if species.visual_scene != null:
		_view = species.visual_scene.instantiate()
	elif view_provider.is_valid():
		_view = view_provider.call(species)
	if _view != null:
		add_child(_view)

func _physics_process(delta: float) -> void:
	if brain == null:
		return

	_perception_timer -= delta
	if _perception_timer <= 0.0:
		_perception_timer = 0.2
		_sense_threats()

	var decision := brain.think(delta, {
		"position": global_position,
		"hour": GameClock.hour,
		"threat_distance": _threat_distance,
		"threat_position": _threat_position,
		"threat_visible": _threat_visible,
		"threat_speed": _threat_speed,
	})

	var target: Vector3 = decision["target"]
	var speed: float = decision["speed"]

	var to_target := target - global_position
	to_target.y = 0.0
	if to_target.length() > 0.5 and speed > 0.0:
		var dir := to_target.normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		var yaw := atan2(dir.x, dir.z)
		rotation.y = lerp_angle(rotation.y, yaw, minf(1.0, delta * species.behavior.turn_rate))
		emitter.set_heading(yaw)
	else:
		velocity.x = move_toward(velocity.x, 0.0, delta * 12.0)
		velocity.z = move_toward(velocity.z, 0.0, delta * 12.0)

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	move_and_slide()

	var horizontal := Vector2(velocity.x, velocity.z).length()
	emitter.update(global_position, horizontal, delta)

## Perception is a query about the world, not a reference to the player object.
func _sense_threats() -> void:
	var players := get_tree().get_nodes_in_group(&"player")
	if players.is_empty():
		_threat_distance = INF
		return
	var p: Node3D = players[0]
	_threat_position = p.global_position
	_threat_distance = global_position.distance_to(_threat_position)
	var reported_speed = p.get("current_speed")
	_threat_speed = float(reported_speed) if typeof(reported_speed) in [TYPE_FLOAT, TYPE_INT] else 0.0

	if _threat_distance > species.behavior.detect_distance:
		_threat_visible = false
		return
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * species.shoulder_height_m
	var to := _threat_position + Vector3.UP * 1.5
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	_threat_visible = hit.is_empty() or hit.get("collider") == p

## Used by the camera to test whether the animal is actually in the open.
func sight_point() -> Vector3:
	return global_position + Vector3.UP * species.shoulder_height_m * 0.9

func state_name() -> String:
	return brain.state_name() if brain != null else "?"
