extends Node3D
## Composition root.
##
## This is the only script that knows which world, which animals and which
## investigation make up this build. Every system it wires together is
## independent of the others and of this file. A second map is a second scene
## like this one — not a change to any system.

const START_HOUR := 7.4
const HISTORY_HOURS := 1.5   ## how long the animals lived here before you arrived

var world: PrototypeValley
var spawner: AnimalSpawner
var player: PlayerController
var ui: UIRoot

func _ready() -> void:
	InputActions.ensure()
	GameClock.hour = START_HOUR
	GameClock.paused = true

	# Presentation injects itself into gameplay here, and only here.
	AnimalController.view_provider = PlaceholderFactory.build_animal

	world = PrototypeValley.new()
	world.name = "World"
	add_child(world)

	spawner = AnimalSpawner.new()
	spawner.name = "Animals"
	add_child(spawner)
	_populate()

	# Let the animals move around before the player arrives, so there is a real
	# trail to find rather than a trail that begins the moment you look.
	spawner.simulate_history(HISTORY_HOURS)

	# Markers are added after the fast-forward so we build nodes once, for the
	# sign that actually survived, instead of churning through the whole history.
	var markers := EvidenceMarkerSpawner.new()
	markers.name = "EvidenceMarkers"
	add_child(markers)

	player = PlayerController.new()
	player.name = "Player"
	add_child(player)
	var spawn := Vector3(0.0, 0.0, 8.0)
	spawn.y = world.height_at(spawn.x, spawn.z) + 1.2
	player.global_position = spawn

	ui = UIRoot.new()
	ui.name = "UI"
	add_child(ui)
	ui.setup(player)

	GameClock.paused = false
	InvestigationSystem.start_by_id(&"ridgeline_report")
	EventBus.notice.emit(
		"Camp. The drainage runs through the valley — follow the creek and read the mud.", "info")

## Which animals are in this valley. Data in, animals out.
func _populate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8152026

	# One lynx, well upstream, with a large range — you will have to work.
	spawner.spawn(&"canada_lynx", world.suggested_animal_home(rng, 70.0))

	# Two bobcats. These are the false leads, and they are not a trick: this is
	# genuinely what makes a lynx report hard to verify in the real world.
	for i in 2:
		spawner.spawn(&"bobcat", world.suggested_animal_home(rng, 30.0))
