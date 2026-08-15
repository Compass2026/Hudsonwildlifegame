class_name AnimalSpawner
extends Node3D
## Creates animals from species ids. Knows nothing about which species belong
## in which map — the scene's composition root tells it what to place, so the
## same spawner serves every future map and every future population system.

var _next_uid := 1
var _animals: Array[AnimalController] = []

## Places one animal and returns it. `home` is the centre of its range.
func spawn(species_id: StringName, home: Vector3, seed_ := 0) -> AnimalController:
	var species := SpeciesDB.get_species(species_id)
	if species == null:
		push_error("[AnimalSpawner] unknown species '%s'" % species_id)
		return null
	var animal := AnimalController.new()
	animal.name = "Animal_%s_%d" % [species_id, _next_uid]
	add_child(animal)
	animal.setup(species, _next_uid, home, seed_ if seed_ != 0 else _next_uid * 7717)
	_next_uid += 1
	_animals.append(animal)
	return animal

func spawn_group(species_id: StringName, count: int, homes: Array) -> void:
	for i in mini(count, homes.size()):
		spawn(species_id, homes[i])

func animals() -> Array[AnimalController]:
	return _animals

## Warm the world up so the player does not arrive to pristine, empty ground.
## The animals have "already been here" — which is the premise of tracking.
##
## This runs the real brain and the real track emitter, just without physics or
## rendering. The trail the player finds was genuinely walked; it was not
## scattered around for them to find. The clock advances as it goes, so the
## resulting sign carries a real age gradient and direction of travel can be
## read off it.
const HISTORY_STEP_SECONDS := 2.0

func simulate_history(hours: float) -> void:
	var steps := int(hours * 3600.0 / HISTORY_STEP_SECONDS)
	var dt := HISTORY_STEP_SECONDS
	var hours_per_step := HISTORY_STEP_SECONDS / 3600.0

	for i in steps:
		for a in _animals:
			if a.brain == null:
				continue
			var decision := a.brain.think(dt, {
				"position": a.global_position,
				"hour": GameClock.hour,
				"threat_distance": INF,
			})
			var speed: float = decision["speed"]
			var step: Vector3 = decision["target"] - a.global_position
			step.y = 0.0
			if step.length() > 0.05 and speed > 0.0:
				var move: float = minf(step.length(), speed * dt)
				a.global_position += step.normalized() * move
				a.emitter.set_heading(atan2(step.x, step.z))
			a.global_position = EnvironmentSystem.ground_position(a.global_position) + Vector3.UP * 0.4
			# emitter.update takes a real-time delta; convert back from game seconds.
			a.emitter.update(a.global_position, speed, dt / GameClock.time_scale)
		GameClock.advance(hours_per_step, true)

	# One visible tick so lighting and UI catch up to the new time of day.
	GameClock.advance(0.0)
