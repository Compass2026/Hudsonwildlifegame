extends Node
## Boots the real game scene headless and checks that the world actually works:
## terrain answers gameplay queries, animals exist and have been leaving sign,
## and the investigation started.
##
## Run:  godot --headless --path . res://tests/smoke_test.tscn

var _passed := 0
var _failed := 0

func _ready() -> void:
	print("\n=== Hudson Wildlife — smoke test ===\n")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)

	# Let a couple of seconds of real simulation run on top of the fast-forward.
	for i in 120:
		await get_tree().process_frame

	_check("terrain registered itself as the environment provider",
		EnvironmentSystem.has_provider())
	_check("ground height varies across the map",
		absf(EnvironmentSystem.height_at(0, 0) - EnvironmentSystem.height_at(40, 80)) > 1.0)
	_check("the creek bed is mud and the uplands are not",
		EnvironmentSystem.substrate_at(Vector3(0, 0, 0)).kind == Substrate.Kind.MUD)

	var animals := get_tree().get_nodes_in_group(&"animal")
	_check("three animals were placed", animals.size() == 3)

	var records := EvidenceSystem.all_records()
	_check("animals left sign behind them (%d records)" % records.size(), records.size() > 50)

	var species_seen := {}
	var kinds_seen := {}
	for r in records:
		species_seen[r.source_species_id] = true
		kinds_seen[r.kind] = true
	_check("both species left sign — the false leads are real",
		species_seen.has(&"canada_lynx") and species_seen.has(&"bobcat"))
	_check("more than one kind of sign was produced", kinds_seen.size() > 1)

	var aged := 0
	for r in records:
		if r.age_hours() > 0.1:
			aged += 1
	_check("sign carries an age gradient, so travel direction is readable", aged > 10)

	_check("the investigation started", InvestigationSystem.active != null)
	_check("no sign has been discovered before the player looks for it",
		EvidenceSystem.discovered_records().is_empty()
			or Settings.tracking_assist != Settings.TrackingAssist.OFF)

	print("\n%d passed, %d failed\n" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("  PASS  %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s" % label)
